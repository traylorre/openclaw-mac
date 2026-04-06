# 027 — Setup Documentation Update

## Problem Statement

GETTING-STARTED.md covers M1 (basic hardening) well but stops at "Next steps" without covering M3 (agent setup) or M4 (workspace integrity). A forker who follows the guide gets a hardened Mac but no understanding of the integrity framework, locked files, or agent deployment. Key gaps:

1. No M4 setup sequence (integrity-deploy, integrity-lock, monitor-setup)
2. No explanation of `sudoers secure_path` (causes 18 PATH warnings under sudo)
3. No warning about NODE_OPTIONS / dangerous env vars blocking agent startup
4. No mention of 3 package managers and why each exists
5. No `make doctor` in the main flow (exists but not referenced)
6. Setup order dependencies not explicit (e.g., runtime-setup before agents-setup)
7. No explanation of what happens after M1 (the "new normal" of locked files)

## User Stories

- **US-01**: As a forker, after completing the TL;DR, I want to know what's next for agent deployment and workspace integrity.
- **US-02**: As a forker, I want `make doctor` early in the flow to catch missing prerequisites.
- **US-03**: As a forker, I want to understand that files will be locked and how to edit them.

## Requirements

- **REQ-01**: Add `make doctor` to the TL;DR (as 5th command, between `make install` and `make audit`) and to Step 2 as a validation checkpoint. Include a brief note on what to do if doctor reports issues.
- **REQ-02**: Add a "Step 5: Workspace Integrity" section covering `make integrity-deploy`, `make integrity-lock`, `make monitor-setup` in dependency order. Note: this step requires Steps 1-4 to be complete.
- **REQ-03**: Add a "Step 6: sudoers secure_path" section. Use `EDITOR=nano` prefix for `visudo` to avoid vi confusion. Include a safety warning about sudoers mistakes. Provide the exact line to add: `Defaults secure_path="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"`.
- **REQ-04**: Add a callout (blockquote) about dangerous env vars (NODE_OPTIONS, DYLD_*, PYTHONPATH) that block agent startup. Place near Step 5 or in a pre-flight section.
- **REQ-05**: Add a "Package Managers" section explaining Homebrew (system tools), npm (dev linting), Bun (OpenClaw runtime) and why all 3 are needed. Place after Step 6 or in a reference section.
- **REQ-06**: Add cross-references to BEHAVIORS.md (028), SECURITY-VALUE.md (029), and FEATURE-COMPARISON.md (030) in the Next Steps section.
- **REQ-07**: Preserve the existing TL;DR simplicity — new steps (5, 6) go AFTER Step 4. The TL;DR may add `make doctor` inline but must not grow beyond 6 commands.
- **REQ-08**: Add troubleshooting entry for "Operation not permitted" with brief explanation and link to BEHAVIORS.md for detailed workflows.

## Scope Boundary

This document is the setup guide — "how to get started." It does NOT:
- Explain the behavioral changes in depth (that's BEHAVIORS.md / 028)
- Justify the security controls (that's SECURITY-VALUE.md / 029)

## Dependencies

- Feature 028 (BEHAVIORS.md) — cross-referenced in Next Steps
- Feature 029 (SECURITY-VALUE.md) — cross-referenced in Next Steps
- Feature 030 (FEATURE-COMPARISON.md) — cross-referenced in Next Steps

## Files Modified

- `GETTING-STARTED.md` — add sections after Step 4, modify TL;DR and Troubleshooting

## Adversarial Review #1

**Reviewed:** 2026-04-06 | **Reviewer:** Battleplan AR pipeline | **Input:** spec.md (Stage 1)

### Findings

| # | Severity | Finding | Resolution |
|---|----------|---------|------------|
| H-001 | **HIGH** | REQ-01 "add to TL;DR" vs REQ-07 "preserve simplicity" — potential conflict. TL;DR is currently 4 commands. Adding `make doctor` makes it 5. | **Fixed:** REQ-01 clarified: add as 5th command between install and audit. REQ-07 updated: TL;DR may grow to 6 commands max. Still simple. |
| H-002 | **HIGH** | REQ-03 `visudo` uses vi by default. Many forkers unfamiliar with vi. Editing sudoers incorrectly can lock out sudo access entirely. | **Fixed:** REQ-03 now specifies `EDITOR=nano` prefix and safety warning. Provides the exact line to add. |
| M-001 | MEDIUM | REQ-06 cross-referenced 028+029 but not 030 (FEATURE-COMPARISON.md). Inconsistent with the other docs which all cross-reference each other. | **Fixed:** REQ-06 now includes 030. |
| M-002 | MEDIUM | REQ-08 troubleshooting "Operation not permitted" overlaps with 028 REQ-05 same error. | **Fixed:** REQ-08 now specifies "brief explanation and link to BEHAVIORS.md for detailed workflows." Avoids duplication. |
| M-003 | MEDIUM | No explicit requirement to explain what `make doctor` checks or what to do when it fails. | **Fixed:** REQ-01 now includes "brief note on what to do if doctor reports issues." |
| L-001 | LOW | No scope boundary section. | **Fixed:** Added Scope Boundary. |

### Gate Statement

**0 CRITICAL, 0 HIGH remaining.** Spec cleared for Stage 3.
