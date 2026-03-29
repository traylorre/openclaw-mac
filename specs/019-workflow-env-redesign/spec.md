# Feature Specification: Workflow Environment Variable Redesign

**Feature Branch**: `019-workflow-env-redesign`
**Created**: 2026-03-28
**Status**: Draft
**Input**: Eliminate all `$env` usage in n8n workflows so `N8N_BLOCK_ENV_ACCESS_IN_NODE=true` can remain deployed without breaking webhook authentication or alert delivery. Correct the F3 (016) documentation that incorrectly claims the env access gap is "closed."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - HMAC Webhook Authentication Works with =true (Priority: P1)

As the platform operator, I need webhook HMAC authentication to function correctly with `N8N_BLOCK_ENV_ACCESS_IN_NODE=true`, so that webhook endpoints are protected against unauthorized callers while Code nodes cannot access arbitrary environment variables.

**Why this priority**: HMAC authentication is the identity and integrity layer for all webhook-triggered workflows. With the current `$env` pattern, setting `=true` silently breaks all webhook auth — every request is rejected because the HMAC secret reads as `undefined`.

**Independent Test**: Send a properly HMAC-signed request to the token-check webhook endpoint. It should return a valid response (not a silent rejection or error).

**Acceptance Scenarios**:

1. **Given** `N8N_BLOCK_ENV_ACCESS_IN_NODE=true` and the HMAC secret is stored in workflow Static Data, **When** a properly signed webhook request is sent, **Then** the HMAC verification passes and the request is processed.
2. **Given** `N8N_BLOCK_ENV_ACCESS_IN_NODE=true`, **When** an unsigned or incorrectly signed webhook request is sent, **Then** the HMAC verification fails and a 401 response is returned.
3. **Given** the HMAC secret is not yet set in Static Data, **When** the workflow executes, **Then** a clear error is returned indicating the secret needs to be configured.

---

### User Story 2 - Alert Delivery Works with =true (Priority: P1)

As the platform operator, I need alert delivery (token-check, error-handler, rate-limit-tracker) to successfully authenticate against the OpenClaw hooks endpoint, so that security alerts reach the agent when tokens are expiring or errors occur.

**Why this priority**: With `{{ $env.OPENCLAW_HOOK_TOKEN }}` resolving to `undefined`, all alerts silently fail to authenticate. Token expiry warnings never reach the operator.

**Independent Test**: Trigger the token-check workflow via schedule. If an alert condition exists, verify the alert HTTP request includes a valid Authorization header (not "Bearer undefined").

**Acceptance Scenarios**:

1. **Given** `N8N_BLOCK_ENV_ACCESS_IN_NODE=true` and a Header Auth credential exists for OpenClaw hooks, **When** an alert is triggered, **Then** the HTTP Request node sends `Authorization: Bearer <actual-token>` (not `Bearer undefined`).
2. **Given** the n8n API key is needed in Code nodes (activity-query, rate-limit-tracker), **When** the workflow executes, **Then** the API key is read from Static Data, not `$env`.

---

### User Story 3 - Correct F3 Documentation (Priority: P1)

As a security auditor, I need the ASI-MAPPING and TRUST-BOUNDARY-MODEL documentation to accurately reflect the current state — that `=true` is deployed AND the workflows have been redesigned to not use `$env`, so that the risk assessment is truthful.

**Why this priority**: The current F3 commit (35977ad) claims the env access gap is "closed" but this is only true AFTER the workflow redesign is complete. The docs must reflect reality.

**Independent Test**: The documentation should state that `=true` is deployed, workflows use credentials/Static Data instead of `$env`, and the trade-off is fully resolved.

**Acceptance Scenarios**:

1. **Given** the workflow redesign is complete, **When** the docs are reviewed, **Then** ASI-MAPPING accurately reflects that env access is blocked AND webhooks/alerts function correctly.

---

### Edge Cases

