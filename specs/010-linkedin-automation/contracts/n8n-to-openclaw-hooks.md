# Contract: n8n → OpenClaw Inbound Hooks

**Date**: 2026-03-21
**Direction**: n8n workflow (caller) → OpenClaw agent (receiver)
**Authentication**: Bearer token in `Authorization` header
**Endpoint**: `http://127.0.0.1:18789/hooks/agent`

## Authentication

```
POST /hooks/agent
Authorization: Bearer <openclaw-hook-token>
Content-Type: application/json

{...payload...}
```

The hook token is configured in OpenClaw's `openclaw.json`:
```json
{
  "hooks": {
    "enabled": true,
    "token": "<shared-token>",
    "path": "/hooks"
  }
}
```

---

## Hook: Token Expiry Alert

**Purpose**: Alert operator via chat about LinkedIn OAuth token lifecycle events

**Trigger**: Daily scheduled workflow detects token expiry conditions or refresh failure

**Alert Types**:

### `token_expiring` — Access token approaching expiry (automated refresh unavailable)

Sent when the access token has ≤7 days remaining and automated refresh cannot be performed (e.g., refresh token expired or circuit breaker engaged).

```json
{
  "type": "alert",
  "alert_type": "token_expiring",
  "message": "LinkedIn access token expires in 5 days (2026-04-02). Automated refresh unavailable — manual re-authorization required.",
  "severity": "warning",
  "access_token_days_remaining": 5,
  "refresh_token_days_remaining": 280,
  "access_token_expiry_date": "2026-04-02"
}
```

### `refresh_token_expiring` — Refresh token approaching expiry (30-day warning)

Sent when the refresh token has ≤30 days remaining. The operator should plan re-authorization before the refresh token expires, as this would require a full manual OAuth flow.

```json
{
  "type": "alert",
  "alert_type": "refresh_token_expiring",
  "message": "LinkedIn refresh token expires in 25 days (2026-05-15). Plan re-authorization.",
  "severity": "warning",
  "access_token_days_remaining": 45,
  "refresh_token_days_remaining": 25,
  "access_token_expiry_date": "2026-04-25"
}
```

### `refresh_token_expired` — Refresh token has expired

Sent when the refresh token TTL has elapsed. Automated refresh is no longer possible. The operator must complete a full manual OAuth re-authorization.

```json
{
  "type": "alert",
  "alert_type": "refresh_token_expired",
  "message": "LinkedIn refresh token has expired. Manual re-authorization required.",
  "severity": "critical",
  "access_token_days_remaining": 0,
  "refresh_token_days_remaining": 0,
  "access_token_expiry_date": "2026-03-20"
}
```

### `token_refresh_failed` — Automated refresh attempt failed

Sent when the automated access token refresh fails after retries. Includes the error classification to guide operator action.

```json
{
  "type": "alert",
  "alert_type": "token_refresh_failed",
  "message": "LinkedIn token refresh failed: refresh token revoked or expired. Manual re-authorization required.",
  "severity": "critical",
  "access_token_days_remaining": 3,
  "refresh_token_days_remaining": 200,
  "access_token_expiry_date": "2026-04-02"
}
```

**Error classifications**:
- `invalid_grant` — Refresh token revoked or expired. No retry. Alert immediately.
- `invalid_client` — Client credentials incorrect. No retry. Alert to verify credentials in n8n.
- HTTP 5xx — LinkedIn server error. Retry up to 3 times across scheduled runs before alerting.
- Network/unknown — Retry once on next scheduled run, then alert.

**Expected behavior**: OpenClaw delivers the message to the operator via the configured chat channel.

> **Note (T042)**: The original `token_expiry` alert type has been standardized to `token_expiring` for consistency. Consumers should handle `token_expiring` (not `token_expiry`).

---

## Hook: Workflow Failure Alert

**Purpose**: Alert operator via chat when an n8n workflow fails

**Trigger**: n8n Error Workflow fires on any LinkedIn-related workflow failure

**Payload**:
```json
{
  "type": "alert",
  "alert_type": "workflow_failure",
  "message": "LinkedIn post workflow failed: API returned 403 Forbidden",
  "severity": "error",
  "workflow_name": "linkedin-post",
  "execution_id": "12345",
  "error_code": "api_error",
  "error_details": "403 Forbidden — possible account restriction",
  "affected_content": "Draft about autonomous racing sensor technology"
}
```

---

## Hook: Rate Limit Warning

**Purpose**: Alert operator when daily API usage approaches the limit

**Trigger**: Counter workflow detects ≥80% of daily 150-request limit

**Payload**:
```json
{
  "type": "alert",
  "alert_type": "rate_limit",
  "message": "LinkedIn API usage at 85% (127/150 requests today). Consider reducing activity.",
  "severity": "warning",
  "requests_used": 127,
  "requests_limit": 150,
  "percentage": 85
}
```

---

## Future

The following hooks are deferred to a future milestone.

### Hook: Browser Session Expiry Alert

**Purpose**: Alert operator via chat that LinkedIn browser session is expired

**Trigger**: Daily session health check or pre-discovery health check detects invalid session

**Payload**:
```json
{
  "type": "alert",
  "alert_type": "browser_session_expired",
  "message": "LinkedIn browser session has expired. Feed discovery is paused. Please re-login manually to restore the session.",
  "severity": "warning",
  "last_valid": "2026-03-18T14:30:00Z"
}
```

**Expected behavior**: OpenClaw delivers the message to the operator. Feed discovery is paused until the operator completes a manual re-login and the storageState is updated.

---

### Hook: Feed Discovery Results

**Purpose**: Deliver discovered feed posts to the operator for engagement decisions

**Trigger**: Feed discovery workflow completes with results

**Payload**:
```json
{
  "type": "discovery_results",
  "message": "Found 6 relevant posts in your feed",
  "posts": [
    {
      "urn": "urn:li:activity:123456789",
      "author_name": "Jane Smith",
      "content_snippet": "Exciting developments in autonomous racing...",
      "post_url": "https://www.linkedin.com/feed/update/...",
      "suggested_comment": "Great analysis! The sensor fusion approach..."
    }
  ]
}
```

**Expected behavior**: OpenClaw presents each post to the operator with the suggested comment, awaiting approval/edit/skip for each.
