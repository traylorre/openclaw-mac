# Tasks: Hardening Guide Coverage Map

**Input**: Design documents from `/specs/004-hardening-coverage-map/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md

**Tests**: Not requested. No test tasks included.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: No project initialization needed — this feature modifies existing files only.

*No tasks in this phase.*

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Fix naming inconsistency and sync the registry before any badges can be assigned. These tasks MUST complete before badge work begins because badge assignment depends on accurate CHK-* data.

- [x] T001 Rename `CHK-LISTENERS-BASELINE` to `CHK-LISTENER-BASELINE` in `scripts/hardening-audit.sh` (FR-013)
- [x] T002 [P] Add `CHK-PASSWORD-POLICY` entry to `scripts/CHK-REGISTRY.md` with severity WARN, deployment both, guide section §2.6, auto-fix no (FR-014)
- [x] T003 [P] Add `CHK-SCRIPT-INTEGRITY` entry to `scripts/CHK-REGISTRY.md` with severity WARN, deployment both, guide section §10.1, auto-fix no (FR-014)
- [x] T004 Add `Auto-Fix` column to all existing entries in `scripts/CHK-REGISTRY.md` by cross-referencing `FIX_REGISTRY` in `scripts/hardening-fix.sh` (FR-015)

**Checkpoint**: Registry is complete (zero omissions), naming is consistent, Auto-Fix column present. Validates SC-003.

---

## Phase 3: User Story 1 — Stakeholder Reviews Coverage at a Glance (Priority: P1) MVP

**Goal**: Add coverage summary block and inline badges to HARDENING.md so a stakeholder can see automation coverage at a glance.

**Independent Test**: Open `docs/HARDENING.md` on GitHub; verify (a) coverage summary table appears immediately after ToC, (b) every §2.x–§10.x subsection heading has a badge, (c) summary counts match badge counts.

### Implementation for User Story 1

- [x] T005 [US1] Add coverage summary table immediately after Table of Contents in `docs/HARDENING.md` with per-section breakdowns for §2–§10, aggregate totals, and links to `scripts/` and `GETTING-STARTED.md` (FR-001, FR-002, FR-008, FR-010)
- [x] T006 [US1] Add inline badges to all §2 OS Foundation subsection headings (§2.1–§2.11) in `docs/HARDENING.md` using badge resolution rules from data-model.md (FR-003, FR-009, FR-012)
- [x] T007 [P] [US1] Add inline badges to all §3 Network Security subsection headings (§3.1–§3.6) in `docs/HARDENING.md` (FR-003, FR-009)
- [x] T008 [P] [US1] Add inline badges to all §4 Container Isolation subsection headings (§4.1–§4.5) in `docs/HARDENING.md` (FR-003, FR-009, FR-012)
- [x] T009 [P] [US1] Add inline badges to all §5 n8n Platform Security subsection headings (§5.1–§5.9) in `docs/HARDENING.md` (FR-003, FR-009)
- [x] T010 [P] [US1] Add inline badges to all §6 Bare-Metal Path subsection headings (§6.1–§6.4) in `docs/HARDENING.md` (FR-003, FR-009)
- [x] T011 [P] [US1] Add inline badges to all §7 Data Security subsection headings (§7.1–§7.11) in `docs/HARDENING.md` (FR-003, FR-009)
- [x] T012 [P] [US1] Add inline badges to all §8 Detection and Monitoring subsection headings (§8.1–§8.7) in `docs/HARDENING.md` (FR-003, FR-009)
- [x] T013 [P] [US1] Add inline badges to all §9 Response and Recovery subsection headings (§9.1–§9.5) in `docs/HARDENING.md` (FR-003, FR-009)
- [x] T014 [P] [US1] Add inline badges to all §10 Operational Maintenance subsection headings (§10.1–§10.6) in `docs/HARDENING.md` (FR-003, FR-009)
- [x] T015 [US1] Verify §1 Threat Model, §11 Audit Script Reference, and Appendices A–E have NO badges in `docs/HARDENING.md` (FR-011)
- [x] T016 [US1] Verify coverage summary counts match actual badge counts by grepping `docs/HARDENING.md` for each badge type and comparing to summary table (SC-002)

**Checkpoint**: HARDENING.md has a coverage summary and all 58 subsections are badged. Validates SC-001, SC-002, SC-004, SC-005, SC-006.

---

## Phase 4: User Story 2 — Maintainer Syncs CHK-REGISTRY (Priority: P1)

**Goal**: Ensure the registry has zero omissions and includes the Auto-Fix column.

**Independent Test**: Extract all `CHK-*` identifiers from `hardening-audit.sh` via grep; compare against `CHK-REGISTRY.md` rows. Sets must match exactly.

### Implementation for User Story 2

- [x] T017 [US2] Verify registry completeness: extract all `local id="CHK-` from `scripts/hardening-audit.sh`, compare against `scripts/CHK-REGISTRY.md`, and confirm zero omissions (SC-003)

**Checkpoint**: Registry is 100% synced with audit script. This was substantially completed in Phase 2 (T002–T004); T017 is the verification step.

---

## Phase 5: User Story 3 — Operator Understands Badge Meaning (Priority: P2)

**Goal**: Add badge definitions to the Notation Conventions table so badges are self-explanatory.

**Independent Test**: Read the Notation Conventions table in HARDENING.md and verify all three badge types are defined with one-line descriptions.

### Implementation for User Story 3