- What if the operator forgets to set the HMAC secret in Static Data after deployment? The hmac-verify Code node must check for a missing/empty secret and return a clear error, not silently fail.
- What if Static Data is lost during workflow import? The import process (make workflow-import) overwrites Static Data. The operator must re-set the secret after import. Document this in quickstart.
- What if the n8n credential for Header Auth is deleted? HTTP Request nodes will fail with a credential-not-found error. This is observable (not silent).
- What if Static Data containing the secret is exported via `make workflow-export`? The secret would be visible in the JSON file. The existing export warning addresses this.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The hmac-verify workflow MUST read the webhook secret from the sub-workflow input (passed by the calling workflow) instead of `$env.OPENCLAW_WEBHOOK_SECRET`.
- **FR-002**: Each workflow that calls hmac-verify MUST pass the webhook secret from its own Static Data via the `workflowInputs` parameter.
- **FR-003**: HTTP Request nodes in token-check, error-handler, and rate-limit-tracker MUST use an n8n Header Auth credential instead of `{{ $env.OPENCLAW_HOOK_TOKEN }}` for the Authorization header.
- **FR-004**: Code nodes in activity-query and rate-limit-tracker that read `$env.N8N_API_KEY` MUST read from Static Data instead.
- **FR-005**: All workflows MUST function correctly with `N8N_BLOCK_ENV_ACCESS_IN_NODE=true`.
- **FR-006**: `grep -r '\$env' workflows/` MUST return zero matches after redesign.
- **FR-007**: The F3 documentation (ASI-MAPPING.md, TRUST-BOUNDARY-MODEL.md) MUST be updated to accurately reflect the complete remediation (env blocked + workflows redesigned).
- **FR-008**: The quickstart and operational docs MUST document the requirement to set Static Data secrets after workflow import.

### Key Entities

- **Static Data**: Workflow-level persistent store used to hold secrets (webhookSecret, n8nApiKey) that were previously in environment variables.
- **Header Auth Credential**: n8n credential type storing the OpenClaw hook token, referenced by HTTP Request nodes.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: `grep -r '\$env' workflows/` returns zero matches.
- **SC-002**: A properly HMAC-signed webhook request to token-check receives a successful response.
- **SC-003**: An unsigned webhook request to token-check receives a 401 rejection.
- **SC-004**: Alert HTTP requests include a valid Authorization header (verified via n8n execution log).
- **SC-005**: All 5 affected workflows execute without errors with `N8N_BLOCK_ENV_ACCESS_IN_NODE=true`.

## Assumptions

- The n8n credential store is secure (encrypted with N8N_ENCRYPTION_KEY stored as a Docker secret).
- Static Data is an acceptable location for secrets given the threat model (operator-only access, localhost-only n8n).
- The operator will set Static Data values after initial deployment and after any `make workflow-import` that resets Static Data.
- Header Auth credentials are created once via n8n UI and persist across container restarts (stored in n8n's encrypted database).

## Adversarial Review #1

| Severity | Finding | Resolution |
|----------|---------|------------|
| CRITICAL | Static Data secrets are visible in `make workflow-export` output. If exported JSON is committed to git, secrets leak. | Already mitigated: workflow-sync.sh has an export warning. Add Static Data stripping to the export process or document as operational requirement. The existing pattern (staticData: null in committed JSON) already handles this — secrets are set operationally, not in git. |
| HIGH | If operator forgets to set Static Data after `make workflow-import`, HMAC auth fails silently (same failure mode as the current $env bug). | Add explicit guard: hmac-verify Code node must check for empty/missing secret and return a descriptive error (not just `verified: false`). Add post-import verification step that checks Static Data is set. |
| MEDIUM | Multiple workflows store the same secret in their own Static Data — no single source of truth. | Acceptable: only token-check calls hmac-verify (one copy of webhookSecret). The Header Auth credential IS a single source of truth for OPENCLAW_HOOK_TOKEN. |
| LOW | Static Data is accessible via n8n REST API. An attacker with API access could read secrets. | Already mitigated: n8n API requires API key stored in macOS Keychain. Same trust boundary as the current env var approach. |

Resolving CRITICAL and HIGH:

For CRITICAL: The committed `workflows/*.json` files already have `"staticData": null`. Secrets are set operationally in the running instance. Export strips them naturally. No additional mitigation needed beyond the existing export warning.

For HIGH: Update FR-001 to require explicit error messaging when secret is missing.

**Gate: 0 CRITICAL, 0 HIGH remaining** after resolutions applied.

## Clarifications

### Session 2026-03-28

- Q: Can Code nodes access n8n credentials? A: No — by design, Code nodes cannot access `$credentials`. Confirmed via n8n docs. This is why we use Static Data for the HMAC secret.
- Q: Can expression fields in non-Code nodes access credentials? A: Yes — HTTP Request nodes can use credential-based auth, replacing manual `{{ $env }}` headers.
- Q: Is Static Data accessible with `N8N_BLOCK_ENV_ACCESS_IN_NODE=true`? A: Yes — Static Data is a workflow-level store, not an environment variable. Unaffected by the setting.
