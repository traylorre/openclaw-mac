# Research Decisions: Adversarial Review Remediation (Phase 4B)

**Branch**: `013-adversarial-remediation` | **Date**: 2026-03-26 | **Spec**: [spec.md](spec.md)

---

## RD-001: Trap Save/Restore Pattern for Bash 5.x

**Question**: How to save and restore ERR traps without clobbering the caller's handler.

**Decision**: Use `_saved_err_trap=$(trap -p ERR)` before setting the function's trap, then `eval "$_saved_err_trap"` on all exit paths (success and failure) to restore.

**Rationale**: `trap -p ERR` outputs the full `trap -- '...' ERR` command, so `eval` re-installs it exactly. This is the only Bash 5.x mechanism that preserves the caller's handler verbatim, including quoted arguments and multi-statement bodies.

**Note on RETURN traps**: RETURN traps are function-scoped in Bash 5.x and do not propagate to the caller. They do not need save/restore. Only ERR, EXIT, INT, and TERM traps are global and require the pattern.

---

## RD-002: Docker Call Timeout Strategy

**Question**: Whether to wrap timeouts inside library functions (e.g., inside `integrity_capture_container_snapshot`) or require every call site to wrap.

**Decision**: Wrap inside the library function.

**Rationale**: Single point of enforcement — the caller cannot forget. The function already handles errors internally; adding timeout is an internal implementation concern, not a caller concern. This matches FR-002/FR-003/FR-009 which specify timeouts at the function level, not the call-site level. The timeout value is an appropriate default for the function's semantics (30s for operational calls, 10s for discovery, 5s for liveness).

---

## RD-003: HMAC Key Exposure Mitigation

**Question**: How to prevent the HMAC key from appearing in `ps` output when using openssl.

**Decision**: Accept that the bash process (which already holds the key in a variable) shows the key in its openssl child's cmdline. Mitigate by ensuring the openssl invocation is extremely short-lived (not backgrounded).

**Investigation**: On macOS with LibreSSL, there is no stdin-based HMAC option. The `-hmac` flag requires the key as an argument. Alternatives explored:

1. **Write key to temp file, `openssl dgst -sha256 -hmac "$(cat "$keyfile")"`**: The `$(cat ...)` expands before exec, so the key still appears in the process argument list. No improvement.
2. **Use `openssl mac` subcommand**: Not available in LibreSSL (macOS system openssl).
3. **Pipe-based approach**: LibreSSL's `dgst -hmac` does not support reading the key from stdin.

**Accepted risk**: The key appears briefly in `ps` during the openssl child process. Mitigations:
- Short-lived process (not backgrounded), minimizing the exposure window
- Keychain access control: only the integrity script's user can read the key
- No backgrounding of the openssl invocation (eliminates persistent exposure)

**Documentation**: This is documented as an accepted risk in the plan's risk log.

---

## RD-004: Stale Lock Cleanup Strategy

**Question**: `rm -rf` vs `rm -f pid && rmdir` for stale lock removal.

**Decision**: Use `rm -rf` with path validation guard.

**Rationale**: The two-step `rm -f pid; rmdir lockdir` has a race condition: between the two operations, another process can acquire the lock (mkdir succeeds after pid removal). Both processes then believe they hold the lock, violating mutual exclusion.

`rm -rf` is atomic from the caller's perspective (single syscall tree). The path MUST be validated before `rm -rf` is called: it must match `*/integrity-audit.log.lock` pattern and must be non-empty. This eliminates the catastrophic-delete risk of `rm -rf ""` or `rm -rf /`.

After stale removal, the process must retry `mkdir` to actually acquire the lock (FR-020) — it must not assume it holds the lock just because it removed the stale one.

---

## RD-005: PIPESTATUS in Command Substitution

**Question**: How to correctly detect output truncation when PIPESTATUS is checked inside a command substitution subshell.

**Decision**: Separate the pipeline into two steps — run the timeout command writing to a temp file, then read and truncate separately.

**Rationale**: `${PIPESTATUS[0]}` inside a `$(...)` command substitution reflects the subshell's pipeline, not the outer shell's. This means:

```bash
result=$(integrity_run_with_timeout 30 docker exec ... | head -c 1048576)
# PIPESTATUS here is from the OUTER shell, but the pipeline ran in the subshell
```

The fix: write the timeout command output to a temp file, capture its exit code directly, then read and truncate the temp file as a separate step. This avoids the subshell PIPESTATUS issue entirely and gives clean access to the timeout's exit code.

