# Tasks: Multi-Browser Support

**Input**: Design documents from `/specs/006-multi-browser-support/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Not requested — no test tasks included.

**Organization**: Tasks are grouped by user story to enable independent
implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

---

## Phase 1: Foundational (Browser Registry)

**Purpose**: Create the shared browser registry file and source it from
all three scripts. This is the foundation for all user stories.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [x] T001 Create scripts/browser-registry.sh with declare -A arrays (BROWSER_NAME, BROWSER_APP_PATH, BROWSER_BINARY_PATH, BROWSER_PLIST_DOMAIN, BROWSER_PROFILE_DIR, BROWSER_TCC_BUNDLE, BROWSER_CASK, BROWSER_PROCESS_NAME) with entries for chromium, chrome, and edge plus BROWSER_PREFERENCE_ORDER array and get_installed_browsers()/get_preferred_browser() helpers
- [x] T002 [P] Add source of browser-registry.sh (with shellcheck directive) to scripts/hardening-audit.sh
- [x] T003 [P] Add source of browser-registry.sh (with shellcheck directive) to scripts/hardening-fix.sh
- [x] T004 [P] Add source of browser-registry.sh (with shellcheck directive) to scripts/browser-cleanup.sh

**Checkpoint**: All three scripts source the registry. Existing functionality
unchanged — old functions still work alongside the new arrays.

---

## Phase 2: User Story 1 — Edge User Gets Same Protections (Priority: P1) 🎯 MVP

**Goal**: An operator with only Edge installed gets all 8 audit checks
and all 5 fix functions working correctly for Edge.

**Independent Test**: Install Edge via `brew install --cask microsoft-edge`,
uninstall Chromium, run `bash scripts/hardening-audit.sh`, verify all 8
`CHK-BROWSER-*` checks detect Edge. Run `bash scripts/hardening-fix.sh`,
verify Edge-specific policies deployed to `com.microsoft.Edge.plist`.

### Audit Script Refactoring (scripts/hardening-audit.sh)

- [x] T005 [US1] Replace _chromium_installed() helper with a registry-based check that returns true if any BROWSER_APP_PATH entry exists on disk in scripts/hardening-audit.sh
- [x] T006 [US1] Replace _chromium_policy_plist() helper with a function that accepts a browser key and returns BROWSER_PLIST_DOMAIN[$browser] in scripts/hardening-audit.sh
- [x] T007 [US1] Refactor check_chromium_policy to check_browser_policy accepting a browser parameter — use BROWSER_PLIST_DOMAIN for plist reads in scripts/hardening-audit.sh
- [x] T008 [US1] Refactor check_chromium_autofill to check_browser_autofill accepting a browser parameter — use BROWSER_PLIST_DOMAIN for PasswordManagerEnabled, AutofillAddressEnabled, AutofillCreditCardEnabled reads in scripts/hardening-audit.sh
- [x] T009 [US1] Refactor check_chromium_extensions to check_browser_extensions accepting a browser parameter — use BROWSER_PLIST_DOMAIN for ExtensionInstallBlocklist read in scripts/hardening-audit.sh
- [x] T010 [US1] Refactor check_chromium_urlblock to check_browser_urlblock accepting a browser parameter — use BROWSER_PLIST_DOMAIN for URLBlocklist read in scripts/hardening-audit.sh
- [x] T011 [US1] Refactor check_chromium_cdp to check_browser_cdp accepting a browser parameter — use BROWSER_PROCESS_NAME to identify port owner in lsof output in scripts/hardening-audit.sh
- [x] T012 [US1] Refactor check_chromium_tcc to check_browser_tcc accepting a browser parameter — use BROWSER_TCC_BUNDLE for sqlite3 TCC.db queries and tccutil commands in scripts/hardening-audit.sh
- [x] T013 [US1] Refactor check_chromium_version to check_browser_version accepting a browser parameter — use BROWSER_BINARY_PATH for version string and BROWSER_CASK for brew info in scripts/hardening-audit.sh
- [x] T014 [US1] Refactor check_chromium_dangerflags to check_browser_dangerflags accepting a browser parameter — use BROWSER_PROCESS_NAME for ps grep pattern in scripts/hardening-audit.sh
- [x] T015 [US1] Rename all 8 check IDs from CHK-CHROMIUM-* to CHK-BROWSER-* in emit_result calls throughout scripts/hardening-audit.sh
- [x] T016 [US1] Update emit_result function (or call sites) to include browser display name in output — format: "CHK-BROWSER-POLICY [Edge] : PASS message" in scripts/hardening-audit.sh
- [x] T017 [US1] Update JSON output to include "browser" field in JSON result objects for all CHK-BROWSER-* checks in scripts/hardening-audit.sh

### Fix Script Refactoring (scripts/hardening-fix.sh)

- [x] T018 [US1] Rename 8 FIX_REGISTRY entries from CHK-CHROMIUM-* keys to CHK-BROWSER-* keys in scripts/hardening-fix.sh
- [x] T019 [US1] Refactor fix_chromium_policy to fix_browser_policy accepting a browser parameter — deploy policy plist to /Library/Managed Preferences/${BROWSER_PLIST_DOMAIN[$browser]}.plist in scripts/hardening-fix.sh
- [x] T020 [US1] Refactor fix_chromium_tcc to fix_browser_tcc accepting a browser parameter — use BROWSER_TCC_BUNDLE for tccutil reset and TCC.db queries in scripts/hardening-fix.sh
- [x] T021 [US1] Refactor fix_chromium_cdp to fix_browser_cdp accepting a browser parameter — use BROWSER_PROCESS_NAME for process identification in scripts/hardening-fix.sh
- [x] T022 [US1] Refactor fix_chromium_dangerflags to fix_browser_dangerflags accepting a browser parameter — use BROWSER_PROCESS_NAME for process grep in scripts/hardening-fix.sh
- [x] T023 [US1] Refactor fix_chromium_version to fix_browser_version accepting a browser parameter — use BROWSER_CASK for brew upgrade command in scripts/hardening-fix.sh

**Checkpoint**: With only Edge installed, all 8 audit checks detect Edge
and all 5 fix functions apply Edge-specific remediation. Chromium-only
installations also still work (backward compat).

---

## Phase 3: User Story 2 — Multiple Browsers Detected and Checked (Priority: P1)

**Goal**: When multiple browsers are installed, audit checks and fix
functions iterate all of them and report/apply per browser.

**Independent Test**: Install both Chromium and Edge, run audit, verify
both browsers appear in output. Run fix, verify both
`org.chromium.Chromium.plist` and `com.microsoft.Edge.plist` are created.

**Depends on**: Phase 2 (parameterized functions must exist before
iteration wrapper can call them)

- [x] T024 [US2] Add run_browser_checks() wrapper that calls get_installed_browsers(), iterates results, and invokes all 8 check_browser_* functions per browser — emit SKIP for all checks if no browser found in scripts/hardening-audit.sh
- [x] T025 [US2] Wire run_browser_checks() into the main audit flow replacing the old direct calls to check_chromium_* functions in scripts/hardening-audit.sh
- [x] T026 [US2] Add browser iteration in fix dispatch so fix_browser_* functions are called once per installed browser (not just first detected) in scripts/hardening-fix.sh

**Checkpoint**: With Chromium + Edge installed, audit shows per-browser
results for both. Fix applies policies to both. With only Chromium,
behavior matches pre-refactor (SC-003).

---

## Phase 4: User Story 3 — Browser Cleanup for Any Browser (Priority: P2)

**Goal**: browser-cleanup.sh detects and cleans any installed browser.
New `--all` flag cleans all; default cleans preferred browser.

**Independent Test**: Create session data in Edge profile dir, run
`bash scripts/browser-cleanup.sh`, verify Edge profile cleaned. Run
with `--all` and verify both profiles cleaned.

- [x] T027 [US3] Refactor _bc_detect_profile() to iterate BROWSER_PREFERENCE_ORDER and return BROWSER_PROFILE_DIR for preferred or specified browser in scripts/browser-cleanup.sh
- [x] T028 [US3] Refactor _bc_detect_browser_type() to use BROWSER_NAME array for display names in scripts/browser-cleanup.sh
- [x] T029 [US3] Refactor _bc_is_browser_running() to use BROWSER_PROCESS_NAME with pgrep in scripts/browser-cleanup.sh
- [x] T030 [US3] Add --all and --browser flags to argument parsing — --all iterates all installed browsers, --browser targets one by short name, default uses get_preferred_browser() in scripts/browser-cleanup.sh
- [x] T031 [US3] Update all user-facing output messages to include BROWSER_NAME[$browser] instead of hardcoded "Chromium" in scripts/browser-cleanup.sh

**Checkpoint**: `browser-cleanup.sh` with Edge only → cleans Edge.
With `--all` and both installed → cleans both. Edge running → refuses
with "Microsoft Edge" in warning message.

---

## Phase 5: User Story 4 — GETTING-STARTED Guides Mention Edge (Priority: P3)

**Goal**: Both getting-started guides mention Edge as a supported
alternative to Chromium.

**Independent Test**: Read the browser section in each guide, verify Edge
is mentioned with `brew install --cask microsoft-edge`.

- [x] T032 [P] [US4] Add Edge as supported alternative in the Chromium/browser section of GETTING-STARTED.md — include `brew install --cask microsoft-edge` command and note that all browser security checks apply equally
- [x] T033 [P] [US4] Add Edge as supported alternative in the Chromium/browser section of GETTING-STARTED-INTEL.md — same content as T032

**Checkpoint**: Both guides mention Edge with correct install command.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation updates, consistency checks, and validation.

- [x] T034 [P] Rename 8 check IDs from CHK-CHROMIUM-* to CHK-BROWSER-* in scripts/CHK-REGISTRY.md
- [x] T035 Update section 2.11 heading from "Browser Security (Chromium)" to "Browser Security (Chromium / Chrome / Edge)" and update browser-specific references throughout section in docs/HARDENING.md
- [x] T036 Update coverage summary table and inline badges to reflect CHK-BROWSER-* IDs in docs/HARDENING.md
- [x] T037 Update audit check reference table near end of file to reflect CHK-BROWSER-* IDs in docs/HARDENING.md
- [x] T038 Run shellcheck on scripts/hardening-audit.sh, scripts/hardening-fix.sh, and scripts/browser-cleanup.sh — fix any warnings
- [x] T039 Test-operator walkthrough: run full audit and fix with only Chromium installed — verify backward compatibility (FR-010, SC-003)

---

## Dependencies & Execution Order

### Phase Dependencies

```text
Phase 1: Foundational ─── no dependencies, start immediately
    │
    ├── Phase 2: US1 (P1) ─── depends on Phase 1
    │       │
    │       └── Phase 3: US2 (P1) ─── depends on Phase 2 (needs parameterized functions)
    │
    ├── Phase 4: US3 (P2) ─── depends on Phase 1 only (cleanup is independent)
    │
    ├── Phase 5: US4 (P3) ─── no code dependencies (documentation only)
    │
    └── Phase 6: Polish ─── depends on Phases 2-5 (documents final state)
