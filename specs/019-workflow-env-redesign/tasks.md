# Tasks: Workflow Environment Variable Redesign

**Input**: Design documents from `/specs/019-workflow-env-redesign/`

## Phase 1: Setup

- [ ] T001 Verify current `$env` usage: `grep -r '\$env' workflows/` — expect 6 matches across 5 files
- [ ] T002 Verify `N8N_BLOCK_ENV_ACCESS_IN_NODE=true` in running container: `docker exec openclaw-n8n env | grep N8N_BLOCK`

---

## Phase 2: User Story 1 - HMAC Authentication (Priority: P1)

**Goal**: hmac-verify reads secret from sub-workflow input, token-check passes it from Static Data

### Implementation

- [ ] T003 [US1] Update `workflows/hmac-verify.json` Code node (Verify HMAC, id: hmac-code): replace `const secret = $env.OPENCLAW_WEBHOOK_SECRET;` with `const inputData = $input.all()[0].json; const secret = inputData.secret;` — read from sub-workflow input instead of env. Update the missing-secret error message to: `"HMAC secret not configured — set webhookSecret in calling workflow Static Data"`
- [ ] T004 [US1] Update `workflows/token-check.json` Execute Workflow node (HMAC Verify, id: hmac-check): add `"secret"` to workflowInputs that reads from a preceding node. Add a Code node before hmac-check that reads `$getWorkflowStaticData('global').webhookSecret` and merges it into the data flow
- [ ] T005 [US1] Test: send an unsigned request to webhook endpoint — should get HMAC rejection (not 404 or crash)

---

## Phase 3: User Story 2 - Alert Delivery (Priority: P1)

**Goal**: HTTP Request nodes use Header Auth credential instead of $env expression

### Implementation

- [ ] T006 [P] [US2] Update `workflows/token-check.json` HTTP Request node (Alert OpenClaw, id: send-alert): remove manual `Authorization` header with `{{ $env.OPENCLAW_HOOK_TOKEN }}`, add credential reference for httpHeaderAuth
- [ ] T007 [P] [US2] Update `workflows/error-handler.json` HTTP Request node: same pattern — remove manual Authorization header, add httpHeaderAuth credential reference
- [ ] T008 [P] [US2] Update `workflows/rate-limit-tracker.json` HTTP Request node: same pattern — remove manual Authorization header, add httpHeaderAuth credential reference
- [ ] T009 [US2] Update `workflows/rate-limit-tracker.json` Code node (Query Executions, id: query-executions): replace `$env.N8N_API_KEY` with `$getWorkflowStaticData('global').n8nApiKey`
- [ ] T010 [US2] Update `workflows/activity-query.json` Code node (Query Activity, id: query-activity): replace `$env.N8N_API_KEY` with `$getWorkflowStaticData('global').n8nApiKey`

---

## Phase 4: User Story 3 - Correct F3 Documentation (Priority: P1)

**Goal**: ASI-MAPPING and TRUST-BOUNDARY-MODEL accurately reflect complete remediation

### Implementation

- [ ] T011 [US3] Update `docs/ASI-MAPPING.md` ASI04 section: note that `=true` is deployed AND workflows redesigned to use credentials/Static Data instead of `$env`. The env access gap is now fully closed.
- [ ] T012 [US3] Update `docs/TRUST-BOUNDARY-MODEL.md` TZ5 section: note the remediation is complete — workflows no longer depend on env access.

---

## Phase 5: Polish & Verification

- [ ] T013 Run `grep -r '\$env' workflows/` — expect zero matches
- [ ] T014 Run `make workflow-import` to deploy updated workflows
- [ ] T015 Operator: create Header Auth credential "OpenClaw Hook Token" in n8n UI
- [ ] T016 Operator: set Static Data in token-check workflow: `webhookSecret` = actual HMAC secret
- [ ] T017 Operator: set Static Data in rate-limit-tracker and activity-query: `n8nApiKey` = n8n API key
- [ ] T018 Test webhook: send HMAC-signed request to token-check — verify success response
- [ ] T019 Test webhook: send unsigned request — verify 401 rejection

---

## Dependencies

- T003 before T004 (hmac-verify must accept input before token-check can pass it)
- T006, T007, T008 can run in parallel (different files)
- T014 after T003-T010 (all workflow edits must be done before import)
- T015-T017 after T014 (credentials must be set after import)

## Adversarial Review #3

| Aspect | Finding |
|--------|---------|
| Highest-risk task | T004 (adding Code node + modifying Execute Workflow inputs in token-check.json) — complex JSON structure manipulation |
| Most likely rework | T006-T008 (Header Auth credential reference format) — n8n credential JSON structure must match exactly |
| Security | Secrets move from env vars to Static Data/credentials — same trust boundary, better isolation |
| 3am scenario | If Static Data is reset (workflow import), HMAC auth returns clear error instead of silent failure |

**READY FOR IMPLEMENTATION** — 0 CRITICAL, 0 HIGH. All 8 requirements covered by 19 tasks.
