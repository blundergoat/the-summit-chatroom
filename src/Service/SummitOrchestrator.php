<?php

declare(strict_types=1);

namespace App\Service;

use Psr\Log\LoggerInterface;
use StrandsPhpClient\Context\AgentContext;
use StrandsPhpClient\StrandsClient;
use Symfony\Component\DependencyInjection\Attribute\Autowire;
use Symfony\Component\Uid\Uuid;

/**
 * Orchestrates a synchronous "summit round" - three AI characters responding in sequence.
 *
 * THE SUMMIT PATTERN:
 *   Three personas are chosen randomly by the frontend from a roster of 10 characters.
 *   They respond in sequence, each seeing previous responses via the shared session.
 *
 * All personas share a single StrandsClient that talks to the Python agent container
 * over HTTP. The persona name is sent as metadata in the request, and the Python agent
 * uses it to select the appropriate system prompt.
 *
 * HOW AGENTS SEE EACH OTHER'S RESPONSES:
 *   All three agents share the same session_id. The Python agent's session store accumulates
 *   each response. So when the second persona is invoked, the session already contains the
 *   first persona's response, and so on.
 *
 * See config/packages/strands.yaml for the agent definition.
 */
class SummitOrchestrator
{
    public function __construct(
        #[Autowire(service: 'strands.client.summit')]
        private readonly StrandsClient $client,
        private readonly LoggerInterface $logger,
    ) {
    }

    /**
     * Run a full summit round with the given personas, sequentially.
     *
     * Each agent sees the full conversation history via the shared session.
     * The order matters - later personas see earlier responses.
     *
     * This method BLOCKS for the duration of all agent calls.
     * For real-time streaming, use SummitStreamOrchestrator instead.
     *
     * @param string      $message   The user's question or proposal
     * @param string|null $sessionId UUID for conversation continuity (null = one-shot, no memory)
     * @param string[]    $personas  Ordered list of persona names to invoke (e.g. ["gandalf", "terminator", "ships_cat"])
     *
     * @return array<array{persona: string, text: string, has_objective: bool}> Responses in order
     */
    public function deliberate(string $message, ?string $sessionId = null, array $personas = []): array
    {
        $correlationId = Uuid::v7()->toRfc4122();
        $deliberationStartedAt = microtime(true);
        $responses = [];

        $this->logger->info('summit.deliberation.started', [
            'correlation_id' => $correlationId,
            'session_id' => $sessionId,
            'message_length' => mb_strlen($message),
            'personas' => $personas,
        ]);

        foreach ($personas as $persona) {
            $personaStartedAt = microtime(true);

            $this->logger->info('summit.agent.invoke.started', [
                'correlation_id' => $correlationId,
                'session_id' => $sessionId,
                'persona' => $persona,
            ]);

            $context = AgentContext::create()
                ->withMetadata('persona', $persona)
                ->withMetadata('correlation_id', $correlationId)
                ->withMetadata('active_personas', $personas);

            try {
                $response = $this->client->invoke(
                    message: $message,
                    context: $context,
                    sessionId: $sessionId,
                );
            } catch (\Throwable $e) {
                $this->logger->error('summit.agent.invoke.failed', [
                    'correlation_id' => $correlationId,
                    'session_id' => $sessionId,
                    'persona' => $persona,
                    'duration_ms' => (int) round((microtime(true) - $personaStartedAt) * 1000),
                    'exception_class' => $e::class,
                    'exception_message' => $e->getMessage(),
                ]);

                throw $e;
            }

            $this->logger->info('summit.agent.invoke.completed', [
                'correlation_id' => $correlationId,
                'session_id' => $sessionId,
                'persona' => $persona,
                'duration_ms' => (int) round((microtime(true) - $personaStartedAt) * 1000),
                'response_chars' => mb_strlen($response->text),
            ]);

            $responses[] = [
                'persona' => $persona,
                'text' => $response->text,
                'has_objective' => $response->hasObjective,
            ];
        }

        $this->logger->info('summit.deliberation.completed', [
            'correlation_id' => $correlationId,
            'session_id' => $sessionId,
            'duration_ms' => (int) round((microtime(true) - $deliberationStartedAt) * 1000),
            'response_count' => count($responses),
        ]);

        return $responses;
    }
}
