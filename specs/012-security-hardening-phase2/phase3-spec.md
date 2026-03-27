# Feature Specification: Container & Orchestration Integrity (Phase 3)

**Feature Branch**: `012-security-hardening-phase2` (Phase 3 sub-spec)
**Created**: 2026-03-24
**Status**: Draft
**Input**: Defense-in-depth verification of the n8n Docker container running in Colima on macOS. Informed by Phase 3 Research Brief: 8 n8n CVEs (CVSS ≥ 9.0), ClawHavoc container exploitation, Colima writable $HOME mount, community node supply chain attacks, CIS Docker Benchmark, NIST SP 800-190, OWASP Docker Security, MITRE ATT&CK for Containers.
**Supersedes**: Original US3 (FR-015 through FR-018) in parent spec.md
**Adversarial Review**: 21 findings (3 CRITICAL, 8 HIGH, 10 MEDIUM). All CRITICALs and HIGHs addressed in this revision.
**Note**: Parent spec US4 (Browser Session Protection) and US5 (Output Sanitization) are implemented in separate phases (Phase 4 and Phase 5 respectively), not subsumed by this Phase 3 spec.

---

## User Scenarios & Testing

### User Story 1 — Container Image Integrity Verification (Priority: P1)

The operator deploys the integrity system and the expected container image digest is recorded in the signed manifest. Before the agent issues any command against the orchestration container, the system verifies the running container's image digest matches the recorded baseline. If the image has been replaced — whether by an attacker, an unintended upgrade, or a supply chain compromise — the verification fails and agent launch is blocked. The image digest is a cryptographic commitment (SHA-256) to the exact image content, not a mutable tag.

**Why this priority**: Image replacement is the highest-impact container attack. A replaced container inherits all volume mounts, network access, and secrets. CVE-2026-25253 demonstrated a chain where config.patch forces execution on a different container. The Trivy tag-poisoning attack (March 2026) showed mutable tags can be silently redirected to malicious images. Digest pinning is the only reliable defense.

**Independent Test**: Record the expected container image digest. Stop the container. Start a different image with the same container name. Run integrity verification — verify the digest mismatch is detected and agent launch is blocked. Restore the correct image — verify verification passes.

**Acceptance Scenarios**:

1. **Given** the orchestration container is running, **When** the integrity system deploys, **Then** it captures the container's image digest (SHA-256) and the n8n application version, recording both in the signed manifest under `container_image_digest` and `container_n8n_version` fields.
2. **Given** a recorded image digest exists in the manifest, **When** integrity verification runs before agent launch, **Then** it compares the running container's image digest against the manifest baseline and blocks launch on mismatch with a specific error including both expected and actual digests.
3. **Given** the container has been replaced with a different image (same name, different digest), **When** verification runs, **Then** the mismatch is detected, the event is logged to the audit trail with the expected and actual digests, and agent launch is blocked.
4. **Given** the container is not running, **When** verification runs, **Then** the check fails with a clear error (not a crash) indicating the container is unreachable, and agent launch is blocked.
5. **Given** the n8n version recorded at deploy time is below a minimum safe version threshold, **When** verification runs, **Then** the system warns the operator about known critical vulnerabilities affecting the running version.

---

### User Story 2 — Container Runtime Configuration Verification (Priority: P1)

The operator can verify that the orchestration container is running with the expected security posture. The system checks that the container is not running in privileged mode, has all capabilities dropped, is not sharing the host network, has no Docker socket mounted, binds ports only to localhost, has a read-only root filesystem, and enforces no-new-privileges. If any of these security properties have been weakened — whether by an attacker restarting the container with different flags, a configuration drift, or an accidental change — the verification fails and agent launch is blocked.

**Why this priority**: CVE-2026-27002 demonstrated that sandbox configuration injection can set `network: host`, `seccompProfile: unconfined`, or mount the Docker socket — all of which bypass container isolation. A container that passes image verification but runs with weakened security posture is a false sense of security. Runtime configuration verification is the second line of defense after image integrity.

**Independent Test**: Stop the container. Restart it with `--privileged` flag. Run integrity verification — verify the privileged mode is detected and reported. Restore the correct configuration — verify verification passes.

**Acceptance Scenarios**:

1. **Given** the orchestration container is running, **When** integrity verification checks runtime configuration, **Then** it captures ALL configuration properties in a single atomic `docker inspect` call using the container ID (not name), and verifies all of the following properties, failing on any violation:
   - Container is NOT running in privileged mode
   - All Linux capabilities are dropped (`CapDrop: [ALL]`)
   - Network mode is NOT `host`
   - No Docker socket (`/var/run/docker.sock`) is mounted as a volume
   - All published ports are bound to `127.0.0.1` only (not `0.0.0.0`)
   - Root filesystem is read-only
   - `no-new-privileges` security option is set
   - Seccomp profile is NOT `unconfined`
   - Container user is non-root (UID != 0)
   - Critical environment variables match expected values (`NODES_EXCLUDE` contains dangerous node exclusions, `N8N_RESTRICT_FILE_ACCESS_TO` is set)
2. **Given** the container is running with `--privileged`, **When** verification runs, **Then** the check fails with a CRITICAL error identifying the specific violation and agent launch is blocked.
3. **Given** the Docker socket is mounted as a volume (even read-only), **When** verification runs, **Then** the check fails with a CRITICAL error — Docker socket access grants full host control regardless of read-only mount.
4. **Given** a port is bound to `0.0.0.0` instead of `127.0.0.1`, **When** verification runs, **Then** the check fails with a warning identifying the exposed port and the network interface.
5. **Given** all runtime configuration properties match the expected secure posture, **When** verification runs, **Then** the check passes and logs the verified configuration summary to the audit trail.

---

### User Story 3 — Credential Set Verification (Priority: P1)

The operator can verify that the orchestration container's credential store contains only the expected set of credentials. During deployment, the system captures the names (not secrets) of all credentials configured in the orchestrator. During verification, it enumerates current credential names and compares against the baseline. Any unexpected credential — one that was not present at deploy time — triggers a compromise alert. Any missing credential triggers a warning about potential service disruption.

**Why this priority**: CVE-2026-27495 demonstrated that sandbox escape gives access to all stored credentials. The January 2026 community node supply chain attack used stolen credentials to pivot to connected services. Credential enumeration is a lightweight, non-invasive check that detects the artifacts of compromise without requiring access to the credential values themselves.

**Independent Test**: Record the expected credential set. Add an unexpected credential to the orchestrator. Run integrity verification — verify the unexpected credential is flagged as a compromise indicator. Remove the added credential — verify verification passes.

**Acceptance Scenarios**:

1. **Given** the orchestration container is running, **When** the integrity system deploys, **Then** it enumerates all credential names from the orchestrator and records them in the manifest under `expected_credentials` as an ordered list of credential names.
2. **Given** a recorded credential baseline exists, **When** integrity verification runs, **Then** it enumerates current credential names and compares against the baseline. Unexpected credentials (present now but not in baseline) are reported as "potential compromise indicator — credential added outside deployment pipeline."
3. **Given** a credential that existed at deploy time is now missing, **When** verification runs, **Then** the system warns about the missing credential (potential service disruption, not necessarily compromise).
4. **Given** the credential enumeration command fails (container unresponsive, n8n not ready), **When** verification runs, **Then** the check fails gracefully with a warning, does not crash, and does not block agent launch solely due to enumeration failure.

---

### User Story 4 — Workflow Integrity Verification (Priority: P2)

The operator can verify that workflows running inside the orchestration container match the version-controlled copies in the repository. The system exports workflow definitions from the running container, normalizes them (removing volatile metadata like timestamps and internal IDs), and compares against the repository versions. Any mismatch — whether from an attacker modifying workflows inside the container, an unintended manual edit, or a failed import — is detected and reported with the specific workflow name and the nature of the divergence.

**Why this priority**: Workflow modification is the primary persistence mechanism inside the container. An attacker who gains access (via n8n sandbox escape or credential theft) can inject exfiltration nodes, disable HMAC verification, or modify API endpoints. Workflow comparison detects this class of attack.

**Independent Test**: Deploy all workflows. Modify a workflow inside the container (add a node, change a webhook URL). Run integrity verification — verify the specific modified workflow is identified. Restore the workflow — verify verification passes.

**Acceptance Scenarios**:

