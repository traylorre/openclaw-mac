# Feature Specification: Fledge Milestone 1 — Gateway Live

**Feature Branch**: `007-n8n-gateway`
**Created**: 2026-03-17
**Status**: Draft
**Input**: Set up n8n in Docker on the Mac Mini, create a hello-world webhook, add Bearer auth, build a gateway Switch node that routes by intent field, and verify the hardening audit still passes with n8n container running. This is the orchestration backbone that all future sub-agents will use.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Hello World Webhook (Priority: P1)

An operator starts n8n in a Docker container on their hardened Mac
Mini. They send a POST request to a webhook endpoint from their
terminal and receive a JSON response confirming the gateway is alive.
This proves the n8n container is running, the network is reachable,
and the webhook mechanism works.

**Why this priority**: Nothing else can be built until n8n is running
and reachable. This is the foundation for every future sub-agent.

**Independent Test**: Run `curl -X POST http://localhost:5678/webhook/hello-world`
from the Mac Mini terminal and verify a JSON response is returned.

**Acceptance Scenarios**:

1. **Given** n8n is running in Docker, **When** the operator sends
   a POST to `/webhook/hello-world` with a JSON body, **Then** a
   200 response is returned containing the echoed body and a status
   field.
2. **Given** n8n is not running, **When** the operator sends the
   same POST, **Then** the connection is refused (no silent failure
   or misleading response from another service).
3. **Given** n8n is running, **When** the operator sends a GET
   instead of POST, **Then** the webhook rejects it with a 404 or
   405 (POST-only).

---

### User Story 2 — Bearer Auth Gate (Priority: P1)

The operator adds authentication to their webhook so that only
authorized callers (OpenClaw, scripts, other agents) can trigger
workflows. Unauthenticated requests are rejected with 401.

**Why this priority**: An unauthenticated webhook on a machine
processing PII and API credentials is an open door. Auth is not
a nice-to-have; it's a security requirement that blocks all
production use.

**Independent Test**: Send a request without the Bearer token and
verify 401. Send with the correct token and verify 200.

**Acceptance Scenarios**:

1. **Given** the gateway webhook requires Bearer auth, **When** a
   request arrives without an Authorization header, **Then** a 401
   Unauthorized response is returned.
2. **Given** the gateway webhook requires Bearer auth, **When** a
   request arrives with an incorrect token, **Then** a 401
   Unauthorized response is returned.
3. **Given** the gateway webhook requires Bearer auth, **When** a
   request arrives with the correct Bearer token, **Then** the
   request proceeds to the workflow and a 200 response is returned.
4. **Given** the auth token is stored as an environment variable,
   **When** the operator inspects the n8n workflow JSON export,
   **Then** the token value does not appear in the export (no
   credential leakage in workflow files).

---

### User Story 3 — Intent-Based Routing (Priority: P2)

The operator configures a single gateway webhook that accepts all
incoming requests and routes them to different sub-workflows based
on an `intent` field in the JSON body. This means OpenClaw (or any
caller) only needs to know one URL. Routing logic lives in n8n.

**Why this priority**: Without routing, each sub-agent needs its
own webhook URL. The gateway pattern centralizes entry, simplifies
callers, and makes adding new sub-agents a configuration change
instead of a new endpoint.

**Independent Test**: Send requests with different `intent` values
and verify each reaches the correct sub-workflow (or returns an
error for unknown intents).

**Acceptance Scenarios**:

1. **Given** the gateway is configured with a `hello` intent route,
   **When** a request arrives with `{"intent": "hello"}`, **Then**
   the request is routed to the hello-world sub-workflow and returns
   its response.
2. **Given** the gateway is configured with multiple intent routes,
   **When** a request arrives with `{"intent": "unknown_intent"}`,
   **Then** the gateway returns a 400 response listing the valid
   intents.
3. **Given** the gateway is configured, **When** a request arrives
   with no `intent` field, **Then** the gateway returns a 400
   response indicating the intent field is required.

---

### User Story 4 — Hardening Audit Passes with n8n Running (Priority: P2)

After n8n is deployed in Docker, the operator runs the hardening
audit and all existing checks continue to pass. The new container
does not introduce regressions in the security posture (no
unexpected open ports, no elevated privileges, no exposed secrets).

**Why this priority**: The hardening audit is the trust verification
layer. If n8n breaks existing checks, the security-first principle
is violated. This must be verified before any production workload
runs through the gateway.

**Independent Test**: Run `sudo bash scripts/hardening-audit.sh --json`
with n8n running and verify no new FAIL results compared to before
n8n was deployed.

**Acceptance Scenarios**:

1. **Given** n8n is running in Docker via Colima, **When** the
   hardening audit runs, **Then** all previously-passing checks
   still pass (zero regressions).
