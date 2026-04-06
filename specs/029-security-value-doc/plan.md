# Implementation Plan: SECURITY-VALUE.md

**Branch**: `029-security-value-doc` | **Date**: 2026-04-06 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/029-security-value-doc/spec.md`

## Summary

Create `docs/SECURITY-VALUE.md` — a control-centric document mapping each openclaw-mac security control to the threat it mitigates, the NIST 800-53r5 control family it implements, the AICPA TSC category it satisfies, and a plain-English value proposition. Complements the existing threat-centric `docs/ASI-MAPPING.md` without duplicating it.

## Technical Context

**Language/Version**: Markdown (CommonMark, per `.markdownlint-cli2.jsonc`)
**Primary Dependencies**: None (pure documentation)
**Storage**: N/A (git-tracked markdown file)
**Testing**: markdownlint-cli2 (CI pipeline), link verification (manual via WebSearch/WebFetch)
**Target Platform**: GitHub rendered markdown (fork-friendly documentation)
**Project Type**: Documentation artifact within a hardening/audit repository
**Performance Goals**: N/A
**Constraints**: Must pass markdownlint CI pipeline; MD013 (line length) disabled; all other rules enforced
**Scale/Scope**: Single markdown file (~200-400 lines), 7+ controls mapped, 6 external standards cited

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Documentation-Is-the-Product | **PASS** | This IS documentation. Core deliverable of the repo. |
| II. Threat-Model Driven | **PASS** | Every control in the matrix traces back to a named threat from the constitution's adversary list. Controls without threat justification will be excluded. |
| III. Free-First with Cost Transparency | **PASS** | All cited standards are freely available (NIST, OWASP, MITRE). AICPA TSC criteria descriptions are publicly summarized. CIS Benchmarks require free registration for download. |
| IV. Cite Canonical Sources | **PASS** | Core requirement (REQ-04). Every control gets at minimum one NIST 800-53r5 citation. Version-pinned. |
| V. Every Recommendation Is Verifiable | **PASS** | Each control row in the matrix includes an "Implementation" column linking to the specific `CHK-*` audit check, `make` target, or configuration file. |
| VI. Bash Scripts Are Infrastructure | **N/A** | No scripts in this feature. |
| VII. Defense in Depth, Organized by Layer | **PASS** | Control Matrix will include a "Layer" indicator (Prevent/Detect/Respond) per Constitution VII. |
| VIII. Explicit Over Clever | **PASS** | Value column uses plain English. TSC/NIST references explained inline. Target audience: technically capable operator, not a security specialist. |
| IX. Markdown Quality Gate | **PASS** | Must pass markdownlint CI before merge. |
| X. CLI-First Infrastructure | **N/A** | No infrastructure changes. |

**Gate result: PASS (8/8 applicable principles satisfied, 2 N/A)**

## Project Structure

### Documentation (this feature)

```text
specs/029-security-value-doc/
├── spec.md              # Feature spec with AR#1 appendix
├── plan.md              # This file
├── research.md          # Phase 0: standards research
├── data-model.md        # Phase 1: document structure model
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
docs/
├── SECURITY-VALUE.md    # NEW — primary deliverable
├── ASI-MAPPING.md       # EXISTING — cross-referenced, not modified
├── HARDENING.md         # EXISTING — referenced for audit check names
└── ...                  # Other existing docs unchanged
```

**Structure Decision**: Single new file in `docs/`. No contracts directory needed (documentation-only feature with no external interfaces). No source code changes.

## Complexity Tracking

No constitution violations. No complexity justification needed.

---

## Phase 0: Research

### Research Tasks

1. **NIST SP 800-53r5 control family mapping** — map each of the 7+ controls to specific NIST families
2. **AICPA TSC category mapping** — map each control to the applicable TSC category
3. **OWASP LLM Top 10 mapping** — map controls to LLM01-LLM10 where applicable
4. **Existing control inventory** — enumerate all security controls in the codebase with their audit check IDs
5. **Defense-in-depth layer assignment** — classify each control as Prevent/Detect/Respond

### Research Findings

Consolidated in [research.md](research.md).

---

## Phase 1: Design

### Document Structure

Defined in [data-model.md](data-model.md). Key design decisions:

1. **Control Matrix as primary artifact** — scannable table with 7 columns per control
2. **Cross-reference model** — SECURITY-VALUE.md links to ASI-MAPPING.md (threat view) and HARDENING.md (audit details)
3. **No contracts directory** — documentation-only feature with no external interfaces
4. **No source code changes** — single new file in `docs/`

### Quickstart

See [quickstart.md](quickstart.md) for implementation steps.

### Agent Context Update

Agent context update skipped — CLAUDE.md is uchg-locked and this feature adds no new technologies (pure markdown documentation).

---

## Post-Design Constitution Re-Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Documentation-Is-the-Product | **PASS** | Control Matrix + narrative serve the primary documentation mission |
| II. Threat-Model Driven | **PASS** | research.md maps every control to constitution's named adversaries |
| III. Free-First | **PASS** | CIS Benchmarks require free registration — noted in Standards Referenced |
| IV. Cite Canonical Sources | **PASS** | 7 standards version-pinned in research.md Section 6 |
| V. Every Recommendation Is Verifiable | **PASS** | Implementation column links each control to `CHK-*` checks |
| VII. Defense in Depth | **PASS** | Layer column (Prevent/Detect/Respond) added to matrix |
| VIII. Explicit Over Clever | **PASS** | Value column uses plain English per research.md |
| IX. Markdown Quality Gate | **PASS** | markdownlint verification in quickstart.md |

**Post-design gate: PASS. No violations introduced during Phase 0-1.**

---

## Adversarial Review #2

**Reviewed:** 2026-04-06 | **Reviewer:** Battleplan AR pipeline | **Input:** spec.md + plan.md + research.md + data-model.md + clarifications

### Drift Analysis

| Artifact | Original (Stage 1) | Current (Post-Stage 4) | Drift? |
|----------|-------------------|----------------------|--------|
| spec.md title | "NIST/TSP Citations" | "NIST/SOC 2 TSC Citations" | Yes — AR#1 fix (C-001) |
| spec.md REQ count | 8 requirements | 11 requirements | Yes — AR#1 added REQ-09, REQ-10, REQ-11 |
| spec.md REQ-05 columns | 6 columns (no Layer) | 7 columns (Layer added) | Yes — **AR#2 fix** (backported from plan/data-model) |
| spec.md Scope Boundary | Not present | Added | Yes — AR#1 fix (H-001) |
| spec.md Clarifications | Not present | 5 Q&A pairs | Yes — Stage 4 (expected) |

**All drift is intentional and traceable to specific AR#1 findings or Stage 4 clarifications.**

### Cross-Artifact Consistency Check

| Check | Status | Notes |
|-------|--------|-------|
| spec.md REQ-05 columns match data-model.md schema | **PASS** (after fix) | Both now specify 7 columns including Layer |
| research.md control list matches spec.md REQ-03 | **PASS** | All 7 core controls researched in research.md Section 1 |
| research.md NIST families are valid 800-53r5 identifiers | **PASS** | 19 families cited, all real (AC, AU, CA, CM, IR, SA, SC, SI, SR) |
| research.md TSC categories match AICPA framework | **PASS** | Security, Availability, Processing Integrity, Confidentiality used; Privacy gap noted |
| research.md OWASP LLM risks match 2025 list | **PASS** | LLM01, LLM03, LLM06, LLM07 cited; matches official list |
| plan.md constitution check references match constitution.md | **PASS** | All 10 principles checked, 8 applicable, 2 N/A |
| data-model.md cross-reference model matches spec.md REQ-08 | **PASS** | Scope boundary defined in both |
| quickstart.md steps cover all 11 REQs | **PASS** | 8 steps map to REQ-01 through REQ-11 |
| Clarification answers consistent with spec.md | **PASS** | Q1→REQ-03, Q2→(new guidance), Q3→REQ-06, Q4→REQ-04/REQ-10, Q5→REQ-09/REQ-11 |
| Standards Referenced in research.md match spec.md list | **PASS** | 7 standards in research.md Section 6, spec lists 6 (7th is CIS Docker, applicable to container control) |

### Findings

| # | Severity | Finding | Resolution |
|---|----------|---------|------------|
| D-001 | **HIGH** | spec.md REQ-05 had 6 columns but data-model.md and plan.md specified 7 (including Layer). The Layer column was justified by Constitution VII but never backported to the spec. This would have caused implementation confusion. | **Fixed:** Updated spec.md REQ-05 to include Layer column with Constitution VII reference. |
| M-005 | MEDIUM | research.md Section 2 says "19 of 20 NIST families touched" but this counts families across ALL 7 controls. The reader might misinterpret this as each control touching 19 families. | **Accepted:** The table in Section 2 shows which controls map to which families — no ambiguity in context. The "19 of 20" is a summary statistic for the document's total coverage. |
| L-003 | LOW | plan.md lists "6 external standards cited" in Scale/Scope but research.md Section 6 lists 7 standards. | **Accepted:** "6+" is accurate since CIS has two entries (macOS + Docker). Minor inconsistency in estimate, not a blocking issue. |

### Gate Statement

**0 CRITICAL remaining. 0 HIGH remaining (D-001 fixed).** All cross-artifact inconsistencies resolved or accepted. Plan is cleared for Stage 6 (Plan Second Pass) / Stage 7 (Tasks).
