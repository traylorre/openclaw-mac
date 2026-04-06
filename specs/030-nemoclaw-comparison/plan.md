# Implementation Plan: FEATURE-COMPARISON.md

**Branch**: `030-nemoclaw-comparison` | **Date**: 2026-04-06 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/030-nemoclaw-comparison/spec.md`

## Summary

Create `docs/FEATURE-COMPARISON.md` — a feature matrix comparing openclaw-mac and NemoClaw security architectures across 8 dimensions using NIST/AICPA TSC terminology from Feature 029. Highlights bidirectional gaps and complementary control opportunities.

## Technical Context

**Language/Version**: Markdown (CommonMark, per `.markdownlint-cli2.jsonc`)
**Primary Dependencies**: Feature 029 (SECURITY-VALUE.md must be written first for terminology)
**Storage**: N/A (git-tracked markdown file)
**Testing**: markdownlint-cli2 (CI pipeline), link verification (WebSearch/WebFetch for NemoClaw URLs)
**Target Platform**: GitHub rendered markdown (fork-friendly documentation)
**Project Type**: Documentation artifact
**Constraints**: Must pass markdownlint CI; must use 029's terminology; NemoClaw docs may evolve

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Documentation-Is-the-Product | **PASS** | Core documentation deliverable |
| II. Threat-Model Driven | **PASS** | Comparison dimensions map to constitution's named threats |
| III. Free-First | **PASS** | All cited sources freely available |
| IV. Cite Canonical Sources | **PASS** | NemoClaw docs cited with version/date; NIST/OWASP via 029 cross-reference |
| V. Every Recommendation Is Verifiable | **PASS** | Each dimension links to specific audit checks or NemoClaw doc sections |
| VI. Bash Scripts | **N/A** | No scripts |
| VII. Defense in Depth | **PASS** | Comparison organized by security layer |
| VIII. Explicit Over Clever | **PASS** | Plain-language explanations |
| IX. Markdown Quality Gate | **PASS** | markdownlint CI |
| X. CLI-First | **N/A** | No infrastructure |

**Gate result: PASS (8/8 applicable, 2 N/A)**

## Project Structure

```text
specs/030-nemoclaw-comparison/
├── spec.md              # Feature spec with AR#1
├── plan.md              # This file
├── research.md          # Phase 0: NemoClaw deep research
├── data-model.md        # Document structure
└── tasks.md             # Phase 2 output

