# Implementation Plan: Security Remediation & Hardening Depth (Phase 4)

**Branch**: `012-security-hardening-phase2` | **Date**: 2026-03-26 | **Spec**: [phase4-spec.md](phase4-spec.md)
**Input**: Phase 4 sub-spec (41 FRs), adversarial review of spec (33 findings — all CRITICALs/HIGHs addressed), phase4-research.md (10 research decisions)

## Summary

Remediate 43 adversarial findings from Phases 3/3B across 6 implementation phases. Core changes: fail-fast verification cascade with trust tiers, process group isolation (macOS-compatible via `set -m` + `kill -TERM -$pgid`), atomic file operations in controlled directory (`~/.openclaw/tmp/`), combined JSON validation+extraction (eliminating all `|| echo 0` patterns), supply chain verification for security tools (commit hash pinning, binary hash verification), PID+start-time-based lock files, credential exposure remediation (3 here-string instances), and protection surface expansion (+3 files). All fixes apply to both one-shot tools AND the integrity-monitor daemon.

## Technical Context

**Language/Version**: Bash 5.x (POSIX-compatible subset per Constitution VI)
**Primary Dependencies**: jq, openssl, Docker CLI, macOS `security` (Keychain), perl (POSIX::setsid fallback), python3 (F_FULLFSYNC)
**Storage**: JSON state files (`~/.openclaw/`), JSONL audit log
**Target Platform**: macOS Ventura (22.6.0), Apple Silicon, Colima + Docker
**Constraints**: No `setsid` on macOS; use `set -m` + job control. `mktemp` creates 0600 files by default. `mv` is atomic on APFS same-volume. `fsync()` does NOT guarantee persistence — use `F_FULLFSYNC` (fcntl 51) via python3.

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Documentation-Is-the-Product | PASS | Quickstart documents verification procedures; research documents decisions |
| II. Threat-Model Driven | PASS | Every fix maps to a specific adversarial finding with exploit path |
| III. Free-First | PASS | All tools free: bash, jq, python3 (system), perl (system) |
| IV. Cite Canonical Sources | PASS | OWASP Agentic Top 10, NIST 800-53A, CIS Docker Benchmark, specific CVEs |
| V. Every Recommendation Verifiable | PASS | Each fix has independent test (quickstart + acceptance scenarios) |
| VI. Bash Scripts Are Infrastructure | PASS | set -euo pipefail, shellcheck, idempotent, quoted variables |
| VII. Defense in Depth | PASS | Trust tier cascade (HIGH→PARTIAL→ADVISORY), process group isolation, supply chain verification |
| VIII. Explicit Over Clever | PASS | Research documents each decision with rationale and alternatives |
| IX. Markdown Quality Gate | PASS | All spec documents follow markdownlint rules |
| X. CLI-First Infrastructure | PASS | All operations via CLI, no GUI dependencies |

## Project Structure

### Modified Files

```text
scripts/
├── lib/
│   └── integrity.sh            # MODIFY: safe_atomic_write(), integrity_run_with_timeout() rewrite,
│                                #   PID-based lock, || echo 0 remediation, JSON validation helpers,
│                                #   TMPDIR regex fix, credential temp file helpers, Docker socket check,
│                                #   audit log action validation, protection surface expansion
├── integrity-verify.sh         # MODIFY: fail-fast cascade, trust tiers, fail() severity param,
│                                #   output bounding, credential exposure fix, container re-verify
├── integrity-deploy.sh         # MODIFY: atomic writes via safe_atomic_write(), manifest merge validation
├── integrity-monitor.sh        # MODIFY: credential exposure (3 instances), JSON validation,
│                                #   output bounding on docker exec/diff, process group for poll loops
├── container-bench.sh          # MODIFY: commit hash verification, || true removal, JSON validation
├── n8n-audit.sh                # MODIFY: sed→grep+jq extraction, output bounding, JSON validation
├── scan-image.sh               # MODIFY: exact version enforcement, binary hash verification
├── security-pipeline.sh        # MODIFY: "$cmd" quoting (bash -c), process group timeout
Makefile                            # MODIFY: security-update-hashes target (repo root, NOT scripts/)

~/.openclaw/
├── tmp/                        # NEW: secure temp directory (mode 700)
└── container-security-config.json  # EXTENDS: tool hash pins (bench commit, grype binary)
```

## Implementation Phases

### Phase A: Foundation (Safe Primitives Library)

Add fundamental safe operation primitives to `scripts/lib/integrity.sh`. Every subsequent phase depends on these.

