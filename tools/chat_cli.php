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