1. **Given** workflows are deployed to the orchestrator, **When** integrity verification runs, **Then** it exports all workflows from the running container and compares each against its version-controlled counterpart in the repository.
2. **Given** a workflow inside the container has been modified (added node, changed configuration, altered webhook URL), **When** verification runs, **Then** the mismatch is detected and the specific workflow name is reported.
3. **Given** workflow comparison is performed, **When** comparing exported and repository versions, **Then** volatile metadata fields (updatedAt, createdAt, versionId, id) are excluded from comparison to avoid false positives. The `meta` field is included in comparison per FR-P3-018 (can contain attacker-planted data).
4. **Given** a workflow exists in the container that has no corresponding version-controlled file, **When** verification runs, **Then** the unexpected workflow is reported as a potential compromise indicator.
5. **Given** the container is not running or export fails, **When** verification runs, **Then** the check fails gracefully with a warning rather than a crash.

---

### User Story 5 — Container Filesystem Drift Detection (Priority: P2)

The operator can detect unauthorized modifications to the orchestration container's filesystem. The system monitors the container's overlay filesystem for changes since startup — files added, deleted, or modified that were not part of the original image. Expected changes (temporary files, runtime caches) are excluded. Unexpected changes — especially added executable files — trigger a compromise alert. This detection runs both at pre-launch verification and continuously during the monitoring heartbeat cycle.

**Why this priority**: Container drift is the forensic evidence of container compromise. The MITRE ATT&CK technique T1525 (Implant Internal Image) and T1610 (Deploy Container) both leave filesystem artifacts. `docker diff` provides zero-dependency drift detection from the host without requiring any tooling inside the container. Falco's `proc.is_exe_upper_layer` detection achieves the same goal with more complexity.

**Independent Test**: Start a clean container. Run drift detection — verify no unexpected changes. Exec into the container and create a file. Run drift detection — verify the added file is detected. Delete the file — verify the deletion is detected.

**Acceptance Scenarios**:

1. **Given** the orchestration container is running, **When** drift detection runs, **Then** it queries the container's filesystem changes since startup and categorizes each as added (A), changed (C), or deleted (D).
2. **Given** filesystem changes are detected, **When** the changes include files outside the expected change paths (/tmp, /var/tmp, /home/node/.cache, /home/node/.local), **Then** the unexpected changes are reported as potential compromise indicators.
3. **Given** an executable file has been added to the container filesystem, **When** drift detection runs, **Then** the event is classified as CRITICAL — added executables are the strongest signal of container compromise.
4. **Given** no unexpected filesystem changes exist, **When** drift detection runs, **Then** the check passes and logs the count of expected changes.
5. **Given** the container is not running, **When** drift detection runs, **Then** the check skips gracefully with a warning.

---

### User Story 6 — Community Node Supply Chain Verification (Priority: P2)

The operator can verify that community nodes installed in the orchestration container match the expected set and have not been tampered with. During deployment, the system captures the installed community node packages and their versions. During verification, it compares the current installed packages against the baseline. Any unexpected package, missing package, or version change triggers an alert.

**Why this priority**: The January 2026 n8n supply chain attack demonstrated that community nodes have full access to the n8n runtime, can decrypt all stored credentials using the master encryption key, and can exfiltrate data silently. 8 malicious packages were published to npm before detection. Community node integrity verification detects this attack vector.

**Independent Test**: Record the expected community node set. Install an additional community node inside the container. Run integrity verification — verify the unexpected package is flagged. Remove it — verify verification passes.

**Acceptance Scenarios**:

1. **Given** the orchestration container is running, **When** the integrity system deploys, **Then** it captures the list of installed community node packages with their versions and records them in the manifest under `expected_community_nodes`.
2. **Given** a recorded baseline exists, **When** verification runs, **Then** it enumerates currently installed community nodes and compares names and versions against the baseline.
3. **Given** an unexpected community node package is installed, **When** verification runs, **Then** the unexpected package is reported as "potential supply chain compromise — package installed outside deployment pipeline."
4. **Given** a community node version has changed from the baseline, **When** verification runs, **Then** the version mismatch is reported as a warning (could be legitimate update or supply chain attack).

---

### User Story 7 — VM Boundary Verification (Priority: P3)

The operator can verify that the Colima VM boundary provides meaningful isolation. The system checks the Colima configuration to verify that host filesystem mounts are appropriately restricted — specifically that the operator's home directory is not writable from inside the VM. If the default writable mount is detected, the system warns the operator and provides remediation guidance.

