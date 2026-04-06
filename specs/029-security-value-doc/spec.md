# 029 — Security Value Document with NIST/SOC 2 TSC Citations

## Problem Statement

New users see restrictions (locked files, mandatory audits, HMAC signing) and ask "why?" The repo lacks a document that connects each security control to the specific threat it mitigates and the standard it implements. Without this, restrictions feel arbitrary rather than principled.

## User Stories

- **US-01**: As a forker, I want to understand the security VALUE of each restriction, not just the restriction itself.
- **US-02**: As an interviewer evaluating this repo, I want to see canonical citations (NIST, OWASP, CIS) that justify the design decisions.
- **US-03**: As a security professional, I want industry-standard terminology throughout, mapped to recognized frameworks.

## Requirements

- **REQ-01**: Create `docs/SECURITY-VALUE.md` mapping each security control to: (a) the threat it mitigates, (b) the NIST 800-53r5 control family, (c) the value proposition in plain English.
- **REQ-02**: Use NIST SP 800-53r5 control families as the primary taxonomy. Provide secondary mapping to AICPA Trust Services Criteria (TSC) categories (Security, Availability, Processing Integrity, Confidentiality, Privacy) — formerly known as Trust Services Principles (TSP) — for SOC 2 compliance context. Define all project-specific terms inline.
- **REQ-03**: Cover at minimum: filesystem immutability (uchg), cryptographic integrity (HMAC), continuous monitoring (fswatch), skill allowlist (supply chain), environment variable validation, container isolation, audit automation.
- **REQ-04**: Each control must have at least one canonical citation (NIST SP 800-53r5, CIS Benchmark, OWASP, MITRE ATLAS) verified via WebSearch/WebFetch. Pin citations to specific standard versions (e.g., "NIST SP 800-53r5 Update 1", "MITRE ATLAS v5.1.0").
- **REQ-05**: Include a "Control Matrix" table: Control | Threat | NIST Family | TSC Category | Layer | Implementation | Value. The Layer column classifies each control as Prevent, Detect, or Respond per Constitution VII (Defense in Depth).
- **REQ-06**: Include a "Why This Matters" narrative section suitable for a 5-minute interview walkthrough — the Control Matrix is the quick reference, the narrative is the discussion material.
- **REQ-07**: All external links must be verified as actually addressing the claimed topic (use WebSearch/WebFetch for government standards; Context7 MCP only for library/framework docs).
- **REQ-08**: Explicitly define the relationship with `docs/ASI-MAPPING.md`: ASI-MAPPING.md is threat-centric (OWASP Agentic ASI01-10 → controls → residual risk); SECURITY-VALUE.md is control-centric (control → NIST family → TSC category → value). Cross-reference between the two docs. Do not duplicate MITRE ATLAS technique mappings already in ASI-MAPPING.md.
- **REQ-09**: Map controls to OWASP Top 10 for LLM Applications 2025 (LLM01-LLM10) where applicable, in addition to the OWASP Agentic list already in ASI-MAPPING.md. These are complementary OWASP lists from the same GenAI Security Project.
- **REQ-10**: Include a "Standards Referenced" section listing each cited standard with version, date, and URL.
- **REQ-11**: Include a "Limitations and Exclusions" section acknowledging security domains this project does NOT address (e.g., network IDS, application-level authentication, runtime memory protection).

## Scope Boundary

This document is **control-centric**: "why does each control exist?" It answers the forker's "why?" question.

`docs/ASI-MAPPING.md` is **threat-centric**: "what threats exist and what addresses them?" It answers the security professional's "what's the attack surface?" question.

Together they provide complementary perspectives on the same control set. Neither should duplicate the other.

## Files Created

- `docs/SECURITY-VALUE.md`

## External Research Required

- AICPA Trust Services Criteria (TSC/TSP) — SOC 2 framework categories
- NIST SP 800-53r5 Update 1 control families (20 families, 1150+ controls)
- CIS macOS Benchmark
- OWASP Top 10 for LLM Applications 2025 (LLM01-LLM10)
- OWASP Top 10 for Agentic Applications (ASI01-ASI10) — already mapped in ASI-MAPPING.md
- MITRE ATLAS v5.1.0 (16 tactics, 84 techniques) — cross-reference only, detail in ASI-MAPPING.md

## Clarifications

**Stage**: 4/9 | **Date**: 2026-04-06 | **Questions**: 5 | **Self-answered**: 5 | **Deferred**: 0

### Q1: Should the document include ALL 103 audit checks or only the 7 core controls?

