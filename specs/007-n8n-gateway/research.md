# Research: Fledge Milestone 1 — Gateway Live

**Feature**: 007-n8n-gateway | **Date**: 2026-03-17

## R1: n8n webhook authentication

**Decision**: Use n8n's built-in Header Auth on the Webhook node.

**Rationale**: The Webhook node has a native Authentication
parameter supporting None, Basic Auth, Header Auth, and JWT Auth.
Header Auth with name=`Authorization` and value=`Bearer <token>`
validates incoming requests before the workflow executes. This is
the recommended approach per n8n docs.

**Alternatives considered**:
- Custom IF node to check header: fragile, bypassable
- JWT Auth: overkill for localhost single-operator
- n8n API auth: would require enabling the public API (disabled
  per hardening config)

**Source**: https://docs.n8n.io/integrations/builtin/credentials/webhook/

## R2: Switch node for intent routing

**Decision**: Use Switch node in Routing Rules mode with string
equality on `{{ $json.body.intent }}` and Fallback Output for
unknown intents.

**Rationale**: Each rule maps to a numbered output. Adding an intent
is one rule + one connection. Fallback Output routes unmatched
intents to an error response node.

**Alternatives considered**:
- Expression mode: harder to read, index arithmetic
- Separate webhooks per intent: breaks single-entry-point, auth
  duplication

**Source**: https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.switch/

## R3: Respond to Webhook node for custom responses

**Decision**: Set Webhook node Response Mode to "Using 'Respond to
Webhook' Node". Place Respond to Webhook nodes at each terminal
point in the workflow to return structured JSON with custom status
codes.

**Rationale**: This allows different responses per route (200 for
success, 400 for unknown intent, etc.). The Respond to Webhook node
supports JSON body, custom status codes, and custom headers.

**Critical gotcha**: If the Webhook node is set to "Immediately",
the Respond to Webhook node never executes.

**Source**: https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.respondtowebhook/

## R4: n8n version pinning

**Decision**: Pin to `n8nio/n8n:2.13.0`.

**Rationale**: n8n 2.0 (Dec 2025) introduced breaking changes:
security defaults changed, task runners enabled, env var access
blocked from Code nodes. Pinning prevents surprise upgrades.

**Update process**: Change tag in docker-compose.yml, run
`docker compose pull n8n && docker compose up -d --no-deps n8n`.

**Source**: https://hub.docker.com/r/n8nio/n8n/tags

## R5: Workflow JSON export/import for git

**Decision**: Export workflows as JSON, commit to `n8n/workflows/`.
Import during initial setup via `n8n import:workflow --input=file.json`
or the n8n UI.

**Rationale**: n8n workflows are fully representable as JSON.
Credential references use names/IDs (not secrets). The JSON format
is the standard mechanism for workflow portability.

**Source**: https://docs.n8n.io/workflows/export-import/

## R6: Existing Docker Compose is already hardened

**Decision**: Modify the existing `scripts/templates/docker-compose.yml`
rather than creating a new one. Only change: pin the image tag from
`:latest` to `:2.13.0`.

**Rationale**: The existing compose file already implements FR-001
(Docker Compose), FR-003 (localhost binding), FR-004 (persistent
volume), FR-011 (non-root, no privileged, no Docker socket), FR-013
(restart unless-stopped). No need to rewrite what's already correct.

## R7: WEBHOOK_URL not needed for localhost

**Decision**: Do not set the `WEBHOOK_URL` environment variable.

**Rationale**: n8n defaults to `http://localhost:5678` when
`WEBHOOK_URL` is not set. Since all callers are on the same machine
(localhost), this default is correct. Setting it would only be
needed for external webhook ingress (out of scope).

**Source**: https://docs.n8n.io/hosting/configuration/environment-variables/endpoints/
