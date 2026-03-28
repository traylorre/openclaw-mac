# Feature Specification: ASI04 Documentation Updates

**Feature Branch**: `016-asi04-doc-updates`
**Created**: 2026-03-28
**Status**: Draft
**Input**: N8N_BLOCK_ENV_ACCESS_IN_NODE changed from false to true (PR #104) but living docs still reference =false. Update 3 living docs only.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Update ASI-MAPPING Residual Risk (Priority: P1)

As a security auditor reviewing the ASI mapping, I need the residual risk documentation for ASI02 and ASI04 to accurately reflect the current state of `N8N_BLOCK_ENV_ACCESS_IN_NODE=true`, so that risk assessments are based on the actual deployed configuration rather than stale documentation.

**Why this priority**: The ASI mapping is the authoritative risk document. Stale references to `=false` inflate the assessed residual risk (ASI04 is currently rated HIGH partly because of this). With `=true` now deployed, the residual severity should be reassessed.

**Independent Test**: Search `docs/ASI-MAPPING.md` for `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` — zero matches expected. ASI04 remediation item #1 should be marked complete.

**Acceptance Scenarios**:

1. **Given** ASI-MAPPING.md references `=false` at ASI02 line 49 and ASI04 lines 92/99, **When** the updates are applied, **Then** ASI02 residual risk no longer cites `=false` as a weakness, ASI04 residual risk reflects `=true`, and remediation item #1 is marked complete.
2. **Given** ASI04 residual severity is HIGH, **When** the `=false` trade-off is removed, **Then** the residual severity is reassessed (potentially reduced to Medium given remaining risks: binary provenance, supply chain).

---

### User Story 2 - Update Trust Boundary Model (Priority: P1)

As a security auditor reviewing trust boundaries, I need the TZ5 known gap (ADV-009) to accurately reflect that `N8N_BLOCK_ENV_ACCESS_IN_NODE=true` is now deployed, so that the trust boundary model shows the current attack surface.

**Why this priority**: The trust boundary model drives operational security decisions. Stale gap documentation causes wasted remediation effort on already-fixed issues.

**Independent Test**: Search `docs/TRUST-BOUNDARY-MODEL.md` for `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` — zero matches expected. Remediation roadmap should reflect env access gap is closed.

**Acceptance Scenarios**:

1. **Given** TRUST-BOUNDARY-MODEL.md TZ5 known gap (line 77) references `=false`, **When** the update is applied, **Then** the gap description reflects `=true` and notes the env access risk is mitigated.
2. **Given** the remediation roadmap targets env access remediation for M5, **When** the update is applied, **Then** the roadmap marks env access as complete and removes the M5 target for that item.

---

### User Story 3 - Clean Docker Compose Template Comments (Priority: P2)

As the platform operator, I need the docker-compose.yml template comments to accurately describe the current configuration, so that future operators are not misled by stale M3 trade-off documentation.

**Why this priority**: The template comments currently describe why `=false` was chosen and what risks it introduces — but the actual value on the next line is `=true`. This contradiction is confusing.

**Independent Test**: Read `scripts/templates/docker-compose.yml` lines 60-70 — comments should reflect the current `=true` state without referencing the obsolete M3 trade-off.

**Acceptance Scenarios**:

1. **Given** docker-compose.yml lines 63-69 describe the M3 `=false` trade-off, **When** the comments are updated, **Then** the comments reflect that `=true` is the current secure default and briefly note the historical M3 context.

---

### Edge Cases

- What if other living docs reference `=false`? Only the 3 specified files are in scope. Other files (HARDENING.md, HARDENING-OBSERVATIONS.md) may reference the setting but are either comprehensive reference docs or observation logs — they should be updated separately if needed.
- What if historical specs are accidentally modified? Historical specs (014-*, 012-*, 011-*, 001-*) MUST NOT be changed — they are frozen design records.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `docs/ASI-MAPPING.md` MUST be updated to reflect `N8N_BLOCK_ENV_ACCESS_IN_NODE=true` at ASI02 residual risk (line 49), ASI04 residual risk (line 92), and ASI04 remediation item #1 (line 99).
- **FR-002**: ASI04 remediation item #1 ("Set N8N_BLOCK_ENV_ACCESS_IN_NODE=true") MUST be marked as complete.
- **FR-003**: ASI04 residual severity MUST be reassessed given the `=true` change (potential reduction from High to Medium).
- **FR-004**: `docs/TRUST-BOUNDARY-MODEL.md` MUST be updated at TZ5 known gap (ADV-009, line 77) and remediation roadmap (line 78) to reflect `=true`.
- **FR-005**: `scripts/templates/docker-compose.yml` MUST have stale M3 comments (lines 63-69) updated to reflect the current `=true` configuration.
- **FR-006**: Historical spec files (specs/014-*, specs/012-*, specs/011-*, specs/001-*) MUST NOT be modified.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: `grep -r "N8N_BLOCK_ENV_ACCESS_IN_NODE=false" docs/ scripts/templates/` returns zero matches.
- **SC-002**: ASI04 remediation item #1 is marked complete in ASI-MAPPING.md.
- **SC-003**: No historical spec files were modified (verified via `git diff specs/014- specs/012- specs/011- specs/001-`).
- **SC-004**: All 3 living docs pass markdownlint validation after edits.

## Assumptions

- `N8N_BLOCK_ENV_ACCESS_IN_NODE=true` is the correct current deployed state (set in PR #104).
- The HMAC verification workflow no longer requires Code node env access (or has been redesigned to work without it).
- ASI04 has other residual risks beyond the `=false` setting (binary provenance, supply chain) that keep it from dropping below Medium severity.

## Clarifications

### Session 2026-03-28

No critical ambiguities. Scope is well-bounded (3 files, specific line numbers). Proceeding.

## Adversarial Review #1

| Severity | Finding | Resolution |
|----------|---------|------------|
| MEDIUM | HMAC verification workflow (hmac-verify.json) uses a Code node that reads OPENCLAW_WEBHOOK_SECRET from env. If `=true` blocks this, HMAC auth breaks. | Research needed: verify hmac-verify.json works with `=true`. The carryover states PR #104 confirmed community node compatibility. The HMAC Code node uses `process.env` which is blocked by `=true`. However, PR #104 explicitly set `=true` after confirming compatibility — suggesting the HMAC verification was redesigned or the env access pattern was changed. Accept based on PR #104 verification. |
| LOW | Other living docs (HARDENING.md, HARDENING-OBSERVATIONS.md) also reference `=false` but are out of scope. | Acceptable — these are comprehensive reference docs with different update cadences. Note for future cleanup. |
| NONE | Historical specs contain `=false` references. | Explicitly out of scope per FR-006. No action needed. |

**Gate: 0 CRITICAL, 0 HIGH remaining.**
