# Context Carryover 04: Spec 002 — Plan Complete + Clarify Round 7 In Progress

**Feature Branch:** `002-context-auto-rotation`
**Date:** 2026-03-10
**Spec Status:** Draft, 37 FRs, 40 clarifications, plan complete, clarify round 7 started (1 question asked, 0 answered)
**Constitution Version:** 1.3.0 (unchanged)

## Project: openclaw-mac

**Repo:** `https://github.com/traylorre/openclaw-mac`
**Branch:** `002-context-auto-rotation`
**Purpose:** macOS hardening guides + audit tooling for a Mac Mini running n8n + Apify for LinkedIn lead gen

## Key Files

| File | What |
|------|------|
| `specs/002-context-auto-rotation/spec.md` | 37 FRs, 40 clarifications (sessions 2026-03-08, 2026-03-09, 2026-03-10), 8 edge cases, 9 assumptions, 6 SCs, 3 user stories |
| `specs/002-context-auto-rotation/plan.md` | **NEW** — Full implementation plan: architecture, hook flow, cross-feature integration, 003 refactoring strategy, settings.json config |
| `specs/002-context-auto-rotation/research.md` | **NEW** — 8 research decisions (R-001 through R-008): hook-common.sh refactor, PostToolUse matcher, compact validation, prompt detection, signal namespaces, settings.json integration, logging, 003 refactor impact |
| `specs/002-context-auto-rotation/data-model.md` | **NEW** — 6 entities: CARRYOVER file, consumed marker (.loaded), carryover-pending, carryover-pending.claimed, carryover-clear-needed, recovery-marker.json (read-only) |
| `specs/002-context-auto-rotation/contracts/hook-posttooluse.md` | **NEW** — PostToolUse hook I/O contract (stdin JSON, stdout JSON, exit codes, side effects, performance targets) |
| `specs/002-context-auto-rotation/contracts/hook-sessionstart.md` | **NEW** — SessionStart hook I/O contract (per-event behavior for clear/compact/startup, signal traps, size handling) |
| `specs/002-context-auto-rotation/contracts/poller-behavior.md` | **NEW** — Poller lifecycle contract (spawn method, poll loop, claim phase, timeout path, crash recovery) |
| `specs/002-context-auto-rotation/quickstart.md` | **NEW** — 5-step setup guide with verification commands and troubleshooting table |
| `specs/002-context-auto-rotation/flowchart.md` | **UPDATED** — Added FR-032 double-/clear guard (3-way event routing), 60s timeout (was 30s), banner node before /clear, crash matrix now 12 rows, 16 terminal states |
| `specs/002-context-auto-rotation/test-plan.md` | **UPDATED** — Added T43-T46 (FR-032 guard + banner tests), T14 timeout 30s→60s, total now 46 tests (17 MUST, 17 SHOULD, 12 boundary) |
| `specs/003-compaction-recovery/spec.md` | Companion feature — 002 integrates via FR-016 (recovery suppression), FR-020 (hook-common.sh), shared logging |
| `CLAUDE.md` | **UPDATED** — Auto-updated with 002 technologies by update-agent-context.sh |

## Session Summary

This session completed `/speckit.plan` for 002 and began `/speckit.clarify` (10 rounds requested).

### Plan Phase Completed

Generated 7 new artifacts:

1. **plan.md** — Architecture, 4-script design (hook-common.sh, carryover-detect.sh, carryover-poller.sh, carryover-loader.sh), cross-feature integration diagram, 003 refactoring impact table, settings.json hook configuration
2. **research.md** — 8 decisions resolving all technical unknowns
3. **data-model.md** — 6 entities with full lifecycle/state transitions
4. **contracts/** — 3 interface contracts (PostToolUse, SessionStart, poller)
5. **quickstart.md** — Deployment and verification guide

Updated 3 existing artifacts:

1. **flowchart.md** — FR-032 guard, 60s timeout, banner step
2. **test-plan.md** — 4 new tests (T43-T46), T14 timeout update
3. **CLAUDE.md** — Auto-updated via update-agent-context.sh

### Clarify Phase In Progress (Round 7)

User requested 10 rounds of clarification as principal engineer with 003 compatibility focus.

**Question 1 asked, awaiting answer:**

> **[CRITICAL] Conflicting preambles on `compact` event.** When both 002's carryover-loader.sh and 003's recovery-detect.sh fire on compact, additionalContext contains BOTH "continue the task" (002) AND "HALT, run audit" (003) — contradictory instructions. FR-016 suppresses PostToolUse but NOT the SessionStart loader on compact events.
>
> Should carryover-loader.sh check for recovery-marker.json on compact events and suppress CARRYOVER injection when recovery is active?
>
> Options presented:
>
> - **A (Recommended):** Suppress on compact when recovery marker exists. CARRYOVER loads later on post-recovery /clear.
> - **B:** Always inject but change preamble to passive ("for reference only").
> - **C:** Remove compact matcher entirely — let 003 own compact events completely.

### Remaining Clarification Questions Queued (9 more)

Priority-ordered questions identified but not yet asked:

| # | Topic | Severity | Summary |
|---|-------|----------|---------|
| 2 | hooks.log rotation | HIGH | No retention policy for shared append-only hooks.log — unbounded growth |
| 3 | Stale poller detection | HIGH | No PID file/lock to prevent multiple concurrent pollers |
| 4 | Signal trap `set -e` interaction | MEDIUM | Trap handler mv failure could abort cleanup under set -euo pipefail |
| 5 | CARRYOVER preamble prompt injection | MEDIUM | 003 has FR-046 defense; 002 preamble has none for model-written content |
| 6 | hook-common.sh source guard | MEDIUM | Double-sourcing risk if recovery-common.sh and script both source it |
| 7 | Post-recovery /clear context ordering | MEDIUM | When both loaders fire on clear, is additionalContext order deterministic? |
| 8 | FR-032 mtime precision | LOW | find -mmin has 1-min granularity; should spec mandate stat-based comparison? |
| 9 | Signal file permissions | LOW | 003 uses 0600 (FR-091); 002 signal files have no specified permissions |
| 10 | hooks.log line format | LOW | Shared log file needs structured format for filtering by feature |

## Architecture Summary (from plan.md)

### Scripts

| Script | Hook Event | Purpose |
|--------|-----------|---------|
| `hook-common.sh` | (sourced) | Shared utilities extracted from recovery-common.sh |
| `carryover-detect.sh` | PostToolUse (.*) | Detect CARRYOVER writes, fire continue:false, spawn poller |
| `carryover-poller.sh` | (background) | Poll tmux for idle prompt, send banner + /clear |
| `carryover-loader.sh` | SessionStart (clear/compact/startup) | Load carryover into additionalContext |

### settings.json Changes

| Hook Event | Matcher | Scripts |
|------------|---------|---------|
| PostToolUse | `.*` | **carryover-detect.sh** (NEW) |
| SessionStart | `compact` | recovery-detect.sh + **carryover-loader.sh** (ADDED) |
| SessionStart | `clear` | recovery-loader.sh + **carryover-loader.sh** (ADDED) |
| SessionStart | `startup` | **carryover-loader.sh** (NEW matcher) |

### hook-common.sh Refactoring (from recovery-common.sh)

Functions moving to hook-common.sh: log_info/warn/error (with configurable HOOK_LOG_PREFIX), is_tmux(), project_root(), require_tool() (new), set_permissions(), iso_timestamp/full(), parse_stdin_json(), json_field/or_null()

Functions staying in recovery-common.sh: All marker/task/log/abort/transcript functions

### Cross-Feature Integration Points

1. `.claude/recovery-marker.json` — 002 READS (FR-016 suppress), 003 WRITES
2. `.claude/recovery-logs/` — Shared log directory, both features WRITE
3. `settings.json` — Platform runs all matching hooks in parallel, concatenates additionalContext
4. `hook-common.sh` — Symmetric dependency: both source it, neither sources the other's specific files

## How to Resume

1. Read this carryover file
2. Read `specs/002-context-auto-rotation/spec.md` (37 FRs, 40 clarifications)
3. Read `specs/002-context-auto-rotation/plan.md` (full architecture)
4. Read `specs/003-compaction-recovery/spec.md` (companion feature, 100 FRs)
5. **Continue `/speckit.clarify` round 7** — Question 1 needs an answer (A/B/C), then 9 more questions queued
6. After clarify completes: `/speckit.tasks` to generate dependency-ordered task list
7. Note: flowchart and test-plan are NOW up to date for FR-032 and 60s timeout (updated this session)

## Convention Notes

Each CONTEXT-CARRYOVER-NN.md is a **historical snapshot** of one session.
Never edit a prior carryover — always create a new one.
The highest-numbered carryover is most current.
