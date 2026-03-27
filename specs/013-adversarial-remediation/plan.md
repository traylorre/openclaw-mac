# Implementation Plan: Adversarial Review Remediation (Phase 4B)

**Branch**: `013-adversarial-remediation` | **Date**: 2026-03-26 | **Spec**: [spec.md](spec.md)
**Input**: Phase 4B spec (44 FRs, 15 SCs, 9 user stories) addressing 26 adversarial findings
**Parent**: `012-security-hardening-phase2` (Phase 4 implementation — to be merged first)

## Summary

Remediate 26 vulnerabilities found during adversarial review of Phase 4 security hardening code. Core changes: timeout-wrap every Docker CLI call inside library functions (single enforcement point), rewrite trap management using save/restore pattern, add process group verification with fallback to tree-based killing, fix audit lock race with validated rm -rf, canonicalize TMPDIR with .. rejection, fix PIPESTATUS subshell issue via temp-file pipeline, replace bash -c command dispatch, add first-run baseline confirmation, and fix all silent-failure fallback patterns.

## Technical Context

**Language/Version**: Bash 5.x (POSIX-compatible subset per Constitution VI)
**Primary Dependencies**: jq, openssl (LibreSSL), Docker CLI, macOS `security` (Keychain), python3 (F_FULLFSYNC fallback)
**Storage**: JSON state files (`~/.openclaw/`), JSONL audit log
**Target Platform**: macOS Ventura (22.6.0), Apple Silicon, Colima + Docker
**Constraints**: No `setsid` on macOS; `set -m` + verification for process groups. LibreSSL has no stdin-based HMAC option. `F_FULLFSYNC` requires python3.

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Documentation-Is-the-Product | PASS | Quickstart updated with verification procedures |
| II. Threat-Model Driven | PASS | Every fix traces to adversarial finding with exploit path |
| III. Free-First | PASS | All tools free: bash, jq, python3 (system), openssl (system) |
| IV. Cite Canonical Sources | PASS | OWASP Agentic Top 10, NIST 800-53A, CIS Docker, Bash Hackers Wiki |
| V. Every Recommendation Verifiable | PASS | Each fix has integration test + grep-based audit |
| VI. Bash Scripts Are Infrastructure | PASS | set -euo pipefail, shellcheck, idempotent, quoted variables |
| VII. Defense in Depth | PASS | Multiple layers: timeout + trap + validation + isolation |
| VIII. Explicit Over Clever | PASS | Research documents each decision with rationale |
| IX. Markdown Quality Gate | PASS | All spec documents follow markdownlint rules |
| X. CLI-First Infrastructure | PASS | All operations via CLI |

## Project Structure

### Modified Files

```text
scripts/
├── lib/
│   └── integrity.sh            # MODIFY: timeout inside library functions, trap save/restore,
│                                #   process group verification, lock race fix, umask, init guard,
│                                #   TMPDIR canonicalization, credential chmod, grep -F, exit code clamp
├── integrity-verify.sh         # MODIFY: timeout on remaining docker calls, PIPESTATUS fix,
│                                #   credential trap protection, liveness gates, grep -F
├── integrity-deploy.sh         # MODIFY: timeout on docker exec, first-run confirmation
├── integrity-monitor.sh        # MODIFY: inherits library fixes
├── container-bench.sh          # MODIFY: timeout on docker info, silent-failure warning
├── n8n-audit.sh                # MODIFY: inherits library timeout fixes
├── scan-image.sh               # MODIFY: timeout on docker image inspect + grype, silent-failure warning
├── security-pipeline.sh        # MODIFY: eliminate bash -c dispatch
├── workflow-sync.sh            # MODIFY: credential exposure fix (curl --config)
├── test-phase4b-integration.sh # NEW: integration test suite for all 15 SCs
```

## Implementation Phases

### Phase A: Library Foundation (integrity.sh)

Fix the core library functions that all scripts depend on. Every subsequent phase inherits these fixes.

1. **Timeout inside library functions** (FR-002, FR-003, FR-009):
   - Add timeout inside `integrity_capture_container_snapshot()` around `docker inspect`
   - Add timeout inside `integrity_discover_container()` around `docker ps`
   - Add timeout inside `integrity_docker_socket_path()` around `docker context inspect`

