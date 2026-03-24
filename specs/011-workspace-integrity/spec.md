# Feature Specification: Agent Workspace Integrity and Host Isolation Hardening

**Feature Branch**: `011-workspace-integrity`
**Created**: 2026-03-23
**Status**: Draft (post-adversarial review, 29 findings addressed)
**Input**: User description: "Self-hosted AI agents run natively on the host with full filesystem access. A compromised skill, supply chain attack, or prompt injection can modify workspace files that are injected into the system prompt on every turn — effectively rewriting the agent's brain. Current checksum-based audit is detection-only and runs on-demand, not at startup or continuously."

## User Scenarios & Testing

### User Story 1 — Workspace Files Are Protected from Unauthorized Modification (Priority: P1)

The operator deploys agent workspace files (persona definitions, operating rules, skill definitions) to the host. These files define the agent's identity, behavior boundaries, and capabilities. Once deployed, the files are locked against modification by any process — including the agent itself, installed skills, and compromised dependencies. The operator explicitly unlocks files when intentional edits are needed, makes changes, and re-locks them. Any tampering attempt between deployments is prevented at the filesystem level, not merely detected after the fact.

This applies to all files injected into the agent's system prompt: SOUL.md, AGENTS.md, TOOLS.md, IDENTITY.md, USER.md, BOOT.md, and all SKILL.md files. It also applies to orchestration files outside the agent workspace: CLAUDE.md, workflow JSON definitions, deployment scripts, Docker configuration, entrypoint scripts, and configuration files (openclaw.json, .env files).

**Privilege model**: Immutable flags require root to set and clear. Every lock/unlock/deploy operation requires elevated privileges. This is intentional friction — it prevents same-user processes (including the agent) from modifying their own instructions. Immutable flags prevent modification by any non-root process. They do NOT prevent modification by a process with root access. The integrity verification layer (US3) detects what immutability misses.

**Why this priority**: These files are the agent's instruction set. A modified SOUL.md changes what the agent says and does across all conversations. A modified SKILL.md can exfiltrate secrets or post unauthorized content. Prevention (even imperfect) raises the bar from "any process can write" to "only root can write." This is the foundation all other security controls build on.

**Independent Test**: Deploy workspace files via `make agents-setup`. Attempt to modify SOUL.md as the operator user. Verify the modification is rejected by the operating system. Run the security audit. Verify the integrity check passes. Unlock the file (requires elevated privileges), make an intentional edit, re-lock. Verify the audit reports the change with the updated checksum.

**Acceptance Scenarios**:

1. **Given** workspace files are deployed and locked, **When** any non-root process (including the agent) attempts to write to SOUL.md, **Then** the operating system rejects the write with a permission error.
2. **Given** workspace files are locked, **When** the operator runs the security audit, **Then** all workspace file integrity checks pass.
3. **Given** the operator needs to update a persona definition, **When** the operator runs the unlock command with elevated privileges, **Then** the specified files become writable.
4. **Given** the operator has edited and saved changes, **When** the operator runs the lock command, **Then** files are re-locked, checksums are updated, and the manifest is re-signed.
5. **Given** an attacker gains root access and modifies a file despite locks, **When** the agent starts or the audit runs, **Then** the checksum mismatch is detected and reported as a critical alert.
6. **Given** CLAUDE.md is deployed in the repository, **When** any non-root process attempts to modify it, **Then** the modification is rejected at the filesystem level.
7. **Given** n8n workflow JSON files are deployed, **When** any non-root process attempts to modify them, **Then** the modification is rejected at the filesystem level.
8. **Given** a protected directory contains a symlink, **When** the lock command runs, **Then** it rejects the symlink and reports it as a security violation.

---

### User Story 2 — Agent Runs in an Isolated Sandbox with Restricted Filesystem Access (Priority: P2)

