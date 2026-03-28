# Quickstart: Token Workflow Sync

## Prerequisites

- n8n container running: `docker ps | grep openclaw-n8n`
- n8n API key in Keychain: `security find-generic-password -a openclaw -s n8n-api-key -w`

## Sync Workflow

```bash
# 1. Remove duplicate workflow (if exists) — check n8n UI or API first
# 2. Import authoritative workflow from git
make workflow-import

# 3. Verify in n8n UI: token-check workflow should show 11 nodes
# 4. Trigger a manual execution to confirm Static Data initialization
```

## Verify

```bash
# Check workflow is active via API
curl -s -H "X-N8N-API-KEY: $(security find-generic-password -a openclaw -s n8n-api-key -w)" \
  http://localhost:5678/api/v1/workflows | jq '.data[] | select(.name=="token-check") | {name, active, nodes: (.nodes | length)}'
```

## If Static Data Was Lost

After import, if grant timestamps need correction:

1. Open token-check workflow in n8n UI
2. Go to Settings → Static Data
3. Set `access_token_granted_at` and `refresh_token_granted_at` to the actual OAuth grant date (ISO 8601 format)
