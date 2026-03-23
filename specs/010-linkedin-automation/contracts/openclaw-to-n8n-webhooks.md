# Contract: OpenClaw → n8n Webhooks

**Date**: 2026-03-21
**Direction**: OpenClaw agent (caller) → n8n workflow (receiver)
**Authentication**: HMAC-SHA256 signature in `X-Signature` header

## Authentication Protocol

Every request from OpenClaw to n8n includes:

```
POST /webhook/<workflow-path>
Content-Type: application/json
X-Signature: sha256=<hex-encoded HMAC-SHA256(shared_secret, raw_body)>
X-Timestamp: <unix-epoch-seconds>

{...payload...}
```

The n8n Code node (first node after Webhook trigger) verifies:
1. `X-Timestamp` is within 5 minutes of current time (replay protection)
2. `X-Signature` matches `HMAC-SHA256(secret, raw_body)` using `crypto.timingSafeEqual()`
3. Reject with 401 if either check fails

The shared secret is stored in:
- OpenClaw: environment variable `N8N_WEBHOOK_SECRET`
- n8n: environment variable `OPENCLAW_WEBHOOK_SECRET`

**Threat justification** (Constitution Principle II):
1. **Compromised localhost process** (threat: malicious npm/community-node supply chain): A compromised package on the Mac Mini could trigger n8n webhooks. HMAC requires the shared secret — attacker must also breach OpenClaw's environment.
2. **Request integrity** (threat: tampering): Header Auth alone doesn't bind token to body — a captured token allows arbitrary payloads. HMAC binds signature to body, preventing modification of what gets posted to LinkedIn.
3. **SSRF vector** (threat: server-side request forgery): A service with an SSRF vulnerability could make localhost webhook calls. Without HMAC, the request succeeds. With HMAC, it's rejected.
4. **Audit trail** (operational): HMAC signatures in logs prove which requests were legitimately issued by OpenClaw vs. unauthorized attempts.

**What HMAC does NOT protect against**: An attacker with full process-level access to OpenClaw's environment (can read the secret). Platform-level hardening (macOS SIP, process isolation — M2 baseline) is the mitigation for that threat level.

---

## Webhook: Publish Post

**Path**: `/webhook/linkedin-post`
**Purpose**: Publish an approved content draft to LinkedIn

**Request**:
```json
{
  "action": "publish_post",
  "draft_id": "uuid",
  "content_type": "text" | "article" | "image",
  "text": "Post content...",
  "article_url": "https://...",
  "article_title": "Optional title",
  "image_base64": "base64-encoded-image",
  "image_filename": "photo.jpg"
}
```

**Response (success)**:
```json
{
  "status": "published",
  "linkedin_post_urn": "urn:li:share:123456789",
  "linkedin_post_url": "https://www.linkedin.com/feed/update/urn:li:share:123456789"
}
```

**Response (error)**:
```json
{
  "status": "error",
  "error_code": "token_expired" | "rate_limited" | "api_error" | "account_restricted",
  "error_message": "Human-readable description",
  "retry_suggested": true | false
}
```

---

## Webhook: Publish Comment

**Path**: `/webhook/linkedin-comment`
**Purpose**: Post a comment on a LinkedIn post

**Request**:
```json
{
  "action": "publish_comment",
  "draft_id": "uuid",
  "target_urn": "urn:li:activity:123456789",
  "text": "Comment content..."
}
```

**Response**: Same structure as Publish Post, with `linkedin_comment_urn` instead of `linkedin_post_urn`.

---

## Webhook: Like Post

**Path**: `/webhook/linkedin-like`
**Purpose**: Like a LinkedIn post (single action, executed by action-runner)

**Request**:
```json
{
  "action": "like_post",
  "target_urn": "urn:li:activity:123456789"
}
```

**Response**:
```json
{
  "status": "liked",
  "target_urn": "urn:li:activity:123456789"
}
```

**Note on batch likes**: The skill does NOT call this webhook directly for batches. Instead, it schedules each like into the action queue (n8n Workflow Static Data) with a computed `scheduled_at` timestamp spread across the day's active hours. The `action-runner` workflow (every 5 min) processes the queue and calls this webhook for each due action. This prevents burst patterns.

---

## Webhook: Config Update

**Path**: `/webhook/config-update`
**Purpose**: Update n8n Custom Variables from operator chat commands (R-002 fix — n8n API key stays inside n8n)

**Request**:
```json
{
  "action": "update_config",
  "variables": {
    "mode": "steady_state",
    "quiet_hours_start": 22,
    "daily_like_limit": 15
  }
}
```

**Response**:
```json
{
  "status": "updated",
  "variables_changed": ["mode", "quiet_hours_start", "daily_like_limit"]
}
```

**Security note**: This webhook uses n8n's internal API to update Custom Variables. The n8n API key exists only inside the n8n environment — it is never exposed to OpenClaw. The OpenClaw `config-update` skill calls this HMAC-signed webhook, not the n8n REST API directly.

---

## Webhook: Feed Discovery

**Path**: `/webhook/feed-discovery`
**Purpose**: Trigger a Playwright CDP feed browsing session

**Request**:
```json
{
  "action": "discover_feed",
  "topics": ["autonomous racing", "F1", "motorsport technology"],
  "max_posts": 10,
  "session_duration_minutes": 5
}
```

**Response**:
```json
{
  "status": "completed",
  "posts_found": 8,
  "posts": [
    {
      "urn": "urn:li:activity:123456789",
      "author_name": "Jane Smith",
      "author_headline": "VP Engineering at RaceTech",
      "content_snippet": "Exciting developments in autonomous...",
      "post_url": "https://www.linkedin.com/feed/update/...",
      "topics_matched": ["autonomous racing"]
    }
  ]
}
```

---

## Webhook: Query Activity

**Path**: `/webhook/activity-query`
**Purpose**: Query execution history for activity summaries

**Request**:
```json
{
  "action": "query_activity",
  "date_from": "2026-03-14",
  "date_to": "2026-03-21",
  "action_types": ["post", "comment", "like"]
}
```

**Response**:
```json
{
  "status": "completed",
  "summary": {
    "posts": 12,
    "comments": 45,
    "likes": 89,
    "feed_discoveries": 18
  },
  "details": [
    {
      "action_type": "post",
      "timestamp": "2026-03-20T14:30:00Z",
      "summary": "Posted about autonomous racing sensor technology",
      "linkedin_url": "https://www.linkedin.com/feed/update/..."
    }
  ]
}
```

---

## Webhook: Token Health Check

**Path**: `/webhook/token-check`
**Purpose**: Check LinkedIn OAuth token status (also runs on daily schedule)

**Request**:
```json
{
  "action": "check_token"
}
```

**Response**:
```json
{
  "status": "valid" | "expiring_soon" | "expired",
  "days_remaining": 42,
  "grant_date": "2026-02-01",
  "expiry_date": "2026-04-02",
  "alert_needed": false
}
```
