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

- [ ] T001 Create integrity manifest schema and helper functions in `scripts/lib/integrity.sh`: signed manifest read/write (JSON via jq), HMAC signing via macOS Keychain (`security find-generic-password`), SHA-256 checksum computation, protected file list enumeration (all categories from FR-004)
- [ ] T002 Generate and store HMAC manifest signing key in macOS Keychain: `security add-generic-password -a "openclaw" -s "integrity-manifest-key" -w "$(openssl rand -hex 32)"` — separate from the webhook HMAC key
- [ ] T003 Define the protected file list as a configuration array in `scripts/lib/integrity.sh` (same file as T001, sequential): workspace files (~/.openclaw/agents/*/SOUL.md, AGENTS.md, TOOLS.md, IDENTITY.md, USER.md, BOOT.md), skill files (*/skills/*/SKILL.md), orchestration files (CLAUDE.md), workflow files (workflows/*.json), scripts (scripts/*.sh), Docker config (scripts/templates/docker-compose.yml, n8n-entrypoint.sh), secrets (scripts/templates/secrets/*.txt), config files (~/.openclaw/openclaw.json, ~/.openclaw/.env, .env)

**Checkpoint**: Shared library ready. All subsequent scripts source `scripts/lib/integrity.sh`.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Integrity manifest creation and signing — required by ALL user stories

**CRITICAL**: No user story work can begin until this phase is complete

- [ ] T004 Create `scripts/integrity-deploy.sh`: verify git working tree is clean and on expected branch (FR-006), copy workspace files from repo to agent directories, compute SHA-256 checksums of all protected files (FR-017: verify manifest contains entries for all four categories — workspace, orchestration, workflow, config), record platform runtime version (`openclaw --version`), record content hashes of all installed skills in the manifest alongside file checksums (FR-028), build manifest JSON with all entries, sign manifest with Keychain HMAC key (FR-016), write to `~/.openclaw/manifest.json`
- [ ] T005 [P] Create initial `~/.openclaw/skill-allowlist.json` with content hashes of the 5 M3 skills: linkedin-post, linkedin-engage, linkedin-activity, config-update, token-status (FR-026)
- [ ] T006 Add `integrity-deploy` target to `Makefile`: wraps `scripts/integrity-deploy.sh`, runs as part of `make agents-setup` post-deployment step

**Checkpoint**: Signed integrity manifest exists with checksums of all ~40 protected files. Skill allowlist populated.

---

## Phase 3: User Story 1 — Filesystem Immutability (Priority: P1) MVP

**Goal**: Protected files are locked against modification by any non-root process. Operator can unlock/lock for intentional edits.

**Independent Test**: Set immutable flag on SOUL.md. Attempt to modify as non-root user. Verify rejection. Unlock, edit, re-lock. Verify manifest updated.

### Implementation

- [ ] T007 [US1] Create `scripts/integrity-lock.sh`: iterate all protected files from manifest, verify no symlinks in protected directories (FR-005), set `chflags uchg` on each file (requires `sudo`), update `locked: true` and `locked_at` in manifest, re-sign manifest (FR-003)
- [ ] T008 [US1] Create `scripts/integrity-unlock.sh`: accept `--file <path>` argument for single-file unlock, verify file is in the manifest, run `sudo chflags nouchg` on the specified file, record unlock in `~/.openclaw/lock-state.json` with timestamp and 5-minute timeout (FR-023), update manifest `locked: false`
- [ ] T009 [P] [US1] Add symlink detection to `scripts/lib/integrity.sh`: function that scans all protected directories for symlinks, returns list of violations. Called by lock, deploy, and audit operations (FR-005)
- [ ] T010 [US1] Add `integrity-lock` and `integrity-unlock` targets to `Makefile`: `integrity-lock` requires sudo, `integrity-unlock` requires sudo and `FILE=<path>` argument
- [ ] T011 [US1] Extend `make agents-setup` to call `integrity-deploy` and `integrity-lock` as final steps after deploying workspace files

### Verification

- [ ] T012 [US1] Verification: deploy and lock workspace files → attempt `echo "tampered" >> ~/.openclaw/agents/linkedin-persona/SOUL.md` as non-root → verify "Operation not permitted" → unlock SOUL.md → verify edit succeeds → re-lock → verify manifest checksum updated
- [ ] T013 [US1] Verification: create a symlink inside a protected directory → run `make integrity-lock` → verify lock refuses with symlink violation error

**Checkpoint**: US1 complete. All protected files immutable. Lock/unlock workflow operational.

---

## Phase 4: User Story 2 — Agent Sandbox Isolation (Priority: P2)

**Goal**: Agent runs with read-only workspace, restricted tools, workspace-only filesystem access. Extraction agent has zero tools.

**Independent Test**: Start agent in sandbox mode. Attempt to read `~/.openclaw/.env` from agent. Verify denied. Attempt to write to workspace. Verify denied. Run M3 draft→approve→publish flow. Verify it works.

### Implementation

- [ ] T014 [US2] Create `scripts/sandbox-setup.sh`: read current `~/.openclaw/openclaw.json`, add sandbox configuration for linkedin-persona agent (`sandbox.mode: "all"`, `sandbox.scope: "agent"`, `sandbox.workspaceAccess: "ro"`, `tools.fs.workspaceOnly: true`, `tools.deny: ["exec", "process", "browser", "apply_patch"]`, `tools.allow: ["read", "web_fetch", "sessions_send"]`), add sandbox configuration for feed-extractor agent (`sandbox.mode: "all"`, `sandbox.scope: "agent"`, `sandbox.workspaceAccess: "none"`, `tools.deny: ["*"]`, `tools.allow: []`), write updated config via jq
- [ ] T015 [P] [US2] Create `scripts/sandbox-teardown.sh`: remove sandbox configuration from both agent entries in `~/.openclaw/openclaw.json`, restore default (unsandboxed) state
- [ ] T016 [US2] Add `sandbox-setup` and `sandbox-teardown` targets to `Makefile`
- [ ] T017 [US2] Create writable data directory for agent state: `mkdir -p ~/.openclaw/sandboxes/linkedin-persona/data/` (inside sandbox writable area, outside read-only workspace per plan Phase 3), update BOOT.md to reference this path for `pending-drafts.json`, ensure sandbox config maps this directory as writable
- [ ] T017b [US2] Add sandbox configuration check to `scripts/integrity-verify.sh`: verify sandbox.mode is set to "all" for both agents in openclaw.json before launching agent (FR-013) — warn but do not block (sandbox is an independent defense layer)

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

- [ ] T022 [US3] Create `scripts/integrity-verify.sh`: load manifest from `~/.openclaw/manifest.json`, verify manifest HMAC signature against Keychain key (FR-016), compute SHA-256 of each protected file and compare to manifest (FR-014), verify no symlinks in protected directories (FR-005), check dangerous environment variables are unset: DYLD_INSERT_LIBRARIES, NODE_OPTIONS (FR-019, exclude BUN_INSTALL per R-007), verify platform version matches manifest (FR-020), validate structural integrity of `~/.openclaw/sandboxes/linkedin-persona/data/pending-drafts.json` via jq (FR-012: required fields, no additional properties, content length limits), verify monitoring service heartbeat is recent (FR-024), if all checks pass: exec the agent process directly (eliminates TOCTOU window per FR-014), if any check fails: print failures and exit non-zero (FR-015)
- [ ] T023 [US3] Add `integrity-verify` target to `Makefile`: runs integrity check without starting agent (dry-run mode)
- [ ] T024 [P] [US3] Create n8n workflow structural comparison in `scripts/integrity-verify.sh`: export workflows from n8n via `docker exec`, compare against version-controlled copies in `workflows/` using jq (ignore metadata keys: updatedAt, createdAt, versionId), report mismatches (FR-018)

### Continuous Monitoring

- [ ] T025 [US3] Create `scripts/integrity-monitor.sh`: use `fswatch` to watch all protected file paths, on file change event: re-verify checksum against manifest (FR-025), check `~/.openclaw/lock-state.json` for active unlock on that specific file (FR-023), if no active unlock and checksum mismatch: send alert to operator via OpenClaw inbound hook (FR-022), write heartbeat to `~/.openclaw/integrity-monitor-heartbeat.json` every 30 seconds (FR-024)
- [ ] T026 [P] [US3] Create `scripts/templates/com.openclaw.integrity-monitor.plist`: launchd LaunchAgent (user-level, starts after login), KeepAlive: true (auto-restart on crash), StandardOutPath and StandardErrorPath for logging, program path to `scripts/integrity-monitor.sh`
- [ ] T027 [US3] Add `monitor-setup`, `monitor-teardown`, `monitor-status` targets to `Makefile`: setup installs plist and loads via `launchctl load`, teardown unloads and removes, status checks process and heartbeat recency
- [ ] T028 [US3] Implement alert suppression cleanup: lock command (`integrity-lock.sh`) clears all entries from `~/.openclaw/lock-state.json` after re-locking, expired entries (past 5-minute timeout) are ignored by the monitor

### Verification

- [ ] T029 [US3] Verification: tamper with SOUL.md via `sudo chflags nouchg && echo tampered >> SOUL.md && sudo chflags uchg` → run `make integrity-verify` → verify check fails with specific file identified
- [ ] T030 [US3] Verification: start monitoring → modify a protected file with sudo → verify operator receives alert within 60 seconds
- [ ] T031 [US3] Verification: unlock SOUL.md → modify it → verify NO alert during grace period → re-lock → verify alert suppression cleared
- [ ] T032 [US3] Verification: kill monitoring service → verify launchd restarts it → verify heartbeat resumes

**Checkpoint**: US3 complete. Agent refuses to start on tampering. Real-time monitoring with alerts.

---

## Phase 6: User Story 4 — Supply Chain Controls (Priority: P4)

**Goal**: Operator-controlled skill allowlist. Skills identified by content hash. Unapproved skills rejected.

**Independent Test**: Add a skill to allowlist. Verify it loads. Add an unapproved skill file. Verify agent rejects it.

### Implementation

- [ ] T033 [US4] Create `scripts/skill-allowlist.sh`: subcommands `add` (compute SHA-256 of SKILL.md, add to `~/.openclaw/skill-allowlist.json`), `remove` (remove entry by name), `check` (verify all installed skills match allowlist), `list` (show current allowlist with hashes)
- [ ] T034 [US4] Integrate skill allowlist check into `scripts/integrity-verify.sh`: on startup, enumerate all SKILL.md files in agent workspaces, compute content hashes, verify each matches an entry in the allowlist (FR-027), fail startup if any skill is not on the list or hash mismatches (FR-029)
- [ ] T035 [US4] Add `skillallow-add` and `skillallow-remove` targets to `Makefile`: `skillallow-add` requires `NAME=<skill-name>`, computes hash from the installed skill file, adds to allowlist, `skillallow-remove` requires `NAME=<skill-name>`
### Verification

- [ ] T037 [US4] Verification: add all 5 M3 skills to allowlist → run integrity check → verify all pass → add a fake skill file to workspace → run integrity check → verify FAIL for unapproved skill
- [ ] T038 [US4] Verification: modify an approved skill's SKILL.md content → run integrity check → verify FAIL due to hash mismatch (simulating T-PERSIST-002 skill update poisoning)
- [ ] T039 [US4] Verification: change OpenClaw version (simulate unexpected update) → run integrity check → verify FAIL due to platform version mismatch

**Checkpoint**: US4 complete. Supply chain controls operational. Skills identified by content hash.

---

## Phase 7: User Story 5 — Audit Extensions (Priority: P5)

**Goal**: Security audit covers all new controls with PASS/FAIL/WARN output.

**Independent Test**: Run `make audit`. Verify all 8 new checks pass. Disable one control. Verify corresponding check fails.

### Implementation

- [ ] T040 [P] [US5] Add CHK-OPENCLAW-INTEGRITY-LOCK to `scripts/hardening-audit.sh`: verify `chflags uchg` is set on all protected files listed in manifest (FR-030)
- [ ] T041 [P] [US5] Add CHK-OPENCLAW-INTEGRITY-MANIFEST to `scripts/hardening-audit.sh`: verify manifest HMAC signature is valid, all checksums match current file contents (FR-035)
- [ ] T042 [P] [US5] Add CHK-OPENCLAW-SANDBOX-MODE to `scripts/hardening-audit.sh`: verify `sandbox.mode` is set to "all" for both agents in `~/.openclaw/openclaw.json` (FR-031)
- [ ] T043 [P] [US5] Add CHK-OPENCLAW-SANDBOX-TOOLS to `scripts/hardening-audit.sh`: verify tool deny lists are configured per agent, verify feed-extractor has zero allowed tools (FR-032)
- [ ] T044 [P] [US5] Add CHK-OPENCLAW-MONITOR-STATUS to `scripts/hardening-audit.sh`: verify monitoring LaunchAgent is loaded, process is running, heartbeat file exists and is recent (<60 seconds old) (FR-033)
- [ ] T045 [P] [US5] Add CHK-OPENCLAW-SKILLALLOW to `scripts/hardening-audit.sh`: verify all installed skills match an entry in the allowlist by content hash (FR-034)
- [ ] T046 [P] [US5] Add CHK-OPENCLAW-SYMLINK to `scripts/hardening-audit.sh`: verify no symlinks exist in any protected directory (FR-036)
- [ ] T047 [P] [US5] Add CHK-OPENCLAW-PLATFORM-VERSION to `scripts/hardening-audit.sh`: verify installed platform version matches version recorded in manifest (FR-037)

### Verification

- [ ] T048 [US5] Verification: deploy all controls → run `make audit` → verify all 8 new CHK-OPENCLAW-* checks pass
- [ ] T049 [US5] Verification: disable sandbox mode → run `make audit` → verify CHK-OPENCLAW-SANDBOX-MODE reports FAIL → re-enable → verify PASS
- [ ] T050 [US5] Verification: stop monitoring service → run `make audit` → verify CHK-OPENCLAW-MONITOR-STATUS reports FAIL → restart → verify PASS
- [ ] T051 [US5] Verification: unlock a workspace file (leave writable) → run `make audit` → verify CHK-OPENCLAW-INTEGRITY-LOCK reports WARN with specific file

**Checkpoint**: US5 complete. All controls auditable.

---

## Phase 8: Polish and Cross-Cutting Concerns

**Purpose**: Testing, documentation, final validation

- [ ] T052 Run shellcheck on all new/modified scripts: `integrity-lock.sh`, `integrity-unlock.sh`, `integrity-deploy.sh`, `integrity-verify.sh`, `integrity-monitor.sh`, `sandbox-setup.sh`, `sandbox-teardown.sh`, `skill-allowlist.sh`, `lib/integrity.sh` — zero warnings required per Constitution VI
- [ ] T053 Update `specs/011-workspace-integrity/quickstart.md`: verify all commands work end-to-end on Mac Mini, fix any inaccuracies
- [ ] T054 Adversarial testing: attempt to bypass immutability via `sudo chflags nouchg` + modify + `sudo chflags uchg` → verify monitoring detects (checksum re-verification per FR-025)
- [ ] T055 Adversarial testing: create symlink from writable data directory pointing into protected workspace → verify integrity check catches it
- [ ] T056 Adversarial testing: set `DYLD_INSERT_LIBRARIES=/tmp/evil.dylib` → run `make integrity-verify` → verify startup blocked with env var warning
- [ ] T057 Full end-to-end: sandbox + locked files + monitoring + allowlist → run M3 draft→approve→publish → verify zero disruption
- [ ] T058 Update `ROADMAP.md`: document 011-workspace-integrity completion status

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
