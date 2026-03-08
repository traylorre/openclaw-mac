# Context Carryover 01: Spec 003 — 10 Specify Rounds

**Feature Branch:** `003-compaction-recovery`
**Date:** 2026-03-08
**Spec Status:** Draft, ready for `/speckit.clarify` or `/speckit.plan`
**Constitution Version:** 1.3.0 (unchanged)

## Project: openclaw-mac

**Repo:** `https://github.com/traylorre/openclaw-mac`
**Branch:** `003-compaction-recovery`
**Purpose:** macOS hardening guides + audit tooling for a Mac Mini running n8n + Apify for LinkedIn lead gen

## Key Files

| File | What |
|------|------|
| `specs/003-compaction-recovery/spec.md` | 55 FRs, 49 edge cases, 27 assumptions, 13 SCs, 5 entities, 3 user stories |
| `specs/003-compaction-recovery/checklists/requirements.md` | Quality checklist — all items pass |
| `.claude/commands/compaction-audit.md` | Existing slash command — 003 orchestrates around it, does not reimplement |
| `specs/002-context-auto-rotation/spec.md` | Companion feature — 003 depends on 002 for CARRYOVER loading (but degrades gracefully without it per FR-050) |

## Session Summary

This session performed 10 rounds of `/speckit.specify` on spec 003-compaction-recovery, growing it from 15 FRs to 55 FRs.

### Round-by-Round

| Round | Focus | FRs Added | Key Additions |
|-------|-------|-----------|---------------|
| 1 | Race conditions | FR-016–023 | Re-entrancy, CARRYOVER suppression, halt instruction, crash-safe reads, tmux timing, infinite loops, exactly-once, stale markers |
| 2 | Blind spots | FR-024–031 | Model non-compliance, trivial task extraction, env validation, tmux fallback, missing transcript, preamble, size limits, **platform API gate (FR-031)** |
| 3 | Structural integrity | FR-032–035 | Resolved SC-004/audit interactivity contradiction (batch mode), FR-002/011 overlap, FR-004 timing, FR-025/030 testability. Added abort, observability, recovery-from-failed-recovery |
| 4 | Coverage & completeness | FR-036–039 | Bash tool tainted edits, git dirty tree check, selective revert, post-revert verification |
| 5 | Real-world failures | FR-040–042 | External file conflict detection, new-file delete revert, detached HEAD |
| 6 | Developer experience | FR-043–045 | Persistent recovery log, reverted-vs-preserved summary, verify-before-replay |
| 7 | Security & integrity | FR-046–048 | Prompt injection prevention, critical infrastructure file detection, pre-/clear infrastructure revert |
| 8 | Cross-feature integration | FR-049–051 | Git hook bypass during reverts, feature 002 failure tolerance, dry-run mode |
| 9 | Operational maturity | FR-052–053 | Recovery log retention (10 max), context efficiency (20% budget) |
| 10 | Consolidation | FR-054–055 | Fixed FR-037/SC-004 contradiction (auto-stash in batch mode), temp file cleanup, artifact tracking |

### Key Contradictions Resolved

- **SC-004 vs compaction-audit "Never auto-revert"**: FR-035 adds batch mode for recovery-triggered invocation; manual /compaction-audit keeps interactive behavior
- **FR-002 vs FR-011**: Context injection is primary trigger, tmux send-keys is backup only
- **FR-004 "before or during"**: Capture happens during (SessionStart handler), no pre-compaction hook exists
- **FR-037 vs SC-004**: Batch mode auto-stashes dirty working tree; interactive mode offers to stash

### Key Planning-Phase Blockers

1. **FR-031 (BLOCKING)**: Validate hook input/output formats against actual Claude Code API — `transcript_path`, `session_id`, `additionalContext` injection, event type distinction are all unverified assumptions
2. **FR-007**: Choose sequencing mechanism for /clear after audit completion
3. **FR-020**: Design tmux response-completion detection
4. **FR-035**: Design batch mode extension for compaction-audit command
5. **FR-047**: Define critical infrastructure file path list
6. **FR-049**: Determine git hook bypass mechanism
7. **FR-051**: Design dry-run/simulation mode

### Spec Architecture

**3 User Stories:**

- US1 (P1): Automatic compaction detection and audit
- US2 (P2): Automated /clear and resume after recovery
- US3 (P2): Interrupted task capture

**FR Categories (7 sections):**

- Core (FR-001–015): Detection, audit invocation, /clear, CARRYOVER loading, tmux/non-tmux paths
- Race Condition Safeguards (FR-016–023): Re-entrancy, CARRYOVER suppression, halt, crash-safe reads, tmux timing, infinite loops, exactly-once, stale markers
- Blind Spot Safeguards (FR-024–031): Model non-compliance, trivial task, env validation, tmux fallback, missing transcript, preamble, size limits, API gate
- Structural Integrity (FR-032–035): Abort, observability, partial failure recovery, batch mode
- Coverage & Completeness (FR-036–039): Bash edits, dirty tree, selective revert, verification
- Real-World / Security / Integration (FR-040–051): Conflicts, new-file delete, detached HEAD, prompt injection, infrastructure files, git hook bypass, feature 002 tolerance, dry-run
- Operational / Lifecycle (FR-052–055): Log retention, context efficiency, temp file cleanup, artifact tracking

**5 Key Entities:** Compaction Event, Interrupted Task Context, Recovery State Marker, CARRYOVER File, Recovery Log

## How to Resume

1. Read this carryover file
2. Read `specs/003-compaction-recovery/spec.md` (the full spec)
3. Read `specs/003-compaction-recovery/checklists/requirements.md` (validation status + planning-phase items)
4. Next step: `/speckit.clarify` or `/speckit.plan`

## Convention Notes

Each CONTEXT-CARRYOVER-NN.md is a **historical snapshot** of one session.
Never edit a prior carryover — always create a new one.
The highest-numbered carryover is most current.
