# Feature Specification: Security Hardening Phase 2

**Feature Branch**: `012-security-hardening-phase2`
**Created**: 2026-03-24
**Status**: Draft
**Input**: User description: "Comprehensive security hardening for a self-hosted AI agent deployment. Building on 011-workspace-integrity, this spec addresses all remaining attack surfaces identified through adversarial review, ecosystem research (ClawHavoc: 1,184 malicious skills, 31 CVEs, NemoClaw gaps), and exhaustive file inventory."

## User Scenarios & Testing

### User Story 1 — Expanded Protection Surface (Priority: P1)

The operator deploys the integrity system and all sensitive files on the host are protected against unauthorized modification. This includes files discovered through adversarial review that were not covered by the initial 49-file protected set: LLM routing configuration, agent session state, development tool permissions, old configuration backups, restore scripts, and git hooks in agent workspaces. The expanded protected file list is maintained as a single source of truth in the integrity library. When the operator runs the deployment and lock commands, all sensitive files — not just the original set — are locked with immutable flags and their checksums recorded in the signed manifest.

**Why this priority**: The file inventory audit identified 15+ sensitive files outside the original protection scope. Any unprotected file that influences agent behavior (LLM routing, session state, development tool permissions) is a potential attack vector. Expanding the protection surface is the foundation for all other hardening.

**Independent Test**: Run the deploy command, verify the manifest contains entries for all newly protected files (models.json, workspace-state.json, settings.local.json, etc.). Run the lock command, verify all files have the immutable flag. Attempt to modify a newly protected file as non-root — verify "Operation not permitted."

**Acceptance Scenarios**:

1. **Given** the integrity system is deployed, **When** the operator runs the deploy command, **Then** the manifest includes checksums for all sensitive files identified in the file inventory (models.json, workspace-state.json, development tool permissions, restore scripts, skill-allowlist.json).
2. **Given** old configuration backups exist (e.g., openclaw.json.bak*), **When** the operator runs the lock command, **Then** the backups are locked with immutable flags (preserving operator recovery capability) and their checksums are added to the manifest. The operator is advised to periodically clean up old backups after confirming the current configuration is stable.
3. **Given** git hooks exist in agent workspace directories (.git/hooks/), **When** the integrity system deploys, **Then** all hook files have their execute permission removed (chmod -x) and are locked with immutable flags. Legitimate hooks declared in a hooks allowlist configuration are preserved. Hooks in the main repository (.git/hooks/ at repo root) are also checked.
4. **Given** restore scripts exist with world-readable permissions (755), **When** the integrity system deploys, **Then** permissions are tightened to owner-only (700) and files are locked, or removed entirely.
5. **Given** the skill-allowlist is not HMAC-signed, **When** the integrity system deploys, **Then** the allowlist is signed using the same state-file signing pattern as the lock-state, and verification checks the signature before trusting allowlist entries.

---

### User Story 2 — Audit Log Integrity and Forensic Readiness (Priority: P1)

The operator has confidence that security-relevant events are logged in an append-only, tamper-evident audit trail that survives compromise. The audit log captures all privileged operations (lock, unlock, deploy, sandbox config changes, skill allowlist modifications, integrity verification results) with operator identity, timestamp, and details. The log file is protected by the operating system's append-only flag, preventing deletion or modification of existing entries even by the file owner. When a breach is detected, the operator can reconstruct the timeline of events from the audit log without worrying that the attacker modified it.

**Why this priority**: The adversarial review (ADV-005, ADV-006) found that monitor logs are writable by the agent (same user), and unlock history is destroyed on re-lock. Without tamper-evident logging, the system becomes an opaque box after compromise — you cannot reconstruct what happened.

**Independent Test**: Write an audit log entry, set the append-only flag, attempt to delete or modify the log as the file owner — verify the operation is denied. Verify that appending new entries still succeeds. Run a sequence of lock/unlock/deploy operations and verify each generates a complete audit log entry with operator, timestamp, action, and details.

**Acceptance Scenarios**:

