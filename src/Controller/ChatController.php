<?php

declare(strict_types=1);

namespace App\Controller;

use App\Service\SummitOrchestrator;
use App\Service\SummitStreamOrchestrator;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\EventDispatcher\EventDispatcherInterface;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

/**
 * The main (and only) controller for The Summit chat application.
 *
 * Handles two routes:
 *   GET  /      - Renders the chat UI (Twig template with Tailwind CSS)
 *   POST /chat  - Receives a user message and returns agent responses
 *
 * Supports two modes:
 *   1. SYNC MODE: The controller calls all agents sequentially via the orchestrator,
 *      waits for all responses, and returns them as JSON.
 *
 *   2. STREAMING MODE: The controller returns immediately with a Mercure topic name.
 *      The actual agent work happens AFTER the response is sent (via kernel.terminate event).
 *      The frontend subscribes to Mercure topics and receives tokens in real-time.
 *
 * The frontend sends a `personas` array with each request specifying which 3 characters
 * (from the roster of 10) were randomly selected for this session.
 */
class ChatController extends AbstractController
{
    public function __construct(
        private readonly SummitOrchestrator $orchestrator,
        private readonly EventDispatcherInterface $eventDispatcher,
        private readonly ?SummitStreamOrchestrator $streamOrchestrator = null,
    ) {
    }

    /**
     * GET / - Render the chat UI.
     */
    #[Route('/', name: 'chat', methods: ['GET'])]
    public function index(): Response
    {
        $mercureUrl = $this->getParameter('mercure_url');

        return $this->render('chatroom.html.twig', [
            'mercure_url' => $mercureUrl,
            'streaming_enabled' => $this->streamOrchestrator !== null && $mercureUrl !== '',
        ]);
    }

    /**
     * POST /chat - Handle a user message.
     *
     * Expected JSON body:
     *   {
     *     "message": "Should we migrate to microservices?",
     *     "session_id": "uuid-here",
     *     "streaming": true,
     *     "personas": ["gandalf", "terminator", "ships_cat"]
     *   }
     *
     * Returns JSON:
     *   Sync mode:      { "responses": [...], "session_id": "..." }
     *   Streaming mode: { "status": "streaming", "session_id": "...", "topic": "the-summit/..." }
     *   Error:          { "error": "..." }
     */
    #[Route('/chat', name: 'chat_submit', methods: ['POST'])]
    public function submit(Request $request): JsonResponse
    {
        $data = json_decode($request->getContent(), true);

        if (!is_array($data)) {
            return $this->json(['error' => 'Invalid JSON'], 400);
        }

        $message = is_string($data['message'] ?? null) ? $data['message'] : '';
        $sessionId = is_string($data['session_id'] ?? null) ? $data['session_id'] : null;
        $streaming = (bool) ($data['streaming'] ?? false);
        /** @var array<string, mixed> $data */
        $personas = $this->extractPersonas($data);

        if ($message === '') {
            return $this->json(['error' => 'Message is required'], 400);
        }

        // ──────────────────────────────────────────────────────────────────────
        // STREAMING MODE
        // ──────────────────────────────────────────────────────────────────────
        if ($streaming && $this->streamOrchestrator !== null) {
            $topicBase = 'the-summit/' . ($sessionId ?? 'anonymous');
            $orchestrator = $this->streamOrchestrator;

            $this->eventDispatcher->addListener(
                'kernel.terminate',
                static function () use ($orchestrator, $message, $sessionId, $topicBase, $personas): void {
                    try {
                        $orchestrator->deliberateStreaming($message, $sessionId ?? '', $topicBase, $personas);
                    } catch (\Throwable) {
                        // Streaming errors are published to Mercure as error events
                        // by the orchestrator itself
                    }
                },
            );

            return $this->json([
                'status' => 'streaming',
                'session_id' => $sessionId,
                'topic' => $topicBase,
            ]);
        }

        // ──────────────────────────────────────────────────────────────────────
        // SYNC MODE
        // ──────────────────────────────────────────────────────────────────────
        try {
            $responses = $this->orchestrator->deliberate($message, $sessionId, $personas);

            return $this->json([
                'responses' => $responses,
                'session_id' => $sessionId,
            ]);
        } catch (\Throwable $e) {
            return $this->json([
                'error' => 'Summit deliberation failed: ' . $e->getMessage(),
            ], 500);
        }
    }

    /**
     * Extract and validate the personas array from the request data.
     *
     * @param array<string, mixed> $data The decoded JSON request body
     *
     * @return string[] Validated persona names
     */
    private function extractPersonas(array $data): array
    {
        $raw = $data['personas'] ?? [];

        if (!is_array($raw)) {
            return [];
        }

        return array_values(array_filter($raw, 'is_string'));
    }
}
