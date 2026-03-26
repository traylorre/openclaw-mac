# Feature Specification: Security Remediation & Hardening Depth (Phase 4)

**Feature Branch**: `012-security-hardening-phase2` (Phase 4 sub-spec)
**Created**: 2026-03-26
**Status**: Draft
**Input**: 43 adversarial review findings from Phases 3/3B, comprehensive sensitive files inventory, and 2026 threat intelligence synthesis (OWASP Agentic Top 10, CSA Agentic Trust Framework, TEA/TSP gap analysis, OpenClaw/n8n CVE landscape, CaMeL architecture research).
**Supersedes**: None (new remediation phase; parent phases 3/3B remain authoritative for their scope).
**Adversarial Review**: 33 findings (2 CRITICAL, 9 HIGH, 12 MEDIUM, 8 LOW). All CRITICALs and HIGHs addressed in this revision.
**Scope**: All FRs apply to BOTH one-shot tool invocations AND the `integrity-monitor.sh` daemon loop unless explicitly noted otherwise.
**Platform**: macOS Ventura (22.6.0). `setsid` is NOT available — bash `set -m` (job control) used for process group creation instead.
**Trust Boundary**: The verification pipeline assumes Docker daemon integrity. If the daemon is compromised, all container verification results are UNKNOWN (not PASS). This limitation is documented in verification output.
**Multi-User**: The integrity system assumes single-user operation. Cross-user state sharing is not supported.

---

## User Scenarios & Testing

### User Story 1 — Fail-Fast Verification Cascade (Priority: P1)

The operator runs integrity verification and, when a high-trust check fails (e.g., container image digest mismatch), all downstream partial-trust checks abort immediately rather than continuing on stale or invalid state. Currently, if the container disappears between discovery and verification, downstream checks (credential enumeration, workflow comparison, drift detection) continue executing against a dead container ID, producing misleading results. The system must treat verification as an ordered pipeline where each tier gates the next.

**Why this priority**: The adversarial review's most critical finding is that 7 verification layers run independently even when layer 1 has already failed. This violates the core principle of defense in depth — layers must cascade, not run in parallel on potentially invalid assumptions. A PASS result when the container has vanished is worse than no result at all.

**Independent Test**: Start the container. Begin verification. Kill the container during the image digest check. Verify that all downstream checks (runtime config, credentials, workflows, drift, community nodes) are skipped and the overall result is FAIL with a clear message indicating the cascade abort reason.

**Acceptance Scenarios**:

1. **Given** the container image digest check fails (mismatch or container unreachable), **When** the verification pipeline proceeds, **Then** all downstream container checks (runtime config, credentials, workflows, drift, community nodes) are skipped with status "SKIPPED: upstream check failed" and the overall result is FAIL.
2. **Given** the container disappears between ID pinning and a subsequent check, **When** any `docker inspect` or `docker exec` call returns an error indicating the container no longer exists, **Then** the current check immediately returns FAIL, all remaining checks are skipped, and the audit log records "container_vanished" with the pinned container ID and the check that detected the absence.
3. **Given** a non-critical check fails (e.g., community node enumeration), **When** the verification pipeline continues, **Then** subsequent checks of equal or lower trust tier still execute, but the overall result reflects the failure.
4. **Given** verification completes with all checks passing, **When** the final re-verification confirms the container is still running with the same ID, **Then** the result is PASS. If the container ID changed during verification, the result is FAIL with "container_replaced_during_verification."

---

### User Story 2 — Atomic File Operations with Symlink Protection (Priority: P1)

The operator can trust that state files (manifest, lock-state, container-security-config, container-verify-state, audit log) are written atomically and are immune to symlink attacks. Currently, mktemp+chmod sequences have a TOCTOU window where an attacker with local access could replace the temp file with a symlink before the chmod, causing the state data to be written to an attacker-controlled path. All file write operations in the integrity library must use symlink-safe atomic writes.

**Why this priority**: State files control the integrity system's own behavior. If an attacker can redirect a state file write to a different path (e.g., overwriting `~/.ssh/authorized_keys`), the integrity system itself becomes the attack vector. The adversarial review identified this pattern in 4 separate locations.