The operator configures the AI agent to run inside a sandbox that restricts its filesystem access to its own workspace directory. The agent can read its workspace files but cannot write to them (read-only mode). The agent cannot access files outside its workspace — no reading CLAUDE.md, no reading other agents' workspaces, no reading system configuration files, no reading the Docker compose file or secrets. The sandbox also restricts which tools the agent can use, following the principle of least privilege. API-calling skills (like config-update) are classified as privileged and subject to the same restrictions as filesystem tools.

The extraction agent (feed-extractor) (used for processing untrusted content) runs in an even more restrictive sandbox: no tools, no skills, no filesystem writes, no exec capability. It is invoked as a sub-agent by the primary agent via the platform's internal multi-agent call mechanism (not via network), receives input as structured data, produces structured JSON output, and nothing else.

**Why this priority**: Filesystem restriction eliminates entire classes of attacks. Even if the agent is compromised via prompt injection, it cannot modify its own instructions (read-only workspace), cannot read secrets from other locations (workspace-only access), and cannot execute arbitrary commands (tool restrictions). This is the NemoClaw model — NVIDIA runs OpenClaw in a sandboxed container where the agent can only write to /sandbox and /tmp, with all other paths read-only.

**Independent Test**: Start the agent in sandbox mode. Attempt to read a file outside the workspace (e.g., `~/.openclaw/.env`). Verify access is denied. Attempt to write to SOUL.md. Verify write is denied. Attempt to use a denied tool (e.g., `exec`). Verify the tool call is rejected. Verify the normal webhook-based workflow still operates.

**Acceptance Scenarios**:

1. **Given** the agent is running in sandbox mode, **When** a skill or prompt attempts to read a file outside the workspace, **Then** the read fails with a permission error.
2. **Given** the agent is running with read-only workspace access, **When** a skill or prompt attempts to write to any workspace file, **Then** the write fails.
3. **Given** the agent's tool allowlist includes only approved tools, **When** a prompt or skill attempts to use a denied tool (exec, browser, process), **Then** the tool call is rejected.
4. **Given** the extraction agent is configured with zero tools and zero skills, **When** any input attempts to invoke a tool, **Then** the invocation is rejected.
5. **Given** the agent is running in sandbox mode, **When** the operator sends a chat message and requests a post, **Then** the normal workflow (draft → approve → publish via webhook) operates without disruption.
6. **Given** sandbox mode is enabled, **When** the security audit runs, **Then** it verifies that sandbox configuration is active and tool restrictions are enforced.

---

### User Story 3 — System Detects and Alerts on Integrity Violations at Startup and Continuously (Priority: P3)

The system verifies file integrity at two points: (1) before the agent loads workspace files on startup, and (2) continuously via a background monitoring service managed by the operating system's process supervisor (so it restarts automatically if killed).

At startup, if any protected file fails its integrity check, the agent refuses to start and alerts the operator with details of which files were modified. The startup check script launches the agent directly after verification passes, eliminating any window between verification and file loading.

The continuous monitoring service writes a heartbeat file at regular intervals. The startup check and audit both verify the heartbeat is recent, detecting a killed or crashed monitor even if the attacker restarts it after tampering.

Alert suppression during intentional edits is scoped to the specific files being edited (not all files) and has a configurable timeout (default: 5 minutes).

**Why this priority**: Immutable flags (US1) are the primary defense. The integrity check layer catches bypass scenarios (privilege escalation, boot from different OS, macOS updates clearing flags, flag clearing by root). Defense in depth requires independent layers.

**Independent Test**: Start the monitoring service. Clear an immutable flag and modify a protected file using elevated privileges. Verify the operator receives an alert within 60 seconds. Restore the file and re-set the flag. Verify the alert clears. Kill the monitoring service. Verify the audit reports monitoring is inactive.

**Acceptance Scenarios**:

1. **Given** the monitoring service is running, **When** a protected file is modified, **Then** the operator receives an alert via chat within 60 seconds.
2. **Given** a workspace file has been tampered with, **When** the agent process starts, **Then** the startup integrity check fails and the agent refuses to load, reporting which files were modified.
3. **Given** the monitoring service is running, **When** the operator performs an intentional edit (unlock specific file → edit → lock), **Then** no false alert is generated for that specific file. Other files remain monitored.
4. **Given** the manifest file itself is modified, **When** the integrity check runs, **Then** the system detects the manifest tampering via independent signature verification.
5. **Given** the monitoring service is killed, **When** the operating system's process supervisor detects the exit, **Then** it restarts the service automatically. If the restart fails, the next audit or startup check detects the stale heartbeat.
6. **Given** a file is modified and immediately restored (transient tampering), **When** the monitoring service detects the filesystem event, **Then** it re-verifies the file's checksum against the manifest, detecting content changes even if the modification is reversed.

---

### User Story 4 — Supply Chain Controls Prevent Malicious Skill Installation (Priority: P4)

The operator controls which skills can be installed on the agent. Skills from the community marketplace are not automatically trusted — they require explicit operator approval before installation. Installed skills are identified by content hash (not just name), checksummed, and monitored for unexpected changes (auto-update poisoning). The operator can pin skill versions to prevent silent updates. The system maintains an allowlist of approved skills and rejects any skill not on the list.

The AI agent platform runtime itself is also version-pinned. The installed platform version is recorded in the integrity manifest so that unexpected platform updates are detected.

**Why this priority**: 341 malicious skills were found on the community marketplace in January 2026. The platform's current moderation (regex pattern matching, GitHub account age checks) is easily bypassed. Even legitimate skills can be compromised via account takeover and malicious updates (T-PERSIST-002). Operator-controlled allowlisting eliminates reliance on marketplace moderation.

**Independent Test**: Attempt to install a skill not on the allowlist. Verify installation is rejected. Add a skill to the allowlist and install it. Verify the skill's checksum is recorded. Modify the installed skill file. Verify the next audit detects the change.

**Acceptance Scenarios**:

1. **Given** a skill allowlist is configured, **When** the agent attempts to use a skill not on the list, **Then** the skill is not loaded.
2. **Given** a skill is on the allowlist and installed, **When** the skill file is modified (simulating a malicious update), **Then** the integrity check detects the change and alerts the operator.
3. **Given** the operator wants to add a new skill, **When** they add it to the allowlist (by content hash) and run the install command, **Then** the skill is installed and its checksum is recorded in the manifest.
4. **Given** the agent is configured with version pinning, **When** a skill update is available, **Then** the update is not applied until the operator explicitly approves it.
5. **Given** the platform runtime version changes unexpectedly, **When** the audit runs, **Then** it detects the version mismatch and reports FAIL.

---

### User Story 5 — Security Audit Verifies All Isolation and Integrity Controls (Priority: P5)

The existing security audit is extended to verify all new controls in a single pass. The operator runs `make audit` and receives a comprehensive report covering workspace file integrity, sandbox configuration, tool restrictions, monitoring service status and heartbeat, skill allowlist compliance, file lock status, symlink detection, and platform version verification. Every new control has a corresponding audit check that produces a clear PASS/FAIL/WARN result.

**Why this priority**: Verification is the proof that controls work. Without auditable checks, controls degrade silently. This story ensures every defense layer from US1-US4 is continuously verifiable via the existing audit framework.

**Independent Test**: Deploy all controls. Run `make audit`. Verify all new checks pass. Deliberately weaken one control (e.g., disable sandbox mode). Re-run audit. Verify the corresponding check fails.

**Acceptance Scenarios**:

1. **Given** all controls are properly deployed, **When** the operator runs the security audit, **Then** all new integrity and isolation checks pass.
2. **Given** sandbox mode is disabled, **When** the audit runs, **Then** the sandbox configuration check reports FAIL.
3. **Given** a workspace file is unlocked (writable), **When** the audit runs, **Then** the file lock check reports WARN with the specific file identified.
4. **Given** the monitoring service is not running or its heartbeat is stale, **When** the audit runs, **Then** the monitoring check reports FAIL.
5. **Given** a skill not on the allowlist is present in the agent workspace, **When** the audit runs, **Then** the skill allowlist check reports FAIL.
6. **Given** a symlink exists in a protected directory, **When** the audit runs, **Then** the symlink check reports FAIL with the symlink path identified.

