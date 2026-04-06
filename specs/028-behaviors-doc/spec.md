# 028 — Before/After Behaviors Document

## Problem Statement

After setup, the repo behaves differently from a normal git repository. Files are locked with `uchg` flags, edits silently fail, `sudo` is required for routine operations, and background services monitor file changes. A new user has no single reference explaining what changed and what the "new normal" is. The 50 gotchas identified in research need to be distilled into a practical guide.

## User Stories

- **US-01**: As a forker, I want a single document that explains every "that's weird" behavior I'll encounter.
- **US-02**: As a forker, I want to know the correct workflow for editing protected files.
- **US-03**: As a forker, I want to understand which operations need sudo and why.

## Requirements

- **REQ-01**: Create `docs/BEHAVIORS.md` with "Before" (normal repo) vs "After" (hardened repo) comparison table covering the most impactful behavioral changes.
- **REQ-02**: Cover at minimum: locked files (uchg + 5-minute grace period), integrity manifest (HMAC signing, Keychain dependency), background services (LaunchAgents/Daemons with schedules), sudo requirements, environment variable restrictions (15 blocked vars), setup order dependencies.
- **REQ-03**: Include "How to edit a protected file" step-by-step workflow: `make integrity-unlock` → edit → `make integrity-lock` → `make manifest-update`.
- **REQ-04**: Include "How to add/modify a skill" workflow: unlock → edit → `make skillallow-add` → lock.
- **REQ-05**: Include "What to do when you see..." troubleshooting section covering at minimum: "Operation not permitted" (uchg), "manifest signature mismatch" (HMAC), "Dangerous environment variable detected" (env var block), "Keychain item not found" (missing HMAC key), "integrity monitor heartbeat stale" (fswatch down).
- **REQ-06**: Include "Services running in background" section listing: `com.openclaw.integrity-monitor` (LaunchAgent, user-level, KeepAlive, 30s heartbeat) and `com.openclaw.audit-cron` (LaunchDaemon, root, weekly Sunday 03:00).
- **REQ-07**: Include "Files outside the repo" section listing: `~/.openclaw/manifest.json`, `~/.openclaw/lock-state.json`, `~/.openclaw/skill-allowlist.json`, `~/.openclaw/openclaw.json`, `~/.openclaw/.env`, and Keychain entry `integrity-manifest-key`.
- **REQ-08**: Tone: practical, not alarmist. For each restriction, briefly state WHY it exists (one sentence linking to SECURITY-VALUE.md for details), then immediately show HOW to work within it.
- **REQ-09**: Cross-reference SECURITY-VALUE.md (029) for "why each restriction exists" and FEATURE-COMPARISON.md (030) for "how this compares to NemoClaw." These links help the reader build a complete mental model.
- **REQ-10**: Prioritize the 50 gotchas from research by impact. Group into "Critical (will block you)" and "Good to know (may surprise you)." Do not attempt to cover all 50 — focus on the ones a forker will hit in the first week.

## Scope Boundary

This document explains the behavioral changes after hardening — the "new normal." It does NOT:

- Explain how to set up the hardening (that's GETTING-STARTED.md / 027)
- Explain the security value of each control (that's SECURITY-VALUE.md / 029)
- Compare to NemoClaw (that's FEATURE-COMPARISON.md / 030)

## Dependencies

- Feature 029 (SECURITY-VALUE.md) — cross-referenced for "why" explanations
- Feature 030 (FEATURE-COMPARISON.md) — cross-referenced for NemoClaw context

## Files Created

- `docs/BEHAVIORS.md`

## Adversarial Review #1

**Reviewed:** 2026-04-06 | **Reviewer:** Battleplan AR pipeline | **Input:** spec.md (Stage 1)

### Findings

| # | Severity | Finding | Resolution |
|---|----------|---------|------------|
| H-001 | **HIGH** | No cross-reference to 029 or 030. Battleplan carryover says 028 "references both" but spec had no such requirement. Without these links, the reader gets operational HOW without strategic WHY. | **Fixed:** Added REQ-09 requiring cross-references to both docs. Updated REQ-08 to include one-sentence "why" per restriction. |
| H-002 | **HIGH** | 50 gotchas from research not prioritized. Without prioritization, document either becomes overwhelming (all 50) or arbitrarily selective. | **Fixed:** Added REQ-10 requiring impact-based prioritization: "Critical (will block you)" vs "Good to know." Focus on first-week experience. |
| M-001 | MEDIUM | REQ-05 error messages not enumerated. Implementer must guess which errors to cover. | **Fixed:** REQ-05 now lists 5 specific error messages at minimum. |
| M-002 | MEDIUM | REQ-02 missing timing-sensitive behaviors (5-min grace period, Sunday 03:00 audit, 30s heartbeat). | **Fixed:** REQ-02 now includes grace period. REQ-06 includes specific schedules. |
| M-003 | MEDIUM | REQ-07 didn't enumerate specific files/Keychain entries. | **Fixed:** REQ-07 now lists all 5 files and the Keychain entry. |
| M-004 | MEDIUM | No scope boundary — document could overlap with GETTING-STARTED.md or SECURITY-VALUE.md. | **Fixed:** Added "Scope Boundary" section with explicit exclusions. |
| L-001 | LOW | No document size constraint. | **Accepted:** Focus on "first week" experience (REQ-10) naturally limits scope. |

### Gate Statement

**0 CRITICAL, 0 HIGH remaining.** Spec cleared for Stage 3.