**Independent Test**: Create a symlink at the temp file path before the atomic write. Verify the write detects the symlink and aborts rather than following it. Verify the state file retains its previous content. Verify the error is logged to the audit trail.

**Acceptance Scenarios**:

1. **Given** the integrity library writes a state file, **When** the atomic write creates a temp file, **Then** it uses `umask 077` before `mktemp` to ensure the temp file is created with owner-only permissions, and validates the created file is NOT a symlink before writing content.
2. **Given** an attacker replaces the temp file with a symlink between creation and the write operation, **When** the write detects the symlink (via `-L` check), **Then** it aborts the write, removes the symlink, logs "symlink_attack_detected" to the audit trail with the symlink target path, and returns a non-zero exit code.
3. **Given** an atomic write fails (disk full, permissions changed), **When** the error is detected, **Then** the temp file is cleaned up via trap-based cleanup (not just error-path cleanup), the original state file is not corrupted, and the failure is logged.
4. **Given** the parent directory of a state file is a symlink, **When** the integrity library initializes, **Then** it detects the directory symlink and refuses to operate, logging "directory_symlink_detected" with the path and target.

---

### User Story 3 — Process Group Isolation for Security Tools (Priority: P1)

The operator runs the security pipeline (`make security`) and each security tool layer (integrity verification, CIS benchmark, n8n audit, image scan) runs in an isolated process group. If a tool hangs, is compromised, or attempts a fork bomb, the timeout mechanism kills the entire process tree — not just the parent process. Currently, `kill $pid` in the timeout function only kills the parent, leaving child processes (including potential fork bombs) running.

**Why this priority**: The security pipeline executes external tools (docker-bench-security from git clone, grype binary, docker exec into potentially compromised containers). If any tool is compromised, it could spawn children that survive the timeout and consume system resources or exfiltrate data. The timeout must be authoritative — nothing survives it.

**Independent Test**: Create a test script that spawns 10 child processes with `sleep 3600`. Run it through the timeout function with a 5-second timeout. Verify that after the timeout fires, zero descendant processes remain (check via `pgrep -P`).

**Acceptance Scenarios**:

1. **Given** a security tool layer starts execution, **When** the timeout wrapper launches it, **Then** the tool runs in its own process group (via bash `set -m` + background launch on macOS) with a unique PGID. The monitor daemon's `_container_monitor_cycle` MUST also run through `integrity_run_with_timeout` with the existing `CONTAINER_POLL_TIMEOUT`.
2. **Given** a tool exceeds its timeout, **When** the watchdog fires, **Then** it sends SIGTERM to the entire process group (`kill -TERM -$pgid`), waits 2 seconds, then sends SIGKILL to any survivors (`kill -KILL -$pgid`). All descendants are terminated.
3. **Given** a tool spawns child processes that ignore SIGTERM, **When** the watchdog escalates to SIGKILL, **Then** all processes in the group are terminated (SIGKILL cannot be caught or ignored).
4. **Given** the tool completes successfully before the timeout, **When** the watchdog is still running, **Then** the watchdog is cleaned up (killed) and no orphaned watchdog processes remain.

---

### User Story 4 — Output Bounding and JSON Validation Gate (Priority: P1)

The operator can trust that all external tool output (docker exec, curl, git-cloned scripts) is bounded in size, validated for format before parsing, and that parse failures produce explicit errors rather than silent false negatives. Currently, `docker exec` output is unbounded (OOM risk), and jq parse failures across all security tools default to `echo 0` via `2>/dev/null || echo 0`, producing false "0 findings" results.

**Why this priority**: Silent false negatives are the worst outcome for a security tool. The operator believes the system is checking 5 categories of risk but the tool silently failed on 3 of them and reported "0 findings" for each. The adversarial review found this pattern in container-bench.sh, n8n-audit.sh, and scan-image.sh — all three security tool wrappers.

**Independent Test**: Feed invalid JSON to each security tool wrapper AND to the monitor's API response parser. Verify all report a parse error and exit with a non-zero code rather than reporting "0 findings." Feed output exceeding 1MB to a docker exec wrapper. Verify it is truncated and the truncation is logged. This applies to 3 here-string credential exposures (integrity.sh:840, integrity-verify.sh:687, integrity-monitor.sh:304) and all `docker exec` calls in both one-shot and daemon contexts.

