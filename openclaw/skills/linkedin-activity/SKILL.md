---
name: linkedin-activity
description: Query past LinkedIn activity and present formatted summaries
requires:
  env:
    - N8N_WEBHOOK_SECRET
  bins:
    - curl
    - jq
    - openssl
---

# LinkedIn Activity

When the operator asks about past activity ("What did we post this week?",
"How active were we today?", "Show last 5 posts"), use this skill.

## Query Activity

Parse the operator's request to determine:

- `date_from` and `date_to` (e.g., "this week" = Monday to today)
- `action_types` filter (e.g., "posts" = ["post"], "everything" = all types)

```bash
WEBHOOK_URL="http://localhost:5678/webhook/activity-query"
TIMESTAMP=$(date +%s)
BODY='{"action":"query_activity","date_from":"'"$DATE_FROM"'","date_to":"'"$DATE_TO"'","action_types":'"$TYPES"'}'

SIGNATURE="sha256=$(echo -n "$BODY" | openssl dgst -sha256 -hmac "$N8N_WEBHOOK_SECRET" | awk '{print $2}')"

RESPONSE=$(curl -s -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -H "X-Signature: $SIGNATURE" \
  -H "X-Timestamp: $TIMESTAMP" \
  -d "$BODY")
```

## Present Results

Format the response as a readable summary:

```text
Activity for [date range]:

Summary: [posts] posts, [comments] comments, [likes] likes

Recent activity:
- [date] Posted: [topic] → [linkedin_url]
- [date] Commented on [author]'s post about [topic]
- [date] Liked [author]'s post about [topic]
```

If no activity found: "No activity recorded for that period."
