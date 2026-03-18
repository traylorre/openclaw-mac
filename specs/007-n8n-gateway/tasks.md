# Tasks: Fledge Milestone 1 — Gateway Live

**Input**: Design documents from `/specs/007-n8n-gateway/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Not requested.

**Organization**: Tasks grouped by user story. The existing Docker
Compose is already hardened; this milestone is primarily n8n workflow
configuration and documentation.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to

---

## Phase 1: Setup (Infrastructure)

**Purpose**: Pin n8n version, create environment template, verify
n8n starts and is reachable.

- [x] T001 Pin n8n image from `n8nio/n8n:latest` to `n8nio/n8n:2.13.0` in scripts/templates/docker-compose.yml
- [x] T002 [P] Create scripts/templates/.env.example with GATEWAY_BEARER_TOKEN placeholder and generation instructions
- [x] T003 [P] Add .env to .gitignore in scripts/templates/ to prevent token leakage
- [x] T004 Create n8n/workflows/ directory at repo root for workflow JSON files
- [x] T005 Start n8n with `docker compose up -d` from scripts/templates/ and verify it responds on localhost:5678

**Checkpoint**: n8n is running in Docker, pinned to a specific version,
with persistent volume. No workflows configured yet.

---

## Phase 2: User Story 1 — Hello World Webhook (Priority: P1)

**Goal**: A POST to `/webhook/hello-world` returns a JSON response
echoing the body.

**Independent Test**: `curl -X POST http://localhost:5678/webhook/hello-world -H "Content-Type: application/json" -d '{"test": true}'`
returns 200 with echoed body.

- [x] T006 [US1] Build hello-world workflow in n8n editor: Webhook node (POST, path: hello-world, Response Mode: "Using Respond to Webhook Node") → Set node (build response JSON with status + echoed body) → Respond to Webhook node (200, JSON)
- [x] T007 [US1] Activate the hello-world workflow and test with curl from terminal
- [x] T008 [US1] Export hello-world workflow as JSON and save to n8n/workflows/hello-world.json

**Checkpoint**: Hello world works. n8n is alive and reachable.

---

## Phase 3: User Story 2 — Bearer Auth Gate (Priority: P1)

**Goal**: Unauthenticated requests get 401. Authenticated requests
proceed to the workflow.

**Independent Test**: `curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:5678/webhook/hello-world -d '{}'`
returns 401.

- [x] T009 [US2] Create Header Auth credential in n8n: name `gateway-bearer-token`, header `Authorization`, value `Bearer <token from .env>`
- [x] T010 [US2] Update hello-world workflow Webhook node to require Header Auth credential `gateway-bearer-token`
- [x] T011 [US2] Test: request without token returns 401, request with correct token returns 200
- [x] T012 [US2] Export updated hello-world workflow JSON to n8n/workflows/hello-world.json (overwrite)

**Checkpoint**: Auth gate works. No unauthenticated access possible.

---

## Phase 4: User Story 3 — Intent-Based Routing (Priority: P2)

**Goal**: A single `/webhook/gateway` URL routes by `intent` field
to different sub-workflows.

**Independent Test**: POST with `{"intent": "hello"}` returns hello
response. POST with `{"intent": "unknown"}` returns 400 with
valid_intents list.

- [x] T013 [US3] Build gateway workflow in n8n editor: Webhook node (POST, path: gateway, Header Auth, Response Mode: "Using Respond to Webhook Node")
- [x] T014 [US3] Add IF node after Webhook to check `{{ $json.body.intent }}` exists — if missing, route to error Respond to Webhook node (400, "Missing required field: intent", valid_intents array)
- [x] T015 [US3] Add Switch node (Routing Rules mode) after IF node: rule `{{ $json.body.intent }}` equals "hello" → output 0, Fallback Output → error response
- [x] T016 [US3] Connect Switch output 0 ("hello") to a Set node that builds the hello response (reuse logic from hello-world workflow) → Respond to Webhook node (200)
- [x] T017 [US3] Connect Switch Fallback Output to a Set node that builds error response with unknown intent name and valid_intents array → Respond to Webhook node (400)
- [x] T018 [US3] Test all three paths: valid intent returns 200, unknown intent returns 400 with valid_intents, missing intent returns 400 with error message
- [x] T019 [US3] Export gateway workflow as JSON and save to n8n/workflows/gateway.json

