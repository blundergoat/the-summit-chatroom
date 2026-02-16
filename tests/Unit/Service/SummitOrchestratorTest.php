<?php

declare(strict_types=1);

namespace App\Tests\Unit\Service;

use App\Service\SummitOrchestrator;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;
use Psr\Log\LoggerInterface;
use Strands\Response\AgentResponse;
use Strands\StrandsClient;

/**
 * Unit tests for SummitOrchestrator (sync mode).
 *
 * These tests verify:
 *   - The single client is called once per persona in the correct order
 *   - The correct message, session_id, and persona metadata are passed
 *   - Null session_id is handled gracefully
 *   - Exceptions from agents propagate to the caller
 */
class SummitOrchestratorTest extends TestCase
{
    /** @var StrandsClient&MockObject */
    private StrandsClient&MockObject $client;

    /** @var LoggerInterface&MockObject */
    private LoggerInterface&MockObject $logger;

    private SummitOrchestrator $orchestrator;

    protected function setUp(): void
    {
        $this->client = $this->createMock(StrandsClient::class);
        $this->logger = $this->createMock(LoggerInterface::class);

        $this->orchestrator = new SummitOrchestrator(
            $this->client,
            $this->logger,
        );
    }

    public function testDeliberateCallsClientOncePerPersonaInOrder(): void
    {
        $callOrder = [];

        $this->client
            ->expects($this->exactly(3))
            ->method('invoke')
            ->willReturnCallback(function (string $message, $context) use (&$callOrder) {
                $persona = $context->toArray()['metadata']['persona'];
                $callOrder[] = $persona;

                return new AgentResponse(text: ucfirst($persona) . ' response');
            });

        $personas = ['gandalf', 'terminator', 'ships_cat'];
        $responses = $this->orchestrator->deliberate('Hello', 'sess-1', $personas);

        $this->assertSame(['gandalf', 'terminator', 'ships_cat'], $callOrder);

        $this->assertCount(3, $responses);
        $this->assertSame('gandalf', $responses[0]['persona']);
        $this->assertSame('Gandalf response', $responses[0]['text']);
        $this->assertSame('terminator', $responses[1]['persona']);
        $this->assertSame('Terminator response', $responses[1]['text']);
        $this->assertSame('ships_cat', $responses[2]['persona']);
        $this->assertSame('Ships_cat response', $responses[2]['text']);
    }

    public function testDeliberatePassesMessageAndSessionId(): void
    {
        $this->client
            ->expects($this->exactly(2))
            ->method('invoke')
            ->with(
                $this->identicalTo('What is AI?'),
                $this->anything(),
                $this->identicalTo('my-session'),
            )
            ->willReturn(new AgentResponse(text: 'ok'));

        $this->orchestrator->deliberate('What is AI?', 'my-session', ['angry_chef', 'your_nan']);
    }

    public function testDeliberateWorksWithNullSessionId(): void
    {
        $this->client->method('invoke')->willReturn(new AgentResponse(text: 'ok'));

        $responses = $this->orchestrator->deliberate('Hello', null, ['gandalf', 'terminator', 'ships_cat']);

        $this->assertCount(3, $responses);
    }

    public function testDeliberatePropagatesException(): void
    {
        $this->client
            ->method('invoke')
            ->willThrowException(new \RuntimeException('Agent timeout'));

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('Agent timeout');

        $this->orchestrator->deliberate('Hello', null, ['gandalf']);
    }

    public function testDeliberateReturnsEmptyArrayWithNoPersonas(): void
    {
        $this->client->expects($this->never())->method('invoke');

        $responses = $this->orchestrator->deliberate('Hello', 'sess-1', []);

        $this->assertSame([], $responses);
    }
}
