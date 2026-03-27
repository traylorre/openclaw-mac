# Feature Specification: Pipeline Security Hardening

**Feature Branch**: `014-pipeline-security-hardening`
**Created**: 2026-03-26
**Status**: Draft
**Input**: User description: "Security hardening update for the LinkedIn automation pipeline (010). Incorporates CVE landscape research, OWASP ASI Top 10 mapping, defense-in-depth controls, trust boundary model updates, sensitive file inventory, and version pinning strategy."

## User Scenarios & Testing

### User Story 1 — Operator Verifies Pipeline Security Posture (Priority: P1)

The operator runs a single command to verify that the entire LinkedIn automation pipeline (agent, orchestrator, container, credentials) meets current security standards. The verification covers dependency versions against known CVEs, credential isolation boundaries, HMAC webhook authentication integrity, sensitive file protections, and container hardening. The operator receives a clear pass/fail report with specific remediation guidance for any failures.

**Why this priority**: Without verified security posture, the pipeline cannot be trusted to publish content under the operator's professional identity. A compromised agent posting harmful content has career-ending consequences. This is the foundation everything else builds on.

**Independent Test**: Run the security verification command and confirm it validates all pipeline components, reports version currency against CVEs, and flags any unpatched dependencies or misconfigurations.

**Acceptance Scenarios**:

1. **Given** the pipeline is deployed with all components running, **When** the operator runs the security verification, **Then** the system checks n8n version against known CVEs (CVE-2026-21858, CVE-2026-25049, CVE-2026-27577), OpenClaw version against known CVEs (CVE-2026-25253, CVE-2026-32048, CVE-2026-32056), and reports pass/fail for each.
2. **Given** an outdated n8n version is detected, **When** the verification runs, **Then** it reports FAIL with the specific CVE numbers, CVSS scores, and upgrade instructions.
3. **Given** all versions are current, **When** the verification runs, **Then** it reports PASS with version numbers and the date each CVE was patched.
4. **Given** the HMAC webhook secret exists in both the agent and orchestrator environments, **When** the verification runs, **Then** it confirms the secrets match without exposing them (hash comparison only).
5. **Given** the Docker container is running, **When** the verification runs, **Then** it verifies read-only filesystem, non-root user, dropped capabilities, and localhost-only port binding.

---

### User Story 2 — Operator Hardens Sensitive File Protections (Priority: P2)

The operator reviews and locks down all sensitive files in the pipeline. The system provides a complete inventory of files that store secrets, control agent behavior, or configure trust boundaries. Each file has documented protections (permissions, immutability flags, HMAC signatures) and verified enforcement. Files without adequate protection are flagged with specific remediation steps.

**Why this priority**: The adversarial review (ADV-001 through ADV-018) identified that several critical files lack adequate protection. lock-state.json is unsigned (ADV-002), heartbeat files are unauthenticated (ADV-004), and the HMAC trust anchor in Keychain is accessible to same-user processes (ADV-001). These gaps must be closed before the pipeline handles real LinkedIn credentials.

**Independent Test**: Run the sensitive file audit and confirm it inventories all files, verifies their protections, and reports any gaps. Intentionally weaken one file's protection and confirm the audit detects it.

**Acceptance Scenarios**:

1. **Given** the pipeline is deployed, **When** the sensitive file audit runs, **Then** it checks every file in the sensitive file inventory (at minimum: `.env`, `~/.openclaw/.env`, `manifest.json`, `lock-state.json`, `openclaw.json`, `skill-allowlist.json`, all workspace `.md` files, all workflow `.json` files, `docker-compose.yml`, `n8n-entrypoint.sh`).
2. **Given** `lock-state.json` exists without HMAC signature, **When** the audit runs, **Then** it reports FAIL for "unsigned grace period file" and provides remediation: sign lock-state.json with the manifest HMAC key.
3. **Given** `integrity-monitor-heartbeat.json` exists without authentication, **When** the audit runs, **Then** it reports FAIL for "unauthenticated heartbeat" and provides remediation: add HMAC signature to heartbeat writes.
4. **Given** a workspace file (SOUL.md) has its `uchg` immutability flag cleared, **When** the audit runs, **Then** it detects the flag is missing and reports FAIL with remediation instructions.
5. **Given** the `.env` file at the repository root contains the HMAC secret, **When** the audit runs, **Then** it verifies the file is listed in `.gitignore` and has mode 600 permissions.

