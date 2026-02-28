<?php

declare(strict_types=1);

namespace App\Tests\Integration\Kernel;

use App\Controller\ChatController;
use App\Kernel;
use PHPUnit\Framework\TestCase;
use StrandsPhpClient\StrandsClient;

class StrandsServiceWiringTest extends TestCase
{
    private ?Kernel $kernel = null;

    protected function setUp(): void
    {
        $this->setEnv('APP_ENV', 'test');
        $this->setEnv('APP_SECRET', 'test-secret-for-kernel-wiring');
        $this->setEnv('AGENT_ENDPOINT', 'http://localhost:8081');
        $this->setEnv('MERCURE_URL', 'http://localhost:3701/.well-known/mercure');
        $this->setEnv('MERCURE_PUBLIC_URL', 'http://localhost:3701/.well-known/mercure');
        $this->setEnv('MERCURE_JWT_SECRET', 'test-mercure-secret-32chars-minimum');
    }

    protected function tearDown(): void
    {
        if ($this->kernel !== null) {
            $this->kernel->shutdown();
            $this->kernel = null;
        }

        parent::tearDown();
    }

    public function testNamedStrandsClientsResolveFromContainer(): void
    {
        $container = $this->bootKernel()->getContainer();
        $controller = $container->get(ChatController::class);
        $this->assertInstanceOf(ChatController::class, $controller);

        $streamOrchestrator = $this->readPrivateProperty($controller, 'streamOrchestrator');
        $this->assertNotNull($streamOrchestrator);
        $streamClient = $this->readPrivateProperty($streamOrchestrator, 'strandsClient');
        $this->assertInstanceOf(StrandsClient::class, $streamClient);
    }

    private function setEnv(string $name, string $value): void
    {
        putenv($name . '=' . $value);
        $_ENV[$name] = $value;
        $_SERVER[$name] = $value;
    }

    private function readPrivateProperty(object $instance, string $property): mixed
    {
        $reflection = new \ReflectionObject($instance);
        $prop = $reflection->getProperty($property);
        $prop->setAccessible(true);

        return $prop->getValue($instance);
    }

    private function bootKernel(): Kernel
    {
        if ($this->kernel === null) {
            $this->kernel = new Kernel('test', true);
            $this->kernel->boot();
        }

        return $this->kernel;
    }
}
