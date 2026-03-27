# Hardening Observations: M3 LinkedIn Automation

Activities observed under the hardened macOS deployment. This document is
maintained throughout M3 and feeds into the M5 practitioner report.

**Last updated**: (update as observations accumulate)

## Works Normally Under Hardening

| Activity | Method | Notes |
|----------|--------|-------|
| LinkedIn API posting | n8n HTTP Request node + OAuth2 | No hardening interference. Standard HTTPS outbound. |
| Telegram polling | OpenClaw native (grammY runner) | Long-polling is outbound-only. No inbound ports needed. |
| LLM API calls | OpenClaw native (HTTPS) | Gemini, Anthropic, Ollama all work normally. |
| n8n workflow execution | Docker container | Container caps (CAP_DROP ALL) do not affect workflow execution. |
| HMAC webhook signing | OpenClaw curl + openssl | Standard tools, no hardening impact. |

## Requires Workarounds

| Activity | Issue | Workaround | Notes |
|----------|-------|------------|-------|
| n8n Code node env access | `N8N_BLOCK_ENV_ACCESS_IN_NODE=true` blocks HMAC Code node from reading webhook secret | Changed to `false` for M3. HMAC verification requires env access. | Trade-off documented in docker-compose.yml. Mitigated by localhost-only binding + workflow version control. |
| n8n Public API | Originally disabled (`N8N_PUBLIC_API_DISABLED=true`) | Enabled for M3 — required for activity-query and rate-limit-tracker | Risk: API key must be protected. Mitigated by localhost-only binding + API key in n8n env only. |

## Not Possible Under Hardening

| Activity | Reason | Impact |
|----------|--------|--------|
| (none observed yet) | | |

## Security Trade-Offs Made for M3

| Change | Original Setting | M3 Setting | Justification |
|--------|-----------------|------------|---------------|
| Code node env access | Blocked | Allowed | HMAC verification Code node reads OPENCLAW_WEBHOOK_SECRET from env (FR-007). Mitigated: localhost-only, workflow version control. |
| n8n Public API | Disabled | Enabled | Required for execution history queries (FR-017, FR-016) |
| Execution data save | Success: none | Success: all | Required for activity log (FR-017). 120-day retention. |

## OWASP ASI Observations

| OWASP ASI Item | Observed? | Details |
|----------------|-----------|---------|
| ASI01: Prompt Injection | Mitigated | Human approval gate prevents unapproved content from being published. |
| ASI09: Human-Agent Trust Exploitation | Addressed (M2) | Self-attestation limitation documented in TRUST-GAPS.md. |
| ASI10: Tool/Skill Misuse | Mitigated | LinkedIn credentials isolated in n8n. Malicious skills cannot access them. 341 ClawHub skills context. |

## Notes for M5 Practitioner Report

- The n8n `N8N_BLOCK_ENV_ACCESS_IN_NODE` setting creates a tension with
  the HMAC verification pattern (Code nodes need the webhook secret).
  This is a real-world example of hardening controls conflicting with
  security architecture requirements.
- Enabling the n8n API for internal use (execution history queries) is a
  calculated trade-off. The API key stays inside Docker, and n8n is
  localhost-only. The risk is low but non-zero.
- The credential isolation architecture (agent never holds LinkedIn
  tokens) is verifiable via audit script — CHK-OPENCLAW-CREDS confirms
  no credentials leak into the agent environment.
