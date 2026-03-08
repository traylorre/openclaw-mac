# Context Carryover 02: Spec 003 — Rounds 11–20

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
| `specs/003-compaction-recovery/spec.md` | 75 FRs, 69 edge cases, 32 assumptions, 18 SCs, 5 entities, 3 user stories |
| `specs/003-compaction-recovery/checklists/requirements.md` | Quality checklist — all items pass |
| `specs/003-compaction-recovery/CONTEXT-CARRYOVER-01.md` | Historical: rounds 1–10 (15 → 55 FRs) |
| `.claude/commands/compaction-audit.md` | Existing slash command — 003 orchestrates around it |

## Session Summary

This session performed rounds 11–20 of `/speckit.specify` on spec 003-compaction-recovery, growing it from 55 FRs to 75 FRs.

### Round-by-Round

| Round | Focus | FRs Added | Key Additions |
|-------|-------|-----------|---------------|
| 11 | Filesystem & resource constraints | FR-056–058 | Read-only FS fallback (stdout-only recovery), symlink resolution for reverts, artifact permission hygiene |
| 12 | Git operational edge cases | FR-059–061 | Index lock detection, submodule-aware reverts, merge/rebase-in-progress handling |
| 13 | Signal & interrupt handling | FR-062–063 | Signal traps (SIGTERM/SIGINT/SIGHUP) with state persistence, resumable recovery workflow |
| 14 | Transcript parsing robustness | FR-064–065 | Defensive parsing (skip unrecognized entries), bounded scan window (last 1MB) |
| 15 | Revert correctness & granularity | FR-066–067 | Multi-edit grouping (revert to pre-compaction state), rename/move revert |
| 16 | Scale & performance boundaries | FR-068–069 | Summarized output for >50 tainted edits, pre-write log cleanup ordering |
| 17 | Platform compatibility & versioning | FR-070–071 | 10-second hook timeout with staged degradation, Claude Code version logging |
| 18 | Environment & context inheritance | FR-072–073 | Environment variable validation, additionalContext size limit detection/truncation |
| 19 | Testing & validation infrastructure | FR-074–075 | Dry-run code path fidelity, health-check command for pre-flight verification |
| 20 | Consolidation | SC-014–018 | 5 new success criteria, 8 new assumptions, 24 new edge cases, checklist update |

### New FR Categories (rounds 11–20)

- Filesystem & Resource Constraints (FR-056–058)
- Git Operational Edge Cases (FR-059–061)
- Signal & Interrupt Handling (FR-062–063)
- Transcript Parsing Robustness (FR-064–065)
- Revert Correctness & Granularity (FR-066–067)
- Scale & Performance Boundaries (FR-068–069)
- Platform Compatibility & Versioning (FR-070–071)
- Environment & Context Inheritance (FR-072–073)
- Testing & Validation Infrastructure (FR-074–075)

### New Success Criteria (rounds 11–20)

- SC-014: Hook completes within 10 seconds even for large transcripts
- SC-015: Resumable recovery after interruption
- SC-016: Health-check validates infrastructure without compaction
- SC-017: Submodule tainted edits detected and reverted
- SC-018: Read-only FS recovery via additionalContext-only path

### Key Planning-Phase Items (cumulative)

1. **FR-031 (BLOCKING)**: Validate hook input/output formats against actual Claude Code API
2. **FR-007**: Choose sequencing mechanism for /clear after audit completion
3. **FR-020**: Design tmux response-completion detection
4. **FR-035**: Design batch mode extension for compaction-audit command
5. **FR-047**: Define critical infrastructure file path list
6. **FR-049**: Determine git hook bypass mechanism
7. **FR-051**: Design dry-run/simulation mode
8. **FR-060**: Determine submodule detection and per-submodule revert approach
9. **FR-070**: Validate platform hook timeout enforcement
10. **FR-075**: Design health-check command scope and output format

### Spec Architecture (after 20 rounds)

**3 User Stories:**
- US1 (P1): Automatic compaction detection and audit
- US2 (P2): Automated /clear and resume after recovery
- US3 (P2): Interrupted task capture

**FR Categories (16 sections):**
- Core (FR-001–015)
- Race Condition Safeguards (FR-016–023)
- Blind Spot Safeguards (FR-024–031)
- Structural Integrity (FR-032–035)
- Coverage & Completeness (FR-036–039)
- Real-World Failure Handling (FR-040–042)
- Developer Experience & Resumption Quality (FR-043–045)
- Security & Integrity (FR-046–048)
- Cross-Feature Integration (FR-049–051)
- Operational Maturity (FR-052–053)
- Lifecycle & Cleanup (FR-054–055)
- Filesystem & Resource Constraints (FR-056–058)
- Git Operational Edge Cases (FR-059–061)
- Signal & Interrupt Handling (FR-062–063)
- Transcript Parsing Robustness (FR-064–065)
- Revert Correctness & Granularity (FR-066–067)
- Scale & Performance Boundaries (FR-068–069)
- Platform Compatibility & Versioning (FR-070–071)
- Environment & Context Inheritance (FR-072–073)
- Testing & Validation Infrastructure (FR-074–075)

## How to Resume

1. Read this carryover file (CONTEXT-CARRYOVER-02.md — highest number is most current)
2. Read `specs/003-compaction-recovery/spec.md` (the full spec)
3. Read `specs/003-compaction-recovery/checklists/requirements.md` (validation status + planning-phase items)
4. Next step: `/speckit.clarify` or `/speckit.plan`

## Convention Notes

Each CONTEXT-CARRYOVER-NN.md is a **historical snapshot** of one session.
Never edit a prior carryover — always create a new one.
The highest-numbered carryover is most current.
