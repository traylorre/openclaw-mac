# Feature Specification: Adversarial Review Remediation (Phase 4B)

**Feature Branch**: `013-adversarial-remediation`
**Created**: 2026-03-26
**Status**: Complete
**Input**: Adversarial review of Phase 4 security hardening code found 26 vulnerabilities (8 CRITICAL, 12 HIGH, 6 MEDIUM). The security remediation code contained the same vulnerability classes it was designed to fix.
**Parent**: `012-security-hardening-phase2` (Phase 4 implementation)
**Adversarial Review**: Phase 4 code reviewed by two independent agents. Findings cross-referenced against OWASP Agentic Top 10 (2026), NIST 800-53A controls (AU-9, SC-12, SC-39, SR-4), CaMeL isolation architecture, and production FIM systems (Wazuh, AIDE, Tripwire).
**Platform**: macOS Ventura (22.6.0), Apple Silicon, Bash 5.x, Colima + Docker.
**Scope**: All fixes apply to the integrity library, all tool wrappers, the verification pipeline, the monitor daemon, and the deployment script. Every Docker CLI invocation across the codebase must be timeout-bounded. Every credential-handling path must be trap-protected. Every exit-code-returning function must be overflow-safe.

---

## User Scenarios & Testing

### User Story 1 — Timeout Authority: No Docker Call Survives Unbounded (Priority: P1)

The operator runs any integrity operation (verify, deploy, monitor, security scan) and every Docker CLI invocation completes or fails within a bounded time. Currently, 8 Docker calls across 4 files lack timeout wrapping. A hung Docker daemon (Colima VM pause, network stall, daemon deadlock) stalls the entire pipeline indefinitely with no recovery path. The operator must hard-kill the process manually.

**Why this priority**: A hung verification pipeline is a denial of service against the security system itself. If the security tool cannot complete, the operator either skips verification (unsafe) or spends time debugging (availability impact). NIST SC-39 requires bounded execution domains. The CaMeL architecture principle — "enforcement engine validates all tool calls before execution" — requires that the enforcement engine itself cannot be stalled by a tool it is validating.

**Independent Test**: Set `DOCKER_HOST` to a non-responsive socket. Run `make integrity-verify`. Verify the pipeline completes (with errors, not hangs) within 60 seconds.

**Acceptance Scenarios**:

1. **Given** the Docker daemon is unresponsive (Colima stopped, socket deleted), **When** any integrity operation runs, **Then** every Docker CLI call times out within 30 seconds, the operation reports FAIL/SKIP with a clear error, and the process exits cleanly.
2. **Given** `docker inspect` hangs inside `integrity_capture_container_snapshot()`, **When** any caller invokes the function, **Then** the timeout fires, the process group is killed, and the caller receives a non-zero exit code within 35 seconds.
3. **Given** `docker ps` hangs inside `integrity_discover_container()`, **When** the discovery function is called, **Then** it times out and returns non-zero within 15 seconds.
4. **Given** `grype` scan runs on a large image, **When** it exceeds 5 minutes without the pipeline wrapper, **Then** the standalone scan-image.sh script times out and exits cleanly.
5. **Given** `docker info` is called as a reachability check, **When** the daemon is in a degraded state, **Then** the check times out within 10 seconds and the script reports the daemon as unreachable.

---

### User Story 2 — Trap Integrity: Cleanup Functions Never Corrupt Caller State (Priority: P1)

The operator's integrity tools use shared library functions (atomic write, credential write, audit log) that manage cleanup via bash traps. These functions must never destroy traps set by their callers, and must guarantee cleanup on ALL exit paths — including signals, errors, and cascading failures. Currently, `_integrity_safe_atomic_write()` clobbers the caller's ERR trap, the audit log lock has no trap-based cleanup, credential temp files are not trap-protected, and `_integrity_init_tmp_dir()` silently continues after detecting a critical symlink attack.

**Why this priority**: Trap clobbering is an invisible bug — the caller's cleanup logic silently disappears, and the failure only manifests when the cleanup is actually needed (signal, error). The audit log lock without trap cleanup means any crash during logging leaves a stale lock that blocks all subsequent audit writes until manual intervention. NIST AU-9 requires protection of audit logging tools from unauthorized modification — a stale lock is a form of self-inflicted denial-of-service.

