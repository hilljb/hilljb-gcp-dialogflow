# Development Plan: PHP Dialogflow CX (Vertex AI) Chat Service

This plan was created via Gemini for creating the link between the frontend webpage on a shared web server and Vertex AI. I will modify with notes where needed for those wishing to follow along.

This document outlines the plan for developing and testing a frontend website that interacts with a PHP backend to communicate with a Google Cloud Dialogflow CX (Vertex AI) agent. The architecture is designed to support multiple concurrent user sessions on a shared PHP server.

## Table of Contents

- [1. Prerequisites and GCP Configuration](#1-prerequisites-and-gcp-configuration)
- [2. Project Setup & Dependencies](#2-project-setup--dependencies)
- [3. Backend Development (PHP)](#3-backend-development-php)
  - [Step 3.1: Configuration file (`private/config.php`)](#step-31-configuration-file-privateconfigphp)
  - [Step 3.2: Config loader (`src/Config.php`)](#step-32-config-loader-srcconfigphp)
  - [Step 3.3: Dialogflow service wrapper (`src/DialogflowService.php`)](#step-33-dialogflow-service-wrapper-srcdialogflowservicephp)
  - [Step 3.4: Session management](#step-34-session-management)
  - [Step 3.5: The HTTP endpoint (`public/api/chat.php`)](#step-35-the-http-endpoint-publicapichatphp)
  - [Step 3.6: Error handling & logging conventions](#step-36-error-handling--logging-conventions)
  - [Step 3.7: Command-line tester (`tools/chat_cli.php`)](#step-37-command-line-tester-toolschat_cliphp)
  - [Step 3.8: Run the backend locally](#step-38-run-the-backend-locally)
  - [Step 3.9: Shared-hosting deployment notes for the backend](#step-39-shared-hosting-deployment-notes-for-the-backend)
- [4. Frontend Development (HTML/JS)](#4-frontend-development-htmljs)
  - [Step 4.1: Session identity strategy](#step-41-session-identity-strategy-how-simultaneous-conversations-stay-separate)
  - [Step 4.2: Markup (`public/index.html`)](#step-42-markup-publicindexhtml)
  - [Step 4.3: Styling (`public/style.css`)](#step-43-styling-publicstylecss)
  - [Step 4.4: Logic (`public/app.js`)](#step-44-logic-publicappjs)
  - [Step 4.5: Run and verify in the browser (local)](#step-45-run-and-verify-in-the-browser-local)
  - [Step 4.6: Verify multiple simultaneous conversations](#step-46-verify-multiple-simultaneous-conversations)
  - [Step 4.7: Keep the endpoint portable for shared hosting](#step-47-keep-the-endpoint-portable-for-shared-hosting)
- [5. Testing Strategy](#5-testing-strategy)
  - [Phase 5.1 — Prerequisites](#phase-51--prerequisites)
  - [Phase 5.2 — PHP Dev Server](#phase-52--php-dev-server)
  - [Phase 5.3 — API Input Validation](#phase-53--api-input-validation)
  - [Phase 5.4 — GCP Connectivity](#phase-54--gcp-connectivity)
  - [Phase 5.5 — Session Isolation & Concurrency](#phase-55--session-isolation--concurrency)
  - [Phase 5.6 — Security](#phase-56--security)
  - [Phase 5.7 — Shared Server Deployment & Testing *(manual)*](#phase-57--shared-server-deployment--testing-manual)
- [6. Deploying to Shared Hosting](#6-deploying-to-shared-hosting)
  - [Step 6.1: Prepare the server environment](#step-61-prepare-the-server-environment)
  - [Step 6.2: Decide where `private/` lives on the server](#step-62-decide-where-private-lives-on-the-server)
  - [Step 6.3: Upload the application files and install dependencies](#step-63-upload-the-application-files-and-install-dependencies)
  - [Step 6.4: Update the application code on the server](#step-64-update-the-application-code-on-the-server)
  - [Step 6.5: Upload credentials and configure them on the server](#step-65-upload-credentials-and-configure-them-on-the-server)
  - [Step 6.6: Adjust the frontend API URL if needed](#step-66-adjust-the-frontend-api-url-if-needed)
  - [Step 6.7: Verify PHP requirements on the host](#step-67-verify-php-requirements-on-the-host)
  - [Step 6.8: Security verification](#step-68-security-verification)
  - [Step 6.9: Smoke test the live endpoint](#step-69-smoke-test-the-live-endpoint)
- [7. Future Enhancements (Post-MVP)](#7-future-enhancements-post-mvp)

## 1. Prerequisites and GCP Configuration
Before writing code, the Google Cloud environment must be prepared to allow the shared server to authenticate and communicate with Dialogflow CX.

*   **GCP Project & API:** Ensure a Google Cloud Project is created and the **Dialogflow API** is enabled.
    *   You don't need to use the "Create credentials" button after enabling the API. We'll add auth through a service account.
*   **Create a Conversational Agent:**
    *   Open the [Conversational Agents Console](https://conversational-agents.cloud.google.com/)
    *   Create an agent. Use the "Build your own" option. Note the details, such as location (mine: `us-central1`). Use the "Playbook" option.
    *   This is where you'll do things like use a datastore, such as a GCP bucket, to specially train the model. For now, we'll just make something via prompting. Do whatever you want.
    *   You can enable logging here, send to BigQuery, etc. to examine chat history.
*   **Service Account Authentication:**
    *   Create a Service Account in GCP.
    *   Assign it the **Dialogflow Client** role (least privilege required to detect intent).
    *   Generate a JSON key for this Service Account. Keep it somewhere safe.
    *   **Security Note for Shared Server:** This JSON file must be securely uploaded to the shared server, ideally *outside* the public web root (e.g., `/home/username/private/gcp-key.json`) so it cannot be accessed via a web browser.

## 2. Project Setup & Dependencies
Set up the PHP environment and install the required Google Cloud client libraries. This requires [Composer](https://getcomposer.org/) on your local dev machine.

*   **Composer Initialization:** Initialize a `composer.json` file in the project root. You can do this by running `composer init` in your terminal and following the interactive prompts, or by manually creating a `composer.json` file with an empty JSON object `{}` or basic metadata.
*   **Install Google Cloud PHP SDK:** Run `composer require google/cloud-dialogflow-cx`.
*   **PSR-4 Autoloading:** So the backend's own PHP classes (in `src/`) can be autoloaded alongside the vendor libraries, add an `autoload` block to `composer.json` mapping the `App\` namespace to the `src/` directory, then run `composer dump-autoload`:
    ```json
    "autoload": {
        "psr-4": {
            "App\\": "src/"
        }
    }
    ```
*   **Directory Structure:** Run `./setup.sh` in your terminal to generate the entire structure **and** write complete, working starter files for every stage — the backend (`src/`, `tools/`, `public/api/chat.php`), the frontend (`public/index.html`, `public/style.css`, `public/app.js`), the `.htaccess` hardening files, and a `private/config.php` template. The script is idempotent: it only writes a file when that file is missing or empty, so re-running it never overwrites code you have already built or a `config.php` that holds your real GCP values. The code blocks shown in Stages 3 and 4 below are the exact contents `setup.sh` writes, included so you can review and understand each file.
    *   **Important:** After running the script, (1) run `composer install`, (2) move your Google Cloud Service Account JSON key into `private/` and rename it to `gcp-key.json`, and (3) edit `private/config.php` with your GCP project ID, location, and agent UUID. The `private/` folder is ignored by git to keep your credentials secure.
    ```text
    / (Project Root)
    ├── composer.json
    ├── vendor/                 # Composer dependencies
    ├── src/                    # Backend PHP classes (App\ namespace, PSR-4)
    │   ├── Config.php          # Loads config from private/config.php
    │   └── DialogflowService.php # Wraps the Dialogflow CX client
    ├── tools/
    │   └── chat_cli.php        # Command-line tester (no browser needed)
    ├── public/                 # Web root
    │   ├── index.html          # Frontend UI
    │   ├── app.js              # Frontend logic
    │   ├── style.css           # Basic styling
    │   └── api/
    │       ├── .htaccess       # (Optional) Apache hardening for the api dir
    │       └── chat.php        # PHP Backend Endpoint
    └── private/                # NEVER web-accessible; entire folder is git-ignored
        ├── .htaccess           # Deny-all fallback for Apache shared hosts
        ├── config.php          # Project/agent settings (git-ignored — back up separately!)
        └── gcp-key.json        # Service Account Key (git-ignored — back up separately!)

> **Note:** The entire `private/` directory is excluded from version control via `.gitignore`. Both `config.php` (which contains your GCP project ID, location, and agent UUID) and `gcp-key.json` (your Service Account key) must be kept backed up in a secure location outside the repository — for example, a password manager, an encrypted vault, or a private cloud storage bucket. Never commit either file.
    ```

## 3. Backend Development (PHP)
The PHP backend acts as a secure proxy between the frontend and Google Cloud. It never exposes the Service Account key or GCP project details to the browser; the browser only ever talks to `chat.php`. This stage is broken into ordered, self-contained steps. Complete them in order — later steps assume the files from earlier steps exist. Every code block below is a complete starting implementation, not pseudocode; an agent can create these files verbatim and then run the local test in Step 3.8.

> **SDK reference (installed version `google/cloud-dialogflow-cx ^0.11.3`).** The plan uses the modern V3 client surface. The exact classes and method signatures used below are:
> *   `Google\Cloud\Dialogflow\Cx\V3\Client\SessionsClient` — constructor takes an options array; `SessionsClient::sessionName($project, $location, $agent, $session)` builds the fully-qualified session resource name; `detectIntent(DetectIntentRequest $request): DetectIntentResponse`.
> *   `Google\Cloud\Dialogflow\Cx\V3\DetectIntentRequest` — `setSession(string)`, `setQueryInput(QueryInput)`.
> *   `Google\Cloud\Dialogflow\Cx\V3\QueryInput` — `setText(TextInput)`, `setLanguageCode(string)`.
> *   `Google\Cloud\Dialogflow\Cx\V3\TextInput` — `setText(string)`.
> *   Response parsing: `DetectIntentResponse::getQueryResult()` → `QueryResult::getResponseMessages()` (a repeated field of `ResponseMessage`); for each message call `hasText()` then `getText()->getText()` (the inner `Text` message holds a repeated field of strings).

### Step 3.1: Configuration file (`private/config.php`)
Keep all environment-specific values out of code and out of the web root. Create `private/config.php` returning a plain PHP array. This file contains **no secrets** (the secret is the separate `gcp-key.json`), but it lives in `private/` so it is never web-served and never committed if it contains anything sensitive.

*   Read the values from your Stage 1 setup: the GCP **Project ID**, the agent **Location** (e.g. `us-central1`), and the **Agent ID** (the UUID in the Conversational Agents console URL, not the display name).
*   **Regional endpoint is required.** For any location other than `global`, the client MUST target `LOCATION-dialogflow.googleapis.com` (e.g. `us-central1-dialogflow.googleapis.com`). Requests to the default global endpoint for a regional agent fail with a `NOT_FOUND`/permission error. The config computes this for you.

```php
<?php
// private/config.php — non-secret runtime configuration. Returns an array.
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
    // Comma-separated list of allowed browser origins for CORS, or ['*'] to allow all.
    // For local dev, http://localhost:8000 is typical.
    'allowed_origins'  => ['http://localhost:8000'],
];
```

### Step 3.2: Config loader (`src/Config.php`)
A tiny class that locates and loads `private/config.php`, validates required keys, and confirms the key file exists. Failing fast here produces clear errors instead of confusing GCP auth failures later.

```php
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
```

### Step 3.3: Dialogflow service wrapper (`src/DialogflowService.php`)
Encapsulate all Dialogflow CX interaction in one class so both the HTTP endpoint (`chat.php`) and the CLI tester (`tools/chat_cli.php`) share identical logic. This is the only place that imports the Google SDK.

*   **Authentication:** pass the key file path via the client's `credentials` option. (The SDK accepts a path here; if you prefer, you may instead `putenv('GOOGLE_APPLICATION_CREDENTIALS=...')` before constructing the client and omit the option — both use the same Service Account. Passing it explicitly is clearer and avoids relying on process-wide env state on shared hosts.)
*   **Session name:** build with `SessionsClient::sessionName(project, location, agentId, sessionId)`. The `sessionId` is the per-user conversation ID from Step 3.4.
*   **Response extraction:** concatenate the text from all `ResponseMessage` entries that carry text; ignore non-text (rich payload) messages for the MVP.

```php
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
```

### Step 3.4: Session management
Dialogflow CX groups turns into a conversation by **Session ID**; the same ID must be reused for every message in a conversation and be unique per user. Choose the **frontend-generated UUID** approach as the primary design (it is stateless on the server, survives across load-balanced shared hosts, and works identically for the CLI tester):

*   The frontend (Stage 4) generates a UUID once, stores it in `localStorage`, and sends it in the JSON body of every request as `session_id`.
*   The backend validates it: it must be a non-empty string of a safe length (e.g. 1–256 chars, matching `[A-Za-z0-9._-]+`). If missing or invalid, generate a server-side fallback UUID for that single request (so a curl test with no ID still works) — but log that this happened.
*   Do **not** rely on PHP `session_start()` cookies for the conversation ID; keep the identifier explicit so it is visible and testable. (You may still keep it in mind as a fallback, but the UUID-in-body approach is the one implemented here.)

### Step 3.5: The HTTP endpoint (`public/api/chat.php`)
This is the only file the browser calls. Responsibilities, in order: load the autoloader, set JSON + CORS headers, enforce POST, decode and validate the JSON body, call `DialogflowService`, and return a JSON envelope. All errors return JSON (never an HTML PHP error page) with an appropriate status code so the frontend can display them.

```php
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
    // Log the full detail server-side; return a generic message to the client.
    error_log('[chat.php] dialogflow error: ' . $e->getMessage());
    send_json(502, ['error' => 'The assistant is temporarily unavailable.']);
}
```

### Step 3.6: Error handling & logging conventions
*   **Never leak internals to the client.** Return generic messages (`'The assistant is temporarily unavailable.'`) with the right status code, and write the exception detail to the server log via `error_log()` (prefix each line with `[chat.php]` for grep-ability). Status code guide: `400` bad/missing input, `405` wrong method, `500` server/config error, `502` upstream (GCP) failure.
*   **Fail fast on config.** `Config` throws immediately on a missing key or missing credentials file, surfaced as a `500` — this makes "it silently does nothing" bugs impossible.
*   **Consistent envelope.** Success = `{"reply": "...", "session_id": "..."}`; failure = `{"error": "..."}`. The frontend keys off the presence of `error`.

### Step 3.7: Command-line tester (`tools/chat_cli.php`)
Create a CLI harness so the backend can be exercised end-to-end **without** the frontend. This is the fastest way for an agent to confirm GCP connectivity and credentials before touching HTML/JS.

```php
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
```

Run it with:

```bash
php tools/chat_cli.php "Hello, what can you do?"
```

Re-run with the same session ID as the second argument to confirm multi-turn context is retained.

### Step 3.8: Run the backend locally
Once the files above exist and `composer install` has been run:

```bash
# From the project root, serve the public/ folder as the web root.
php -S localhost:8000 -t public/
```

Then, in a second terminal, hit the endpoint directly with curl to verify it independently of any browser:

```bash
curl -s -X POST http://localhost:8000/api/chat.php \
  -H 'Content-Type: application/json' \
  -d '{"message":"Hello","session_id":"test-123"}'
```

A healthy response looks like `{"reply":"...","session_id":"test-123"}`. Send a second request with the same `session_id` to confirm the conversation context carries over. (Full local/concurrency/deployment testing is covered in Stage 5.)

### Step 3.9: Shared-hosting deployment notes for the backend
The same code must run unchanged on the shared host. Bake these in now so deployment in Stage 5 is a copy, not a rewrite:

*   **Keep `private/` unreachable.** Ideally the host lets you place `private/` *above* `public_html` and point the site's document root at `public/`. If the host forces everything under `public_html`, add a deny-all `private/.htaccess` as a fallback (Apache):
    ```apache
    Require all denied
    ```
    (On older Apache: `Deny from all`.) Verify with a browser in Stage 5 that `.../private/gcp-key.json` returns 403/404.
*   **Endpoint path may differ.** If the host does not let you set the document root to `public/`, `chat.php` will be served from a deeper URL (e.g. `/hilljb-gcp-dialogflow/public/api/chat.php`). Keep the frontend's fetch URL configurable (Stage 4) so only one constant changes between local and hosted.
*   **Check PHP requirements on the host.** Confirm PHP 8.1+ and the extensions the SDK needs: `curl`, `json`, `mbstring`, and ideally `grpc`/`protobuf` (the SDK falls back to a REST transport over cURL if gRPC is absent, which is fine for a low-traffic chat proxy). If you cannot install Composer on the host, run `composer install --no-dev` locally and upload the resulting `vendor/` directory with the rest of the code.
*   **`allowed_origins`** in `private/config.php` must be updated to the production domain (e.g. `https://yourdomain.com`) when deployed.

## 4. Frontend Development (HTML/JS)
A lightweight, dependency-free (vanilla HTML/CSS/JS) frontend that talks to the Stage 3 backend. Like Stage 3, this stage is broken into ordered, self-contained steps, and every code block below is a **complete** starting file an agent can create verbatim. The three files live in the existing `public/` folder (`index.html`, `style.css`, `app.js`) so they are served from the **same origin** as `api/chat.php` — this keeps the setup simple and sidesteps CORS entirely during local development. By the end of this stage you will open `http://localhost:8000/` in a browser and hold a live, multi-turn conversation with the agent, and confirm that separate browsers hold independent conversations.

> **Backend contract this frontend must match (implemented and verified in Stage 3).** Do not deviate from these field names or the frontend will silently fail.
> *   **Endpoint:** `POST api/chat.php` (relative to the page URL when served from `public/`).
> *   **Request body (JSON):** `{"message": "<user text>", "session_id": "<per-browser id>"}`.
> *   **Success response (HTTP 200, JSON):** `{"reply": "<agent text>", "session_id": "<echoed id>"}`.
> *   **Error response (HTTP 400/405/500/502, JSON):** `{"error": "<human-readable message>"}`.
> *   The reply text may contain newlines (the backend joins multiple response messages with `\n`); render them, but always insert user/agent text as **text nodes**, never as HTML, to avoid XSS.

### Step 4.1: Session identity strategy (how simultaneous conversations stay separate)
Dialogflow CX keys a conversation off the `session_id` the backend receives (Step 3.4). The frontend owns generating and persisting that ID:

*   On first load, generate a UUID with `crypto.randomUUID()` and store it in `localStorage` under a fixed key (e.g. `dialogflow_session_id`). On every subsequent load, reuse the stored value so a page refresh continues the same conversation.
*   Because `localStorage` is **scoped per browser and per origin**, Chrome, Firefox, Safari, and each Incognito/Private window automatically get their own stored UUID — and therefore their own independent Dialogflow conversation. This is exactly what satisfies the "multiple simultaneous conversations in different browsers" requirement; no server-side work is needed.
*   Send this ID as `session_id` in every request. Provide a **"New chat"** button that clears the stored ID, generates a fresh UUID, and empties the transcript, so a single browser can start a brand-new conversation on demand.

### Step 4.2: Markup (`public/index.html`)
A minimal, accessible chat shell: a scrollable transcript region, a text input, a Send button, and a New-chat button. It loads `style.css` and `app.js` (the latter as a `defer`ed module-free script).

```html
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
```

### Step 4.3: Styling (`public/style.css`)
Just enough CSS for a clean, responsive chat window with distinct user/agent bubbles and an animated "typing" indicator. No framework required (upgrading to one is a Stage 6 enhancement).

```css
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
```

### Step 4.4: Logic (`public/app.js`)
Handles session persistence, submitting messages, rendering the transcript, the typing indicator, disabling the form while a request is in flight, and error display. Read the endpoint from a single configurable constant so only that line changes between local and hosted deployments (Step 4.6).

```javascript
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
```

> **Note on the Enter key:** because the input lives inside a `<form>` and Send is a `type="submit"` button, pressing **Enter** submits the form natively — no extra key listener is needed. (A multi-line `<textarea>` with Shift+Enter for newlines is a Stage 6 enhancement.)

### Step 4.5: Run and verify in the browser (local)
With `private/config.php` and `gcp-key.json` in place from Stage 3, and `composer install` already run:

```bash
# From the project root — serves public/ so index.html and api/chat.php share an origin.
php -S localhost:8000 -t public/
```

Then open **`http://localhost:8000/`** in a browser and verify, in order:

1.  The page loads with the greeting bubble and the input is focused.
2.  Type a message and press Enter (or click **Send**): your text appears as a right-aligned bubble, a typing indicator shows, and the agent's reply appears as a left-aligned bubble.
3.  Ask a follow-up that depends on the previous turn (e.g. "and what about tomorrow?") to confirm **multi-turn context** is preserved within the session.
4.  Refresh the page: the transcript clears (expected — history isn't persisted for the MVP) but the **same** `session_id` is reused (check `localStorage` in DevTools → Application), so the agent still remembers the conversation.
5.  Open DevTools → Network, send a message, and confirm the request body is `{"message":"…","session_id":"…"}` and the response is `{"reply":"…","session_id":"…"}`.
6.  Force an error path to confirm graceful handling: stop the PHP server and send a message — you should see an italicized "Network error" line, not a frozen UI.

### Step 4.6: Verify multiple simultaneous conversations
This is the key acceptance criterion for the stage:

1.  With the server still running, open `http://localhost:8000/` in **two different browsers** (e.g. Chrome and Firefox), or one normal window and one Incognito/Private window.
2.  In window A, tell the agent a distinct fact (e.g. "My name is Alice"). In window B, tell it something different (e.g. "My name is Bob").
3.  In each window, ask "What is my name?" — **A must answer Alice and B must answer Bob.** Because each browser/profile has its own `localStorage` `session_id`, Dialogflow CX treats them as fully separate conversations with no context bleed.
4.  Confirm in DevTools → Application → Local Storage that the two windows hold **different** `dialogflow_session_id` values.

(Cross-browser and shared-server concurrency testing is formalized in Stage 5.)

### Step 4.7: Keep the endpoint portable for shared hosting
No code change is needed for the common case, but be aware:

*   Serving the frontend and backend from the same origin means the relative `API_URL = "api/chat.php"` works both locally (`http://localhost:8000/`) and when the site is deployed under a subfolder (e.g. `https://yourdomain.com/chat/` → resolves to `https://yourdomain.com/chat/api/chat.php`).
*   Only if you host the frontend on a **different** origin than the PHP backend do you need to (a) set `API_URL` to the backend's absolute URL and (b) add that frontend origin to `allowed_origins` in `private/config.php` (Step 3.1) so the CORS headers permit it.

## 5. Testing Strategy

The test suite lives in `test/run_tests.sh`. Run it with a single command from the project root:

```bash
bash test/run_tests.sh
```

The script manages the PHP dev server itself — it stops any existing process on port 8000 and starts a fresh one at the beginning of each run, then shuts it down when the tests finish (or on Ctrl-C). Each test prints its description, then **PASS** in green or **FAIL** in red. A summary of total passed and failed counts is printed at the end. Exit code is `0` if all tests pass, `1` if any fail.

The suite is organised into six groups, run in order:

### Phase 5.1 — Prerequisites
Checks that the local environment has everything the application needs before trying to run anything else. If a critical dependency (PHP, curl, or `vendor/`) is missing the suite aborts with a clear message rather than producing confusing downstream failures.

*   PHP 8.1+ is installed
*   curl is installed
*   `vendor/` directory exists (i.e. `composer install` has been run)
*   `private/config.php` is present (non-fatal; GCP tests are skipped if missing)
*   `private/gcp-key.json` is present (non-fatal; GCP tests are skipped if missing)

### Phase 5.2 — PHP Dev Server
Starts a fresh server and confirms all three frontend assets are served correctly.

*   Server starts and responds within 5 seconds
*   `GET /` → HTTP 200 (`index.html`)
*   `GET /style.css` → HTTP 200
*   `GET /app.js` → HTTP 200

### Phase 5.3 — API Input Validation
Exercises all rejection paths in `chat.php` without touching GCP — these tests pass even if credentials are not configured.

*   `GET /api/chat.php` → 405 Method Not Allowed
*   Non-JSON body → 400 Bad Request
*   Empty `message` field → 400 Bad Request
*   Message longer than 4000 characters → 400 Bad Request

### Phase 5.4 — GCP Connectivity
Verifies end-to-end communication with Dialogflow CX. Skipped if `private/config.php` or `private/gcp-key.json` is missing.

*   `POST /api/chat.php` with a valid body → HTTP 200
*   Response JSON contains a `reply` field
*   Response echoes the sent `session_id` back correctly
*   Reply text is non-empty
*   Invalid `session_id` value triggers the server-side fallback UUID (still 200)

### Phase 5.5 — Session Isolation & Concurrency
Confirms that simultaneous requests with different session IDs are fully independent. Skipped if GCP credentials are missing.

*   Session A and Session B requests fired concurrently — each response echoes its own `session_id`
*   Both concurrent sessions return a non-error reply
*   Multi-turn: a second message on session A succeeds and still carries the correct `session_id`

### Phase 5.6 — Security
Checks that `private/` is not reachable through the web server (since it sits outside the `public/` web root).

*   `GET /private/config.php` → not HTTP 200 (expect 404)
*   `GET /private/gcp-key.json` → not HTTP 200 (expect 404)

### Phase 5.7 — Shared Server Deployment & Testing *(manual)*
*   Deploy the code to the shared hosting environment (via FTP, SSH, or Git).
*   **Crucial Security Check:** Attempt to access the `gcp-key.json` file directly via the web browser (e.g., `https://yourdomain.com/private/gcp-key.json`). Ensure it returns a 403 Forbidden or 404 Not Found error. If it is accessible, move it outside the `public_html` directory or secure it with `.htaccess`.
*   Test the live URL to ensure the PHP environment has the necessary extensions (like cURL, JSON, and gRPC/Protobuf if required by the Google Cloud SDK) and can successfully reach the outside internet to contact GCP.

## 6. Deploying to Shared Hosting

Complete Stages 1–5 locally first. By this point the application should be running and fully tested at `http://localhost:8000/`. This section walks through transferring it to a shared PHP host, including the case where you are deploying into a **specific subfolder** (e.g. `https://yourdomain.com/chat/`) rather than the domain root.

### Step 6.1: Prepare the server environment
Because SSH access is available, Composer will be run on the server after uploading the project files. This avoids transferring the large `vendor/` directory and ensures installed packages match the server's PHP version and extensions.

**Install Composer in your home directory (once, if not already present):**

Use the instructions [here](https://getcomposer.org/download/) to install Composer. Symlink the `composer.phar` file and add it to your `PATH` as needed so that `composer` can be called from any directory.

**Confirm the PHP version before continuing.** Some shared hosts default to an older PHP on the command line even if a newer one is available via the web server:

```bash
php -v
```

The output must show PHP 8.1 or higher. If it shows an older version, check whether the host provides a versioned binary (e.g. `php81`, `php8.1`) and use that in place of `php` for all subsequent commands. Contact your host if you are unsure which binary to use.

### Step 6.2: Decide where `private/` lives on the server
Your server uses the layout `/home/username/domainN/` as the web root for each domain. This means your home directory — `/home/username/` — sits **above every domain's web root** and cannot be reached by any browser on any domain. This is the ideal place for credentials: no `.htaccess` fallback needed, no risk of misconfiguration exposing a key file.

The full directory layout for a chat service on domain3 looks like this:

```text
/home/username/
├── private/                              ← never web-accessible (above all domain roots)
│   └── chat-service-2/                   ← one subfolder per chat service
│       ├── config.php
│       └── gcp-key.json
├── domain1/                              ← web root for domain1 (unrelated)
├── domain2/                              ← web root for domain2 (unrelated)
└── domain3/                              ← web root for domain3
    └── chat-service-2/                   ← project root (web-accessible subfolder)
        ├── src/
        ├── vendor/
        ├── composer.json
        ├── composer.lock
        └── public/                       ← served at https://domain3.com/chat-service-2/public/
            ├── index.html
            ├── app.js
            ├── style.css
            └── api/
                └── chat.php
```

**A code change will be required — but make it on the server, not locally.**
By default, `Config.php` looks for `private/` relative to the project root. Since credentials now live outside the project tree, the app must be told the explicit path to `config.php` when constructing `Config` in two files (`public/api/chat.php` and `tools/chat_cli.php`). This is a server-specific path, so **do not** edit these files in your local repository — that would bake a machine-specific path into your clean, committed code. Instead, upload the unmodified files first (Step 6.3) and apply this edit directly on the server afterward (Step 6.4).

> **Adding a second chat service later** follows the same pattern: create `/home/username/private/chat-service-3/`, deploy the unmodified project code to `/home/username/domain3/chat-service-3/` (or another domain subfolder), then edit the two path references in *that server copy* of `chat.php` and `chat_cli.php` to point at the new private directory.

### Step 6.3: Upload the application files and install dependencies
Upload the project **exactly as it exists in your local repository** — do not pre-edit any files for the server. All server-specific modifications happen after the files are in place (Steps 6.4–6.6).

Transfer the project to the server via SFTP (avoid plain FTP; credentials will be nearby). Upload the following to `/home/username/domain3/chat-service-2/`:

- `composer.json`
- `composer.lock`
- `src/`
- `tools/`
- `public/`

Do **not** upload `vendor/` (it will be built on the server in the next step) and do **not** upload `private/` (credentials are handled separately in Step 6.5).

**Run Composer on the server** to install dependencies:

```bash
cd /home/username/domain3/chat-service-2
composer install --no-dev --optimize-autoloader
```

Composer reads `composer.json` and `composer.lock` from the current directory and writes `vendor/` right alongside them — which is exactly where the autoloader in `public/api/chat.php` expects it.

### Step 6.4: Update the application code on the server
Now that the unmodified files are on the server, apply the server-specific path change described in Step 6.2. Make these edits **on the server** (over SSH, with `nano`/`vim`, or by editing the remote files in your editor) — never in your local repository.

In `/home/username/domain3/chat-service-2/public/api/chat.php`, change:

```php
$config = new Config();
```

to:

```php
$config = new Config('/home/username/private/chat-service-2/config.php');
```

In `/home/username/domain3/chat-service-2/tools/chat_cli.php`, change:

```php
$service = new DialogflowService(new Config());
```

to:

```php
$service = new DialogflowService(new Config('/home/username/private/chat-service-2/config.php'));
```

The referenced `config.php` does not exist yet — you will upload it in the next step.

### Step 6.5: Upload credentials and configure them on the server
First, create the private directory on the server over SSH:

```bash
mkdir -p /home/username/private/chat-service-2
chmod 700 /home/username/private/chat-service-2
```

Then upload your two local credential files **unmodified** via SFTP to `/home/username/private/chat-service-2/`:

- `gcp-key.json` — your Service Account JSON key
- `config.php` — your configuration file (still holding the local-dev values)

Once both files are on the server, edit `config.php` **in place on the server** to apply the two production changes:

**1. Set `credentials_path` to the absolute path of the key file on the server:**

```php
'credentials_path' => '/home/username/private/chat-service-2/gcp-key.json',
```

**2. Update `allowed_origins` to your production domain:**

```php
'allowed_origins' => ['https://domain3.com'],
```

For the common case where the frontend and backend are served from the same origin (which they are here), CORS headers are not actually required — but this value should still reflect the real domain so the header is correct if a browser does send an `Origin`.

Finally, tighten the permissions on both files:

```bash
chmod 600 /home/username/private/chat-service-2/config.php
chmod 600 /home/username/private/chat-service-2/gcp-key.json
```

### Step 6.6: Adjust the frontend API URL if needed
This is another file modification, so — like the edits above — only apply it **on the server** after the upload, and only if your layout requires it. Open the server copy of `public/app.js` and check the `API_URL` constant near the top:

```javascript
const API_URL = "api/chat.php";
```

This relative path resolves correctly in two common cases:
- **Layout A** with document root set to `public/`: the page is at `https://yourdomain.com/` and the API resolves to `https://yourdomain.com/api/chat.php`. No change needed.
- **Layout B** with the page served from `https://yourdomain.com/chat/public/`: the relative URL resolves to `https://yourdomain.com/chat/public/api/chat.php`. No change needed.

Only change `API_URL` to an absolute URL if the frontend is hosted on a **different origin** than the backend (and in that case also update `allowed_origins` in `private/config.php`).

### Step 6.7: Verify PHP requirements on the host
Before testing, confirm the host provides what the SDK needs. A `<?php phpinfo(); ?>` page or your hosting control panel can help:

| Requirement | Notes |
|---|---|
| PHP 8.1+ | Required |
| `curl` extension | Required (SDK HTTP transport) |
| `json` extension | Required |
| `mbstring` extension | Required |
| `grpc` + `protobuf` extensions | Optional but faster; SDK falls back to REST over cURL if absent |

### Step 6.8: Security verification
Before sharing the URL, confirm the credentials directory is not reachable via a browser. Run from your local machine:

```bash
# Both should return 403 or 404 — never 200.
curl -I https://yourdomain.com/private/gcp-key.json
curl -I https://yourdomain.com/private/config.php
```

If either returns `200 OK`, stop and fix the directory protection before proceeding. In Layout B this means verifying the deny-all `private/.htaccess` was uploaded correctly (see [Step 3.9](#step-39-shared-hosting-deployment-notes-for-the-backend)).

### Step 6.9: Smoke test the live endpoint
Hit the API directly with curl to confirm GCP connectivity before testing the UI:

```bash
curl -s -X POST https://yourdomain.com/api/chat.php \
  -H 'Content-Type: application/json' \
  -d '{"message":"Hello","session_id":"deploy-test-1"}'
```

A healthy response: `{"reply":"…","session_id":"deploy-test-1"}`.

Then open the URL in a browser, send a message, and verify the full chat UI loads and the agent responds. Open a second browser or Incognito window and confirm the two conversations are independent (the same acceptance criteria as [Step 4.6](#step-46-verify-multiple-simultaneous-conversations)).

## 7. Future Enhancements (Post-MVP)
*   **Styling:** Upgrade the basic UI with a modern CSS framework (Tailwind, Bootstrap) or custom CSS.
*   **Rich Responses:** Handle Dialogflow CX rich responses (buttons, links, custom payloads) in the PHP parser and frontend UI.
*   **Logging:** Implement a logging mechanism in PHP to track API latency, errors, and usage for debugging on the shared server.
*   **Rate Limiting:** Add basic rate limiting to `chat.php` to prevent abuse of the GCP API quota.