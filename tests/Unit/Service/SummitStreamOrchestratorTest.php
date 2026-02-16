<?php

declare(strict_types=1);

namespace App\Tests\Unit\Service;

use App\Service\SummitStreamOrchestrator;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;
use Psr\Log\LoggerInterface;
use Strands\StrandsClient;
use Strands\Streaming\StreamEvent;
use Strands\Streaming\StreamEventType;
use Symfony\Component\Mercure\HubInterface;
use Symfony\Component\Mercure\Update;

/**
 * Unit tests for SummitStreamOrchestrator (Mercure streaming mode).
 *
 * These tests verify:
 *   - Start and all_complete events are always published
 *   - Text tokens from agents are forwarded to Mercure
 *   - All event types are handled
 *   - Exceptions during streaming are caught and published as error events
 *   - All personas are streamed in order
 */
class SummitStreamOrchestratorTest extends TestCase
{
    /** @var StrandsClient&MockObject */
    private StrandsClient&MockObject $client;

    /** @var HubInterface&MockObject */
    private HubInterface&MockObject $hub;

    /** @var LoggerInterface&MockObject */
    private LoggerInterface&MockObject $logger;

    private SummitStreamOrchestrator $orchestrator;

    /** @var string[] Default test personas */
    private array $personas = ['gandalf', 'terminator', 'ships_cat'];

    protected function setUp(): void
    {
        $this->client = $this->createMock(StrandsClient::class);
        $this->hub = $this->createMock(HubInterface::class);
        $this->logger = $this->createMock(LoggerInterface::class);

        $this->orchestrator = new SummitStreamOrchestrator(
            $this->client,
            $this->hub,
            $this->logger,
        );
    }

    public function testDeliberateStreamingPublishesStartAndDoneEvents(): void
    {
        $this->client->method('stream');

        $published = [];
        $this->hub
            ->method('publish')
            ->willReturnCallback(function (Update $update) use (&$published) {
                $published[] = [
                    'topic' => $update->getTopics()[0],
                    'data' => json_decode($update->getData(), true),
                ];

                return 'id';
            });

        $this->orchestrator->deliberateStreaming('Hello', 'sess-1', 'the-summit/sess-1', $this->personas);

        $types = array_column(array_column($published, 'data'), 'type');
        $this->assertContains('start', $types);
        $this->assertContains('all_complete', $types);

        $last = end($published);
        $this->assertSame('the-summit/sess-1/done', $last['topic']);
        $this->assertSame('all_complete', $last['data']['type']);
    }

    public function testDeliberateStreamingPublishesTextEvents(): void
    {
        $callCount = 0;
        $this->client
            ->method('stream')
            ->willReturnCallback(function (string $message, callable $onEvent) use (&$callCount) {
                if ($callCount === 0) {
                    $onEvent(new StreamEvent(
                        type: StreamEventType::Text,
                        text: 'Hello from gandalf',
                    ));
                }
                $callCount++;
            });

        $published = [];
        $this->hub
            ->method('publish')
            ->willReturnCallback(function (Update $update) use (&$published) {
                $published[] = json_decode($update->getData(), true);

                return 'id';
            });

        $this->orchestrator->deliberateStreaming('Hi', 'sess-1', 'topic', $this->personas);

        $textEvents = array_filter($published, fn ($e) => ($e['type'] ?? '') === 'text');
        $this->assertNotEmpty($textEvents);
        $textEvent = array_values($textEvents)[0];
        $this->assertSame('gandalf', $textEvent['persona']);
        $this->assertSame('Hello from gandalf', $textEvent['content']);
    }

    public function testDeliberateStreamingPublishesAllEventTypes(): void
    {
        $callCount = 0;
        $this->client
            ->method('stream')
            ->willReturnCallback(function (string $message, callable $onEvent) use (&$callCount) {
                if ($callCount === 0) {
                    $onEvent(new StreamEvent(type: StreamEventType::Thinking));
                    $onEvent(new StreamEvent(type: StreamEventType::ToolUse, toolName: 'search'));
                    $onEvent(new StreamEvent(type: StreamEventType::ToolResult, toolName: 'search'));
                    $onEvent(new StreamEvent(type: StreamEventType::Text, text: 'result'));
                    $onEvent(new StreamEvent(type: StreamEventType::Complete));
                }
                $callCount++;
            });

        $published = [];
        $this->hub
            ->method('publish')
            ->willReturnCallback(function (Update $update) use (&$published) {
                $published[] = json_decode($update->getData(), true);

                return 'id';
            });

        $this->orchestrator->deliberateStreaming('Hi', 'sess-1', 'topic', $this->personas);

        $types = array_column($published, 'type');
        $this->assertContains('thinking', $types);
        $this->assertContains('tool_use', $types);
        $this->assertContains('tool_result', $types);
        $this->assertContains('text', $types);
        $this->assertContains('complete', $types);
    }

    public function testDeliberateStreamingPublishesErrorOnStreamException(): void
    {
        $callCount = 0;
        $this->client
            ->method('stream')
            ->willReturnCallback(function () use (&$callCount) {
                $callCount++;
                if ($callCount === 1) {
                    throw new \RuntimeException('Connection lost');
                }
            });

        $published = [];
        $this->hub
            ->method('publish')
            ->willReturnCallback(function (Update $update) use (&$published) {
                $published[] = [
                    'topic' => $update->getTopics()[0],
                    'data' => json_decode($update->getData(), true),
                ];

                return 'id';
            });

        $this->orchestrator->deliberateStreaming('Hi', 'sess-1', 'topic', $this->personas);

        $errorEvents = array_filter($published, fn ($e) => ($e['data']['type'] ?? '') === 'error');
        $this->assertNotEmpty($errorEvents);
        $error = array_values($errorEvents)[0];
        $this->assertSame('gandalf', $error['data']['persona']);
        $this->assertSame('Connection lost', $error['data']['message']);

        $last = end($published);
        $this->assertSame('all_complete', $last['data']['type']);
    }

    public function testDeliberateStreamingPublishesErrorEventFromStream(): void
    {
        $callCount = 0;
        $this->client
            ->method('stream')
            ->willReturnCallback(function (string $message, callable $onEvent) use (&$callCount) {
                if ($callCount === 0) {
                    $onEvent(new StreamEvent(
                        type: StreamEventType::Error,
                        errorMessage: 'Rate limited',
                    ));
                }
                $callCount++;
            });

        $published = [];
        $this->hub
            ->method('publish')
            ->willReturnCallback(function (Update $update) use (&$published) {
                $published[] = json_decode($update->getData(), true);

                return 'id';
            });

        $this->orchestrator->deliberateStreaming('Hi', 'sess-1', 'topic', $this->personas);

        $errorEvents = array_filter($published, fn ($e) => ($e['type'] ?? '') === 'error');
        $this->assertNotEmpty($errorEvents);
        $error = array_values($errorEvents)[0];
        $this->assertSame('Rate limited', $error['message']);
    }

    public function testDeliberateStreamingStreamsAllPersonasInOrder(): void
    {
        $streamedPersonas = [];

        $this->client
            ->method('stream')
            ->willReturnCallback(function (string $message, callable $onEvent, $context) use (&$streamedPersonas) {
                $streamedPersonas[] = $context->toArray()['metadata']['persona'];
            });

        $this->hub->method('publish')->willReturn('id');

        $this->orchestrator->deliberateStreaming('Hi', 'sess-1', 'topic', $this->personas);

        $this->assertSame(['gandalf', 'terminator', 'ships_cat'], $streamedPersonas);
    }
}