**Answer**: The 7 core controls as detailed rows in the Control Matrix table, plus a summary row or paragraph noting "84+ additional checks cover macOS platform hardening, browser security, network controls, threat detection, and backup — see `make audit` for the full assessment." This keeps the document scannable (REQ-06: 5-minute walkthrough) while acknowledging the full scope.

**Evidence**: research.md Section 1 identifies 7 core controls with full NIST/TSC mappings. The Explore agent found 103 total CHK-* checks. Including all 103 would make the Control Matrix unusable for interview discussion.

### Q2: Should SECURITY-VALUE.md use the same "INTERNAL — Operator Reference Only" marking as ASI-MAPPING.md?

**Answer**: No. ASI-MAPPING.md is marked internal because it contains residual risk assessments and specific vulnerability details (CVE numbers, bypass counts). SECURITY-VALUE.md contains only public standards references and generic value propositions — nothing operationally sensitive. It should be unmarked (public-suitable), which serves the forker audience (US-01) better.

**Evidence**: ASI-MAPPING.md line 3: "INTERNAL — Operator Reference Only". Its content includes CVE-2025-68613, bypass counts, and residual severity ratings. SECURITY-VALUE.md's content will reference only public standards and generic threat categories.

### Q3: What format should the "Why This Matters" narrative use?

**Answer**: A series of short paragraphs (2-3 sentences each), one per control, structured as: "Without [control], [specific attack scenario]. With it, [protection provided]." This mirrors the "name the attack it prevents" pattern from Constitution VIII. Not a bulleted list — narrative flow supports the interview discussion use case.

**Evidence**: Constitution VIII: "Explain WHY a control matters before HOW to enable it — name the attack it prevents." REQ-06: "suitable for a 5-minute interview walkthrough."

### Q4: How should we handle CIS Benchmark citations given they require registration to download?

