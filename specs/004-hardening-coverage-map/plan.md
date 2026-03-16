# Implementation Plan: Hardening Coverage Map

**Branch**: `004-hardening-coverage-map` | **Date**: 2026-03-16 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/004-hardening-coverage-map/spec.md`

## Summary

Add inline coverage badges (`[AUTO-FIX]`, `[AUDIT-ONLY]`, `[MANUAL]`)
to every actionable subsection of HARDENING.md, insert a coverage
summary block immediately after the Table of Contents, sync
CHK-REGISTRY.md with 2 missing checks, fix a naming inconsistency,
and add an Auto-Fix column to the registry. This is a documentation-
only change — no scripts are modified except to fix one identifier
name.

## Technical Context

**Language/Version**: Markdown (documentation), Bash 5.x (one identifier rename)
**Primary Dependencies**: None (manual markdown edits)
**Storage**: N/A (filesystem, git-tracked markdown files)
**Testing**: Manual visual review + grep-based validation
**Target Platform**: GitHub-rendered markdown
**Project Type**: Documentation / scripting repository
**Performance Goals**: N/A
**Constraints**: Must not alter existing HARDENING.md content (FR-009); markdown must pass markdownlint
**Scale/Scope**: 58 actionable subsections to badge, 2 registry entries to add, 1 naming fix

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Documentation-Is-the-Product | PASS | This feature directly improves guide completeness and usability |
| II. Threat-Model Driven | PASS | Badges trace back to CHK-* checks which trace to threat model |
| III. Free-First | PASS | No tools or costs involved |
| IV. Cite Canonical Sources | PASS | Badges reference CHK-* identifiers which cite sources |
| V. Every Recommendation Is Verifiable | PASS | Badges make verification status visible inline |
| VI. Bash Scripts Are Infrastructure | PASS | Only change: rename one CHK identifier for consistency |
| VII. Defense in Depth, Organized by Layer | PASS | Coverage summary organizes by defensive layer (§2-§10) |
| VIII. Explicit Over Clever | PASS | Badges are self-explanatory with legend |
| IX. Markdown Quality Gate | PASS | Badge format must pass markdownlint |
| X. CLI-First | N/A | Documentation change, no CLI implications |

All gates pass. No violations to justify.

## Project Structure

### Documentation (this feature)

```text
specs/004-hardening-coverage-map/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
└── checklists/
    └── requirements.md  # Spec quality checklist
```

### Source Code (repository root)

```text
docs/
└── HARDENING.md         # Primary target: add badges + coverage summary

scripts/
├── CHK-REGISTRY.md      # Add 2 missing entries + Auto-Fix column
├── hardening-audit.sh   # Fix CHK-LISTENERS-BASELINE naming (1 line)
└── hardening-fix.sh     # No changes needed
```

**Structure Decision**: This feature modifies 3 existing files. No
new files are created in the repository root. The only code change
is a single identifier rename in the audit script for consistency.