1. **Given** the audit log exists with the append-only flag set, **When** any process (including root) attempts to delete or truncate the log, **Then** the operation fails.
2. **Given** a new audit log entry is appended, **When** the entry is written, **Then** it includes: ISO-8601 timestamp, action type, operator identity, process ID, and structured details.
3. **Given** the operator runs the lock command, **When** lock completes, **Then** the audit log contains an entry for the lock operation listing the number of files locked and the operator.
4. **Given** the operator unlocks a specific file, **When** unlock completes, **Then** the audit log contains an entry for the unlock operation listing the specific file and operator.
5. **Given** the operator runs the deploy command, **When** deploy completes, **Then** the audit log contains an entry recording the manifest version, file count, and operator.
6. **Given** a skill is added or removed from the allowlist, **When** the operation completes, **Then** the audit log records the skill name, content hash, and operator.
7. **Given** the integrity verification runs, **When** the check completes, **Then** the audit log records the result (pass/fail), number of errors and warnings, and any specific failures.
8. **Given** the monitor detects a file modification, **When** an alert is generated, **Then** the audit log records the event regardless of whether alert delivery succeeds or fails.

---

### User Story 3 — Docker Volume and Container Integrity (Priority: P2)

The operator can verify that the workflow orchestration container is running the expected image and that its persistent state (workflows, credentials configuration, execution history) has not been tampered with. The system exports workflow definitions and compares them against version-controlled copies. The container image ID is verified against an expected hash before any commands are issued against the container. Credential names stored in the orchestrator are enumerated and compared against an expected set — any unexpected credential triggers an alert.

**Why this priority**: The adversarial review (ADV-009) found that container integrity is not verified. An attacker with Docker access could replace the container with a malicious one, or modify workflows inside the running container to exfiltrate data.

**Independent Test**: Record the expected container image ID. Replace the running container with a different image. Run integrity verification — verify the image ID mismatch is detected. Modify a workflow inside the container. Run integrity verification — verify the workflow mismatch is detected.

**Acceptance Scenarios**:

1. **Given** the orchestration container is running, **When** the integrity system checks container integrity, **Then** it verifies the running image ID matches the expected image hash recorded in the manifest.
2. **Given** workflows are exported and compared, **When** a workflow has been modified inside the container, **Then** the integrity check detects the mismatch and reports the specific workflow.
3. **Given** the orchestrator has credential entries configured, **When** the integrity system checks credentials, **Then** it enumerates credential names (not secrets) and compares against an expected set — unexpected credentials are flagged.
4. **Given** the container has been replaced with a different image, **When** the integrity check runs, **Then** it detects the image ID mismatch and blocks agent launch with a specific error.
5. **Given** the continuous monitoring service is running, **When** the container image ID changes at any time (not just startup), **Then** the monitor detects the change and alerts the operator within 60 seconds.

---

### User Story 4 — Browser Session Protection (Priority: P2)

The operator's browser session authentication state (containing cookies and local storage) is encrypted at rest. The session file is only decrypted when needed by the browser automation workflow, and the plaintext is never persisted to disk outside of the encrypted container. If the session file is exfiltrated, the attacker cannot use it without the decryption key. Session file access is logged in the audit trail.

**Why this priority**: The browser session contains authentication cookies granting full access to the operator's social media account. The Atomic macOS Stealer (distributed via ClawHavoc) specifically targets browser credentials and cookies. Encrypting the session at rest reduces the blast radius of credential theft.

**Independent Test**: Encrypt the session file. Attempt to read it directly — verify it is not plaintext. Trigger a browser automation workflow — verify it can decrypt and use the session. Verify the decryption event is logged in the audit trail.

**Acceptance Scenarios**:

1. **Given** a browser session file exists, **When** the operator runs the session encryption command, **Then** the plaintext file is replaced with an encrypted version and the original is securely deleted.
2. **Given** the encrypted session file exists, **When** the browser automation workflow needs to use the session, **Then** the session is decrypted into a temporary location, used, and the temporary plaintext is deleted immediately after.
3. **Given** the encrypted session file is copied to another machine, **When** an attacker attempts to use it, **Then** decryption fails because the key is stored in the operator's credential store (not alongside the file).
4. **Given** a session decryption event occurs, **When** the workflow accesses the session, **Then** an audit log entry records the access timestamp and the workflow that requested it.

