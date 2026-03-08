# Tasks: Compaction Detection and Recovery

**Input**: Design documents from `/specs/003-compaction-recovery/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: Not requested — test tasks omitted. Validation via dry-run mode (FR-051) and health-check (FR-075).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Scripts**: `~/dotfiles/scripts/bin/` (symlinked to `~/bin/`)
- **Hook config**: `~/dotfiles/claude/.claude/settings.json` (symlinked to `~/.claude/settings.json`)
- **Slash command**: `.claude/commands/compaction-audit.md`
- **Runtime artifacts**: `.claude/` (not version-controlled)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Directory structure and prerequisite verification

- [ ] T001 [P] Create directory structure: ensure `~/dotfiles/scripts/bin/` exists, ensure `.claude/recovery-logs/` exists with 0700 permissions, verify `~/bin/` symlink directory exists
- [ ] T002 [P] Verify prerequisites (jq, git) are on PATH and functional; warn if tmux is absent (optional but needed for US2 zero-manual-step recovery)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared utility library and hook wiring that MUST be complete before ANY user story script

**CRITICAL**: No user story work can begin until this phase is complete

- [ ] T003 Create `~/dotfiles/scripts/bin/recovery-common.sh` with: `set -euo pipefail`, shared constants (`MARKER_FILE`, `TASK_FILE`, `LOG_DIR`, `SENTINEL_FILE`, format version strings), environment detection helpers (`is_tmux`, `project_root`), error/warn/info logging to stderr, `set_permissions` helper (chmod 0600), marker management functions (`write_marker`, `read_marker`, `validate_marker`, `check_marker_staleness`, `consume_marker`), interrupted task JSON read/write/cleanup utilities, and stdin JSON parsing helper (jq wrapper with field validation)
- [ ] T004 [P] Add hook configurations for PreCompact, SessionStart(compact), and SessionStart(clear) to `~/dotfiles/claude/.claude/settings.json` per quickstart.md hook config section — preserve existing hooks (FR-015)

**Checkpoint**: Foundation ready — user story implementation can now begin

---

## Phase 3: User Story 1 — Automatic Compaction Detection and Audit (Priority: P1) MVP

**Goal**: Detect compaction via hooks, inject context instructing model to run audit, extend compaction-audit with batch mode for automatic reverts

**Independent Test**: Simulate PreCompact + SessionStart(compact) via dry-run and verify marker creation + additionalContext output contains HALT+audit instructions

### Implementation for User Story 1

- [ ] T005 [P] [US1] Implement `recovery-precompact.sh`: source `recovery-common.sh`, parse stdin JSON (session_id, transcript_path, cwd), create recovery marker with stage `"detected"` and `precompact_fired: true` (FR-010), install signal handlers (FR-062) that persist marker state on SIGTERM/SIGINT/SIGHUP, initialize recovery log header (FR-043) in `~/dotfiles/scripts/bin/recovery-precompact.sh`
- [ ] T006 [P] [US1] Implement `recovery-detect.sh`: source `recovery-common.sh`, parse stdin JSON (session_id, transcript_path, cwd, source), check for existing marker and handle staleness (FR-023) and re-entrancy (FR-016), create marker if PreCompact didn't fire (fallback), update marker stage to `"audit_pending"`, output `hookSpecificOutput.additionalContext` JSON with HALT+audit instructions per hook-compact.md contract, initialize recovery log if not yet created (FR-043), enforce log retention max 10 (FR-052, FR-069) in `~/dotfiles/scripts/bin/recovery-detect.sh`
- [ ] T007 [P] [US1] Extend `.claude/commands/compaction-audit.md` with `--batch` mode per batch-mode.md contract: detect `--batch` in `$ARGUMENTS`, auto-approve all reverts without confirmation, `git stash push --keep-index` before reverts (FR-037), revert modified files via `git checkout`, delete created files (FR-041), skip out-of-repo files (FR-086), flag infrastructure files (FR-047), restore stash after reverts, write recovery log tainted edits table (FR-043), create `.claude/recovery-audit-complete` sentinel, update marker stage to `"reverts_complete"`, summarized output for >50 edits (FR-068)
- [ ] T008 [US1] Create symlinks in `~/bin/` for `recovery-precompact.sh` and `recovery-detect.sh`, make scripts executable (chmod +x)

**Checkpoint**: Compaction detection and audit workflow functional — model receives HALT instruction and can run `/compaction-audit --batch` to revert tainted edits

---

## Phase 4: User Story 3 — Interrupted Task Capture (Priority: P2)

**Goal**: Capture the specific task/prompt the model was working on when compaction fired, so the resume step (US2) can reference it

**Independent Test**: Simulate PreCompact with a mock transcript JSONL and verify `.claude/recovery-interrupted-task.json` contains the correct substantive message, not a trivial confirmation

### Implementation for User Story 3

- [ ] T009 [P] [US3] Add transcript parsing to `recovery-precompact.sh`: seek to last 1MB of transcript file (FR-065), discard partial first line (FR-019), parse JSONL with jq, filter `type=="user"` and `isSidechain!=true`, reverse iterate to find last substantive message — skip trivial (10 chars or matches confirmation patterns per FR-025), detect slash commands (`/` prefix, FR-095), capture up to 3 preceding substantive messages (FR-082), write `.claude/recovery-interrupted-task.json` with `interrupted-task-v1` format (data-model.md), update marker stage to `"task_captured"` and `capture_source: "precompact"` in `~/dotfiles/scripts/bin/recovery-precompact.sh`
- [ ] T010 [P] [US3] Add fallback transcript parsing to `recovery-detect.sh`: read marker, check `precompact_fired` flag — if `false` or marker absent, parse transcript using same algorithm as T009, write interrupted task JSON with `capture_source: "transcript_parse"`, update marker stage to `"task_captured"` — if transcript unavailable (FR-028), add warning to marker and proceed without task capture in `~/dotfiles/scripts/bin/recovery-detect.sh`

**Checkpoint**: After compaction, `.claude/recovery-interrupted-task.json` contains the captured task regardless of whether PreCompact or SessionStart(compact) performed the capture

---

## Phase 5: User Story 2 — Automated /clear and Resume After Recovery (Priority: P2)

**Goal**: After audit completes, automatically trigger /clear (tmux) or instruct developer (non-tmux), then inject recovery context + interrupted task into the fresh session

**Independent Test**: Create a mock recovery marker + interrupted task file + recovery log, simulate SessionStart(clear) via pipe to recovery-loader.sh, verify additionalContext output contains recovery preamble with reverted files, interrupted task, and resume instructions

### Implementation for User Story 2

- [ ] T011 [P] [US2] Implement `recovery-watcher.sh`: validate TMUX and TMUX_PANE env vars, poll for `.claude/recovery-audit-complete` sentinel every 2 seconds, on sentinel detection poll tmux pane for idle state via `tmux capture-pane -p` and prompt pattern matching (research.md R-003), send `/clear` + Enter via `tmux send-keys`, delete sentinel file, 5-minute timeout with clean exit (FR-020), log actions to recovery log in `~/dotfiles/scripts/bin/recovery-watcher.sh`
- [ ] T012 [P] [US2] Implement `recovery-loader.sh`: source `recovery-common.sh`, parse stdin JSON, check for recovery marker — if absent exit 0 (normal /clear, not recovery), load interrupted task from path in marker, read recovery log for reverted/preserved file summary, build recovery preamble per data-model.md Recovery Preamble format (2KB max FR-083, truncation priority: preceding messages first, then file list to 10, then task desc to 500 chars, never truncate instructions), output `hookSpecificOutput.additionalContext` JSON, consume (delete) marker (FR-022), delete interrupted task file, clean stale task files >24h (FR-054), handle corrupt marker by renaming to `.corrupt` (FR-092) in `~/dotfiles/scripts/bin/recovery-loader.sh`
- [ ] T013 [US2] Add watcher spawning to `recovery-detect.sh`: after context injection, check `TMUX` env var — if present, launch `recovery-watcher.sh` as background process (`&`), record PID in marker; if absent, append non-tmux instruction ("Type /clear to complete recovery") to additionalContext in `~/dotfiles/scripts/bin/recovery-detect.sh`
- [ ] T014 [US2] Create symlinks in `~/bin/` for `recovery-watcher.sh` and `recovery-loader.sh`, make scripts executable (chmod +x)

**Checkpoint**: Full recovery loop works end-to-end — compaction detected, audit runs, /clear fires (auto in tmux, manual outside), fresh session receives recovery context and interrupted task

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Health-check, dry-run mode, code quality, and end-to-end validation

- [ ] T015 [P] Implement `recovery-health.sh`: check jq/git/tmux presence and versions, verify all 4 recovery scripts exist and are executable in `~/bin/`, validate hook config entries in `~/.claude/settings.json` for PreCompact + SessionStart(compact) + SessionStart(clear), check `.claude/commands/compaction-audit.md` exists and contains `--batch` support, verify `.claude/` directory is writable, create `.claude/recovery-logs/` if missing, display colored pass/fail output (Principle VIII) in `~/dotfiles/scripts/bin/recovery-health.sh`
- [ ] T016 [P] Add `--dry-run` mode (FR-051) to `recovery-precompact.sh`, `recovery-detect.sh`, and `recovery-loader.sh`: accept `--dry-run` flag, log all actions to stderr without writing files or modifying state, output what would be written/injected
- [ ] T017 Run shellcheck on all `recovery-*.sh` scripts in `~/dotfiles/scripts/bin/` and fix warnings — ensure compliance with Principle VI (Bash Scripts Are Infrastructure)
- [ ] T018 Validate end-to-end flow using quickstart.md dry-run scenarios: simulate PreCompact event, simulate SessionStart(compact) event, simulate SessionStart(clear) event, verify output formats match contracts
- [ ] T019 Create symlink in `~/bin/` for `recovery-health.sh`, make executable (chmod +x)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion — BLOCKS all user stories
- **US1 (Phase 3)**: Depends on Foundational — implements core detection and audit
- **US3 (Phase 4)**: Depends on US1 (extends precompact and detect scripts with transcript parsing)
- **US2 (Phase 5)**: Depends on US1 (extends detect script with watcher spawning); benefits from US3 (interrupted task available for preamble, but degrades gracefully without it per FR-093 tier 2)
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) — no dependencies on other stories
- **User Story 3 (P2)**: Extends US1 scripts — depends on Phase 3 completion
- **User Story 2 (P2)**: Extends US1 detect script with watcher spawning — depends on Phase 3; uses US3 interrupted task output but works without it (degradation tier 2)

### Within Each User Story

- Scripts that share no files can be implemented in parallel ([P] marked)
- Symlink tasks depend on their scripts being complete
- Common library (recovery-common.sh) must be complete before any script

### Parallel Opportunities

- **Phase 1**: T001, T002 — independent setup tasks
- **Phase 2**: T004 can run alongside T003 (different files)
- **Phase 3**: T005, T006, T007 — three different files, all parallelizable
- **Phase 4**: T009, T010 — two different scripts, both parallelizable
- **Phase 5**: T011, T012 — two new scripts, both parallelizable
- **Phase 6**: T015, T016 — health-check (new script) and dry-run (flag additions), parallelizable

---

## Parallel Example: User Story 1

```bash
# Launch all US1 script implementations together (different files):
Task: T005 "Implement recovery-precompact.sh" in ~/dotfiles/scripts/bin/recovery-precompact.sh
Task: T006 "Implement recovery-detect.sh" in ~/dotfiles/scripts/bin/recovery-detect.sh
Task: T007 "Extend compaction-audit.md --batch" in .claude/commands/compaction-audit.md

