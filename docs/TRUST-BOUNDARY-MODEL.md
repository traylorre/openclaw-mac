# Trust Boundary Model

INTERNAL -- Operator Reference Only

This document defines the five trust zones in the LinkedIn automation pipeline,
enumerates data flows across zone boundaries, and maps future trust
establishment to the ToIP Trust Spanning Protocol (TSP) architecture.

Requirement traceability: FR-024, FR-025, SC-012, US4.

---

## Trust Zones

### TZ1: Operator Authority

| Attribute | Value |
|-----------|-------|
| **Component** | Human operator + sudo |
| **Trust Anchor** | macOS login credentials (password + Touch ID) |
| **Known Gap** | Cannot protect against the operator's own credentials being stolen (phishing, keylogger, session hijack). No gap ADV reference -- this is an inherent platform limitation. |
| **Remediation Roadmap** | Hardware security key (FIDO2/WebAuthn) for macOS login. Enforce FileVault + firmware password. Monitor for credential compromise via Have I Been Pwned alerts. No target milestone -- depends on macOS platform evolution. |

The operator is the root of trust for the entire pipeline. All other trust
zones derive their authority from operator actions: deploying workspace files,
signing manifests, approving posts, rotating credentials. If the operator's
macOS account is compromised, all downstream trust is invalidated.

### TZ2: Instruction Governance

| Attribute | Value |
|-----------|-------|
| **Component** | `manifest.json` (HMAC-signed), workspace files (SOUL.md, AGENTS.md, TOOLS.md), `skill-allowlist.json` |
| **Trust Anchor** | macOS Keychain HMAC key |
| **Known Gap** | ADV-001: The Keychain HMAC key is accessible to any process running as the same macOS user. A compromised same-user process can read the key, forge manifest signatures, and modify instruction files without detection. |
| **Remediation Roadmap** | Keychain access control lists (ACLs) restricting key access to specific binaries. Longer term: Secure Enclave-backed signing where the key never leaves hardware. Target: M5+ (requires OS-level isolation beyond current capabilities). |

Instruction Governance controls what the agent is allowed to do. The manifest
checksums ensure workspace files have not been tampered with since the operator
last deployed them. The skill allowlist restricts which OpenClaw skills can
execute. Both are HMAC-signed with the Keychain key.

### TZ3: Runtime Isolation

| Attribute | Value |
|-----------|-------|
| **Component** | OpenClaw agent process (sandbox mode) |
| **Trust Anchor** | `openclaw.json` configuration (sandbox mode, deny lists, tool restrictions) |
| **Known Gap** | ADV-003: `openclaw.json` can be modified between deploy and launch. There is no out-of-band verification that the config the agent reads at startup matches what the operator deployed. A compromised process could disable sandbox mode before launch. |
| **Remediation Roadmap** | Pre-launch attestation that verifies `openclaw.json` checksum against manifest immediately before agent startup, in a process the agent cannot influence. Target: M5 (requires external attestation service or launch wrapper with independent trust root). |

Runtime Isolation defines the agent's operational boundaries during execution.
Sandbox mode denies exec, process, browser, and write tools. The deny list
prevents the agent from invoking dangerous capabilities. These controls contain
blast radius if the agent is compromised or manipulated (ASI01, ASI02).

### TZ4: Detection Layer

| Attribute | Value |
|-----------|-------|
| **Component** | `integrity-verify.sh`, fswatch continuous monitor, behavioral baseline |
| **Trust Anchor** | Filesystem events, manifest signatures |
| **Known Gap** | ADV-008: `lib/integrity.sh` is sourced by the verification script before the verification script can check its own integrity. A compromised `integrity.sh` could suppress all subsequent detection. This is a circular dependency -- the detection tool cannot verify itself. |
| **Remediation Roadmap** | External integrity witness that independently checksums `lib/integrity.sh` before it is sourced. Candidate: launchd-supervised watchdog process with its own copy of the expected hash. Target: M5+ (accepted risk -- circular dependency is inherent to self-assessment). |

The Detection Layer raises alerts when the pipeline deviates from its expected
state. It operates continuously (fswatch), at launch (integrity-verify.sh),
and on demand (make audit). The self-assessment limitation is documented in
`docs/TRUST-GAPS.md`.

### TZ5: External Services

