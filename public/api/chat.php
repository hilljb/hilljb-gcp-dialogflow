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