**Acceptance Scenarios**:

1. **Given** any `docker exec` call runs against the orchestration container, **When** the output is captured, **Then** it is piped through a size limiter (1MB default, configurable) and a timeout wrapper (30 seconds default, configurable). If either limit is hit, the call fails with an explicit error including the limit that was exceeded.
2. **Given** any external tool produces JSON output, **When** the output is parsed, **Then** a JSON validation gate (`jq -e empty`) runs first. If validation fails, the tool exits with a non-zero code and logs "json_validation_failed" with the tool name and the first 200 characters of raw output. The tool MUST NOT default to "0 findings."
3. **Given** curl returns an HTML error page (e.g., n8n not ready) instead of JSON, **When** the credential enumeration parses the response, **Then** the jq validation gate catches the non-JSON response, reports the error, and the check result is UNKNOWN (not PASS).
4. **Given** the docker-bench-security JSON output is missing expected fields, **When** the wrapper parses it, **Then** the wrapper validates the presence of required fields (`.tests`, `.results`) before counting findings. Missing fields produce an error, not a default of 0.
5. **Given** the `---PKG_DELIMITER---` string appears inside a package.json file (attacker-controlled content), **When** the community node parser encounters it, **Then** the parser uses a delimiter that cannot appear in valid JSON (e.g., a null byte separator or length-prefixed framing) or validates each parsed segment is valid JSON before processing.

---

### User Story 5 — Supply Chain Verification for Security Tools (Priority: P2)

The operator can trust that the security tools used to audit the system have not themselves been tampered with. Docker-bench-security is cloned from GitHub without commit hash verification — an attacker who compromises the GitHub repo or performs a MITM attack can substitute a malicious script that reports "all PASS." Grype's version is checked but the binary hash is not verified — a compromised binary could suppress CVE findings.

**Why this priority**: A security tool that lies is worse than no security tool. If docker-bench-security always reports PASS, the operator develops false confidence and stops manually checking. The March 2026 Trivy supply chain attack demonstrated this exact pattern — the compromised tool was trusted because it was "the security scanner."

**Independent Test**: Clone docker-bench-security with the pinned commit hash. Modify one file in the clone. Run container-bench.sh. Verify it detects the hash mismatch and refuses to run the modified script. Restore the original. Verify it runs successfully.

**Acceptance Scenarios**:

1. **Given** docker-bench-security is cloned from GitHub, **When** the clone completes, **Then** the script verifies the HEAD commit hash matches a pinned expected hash stored in the integrity library. If the hash does not match, the clone is deleted and the check exits with "supply_chain_verification_failed."
2. **Given** the docker-bench-security clone already exists from a previous run, **When** container-bench.sh runs again, **Then** it re-verifies the commit hash before execution. A stale clone with the wrong hash is deleted and re-cloned.
3. **Given** the Grype binary is installed, **When** scan-image.sh runs, **Then** it enforces an exact version match (not prefix match) and verifies the binary's SHA-256 hash against a pinned expected hash. Version mismatch or hash mismatch blocks execution with "tool_integrity_failed."
4. **Given** the pinned hashes need updating (new tool version), **When** the operator runs a hash update command, **Then** the new hashes are recorded in the HMAC-signed container security config and the update is logged to the audit trail.
5. **Given** a network error prevents cloning docker-bench-security, **When** the clone fails, **Then** the tool exits with a clear error. It MUST NOT fall back to a previously cloned copy without hash verification.

---

### User Story 6 — Protection Surface Expansion (Priority: P2)

The operator's sensitive files are comprehensively protected based on a systematic inventory of all files that influence agent behavior, contain secrets, or control the integrity system itself. Currently, several critical files are missing from the protected files list or have overly permissive permissions.

**Why this priority**: The Phase 1A expansion brought the protected file count from 49 to 77, but a comprehensive inventory revealed gaps. The most critical: `.git/config` (which controls where code is pushed) and `n8n/workflows/*.json` (which define what the orchestrator executes) are not in the protected list. An attacker who modifies `.git/config` can exfiltrate the entire codebase to a controlled remote.

**Independent Test**: Run integrity verification. Modify `.git/config` to point to a different remote. Verify the modification is detected by the next verification cycle. Restore the original. Verify verification passes.