---

### Edge Cases

- What happens when the operator forgets to re-lock files after editing? The audit warns, and the monitoring service alerts after the per-file grace period expires (default: 5 minutes). Alert suppression is scoped to the specific unlocked file only.
- What happens when a macOS update clears immutable flags? The startup integrity check catches this before the agent loads modified files. The monitoring service alerts in real time. Flags are re-applied on next `make integrity-lock`.
- What happens when the agent legitimately needs to write a file (e.g., pending-drafts.json)? A designated writable data directory exists outside the protected workspace. Protected files (instructions) and mutable data (drafts, state) are separated. Data files loaded at startup (e.g., pending-drafts.json) are validated for structural integrity before loading — they cannot contain arbitrary content that would be treated as instructions.
- What happens when Docker volumes are modified outside the container? Volume integrity is checked by comparing exported workflow JSON against the version-controlled copies in the repository. Structural comparison ignores benign metadata differences (IDs, timestamps).
- What happens when the manifest itself is tampered with? The manifest is signed with a key stored in the macOS Keychain. The signing key is accessible only to the operator's user account. An attacker who can read the Keychain already has full user-level access — the manifest signing protects against offline tampering (boot from USB, external drive) and non-authenticated local processes, not against root or same-user Keychain access. This is documented as an accepted residual risk.
- What happens when the operator needs to deploy updated workspace files from the repository? The deploy command verifies the git working tree is clean and on an expected branch, computes fresh checksums, updates the signed manifest, and sets immutable flags. The operation is idempotent — safe to re-run if interrupted.
- What happens when an attacker creates a symlink from the writable data directory into the protected workspace? The lock command and integrity check verify no symlinks exist in protected directories. The writable data directory is checked for symlinks pointing outside its scope.
- What happens when environment variables are manipulated (e.g., LD_PRELOAD, NODE_OPTIONS)? The startup integrity check verifies that dangerous environment variables are unset or contain expected values before launching the agent.
- What happens when the agent's conversation history database is poisoned? Agent session transcripts and conversation history are outside the scope of this spec (they are platform-managed state). This is documented as an accepted residual risk — the platform's own session management is the trust boundary for conversation integrity.

## Requirements

### Functional Requirements

**Filesystem Immutability (Prevent)**

