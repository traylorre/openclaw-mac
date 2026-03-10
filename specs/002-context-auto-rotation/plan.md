# Implementation Plan: Context Guardian Auto-Rotation

**Branch**: `002-context-auto-rotation` | **Date**: 2026-03-10 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/002-context-auto-rotation/spec.md`

## Summary

Implement a hook-based system that automates the context rotation cycle when
the context guardian detects usage approaching the hard limit. The system uses
a PostToolUse hook to detect CARRYOVER file writes and halt the model, a
background poller (tmux) or manual instruction (non-tmux) to trigger /clear,
and a SessionStart hook to load carryover context into the fresh session.
Requires extracting shared utilities from 003's `recovery-common.sh` into a
new `hook-common.sh` to maintain symmetric independence between features.

## Technical Context

**Language/Version**: Bash 5.x (POSIX-compatible subset for portability)
**Primary Dependencies**: jq (JSON parsing), git (branch detection), tmux (optional automation)
**Storage**: Filesystem — signal files in `.claude/`, CARRYOVER files in `specs/<branch>/`, logs in `.claude/recovery-logs/`
**Testing**: Unit tests via synthetic stdin JSON + mock tmux; E2E in real Claude Code session
**Target Platform**: macOS (Apple Silicon/Intel) + WSL2 development
**Project Type**: CLI scripts + hook configuration (development infrastructure)
**Performance Goals**: PostToolUse hook <200ms non-matching (SC-005), SessionStart <500ms no-carryover (SC-006)
**Constraints**: 80KB carryover cap (FR-019), 60s poller timeout (FR-004), 0600 permissions for signal files
**Scale/Scope**: Single developer, single machine, 1–5 carryover files per feature branch

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| # | Principle | Relevance | Status |
|---|-----------|-----------|--------|
| I | Documentation-Is-the-Product | Preserves doc workflow continuity across rotations | PASS |
| II | Threat-Model Driven (NON-NEGOTIABLE) | N/A — infrastructure tooling, not a security control | PASS (exempt) |
| III | Free-First | jq, git, tmux, bash — all free/OSS | PASS |
| IV | Cite Canonical Sources | Claude Code hooks API (validated 2026-03-08) | PASS |
| V | Every Recommendation Is Verifiable | Test plan (42+ tests), E2E validation | PASS |
| VI | Bash Scripts Are Infrastructure | All scripts: `set -euo pipefail`, shellcheck, idempotent | MUST ENFORCE |
| VII | Defense in Depth | Detect → Stop → /clear → Load (3 phases, 14 terminal states, crash recovery) | PASS |
| VIII | Explicit Over Clever | Clear stopReason messages, signal file names, log output | MUST ENFORCE |
| IX | Markdown Quality Gate | N/A — scripts and config, not documentation | N/A |
| X | CLI-First Infrastructure | All components are CLI scripts and hook configs | PASS |

**Gate result**: PASS — no violations. Principles VI and VIII require active
enforcement during implementation (shellcheck, colored output, quoted variables).

**Post-design re-check**: PASS — no new violations introduced by Phase 1 design.
hook-common.sh refactoring is additive (no behavioral changes to existing scripts).

## Project Structure

### Documentation (this feature)

```text
specs/002-context-auto-rotation/
├── spec.md                        # 34 FRs, 45 clarifications
├── plan.md                        # This file
├── research.md                    # Phase 0: research findings
├── data-model.md                  # Phase 1: entity definitions
├── quickstart.md                  # Phase 1: setup guide
├── contracts/                     # Phase 1: interface contracts
│   ├── hook-posttooluse.md        # PostToolUse hook I/O contract
│   ├── hook-sessionstart.md       # SessionStart hook I/O contract
│   └── poller-behavior.md         # Poller lifecycle contract
├── flowchart.md                   # End-to-end Mermaid flowchart (updated for FR-032, 60s)
├── test-plan.md                   # Test plan (updated for FR-032, 60s)
└── checklists/
    └── requirements.md            # Quality checklist