| Attribute | Value |
|-----------|-------|
| **Component** | n8n Docker container, Ollama, LinkedIn API |
| **Trust Anchor** | Docker container isolation (read-only FS, non-root, caps dropped, no-new-privileges) |
| **Known Gap** | ADV-009: The n8n container image digest is not verified before `docker exec` commands are issued. A replaced image (tag mutation or local tampering) would be trusted implicitly. Additionally, `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` allows Code nodes to read all environment variables, including the n8n encryption key. |
| **Remediation Roadmap** | Pre-exec image digest verification against manifest before any `docker exec`. Digest pinning in `docker-compose.yml` (see Dependency Update Procedure). For env access: migrate HMAC verification to a mechanism that does not require Code node env access, then re-enable `N8N_BLOCK_ENV_ACCESS_IN_NODE=true`. Target: digest pinning in M4, env access remediation in M5. |

External Services are components the operator does not build from source.
Their trust relies on container isolation, version pinning, and CVE monitoring.
The n8n container is the orchestration engine; Ollama provides local LLM
inference; LinkedIn API is the publication target.

---

## Data Flow Across Trust Zone Boundaries

Each row describes data that crosses a zone boundary, the direction of flow,
and what authentication governs the crossing.

| Source Zone | Destination Zone | Data | Authentication |
|-------------|-----------------|------|----------------|
| TZ1 (Operator) | TZ2 (Instruction) | Workspace files (SOUL.md, AGENTS.md, TOOLS.md), skill allowlist, manifest | HMAC signature via Keychain key. Operator runs `integrity-deploy.sh` which checksums files and signs the manifest. |
| TZ1 (Operator) | TZ3 (Runtime) | `openclaw.json` sandbox configuration | File permissions (mode 600). No cryptographic authentication (ADV-003). |
| TZ1 (Operator) | TZ5 (External) | Docker compose configuration, n8n credentials, HMAC shared secret | Docker secrets for encryption key. HMAC secret via `.env` file (mode 600). |
| TZ2 (Instruction) | TZ3 (Runtime) | Agent persona, operating rules, tool definitions, skill content | OpenClaw reads workspace files at startup. Integrity verified by pre-launch attestation (`integrity-verify.sh`) checking manifest checksums. |
| TZ3 (Runtime) | TZ5 (External) | Webhook payloads (draft content, status updates) | HMAC-SHA256 signature with replay protection (5-minute timestamp window). OpenClaw signs outbound webhooks; n8n Code node verifies signature. |
| TZ5 (External) | TZ3 (Runtime) | Webhook callbacks (approval notifications, alerts) | Unsigned (acceptable for localhost-only alerts from n8n to OpenClaw). Residual risk: a local process could spoof callbacks. |
| TZ5 (External) | TZ5 (External) | LinkedIn API calls (post creation, token refresh) | OAuth 2.0 bearer tokens. Access token (60-day TTL) refreshed via refresh token (365-day TTL). Agent never holds LinkedIn tokens directly -- credential isolation enforced by n8n credential store. |
| TZ4 (Detection) | TZ1 (Operator) | Audit reports, alert notifications, behavioral deviation warnings | Unsigned JSON reports (see `docs/TRUST-GAPS.md` -- report provenance gap). Alerts delivered via webhook callback to operator. |
| TZ4 (Detection) | TZ2 (Instruction) | Manifest signature verification results | Detection reads manifest and verifies HMAC signature using Keychain key. Verification result is trustworthy only if `lib/integrity.sh` is uncompromised (ADV-008). |
| TZ4 (Detection) | TZ5 (External) | n8n API queries (execution history, version) | n8n API key stored in macOS Keychain. Passed via credential-safe curl pattern (tmpfile, not command-line argument). |

---

## ToIP TEA Mapping (Future -- Documentation Only)

The current pipeline uses HMAC-SHA256 shared secrets as its sole trust
mechanism. The Trust over IP (ToIP) Trust Establishment Architecture (TEA)
provides a standards-based framework for stronger trust establishment between
autonomous agents and their orchestrators.

This section documents how TEA concepts would map to the pipeline. Implementation
is deferred -- the TSP specification is at Revision 2 (November 2025) and
practical implementation for AI agents is being defined by the ToIP/DIF
working groups.

