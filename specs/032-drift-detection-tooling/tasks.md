# Tasks: Drift Detection Tooling (032)

## Phase 1: Setup

- [ ] T001 Install Vale via Homebrew: add `brew "vale"` to `~/dotfiles/Brewfile` and run `brew install vale`

## Phase 2: Vale Prose Linter (US-01)

- [ ] T002 [US1] Create `.vale.ini` in repo root with MinAlertLevel, StylesPath, glob config, and ignore patterns
- [ ] T003 [P] [US1] Create `styles/OpenClaw/NistFormat.yml` — warn on NIST family IDs missing hyphens (e.g., "SC28" instead of "SC-28")
- [ ] T004 [P] [US1] Create `styles/OpenClaw/VersionPinning.yml` — warn on standard references without version/date in structured sections
- [ ] T005 [P] [US1] Create `styles/OpenClaw/NemoClawDateQualifier.yml` — warn on "Not documented in NemoClaw" without "as of YYYY-MM-DD"
- [ ] T006 [P] [US1] Create `styles/OpenClaw/RejectTSP.yml` — flag bare "TSP" without AICPA/Trust Services context
- [ ] T007 [US1] Add `vale` target to Makefile
- [ ] T008 [US1] Run `make vale` and tune rules to eliminate false positives on existing docs

## Phase 3: spec-check (US-02)

- [ ] T009 [US2] Add `spec-check` target to Makefile — inline bash extracting CHK-* from docs, verifying against hardening-audit.sh
- [ ] T010 [US2] Run `make spec-check` and verify zero false positives

## Phase 4: markdown-link-check (US-03)

- [ ] T011 [US3] Create `.markdown-link-check.json` with retry, timeout, alive status codes, ignore patterns
- [ ] T012 [US3] Add `link-check` target to Makefile — npx markdown-link-check, WARN-only
- [ ] T013 [US3] Run `make link-check` and evaluate false positive rate

## Phase 5: Polish

- [ ] T014 Run all 3 new targets plus existing `markdownlint` to verify no conflicts
- [ ] T015 Verify Makefile passes markdownlint (if applicable) and shellcheck (if targets use inline bash)

## Summary

| Metric | Value |
|--------|-------|
| Total tasks | 15 |
| Files created | 7 (.vale.ini, 4 styles, .markdown-link-check.json, Brewfile edit) |
| Files modified | 1 (Makefile) |
| New dependencies | 1 (vale via Homebrew) |

## Adversarial Review #3

All REQs covered. Highest risk: Vale false positives on existing docs (T008). Most likely rework: VersionPinning rule scope. **READY FOR IMPLEMENTATION.**
