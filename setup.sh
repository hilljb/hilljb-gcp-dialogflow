#!/bin/bash

# setup.sh - Idempotent scaffolder for the PHP Dialogflow CX chat service.
#
# Creates the full project structure and writes complete, working starter files
# for every stage of plan.md. It is SAFE to re-run: a file is only written when
# it is missing or empty, so it will never clobber code you have already built
# or a private/config.php that holds your real GCP values.

set -e

echo "Setting up project directory structure..."

# --- directories -----------------------------------------------------------
mkdir -p public/api
mkdir -p src
mkdir -p tools
mkdir -p private

# --- helper: write stdin to a file only if it is missing or empty ----------
write_if_absent() {
    local path="$1"
    if [ -s "$path" ]; then
        echo "  skip (already present): $path"
        return 0
    fi
    cat > "$path"
    echo "  created: $path"
}

# ===========================================================================
# Stage 3 — Backend (src/, tools/, public/api/, private/)
# ===========================================================================

write_if_absent src/Config.php <<'EOF_CONFIG_PHP'
<?php
namespace App;

final class Config
{
    /** @var array<string,mixed> */
    private array $values;

    public function __construct(?string $path = null)
    {
        $path ??= dirname(__DIR__) . '/private/config.php';
        if (!is_file($path)) {
            throw new \RuntimeException("Config file not found at {$path}");
        }
        $values = require $path;
        if (!is_array($values)) {
            throw new \RuntimeException('Config file must return an array');
        }
        foreach (['project_id', 'location', 'agent_id', 'credentials_path'] as $key) {
            if (empty($values[$key])) {
                throw new \RuntimeException("Missing required config key: {$key}");
            }
        }
        if (!is_file($values['credentials_path'])) {
            throw new \RuntimeException(
                "Service Account key not found at {$values['credentials_path']}"
            );
        }
        $this->values = $values;
    }

    public function get(string $key, mixed $default = null): mixed
    {
        return $this->values[$key] ?? $default;
    }
}
EOF_CONFIG_PHP

write_if_absent src/DialogflowService.php <<'EOF_SERVICE_PHP'
<?php
namespace App;

use Google\Cloud\Dialogflow\Cx\V3\Client\SessionsClient;
use Google\Cloud\Dialogflow\Cx\V3\DetectIntentRequest;
use Google\Cloud\Dialogflow\Cx\V3\QueryInput;
use Google\Cloud\Dialogflow\Cx\V3\TextInput;

final class DialogflowService
{
    private Config $config;
    private ?SessionsClient $client = null;

    public function __construct(Config $config)
    {
        $this->config = $config;
    }

    private function client(): SessionsClient
    {
        if ($this->client === null) {
            $options = ['credentials' => $this->config->get('credentials_path')];
            $endpoint = $this->config->get('api_endpoint');
            if ($endpoint) {
                $options['apiEndpoint'] = $endpoint;
            }
            $this->client = new SessionsClient($options);
        }
        return $this->client;
    }

    /**
     * Sends one user message to the agent and returns the agent's combined text reply.
     */
    public function detectIntent(string $sessionId, string $message): string
    {
        $client = $this->client();

        $sessionName = SessionsClient::sessionName(
            $this->config->get('project_id'),
            $this->config->get('location'),
            $this->config->get('agent_id'),
            $sessionId
        );

        $textInput = (new TextInput())->setText($message);
        $queryInput = (new QueryInput())
            ->setText($textInput)
            ->setLanguageCode($this->config->get('language_code', 'en'));

        $request = (new DetectIntentRequest())
            ->setSession($sessionName)
            ->setQueryInput($queryInput);

        $response = $client->detectIntent($request);

        $parts = [];
        foreach ($response->getQueryResult()->getResponseMessages() as $msg) {
            if ($msg->hasText()) {
                foreach ($msg->getText()->getText() as $line) {
                    $parts[] = $line;
                }
            }
        }
        return trim(implode("\n", $parts));
    }
}
EOF_SERVICE_PHP

write_if_absent tools/chat_cli.php <<'EOF_CLI_PHP'
<?php
// Usage: php tools/chat_cli.php "your message here" [session-id]
declare(strict_types=1);

use App\Config;
use App\DialogflowService;

require dirname(__DIR__) . '/vendor/autoload.php';

