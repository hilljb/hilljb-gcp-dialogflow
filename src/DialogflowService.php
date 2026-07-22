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