**Acceptance Scenarios**:

1. **Given** the protected files list is enumerated, **When** integrity verification runs, **Then** the following additional files are included:
   - `.git/config` (VCS remote URLs — code exfiltration vector)
   - `n8n/workflows/*.json` (orchestration workflow definitions, if directory exists)
   - `.specify/memory/constitution.md` (agent automation framework control, if file exists)
2. **Given** `scripts/templates/secrets/n8n_encryption_key.txt` exists, **When** permission verification runs, **Then** it verifies the file has mode 600 (owner-only). If permissions are more permissive (e.g., 644), the check fails with "secret_file_overly_permissive" and reports the current permissions.
3. **Given** `~/.openclaw/logs/` or `~/.openclaw/reports/` directories exist, **When** permission verification runs, **Then** it verifies the directories have mode 700 (owner-only). If more permissive, the check warns "audit_data_world_readable" with the current permissions.
4. **Given** any file in the protected list has changed its permissions since the last verification, **When** the next verification runs, **Then** the permission change is detected and reported separately from content changes.

---

### User Story 7 — Command Injection Prevention in Security Pipeline (Priority: P1)

The operator can trust that the security pipeline's internal orchestration is immune to command injection. Currently, the `$cmd` variable in security-pipeline.sh is passed unquoted to `bash`, enabling word splitting and glob expansion. Additionally, sed-based parsing of untrusted n8n audit output accepts injected JSON, and audit log parameters allow log injection via unvalidated action strings.

**Why this priority**: Command injection in the security pipeline is ironic and critical — the tool designed to find security issues is itself vulnerable to the most basic web application attack (OWASP A1). The unquoted variable is a one-character fix (`"$cmd"`) but the pattern extends to several locations.

**Independent Test**: Set a layer command to a string containing spaces and glob characters. Run the security pipeline. Verify the command is treated as a single argument (not split). Verify the pipeline does not expand `*` or `?` characters in command paths.

**Acceptance Scenarios**:

1. **Given** the security pipeline iterates over layer commands, **When** it passes a command to `bash`, **Then** the command variable is properly quoted (`"$cmd"`) to prevent word splitting and glob expansion.
2. **Given** the n8n audit tool receives output from the container, **When** it extracts JSON from the raw output, **Then** it uses `jq` with strict validation (not `sed`) to extract the first valid JSON object or array. If no valid JSON is found, the tool fails with "no_valid_json_in_output."
3. **Given** the audit log function receives an action parameter, **When** the parameter is written to the log, **Then** the action is validated against a strict allowlist of known action strings (`^[a-z][a-z0-9_]{2,48}$`). Invalid actions are rejected with an error, not written.
4. **Given** the audit log function receives a details parameter, **When** the parameter is written, **Then** newlines and control characters are stripped or escaped to prevent JSONL injection (one JSON object per line invariant maintained).
5. **Given** a Docker container name pattern is validated, **When** the pattern is used in a `docker ps --filter` argument, **Then** the validation regex enforces `^[a-zA-Z][a-zA-Z0-9_-]{0,63}$` (starts with letter, max 64 chars, alphanumeric plus hyphen/underscore only — no dots, which Docker interprets as regex).

---

### User Story 8 — Credential Exposure Remediation (Priority: P2)

The operator's API keys and secrets are never exposed via process listings, temporary files, or overly permissive file permissions. Currently, bash here-strings (`<<<`) create temporary files that briefly contain the API key and are visible via `lsof`. The n8n encryption key file has 644 permissions (world-readable).

**Why this priority**: API key exposure in `ps` output or temp files is a common real-world attack vector. AWS has documented multiple incidents where credentials were harvested from process listings on shared systems. While this deployment runs on a single-user Mac, defense in depth requires eliminating exposure vectors regardless of current threat model.

**Independent Test**: Run the credential enumeration function. During execution, check `lsof` for any temp files containing API key material. Verify none exist. Check `ps` output for any command lines containing API key strings. Verify none exist.

**Acceptance Scenarios**:

1. **Given** the integrity system needs to pass an API key to curl, **When** it constructs the curl command, **Then** it writes the key to a temp file with mode 600, passes the file via `curl --config <file>`, and deletes the file immediately after curl completes (via trap-based cleanup, not just sequential delete).
2. **Given** the temp config file is created, **When** it exists on disk, **Then** it is created in `~/.openclaw/tmp/` (not `/tmp`), the directory has mode 700, and the file is never readable by other users.
3. **Given** `scripts/templates/secrets/n8n_encryption_key.txt` exists, **When** the integrity system verifies file permissions, **Then** it checks the file has mode 600. If the file has mode 644 (current state), the fix script corrects it to 600 and logs the change.
4. **Given** `~/.openclaw/logs/` and `~/.openclaw/reports/` directories exist, **When** the integrity system verifies directory permissions, **Then** it checks they have mode 700. If more permissive, the fix script corrects them and logs the change.

---

### User Story 9 — Audit Log Integrity Hardening (Priority: P2)

The operator can trust that the audit log's hash chain remains valid under concurrent access, that write failures are detected (not silently ignored), and that log injection attacks are prevented. Currently, the mkdir-based lock has a TOCTOU race where two processes can both acquire the lock, the chmod on the log file silently ignores failures, and the action parameter is not validated against an allowlist.

**Why this priority**: The audit log is the forensic record. If its integrity can be silently compromised (hash chain broken by concurrent writes, or fake entries injected via log injection), the operator loses the ability to reconstruct what happened during an incident. The adversarial review found 3 separate vulnerabilities in the audit log subsystem.

**Independent Test**: Run two verification processes concurrently. Verify the hash chain remains valid after both complete. Attempt to write an audit entry with an action containing newlines. Verify the newlines are stripped and the JSONL invariant (one object per line) is maintained.

**Acceptance Scenarios**:

1. **Given** two processes attempt to write to the audit log simultaneously, **When** the locking mechanism is invoked, **Then** only one process acquires the lock at a time. The lock uses atomic mkdir with immediate trap-based cleanup on all exit paths (normal, error, signal). The stale lock detection uses a PID-based liveness check (check if the PID recorded in a lockfile is still running) rather than age-based detection (which has a TOCTOU race).
2. **Given** an audit log entry is written, **When** the write completes, **Then** the entry is flushed to disk. If the flush fails, the function returns non-zero and the calling code detects the failure.
3. **Given** the chmod on the audit log file fails, **When** the failure is detected, **Then** it is logged to stderr and the function returns non-zero. The `|| true` suppression is removed.
4. **Given** the action parameter contains characters outside the allowlist, **When** the audit log function validates it, **Then** the write is rejected with an error. Valid actions match `^[a-z][a-z0-9_]{2,48}$`.
5. **Given** the details parameter contains newline characters, **When** the audit log function processes it, **Then** newlines are replaced with spaces (or escaped as `\n`) to maintain the JSONL one-object-per-line invariant.

---

### Edge Cases

- What happens when the container is paused (not stopped) during verification? The system should detect paused state via `docker inspect` `.State.Paused` and treat it as a verification failure.
- What happens when Docker daemon itself is unresponsive? All Docker API calls should have timeouts. Daemon unresponsiveness produces UNKNOWN status, not PASS.
- What happens when the Keychain is locked (screen saver, sleep)? HMAC key retrieval fails. System MUST fail closed for both reads AND writes — use safe/restrictive defaults when signature cannot be verified. This is the correct security posture (a Keychain-locked state means ALL operations use safe defaults).
- What happens when disk is full during state file write? Atomic write detects the failure and preserves the previous state file. Audit log write failure is detected and reported.
- What happens when two operators run verification simultaneously on the same host? Lock contention is handled gracefully with retry and timeout, not deadlock.
- What happens when the security pipeline is interrupted (Ctrl+C, SIGTERM) mid-execution? Process group cleanup ensures no orphaned tool processes remain. Partial results are not written to state files.
- What happens when a cloned tool repository is corrupted (partial clone, disk error)? Hash verification detects the corruption and triggers a re-clone.

---

## Requirements

### Functional Requirements

