# Quickstart: Fledge Milestone 1 — Gateway Live

**Feature**: 007-n8n-gateway | **Date**: 2026-03-17

## Prerequisites

- Colima running: `colima status`
- Docker CLI available: `docker version`
- Port 5678 free: `lsof -i :5678` should return nothing

## Step 1: Pin n8n version and create .env

Update `scripts/templates/docker-compose.yml`:
change `image: n8nio/n8n:latest` to `image: n8nio/n8n:2.13.0`.

Create `.env` from template:

```bash
cp scripts/templates/.env.example scripts/templates/.env
# Generate a random Bearer token
openssl rand -hex 32 >> scripts/templates/.env
# Edit .env to set GATEWAY_BEARER_TOKEN to the generated value
```

## Step 2: Start n8n

```bash
cd scripts/templates
mkdir -p secrets && chmod 700 secrets
openssl rand -hex 32 > secrets/n8n_encryption_key.txt
chmod 600 secrets/n8n_encryption_key.txt
docker compose up -d
```

Verify:

```bash
docker compose ps    # should show n8n running, healthy
curl -s http://localhost:5678/healthz  # should return OK or redirect
```

## Step 3: Import workflows

```bash
# From repo root
docker compose -f scripts/templates/docker-compose.yml exec n8n \
  n8n import:workflow --input=/home/node/.n8n/workflows/gateway.json

docker compose -f scripts/templates/docker-compose.yml exec n8n \
  n8n import:workflow --input=/home/node/.n8n/workflows/hello-world.json
```

Or open http://localhost:5678 in browser and import via UI
(Settings → Import from File).

After import, activate both workflows in the n8n editor.

## Step 4: Configure Bearer auth credential

In n8n UI:
1. Go to Settings → Credentials → Add Credential
2. Type: Header Auth
3. Name: `gateway-bearer-token`
4. Header Name: `Authorization`
5. Header Value: `Bearer <paste token from .env>`
6. Save

Then edit the Gateway workflow's Webhook node:
- Authentication: Header Auth
- Credential: select `gateway-bearer-token`

## Step 5: Test

```bash
export GATEWAY_TOKEN="<your token from .env>"

# Hello world (expect 200 with JSON)
curl -s -X POST http://localhost:5678/webhook/gateway \
  -H "Authorization: Bearer $GATEWAY_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"intent": "hello", "payload": {"test": true}}'

# No auth (expect 401)
curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://localhost:5678/webhook/gateway \
  -H "Content-Type: application/json" \
  -d '{"intent": "hello"}'

# Unknown intent (expect 400 with valid_intents)
curl -s -X POST http://localhost:5678/webhook/gateway \
  -H "Authorization: Bearer $GATEWAY_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"intent": "nonexistent"}'
```

## Step 6: Verify hardening audit

```bash
sudo bash scripts/hardening-audit.sh --json | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(f'PASS:{d[\"summary\"][\"pass\"]} FAIL:{d[\"summary\"][\"fail\"]}')"
```

Compare FAIL count to pre-n8n baseline. Should be zero new FAILs.

## Key Gotchas

1. **Webhook node Response Mode**: Must be set to "Using 'Respond to
   Webhook' Node", not "Immediately". Otherwise custom responses
   never reach the caller.
2. **Workflow must be active**: Inactive workflows don't register
   webhook endpoints. Toggle the workflow to "Active" after import.
3. **Read-only filesystem**: The Docker Compose uses `read_only: true`.
   n8n writes to the mounted volume (`/home/node/.n8n`) and tmpfs
   only. If n8n fails to start, check volume permissions.
4. **Credential not in workflow JSON**: The Header Auth credential
   is stored in n8n's encrypted database, not in the exported JSON.
   After importing workflows on a new machine, you must recreate
   the credential manually (Step 4).
