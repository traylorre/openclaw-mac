# Implementation Plan: Token Workflow Sync

**Branch**: `015-token-workflow-sync` | **Date**: 2026-03-28 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/015-token-workflow-sync/spec.md`

## Summary

Resolve the divergence between the git-committed `workflows/token-check.json` (11 nodes with dual-token lifecycle, OAuth refresh, circuit breaker, error classification) and the running n8n instance (9 nodes, old version). Use the existing `make workflow-import` mechanism. Add a pre-import Static Data backup step to prevent data loss, and post-import verification to confirm correct sync. Remove the duplicate workflow created by the failed n8n UI import.

## Technical Context

**Language/Version**: Bash 5.x (POSIX-compatible subset per Constitution VI)
**Primary Dependencies**: Docker CLI, n8n CLI (`import:workflow`, `export:workflow`), jq, curl, macOS Keychain (`security`)
**Storage**: n8n SQLite database (via container), filesystem (`workflows/` directory)
**Testing**: Manual verification via n8n REST API and UI; automated verification script
**Target Platform**: macOS (Apple Silicon Mac Mini)
**Project Type**: CLI/infrastructure tooling
**Performance Goals**: Import completes in under 30 seconds
**Constraints**: n8n container is read-only (no `docker cp`); must use `docker exec` + tmpfs
**Scale/Scope**: Single workflow sync operation (1 workflow, 11 nodes)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Gate | Status | Notes |
|------|--------|-------|
| I. Documentation-Is-the-Product | PASS | Operational sync, not documentation change |
| II. Threat-Model Driven | PASS | Protects LinkedIn credential lifecycle — token refresh failure = pipeline down |
| III. Free-First | PASS | All tools are free (Docker, n8n OSS, bash, jq) |
| IV. Cite Canonical Sources | PASS | n8n CLI docs for import/export behavior |
| V. Every Recommendation Is Verifiable | PASS | Post-import verification via API query |
| VI. Bash Scripts Are Infrastructure | PASS | All operations are CLI commands |
| VII. Defense in Depth | PASS | Pre-import backup + post-import verification = two layers |
| VIII. Explicit Over Clever | PASS | Operator-initiated, clear Makefile targets |
| IX. Markdown Quality Gate | N/A | No markdown documentation changes |
| X. CLI-First Infrastructure | PASS | `make workflow-import` is the interface |

All gates pass. No violations to justify.

## Project Structure

### Documentation (this feature)

```text
specs/015-token-workflow-sync/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── workflow-sync-contract.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
scripts/
├── workflow-sync.sh          # Existing — may need pre-import backup addition
└── lib/
    └── common.sh             # Existing — require_command(), logging functions

workflows/
└── token-check.json          # Authoritative workflow definition (11 nodes)

Makefile                      # Existing workflow-import/workflow-export targets
```

**Structure Decision**: No new directories or files beyond the spec artifacts. The implementation adds a pre-import Static Data logging step and post-import verification. All changes are within the existing project structure.

## Adversarial Review #2

| Finding | Drift Type | Resolution |
|---------|-----------|------------|
| Spec Assumptions said workflow-sync.sh "does not need modification" but Plan said it would be modified for Static Data backup. | Spec-Plan inconsistency | Updated Assumption to acknowledge minor enhancements while noting core logic unchanged. |
| Research R1 selected "re-initialize via migration code" approach but FR-004 said "export and restore afterward" — different mechanisms. | Spec-Research inconsistency | Aligned FR-004 with R1's practical approach: log current Static Data for reference, rely on migration code for re-initialization, allow manual correction via UI. |
| Contract doesn't reflect enhanced import workflow (pre-backup, post-verification). | Contract gap | Low severity — contract describes existing `make` targets; verification is a new addition to be documented in tasks. |

**Cross-artifact consistency**: Node count (11), workflow ID (`token-check`), Static Data fields, and activation order all consistent across spec, plan, research, data-model, and contract.

**Gate: 0 CRITICAL, 0 HIGH remaining. No spec drift requiring plan realignment.**
