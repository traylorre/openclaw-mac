---
name: token-status
description: Check LinkedIn OAuth token health
requires:
  env:
    - N8N_WEBHOOK_SECRET
  bins:
    - curl
    - jq
    - openssl
---

# Token Status

When the operator asks "check token status", "how's the token?", or
similar, use this skill.

## Check Token Health

```bash
WEBHOOK_URL="http://localhost:5678/webhook/token-check"
TIMESTAMP=$(date +%s)
BODY='{"action":"check_token"}'

SIGNATURE="sha256=$(echo -n "$BODY" | openssl dgst -sha256 -hmac "$N8N_WEBHOOK_SECRET" | awk '{print $2}')"

RESPONSE=$(curl -s -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -H "X-Signature: $SIGNATURE" \
  -H "X-Timestamp: $TIMESTAMP" \
  -d "$BODY")
```

## Present Results

```text
LinkedIn Integration Status:

OAuth Token: [valid/expiring_soon/expired]
  Days remaining: [N]
  Granted: [date]
  Expires: [date]

[If expiring_soon]: Token expires in [N] days. Please re-authorize soon.
[If expired]: Token has expired. Please re-authorize to resume posting.
```