**Answer**: Cite CIS Benchmarks by name and section number (e.g., "CIS Apple macOS 15 Benchmark v1.0, Section 2.1.1"). Include the landing page URL (https://www.cisecurity.org/benchmark/apple_os) which is publicly accessible. Note in Standards Referenced that the full benchmark document requires free CIS registration. This satisfies Constitution III (Free-First) since the benchmarks are free-as-in-beer, just gated.

**Evidence**: Constitution III requires documenting costs transparently. CIS Benchmarks are free with registration — no payment required. The landing page URL works without auth.

### Q5: Should the OWASP LLM mapping table duplicate all 10 LLM risks, or only those with applicable controls?

**Answer**: Include all 10 LLM risks in the table, with "Not directly addressed" for risks without applicable controls (LLM02, LLM04, LLM05, LLM08-10). This serves US-03 (security professional) by showing gap awareness, and feeds into REQ-11 (Limitations). A security professional who sees only the risks we DO cover will wonder what we're hiding about the ones we don't.

**Evidence**: research.md Section 4 already maps 4 of 10 LLM risks to controls and notes the remaining 6 as "not directly addressed." REQ-11 requires a Limitations section. Showing all 10 risks with honest gap acknowledgment strengthens credibility.

---

**All 5 questions self-answered with evidence. No questions deferred to Phase 2.**

## Adversarial Review #1

**Reviewed:** 2026-04-06 | **Reviewer:** Battleplan AR pipeline | **Input:** spec.md (Stage 1)

### Attack Vectors Considered

1. **Scope creep** — does this duplicate ASI-MAPPING.md?
2. **Testability** — can we verify citations are correct?
3. **Feasibility** — do the referenced standards actually exist as described?
4. **Contradictions** — do requirements conflict with each other or existing docs?
5. **Missing failure modes** — what happens when standards change?
6. **Security gaps** — could false compliance claims create real risk?
7. **State-sponsored attacker** — would overstated security posture invite complacency?
8. **Penetration tester** — would they find controls that don't match claims?
9. **3am production failure** — documentation-only, but stale citations mislead incident responders

### Findings

| # | Severity | Finding | Resolution |
|---|----------|---------|------------|
| C-001 | **CRITICAL** | Spec used "TSP (Trusted Software Principles)" — this framework does not exist. NIST glossary defines TSP as "Telecommunications Service Priority." The actual security-relevant TSP is AICPA Trust Services Principles (now Trust Services Criteria/TSC), the SOC 2 framework with 5 categories: Security, Availability, Processing Integrity, Confidentiality, Privacy. | **Fixed:** Corrected to AICPA TSC with SOC 2 context. Added as secondary taxonomy alongside NIST 800-53r5 primary. Updated REQ-02, REQ-05, title. |
| H-001 | **HIGH** | No clear scope boundary with ASI-MAPPING.md. Both docs map controls to threats/standards. Without explicit delineation, SECURITY-VALUE.md would partially duplicate ASI-MAPPING.md, creating maintenance burden and potential contradictions. | **Fixed:** Added "Scope Boundary" section. Defined ASI-MAPPING as threat-centric, SECURITY-VALUE as control-centric. Added REQ-08 cross-reference rule. Prohibited MITRE ATLAS duplication. |
| H-002 | **HIGH** | REQ-04 and REQ-07 specified Context7 MCP for verifying government standards (NIST, CIS, OWASP). Context7 is designed for library/framework documentation, not government standards publications. Verification would silently fail or return irrelevant results. | **Fixed:** Changed verification method to WebSearch/WebFetch for government standards. Context7 retained only for library/framework docs. Updated REQ-04, REQ-07. |
| H-003 | **HIGH** | Two different OWASP lists not distinguished. ASI-MAPPING.md maps OWASP Top 10 for Agentic Applications (ASI01-10, December 2025). Spec 029 referenced OWASP Top 10 for LLM Applications (LLM01-10, 2025). These are complementary lists from the same OWASP GenAI Security Project, not interchangeable. | **Fixed:** Added REQ-09 mapping controls to LLM list where applicable. Clarified relationship in REQ-08 (Agentic list stays in ASI-MAPPING.md). |
| M-001 | MEDIUM | No version-pinning for cited standards. NIST 800-53r5 got Release 5.2.0 (Aug 2025) with 3 new controls. MITRE ATLAS is at v5.1.0 (Nov 2025) with 14 new agent-specific techniques. Citations without version info become ambiguous as standards evolve. | **Fixed:** Added REQ-04 version-pinning requirement. Added REQ-10 "Standards Referenced" section with version, date, URL. |
| M-002 | MEDIUM | "Interview discussion" scope in REQ-06 was vague — interview for what role? How deep? | **Fixed:** Clarified REQ-06: 5-minute walkthrough, Control Matrix as quick reference, narrative as discussion material. |
| M-003 | MEDIUM | Missing "what we don't cover." Document could imply comprehensive security coverage when it only covers this project's controls. A reader might assume topics not mentioned (network IDS, app-level auth, memory protection) are handled elsewhere. | **Fixed:** Added REQ-11 "Limitations and Exclusions" section. |
| M-004 | MEDIUM | US-03 referenced "TSP-aligned terminology" which propagated the C-001 error into user stories. | **Fixed:** Updated US-03 to "industry-standard terminology throughout, mapped to recognized frameworks." |
| L-001 | LOW | MITRE ATLAS technique mappings already in ASI-MAPPING.md (AML.T0051, AML.T0061, etc.). Duplicating in SECURITY-VALUE.md creates maintenance burden. | **Fixed:** REQ-08 now prohibits ATLAS duplication; cross-reference only. |
| L-002 | LOW | No target audience prioritization among three user stories. Forker, interviewer, and security professional have different depth needs. | **Accepted:** Document structure naturally serves all three — matrix table for quick scan (forker), narrative for discussion (interviewer), citations for verification (security professional). No conflict exists. |

### Spec Edits Made

1. **Title**: "NIST/TSP Citations" → "NIST/SOC 2 TSC Citations"
2. **US-03**: Removed TSP reference, generalized to "industry-standard terminology"
3. **REQ-02**: Complete rewrite — NIST primary, AICPA TSC secondary, inline term definitions
4. **REQ-04**: Context7 → WebSearch/WebFetch; added version-pinning
5. **REQ-05**: Added "TSC Category" column to Control Matrix
6. **REQ-06**: Added "5-minute walkthrough" scope
7. **REQ-07**: Split verification methods (WebSearch for standards, Context7 for libraries)
8. **REQ-08**: Complete rewrite — explicit ASI-MAPPING.md boundary, cross-reference rule
9. **New REQ-09**: OWASP LLM list mapping
10. **New REQ-10**: Standards Referenced section with versions
11. **New REQ-11**: Limitations and Exclusions section
12. **New section**: "Scope Boundary" defining control-centric vs threat-centric delineation

### Gate Statement

**0 CRITICAL remaining. 0 HIGH remaining.** All findings at MEDIUM or below are resolved or accepted with rationale. Spec is cleared for Stage 3 (Plan).