**Why this priority**: Colima's default configuration mounts `$HOME` writable via virtiofs. A container escape (via any of the 8 n8n CVEs) lands in the Linux VM. With writable `$HOME`, the attacker has full access to SSH keys, GPG keys, the entire `.openclaw/` integrity infrastructure, and shell initialization files for persistence. The VM boundary is the outermost defense layer.

**Independent Test**: Check the Colima configuration. If `$HOME` is writable, verify the check produces a warning with remediation steps. Configure restrictive mounts. Verify the check passes.

**Acceptance Scenarios**:

1. **Given** Colima is running, **When** the VM boundary check runs, **Then** it reads the Colima configuration and identifies all host filesystem mounts and their writability.
2. **Given** the operator's home directory is mounted writable (default configuration), **When** the check runs, **Then** it produces a WARNING with specific remediation guidance for restricting mounts.
3. **Given** restrictive mounts are configured (home directory read-only, project directory writable), **When** the check runs, **Then** the check passes with a log of the verified mount configuration.
4. **Given** Colima is not running, **When** the check runs, **Then** the check skips gracefully with a note that VM boundary verification requires a running VM.

---

### User Story 8 — Continuous Container Monitoring (Priority: P3)

The operator has continuous assurance that the orchestration container's integrity holds over time, not just at startup. The existing monitoring heartbeat cycle is extended to include container-specific checks: image digest, runtime configuration, credential count, and filesystem drift. Changes detected between heartbeats trigger immediate operator notification via the existing alert pipeline.

**Why this priority**: Pre-launch verification protects against persistent compromise. Continuous monitoring protects against runtime compromise — an attacker who gains access after agent launch (via n8n sandbox escape, credential theft, or community node supply chain) modifies the container state in ways that pre-launch checks cannot detect.

**Independent Test**: Start the monitoring service. Verify container checks appear in the heartbeat. Replace the container image while monitoring is active. Verify the alert fires within the configured monitoring interval.

**Acceptance Scenarios**:

1. **Given** the continuous monitoring service is running, **When** a container polling cycle executes (60-second interval), **Then** it includes container checks: image digest comparison, credential name set comparison, and filesystem drift detection.
2. **Given** the container image digest changes between heartbeats, **When** the change is detected, **Then** the monitor alerts the operator via the existing alert webhook with the old and new digests.
3. **Given** new credentials appear between heartbeats, **When** the change is detected, **Then** the monitor alerts the operator with the names of the new credentials.
4. **Given** unexpected filesystem drift is detected between heartbeats, **When** the drift includes added executables, **Then** the monitor triggers a CRITICAL alert.
5. **Given** the container becomes unreachable between heartbeats, **When** the monitoring cycle runs, **Then** the monitor alerts the operator that the container is down.

---

### Edge Cases

- What happens when the container is being restarted during a verification check? The system retries once after a 2-second delay, then reports the container as unreachable rather than crashing.
- What happens when the n8n API is not yet ready (container started but n8n still initializing)? Credential and workflow checks retry up to 3 times with 5-second backoff (max 15 seconds), then skip with a warning.
- What happens when docker is not installed or not in PATH? The system detects this and reports all container checks as SKIPPED with guidance to install Docker.
- What happens when the operator intentionally upgrades the n8n image? The operator re-runs the deploy command which captures the new image digest, then verification passes against the updated baseline.
- What happens when community nodes auto-update? The auto-update changes the installed version, triggering a version mismatch warning at next verification. The operator re-deploys to accept the new version.
- What happens when `docker diff` returns a large number of expected changes? The system filters known-safe paths before reporting, preventing alert fatigue from normal runtime behavior.
- What happens when the Colima VM is restarted but the container auto-starts? The monitoring service detects the container restart via a changed container ID and re-verifies all baselines.
- What happens when the container is replaced between checks in the same verification run? The system pins the container ID at the start of verification and uses it (not the container name) for ALL subsequent commands. At the end, it re-verifies the container ID has not changed. If it has, the entire verification is invalidated and restarted.
- What happens when credential enumeration repeatedly fails? After 3 consecutive failures across verification cycles, the system escalates from warning to hard failure — repeated enumeration failure is a potential indicator of an attacker blocking the check.
- What happens when monitoring fires repeated identical alerts? The system deduplicates alerts: same alert type within a 5-minute window is batched into a single "still occurring" notification. When the condition clears, a "resolved" notification is sent.