**Independent Test**: Source `integrity.sh`, set an ERR trap, call `_integrity_safe_atomic_write()`, verify the ERR trap is still set. Send SIGTERM during an `integrity_audit_log()` call, verify the lock directory is cleaned up.

**Acceptance Scenarios**:

1. **Given** a caller sets `trap 'cleanup' ERR` before calling `_integrity_safe_atomic_write()`, **When** the atomic write function completes (success or failure), **Then** the caller's ERR trap is still in effect with its original handler.
2. **Given** `_integrity_safe_atomic_write()` creates a temp file, **When** `umask` is checked during mktemp, **Then** umask 077 is set before creation and restored afterward, ensuring the temp file is created with mode 600 regardless of caller's umask.
3. **Given** the process receives SIGTERM during `integrity_audit_log()` between lock acquisition and lock release, **When** the signal handler fires, **Then** the lock directory and PID file are both cleaned up via trap.
4. **Given** `_integrity_safe_credential_write()` creates a curl config file, **When** the file is created, **Then** it has mode 600, and if the calling process is killed before explicit cleanup, an EXIT trap removes the file.
5. **Given** `_integrity_init_tmp_dir()` detects that `~/.openclaw` is a symlink, **When** the detection fires, **Then** initialization aborts with a non-zero exit and all subsequent integrity library functions refuse to operate (not silently continuing via `|| true`).

---

### User Story 3 — Process Group Verification: Timeout Kills What It Intends To Kill (Priority: P1)

The operator relies on `integrity_run_with_timeout()` to kill runaway processes. The function must verify that `set -m` actually created a new process group before attempting to kill by PGID. If process group creation fails silently, `kill -TERM -$pgid` could send SIGTERM to the wrong process group — potentially killing the caller or unrelated processes.

**Why this priority**: Sending SIGTERM to the wrong process group is a privilege escalation of the timeout mechanism. If `set -m` fails in a non-interactive shell context (subshell, pipe, backgrounded process), the backgrounded command inherits the parent's process group. `kill -TERM -$parent_pgid` then kills the entire parent tree. NIST SC-39 (process isolation) requires that execution domains are genuinely separate.

**Independent Test**: Run `integrity_run_with_timeout` inside a subshell where `set -m` might not take effect. Verify the function detects the failure and falls back to tree-based killing via `pkill -P`.

**Acceptance Scenarios**:

1. **Given** `set -m` succeeds and the background command gets its own PGID, **When** the timeout fires, **Then** `kill -TERM -$pgid` kills only the target process group.
2. **Given** `set -m` fails silently (e.g., inside a pipeline or nested subshell), **When** the background command's PGID is checked, **Then** the function detects PGID != PID, logs a warning, and falls back to `pkill -P $pid` (recursive child kill).
3. **Given** a process spawns children that escape the process group, **When** the timeout fires, **Then** any remaining processes with the original PGID are detected via `pgrep -g` post-kill sweep, logged to stderr with the escaped PID, and the function returns exit code 124 (timeout) regardless of escapees. Note: detection and reporting is best-effort; true setsid() escapees cannot be killed by PGID.

---

### User Story 4 — Lock Integrity: Concurrent Writers Cannot Both Acquire the Lock (Priority: P2)

The operator runs multiple integrity operations concurrently (e.g., monitor daemon + manual verify). The audit log lock must guarantee mutual exclusion — exactly one writer holds the lock at any time. Currently, the PID-based stale lock detection has a race where `rm -f pid; rmdir lockdir` is not atomic, allowing two processes to both break the "stale" lock and both acquire it.

**Why this priority**: Audit log corruption breaks the hash chain, which is the forensic evidence trail. NIST AU-9(3) requires cryptographic mechanisms for audit integrity. If two concurrent writers both acquire the lock, their interleaved writes break the hash chain, making the audit log forensically useless. SC-007 requires 100% hash chain validity across concurrent access.

**Independent Test**: Run 100 concurrent audit log writes (10 processes x 10 entries each). Verify the hash chain is valid after all complete.

**Acceptance Scenarios**:

