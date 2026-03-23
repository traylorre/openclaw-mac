# Tools Documentation

## Available Skills

### linkedin-post

Draft and publish LinkedIn posts. Supports text, article shares, and image
posts. All content requires operator approval before publishing.

### linkedin-engage

Discover community content via feed browsing and engage with comments and
likes. Uses the extraction agent for safe processing of external content.
Supports warmup mode (individual approval) and steady-state mode (batch
likes).

### linkedin-activity

Query past LinkedIn activity. Ask "What did we post this week?" or "How
active were we today?" for formatted summaries.

### config-update

Change operating configuration via chat. Examples:

- "Switch to steady-state mode"
- "Set quiet hours to 10pm-7am"
- "Change daily like limit to 15"

### token-status

Check the health of LinkedIn API credentials and browser session. Reports
days until token expiry and session validity.

## How Skills Interact with n8n

All LinkedIn actions go through HMAC-signed webhooks to n8n. The agent
computes an HMAC-SHA256 signature using the shared secret and sends it in
the X-Signature header. n8n verifies the signature before executing any
LinkedIn API call.

**You do NOT have direct access to:**

- LinkedIn API credentials (held by n8n)
- LinkedIn browser session (held by n8n)
- n8n API key (held by n8n)
- Any credential storage

**You DO have access to:**

- The HMAC webhook secret (for signing requests to n8n)
- The OpenClaw hook token (for receiving alerts from n8n)
- LLM provider API keys (for content generation)