## Requirements

### Functional Requirements

**Image Integrity (US1)**:

- **FR-P3-001**: System MUST capture the orchestration container's image digest (SHA-256) during deployment and record it in the signed manifest under a `container_image_digest` field.
- **FR-P3-002**: System MUST capture the n8n application version string during deployment (via container inspection or API query) and record it in the manifest under a `container_n8n_version` field.
- **FR-P3-003**: System MUST verify the running container's image digest against the manifest baseline before any `docker exec` command is issued, blocking agent launch on mismatch.
- **FR-P3-004**: System MUST maintain a minimum safe n8n version threshold and warn the operator when the deployed version is below it. The initial threshold MUST be set to address CVE-2026-21858 (CVSS 10.0) and CVE-2026-27495 (CVSS 9.4).

**Verification Orchestration (Cross-Cutting)**:

- **FR-P3-036**: System MUST capture the container ID at the start of verification and use it (not the container name) for ALL subsequent docker commands during that verification cycle. This prevents TOCTOU attacks where the container is replaced between checks.
- **FR-P3-037**: System MUST re-verify the container ID has not changed at the end of the verification cycle. If the ID has changed, the entire verification MUST be invalidated, logged as a CRITICAL event, and restarted.
- **FR-P3-038**: Verification checks MUST execute in the following order: (1) container existence and ID capture, (2) image digest verification, (3) runtime configuration verification, (4) all application-level checks (credentials, workflows, community nodes, drift). Application-level checks MUST NOT run if image digest verification fails.
- **FR-P3-039**: All application-level checks that use `docker exec` (credential enumeration, workflow export, community node listing) MUST be documented as "partial compromise detection" — they detect artifacts of partial compromise but are defeated by full container takeover where the attacker controls the n8n binary. Image digest verification is the primary defense against total takeover.

**Runtime Configuration (US2)**:

- **FR-P3-005**: System MUST verify the container is NOT running in privileged mode during pre-launch verification.
- **FR-P3-006**: System MUST verify the container has `ALL` capabilities dropped during pre-launch verification.
- **FR-P3-007**: System MUST verify the container's network mode is NOT `host` during pre-launch verification.
- **FR-P3-008**: System MUST verify no Docker socket path (`/var/run/docker.sock`, `docker.sock`) is present in the container's volume mounts during pre-launch verification. This check MUST fail regardless of whether the mount is read-only or read-write.
- **FR-P3-009**: System MUST verify all published container ports are bound to `127.0.0.1` (not `0.0.0.0` or any other interface) during pre-launch verification.
- **FR-P3-010**: System MUST verify the container's root filesystem is read-only during pre-launch verification.
- **FR-P3-011**: System MUST verify the `no-new-privileges` security option is set during pre-launch verification.
- **FR-P3-011b**: System MUST verify the container's seccomp profile is NOT `unconfined` during pre-launch verification. CVE-2026-27002 specifically demonstrated seccomp bypass as an attack vector.
- **FR-P3-011c**: System MUST verify the container is running as a non-root user (UID != 0) during pre-launch verification.
- **FR-P3-011d**: System MUST verify critical environment variables match expected values during pre-launch verification: `NODES_EXCLUDE` contains the expected dangerous node exclusion list, `N8N_RESTRICT_FILE_ACCESS_TO` is set. These can be verified via `docker inspect` without trusting the container.
- **FR-P3-012**: All runtime configuration violations MUST be logged to the audit trail with the specific property that failed and the actual vs expected value.
- **FR-P3-012b**: All runtime configuration properties MUST be captured in a single atomic `docker inspect` call to prevent TOCTOU between individual property checks.

**Credential Verification (US3)**:

- **FR-P3-013**: System MUST enumerate orchestrator credential names (not secret values) during deployment and record them in the manifest under `expected_credentials` as an ordered list.
- **FR-P3-014**: System MUST compare current credential names against the baseline during verification and report unexpected credentials as a "potential compromise indicator."
- **FR-P3-015**: System MUST report missing credentials (present in baseline but absent now) as a warning about potential service disruption.
- **FR-P3-016**: Credential enumeration failures (container unresponsive, API timeout) MUST result in a warning on the first occurrence. After 3 consecutive enumeration failures across verification cycles, the system MUST escalate to a hard failure — repeated enumeration failure is a potential indicator of an attacker blocking the check.

