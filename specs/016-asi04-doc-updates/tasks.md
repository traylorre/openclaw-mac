# Tasks: ASI04 Documentation Updates

**Input**: Design documents from `/specs/016-asi04-doc-updates/`
**Prerequisites**: plan.md (required), spec.md (required)

**Tests**: Not applicable — verification via grep and markdownlint.

**Organization**: Tasks grouped by user story (each file is one story).

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

**Purpose**: Verify preconditions

- [ ] T001 Verify `N8N_BLOCK_ENV_ACCESS_IN_NODE=true` is the current deployed state by checking the running container: `docker exec openclaw-n8n env | grep N8N_BLOCK_ENV_ACCESS_IN_NODE`
- [ ] T002 Verify no historical specs will be touched: confirm working tree is clean via `git status`

---

## Phase 2: User Story 1 - Update ASI-MAPPING.md (Priority: P1)

**Goal**: Remove stale `=false` references from ASI02 and ASI04 sections, mark remediation complete

**Independent Test**: `grep "N8N_BLOCK_ENV_ACCESS_IN_NODE=false" docs/ASI-MAPPING.md` returns zero matches

### Implementation for User Story 1

- [ ] T003 [US1] Update ASI02 residual risk (line 49 of `docs/ASI-MAPPING.md`): change "`N8N_BLOCK_ENV_ACCESS_IN_NODE=false` weakens Code Node isolation" to reflect `=true` is now deployed, noting this mitigation is in place
- [ ] T004 [US1] Update ASI04 residual risk (lines 92-93 of `docs/ASI-MAPPING.md`): remove or update the sentence about `=false` allowing credential decryption, note `=true` blocks Code node env access
- [ ] T005 [US1] Reassess ASI04 residual severity (line 95 of `docs/ASI-MAPPING.md`): evaluate whether High can be reduced to Medium given `=true` is deployed (remaining risks: binary provenance, supply chain)
- [ ] T006 [US1] Mark ASI04 remediation item #1 as complete (line 99 of `docs/ASI-MAPPING.md`): add "COMPLETE (PR #104, 2026-03-28)" or similar marker

**Checkpoint**: ASI-MAPPING.md accurately reflects deployed state

---

## Phase 3: User Story 2 - Update TRUST-BOUNDARY-MODEL.md (Priority: P1)

**Goal**: Update TZ5 known gap and remediation roadmap to reflect `=true`

**Independent Test**: `grep "N8N_BLOCK_ENV_ACCESS_IN_NODE=false" docs/TRUST-BOUNDARY-MODEL.md` returns zero matches

### Implementation for User Story 2

- [ ] T007 [P] [US2] Update TZ5 known gap ADV-009 (line 77 of `docs/TRUST-BOUNDARY-MODEL.md`): revise to note env access is now blocked (`=true`), remove the `=false` reference
- [ ] T008 [P] [US2] Update remediation roadmap (line 78 of `docs/TRUST-BOUNDARY-MODEL.md`): mark env access remediation as complete, remove M5 target for that item, keep remaining items (digest pinning)

**Checkpoint**: Trust boundary model reflects current attack surface

---

## Phase 4: User Story 3 - Clean Docker Compose Comments (Priority: P2)

**Goal**: Remove stale M3 trade-off documentation from docker-compose template

**Independent Test**: Read `scripts/templates/docker-compose.yml` lines 63-69 — no reference to `=false` trade-off

### Implementation for User Story 3

- [ ] T009 [US3] Update comments on lines 63-69 of `scripts/templates/docker-compose.yml`: replace the M3 `=false` trade-off explanation with a brief note that `=true` is the secure default (env access blocked), with historical note referencing M3/PR #104

**Checkpoint**: Docker compose template comments are accurate

---

## Phase 5: Polish & Verification

**Purpose**: Final validation

- [ ] T010 Run `grep -r "N8N_BLOCK_ENV_ACCESS_IN_NODE=false" docs/ scripts/templates/` — expect zero matches
- [ ] T011 Verify no historical specs were modified: `git diff --name-only specs/014- specs/012- specs/011- specs/001-` — expect empty output
- [ ] T012 Run markdownlint on modified files to verify formatting

---

## Dependencies & Execution Order

- **Phase 1**: No dependencies
- **Phase 2 (US1)**: Depends on Phase 1
- **Phase 3 (US2)**: Can run in parallel with Phase 2 (different file)
- **Phase 4 (US3)**: Can run in parallel with Phase 2 and 3 (different file)
- **Phase 5**: Depends on all user stories complete

### Parallel Opportunities

- T003-T006 (US1), T007-T008 (US2), and T009 (US3) operate on different files and can run in parallel

---

## Notes

- Pure documentation edits — no code changes, no runtime impact
- All changes are to "living docs" that are expected to be updated as the system evolves
- Historical specs are frozen design records and must not be modified

## Adversarial Review #3

| Aspect | Finding |
|--------|---------|
| Highest-risk task | T005 (ASI04 severity reassessment) — requires judgment about remaining risk level |
| Most likely rework | T004 (ASI04 residual risk wording) — phrasing the new risk statement may need iteration |
| Security | No security impact — these are documentation corrections that improve risk accuracy |
| 3am scenario | N/A — documentation edits have no runtime behavior |
| 6-month neglect | If the setting changes again in the future, these docs will need re-updating |

**READY FOR IMPLEMENTATION** — 0 CRITICAL, 0 HIGH. All 6 requirements covered by 12 tasks.