2. **Trap save/restore pattern** (FR-010, FR-011, FR-012):
   a. Create helper: `_integrity_save_trap()` and `_integrity_restore_trap()` for ERR trap management
   b. Rewrite `_integrity_safe_atomic_write()`: save ERR trap, set umask 077, create temp file, restore umask, write content, mv, clear cleanup trap on success, restore ERR trap on all paths
   c. Rewrite credential write call sites in integrity-verify.sh, integrity-monitor.sh, integrity.sh: use RETURN trap (function-scoped) for credential cleanup instead of EXIT
   d. Test: nested call scenario — atomic write called from within audit log (which has its own lock trap)

3. **Audit log lock trap cleanup** (FR-013, FR-019, FR-020, FR-044):
   - Install trap for lock cleanup immediately after mkdir succeeds
   - Use validated `rm -rf` for stale lock removal (check path matches pattern)
   - After stale removal, retry mkdir (don't assume lock held)

4. **Credential write hardening** (FR-014):
   - Add `chmod 600` after mktemp in `_integrity_safe_credential_write()`

5. **Init guard** (FR-016):
   - Remove `|| true` from `_integrity_init_tmp_dir` call
   - Set `_INTEGRITY_INIT_OK=true` on success
   - Add guard check at top of key functions

5b. **Init guard scoping** (RD-013):
   - Guard only security-critical functions: signing, audit log, credential handling, atomic write
   - Leave non-critical helpers ungated: SHA-256, symlink check, version comparison
   - This preserves compatibility with hardening-audit.sh which sources with || true

6. **Process group verification** (FR-017, FR-018):
   - After `"$@" &`, check `ps -o pgid= -p $cmd_pid`
   - If PGID != PID, set `_use_pkill=true` and use `pkill -P` for killing

7. **TMPDIR canonicalization** (FR-021, FR-022):
   - Reject paths containing `..` before regex
   - After regex pass, canonicalize via `cd "$TMPDIR" && pwd -P`, re-validate

8. **Exit code clamp** (FR-031, FR-032, FR-033):
   - `_integrity_check_permissions()`: `[[ $violations -gt 0 ]] && return 1 || return 0`
   - `integrity_check_env_vars()`: same pattern

9. **grep -F for file-derived strings** (FR-040):
   - `_integrity_check_permissions()`: change `grep -q` to `grep -qF`

10. **_integrity_validate_json stderr fix** (FR-026):
    - Change `2>&1` to `2>/dev/null` for result capture
    - On error, re-run with stderr for diagnostics

11. **F_FULLFSYNC fallback** (FR-041):
    - Check `command -v python3`, fall back to `sync` with warning

12. **Keychain fail-closed** (FR-042):
    - Signing function returns error when key unavailable, never falls back to unsigned

13. **HMAC key exposure mitigation** (FR-023, RD-015):
    - Write key to mode-600 temp file before openssl invocation
    - Read back into variable for -hmac argument
    - Clean up temp file via trap
    - Document as accepted limitation (ps exposure < 1ms, single-user, Keychain-protected)

### Phase B: Verification Pipeline (integrity-verify.sh)

1. **Timeout remaining Docker calls** (FR-006, FR-008, FR-035):
   - `docker exec true` liveness -> 5s timeout
   - `docker inspect` in re-verification -> 5s timeout
   - `docker ps` in credential/community checks -> 5s timeout

2. **Credential trap protection** (FR-015, FR-025):
   - Every `_integrity_safe_credential_write` call site gets EXIT trap with save/restore

3. **PIPESTATUS fix** (FR-039):
   - Workflow export: write to temp file via timeout, then read+truncate separately

4. **Liveness gates** (FR-029, FR-030):
   - Add `_verify_container_alive || return` before drift and community node checks

5. **Silent-failure warnings** (FR-027, FR-028):
   - JSON fallback patterns log warning, set non-zero exit when triggered

### Phase C: Tool Scripts

1. **container-bench.sh** (FR-005):
   - Timeout `docker info` reachability check

2. **scan-image.sh** (FR-004, FR-007):
   - Timeout `docker image inspect` and standalone grype scan
   - Silent-failure warnings on JSON fallbacks

3. **security-pipeline.sh** (FR-036):
   - Convert LAYERS associative array from string values to separate script+args
   - Invoke via `integrity_run_with_timeout "$LAYER_TIMEOUT" "$script" $args` where script is quoted and args are intentionally split
   - Alternative (simpler): since all layer commands are hardcoded, use a case statement or indexed array of arrays
   - Per RD-008: avoid bash -c entirely

4. **workflow-sync.sh** (FR-024, FR-001):
   - Replace `-H "X-N8N-API-KEY: ..."` with `_integrity_safe_credential_write` + `curl --config`
   - Timeout-wrap all ~12 docker exec/ps calls with integrity_run_with_timeout
   - Source integrity.sh (add if not already sourced)

5. **hardening-audit.sh** (FR-001):
   - Timeout-wrap docker calls that use integrity library functions
   - Keep `|| true` on source line (interactive tool, per RD-013)
   - Note: hardening-audit.sh has ~50+ docker refs but many are audit checks that need different timeout values. Add 30s default timeout to docker inspect/exec calls.

### Phase D: Deploy + First-Run

1. **integrity-deploy.sh** (FR-034, FR-037, FR-038):
   - Timeout docker exec calls in baseline capture
   - First-run confirmation prompt with summary display
   - `--verify-baseline` flag

### Phase E: Integration Tests + Polish

1. **test-phase4b-integration.sh** — tests for all 15 SCs
2. **Key rotation lock** (FR-043) — exclusive lock in rotate-key.sh
3. **Update phase4b-traceability.md** — map all 26 findings to fixes
4. **FR-001 codebase-wide audit** — Run SC-001 audit: `grep -rn '\bdocker\b' scripts/` minus known-protected calls. Zero unprotected calls must remain.
5. **Regression test** — Run existing `test-phase4-integration.sh` to verify Phase A-D changes don't break existing functionality.
6. **Test traceability matrix**:
   | SC | Test Function | Complexity | Notes |
   |-----|--------------|-----------|-------|
   | SC-001 | test_docker_audit | Low | grep-based |
   | SC-002 | test_trap_preservation | Medium | source + verify |
   | SC-003 | test_concurrent_writes | High | 10 processes, SIGKILL, stale lock |
   | SC-004 | test_tmpdir_traversal | Low | 10+ attack paths |
   | SC-005 | test_credential_opacity | Medium | parallel ps, race-sensitive |
   | SC-006 | test_false_negatives | Low | feed bad JSON |
   | SC-007 | test_pgid_verification | Medium | pipeline context |
   | SC-008 | test_lock_crash | Medium | SIGTERM + verify |
   | SC-009 | test_symlink_init | Medium | temp symlink, cleanup required |
   | SC-010 | test_exit_codes | Low | mock 256 violations |
   | SC-011 | test_command_dispatch | Medium | metachar in command |
   | SC-012 | test_first_run | High | interactive prompt simulation |
   | SC-013 | test_pipestatus | Medium | >1MB output |
   | SC-014 | test_grep_fixed | Low | regex metachar filename |
   | SC-015 | test_performance | Low | time make integrity-verify |
7. Performance validation (SC-015)

## Design Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Timeout inside library functions | Single enforcement point; callers can't forget |
| 2 | Trap save/restore via `trap -p` | Only Bash 5.x pattern that preserves caller traps |
| 3 | Validated `rm -rf` for stale locks | Eliminates rm/rmdir race; path guard prevents catastrophic delete |
| 4 | Accept HMAC key exposure in process | LibreSSL has no stdin HMAC; short-lived process + Keychain ACL mitigates |
| 5 | Temp file for PIPESTATUS fix | Avoids subshell PIPESTATUS issue entirely |
| 6 | PGID check after backgrounding | Detects set -m failure per-invocation |
| 7 | First-run confirmation prompt | TOFU requires human verification of initial state |
| 8 | Direct script invocation for pipeline | Eliminates shell metacharacter interpretation |
| 9 | jq 2>/dev/null for result capture | Prevents stderr mixing; re-run for diagnostics on error |
| 10 | sync fallback for F_FULLFSYNC | Better than nothing; documented limitation |

## Risk Log

| Risk | Mitigation |
|------|-----------|
| Timeout overhead slows verification | Timeouts only fire on failure; healthy path unaffected. SC-015 validates <5s overhead |
| Trap save/restore complex, easy to get wrong | Single pattern used everywhere; integration test verifies (SC-002) |
| First-run prompt blocks CI | `--force` flag bypasses prompt for automation |
| HMAC key briefly in ps | Short-lived, non-backgrounded, Keychain-protected. Documented accepted risk |
| rm -rf with wrong path | Validated against expected pattern before execution (FR-044) |
