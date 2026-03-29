# Feature Specification: Token Workflow Sync

**Feature Branch**: `015-token-workflow-sync`
**Created**: 2026-03-28
**Status**: Draft
**Input**: Resolve token workflow divergence between git-committed workflows/token-check.json (13 nodes) and the running n8n instance (9 nodes, old version). Use existing make workflow-import. Verify Static Data survives import.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Sync Authoritative Workflow to Running Instance (Priority: P1)

As the platform operator, I need the running n8n instance to execute the current authoritative token-check workflow (13 nodes with dual-token lifecycle, OAuth refresh, circuit breaker, error classification) instead of the outdated 9-node version, so that token expiry monitoring and automated refresh function correctly.

**Why this priority**: The divergence means the running workflow lacks OAuth refresh, circuit breaker logic, and error classification. If the LinkedIn access token expires, the pipeline cannot auto-recover. This is the core problem to solve.

**Independent Test**: Run `make workflow-import`, then verify in the n8n UI that the token-check workflow shows 13 nodes with the correct dual-path architecture (schedule + webhook).

**Acceptance Scenarios**:

1. **Given** the n8n instance is running with a 9-node token-check workflow, **When** the operator runs `make workflow-import`, **Then** the running workflow is replaced (not duplicated) with the 13-node version from `workflows/token-check.json`.
2. **Given** the import has completed, **When** the operator opens the token-check workflow in the n8n UI, **Then** all 13 nodes are visible (13 nodes including internal webhook response nodes) with correct connections: Schedule Trigger, Webhook, HMAC Verify, Is Verified?, Check Token (schedule path), Check Token (webhook path), Should Refresh?, Refresh Access Token, Handle Refresh Response, Alert Needed?, and Alert OpenClaw.
3. **Given** the import has completed, **When** the operator triggers the workflow via the schedule path, **Then** the dual-token lifecycle logic executes without errors.

---

### User Story 2 - Preserve Static Data Across Import (Priority: P1)

As the platform operator, I need any existing Static Data (token grant timestamps, refresh retry state, circuit breaker flags) to survive the workflow import, so that token expiry calculations remain accurate and the system does not lose track of when tokens were granted.

**Why this priority**: If Static Data is lost or reset during import, the workflow will miscalculate token expiry dates. The migration code (grant_timestamp to access_token_granted_at / refresh_token_granted_at) must function correctly after import.

**Independent Test**: Before import, record the current Static Data values via the n8n UI or API. After import, verify the same values are present (or correctly migrated).

**Acceptance Scenarios**:

1. **Given** the running workflow has Static Data with `grant_timestamp` set, **When** the import completes and the workflow executes, **Then** the migration code converts `grant_timestamp` to `access_token_granted_at` and `refresh_token_granted_at` and deletes the legacy field.
2. **Given** the running workflow has no Static Data (null), **When** the import completes and the workflow executes for the first time, **Then** both `access_token_granted_at` and `refresh_token_granted_at` are initialized to the current time.
3. **Given** the running workflow already has `access_token_granted_at` and `refresh_token_granted_at` set, **When** the import completes and the workflow executes, **Then** existing values are preserved without re-initialization.

---

### User Story 3 - Remove Duplicate Workflow (Priority: P2)

As the platform operator, I need the duplicate workflow created by the failed n8n UI import to be removed, so that only one token-check workflow exists in the n8n instance to avoid confusion and accidental execution of the wrong version.

**Why this priority**: A duplicate workflow could fire on the same schedule, causing double alerts or conflicting refresh attempts. This is a cleanup task after the primary sync.

**Independent Test**: After cleanup, query the n8n API or UI to confirm exactly one workflow with ID `token-check` exists.

**Acceptance Scenarios**:

1. **Given** the n8n instance contains a duplicate token-check workflow (created by the failed UI import), **When** the operator identifies and removes the duplicate, **Then** only the authoritative 13-node workflow remains.
2. **Given** the duplicate has been removed and `make workflow-import` has run, **When** the operator lists all workflows, **Then** no workflow name contains "copy" or similar duplicate indicators.

---

### Edge Cases