# Then sequentially:
Task: T008 "Create symlinks" (depends on T005, T006)
```

## Parallel Example: User Story 2

```bash
# Launch both new scripts together (different files):
Task: T011 "Implement recovery-watcher.sh" in ~/dotfiles/scripts/bin/recovery-watcher.sh
Task: T012 "Implement recovery-loader.sh" in ~/dotfiles/scripts/bin/recovery-loader.sh

# Then sequentially:
Task: T013 "Add watcher spawning to recovery-detect.sh" (extends existing script)
Task: T014 "Create symlinks" (depends on T011, T012)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL — blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Simulate compaction → verify marker created, audit context injected, `/compaction-audit --batch` reverts tainted edits
5. At this point: detection + audit + revert works. Recovery is manual (/clear + resume by developer)

### Incremental Delivery

1. Setup + Foundational → Foundation ready
2. Add US1 → Test independently → **MVP: detection + audit works** (manual /clear)
3. Add US3 → Test independently → Interrupted task captured (enriches recovery context)
4. Add US2 → Test independently → Full automated recovery loop (/clear + resume)
5. Add Polish → Health-check, dry-run, shellcheck compliance

### Degradation Tiers (FR-093 alignment)

| After Phase | Tier | Capability |
|-------------|------|------------|
| Phase 3 (US1) | 6→4 | Detect + audit + revert, no task capture, no auto-/clear |
| Phase 4 (US3) | 3→2 | + interrupted task capture |
| Phase 5 (US2) | 1 | Full: detect + audit + revert + task + auto-/clear + resume |

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks in same phase
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- All scripts must: `set -euo pipefail`, quote all variables, use absolute paths (Principle VI)
- Recovery marker is the central coordination artifact — write it first (FR-070)
- The `additionalContext` output format must be valid JSON with `hookSpecificOutput.hookEventName` and `hookSpecificOutput.additionalContext` fields