1. **Given** two processes attempt to acquire the audit log lock simultaneously, **When** the lock mechanism resolves, **Then** exactly one process holds the lock and the other retries or fails.
2. **Given** a stale lock exists (holding process crashed), **When** a new process detects the stale lock, **Then** it removes the stale lock and acquires it atomically in a single operation (not separate rm + mkdir).
3. **Given** the lock holder is killed by SIGKILL (cannot run traps), **When** the next process checks the lock, **Then** it detects the dead PID via `kill -0` + start-time comparison and breaks the stale lock.

---

### User Story 5 — Input Canonicalization: Path Traversal Cannot Bypass Validation (Priority: P2)

The operator's TMPDIR validation must reject all path traversal attempts, including those that start with a valid prefix but contain `..` components. Currently, `/var/folders/ab/x/T/../../etc/shadow` passes the regex because the suffix `(/.*)?$` accepts any path after the valid prefix.

**Why this priority**: TMPDIR controls where temporary files are created. If an attacker can set TMPDIR to a traversal path that passes validation, all `mktemp` calls create files in attacker-controlled directories. This converts the integrity system's own temp file creation into a write-anywhere primitive.

**Independent Test**: Set `TMPDIR=/var/folders/ab/x/T/../../etc` and run TMPDIR validation. Verify rejection.

**Acceptance Scenarios**:

1. **Given** TMPDIR is set to `/var/folders/ab/x/T/../../etc/shadow`, **When** validation runs, **Then** the path is rejected because it contains `..` components.
2. **Given** TMPDIR is set to `/var/folders/Xb/abc123def/T`, **When** validation runs, **Then** the path is accepted (valid macOS temp path).
3. **Given** TMPDIR is set to a valid path, **When** validation runs, **Then** the path is canonicalized (resolved to absolute path without symlinks) before comparison.

---

### User Story 6 — Credential Opacity: No Secret Material Visible in Process Listings (Priority: P2)

The operator's HMAC signing key and API credentials must never appear in process argument lists (`ps`), temporary file listings (`lsof`), or environment inspection (`/proc/pid/environ`). Currently, the HMAC key is passed as a command-line argument to `openssl dgst -hmac "$key"`, visible to any local user via `ps aux`. Credential temp files in `integrity-verify.sh` are not trap-protected and can persist after crashes.

**Why this priority**: Process listing credential exposure is OWASP A07 (Security Misconfiguration) mapped to the agentic context (ASI02 Tool Misuse). The HMAC key is the root of trust — if exfiltrated, an attacker can forge manifests, state files, and audit log entries. AWS has documented multiple incidents of credential harvesting from process listings.

**Independent Test**: During HMAC signing, run `ps aux | grep openssl` in a parallel terminal. Verify no key material appears. During credential enumeration, verify no API key appears in `lsof` or `ps` output.

**Acceptance Scenarios**:

1. **Given** the integrity system signs a manifest with the HMAC key, **When** `openssl dgst` runs, **Then** the key is passed via stdin pipe or via a temp file with mode 600 — not as a command-line argument.
2. **Given** a credential temp file is created for curl, **When** the process is killed before explicit cleanup, **Then** an EXIT trap removes the file.
3. **Given** `workflow-sync.sh` passes API keys to curl, **When** it runs, **Then** keys are passed via `--config` temp files, not `-H` command-line arguments.

---

### User Story 7 — Failure Transparency: Parse Failures Never Produce False Negatives (Priority: P2)

The operator must be able to trust that "0 findings" means the security tool actually checked and found nothing — not that it failed to parse the output. Currently, `_integrity_validate_json()` mixes stderr into its return value via `2>&1`, and the `|| var=0` fallback pattern in container-bench.sh and scan-image.sh silently converts parse failures into "0 findings."

**Why this priority**: Silent false negatives are the worst outcome for a security tool (OWASP ASI02 — Tool Misuse). The operator develops false confidence. The adversarial review found this same pattern was identified as a Phase 3 vulnerability, fixed in Phase 4, and then re-introduced in a different form during the fix.

**Independent Test**: Feed syntactically valid but structurally wrong JSON to each security tool wrapper. Verify non-zero exit and logged error, never "0 findings."

**Acceptance Scenarios**:

1. **Given** `_integrity_validate_json()` processes input, **When** jq writes a warning to stderr, **Then** stderr is captured separately from the result value, not mixed via `2>&1`.
2. **Given** docker-bench JSON is missing the `.tests` field, **When** the count extraction runs, **Then** the wrapper exits with a non-zero code and logs the error — it does not default to 0.
3. **Given** Grype JSON has a different schema than expected, **When** the `.matches` field extraction fails, **Then** the wrapper exits non-zero — it does not report "0 CVEs found."

---

### User Story 8 — Liveness Authority: No Check Runs Against a Dead Container (Priority: P3)

The operator's drift detection and community node checks must verify the container is still alive before executing. Currently, these two checks in the verification pipeline lack the `_verify_container_alive()` gate that credentials and workflows have.

**Why this priority**: Running `docker diff` or `docker exec` against a vanished container produces misleading results or errors that are harder to diagnose than a clean "SKIPPED: upstream CRITICAL" message. Consistency in the cascade abort pattern prevents partial verification results.

**Independent Test**: Kill the container after the workflow check but before the drift check. Verify drift and community node checks are skipped with the cascade abort message.

**Acceptance Scenarios**:

1. **Given** the container disappears between the workflow check and drift check, **When** the drift check begins, **Then** `_verify_container_alive()` detects the absence, sets cascade abort, and the drift check is skipped.
2. **Given** the container disappears before the community node check, **When** the check begins, **Then** it is skipped with "SKIPPED: upstream CRITICAL failure."

---

### User Story 9 — Exit Code Safety: Functions Return Boolean, Not Counts (Priority: P3)

The operator's permission check and environment check functions must return boolean success/failure (0/1), not violation counts. Violation counts as exit codes overflow at 256 (wrapping to 0, which means "no violations"), creating a silent false-pass when there are exactly 256 violations.

**Why this priority**: While 256 violations is unlikely with current checks, the pattern is fundamentally wrong and will silently break as checks are added. Defense-in-depth means removing latent vulnerabilities even when the current trigger condition is improbable.

**Independent Test**: Mock a function that returns 256 violations. Verify the caller sees failure, not success.

**Acceptance Scenarios**:

1. **Given** `_integrity_check_permissions()` finds violations, **When** it returns, **Then** it returns 1 (failure), not the violation count.
2. **Given** `integrity_check_env_vars()` finds violations, **When** it returns, **Then** it returns 1 (failure), not the violation count.
3. **Given** any function returns a count as an exit code, **When** the count exceeds 255, **Then** the exit code is still non-zero (clamped to 1).

---

### Edge Cases

- What happens when `set -m` succeeds in the outer function but fails in a nested subshell call to `integrity_run_with_timeout`? The function must detect the failure per-invocation, not assume global state.
- What happens when `python3` is not available for F_FULLFSYNC? The function must fall back to `sync` and log a warning. The fallback must be documented.
- What happens when the macOS Keychain is locked during HMAC signing? The function must fail closed (refuse to operate), not fall back to unsigned writes.
- What happens when two `integrity_rotate_key` processes run simultaneously? The rotation lock must prevent concurrent key rotation.
- What happens when `docker context inspect` hangs during socket path resolution? It must be timeout-bounded like all other Docker calls.
- What happens when `workflow-sync.sh` is called outside the integrity pipeline? Credential exposure must be fixed regardless of call context.
- What happens when the integrity system is deployed for the first time on a compromised host? The first-run baseline captures attacker-controlled state as "trusted." The operator must confirm the initial baseline.
- What happens when PIPESTATUS is checked inside a command substitution subshell? It reflects the subshell's pipeline, not the outer shell's. Pipeline exit codes must be captured correctly.
- What happens when a secret filename contains regex metacharacters (e.g., `secret.key` where `.` matches any char)? File-derived strings used in grep must use fixed-string mode.
- What happens when the `$lockdir` variable is empty or wrong during `rm -rf`? Lock cleanup must validate the path before deletion.

---

## Requirements

### Functional Requirements

