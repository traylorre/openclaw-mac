# Tasks: Workspace Integrity

**Input**: Design documents from `/specs/011-workspace-integrity/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: Not explicitly requested. Verification tasks included as checkpoint tasks within each phase. Phase 7 includes adversarial testing strategy.

**Organization**: Tasks grouped by user story. Each story is independently testable after Phase 2 (Foundational) completes.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story (US1-US5)
- Exact file paths included in all descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create shared library functions and data structures used by all integrity scripts

- [x] T001 Create integrity manifest schema and helper functions in `scripts/lib/integrity.sh`: signed manifest read/write (JSON via jq), HMAC signing via macOS Keychain (`security find-generic-password`), SHA-256 checksum computation, protected file list enumeration (all categories from FR-004)
- [x] T002 Generate and store HMAC manifest signing key in macOS Keychain: `security add-generic-password -a "openclaw" -s "integrity-manifest-key" -w "$(openssl rand -hex 32)"` — separate from the webhook HMAC key
- [x] T003 Define the protected file list as a configuration array in `scripts/lib/integrity.sh` (same file as T001, sequential): workspace files (~/.openclaw/agents/*/SOUL.md, AGENTS.md, TOOLS.md, IDENTITY.md, USER.md, BOOT.md), skill files (*/skills/*/SKILL.md), orchestration files (CLAUDE.md), workflow files (workflows/*.json), scripts (scripts/*.sh), Docker config (scripts/templates/docker-compose.yml, n8n-entrypoint.sh), secrets (scripts/templates/secrets/*.txt), config files (~/.openclaw/openclaw.json, ~/.openclaw/.env, .env)

**Checkpoint**: Shared library ready. All subsequent scripts source `scripts/lib/integrity.sh`.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Integrity manifest creation and signing — required by ALL user stories

**CRITICAL**: No user story work can begin until this phase is complete

- [x] T004 Create `scripts/integrity-deploy.sh`: verify git working tree is clean and on expected branch (FR-006), copy workspace files from repo to agent directories, compute SHA-256 checksums of all protected files (FR-017: verify manifest contains entries for all four categories — workspace, orchestration, workflow, config), record platform runtime version (`openclaw --version`), record content hashes of all installed skills in the manifest alongside file checksums (FR-028), build manifest JSON with all entries, sign manifest with Keychain HMAC key (FR-016), write to `~/.openclaw/manifest.json`
- [x] T005 [P] Create initial `~/.openclaw/skill-allowlist.json` with content hashes of the 5 M3 skills: linkedin-post, linkedin-engage, linkedin-activity, config-update, token-status (FR-026)
- [x] T006 Add `integrity-deploy` target to `Makefile`: wraps `scripts/integrity-deploy.sh`, runs as part of `make agents-setup` post-deployment step

**Checkpoint**: Signed integrity manifest exists with checksums of all ~40 protected files. Skill allowlist populated.

---

## Phase 3: User Story 1 — Filesystem Immutability (Priority: P1) MVP

**Goal**: Protected files are locked against modification by any non-root process. Operator can unlock/lock for intentional edits.

**Independent Test**: Set immutable flag on SOUL.md. Attempt to modify as non-root user. Verify rejection. Unlock, edit, re-lock. Verify manifest updated.

### Implementation

- [x] T007 [US1] Create `scripts/integrity-lock.sh`: iterate all protected files from manifest, verify no symlinks in protected directories (FR-005), set `chflags uchg` on each file (requires `sudo`), update `locked: true` and `locked_at` in manifest, re-sign manifest (FR-003)
- [x] T008 [US1] Create `scripts/integrity-unlock.sh`: accept `--file <path>` argument for single-file unlock, verify file is in the manifest, run `sudo chflags nouchg` on the specified file, record unlock in `~/.openclaw/lock-state.json` with timestamp and 5-minute timeout (FR-023), update manifest `locked: false`
- [x] T009 [P] [US1] Add symlink detection to `scripts/lib/integrity.sh`: function that scans all protected directories for symlinks, returns list of violations. Called by lock, deploy, and audit operations (FR-005)
- [x] T010 [US1] Add `integrity-lock` and `integrity-unlock` targets to `Makefile`: `integrity-lock` requires sudo, `integrity-unlock` requires sudo and `FILE=<path>` argument
- [x] T011 [US1] Extend `make agents-setup` to call `integrity-deploy` and `integrity-lock` as final steps after deploying workspace files

### Verification

- [x] T012 [US1] Verification: deploy and lock workspace files → attempt write to locked agent .md as non-root → verify "Operation not permitted" → unlock → verify edit succeeds → re-lock → verify manifest checksum updated. Also fixed: root-ownership creep in lock-state.json/manifest.json (chown to SUDO_USER after lock)
- [x] T013 [US1] Verification: create a symlink inside a protected directory → run `make integrity-lock` → verify lock refuses with symlink violation error. Also fixed: `integrity_check_symlinks` now scans protected directories with `find -type l` (planted symlinks were invisible to `find -type f`)

**Checkpoint**: US1 complete. All protected files immutable. Lock/unlock workflow operational.

---

## Phase 4: User Story 2 — Agent Sandbox Isolation (Priority: P2)

**Goal**: Agent runs with read-only workspace, restricted tools, workspace-only filesystem access. Extraction agent has zero tools.

**Independent Test**: Start agent in sandbox mode. Attempt to read `~/.openclaw/.env` from agent. Verify denied. Attempt to write to workspace. Verify denied. Run M3 draft→approve→publish flow. Verify it works.

### Implementation

- [x] T014 [US2] Create `scripts/sandbox-setup.sh`: read current `~/.openclaw/openclaw.json`, add sandbox configuration for linkedin-persona agent (`sandbox.mode: "all"`, `sandbox.scope: "agent"`, `sandbox.workspaceAccess: "ro"`, `tools.fs.workspaceOnly: true`, `tools.deny: ["exec", "process", "browser", "apply_patch"]`, `tools.allow: ["read", "web_fetch", "sessions_send"]`), add sandbox configuration for feed-extractor agent (`sandbox.mode: "all"`, `sandbox.scope: "agent"`, `sandbox.workspaceAccess: "none"`, `tools.deny: ["*"]`, `tools.allow: []`), write updated config via jq. Also: atomic writes (mktemp+mv), idempotent upsert, stdout/stderr separation in shell functions
- [x] T015 [P] [US2] Create `scripts/sandbox-teardown.sh`: remove sandbox configuration from both agent entries in `~/.openclaw/openclaw.json`, restore default (unsandboxed) state. Atomic writes to prevent truncation on error
- [x] T016 [US2] Add `sandbox-setup` and `sandbox-teardown` targets to `Makefile` (existed from T006, fixed teardown to point to correct script)
- [x] T017 [US2] Create writable data directory for agent state: `mkdir -p ~/.openclaw/sandboxes/linkedin-persona/data/` (inside sandbox writable area, outside read-only workspace per plan Phase 3), updated BOOT.md and linkedin-post SKILL.md to reference new path for `pending-drafts.json`, sandbox config maps this directory as writable via `writablePaths`
- [x] T017b [US2] Add sandbox configuration check to `scripts/integrity-verify.sh`: verify sandbox.mode is set to "all" for both agents in openclaw.json before launching agent (FR-013) — warn but do not block (sandbox is an independent defense layer). Created initial integrity-verify.sh with sandbox check; T022 will expand with full manifest verification

### Verification

- [ ] T018 [US2] Verification: enable sandbox → start agent → attempt to read `~/.openclaw/.env` via agent prompt → verify access denied
- [ ] T019 [US2] Verification: enable sandbox → start agent → attempt to write to SOUL.md via agent prompt → verify write denied
- [ ] T020 [US2] Verification: enable sandbox → run full M3 draft→approve→publish flow via chat → verify webhook call to n8n succeeds and stub response returns → verify no disruption to operator workflow
- [ ] T021 [US2] Verification: start feed-extractor agent → attempt to invoke any tool → verify rejected

**Checkpoint**: US2 complete. Both agents sandboxed. M3 workflow unaffected.

---

## Phase 5: User Story 3 — Startup Integrity Check and Continuous Monitoring (Priority: P3)

**Goal**: Agent refuses to start on tampered files. Background service monitors for changes in real time.

**Independent Test**: Modify a protected file with sudo. Attempt to start agent. Verify startup blocked. Start monitoring. Modify file with sudo. Verify alert within 60 seconds.

### Startup Integrity Check

- [x] T022 [US3] Create `scripts/integrity-verify.sh`: 9 check functions — manifest HMAC signature (FR-016), SHA-256 checksums for all protected files (FR-014), symlink detection (FR-005), env var validation (FR-019), platform version match (FR-020), pending-drafts.json schema validation with field/key/length checks (FR-012), monitoring heartbeat (FR-024), sandbox config (FR-013, warn only), n8n workflow comparison (FR-018). Exec into agent on pass (FR-014 TOCTOU elimination). Errors block, warnings don't.
- [x] T023 [US3] Add `integrity-verify` target to `Makefile`: already existed from T006, confirmed working with --dry-run
- [x] T024 [P] [US3] Create n8n workflow structural comparison in `scripts/integrity-verify.sh`: exports from n8n via `docker exec`, normalizes with jq (strips updatedAt, createdAt, versionId, id, meta), compares against workflows/*.json. Gracefully skips when n8n not running.

### Continuous Monitoring

- [x] T025 [US3] Create `scripts/integrity-monitor.sh`: fswatch-based watcher for all manifest files, checksum verification on change (FR-025), grace period suppression via lock-state.json (FR-023), alert delivery via n8n webhook (FR-022), heartbeat every 30s (FR-024). Includes --install/--uninstall/--status subcommands for LaunchAgent lifecycle.
- [x] T026 [P] [US3] Create `scripts/templates/com.openclaw.integrity-monitor.plist`: LaunchAgent with KeepAlive, RunAtLoad, template variables for script path/repo root/log dir. Homebrew PATH included for fswatch.
- [x] T027 [US3] Add `monitor-setup`, `monitor-teardown`, `monitor-status` targets to `Makefile`: already existed from T006, confirmed working
- [x] T028 [US3] Implement alert suppression cleanup: `integrity-lock.sh` already calls `integrity_clear_lockstate` (Phase 3). Monitor's `handle_change` checks `integrity_is_in_grace_period` and expired entries (past 5-minute timeout) return false.

### Verification

- [x] T029 [US3] Verification: tamper with agent .md via root (chflags nouchg → append → chflags uchg) → run integrity-verify → detected checksum mismatch on specific file, exited non-zero (5/5 assertions passed)
- [ ] T030 [US3] Verification: start monitoring → modify a protected file with sudo → verify operator receives alert within 60 seconds (deferred — requires running monitor)
- [ ] T031 [US3] Verification: unlock SOUL.md → modify it → verify NO alert during grace period → re-lock → verify alert suppression cleared (deferred — requires running monitor)
- [ ] T032 [US3] Verification: kill monitoring service → verify launchd restarts it → verify heartbeat resumes (deferred — requires running monitor)

**Checkpoint**: US3 complete. Agent refuses to start on tampering. Real-time monitoring with alerts.

---

## Phase 6: User Story 4 — Supply Chain Controls (Priority: P4)

**Goal**: Operator-controlled skill allowlist. Skills identified by content hash. Unapproved skills rejected.

**Independent Test**: Add a skill to allowlist. Verify it loads. Add an unapproved skill file. Verify agent rejects it.

### Implementation

- [x] T033 [US4] Create `scripts/skill-allowlist.sh`: 4 subcommands (add, remove, check, list). Atomic writes, idempotent add/update, searches both repo and deployed agent skills. Detected real hash mismatch on linkedin-post from T017 path change — re-approved.
- [x] T034 [US4] Integrate skill allowlist check into `scripts/integrity-verify.sh`: check_skill_allowlist() enumerates all SKILL.md files (repo + deployed), computes content hashes, verifies against allowlist (FR-027). Fails startup on unapproved or mismatched skills (FR-029). Added as critical check.
- [x] T035 [US4] Add `skillallow-add` and `skillallow-remove` targets to `Makefile`: already existed from T006, confirmed working
### Verification

- [x] T037 [US4] Verification: all 5 M3 skills pass → fake evil-skill detected as UNAPPROVED by both skill-allowlist.sh and integrity-verify.sh (7/7 assertions passed). pipefail bug found and fixed in test harness.
- [x] T038 [US4] Verification: appended malicious content to token-status SKILL.md → HASH MISMATCH detected → restored → all pass. Simulates T-PERSIST-002 skill update poisoning.
- [x] T039 [US4] Verification: platform version check exists in integrity-verify (check_platform_version). On dev machine returns "unknown" vs manifest version — correctly flagged as mismatch.

**Checkpoint**: US4 complete. Supply chain controls operational. Skills identified by content hash.

---

## Phase 7: User Story 5 — Audit Extensions (Priority: P5)

**Goal**: Security audit covers all new controls with PASS/FAIL/WARN output.

**Independent Test**: Run `make audit`. Verify all 8 new checks pass. Disable one control. Verify corresponding check fails.

### Implementation

- [x] T040 [P] [US5] Add CHK-OPENCLAW-INTEGRITY-LOCK: checks uchg flag on all manifest files. Reports PASS/WARN (partial)/FAIL with list of unlocked files.
- [x] T041 [P] [US5] Add CHK-OPENCLAW-INTEGRITY-MANIFEST: verifies HMAC signature + SHA-256 checksums for all protected files. Reports count of mismatches.
- [x] T042 [P] [US5] Add CHK-OPENCLAW-SANDBOX-MODE: checks sandbox.mode = "all" for both agents. Names missing agents in FAIL message.
- [x] T043 [P] [US5] Add CHK-OPENCLAW-SANDBOX-TOOLS: verifies persona deny list configured, extractor allow=0.
- [x] T044 [P] [US5] Add CHK-OPENCLAW-MONITOR-STATUS: checks LaunchAgent loaded + heartbeat freshness (<60s).
- [x] T045 [P] [US5] Add CHK-OPENCLAW-SKILLALLOW: scans repo + deployed skills, verifies content hashes against allowlist.
- [x] T046 [P] [US5] Add CHK-OPENCLAW-SYMLINK: delegates to integrity_check_symlinks for full directory-level scan.
- [x] T047 [P] [US5] Add CHK-OPENCLAW-PLATFORM-VERSION: compares openclaw --version against manifest recorded version.

### Verification

- [x] T048 [US5] Verification: ran `make audit --section "Workspace Integrity"` — all 8 checks execute correctly. 4 PASS, 3 FAIL (expected: no monitor, stale manifest, openclaw not in PATH), 1 WARN (2 files unlocked for editing).
- [x] T049 [US5] Verification: sandbox-mode check confirmed working — PASS when sandbox configured, FAIL names the missing agents. Tested via setup/teardown round-trip earlier.
- [ ] T050 [US5] Verification: monitor FAIL confirmed (not installed). PASS verification deferred — requires running monitor.
- [x] T051 [US5] Verification: INTEGRITY-LOCK correctly reports WARN with specific unlocked file paths (hardening-audit.sh and integrity-verify.sh shown in output).

**Checkpoint**: US5 complete. All controls auditable.

---

## Phase 8: Polish and Cross-Cutting Concerns

**Purpose**: Testing, documentation, final validation

- [x] T052 Run shellcheck on all 9 scripts — zero warnings. Fixed SC2064 (trap expansion), SC2034 (library constants), SC2010 (ls -lO for BSD flags).
- [ ] T053 Update quickstart.md: deferred — verify all commands end-to-end on Mac Mini
- [ ] T054 Adversarial testing: immutability bypass via sudo chflags nouchg + modify + uchg — deferred (requires running monitor, already proven in T029 via integrity-verify checksum detection)
- [x] T055 Adversarial testing: symlink from writable data dir to protected workspace — initially MISSED (writable dir not in scan list). Fixed by adding `~/.openclaw/sandboxes` to `integrity_check_symlinks` protected_dirs. Now detected.
- [x] T056 Adversarial testing: DYLD_INSERT_LIBRARIES crashes process before check runs (dyld terminates). NODE_OPTIONS=--require=/tmp/evil.js correctly detected and blocks startup. Both env vars checked.
- [ ] T057 Full end-to-end: deferred — requires running agent + n8n + monitor
- [x] T058 Update ROADMAP.md: added M3.5 section documenting workspace integrity as pulled-forward milestone, updated M3 security checklist, updated architecture diagram

---

## Dependencies and Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 — manifest library must be ready
- **Phase 3 (US1)**: Depends on Phase 2 — needs manifest with checksums
- **Phase 4 (US2)**: Can start after Phase 2 — independent of US1 (sandbox doesn't require immutable flags)
- **Phase 5 (US3)**: Depends on Phase 2 — needs manifest for checksum verification. Monitoring (US3b) can start after US1 (watches locked files).
- **Phase 6 (US4)**: Depends on Phase 2 — needs manifest for hash storage
- **Phase 7 (US5)**: Depends on Phases 3-6 — audits all controls
- **Phase 8 (Polish)**: Depends on all prior phases

### User Story Dependencies

- **US1 (P1)**: Can start after Phase 2. **No dependencies on other stories.** MVP deliverable.
- **US2 (P2)**: Can start after Phase 2. Independent of US1. **Critical: test M3 workflow in sandbox before proceeding.**
- **US3 (P3)**: Startup check depends on Phase 2. Monitoring benefits from US1 (locked files to watch) but can start independently.
- **US4 (P4)**: Can start after Phase 2. Independent of US1-US3.
- **US5 (P5)**: Depends on US1-US4 (audits their controls).

### Within Each User Story

- Shared library functions (Phase 1) before scripts
- Scripts before Makefile targets
- Makefile targets before verification tasks
- Verification tasks are the last items in each phase

### Parallel Opportunities

**Phase 1**: T001 and T003 can run in parallel (T003 is a sub-function of T001's file)
**Phase 2**: T005 can run in parallel with T004 (different files)
**Phase 3 (US1)**: T009 can run in parallel with T007/T008 (library function)
**Phase 4 (US2)**: T015 can run in parallel with T014 (setup vs teardown scripts)
**Phase 5 (US3)**: T024 and T026 can run in parallel with T025 (different scripts)
**Phase 6 (US4)**: No parallelism — sequential dependency (allowlist → verify integration → Makefile)
**Phase 7 (US5)**: T040-T047 can ALL run in parallel (separate audit check functions)

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (shared library)
2. Complete Phase 2: Foundational (manifest creation)
3. Complete Phase 3: User Story 1 (filesystem immutability)
4. **STOP and VALIDATE**: Protected files are immutable. Checksums verified.
5. This alone prevents the most common attack vector (agent workspace tampering)

### Incremental Delivery

1. Setup + Foundational → Manifest ready
2. US1 → Immutable files → **Deploy/Demo** (MVP: tamper prevention)
3. US2 → Sandbox isolation → **Deploy/Demo** (blast radius containment)
4. US3 → Startup check + monitoring → **Deploy/Demo** (detection layer)
5. US4 → Skill allowlist → **Deploy/Demo** (supply chain defense)
6. US5 → Audit extensions → **Deploy/Demo** (verification layer)
7. Polish → Production-ready

### Key Decision Points

- **After US1**: Can an operator lock and unlock files without friction? Is the Makefile workflow natural?
- **After US2**: Does the M3 webhook workflow work in sandbox? If not, adjust tool allowlist before proceeding.
- **After US3**: Does the monitoring service run reliably? Are there false positives during normal operation?
- **After US5**: Does the full audit pass? Are all 8 new checks green?

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks
- [Story] label maps task to specific user story for traceability
- All scripts source `scripts/lib/integrity.sh` and `scripts/lib/common.sh`
- All scripts follow Constitution VI (set -euo pipefail, shellcheck clean, idempotent, colored output)
- FR numbers from spec.md referenced in task descriptions for traceability
- 58 total tasks across 8 phases (T017b added for FR-013 coverage, T036 removed as duplicate of T004)
