<?php

declare(strict_types=1);

namespace App\Controller;

use App\Streaming\CancellationToken;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Routing\Attribute\Route;

class StreamCancelController extends AbstractController
{
    public function __construct(
        private readonly CancellationToken $cancellationToken,
    ) {
    }

    #[Route('/stream/cancel', name: 'stream_cancel', methods: ['POST'])]
    public function cancel(Request $request): JsonResponse
    {
        $data = json_decode($request->getContent(), true);
        $topic = is_array($data) && is_string($data['topic'] ?? null) ? $data['topic'] : '';

        if ($topic === '') {
            return $this->json(['error' => 'Topic is required'], 400);
        }

        $this->cancellationToken->cancel($topic);

        return $this->json(['status' => 'cancelled']);
    }
}
