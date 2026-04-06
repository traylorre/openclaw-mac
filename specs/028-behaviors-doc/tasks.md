# Tasks: BEHAVIORS.md (Feature 028)

**Input**: Design documents from `/specs/028-behaviors-doc/`
**Prerequisites**: Feature 029 + 030 must be implemented first (cross-reference dependency)

---

## Phase 1: Setup

- [ ] T001 Create `docs/BEHAVIORS.md` with title, scope statement, and section headers
- [ ] T002 Verify `docs/SECURITY-VALUE.md` and `docs/FEATURE-COMPARISON.md` exist (cross-reference deps)

---

## Phase 2: Foundational (Before/After Table)

- [ ] T003 Write the "Before vs After" comparison table per REQ-01. Columns: Behavior | Before Hardening | After Hardening | Why (link). Cover: file editing, `sudo` usage, background processes, env vars, Keychain in `docs/BEHAVIORS.md`

**Checkpoint**: Reader immediately sees what changed.

---

## Phase 3: User Story 1 — "That's Weird" Behaviors (P1)

**Goal**: US-01 — Forker understands every surprising behavior

- [ ] T004 [US1] Write "Critical — Will Block You" section covering: uchg silent failures, missing Keychain key, NODE_OPTIONS blocking, sudo+make conflict, setup order per REQ-10 in `docs/BEHAVIORS.md`
- [ ] T005 [US1] Write "Good to Know — May Surprise You" section covering: 5-min grace period, manifest.json not versioned, repo-move breaks plists, audit cron schedule, Bash 5.x requirement per REQ-10 in `docs/BEHAVIORS.md`
- [ ] T006 [US1] Write "Services Running in Background" section listing both LaunchAgent/Daemon with schedules per REQ-06 in `docs/BEHAVIORS.md`
- [ ] T007 [US1] Write "Files Outside the Repo" section listing all 5 ~/.openclaw/ files + Keychain entry per REQ-07 in `docs/BEHAVIORS.md`

---

## Phase 4: User Story 2 — Editing Workflows (P2)

**Goal**: US-02 — Forker knows the correct workflow for protected files

- [ ] T008 [US2] Write "How to Edit a Protected File" workflow: `make integrity-unlock` → edit → `make integrity-lock` → `make manifest-update` per REQ-03 in `docs/BEHAVIORS.md`
- [ ] T009 [US2] Write "How to Add/Modify a Skill" workflow: unlock → edit → `make skillallow-add` → lock per REQ-04 in `docs/BEHAVIORS.md`

---

## Phase 5: User Story 3 — Sudo and Troubleshooting (P3)

**Goal**: US-03 — Forker understands sudo requirements and can self-diagnose errors

- [ ] T010 [US3] Write "What to Do When You See..." troubleshooting section with 5 error messages per REQ-05 in `docs/BEHAVIORS.md`
- [ ] T011 [US3] Write "Operations That Require sudo" subsection explaining which `make` targets need sudo and why in `docs/BEHAVIORS.md`

---

## Phase 6: Polish

- [ ] T012 Add cross-reference links to SECURITY-VALUE.md and FEATURE-COMPARISON.md per REQ-09 in `docs/BEHAVIORS.md`
- [ ] T013 Verify tone is practical per REQ-08 — each restriction has one-sentence "why" + "how to work within it"
- [ ] T014 Run `npx markdownlint-cli2 docs/BEHAVIORS.md` and fix violations
- [ ] T015 Final REQ checklist: verify all 10 requirements satisfied

---

## Summary

| Metric | Value |
|--------|-------|
| Total tasks | 15 |
| Parallel opportunities | T004-T007 (4 sections), T008-T009 (2 workflows) |
| MVP scope | Phases 1-3 (T001-T007: Before/After + gotchas) |

---

## Adversarial Review #3

**Reviewed:** 2026-04-06

### Readiness

| Check | Status |
|-------|--------|
| All 10 REQs covered | **PASS** |
| All 3 user stories have phases | **PASS** |
| Cross-references to 029+030 | **PASS** (T002 + T012) |
| Gotcha prioritization | **PASS** (T004 critical, T005 good-to-know) |
| 5 error messages enumerated | **PASS** (T010) |
| Make target names explicit | **PASS** (T008, T009) |

### Highest-Risk Task

**T003** — Before/After table scope. Must be concise enough to scan but comprehensive enough to cover key changes. Plan.md Phase 0 research provides the priority list.

### Gate Statement

**0 CRITICAL, 0 HIGH remaining. READY FOR IMPLEMENTATION.**
