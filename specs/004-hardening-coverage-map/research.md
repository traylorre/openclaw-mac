# Research: Hardening Coverage Map

**Date**: 2026-03-16
**Feature**: 004-hardening-coverage-map

## R-001: Exact Count of Missing Registry Entries

**Decision**: 2 entries are missing (not 10 as originally assumed).

**Rationale**: Deep audit on 2026-03-16 extracted all `CHK-*`
identifiers from `hardening-audit.sh` and cross-referenced against
`CHK-REGISTRY.md`. The 8 Chromium checks (CHK-CHROMIUM-*) were
already added in a prior PR. Only `CHK-PASSWORD-POLICY` and
`CHK-SCRIPT-INTEGRITY` are absent.

**Alternatives considered**: Original assumption of 10 missing was
based on an earlier conversation analysis before the Chromium checks
were added to the registry.

## R-002: Naming Inconsistency — LISTENER vs LISTENERS

**Decision**: Rename `CHK-LISTENERS-BASELINE` in audit script to
`CHK-LISTENER-BASELINE` to match the registry.

**Rationale**: The registry is the canonical source of CHK-*
identifiers. The audit script should conform to it. The singular
form `LISTENER` is consistent with the other baseline checks
(`PERSISTENCE-BASELINE`, `WORKFLOW-BASELINE`, `CERT-BASELINE`).

**Alternatives considered**: Rename the registry entry instead.
Rejected because the registry was published first and may be
referenced externally.

## R-003: CHK-SCRIPT-INTEGRITY Guide Section Mapping

**Decision**: Map CHK-SCRIPT-INTEGRITY to §10.1 (Automated Audit
Scheduling).

**Rationale**: Script integrity verification is part of operational
maintenance infrastructure. The check verifies that deployed scripts
match known-good hashes, which is a maintenance concern. §10.1
already covers the audit scheduling infrastructure, and script
integrity is a natural companion.

**Alternatives considered**: Create a new §10.7 for script integrity.
Rejected because the guide structure should not be modified in this
feature (FR-009).

## R-004: Badge Assignment for Mixed-Coverage Sections

**Decision**: Use the highest coverage level present. If at least one
check has auto-fix, badge is `[AUTO-FIX]`. List all CHK-* identifiers
in the section body so the reader can see the per-check breakdown.

**Rationale**: The badge answers the question "can I fix this by
running the fix script?" If any check in the section can be auto-
fixed, the answer is yes (partially). Listing all IDs with their
individual status gives the full picture without making the heading
badge overly complex.

**Affected sections**: §2.6 (3 checks, 2 auto-fix + 1 audit-only),
§2.11 (8 checks, 5 auto-fix + 3 audit-only), §4.3 (8 checks,
7 auto-fix + 1 audit-only).

**Alternatives considered**: Use lowest coverage level (most
conservative). Rejected because it understates the automation
available and would make all mixed sections look like they have no
automation.

## R-005: Coverage Summary Format

**Decision**: Use a markdown table with per-section rows and an
aggregate total row. Include columns for section name, total
subsections, automated (audit + fix), and manual.

**Rationale**: A table is scannable, renders well on GitHub, and
satisfies SC-005 (non-technical stakeholder comprehension) and
SC-006 (weakest sections identifiable).

**Format example**:

```markdown
| Section | Subsections | Automated | Manual | Coverage |
|---------|-------------|-----------|--------|----------|
| §2 OS Foundation | 11 | 10 | 1 | 91% |
| §7 Data Security | 11 | 3 | 8 | 27% |
| **Total** | **58** | **38** | **20** | **66%** |
```

**Alternatives considered**: Prose-based summary. Rejected because
tables are faster to scan and easier to maintain.

## R-006: Sections That Are Truly Actionable vs Educational

**Decision**: 35 of 58 subsections (§2.1–§10.6) contain actionable
hardening steps and will receive badges. 23 subsections are
educational/reference (e.g., §4.1 Colima Setup, §5.2 User
Management) and will receive `[MANUAL]` badges because they describe
procedures the operator must perform by hand.

**Rationale**: Even educational sections describe steps the operator
should take. The `[MANUAL]` badge correctly indicates "no script
handles this — you do it yourself."

**Alternatives considered**: Skip badges on educational sections
entirely. Rejected because it creates ambiguity — is the section
unbadged because it's educational or because someone forgot?
