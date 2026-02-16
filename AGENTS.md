# Repository Guidelines

## Project Structure & Module Organization
Core PHP app code lives in `src/` with routes/controllers in `src/Controller/` and orchestration logic in `src/Service/`. Templates are in `templates/` (main UI: `templates/chatroom.html.twig`), and the web entrypoint is `public/index.php`. Unit tests live under `tests/Unit/` and mirror app namespaces (`Controller/`, `Service/`).  
The Python agent lives in `strands_agents/` (`api/server.py` for HTTP, `agents/` for per-persona modules, `session.py` for history). Frontend streaming helpers live in `assets/controllers/`. Runtime wiring is in `config/`, and repository quality scripts are in `scripts/`.

## Build, Test, and Development Commands
```bash
cp .env.example .env              # create local env file
docker compose up --build         # start full stack (app, agent, ollama, mercure)
composer test                     # run PHPUnit suite
composer test:coverage            # generate coverage-html/ and coverage.xml
composer analyse                  # run PHPStan (level 10)
composer cs:check                 # dry-run PHP-CS-Fixer
composer cs:fix                   # apply code style fixes
composer preflight                # run full quality gate script
```
Use `docker compose down` to stop services.

## Coding Style & Naming Conventions
PHP follows PSR-12 with `declare(strict_types=1);`, 4-space indentation, short array syntax, ordered imports, and single quotes (enforced by `.php-cs-fixer.php`). Keep namespaces under `App\` and class/file names in PascalCase (`SummitStreamOrchestrator.php`).  
Tests use `*Test.php` files with descriptive `test...` method names. For Python and JS files, follow the existing style in this repo: clear module-level docs, readable names, and small focused functions.

## Testing Guidelines
Primary framework: PHPUnit 11 (`phpunit.xml.dist`). Place tests in `tests/Unit/...` matching production paths. Prefer deterministic unit tests with mocks for external dependencies (HTTP clients, event dispatching, Mercure).  
Run a focused test during iteration, for example:
```bash
vendor/bin/phpunit tests/Unit/Service/SummitOrchestratorTest.php
```
Coverage checks use an 80% minimum threshold in preflight (`composer preflight:coverage`).

## Commit & Pull Request Guidelines
Commit messages in history use concise imperative subjects (`Add ...`, `Fix ...`, `Refactor ...`, `Enhance ...`). Keep commits scoped to one change and explain non-obvious decisions in the body.  
PRs should include: what changed, why, test evidence (commands run), and screenshots/GIFs for UI updates. Link related issues and call out any `.env` or Docker/config changes explicitly.

## Security & Configuration Tips
Never commit secrets in `.env`. Use `.env.example` as the template. Default provider is local Ollama; Bedrock requires AWS credentials and region/model configuration. Replace development secrets before any production deployment.