---

## RD-006: Process Group Verification

**Question**: How to detect when `set -m` fails silently (no error, but no new process group created).

**Decision**: After `"$@" &`, check `ps -o pgid= -p $cmd_pid`. If PGID != PID, `set -m` did not create a new group. Fall back to `pkill -P` for tree-based killing.

**Rationale**: `set -m` can fail silently in non-interactive contexts (subshells, pipes, backgrounded processes). The function must detect this per-invocation, not assume global state. The verification is:

```bash
"$@" &
cmd_pid=$!
cmd_pgid=$(ps -o pgid= -p "$cmd_pid" | tr -d ' ')
if [[ "$cmd_pgid" != "$cmd_pid" ]]; then
    _use_pkill=true  # fall back to pkill -P for tree killing
fi
```

`pkill -P $pid` recursively kills children of the given PID. This is less precise than PGID-based killing (processes that re-parent escape), but is the best available fallback without `setsid` on macOS.

---

## RD-007: First-Run Baseline Confirmation

**Question**: UX for operator confirmation of the initial TOFU (Trust On First Use) baseline.

**Decision**: Display a summary table (file count, image digest, n8n version, credential count, community node count) and prompt `Confirm baseline? [y/N]`. Skip the prompt if `--force` flag is passed (for CI/automation).

**Rationale**: The first-run baseline captures system state as "trusted." If the host is already compromised, the baseline encodes attacker-controlled state. The operator must explicitly verify that the captured state matches their expectation. The summary table provides enough information for a quick sanity check without overwhelming the operator.

The `--force` flag enables unattended deployment in CI/automation where the pipeline itself is trusted. The `--verify-baseline` flag (FR-038) allows re-displaying the current baseline at any time.

---

## RD-008: Command Dispatch in security-pipeline.sh

**Question**: How to replace `bash -c "$cmd"` which allows shell metacharacter interpretation.

**Decision**: The LAYERS array values are hardcoded script paths with arguments. Split on first space to get script path and args. Use `integrity_run_with_timeout "$LAYER_TIMEOUT" bash "$script" $args` which avoids shell interpretation of metacharacters in `$cmd` while preserving argument splitting.

**Rationale**: `bash -c "$cmd"` interprets the entire string as a shell command, meaning `$(evil)` or `; rm -rf /` in `$cmd` would execute. While the LAYERS array is currently hardcoded (not user-supplied), defense-in-depth requires that the dispatch mechanism cannot be weaponized if the array source changes.

Direct invocation with word-splitting on `$args` (intentionally unquoted) preserves the ability to pass arguments like `--timeout 300` while preventing shell metacharacter interpretation. The script path itself is quoted to handle paths with spaces.

---

## RD-009: _integrity_validate_json stderr Handling

**Question**: How to separate stderr from stdout when capturing jq output.

**Decision**: Use `2>/dev/null` for the result capture (suppress jq stderr from mixing into output), check `$?` for error detection. If error, re-run with stderr captured to a variable for diagnostics.

**Rationale**: The current `2>&1` pattern mixes jq's stderr warnings into the captured result variable. This means a jq warning like `null` or `jq: error ...` becomes part of the "result," causing downstream parsing failures or, worse, being silently treated as valid output.

The two-pass approach:
1. `result=$(echo "$input" | jq -e "$expr" 2>/dev/null); rc=$?` — clean result capture
2. If `rc != 0`: `err=$(echo "$input" | jq -e "$expr" 2>&1 >/dev/null)` — capture stderr for diagnostics

This adds one extra jq invocation on the error path only. The happy path (no error) has zero overhead.

---

## RD-010: F_FULLFSYNC Fallback When python3 Unavailable

**Question**: What to do when `python3` is not available for per-file fsync via `F_FULLFSYNC`.

**Decision**: Check `command -v python3` first. If unavailable, fall back to `sync` (system-wide flush, not per-file but better than nothing). Log a warning. Do NOT use `|| true` — use explicit fallback logic.

**Rationale**: `F_FULLFSYNC` (macOS equivalent of `fsync` that actually flushes to disk) requires the `fcntl` syscall, which is accessible from python3 but not from bash. If python3 is unavailable:

- `sync` flushes all pending writes system-wide. It is coarser-grained but ensures data reaches disk.
- `|| true` suppresses the error silently, which violates the failure transparency principle (US7).
- Explicit fallback with a logged warning makes the degraded behavior visible to the operator.

