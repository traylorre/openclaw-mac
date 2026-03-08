# Context Carryover 03: Spec 003 — Rounds 21–25

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
| `specs/003-compaction-recovery/spec.md` | 87 FRs, 82 edge cases, 37 assumptions, 23 SCs, 5 entities, 3 user stories |
| `specs/003-compaction-recovery/checklists/requirements.md` | Quality checklist — all items pass |
| `specs/003-compaction-recovery/CONTEXT-CARRYOVER-01.md` | Historical: rounds 1–10 (15 → 55 FRs) |
| `specs/003-compaction-recovery/CONTEXT-CARRYOVER-02.md` | Historical: rounds 11–20 (55 → 75 FRs) |

## Session Summary

This session performed rounds 21–25 of `/speckit.specify` on spec 003-compaction-recovery, growing it from 75 FRs to 87 FRs.

### Round-by-Round

| Round | Focus | FRs Added | Key Additions |
|-------|-------|-----------|---------------|
| 21 | Multi-hook & subagent coordination | FR-076–078 | Subagent tainted edit detection, multi-hook coexistence, audit-format independence |
| 22 | Observability & post-mortem | FR-079–081 | Versioned log format (`recovery-log-v1`), structured metadata for aggregation, configurable notification (default: terminal bell) |
| 23 | Recovery context quality | FR-082–084 | Multi-message context capture (3 preceding messages), 2KB preamble budget, model confirmation before resuming |
| 24 | Non-git & alternative recovery | FR-085–087 | File-backup fallback for non-git repos, out-of-repo edit detection/skip, backup retention policy |
| 25 | Final consolidation | SC-019–023 | 5 new SCs, 6 new assumptions, 13 new edge cases. No contradictions found. |

### New FR Categories (rounds 21–25)

- Multi-Hook & Subagent Coordination (FR-076–078)
- Observability & Post-Mortem (FR-079–081)
- Recovery Context Quality (FR-082–084)
- Non-Git & Alternative Recovery Paths (FR-085–087)

### New Success Criteria (rounds 21–25)

- SC-019: Subagent tainted edits detected with same reliability as main-session edits
- SC-020: Recovery preamble ≤ 2KB
- SC-021: Non-git recovery completes with file-backup-based reverts
- SC-022: Model confirms understanding of interrupted task before resuming
- SC-023: Recovery logs have stable versioned format for external tooling

### Key Planning-Phase Items (cumulative, 13 total)

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
11. **FR-076**: Determine transcript format for subagent tool calls
12. **FR-077**: Determine platform hook multiplicity model
13. **FR-085**: Design file-backup revert strategy for non-git environments

### Spec Architecture (after 25 rounds)

**3 User Stories:**

- US1 (P1): Automatic compaction detection and audit
- US2 (P2): Automated /clear and resume after recovery
- US3 (P2): Interrupted task capture

**FR Categories (20 sections):**

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
- Multi-Hook & Subagent Coordination (FR-076–078)
- Observability & Post-Mortem (FR-079–081)
- Recovery Context Quality (FR-082–084)
- Non-Git & Alternative Recovery Paths (FR-085–087)

## How to Resume

1. Read this carryover file (CONTEXT-CARRYOVER-03.md — highest number is most current)
2. Read `specs/003-compaction-recovery/spec.md` (the full spec)
3. Read `specs/003-compaction-recovery/checklists/requirements.md` (validation status + planning-phase items)
4. Next step: `/speckit.clarify` or `/speckit.plan`

## Convention Notes

Each CONTEXT-CARRYOVER-NN.md is a **historical snapshot** of one session.
Never edit a prior carryover — always create a new one.
The highest-numbered carryover is most current.
