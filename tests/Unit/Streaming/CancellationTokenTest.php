<?php

declare(strict_types=1);

namespace App\Tests\Unit\Streaming;

use App\Streaming\CancellationToken;
use PHPUnit\Framework\TestCase;
use Symfony\Component\Cache\Adapter\ArrayAdapter;

class CancellationTokenTest extends TestCase
{
    private CancellationToken $token;

    protected function setUp(): void
    {
        $this->token = new CancellationToken(new ArrayAdapter());
    }

    public function testNotCancelledByDefault(): void
    {
        $this->assertFalse($this->token->isCancelled('topic/123'));
    }

    public function testCancelSetsCancelledFlag(): void
    {
        $this->token->cancel('topic/123');

        $this->assertTrue($this->token->isCancelled('topic/123'));
    }

    public function testClearRemovesCancelledFlag(): void
    {
        $this->token->cancel('topic/123');
        $this->token->clear('topic/123');

        $this->assertFalse($this->token->isCancelled('topic/123'));
    }

    public function testDifferentTopicsAreIndependent(): void
    {
        $this->token->cancel('topic/123');

        $this->assertTrue($this->token->isCancelled('topic/123'));
        $this->assertFalse($this->token->isCancelled('topic/456'));
    }
}