```

### Source Code (dotfiles + project hooks)

```text
~/dotfiles/scripts/bin/              # Symlinked to ~/bin/
├── hook-common.sh                   # NEW: Shared hook utilities (extracted from recovery-common.sh)
├── carryover-detect.sh              # NEW: PostToolUse hook — detect CARRYOVER writes
├── carryover-poller.sh              # NEW: Background idle-detection poller (tmux)
├── carryover-loader.sh              # NEW: SessionStart hook — load carryover context
├── recovery-common.sh               # MODIFIED: Sources hook-common.sh, keeps recovery-specific code
├── recovery-detect.sh               # EXISTING (003): SessionStart(compact) handler
├── recovery-loader.sh               # EXISTING (003): SessionStart(clear) handler
├── recovery-precompact.sh           # EXISTING (003): PreCompact handler
├── recovery-watcher.sh              # EXISTING (003): Background /clear trigger
├── recovery-health.sh               # EXISTING (003): Infrastructure health-check
├── context-guardian.sh              # EXISTING: PreToolUse guardian (UNTOUCHED per FR-012)
└── context-monitor.sh               # EXISTING: Status line monitor (UNTOUCHED per FR-012)

~/dotfiles/claude/.claude/
└── settings.json                    # MODIFIED: Add PostToolUse + SessionStart entries for 002

.claude/                             # Runtime artifacts (not version-controlled)
├── carryover-pending                # Signal: rotation initiated, /clear needed
├── carryover-pending.claimed        # Signal: poller claimed ownership of /clear
├── carryover-clear-needed           # Signal: poller failed, manual /clear needed
└── recovery-logs/                   # Shared log directory with 003
    └── *.log                        # Per-invocation timestamped log files (7-day retention)
```

**Structure Decision**: Scripts + hook config infrastructure pattern matching
003's established structure. New scripts symlinked alongside existing 003 scripts.
Shared `hook-common.sh` extracted from 003's `recovery-common.sh` to prevent
coupling (FR-020). Signal files use `.claude/` directory (same as 003's recovery
marker). Log directory shared with 003 (FR-023).

## Architecture Overview

### Hook Flow (Happy Path — tmux)

```text
                      ┌────────────────────────────────────────────────────────┐
                      │             Claude Code Session (tmux)                 │
                      │                                                        │
  Guardian fires ────►│  Model writes CONTEXT-CARRYOVER-NN.md                 │
  (PreToolUse)        │                                                        │
                      │  PostToolUse fires → carryover-detect.sh              │
                      │    ├── tool_name == Write|Edit? (fast-path exit if no) │
                      │    ├── basename matches CARRYOVER regex?               │
                      │    ├── .claude/recovery-marker.json exists? (FR-016)   │
                      │    ├── Write .claude/carryover-pending                 │
                      │    ├── Spawn carryover-poller.sh (detached)            │
                      │    └── Output: {continue:false, stopReason:...}        │
                      │                                                        │
  Claude stops ──────►│  carryover-poller.sh (background)                      │
                      │    ├── Install EXIT trap (clean .claimed)              │
                      │    ├── Poll tmux pane for idle prompt (1s, 60s max)    │
                      │    ├── Strip ANSI, match 3-line pattern                │
                      │    ├── Atomic mv: pending → .claimed                   │
                      │    ├── Send banner: "⏳ Auto-clearing..."              │
                      │    └── Send /clear via tmux send-keys                  │
                      │                                                        │
  /clear fires ──────►│  SessionStart(clear) → carryover-loader.sh            │
                      │    ├── Validate jq, install signal traps               │
                      │    ├── FR-032: Check .loaded mtime ≤60s guard          │
                      │    ├── Derive spec dir from git branch                 │
                      │    ├── Find highest-NN unconsumed CARRYOVER            │
                      │    ├── Size check: <100B skip, >80KB truncate          │
                      │    ├── Rename → .loaded (protected by traps)           │
                      │    ├── Wrap in preamble delimiters                     │
                      │    ├── Output via jq: additionalContext                │
                      │    └── Cleanup: delete pending, prune .loaded >5       │
                      │                                                        │
  Fresh session ─────►│  Model resumes with carryover context                  │
                      └────────────────────────────────────────────────────────┘
```

### Cross-Feature Integration (002 ↔ 003)

```text
   Feature 002                       Shared                        Feature 003
