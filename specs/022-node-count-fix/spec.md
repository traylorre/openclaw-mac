# Feature Specification: Node Count Fix

**Feature Branch**: `022-node-count-fix`
**Created**: 2026-03-28
**Status**: Draft

## Problem
The `specs/015-token-workflow-sync/` documentation references "11 nodes" throughout, but the actual imported workflow has 13 nodes. n8n counts internal/webhook response nodes differently, resulting in a mismatch between documented and actual node count.

## Fix
Update all references to "11 nodes" (and "11-node") to "13 nodes" (and "13-node") across:
- `specs/015-token-workflow-sync/spec.md`
- `specs/015-token-workflow-sync/plan.md`
- `specs/015-token-workflow-sync/quickstart.md`
- `specs/015-token-workflow-sync/tasks.md`
- `specs/015-token-workflow-sync/data-model.md`
- `specs/015-token-workflow-sync/research.md`

Also add a parenthetical note in acceptance scenario 2 clarifying the count includes internal webhook response nodes.

## Verification
Grep for "11 nodes" across `specs/015-token-workflow-sync/` — should return zero matches.