$message   = $argv[1] ?? 'Hello';
$sessionId = $argv[2] ?? 'cli-' . bin2hex(random_bytes(8));

try {
    $service = new DialogflowService(new Config());
    $reply   = $service->detectIntent($sessionId, $message);
    fwrite(STDOUT, "Session: {$sessionId}\nUser: {$message}\nAgent: {$reply}\n");
} catch (\Throwable $e) {
    fwrite(STDERR, 'ERROR: ' . $e->getMessage() . "\n");
    exit(1);
}
EOF_CLI_PHP

write_if_absent public/api/chat.php <<'EOF_CHAT_PHP'
<?php
declare(strict_types=1);

use App\Config;
use App\DialogflowService;

require dirname(__DIR__, 2) . '/vendor/autoload.php';

// --- helpers ---------------------------------------------------------------
function send_json(int $status, array $payload): never
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    exit;
}

// --- config + CORS ---------------------------------------------------------
try {
    $config = new Config();
} catch (\Throwable $e) {
    error_log('[chat.php] config error: ' . $e->getMessage());
    send_json(500, ['error' => 'Server configuration error.']);
}

$allowed = $config->get('allowed_origins', []);
$origin  = $_SERVER['HTTP_ORIGIN'] ?? '';
if (in_array('*', $allowed, true)) {
    header('Access-Control-Allow-Origin: *');
} elseif ($origin !== '' && in_array($origin, $allowed, true)) {
    header('Access-Control-Allow-Origin: ' . $origin);
    header('Vary: Origin');
}
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    send_json(204, []); // CORS preflight
}
if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    send_json(405, ['error' => 'Method not allowed. Use POST.']);
}

// --- parse + validate body -------------------------------------------------
$raw  = file_get_contents('php://input');
$data = json_decode($raw ?: '', true);
if (!is_array($data)) {
    send_json(400, ['error' => 'Request body must be valid JSON.']);
}

$message = trim((string)($data['message'] ?? ''));
if ($message === '') {
    send_json(400, ['error' => 'Field "message" is required.']);
}
if (mb_strlen($message) > 4000) {
    send_json(400, ['error' => 'Message is too long.']);
}

$sessionId = (string)($data['session_id'] ?? '');
if ($sessionId === '' || !preg_match('/^[A-Za-z0-9._-]{1,256}$/', $sessionId)) {
    error_log('[chat.php] missing/invalid session_id; generating fallback');
    $sessionId = bin2hex(random_bytes(16));
}

// --- call Dialogflow -------------------------------------------------------
try {
    $service = new DialogflowService($config);
    $reply   = $service->detectIntent($sessionId, $message);
    if ($reply === '') {
        $reply = "Sorry, I didn't have a response for that.";
    }
    send_json(200, ['reply' => $reply, 'session_id' => $sessionId]);
} catch (\Throwable $e) {
    error_log('[chat.php] dialogflow error: ' . $e->getMessage());
    send_json(502, ['error' => 'The assistant is temporarily unavailable.']);
}
EOF_CHAT_PHP

write_if_absent private/config.php <<'EOF_CONFIG_TEMPLATE'
<?php
// private/config.php — non-secret runtime configuration. Returns an array.
// EDIT the three values below with your own GCP project/agent details.
$projectId = 'YOUR_GCP_PROJECT_ID';
$location  = 'us-central1';              // must match the agent's region
$agentId   = 'YOUR_AGENT_UUID';          // from the Conversational Agents console URL

return [
    'project_id'       => $projectId,
    'location'         => $location,
    'agent_id'         => $agentId,
    'language_code'    => 'en',
    // Absolute path to the Service Account key, kept outside the web root.
    'credentials_path' => __DIR__ . '/gcp-key.json',
    // Regional endpoint. Use null only if $location === 'global'.
    'api_endpoint'     => $location === 'global'
        ? null
        : $location . '-dialogflow.googleapis.com',
    // Allowed browser origins for CORS, or ['*'] to allow all.
    // For local dev, http://localhost:8000 is typical.
    'allowed_origins'  => ['http://localhost:8000'],
];
EOF_CONFIG_TEMPLATE

write_if_absent private/.htaccess <<'EOF_PRIVATE_HTACCESS'
Require all denied
EOF_PRIVATE_HTACCESS