- What happens if the n8n container is not running when `make workflow-import` is executed? The script checks container status and exits with a clear error message.
- What happens if the n8n API key is not stored in macOS Keychain? The import succeeds but workflows remain inactive. A warning is logged with instructions to store the key.
- What happens if Static Data contains corrupted or unexpected fields? The check-token code node handles unknown fields gracefully by only reading expected keys.
- What happens if a concurrent workflow execution is in progress during import? The n8n import command replaces the workflow definition atomically; in-flight executions complete with the old version.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The operator MUST be able to sync the authoritative workflow from `workflows/token-check.json` to the running n8n instance using `make workflow-import`.
- **FR-002**: The import MUST replace the existing workflow (not create a duplicate) by matching on workflow ID (`token-check`).
- **FR-003**: The workflow MUST be activated after import (schedule trigger armed, webhook endpoint registered).
- **FR-004**: Static Data MUST survive the import cycle — existing grant timestamps, retry counts, and circuit breaker flags MUST be preserved. Since n8n's `import:workflow` overwrites the `staticData` field from the JSON file, the implementation MUST log current Static Data (via API export) before import for operator reference. After import, the workflow's built-in migration code re-initializes Static Data on first execution. If the operator knows the actual grant date, they MUST be able to set it via the n8n UI Static Data editor.
- **FR-005**: The Static Data migration code MUST convert legacy `grant_timestamp` to `access_token_granted_at` and `refresh_token_granted_at` on first execution after import.
- **FR-006**: Any duplicate workflows created by prior failed imports MUST be identified (by name pattern, e.g., names containing "copy", "2", or duplicate entries with different IDs) and removed.
- **FR-007**: The import process MUST validate that the imported workflow has the expected node count (13 nodes) after import.
- **FR-008**: The post-import verification MUST confirm the workflow is active and the webhook endpoint responds.

### Key Entities

- **Workflow Definition**: The JSON file representing the token-check workflow, including nodes, connections, settings, and Static Data.
- **Static Data**: Persistent key-value store attached to the workflow, containing token grant timestamps, refresh state, and circuit breaker flags.
- **Workflow Activation State**: Whether the workflow's triggers (schedule, webhook) are armed and responding.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After sync, the running n8n instance contains exactly one token-check workflow with 13 nodes.
- **SC-002**: The workflow's schedule trigger fires at 09:00 UTC daily without manual intervention.
- **SC-003**: The webhook endpoint (`POST /token-check`) responds to authenticated requests within 5 seconds.
- **SC-004**: Static Data grant timestamps are accurate to within 1 day of the actual OAuth grant date after import.
- **SC-005**: No duplicate token-check workflows exist in the n8n instance after the sync process completes.

## Assumptions

- The n8n container (`openclaw-n8n`) is running and accessible via Docker CLI.
- The existing `scripts/workflow-sync.sh` import mechanism is functional. Minor enhancements (Static Data backup logging, post-import verification) may be added but the core import/export logic is unchanged.
- The n8n API key is stored in macOS Keychain (or the operator accepts inactive workflows with a plan to activate later).
- The 9-node workflow currently running is a known prior version, not a custom modification that should be preserved.
- The `grant_timestamp` Static Data field may or may not be set — the migration code handles both cases.

## Clarifications

### Session 2026-03-28

No critical ambiguities detected. All taxonomy categories assessed as Clear. Adversarial Review #1 resolved the key technical concern (Static Data overwrite on import). Proceeding to planning.

## Adversarial Review #1

| Severity | Finding | Resolution |
|----------|---------|------------|
| CRITICAL | FR-004 assumes Static Data survives import, but n8n `import:workflow` overwrites `staticData` from the JSON file. If committed JSON has `staticData: null`, runtime state (grant timestamps, circuit breaker flags) is destroyed. | Updated FR-004: implementation must export current Static Data before import and restore afterward. Added explicit mechanism requirement. |
| MEDIUM | FR-006 lacks duplicate detection method. n8n UI copies get different UUIDs; need name-pattern matching to find them. | Updated FR-006: detect duplicates by name pattern (e.g., "copy", " 2", or entries with different IDs but similar names). |
| MEDIUM | Webhook re-registration after import could change webhookId, breaking existing HMAC-verified integrations. | Already handled: `activate_workflows()` in workflow-sync.sh deactivates then reactivates, and sorts hmac-verify first. No spec change needed. |
| LOW | FR-007/FR-008 add verification scope beyond core sync. | Acceptable — lightweight validation, provides defense-in-depth. No change. |
| LOW | If import runs during 09:00 UTC schedule window, old and new workflows could both fire. | Operator-initiated timing, controllable. No spec change needed. |
| NONE | Static Data contains no secrets — only timestamps and boolean flags. No credential exposure risk from git-committed JSON. | No action needed. |

**Gate: 0 CRITICAL remaining, 0 HIGH remaining.** The CRITICAL finding (Static Data overwrite) was resolved by updating FR-004 with an explicit backup-and-restore requirement.
