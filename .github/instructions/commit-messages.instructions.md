---
applyTo: '**'
---

# Commit Message Guidelines

## Purpose
Rules for generating commit messages (used by Copilot's "Generate Commit Message" feature and during code reviews that include commits).

## Format

```
<type>(<scope>): <subject>

<body>
```

### Subject Line
- **Type** (required): `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `style`, `ci`
- **Scope** (optional): the area affected — e.g., `orchestrator`, `agent`, `chat`, `streaming`, `personas`, `objectives`, `docker`, `config`, `terraform`, `scripts`
- **Subject** (required): imperative mood, lowercase, no period, max 72 chars
- If the branch or PR references a GitHub issue, prefix the subject with `#<number> ` (e.g., `#5 add verification endpoint`)

### Body
- Always include a body with 2-5 bullet points explaining **what changed and why**
- Each bullet should be a concrete change, not a vague summary
- Reference specific files, classes, endpoints, or tools when relevant
- Mention cross-layer impacts (e.g., "Python response contract changed, PHP client updated to match")

## Examples

Good:
```
feat(agent): add MODEL_ID loading to start-dev.sh for Bedrock support

- Add env_default MODEL_ID "" to load from .env with other Bedrock vars
- Add conditional export in the Bedrock exports block
- Without this, the Python agent ignores MODEL_ID set in .env during local dev
```

Good:
```
fix(chat): wire has_objective through full streaming pipeline

- Add has_objective to Python InvokeResponse and build_complete_event
- PHP SummitStreamOrchestrator reads hasObjective from StreamEvent complete
- Frontend shows red ring on avatar when persona had a secret objective
- Update ChatControllerTest and SummitOrchestratorTest assertions
```

Good:
```
refactor(scripts): parallel agent + Mercure startup in start-dev.sh

- Launch Python agent and Mercure Docker container concurrently
- Replace sequential health checks with single interleaved polling loop
- Add 5-second cleanup timeout with force-kill to prevent hanging on Ctrl+C
- Saves 2-5 seconds per startup
```

Bad (too vague):
```
Update AI agent guidelines and project documentation
```

Bad (no body):
```
feat: add verification to file summariser
```

Bad (generic fluff):
```
Enhance dev script and improve configuration handling
```

## Priorities
- Be specific about what changed — name the files, classes, endpoints, or tools
- Explain the "why" when it isn't obvious from the diff
- Mention cross-layer changes explicitly (PHP + Python + frontend)
- Keep the subject line scannable; put detail in the body

## Guardrails
- Never generate a commit message that is just a single generic sentence
- Never use phrases like "update code", "improve functionality", "various changes", "enhance documentation"
- If changes span multiple features, consider whether they should be separate commits
