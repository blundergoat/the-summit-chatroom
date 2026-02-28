<?php

declare(strict_types=1);

namespace App\Tests\Unit\Controller;

use App\Controller\ChatController;
use App\Service\SummitStreamOrchestrator;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;
use Psr\Log\LoggerInterface;
use Symfony\Component\DependencyInjection\Container;
use Symfony\Component\EventDispatcher\EventDispatcherInterface;
use Symfony\Component\HttpFoundation\Request;

class ChatControllerTest extends TestCase
{
    /** @var EventDispatcherInterface&MockObject */
    private EventDispatcherInterface&MockObject $eventDispatcher;

    /** @var SummitStreamOrchestrator&MockObject */
    private SummitStreamOrchestrator&MockObject $streamOrchestrator;

    /** @var LoggerInterface&MockObject */
    private LoggerInterface&MockObject $logger;

    private ChatController $controller;

    protected function setUp(): void
    {
        $this->eventDispatcher = $this->createMock(EventDispatcherInterface::class);
        $this->streamOrchestrator = $this->createMock(SummitStreamOrchestrator::class);
        $this->logger = $this->createMock(LoggerInterface::class);

        $this->controller = new ChatController(
            $this->streamOrchestrator,
            $this->eventDispatcher,
            $this->logger,
        );

        $container = new Container();
        $container->set('parameter_bag', new \Symfony\Component\DependencyInjection\ParameterBag\ContainerBag($container));
        $this->controller->setContainer($container);
    }

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

    public function testSubmitRegistersTerminateListenerAndReturnsStreamingPayload(): void
    {
        $this->eventDispatcher
            ->expects($this->once())
            ->method('addListener')
            ->with('kernel.terminate', $this->isType('callable'));

        $request = new Request(content: json_encode([
            'message' => 'Hello',
            'session_id' => 'sess-1',
            'personas' => ['gandalf', 'terminator', 'ships_cat'],
        ]) ?: '');

        $response = $this->controller->submit($request);

        $this->assertSame(200, $response->getStatusCode());
        $data = json_decode((string) $response->getContent(), true);
        $this->assertSame('streaming', $data['status']);
        $this->assertSame('sess-1', $data['session_id']);
        $this->assertSame('the-summit/sess-1', $data['topic']);
    }

    public function testSubmitWithNullSessionUsesAnonymousTopic(): void
    {
        $this->eventDispatcher
            ->expects($this->once())
            ->method('addListener');

        $request = new Request(content: json_encode([
            'message' => 'Hello',
            'personas' => ['gandalf'],
        ]) ?: '');

        $response = $this->controller->submit($request);

        $data = json_decode((string) $response->getContent(), true);
        $this->assertSame('the-summit/anonymous', $data['topic']);
    }
}
