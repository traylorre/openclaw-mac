# Context Carryover 03: Spec 002 — Clarify Round 6 (Race Conditions + /clear Timing)

**Feature Branch:** `002-context-auto-rotation`
**Date:** 2026-03-10
**Spec Status:** Draft, 37 FRs (was 35), 40 clarifications (was 35), ready for `/speckit.plan`
**Constitution Version:** 1.3.0 (unchanged)

## Project: openclaw-mac

**Repo:** `https://github.com/traylorre/openclaw-mac`
**Branch:** `002-context-auto-rotation`
**Purpose:** macOS hardening guides + audit tooling for a Mac Mini running n8n + Apify for LinkedIn lead gen

## Key Files

| File | What |
|------|------|
| `specs/002-context-auto-rotation/spec.md` | 37 FRs, 40 clarifications (sessions 2026-03-08, 2026-03-09, 2026-03-10), 8 edge cases, 9 assumptions, 6 SCs, 3 user stories |
| `specs/002-context-auto-rotation/flowchart.md` | End-to-end Mermaid flowchart, crash recovery matrix (12 rows), terminal states (14 total) — **needs update for FR-032 and 60s timeout** |
| `specs/002-context-auto-rotation/test-plan.md` | 42 test cases — **needs update for FR-032 double-/clear guard and 60s timeout** |
| `specs/002-context-auto-rotation/checklists/requirements.md` | Quality checklist |
| `specs/003-compaction-recovery/spec.md` | Companion feature — 002 integrates with 003 via FR-016 (recovery suppression), FR-020 (hook-common.sh), shared logging |

## Session Summary

This session performed 1 clarification round (5 questions, Q36–Q40) focused on race conditions from `/clear` taking 10-25 seconds, blind spots, and timing issues. Identified top 10 possible issues, asked the 5 highest-impact as clarification questions.

### Top 10 Issues Analyzed

| # | Issue | Severity | Resolution |
|---|-------|----------|------------|
| 1 | Double-/clear from keystroke queuing during 10-25s /clear | CRITICAL | **Q36: Banner + .loaded mtime ≤60s guard (FR-004, FR-032)** |
| 2 | Poller 30s timeout vs. continue:false → prompt latency | HIGH | **Q37: Increased to 60 seconds (FR-004)** |
| 3 | No signal file during 10-25s /clear window | MEDIUM-HIGH | Covered by FR-032 mtime guard + carryover file on disk |
| 4 | `compact` SessionStart event unvalidated | MEDIUM-HIGH | **Q38: Marked as unvalidated assumption (FR-011)** |
| 5 | Prompt pattern version-coupled to Claude Code UI | MEDIUM | **Q39: Hardcode, accept fallback** |
| 6 | `carryover-pending` orphan (hook crash before continue:false) | MEDIUM | **Q40: Accept risk — sub-ms window, benign impact** |
| 7 | Hook execution order between 002 and 003 SessionStart hooks | LOW-MEDIUM | Deferred — plan phase |
| 8 | `resume` event definition ambiguity | LOW-MEDIUM | Deferred — plan phase |
| 9 | send-keys reliability when pane is processing | LOW | Deferred — plan phase |
| 10 | Log rotation unbounded growth | LOW | Already deferred from prior session |

### Clarification Round 6 (5 questions) — Race Conditions + /clear Timing

| # | Focus | Key Decision |
|---|-------|-------------|
| 36 | Double-/clear keystroke queuing (CRITICAL) | Banner before `/clear` via send-keys + loader mtime ≤60s guard on `.loaded` files. New FR-032. |
| 37 | Poller timeout adequacy | Increased from 30s to 60s. FR-004 updated. Log elapsed time for tuning. |
| 38 | `compact` event validation | Unvalidated assumption — confirm empirically during implementation. FR-011 annotated. |
| 39 | Prompt pattern version coupling | Hardcode in `carryover-poller.sh`, accept 60s timeout fallback to `carryover-clear-needed`. |
| 40 | `carryover-pending` orphan signal | Accept risk — sub-millisecond crash window, benign impact (extra context). |

### New/Updated FRs This Session

| FR | Change |
|----|--------|
| FR-004 | Poller sends banner before `/clear` via send-keys; timeout increased from 30s to 60s; must log elapsed time at exit |
| FR-011 | Annotated: `compact` event name is UNVALIDATED — confirm during implementation |
| FR-032 | New: double-/clear mtime guard — loader checks `.loaded` modified ≤60s ago, treats as no-op if no unconsumed carryover |

### Updated Assumptions

- Added: `compact` event name for SessionStart hooks is UNVALIDATED (Q38)

### Deferred Items (Low Impact, carry forward)

- Log rotation for `.claude/recovery-logs/` — unbounded growth, plan-phase concern
- Poller spawn failure detection (G6) — low probability, self-heals
- `require_tool git` (G8) — git absence is catastrophic for entire workflow
- Hook execution order between 002 and 003 — independent, platform concatenates
- `resume` event definition — low risk, test during implementation
- send-keys reliability — tmux is well-tested, low concern

### Artifacts Needing Update (next session)

- **flowchart.md** — Add FR-032 double-/clear guard to Phase 3 loader flow; update timeout from 30s to 60s; add banner step to Phase 2a poller
- **test-plan.md** — Add test cases for FR-032 (double-/clear detection, mtime boundary tests); update T14 timeout from 30s to 60s

## How to Resume

1. Read this carryover file
2. Read `specs/002-context-auto-rotation/spec.md` (the full spec — 37 FRs, 40 clarifications)
3. Optionally read `flowchart.md` and `test-plan.md` for visual/test context (note: both need updates per this session)
4. Next step: `/speckit.plan` on 002
5. Note: 003 refactor task (split `recovery-common.sh` into `hook-common.sh`) should be tracked
6. Note: flowchart and test-plan need updates for FR-032 and 60s timeout before or during plan phase

## Convention Notes

Each CONTEXT-CARRYOVER-NN.md is a **historical snapshot** of one session.
Never edit a prior carryover — always create a new one.
The highest-numbered carryover is most current.
