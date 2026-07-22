# Development Plan: PHP Dialogflow CX (Vertex AI) Chat Service

This plan was created via Gemini for creating the link between the frontend webpage on a shared web server and Vertex AI. I will modify with notes where needed for those wishing to follow along.

This document outlines the plan for developing and testing a frontend website that interacts with a PHP backend to communicate with a Google Cloud Dialogflow CX (Vertex AI) agent. The architecture is designed to support multiple concurrent user sessions on a shared PHP server.

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
*   **Directory Structure:** You can automatically generate the base folders and empty frontend/backend files by running `./setup.sh` in your terminal. The backend files under `src/`, `tools/`, and the config/`.htaccess` files described in Stage 3 are created during that stage.
    *   **Important:** Once the structure is created, move your Google Cloud Service Account JSON key into the `private/` folder and rename it to `gcp-key.json`. This folder is ignored by git to keep your credentials secure.
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
    └── private/                # NEVER web-accessible
        ├── .htaccess           # Deny-all fallback for Apache shared hosts
        ├── config.php          # Non-secret settings (project, location, agent)
        └── gcp-key.json        # Service Account Key (Keep secure!)
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
A basic, lightweight frontend to interact with the PHP backend.

*   **UI (`index.html` & `style.css`):**
    *   A scrollable chat window to display the conversation history.
    *   An input text field for the user's message.
    *   A "Send" button (and "Enter" key listener).
*   **Logic (`app.js`):**
    *   Maintain the chat UI state (appending user messages and bot responses to the DOM).
    *   Use the `fetch()` API to send asynchronous POST requests to `chat.php`.
    *   Handle loading states (e.g., showing a "typing..." indicator while waiting for the PHP backend).
    *   Manage the Session ID (if using the frontend-generated UUID approach) by checking `localStorage` on load and generating one if it doesn't exist.

## 5. Testing Strategy

### Phase 5.1: Local Testing
*   Use PHP's built-in web server (`php -S localhost:8000 -t public/`) to test the application locally.
*   Verify that the `chat.php` endpoint successfully communicates with GCP using the local path to the JSON key.
*   Test basic conversation flow in the browser.

### Phase 5.2: Concurrency & Session Testing
*   Open the frontend in multiple different browsers (e.g., Chrome, Firefox) or use Incognito/Private windows simultaneously.
*   Send different messages in each window.
*   **Verification:** Ensure that Dialogflow CX treats them as separate conversations (e.g., context from Browser A does not bleed into Browser B). This confirms the Session ID logic is working correctly.

### Phase 5.3: Shared Server Deployment & Testing
*   Deploy the code to the shared hosting environment (via FTP, SSH, or Git).
*   **Crucial Security Check:** Attempt to access the `gcp-key.json` file directly via the web browser (e.g., `https://yourdomain.com/private/gcp-key.json`). Ensure it returns a 403 Forbidden or 404 Not Found error. If it is accessible, move it outside the `public_html` directory or secure it with `.htaccess`.
*   Test the live URL to ensure the PHP environment has the necessary extensions (like cURL, JSON, and gRPC/Protobuf if required by the Google Cloud SDK) and can successfully reach the outside internet to contact GCP.

## 6. Future Enhancements (Post-MVP)
*   **Styling:** Upgrade the basic UI with a modern CSS framework (Tailwind, Bootstrap) or custom CSS.
*   **Rich Responses:** Handle Dialogflow CX rich responses (buttons, links, custom payloads) in the PHP parser and frontend UI.
*   **Logging:** Implement a logging mechanism in PHP to track API latency, errors, and usage for debugging on the shared server.
*   **Rate Limiting:** Add basic rate limiting to `chat.php` to prevent abuse of the GCP API quota.