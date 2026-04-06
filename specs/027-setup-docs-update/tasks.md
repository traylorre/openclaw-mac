# Tasks: GETTING-STARTED.md Update (Feature 027)

**Input**: Design documents from `/specs/027-setup-docs-update/`
**Prerequisites**: Features 028, 029, 030 must be implemented first

---

## Phase 1: Setup

- [ ] T001 Read current `GETTING-STARTED.md` structure to identify exact insertion points
- [ ] T002 Verify `docs/BEHAVIORS.md`, `docs/SECURITY-VALUE.md`, `docs/FEATURE-COMPARISON.md` exist

---

## Phase 2: Foundational (TL;DR + Step 2 modifications)

- [ ] T003 Add `make doctor` to TL;DR between `make install` and `make audit` (5th of 6 commands now) per REQ-01 in `GETTING-STARTED.md`
- [ ] T004 Add `make doctor` validation checkpoint to Step 2 with note on what to do if issues found per REQ-01 in `GETTING-STARTED.md`

**Checkpoint**: Existing flow enhanced with validation. Nothing moved or removed.

---

## Phase 3: User Story 1 — Post-M1 Setup Path (P1)

**Goal**: US-01 — Forker knows what's next after Step 4

- [ ] T005 [US1] Write "Step 5: Workspace Integrity" section between Step 4 and "What was changed." Cover `make integrity-deploy` → `make integrity-lock` → `make monitor-setup` in dependency order per REQ-02 in `GETTING-STARTED.md`
- [ ] T006 [US1] Add callout in Step 5: "After this step, workspace files will be locked. See [BEHAVIORS.md](docs/BEHAVIORS.md) for how to edit protected files." per plan Clarification Q2 in `GETTING-STARTED.md`
- [ ] T007 [US1] Write "Step 6: sudoers secure_path" section with `EDITOR=nano sudo visudo` command, safety warning, and exact line to add per REQ-03 in `GETTING-STARTED.md`

---

## Phase 4: User Story 2 — Prerequisites Validation (P2)

**Goal**: US-02 — `make doctor` catches missing prerequisites early

- [ ] T008 [US2] Add dangerous env vars callout (blockquote) near Step 5: NODE_OPTIONS, DYLD_*, PYTHONPATH block agent startup per REQ-04 in `GETTING-STARTED.md`
- [ ] T009 [US2] Write "Package Managers" section explaining Homebrew/npm/Bun and why all 3 are needed, placed after Step 6 per REQ-05 in `GETTING-STARTED.md`

---

## Phase 5: User Story 3 — File Locking Awareness (P3)

**Goal**: US-03 — Forker understands files will be locked

- [ ] T010 [US3] Add cross-references to BEHAVIORS.md (028), SECURITY-VALUE.md (029), FEATURE-COMPARISON.md (030) in Next Steps section per REQ-06 in `GETTING-STARTED.md`
- [ ] T011 [US3] Add "Operation not permitted" troubleshooting entry with brief explanation and link to BEHAVIORS.md per REQ-08 in `GETTING-STARTED.md`

---

## Phase 6: Polish

- [ ] T012 Verify TL;DR has at most 6 commands per REQ-07 in `GETTING-STARTED.md`
- [ ] T013 Run `npx markdownlint-cli2 GETTING-STARTED.md` and fix violations
- [ ] T014 Final REQ checklist: verify all 8 requirements satisfied

---

## Summary

| Metric | Value |
|--------|-------|
| Total tasks | 14 |
| File modified | `GETTING-STARTED.md` (existing) |
| New sections added | 4 (Step 5, Step 6, env vars callout, Package Managers) |
| Existing sections modified | 3 (TL;DR, Next Steps, Troubleshooting) |

---

## Adversarial Review #3

**Reviewed:** 2026-04-06

### Readiness

| Check | Status |
|-------|--------|
| All 8 REQs covered | **PASS** |
| All 3 user stories have phases | **PASS** |
| TL;DR simplicity preserved (REQ-07) | **PASS** — max 6 commands |
| Insertion points specific | **PASS** — "between Step 4 and What was changed" |
| visudo safety covered | **PASS** — EDITOR=nano + warning (T007) |
| Cross-references to 028+029+030 | **PASS** (T010) |

### Highest-Risk Task

**T005** — Inserting Step 5 into the middle of an existing document. Must preserve section numbering and internal links. The "What was changed" and "Next steps" sections shift down.

### Gate Statement

**0 CRITICAL, 0 HIGH remaining. READY FOR IMPLEMENTATION.**
