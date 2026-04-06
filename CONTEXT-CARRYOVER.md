# Context Carryover

## Status: AWAITING GO/NO-GO

## Current Task

Battleplan pipeline for 4 documentation features (029→030→028→027). Phases 0-2 COMPLETE. Waiting for user approval to begin Phase 3 (Implementation).

## Pipeline Status

| Feature | Stages 1-9 | Spec | Plan | Tasks | AR#1 | AR#2 | AR#3 | Ready? |
|---------|-----------|------|------|-------|------|------|------|--------|
| 029 | COMPLETE | Done | Done | 33 tasks | Done | Done | Done | YES |
| 030 | COMPLETE | Done | Done | 23 tasks | Done | Done | Done | YES |
| 028 | COMPLETE | Done | Done | 15 tasks | Done | Done | Done | YES |
| 027 | COMPLETE | Done | Done | 14 tasks | Done | Done | Done | YES |

## Key Decisions Made

1. **TSP → AICPA TSC (C-001)**: "Trusted Software Principles" doesn't exist. Corrected to AICPA Trust Services Criteria (SOC 2 framework) across all 4 specs.
2. **Context7 → WebSearch/WebFetch**: Context7 is for library docs, not government standards. All specs updated.
3. **Two OWASP lists**: Agentic (ASI01-10) in ASI-MAPPING.md, LLM (LLM01-10) new in 029.
4. **"Contain" → "Respond"**: Constitution VII layer terminology corrected.
5. **Bidirectional gap analysis**: 030 requires equal coverage of both directions.
6. **Execution order**: 029→030→028→027 (strictly sequential, terminology flows downstream).

## Feature Branches

- `029-security-value-doc`
- `030-nemoclaw-comparison`
- `028-behaviors-doc`
- `027-setup-docs-update`

Currently on branch: `027-setup-docs-update`

## Implementation Files

### Feature 029 (SECURITY-VALUE.md)

- `specs/029-security-value-doc/spec.md` — 11 REQs, AR#1 appendix, Clarifications
- `specs/029-security-value-doc/plan.md` — Constitution check, Phase 0-1, AR#2 appendix
- `specs/029-security-value-doc/research.md` — NIST/TSC/OWASP/ATLAS mappings for 7 controls
- `specs/029-security-value-doc/data-model.md` — Document structure model
- `specs/029-security-value-doc/tasks.md` — 33 tasks, AR#3 appendix

### Feature 030 (FEATURE-COMPARISON.md)

- `specs/030-nemoclaw-comparison/spec.md` — 9 REQs, AR#1 appendix, Clarifications
- `specs/030-nemoclaw-comparison/plan.md` — NemoClaw research, gap analysis, AR#2
- `specs/030-nemoclaw-comparison/tasks.md` — 23 tasks, AR#3

### Feature 028 (BEHAVIORS.md)

- `specs/028-behaviors-doc/spec.md` — 10 REQs, AR#1 appendix
- `specs/028-behaviors-doc/plan.md` — Gotcha prioritization, AR#2
- `specs/028-behaviors-doc/tasks.md` — 15 tasks, AR#3

### Feature 027 (GETTING-STARTED.md update)

- `specs/027-setup-docs-update/spec.md` — 8 REQs, AR#1 appendix
- `specs/027-setup-docs-update/plan.md` — Document structure mapping, AR#2
- `specs/027-setup-docs-update/tasks.md` — 14 tasks, AR#3

## Research Already Complete

- `specs/battleplan-029-030-028-027/research-findings.md` — ALL Phase 0 research
- `specs/029-security-value-doc/research.md` — Detailed NIST/TSC/OWASP mappings
- NemoClaw docs verified via WebFetch (2026-04-06)
- NIST 800-53r5, OWASP LLM 2025, MITRE ATLAS v5.1.0 researched via WebSearch

## What To Do Next

1. All 4 features implemented, committed, pushed, and PRs created
2. Merge in order: 029 → 030 → 028 → 027

## User Preferences

- Commit → push → PR → automerge workflow
- Branch protection on main (0 reviewers needed)
- Files in scripts/ are uchg-locked
- docs/ files are NOT locked — can edit freely
- GETTING-STARTED.md is NOT locked — can edit freely