**Timeout Authority (US1)**:
- **FR-001**: Every `docker` CLI invocation across the entire codebase (inspect, exec, ps, diff, info, image inspect, context inspect) MUST be wrapped with `integrity_run_with_timeout` with a maximum of 30 seconds for operational calls and 10 seconds for discovery/reachability calls.
- **FR-002**: `integrity_capture_container_snapshot()` MUST wrap its internal `docker inspect` call with a 30-second timeout.
- **FR-003**: `integrity_discover_container()` MUST wrap its internal `docker ps` call with a 10-second timeout.
- **FR-004**: `grype` scan in `scan-image.sh` MUST be wrapped with a 300-second timeout when run standalone (not through security-pipeline.sh).
- **FR-005**: `docker info` reachability checks in `container-bench.sh` MUST be wrapped with a 10-second timeout.
- **FR-006**: `docker exec ... true` liveness checks in `integrity-verify.sh` MUST be wrapped with a 5-second timeout.
- **FR-007**: `docker image inspect` in `scan-image.sh` MUST be wrapped with a 10-second timeout.
- **FR-008**: `docker inspect` in the final re-verification step of `_run_container_checks()` MUST be wrapped with a 5-second timeout.
- **FR-009**: `docker context inspect` in `integrity_docker_socket_path()` MUST be wrapped with a 5-second timeout.
- **FR-034**: `docker exec` calls in `integrity-deploy.sh` baseline capture (n8n version check, up to 3 retries) MUST each be wrapped with a 10-second timeout.
- **FR-035**: `docker ps` calls in `check_container_credentials()` and `check_container_community_nodes()` for liveness verification MUST be wrapped with a 5-second timeout.

**Trap Integrity (US2)**:
- **FR-010**: `_integrity_safe_atomic_write()` MUST save the existing ERR trap before setting its own, and restore it on all exit paths. The RETURN trap (function-scoped in Bash 5.x) is acceptable without save/restore.
- **FR-011**: `_integrity_safe_atomic_write()` MUST set `umask 077` before `mktemp` and restore the previous umask after the temp file is created.
- **FR-012**: `_integrity_safe_atomic_write()` MUST clear its cleanup trap after a successful `mv` to prevent accidental deletion of the target file.
- **FR-013**: `integrity_audit_log()` MUST install a trap for RETURN, INT, and TERM that removes the lock directory and PID file immediately after lock acquisition. RETURN (not EXIT) is used because Bash 5.x RETURN traps are function-scoped — they fire when the function exits, regardless of exit path, without persisting beyond the function scope. INT and TERM handle signal-based interruption. The trap MUST be removed after explicit lock release.
- **FR-014**: `_integrity_safe_credential_write()` MUST set `chmod 600` on the created temp file immediately after creation.
- **FR-015**: Every call site that uses `_integrity_safe_credential_write()` MUST install a local EXIT trap that removes the temp file. The trap MUST use the saved/restored trap pattern to avoid clobbering caller traps.
- **FR-016**: `_integrity_init_tmp_dir()` MUST NOT be called with `|| true`. If symlink detection fails, the sourcing script MUST abort. The initialization function MUST set a global flag `_INTEGRITY_INIT_OK` that all other functions check before operating.

**Process Group Verification (US3)**:
- **FR-017**: `integrity_run_with_timeout()` MUST verify that the backgrounded command's PGID equals its PID (confirming process group creation succeeded). If PGID != PID, the function MUST fall back to `pkill -P $pid` for recursive child killing instead of `kill -TERM -$pgid`.
- **FR-018**: The verification MUST use `ps -o pgid= -p $pid` immediately after `"$@" &` to check the process group.

**Lock Integrity (US4)**:
- **FR-019**: Stale lock removal in `integrity_audit_log()` MUST use `rm -rf "$lockdir"` as a single operation instead of separate `rm -f pid; rmdir lockdir`. Before `rm -rf`, the lock path MUST be validated per FR-044. This eliminates the race window between the two operations.
- **FR-020**: After stale lock removal, the process MUST NOT assume it holds the lock. It MUST retry the `mkdir` to actually acquire it.

**Input Canonicalization (US5)**:
- **FR-021**: TMPDIR validation MUST reject any path containing `..` as a path component, regardless of prefix validity. The check MUST be performed before the regex match.
- **FR-022**: After regex validation passes, the path MUST be canonicalized via `cd "$TMPDIR" && pwd -P` (or equivalent) and the canonical path re-validated to ensure it still matches the allowed pattern.

