# Tasks: Security Hardening Phase 2

**Input**: Design documents from `/specs/012-security-hardening-phase2/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: Not explicitly requested. Verification tasks included as checkpoint tasks within each phase.

**Organization**: Tasks grouped by user story. Each story is independently testable after Phase 2 (Foundational) completes. Phases 1A/1B must be sequential; subsequent phases can be implemented in any order (respecting noted dependencies).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story (US1-US7)
- Exact file paths included in all descriptions

---

## Phase 1A: Expanded Protection Surface — Deploy (US1, Spec Phase A)

**Purpose**: Add all newly identified sensitive files to the protected file list and deploy updated manifest.

- [ ] T001 [US1] Expand `_integrity_protected_file_patterns()` in `scripts/lib/integrity.sh`: add `~/.openclaw/agents/*/models.json` (LLM routing, FR-001), `~/.openclaw/agents/*/.openclaw/workspace-state.json` (session state, FR-002), `.claude/settings.local.json` (development tool permissions, FR-003), `~/.openclaw/openclaw.json.bak*` (old config backups, FR-004), `~/.openclaw/restore-scripts/*` (restore scripts, FR-006), `~/.openclaw/manifest-sequence.json` (rollback counter), `~/.openclaw/enforcement.json` (enforcement config)
- [ ] T002 [US1] Add git hooks neutralization to `scripts/integrity-deploy.sh`: scan `~/.openclaw/agents/*/.git/hooks/` and repo root `.git/hooks/`, remove execute permission (`chmod -x`) on all hook files. Create `~/.openclaw/hooks-allowlist.json` (signed with HMAC, added to protected file list) for operator-declared legitimate hooks — hooks in the allowlist are preserved. Default: empty allowlist (all hooks neutralized). (FR-005)
- [ ] T003 [US1] Add restore script permission tightening to `scripts/integrity-deploy.sh`: change `~/.openclaw/restore-scripts/*` from 755 to 700, add to protected file list with uchg (FR-006)
- [ ] T004 [US1] Add HMAC signing to `scripts/skill-allowlist.sh`: wrap the allowlist JSON in the state-file signing pattern (`integrity_sign_state_file`), update `do_add`, `do_remove` to re-sign after modification. Update `do_check` to verify signature before trusting entries (FR-007, FR-008)
- [ ] T005 [US1] Update `scripts/integrity-verify.sh` `check_skill_allowlist()`: verify allowlist signature via `integrity_verify_state_file` before reading skill entries. Fail (not warn) if signature is invalid or missing (FR-008)
- [ ] T006 [P] [US1] Add TMPDIR validation to `integrity_check_env_vars()` in `scripts/lib/integrity.sh`: verify TMPDIR is unset or points to `/tmp` or `/private/tmp` (FR-035)
- [ ] T007 [US1] Add lib self-verification function to `scripts/lib/integrity.sh`: `_integrity_verify_self()` computes SHA-256 of the library file and compares against manifest. Called by all new scripts created in 012 before sourcing (FR-034). Bootstrap case (no manifest) logs warning.
- [ ] T008 [US1] Add `scripts/integrity-verify.sh` `check_n8n_workflows()` workflow definition files to protected file list (FR-036): add `workflows/linkedin-post.json` and all other workflow files to `_integrity_protected_file_patterns()`

**Checkpoint**: Deploy → verify manifest now includes 65+ files (up from 49). All new files have checksums.

---

## Phase 1B: Expanded Protection Surface — Lock (US1, Spec Phase B)

**Purpose**: Lock all files including newly protected set. Separate from deploy per spec Deployment Sequence.

- [ ] T009 [US1] Add old configuration backup detection to `scripts/integrity-lock.sh`: find `~/.openclaw/openclaw.json.bak*`, lock with uchg (FR-004). Log count of backups locked to audit trail.
- [ ] T010 [US1] Run `make integrity-lock` to lock all files including newly protected set

### Verification

- [ ] T011 [US1] Verification: deploy → verify manifest contains new files (models.json, workspace-state.json, settings.local.json, restore-scripts, bak files) → lock → verify all have uchg flag → attempt modification of newly protected file as non-root → verify "Operation not permitted"
- [ ] T012 [US1] Verification: deploy with git hooks in agent workspace → verify hooks have execute permission removed → verify hooks locked with uchg → verify legitimate hooks (if allowlisted) preserved

**Checkpoint**: US1 complete. All sensitive files locked and manifested.

---

## Phase 2: Hash-Chained Audit Log (US2, Spec Phase C)

**Purpose**: Implement tamper-evident audit logging with hash chain and append-only enforcement.

### Implementation (MUST be in this order)

- [ ] T013 [US2] Verify and update `integrity_audit_log()` base entry schema in `scripts/lib/integrity.sh`: ensure every entry includes ISO-8601 timestamp, action type, operator identity ($SUDO_USER or whoami), process ID, and structured details field (FR-011). Then add `prev_hash` field: compute SHA-256 of the last line in the audit log file (FR-014b). First entry uses `"GENESIS"` as prev_hash. Ensure each entry is single-line JSONL (FR-014)
- [ ] T014 [US2] Add `integrity_verify_audit_chain()` to `scripts/lib/integrity.sh`: walk the log file line-by-line, verify each entry's `prev_hash` matches the SHA-256 of the preceding line. Return count of violations.
- [ ] T015 [US2] Update all operations to include required detail fields in audit log entries: `integrity-lock.sh` (file count, operator — FR-010), `integrity-unlock.sh` (file path, operator — FR-010), `integrity-deploy.sh` (manifest version, file count — FR-010), `integrity-verify.sh` (pass/fail, error count, warning count, specific failures — FR-012), `integrity-monitor.sh` (file path, expected hash, actual hash, delivery status — FR-013), `skill-allowlist.sh` (skill name, content hash — FR-010)
- [ ] T016 [US2] Add audit log write failure detection to `integrity_audit_log()`: if append fails (disk full, permission denied), print error to stderr and attempt to alert operator via alternative channel (FR-009 edge case)
- [ ] T017 [US2] Add `chflags uappnd` setup to `scripts/integrity-deploy.sh`: after first hash-chained log entry is written, set the append-only flag (FR-009). Must run AFTER T018 is deployed. Include ownership fix (chown to $SUDO_USER if running as root)
- [ ] T019 [P] [US2] Document audit log rotation procedure in `specs/012-security-hardening-phase2/quickstart.md`: `sudo chflags nouappnd` → archive → create new log → `sudo chflags uappnd`. Log rotation event to new log.
- [ ] T020 [US2] Add audit log chain verification to `scripts/integrity-verify.sh`: new `check_audit_chain()` function calls `integrity_verify_audit_chain()`, fails if violations found
- [ ] T021 [US2] Add CHK-OPENCLAW-AUDIT-CHAIN check to `scripts/hardening-audit.sh`: verify hash chain integrity, verify uappnd flag is set, report entry count

### Verification

- [ ] T022 [US2] Verification: append entries → verify chain validates → attempt to truncate log → verify "Operation not permitted" → insert a forged entry in the middle → verify chain verification detects the break
- [ ] T023 [US2] Verification: run lock/unlock/deploy/verify/skill-add sequence → verify each generates audit log entry with all required fields (timestamp, action, operator, pid, details, prev_hash)

**Checkpoint**: US2 complete. Audit log is hash-chained and append-only. All privileged operations logged.

---

## Phase 3: Docker and Container Integrity (US3, Spec Phase D)

**Purpose**: Verify orchestration container image and credential set.

- [ ] T024 [US3] Add container image ID capture to `scripts/integrity-deploy.sh`: use `docker inspect --format '{{.Image}}' n8n` to record SHA-256 digest in manifest under `container_image_id` field (FR-016). Also record expected credential names via `docker exec n8n n8n list:credentials --format=json | jq '.[].name'` under `expected_credentials` (FR-017)
- [ ] T025 [US3] Add `check_container_image()` to `scripts/integrity-verify.sh`: verify running container image ID matches manifest's `container_image_id`. Block agent launch on mismatch (FR-015). Gracefully skip with warning if container is not running.
- [ ] T026 [US3] Add `check_container_credentials()` to `scripts/integrity-verify.sh`: enumerate n8n credential names, compare against `expected_credentials` from manifest. Report unexpected credentials as "potential compromise indicator" (FR-017, FR-018)
- [ ] T027 [US3] Enhance `check_n8n_workflows()` in `scripts/integrity-verify.sh`: export workflows from running container via `docker exec n8n n8n export:workflow --all`, compare against version-controlled copies in `workflows/` using jq (ignore metadata: updatedAt, createdAt, versionId). Report specific workflow mismatches. Must run AFTER container image verification passes (US3 acceptance scenario 2)
- [ ] T028 [US3] Add container image monitoring to `scripts/integrity-monitor.sh`: in the heartbeat cycle, check current container image ID against manifest. Alert operator if changed (US3 acceptance scenario 5)
- [ ] T029 [P] [US3] Add CHK-OPENCLAW-CONTAINER-IMAGE and CHK-OPENCLAW-CONTAINER-CREDS checks to `scripts/hardening-audit.sh`

### Verification

- [ ] T030 [US3] Verification: record n8n image ID in manifest → stop n8n → start different image with same name → run integrity-verify → verify image mismatch detected → restore correct image → verify passes
- [ ] T031 [US3] Verification: add unexpected credential to n8n → run integrity-verify → verify unexpected credential flagged as compromise indicator

**Checkpoint**: US3 complete. Container image and credential set verified at startup and continuously.

---

## Phase 4: Browser Session Protection (US4, Spec Phase E)

**Purpose**: Encrypt browser session authentication state at rest.

**Dependencies**: Phase 2 (audit logging for session access events per FR-021)

- [ ] T032 [US4] Create `scripts/session-encrypt.sh` with subcommands: `encrypt` (AES-256-GCM via openssl, key from Keychain service `session-encryption-key`), `decrypt --temp` (decrypt to temporary file, return path), `status` (check if encrypted). Use `security add-generic-password` for key generation if not exists (FR-019, FR-020)
- [ ] T033 [US4] Add secure deletion of plaintext after encryption in `scripts/session-encrypt.sh`: overwrite with random bytes before unlinking (`dd if=/dev/urandom of=<file> bs=1 count=<size> && rm`) (FR-022)
- [ ] T034 [US4] Add session access audit logging to `scripts/session-encrypt.sh`: log decrypt events to integrity audit log with timestamp and calling context (FR-021)
- [ ] T035 [P] [US4] Add CHK-OPENCLAW-SESSION-ENCRYPTED check to `scripts/hardening-audit.sh`: verify storageState file is encrypted (not plaintext JSON), verify encryption key exists in Keychain
- [ ] T036 [P] [US4] Add Makefile targets: `session-encrypt`, `session-decrypt`, `session-status`

### Verification

- [ ] T037 [US4] Verification: encrypt storageState → verify file is not readable as JSON → attempt to read raw bytes → verify encrypted → decrypt to temp → verify usable JSON → verify temp file deleted after use → verify audit log entry for decrypt event

**Checkpoint**: US4 complete. Browser session credentials encrypted at rest.

---

## Phase 5: Output Sanitization (US5, Spec Phase F)

**Purpose**: Validate webhook payloads before they reach external APIs.

**Dependencies**: Phase 1A (workflow files in protected set per FR-036)

- [ ] T038 [US5] Add sanitization Code node to `workflows/linkedin-post.json`: insert after HMAC verification node, before LinkedIn API node. Validates: (1) required fields present with correct types (FR-023), (2) no control characters in content fields — reject null bytes, escape sequences, terminal injection (FR-024), (3) content length within limits: 3000 chars for posts, 1250 for comments (FR-025)
- [ ] T039 [US5] Add rejection logging and operator notification to sanitization node: on validation failure, return structured error with rejection reason, log to audit trail, trigger error-handler workflow for operator notification (FR-026)
- [ ] T040 [P] [US5] Create sanitization test payloads in `specs/012-security-hardening-phase2/test-payloads/`: valid payload, payload with null bytes, payload with escape sequences, oversized payload, payload missing required fields, payload with unexpected fields, payload with wrong types

### Verification

- [ ] T041 [US5] Verification: send each test payload to linkedin-post webhook → verify valid payload passes through → verify all injection payloads rejected with specific error → verify rejection events in audit log → verify operator notified

**Checkpoint**: US5 complete. Webhook payloads sanitized before reaching external APIs.

---

## Phase 6: Manifest Versioning and Rollback Detection (US6, Spec Phase G)

**Purpose**: Detect manifest rollback attacks.

**Dependencies**: Phase 2 (audit logging for rollback events)

- [ ] T042 [US6] Add `manifest_sequence` counter to `integrity_build_manifest()` in `scripts/lib/integrity.sh`: read current sequence from `~/.openclaw/manifest-sequence.json`, increment, include in manifest (FR-027)
- [ ] T043 [US6] Create `~/.openclaw/manifest-sequence.json` signed state file management: `integrity_read_sequence()` reads and verifies signature, `integrity_write_sequence()` writes and signs (FR-029). First deploy initializes sequence to 1.
- [ ] T044 [US6] Add sequence verification to `scripts/integrity-verify.sh`: new `check_manifest_sequence()` function reads last verified sequence from signed state file, compares to manifest sequence, fails if manifest sequence < last verified (FR-028). Log rollback attempt to audit trail.
- [ ] T045 [US6] Add `--force` flag to `scripts/integrity-deploy.sh`: when set, resets sequence counter with audit trail warning (FR-030). Without flag, sequence must only increase.

### Verification

- [ ] T046 [US6] Verification: deploy manifest (seq=1) → deploy again (seq=2) → copy seq=1 manifest back → run integrity-verify → verify rollback detected and agent launch blocked → verify audit log records rollback attempt
- [ ] T047 [US6] Verification: deploy with `--force` → verify sequence resets → verify audit log records the force reset with warning

**Checkpoint**: US6 complete. Manifest rollback attacks detected and blocked.

---

## Phase 7: Audit Enforcement Gate (US7, Spec Phase H)

**Purpose**: Critical audit checks block agent launch.

**Dependencies**: Phase 1A (enforcement.json in protected set), Phase 2 (audit logging for bypass events)

- [ ] T048 [US7] Create `scripts/enforcement-setup.sh`: create `~/.openclaw/enforcement.json` with default enforced checks (sandbox_enabled, manifest_signature, files_locked, allowlist_valid), sign with HMAC (R-008)
- [ ] T049 [US7] Modify `scripts/integrity-verify.sh`: load enforcement config, for each enforced check, change from `warn()` to `fail()` on failure (FR-031). Implement hardcoded minimum set that cannot be disabled: sandbox_enabled, manifest_signature (FR-033).
- [ ] T050 [US7] Add `FORCE=1` bypass to `scripts/integrity-verify.sh`: when set, enforced checks warn instead of fail. Log bypass event to audit trail with operator identity (FR-032)
- [ ] T051 [US7] Add enforcement.json to protected file list and lock with uchg (FR-033)
- [ ] T052 [P] [US7] Add CHK-OPENCLAW-ENFORCEMENT check to `scripts/hardening-audit.sh`: verify enforcement.json exists, is signed, and contains the hardcoded minimum set
- [ ] T053 [P] [US7] Add Makefile targets: `enforcement-setup`, `enforcement-status`

### Verification

- [ ] T054 [US7] Verification: enable enforcement → disable sandbox → run integrity-verify → verify FAILS (not warns) → re-enable sandbox → verify PASSES
- [ ] T055 [US7] Verification: enable enforcement → run with FORCE=1 → verify warns but does not block → verify audit log records bypass event
- [ ] T056 [US7] Verification: attempt to remove sandbox_enabled from enforced checks via enforcement.json edit → verify hardcoded minimum prevents removal

**Checkpoint**: US7 complete. Critical audit checks enforced at startup.

---

## Phase 8: Polish and Cross-Cutting Concerns

**Purpose**: Shellcheck, verification, key rotation, documentation.

- [ ] T057 Run shellcheck on all new/modified scripts: `session-encrypt.sh`, `enforcement-setup.sh`, `lib/integrity.sh`, `integrity-verify.sh`, `integrity-deploy.sh`, `integrity-lock.sh`, `integrity-monitor.sh`, `skill-allowlist.sh`, `hardening-audit.sh` — zero warnings required per Constitution VI
- [ ] T058 Create key rotation script `scripts/integrity-key-rotate.sh`: re-sign all signed artifacts (manifest, lock-state, heartbeat, allowlist, sequence, enforcement) in documented order. Log rotation event to audit trail. Handle interruption gracefully (rollback to old key if incomplete)
- [ ] T059 Full verification script `scripts/integrity-verify-phase2.sh`: automated assertions for all 7 user stories
- [ ] T060 Adversarial testing: state-actor scenarios from ADVERSARIAL-REVIEW-01.md — attempt manifest forgery, grace period exploitation, heartbeat forgery, container replacement, session exfiltration
- [ ] T061 Update `specs/012-security-hardening-phase2/quickstart.md` with verified commands
- [ ] T062 Content notes for LinkedIn: capture findings for social-content inbox

---

## Dependencies and Execution Order

### Phase Dependencies

- **Phase 1A (Deploy)**: No dependencies — start immediately
- **Phase 1B (Lock)**: Depends on Phase 1A
- **Phase 2 (Audit Log)**: Depends on Phase 1A (file list)
- **Phase 3 (Container)**: Depends on Phase 1A (manifest fields)
- **Phase 4 (Session)**: Depends on Phase 2 (audit logging). Code can be written in parallel but deployment must follow Phase 2
- **Phase 5 (Sanitization)**: Depends on Phase 1A (workflow files in protected set)
- **Phase 6 (Versioning)**: Depends on Phase 2 (audit logging)
- **Phase 7 (Enforcement)**: Depends on Phase 1A (config in protected set) + Phase 2 (bypass logging). Deploy LAST per spec Deployment Sequence.
- **Phase 8 (Polish)**: Depends on all previous phases

### Parallel Opportunities

Within each phase, tasks marked [P] can run in parallel. Across phases:

- Phase 3 and Phase 4 code can be written in parallel (independent concerns)
- Phase 5 code can be written in parallel with Phase 3/4 (different files)
- Phase 6 is independent of Phases 3-5

### Implementation Strategy

1. **MVP**: Phase 1A + 1B + Phase 2 = expanded protection + tamper-evident audit log
2. **Security Complete**: Add Phases 3-7 for full hardening
3. **Production Ready**: Phase 8 for polish and adversarial testing
