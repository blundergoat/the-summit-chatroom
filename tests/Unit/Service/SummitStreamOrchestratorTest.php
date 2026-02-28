<?php

declare(strict_types=1);

namespace App\Tests\Unit\Service;

use App\Service\SummitStreamOrchestrator;
use App\Streaming\CancellationToken;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;
use Psr\Log\LoggerInterface;
use StrandsPhpClient\Response\Usage;
use StrandsPhpClient\StrandsClient;
use StrandsPhpClient\Streaming\StreamEvent;
use StrandsPhpClient\Streaming\StreamEventType;
use StrandsPhpClient\Streaming\StreamResult;
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
 *   - StreamResult usage data is logged
 *   - Cancellation aborts the stream
 */
class SummitStreamOrchestratorTest extends TestCase
{
    /** @var StrandsClient&MockObject */
    private StrandsClient&MockObject $strandsClient;

    /** @var HubInterface&MockObject */
    private HubInterface&MockObject $hub;

    /** @var LoggerInterface&MockObject */
    private LoggerInterface&MockObject $logger;

    /** @var CancellationToken&MockObject */
    private CancellationToken&MockObject $cancellationToken;

    private SummitStreamOrchestrator $orchestrator;

    /** @var string[] Default test personas */
    private array $personas = ['gandalf', 'terminator', 'ships_cat'];

    protected function setUp(): void
    {
        $this->strandsClient = $this->createMock(StrandsClient::class);
        $this->hub = $this->createMock(HubInterface::class);
        $this->logger = $this->createMock(LoggerInterface::class);
        $this->cancellationToken = $this->createMock(CancellationToken::class);
        $this->cancellationToken->method('isCancelled')->willReturn(false);

        $this->orchestrator = new SummitStreamOrchestrator(
            $this->strandsClient,
            $this->hub,
            $this->logger,
            $this->cancellationToken,
        );
    }

    public function testDeliberateStreamingPublishesStartAndDoneEvents(): void
    {
        $this->strandsClient->method('stream')->willReturn(
            new StreamResult(text: '', usage: new Usage()),
        );

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
        $this->strandsClient
            ->method('stream')
            ->willReturnCallback(function (string $message, callable $onEvent) use (&$callCount) {
                if ($callCount === 0) {
                    $onEvent(new StreamEvent(
                        type: StreamEventType::Text,
                        text: 'Hello from gandalf',
                    ));
                }
                $callCount++;

                return new StreamResult(text: 'Hello from gandalf', usage: new Usage());
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
        $this->strandsClient
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

                return new StreamResult(text: 'result', usage: new Usage());
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
        $this->strandsClient
            ->method('stream')
            ->willReturnCallback(function () use (&$callCount) {
                $callCount++;
                if ($callCount === 1) {
                    throw new \RuntimeException('Connection lost');
                }

                return new StreamResult(text: '', usage: new Usage());
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
        $this->strandsClient
            ->method('stream')
            ->willReturnCallback(function (string $message, callable $onEvent) use (&$callCount) {
                if ($callCount === 0) {
                    $onEvent(new StreamEvent(
                        type: StreamEventType::Error,
                        errorMessage: 'Rate limited',
                    ));
                }
                $callCount++;

                return new StreamResult(text: '', usage: new Usage());
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

        $this->strandsClient
            ->method('stream')
            ->willReturnCallback(function (string $message, callable $onEvent, $context) use (&$streamedPersonas) {
                $streamedPersonas[] = $context->toArray()['metadata']['persona'];

                return new StreamResult(text: '', usage: new Usage());
            });

        $this->hub->method('publish')->willReturn('id');

        $this->orchestrator->deliberateStreaming('Hi', 'sess-1', 'topic', $this->personas);

        $this->assertSame(['gandalf', 'terminator', 'ships_cat'], $streamedPersonas);
    }

    public function testDeliberateStreamingLogsStreamResultUsageData(): void
    {
        $this->strandsClient
            ->method('stream')
            ->willReturnCallback(function (string $message, callable $onEvent) {
                return new StreamResult(
                    text: 'response',
                    usage: new Usage(inputTokens: 150, outputTokens: 75),
                    toolsUsed: [['name' => 'search']],
                );
            });

        $logEntries = [];
        $this->logger
            ->method('info')
            ->willReturnCallback(function (string $message, array $context) use (&$logEntries) {
                $logEntries[] = ['message' => $message, 'context' => $context];
            });

        $this->hub->method('publish')->willReturn('id');

        $this->orchestrator->deliberateStreaming('Hi', 'sess-1', 'topic', ['gandalf']);

        $completedLogs = array_filter($logEntries, fn ($e) => $e['message'] === 'summit.streaming.persona.completed');
        $this->assertNotEmpty($completedLogs);

        $log = array_values($completedLogs)[0]['context'];
        $this->assertSame(150, $log['input_tokens']);
        $this->assertSame(75, $log['output_tokens']);
        $this->assertSame(1, $log['tools_used']);
    }

    public function testDeliberateStreamingAbortOnCancellation(): void
    {
        $cancellationToken = $this->createMock(CancellationToken::class);
        $cancellationToken->method('isCancelled')->willReturn(true);

        $orchestrator = new SummitStreamOrchestrator(
            $this->strandsClient,
            $this->hub,
            $this->logger,
            $cancellationToken,
        );

        $this->strandsClient
            ->method('stream')
            ->willReturnCallback(function (string $message, callable $onEvent) {
                $result = $onEvent(new StreamEvent(type: StreamEventType::Text, text: 'Hello'));
                $this->assertFalse($result);

                return new StreamResult(text: '', usage: new Usage());
            });

        $published = [];
        $this->hub
            ->method('publish')
            ->willReturnCallback(function (Update $update) use (&$published) {
                $published[] = json_decode($update->getData(), true);

                return 'id';
            });

        $orchestrator->deliberateStreaming('Hi', 'sess-1', 'topic', ['gandalf']);

        $cancelledEvents = array_filter($published, fn ($e) => ($e['type'] ?? '') === 'cancelled');
        $this->assertNotEmpty($cancelledEvents);
    }
}