---

### User Story 3 — Operator Maps Threats to OWASP ASI Controls (Priority: P3)

The operator can review a documented mapping between the OWASP Agentic Security Index (ASI) Top 10 risks and the pipeline's specific controls. Each ASI risk has at least one implemented control, a verification method (audit check or manual procedure), and a residual risk assessment. This mapping serves as both an operational reference and a compliance artifact.

**Why this priority**: The OWASP ASI Top 10 (December 2025) is the industry's first comprehensive security standard for autonomous AI agents. Mapping the pipeline's controls to this standard demonstrates security maturity, identifies coverage gaps, and provides a framework for ongoing improvement.

**Independent Test**: Review the ASI mapping document and confirm each of the 10 ASI risks has a documented control, verification method, and residual risk assessment. Cross-reference with the audit script to confirm verification methods are implemented.

**Acceptance Scenarios**:

1. **Given** the ASI mapping document exists, **When** the operator reviews it, **Then** all 10 ASI risks (ASI01 through ASI10) have at least one control documented.
2. **Given** ASI01 (Agent Goal Hijack) is mapped, **When** the operator reviews the control, **Then** it references the human approval gate, workspace immutability, and persona boundaries as mitigations.
3. **Given** ASI04 (Supply Chain) is mapped, **When** the operator reviews the control, **Then** it references the skill-allowlist, version pinning, and container image verification as mitigations.
4. **Given** ASI07 (Inter-Agent Communication) is mapped, **When** the operator reviews the control, **Then** it references HMAC-SHA256 webhook authentication with replay protection as the mitigation.
5. **Given** any ASI risk has a residual risk rated "High" or above, **When** the operator reviews it, **Then** the mapping includes a remediation roadmap with target milestone.

---

### User Story 4 — Operator Updates Dependencies to Patched Versions (Priority: P4)

The operator uses a documented procedure to update pipeline dependencies (n8n Docker image, OpenClaw version, Ollama models) to versions that patch all known CVEs. The update procedure includes pre-update verification, the update itself, post-update verification, and rollback instructions. Each dependency has a pinned version with hash verification where available.

**Why this priority**: Critical CVEs across all pipeline components in the last 90 days make patching a prerequisite for production deployment. The procedure must be repeatable for ongoing maintenance.

**Independent Test**: Follow the update procedure for one dependency (e.g., n8n Docker image) and confirm the pre/post verification steps work, the updated version is reflected in the manifest, and the audit passes.

**Acceptance Scenarios**:

1. **Given** the n8n Docker image is pinned in `docker-compose.yml`, **When** the operator follows the update procedure, **Then** the procedure includes: check current version, verify new version patches target CVEs, pull new image, restart container, re-run security verification, update manifest baseline.
2. **Given** the OpenClaw version is tracked in the manifest, **When** a new version is released, **Then** the operator can verify it patches specific CVEs before upgrading.
3. **Given** a dependency update breaks the pipeline, **When** the operator follows the rollback procedure, **Then** the previous version is restored and the pipeline returns to working state.
4. **Given** the n8n image is pulled, **When** the update procedure runs, **Then** the image digest (sha256) is recorded in the manifest for future integrity verification.

---

### User Story 5 — Operator Configures Defense-in-Depth Controls (Priority: P5)

The operator enables and verifies all five layers of defense (Prevent, Contain, Detect, Respond, Recover) for the LinkedIn automation pipeline. Each layer has specific controls that are independently verifiable. The controls are documented with their NIST Cybersecurity Framework (CSF) function mappings (Protect, Detect, Respond, Recover) and MITRE ATLAS technique IDs where applicable.