0. **`set -m` validation test** — Before any production use, create a standalone test (`scripts/test-job-control.sh`) that validates:
   - `set -m` + `"$@" &` creates a new process group (PGID = PID)
   - `kill -TERM -$pgid` kills all group members
   - `set -m` inside a function does NOT affect caller's job control mode
   - Nested `set -m` contexts (timeout within timeout) behave predictably
   - Interaction with `set -euo pipefail` and trap handlers
   - Behavior in subshells `(...)` used by monitor heartbeat/poll loops
   - If any test fails, fall back to `perl -e 'use POSIX; fork and exit; POSIX::setsid(); exec @ARGV'`

1. **`_integrity_safe_atomic_write()`** — Atomic file write with symlink protection:
   - Create `~/.openclaw/tmp/` if not exists (mode 700)
   - Validate `~/.openclaw/` and all parents are not symlinks
   - `mktemp` in `~/.openclaw/tmp/` (already creates 0600)
   - Validate created file is not symlink (post-creation check)
   - Write content to temp file
   - `mv` to target (atomic on APFS same-volume)
   - Trap-based cleanup on all exit paths (RETURN, ERR, EXIT, INT, TERM)
   - **Incremental adoption**: first deploy for heartbeat file only, validate in monitor loop for 1 cycle, then expand to manifest, lock-state, etc. Do NOT replace all mktemp sequences in a single change.
   - **Enumerated instances to replace** (after validation):
     - `integrity.sh:302-312` (state file signing)
     - `integrity.sh:382-390` (audit log append — different pattern, append not replace)
     - `integrity-deploy.sh:226-235` (manifest re-signing)
     - `Makefile:284,296` (hooks-setup/teardown)

2. **`_integrity_safe_credential_write()`** — Write API key to temp file for curl:
   - Create temp file in `~/.openclaw/tmp/` via `_integrity_safe_atomic_write`
   - Format as curl config: `header = "X-N8N-API-KEY: $key"`
   - Return temp file path (caller passes to `curl --config`)
   - Use EXIT trap (not RETURN) for cleanup — RETURN trap does not fire when subshell is killed via SIGTERM
   - Monitor's SIGTERM handler (line 417) MUST also sweep `~/.openclaw/tmp/curl-*` for orphaned credential files
   - Replace all 3 here-string instances: integrity.sh:840, integrity-verify.sh:687, integrity-monitor.sh:304

3. **`_integrity_run_with_timeout()` rewrite** — Process group isolation:
   - `set -m` before background launch
   - `"$@" &` (creates new process group, PGID = PID)
   - Watchdog: `sleep $timeout; kill -TERM -$pgid 2>/dev/null; sleep 2; kill -KILL -$pgid 2>/dev/null`
   - On normal completion: kill watchdog, restore `set +m`
   - After timeout SIGKILL: `pgrep -P $pgid` to detect escapees, log if found
   - Single implementation — NOT duplicated in security-pipeline.sh

4. **`_integrity_validate_json()`** — Combined validation+extraction:
   - Takes jq expression + input, runs in single pass
   - Uses `jq -e '$expr // error("missing $field")'` pattern
   - Replaces ALL `2>/dev/null || echo 0` patterns across codebase
   - Returns extracted value on success, exits non-zero with logged error on failure

5. **PID-based lock rewrite** for `integrity_audit_log()`:
   - `mkdir "$lockdir"` — atomic lock acquisition
   - Immediately write `$$ $(ps -o lstart= -p $$)` to `$lockdir/pid`
   - Trap: `rm -f "$lockdir/pid"; rmdir "$lockdir"` on RETURN/ERR/EXIT/INT/TERM
   - Stale detection: read PID file, compare `ps -o lstart=` against stored start time
   - Missing/empty PID file: stale after 30 seconds (conservative timeout)
   - Remove `chmod ... || true` — detect and report permission failures
   - F_FULLFSYNC critical state files (manifest, lock-state) via: `python3 -c "import os,fcntl,sys; fd=os.open(sys.argv[1],os.O_RDONLY); fcntl.fcntl(fd,51); os.close(fd)" "$file"` (pass path as argv, NOT string interpolation — avoids command injection)

6. **Audit log hardening**:
   - Action validation: `^[a-z][a-z0-9_]{2,48}$` regex
   - Details escaping: all values through jq `--arg` (handles newlines → `\n`, tabs → `\t`)
   - Remove all `|| echo 0` patterns in integrity.sh (lines 352, 508, 592)
   - Date parsing failures → hard error (return 1), not epoch 0 fallback

7. **TMPDIR validation fix**: Regex `^(/tmp|/private/tmp|/var/folders/[a-zA-Z0-9_+]{2}/[^/]+/T)(/.*)?$` — uses `[^/]+` for random subdirectory component (macOS may include `+` and other chars); security goal is preventing `..` traversal, not restricting charset.

