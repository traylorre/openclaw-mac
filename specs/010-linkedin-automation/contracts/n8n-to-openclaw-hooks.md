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

**Purpose**: Alert operator via chat that LinkedIn OAuth token is expiring

**Trigger**: Daily scheduled workflow detects ≤7 days remaining

**Payload**:
```json
{
  "type": "alert",
  "alert_type": "token_expiry",
  "message": "LinkedIn OAuth token expires in 5 days (2026-04-02). Please re-authorize: [instructions URL]",
  "severity": "warning",
  "days_remaining": 5,
  "expiry_date": "2026-04-02"
}
```

**Expected behavior**: OpenClaw delivers the message to the operator via the configured chat channel.

---

## Hook: Browser Session Expiry Alert

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

## Hook: Feed Discovery Results

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
