---
applyTo: '**'
---

# Code Review Guidelines - The Summit

You are reviewing a multi-agent chat application with a PHP/Symfony backend, Python/FastAPI agent layer, and Mercure real-time streaming. Every review comment should account for the cross-layer nature of this project.

## Project Context

- PHP >=8.2, Symfony 6.4, `declare(strict_types=1)` everywhere, PSR-12 formatting
- Namespace: `App\` (src/), `App\Tests\` (tests/)
- PHPStan level 10 - type errors are blockers
- PHP-CS-Fixer enforces: short arrays, single quotes, ordered imports, trailing commas
- Python 3.12+, FastAPI + Pydantic for request/response validation
- Real-time streaming via Mercure (JWT-authenticated SSE)
- Two execution modes: sync (blocking JSON) and streaming (Mercure SSE)
- `blundergoat/strands-client` is a local path dependency at `../strands-php-client`
- 10 comedy personas defined in `strands_agents/agents/multi_persona_chat.py`, 3 randomly selected per session
- Secret objectives system in `strands_agents/persona_objectives.py`

## What to Flag

### Correctness (Blockers)
- Type mismatches or missing return types (PHPStan level 10)
- Breaking changes to the Python agent's Pydantic request/response models without updating PHP callers
- Mercure JWT signing using secrets shorter than 32 characters (HS256 minimum)
- Missing `declare(strict_types=1)` in new PHP files
- Orchestrator changes that break sequential agent deliberation order or session accumulation
- Streaming orchestrator changes that don't handle the `kernel.terminate` lifecycle correctly

### Cross-Layer Consistency (High Priority)
- Python endpoint changes without matching PHP `StrandsClient` call updates
- New environment variables added in one place but not in `.env.example`, `docker-compose.yml`, or `scripts/start-dev.sh`
- Symfony service wiring changes that don't match `config/packages/strands.yaml` agent definitions
- Twig template changes that assume streaming when sync mode is also supported (and vice versa)
- Docker Compose changes that break the service dependency chain (ollama → agent → mercure → app)

### Architecture
- The characters are personas, not separate services — they all hit the same Python endpoint with different `persona` metadata
- `ChatController` is the single entry point; orchestrators handle sequencing — don't add agent logic to the controller
- The single `StrandsClient` is injected via `#[Autowire(service: 'strands.client.summit')]` from `config/packages/strands.yaml` — don't hardcode service references
- Session history lives in Python agent memory (`session.py`) — PHP is stateless between requests
- The sync orchestrator returns a complete response; the streaming orchestrator publishes to Mercure topics — don't mix these patterns
- Secret objectives are injected via `persona_objectives.py` — they append to the system prompt, never replace it

### Style and Convention
- 4-space indentation, single quotes, short array syntax `[]`
- `camelCase` methods/variables, `PascalCase` classes
- Trailing commas in multiline arrays, arguments, and parameters
- `declare(strict_types=1)` at the top of every PHP file
- Ordered imports (alphabetical)

### Security
- No secrets in `.env` committed to git — only dev-safe defaults
- `MERCURE_JWT_SECRET` must be ≥ 32 characters for HS256
- `APP_SECRET` must not be the default value in production
- No raw user input passed to agent prompts without the controller's validation

## What NOT to Flag

- Empty `MERCURE_*` variables in `start-dev.sh` — this is intentional (sync-only mode, no Mercure)
- Python agent using in-memory session storage — this is by design for local dev; DynamoDB is used in production
- `docker-compose.override.yml` not existing — it's optional and gitignored
- Persona names being strings rather than enums — the roster is designed to be easily extended

## Review Checklist for Common PR Types

### Orchestrator Changes
- [ ] Both sync and streaming orchestrators updated consistently
- [ ] Agent ordering and session accumulation preserved (each agent sees prior responses)
- [ ] Error handling doesn't leave Mercure topics in a broken state (streaming mode)
- [ ] PHPUnit tests cover the changed orchestration logic

### Python Agent Changes
- [ ] Pydantic models match what PHP sends/expects
- [ ] Health endpoint still works (`GET /health`)
- [ ] Both `/invoke` and `/stream` endpoints handle the change
- [ ] Persona routing logic still selects correct system prompts
- [ ] Session deduplication not broken
- [ ] Secret objectives system not broken if personas changed

### Docker / Infrastructure Changes
- [ ] Service dependency chain preserved (healthchecks, depends_on)
- [ ] Port mappings consistent with `scripts/start-dev.sh` defaults (8081, 8082, 11434, 3701)
- [ ] Environment variables match between `docker-compose.yml` and `.env.example`
- [ ] Local dev mode (`scripts/start-dev.sh`) still works without Docker

### Frontend (Twig) Changes
- [ ] Both sync and streaming UI paths work
- [ ] EventSource error handling present for streaming mode
- [ ] Graceful degradation when Mercure is unavailable (falls back to sync)
- [ ] No hardcoded URLs — uses Symfony/Twig variables

## Scope and Hygiene

- PRs should be atomic — one logical change. Flag PRs that mix formatting with behavioral changes.
- If a PR reveals deeper issues, the fix should be scoped to the reported problem. Broader refactors belong in follow-up PRs.
- Every PR should include a verification story: what changed, how it was tested, what commands were run.

## Running Verification

```bash
composer test          # PHPUnit
composer analyse       # PHPStan level 10
composer cs:check      # PHP-CS-Fixer dry-run
composer preflight     # All of the above in sequence
```
