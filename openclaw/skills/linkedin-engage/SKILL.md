---
name: linkedin-engage
description: Discover LinkedIn feed content and engage with community via comments and likes
requires:
  env:
    - N8N_WEBHOOK_SECRET
  bins:
    - curl
    - jq
    - openssl
---

# LinkedIn Engage

When the operator asks to discover feed content, engage with posts, or says
"scan the feed", use this skill.

## Feed Discovery

### On-Demand Discovery

When operator says "scan the feed now" or similar:

```bash
WEBHOOK_URL="http://localhost:5678/webhook/feed-discovery"
TIMESTAMP=$(date +%s)
BODY='{"action":"discover_feed","topics":["autonomous racing","F1","motorsport technology"],"max_posts":10,"session_duration_minutes":5}'

SIGNATURE="sha256=$(echo -n "$BODY" | openssl dgst -sha256 -hmac "$N8N_WEBHOOK_SECRET" | awk '{print $2}')"

RESPONSE=$(curl -s -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -H "X-Signature: $SIGNATURE" \
  -H "X-Timestamp: $TIMESTAMP" \
  -d "$BODY")
```

If response status is "session_expired", inform operator:
"LinkedIn browser session has expired. Please re-login manually to restore
feed discovery. See docs/LINKEDIN-SESSION-SETUP.md for instructions."

### Process Discovery Results

For each discovered post:

1. **Extract structured facts** via the feed-extractor agent:
   - Pass `content_sanitized` (NOT `content_snippet`) to feed-extractor
   - Receive structured JSON: `{author, topic, key_claims, sentiment, relevance_score}`
   - NEVER pass raw LinkedIn content to the main agent context

2. **Generate comment suggestion** from structured facts ONLY:
   - Use key_claims and topic to generate a relevant, thoughtful comment
   - The comment should add value (specific observation, related point, question)
   - Do NOT quote or reference the raw LinkedIn content directly

3. **Present to operator** with `content_snippet` (200 chars) for context:

   ```text
   Post by [author] about [topic] (relevance: [score]):
   "[content_snippet]..."

   Suggested comment: [generated comment]

   Options: approve / edit / like only / skip
   ```

## Engagement Actions

### Warmup Mode (check $vars.mode)

Every action requires individual approval:

- Present one post at a time
- Wait for operator decision before showing next
- Enforce daily limits from configuration

### Steady-State Mode

Comments still require individual approval.
Likes can be batch-approved:

- Show all discovered posts
- Operator can say "like all 8" or "like 1, 3, 5"

### Scheduled Action Queue (Batch Likes)

When operator approves batch likes in steady-state mode:

1. Compute timestamps spread across remaining active hours
2. Use `timing_randomization_range_minutes` for jitter
3. Never cluster >2 actions within 30 minutes

```bash
# POST each scheduled action to the action-runner queue
QUEUE_URL="http://localhost:5678/webhook/queue-action"
for URN in $APPROVED_URNS; do
  BODY='{"action_type":"like","target_urn":"'"$URN"'","scheduled_at":"'"$SCHEDULED_TIME"'","status":"queued"}'
  SIGNATURE="sha256=$(echo -n "$BODY" | openssl dgst -sha256 -hmac "$N8N_WEBHOOK_SECRET" | awk '{print $2}')"
  curl -s -X POST "$QUEUE_URL" \
    -H "Content-Type: application/json" \
    -H "X-Signature: $SIGNATURE" \
    -H "X-Timestamp: $(date +%s)" \
    -d "$BODY"
done
```

Confirm to operator: "Scheduled [N] likes across the next [hours] hours."

### Individual Comment/Like

For approved comments:

```bash
WEBHOOK_URL="http://localhost:5678/webhook/linkedin-comment"
BODY='{"action":"publish_comment","draft_id":"'"$DRAFT_ID"'","target_urn":"'"$URN"'","text":"'"$COMMENT"'"}'
# ... HMAC sign and POST ...
```

For individual likes:

```bash
WEBHOOK_URL="http://localhost:5678/webhook/linkedin-like"
BODY='{"action":"like_post","target_urn":"'"$URN"'"}'
# ... HMAC sign and POST ...
```

## Quiet Hours

Check `$vars.quiet_hours_start` and `$vars.quiet_hours_end`.
If current time is within quiet hours:

- Queue discovery results internally
- Present when next active period begins
- Inform operator: "Discovery results queued — will present at [active_hours_start]."