write_if_absent public/api/.htaccess <<'EOF_API_HTACCESS'
# Restrict direct file access; only chat.php should be called.
<Files "*">
    Require all denied
</Files>
<Files "chat.php">
    Require all granted
</Files>
EOF_API_HTACCESS

# ===========================================================================
# Stage 4 — Frontend (public/index.html, public/style.css, public/app.js)
# ===========================================================================

write_if_absent public/index.html <<'EOF_INDEX_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Dialogflow CX Chat</title>
  <link rel="stylesheet" href="style.css" />
</head>
<body>
  <main class="chat">
    <header class="chat__header">
      <h1 class="chat__title">Assistant</h1>
      <button id="new-chat" class="chat__new" type="button">New chat</button>
    </header>

    <!-- aria-live so screen readers announce new messages as they arrive -->
    <div id="messages" class="chat__messages" aria-live="polite"></div>

    <form id="chat-form" class="chat__form" autocomplete="off">
      <input
        id="chat-input"
        class="chat__input"
        type="text"
        name="message"
        placeholder="Type a message…"
        maxlength="4000"
        autocomplete="off"
        required
      />
      <button id="send-btn" class="chat__send" type="submit">Send</button>
    </form>
  </main>

  <script src="app.js" defer></script>
</body>
</html>
EOF_INDEX_HTML

write_if_absent public/style.css <<'EOF_STYLE_CSS'
:root {
  --bg: #f5f6f8;
  --panel: #ffffff;
  --user: #2563eb;
  --user-text: #ffffff;
  --agent: #e9ebef;
  --agent-text: #111827;
  --border: #d1d5db;
  --error: #b91c1c;
}

* { box-sizing: border-box; }

body {
  margin: 0;
  min-height: 100vh;
  display: flex;
  justify-content: center;
  align-items: stretch;
  background: var(--bg);
  font-family: system-ui, -apple-system, Segoe UI, Roboto, sans-serif;
}

.chat {
  display: flex;
  flex-direction: column;
  width: 100%;
  max-width: 640px;
  height: 100vh;
  background: var(--panel);
  border-left: 1px solid var(--border);
  border-right: 1px solid var(--border);
}

.chat__header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 16px;
  border-bottom: 1px solid var(--border);
}

.chat__title { font-size: 1.1rem; margin: 0; }

.chat__new {
  border: 1px solid var(--border);
  background: transparent;
  border-radius: 8px;
  padding: 6px 10px;
  cursor: pointer;
  font-size: 0.85rem;
}
.chat__new:hover { background: var(--bg); }

