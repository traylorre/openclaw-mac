# Tasks: Context Guardian Auto-Rotation

**Input**: Design documents from `/specs/002-context-auto-rotation/`
**Prerequisites**: plan.md (required), spec.md (required), data-model.md, contracts/, research.md, quickstart.md

**Tests**: Not explicitly requested in spec — test tasks excluded. Test plan exists in `test-plan.md` for future reference.

**Organization**: Tasks grouped by user story. US2 requires no additional code (fully covered by US1's implementation).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Ensure directory structure exists for 002 scripts and runtime artifacts.

- [ ] T001 Create directory structure: verify `~/dotfiles/scripts/bin/` exists, verify `~/bin/` symlink target exists, run `mkdir -p .claude/recovery-logs` for runtime artifacts

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Extract shared hook utilities into `hook-common.sh` and refactor 003's `recovery-common.sh` to source it (FR-020). All 002 scripts depend on `hook-common.sh`.

**CRITICAL**: No user story work can begin until this phase is complete.

- [ ] T002 Create hook-common.sh with shared utilities (HOME/PATH validation, `require_tool()`, `log_info()`/`log_warn()`/`log_error()` with per-invocation log files, `is_tmux()`, `project_root()`, `set_permissions()`, `iso_timestamp()`/`iso_timestamp_full()`, `parse_stdin_json()`, `json_field()`/`json_field_or_null()`) extracted per research.md R-001 and R-007 in ~/dotfiles/scripts/bin/hook-common.sh
- [ ] T003 Refactor recovery-common.sh: add `HOOK_LOG_PREFIX="recovery"` and `source "$HOME/bin/hook-common.sh"` at top, remove all functions now provided by hook-common.sh (keep only recovery-specific marker/task/log/abort/transcript functions) per research.md R-001 and R-008 in ~/dotfiles/scripts/bin/recovery-common.sh
- [ ] T004 Create ~/bin/hook-common.sh symlink (`ln -sf ~/dotfiles/scripts/bin/hook-common.sh ~/bin/hook-common.sh`) and run `~/bin/recovery-health.sh` to verify 003 still works after refactoring

**Checkpoint**: Foundation ready — `hook-common.sh` sourced by both 002 and 003 scripts, 003 health-check passes.

---

## Phase 3: User Story 1 - Zero-Touch Context Rotation (Priority: P1) MVP

**Goal**: Full automated rotation in tmux: detect CARRYOVER write -> stop Claude -> poll for idle prompt -> send /clear -> load carryover into fresh session. Also handles non-tmux (US2) and crash recovery (startup path) as inherent parts of the same scripts.

**Independent Test**: Run Claude Code in tmux on feature branch, create test CARRYOVER file in `specs/<branch>/`, type `/clear`, verify carryover content appears in model context and file is renamed to `.loaded`.

### Implementation for User Story 1

- [ ] T005 [P] [US1] Implement carryover-detect.sh PostToolUse hook: guard `hook-common.sh` exists before sourcing (exit 2 with remediation if missing, FR-031), set `HOOK_LOG_PREFIX="carryover-detect"` then source hook-common.sh, validate jq (FR-024), validate tool_name exists (FR-010), fast-path exit for non-Write/Edit tools, extract basename and match `/^CONTEXT-CARRYOVER-[0-9]{2}\.md$/` (FR-001), check `.claude/recovery-marker.json` suppression (FR-016), `mkdir -p .claude` (FR-031), write `.claude/carryover-pending` (FR-022), spawn poller if `is_tmux()` with `TMUX_PANE` passthrough (FR-003, FR-028), output `{continue:false, stopReason:...}` via jq — stopReason covers both tmux and non-tmux paths (FR-002, FR-005, FR-027) -- per contracts/hook-posttooluse.md in ~/dotfiles/scripts/bin/carryover-detect.sh
- [ ] T006 [P] [US1] Implement carryover-poller.sh background poller: guard `hook-common.sh` exists before sourcing (exit 2 if missing, FR-031), source hook-common.sh with `HOOK_LOG_PREFIX="poller"`, validate `$TMUX_PANE` non-empty (FR-028), install EXIT trap for `.claimed` cleanup, `mkdir -p .claude` (FR-031), poll loop (1s interval, 60s timeout) with `tmux capture-pane -p -t "$TMUX_PANE"`, strip ANSI codes, scan for 3-line separator/prompt/separator pattern (FR-004), atomic `mv carryover-pending .claimed`, send banner then `/clear` via `tmux send-keys`, write `.claude/carryover-clear-needed` on timeout/failure, log elapsed time -- per contracts/poller-behavior.md in ~/dotfiles/scripts/bin/carryover-poller.sh
- [ ] T007a [P] [US1] Implement carryover-loader.sh core logic: guard `hook-common.sh` exists before sourcing (exit 2 if missing, FR-031), set `HOOK_LOG_PREFIX="carryover-loader"` then source hook-common.sh, validate jq (FR-025), install signal traps to undo `.loaded` rename with `set +e` in handler (FR-025), parse `source` from stdin JSON (FR-011). Script entry point: parse source, derive spec dir from `git branch --show-current` (FR-006, FR-031 detached HEAD guard) — spec_dir MUST be derived in the entry point (not inside `do_load()`) so T007b's FR-032 guard can use it before calling `do_load()`. Structure the search/load pipeline as a function (e.g., `do_load(spec_dir)`) accepting spec_dir as a parameter so T007b can call it after event-specific pre-processing. Core function: find unconsumed `CONTEXT-CARRYOVER-NN.md` in spec_dir sorted by highest NN (FR-026); if none found: check `carryover-pending` — if present inject "expected but missing" warning and delete pending (FR-022), else exit 0; if found: size handling <100B skip with warning / >80KB tail-truncate (FR-019, FR-022), read contents (FR-007), rename to `.loaded` (FR-008, FR-009), wrap in preamble delimiters (FR-015, FR-018). Collect all messages (warnings + carryover context) into a variable; output via `jq -n --arg` only if messages collected (FR-027). After output: delete `carryover-pending` if still present, prune `.loaded` beyond 5 (FR-021) -- per contracts/hook-sessionstart.md in ~/dotfiles/scripts/bin/carryover-loader.sh
- [ ] T007b [US1] Add event-specific routing to carryover-loader.sh: insert a `case "$source"` dispatch before calling `do_load()`. Clear path — FR-032 double-/clear guard (check `.loaded` mtime <=60s, requires recent `.loaded` AND no unconsumed CARRYOVER AND no pending; if all three true, log and exit 0). Startup path — delete stale `.claimed` (FR-029), check `carryover-clear-needed` and collect reminder text if present then delete file (FR-030), log file retention 7-day cleanup via `find .claude/recovery-logs/ -name '*.log' -mtime +7 -delete` (FR-034); pass collected reminder text to `do_load()` so it can be prepended to any core-generated messages before JSON output (FR-030 concatenation). All event paths then call `do_load()` -- per contracts/hook-sessionstart.md per-event behavior sections in ~/dotfiles/scripts/bin/carryover-loader.sh
- [ ] T008 [P] [US1] Add hook entries to settings.json: PostToolUse (matcher `.*`, command `carryover-detect.sh`), SessionStart matcher `clear` (add `carryover-loader.sh` timeout 30s alongside existing `recovery-loader.sh`), SessionStart matcher `startup` (new entry, `carryover-loader.sh` only, timeout 30s) -- per quickstart.md Step 3 and research.md R-006 in ~/dotfiles/claude/.claude/settings.json
- [ ] T009 [US1] Create symlinks (`ln -sf`) for carryover-detect.sh, carryover-poller.sh, carryover-loader.sh from ~/dotfiles/scripts/bin/ to ~/bin/ and set executable permissions (`chmod +x`) on source files

**Checkpoint**: Zero-touch rotation works in tmux. Manual `/clear` rotation works outside tmux. US1 and US2 acceptance scenarios pass.

---

## Phase 4: User Story 2 - Graceful Degradation Without tmux (Priority: P2)

**Goal**: When tmux is unavailable, stop Claude with a clear "type /clear" message; loader handles the subsequent manual `/clear` identically.

**Independent Test**: Run Claude Code outside tmux, trigger CARRYOVER write, verify stopReason message is displayed and `/clear` loads carryover.

> **No additional implementation required.** US1's `carryover-detect.sh` handles non-tmux via `is_tmux()` branch: skips poller spawn, outputs the same `stopReason` message ("Context rotation: CARRYOVER saved. Type /clear to continue (auto-clear in progress if tmux detected)."). The `carryover-loader.sh` `clear` event path loads carryover identically regardless of how `/clear` was triggered. All US2 acceptance scenarios are satisfied by US1's implementation in Phase 3.

**Checkpoint**: Non-tmux degradation path works. stopReason message guides user to type `/clear`.

---

## Phase 5: User Story 3 - Carryover Loading on Compaction Fallback (Priority: P3)

**Goal**: When auto-compaction occurs, load existing CARRYOVER file as fallback context to mitigate information loss. Suppress during active 003 recovery to avoid contradictory instructions.

**Independent Test**: Place a CARRYOVER file in the spec directory, trigger a `compact` SessionStart event, verify carryover is loaded. Repeat with `.claude/recovery-marker.json` present and verify suppression.

### Implementation for User Story 3

- [ ] T010 [P] [US3] Add compact event handling to carryover-loader.sh: when `source` is `compact`, check for `.claude/recovery-marker.json` — if present, log "compact suppressed -- recovery active" and exit 0 with no output (FR-033); if absent, proceed with standard CARRYOVER search/load flow (no FR-032 double-clear guard, no signal file cleanup); note: `compact` event name is UNVALIDATED per Q38 — confirm empirically during implementation and update FR-011 if actual name differs -- per contracts/hook-sessionstart.md "compact Events" section in ~/dotfiles/scripts/bin/carryover-loader.sh
- [ ] T011 [P] [US3] Add carryover-loader.sh (timeout 30s) to SessionStart `compact` matcher hooks array alongside existing recovery-detect.sh entry in ~/dotfiles/claude/.claude/settings.json

**Checkpoint**: Compaction fallback works. CARRYOVER loaded on compact events when no recovery is active. Suppressed when recovery marker present.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Code quality validation and end-to-end verification across all implemented scripts.

- [ ] T012 [P] Run shellcheck on all 002 scripts (hook-common.sh, carryover-detect.sh, carryover-poller.sh, carryover-loader.sh) and fix any warnings per Constitution Principle VI
- [ ] T013 [P] Validate quickstart.md Step 4 fast-path tests: echo synthetic JSON to carryover-detect.sh (non-matching tool, non-matching file) and carryover-loader.sh (no carryover) -- verify exit 0 with no output
- [ ] T014 Run quickstart.md Step 5 end-to-end smoke test: create test CARRYOVER file, type /clear in tmux Claude Code session, verify carryover loaded and file renamed to .loaded
- [ ] T015 [P] Fix quickstart.md drift: update Step 4 verification command and troubleshooting table to reference per-invocation log files (e.g., `ls .claude/recovery-logs/carryover-detect.*.log`) instead of nonexistent shared `hooks.log` -- aligns with FR-034 and research.md R-007 in specs/002-context-auto-rotation/quickstart.md

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies -- can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 -- BLOCKS all user stories
- **US1 (Phase 3)**: Depends on Phase 2 completion -- core MVP
- **US2 (Phase 4)**: No additional code -- covered by Phase 3
- **US3 (Phase 5)**: Depends on T007b (extends carryover-loader.sh with compact path)
- **Polish (Phase 6)**: Depends on Phases 3 and 5 completion

### Within Phase 3 (US1)

- T005 (detect.sh), T006 (poller.sh), T007a (loader.sh core), T008 (settings.json) are all [P] -- different files, implement simultaneously
- T007b (loader event routing) depends on T007a (adds routing to existing core logic, same file)
- T009 (symlinks) depends on T005, T006, T007a/T007b (source files must exist)

### User Story Dependencies

- **US1 (P1)**: Depends only on Phase 2 -- no cross-story dependencies
- **US2 (P2)**: No additional code -- fully covered by US1
- **US3 (P3)**: Depends on T007b (adds compact event path to existing loader)

### Parallel Opportunities

- T005, T006, T007a, T008: Four tasks implementable in parallel (all different files)
- T010, T011: Both [P] within Phase 5 (different files -- loader.sh vs settings.json)
- T012, T013, T015: shellcheck, fast-path tests, and quickstart fix run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch all four [P] tasks in parallel (different files, no dependencies):
Task T005: "Implement carryover-detect.sh in ~/dotfiles/scripts/bin/carryover-detect.sh"
Task T006: "Implement carryover-poller.sh in ~/dotfiles/scripts/bin/carryover-poller.sh"
Task T007a: "Implement carryover-loader.sh core in ~/dotfiles/scripts/bin/carryover-loader.sh"
Task T008: "Update settings.json in ~/dotfiles/claude/.claude/settings.json"

# Then sequentially (same file as T007a):
Task T007b: "Add event routing to carryover-loader.sh"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001)
2. Complete Phase 2: Foundational -- hook-common.sh extraction (T002-T004, CRITICAL blocker)
3. Complete Phase 3: User Story 1 (T005-T009, with T005/T006/T007a/T008 in parallel, then T007b, then T009)
4. **STOP and VALIDATE**: Run quickstart.md smoke test in tmux
5. Deploy: hooks active, zero-touch rotation working, non-tmux degradation working