- **FR-001**: System MUST set operating system immutable flags (requiring elevated privileges to clear) on all protected files after deployment, preventing modification by any non-root process.
- **FR-002**: System MUST provide explicit unlock and lock commands (requiring elevated privileges) for the operator to make intentional edits to protected files.
- **FR-003**: System MUST automatically re-lock files, update checksums, and re-sign the manifest when the lock command is executed.
- **FR-004**: System MUST protect the following file categories: agent workspace files (SOUL.md, AGENTS.md, TOOLS.md, IDENTITY.md, USER.md, BOOT.md), skill definitions (SKILL.md), orchestration files (CLAUDE.md), workflow definitions (workflows/*.json), deployment scripts (scripts/*.sh), Docker configuration (docker-compose.yml, n8n-entrypoint.sh), encryption keys (secrets/*.txt), and configuration files (openclaw.json, .env files containing secrets).
- **FR-005**: System MUST verify no symlinks exist in protected directories during lock, deploy, and audit operations.
- **FR-006**: System MUST verify the git working tree is clean and on an expected branch before deploying workspace files from the repository.

**Agent Sandbox Isolation (Contain)**

- **FR-007**: System MUST run the primary agent with filesystem access restricted to its workspace directory only.
- **FR-008**: System MUST run the primary agent with read-only workspace access, preventing writes to instruction files.
- **FR-009**: System MUST run the extraction agent (feed-extractor) with zero tools, zero skills, and no workspace write access.
- **FR-010**: System MUST restrict the primary agent's tool access to an explicit allowlist, denying exec, process, and browser tools.
- **FR-011**: System MUST provide a designated writable data directory (outside the protected workspace) for legitimate agent state (pending drafts, session data).
- **FR-012**: System MUST validate the structural integrity of data files loaded from the writable directory at startup (e.g., pending-drafts.json must conform to expected schema).
- **FR-013**: System MUST verify sandbox configuration is active before allowing agent operations that interact with external services.

**Integrity Verification (Detect)**

- **FR-014**: System MUST verify checksums of all protected files before the agent loads workspace files on startup. The verification script MUST launch the agent directly after passing, eliminating any window between verification and file loading.
- **FR-015**: System MUST refuse to start the agent if any protected file fails its integrity check.
- **FR-016**: System MUST sign the manifest with a key stored in the macOS Keychain, preventing manifest-and-file co-tampering by processes without Keychain access.
- **FR-017**: System MUST include CLAUDE.md, workflow JSON files, deployment scripts, and configuration files in the integrity manifest alongside workspace files.
- **FR-018**: System MUST compare exported n8n workflow JSON against version-controlled copies using structural comparison (ignoring benign metadata differences) to detect in-container workflow tampering.
- **FR-019**: System MUST verify that dangerous environment variables (LD_PRELOAD, DYLD_INSERT_LIBRARIES, NODE_OPTIONS) are unset or contain expected values at agent startup.
- **FR-020**: System MUST record the installed platform runtime version in the integrity manifest and detect unexpected version changes.

**Real-Time Monitoring (Respond)**

- **FR-021**: System MUST continuously monitor all protected files for modifications using a background service managed by the operating system's process supervisor (auto-restart on crash).
- **FR-022**: System MUST alert the operator via chat within 60 seconds of detecting an unauthorized file modification.
- **FR-023**: System MUST scope alert suppression to specific files during intentional edit windows, with a configurable timeout (default: 5 minutes). Other files remain monitored.
- **FR-024**: System MUST write a heartbeat file at regular intervals. The startup integrity check and audit MUST verify the heartbeat is recent.
- **FR-025**: System MUST re-verify file checksums (not just filesystem events) when a modification event is detected, catching transient modify-and-restore attacks.

**Supply Chain Controls (Prevent)**

- **FR-026**: System MUST maintain an operator-controlled allowlist of approved skills, identified by content hash.
- **FR-027**: System MUST reject loading any skill not present on the allowlist.
- **FR-028**: System MUST record content hashes of all installed skills in the integrity manifest.
- **FR-029**: System MUST detect when an installed skill's content hash changes (auto-update poisoning detection).

**Audit Extension (Verify)**

- **FR-030**: Security audit MUST verify immutable flag status on all protected files.
- **FR-031**: Security audit MUST verify sandbox mode is enabled and correctly configured.
- **FR-032**: Security audit MUST verify tool restrictions are enforced per agent.
- **FR-033**: Security audit MUST verify real-time monitoring service is running and heartbeat is recent.
- **FR-034**: Security audit MUST verify all installed skills are on the allowlist (by content hash).
- **FR-035**: Security audit MUST verify the integrity manifest signature is valid.
- **FR-036**: Security audit MUST verify no symlinks exist in protected directories.
- **FR-037**: Security audit MUST verify the installed platform runtime version matches the expected version in the manifest.

### Key Entities

- **Protected File**: A file subject to immutability controls and integrity verification. Includes workspace files, orchestration files, configuration files, and deployment artifacts. Excludes agent session data and conversation history (platform-managed state).
- **Integrity Manifest**: A signed document containing SHA-256 checksums of all protected files and the platform runtime version. The manifest signature uses a key stored in the macOS Keychain.
- **Sandbox Configuration**: The set of restrictions applied to an agent's runtime environment: filesystem access scope (workspace-only), workspace access mode (read-only), and tool allowlist (deny exec, process, browser).
- **Skill Allowlist**: An operator-maintained list of approved skills, identified by content hash. Skills not matching a known hash are rejected at load time.
- **File Lock State**: The immutability status of a protected file — locked (immutable flag set, requires elevated privileges to clear) or unlocked (writable, per-file grace period with timeout).
- **Monitoring Service**: A background process managed by the OS process supervisor that watches protected files for modifications, writes heartbeat, and generates alerts. Runs independently of the agent process.
- **Writable Data Directory**: A designated directory for legitimate agent state (pending drafts, session data) that is NOT protected by immutable flags but IS validated for structural integrity at startup.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Zero protected files can be modified by the agent process or any non-root process when locks are active.
- **SC-002**: Agent startup integrity check adds less than 500ms to agent startup time.
- **SC-003**: Unauthorized file modifications are detected and alerted within 60 seconds of occurrence.
- **SC-004**: Security audit covers all new controls with zero manual verification steps — fully automated PASS/FAIL.
- **SC-005**: Normal operator workflow (chat, draft, approve, publish) operates without disruption when all controls are active.
- **SC-006**: The agent cannot read files outside its designated workspace when sandbox mode is active.
- **SC-007**: The extraction agent cannot invoke any tools or write any files under any circumstances.
- **SC-008**: All controls survive a normal system restart — immutable flags, manifest, sandbox configuration, and monitoring service persist without manual re-application.
- **SC-009**: Intentional workspace updates (deploy, edit, lock) complete in under 30 seconds including checksum recomputation and manifest signing.

## Assumptions

- macOS system immutable flags are available and enforced on the target system (macOS Sonoma/Tahoe, Intel). Setting and clearing the flag requires elevated privileges.
- The AI agent platform's native sandbox mode (read-only workspace, tool restrictions, workspace-only filesystem access) is functional on the current version (verified: v2026.3.13 supports sandbox.mode, workspaceAccess, tools.fs.workspaceOnly, per-agent tool allow/deny lists).
- The macOS Keychain is accessible to the operator's user account for manifest signing key storage. Keychain access does not protect against root-level or same-user attacks — this is an accepted residual risk, documented in edge cases.
- Filesystem monitoring tools are available via the system package manager.
- The agent's legitimate state files (pending drafts, session data) can be stored in a separate writable directory without breaking agent functionality.
- Docker volumes can be inspected by exporting and comparing workflow JSON against version-controlled copies.
- Agent conversation history and session transcripts are platform-managed state outside the scope of this spec. Conversation integrity is the platform's responsibility.

## Accepted Residual Risks

| Risk | Severity | Rationale |
| --- | --- | --- |
| Root-level file modification | Medium | Immutable flags prevent non-root modification. Root bypass is detected by integrity verification (US3). Full root compromise is a platform-level threat mitigated by macOS hardening (M2 baseline). |
| Keychain-stored manifest key accessible to same user | Low | Protects against offline tampering and non-authenticated processes. Same-user Keychain access requires the attack to already have the operator's session — game-over for most threat models. |
| Conversation history/session tampering | Medium | Platform-managed state. The platform's own session integrity mechanisms apply. Modifying conversation history could inject context but cannot modify workspace files (US1) or bypass sandbox restrictions (US2). |
| Transient file modifications between filesystem events | Low | Monitoring re-verifies checksums on events (FR-025), catching most transient attacks. Sub-second modify-and-restore is theoretically possible but not practical for meaningful content injection. |

## Threat Traceability

Every functional requirement traces to a named threat:

| Requirement | Threat | Source |
| --- | --- | --- |
| FR-001 to FR-006 | Agent Configuration Tampering (T-PERSIST-003), symlink/hardlink attacks | Platform Threat Model (MITRE ATLAS), adversarial review finding #6 |
| FR-007 to FR-013 | Compromised skill with filesystem access, writable data injection | OWASP AI Agent Security, community marketplace incident (341 skills, Jan 2026), adversarial review finding #7 |
| FR-014 to FR-020 | Silent file modification between audits, TOCTOU race, env var manipulation, platform supply chain | Gap analysis, adversarial review findings #3, #9, #12 |
| FR-021 to FR-025 | Privilege escalation bypassing immutable flags, monitor tampering, transient attacks | Defense in depth, adversarial review findings #8, #14 |
| FR-026 to FR-029 | Skill Update Poisoning (T-PERSIST-002) | Platform Threat Model (residual risk: HIGH) |
| FR-030 to FR-037 | Controls degrade silently without verification | Constitution V: Every recommendation is verifiable |

## Adversarial Review Summary

29 findings from adversarial review. Disposition:

| Finding | Severity | Disposition |
| --- | --- | --- |
| #1: Sandbox mode may not exist | CRITICAL | **Resolved**: Verified present in OpenClaw v2026.3.13 |
| #2: chflags privilege model undefined | CRITICAL | **Resolved**: Privilege model documented in US1. Uses system immutable flag requiring elevated privileges. |
| #3: TOCTOU race between check and load | CRITICAL | **Resolved**: FR-014 requires verification script to launch agent directly. |
| #4: Agent memory/config/env unprotected | CRITICAL | **Resolved**: FR-004 expanded to include openclaw.json and .env. Conversation history documented as accepted residual risk. |
| #5: Manifest signing key vague | HIGH | **Resolved**: Keychain specified. Residual risk documented. |
| #6: Symlink/hardlink attacks | HIGH | **Resolved**: FR-005, FR-036 added. |
| #7: Writable data dir injection | HIGH | **Resolved**: FR-012 added (structural validation of data files). |
| #8: Monitor tamper resistance | HIGH | **Resolved**: FR-021 (OS process supervisor), FR-024 (heartbeat). |
| #9: Environment variable manipulation | HIGH | **Resolved**: FR-019 added. |
| #10: chflags not a hard boundary | HIGH | **Resolved**: US1 reframed honestly. Residual risk documented. |
| #11: n8n workflow tampering detection weak | HIGH | **Resolved**: FR-018 uses structural comparison. Accepted trade-off. |
| #12: Platform runtime supply chain | HIGH | **Resolved**: FR-020, FR-037 added (version pinning and audit). |
| #13: SC-008 underspecified | MEDIUM | **Resolved**: Clarified to "normal system restart." |
| #14: 60s detection window | MEDIUM | **Resolved**: FR-025 adds checksum re-verification on events. |
| #15: Alert suppression attack window | MEDIUM | **Resolved**: FR-023 scoped to per-file, 5-min timeout. |
| #16: Skill identity by name only | MEDIUM | **Resolved**: FR-026 uses content hash. |
| #17: config-update as privileged skill | MEDIUM | **Resolved**: US2 narrative updated. Tool restrictions cover API-calling skills. |
| #18: Extraction agent invocation model | MEDIUM | **Resolved**: US2 specifies sub-agent via internal mechanism, not network. |
| #19: Immutable keys block rotation | MEDIUM | **Accepted**: Operational procedure documented in edge cases. |
| #20: False atomicity claim | MEDIUM | **Resolved**: Changed to "idempotent" in edge cases. |
| #21: No process-level isolation (UID) | MEDIUM | **Deferred**: Running as dedicated user is a potential future enhancement. Sandbox mode provides the isolation layer for now. |
| #22: Container credential exfiltration | MEDIUM | **Accepted**: N8N_BLOCK_ENV_ACCESS_IN_NODE=false is a documented trade-off from M3. |
| #23: Monitoring may be over-engineering | MEDIUM | **Kept**: Defense in depth is a stated design principle. Startup check + continuous monitoring serve different scenarios. |
| #24: Checklist claims no implementation details | LOW | **Resolved**: Acknowledged platform-specific references. |
| #25: SC-002 trivially achievable | LOW | **Resolved**: Changed to "adds less than 500ms." |
| #26: SC-010 unverifiable | LOW | **Resolved**: Removed. Replaced with residual risk register. |
| #27: No log integrity | LOW | **Deferred**: Out of scope. Noted for future work. |
| #28: FileVault initial unlock timing | LOW | **Noted**: Monitoring service should be user-level (starts after login). |
| #29: Git source verification | LOW | **Resolved**: FR-006 added. |