---

### User Story 5 — Output Sanitization for Webhook Payloads (Priority: P2)

The system validates all data flowing from the AI agent to workflow orchestration endpoints before it reaches external APIs. The agent's output (post content, comment text, metadata) is checked for injection patterns, control characters, excessive length, and structural conformance to the expected payload schema. Payloads that fail validation are rejected with a specific error, and the rejection is logged. This prevents a compromised agent from using the webhook pipeline to exfiltrate data, post unauthorized content, or inject payloads into external API calls.

**Why this priority**: Untrusted output passed to downstream systems is a primary risk (OWASP LLM02). The agent's output flows through webhooks to external APIs — if the agent is compromised via prompt injection, it could craft payloads that abuse the pipeline.

**Independent Test**: Send a webhook payload with control characters embedded in the content field — verify rejection. Send a payload with content exceeding the maximum length — verify rejection. Send a valid payload — verify it passes through.

**Acceptance Scenarios**:

1. **Given** the agent sends a webhook payload, **When** the payload arrives at the endpoint, **Then** the signature verification validates authenticity before any content processing.
2. **Given** a valid signed payload arrives, **When** the content field contains control characters (null bytes, escape sequences, terminal injection), **Then** the workflow rejects the payload with a sanitization error.
3. **Given** a valid payload arrives, **When** the content exceeds the maximum allowed length (3000 characters for posts, 1250 for comments), **Then** the workflow rejects the payload with a length error.
4. **Given** a valid payload arrives, **When** the payload structure does not match the expected schema (missing required fields, unexpected fields, wrong types), **Then** the workflow rejects the payload with a schema error.
5. **Given** a payload is rejected for any sanitization reason, **When** the rejection occurs, **Then** the rejection details are logged in the audit trail and the operator is notified.

---

### User Story 6 — Manifest Versioning and Rollback Detection (Priority: P3)

The system maintains a history of manifest versions, enabling detection of rollback attacks where an attacker replaces the current manifest with an older version containing weaker checksums. Each manifest includes a monotonically increasing version counter and a reference to the previous manifest's signature. The integrity verification validates that the manifest version is not lower than the last verified version. If a rollback is detected, the system blocks agent launch and alerts the operator.

**Why this priority**: The adversarial review (ADV-010) found that manifests are updated in-place with no version history. An attacker who compromises the signing key can re-sign an old manifest and roll back the protection to a weaker state without detection.

**Independent Test**: Deploy a manifest (version N). Deploy again (version N+1). Replace manifest with the version N copy. Run integrity verification — verify the rollback is detected and agent launch is blocked.

**Acceptance Scenarios**:

1. **Given** a manifest is built, **When** the deploy command runs, **Then** the manifest includes a sequence counter that increments on every deploy.
2. **Given** the last verified manifest had sequence N, **When** a manifest with sequence M < N is presented, **Then** the verification detects the rollback and reports the expected vs actual sequence numbers.
3. **Given** a rollback is detected, **When** the integrity check runs, **Then** agent launch is blocked and the audit log records the rollback attempt.
4. **Given** the operator intentionally needs to deploy an older manifest, **When** they run deploy with a force flag, **Then** the deploy proceeds with a warning in the audit log that the sequence was reset.

---

### User Story 7 — Audit Enforcement Gate (Priority: P3)

The integrity verification system integrates critical audit checks so that known security misconfigurations block agent launch. Instead of running the audit separately (advisory only), the most critical checks (sandbox enabled, monitor running, all files locked, skill allowlist valid) are included in the pre-launch attestation. If any critical audit check fails, the agent does not start.

**Why this priority**: The adversarial review (ADV-012) found that audit failures are advisory only — the operator can ignore results and launch the agent anyway. Critical security controls should be enforced, not just reported.

