# Tasks: Token Workflow Sync

**Input**: Design documents from `/specs/015-token-workflow-sync/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: Not explicitly requested. Verification is via post-import API checks (operational, not unit tests).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: Ensure prerequisites are met before any sync operations

- [ ] T001 Verify n8n container (`openclaw-n8n`) is running via `docker ps`
- [ ] T002 Verify n8n API key exists in macOS Keychain via `security find-generic-password -a openclaw -s n8n-api-key -w`
- [ ] T003 Verify `workflows/token-check.json` exists and contains 13 nodes via `jq '.nodes | length' workflows/token-check.json`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Back up current state before any destructive operations

**CRITICAL**: No import can proceed until Static Data is captured

- [ ] T004 Export current Static Data from running token-check workflow via n8n REST API (`GET /api/v1/workflows`) and save to `/tmp/token-check-static-data-backup.json` for operator reference
- [ ] T005 Record current workflow list from n8n API to identify any duplicates (save to `/tmp/n8n-workflow-inventory.json`)

**Checkpoint**: Current state captured — import operations can proceed

---

## Phase 3: User Story 1 - Sync Authoritative Workflow (Priority: P1)

**Goal**: Replace the 9-node workflow in n8n with the authoritative 13-node version from git

**Independent Test**: After `make workflow-import`, query n8n API to confirm token-check workflow has 13 nodes and is active

### Implementation for User Story 1

- [ ] T006 [US1] Run `make workflow-import` to import all workflows from `workflows/` directory into n8n via `scripts/workflow-sync.sh import`
- [ ] T007 [US1] Verify imported token-check workflow has 13 nodes via n8n REST API: `curl -s -H "X-N8N-API-KEY: $KEY" http://localhost:5678/api/v1/workflows | jq '.data[] | select(.name=="token-check") | .nodes | length'`
- [ ] T008 [US1] Verify workflow is active (triggers armed) via n8n REST API: `curl -s -H "X-N8N-API-KEY: $KEY" http://localhost:5678/api/v1/workflows | jq '.data[] | select(.name=="token-check") | .active'`
- [ ] T009 [US1] Verify webhook endpoint responds: `curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:5678/webhook-test/token-check` (expect 401 or HMAC rejection, not 404)

**Checkpoint**: Authoritative 13-node workflow is running and active in n8n

---

## Phase 4: User Story 2 - Preserve Static Data (Priority: P1)

**Goal**: Ensure token grant timestamps and circuit breaker state are correct after import

**Independent Test**: Trigger the workflow manually and verify Static Data is initialized correctly

### Implementation for User Story 2

- [ ] T010 [US2] Trigger one manual execution of the token-check workflow via n8n UI or API to initialize Static Data via the built-in migration code
- [ ] T011 [US2] Verify Static Data was initialized by querying the workflow via API: check that `access_token_granted_at` and `refresh_token_granted_at` are set
- [ ] T012 [US2] Compare initialized timestamps against the pre-import backup (`/tmp/token-check-static-data-backup.json`). If operator knows the actual OAuth grant date, update via n8n UI Static Data editor
- [ ] T013 [US2] Verify legacy `grant_timestamp` field is absent (migration code should have deleted it)

**Checkpoint**: Static Data is correctly initialized with accurate grant timestamps

---

## Phase 5: User Story 3 - Remove Duplicate Workflow (Priority: P2)

**Goal**: Remove any duplicate token-check workflows created by the failed UI import

**Independent Test**: Query n8n API and confirm exactly one workflow with name containing "token-check"

### Implementation for User Story 3

- [ ] T014 [US3] Query n8n API for all workflows and identify duplicates: `curl -s -H "X-N8N-API-KEY: $KEY" http://localhost:5678/api/v1/workflows | jq '.data[] | select(.name | test("token.?check"; "i")) | {id, name, active}'`
- [ ] T015 [US3] If duplicates found, delete each duplicate via n8n REST API: `curl -s -X DELETE -H "X-N8N-API-KEY: $KEY" http://localhost:5678/api/v1/workflows/{duplicate_id}`
- [ ] T016 [US3] Verify exactly one token-check workflow remains after cleanup

**Checkpoint**: No duplicate workflows exist in n8n

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and documentation

- [ ] T017 Run full post-import verification: workflow active, 13 nodes, webhook responsive, Static Data correct, no duplicates
- [ ] T018 Run `make workflow-export --dry-run` to confirm export mechanism still works correctly after import
- [ ] T019 Update `specs/015-token-workflow-sync/quickstart.md` with actual verification results

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — T001, T002, T003 can run in parallel
- **Foundational (Phase 2)**: Depends on Phase 1 — T004, T005 can run in parallel
- **US1 (Phase 3)**: Depends on Phase 2 — T006 must complete before T007-T009
- **US2 (Phase 4)**: Depends on US1 completion (workflow must be imported first)
- **US3 (Phase 5)**: Can run after Phase 2 (independent of US1/US2, but recommended after US1)
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational — no dependencies on other stories
- **User Story 2 (P1)**: Depends on US1 (workflow must be imported before Static Data can be verified)
- **User Story 3 (P2)**: Can start after Foundational — independent of US1/US2, but logically runs after US1

### Parallel Opportunities

- T001, T002, T003 (Setup) can all run in parallel
- T004, T005 (Foundational) can run in parallel
- T007, T008, T009 (US1 verification) can run in parallel after T006
- T014, T015, T016 (US3) can overlap with US2 work

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup verification
2. Complete Phase 2: Static Data backup
3. Complete Phase 3: `make workflow-import` + verify
4. **STOP and VALIDATE**: Confirm 13 nodes, active, webhook responsive
5. This alone resolves the primary divergence problem

### Incremental Delivery

1. Setup + Foundational → State captured
2. US1: Import workflow → Verify → Core problem solved (MVP)
3. US2: Initialize Static Data → Verify timestamps → Expiry calculations correct
4. US3: Remove duplicates → Clean state
5. Polish: Full verification pass

---

## Notes

- This feature is primarily operational (run commands, verify state) rather than code-writing
- T006 (`make workflow-import`) is the single most important task — it resolves the divergence
- Static Data loss on import is expected and handled by the workflow's built-in migration code
- Operator intervention may be needed for T012 if the actual OAuth grant date differs from `now()`
- All verification uses n8n REST API (CLI-first per Constitution X)

## Adversarial Review #3

| Aspect | Finding |
|--------|---------|
| Highest-risk task | T006 (`make workflow-import`) — single destructive operation that overwrites running workflow. Mitigated by T004 pre-import backup and n8n's atomic per-workflow import. |
| Most likely rework | T012 (timestamp comparison) — operator may not know actual OAuth grant date, or backup may show `staticData: null`. Operational decision, not code fix. |
| Security | T015 API key in curl header acceptable for one-time operator command. No secrets written to disk. Duplicate deletion targets specific IDs, not bulk. |
| 3am scenario | N/A — operator-initiated sync, not automated. Post-sync workflow is self-maintaining. |
| 6-month neglect | No drift — one-time import, resulting workflow is self-maintaining with daily schedule and circuit breaker. |

**READY FOR IMPLEMENTATION** — 0 CRITICAL, 0 HIGH findings. All 8 requirements covered by 19 tasks. Constitution gates pass.
