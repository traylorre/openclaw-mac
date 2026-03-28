# Tasks: Prerequisite Validation (make doctor)

**Input**: Design documents from `/specs/017-prerequisite-validation/`
**Prerequisites**: plan.md (required), spec.md (required)

**Tests**: Not explicitly requested. Verification via running `make doctor`.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

**Purpose**: Review existing patterns before implementation

- [ ] T001 Read `scripts/bootstrap.sh` report() function and accumulator pattern (OK/FIXED/ERRORS counters, summary line) to use as the template for doctor.sh output format
- [ ] T002 Read `scripts/lib/common.sh` require_command() function signature and behavior to understand the integration point

---

## Phase 2: User Story 1 - Validate All Prerequisites (Priority: P1)

**Goal**: Create doctor.sh that checks all 11 tools and reports results

**Independent Test**: Run `make doctor` — all 11 checks displayed with pass/fail status

### Implementation for User Story 1

- [ ] T003 [US1] Create `scripts/doctor.sh` with Constitution VI header (set -euo pipefail, shellcheck directives), source lib/common.sh, define color constants and report() accumulator function matching bootstrap.sh pattern
- [ ] T004 [US1] Implement tool checks for system-provided commands in `scripts/doctor.sh`: shasum, curl, security (Keychain CLI) — these use simple `command -v` checks with no install hints (system-provided)
- [ ] T005 [P] [US1] Implement tool checks for Homebrew-installed commands in `scripts/doctor.sh`: jq, shellcheck, docker, colima, fswatch, ollama, openssl — each with `brew install <name>` hint
- [ ] T006 [US1] Implement bash version check in `scripts/doctor.sh`: verify `bash --version` reports >= 5.0, fail with upgrade instructions if < 5.0
- [ ] T007 [US1] Implement summary output in `scripts/doctor.sh`: print total OK/FAIL counts, exit 0 if all pass, exit 1 if any fail
- [ ] T008 [US1] Add `doctor` target to `Makefile`: `doctor: ## Check all prerequisites` → `bash $(SCRIPTS)/doctor.sh`
- [ ] T009 [US1] Run `shellcheck scripts/doctor.sh` — fix any warnings

**Checkpoint**: `make doctor` reports all 11 tools with pass/fail and install hints

---

## Phase 3: User Story 2 - Version Information (Priority: P2)

**Goal**: Show installed version alongside each check result

**Independent Test**: Run `make doctor` — each passing tool shows its version string

### Implementation for User Story 2

- [ ] T010 [US2] Add version extraction to each tool check in `scripts/doctor.sh`: capture output of `<tool> --version` or equivalent, display alongside pass indicator
- [ ] T011 [US2] Handle tools with non-standard version output: `security` (no --version), `shasum` (--version), `openssl version`

**Checkpoint**: `make doctor` shows version info for all installed tools

---

## Phase 4: Polish & Verification

- [ ] T012 Run `make doctor` on current system — verify all 11 checks pass with versions displayed
- [ ] T013 Verify script is idempotent — run `make doctor` twice, confirm no side effects

---

## Dependencies & Execution Order

- **Phase 1**: No dependencies — T001, T002 can run in parallel
- **Phase 2 (US1)**: Depends on Phase 1 — T003 first, then T004-T007 (T004 and T005 can be parallel), then T008-T009
- **Phase 3 (US2)**: Depends on US1 (script must exist first)
- **Phase 4**: Depends on all user stories complete

### Parallel Opportunities

- T001, T002 (Setup) can run in parallel
- T004, T005 (system vs brew tools) can run in parallel

---

## Notes

- Script should be ~80-120 lines following bootstrap.sh conventions
- Use `require_command cmd hint || errors=$((errors + 1))` to prevent set -e abort
- Version checks are best-effort — not all tools have consistent `--version` output
- `security` (Keychain CLI) is macOS system tool with no version flag — check existence only

## Adversarial Review #3

| Aspect | Finding |
|--------|---------|
| Highest-risk task | T006 (bash version check) — version string parsing varies across bash installations |
| Most likely rework | T010/T011 (version extraction) — non-standard `--version` output formats across tools |
| Security | No security impact — read-only checks with no state changes |
| 3am scenario | N/A — diagnostic tool, not automated process |
| 6-month neglect | New tools added to the project won't be checked until doctor.sh is updated |

**READY FOR IMPLEMENTATION** — 0 CRITICAL, 0 HIGH. All 9 requirements covered by 13 tasks.
