# Data Model: Fledge Milestone 1 — Gateway Live

**Feature**: 007-n8n-gateway | **Date**: 2026-03-17

## Entities

### Gateway Request

The JSON payload sent to the gateway webhook by any caller.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| intent | string | yes | Route identifier (e.g., `hello`, `lead_gen`) |
| payload | object | no | Arbitrary data passed to the sub-workflow |

Example:

```json
{
  "intent": "hello",
  "payload": { "message": "testing gateway" }
}
```

### Gateway Response

The JSON response returned by the gateway to the caller.

| Field | Type | Description |
|-------|------|-------------|
| status | string | `ok`, `error` |
| intent | string | The intent that was routed (echoed back) |
| result | object | Sub-workflow output (varies by intent) |
| error | string | Error message (only when status is `error`) |
| valid_intents | array | List of valid intents (only on 400 errors) |

Success example (200):

```json
{
  "status": "ok",
  "intent": "hello",
  "result": { "message": "Hello from n8n gateway", "received": { "message": "testing gateway" } }
}
```

Error example (400 unknown intent):

```json
{
  "status": "error",
  "error": "Unknown intent: foo",
  "valid_intents": ["hello"]
}
```

Error example (400 missing intent):

```json
{
  "status": "error",
  "error": "Missing required field: intent",
  "valid_intents": ["hello"]
}
```

### n8n Header Auth Credential

Stored in n8n's encrypted credential store (not in workflow JSON).

| Field | Value |
|-------|-------|
| Name | `gateway-bearer-token` |
| Type | Header Auth (`httpHeaderAuth`) |
| Header Name | `Authorization` |
| Header Value | `Bearer <token from .env>` |

### n8n Workflows

Two workflows committed as JSON:

| Workflow | File | Webhook Path | Purpose |
|----------|------|-------------|---------|
| Gateway | `n8n/workflows/gateway.json` | `/webhook/gateway` | Auth + intent routing |
| Hello World | `n8n/workflows/hello-world.json` | (triggered by gateway) | Echo response for testing |

## Relationships

```text
Caller (curl / OpenClaw / script)
  │
  POST /webhook/gateway
  Authorization: Bearer <token>
  {"intent": "hello", "payload": {...}}
  │
  ▼
Gateway Workflow
  ├── Webhook Node (Header Auth validates Bearer token)
  ├── Switch Node (routes by intent field)
  │     ├── "hello" → Hello World sub-workflow → Respond 200
  │     ├── "lead_gen" → (future milestone 2)
  │     └── fallback → Respond 400 with valid_intents
  └── Respond to Webhook Node (returns JSON to caller)
```

## Validation Rules

- `intent` field must be a non-empty string
- `intent` must match a configured route in the Switch node
- Authorization header must match the stored credential exactly
- Request method must be POST (Webhook node configured POST-only)