**Why this priority**: Defense in depth is the architectural pattern that survives when individual components are compromised. Each layer provides independent protection. The Recover layer ensures the pipeline can return to a known-good state after compromise.

**Independent Test**: Disable one defense layer (e.g., stop the continuous monitor) and confirm the audit detects the gap. Re-enable and confirm all five layers report healthy.

**Acceptance Scenarios**:

1. **Given** the Prevent layer is configured, **When** the operator verifies it, **Then** credential isolation, HMAC authentication, workspace immutability, and sandbox mode all pass.
2. **Given** the Contain layer is configured, **When** the operator verifies it, **Then** Docker container isolation, OpenClaw sandbox, and dangerous node exclusion all pass.
3. **Given** the Detect layer is configured, **When** the operator verifies it, **Then** pre-launch attestation, continuous monitoring, HMAC-signed manifest verification, and agent behavioral baseline comparison all pass.
4. **Given** the Respond layer is configured, **When** the operator verifies it, **Then** alert delivery to operator, audit logging, and manual remediation procedures are all available.
5. **Given** the Recover layer is configured, **When** the operator verifies it, **Then** credential rotation procedures, manifest re-baseline, and dependency rollback instructions are all documented and tested.
6. **Given** the continuous monitor is stopped, **When** the security verification runs, **Then** it detects the missing heartbeat and reports FAIL for the Detect layer.

---

### User Story 6 — Operator Manages LinkedIn Token Lifecycle (Priority: P6)

The operator configures automated LinkedIn OAuth token refresh using the 365-day refresh token. The system refreshes the 60-day access token automatically at least 7 days before expiry, alerts the operator when the refresh token itself approaches expiry, and provides a re-authorization procedure. Note: LinkedIn added programmatic refresh token support for consumer apps with `w_member_social` scope in late 2025; this supersedes earlier documentation that stated refresh was partner-only.

**Why this priority**: Token expiry is the most common operational failure for API integrations. Automated refresh prevents silent pipeline failures. The 365-day refresh token significantly reduces manual intervention compared to the original 60-day manual re-auth model.

**Independent Test**: Set a test grant_timestamp to simulate 53 days elapsed. Confirm the token refresh triggers automatically at day 53 (7 days before expiry). Confirm the operator receives an alert when the refresh token is within 30 days of its 365-day expiry.

**Acceptance Scenarios**:

1. **Given** the access token was granted 53 days ago, **When** the daily token check runs, **Then** it triggers an automated refresh using the refresh token and logs the new access token grant timestamp.
2. **Given** the refresh token was granted 335 days ago, **When** the daily token check runs, **Then** the operator receives an alert that the refresh token expires in 30 days and manual re-authorization is required.
3. **Given** the automated token refresh fails (network error or invalid refresh token), **When** the failure is detected, **Then** the operator receives an alert with the error details and manual re-authorization instructions.
4. **Given** the access token has been refreshed, **When** the security verification runs, **Then** it reports the new access token expiry date and confirms the refresh token is still valid.

---

### Edge Cases

