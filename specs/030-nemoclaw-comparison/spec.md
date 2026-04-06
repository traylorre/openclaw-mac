# 030 — Feature Comparison: openclaw-mac vs NemoClaw

## Problem Statement

The repo references NemoClaw (NVIDIA's cloud-based OpenClaw sandbox) as a reference architecture but has no document comparing the two approaches. A forker or interviewer can't quickly see what this repo provides that NemoClaw doesn't (and vice versa).

## User Stories

- **US-01**: As a forker, I want to understand what security gaps NemoClaw leaves that this repo addresses.
- **US-02**: As an interviewer, I want a feature matrix comparing the two approaches using NIST/AICPA TSC terminology.
- **US-03**: As a security professional, I want to understand the tradeoffs between cloud-native (NemoClaw) and local-native (openclaw-mac) hardening.

## Requirements

- **REQ-01**: Create `docs/FEATURE-COMPARISON.md` with a feature matrix table as the primary artifact.
- **REQ-02**: Compare across dimensions: filesystem isolation, integrity verification, supply chain controls, runtime monitoring, network policy, credential management, audit automation, prompt injection detection.
- **REQ-03**: Use NIST 800-53r5 / AICPA TSC terminology from SECURITY-VALUE.md (029) for consistency. Reference the same standard versions pinned in 029's "Standards Referenced" section.
- **REQ-04**: Cite NemoClaw documentation (NVIDIA docs). Pin citations to the documentation version reviewed (include access date).
- **REQ-05**: Highlight gaps in BOTH directions with equal coverage: what NemoClaw does that we don't (e.g., kernel-level Landlock isolation, deny-by-default networking), and what we do that NemoClaw doesn't (e.g., HMAC integrity, skill allowlist, continuous monitoring). Frame gaps as "areas for future development," not deficiencies.
- **REQ-06**: Include a "Complementary Controls" section — how the two approaches could work together (e.g., NemoClaw's Landlock + openclaw-mac's HMAC would provide both prevention and detection).
- **REQ-07**: Verify NemoClaw documentation links via WebSearch/WebFetch (not Context7 MCP, which is for library/framework docs).
- **REQ-08**: Include a "Comparison Methodology" note stating which NemoClaw documentation version was reviewed and when. This enables future updates when NemoClaw adds features.
- **REQ-09**: Cross-reference SECURITY-VALUE.md (029) for NIST family details and ASI-MAPPING.md for OWASP Agentic risk mappings. Do not duplicate detailed mappings from either document.

## Scope Boundary

This document compares security architectures at the feature level. It does NOT:
- Benchmark performance (latency, throughput)
- Compare pricing/licensing
- Recommend one approach over the other (both are valid for different deployment models)

## Dependencies

- Feature 029 (SECURITY-VALUE.md) for NIST/AICPA TSC terminology alignment

## Files Created

- `docs/FEATURE-COMPARISON.md`

## Adversarial Review #1

**Reviewed:** 2026-04-06 | **Reviewer:** Battleplan AR pipeline | **Input:** spec.md (Stage 1)

### Attack Vectors Considered

1. Scope creep — comparison could expand to cover every possible dimension
2. Terminology drift from Feature 029 (TSP→AICPA TSC correction)
3. Verification method mismatch (Context7 vs WebSearch for NVIDIA docs)
4. Staleness — NemoClaw evolves, comparison decays
5. Security disclosure — gap analysis reveals what we lack to adversaries
6. Bias — comparison that only highlights our strengths is not credible
7. Duplication — overlapping with ASI-MAPPING.md control mappings

### Findings

| # | Severity | Finding | Resolution |
|---|----------|---------|------------|
| H-001 | **HIGH** | REQ-03 used "TSP/NIST terminology" — TSP was corrected to AICPA TSC in Feature 029's AR#1 (C-001). Spec 030 propagated the obsolete term. | **Fixed:** Updated to "NIST 800-53r5 / AICPA TSC terminology." Updated US-02 similarly. |
| H-002 | **HIGH** | REQ-07 specified Context7 MCP for NemoClaw docs. Context7 indexes library/framework docs, not NVIDIA documentation. | **Fixed:** Changed to WebSearch/WebFetch. |
| M-001 | MEDIUM | No version pinning for NemoClaw documentation. NemoClaw could add features between spec writing and implementation, making the comparison stale. | **Fixed:** Added REQ-08 requiring "Comparison Methodology" section with NemoClaw doc version and access date. |
| M-002 | MEDIUM | REQ-05 "Highlight gaps" could produce a biased document showing only NemoClaw's weaknesses. | **Fixed:** Updated REQ-05 to require equal coverage in both directions. Added explicit examples of openclaw-mac gaps (no kernel-level isolation, no deny-by-default networking). Framing as "areas for future development." |
| M-003 | MEDIUM | No explicit scope exclusion. Document could expand to cover performance, pricing, or make a recommendation. | **Fixed:** Added "Scope Boundary" section with explicit exclusions. |
| M-004 | MEDIUM | Could duplicate NIST/ATLAS mappings from ASI-MAPPING.md or SECURITY-VALUE.md. | **Fixed:** Added REQ-09 requiring cross-references instead of duplication. |
| L-001 | LOW | No document size constraint. 8 comparison dimensions with bidirectional gaps could become very long. | **Accepted:** The feature matrix table is the primary artifact (REQ-01). Supporting sections should be concise. No hard line limit needed for documentation. |

### Spec Edits Made

1. **US-02**: "TSP/NIST" → "NIST/AICPA TSC"
2. **REQ-01**: Added "as the primary artifact" scope
3. **REQ-03**: Complete rewrite with AICPA TSC terminology and version-pinning reference
4. **REQ-04**: Added version-pinning requirement with access date
5. **REQ-05**: Complete rewrite — bidirectional, equal coverage, "future development" framing
6. **REQ-07**: Context7 MCP → WebSearch/WebFetch
7. **New REQ-08**: Comparison Methodology section with NemoClaw doc version
8. **New REQ-09**: Cross-reference 029 and ASI-MAPPING.md, no duplication
9. **New section**: Scope Boundary with explicit exclusions

### NemoClaw Documentation Verification

All 4 NemoClaw URLs verified via WebFetch on 2026-04-06:
- https://docs.nvidia.com/nemoclaw/latest/about/how-it-works.html — Valid (sandbox overview)
- https://docs.nvidia.com/nemoclaw/latest/reference/architecture.html — Valid (TypeScript plugin + Python blueprint)
- https://docs.nvidia.com/nemoclaw/latest/reference/network-policies.html — Valid (deny-by-default model)
- https://docs.nvidia.com/nemoclaw/latest/network-policy/customize-network-policy.html — Not yet verified

### Gate Statement

**0 CRITICAL remaining. 0 HIGH remaining.** Spec cleared for Stage 3 (Plan).

## Clarifications

**Stage**: 4/9 | **Date**: 2026-04-06 | **Questions**: 4 | **Self-answered**: 4 | **Deferred**: 0

### Q1: Should the document acknowledge NemoClaw's kernel-level isolation as objectively stronger than uchg?

**Answer**: Yes. Landlock LSM is enforced at the kernel level and cannot be bypassed by root (without disabling the LSM entirely). uchg can be removed by root via `chflags nouchg`. This is a factual difference in enforcement strength, not a value judgment. State it clearly: "NemoClaw's Landlock provides kernel-enforced isolation that cannot be bypassed by privileged processes. openclaw-mac's uchg operates at the userspace level and can be removed by root."

**Evidence**: NemoClaw architecture docs confirm Landlock + seccomp. macOS `chflags` man page confirms root can remove uchg. Constitution VIII requires explicit, honest explanations.

### Q2: How should we handle NemoClaw features described as "Not documented"?

**Answer**: Distinguish between "not documented" and "does not exist." For each NemoClaw gap, state: "Not documented in NemoClaw [version] as of [date]." This leaves room for features that exist but aren't publicly documented. Do not claim NemoClaw definitively lacks a feature if we only know its docs don't mention it.

**Evidence**: NemoClaw is a proprietary NVIDIA product. Private features may exist. Constitution IV requires citing what we can verify.

### Q3: Should the comparison include a "winner" per dimension?

**Answer**: No. Per the Scope Boundary, the document should not recommend one approach over the other. Each dimension should present facts. The reader decides which tradeoffs matter for their deployment. A "winner" column would bias the document and undermine credibility (M-002 from AR#1).

**Evidence**: Spec Scope Boundary: "Does NOT recommend one approach over the other." REQ-05: "Frame gaps as 'areas for future development.'"

### Q4: Should we include NemoClaw's OpenShell gateway architecture in the comparison?

**Answer**: Only at the dimension level (inference routing, network policy). The internal architecture details (TypeScript plugin, Python blueprint) are implementation details that don't map to our comparison dimensions. Including them would expand scope beyond security feature comparison.

**Evidence**: Spec Scope Boundary limits comparison to "security architectures at the feature level." OpenShell internals are below feature level.

---

**All 4 questions self-answered with evidence. No questions deferred to Phase 2.**
