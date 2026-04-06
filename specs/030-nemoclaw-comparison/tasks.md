# Tasks: FEATURE-COMPARISON.md (Feature 030)

**Input**: Design documents from `/specs/030-nemoclaw-comparison/`
**Prerequisites**: plan.md, spec.md, Feature 029 SECURITY-VALUE.md (terminology dependency)

**Tests**: Not applicable — documentation feature. Validation is markdownlint CI + link verification.

---

## Phase 1: Setup

- [ ] T001 Create `docs/FEATURE-COMPARISON.md` with title, scope statement, and section headers per plan.md document structure
- [ ] T002 Verify Feature 029 `docs/SECURITY-VALUE.md` exists (terminology dependency)

---

## Phase 2: Foundational (Feature Matrix)

**CRITICAL**: Feature matrix is the core artifact for all 3 user stories.

- [ ] T003 Write "Comparison Methodology" section noting NemoClaw docs version, access date (2026-04-06), and approach per REQ-08 in `docs/FEATURE-COMPARISON.md`
- [ ] T004 Write Feature Matrix table header: Dimension | NemoClaw | openclaw-mac | NIST Family per REQ-01 in `docs/FEATURE-COMPARISON.md`
- [ ] T005 [P] Write matrix row: Filesystem Isolation — Landlock LSM vs uchg flags, NIST SC-28/CM-5 in `docs/FEATURE-COMPARISON.md`
- [ ] T006 [P] Write matrix row: Integrity Verification — "Not documented" vs HMAC-SHA256, NIST SI-7 in `docs/FEATURE-COMPARISON.md`
- [ ] T007 [P] Write matrix row: Supply Chain Controls — writable /sandbox vs skill allowlist, NIST SR-4/SA-12 in `docs/FEATURE-COMPARISON.md`
- [ ] T008 [P] Write matrix row: Runtime Monitoring — "Not documented" vs fswatch+heartbeat, NIST SI-4 in `docs/FEATURE-COMPARISON.md`
- [ ] T009 [P] Write matrix row: Network Policy — deny-by-default vs pf+HMAC webhook, NIST SC-7 in `docs/FEATURE-COMPARISON.md`
- [ ] T010 [P] Write matrix row: Credential Management — "Not documented" vs Keychain+Docker secrets, NIST SC-13 in `docs/FEATURE-COMPARISON.md`
- [ ] T011 [P] Write matrix row: Audit Automation — "Not documented" vs 84-check cron, NIST CA-7 in `docs/FEATURE-COMPARISON.md`
- [ ] T012 [P] Write matrix row: Prompt Injection Detection — "Not documented" vs skill hash mismatch, NIST SI-7 in `docs/FEATURE-COMPARISON.md`

**Checkpoint**: Feature matrix complete with 8 rows.

---

## Phase 3: User Story 1 — Forker Gap Understanding (Priority: P1)

**Goal**: US-01 — Forker understands what NemoClaw gaps this repo addresses

- [ ] T013 [US1] Write "What openclaw-mac Provides That NemoClaw Lacks" section with paragraphs for each of the 8 advantages (HMAC, skill allowlist, fswatch, audit, credentials, prompt injection, env vars, CVE registry) per REQ-05 in `docs/FEATURE-COMPARISON.md`
- [ ] T014 [US1] Write "What NemoClaw Provides That openclaw-mac Lacks" section with thorough treatment of 3 advantages (Landlock, deny-by-default network, seccomp) per REQ-05 and Clarification Q1 in `docs/FEATURE-COMPARISON.md`

**Checkpoint**: Bidirectional gap analysis complete. Forker understands both directions.

---

## Phase 4: User Story 2 — Interview Feature Matrix (Priority: P2)

**Goal**: US-02 — Interviewer sees NIST/AICPA TSC terminology in comparison

- [ ] T015 [US2] Verify all NIST family references in the feature matrix match terminology from SECURITY-VALUE.md (029) per REQ-03 in `docs/FEATURE-COMPARISON.md`
- [ ] T016 [US2] Add cross-reference links to SECURITY-VALUE.md (029) and ASI-MAPPING.md per REQ-09 in `docs/FEATURE-COMPARISON.md`
- [ ] T017 [US2] Verify all 4 NemoClaw documentation URLs resolve via WebSearch/WebFetch per REQ-07

**Checkpoint**: Every claim traceable to source documentation.

---

## Phase 5: User Story 3 — Security Professional Tradeoffs (Priority: P3)

**Goal**: US-03 — Security professional understands cloud vs local tradeoffs

- [ ] T018 [US3] Write "Complementary Controls" section showing how NemoClaw + openclaw-mac controls combine for defense-in-depth per REQ-06 in `docs/FEATURE-COMPARISON.md`
- [ ] T019 [US3] Use "Not documented in NemoClaw [version] as of [date]" language per Clarification Q2 — do not claim definitive absence in `docs/FEATURE-COMPARISON.md`
- [ ] T020 [US3] Ensure no "winner" per dimension — present facts, let reader decide per Clarification Q3 in `docs/FEATURE-COMPARISON.md`

**Checkpoint**: Security professional gets honest tradeoff analysis.

---

## Phase 6: Polish

- [ ] T021 [P] Run `npx markdownlint-cli2 docs/FEATURE-COMPARISON.md` and fix violations
- [ ] T022 [P] Verify no MITRE ATLAS or OWASP Agentic mappings duplicated from ASI-MAPPING.md per REQ-09
- [ ] T023 Final read-through: verify all 9 requirements (REQ-01 through REQ-09) satisfied

---

## Dependencies

- **Phase 1**: No dependencies
- **Phase 2**: Depends on T001 (skeleton) and T002 (029 exists)
- **Phases 3-5**: Depend on Phase 2 (matrix complete); can run in parallel
- **Phase 6**: Depends on all content phases

## Summary

| Metric | Value |
|--------|-------|
| Total tasks | 23 |
| Phase 1 (Setup) | 2 |
| Phase 2 (Foundational) | 10 |
| Phase 3 (US1 — Gaps) | 2 |
| Phase 4 (US2 — Citations) | 3 |
| Phase 5 (US3 — Tradeoffs) | 3 |
| Phase 6 (Polish) | 3 |
| Parallel opportunities | T005-T012 (8 matrix rows) |

---

## Adversarial Review #3

**Reviewed:** 2026-04-06 | **Input:** spec.md + plan.md + tasks.md

### Implementation Readiness

| Check | Status |
|-------|--------|
| All 9 REQs have task coverage | **PASS** |
| All 3 user stories have phases | **PASS** |
| NemoClaw URLs verified | **PASS** (3/4 verified; 4th pending implementation) |
| Terminology aligned with 029 | **PASS** |
| Bidirectional gap coverage | **PASS** (T013 + T014) |
| "Not documented" language specified | **PASS** (T019) |
| No winner/recommendation | **PASS** (T020) |

### Highest-Risk Task

**T002** — Dependency on Feature 029's SECURITY-VALUE.md existing. If 029 hasn't been implemented yet when 030 begins, the terminology references won't resolve. Mitigation: Implementation order is strictly 029 before 030.

### Most Likely Rework

**T005 (Filesystem Isolation row)** — Explaining the enforcement strength difference (kernel vs userspace) without appearing biased. Clarification Q1 provides the framing.

### Gate Statement

**0 CRITICAL, 0 HIGH remaining. READY FOR IMPLEMENTATION.**
