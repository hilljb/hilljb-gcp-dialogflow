#!/usr/bin/env bash
# test/run_tests.sh — Dialogflow CX Chat: automated local test suite
#
# Usage (from project root):  bash test/run_tests.sh
# Usage (from test/ dir):     ./run_tests.sh
#
# What it does:
#   1. Checks local prerequisites (PHP, curl, vendor/, config, GCP key)
#   2. Stops any existing PHP server on :8000 and starts a fresh one
#   3. Runs all test groups in order, printing PASS/FAIL for each
#   4. Stops the server and prints a summary
#
# Exit code: 0 if all tests pass, 1 if any fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PORT=8000
BASE_URL="http://localhost:$PORT"
SERVER_LOG="/tmp/dialogflow-php-test.log"
SERVER_PID=""
PASS_COUNT=0
FAIL_COUNT=0

# ── ANSI colours (disabled when output is not a terminal) ─────────────────────
if [[ -t 1 ]]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[1;33m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  GREEN=''; RED=''; YELLOW=''; BOLD=''; RESET=''
fi

# ── Reporting helpers ─────────────────────────────────────────────────────────

pass() {
  printf "  ${GREEN}✓${RESET} %-54s ${GREEN}PASS${RESET}\n" "$1"
  PASS_COUNT=$(( PASS_COUNT + 1 ))
}

fail() {
  printf "  ${RED}✗${RESET} %-54s ${RED}FAIL${RESET}\n" "$1"
  if [[ -n "${2:-}" ]]; then
    printf "      ${RED}↳ %s${RESET}\n" "$2"
  fi
  FAIL_COUNT=$(( FAIL_COUNT + 1 ))
}

skip() {
  printf "  ${YELLOW}−${RESET} %-54s ${YELLOW}SKIP${RESET}\n" "$1"
  if [[ -n "${2:-}" ]]; then
    printf "      ${YELLOW}↳ %s${RESET}\n" "$2"
  fi
}

section() {
  printf "\n${BOLD}[%s]${RESET}\n" "$1"
}

fatal() {
  echo ""
  printf "${RED}%s${RESET}\n" "$1"
  print_summary
  exit 1
}

print_summary() {
  local total=$(( PASS_COUNT + FAIL_COUNT ))
  echo ""
  printf "${BOLD}%s${RESET}\n" "════════════════════════════════════════════════════════"
  if (( FAIL_COUNT == 0 )); then
    printf "  ${GREEN}${BOLD}All %d tests passed.${RESET}\n" "$total"
  else
    printf "  ${GREEN}%d passed${RESET}   ${RED}%d failed${RESET}   (%d total)\n" \
      "$PASS_COUNT" "$FAIL_COUNT" "$total"
  fi
  printf "${BOLD}%s${RESET}\n" "════════════════════════════════════════════════════════"
  echo ""
}

# ── Server management ─────────────────────────────────────────────────────────

stop_server() {
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    printf "  ${YELLOW}→${RESET} Stopping PHP dev server (PID %s)...\n" "$SERVER_PID"
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    SERVER_PID=""
  fi
}

# Always stop the server on exit (covers Ctrl-C, errors, normal exit).
trap 'echo ""; stop_server; print_summary; exit ${FAIL_COUNT:-1}' EXIT

start_server() {
  # Kill any process already holding the port.
  local existing
  existing=$(lsof -ti ":$PORT" 2>/dev/null || true)
  if [[ -n "$existing" ]]; then
    printf "  ${YELLOW}→${RESET} Stopping existing process on :%s (PID %s)...\n" \
      "$PORT" "$existing"
    kill "$existing" 2>/dev/null || true
    sleep 0.8
  fi

  php -S "localhost:$PORT" -t "$PROJECT_ROOT/public/" \
    >"$SERVER_LOG" 2>&1 &
  SERVER_PID=$!

  # Wait up to 5 seconds for the server to respond.
  local i=0
  while (( i < 20 )); do
    if curl -s --max-time 1 -o /dev/null "$BASE_URL/" 2>/dev/null; then
      return 0
    fi
    sleep 0.25
    i=$(( i + 1 ))
  done
  return 1
}

# ── HTTP helpers ──────────────────────────────────────────────────────────────

# get_code <method> <path> [body]
get_code() {
  local method="$1" path="$2" body="${3:-}"
  if [[ -n "$body" ]]; then
    curl -s --max-time 15 -o /dev/null -w "%{http_code}" \
      -X "$method" "${BASE_URL}${path}" \
      -H "Content-Type: application/json" -d "$body"
  else
    curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
      -X "$method" "${BASE_URL}${path}"
  fi
}

# post_json <session_id> <message>  →  prints full response body
post_chat() {
  local sid="$1" msg="$2"
  curl -s --max-time 15 -X POST "${BASE_URL}/api/chat.php" \
    -H "Content-Type: application/json" \
    -d "{\"message\":\"${msg}\",\"session_id\":\"${sid}\"}"
}

# ═════════════════════════════════════════════════════════════════════════════
#  MAIN
# ═════════════════════════════════════════════════════════════════════════════

echo ""
printf "${BOLD}%s${RESET}\n" "════════════════════════════════════════════════════════"
printf "${BOLD}  Dialogflow CX Chat — Test Suite${RESET}\n"
printf "${BOLD}%s${RESET}\n" "════════════════════════════════════════════════════════"

# ── 1. Prerequisites ──────────────────────────────────────────────────────────
section "Prerequisites"

ABORT=false
GCP_READY=true

# PHP installed?
if command -v php &>/dev/null; then
  PHP_VER=$(php -r 'echo PHP_VERSION;')
  pass "PHP installed ($PHP_VER)"
  PHP_MAJOR=$(php -r 'echo PHP_MAJOR_VERSION;')
  PHP_MINOR=$(php -r 'echo PHP_MINOR_VERSION;')
  if (( PHP_MAJOR > 8 )) || (( PHP_MAJOR == 8 && PHP_MINOR >= 1 )); then
    pass "PHP version >= 8.1"
  else
    fail "PHP version >= 8.1" "found $PHP_VER — upgrade PHP and retry"
    ABORT=true
  fi
else
  fail "PHP installed" "'php' not found in PATH — install PHP 8.1+ and retry"
  ABORT=true
fi

# curl installed?
if command -v curl &>/dev/null; then
  pass "curl installed"
else
  fail "curl installed" "'curl' not found in PATH — install curl and retry"
  ABORT=true
fi

# vendor/ exists?
if [[ -d "$PROJECT_ROOT/vendor" ]]; then
  pass "vendor/ exists (composer install has been run)"
else
  fail "vendor/ exists" "run 'composer install' from the project root first"
  ABORT=true
fi

# private/config.php?
if [[ -f "$PROJECT_ROOT/private/config.php" ]]; then
  pass "private/config.php present"
else
  fail "private/config.php present" "create it from the template in plan.md § 3.1"
  GCP_READY=false
fi

# private/gcp-key.json?
if [[ -f "$PROJECT_ROOT/private/gcp-key.json" ]]; then
  pass "private/gcp-key.json present"
else
  fail "private/gcp-key.json present" \
    "place your GCP Service Account key at private/gcp-key.json"
  GCP_READY=false
fi

if $ABORT; then
  fatal "Critical prerequisites missing — fix the issues above and re-run."
fi

# ── 2. PHP Dev Server ─────────────────────────────────────────────────────────
section "PHP Dev Server"

printf "  ${YELLOW}→${RESET} Starting PHP server on localhost:%s...\n" "$PORT"
if start_server; then
  pass "Server started and responding (PID $SERVER_PID)"
else
  fail "Server started and responding" \
    "server did not respond in 5 s — see $SERVER_LOG"
  fatal "Cannot continue without the PHP dev server."
fi

CODE=$(get_code GET /)
[[ "$CODE" == "200" ]] \
  && pass "GET / → HTTP 200 (index.html served)" \
  || fail "GET / → HTTP 200 (index.html served)" "got HTTP $CODE"

CODE=$(get_code GET /style.css)
[[ "$CODE" == "200" ]] \
  && pass "GET /style.css → HTTP 200" \
  || fail "GET /style.css → HTTP 200" "got HTTP $CODE"

CODE=$(get_code GET /app.js)
[[ "$CODE" == "200" ]] \
  && pass "GET /app.js → HTTP 200" \
  || fail "GET /app.js → HTTP 200" "got HTTP $CODE"

# ── 3. API Input Validation (no GCP call needed) ──────────────────────────────
section "API Input Validation"

CODE=$(get_code GET /api/chat.php)
[[ "$CODE" == "405" ]] \
  && pass "GET /api/chat.php → 405 Method Not Allowed" \
  || fail "GET /api/chat.php → 405 Method Not Allowed" "got HTTP $CODE"

CODE=$(get_code POST /api/chat.php 'not-valid-json')
[[ "$CODE" == "400" ]] \
  && pass "Non-JSON body → 400 Bad Request" \
  || fail "Non-JSON body → 400 Bad Request" "got HTTP $CODE"

CODE=$(get_code POST /api/chat.php '{"message":"","session_id":"val-01"}')
[[ "$CODE" == "400" ]] \
  && pass "Empty message field → 400 Bad Request" \
  || fail "Empty message field → 400 Bad Request" "got HTTP $CODE"

# Build a 4001-character message (pure bash, no python required)
LONG_MSG=$(head -c 4001 /dev/zero | tr '\0' 'a')
CODE=$(get_code POST /api/chat.php "{\"message\":\"${LONG_MSG}\",\"session_id\":\"val-02\"}")
[[ "$CODE" == "400" ]] \
  && pass "Message > 4000 chars → 400 Bad Request" \
  || fail "Message > 4000 chars → 400 Bad Request" "got HTTP $CODE"

# ── 4. GCP Connectivity ───────────────────────────────────────────────────────
section "GCP Connectivity"

if ! $GCP_READY; then
  skip "POST /api/chat.php with valid body → 200 OK" "GCP config/key missing"
  skip "Response JSON contains 'reply' field" "GCP config/key missing"
  skip "Response echoes session_id correctly" "GCP config/key missing"
  skip "Reply text is non-empty" "GCP config/key missing"
else

  SID="test-gcp-$(date +%s)-$RANDOM"
  RESP=$(post_chat "$SID" "Hello, what can you help me with?")
  CODE=$(get_code POST /api/chat.php \
    "{\"message\":\"Hello\",\"session_id\":\"${SID}\"}")

  [[ "$CODE" == "200" ]] \
    && pass "POST /api/chat.php with valid body → 200 OK" \
    || fail "POST /api/chat.php with valid body → 200 OK" \
         "got HTTP $CODE — check GCP credentials and network"

  echo "$RESP" | grep -q '"reply"' \
    && pass "Response JSON contains 'reply' field" \
    || fail "Response JSON contains 'reply' field" "got: $RESP"

  echo "$RESP" | grep -q "\"session_id\":\"${SID}\"" \
    && pass "Response echoes session_id correctly" \
    || fail "Response echoes session_id correctly" "got: $RESP"

  # Reply is non-empty: the 'reply' value should be something other than ""
  echo "$RESP" | grep -qE '"reply":"[^"]' \
    && pass "Reply text is non-empty" \
    || fail "Reply text is non-empty" "reply appears empty in: $RESP"

  # Missing/invalid session_id → server generates fallback UUID, still returns 200
  CODE=$(get_code POST /api/chat.php '{"message":"Hello","session_id":"!bad sid!"}')
  [[ "$CODE" == "200" ]] \
    && pass "Invalid session_id → server fallback UUID, still 200 OK" \
    || fail "Invalid session_id → server fallback UUID, still 200 OK" \
         "got HTTP $CODE"

fi

# ── 5. Session Isolation & Concurrency ───────────────────────────────────────
section "Session Isolation & Concurrency"

if ! $GCP_READY; then
  skip "Session A concurrent request — correct session_id" "GCP config/key missing"
  skip "Session B concurrent request — correct session_id" "GCP config/key missing"
  skip "Both concurrent sessions returned replies" "GCP config/key missing"
  skip "Multi-turn: second message in session A succeeds" "GCP config/key missing"
else

  TS=$(date +%s)
  SID_A="sess-a-${TS}-$RANDOM"
  SID_B="sess-b-${TS}-$RANDOM"

  TMP_A=$(mktemp)
  TMP_B=$(mktemp)

  # Fire both sessions concurrently to verify the server handles simultaneous
  # requests with independent session state.
  post_chat "$SID_A" "Hello" >"$TMP_A" &
  PID_A=$!
  post_chat "$SID_B" "Hello" >"$TMP_B" &
  PID_B=$!
  wait "$PID_A" "$PID_B"

  RESP_A=$(cat "$TMP_A")
  RESP_B=$(cat "$TMP_B")
  rm -f "$TMP_A" "$TMP_B"

  echo "$RESP_A" | grep -q "\"session_id\":\"${SID_A}\"" \
    && pass "Session A concurrent request — correct session_id" \
    || fail "Session A concurrent request — correct session_id" "got: $RESP_A"

  echo "$RESP_B" | grep -q "\"session_id\":\"${SID_B}\"" \
    && pass "Session B concurrent request — correct session_id" \
    || fail "Session B concurrent request — correct session_id" "got: $RESP_B"

  (echo "$RESP_A" | grep -q '"reply"') \
    && (echo "$RESP_B" | grep -q '"reply"') \
    && pass "Both concurrent sessions returned replies" \
    || fail "Both concurrent sessions returned replies" \
         "A: $RESP_A | B: $RESP_B"

  # Multi-turn: send a second message to session A to confirm the session
  # persists across requests.
  RESP_A2=$(post_chat "$SID_A" "And what else can you help with?")
  echo "$RESP_A2" | grep -q "\"session_id\":\"${SID_A}\"" \
    && pass "Multi-turn: second message in session A succeeds" \
    || fail "Multi-turn: second message in session A succeeds" "got: $RESP_A2"

fi

# ── 6. Security ───────────────────────────────────────────────────────────────
section "Security"

# private/ sits outside public/ (the web root), so these paths should never
# expose real file contents.  PHP's built-in dev server falls back to serving
# index.html for unknown paths (returning HTTP 200), so we check the response
# BODY rather than just the status code — the test fails only if the actual
# sensitive file contents are present in the response.

CONFIG_RESP=$(curl -s --max-time 5 "${BASE_URL}/private/config.php")
CONFIG_CODE=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
  "${BASE_URL}/private/config.php")
