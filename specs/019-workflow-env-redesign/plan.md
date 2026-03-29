# Implementation Plan: Workflow Environment Variable Redesign

**Branch**: `019-workflow-env-redesign` | **Date**: 2026-03-28 | **Spec**: [spec.md](spec.md)

## Summary

Eliminate all `$env` usage across 5 n8n workflows by migrating to n8n credentials (Header Auth) and workflow Static Data. This allows `N8N_BLOCK_ENV_ACCESS_IN_NODE=true` to remain deployed while all workflows function correctly.

## Technical Context

**Language/Version**: n8n workflow JSON, Bash 5.x for operational scripts
**Primary Dependencies**: n8n v2.13.0 credentials store, workflow Static Data API
**Target Platform**: macOS (Apple Silicon Mac Mini)

## Redesign Strategy

### Pattern A: HTTP Request Authorization Headers (3 workflows)
**Current**: `"value": "Bearer {{ $env.OPENCLAW_HOOK_TOKEN }}"`
**New**: Remove manual Authorization header. Configure HTTP Request node with Header Auth credential.

Affected nodes:
- token-check → Alert OpenClaw (HTTP Request)
- error-handler → HTTP Request
- rate-limit-tracker → HTTP Request

**Implementation**: For each HTTP Request node:
1. Remove the manual `Authorization` header parameter
2. Add `"credentials": { "httpHeaderAuth": { "id": "<cred-id>", "name": "OpenClaw Hook Token" } }`
3. Set `"authentication": "genericCredentialType"` and `"genericAuthType": "httpHeaderAuth"`

### Pattern B: Code Node API Key (2 workflows)
**Current**: `const apiKey = $env.N8N_API_KEY;`
**New**: Read from workflow Static Data: `const staticData = $getWorkflowStaticData('global'); const apiKey = staticData.n8nApiKey;`

Affected nodes:
- rate-limit-tracker → Query Executions (Code)
- activity-query → Query Activity (Code)

**Implementation**: In each Code node's jsCode:
1. Replace `$env.N8N_API_KEY` with `$getWorkflowStaticData('global').n8nApiKey`
2. Keep the existing null check (it already handles missing key)

### Pattern C: HMAC Sub-Workflow Secret (1 workflow + 1 sub-workflow)
**Current**: hmac-verify Code node reads `$env.OPENCLAW_WEBHOOK_SECRET`
**New**: Calling workflow passes secret from Static Data via workflowInputs

Affected nodes:
- token-check → HMAC Verify (Execute Workflow node) — pass secret
- hmac-verify → Verify HMAC (Code node) — read from input

**Implementation**:
1. In token-check: Add Code node before Execute Workflow that reads `webhookSecret` from Static Data and adds it to the data flow
2. In token-check: Update Execute Workflow node's workflowInputs to include `"secret": "={{ $json.webhookSecret }}"`
3. In hmac-verify: Change Code node to read `$input.all()[0].json.secret` instead of `$env.OPENCLAW_WEBHOOK_SECRET`
4. Add guard: if secret is empty, return descriptive error `"HMAC secret not configured in workflow Static Data"`

## Operational Requirements (Post-Deployment)

After workflow import, the operator must set:
1. Header Auth credential "OpenClaw Hook Token" in n8n UI (Settings → Credentials)
2. Static Data in token-check workflow: `webhookSecret` = OPENCLAW_WEBHOOK_SECRET value
3. Static Data in rate-limit-tracker workflow: `n8nApiKey` = n8n API key value
4. Static Data in activity-query workflow: `n8nApiKey` = n8n API key value

## Constitution Check

| Gate | Status | Notes |
|------|--------|-------|
| II. Threat-Model Driven | PASS | Eliminates credential exposure via env vars |
| VI. Bash Scripts Are Infrastructure | PASS | Workflow JSON edits, operational scripts |
| X. CLI-First Infrastructure | PASS | Credentials created via n8n UI (business logic per Constitution X) |

## Files Modified

```text
workflows/
├── hmac-verify.json           # Pattern C: read secret from input
├── token-check.json           # Pattern A + C: Header Auth + pass secret
├── error-handler.json         # Pattern A: Header Auth
├── rate-limit-tracker.json    # Pattern A + B: Header Auth + Static Data
└── activity-query.json        # Pattern B: Static Data

docs/
├── ASI-MAPPING.md             # Correct F3 to reflect full remediation
└── TRUST-BOUNDARY-MODEL.md    # Correct F3 to reflect full remediation
```

## Adversarial Review #2

No drift between spec and plan. The three patterns (A, B, C) cleanly map to the $env usage types. Each pattern is independently testable.

**Gate: 0 CRITICAL, 0 HIGH remaining.**