2. **Given** n8n is running, **When** the container security checks
   run, **Then** n8n's container passes container isolation checks
   (non-root, no privileged mode, no Docker socket mount).
3. **Given** the n8n container is configured, **When** the operator
   runs `lsof -i -P | grep LISTEN`, **Then** n8n is only listening
   on localhost:5678 (not bound to all interfaces).

---

### Edge Cases

- n8n container is restarted (via Docker restart policy or manual
  restart). The gateway webhook should be available again within 30
  seconds without manual intervention.
- Docker/Colima is not running when the operator tries to start n8n.
  Clear error message naming the missing dependency.
- The operator already has a service on port 5678. The Docker Compose
  configuration should make the port configurable, and the error
  message should name the port conflict.
- Multiple requests arrive simultaneously. n8n handles concurrent
  webhooks natively; no special configuration needed.
- The Bearer auth token contains special characters. The auth
  validation must handle this correctly.
- n8n is updated to a newer version. The Docker Compose file should
  pin to a specific version tag to prevent unexpected upgrades.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: n8n MUST run as a Docker container managed by Docker
  Compose, using Colima as the container runtime.
- **FR-002**: The Docker Compose file MUST pin n8n to a specific
  version tag (not `latest`).
- **FR-003**: n8n MUST bind only to localhost (127.0.0.1:5678), not
  to all interfaces.
- **FR-004**: n8n MUST persist workflow data to a Docker volume so
  workflows survive container restarts.
- **FR-005**: A hello-world webhook workflow MUST accept POST
  requests, echo the received body, and return a JSON response with
  a status field.
- **FR-006**: All gateway webhook endpoints MUST require Bearer
  token authentication. The token MUST be configured via environment
  variable, not hardcoded in workflow JSON.
- **FR-007**: Unauthenticated or incorrectly-authenticated requests
  MUST receive a 401 response with no workflow execution.
- **FR-008**: A gateway workflow MUST accept a JSON body with an
  `intent` field and route to the correct sub-workflow based on
  the intent value.
- **FR-009a**: A request with no `intent` field MUST return a 400
  response with error "Missing required field: intent" and a list
  of valid intents.
- **FR-009b**: A request with an unrecognized `intent` value MUST
  return a 400 response naming the unknown intent and listing valid
  intents.
- **FR-010**: The n8n deployment MUST NOT introduce any new FAIL
  results in the hardening audit.
- **FR-011**: The n8n container MUST run as a non-root user, without
  privileged mode, and without mounting the Docker socket.
- **FR-012**: The Docker Compose file and startup instructions MUST
  be added to the repository so another operator can reproduce the
  setup.
- **FR-013**: n8n MUST restart automatically on failure (Docker
  restart policy `unless-stopped`).

### Key Entities

- **Gateway Webhook**: The single entry-point URL that all callers
  use. Receives JSON with an `intent` field and a payload. Routes
  to sub-workflows.
- **Intent**: A string identifier in the request body that determines
  which sub-workflow handles the request. Examples: `hello`,
  `lead_gen`, `competitive_scan`.
- **Sub-Workflow**: An n8n workflow triggered by the gateway based on
  intent. Each sub-workflow handles one type of work and returns a
  result to the gateway for response.
- **Auth Token**: A Bearer token stored as an environment variable
  that gates access to all gateway webhooks.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An operator can go from a fresh clone of the repo to a
  running n8n gateway with working webhooks in under 15 minutes
  following the documentation.
- **SC-002**: All existing hardening audit checks pass with n8n
  running (zero regressions).
- **SC-003**: An unauthenticated request to the gateway is rejected
  within 1 second with no workflow execution.
- **SC-004**: Adding a new intent route requires only a configuration
  change in the gateway workflow (no new webhook endpoints or code).
- **SC-005**: The gateway handles 10 concurrent requests without
  errors or dropped connections.

## Assumptions

- Colima is already installed and running on the Mac Mini (covered
  by the existing GETTING-STARTED guides).
- Docker CLI is available (installed via Homebrew, per constitution).
- Port 5678 is available on localhost (no other service using it).
- The operator has sudo access for the hardening audit but n8n itself
  runs without sudo.
- n8n community edition (free, open-source) is sufficient; no paid
  features are needed for the gateway pattern.

## Out of Scope

- n8n workflow UI access from external networks (localhost only).
- n8n user management or team features (single operator).
- HTTPS/TLS on the webhook (localhost-only traffic; TLS is added
  when/if external ingress is needed in a future milestone).
- Sub-agent workflow implementation beyond the hello-world example
  (that's Milestone 2+).
- Qdrant, Ollama, or Mem0 setup (those are Milestone 2).
- OpenClaw installation or configuration (this milestone only sets up
  the n8n side of the integration).