```

### User Story Dependencies

- **US1 (P1)**: Depends on Foundational. No dependencies on other stories.
- **US2 (P1)**: Depends on US1 — iteration wrapper needs parameterized
  functions. Cannot run in parallel with US1.
- **US3 (P2)**: Depends on Foundational only. Can run in parallel with
  US1/US2 (different file: browser-cleanup.sh).
- **US4 (P3)**: No code dependencies. Can run in parallel with any phase.

### Parallel Opportunities

```text
After Phase 1 completes:
  ┌─ Phase 2 (US1) in hardening-audit.sh + hardening-fix.sh
  │
  ├─ Phase 4 (US3) in browser-cleanup.sh  ← PARALLEL with US1
  │
  └─ Phase 5 (US4) in GETTING-STARTED*.md ← PARALLEL with US1
```

Within Phase 1 (Foundational):
- T002, T003, T004 are [P] — can run in parallel after T001 (different files)

Within Phase 5 (US4):
- T032 and T033 are [P] — different files

---

## Parallel Example: Fastest Execution Path

```text
# Step 1: Create shared registry, then source it (T001 first, then T002-T004 parallel)
T001: Create scripts/browser-registry.sh
T002: Source registry in hardening-audit.sh   [P]
T003: Source registry in hardening-fix.sh     [P]
T004: Source registry in browser-cleanup.sh   [P]

