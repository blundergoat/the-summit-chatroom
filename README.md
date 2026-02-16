# The Summit

Multi-agent group chat where three AI advisors - **Analyst**, **Skeptic**, and **Strategist** - debate your decisions. Built with [strands-php-client](https://github.com/blundergoat/strands-client) + [strands-symfony-bundle](https://github.com/blundergoat/strands-bundle).

*"Your decision, cross-examined by three minds that disagree on purpose."*

## How It Works

You ask a question. Three agents respond in sequence:

1. **Analyst** (blue) - quantifies the landscape with data, baselines, and confidence bands
2. **Skeptic** (amber) - challenges assumptions, demands evidence, runs premortems
3. **Strategist** (green) - synthesises both into an actionable recommendation

Each agent sees the full conversation history, including what the other agents said. The Skeptic challenges the Analyst's numbers. The Strategist weighs both perspectives. It's a real debate, not three disconnected monologues.

## Quick Start

```bash
git clone https://github.com/blundergoat/the-summit-chatroom.git
cd the-summit-chatroom
cp .env.example .env
docker-compose up --build
```

Open http://localhost:8080 and ask a question.

The first run downloads the LLM model (~9GB for `qwen2.5:14b`). Subsequent starts are fast.

## Requirements

- Docker and Docker Compose
- ~12GB free disk space (model + containers)
- GPU with 16GB+ VRAM recommended (runs on CPU too, just slower)

No cloud accounts or API keys needed for local development.

## Architecture

```
docker-compose up
  |
  ├── ollama        (local LLM server - no cloud needed)
  ├── agent         (Python - Strands SDK + FastAPI + persona routing)
  ├── app           (PHP - Symfony + strands-php-client + Twig chat UI)
  └── mercure       (real-time streaming via SSE)
```

The PHP app talks to the Python agent over HTTP. The agent talks to Ollama (or AWS Bedrock) for inference. Mercure handles real-time token streaming to the browser.

## Model Provider

Defaults to **Ollama** (local, free). Switch to **AWS Bedrock** by editing `.env`:

```bash
# Local (default)
MODEL_PROVIDER=ollama
OLLAMA_MODEL=qwen2.5:14b

# AWS Bedrock
MODEL_PROVIDER=bedrock
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
```

## Modes

**Sync mode** (Milestone 4) - User sends message, waits ~30s, gets all three responses at once. Works now.

**Streaming mode** (Milestone 5) - Agents stream token-by-token via Mercure. Text appears in real-time like a group chat. Requires Mercure container.

## Project Structure

```
the-summit-chatroom/
├── strands_agents/         # Python agent
│   ├── Dockerfile          # Agent container build
│   ├── requirements.txt    # Python dependencies
│   └── multi_persona_chat/ # Agent source code (server.py, agent.py, session.py)
├── app/                    # Symfony app container
│   ├── src/Controller/     # ChatController
│   ├── src/Service/        # Orchestrators (sync + streaming)
│   └── templates/          # Twig chat UI
├── docker-compose.yml
└── .env.example
```

## Deploying to AWS

This repo includes a reference architecture for deploying the Python agent to AWS - see [`03-strands-agent-stack.md`](03-strands-agent-stack.md) for the full spec (Fargate, API Gateway, DynamoDB sessions). Most users will bring their own infrastructure; the spec is a guide, not a required dependency.

## Related Repos

| Repo | What |
|------|------|
| [strands-php-client](https://github.com/blundergoat/strands-client) | PHP client library for Strands agents (on Packagist) |
| [strands-symfony-bundle](https://github.com/blundergoat/strands-bundle) | Symfony bundle for DI wiring |

## License

Apache 2.0
