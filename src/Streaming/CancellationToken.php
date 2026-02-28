<?php

declare(strict_types=1);

namespace App\Streaming;

use Psr\Cache\CacheItemPoolInterface;

/**
 * Signal store for stream cancellation.
 *
 * Orchestrators check isCancelled() on each event callback and return false
 * to abort the StrandsClient stream when the user cancels.
 *
 * Uses Symfony's cache pool (filesystem by default) with short TTL for
 * automatic cleanup of stale entries.
 */
class CancellationToken
{
    private const TTL_SECONDS = 120;

    public function __construct(private readonly CacheItemPoolInterface $cache)
    {
    }

    public function cancel(string $topic): void
    {
        $item = $this->cache->getItem($this->key($topic));
        $item->set(true);
        $item->expiresAfter(self::TTL_SECONDS);
        $this->cache->save($item);
    }

    public function isCancelled(string $topic): bool
    {
        return $this->cache->getItem($this->key($topic))->isHit();
    }

    public function clear(string $topic): void
    {
        $this->cache->deleteItem($this->key($topic));
    }

    private function key(string $topic): string
    {
        return 'strands_cancel_' . hash('xxh3', $topic);
    }
}