**Credential Opacity (US6)**:
- **FR-023**: `integrity_sign_manifest()` MUST NOT expose the HMAC key in process argument lists visible via `ps`. The key MUST be written to a mode-600 temp file in `~/.openclaw/tmp/` and read back for the openssl invocation, or passed via a mechanism that does not appear in `/proc/PID/cmdline`. The temp file MUST be cleaned up via trap. Note: OpenSSL's `-hmac` flag requires the key as an argument; the implementation must find a platform-appropriate workaround (e.g., using `openssl mac` subcommand if available, or accepting that the key appears briefly in the process of the integrity script itself — which is expected to hold the key — while ensuring it does not appear in forked child processes).
- **FR-024**: `workflow-sync.sh` MUST use `_integrity_safe_credential_write()` + `curl --config` for all API key passing, replacing any `-H "X-N8N-API-KEY: ..."` patterns.
- **FR-025**: Every credential temp file MUST be protected by an EXIT trap at the call site, using the saved/restored trap pattern.

**Failure Transparency (US7)**:
- **FR-026**: `_integrity_validate_json()` MUST capture stderr separately from stdout. stderr MUST NOT be mixed into the return value. Use `result=$(echo "$input" | jq -e "$expr" 2>/dev/null)` for the result, and capture jq exit code for error detection.
- **FR-027**: The `|| var=0` fallback pattern in `container-bench.sh` and `scan-image.sh` MUST be replaced with a pattern that logs a warning when the fallback triggers, distinguishing "0 findings" from "parse failure defaulted to 0."
- **FR-028**: When a jq extraction falls back to 0, the wrapper script's exit code MUST be non-zero (WARN or FAIL), not PASS.

**Liveness Authority (US8)**:
- **FR-029**: `check_container_drift()` in `integrity-verify.sh` MUST call `_verify_container_alive()` before executing, matching the pattern used by `check_container_credentials()` and `check_container_workflows()`.
- **FR-030**: `check_container_community_nodes()` in `integrity-verify.sh` MUST call `_verify_container_alive()` before executing.

**Exit Code Safety (US9)**:
- **FR-031**: `_integrity_check_permissions()` MUST return 0 (no violations) or 1 (violations found), not the violation count.
- **FR-032**: `integrity_check_env_vars()` MUST return 0 (no violations) or 1 (violations found), not the violation count.
- **FR-033**: Any function that accumulates a violation count MUST clamp its return value: `[[ $violations -gt 0 ]] && return 1 || return 0`.

**Command Dispatch Safety (H8)**:
- **FR-036**: `security-pipeline.sh` MUST NOT use `bash -c "$cmd"` to dispatch layer commands. Layer commands MUST be invoked directly (e.g., `integrity_run_with_timeout "$LAYER_TIMEOUT" $cmd`) or via array-based dispatch where the command and its arguments are separate elements, preventing shell metacharacter interpretation.

**First-Run Trust Bootstrapping (H9)**:
- **FR-037**: The first-run baseline capture (`make integrity-deploy` with no prior manifest) MUST display a summary of captured state (file count, image digest, n8n version, credential count, community node count) and require explicit operator confirmation before persisting. Without confirmation, the manifest MUST NOT be written.
- **FR-038**: A `--verify-baseline` flag MUST be available on `integrity-deploy.sh` to re-display the current baseline summary for operator audit.

**Pipeline Exit Code Correctness (M3)**:
- **FR-039**: PIPESTATUS-based truncation detection MUST NOT rely on `${PIPESTATUS[0]}` inside a command substitution (which reflects the subshell's pipeline, not the outer shell's). The pipeline MUST be restructured: either run the timeout and output bounding as separate steps (write to temp file, then truncate), or capture the exit code within the same subshell and return it as part of the output.

**Input Pattern Safety (M6)**:
- **FR-040**: All `grep` invocations that match file-derived or user-derived strings MUST use `-F` (fixed-string) mode. Specifically, the docker-compose.yml bind-mount check in `_integrity_check_permissions()` MUST use `grep -qF`.