8. **`_integrity_validate_container_name()`** — Container name pattern validation:
   - Regex: `^[a-zA-Z][a-zA-Z0-9_-]{0,63}$` (no dots, starts with letter, max 64 chars)
   - Called before any `docker ps --filter name=` invocation
   - Migration: if existing config value fails validation, log warning, fall back to default `"n8n"`

9. **PKG_DELIMITER injection fix** — Replace `---PKG_DELIMITER---` in community node parsing:
   - Validate each parsed segment with `_integrity_validate_json()` before field extraction
   - Log parse failures with truncated block content (200 chars), skip invalid blocks
   - Count and report parse failures in verification result

### Phase B: Fail-Fast Verification Cascade

Restructure `integrity-verify.sh` to enforce trust tier ordering with cascade abort.

1. **Trust tier constants**:
   ```
   TIER_HIGH: container_exists, image_digest, runtime_config
   TIER_PARTIAL: credential_enum, workflow_compare
   TIER_ADVISORY: drift_detection, community_node_scan
   ```

2. **`fail()` with severity parameter**:
   - `fail CRITICAL "msg"` → increment ERRORS, set `_CASCADE_ABORT=true`
   - `fail WARNING "msg"` → increment WARNINGS, do not abort
   - Before each check function: `[[ "$_CASCADE_ABORT" == "true" ]] && { log_warn "SKIPPED: upstream CRITICAL failure"; return 0; }`

3. **Container liveness gate** — `_verify_container_alive()`:
   - Called before every `docker inspect`/`docker exec`/`docker diff`
   - `docker ps -q --filter "id=$_CONTAINER_PINNED_CID"` with 5-second timeout
   - If empty: `fail CRITICAL "container_vanished"` → cascade abort
   - Also check `.State.Paused` from snapshot — if paused, `fail CRITICAL "container_paused"`
   - Distinguish timeout exit code 124 (daemon unresponsive → status UNKNOWN) from other failures (container absent → FAIL)

4. **Final re-verification** at end of pipeline:
   - Compare container ID AND image digest against start-of-pipeline values
   - Container replaced during verification → FAIL with "container_replaced_during_verification"

5. **Trust boundary documentation** — verification result JSON includes `trust_assumptions` field:
   - Lists: "Docker daemon integrity assumed", "Colima VM integrity assumed", "Keychain integrity assumed"
   - If Docker socket permissions fail (Phase D), add: "Docker socket permissions non-standard"

6. **Output bounding** on all docker exec calls:
   - Wrap with `integrity_run_with_timeout 30`
   - Pipe stdout through `head -c 1048576`
   - Detect truncation via pipeline exit status (141 = SIGPIPE)
   - Log "output_truncated" if detected

### Phase C: Security Tool Hardening

Harden the 4 security tool wrappers and the pipeline orchestrator.

1. **security-pipeline.sh**:
   - Fix command injection: `bash -c "$cmd"` (not `bash $cmd`)
   - Each layer runs through `integrity_run_with_timeout` with process group isolation
   - Remove `>/dev/null 2>&1` — capture output to temp file for debugging

2. **container-bench.sh**:
   - Pin to commit hash (stored in HMAC-signed container-security-config.json)
   - After clone: `git rev-parse HEAD` must match pinned hash
   - Before each run: re-verify hash of existing clone
   - Hash mismatch: delete clone, log "supply_chain_verification_failed"
   - Remove `|| true` from docker-bench execution — capture exit code, treat non-zero as FAIL
   - JSON validation: `jq -e '.tests // error("missing .tests")' "$json_file"`

3. **n8n-audit.sh**:
   - Replace `sed -n '/^[{[]/,$p'` with: `grep -m1 -n '^[{[]'` → `tail -n +$N` → `jq -e`
   - Output bounding: `docker exec` through `head -c 1048576` with timeout
   - JSON validation: combined extraction with `jq -e`

4. **scan-image.sh**:
   - Enforce exact version match (not prefix): `[[ "$grype_version" == "$EXPECTED" ]]`
   - Binary hash verification: `shasum -a 256 "$(which grype)"` vs stored hash
   - Either mismatch → FAIL with "tool_integrity_failed"

5. **New Makefile target**: `security-update-hashes` (MUST be implemented FIRST in Phase C)
   - Computes current docker-bench commit hash and grype binary hash
   - Stores in container-security-config.json via HMAC-signed write
   - Logs update to audit trail
   - **Trust-on-first-use**: if no pinned hash exists in config, compute and store it on first run, then enforce on subsequent runs. This avoids chicken-and-egg ordering.

6. **Docker-compose YAML parsing** for secret file bind-mount check:
   - Use `grep` (not jq — YAML is not JSON) to check if secret files are bind-mounted
   - If bind-mounted: use 640 permissions with Docker GID, not 600

