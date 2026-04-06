# Tasks: SECURITY-VALUE.md (Feature 029)

**Input**: Design documents from `/specs/029-security-value-doc/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, quickstart.md

**Tests**: Not applicable — documentation-only feature. Validation is markdownlint CI + link verification.

**Organization**: Tasks grouped by user story. Each story adds incremental value to the same document.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different sections, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: Create file skeleton and validate environment

- [ ] T001 Create `docs/SECURITY-VALUE.md` with document title, scope statement, and section headers per data-model.md layout
- [ ] T002 Verify markdownlint configuration supports new file: run `npx markdownlint-cli2 docs/SECURITY-VALUE.md`

**Checkpoint**: Empty skeleton file exists and passes linting

---

## Phase 2: Foundational (Control Matrix)

**Purpose**: The Control Matrix table is the core artifact that ALL three user stories depend on. Must be complete before any story-specific sections.

**CRITICAL**: No user story work can begin until the Control Matrix is populated.

- [ ] T003 Write the Control Matrix table header row with 7 columns: Control | Threat | NIST Family | TSC Category | Layer | Implementation | Value — per REQ-05 in `docs/SECURITY-VALUE.md`
- [ ] T004 [P] Write Control Matrix row: Filesystem Immutability (uchg) — map to SC-28/CM-5/SI-7, Security (CC6.1), Prevent, CHK-OPENCLAW-INTEGRITY-LOCK per research.md Section 1.1 in `docs/SECURITY-VALUE.md`
- [ ] T005 [P] Write Control Matrix row: Cryptographic Integrity (HMAC-SHA256) — map to SI-7/SC-13/AU-10, Processing Integrity (PI1.1), Detect, CHK-PIPELINE-HMAC-CONSISTENCY per research.md Section 1.2 in `docs/SECURITY-VALUE.md`
- [ ] T006 [P] Write Control Matrix row: Continuous Monitoring (fswatch) — map to SI-4/IR-4/AU-6, Security (CC7.2), Detect, CHK-OPENCLAW-MONITOR-STATUS per research.md Section 1.3 in `docs/SECURITY-VALUE.md`
- [ ] T007 [P] Write Control Matrix row: Skill Allowlist (Supply Chain) — map to SR-4/SA-12/CM-7, Security+PI, Prevent, CHK-OPENCLAW-SKILLALLOW per research.md Section 1.4 in `docs/SECURITY-VALUE.md`
- [ ] T008 [P] Write Control Matrix row: Environment Variable Validation — map to CM-6/SA-8/AC-6, Security (CC6.1), Prevent, CHK-PIPELINE-ENV-VARS per research.md Section 1.5 in `docs/SECURITY-VALUE.md`
- [ ] T009 [P] Write Control Matrix row: Container Isolation — map to SC-7/SC-39/CM-7/AC-6, Security (CC6.1/CC6.3), Prevent+Respond, CHK-PIPELINE-CONTAINER-HARDENING per research.md Section 1.6 in `docs/SECURITY-VALUE.md`
- [ ] T010 [P] Write Control Matrix row: Audit Automation — map to CA-7/AU-2/SI-6, Security (CC7.1)+Availability (A1.2), Detect+Respond, CHK-LAUNCHD-AUDIT-JOB per research.md Section 1.7 in `docs/SECURITY-VALUE.md`
- [ ] T011 Write summary paragraph below Control Matrix noting "84+ additional checks cover macOS platform hardening, browser security, network controls, threat detection, and backup — see `make audit`" per Clarification Q1 in `docs/SECURITY-VALUE.md`

**Checkpoint**: Control Matrix table complete with 7 rows + summary. All user stories can now build on this foundation.

---

## Phase 3: User Story 1 — Forker Value Proposition (Priority: P1)

**Goal**: US-01 — Forker understands the security VALUE of each restriction

**Independent Test**: Read "Why This Matters" section alone — does each paragraph name a specific attack and the protection provided?

### Implementation for User Story 1

- [ ] T012 [US1] Write the "Why This Matters" section header and introductory paragraph in `docs/SECURITY-VALUE.md`
- [ ] T013 [P] [US1] Write narrative paragraph for filesystem immutability: "Without uchg, [attack]. With it, [protection]." per Clarification Q3 format in `docs/SECURITY-VALUE.md`
- [ ] T014 [P] [US1] Write narrative paragraph for cryptographic integrity: "Without HMAC, [attack]. With it, [protection]." in `docs/SECURITY-VALUE.md`
- [ ] T015 [P] [US1] Write narrative paragraph for continuous monitoring: "Without fswatch, [attack]. With it, [protection]." in `docs/SECURITY-VALUE.md`
- [ ] T016 [P] [US1] Write narrative paragraph for skill allowlist: "Without allowlist, [attack]. With it, [protection]." in `docs/SECURITY-VALUE.md`
- [ ] T017 [P] [US1] Write narrative paragraph for env var validation: "Without validation, [attack]. With it, [protection]." in `docs/SECURITY-VALUE.md`
- [ ] T018 [P] [US1] Write narrative paragraph for container isolation: "Without isolation, [attack]. With it, [protection]." in `docs/SECURITY-VALUE.md`
- [ ] T019 [P] [US1] Write narrative paragraph for audit automation: "Without automation, [attack]. With it, [protection]." in `docs/SECURITY-VALUE.md`
- [ ] T020 [US1] Write defense-in-depth chain explanation showing how Prevent+Detect+Respond controls work together (e.g., uchg prevents, HMAC detects, fswatch alerts) in `docs/SECURITY-VALUE.md`

**Checkpoint**: "Why This Matters" section complete. Forker can read this section alone and understand the value of every restriction.

---

## Phase 4: User Story 2 — Interview-Ready Citations (Priority: P2)

**Goal**: US-02 — Interviewer sees canonical citations justifying design decisions

**Independent Test**: Can someone point to every claim in the document and find its source standard with version?

### Implementation for User Story 2

- [ ] T021 [US2] Write the "Standards Referenced" table listing all cited standards with version, date, and URL per REQ-10 and research.md Section 6 in `docs/SECURITY-VALUE.md`
- [ ] T022 [US2] Write the Scope Boundary section explaining the relationship between SECURITY-VALUE.md (control-centric) and ASI-MAPPING.md (threat-centric) per REQ-08 in `docs/SECURITY-VALUE.md`
- [ ] T023 [US2] Verify all 7 external standard URLs resolve correctly using WebSearch/WebFetch per REQ-07
- [ ] T024 [US2] Add CIS Benchmark citation note: "Full benchmark documents require free CIS registration" per Clarification Q4 in `docs/SECURITY-VALUE.md`

**Checkpoint**: Every claim in the document traces to a version-pinned standard. Interviewer can verify any citation.

---

## Phase 5: User Story 3 — Security Professional Depth (Priority: P3)

**Goal**: US-03 — Security professional finds industry-standard terminology and framework mappings

**Independent Test**: Can a SOC 2 auditor or NIST assessor map this document's controls to their framework?

### Implementation for User Story 3

- [ ] T025 [US3] Write the OWASP LLM 2025 Mapping table with all 10 LLM risks (LLM01-LLM10), applicable controls, and "Not directly addressed" for gaps per REQ-09 and Clarification Q5 in `docs/SECURITY-VALUE.md`
- [ ] T026 [US3] Write the "Limitations and Exclusions" section listing security domains not addressed (network IDS, app-level auth, runtime memory protection, LLM risks LLM02/LLM04/LLM05/LLM08-10) per REQ-11 in `docs/SECURITY-VALUE.md`
- [ ] T027 [US3] Ensure all NIST family references in Control Matrix use correct identifiers (verify against research.md Section 2) in `docs/SECURITY-VALUE.md`
- [ ] T028 [US3] Ensure all TSC category references use correct AICPA terminology (Security CC6.x, Availability A1.x, Processing Integrity PI1.x) per REQ-02 in `docs/SECURITY-VALUE.md`

**Checkpoint**: Security professional can map every control to NIST 800-53r5 and AICPA TSC. OWASP LLM gaps are honestly acknowledged.

---

## Phase 6: Polish and Cross-Cutting Concerns

**Purpose**: Final quality pass across all sections

- [ ] T029 [P] Run `npx markdownlint-cli2 docs/SECURITY-VALUE.md` and fix any violations per Constitution IX (Markdown Quality Gate)
- [ ] T030 [P] Verify no content from ASI-MAPPING.md is duplicated — specifically check that MITRE ATLAS technique IDs (AML.T0051, etc.) are cross-referenced, not reproduced per REQ-08
- [ ] T031 Verify document is NOT marked "INTERNAL" per Clarification Q2 — confirm it's public-suitable
- [ ] T032 Final read-through: verify all 11 requirements (REQ-01 through REQ-11) are satisfied with a checklist pass
- [ ] T033 Run quickstart.md validation steps (markdownlint + internal cross-reference check)

---

## Dependencies and Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on T001 (skeleton file exists)
- **User Story 1 (Phase 3)**: Depends on Phase 2 (Control Matrix complete) — needs the matrix to reference
- **User Story 2 (Phase 4)**: Depends on Phase 2 — needs the matrix to cite standards for
- **User Story 3 (Phase 5)**: Depends on Phase 2 — needs the matrix to verify terminology in
- **Polish (Phase 6)**: Depends on all user story phases complete

### User Story Dependencies

- **US1 (P1)**: Depends on Foundational only — can start immediately after Phase 2
- **US2 (P2)**: Depends on Foundational only — can run in parallel with US1
- **US3 (P3)**: Depends on Foundational only — can run in parallel with US1 and US2
- **All three stories are independent** — they add different sections to the same document

### Within Each User Story

- Narrative/content tasks marked [P] can run in parallel (different paragraphs/sections)
- Verification tasks depend on content being written first

### Parallel Opportunities

- T004-T010: All 7 Control Matrix rows can be written in parallel
- T013-T019: All 7 narrative paragraphs can be written in parallel
- T029-T030: Both polish checks can run in parallel
- US1, US2, US3 can all proceed in parallel after Phase 2

---

## Parallel Example: Phase 2 (Control Matrix)

```bash
# All matrix rows can be written simultaneously:
Task T004: "Filesystem Immutability row"
Task T005: "Cryptographic Integrity row"
Task T006: "Continuous Monitoring row"
Task T007: "Skill Allowlist row"
Task T008: "Environment Variable Validation row"
Task T009: "Container Isolation row"
Task T010: "Audit Automation row"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T002)
2. Complete Phase 2: Control Matrix (T003-T011)
3. Complete Phase 3: "Why This Matters" narrative (T012-T020)
4. **STOP and VALIDATE**: Document answers "why?" for every control
5. This alone satisfies the primary user story (forker understanding)