**Resilience (edge cases promoted to FRs)**:
- **FR-041**: When `python3` is not available for F_FULLFSYNC, the function MUST fall back to the system `sync` command and log a warning. The `|| true` suppression MUST be replaced with explicit fallback logic.
- **FR-042**: If the macOS Keychain is locked or inaccessible when the HMAC key is needed, the signing function MUST fail with a non-zero exit code and a clear error message. It MUST NOT fall back to unsigned operation.
- **FR-043**: Key rotation (`integrity-rotate-key.sh`) MUST acquire an exclusive lock before modifying the keychain entry. Concurrent rotation attempts MUST fail with a clear error rather than corrupt the key.
- **FR-044**: Lock directory paths passed to `rm -rf` MUST be validated (non-empty, matches expected pattern `*integrity-audit.log.lock*`) before deletion. An empty or unexpected path MUST abort the cleanup with an error.

### Key Entities

- **Timeout Boundary**: A function-level enforcement wrapper that guarantees a Docker CLI call completes or fails within a defined time, using process group isolation.
- **Trap Chain**: The ordered set of bash trap handlers for a given signal. Library functions must participate in the chain (save/restore) rather than replacing it.
- **Lock Lifecycle**: The complete acquire-use-release cycle for the audit log lock, with trap-guaranteed cleanup on all exit paths including signals.
- **Canonical Path**: A filesystem path with all symlinks resolved, `..` components eliminated, and validated against an allowlist — the result of `realpath` or `cd && pwd -P`.

---

## Success Criteria

### Measurable Outcomes

- **SC-001**: Zero unbounded Docker CLI calls — every `docker` invocation in every script has an explicit timeout. Verified by audit script that: (a) uses `grep -rn '\bdocker\b' scripts/` to find all Docker calls, (b) excludes lines where `integrity_run_with_timeout` precedes the `docker` token, (c) excludes comment-only lines, (d) manually audits any helper function wrappers. Zero unprotected calls must remain.
- **SC-002**: Trap preservation — after calling any integrity library function that sets traps, the caller's pre-existing ERR trap is still in effect. Verified by integration test.
- **SC-003**: Lock safety under concurrency — 100 concurrent audit log writes (10 processes x 10 entries) produce a valid hash chain 100% of the time across 10 trials. Additionally: (a) a test that kills one writer with SIGKILL mid-write, then runs a second writer, produces a valid hash chain, and (b) a test that runs 10 processes simultaneously trying to break the same stale lock results in exactly one acquiring it.
- **SC-004**: TMPDIR traversal rejection — all paths containing `..` are rejected, regardless of prefix. Verified by test suite with 10+ traversal variants.
- **SC-005**: Zero credential exposure — during any integrity operation, `ps aux` and `lsof` show zero instances of HMAC keys or API keys. Verified by integration test.
- **SC-006**: Zero silent false negatives — feeding invalid JSON to each wrapper produces a non-zero exit code and logged error, never "0 findings." Verified by test suite.
- **SC-007**: Process group verification — when `set -m` fails to create a new PGID, the timeout function detects this and uses fallback killing. Verified by integration test in a pipeline context.
- **SC-008**: Cleanup on crash — sending SIGTERM during audit log write results in no stale lock. Verified by test that kills the process mid-write and checks for lock cleanup.
- **SC-009**: Init abort on symlink — if `~/.openclaw` is a symlink, all integrity functions refuse to operate. Verified by creating a test symlink.
- **SC-010**: Exit code correctness — functions with violation counts return 0 or 1, never the count itself. Verified by unit test with count > 255.
- **SC-011**: Command dispatch safety — layer commands in security-pipeline.sh containing shell metacharacters (spaces, quotes, globs) are executed without interpretation. Verified by test with a command containing `$(evil)`.
- **SC-012**: First-run trust — first-time `make integrity-deploy` displays baseline summary and requires operator confirmation. Verified by running deploy with no prior manifest and checking for interactive prompt.
- **SC-013**: Pipeline exit code correctness — output truncation of workflow export is detected and logged. Verified by test with output exceeding 1MB.
- **SC-014**: Fixed-string grep — filenames with regex metacharacters do not cause false matches in permission checks. Verified by creating a test file named `test.key` and ensuring `.` is not treated as regex wildcard.
- **SC-015**: Full verification pipeline completes within 120 seconds on a healthy system. Timeout wrapping and trap management adds less than 5 seconds overhead.
