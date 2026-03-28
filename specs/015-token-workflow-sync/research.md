# Research: Token Workflow Sync

## R1: n8n `import:workflow` Static Data Behavior

**Decision**: Pre-import backup of Static Data is required.

**Rationale**: n8n's `import:workflow --input=<file>` command replaces the entire workflow definition in its database, including the `staticData` field. The committed `workflows/token-check.json` has `"staticData": null` (clean template state). Importing this file overwrites any runtime Static Data that the workflow has accumulated (grant timestamps, retry counts, circuit breaker flags). This would reset token expiry calculations and potentially trigger false alerts.

**Alternatives considered**:
- *Modify committed JSON to include Static Data*: Rejected — leaks runtime state into version control, causes git diff noise, and stale timestamps on other machines.
- *Strip staticData from JSON before import*: n8n still overwrites with null if field is absent.
- *Post-import restore via n8n API*: n8n REST API does not expose a direct Static Data write endpoint.
- *Pre-import export + post-import re-inject via n8n CLI*: The export captures current staticData. After import, use `docker exec` to directly update the workflow's staticData in n8n's SQLite database. Rejected — fragile, bypasses n8n's ORM.
- *Pre-import export + trigger workflow to self-initialize*: If the workflow is designed to handle `staticData: null` gracefully (which the migration code does), the data loss is acceptable if the operator sets initial timestamps. **Selected approach with enhancement**: export current Static Data via API before import, then execute one manual workflow run to let the migration code re-initialize.

**Key finding**: The workflow's check-token code node already handles the `staticData: null` case by initializing timestamps to `now()`. The only data at risk is the historical accuracy of `access_token_granted_at` and `refresh_token_granted_at`. If the operator knows the actual grant date, they can set it via the n8n UI after import (Static Data editor in workflow settings).

**Source**: n8n CLI documentation, workflow-sync.sh source code analysis.

## R2: Duplicate Workflow Detection

**Decision**: Detect duplicates by querying n8n REST API for workflows with similar names.

**Rationale**: When a workflow is imported via n8n UI (drag-and-drop), n8n creates a new workflow with a generated UUID, not the original ID. The duplicate will have a name like "token-check 2" or "token-check (copy)". The CLI `import:workflow` command matches by ID and overwrites, so it won't create duplicates — only the UI import does.

**Alternatives considered**:
- *Delete all workflows and re-import*: `make workflow-clean` exists but is destructive — removes all workflows including hmac-verify.
- *Query by name pattern*: Use n8n REST API `GET /api/v1/workflows` and filter for name containing "token-check" with a different ID. **Selected approach**.
- *Manual UI deletion*: Works but violates Constitution X (CLI-first). Used as fallback only.

**Source**: n8n REST API documentation, existing `make workflow-clean` target.

## R3: Post-Import Verification

**Decision**: Verify via n8n REST API after import.

**Rationale**: The operator needs confidence that the import succeeded. Verification checks: (1) workflow exists with correct ID, (2) node count matches expected (11), (3) workflow is active, (4) webhook endpoint responds to a health check.

**Alternatives considered**:
- *Manual UI inspection*: Not scriptable, violates Constitution X.
- *Export after import and diff*: Heavy-weight, exports include volatile metadata.
- *API query for workflow metadata*: Lightweight, provides node count, active state, and webhook registration. **Selected approach**.

**Source**: n8n REST API, existing `activate_workflows()` pattern in workflow-sync.sh.

## R4: hmac-verify Dependency

**Decision**: Import hmac-verify before token-check (already handled).

**Rationale**: The token-check workflow's webhook path invokes the hmac-verify sub-workflow. If hmac-verify is not active, webhook authentication fails. The existing `activate_workflows()` function in workflow-sync.sh already sorts hmac-verify first.

**Alternatives considered**: None needed — existing code handles this correctly.

**Source**: workflow-sync.sh line 177-185.