### Incremental Delivery

1. Setup + Control Matrix → Foundation ready
2. Add "Why This Matters" → Forker value (MVP)
3. Add Citations + Standards → Interview-ready
4. Add OWASP LLM + Limitations → Security professional depth
5. Polish → CI-ready, merge-ready

---

## Summary

| Metric | Value |
|--------|-------|
| Total tasks | 33 |
| Phase 1 (Setup) | 2 tasks |
| Phase 2 (Foundational) | 9 tasks |
| Phase 3 (US1 — Forker) | 9 tasks |
| Phase 4 (US2 — Interviewer) | 4 tasks |
| Phase 5 (US3 — Security Pro) | 4 tasks |
| Phase 6 (Polish) | 5 tasks |
| Parallel opportunities | T004-T010 (7), T013-T019 (7), T029-T030 (2) |
| Suggested MVP scope | Phases 1-3 (US1 only: 20 tasks) |

## Notes

- All tasks operate on a single file: `docs/SECURITY-VALUE.md`
- No source code changes required
- No tests required (documentation feature)
- research.md is the primary data source for all content tasks
- Commit after each phase completion (4-6 commits total)

---

## Adversarial Review #3

**Reviewed:** 2026-04-06 | **Reviewer:** Battleplan AR pipeline | **Input:** spec.md + plan.md + tasks.md (full artifact suite)