┌──────────────────┐    ┌───────────────────────────┐    ┌──────────────────────┐
│ carryover-detect │    │      hook-common.sh        │    │ recovery-precompact  │
│ carryover-poller │───►│  • log_info/warn/error     │◄───│ recovery-detect      │
│ carryover-loader │    │  • is_tmux()               │    │ recovery-loader      │
└──────┬───────────┘    │  • project_root()          │    │ recovery-watcher     │
       │                │  • require_tool()          │    │ recovery-health      │
       │                │  • parse_stdin_json()      │    └──────────────────────┘
       │                │  • json_field()            │              │
       │                │  • set_permissions()       │              │
       │                │  • iso_timestamp()         │              │
       │                └───────────────────────────┘              │
       │                                                           │
       │   Coordination Points:                                    │
       │   ┌──────────────────────────────────────────────────┐   │
       │   │ .claude/recovery-marker.json                      │   │
       ├──►│   002 READS (FR-016: suppress if present)         │◄──┤
       │   │   003 WRITES/READS (recovery lifecycle)           │   │
       │   ├──────────────────────────────────────────────────┤   │
       │   │ .claude/recovery-logs/                            │   │
       ├──►│   002 WRITES (hook event logging)                 │◄──┤
       │   │   003 WRITES (recovery logs)                      │   │
       │   ├──────────────────────────────────────────────────┤   │
       │   │ settings.json hooks                               │   │
       │   │   Platform runs all matching hooks in parallel    │   │
       │   │   additionalContext values concatenated            │   │
       │   └──────────────────────────────────────────────────┘   │
       │                                                           │
       │   Independence guarantees:                                │
       │   • 002 never sources 003-specific files                  │
       │   • 003 never sources 002-specific files                  │
       │   • Either can be uninstalled without breaking the other  │
       │   • Composition via platform hook concatenation            │
       └───────────────────────────────────────────────────────────┘
```

### Script Responsibilities

| Script | Hook Event | Trigger | Key FRs |
|--------|-----------|---------|---------|
| `hook-common.sh` | (sourced) | All 002+003 scripts | FR-020, FR-024, FR-031 |
| `carryover-detect.sh` | PostToolUse | `.*` (all tools) | FR-001, FR-002, FR-010, FR-016, FR-022, FR-024, FR-028 |
| `carryover-poller.sh` | (background) | Spawned by detect | FR-003, FR-004, FR-028, FR-029 |
| `carryover-loader.sh` | SessionStart | `clear`, `compact`, `startup` | FR-006–FR-009, FR-011, FR-019–FR-022, FR-025–FR-027, FR-030, FR-032–FR-034 |

### Refactoring Impact on 003

The extraction of `hook-common.sh` from `recovery-common.sh` is a prerequisite (FR-020).

| recovery-common.sh function | Destination | Notes |
|------------------------------|------------|-------|
| Environment validation (HOME, PATH) | hook-common.sh | Parameterized prefix |
| Tool validation (jq, git inline loop) | hook-common.sh | New `require_tool()` function |
| `log_info`, `log_warn`, `log_error` | hook-common.sh | Configurable `HOOK_LOG_PREFIX` |
| `is_tmux()` | hook-common.sh | Unchanged |
| `project_root()` | hook-common.sh | Unchanged |
| `set_permissions()` | hook-common.sh | Unchanged |
| `iso_timestamp()`, `iso_timestamp_full()` | hook-common.sh | Unchanged |
| `parse_stdin_json()` | hook-common.sh | Unchanged |
| `json_field()`, `json_field_or_null()` | hook-common.sh | Unchanged |
| All marker/task/log/abort/transcript functions | Stays in recovery-common.sh | recovery-common.sh sources hook-common.sh |

After refactoring, `recovery-common.sh` header becomes:

```bash
#!/usr/bin/env bash
# recovery-common.sh — Recovery-specific library for 003 scripts
HOOK_LOG_PREFIX="recovery"
source "$HOME/bin/hook-common.sh"

# ... all recovery-specific functions unchanged ...
```

All existing 003 scripts continue to source `recovery-common.sh` — no changes
to those scripts. The shared functions simply come from `hook-common.sh` now.

### settings.json Hook Configuration

Updated `~/dotfiles/claude/.claude/settings.json` (see quickstart.md for full file):

| Hook Event | Matcher | Scripts | Timeout |
|------------|---------|---------|---------|
| PreToolUse | `.*` | context-guardian.sh | default |
| **PostToolUse** | **`.*`** | **carryover-detect.sh** | **default** |
| PreCompact | `` | recovery-precompact.sh | 30s |
| SessionStart | `compact` | recovery-detect.sh + **carryover-loader.sh** | 60s / **30s** |
| SessionStart | `clear` | recovery-loader.sh + **carryover-loader.sh** | 30s / **30s** |
| **SessionStart** | **`startup`** | **carryover-loader.sh** | **30s** |
| Stop | `.*` | notify-log | default |
| Notification | `.*` | notify-log | default |

**Bold** = new or modified for 002.

## Complexity Tracking

No constitution violations to justify.