**Checkpoint**: Single gateway URL routes by intent. Adding a new
intent means adding one Switch rule and one output connection.

---

## Phase 5: User Story 4 — Hardening Audit Passes (Priority: P2)

**Goal**: All previously-passing audit checks still pass with n8n
running.

**Independent Test**: `sudo bash scripts/hardening-audit.sh --json`
shows zero new FAIL results.

- [x] T020 [US4] Run `sudo bash scripts/hardening-audit.sh --json` with n8n container running and capture results
- [x] T021 [US4] Verify container isolation: non-root user, no privileged mode, no Docker socket mount via `docker inspect`
- [x] T022 [US4] Verify localhost-only binding: `lsof -i :5678 -sTCP:LISTEN` shows 127.0.0.1 only
- [x] T023 [US4] Compare FAIL count to pre-n8n baseline — document any discrepancies and resolve

**Checkpoint**: Security posture maintained. Gateway is production-ready.

---

## Phase 6: Polish & Documentation

**Purpose**: Setup documentation, workflow import instructions, cleanup.

- [x] T024 [P] Add n8n gateway setup section to GETTING-STARTED.md with step-by-step instructions referencing quickstart.md
- [x] T025 [P] Add n8n gateway setup section to GETTING-STARTED-INTEL.md (same content as T024)
- [x] T026 Update ROADMAP.md to check off Milestone 1 items as completed
- [x] T027 Run markdownlint on all modified files and fix any errors

---

## Dependencies & Execution Order

### Phase Dependencies

```text
Phase 1: Setup ─── no dependencies, start immediately
    │
    ├── Phase 2: US1 (P1) ─── depends on Phase 1 (n8n must be running)
    │       │
    │       └── Phase 3: US2 (P1) ─── depends on Phase 2 (needs hello-world workflow to add auth)
    │               │
    │               └── Phase 4: US3 (P2) ─── depends on Phase 3 (gateway reuses auth credential)
    │
    ├── Phase 5: US4 (P2) ─── depends on Phase 1 only (audit runs independently)
    │
    └── Phase 6: Polish ─── depends on Phases 2-5
```

### Parallel Opportunities

```text
Phase 1:
  T002 and T003 are [P] — different files

After Phase 3 (US2) completes:
  Phase 4 (US3 gateway) and Phase 5 (US4 audit) can run in parallel

Phase 6:
  T024 and T025 are [P] — different files
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2)

1. Complete Phase 1: Setup (n8n running)
2. Complete Phase 2: US1 (hello world webhook)
3. Complete Phase 3: US2 (Bearer auth)
4. **STOP and VALIDATE**: curl with and without auth token
5. This is deployable — authenticated webhook works

### Incremental Delivery

1. Phase 1 → n8n running, pinned, persistent
2. Phase 2 (US1) → hello world proves the wire
3. Phase 3 (US2) → auth gate secures access
4. Phase 4 (US3) → gateway routing centralizes entry
5. Phase 5 (US4) → audit confirms security posture
6. Phase 6 → documentation complete, milestone tagged

### Requirement Coverage

| Requirement | Task(s) | Story |
|-------------|---------|-------|
| FR-001 (Docker Compose + Colima) | T001, T005 | Setup |
| FR-002 (version pin) | T001 | Setup |
| FR-003 (localhost binding) | T022 | US4 |
| FR-004 (persistent volume) | T005 | Setup |
| FR-005 (hello-world webhook) | T006-T008 | US1 |
| FR-006 (Bearer auth via env var) | T002, T009 | Setup + US2 |
| FR-007 (401 for unauth) | T010-T011 | US2 |
| FR-008 (intent routing) | T013-T016 | US3 |
| FR-009 (400 for unknown intent) | T014, T017 | US3 |
| FR-010 (no audit regressions) | T020, T023 | US4 |
| FR-011 (non-root, no privileged) | T021 | US4 |
| FR-012 (reproducible setup) | T024-T025 | Polish |
| FR-013 (restart policy) | T001 | Setup (already in compose) |

---

## Notes

- Most tasks are n8n UI work (building workflows), not code
- The Docker Compose is already hardened — only the version pin changes
- Workflow JSON exports are the git-tracked artifacts
- Credentials (Header Auth) are in n8n's encrypted store, not in JSON
- After implementation, export workflows and commit JSON to n8n/workflows/