**Fail-Fast Cascade**:
- **FR-001**: Verification pipeline MUST define trust tiers and execute checks in descending trust order, where failure at a higher tier skips all checks at lower tiers. Tier mapping: **HIGH** = {container existence, image digest, runtime config}; **PARTIAL** = {credential enumeration, workflow comparison}; **ADVISORY** = {drift detection, community node scan}.
- **FR-002**: Each verification check MUST validate that the pinned container ID still corresponds to a running container before performing any operation. Container absence MUST produce an immediate FAIL, not a warning.
- **FR-003**: The `fail()` function within `integrity-verify.sh` MUST support a severity parameter. CRITICAL failures MUST halt the verification pipeline (no further container checks execute). WARNING failures MUST allow the pipeline to continue but affect the overall result. This does NOT change the exit-code-based interface between security-pipeline.sh and its layer scripts.
- **FR-004**: The final re-verification at the end of the check cycle MUST compare both the container ID AND the image digest against the values captured at the start. Any change MUST produce FAIL.

**Atomic File Operations**:
- **FR-005**: All state file writes MUST use a safe atomic write function that: (a) creates temp files in `~/.openclaw/tmp/` (mode 700, owned by user — eliminates symlink TOCTOU because attacker cannot create symlinks in a 700-owned directory), (b) sets umask 077 before mktemp, (c) validates the created file is not a symlink post-creation, (d) validates the parent directory is not a symlink, (e) uses trap-based cleanup on all exit paths, (f) uses `mv` for atomic replacement. Temp files MUST NOT be created adjacent to the target file (the current `mktemp "${output_file}.XXXXXX"` pattern).
- **FR-006**: The integrity library MUST validate at initialization that `~/.openclaw/` and all parent directories are not symlinks. If any symlink is detected, all operations MUST abort with "directory_symlink_detected."

**Process Group Isolation**:
- **FR-007**: The timeout wrapper function MUST run the target command in its own process group. On macOS (where `setsid` is unavailable), this MUST use bash `set -m` (job control mode) which causes background processes to run in their own process group (PGID = PID). The existing `integrity_run_with_timeout` function in integrity.sh MUST be updated in-place — a separate timeout wrapper MUST NOT be created. Nested `set -m` contexts (timeout within timeout) MUST be validated before deployment.
- **FR-008**: On timeout, the wrapper MUST send SIGTERM to the entire process group, wait a grace period (2 seconds), then send SIGKILL to any survivors.
- **FR-009**: On normal completion, the wrapper MUST clean up the watchdog process to prevent orphans.

**Output Bounding and Validation**:
- **FR-010**: All `docker exec` invocations MUST be wrapped with a timeout (30 seconds default) and output size limit (1MB default, stdout only). The size limit MUST use `head -c 1048576` with SIGPIPE handling (trap in the wrapper). Truncation MUST be detected by checking the pipeline exit status and logged with "output_truncated."
- **FR-010a**: All Docker CLI calls (`docker inspect`, `docker ps`, `docker exec`, `docker diff`) in the integrity library AND the monitor daemon MUST use `integrity_run_with_timeout` with a 30-second default. This includes calls currently made without any timeout.
- **FR-011**: JSON parsing MUST combine validation and extraction in a single jq pass using error-raising expressions (e.g., `jq -e '.tests // error("missing .tests field")'`). A separate `jq -e empty` validation pass MUST NOT be used (doubles CPU cost, valid JSON string `"hello"` passes empty but fails field extraction silently). The pattern `2>/dev/null || echo 0` MUST NOT be used anywhere in the codebase — including integrity.sh itself (lines 352, 508, 592).
- **FR-012**: The community node package delimiter MUST be replaced with a delimiter that cannot appear in valid JSON content, or each segment MUST be validated as valid JSON before processing.
- **FR-013**: All external tool output (docker-bench, grype, n8n audit) MUST be validated for expected structure before field extraction. Missing expected fields MUST produce an error.

**Supply Chain Verification**:
- **FR-014**: Docker-bench-security MUST be pinned to a specific commit hash. After clone or on each execution, the HEAD commit hash MUST be verified against the pinned value. Hash mismatch MUST block execution.
- **FR-015**: Grype binary MUST be verified by exact version match AND SHA-256 hash of the binary. Either mismatch MUST block execution.
- **FR-016**: Pinned hashes MUST be stored in the HMAC-signed container security config. Updating pinned hashes MUST require operator action and MUST be logged to the audit trail.