### Incremental Delivery

1. Setup + Foundational -> hook-common.sh ready, 003 health verified
2. User Story 1 -> Full tmux rotation + non-tmux fallback -> Deploy (MVP!)
3. User Story 2 -> Already done (no code) -> Validate non-tmux path
4. User Story 3 -> Add compact fallback (T010-T011, in parallel) -> Deploy
5. Polish -> shellcheck, fast-path validation, E2E smoke test (T012-T014)

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks
- [Story] label maps task to specific user story for traceability
- US2 requires no new code -- detect.sh's `is_tmux()` branch and loader's clear path cover all non-tmux scenarios
- Each script has a matching contract document in `specs/002-context-auto-rotation/contracts/`
- All JSON output must use `jq` (FR-027) -- never raw `printf`/`echo` for model-generated content
- All scripts must start with `set -euo pipefail`, then guard `[[ -f "$HOME/bin/hook-common.sh" ]] || { echo "hook-common.sh not found — run dotfiles symlink setup" >&2; exit 2; }` (FR-031), then `source "$HOME/bin/hook-common.sh"`
- `HOOK_LOG_PREFIX` must be set before sourcing hook-common.sh (detect, poller, loader each use their own prefix)
- Constitution Principle VI requires shellcheck compliance for all bash scripts
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
