---
applyTo: '**'
---

# AI Agent Guidelines - The Summit

General principles for AI agents working in this codebase.

## Core Rules

- Correctness over cleverness. Prefer boring, readable solutions.
- Smallest change that works. Don't refactor adjacent code unless it reduces risk.
- Follow existing patterns before introducing new abstractions or dependencies.
- Full-stack awareness: a change in one layer often affects others (PHP ↔ Python ↔ Twig ↔ Docker).
- Read first, fix second. Trace the actual code path before proposing changes.
- Prove it works: validate with `composer preflight` (tests + PHPStan + CS check).
- Be explicit about uncertainty. If you can't verify something, say so.

## Project-Specific Constraints

- **PHP**: >=8.2, Symfony 6.4, `declare(strict_types=1)`, PSR-12, PHPStan level 10
- **Style**: Single quotes, short arrays, ordered imports, trailing commas in multiline
- **Namespace**: `App\` for src/, `App\Tests\` for tests/
- **Python agent**: FastAPI + Strands SDK in `strands_agents/`
- **Frontend**: Single Twig template (`templates/chatroom.html.twig`) with inline JS
- **Local dependency**: `blundergoat/strands-client` is a path dependency at `../strands-php-client`

## Architecture

Three AI advisors (Analyst, Skeptic, Strategist) deliberate in sequence. Each sees prior responses.

```
Browser → ChatController → Orchestrator → Python agent → Ollama/Bedrock
                                              ↕
                              Mercure (streaming mode only)
```

Two execution modes:
- **Sync**: `SummitOrchestrator` - blocks, returns JSON
- **Streaming**: `SummitStreamOrchestrator` - publishes tokens via Mercure SSE

All three agents hit the same Python `/invoke` or `/stream` endpoint; the `persona` field in request metadata selects different system prompts.

## Cross-Layer Impact

When changing any layer, check:
1. PHP service wiring (`config/services.yaml`, `config/packages/strands.yaml`)
2. Python agent contracts (Pydantic models in `api/server.py`)
3. Symfony route registration (controller attributes)
4. Twig template (`templates/chatroom.html.twig`)
5. Docker Compose environment variables (`docker-compose.yml`)
6. PHPUnit tests covering the changed code path
7. PHPStan passes at Level 10

Do NOT consider a feature done until all affected layers are covered.

## Before Marking Done

- `composer test` passes
- `composer analyse` passes (PHPStan level 10, zero errors)
- `composer cs:check` passes (PHP-CS-Fixer)
- If Docker config changed: `docker compose config` validates
- If Python agent changed: endpoint contract matches PHP client calls
- If environment variables added: `.env.example`, `docker-compose.yml`, and `start-dev.sh` all updated

## Testing Conventions

- Framework: PHPUnit 11 (`phpunit.xml.dist`)
- Test files: `tests/Unit/*Test.php` mirroring production paths
- Prefer deterministic unit tests with mocks for HTTP clients, Mercure, event dispatch
- Coverage minimum: 80% (enforced by `composer preflight:coverage`)
- Run focused tests during iteration: `vendor/bin/phpunit tests/Unit/Service/SummitOrchestratorTest.php`

## Commit Messages

Short, imperative. Examples:
- `Add session history endpoint to Python agent`
- `Fix Mercure JWT secret length validation in start-dev.sh`
- `Refactor orchestrator to extract agent sequencing logic`
