# Implementation Plan: Fledge Milestone 1 — Gateway Live

**Branch**: `007-n8n-gateway` | **Date**: 2026-03-17 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/007-n8n-gateway/spec.md`

## Summary

Deploy n8n as the orchestration backbone for the Fledge platform.
The hardened Docker Compose already exists (`scripts/templates/`).
This milestone adds: (1) version pinning, (2) a hello-world webhook
workflow, (3) Bearer token auth via n8n's native Header Auth
credential, (4) an intent-based gateway routing workflow using the
Switch node, and (5) verification that the hardening audit still
passes with n8n running.

## Technical Context

**Language/Version**: n8n workflow JSON (declarative), Bash 5.x (setup scripts)
**Primary Dependencies**: n8n v2.13.0 (Docker), Colima, Docker CLI
**Storage**: Docker volume `n8n_data` (workflows, credentials, execution logs)
**Testing**: Manual curl commands + hardening-audit.sh regression check
**Target Platform**: macOS Sonoma/Tahoe on Apple Silicon and Intel Mac Mini
**Project Type**: Infrastructure deployment + workflow configuration
**Performance Goals**: N/A (single operator, localhost traffic only)
**Constraints**: Localhost-only binding, non-root container, no Docker socket
**Scale/Scope**: 1 gateway workflow, 1 hello-world sub-workflow, 3 n8n nodes
per workflow maximum

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Documentation-Is-the-Product | PASS | Setup instructions added to repo |
| II. Threat-Model Driven | PASS | Bearer auth gates webhook against unauthorized access; localhost binding prevents network exposure |
| III. Free-First | PASS | n8n community edition (open-source, free) |
| IV. Cite Canonical Sources | PASS | n8n official docs for webhook/Switch/auth patterns |
| V. Every Recommendation Is Verifiable | PASS | curl commands verify each capability; audit script verifies security posture |
| VI. Bash Scripts Are Infrastructure | PASS | Setup script follows existing patterns (set -euo pipefail, shellcheck) |
| VII. Defense in Depth | PASS | Auth (prevent) + audit regression check (detect) + localhost binding (prevent) |
| VIII. Explicit Over Clever | PASS | Step-by-step setup, copy-pasteable commands |
| IX. Markdown Quality Gate | PASS | CI lint + pre-commit hook enforced |
| X. CLI-First | PASS | All setup via docker compose, curl, environment variables |

**Gate result**: PASS — no violations.

## Project Structure

### Documentation (this feature)

```text
specs/007-n8n-gateway/
├── plan.md              # This file
├── research.md          # Phase 0: n8n patterns and decisions
├── data-model.md        # Phase 1: workflow entities
├── quickstart.md        # Phase 1: setup and test guide
├── contracts/           # Phase 1: webhook API contract
│   └── gateway-webhook.md
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
scripts/templates/
├── docker-compose.yml       # MODIFY: pin n8n version tag
├── n8n-entrypoint.sh        # EXISTING: no changes needed
└── .env.example             # NEW: environment variable template

n8n/workflows/
├── gateway.json             # NEW: gateway webhook + Switch routing
└── hello-world.json         # NEW: hello-world sub-workflow
```

**Structure Decision**: n8n workflows are exported as JSON and
committed to `n8n/workflows/`. This enables git-tracked workflow
versioning. The operator imports them via `n8n import:workflow`
or the n8n UI after first start.

## Design Decisions

### D1: n8n native Header Auth (not custom IF node)

**Decision**: Use n8n's built-in Webhook node Authentication →
Header Auth credential for Bearer token validation.

**Rationale**: The Webhook node natively supports Header Auth with
name=`Authorization` and value=`Bearer <token>`. n8n rejects
unauthenticated requests before the workflow runs. No custom IF
node needed, which means fewer nodes, less attack surface, and
auth enforcement that can't be accidentally bypassed by workflow
edits.

**Alternatives rejected**:
- IF node checking Authorization header: fragile, bypassable, more
  nodes to maintain
- Basic Auth: less standard for API-to-API communication
- JWT Auth: overkill for localhost single-operator setup

### D2: Switch node for intent routing (Rules mode)

**Decision**: Use the Switch node in Routing Rules mode with string
equality comparisons on `{{ $json.body.intent }}`.

**Rationale**: Each intent maps to a numbered output connected to
a sub-workflow trigger. Adding a new intent means adding one rule
and one connection. The Fallback Output handles unknown intents
(returns 400 with valid intent list).

**Alternatives rejected**:
- Expression mode (index-based): harder to read, error-prone
- Separate webhook per intent: violates the single-entry-point
  pattern, harder to secure (auth on every webhook)
- Execute Workflow node: adds complexity for simple routing

### D3: Workflow JSON in git (not n8n CLI export cron)

**Decision**: Manually export workflow JSON after changes and commit
to `n8n/workflows/`. Import during initial setup.

**Rationale**: A cron-based export adds infrastructure complexity
for a single-operator system. Manual export after deliberate changes
is sufficient and keeps the repo as the single source of truth.

**Alternatives rejected**:
- Cron export to git: premature automation for 2 workflows
- n8n API-based backup: requires enabling the API (currently disabled
  per hardening config)

### D4: Version pin to n8n 2.13.0

**Decision**: Pin Docker image to `n8nio/n8n:2.13.0`.

**Rationale**: n8n 2.0 introduced breaking changes (Dec 2025). The
`:latest` tag risks pulling a breaking update on `docker compose pull`.
Pinning to a known-good version prevents surprises. Update process:
change the tag, pull, restart, verify.

### D5: .env.example for auth token (not Docker secret)

**Decision**: Store the gateway Bearer token in a `.env` file loaded
by Docker Compose. Provide a `.env.example` template.

**Rationale**: The token is used by n8n's credential system, not by
the container's environment variables. n8n stores credentials
encrypted in its SQLite database. The `.env` file provides the
initial token value for the n8n Header Auth credential setup. The
`.env` file is gitignored; `.env.example` is committed with a
placeholder.

## Complexity Tracking

> No constitution violations — this section is empty.
