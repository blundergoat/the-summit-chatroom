---
applyTo: 'strands_agents/**/*.py'
---

# Python Conventions - The Summit Agent

## Language & Framework

- Python 3.12+
- FastAPI for the HTTP layer (`api/server.py`)
- Pydantic v2 for request/response validation
- Strands SDK for agent creation and LLM interaction

## Project Layout

```
strands_agents/
├── api/
│   ├── __init__.py
│   └── server.py              # FastAPI app — /invoke, /stream, /health endpoints
├── agents/
│   ├── __init__.py            # Agent registry — create_agent(), get_personas()
│   └── multi_persona_chat.py  # 10 persona system prompts + PERSONAS dict
├── persona_objectives.py      # Secret objectives system (SabotageEngine)
└── session.py                 # In-memory conversation history (SessionStore)
```

## Style

- 4-space indentation
- Double quotes for docstrings, single or double for other strings (follow surrounding code)
- Type hints on all function signatures: `def create_agent(persona: str) -> Agent:`
- Use `| None` syntax over `Optional[]`: `objective_prompt: str | None = None`
- Module-level docstrings explaining what the file does and how it fits into the system
- Blank line after module docstrings, between top-level definitions, and before `return` in long functions

## Naming

- `snake_case` for functions, methods, variables, and modules
- `PascalCase` for classes and Pydantic models
- `UPPER_SNAKE_CASE` for module-level constants
- Descriptive names — `session_store` not `ss`, `correlation_id` not `cid`

## Architecture Patterns

- **Shared model**: One LLM model instance created at import time in `agents/__init__.py`, shared across all requests
- **Persona routing**: `persona` field in request metadata selects system prompts from the `PERSONAS` dict
- **Session accumulation**: The `SessionStore` deduplicates user messages and accumulates agent responses so later agents see earlier ones
- **Secret objectives**: `SabotageEngine` decides once per round (per `correlation_id`) whether to inject a side mission

## API Contract

The PHP `StrandsClient` sends requests to these endpoints:

- `POST /invoke` — Synchronous: returns `{ "output": { "text": "..." } }`
- `POST /stream` — Streaming: returns SSE events ending with `complete` or `error`
- `GET /health` — Returns `{ "status": "healthy" }`

Request body:
```json
{
  "message": "user question",
  "session_id": "uuid",
  "context": {
    "metadata": {
      "persona": "angry_chef",
      "correlation_id": "uuid",
      "active_personas": ["angry_chef", "gandalf", "ships_cat"]
    }
  }
}
```

Changes to these Pydantic models MUST be coordinated with the PHP `StrandsClient` calls.

## Environment Variables

| Variable | Default | Used by |
|----------|---------|---------|
| `MODEL_PROVIDER` | `ollama` | `agents/__init__.py` |
| `MODEL_ID` | `us.anthropic.claude-sonnet-4-20250514-v1:0` | Bedrock model selection |
| `OLLAMA_HOST` | `http://ollama:11434` | Ollama connection |
| `OLLAMA_MODEL` | `qwen2.5:14b` | Ollama model selection |
| `AWS_DEFAULT_REGION` | `ap-southeast-2` | Bedrock region |

## Validation

```bash
python3 -m py_compile strands_agents/api/server.py
python3 -m py_compile strands_agents/agents/__init__.py
python3 -m py_compile strands_agents/persona_objectives.py
```
