# GEMINI.md - The Summit

## Project Overview
**The Summit** is a multi-agent group chat application where three AI advisors-**Analyst**, **Skeptic**, and **Strategist**-debate user decisions. It is designed to demonstrate multi-agent orchestration using the Strands SDK.

### Core Technologies
- **Backend (App):** PHP 8.2+ with Symfony 6.4.
- **Backend (Agent):** Python 3.11+ with FastAPI and Strands SDK.
- **Real-time:** Mercure Hub (SSE) for token-by-token streaming.
- **LLM Provider:** Ollama (Local) or AWS Bedrock.
- **Frontend:** Twig templates with Tailwind CSS and Stimulus/AssetMapper.

---

## Architecture
The system follows a containerized microservices architecture:

1.  **App (Symfony):** Handles the web UI and orchestrates agent calls.
    - `src/Service/SummitOrchestrator`: Synchronous (blocking) sequential calls.
    - `src/Service/SummitStreamOrchestrator`: Asynchronous streaming via Mercure.
2.  **Agent (Python):** A FastAPI server wrapping the Strands SDK.
    - Manages three distinct personas via system prompts.
    - Interfaces with Ollama or AWS Bedrock for inference.
3.  **Mercure:** Acts as the real-time hub, relaying tokens from the PHP app to the browser.
4.  **Ollama:** Optional local container for running LLMs (default: `qwen2.5:14b`).

### Data Flow (Streaming)
1. Browser POSTs message to `/chat`.
2. Controller returns immediately with a Mercure topic.
3. After response (`kernel.terminate`), PHP calls the Python agent.
4. Python agent streams tokens to PHP.
5. PHP publishes tokens to Mercure.
6. Browser receives tokens via `EventSource` and renders them in real-time.

---

## Building and Running

### Prerequisites
- Docker and Docker Compose.
- ~12GB disk space for the LLM model.
- 16GB+ RAM recommended.

### Commands
```bash
# Setup environment
cp .env.example .env

# Start the stack
docker-compose up --build

# Run all quality checks (Preflight)
composer preflight

# Run tests
composer test

# Fix code style
composer cs:fix

# Static analysis
composer analyse
```

---

## Development Conventions

### Quality Gates
The project maintains a high quality bar, enforced by `./scripts/preflight-checks.sh`:
- **PHPStan:** Level 10 (Maximum strictness).
- **Complexity:** Cyclomatic complexity must be <= 20 per method.
- **Testing:** Minimum 80% line coverage for PHP code.
- **Style:** PSR-12/Symfony standards via PHP-CS-Fixer.

### Agent Orchestration
- **Sequential Order:** Analyst (Quantify) -> Skeptic (Challenge) -> Strategist (Synthesize).
- **Shared Context:** All agents share the same `session_id` to maintain conversation history and awareness of previous agents' responses.
- **Persona Routing:** The `persona` metadata sent by the PHP client determines the system prompt used by the Python agent.

### Streaming Pattern
Streaming logic in `ChatController` utilizes Symfony's `kernel.terminate` event. This ensures the browser has time to establish a Mercure subscription before the PHP process starts publishing tokens, preventing "head-of-line" token loss.

---

## Key Files
- `src/Controller/ChatController.php`: Main entry point for chat requests.
- `src/Service/SummitStreamOrchestrator.php`: Logic for relaying tokens to Mercure.
- `strands_agents/agents/`: Per-persona modules (analyst.py, skeptic.py, strategist.py) with system prompts and model routing.
- `templates/chatroom.html.twig`: Main UI and frontend streaming implementation.
- `docker-compose.yml`: Defines the local development environment.
