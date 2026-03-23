---
name: config-update
description: Update operating configuration via HMAC-signed webhook to n8n
requires:
  env:
    - N8N_WEBHOOK_SECRET
  bins:
    - curl
    - jq
    - openssl
---

# Config Update

When the operator wants to change system configuration, use this skill.

## Supported Configuration Changes

- `mode`: "warmup" or "steady_state"
- `quiet_hours_start` / `quiet_hours_end`: hour (0-23)
- `active_hours_start` / `active_hours_end`: hour (0-23)
- `daily_post_limit` / `daily_comment_limit` / `daily_like_limit`: integer
- `topics`: comma-separated list of topic keywords
- `timing_randomization_range_minutes`: min-max (e.g., "15-60")

## Parse Operator Commands

Examples:

- "Switch to steady-state mode" → `{"mode": "steady_state"}`
- "Set quiet hours to 10pm-7am" → `{"quiet_hours_start": 22, "quiet_hours_end": 7}`
- "Change daily like limit to 15" → `{"daily_like_limit": 15}`

## Update via Webhook

```bash
WEBHOOK_URL="http://localhost:5678/webhook/config-update"
TIMESTAMP=$(date +%s)
BODY='{"action":"update_config","variables":'"$VARIABLES_JSON"'}'

SIGNATURE="sha256=$(echo -n "$BODY" | openssl dgst -sha256 -hmac "$N8N_WEBHOOK_SECRET" | awk '{print $2}')"

RESPONSE=$(curl -s -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -H "X-Signature: $SIGNATURE" \
  -H "X-Timestamp: $TIMESTAMP" \
  -d "$BODY")
```

## Confirm Changes

"Updated configuration: [list of changed variables and new values]."

Note: Configuration is stored in n8n Custom Variables. The n8n API key
stays inside n8n — this skill calls the config-update webhook, not the
n8n REST API directly.
