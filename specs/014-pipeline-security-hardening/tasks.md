# Tasks: Pipeline Security Hardening

**Input**: Design documents from `/specs/014-pipeline-security-hardening/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md

**Tests**: Integration tests included (test-phase5-integration.sh pattern per existing codebase convention).

**Organization**: Tasks grouped by user story. Each story is independently testable after Phase 2 (Foundational) completes.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story (US1-US6)
- Exact file paths included in all descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create CVE registry data file and library functions shared by all user stories

- [x] T001 Create `data/cve-registry.json` with known CVEs for n8n (7 CVEs), OpenClaw (8 CVEs), and Ollama (if any). Each entry: `{cve_id, cvss_score, severity, component, affected_versions, fixed_version, description, source_url, date_added}` per data-model.md
- [x] T002 Create `scripts/lib/cve-registry.sh` with functions: `cve_load_registry()` loads JSON, `cve_check_version()` compares installed version against affected_versions using semver, `cve_report_component()` outputs PASS/FAIL with CVE details. Follow Constitution VI (set -euo pipefail, shellcheck clean)
- [x] T003 [P] Create `docs/SENSITIVE-FILE-INVENTORY.md` with complete inventory of 14+ sensitive files per research.md R-009. Each entry: path, risk level, protection type, expected state, ADV reference

**Checkpoint**: CVE registry populated, lookup library ready, sensitive file inventory documented.

---

## Phase 2: Foundational (Verify Existing + Fill Gaps)

**Purpose**: Verify ADV-002/ADV-004 fixes already implemented in lib/integrity.sh are working correctly, create `data/` directory, and fill coverage gaps for FR-004, FR-020, FR-022

**CRITICAL**: No user story work can begin until this phase is complete

- [x] T004 Create `data/` directory with `.gitkeep`. Verify `scripts/lib/integrity.sh` already implements HMAC-signed lock-state (lines 557-620, `integrity_sign_state_file`/`integrity_verify_state_file`) addressing ADV-002. Run `make integrity-unlock` then `make integrity-lock` and verify lock-state.json contains `_signature` field
- [x] T005 Verify `scripts/lib/integrity.sh` already implements HMAC-signed heartbeat (lines 765-806, `integrity_write_heartbeat` calls `integrity_sign_state_file`) addressing ADV-004. Stop and restart the monitor and verify heartbeat contains `_signature` field
- [x] T006 Verify `scripts/integrity-verify.sh` already calls `integrity_verify_state_file` for lock-state and heartbeat in the verification cascade. Run `integrity-verify.sh --dry-run` and confirm signature verification output
- [x] T007 Verify `scripts/lib/integrity.sh` already implements `integrity_check_env_vars()` (line 641) covering all 7 dangerous variables per FR-023. Confirm the function checks: DYLD_INSERT_LIBRARIES, DYLD_FRAMEWORK_PATH, DYLD_LIBRARY_PATH, NODE_OPTIONS, LD_PRELOAD, HOME, TMPDIR
- [x] T008 Add n8n image digest recording to `scripts/integrity-deploy.sh`: capture `docker inspect --format='{{index .RepoDigests 0}}' openclaw-n8n` and store as `n8n_image_digest` in manifest.json. Addresses FR-004
- [x] T009 Verify `scripts/templates/docker-compose.yml` already uses Docker secrets for n8n encryption key (line 10-11: `secrets:` section, line 49-50: `secrets:` mount). If not using Docker secrets pattern, migrate. Addresses FR-022
- [x] T010 Verify `scripts/templates/docker-compose.yml` already has `NODES_EXCLUDE` configuration (line 76). Confirm it includes executeCommand, ssh, localFileTrigger at minimum. Add any missing entries. Addresses FR-020

**Checkpoint**: ADV-002 and ADV-004 confirmed working. data/ directory created. n8n image digest captured. Docker secrets and NODES_EXCLUDE verified.

---

## Phase 3: User Story 1 — Operator Verifies Pipeline Security Posture (Priority: P1) MVP

**Goal**: Single-command security verification covering CVEs, container hardening, HMAC consistency, and sensitive file protections.

**Independent Test**: Run `make audit` and confirm CVE checks report PASS for current pinned versions. Change a version string and confirm FAIL with CVE details.

- [x] T011 [P] [US1] Add `check_cve_n8n()` to `scripts/hardening-audit.sh`: query running n8n container version via `docker exec`, look up in CVE registry, report PASS/FAIL with CVE numbers and CVSS scores
- [x] T012 [P] [US1] Add `check_cve_openclaw()` to `scripts/hardening-audit.sh`: read OpenClaw version via `openclaw --version`, look up in CVE registry, report PASS/FAIL
- [x] T013 [P] [US1] Add `check_cve_ollama()` to `scripts/hardening-audit.sh`: read Ollama version via `ollama --version`, look up in CVE registry, report PASS/FAIL. Also verify model digest matches manifest expected value
- [x] T014 [US1] Add `check_hmac_secret_consistency()` to `scripts/hardening-audit.sh`: compute SHA-256 hash of `.env` HMAC secret and `~/.openclaw/.env` HMAC secret, compare hashes (never expose raw secrets), report PASS/FAIL
- [x] T015 [US1] Add `check_container_hardening_full()` to `scripts/hardening-audit.sh`: verify read-only rootfs (`docker inspect --format '{{.HostConfig.ReadonlyRootfs}}'`), non-root user, all caps dropped, no-new-privileges, localhost-only port binding — consolidating existing checks into a single defense-layer-aware check
- [x] T016 [US1] Wire all new US1 checks into the `run_checks_pipeline_security()` section of `scripts/hardening-audit.sh` with `run_check` calls. Also wire `integrity_check_env_vars()` (already implemented in lib/integrity.sh) into the audit run list
- [x] T017 [US1] Extend `scripts/integrity-deploy.sh`: capture Ollama model digest via `ollama show <model> --digest` and store in manifest.json as `ollama_model_digest`
- [x] T018 [US1] End-to-end verification: run `make audit` → confirm all CVE checks report PASS for n8n 2.13.0, OpenClaw 2026.3.13, and Ollama current version. Confirm HMAC consistency check passes

**Checkpoint**: US1 complete. `make audit` covers CVE verification, container hardening, and HMAC consistency. Single command, < 60 seconds.

---

## Phase 4: User Story 2 — Operator Hardens Sensitive File Protections (Priority: P2)

**Goal**: Audit verifies all 14+ sensitive files have correct protections. ADV-002 and ADV-004 remediated.

**Independent Test**: Run `make audit` and confirm all CHK-SENSITIVE-FILE-* checks pass. Clear uchg on one file and confirm FAIL.

- [x] T019 [P] [US2] Add `check_sensitive_file_protections()` to `scripts/hardening-audit.sh`: iterate the sensitive file inventory, verify each file's permissions, immutability flags, and HMAC signatures match expected state. Report per-file PASS/FAIL. Implementation notes: (1) Must guard `integrity_verify_state_file()` calls with `_INTEGRITY_INIT_OK` check; report SKIP if Keychain unavailable. (2) Must glob `workflows/*.json` dynamically rather than assuming count. (3) Must include `container-security-config.json` and `container-verify-state.json`. (4) Must include `integrity-audit.log` (mode 600 check only, no HMAC)
- [x] T020 [P] [US2] Add `check_env_gitignore()` to `scripts/hardening-audit.sh`: verify `.env` at repo root is listed in `.gitignore` and has mode 600. Verify `~/.openclaw/.env` has mode 600
- [x] T021 [P] [US2] Add `check_lock_state_signed()` to `scripts/hardening-audit.sh`: call `integrity_verify_state_file()` for lock-state.json (existing function in lib/integrity.sh), report PASS/FAIL. Must guard with `_INTEGRITY_INIT_OK` check; report SKIP if Keychain unavailable
- [x] T022 [P] [US2] Add `check_heartbeat_signed()` to `scripts/hardening-audit.sh`: call `integrity_verify_state_file()` for heartbeat (existing function in lib/integrity.sh), report PASS/FAIL. Must guard with `_INTEGRITY_INIT_OK` check; report SKIP if Keychain unavailable
- [x] T023 [US2] Wire all US2 checks into the `§14: Pipeline Security Hardening (014)` section of `main()` in `scripts/hardening-audit.sh`, after the existing `check_pipeline_container_hardening` call (line 3171)
- [ ] T024 [US2] End-to-end verification: run `make audit` → confirm all 14+ sensitive files pass. Clear uchg on SOUL.md → confirm FAIL. Re-lock → confirm PASS

**Checkpoint**: US2 complete. All sensitive files verified. ADV-002 (lock-state unsigned) and ADV-004 (heartbeat unsigned) are closed.

---

## Phase 5: User Story 3 — Operator Maps Threats to OWASP ASI Controls (Priority: P3)

**Goal**: ASI mapping document complete. Audit checks verify at least one control per ASI risk.

**Independent Test**: Review `docs/ASI-MAPPING.md` and confirm all 10 ASI risks mapped. Run `make audit` and confirm ASI-related checks pass.

- [x] T025 [US3] Create `docs/ASI-MAPPING.md` with all 10 OWASP ASI risks mapped per research.md R-005. Each risk: ID, name, pipeline controls, verification method (audit check name), residual risk, residual severity, remediation milestone. Include FR-026 (LLM compromise) and FR-027 (binary integrity) as documented residual risks. Include FR-019 (N8N_BLOCK_ENV_ACCESS trade-off) under ASI04 residual risk. Include note that ASI01-ASI10 are local identifiers mapped to the official OWASP Top 10 for Agentic Applications categories. Implementation notes: (1) For any residual risk rated 'high' or above, include a remediation roadmap with target milestone per acceptance scenario 5. (2) ASI06 must be documented as partially applicable (SQLite conversation history + n8n Static Data are persistent memory surfaces), not marked 'not applicable'. (3) ASI09 must be labeled as 'process control' with CHK-OPENCLAW-SANDBOX-MODE as technical proxy. (4) Include MITRE ATLAS technique cross-references where available from R-007
- [x] T026 [US3] Add `check_asi_controls()` to `scripts/hardening-audit.sh`: for each ASI risk, verify at least one control is active. Map to existing checks where possible (e.g., ASI03 → CHK-OPENCLAW-CREDS, ASI07 → CHK-OPENCLAW-WEBHOOK-AUTH). Report per-ASI PASS/FAIL. Implementation notes: (1) Handle SKIP propagation: if all sub-checks for an ASI risk return SKIP, the ASI risk reports SKIP. WARN from a sub-check counts as PASS (documented trade-off). (2) For ASI10, use CHK-OPENCLAW-MONITOR-STATUS as the M3 check; behavioral baseline is a Phase 6 enhancement. (3) For ASI06, verify SQLite DB permissions if file exists, otherwise SKIP. (4) For ASI09, map to CHK-OPENCLAW-SANDBOX-MODE as technical proxy. (5) Use associative array mapping ASI_ID → [check_functions] for systematic verification
- [ ] T027 [US3] End-to-end verification: review ASI mapping → confirm 10/10 risks covered. Run `make audit` → confirm ASI control checks pass

**Checkpoint**: US3 complete. OWASP ASI Top 10 fully mapped with verified controls.

---

## Phase 6: User Story 5 — Operator Configures Defense-in-Depth Controls (Priority: P5)

**Goal**: Five defense layers independently verifiable. Behavioral baseline established.

**Independent Test**: Run `make audit` and confirm all 5 defense layers report healthy. Stop the monitor and confirm Detect layer reports degraded.

- [x] T028 [P] [US5] Add `check_defense_layer_prevent()` to `scripts/hardening-audit.sh`: verify credential isolation (CHK-OPENCLAW-CREDS), HMAC auth (CHK-OPENCLAW-WEBHOOK-AUTH), workspace immutability (CHK-OPENCLAW-INTEGRITY-LOCK), sandbox mode (CHK-OPENCLAW-SANDBOX-MODE). Aggregation rules: any sub-check FAIL → layer FAIL; all SKIP → layer SKIP; any WARN or known partial (e.g., ADV-001 Keychain gap) → layer WARN; all PASS → layer PASS. Use WARN for PARTIAL status (no PARTIAL in report_result). For sub-check delegation, create local helper that calls existing check functions and captures their report_result output status
- [x] T029 [P] [US5] Add `check_defense_layer_contain()` to `scripts/hardening-audit.sh`: verify Docker isolation (read-only FS, non-root, dropped caps), OpenClaw sandbox (ro workspace, tool deny lists), dangerous node exclusion (NODES_EXCLUDE). Aggregation rules: any sub-check FAIL → layer FAIL; all SKIP → layer SKIP; any WARN → layer WARN; all PASS → layer PASS
- [x] T030 [P] [US5] Add `check_defense_layer_detect()` to `scripts/hardening-audit.sh`: verify pre-launch attestation (integrity-verify.sh exists and runs), continuous monitoring (monitor heartbeat fresh), behavioral baseline (baseline file exists). Aggregation rules: same as T028. If behavioral-baseline.json does not exist, that sub-check reports WARN (not FAIL) with remediation "Run integrity-deploy.sh to establish baseline"
- [x] T031 [P] [US5] Add `check_defense_layer_respond()` to `scripts/hardening-audit.sh`: verify alert delivery (webhook callback configured in openclaw.json), audit logging (make audit --json produces output), manual remediation (make integrity-lock target exists). Aggregation rules: same as T028
- [x] T032 [P] [US5] Add `check_defense_layer_recover()` to `scripts/hardening-audit.sh`: verify credential rotation procedure documented (docs/DEPENDENCY-UPDATE-PROCEDURE.md exists), manifest re-baseline (make integrity-deploy works), dependency rollback (rollback section in update procedure). Aggregation rules: same as T028. Note: Recover layer is documentation-verified by design; runtime enforcement is not feasible for operator-driven recovery procedures. If docs/DEPENDENCY-UPDATE-PROCEDURE.md does not exist (created in Phase 7 T037), report WARN
- [x] T033 [US5] Create wrapper function `check_pipeline_env_vars()` in `scripts/hardening-audit.sh` that calls `integrity_check_env_vars()` (lib/integrity.sh line 641), captures the return code, and calls `report_result` with ID `CHK-PIPELINE-ENV-VARS`, section `Pipeline Security`, status PASS (rc=0) or FAIL (rc=1). Then add `run_check check_pipeline_env_vars` to the S14 section. Note: `integrity_check_env_vars()` uses `log_error`/return-code pattern, NOT `report_result` — a wrapper is required for audit output
- [x] T034 [US5] Implement behavioral baseline in `scripts/integrity-verify.sh` (comparison) and `scripts/integrity-deploy.sh` (baseline creation). Use n8n REST API endpoint `GET http://localhost:5678/api/v1/executions?limit=250&status=success`. On first run (no baseline file), create `~/.openclaw/behavioral-baseline.json` and report WARN "baseline established, comparison deferred to next run." On subsequent runs, compare current frequency against baseline. WARN if deviation exceeds 200%. If n8n not running or API key missing, report SKIP. Use existing credential-safe curl pattern from integrity-verify.sh. Set `skill_invocation_frequency` to null in initial baseline (deferred until OpenClaw agent produces skill invocation logs)
- [x] T035 [US5] Add section comment `# S14.2: Defense-in-Depth Layers (014 US5)` after the existing S14 pipeline security checks in `main()`, then add `run_check` calls for: `check_defense_layer_prevent`, `check_defense_layer_contain`, `check_defense_layer_detect`, `check_defense_layer_respond`, `check_defense_layer_recover`, `check_pipeline_env_vars`
- [ ] T036 [US5] End-to-end verification: run `make audit` → confirm all 5 layers report healthy. Stop monitor → confirm Detect layer FAIL. Restart → confirm recovery. Expected 3am behavior: when all services stopped, Contain layer reports SKIP, Detect layer reports WARN (stale heartbeat + no baseline), Prevent layer reports PASS/WARN (file-based checks pass, service-based checks SKIP), Respond/Recover layers report PASS (documentation checks)

**Checkpoint**: US5 complete. Five defense layers verified. Behavioral baseline established. Environment variables validated.

---

## Phase 7: User Story 4 — Operator Updates Dependencies (Priority: P4)

**Goal**: Documented update/rollback procedures for n8n, OpenClaw, Ollama.

**Independent Test**: Follow the n8n update procedure end-to-end. Confirm manifest updated. Confirm rollback works.

- [ ] T037 [US4] Create `docs/DEPENDENCY-UPDATE-PROCEDURE.md` with procedures for n8n (pull image, restart, re-baseline), OpenClaw (version check, upgrade, verify CVEs), and Ollama (pull model, verify digest). Each procedure: pre-update check, update command, post-update verification, rollback steps, post-rollback CVE check
- [ ] T038 [US4] Create `docs/TRUST-BOUNDARY-MODEL.md` with 5 trust zones per research.md R-008. Each zone: component, trust anchor, known gap (ADV reference), remediation roadmap. Include ToIP TEA mapping section per FR-025 (VID, TSP, did:peer concepts)
- [ ] T039 [US4] End-to-end verification: follow n8n update procedure → confirm manifest updated with new image digest → run `make audit` → confirm CVE check reports PASS for new version

**Checkpoint**: US4 complete. Update procedures documented and tested.

---

## Phase 8: User Story 6 — Operator Manages LinkedIn Token Lifecycle (Priority: P6)

**Goal**: Automated token refresh, refresh token expiry alerting.

**Independent Test**: Simulate day-53 grant timestamp. Confirm refresh triggers. Confirm alert on refresh token approaching expiry.

- [ ] T040 [US6] Update `workflows/token-check.json`: add dual-token tracking in Workflow Static Data — store both `access_token_granted_at` and `refresh_token_granted_at` timestamps. Compute days remaining for each. Existing 60-day access token logic is preserved; add 365-day refresh token tracking alongside it
- [ ] T041 [US6] Update `workflows/token-check.json`: add HTTP Request node for automated refresh — when access token has ≤7 days remaining, POST to `https://www.linkedin.com/oauth/v2/accessToken` with `grant_type=refresh_token`, `refresh_token` from n8n credential store, `client_id` and `client_secret` from OAuth credential. Parse response and update `access_token_granted_at` in Static Data. Handle errors: invalid_grant (refresh token revoked) → alert operator; network error → retry once then alert
- [ ] T042 [US6] Update `workflows/token-check.json`: add refresh token expiry monitoring — compute days remaining on 365-day refresh token. When ≤30 days remaining, POST refresh token expiry alert to OpenClaw inbound hook per contracts/n8n-to-openclaw-hooks.md. When refresh token has expired, POST critical alert with manual re-authorization instructions
- [ ] T043 [US6] Update `specs/010-linkedin-automation/research.md` R-006: correct the LinkedIn refresh token information. Note that consumer apps with `w_member_social` now support programmatic refresh tokens (365-day TTL). Reference: Microsoft Learn LinkedIn API documentation. Also update FR-016 rate limit note per research R-004 (rate limits are unpublished, must be determined empirically)
- [ ] T044 [US6] Update `specs/010-linkedin-automation/spec.md` Credential Lifecycle State entity: change from "60-day expiry, manual re-auth" to "60-day access token + 365-day refresh token, automated refresh"
- [ ] T045 [US6] End-to-end verification: set access_token_granted_at to 53 days ago in n8n Static Data → trigger token-check → verify refresh HTTP request logged → verify new access_token_granted_at stored → verify refresh_token_granted_at unchanged

**Checkpoint**: US6 complete. Token refresh automated. 010 spec corrected.

---

## Phase 9: Integration Tests + Polish

**Purpose**: End-to-end validation, shellcheck, documentation quality

- [ ] T046 Create `scripts/test-phase5-integration.sh` with integration tests for all new audit checks. Test pattern: for each check, set up passing state → verify PASS, then set up failing state → verify FAIL. At minimum: CVE checks (3), HMAC consistency (1), sensitive file protections (1), lock-state signed (1), heartbeat signed (1), defense layers (5), env vars (1), behavioral baseline (1). Total: ~14 tests
- [ ] T047 Run `shellcheck` on all modified scripts: `scripts/hardening-audit.sh`, `scripts/lib/cve-registry.sh`, `scripts/lib/integrity.sh`, `scripts/integrity-verify.sh`, `scripts/integrity-deploy.sh`, `scripts/test-phase5-integration.sh` — zero warnings required per Constitution VI
- [ ] T048 Run `make audit` full suite — verify zero FAIL across all checks (existing 84 + new pipeline security checks)
- [ ] T049 [P] Update `ROADMAP.md`: add note about 014 completion in M3 section
- [ ] T050 Validate `specs/014-pipeline-security-hardening/quickstart.md` end-to-end on actual Mac Mini

---

## Dependencies and Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 — HMAC-signing requires CVE registry library pattern
- **Phase 3 (US1)**: Depends on Phase 2 — CVE checks use cve-registry.sh
- **Phase 4 (US2)**: Depends on Phase 2 — sensitive file checks use HMAC verification from Phase 2
- **Phase 5 (US3)**: Depends on Phase 3 — ASI mapping references CVE verification checks
- **Phase 6 (US5)**: Depends on Phase 4 — defense layers reference sensitive file checks
- **Phase 7 (US4)**: Depends on Phase 1 — update procedures reference CVE registry
- **Phase 8 (US6)**: Independent of other phases after Phase 1
- **Phase 9 (Polish)**: Depends on all prior phases

### User Story Dependencies

- **US1 (P1)**: Can start after Phase 2. **No dependencies on other stories.** MVP deliverable.
- **US2 (P2)**: Can start after Phase 2. Independent of US1.
- **US3 (P3)**: Best after US1 (ASI mapping references CVE checks). Can be started in parallel if needed.
- **US5 (P5)**: Best after US2 (defense layers reference sensitive file checks). Can be started in parallel if needed.
- **US4 (P4)**: Can start after Phase 1. Largely documentation — independent of audit code.
- **US6 (P6)**: Can start after Phase 1. Independent of all other stories (n8n workflow changes only).

### Within Each User Story

- Audit check functions before wiring into run list
- Wiring before end-to-end verification
- Core implementation before verification tasks

### Parallel Opportunities

**Phase 1**: T001, T002, T003 can all run in parallel (different files)
**Phase 3 (US1)**: T011, T012, T013 can run in parallel (different check functions)
**Phase 4 (US2)**: T019, T020, T021, T022 can run in parallel (different check functions)
**Phase 6 (US5)**: T028, T029, T030, T031, T032 can run in parallel (different defense layer checks)
**Phase 7 + Phase 8**: Can run in parallel (docs vs workflow changes)

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (CVE registry, library)
2. Complete Phase 2: Foundational (HMAC-sign lock-state + heartbeat)
3. Complete Phase 3: User Story 1 (CVE verification + container hardening)
4. **STOP and VALIDATE**: `make audit` includes CVE checks, reports PASS
5. This is a functional security verification system

### Incremental Delivery

1. Setup + Foundational → Infrastructure ready
2. US1 → CVE verification operational → **Validate** (MVP)
3. US2 → Sensitive file hardening → **Validate**
4. US3 → ASI mapping complete → **Validate** (compliance artifact)
5. US5 → Defense-in-depth verified → **Validate**
6. US4 → Update procedures documented → **Validate**
7. US6 → Token refresh automated → **Validate**
8. Polish → Production-ready

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks
- [Story] label maps task to specific user story for traceability
- All new audit checks follow existing hardening-audit.sh patterns (report_result, colored output)
- All new integrity functions follow existing lib/integrity.sh patterns (atomic writes, HMAC signing)
- Constitution VI: all scripts must pass shellcheck with zero warnings
- Constitution V: every check must be verifiable via terminal command
- 50 total tasks across 9 phases
- Phase 2 tasks verify existing implementations (ADV-002, ADV-004, env vars) rather than re-implementing
- US6 token refresh broken into 3 implementation sub-tasks (tracking, refresh HTTP, expiry monitoring)