- [x] T018 [US3] Add three badge definitions (`[AUTO-FIX]`, `[AUDIT-ONLY]`, `[MANUAL]`) to the Notation Conventions table in `docs/HARDENING.md` (FR-004)

**Checkpoint**: Any reader encountering a badge can look up its meaning in the Notation Conventions table.

---

## Phase 6: User Story 4 — Security Reviewer Finds Weakest Layers (Priority: P2)

**Goal**: Coverage summary highlights low-coverage sections so a reviewer can prioritize gap closure.

**Independent Test**: Read the coverage summary table and identify the three sections with the lowest automation percentage without scrolling further.

### Implementation for User Story 4

*No additional tasks needed.* The coverage summary table (T005) already includes per-section breakdowns with coverage percentages. SC-006 (three weakest sections identifiable) is validated by T016.

**Checkpoint**: Validated by T005 and T016.

---

## Phase 7: User Story 5 — Guide Links Back to Scripts (Priority: P3)

**Goal**: Automated sections reference their CHK-* identifiers so technical readers can navigate to the implementation.

**Independent Test**: For any `[AUTO-FIX]` section, find the CHK-* identifier and verify it exists in both `hardening-audit.sh` and `hardening-fix.sh`.

### Implementation for User Story 5

- [ ] T019 [US5] For each section badged `[AUTO-FIX]` or `[AUDIT-ONLY]` in `docs/HARDENING.md`, ensure the section body contains a reference to its CHK-* identifier(s) — add if missing (FR-007)
- [ ] T020 [US5] Verify all referenced CHK-* identifiers exist in `scripts/hardening-audit.sh` and, for auto-fix sections, also in `scripts/hardening-fix.sh`

**Checkpoint**: Technical readers can navigate from any badged section to the corresponding script implementation.

---

## Phase 8: Polish and Cross-Cutting Concerns

**Purpose**: Final validation and cleanup across all modified files.

- [ ] T021 Run markdownlint on `docs/HARDENING.md` and fix any violations introduced by badges or coverage summary
- [ ] T022 [P] Run markdownlint on `scripts/CHK-REGISTRY.md` and fix any violations
- [x] T023 Verify `scripts/hardening-audit.sh` passes `bash -n` syntax check after the identifier rename (T001)
- [ ] T024 Commit all changes and create PR with summary of coverage statistics

---

## Dependencies and Execution Order

### Phase Dependencies

- **Phase 2 (Foundational)**: No dependencies — can start immediately. BLOCKS all badge work.
- **Phase 3 (US1)**: Depends on Phase 2 completion (needs accurate CHK data for badge assignment)
- **Phase 4 (US2)**: Depends on Phase 2 completion (verification of registry sync)
- **Phase 5 (US3)**: Independent — can run in parallel with Phase 3
- **Phase 6 (US4)**: No additional tasks — satisfied by Phase 3
- **Phase 7 (US5)**: Depends on Phase 3 completion (needs badges in place to add CHK references)
- **Phase 8 (Polish)**: Depends on all previous phases

### User Story Dependencies

- **US1 (P1)**: Depends on Foundational (Phase 2) — primary deliverable
- **US2 (P1)**: Depends on Foundational (Phase 2) — mostly completed in Phase 2, T017 verifies
- **US3 (P2)**: Independent — can start any time
- **US4 (P2)**: No tasks — satisfied by US1 coverage summary
- **US5 (P3)**: Depends on US1 completion (needs badges in place)

### Parallel Opportunities

- T002, T003 can run in parallel (different registry entries)
- T007–T014 can all run in parallel (different sections of HARDENING.md)
- T018 (US3) can run in parallel with T006–T014 (different section of HARDENING.md)
- T021, T022 can run in parallel (different files)

---

## Parallel Example: User Story 1

```bash
# After Phase 2 is complete, launch all section badge tasks together:
Task: "Add badges to §3 subsections in docs/HARDENING.md"   # T007
Task: "Add badges to §4 subsections in docs/HARDENING.md"   # T008
Task: "Add badges to §5 subsections in docs/HARDENING.md"   # T009
Task: "Add badges to §6 subsections in docs/HARDENING.md"   # T010
Task: "Add badges to §7 subsections in docs/HARDENING.md"   # T011
Task: "Add badges to §8 subsections in docs/HARDENING.md"   # T012
Task: "Add badges to §9 subsections in docs/HARDENING.md"   # T013
Task: "Add badges to §10 subsections in docs/HARDENING.md"  # T014
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 2: Foundational (registry sync + naming fix)
2. Complete Phase 3: User Story 1 (coverage summary + all badges)
3. **STOP and VALIDATE**: Open HARDENING.md on GitHub and verify
4. This alone delivers the primary value — at-a-glance coverage visibility

### Incremental Delivery

1. Phase 2 → Registry is clean and complete
2. Phase 3 (US1) → Coverage summary + badges visible (MVP)
3. Phase 5 (US3) → Badge legend in notation table
4. Phase 7 (US5) → CHK-* cross-references in section bodies
5. Phase 8 → Polish and PR

---

## Notes

- All badge tasks edit `docs/HARDENING.md` — parallel execution requires careful merge or sequential application per section
- T006 (§2) is NOT marked [P] because §2 has the most complex badge assignments (mixed-coverage sections §2.6 and §2.11) — do it first as a template
- The coverage summary (T005) should be written last within Phase 3, after all badges are in place, so counts are accurate
- Total tasks: 24
