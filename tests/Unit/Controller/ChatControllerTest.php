<?php

declare(strict_types=1);

namespace App\Tests\Unit\Controller;

use App\Controller\ChatController;
use App\Service\SummitOrchestrator;
use App\Service\SummitStreamOrchestrator;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;
use Symfony\Component\DependencyInjection\Container;
use Symfony\Component\EventDispatcher\EventDispatcherInterface;
use Symfony\Component\HttpFoundation\Request;

/**
 * Unit tests for ChatController.
 *
 * These tests verify:
 *   - Input validation (invalid JSON, empty/missing message)
 *   - Sync mode returns all agent responses with personas
 *   - Sync mode wraps exceptions in 500 responses
 *   - Streaming mode registers a kernel.terminate listener
 *   - Streaming mode falls back to sync when no stream orchestrator is available
 */
class ChatControllerTest extends TestCase
{
    /** @var SummitOrchestrator&MockObject */
    private SummitOrchestrator&MockObject $orchestrator;

    /** @var EventDispatcherInterface&MockObject */
    private EventDispatcherInterface&MockObject $eventDispatcher;

    /** @var SummitStreamOrchestrator&MockObject */
    private SummitStreamOrchestrator&MockObject $streamOrchestrator;

    private ChatController $controller;

    protected function setUp(): void
    {
        $this->orchestrator = $this->createMock(SummitOrchestrator::class);
        $this->eventDispatcher = $this->createMock(EventDispatcherInterface::class);
        $this->streamOrchestrator = $this->createMock(SummitStreamOrchestrator::class);

        $this->controller = new ChatController(
            $this->orchestrator,
            $this->eventDispatcher,
            $this->streamOrchestrator,
        );

        $container = new Container();
        $container->set('parameter_bag', new \Symfony\Component\DependencyInjection\ParameterBag\ContainerBag($container));
        $this->controller->setContainer($container);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // INPUT VALIDATION TESTS
    // ──────────────────────────────────────────────────────────────────────────

    public function testSubmitReturnsErrorOnInvalidJson(): void
    {
        $request = new Request(content: 'not json');

        $response = $this->controller->submit($request);

        $this->assertSame(400, $response->getStatusCode());
        $data = json_decode((string) $response->getContent(), true);
        $this->assertSame('Invalid JSON', $data['error']);
    }

    public function testSubmitReturnsErrorOnEmptyMessage(): void
    {
        $request = new Request(content: '{"message":""}');

        $response = $this->controller->submit($request);

        $this->assertSame(400, $response->getStatusCode());
        $data = json_decode((string) $response->getContent(), true);
        $this->assertSame('Message is required', $data['error']);
    }

    public function testSubmitReturnsErrorOnMissingMessage(): void
    {
        $request = new Request(content: '{"session_id":"s1"}');

        $response = $this->controller->submit($request);

        $this->assertSame(400, $response->getStatusCode());
    }

    // ──────────────────────────────────────────────────────────────────────────
    // SYNC MODE TESTS
    // ──────────────────────────────────────────────────────────────────────────

    public function testSubmitSyncModeReturnsResponses(): void
    {
        $personas = ['gandalf', 'terminator', 'ships_cat'];

        $this->orchestrator
            ->expects($this->once())
            ->method('deliberate')
            ->with('Hello', 'sess-1', $personas)
            ->willReturn([
                ['persona' => 'gandalf', 'text' => 'A wizard speaks'],
                ['persona' => 'terminator', 'text' => 'Affirmative'],
                ['persona' => 'ships_cat', 'text' => 'Meow'],
            ]);

        $request = new Request(content: json_encode([
            'message' => 'Hello',
            'session_id' => 'sess-1',
            'personas' => $personas,
        ]) ?: '');

        $response = $this->controller->submit($request);

        $this->assertSame(200, $response->getStatusCode());
        $data = json_decode((string) $response->getContent(), true);
        $this->assertCount(3, $data['responses']);
        $this->assertSame('gandalf', $data['responses'][0]['persona']);
        $this->assertSame('sess-1', $data['session_id']);
    }

    public function testSubmitSyncModeReturns500OnException(): void
    {
        $this->orchestrator
            ->method('deliberate')
            ->willThrowException(new \RuntimeException('Agent down'));

        $request = new Request(content: json_encode([
            'message' => 'Hello',
            'session_id' => null,
            'personas' => ['gandalf'],
        ]) ?: '');

        $response = $this->controller->submit($request);

        $this->assertSame(500, $response->getStatusCode());
        $data = json_decode((string) $response->getContent(), true);
        $this->assertStringContainsString('Agent down', $data['error']);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // STREAMING MODE TESTS
    // ──────────────────────────────────────────────────────────────────────────

    public function testSubmitStreamingModeRegistersTerminateListener(): void
    {
        $this->eventDispatcher
            ->expects($this->once())
            ->method('addListener')
            ->with('kernel.terminate', $this->isType('callable'));

        $request = new Request(content: json_encode([
            'message' => 'Hello',
            'session_id' => 'sess-1',
            'streaming' => true,
            'personas' => ['gandalf', 'terminator', 'ships_cat'],
        ]) ?: '');

        $response = $this->controller->submit($request);

        $this->assertSame(200, $response->getStatusCode());
        $data = json_decode((string) $response->getContent(), true);
        $this->assertSame('streaming', $data['status']);
        $this->assertSame('sess-1', $data['session_id']);
        $this->assertSame('the-summit/sess-1', $data['topic']);
    }

    public function testSubmitStreamingWithNullSessionUsesAnonymousTopic(): void
    {
        $this->eventDispatcher
            ->expects($this->once())
            ->method('addListener');

        $request = new Request(content: json_encode([
            'message' => 'Hello',
            'streaming' => true,
            'personas' => ['gandalf'],
        ]) ?: '');

        $response = $this->controller->submit($request);

        $data = json_decode((string) $response->getContent(), true);
        $this->assertSame('the-summit/anonymous', $data['topic']);
    }

    public function testSubmitStreamingWithoutOrchestratorFallsBackToSync(): void
    {
        $controller = new ChatController(
            $this->orchestrator,
            $this->eventDispatcher,
            null,
        );
        $container = new Container();
        $container->set('parameter_bag', new \Symfony\Component\DependencyInjection\ParameterBag\ContainerBag($container));
        $controller->setContainer($container);

        $this->orchestrator
            ->expects($this->once())
            ->method('deliberate')
            ->willReturn([['persona' => 'gandalf', 'text' => 'ok']]);

        $request = new Request(content: json_encode([
            'message' => 'Hello',
            'streaming' => true,
            'personas' => ['gandalf'],
        ]) ?: '');

        $response = $controller->submit($request);

        $this->assertSame(200, $response->getStatusCode());
        $data = json_decode((string) $response->getContent(), true);
        $this->assertArrayHasKey('responses', $data);
    }
}