### Verifiable Identifier (VID)

The OpenClaw agent would hold a Verifiable Identifier (VID) issued by the
operator's governance framework. This replaces the current model where the
agent's identity is implicitly established by the HMAC shared secret it
possesses.

- **Current state**: Agent identity = possession of HMAC key (bearer token model)
- **TEA target**: Agent identity = VID bound to a cryptographic key pair, verifiable independent of the HMAC channel

The VID would be generated during agent provisioning (`make agents-setup`)
and stored alongside the agent's workspace files.

### Trust Spanning Protocol (TSP)

The orchestrator (n8n) would verify the agent's VID via TSP before accepting
webhook payloads. This replaces the current HMAC-only webhook authentication.

- **Current state**: n8n verifies HMAC-SHA256 signature on inbound webhooks
- **TEA target**: n8n verifies VID via TSP, establishing a bidirectional trust relationship. The HMAC signature becomes one layer within the TSP message envelope, not the sole trust mechanism.

TSP would also enable the delegation chain that is currently missing (see
`docs/TRUST-GAPS.md` -- delegation chain gap): when the audit script calls
n8n which calls the LLM, each hop would carry a verifiable delegation
credential.

### did:peer for Localhost Trust

`did:peer` is the candidate DID method for establishing pairwise trust between
components running on the same host. It requires no external resolver or
blockchain, making it suitable for the localhost-only deployment model.

- **Agent DID**: `did:peer` generated by OpenClaw during provisioning
- **Orchestrator DID**: `did:peer` generated by n8n or its trust proxy
- **Resolution**: Local, no network dependency

The `did:peer` exchange would occur during the initial trust establishment
ceremony (analogous to `make hmac-setup` today) and would be stored in each
component's local configuration.

### Trust Tasks

Trust Tasks model atomic verifiable actions within the TEA framework. Each
task represents an operation that can be independently verified.

Candidate trust tasks for this pipeline:

| Trust Task | Current Equivalent | TEA Enhancement |
|------------|-------------------|-----------------|
| Post approval | Human clicks approve in n8n UI | Signed approval credential with timestamp and content hash |
| Credential check | `make audit` HMAC consistency check | Verifiable credential asserting credential isolation status |
| Manifest verification | `integrity-verify.sh` checksum comparison | DID-signed verification report with assessor identity |
| Token refresh | n8n workflow automated refresh | Delegation credential from operator authorizing refresh action |

---

## Cross-Reference: Examine vs. Test Gap

`docs/TRUST-GAPS.md` documents the fundamental limitation of self-attested
security audits. The trust boundary model described in this document operates
entirely within the Examine assessment method (NIST SP 800-53A): configuration
values are read and compared to expected state.

What this model cannot verify:

- **Control effectiveness**: Do the controls actually block attacks? (requires Test method)
- **Report provenance**: Is the audit report authentic? (requires DID-signed reports via TEA)
- **Assessor independence**: The system audits itself (requires external witness via TEA)
- **Temporal integrity**: Configuration can change after an audit passes (requires continuous signed state transitions)

The self-assessment trust problem (OWASP ASI09) applies to every trust zone
in this model. A compromised TZ4 (Detection Layer) would report all zones as
healthy. This is not a flaw to fix in the current milestone -- it is the
design constraint that TEA integration aims to address.

---

## References

- `docs/TRUST-GAPS.md` -- Examine-vs-Test gap and self-attestation problem
- `docs/ASI-MAPPING.md` -- OWASP ASI control mappings
- `docs/SENSITIVE-FILE-INVENTORY.md` -- sensitive file protections by trust zone
- `docs/DEPENDENCY-UPDATE-PROCEDURE.md` -- component update and rollback procedures
- `data/cve-registry.json` -- maintained CVE registry
- [TEA specification](https://github.com/trustoverip/aimwg-tsp-enabled-ai-agent-protocols) -- TSP-Enabled AI Agent protocols
- [TSP specification](https://trustoverip.github.io/tswg-tsp-specification/) -- Trust Spanning Protocol Revision 2
- [did:peer method](https://identity.foundation/peer-did-method-spec/) -- Peer DID specification
- NIST SP 800-53A Rev 5 -- Assessment methods (Examine, Interview, Test)
- [OWASP Top 10 for Agentic Applications](https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/)