**Independent Test**: Disable sandbox mode. Run integrity verification — verify it fails with a specific audit check failure. Re-enable sandbox. Run again — verify it passes.

**Acceptance Scenarios**:

1. **Given** sandbox mode is disabled for any agent, **When** integrity verification runs, **Then** the check fails (not just warns) and agent launch is blocked.
2. **Given** any protected file is not locked (missing immutable flag), **When** integrity verification runs, **Then** the check fails with a list of unlocked files.
3. **Given** the skill allowlist signature is invalid or missing, **When** integrity verification runs, **Then** the check fails and reports the allowlist integrity issue.
4. **Given** all critical audit checks pass, **When** integrity verification runs, **Then** the agent launches normally.
5. **Given** the operator needs to bypass enforcement for debugging, **When** they run verification with a force override, **Then** the check warns but does not block, and the bypass is logged in the audit trail.

---

### Edge Cases

- What happens when the audit log file is full or the filesystem is full? The system detects write failures and alerts the operator rather than silently dropping events.
- What happens when the orchestration container is stopped during an integrity check? Docker-related checks gracefully skip with a warning, not crash.
- What happens when the operator rotates the signing key? All signed state files (manifest, lock-state, heartbeat, allowlist) must be re-signed in a single atomic operation. The audit log records the key rotation event.
- What happens when a new file type is added that should be protected? The operator adds it to the protected file list configuration in the integrity library and re-deploys.
- What happens when the browser session expires naturally? The system detects the expired session during the health check and alerts the operator — it does not attempt automated re-login.

## Requirements

### Functional Requirements

**Expanded Protection Surface (US1)**:

- **FR-001**: System MUST protect LLM routing configuration in all agent directories against unauthorized modification.
- **FR-002**: System MUST protect agent session state files in all agent directories against unauthorized modification.
- **FR-003**: System MUST protect development tool permission configuration against unauthorized modification.
- **FR-004**: System MUST remove or lock old configuration backups to prevent rollback to weaker security posture.
- **FR-005**: System MUST empty or make read-only all git hooks directories in agent workspaces to prevent arbitrary code execution.
- **FR-006**: System MUST tighten restore script permissions to owner-only and lock with immutable flag, or remove entirely.
- **FR-007**: System MUST sign the skill-allowlist file using the same state-file signing pattern as the lock-state and heartbeat files.
- **FR-008**: System MUST verify the skill-allowlist signature before trusting its contents during integrity verification and skill checks.

**Audit Log Integrity (US2)**:

- **FR-009**: System MUST set the operating system's append-only flag on the integrity audit log file after creation.
- **FR-010**: System MUST log all privileged operations (lock, unlock, deploy, verify, skill allowlist changes, sandbox config changes, monitor alerts) to the audit log.
- **FR-011**: Each audit log entry MUST include: ISO-8601 timestamp, action type, operator identity, process ID, and structured details.
- **FR-012**: System MUST log integrity verification results (pass/fail, error count, warning count, specific failures) to the audit log.
- **FR-013**: System MUST log monitor alert events (file path, expected hash, actual hash, delivery status) to the audit log regardless of alert delivery success.
- **FR-014**: Audit log entries MUST be structured (one entry per line) for machine parseability.
- **FR-014b**: Each audit log entry MUST include the hash of the previous entry (hash chain), enabling detection of entry insertion, reordering, or deletion. The first entry's previous-hash is a well-known constant.

**Docker and Container Integrity (US3)**:

- **FR-015**: System MUST verify the running orchestration container image ID against an expected hash before issuing any commands against the container.
- **FR-016**: System MUST record the expected container image ID in the integrity manifest during deployment.
- **FR-017**: System MUST enumerate orchestrator credential names (not secrets) and compare against an expected set during integrity verification.
- **FR-018**: System MUST detect and report unexpected credentials as a potential compromise indicator.

**Browser Session Protection (US4)**:

- **FR-019**: System MUST encrypt browser session authentication state at rest using a key stored in the operator's credential store.
- **FR-020**: System MUST provide commands to encrypt and decrypt the session file for use by browser automation workflows.
- **FR-021**: System MUST log session file access (decrypt events) in the audit trail.
- **FR-022**: System MUST securely delete the plaintext session file after encryption.

**Output Sanitization (US5)**:

- **FR-023**: The webhook pipeline MUST validate incoming payload structure against the expected schema before processing.
- **FR-024**: The webhook pipeline MUST reject payloads containing control characters (null bytes, escape sequences) in content fields.
- **FR-025**: The webhook pipeline MUST enforce maximum content length limits appropriate to each content type.
- **FR-026**: Rejected payloads MUST be logged with rejection reason, and the operator MUST be notified.

**Manifest Versioning (US6)**:

- **FR-027**: Each manifest MUST include a monotonically increasing sequence counter.
- **FR-028**: Integrity verification MUST reject manifests with a sequence number lower than the last verified sequence.
- **FR-029**: The last verified sequence number MUST be stored outside the manifest (in a separate signed state file) to prevent tampering.
- **FR-030**: A force flag on deployment MUST allow intentional sequence resets, logged in the audit trail.

**Audit Enforcement (US7)**:

- **FR-031**: Integrity verification MUST enforce (not just warn on) critical audit checks: sandbox enabled, all files locked, skill allowlist valid.
- **FR-032**: A force override MUST be available for debugging, with the bypass logged in the audit trail.
- **FR-033**: The set of enforced checks MUST be configurable (not hardcoded) to allow the operator to adjust enforcement as the system matures. A minimum set (sandbox enabled, manifest signature valid) MUST be hardcoded and cannot be disabled via configuration. The enforcement configuration file MUST be in the protected file set (US1).
- **FR-034**: ALL scripts performing security operations MUST verify the integrity library's content hash before sourcing it. The bootstrap case (no manifest yet) MUST log a warning rather than silently pass.
- **FR-035**: The environment variable validation MUST include TMPDIR (verify it points to the system default or is unset) in addition to the existing checks.
- **FR-036**: The output sanitization workflow definition MUST be included in the protected file set (US1) so that an attacker who can modify container workflows cannot disable sanitization without detection.

### Key Entities

- **Protected File**: Any file whose modification could alter agent behavior, leak credentials, or weaken security posture. Identified by path and content hash. Categorized as: instruction, control, credential, configuration, governance, or state.
- **Trust Anchor**: The signing key stored in the operator's credential store. Used to sign manifests, state files, and verify authenticity. Accessible to any process running as the operator's user (known limitation).
- **Audit Event**: A structured record of a security-relevant operation, appended to the integrity audit log. Includes timestamp, action, operator, process ID, and details.
- **Manifest Sequence**: A monotonically increasing counter embedded in each manifest version, enabling rollback detection.
- **Container Attestation**: The verified mapping between a running container and its expected image hash, recorded in the manifest.
- **Session Credential**: An encrypted-at-rest browser authentication state protected by a credential-store encryption key.

## Success Criteria

- **SC-001**: All sensitive files identified in the adversarial review file inventory are protected by immutable flags and recorded in the signed manifest — zero unprotected sensitive files remain.
- **SC-002**: The audit log survives a simulated compromise scenario where an attacker with user-level access attempts to delete or modify log entries — append-only enforcement holds.
- **SC-003**: A container replacement attack (swapping the orchestrator image) is detected within one integrity verification cycle.
- **SC-004**: Browser session credentials are not readable at rest without the credential-store decryption key — exfiltration of the encrypted file yields no usable credentials.
- **SC-005**: All webhook payloads are validated against the schema and sanitization rules before processing. A defined test suite of injection patterns (control characters, null bytes, escape sequences, oversized payloads, schema violations) is rejected with 100% accuracy.
- **SC-006**: A manifest rollback attack (replacing current manifest with an older signed version) is detected and blocks agent launch.
- **SC-007**: The system blocks agent launch when critical security controls are disabled (sandbox off, files unlocked) — enforcement is not advisory.
- **SC-008**: All security-relevant events are reconstructable from the audit log after a simulated compromise — no forensic gaps.