docs/
├── FEATURE-COMPARISON.md  # NEW — primary deliverable
├── SECURITY-VALUE.md      # Feature 029 — cross-referenced for terminology
├── ASI-MAPPING.md         # EXISTING — cross-referenced for OWASP Agentic
```

**Structure Decision**: Single new file in `docs/`. No source code changes.

---

## Phase 0: Research

### Research Sources

Primary research already consolidated in:
- `specs/battleplan-029-030-028-027/research-findings.md` Section 5 (NemoClaw)
- Feature 029 research.md (openclaw-mac control inventory)
- NemoClaw documentation (4 URLs verified via WebFetch on 2026-04-06)

### NemoClaw Capabilities (verified)

| Dimension | NemoClaw Control | Source |
|-----------|-----------------|--------|
| Filesystem isolation | Landlock LSM (kernel-level), writable /sandbox + /tmp, read-only system paths | how-it-works.html |
| Network policy | Deny-by-default, explicit allowlist (Anthropic API, GitHub, operator-specified) | network-policies.html |
| Process isolation | seccomp filters, no privilege escalation | architecture.html |
| Inference routing | Gateway-routed, operator-controlled model access | architecture.html |
| Integrity verification | Not documented | Gap |
| Runtime monitoring | Not documented | Gap |
| Supply chain controls | Skill files copied to writable /sandbox (modifiable by agent) | Gap (research-findings.md) |
| Credential management | Not documented | Gap |
| Audit automation | Not documented | Gap |
| Prompt injection detection | Not documented | Gap |

### Bidirectional Gap Analysis

**NemoClaw has, openclaw-mac lacks:**
1. Kernel-level filesystem isolation (Landlock LSM) — macOS has no equivalent
2. Deny-by-default network policy with explicit allowlist — openclaw-mac uses pf but not deny-all-then-allow
3. seccomp process filters — macOS sandbox profiles exist but not used here

**openclaw-mac has, NemoClaw lacks:**
1. HMAC-SHA256 integrity manifest with Keychain-stored keys
2. Skill allowlist with content-hash verification
3. Continuous filesystem monitoring (fswatch + heartbeat)
4. 84-check automated audit with auto-fix capability
5. Credential isolation via macOS Keychain + Docker secrets
6. Prompt injection detection via skill hash mismatch warning
7. Environment variable validation (15 dangerous vars blocked)
8. CVE registry with version pinning for dependencies

### Complementary Control Concepts

| NemoClaw Control | openclaw-mac Control | Combined Value |
|-----------------|---------------------|---------------|
| Landlock (prevent writes) | HMAC manifest (detect changes) | Prevent + Detect = defense in depth |
| Deny-by-default network | HMAC webhook auth | Network isolation + authenticated communication |
| seccomp (limit syscalls) | fswatch (monitor filesystem) | Process restriction + runtime monitoring |
| Gateway routing | Skill allowlist | Controlled inference + controlled instructions |

---

## Phase 1: Design

### Document Structure

```text
docs/FEATURE-COMPARISON.md
├── Title + scope statement
├── Comparison Methodology (NemoClaw version, access date, limitations)
├── Feature Matrix (table — 8+ dimensions × 2 platforms)
│   └── Columns: Dimension | NemoClaw | openclaw-mac | NIST Family
├── Gap Analysis
│   ├── What NemoClaw provides that openclaw-mac lacks
│   └── What openclaw-mac provides that NemoClaw lacks
├── Complementary Controls (how both could combine)
├── Cross-References (→ SECURITY-VALUE.md, → ASI-MAPPING.md)
└── Footer with document version and access date
```

---

## Post-Design Constitution Re-Check

All 8 applicable principles still pass. No violations introduced during Phase 0-1.

---

## Adversarial Review #2

**Reviewed:** 2026-04-06 | **Input:** spec.md + plan.md + clarifications

### Drift Analysis

| Artifact | Change | Source |
|----------|--------|--------|
| spec.md REQ count | 7 → 9 | AR#1 added REQ-08 (methodology), REQ-09 (cross-references) |
| spec.md Scope Boundary | Added | AR#1 fix (M-003) |
| spec.md Clarifications | 4 Q&A added | Stage 4 |
| spec.md NemoClaw URL verification | Added to AR#1 | Stage 2 research |

All drift is intentional and traceable.

### Cross-Artifact Consistency

| Check | Status |
|-------|--------|
| plan.md comparison dimensions match spec.md REQ-02 | **PASS** — all 8 dimensions covered |
| plan.md NemoClaw inventory matches spec AR#1 URL verification | **PASS** — same 4 URLs |
| plan.md gap analysis is bidirectional per REQ-05 | **PASS** — 3 NemoClaw advantages, 8 openclaw-mac advantages |
| plan.md "Not documented" language matches Clarification Q2 | **PASS** — uses "Not documented" not "Does not exist" |
| Terminology uses "NIST/AICPA TSC" per 029 corrections | **PASS** — no TSP references remain |

### Findings

| # | Severity | Finding | Resolution |
|---|----------|---------|------------|
| M-005 | MEDIUM | Gap analysis shows 3 NemoClaw advantages vs 8 openclaw-mac advantages. Per REQ-05 this should have "equal coverage." While the raw count is unequal (we genuinely have more features), the depth of treatment should be balanced. | **Accepted:** The count difference reflects reality. REQ-05 requires equal coverage depth (paragraphs per gap), not equal gap count. The implementation should give NemoClaw's 3 advantages thorough treatment. |

### Gate Statement

**0 CRITICAL, 0 HIGH remaining.** Plan cleared for Stage 7 (Tasks).