### Phase D: Protection Surface Expansion

Expand the protected files list and enforce permissions.

1. **Add to `_integrity_protected_file_patterns()`**:
   - `.git/config` — always (VCS remote URLs)
   - `n8n/workflows/*.json` — existence-gated (`find` with `-maxdepth 1`)
   - `.specify/memory/constitution.md` — existence-gated

2. **Permission verification function** — `_integrity_check_permissions()`:
   - Secret files (`scripts/templates/secrets/*`): must be 600
   - Check if secret file is Docker-bind-mounted (parse docker-compose.yml with jq): if yes, use 640 with Docker GID instead of 600
   - Audit directories (`~/.openclaw/logs/`, `~/.openclaw/reports/`): must be 700
   - Report permission violations as WARN with current vs expected permissions

3. **Update integrity-deploy.sh** — after expanding `_integrity_protected_file_patterns()`, the next `make integrity-deploy` MUST include new files in manifest checksum computation. Add auto-detection: `integrity-verify.sh` warns if protected files exist but are not in the manifest.

4. **Docker socket permission check** (FR-034):
   - Verify `~/.colima/default/docker.sock` has mode 0600, owned by current user
   - Non-matching permissions → WARNING "docker_socket_permissions"
   - Trust boundary documentation in verification output JSON

### Phase E: Monitor Daemon Remediation

Apply all Phase A-D fixes to `integrity-monitor.sh`.

1. **Credential exposure**: Replace 3 `<<<` instances with `_integrity_safe_credential_write()`
2. **Output bounding**: All `docker exec`, `docker diff`, `docker inspect` through `integrity_run_with_timeout 30`
3. **JSON validation**: All API response parsing through `_integrity_validate_json()`
4. **Process group**: Heartbeat and container-poll background loops must be killable via SIGTERM to process group
5. **Container poll via timeout**: `_container_monitor_cycle` runs through `integrity_run_with_timeout $CONTAINER_POLL_TIMEOUT`

### Phase F: HMAC Key Rotation & Integration Testing

1. **Key rotation command** — `integrity-rotate-key.sh`:
   - Generate new HMAC key, store in Keychain
   - Re-sign all state files atomically (manifest, lock-state, container-security-config, container-verify-state)
   - Last audit entry signed with old key; next entry with new key
   - Log "hmac_key_rotated" to audit trail

2. **Integration testing**:
   - Container disappearance during verification → FAIL + cascade abort
   - Concurrent audit log writes (2 processes) → hash chain valid
   - Process group timeout → 100% descendants killed
   - Invalid JSON to each wrapper → error (not "0 findings")
   - Docker-bench hash tamper → execution blocked
   - Permission enforcement → secrets 600, audit dirs 700
   - Monitor daemon credential exposure → none in lsof/ps

## Design Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | `set -m` for process groups | `setsid` unavailable on macOS; `set -m` is native bash |
| 2 | Temp files in `~/.openclaw/tmp/` | Mode 700 dir eliminates symlink TOCTOU |
| 3 | `F_FULLFSYNC` via python3 | macOS `fsync()` doesn't guarantee persistence |
| 4 | PID + start time for locks | PID recycling real risk (99999 PID space) |
| 5 | Combined jq validation+extraction | Eliminates double parse, catches structure issues |
| 6 | Commit hash pinning for bench | Tag-based clone can be spoofed by MITM |
| 7 | Regex for action validation | Allowlist too high maintenance for evolving actions |
| 8 | Escape (not strip) details | Preserves forensic content in audit trail |
| 9 | `bash -c "$cmd"` for pipeline | Preserves space-separated args while preventing word splitting |
| 10 | Docker socket check as heuristic | Cannot fully verify daemon integrity, but raises the bar |

## Risk Log

| Risk | Mitigation |
|------|-----------|
| `set -m` may interfere with existing job control | Scope `set -m` to within `integrity_run_with_timeout` only; restore `set +m` after |
| python3 dependency for F_FULLFSYNC | python3 is shipped with macOS; fallback to no fsync if unavailable |
| Secret file permission tightening may break Docker bind mount | Check docker-compose.yml before tightening; use 640 if bind-mounted |
| Commit hash update requires manual operator action | `make security-update-hashes` makes it a single command |
| Process group escapees (child calls setsid) | Post-timeout `pgrep -P` sweep; best-effort detection |

## Artifacts

| File | Status |
|------|--------|
| phase4-spec.md | Complete (41 FRs, 10 SCs, adversarial review addressed) |
| phase4-research.md | Complete (10 research decisions) |
| phase4-quickstart.md | Complete (verification procedures + recovery) |
| phase4-plan.md | This file |
| phase4-tasks.md | Pending (next: `/speckit.tasks`) |