if [[ "$CONFIG_CODE" != "200" ]]; then
  pass "private/config.php not web-accessible (HTTP $CONFIG_CODE)"
elif ! echo "$CONFIG_RESP" | grep -q 'credentials_path\|gcp-key\|project_id'; then
  pass "private/config.php not web-accessible (HTTP $CONFIG_CODE, body is not config)"
else
  fail "private/config.php not web-accessible" \
    "HTTP $CONFIG_CODE with config file contents in body — credentials are exposed!"
fi

KEY_RESP=$(curl -s --max-time 5 "${BASE_URL}/private/gcp-key.json")
KEY_CODE=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
  "${BASE_URL}/private/gcp-key.json")
if [[ "$KEY_CODE" != "200" ]]; then
  pass "private/gcp-key.json not web-accessible (HTTP $KEY_CODE)"
elif ! echo "$KEY_RESP" | grep -q 'private_key\|service_account\|client_email'; then
  pass "private/gcp-key.json not web-accessible (HTTP $KEY_CODE, body is not key)"
else
  fail "private/gcp-key.json not web-accessible" \
    "HTTP $KEY_CODE with key file contents in body — Service Account key is exposed!"
fi

# ── Teardown & summary ────────────────────────────────────────────────────────
#
# The EXIT trap calls stop_server and print_summary automatically, so we just
# set the correct exit code here and let the trap take care of the rest.

stop_server

# Disable the trap so it doesn't double-print the summary.
trap - EXIT

print_summary

if (( FAIL_COUNT > 0 )); then
  exit 1
fi
