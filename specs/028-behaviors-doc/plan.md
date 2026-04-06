# Implementation Plan: BEHAVIORS.md

**Branch**: `028-behaviors-doc` | **Date**: 2026-04-06 | **Spec**: [spec.md](spec.md)

## Summary

Create `docs/BEHAVIORS.md` — a practical guide explaining the "new normal" after hardening. Before/After comparison table, step-by-step workflows for common operations, troubleshooting guide for error messages, and inventory of background services and external files.

## Technical Context

**Language/Version**: Markdown (CommonMark)
**Dependencies**: Features 029 + 030 (cross-referenced, must exist first)
**Testing**: markdownlint-cli2 CI
**Project Type**: Documentation artifact

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Documentation-Is-the-Product | **PASS** | Core user-facing guide |
| II. Threat-Model Driven | **PASS** | Each restriction traces to a threat; REQ-08 requires one-sentence "why" |
| IV. Cite Canonical Sources | **PASS** | Cross-references SECURITY-VALUE.md for canonical citations |
| V. Every Recommendation Is Verifiable | **PASS** | Workflows reference specific `make` targets |
| VII. Defense in Depth | **PASS** | Explains how controls layer together |
| VIII. Explicit Over Clever | **PASS** | Practical tone, copy-pasteable commands |
| IX. Markdown Quality Gate | **PASS** | markdownlint CI |

**Gate result: PASS**

## Project Structure

```text
docs/
├── BEHAVIORS.md           # NEW — primary deliverable
├── SECURITY-VALUE.md      # Feature 029 — cross-referenced
├── FEATURE-COMPARISON.md  # Feature 030 — cross-referenced
```

## Phase 0: Research

Primary research in `specs/battleplan-029-030-028-027/research-findings.md` Section 4 (50 gotchas). Key gotchas prioritized for first-week impact:

**Critical (will block you):**
1. uchg flags prevent edits silently — no error in editors
2. Missing Keychain key = all startups blocked
3. NODE_OPTIONS / DYLD_* block agent startup
4. `make install` breaks if run with sudo
5. Setup order: runtime-setup before agents-setup

**Good to know (may surprise you):**
6. 5-minute grace period suppresses ALL alerts during unlock
7. Manifest.json must not be version-controlled
8. Moving repo after monitor-setup breaks absolute paths in plists
9. Audit cron runs Sunday 03:00 as root
10. Bash 5.x required — system bash (3.x) too old

## Clarifications

**Q1: Should the Before/After table cover every behavioral change or just key ones?**
Answer: Key ones only — the ones that would confuse or block a forker in the first week. REQ-10 prioritization handles this.

**Q2: Should workflows include the actual `make` target names or abstract them?**
Answer: Exact `make` target names — per Constitution X (CLI-First) and VIII (Explicit Over Clever). Copy-pasteable commands.

**Q3: Should the troubleshooting section include resolution steps or just explanations?**
Answer: Both. Each error: what it means, why it happened, how to fix it. One command per fix where possible.

All 3 self-answered. 0 deferred.

## Adversarial Review #2

No drift detected. Clarifications are consistent with spec. Cross-references to 029/030 confirmed in REQ-09. Gate: PASS.
