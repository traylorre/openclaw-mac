# Data Model: Token Workflow Sync

## Entities

### Workflow Definition

The n8n workflow JSON file stored in `workflows/token-check.json`.

| Field | Type | Description |
|-------|------|-------------|
| id | string | Workflow identifier (`token-check`). Used for import matching. |
| name | string | Human-readable name (`token-check`). |
| nodes | array | List of 11 node definitions (triggers, code, HTTP, conditionals). |
| connections | object | Node-to-node wiring (edges in the workflow graph). |
| settings | object | Workflow-level configuration (timezone, error handling). |
| staticData | object/null | Runtime state persisted across executions. `null` in git-committed version. |
| active | boolean | Whether the workflow's triggers are armed. |

### Static Data (Runtime State)

Persisted key-value store within the workflow. Mutated at runtime by code nodes.

| Field | Type | Description | Default |
|-------|------|-------------|---------|
| access_token_granted_at | ISO 8601 string | When the current access token was granted | `now()` on first run |
| refresh_token_granted_at | ISO 8601 string | When the current refresh token was granted | `now()` on first run |
| grant_timestamp | ISO 8601 string | Legacy field — migrated to the two fields above | Deleted after migration |
| refresh_retry_count | number | Consecutive failed refresh attempts (0-3) | 0 |
| refresh_in_progress | boolean | Concurrency guard for refresh operations | false |
| refresh_token_expired | boolean | Circuit breaker — stops refresh attempts | false |
| last_refresh_attempt | ISO 8601 string | Timestamp of most recent refresh attempt | null |
| last_refresh_result | string | `success`, `failed`, or `not_attempted` | `not_attempted` |

### State Transitions

```
staticData: null → First execution → {
  access_token_granted_at: now(),
  refresh_token_granted_at: now(),
  refresh_retry_count: 0,
  refresh_in_progress: false,
  refresh_token_expired: false
}

grant_timestamp present → Migration → {
  access_token_granted_at: grant_timestamp,
  refresh_token_granted_at: grant_timestamp,
  grant_timestamp: DELETED
}

Refresh success → {
  access_token_granted_at: now(),
  refresh_retry_count: 0,
  last_refresh_result: 'success'
}

Refresh failure (retryable) → {
  refresh_retry_count: count + 1,
  last_refresh_result: 'failed'
}

Refresh failure (invalid_grant) → {
  refresh_token_expired: true,  // Circuit breaker
  last_refresh_result: 'failed'
}
```
