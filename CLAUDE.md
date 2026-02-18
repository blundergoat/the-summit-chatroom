# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

The Summit is a multi-agent group chat where AI characters debate user questions. Three characters are randomly selected per session from a roster of 10 comedy personas (Angry Chef, Gandalf, Ship's Cat, etc.). Built with PHP/Symfony backend, Python/FastAPI agent layer, and Mercure for real-time streaming.

A secret objectives system occasionally injects a hidden side mission into one character's prompt per round, creating comedic contrast while the other two play it straight.

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

# Local dev
./scripts/start-dev.sh                 # Start PHP + Python + Ollama (bare-metal)
./scripts/health-check-localdev.sh     # Verify all services are running

# Docker (full stack)
docker compose up --build              # Build and start all 5 services

# Dependencies
./scripts/dependencies-install.sh      # Install from lock files
./scripts/dependencies-update.sh       # Update to latest within constraints

# Deployment
./scripts/deploy.sh                    # Build, push to ECR, redeploy ECS
./scripts/terraform.sh plan            # Preview infrastructure changes
./scripts/terraform.sh apply           # Apply infrastructure changes
```

## Architecture

### Data Flow

```
Browser (Twig UI :8082)
  → ChatController (POST /chat)
    → SummitOrchestrator (sync) or SummitStreamOrchestrator (streaming)
      → Python FastAPI agent (:8000) with persona metadata
        → Ollama (:11434) or AWS Bedrock
      ← Responses streamed back via Mercure (:3701) in streaming mode
```

### Two Execution Modes

- **Sync**: `SummitOrchestrator::deliberate()` calls all 3 agents sequentially, blocks until complete, returns JSON
- **Streaming**: `SummitStreamOrchestrator::deliberateStreaming()` runs after HTTP response via `kernel.terminate` event, publishes tokens to Mercure topics in real-time

### The Summit Pattern

Three characters are randomly selected per session from a roster of 10 personas. They respond in sequence, each seeing previous responses via the shared session. All three hit the same Python endpoint; the `persona` field in request metadata selects different system prompts.

The 10 personas are defined in `strands_agents/agents/multi_persona_chat.py`. The secret objectives system in `strands_agents/persona_objectives.py` occasionally assigns one character a hidden side mission per round.

A single `StrandsClient` is injected via `#[Autowire(service: 'strands.client.summit')]` from `config/packages/strands.yaml`.

### Key Components

- **PHP layer** (`src/`): PSR-4 namespace `App\`, Symfony 6.4. `ChatController` routes requests, `SummitOrchestrator` and `SummitStreamOrchestrator` manage agent sequencing
- **Python agent** (`strands_agents/`): FastAPI with Strands SDK. `agents/multi_persona_chat.py` defines 10 persona system prompts, `api/server.py` is the HTTP layer, `session.py` has in-memory conversation history, `persona_objectives.py` handles secret objective injection
- **Frontend** (`templates/chatroom.html.twig`): Single Twig template with inline JS for both fetch (sync) and EventSource (streaming)
- **Infrastructure** (`infra/terraform/`): AWS deployment — ECS Fargate, ALB, WAF, Route53, DynamoDB, ECR

### Docker Services (docker-compose.yml)

5 services with dependency ordering: `ollama` → `ollama-pull` (model download) → `agent` (FastAPI) → `mercure` (SSE hub) → `app` (Symfony)

## Quality Standards

- PHPStan Level 10 (strictest)
- PHP-CS-Fixer with PSR-12
- PHPMD for design/codesize/unusedcode
- Cyclomatic complexity max 20
- Coverage minimum 80% (enforced by `preflight:coverage`)

## Environment

Copy `.env.example` to `.env`. Key variables:
- `MODEL_PROVIDER`: `ollama` (local, default) or `bedrock` (AWS)
- `MODEL_ID`: Bedrock model ID (only when `MODEL_PROVIDER=bedrock`)
- `AGENT_ENDPOINT`: Python agent URL (`http://agent:8000` in Docker, `http://localhost:8081` bare-metal)
- `MERCURE_URL` / `MERCURE_PUBLIC_URL`: Mercure hub endpoints
- `MERCURE_JWT_SECRET`: JWT signing key for Mercure (must be ≥ 32 chars)

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

### Stop-the-line

If tests, builds, or analysis break during a task — stop adding features immediately. Preserve the error output, diagnose the failure, and fix it before continuing. Don't push forward hoping it resolves itself.

### Control scope

If a change reveals deeper issues, fix only what is necessary for correctness. Log follow-ups as TODOs or issues rather than expanding the current task. A focused fix now beats a sprawling refactor that introduces new risk.

### Incremental delivery

Prefer thin vertical slices over big-bang changes. Implement → test → verify → then expand. When feasible, keep changes behind safe defaults or feature flags so partial work doesn't break the main path.

### Deep investigation

When asked to review code or investigate bugs, do a DEEP first pass. Don't produce surface-level findings. Check for false positives before reporting - verify each finding by reading surrounding code. If told to "look deeper", treat it as a signal the first pass was insufficient.

### Bug triage pattern

When given a bug report, follow this order:
1. **Reproduce** reliably (test, script, or minimal steps)
2. **Localize** the failure (which layer: controller, orchestrator, Python agent, LLM, Mercure)
3. **Reduce** to a minimal failing case
4. **Fix** root cause (not symptoms)
5. **Guard** with regression test coverage
6. **Verify** end-to-end against the original report

### Git hygiene

Keep commits atomic and describable — one logical change per commit. Don't mix formatting-only changes with behavioral changes in the same commit. Don't rewrite history unless explicitly asked.