- What happens when the n8n container is restarted with a different image than the manifest expects? The security verification detects the image digest mismatch and reports FAIL.
- What happens when the HMAC secret is rotated? Both the agent and orchestrator environments must be updated atomically. The rotation procedure documents the sequence and includes a verification step.
- What happens when a new OpenClaw CVE is published that affects the pinned version? The security verification reports the version as potentially vulnerable and links to the advisory.
- What happens when the Keychain HMAC key is accessed by a same-user process? This is the documented ADV-001 residual risk. The ASI mapping acknowledges this gap and references future trust establishment improvements as the remediation path. The Prevent layer is marked as "partial" for this specific control.
- What happens when the operator modifies a workspace file but forgets to re-sign the manifest? The pre-launch attestation detects the checksum mismatch and warns.
- What happens when `N8N_BLOCK_ENV_ACCESS_IN_NODE` is set to `false` (current state)? The audit documents this as a security trade-off with explicit justification and mitigations. This setting creates a residual risk under ASI04 (Supply Chain): a malicious community node could read the n8n encryption key and decrypt stored credentials.
- What happens when the LLM provider (Gemini, Anthropic, Ollama) is compromised or subtly biased? The human approval gate is the primary defense — the operator reviews each post before publishing. No automated detection of subtle content manipulation is feasible at the volume of 1-3 posts per day. This is a documented residual risk under ASI01 (Agent Goal Hijack).
- What happens when a dependency rollback reintroduces known CVEs? After rollback, the security verification runs and reports any CVEs present in the rolled-back version. The operator can make an informed decision to accept the risk temporarily.
- What happens when the OpenClaw binary itself is compromised via a trojanized update? OpenClaw binary integrity verification (signature check, provenance attestation) is not currently implemented. This is a documented residual risk under ASI04 (Supply Chain). The agent binary is the most privileged component, and the security tools protecting it cannot detect its own compromise.

## Requirements

### Functional Requirements

#### Version Currency and CVE Verification

- **FR-001**: The system MUST verify the n8n Docker image version against a maintained CVE registry and report PASS (patched) or FAIL (vulnerable) with specific CVE numbers and CVSS scores. The registry MUST be a version-controlled file in the spec directory, updated manually when new CVEs are disclosed.
- **FR-002**: The system MUST verify the OpenClaw version against the CVE registry and report PASS or FAIL with specific CVE numbers.
- **FR-003**: The system MUST verify the Ollama version against the CVE registry and report PASS or FAIL. Ollama model integrity MUST be verified by comparing the model digest against the expected value in the manifest.
- **FR-004**: The system MUST record the pinned version and image digest (sha256) of the n8n Docker image in the integrity manifest.
- **FR-005**: The system MUST provide a documented update procedure for each pipeline dependency (n8n, OpenClaw, Ollama) that includes pre-update verification, the update, post-update verification, and rollback. The procedure MUST include a post-rollback security verification step that flags any reintroduced CVEs.

#### Sensitive File Protection

- **FR-006**: The system MUST maintain a complete inventory of sensitive files with their expected protections (permissions, immutability flags, HMAC signatures). The inventory MUST include `storageState` / browser profile files with status "Future — required when US2 is implemented."
- **FR-007**: The system MUST verify that `lock-state.json` is HMAC-signed, addressing adversarial finding ADV-002.
- **FR-008**: The system MUST verify that `integrity-monitor-heartbeat.json` is HMAC-signed, addressing adversarial finding ADV-004.
- **FR-009**: The system MUST verify that `.env` files containing secrets are excluded from version control and have mode 600 permissions.
- **FR-010**: The system MUST verify that all workspace files have `uchg` immutability flags set.

#### OWASP ASI Compliance

- **FR-011**: The system MUST include a documented mapping of all 10 OWASP Top 10 for Agentic Applications risks to pipeline-specific controls, verification methods, and residual risk assessments. Note: this spec uses local identifiers ASI01-ASI10 mapped to the official OWASP risk categories for brevity.
- **FR-012**: The system MUST include audit checks that verify at least one control for each ASI risk. The ASI04 (Supply Chain) mapping MUST explicitly note that `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` is a residual risk that weakens credential confidentiality for community node supply chain attacks.

#### Defense-in-Depth Verification

- **FR-013**: The system MUST verify all five defense layers (Prevent, Contain, Detect, Respond, Recover) and report the status of each layer independently.
- **FR-014**: The system MUST detect when any defense layer is degraded and report the specific gap. The Prevent layer MUST be marked as "partial" for the HMAC trust anchor (ADV-001), documenting that credential isolation protects LinkedIn tokens but not the HMAC root of trust.
- **FR-015**: The system MUST include agent behavioral baseline monitoring in the Detect layer: webhook call frequency tracking and skill invocation logging with deviation alerting.