**Protection Surface Expansion**:
- **FR-017**: The protected files list MUST include `.git/config` for checksum verification.
- **FR-018**: The protected files list MUST include `n8n/workflows/*.json` if the directory exists.
- **FR-019**: The protected files list MUST include `.specify/memory/constitution.md` if the file exists.
- **FR-020**: Permission verification MUST check that secret files (`scripts/templates/secrets/*`) have mode 600 and that audit directories (`~/.openclaw/logs/`, `~/.openclaw/reports/`) have mode 700.

**Command Injection Prevention**:
- **FR-021**: All variables passed to `bash` or used in command construction MUST be properly quoted to prevent word splitting and glob expansion.
- **FR-022**: The n8n audit output parser MUST use `jq` (not `sed`) to extract JSON from mixed output. It MUST validate the extracted content is a valid JSON object or array.
- **FR-023**: Audit log action parameters MUST be validated against a strict regex (`^[a-z][a-z0-9_]{2,48}$`). Invalid actions MUST be rejected.
- **FR-024**: Audit log detail parameters MUST have newlines and control characters ESCAPED (not stripped — preserves forensic content). Newlines become `\n`, tabs become `\t`, other control characters become `\uXXXX`. All detail values MUST go through jq `--arg` (which handles this escaping correctly) rather than string interpolation.
- **FR-025**: Docker container name pattern validation MUST enforce `^[a-zA-Z][a-zA-Z0-9_-]{0,63}$` — no dots (Docker regex interpretation), starts with letter, max 64 characters.

**Credential Exposure Remediation**:
- **FR-026**: API keys MUST NOT be passed via bash here-strings (`<<<`). All 3 instances MUST be fixed: (1) integrity.sh:840, (2) integrity-verify.sh:687, (3) integrity-monitor.sh:304. Keys MUST be written to a temp file with mode 600 in `~/.openclaw/tmp/` (mode 700 directory), passed via `curl --config <file>` (NOT `curl --config -` with here-string), and deleted via trap-based cleanup.
- **FR-027**: The `~/.openclaw/tmp/` directory MUST be created with mode 700 if it does not exist.
- **FR-028**: Permission verification MUST check that `scripts/templates/secrets/n8n_encryption_key.txt` has mode 600 and correct it if not.

**Audit Log Hardening**:
- **FR-029**: The audit log lock MUST use atomic mkdir with a PID lockfile written atomically inside the lock directory (`mkdir lockdir && echo $$ > lockdir/pid`). Trap-based cleanup MUST remove both the PID file and lock directory. Stale lock detection: if lock directory exists with a valid PID file, check `kill -0 $pid`; if PID is not running, lock is stale. If lock directory exists but PID file is missing or empty (crash between mkdir and PID write), treat as stale after 30-second conservative timeout.
- **FR-030**: Audit log writes MUST NOT use `chmod ... || true`. Permission failures MUST be detected and returned as errors.
- **FR-031**: Audit log writes MUST call `sync` or equivalent after append to guarantee durability.

**TMPDIR Hardening**:
- **FR-032**: TMPDIR validation MUST use a strict regex: `^(/tmp|/private/tmp|/var/folders/[a-zA-Z0-9_]{2}/[a-zA-Z0-9_]+/T)(/.*)?$` — macOS uses mixed case in `/var/folders/` subdirectories. The regex MUST reject path traversal attempts (e.g., `/var/folders/../../../tmp/evil`).

**Docker Daemon Trust Boundary**:
- **FR-033**: Verification output MUST document the trust boundary: "Container verification assumes Docker daemon integrity. Results are UNKNOWN if daemon integrity cannot be verified." The verification result JSON MUST include a `trust_assumptions` field listing assumed-trustworthy components.
- **FR-034**: Verification MUST check Docker socket permissions (should be root:staff on macOS, not world-writable) as a heuristic for daemon integrity. Socket permission failure produces a WARNING, not a hard failure.

**Monitor Daemon Coverage**:
- **FR-035**: All fixes specified in FR-005 through FR-032 MUST apply to `integrity-monitor.sh` in addition to one-shot tools. Specifically: (a) the monitor's 3 `curl --config - <<<` instances at lines ~300-310 MUST use temp file approach per FR-026, (b) all `docker exec`/`docker diff`/`docker inspect` calls in monitor loops MUST use `integrity_run_with_timeout` per FR-010a, (c) monitor's JSON parsing MUST use combined validation+extraction per FR-011, (d) monitor's heartbeat/container-poll background loops MUST be killable via process group on SIGTERM.

