# Code Map

```
the-summit-chatroom/
├── assets/
│   └── controllers/        = Stimulus JS controllers (chat UI interactions)
├── config/
│   ├── packages/            = yaml config for framework, mercure, strands client, twig
│   │   └── test/            = test-environment overrides
│   ├── bundles.php          = registered Symfony bundles
│   ├── reference.php        = configuration reference
│   ├── routes.yaml          = route definitions
│   └── services.yaml        = service container wiring and autowiring
├── docs/                    = project docs (deployment, infrastructure, local dev, terraform, workflow)
├── infra/
│   └── terraform/
│       ├── bootstrap/       = one-time AWS bootstrap (S3 state bucket, DynamoDB lock table)
│       ├── environments/
│       │   └── prod/        = production tfvars, backend config, root module
│       └── modules/         = reusable modules (alb, dns, dynamodb, ecr, ecs, ecs-service, iam, observability, secrets, security, waf, alarms)
├── public/
│   ├── images/              = static images (avatars)
│   ├── favicon.ico
│   └── index.php            = Symfony front controller
├── scripts/
│   ├── installers/          = install/uninstall scripts for AI coding agents (claude, codex, gemini, copilot, grok, kilo, cursor)
│   ├── maintenance/         = repo housekeeping (permissions, Zone.Identifier cleanup)
│   ├── start-dev.sh         = start PHP + Python + Ollama for local dev
│   ├── deploy.sh            = build, push to ECR, redeploy ECS
│   ├── terraform.sh         = terraform plan/apply wrapper
│   ├── health-check-*.sh    = service health checks (local and remote)
│   ├── dependencies-*.sh    = composer/pip install and update
│   └── ...                  = setup, secrets, load testing scripts
├── src/
│   ├── Controller/
│   │   └── ChatController.php           = POST /chat endpoint, GET / renders chatroom
│   ├── Service/
│   │   ├── SummitOrchestrator.php       = sync mode: calls 3 agents sequentially, returns JSON
│   │   └── SummitStreamOrchestrator.php = streaming mode: publishes tokens to Mercure via kernel.terminate
│   └── Kernel.php                       = Symfony kernel
├── strands_agents/                      = Python/FastAPI agent layer
│   ├── agents/
│   │   └── multi_persona_chat.py        = 10 comedy persona system prompts, agent creation
│   ├── api/
│   │   └── server.py                    = FastAPI HTTP layer, Pydantic request/response models
│   ├── persona_objectives.py            = secret objective injection system
│   ├── session.py                       = in-memory conversation history per session
│   ├── requirements.txt                 = Python dependencies
│   └── Dockerfile                       = agent container image
├── templates/
│   └── chatroom.html.twig              = single-page chat UI with inline JS (fetch + EventSource)
├── tests/
│   ├── Integration/
│   │   └── Kernel/
│   │       └── StrandsServiceWiringTest.php    = verifies service container wiring
│   └── Unit/
│       ├── Controller/
│       │   └── ChatControllerTest.php          = controller unit tests
│       └── Service/
│           ├── SummitOrchestratorTest.php       = sync orchestrator tests
│           └── SummitStreamOrchestratorTest.php = streaming orchestrator tests
├── var/                    = logs and cache (gitignored)
├── vendor/                 = composer dependencies (gitignored)
├── .github/
│   ├── instructions/       = AI agent coding guidelines (php, python, twig, shell, code review, commits)
│   └── workflows/
│       └── deploy-prod.yml = GitHub Actions production deployment
├── docker-compose.yml      = 5 services: ollama → ollama-pull → agent → mercure → app
├── Dockerfile              = Symfony app container image
├── composer.json           = PHP dependencies and script aliases (preflight, test, analyse, cs:fix)
├── phpstan.neon            = PHPStan Level 10 config
├── phpunit.xml.dist        = PHPUnit config with coverage
├── phpmd.xml               = PHPMD rules (design, codesize, unusedcode)
├── infection.json5         = mutation testing config
├── .php-cs-fixer.php       = PHP-CS-Fixer PSR-12 rules
├── .env.example            = environment variable template
├── CLAUDE.md               = Claude Code project instructions
├── GEMINI.md               = Gemini CLI project instructions
└── AGENTS.md               = shared AI agent guidelines
```