.chat__messages {
  flex: 1;
  overflow-y: auto;
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.msg {
  max-width: 78%;
  padding: 10px 14px;
  border-radius: 14px;
  line-height: 1.4;
  white-space: pre-wrap;   /* preserve newlines from the agent */
  word-wrap: break-word;
}

.msg--user {
  align-self: flex-end;
  background: var(--user);
  color: var(--user-text);
  border-bottom-right-radius: 4px;
}

.msg--agent {
  align-self: flex-start;
  background: var(--agent);
  color: var(--agent-text);
  border-bottom-left-radius: 4px;
}

.msg--error {
  align-self: center;
  background: transparent;
  color: var(--error);
  font-size: 0.85rem;
  font-style: italic;
}

.msg--typing { display: inline-flex; gap: 4px; align-items: center; }
.msg--typing span {
  width: 6px; height: 6px; border-radius: 50%;
  background: #9ca3af; animation: blink 1.2s infinite both;
}
.msg--typing span:nth-child(2) { animation-delay: 0.2s; }
.msg--typing span:nth-child(3) { animation-delay: 0.4s; }
@keyframes blink { 0%, 80%, 100% { opacity: 0.3; } 40% { opacity: 1; } }

.chat__form {
  display: flex;
  gap: 8px;
  padding: 12px 16px;
  border-top: 1px solid var(--border);
}

.chat__input {
  flex: 1;
  padding: 10px 12px;
  border: 1px solid var(--border);
  border-radius: 10px;
  font-size: 1rem;
}
.chat__input:focus { outline: 2px solid var(--user); border-color: var(--user); }

.chat__send {
  padding: 10px 18px;
  border: none;
  border-radius: 10px;
  background: var(--user);
  color: var(--user-text);
  font-size: 1rem;
  cursor: pointer;
}
.chat__send:disabled { opacity: 0.5; cursor: not-allowed; }
EOF_STYLE_CSS

write_if_absent public/app.js <<'EOF_APP_JS'
(() => {
  "use strict";

  // Endpoint is relative to this page, so it works whether the site is served
  // at http://localhost:8000/ or from a subfolder on shared hosting.
  // If the frontend is ever hosted on a DIFFERENT origin than the backend,
  // change this to the absolute URL and add that origin to `allowed_origins`
  // in private/config.php.
  const API_URL = "api/chat.php";
  const SESSION_KEY = "dialogflow_session_id";

  const messagesEl = document.getElementById("messages");
  const formEl = document.getElementById("chat-form");
  const inputEl = document.getElementById("chat-input");
  const sendBtn = document.getElementById("send-btn");
  const newChatBtn = document.getElementById("new-chat");

  // --- session management --------------------------------------------------
  function getSessionId() {
    let id = localStorage.getItem(SESSION_KEY);
    if (!id) {
      id = (crypto.randomUUID && crypto.randomUUID()) ||
           String(Date.now()) + "-" + Math.random().toString(16).slice(2);
      localStorage.setItem(SESSION_KEY, id);
    }
    return id;
  }

  function resetSession() {
    localStorage.removeItem(SESSION_KEY);
    messagesEl.innerHTML = "";
    getSessionId(); // create a fresh one immediately
    addMessage("agent", "Started a new conversation. How can I help?");
    inputEl.focus();
  }

  // --- rendering (always uses textContent -> no HTML injection) ------------
  function addMessage(role, text) {
    const el = document.createElement("div");
    el.className = "msg msg--" + role;
    el.textContent = text;
    messagesEl.appendChild(el);
    messagesEl.scrollTop = messagesEl.scrollHeight;
    return el;
  }

  function showTyping() {
    const el = document.createElement("div");
    el.className = "msg msg--agent msg--typing";
    el.innerHTML = "<span></span><span></span><span></span>";
    messagesEl.appendChild(el);
    messagesEl.scrollTop = messagesEl.scrollHeight;
    return el;
  }

  function setBusy(busy) {
    inputEl.disabled = busy;
    sendBtn.disabled = busy;
    if (!busy) inputEl.focus();
  }

  // --- send flow -----------------------------------------------------------
  async function sendMessage(message) {
    addMessage("user", message);
    setBusy(true);
    const typingEl = showTyping();

    try {
      const res = await fetch(API_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message, session_id: getSessionId() }),
      });

      const data = await res.json().catch(() => ({}));
      typingEl.remove();

      if (!res.ok || data.error) {
        addMessage("error", data.error || ("Request failed (" + res.status + ")."));
        return;
      }
      addMessage("agent", data.reply || "(no response)");
    } catch (err) {
      typingEl.remove();
      addMessage("error", "Network error — is the local server running?");
    } finally {
      setBusy(false);
    }
  }

  // --- wiring --------------------------------------------------------------
  formEl.addEventListener("submit", (e) => {
    e.preventDefault();
    const message = inputEl.value.trim();
    if (!message) return;
    inputEl.value = "";
    sendMessage(message);
  });

  newChatBtn.addEventListener("click", resetSession);

  // Initialize on load.
  getSessionId();
  addMessage("agent", "Hi! Ask me anything.");
  inputEl.focus();
})();
EOF_APP_JS

# --- final guidance --------------------------------------------------------
echo ""
echo "Directory structure and starter files are ready."
echo ""
echo "Next steps:"
echo "  1. Run 'composer install' (or 'composer update') to fetch the Google Cloud SDK into vendor/."
if [ ! -f "private/gcp-key.json" ]; then
    echo "  2. Place your Google Cloud Service Account JSON key at 'private/gcp-key.json'."
else
    echo "  2. Service Account key found at 'private/gcp-key.json'. (OK)"
fi
echo "  3. Edit 'private/config.php' with your GCP project ID, location, and agent UUID."
echo "  4. Start the server:  php -S localhost:8000 -t public/"
echo "  5. Open http://localhost:8000/ in your browser to chat."
echo ""
echo "Setup complete."