**Workflow Integrity (US4)**:

- **FR-P3-017**: System MUST export all workflows from the running container and compare each against its version-controlled counterpart during pre-launch verification.
- **FR-P3-018**: Workflow comparison MUST exclude volatile metadata fields (updatedAt, createdAt, versionId, id) to prevent false positives from routine operations. The `meta` field MUST be included in comparison — it can contain arbitrary key-value pairs that an attacker could use to store exfiltration endpoints or encoded payloads. If `meta` changes cause legitimate false positives, narrow the exclusion to specific sub-fields rather than the entire object.
- **FR-P3-019**: Workflows present in the container but absent from the repository MUST be reported as potential compromise indicators.
- **FR-P3-020**: Workflow comparison MUST run AFTER image digest verification passes — if the image is wrong, workflow comparison results are meaningless.

**Drift Detection (US5)**:

- **FR-P3-021**: System MUST detect container filesystem changes since startup (files added, deleted, or modified) using the container runtime's diff capability.
- **FR-P3-022**: System MUST filter known-safe change paths (/tmp, /var/tmp, /home/node/.cache, /home/node/.local, /run) from drift detection results to prevent false positives.
- **FR-P3-023**: On a read-only root filesystem (FR-P3-010 passed), ANY added file outside safe paths MUST be classified as a CRITICAL drift event — file additions should be impossible on a read-only overlay, indicating rootfs compromise or misconfiguration. On a non-read-only filesystem (degraded posture), added files outside safe paths MUST be classified as WARNING. Note: `docker diff` does not report file permissions, so executable detection is not possible without additional `docker exec` calls — the rootfs-read-only heuristic is the primary classification mechanism.
- **FR-P3-024**: Drift detection results MUST be logged to the audit trail with the full list of unexpected changes.

**Community Node Verification (US6)**:

- **FR-P3-025**: System MUST capture the installed community node packages and their versions during deployment and record them in the manifest under `expected_community_nodes`. Package enumeration MUST read `package.json` files from the known community node installation path inside the container, not rely on `npm list` (which an attacker could patch). This is a `docker exec` based check and is subject to the same partial-compromise-only limitation as credential enumeration (FR-P3-039).
- **FR-P3-026**: System MUST compare currently installed community nodes against the baseline during verification and report unexpected packages as "potential supply chain compromise."
- **FR-P3-027**: Version changes in existing community nodes MUST be reported as warnings (could be legitimate update or attack).
- **FR-P3-027b**: The minimum safe version threshold configuration (FR-P3-004) MUST be stored in a configuration file within the protected file set, not hardcoded. The operator MUST be able to update it via a documented command. An attacker who lowers the threshold is detected by the manifest integrity check.

**VM Boundary (US7)**:

- **FR-P3-028**: System MUST check the Colima configuration for host filesystem mount writability during the hardening audit.
- **FR-P3-029**: A writable home directory mount MUST produce a WARNING with specific remediation guidance for configuring restrictive mounts.
- **FR-P3-030**: The check MUST identify the specific mount paths and their writability status (read-only vs read-write).

**Continuous Monitoring (US8)**:

- **FR-P3-031**: The monitoring heartbeat cycle MUST include container image digest comparison against the manifest baseline.
- **FR-P3-032**: The monitoring heartbeat cycle MUST include credential name set comparison (current names vs baseline names), not just count comparison. An attacker who replaces one credential with another maintains the count but changes the set.
- **FR-P3-033**: The monitoring heartbeat cycle MUST include filesystem drift detection with the same filtering as pre-launch checks.
- **FR-P3-034**: Container state changes detected during monitoring (image change, new credentials, critical drift) MUST trigger operator notification via the existing alert webhook.
- **FR-P3-035**: Container unreachability during monitoring MUST trigger an operator notification.
- **FR-P3-035b**: Monitoring alerts MUST be deduplicated: the same alert type within a 5-minute window MUST be batched into a single "still occurring" notification rather than firing on every heartbeat. When the condition clears, a "resolved" notification MUST be sent.

### Key Entities