#### LinkedIn OAuth Token Lifecycle

- **FR-016**: The system MUST support LinkedIn OAuth refresh tokens (365-day TTL) in addition to access tokens (60-day TTL). Note: LinkedIn added programmatic refresh token support for consumer apps with `w_member_social` scope in late 2025; this supersedes the 010 spec's R-006 research conclusion.
- **FR-017**: The system MUST implement automated token refresh at least 7 days before access token expiry.
- **FR-018**: The system MUST alert the operator when the refresh token approaches expiry (365-day TTL), requiring manual re-authorization.

#### n8n Hardening

- **FR-019**: The system MUST document the `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` trade-off with explicit justification, mitigations, conditions for change, and cross-reference to ASI04 residual risk.
- **FR-020**: The system MUST exclude dangerous n8n nodes via configuration: executeCommand, ssh, localFileTrigger at minimum.
- **FR-021**: The system MUST run the n8n container with read-only root filesystem, non-root user, all capabilities dropped, and `no-new-privileges` security option.
- **FR-022**: The system MUST store the n8n encryption key as a Docker secret, not as an environment variable in compose configuration.

#### Environment Variable Validation

- **FR-023**: The system MUST validate that no dangerous environment variables are set before agent launch: DYLD_INSERT_LIBRARIES, DYLD_FRAMEWORK_PATH, DYLD_LIBRARY_PATH, NODE_OPTIONS, LD_PRELOAD, HOME (if overridden), TMPDIR (if overridden). This addresses adversarial finding ADV-007.

#### Trust Boundary Documentation

- **FR-024**: The system MUST maintain a documented trust boundary model with at least 5 trust zones (Operator Authority, Instruction Governance, Runtime Isolation, Detection Layer, External Services) and their known gaps, with acceptance scenarios that verify the model is complete.
- **FR-025**: The system MUST reference Trust over IP (ToIP) Trust Establishment Architecture (TEA) as the candidate framework for future trust establishment. The reference MUST include how TEA concepts map to the pipeline: the agent holds a Verifiable Identifier (VID) that the orchestrator verifies via TSP before accepting webhook payloads. `did:peer` is the candidate DID method for localhost pairwise trust. This is a documentation-only deliverable; implementation is deferred.

#### Residual Risk Documentation

- **FR-026**: The system MUST document the LLM provider compromise risk as a residual threat under ASI01 (Agent Goal Hijack). The human approval gate is the primary mitigation. No automated detection of subtle content manipulation is feasible at current posting volume.
- **FR-027**: The system MUST document the OpenClaw binary integrity gap as a residual threat under ASI04 (Supply Chain). The agent binary has no signature verification or provenance attestation. Mitigation: pin version, monitor release notes for security advisories.

### Key Entities