# Step 2: US1 audit + US3 cleanup + US4 docs in parallel (3 tracks)
Track A: T005-T017 (audit refactor in hardening-audit.sh)
Track B: T027-T031 (cleanup refactor in browser-cleanup.sh)  [P]
Track C: T032-T033 (getting-started guides)                   [P]

# Step 3: US1 fix + US2 audit (depends on Step 2 Track A)
Track A: T018-T023 (fix refactor in hardening-fix.sh)
Track B: T024-T025 (audit iteration wrapper)

# Step 4: US2 fix iteration
T026 (fix iteration in hardening-fix.sh)

# Step 5: Polish (depends on all above)
T034-T039 (docs + shellcheck + walkthrough)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Foundational (registry in all scripts)
2. Complete Phase 2: US1 (audit + fix parameterization)
3. **STOP and VALIDATE**: Run audit with Edge installed, verify all 8
   checks detect Edge and all fixes apply to Edge's plist domain
4. This is deployable — single-browser support works for any browser

### Incremental Delivery

1. Phase 1 (Foundational) → Registry in place
2. Phase 2 (US1) → Any single browser works → **MVP deployable**
3. Phase 3 (US2) → Multiple browsers work simultaneously
4. Phase 4 (US3) → Cleanup works for any/all browsers
5. Phase 5 (US4) → Guides updated
6. Phase 6 (Polish) → Full documentation consistency

### Requirement Coverage

| Requirement | Task(s) | Story |
|-------------|---------|-------|
| FR-001 (registry metadata) | T001-T004 | Foundational |
| FR-002 (3 browsers, extensible) | T001 | Foundational |
| FR-003 (refactor 8 checks) | T005-T014 | US1 |
| FR-004 (iterate installed browsers) | T024-T025 | US2 |
| FR-005 (fix all detected browsers) | T026 | US2 |
| FR-006 (rename CHK IDs) | T015, T018, T034 | US1 + Polish |
| FR-007 (cleanup + --all flag) | T027-T031 | US3 |
| FR-008 (CHK-REGISTRY.md) | T034 | Polish |
| FR-009 (HARDENING.md badges) | T035-T037 | Polish |
| FR-010 (backward compat) | T039 | Polish |
| FR-011 (guides mention Edge) | T032-T033 | US4 |

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story is independently testable at its checkpoint
- Commit after each phase or logical task group
- Stop at any checkpoint to validate story independently
- All 3 scripts source scripts/browser-registry.sh (shared per Rule-of-Three: 3 browsers = extract)