- **Container Attestation**: A verified snapshot of the orchestration container's identity and configuration, captured at deployment and verified at startup and continuously. Includes image digest, n8n version, runtime configuration properties, credential names, community node inventory.
- **Image Digest**: The SHA-256 hash of the container image content. Unlike tags, digests are immutable cryptographic commitments. Recorded in the signed manifest as the ground truth for image integrity.
- **Runtime Security Posture**: The set of container configuration properties that collectively define its isolation from the host: privileged mode, capabilities, network mode, volume mounts, port bindings, filesystem read-only status, privilege escalation controls.
- **Drift Event**: A filesystem change detected in the container's overlay filesystem since startup. Categorized as Added (A), Changed (C), or Deleted (D). Filtered against known-safe paths to reduce false positives.
- **Credential Baseline**: An ordered list of credential names captured at deployment. Used for delta comparison to detect unauthorized credential injection (compromise indicator) or removal (service disruption).
- **Community Node Inventory**: A list of installed community node packages with their versions, captured at deployment. Used to detect supply chain attacks where malicious packages are installed or legitimate packages are replaced.

## Success Criteria

### Measurable Outcomes

- **SC-P3-001**: A container replacement attack (swapping the orchestrator image with a different digest) is detected and blocks agent launch within one verification cycle — 100% detection rate.
- **SC-P3-002**: A container configuration weakening attack (restarting with `--privileged`, host network, Docker socket mount, unconfined seccomp, or root user) is detected and blocks agent launch — all 10 runtime configuration properties verified.
- **SC-P3-003**: An unauthorized credential injection (adding a credential outside the deployment pipeline) is detected as a compromise indicator within one verification or monitoring cycle.
- **SC-P3-004**: A workflow modification inside the container (added/changed nodes, altered webhook URLs) is detected and reported with the specific workflow name within one verification cycle.
- **SC-P3-005**: Container filesystem drift (added executables, modified system files) is detected within one monitoring heartbeat cycle.
- **SC-P3-006**: An unauthorized community node installation is detected as a supply chain compromise indicator within one verification cycle.
- **SC-P3-007**: The operator receives notification of any container integrity violation within the configured container monitoring interval (default: 60 seconds). The container polling interval is longer than the file-monitoring heartbeat (30 seconds) to account for Docker API latency.
- **SC-P3-008**: All container verification checks degrade gracefully when the container is unreachable — no crashes, clear error messages, appropriate skip/fail behavior.

## Assumptions

- Docker CLI is available on the host and can communicate with the Colima VM's Docker daemon.
- The orchestration container name is consistent and known (`openclaw-n8n`).
- The n8n CLI is available inside the container for credential and workflow enumeration (`n8n list:credentials`, `n8n export:workflow`).
- The existing integrity manifest format can be extended with container-specific fields without breaking backward compatibility.
- The existing monitoring heartbeat cycle can be extended with additional checks without exceeding the heartbeat interval.
- The Colima configuration file location follows the standard path (`~/.colima/default/colima.yaml`).
- The `docker diff` command accurately reflects container overlay filesystem changes (does not cover volume-mounted paths — this is a known limitation documented in the research brief).
- Community node packages are installed in a predictable location inside the container (`/home/node/.n8n/nodes/`).

## Scope and Boundaries

**In scope**:

- Container image digest capture and verification (deploy-time and pre-launch)
- Container runtime configuration verification (10 security properties)
- Credential name enumeration and baseline comparison
- Workflow export, normalization, and comparison against version-controlled copies
- Container filesystem drift detection via `docker diff`
- Community node package inventory and verification
- Colima VM mount configuration audit
- Continuous monitoring integration (heartbeat cycle extension)
- Audit trail integration for all container events
- n8n version verification against minimum safe threshold

**Out of scope**:

- Modifying the Dockerfile or docker-compose.yml (operational config, not verification)
- Implementing network egress filtering (requires pf rules, separate initiative)
- Cosign/Sigstore image signing (n8n images are not signed with Cosign)
- Modifying n8n application code or configuration
- Real-time syscall monitoring (Falco/Sysdig — excessive for single-container deployment)
- Container image scanning for vulnerabilities (Trivy/Grype — CI/CD concern, not runtime verification)
- Docker Content Trust (retired, replaced by Cosign which n8n doesn't use)
- Credential value verification (only names are enumerated, not secrets)

## Known Limitations (Accepted Residual Risk)

**Docker diff does not cover volume-mounted paths (CRITICAL blind spot)**: The `docker diff` command detects changes in the container's overlay filesystem but NOT in Docker volumes. The n8n data volume (`/home/node/.n8n/`) — which contains the SQLite database, encryption key config, and community node installations — is the primary writable attack surface and is entirely invisible to `docker diff`. Additionally, when the root filesystem is read-only (FR-P3-010), `docker diff` on the overlay is largely redundant since no files can be added there. Credential enumeration (FR-P3-013/014) and community node verification (FR-P3-025/026) partially compensate by checking application-level state within the volume, but both run via `docker exec` and are subject to the partial-compromise limitation (FR-P3-039). This is the most significant detection gap in the Phase 3 design — full volume integrity verification would require host-side access to the Docker volume data inside the Colima VM, which is architecturally complex.

**Credential enumeration requires container cooperation**: The `n8n list:credentials` command runs inside the container. A fully compromised container could return fabricated results. This check detects artifacts of partial compromise (attacker who adds credentials but doesn't modify the n8n binary itself), not total container takeover. Image digest verification is the primary defense against total takeover.

**VM boundary check is advisory only**: The Colima mount configuration check (FR-P3-028/029) produces warnings, not hard failures. Changing the mount configuration requires a Colima restart, which is disruptive. The operator must act on the warning — the system cannot enforce restrictive mounts programmatically.

**Same-user attacker can modify Docker configuration**: An attacker running as the operator's user can stop and restart the container with different flags. Runtime configuration verification (US2) detects this after the fact but cannot prevent it. The defense is detection-and-block (at verification time), not prevention.

**n8n minimum version is a point-in-time assessment**: The minimum safe version threshold (FR-P3-004) must be manually updated as new CVEs are disclosed. It is not automatically derived from a vulnerability database.

## Dependencies

- Phase 1A (Expanded Protection Surface) — COMPLETE: container-related files in protected set
- Phase 2 (Hash-Chained Audit Log) — COMPLETE: audit logging available for container events
- 011-workspace-integrity merged to main (DONE — PR #95)
- Docker CLI available via Colima infrastructure (established in M1)
- n8n CLI available inside the container (established in gateway-setup.sh)
- Existing integrity library functions (manifest build/verify, audit log, state-file signing)

## Framework Alignment

| Framework | Requirement | Coverage |
|-----------|-------------|----------|
| CIS Docker Benchmark 5.1 | No privileged containers | FR-P3-005 |
| CIS Docker Benchmark 5.2 | Drop all capabilities | FR-P3-006 |
| CIS Docker Benchmark 5.3 | No Docker socket mount | FR-P3-008 |
| CIS Docker Benchmark 5.4 | Read-only filesystem | FR-P3-010 |
| CIS Docker Benchmark 5.16 | Bind ports to localhost | FR-P3-009 |
| CIS Docker Benchmark 5.25 | No new privileges | FR-P3-011 |
| CIS Docker Benchmark 5.2 (user) | Non-root container user | FR-P3-011c |
| CIS Docker Benchmark 5.7 | Memory limits set | FR-P3-011d (env var check) |
| NIST SP 800-190 | Seccomp profile enforcement | FR-P3-011b |
| OWASP Docker #2 | Set a user | FR-P3-011c |
| NIST SP 800-190 | Image integrity and provenance | FR-P3-001, FR-P3-002, FR-P3-003 |
| NIST SP 800-190 | Runtime protection | FR-P3-021 through FR-P3-024 |
| NIST SP 800-190 | Credential management | FR-P3-013 through FR-P3-016 |
| OWASP Docker #1 | No Docker socket exposure | FR-P3-008 |
| OWASP Docker #3 | Limit capabilities | FR-P3-006 |
| OWASP Docker #4 | Prevent privilege escalation | FR-P3-011 |
| OWASP Docker #8 | Read-only filesystem | FR-P3-010 |
| MITRE ATT&CK T1610 | Deploy Container detection | FR-P3-001, FR-P3-003 |
| MITRE ATT&CK T1611 | Escape to Host detection | FR-P3-028, FR-P3-029 |
| MITRE ATT&CK T1525 | Implant Internal Image detection | FR-P3-021, FR-P3-023 |
| MITRE ATT&CK T1613 | Container Discovery detection | FR-P3-008 |
