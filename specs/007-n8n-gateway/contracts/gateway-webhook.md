# Contract: Gateway Webhook API

**Feature**: 007-n8n-gateway | **Date**: 2026-03-17

## Endpoint

```
POST http://localhost:5678/webhook/gateway
Authorization: Bearer <token>
Content-Type: application/json
```

## Request

```json
{
  "intent": "hello",
  "payload": {}
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| intent | string | yes | Must match a configured route |
| payload | object | no | Passed to the sub-workflow as-is |

## Responses

### 200 OK (intent routed successfully)

```json
{
  "status": "ok",
  "intent": "hello",
  "result": { ... }
}
```

### 400 Bad Request (unknown or missing intent)

```json
{
  "status": "error",
  "error": "Unknown intent: foo",
  "valid_intents": ["hello"]
}
```

### 401 Unauthorized (missing or invalid token)

No body. n8n returns 401 natively before workflow execution.

### 404/405 (wrong method or path)

n8n returns 404 for unregistered webhook paths, 404 for GET on
a POST-only webhook.

## Test Commands

```bash
# Healthy gateway
curl -s -X POST http://localhost:5678/webhook/gateway \
  -H "Authorization: Bearer $GATEWAY_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"intent": "hello", "payload": {"test": true}}'

# Missing auth (expect 401)
curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://localhost:5678/webhook/gateway \
  -H "Content-Type: application/json" \
  -d '{"intent": "hello"}'

# Unknown intent (expect 400)
curl -s -X POST http://localhost:5678/webhook/gateway \
  -H "Authorization: Bearer $GATEWAY_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"intent": "nonexistent"}'

# Missing intent field (expect 400)
curl -s -X POST http://localhost:5678/webhook/gateway \
  -H "Authorization: Bearer $GATEWAY_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"payload": {"test": true}}'
```

## Adding a New Intent

1. Open the Gateway workflow in n8n editor
2. Add a rule to the Switch node: `{{ $json.body.intent }}` equals `"your_intent"`
3. Connect the new output to a sub-workflow or Execute Workflow node
4. Add a Respond to Webhook node at the end of the new branch
5. Export the updated workflow JSON and commit to `n8n/workflows/gateway.json`