### Implementation Readiness Assessment

| Check | Status | Notes |
|-------|--------|-------|
| All 11 REQs have task coverage | **PASS** | 100% coverage confirmed by /speckit.analyze |
| All 3 user stories have independent phases | **PASS** | US1→Phase 3, US2→Phase 4, US3→Phase 5 |
| Task dependencies are acyclic | **PASS** | Setup→Foundational→{US1,US2,US3}→Polish |
| All file paths are specific | **PASS** | Every task references `docs/SECURITY-VALUE.md` |
| research.md provides data for all content tasks | **PASS** | T004-T010 reference specific research.md sections |
| Constitution alignment maintained | **PASS** | "Contain" → "Respond" fix applied (analysis I1) |
| No unresolved clarification questions | **PASS** | 5/5 self-answered, 0 deferred |
| Markdownlint validation included | **PASS** | T002 (pre), T029 (post), T033 (quickstart) |
| Cross-reference with ASI-MAPPING.md | **PASS** | T022 (scope boundary), T030 (no duplication) |

### Highest-Risk Task

**T023** — Verify all 7 external standard URLs resolve correctly. Risk: URLs may change, be gated (CIS requires registration), or redirect. Mitigation: Clarification Q4 already addressed the CIS registration issue. WebSearch/WebFetch validation during implementation will catch broken links. If a URL breaks between planning and implementation, substitute with the organization's landing page.

### Most Likely Source of Rework

**Control Matrix table formatting (T003-T010)**. A 7-column markdown table is hard to read on narrow screens. The implementation may need to split into two tables (core mapping + detail) or use a different format. This is a presentation concern, not a content concern — the data is fully specified in research.md.

### Findings

| # | Severity | Finding | Resolution |
|---|----------|---------|------------|
| I1 | MEDIUM | "Contain" terminology fixed in analysis pass | **Resolved** — changed to "Respond" per Constitution VII |
| I2 | LOW | T029 REQ reference corrected in analysis pass | **Resolved** — changed to "Constitution IX" |
| M-006 | LOW | 7-column table may render poorly in narrow viewports | **Accepted** — implementer can adjust formatting (split table, abbreviate headers) without changing content requirements |

### Gate Statement

**0 CRITICAL remaining. 0 HIGH remaining.** All cross-artifact inconsistencies resolved. Tasks have 100% requirement coverage.

**READY FOR IMPLEMENTATION.**