- **CVE Record**: A known vulnerability with CVE identifier, CVSS score, affected component, affected version range, patched version, and verification status.
- **Sensitive File Entry**: A file in the pipeline with path, protection type (permissions, immutability, HMAC signature), expected state, and verification status.
- **ASI Control Mapping**: An OWASP ASI risk (ASI01-ASI10) mapped to pipeline controls, each with a verification method and residual risk assessment.
- **Defense Layer**: One of five defense-in-depth layers (Prevent, Contain, Detect, Respond, Recover) with independently verifiable controls. Each layer maps to NIST CSF functions and MITRE ATLAS techniques where applicable.
- **Token Lifecycle State**: LinkedIn API credential status including access token (60-day TTL), refresh token (365-day TTL), grant timestamp, and days remaining.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Security verification completes in under 60 seconds and covers all pipeline components (agent, orchestrator, container, credentials, sensitive files).
- **SC-002**: All CVEs in the maintained registry are either patched in pinned versions or documented as accepted risk with mitigations. The registry covers n8n, OpenClaw, and Ollama.
- **SC-003**: 100% of sensitive files (at least 14 files) have verified protections matching the inventory.
- **SC-004**: All 10 OWASP ASI risks have at least one implemented control with a working verification method.
- **SC-005**: All five defense-in-depth layers (Prevent, Contain, Detect, Respond, Recover) report healthy when the pipeline is fully configured.
- **SC-006**: The operator can update any single dependency (n8n, OpenClaw, Ollama) from current to latest in under 15 minutes using the documented procedure, including rollback.
- **SC-007**: LinkedIn OAuth token refresh succeeds automatically without operator intervention for at least 60 days after initial authorization.
- **SC-008**: Zero sensitive files are committed to version control (verified by pre-commit hook and audit check).
- **SC-009**: The adversarial review gaps for unsigned lock-state.json (ADV-002) and unauthenticated heartbeat (ADV-004) are closed with HMAC-signed replacements.
- **SC-010**: The environment variable validation check covers at least 7 dangerous variables (DYLD_INSERT_LIBRARIES, DYLD_FRAMEWORK_PATH, DYLD_LIBRARY_PATH, NODE_OPTIONS, LD_PRELOAD, HOME, TMPDIR).
- **SC-011**: Agent behavioral baseline is established and webhook call frequency deviations are detected within one audit cycle.
- **SC-012**: The trust boundary model documents all 5 trust zones with known gaps and remediation roadmap, including ToIP TEA mapping.

## Assumptions

- The operator has access to the macOS Keychain for HMAC key storage (existing infrastructure from M3.5).
- The existing integrity framework (lib/integrity.sh, integrity-deploy.sh, integrity-verify.sh) is the foundation for new verification checks — this spec extends it, not replaces it.
- The n8n container continues to run on localhost only (127.0.0.1:5678) — internet-facing deployment is out of scope.
- Trust Spanning Protocol integration referenced in FR-023 is a documentation deliverable only — implementation is deferred to a future milestone.
- The pipeline uses the standard n8n Docker image — custom Dockerfile builds are deferred.
- LinkedIn API rate limits are per-app per-member and reset at midnight UTC. The specific numeric limit is not published by LinkedIn and must be determined empirically after the first API call via the Developer Portal Analytics tab.

## Scope Boundaries

### In Scope

- Version verification for n8n, OpenClaw, and Ollama against known CVEs
- Sensitive file inventory with protection verification
- OWASP ASI Top 10 control mapping document
- Defense-in-depth layer verification (Prevent, Contain, Detect, Respond, Recover)
- LinkedIn OAuth refresh token support (365-day lifecycle)
- n8n container hardening verification
- Environment variable validation (expanded set)
- HMAC-signing of lock-state.json and heartbeat files (ADV-002, ADV-004 remediation)
- Dependency update procedure documentation
- Trust boundary model documentation with known gaps

### Out of Scope

- Trust Spanning Protocol implementation (documentation reference only)
- Fixing ADV-001 (Keychain trust anchor — requires OS-level isolation beyond current capabilities)
- Fixing ADV-003 (no out-of-band verification — requires external attestation service)
- Fixing ADV-008 (lib/integrity.sh sourced before verification — circular dependency, accepted risk)
- US2 feed discovery features (deferred per prior decision)
- Cloud deployment or multi-node configurations
- Automated CVE database updates (manual maintenance of known CVE list)

## Dependencies

- **M3.5 (Workspace Integrity)**: Existing integrity framework provides the foundation
- **010 (LinkedIn Automation)**: This spec hardens the pipeline defined in 010
- **012/013 (Security Hardening + Adversarial Remediation)**: Adversarial findings ADV-001 through ADV-018 inform the sensitive file protections

## Deliverables

- **OWASP ASI Mapping Document**: Complete mapping of all 10 ASI risks to pipeline controls
- **Sensitive File Inventory**: Machine-readable inventory of all sensitive files with expected protections
- **Dependency Update Procedure**: Step-by-step procedure for updating each pipeline dependency
- **Trust Boundary Model**: Updated trust zone documentation with known gaps and remediation roadmap
