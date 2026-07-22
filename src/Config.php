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