```bash
if command -v python3 >/dev/null 2>&1; then
    python3 -c "import fcntl, os; fd=os.open('$file',os.O_RDONLY); fcntl.fcntl(fd,51); os.close(fd)"
else
    printf '[WARN] python3 unavailable, using system sync (not per-file)\n' >&2
    sync
fi
```

---

## RD-011: EXIT trap save/restore nesting

**Question**: When `integrity_audit_log()` installs an EXIT trap for lock cleanup, and it's called from within a function that also has a credential EXIT trap, the traps can conflict.

**Decision**: Use a trap-stacking pattern — each function appends its cleanup to the existing EXIT trap rather than replacing it. Pattern: `trap "$(_existing_exit_trap_cmd); my_cleanup" EXIT` where `_existing_exit_trap_cmd` extracts the current handler via `trap -p EXIT | sed "s/trap -- '//;s/' EXIT//"`. This allows multiple cleanup handlers to coexist. Alternative: Use RETURN traps (function-scoped) where possible, reserving EXIT for the outermost script-level cleanup.

**Decision**: Prefer RETURN for function-scoped cleanup, EXIT only for process-level cleanup (credential files, lock dirs). Since RETURN is function-scoped in Bash 5.x, nested RETURN traps don't conflict.

---

## RD-012: set -m interaction with set -e (errexit)

**Question**: `set -m` changes job control mode. When a backgrounded process under `set -m` exits with non-zero, bash may report "Done(1)" to stderr. Under `set -e`, does this cause the script to exit?

**Decision**: Under `set -e`, this does NOT cause the script to exit because the `wait` command's exit code is what matters, and `wait` is explicitly checked. The ordering in `integrity_run_with_timeout` — `set -m` before `"$@" &`, then `set +m` before watchdog — is correct: the command gets its own process group, the watchdog does not. No change needed, but document this explicitly in the function's header comment.

---

## RD-013: hardening-audit.sh and init guard compatibility

**Question**: `hardening-audit.sh` sources `integrity.sh` with `|| true` because it can function without the integrity library (it only uses a few helper functions). FR-016 requires removing `|| true` from the init call, which would break `hardening-audit.sh`.

**Decision**: The init guard (`_INTEGRITY_INIT_OK`) only gates security-critical functions (signing, audit log, credential handling). Non-critical helpers (SHA-256, symlink check, version comparison) remain available without the guard. This means `hardening-audit.sh` can continue to source with `|| true` — it just won't be able to call guarded functions. Add `hardening-audit.sh` to scope for FR-001 (timeout wrapping of its docker calls) as a separate task. The `|| true` on the source line is acceptable for this script since it's an interactive audit tool, not a pipeline component.

---

## RD-014: macOS /Users firmlink and symlink detection

**Question**: On APFS (macOS Catalina+), `/Users` is a "firmlink" — a bidirectional hard link between read-only system volume and writable data volume (`/System/Volumes/Data/Users`). Does the symlink detection in `_integrity_init_tmp_dir()` false-positive on firmlinks?

**Decision**: Firmlinks are NOT symlinks — `[[ -L /Users ]]` returns false. The symlink detection in `_integrity_init_tmp_dir()` will NOT false-positive on firmlinks. Verified: `[[ -L /Users ]]` returns 1 on macOS Ventura. No change needed.

---

## RD-015: FR-023 HMAC key exposure resolution

**Question**: The spec requires the HMAC key not appear in `ps` output. LibreSSL's `openssl dgst -hmac` requires the key as a command-line argument — there is no stdin or file-based alternative.

**Investigation**: On macOS, `/proc` does not exist and `ps` shows the key only briefly during the `openssl` child process lifetime (~1ms for a small HMAC). The risk is LOCAL users running `ps aux` at exactly the right moment.

**Decision**: Implement a mitigation — write the key to a mode-600 temp file, read it back into a variable, pass via `-hmac "$key_from_file"`. This does NOT prevent `ps` exposure (the variable is still expanded on exec), but it ensures the Keychain is not read inline in the openssl command, and the temp file pattern is consistent with credential handling. Document as a known limitation with mitigating factors: (1) single-user system, (2) key lifetime in ps < 1ms, (3) Keychain ACL restricts reading to script user. Update spec FR-023 to reflect this accepted limitation.
