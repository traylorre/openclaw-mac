# Tasks: Colima Lifecycle Management

**Input**: Design documents from `/specs/008-colima-lifecycle/`
**Prerequisites**: plan.md, spec.md, research.md

**Tests**: Not requested.

**Organization**: Tasks grouped by user story.

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: User Story 1 — Bootstrap Installs Colima and Docker (Priority: P1)

**Goal**: Bootstrap script installs Colima and Docker CLI if missing.

**Independent Test**: Run `bash scripts/bootstrap.sh --check` on a Mac
without Colima and verify it reports FAIL for both. Run without --check
and verify both are installed.

- [x] T001 [US1] Change the Docker/Colima section in scripts/bootstrap.sh from SKIP (optional) to FAIL/install pattern: if `command -v colima` fails, install via `brew install colima`; if `command -v docker` fails, install via `brew install docker`
- [x] T002 [US1] Add hardware detection (`uname -m`) to bootstrap.sh Colima section: report Apple Silicon or Intel for operator awareness (informational, no branching needed at install time)
- [x] T003 [US1] Verify idempotency: run bootstrap twice and confirm second run reports OK for both colima and docker (no reinstall attempt)

**Checkpoint**: `colima version` and `docker version` both succeed
after bootstrap.

---

## Phase 2: User Story 2 — Audit Check CHK-COLIMA-RUNNING (Priority: P1)

**Goal**: Audit detects whether Colima is running and Docker is
functional.

**Independent Test**: Stop Colima, run audit, verify WARN. Start
Colima, run audit, verify PASS.

- [x] T004 [US2] Add `check_colima_running()` function to scripts/hardening-audit.sh: three-state detection (not installed → SKIP, stopped → WARN, running + docker info succeeds → PASS) in section §4.1 Container Runtime
- [x] T005 [US2] Wire `run_check check_colima_running` into the main() function in scripts/hardening-audit.sh before the existing container checks (CHK-CONTAINER-*)
- [x] T006 [US2] Add CHK-COLIMA-RUNNING row to scripts/CHK-REGISTRY.md: WARN severity, both deployment types, section §4.1, auto-fix yes
- [x] T007 [US2] Verify existing container checks still function correctly with Colima running (zero regressions)

**Checkpoint**: Audit shows CHK-COLIMA-RUNNING with correct state.
All other container checks unaffected.

---

## Phase 3: User Story 3 — Fix Function Starts Colima (Priority: P2)

**Goal**: Fix script starts Colima with hardened defaults if stopped.

**Independent Test**: Stop Colima, run fix targeting CHK-COLIMA-RUNNING,
verify Colima starts and `docker info` works.

- [x] T008 [US3] Add FIX_REGISTRY entry for CHK-COLIMA-RUNNING in scripts/hardening-fix.sh: classification SAFE, function fix_colima_running, description "Start Colima container runtime"
- [x] T009 [US3] Add `fix_colima_running()` function to scripts/hardening-fix.sh: detect hardware via `uname -m`, start Colima with appropriate flags (vz+rosetta for arm64, defaults for x86_64), verify with `docker info`
- [x] T010 [US3] Handle edge cases in fix_colima_running: already running → SKIPPED, not installed → FAILED with bootstrap instruction, start fails → FAILED with error output

**Checkpoint**: Fix script can bring Colima from stopped to running.
`docker info` succeeds after fix.

---

## Phase 4: User Story 4 — GETTING-STARTED Guides (Priority: P3)

**Goal**: Guides include Colima install and start commands.

**Independent Test**: Read the container section and verify commands
are present.

- [x] T011 [P] [US4] Add Colima setup section to GETTING-STARTED.md: `brew install colima docker`, `colima start` with recommended flags, `docker info` verification
- [x] T012 [P] [US4] Add identical Colima setup section to GETTING-STARTED-INTEL.md with Intel-appropriate flags (no vz/rosetta)

**Checkpoint**: Both guides have complete Colima setup instructions.

---

## Phase 5: Polish

- [x] T013 Run `bash -n` syntax check on bootstrap.sh, hardening-audit.sh, hardening-fix.sh
- [x] T014 Run markdownlint on all modified markdown files

---

## Dependencies & Execution Order

```text
Phase 1: US1 (bootstrap) ─── no dependencies
    │
    ├── Phase 2: US2 (audit check) ─── depends on Phase 1 (colima must be installable)
    │       │
    │       └── Phase 3: US3 (fix function) ─── depends on Phase 2 (check must exist before fix)
    │
    ├── Phase 4: US4 (docs) ─── no code dependencies, can parallel with Phase 2-3
    │
    └── Phase 5: Polish ─── depends on all above
```

### Requirement Coverage

| Requirement | Task(s) | Story |
|-------------|---------|-------|
| FR-001 (install colima) | T001 | US1 |
| FR-002 (install docker) | T001 | US1 |
| FR-003 (idempotent) | T003 | US1 |
| FR-004 (CHK-COLIMA-RUNNING) | T004 | US2 |
| FR-005 (PASS/WARN/SKIP) | T004 | US2 |
| FR-006 (CHK-REGISTRY) | T006 | US2 |
| FR-007 (fix starts colima) | T009 | US3 |
| FR-008 (fix idempotent) | T010 | US3 |
| FR-009 (fix fails if not installed) | T010 | US3 |
| FR-010 (hardened defaults) | T009 | US3 |
| FR-011 (guides updated) | T011-T012 | US4 |
| FR-012 (no regressions) | T007 | US2 |