## Assumptions

- The operator has elevated privileges on the host (required for filesystem flag operations).
- The operator's credential store is unlocked during the login session (standard behavior).
- Container orchestration is available via existing infrastructure (established in M1).
- The existing integrity library and its signing/verification functions are the foundation for all new protections.
- The existing manifest format can be extended with new fields without breaking backward compatibility.
- Browser session encryption uses industry-standard authenticated encryption (AES-256-GCM or equivalent).
- The audit log append-only flag requires elevated privileges to set but prevents even elevated processes from clearing it without recovery-mode boot.

## Scope and Boundaries

**In scope**:

- Expanding the protected file list to all sensitive files identified in the adversarial review
- Signing the skill-allowlist with the established state-file signing pattern
- Enforcing append-only on the audit log via operating system flags
- Container image verification before command execution
- Browser session encryption at rest
- Webhook payload sanitization and schema validation
- Manifest versioning with rollback detection
- Audit enforcement gate in startup verification

**Out of scope**:

- Hardware security module or secure enclave integration for key storage (deferred to M5)
- Out-of-band verification via external witness service (deferred to M5)
- Agent identity separation (running agent as a different system user) (deferred to M5)
- Real-time prompt injection detection at the model level
- Automated incident response (quarantine, rollback) — response remains manual
- Full provenance chain for all artifacts (partial implementation via manifest versioning)
- Social engineering attacks via skill marketplace comments (operator training concern, not technical control)

## Known Limitations (Accepted Residual Risk)

**Trust anchor in shared security domain (ADV-001)**: All HMAC signing operations (manifest, lock-state, heartbeat, allowlist, sequence file) use a key stored in the macOS login Keychain, which is accessible to any process running as the operator's user. This means a same-user attacker can extract the key and forge any signed artifact. All signing-dependent protections (US1-FR007/FR008, US6, US7) are defense against external/agent-level threats, NOT against same-user compromise. Browser session encryption (US4) similarly only protects against offline/physical-access attacks, not same-user extraction. Moving to a per-application Keychain with interactive confirmation is deferred to M5.

**Append-only is not forgery-proof**: The audit log's append-only flag prevents deletion and truncation but does not prevent a same-user attacker from appending false entries. Hash-chained entries (FR-014b) detect insertion and reordering but not appended forgeries unless each entry is also HMAC-signed. The hash chain provides ordering integrity; the append-only flag provides deletion resistance. Together they raise the bar significantly but do not achieve full tamper-evidence against a same-user attacker with the HMAC key.

**TOCTOU in symlink detection (ADV-013)**: A race condition exists between symlink checking and file locking. An attacker who can observe the lock sequence can plant a symlink after the check but before the lock is applied. Atomic check-and-lock per file would close this gap but is not implemented in this spec (would require significant refactoring of the lock script).

## Deployment Sequence

The following order resolves circular dependencies between user stories:

1. **Phase A**: Deploy expanded file list (US1) — adds new files to manifest
2. **Phase B**: Lock all files (US1) — sets immutable flags
3. **Phase C**: Set append-only on audit log (US2) — after first log entries are written
4. **Phase D**: Deploy container integrity checks (US3) — records image IDs
5. **Phase E**: Deploy session encryption (US4) — encrypts browser state
6. **Phase F**: Deploy output sanitization (US5) — adds validation to webhook workflows
7. **Phase G**: Deploy manifest versioning (US6) — starts sequence counter
8. **Phase H**: Enable enforcement gate (US7) — last, after all controls are active

The system is vulnerable during this transition. Each phase should be followed by a verification run to confirm the control is active before proceeding.

## Dependencies

- 011-workspace-integrity merged to main (DONE — PR #95)
- Operating system support for append-only file flags (available on target platform)
- Container CLI available via existing infrastructure (established in M1)
- Standard encryption tools available on target platform
- Existing integrity library functions (state-file signing, verification, audit logging)
