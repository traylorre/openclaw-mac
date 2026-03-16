# Tasks: Chromium CDP Hardening

**Input**: Design documents from `/specs/005-chromium-cdp-hardening/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md

**Tests**: Not requested. No test tasks included.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: No project initialization needed — this feature modifies existing scripts and creates one new script.

*No tasks in this phase.*

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Create the standalone browser cleanup script that US4 needs and US1-US3 fix functions reference.

- [x] T001 Create `scripts/browser-cleanup.sh` with the following: set -euo pipefail, color setup, detect browser type (Chromium vs Chrome), detect profile directory, refuse if browser is running (pgrep check per R-005), accept optional --profile argument, remove session data files listed in data-model.md (Cookies, Local Storage, Session Storage, History, Cache, Code Cache, Service Worker, GPUCache), preserve Bookmarks/Extensions/Preferences, report what was cleaned
- [x] T002 Verify `scripts/browser-cleanup.sh` passes `bash -n` syntax check and is executable (chmod 755)

**Checkpoint**: `browser-cleanup.sh` is a working standalone script that can be called independently.

---

## Phase 3: User Story 1 — CDP Port Binding Fix (Priority: P1) MVP

**Goal**: Register an INSTRUCTED fix for `CHK-CHROMIUM-CDP` that shows correct launch flags.

**Independent Test**: Run `sudo bash scripts/hardening-fix.sh --dry-run --auto` on a system with Chromium — verify CHK-CHROMIUM-CDP appears with INSTRUCTED status showing the correct `--remote-debugging-address=127.0.0.1` flag.

### Implementation for User Story 1

- [x] T003 [US1] Add `fix_chromium_cdp()` function to `scripts/hardening-fix.sh` as CONFIRMATION classification that uses `print_instruction` to show: (1) the correct launch flags `--remote-debugging-address=127.0.0.1 --remote-debugging-port=9222`, (2) where to set them (OpenClaw config or launch script), (3) why CDP on 0.0.0.0 is unauthenticated RCE. Must use `prompt_confirm` for interactive mode. Reports INSTRUCTED on success. (FR-001)
- [x] T004 [US1] Register `CHK-CHROMIUM-CDP` in `FIX_REGISTRY`, `FIX_FUNCTIONS`, and `FIX_DESCRIPTIONS` arrays in `scripts/hardening-fix.sh` with classification CONFIRMATION (FR-001)

**Checkpoint**: Fix script recognizes CHK-CHROMIUM-CDP and provides actionable remediation.

---

## Phase 4: User Story 2 — Dangerous Launch Flags Fix (Priority: P1)

**Goal**: Register an INSTRUCTED fix for `CHK-CHROMIUM-DANGERFLAGS` that names each bad flag.

**Independent Test**: Run fix script dry-run — verify CHK-CHROMIUM-DANGERFLAGS appears with INSTRUCTED status listing dangerous flags and their risks.

### Implementation for User Story 2

- [x] T005 [P] [US2] Add `fix_chromium_dangerflags()` function to `scripts/hardening-fix.sh` as CONFIRMATION classification that uses `print_instruction` to show: (1) each dangerous flag from the known list in data-model.md, (2) what each flag disables, (3) where to remove them (OpenClaw config `~/.openclaw/openclaw.json` browser.launchArgs or launch script). Must use `prompt_confirm`. Reports INSTRUCTED on success. (FR-002, FR-010)
- [x] T006 [P] [US2] Register `CHK-CHROMIUM-DANGERFLAGS` in `FIX_REGISTRY`, `FIX_FUNCTIONS`, and `FIX_DESCRIPTIONS` arrays in `scripts/hardening-fix.sh` with classification CONFIRMATION (FR-002)

**Checkpoint**: Fix script recognizes CHK-CHROMIUM-DANGERFLAGS and provides per-flag remediation.

---

## Phase 5: User Story 3 — Version Freshness Fix (Priority: P2)

**Goal**: Register a SAFE auto-fix for `CHK-CHROMIUM-VERSION` that updates via Homebrew.

**Independent Test**: Run fix script dry-run — verify CHK-CHROMIUM-VERSION appears with DRY-RUN status showing the brew upgrade command.

### Implementation for User Story 3

- [x] T007 [US3] Add `fix_chromium_version()` function to `scripts/hardening-fix.sh` as SAFE classification that: (1) detects installation method (Homebrew Chromium, Homebrew Chrome, or manual per data-model.md), (2) for Homebrew: runs `run_as_user brew upgrade --cask chromium` (or google-chrome), (3) for manual install: reports SKIPPED with manual instructions, (4) adds snapshot_setting entry before update (FR-008). Must use run_as_user for brew commands (FR-009). (FR-003)
- [x] T008 [US3] Register `CHK-CHROMIUM-VERSION` in `FIX_REGISTRY`, `FIX_FUNCTIONS`, and `FIX_DESCRIPTIONS` arrays in `scripts/hardening-fix.sh` with classification SAFE (FR-003)

**Checkpoint**: Fix script can auto-update Chromium via Homebrew when stale.

---

## Phase 6: User Story 4 — Browser Data Cleanup Integration (Priority: P2)

**Goal**: Wire the standalone cleanup script into the fix script so it can be invoked during a fix run.

**Independent Test**: Run `bash scripts/browser-cleanup.sh` directly and verify it cleans session data. Also run via fix script dry-run and verify it shows as an available action.

### Implementation for User Story 4

- [ ] T009 [US4] Add `fix_browser_cleanup()` function to `scripts/hardening-fix.sh` that sources `scripts/browser-cleanup.sh` and calls its cleanup function. Classification CONFIRMATION (requires user approval since it deletes data). Must use `prompt_confirm`. (FR-004, FR-005, FR-011)
- [ ] T010 [US4] Add a new check ID `CHK-BROWSER-DATA` or integrate cleanup as a remediation for an existing check. Register in `FIX_REGISTRY` with classification CONFIRMATION.

**Checkpoint**: Browser cleanup is callable both standalone and through the fix script.

---

## Phase 7: User Story 5 — GETTING-STARTED Guide Update (Priority: P3)

**Goal**: Add Chromium setup and verification to the getting-started guide.

**Independent Test**: Read GETTING-STARTED.md Next Steps section and verify it includes Chromium install + audit verification commands.

### Implementation for User Story 5

- [x] T011 [US5] Add a "Set Up Chromium (Optional)" subsection to the Next Steps section of `GETTING-STARTED.md` with: (1) install command `brew install --cask chromium`, (2) run audit to verify `bash scripts/hardening-audit.sh --section "Browser Security"`, (3) expected output showing Chromium checks, (4) link to §2.11 of HARDENING.md for full details (FR-007)

**Checkpoint**: A new operator can set up and verify Chromium hardening from the getting-started guide.

---

## Phase 8: Polish and Cross-Cutting Concerns

**Purpose**: Update registry, verify syntax, run lint, create PR.

- [x] T012 Update `Auto-Fix` column in `scripts/CHK-REGISTRY.md` for CHK-CHROMIUM-CDP (yes), CHK-CHROMIUM-DANGERFLAGS (yes), and CHK-CHROMIUM-VERSION (yes)
- [x] T013 [P] Verify `scripts/hardening-fix.sh` passes `bash -n` syntax check after all additions
- [x] T014 [P] Verify `scripts/browser-cleanup.sh` passes `bash -n` syntax check
- [ ] T015 Run markdownlint on `GETTING-STARTED.md` and fix any violations
- [ ] T016 Commit all changes and create PR with summary

---

## Dependencies and Execution Order

### Phase Dependencies

- **Phase 2 (Foundational)**: No dependencies — create cleanup script first
- **Phase 3 (US1)**: Independent of Phase 2 (different file: hardening-fix.sh)
- **Phase 4 (US2)**: Independent of Phase 3 (different function, same file but no dependency)
- **Phase 5 (US3)**: Independent of Phase 3/4 (different function)
- **Phase 6 (US4)**: Depends on Phase 2 (needs browser-cleanup.sh to exist)
- **Phase 7 (US5)**: Independent (different file: GETTING-STARTED.md)
- **Phase 8 (Polish)**: Depends on all previous phases

### User Story Dependencies

- **US1 (P1)**: Independent — can start immediately
- **US2 (P1)**: Independent — can start immediately
- **US3 (P2)**: Independent — can start immediately
- **US4 (P2)**: Depends on Phase 2 (browser-cleanup.sh must exist)
- **US5 (P3)**: Independent — can start immediately

### Parallel Opportunities

- T003/T004 (US1) and T005/T006 (US2) can run in parallel (different functions in same file, no conflicts)
- T007/T008 (US3) can run in parallel with US1/US2
- T011 (US5) can run in parallel with everything (different file)
- T013, T014 can run in parallel (different files)

---

## Implementation Strategy

### MVP First (User Stories 1 + 2)

1. Complete Phase 3: US1 — CDP port binding fix
2. Complete Phase 4: US2 — Dangerous flags fix
3. **STOP and VALIDATE**: Run `--dry-run` to verify both fixes appear
4. This closes the two highest-risk gaps (RCE via CDP, weakened isolation)

### Incremental Delivery

1. US1 + US2 → CDP and dangerous flags fixable (MVP)
2. US3 → Version staleness auto-updated
3. Phase 2 + US4 → Browser cleanup available
4. US5 → Guide updated for new operators
5. Phase 8 → Registry sync, lint, PR

---

## Notes

- All fix functions are added to `scripts/hardening-fix.sh` — sequential execution avoids merge conflicts
- T001 (browser-cleanup.sh) is the only new file; all other tasks modify existing files
- INSTRUCTED fixes (CDP, dangerflags) use `print_instruction` and `report_fix ... INSTRUCTED` — they do not modify the system
- The SAFE fix (version) uses `run_as_user` to avoid the sudo privilege pollution bug
- Total tasks: 16
