# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

The Summit is a multi-agent group chat application where three AI advisors (Analyst, Skeptic, Strategist) debate user questions sequentially. Built with PHP/Symfony backend, Python/FastAPI agent layer, and Mercure for real-time streaming.

## Commands

```bash
# Run all quality checks (tests, lint, analysis, coverage)
composer preflight

# Tests
composer test                          # Run PHPUnit tests
composer test:coverage                 # Tests with HTML + clover coverage
vendor/bin/phpunit tests/Unit/Controller/ChatControllerTest.php  # Single test file

# Static analysis
composer analyse                       # PHPStan Level 10
composer analyse:complexity            # Cyclomatic complexity (max 20)
composer analyse:messdetector          # PHPMD

# Code style
composer cs:check                      # Dry-run PHP-CS-Fixer
composer cs:fix                        # Auto-fix code style (PSR-12)

# Docker (full stack)
docker compose up --build              # Build and start all 5 services
```

## Architecture

### Data Flow

```
Browser (Twig UI :8082)
  → ChatController (POST /chat)
    → SummitOrchestrator (sync) or SummitStreamOrchestrator (streaming)
      → Python FastAPI agent (:8000) with persona metadata
        → Ollama (:11434) or AWS Bedrock
      ← Responses streamed back via Mercure (:3100) in streaming mode
```

### Two Execution Modes

- **Sync**: `SummitOrchestrator::deliberate()` calls all 3 agents sequentially, blocks until complete, returns JSON
- **Streaming**: `SummitStreamOrchestrator::deliberateStreaming()` runs after HTTP response via `kernel.terminate` event, publishes tokens to Mercure topics in real-time

### The Council Pattern

Three agents respond in sequence, each seeing previous responses:
1. **Analyst** - Quantifies claims with baselines and confidence bands
2. **Skeptic** - Challenges assumptions, demands evidence
3. **Strategist** - Synthesizes into actionable recommendations

All three agents hit the same Python endpoint; the `persona` field in request metadata selects different system prompts. Agents are injected via `#[Autowire(service: 'strands.client.{name}')]` from `config/packages/strands.yaml`.

### Key Components

- **PHP layer** (`src/`): PSR-4 namespace `App\`, Symfony 6.4. Controller routes requests, orchestrators manage agent sequencing
- **Python agent** (`strands_agents/`): FastAPI with Strands SDK. `agents/` has per-persona modules (analyst, skeptic, strategist), `api/server.py` is the HTTP layer, `session.py` has in-memory conversation history with deduplication
- **Frontend** (`templates/chatroom.html.twig`): Single Twig template with inline JS for both fetch (sync) and EventSource (streaming)

### Docker Services (docker-compose.yml)

5 services with dependency ordering: `ollama` → `ollama-pull` (model download) → `agent` (FastAPI) → `mercure` (SSE hub) → `app` (Symfony)

## Quality Standards

- PHPStan Level 10 (strictest)
- PHP-CS-Fixer with PSR-12
- PHPMD for design/codesize/unusedcode
- Cyclomatic complexity max 20
- Coverage minimum 80% (enforced by `preflight:coverage`)

## Dependencies

The `blundergoat/strands-client` package is a **local path dependency** at `../strands-php-client`. It must be present as a sibling directory for composer install to work.

## Environment

Copy `.env.example` to `.env`. Key variables:
- `MODEL_PROVIDER`: `ollama` (local, default) or `bedrock` (AWS)
- `AGENT_ENDPOINT`: Python agent URL (`http://agent:8000` in Docker)
- `MERCURE_URL` / `MERCURE_PUBLIC_URL`: Mercure hub endpoints

## Workflow Rules

### Debugging: read first, fix second

When debugging issues, ALWAYS read the actual code and configuration files before proposing a fix. Never assume auth flows, API patterns, Symfony service wiring, or Docker networking based on env var names or conventions. Trace the actual code path through ChatController → Orchestrator → Python agent → LLM provider first.

### Full-stack awareness

This is a full-stack platform with a PHP/Symfony backend, Python/FastAPI agent layer, Twig frontend, Docker Compose orchestration, and Mercure real-time streaming. When making changes, consider the impact across all layers. A change to the Python agent's request/response contract affects the PHP StrandsClient calls. A change to Symfony config affects Docker environment variables.

### Feature completeness checklist

After implementing any feature, verify completeness by checking:
1. PHP service wiring (`config/services.yaml`, `config/packages/strands.yaml`)
2. Python agent endpoint contracts (Pydantic models in `api/server.py`)
3. Symfony route registration (controller attributes)
4. Twig template updates (`templates/chatroom.html.twig`)
5. Docker Compose environment variables if new config is needed
6. PHPUnit tests covering the new code path
7. PHPStan passes at Level 10

Do NOT consider a feature done until all affected layers are covered.

### Preflight before done

Always run `composer preflight` (or at minimum `composer test && composer analyse && composer cs:check`) BEFORE reporting that a task is complete. Fix any failures before declaring success.

### Deep investigation

When asked to review code or investigate bugs, do a DEEP first pass. Don't produce surface-level findings. Check for false positives before reporting - verify each finding by reading surrounding code. If told to "look deeper", treat it as a signal the first pass was insufficient.
