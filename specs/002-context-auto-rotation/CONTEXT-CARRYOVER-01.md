# Context Carryover 01: Spec 002 — 25 Clarify Rounds

**Feature Branch:** `002-context-auto-rotation`
**Date:** 2026-03-09
**Spec Status:** Draft, fully clarified, ready for `/speckit.plan`
**Constitution Version:** 1.3.0 (unchanged)

## Project: openclaw-mac

**Repo:** `https://github.com/traylorre/openclaw-mac`
**Branch:** `003-compaction-recovery` (002 spec edited from 003 branch)
**Purpose:** macOS hardening guides + audit tooling for a Mac Mini running n8n + Apify for LinkedIn lead gen

## Key Files

| File | What |
|------|------|
| `specs/002-context-auto-rotation/spec.md` | 28 FRs, 7 edge cases (all resolved), 8 assumptions, 6 SCs, 2 entities, 3 user stories, 25 clarifications |
| `specs/002-context-auto-rotation/checklists/requirements.md` | Quality checklist |
| `specs/003-compaction-recovery/spec.md` | Companion feature — 002 integrates with 003 via FR-016 (recovery suppression), FR-020 (hook-common.sh), shared logging |

## Session Summary

This session performed 3 rounds of `/speckit.clarify` on spec 002-context-auto-rotation (10 + 10 + 5 questions = 25 total), growing it from 15 FRs to 28 FRs.

### Round 1 (10 questions) — Architecture & Integration

| # | Focus | Key Decision |
|---|-------|-------------|
| 1 | PostToolUse API validation (BLOCKING) | Confirmed viable: `tool_name`, `tool_input`, `continue: false` all supported. FR-001/002/010 resolved. |
| 2 | Recovery suppression (003 FR-017) | FR-016: PostToolUse checks `.claude/recovery-marker.json`, suppresses entirely if present |
| 3 | /clear delivery mechanism | FR-004: Idle-detection polling (not fixed delay), 1s interval, 30s timeout |
| 4 | Hook coexistence with 003 | FR-017: Standalone `carryover-loader.sh`, parallel execution, delimited context blocks |
| 5 | CARRYOVER size limit | FR-019: 80KB cap (~12% of context window), tail-truncation |
| 6 | Shared infrastructure | FR-020: Extract `hook-common.sh` from 003's `recovery-common.sh` (003 refactor needed) |
| 7 | Concurrent sessions | Accepted risk: "most recent unconsumed" heuristic |
| 8 | Stale .loaded cleanup | FR-021: Keep last 5, delete oldest (matches 003 FR-052) |
| 9 | Empty/missing CARRYOVER | FR-022: Inject warning context (signal-file gated) |
| 10 | Observability | FR-023: Shared `.claude/recovery-logs/` directory |

### Round 2 (10 questions) — Operational Correctness

| # | Focus | Key Decision |
|---|-------|-------------|
| 11 | FR-022 false positive | FR-022 rewritten: `.claude/carryover-pending` signal file gates the warning |
| 12 | SessionStart on startup/resume | FR-011: Add `startup`, skip `resume` |
| 13 | stopReason message | FR-002: Single message covering both tmux/non-tmux paths |
| 14 | tmux send-keys failure | FR-004: Poller writes `.claude/carryover-clear-needed` on failure; startup loads reminder |
| 15 | PostToolUse error handling | FR-024: Minimal — `require_tool jq` + exit codes, no signal traps (<200ms hook) |
| 16 | CARRYOVER search scope | FR-006: Active spec directory only (`specs/<feature>/`) |
| 17 | Out-of-scope declarations | New section: 4 explicit exclusions |
| 18 | Preamble content | FR-015: ~150 bytes overhead, within delimiters and size cap |
| 19 | SessionStart error handling | FR-025: Full pattern — signal traps to undo .loaded rename on kill |
| 20 | Multiple file selection | FR-026: Highest sequence number (NN) wins |

### Round 3 (5 questions) — Blind Spots & Race Conditions

| # | Focus | Key Decision |
|---|-------|-------------|
| 21 | JSON escaping (guaranteed bug) | FR-027: All JSON output via `jq` — never raw string interpolation |
| 22 | Feature directory resolution | FR-006: `git branch --show-current` → `specs/${branch}/`, log-and-skip if no match |
| 23 | Double /clear race condition | FR-004: Atomic `mv` claim — zero race window |
| 24 | Poller detachment + stdout corruption | FR-028: Portable `(nohup ... &)` — no `setsid` (not on macOS) |
| 25 | Multi-call CARRYOVER write | Assumption: single Write call, first PostToolUse match fires |

### Key Decisions Requiring 003 Changes

1. **FR-020**: Split 003's `recovery-common.sh` into `hook-common.sh` (shared) + recovery-specific code
2. **Shared log directory**: 002 logs to `.claude/recovery-logs/` alongside 003

### Scripts to Implement

| Script | Hook Event | Matcher | Purpose |
|--------|-----------|---------|---------|
| `carryover-detect.sh` | PostToolUse | (all — fast-path filter) | Detect CARRYOVER writes, fire `continue: false`, spawn poller |
| `carryover-loader.sh` | SessionStart | `clear`, `compact`, `startup` | Load CARRYOVER into `additionalContext` |
| `carryover-poller.sh` | (background) | Spawned by detect | Idle-detection polling, atomic `/clear` delivery |
| `hook-common.sh` | (sourced) | N/A | Shared utils: `is_tmux`, `project_root`, logging, `require_tool` |

### Signal/Marker Files

| File | Written By | Read By | Purpose |
|------|-----------|---------|---------|
| `.claude/carryover-pending` | PostToolUse hook | Loader, Poller | Auto-rotation was initiated — carryover expected |
| `.claude/carryover-pending.claimed` | Poller (atomic `mv`) | Poller | Poller owns the `/clear` — prevents double-clear race |
| `.claude/carryover-clear-needed` | Poller (on failure) | Loader (on startup) | Poller failed — remind user to type `/clear` |
| `.claude/recovery-marker.json` | 003 hooks | 002 PostToolUse (FR-016) | Recovery in progress — suppress 002 entirely |

## How to Resume

1. Read this carryover file
2. Read `specs/002-context-auto-rotation/spec.md` (the full spec — 164 lines)
3. Next step: `/speckit.plan` on 002
4. Note: 003 refactor task (split `recovery-common.sh`) should be tracked

## Convention Notes

Each CONTEXT-CARRYOVER-NN.md is a **historical snapshot** of one session.
Never edit a prior carryover — always create a new one.
The highest-numbered carryover is most current.
