# GEMINI.md - The Summit

## Project Overview
**The Summit** is a multi-agent group chat application where AI characters debate user decisions. Three advisors are randomly selected per session from a roster of 10 distinct personas (e.g., Angry Chef, Medieval Knight, Gandalf) to provide diverse, punchy, and often comedic perspectives.

It is designed to demonstrate multi-agent orchestration and "secret objective" injection using the Strands SDK.

### Core Technologies
- **Backend (App):** PHP 8.2+ with Symfony 6.4.
- **Backend (Agent):** Python 3.11+ with FastAPI and Strands SDK (`strands-agents`).
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
    - **Multi-Persona Registry:** Manages 10 distinct personas with specialized system prompts.
    - **Sabotage Engine:** Randomly injects "Secret Objectives" into one agent per round to create comedic contrast and "derail" the debate subtly.
    - **Session Store:** In-memory deduplication of user messages and accumulation of assistant responses to maintain "debate context".
3.  **Mercure:** Acts as the real-time hub, relaying tokens from the PHP app to the browser.
4.  **Ollama:** Optional local container for running LLMs (default: `qwen3:14b`).

### Data Flow (Streaming)
1. Browser POSTs message to `/chat` with a list of 3 selected `personas`.
2. Controller returns immediately with a Mercure topic.
3. After response (`kernel.terminate`), PHP calls the Python agent sequentially for each persona.
4. Python agent:
    - Checks the **Sabotage Engine** for any secret objective for the current persona.
    - Streams tokens from the LLM (Ollama or Bedrock).
5. PHP publishes tokens to Mercure as they arrive.
6. Browser receives tokens via `EventSource` and renders them in real-time.

---

## Building and Running

### Prerequisites
- Docker and Docker Compose.
- ~12GB disk space for the LLM model (if using Ollama).
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
- **Python:** Syntax checks for agent code.

### Agent Orchestration
- **Sequential Order:** Personas respond in the order they are selected.
- **Shared Context:** All agents share the same `session_id` to maintain conversation history.
- **Sabotage Logic:** One agent per round has a 33% chance (configurable) of receiving a secret objective that amplifies their personality or gives them a hidden mission.

### Streaming Pattern
Streaming logic in `ChatController` utilizes Symfony's `kernel.terminate` event. This ensures the browser has time to establish a Mercure subscription before the PHP process starts publishing tokens, preventing "head-of-line" token loss.

---

## Key Files
- `src/Controller/ChatController.php`: Main entry point for chat requests.
- `src/Service/SummitStreamOrchestrator.php`: Logic for relaying tokens to Mercure.
- `strands_agents/agents/multi_persona_chat.py`: Registry of all 10 persona prompts.
- `strands_agents/persona_objectives.py`: The Sabotage Engine and secret objectives database.
- `strands_agents/api/server.py`: FastAPI server implementation and SSE mapping.
- `templates/chatroom.html.twig`: Main UI and frontend streaming implementation.
- `docker-compose.yml`: Defines the local development environment.
