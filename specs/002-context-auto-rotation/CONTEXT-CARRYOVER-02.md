# Context Carryover 02: Spec 002 — Flowchart, Test Plan, Clarify Rounds 4-5

**Feature Branch:** `002-context-auto-rotation`
**Date:** 2026-03-10
**Spec Status:** Draft, 35 FRs, 35 clarifications, ready for `/speckit.plan`
**Constitution Version:** 1.3.0 (unchanged)

## Project: openclaw-mac

**Repo:** `https://github.com/traylorre/openclaw-mac`
**Branch:** `002-context-auto-rotation`
**Purpose:** macOS hardening guides + audit tooling for a Mac Mini running n8n + Apify for LinkedIn lead gen

## Key Files

| File | What |
|------|------|
| `specs/002-context-auto-rotation/spec.md` | 35 FRs, 35 clarifications (sessions 2026-03-08, 2026-03-09), 7 edge cases, 8 assumptions, 6 SCs, 3 user stories |
| `specs/002-context-auto-rotation/flowchart.md` | End-to-end Mermaid flowchart, crash recovery matrix (12 rows), terminal states (14 total) |
| `specs/002-context-auto-rotation/test-plan.md` | 42 test cases covering all 16 junctions + 4 crash points + 8 gaps (G1-G8) |
| `specs/002-context-auto-rotation/checklists/requirements.md` | Quality checklist |
| `specs/003-compaction-recovery/spec.md` | Companion feature — 002 integrates with 003 via FR-016 (recovery suppression), FR-020 (hook-common.sh), shared logging |

## Session Summary

This session performed 2 clarification rounds (5+5 = 10 questions), created the flowchart and test plan, and committed/pushed all artifacts.

### Artifacts Created

1. **flowchart.md** — Full Mermaid flowchart with 3 phases (PostToolUse hook, Poller, SessionStart loader), 16 decision diamonds, 4 crash recovery paths, color-coded terminal states (green=self-heals, amber=warns, red=blocks, orange=crash). Includes crash recovery matrix table and terminal states summary.

2. **test-plan.md** — 42 test cases derived from junction-by-junction flowchart analysis. 15 MUST, 16 SHOULD, 11 boundary. Identified 8 gaps (G1-G8) not in the original flowchart.

### Clarification Round 4 (5 questions) — Blind Spots from Flowchart Analysis

| # | Focus | Key Decision |
|---|-------|-------------|
| 26 | Prompt detection pattern (BLOCKING) | 3 consecutive lines: `^─{12,}` / `^❯` / `^─{12,}` — full pane scan, not `tail -1` |
| 27 | Stale `.claimed` cleanup | EXIT trap + FR-029 startup defense-in-depth |
| 28 | CARRYOVER filename regex | `/^CONTEXT-CARRYOVER-[0-9]{2}\.md$/` — case-sensitive, basename only |
| 29 | `hook-common.sh` sourcing path | `source "$HOME/bin/hook-common.sh"` — symlink deploy via `~/bin/` |
| 30 | Signal file coexistence on startup | FR-030: linear scan mirroring creation timeline (claimed → clear-needed → pending) |

### Clarification Round 5 (5 questions) — Test Plan Gaps + Race Conditions

| # | Focus | Key Decision |
|---|-------|-------------|
| 31 | tmux pane targeting (CRITICAL BUG) | Poller MUST use `-t "$TMUX_PANE"` for all tmux commands. FR-004, FR-028 updated. Without this, `capture-pane`/`send-keys` target wrong pane in split layouts. |
| 32 | ANSI escape code stripping | Always strip via `sed 's/\x1b\[[0-9;]*m//g'` before prompt regex. FR-004 updated. |
| 33 | UTF-8 safe truncation | Line-boundary: `tail -c 81920 \| sed '1d'`. Cap is ~80KB ±1 line. FR-019 updated. |
| 34 | Pre-entry infrastructure guards | New FR-031: validate hook-common.sh exists, guard empty branch (detached HEAD), `mkdir -p .claude`. |
| 35 | Malformed stdin JSON | Validate `tool_name` exists (single jq check), let rest filter naturally. FR-010 updated. |

### PRs Merged

| PR | Branch | Content |
|----|--------|---------|
| #3 | `003-compaction-recovery` | Spec, plan, operational artifacts (squash merged to main) |
| #4 | `002-context-auto-rotation` | Spec, flowchart, carryover artifacts (squash merged to main) |
| #5 | `002-context-auto-rotation` | Test plan: 42 tests (squash merged to main) |

### New/Updated FRs This Session

| FR | Change |
|----|--------|
| FR-001 | Exact regex: `/^CONTEXT-CARRYOVER-[0-9]{2}\.md$/`, basename extraction |
| FR-004 | Prompt pattern (3-line), ANSI stripping, `-t "$TMUX_PANE"`, EXIT trap for `.claimed` |
| FR-010 | Case-sensitive match, `tool_name` null check before fast-path |
| FR-019 | Line-boundary truncation (`tail -c 81920 \| sed '1d'`), ~80KB cap |
| FR-020 | `source "$HOME/bin/hook-common.sh"` — canonical sourcing path |
| FR-028 | `TMUX_PANE="$TMUX_PANE"` explicit passthrough at poller spawn |
| FR-029 | New: startup deletes stale `.claimed` (SIGKILL defense) |
| FR-030 | New: linear signal file processing order on startup |
| FR-031 | New: pre-entry guards (hook-common.sh, empty branch, mkdir .claude) |

### Deferred Items (Low Impact)

- Log rotation for `.claude/recovery-logs/` — unbounded growth, plan-phase concern
- Poller spawn failure detection (G6) — low probability, self-heals
- `require_tool git` (G8) — git absence is catastrophic for entire workflow
- User typing during 1s poll window — accepted risk, mitigated by stopReason

## How to Resume

1. Read this carryover file
2. Read `specs/002-context-auto-rotation/spec.md` (the full spec — 35 FRs)
3. Optionally read `flowchart.md` and `test-plan.md` for visual/test context
4. Next step: `/speckit.plan` on 002
5. Note: 003 refactor task (split `recovery-common.sh` into `hook-common.sh`) should be tracked

## Convention Notes

Each CONTEXT-CARRYOVER-NN.md is a **historical snapshot** of one session.
Never edit a prior carryover — always create a new one.
The highest-numbered carryover is most current.
