# Data Model: Hardening Coverage Map

**Date**: 2026-03-16
**Feature**: 004-hardening-coverage-map

## Entities

### Guide Section

A subsection of HARDENING.md containing a specific hardening topic.

| Attribute | Type | Description |
|-----------|------|-------------|
| section_id | string | Section number (e.g., "2.1", "10.6") |
| title | string | Section heading text |
| badge | enum | One of: AUTO-FIX, AUDIT-ONLY, MANUAL |
| chk_ids | string[] | List of CHK-* identifiers mapped to this section |
| has_any_autofix | boolean | True if at least one chk_id has an auto-fix |

### CHK Identifier

A unique audit check identifier in the audit script.

| Attribute | Type | Description |
|-----------|------|-------------|
| id | string | Unique identifier (e.g., "CHK-FIREWALL") |
| severity | enum | FAIL or WARN |
| deployment | enum | both, containerized, or bare-metal |
| guide_section | string | Section reference (e.g., "§2.2") |
| has_autofix | boolean | Whether a fix function exists |
| owning_task | string | Task that implemented this check |

### Coverage Summary

Aggregate metrics displayed at the top of HARDENING.md.

| Attribute | Type | Description |
|-----------|------|-------------|
| section_name | string | Major section (e.g., "§2 OS Foundation") |
| total_subsections | integer | Count of subsections in this section |
| automated_count | integer | Subsections with at least one CHK-* |
| manual_count | integer | Subsections with no CHK-* |
| coverage_pct | integer | automated_count / total_subsections * 100 |

## Relationships

- A Guide Section has zero or more CHK Identifiers (one-to-many)
- A CHK Identifier belongs to exactly one Guide Section (many-to-one)
- A CHK Identifier may or may not have an auto-fix (boolean attribute)
- The Coverage Summary aggregates Guide Sections by major section number

## Badge Resolution Rules

1. If a section has zero CHK-* identifiers → `[MANUAL]`
2. If a section has CHK-* identifiers and ALL have auto-fix → `[AUTO-FIX]`
3. If a section has CHK-* identifiers and at least one has auto-fix → `[AUTO-FIX]`
4. If a section has CHK-* identifiers and NONE have auto-fix → `[AUDIT-ONLY]`
5. §1, §11, and Appendices receive no badge (FR-011)