**HMAC Key Rotation**:
- **FR-036**: The operator MUST be able to rotate the HMAC key via a dedicated command. Key rotation MUST re-sign all state files atomically. The rotation event MUST be logged to the audit trail with the last entry signed using the old key and subsequent entries using the new key.

**Audit Log `|| echo 0` Remediation**:
- **FR-037**: The `|| echo 0` pattern in integrity.sh (lines 352, 508, 592) MUST be replaced with explicit error handling. Date parsing failures MUST produce a hard error (return 1), not silent fallback to epoch 0. Lock stat failures MUST use PID-based liveness check per FR-029.

**Security Pipeline Command Handling**:
- **FR-038**: Layer commands in security-pipeline.sh MUST be executed via `bash -c "$cmd"` (not `bash $cmd`) to preserve space-separated arguments while preventing word splitting of the command variable itself.

**Docker-bench Execution Error Handling**:
- **FR-039**: The `|| true` suppression on docker-bench-security execution MUST be removed. If the tool exits non-zero after passing supply chain verification, the result MUST be FAIL (not SKIP). A supply-chain-verified tool that crashes is more suspicious than one that is unavailable.

**N8n Audit JSON Extraction**:
- **FR-040**: The n8n audit output parser MUST identify the first line starting with `{` or `[`, extract from that line to end-of-output, then validate with combined `jq -e` extraction. If no JSON-starting line exists, report "no_valid_json_in_output." This replaces the current `sed -n '/^[{[]/,$p'` approach with a validation-gated text extraction step.

**Secret File Permission Compatibility**:
- **FR-041**: Before tightening `scripts/templates/secrets/n8n_encryption_key.txt` from 644 to 600, the system MUST verify the file is NOT bind-mounted into a Docker container that requires other-readable access. If the Docker Compose file maps the file as a volume, permissions should be 640 with group set to the Docker GID, not 600.

### Key Entities

- **Verification Pipeline**: Ordered sequence of checks with trust tiers (HIGH → PARTIAL → ADVISORY) and cascade abort semantics.
- **Safe Atomic Write**: Standardized file write operation with symlink detection, trap-based cleanup, and atomic replacement.
- **Process Group**: OS-level isolation boundary for security tool execution, enabling authoritative timeout via PGID-based signal delivery.
- **JSON Validation Gate**: Pre-parsing validation step that rejects invalid JSON before any field extraction, preventing silent false negatives.
- **Tool Hash Pin**: Cryptographic commitment (SHA-256) to a specific version of an external security tool, stored in HMAC-signed config.

---

## Success Criteria

### Measurable Outcomes

- **SC-001**: Zero silent false negatives — when any security tool parse fails, the tool reports an error (never "0 findings"). Verified by feeding invalid JSON to each wrapper and confirming non-zero exit.
- **SC-002**: Container disappearance during verification produces FAIL within 5 seconds of the container being killed, with all downstream checks skipped.
- **SC-003**: Process group timeout kills 100% of descendant processes within 5 seconds of timeout expiry. Verified by spawning a multi-level process tree and confirming zero survivors.
- **SC-004**: All 43 adversarial review findings are addressed — 6 CRITICAL, 10 HIGH, 19 MEDIUM, 8 LOW. Each fix is traceable to a specific finding and testable independently.
- **SC-005**: Protected file count increases from 77 to include all identified gaps (`.git/config`, `n8n/workflows/*.json`, `.specify/memory/constitution.md`).
- **SC-006**: No API key material appears in `ps` output or `lsof` temp file listings during any integrity operation.
- **SC-007**: Concurrent audit log writes (2 processes) maintain hash chain validity 100% of the time across 100 trials.
- **SC-008**: Docker-bench-security execution is blocked when the cloned commit hash does not match the pinned hash. Verified by modifying one file in the clone and confirming execution refusal.
- **SC-009**: All secret files have mode 600 and all audit directories have mode 700 after verification and remediation.
- **SC-010**: The TMPDIR validation rejects paths like `/var/folders/../../../tmp/evil` and accepts only legitimate macOS temp paths.
