# Tasks: Adversarial Review Remediation (Phase 4B)

**Input**: Design documents from `/specs/013-adversarial-remediation/`
**Prerequisites**: plan.md, spec.md, research.md, quickstart.md

**Organization**: Tasks grouped by user story (US1-US9) with shared foundational phase. 44 FRs across 9 user stories, 15 success criteria.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1-US9 maps to spec user stories

---

## Phase 1: Setup

**Purpose**: Validate platform primitives and establish shared patterns

- [X] T001 Create trap save/restore helper functions `_integrity_save_err_trap()` and `_integrity_restore_err_trap()` in `scripts/lib/integrity.sh` — pattern: `_saved_err=$(trap -p ERR)` to save, `eval "$_saved_err"` to restore. These are used by all subsequent trap-related fixes (FR-010).
- [X] T002 Create `_integrity_validate_lock_path()` helper in `scripts/lib/integrity.sh` — validates lock directory path is non-empty and matches expected pattern `*integrity-audit.log.lock*` before any `rm -rf` operation (FR-044).

**Checkpoint**: Shared helpers ready — foundational fixes can begin.

---

## Phase 2: Foundational — Core Library Fixes (integrity.sh)

**Purpose**: Fix core library functions that ALL scripts depend on. Every subsequent phase inherits these.

**CRITICAL**: No user story work can begin until this phase is complete.

- [X] T003 [US1] Wrap `docker inspect` inside `integrity_capture_container_snapshot()` with `integrity_run_with_timeout 30` in `scripts/lib/integrity.sh` (FR-002).
- [X] T004 [US1] Wrap `docker ps` inside `integrity_discover_container()` with `integrity_run_with_timeout 10` in `scripts/lib/integrity.sh` (FR-003).
- [X] T005 [US1] Wrap `docker context inspect` inside `integrity_docker_socket_path()` with `integrity_run_with_timeout 5` in `scripts/lib/integrity.sh` (FR-009).
- [X] T006 [US2] Rewrite `_integrity_safe_atomic_write()` in `scripts/lib/integrity.sh` — save ERR trap via `_integrity_save_err_trap`, set `umask 077` before mktemp, restore umask after, use RETURN trap for cleanup (function-scoped in Bash 5.x), clear cleanup trap after successful `mv`, restore ERR trap on all exit paths (FR-010, FR-011, FR-012).
- [X] T007 [US2] Rewrite audit log lock in `integrity_audit_log()` in `scripts/lib/integrity.sh` — install RETURN+INT+TERM trap for lock cleanup immediately after `mkdir` succeeds, use `_integrity_validate_lock_path` + `rm -rf` for stale lock removal, retry `mkdir` after stale removal (FR-013, FR-019, FR-020, FR-044).
- [X] T008 [US2] Add `chmod 600` immediately after mktemp in `_integrity_safe_credential_write()` in `scripts/lib/integrity.sh` (FR-014).
- [X] T009 [US2] Remove `|| true` from `_integrity_init_tmp_dir` call in `scripts/lib/integrity.sh` — set `_INTEGRITY_INIT_OK=true` on success, add guard checks to security-critical functions (signing, audit log, credential, atomic write). Leave non-critical helpers ungated per RD-013 (FR-016).
- [X] T010 [US3] Add process group verification to `integrity_run_with_timeout()` in `scripts/lib/integrity.sh` — after `"$@" &`, check `ps -o pgid= -p $cmd_pid`. If PGID != PID, log warning and use `pkill -P $pid` fallback instead of `kill -TERM -$pgid` (FR-017, FR-018).
- [X] T011 [US5] Fix TMPDIR validation in `integrity_check_env_vars()` in `scripts/lib/integrity.sh` — reject paths containing `..` before regex match, canonicalize via `cd "$dir" && pwd -P` after regex pass, re-validate canonical path (FR-021, FR-022).
- [X] T012 [US9] Clamp exit code in `_integrity_check_permissions()` in `scripts/lib/integrity.sh` — replace `return "$violations"` with `[[ $violations -gt 0 ]] && return 1 || return 0` (FR-031).
- [X] T013 [US9] Clamp exit code in `integrity_check_env_vars()` in `scripts/lib/integrity.sh` — same pattern (FR-032).
- [X] T014 [P] [US7] Fix `_integrity_validate_json()` in `scripts/lib/integrity.sh` — change `2>&1` to `2>/dev/null` for result capture. On error, re-run with stderr captured to `_jq_err` variable for diagnostics (FR-026).
- [X] T015 [P] Fix `grep -q` to `grep -qF` in `_integrity_check_permissions()` docker-compose bind-mount check in `scripts/lib/integrity.sh` (FR-040).
- [X] T016 [P] Fix F_FULLFSYNC fallback in `integrity_audit_log()` in `scripts/lib/integrity.sh` — check `command -v python3` first, fall back to `sync` with logged warning. Replace `|| true` with explicit fallback (FR-041).
- [X] T017 [P] Ensure `integrity_get_signing_key()` fails closed in `scripts/lib/integrity.sh` — return non-zero with error when Keychain locked/inaccessible, never fall back to empty key (FR-042).
- [X] T018 [US6] Mitigate HMAC key exposure in `integrity_sign_manifest()` in `scripts/lib/integrity.sh` — write key to mode-600 temp file, read back, pass to openssl, clean up via trap. Document accepted limitation per RD-015 (FR-023).

**Checkpoint**: Core library hardened. All scripts that source integrity.sh inherit timeout, trap, and validation fixes.

---

## Phase 3: Timeout Authority — Remaining Docker Calls (US1, Priority: P1)

**Goal**: Every Docker CLI invocation across the entire codebase has an explicit timeout.

**Independent Test**: Set `DOCKER_HOST=unix:///nonexistent` and run `make integrity-verify`. Pipeline completes with errors in <60s.

- [X] T019 [US1] Wrap `docker exec ... true` liveness check in `check_container_workflows()` in `scripts/integrity-verify.sh` with `integrity_run_with_timeout 5` (FR-006).
- [X] T020 [US1] Wrap `docker inspect` in final re-verification step of `_run_container_checks()` in `scripts/integrity-verify.sh` with `integrity_run_with_timeout 5` (FR-008).
- [X] T021 [US1] Wrap `docker ps` liveness checks in `check_container_credentials()` and `check_container_community_nodes()` in `scripts/integrity-verify.sh` with `integrity_run_with_timeout 5` (FR-035).
- [X] T022 [P] [US1] Wrap `docker info` reachability check in `scripts/container-bench.sh` with `integrity_run_with_timeout 10` (FR-005).
- [X] T023 [P] [US1] Wrap `docker image inspect` in `scripts/scan-image.sh` with `integrity_run_with_timeout 10` (FR-007).
- [X] T024 [P] [US1] Wrap standalone `grype` scan in `scripts/scan-image.sh` with `integrity_run_with_timeout 300` (FR-004).
- [X] T025 [US1] Wrap `docker exec` calls in baseline capture in `scripts/integrity-deploy.sh` (3 retry loop) with `integrity_run_with_timeout 10` each (FR-034).
- [X] T026 [US1] Timeout-wrap all ~12 `docker exec`/`docker ps` calls in `scripts/workflow-sync.sh` with `integrity_run_with_timeout 30` — source `scripts/lib/integrity.sh` if not already sourced. Note: credential fix (FR-024) is handled separately in T034 (FR-001).
- [X] T027 [US1] Timeout-wrap docker calls in `scripts/hardening-audit.sh` — add 30s default timeout to `docker inspect`/`docker exec` calls. Keep `|| true` on integrity.sh source line per RD-013 (FR-001).

**Checkpoint**: `grep -rn '\bdocker\b' scripts/ | grep -v integrity_run_with_timeout | grep -v '#'` returns zero unprotected calls.

---

## Phase 4: Trap Integrity — Credential and Lock Cleanup (US2, Priority: P1)

**Goal**: Every credential temp file is trap-protected. Audit log lock has trap-based cleanup.

**Independent Test**: Source integrity.sh, set ERR trap, call `_integrity_safe_atomic_write()`, verify ERR trap preserved.

- [X] T028 [US2] Add credential trap protection to `check_container_credentials()` in `scripts/integrity-verify.sh` — save existing EXIT trap, install cleanup trap for credential temp file, restore on completion (FR-015, FR-025).
- [X] T029 [US2] Add credential trap protection to `_container_monitor_cycle()` in `scripts/integrity-monitor.sh` — same pattern as T028 (FR-015, FR-025).
- [X] T030 [US2] Add credential trap protection to `integrity_capture_container_baseline()` in `scripts/lib/integrity.sh` — same pattern (FR-015, FR-025).

**Checkpoint**: Kill process during credential enumeration — no residual curl config files in `~/.openclaw/tmp/`.

---

## Phase 5: Process Group Verification (US3, Priority: P1)

**Goal**: `integrity_run_with_timeout` verifies process group creation and falls back to tree killing.

**Independent Test**: Run timeout function inside a pipeline context. Verify fallback detection.

Note: T010 in Phase 2 implements the core fix. This phase validates it.

- [X] T031 [US3] Verify T010 implementation handles the pipeline subshell case — create test in `scripts/test-phase4b-integration.sh` that runs `integrity_run_with_timeout` inside `$(...)` and verifies fallback to `pkill -P` (SC-007).

**Checkpoint**: Process group verification working in all contexts.

---

## Phase 6: Lock Integrity — Concurrent Access (US4, Priority: P2)

**Goal**: Concurrent writers cannot both acquire the audit log lock.

**Independent Test**: 10 processes x 10 entries — hash chain valid 100% of the time.

Note: T007 in Phase 2 implements the core fix. This phase validates it.

- [X] T032 [US4] Create concurrent write stress test in `scripts/test-phase4b-integration.sh` — 10 processes x 10 entries, verify hash chain validity. Also test SIGKILL mid-write recovery and stale lock contention (SC-003).

**Checkpoint**: 100 concurrent writes, valid hash chain, no stale lock residue.

---

## Phase 7: Input Canonicalization — TMPDIR Traversal (US5, Priority: P2)

**Goal**: TMPDIR paths with `..` components are rejected.

**Independent Test**: `TMPDIR=/var/folders/ab/x/T/../../etc` is rejected.

Note: T011 in Phase 2 implements the core fix. This phase validates it.

- [X] T033 [US5] Create TMPDIR traversal test suite in `scripts/test-phase4b-integration.sh` — 10+ attack paths including `../`, symlinked prefixes, double-encoding (SC-004).

**Checkpoint**: All traversal variants rejected, valid paths accepted.

---

## Phase 8: Credential Opacity (US6, Priority: P2)

**Goal**: No HMAC key or API key visible in `ps` or `lsof`.

**Independent Test**: `ps aux | grep openssl` during signing shows no key material.

- [X] T034 [US6] Replace `-H "X-N8N-API-KEY: ..."` patterns in `scripts/workflow-sync.sh` with `_integrity_safe_credential_write()` + `curl --config`. Depends on T026 (which adds integrity.sh sourcing and timeouts to the same file) (FR-024).
- [X] T035 [US6] Create credential opacity integration test in `scripts/test-phase4b-integration.sh` — run signing operation with parallel `ps aux` monitoring (SC-005).

**Checkpoint**: Zero credential material in process listings.

---

## Phase 9: Failure Transparency (US7, Priority: P2)

**Goal**: Parse failures produce errors, never "0 findings."

**Independent Test**: Feed invalid JSON to each wrapper, verify non-zero exit.

- [X] T036 [US7] Fix `|| var=0` fallback in `scripts/container-bench.sh` — log warning when fallback triggers, set `_parse_fallback=true` flag, exit WARN (not PASS) when flag is set (FR-027, FR-028).
- [X] T037 [P] [US7] Fix `|| var=0` fallback in `scripts/scan-image.sh` — same pattern as T036 (FR-027, FR-028).
- [X] T038 [US7] Create false-negative detection test in `scripts/test-phase4b-integration.sh` — feed structurally wrong JSON to each wrapper (SC-006).

**Checkpoint**: Invalid JSON → non-zero exit, never "0 findings."

---

## Phase 10: Liveness Authority + Command Dispatch + First-Run (US8 + H8 + H9)

**Goal**: Drift/community checks have liveness gates. Pipeline dispatch is safe. First-run requires confirmation.

- [X] T039 [US8] Add `_verify_container_alive || return` before `check_container_drift()` in `_run_container_checks()` in `scripts/integrity-verify.sh` (FR-029).
- [X] T040 [US8] Add `_verify_container_alive || return` before `check_container_community_nodes()` in `_run_container_checks()` in `scripts/integrity-verify.sh` (FR-030).
- [X] T041 Eliminate `bash -c "$cmd"` in `scripts/security-pipeline.sh` — convert LAYERS array to separate script path + args arrays, invoke via `integrity_run_with_timeout "$LAYER_TIMEOUT" "$script" $args` (FR-036).
- [X] T042 Add first-run baseline confirmation to `scripts/integrity-deploy.sh` — detect no prior manifest, display summary (file count, image digest, n8n version, credential count, node count), prompt operator confirmation. Add `--force` flag for CI and `--verify-baseline` flag for audit (FR-037, FR-038).
- [X] T043 Fix PIPESTATUS subshell issue in workflow export in `scripts/integrity-verify.sh` — write to temp file via `integrity_run_with_timeout`, then read + truncate separately. Detect truncation by comparing file size (FR-039).

**Checkpoint**: Liveness gates consistent. Pipeline dispatch safe. First-run prompts operator.

---

## Phase 11: Exit Code Safety (US9, Priority: P3)

Note: T012 and T013 in Phase 2 implement the core fixes. This phase validates.

- [X] T044 [US9] Create exit code overflow test in `scripts/test-phase4b-integration.sh` — verify functions with >255 violations still return non-zero (SC-010).

---

## Phase 12: Integration Tests + Polish

**Purpose**: Validate all 15 success criteria, regression test, codebase audit, traceability.

- [X] T045 Create `scripts/test-phase4b-integration.sh` test harness with functions for all 15 SCs (consolidates test functions from T031-T044 into a single executable suite).
- [X] T046 Implement test_docker_audit (SC-001) — `grep -rn '\bdocker\b' scripts/` audit verifying zero unprotected calls.
- [X] T047 Implement test_trap_preservation (SC-002) — source integrity.sh, set ERR trap, call atomic write, verify ERR trap intact.
- [X] T048 Implement test_lock_crash (SC-008) — send SIGTERM during audit write, verify no stale lock.
- [X] T049 Implement test_symlink_init (SC-009) — create temp symlink at `~/.openclaw`, verify init refuses, clean up.
- [X] T050 Implement test_command_dispatch (SC-011) — test pipeline with command containing `$(echo evil)`, verify no execution.
- [X] T051 Implement test_first_run (SC-012) — run deploy with no prior manifest, pipe `y` to stdin, verify prompt and confirmation.
- [X] T052 Implement test_pipestatus (SC-013) — generate >1MB workflow export output, verify truncation detected.
- [X] T053 Implement test_grep_fixed (SC-014) — create test file `test.key`, verify `.` not treated as regex wildcard.
- [X] T054 Implement test_performance (SC-015) — time `make integrity-verify`, verify <120s total, <5s overhead from changes.
- [X] T055 Add key rotation exclusive lock to `scripts/integrity-rotate-key.sh` — acquire lock before Keychain modification, fail on concurrent rotation (FR-043).
- [X] T056 Run existing `scripts/test-phase4-integration.sh` regression test — verify all existing Phase 4 tests still pass after 4B changes.
- [X] T057 Create `specs/013-adversarial-remediation/phase4b-traceability.md` — map all 26 adversarial findings to implementing FR(s) and task(s), verify 100% coverage.
- [X] T058 Run `scripts/test-phase4b-integration.sh` full suite — all 15 SCs must pass.
- [X] T059 Update `specs/013-adversarial-remediation/spec.md` status from Draft to Complete.

**Checkpoint**: All 15 SCs validated. All 26 findings remediated. Regression tests pass.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 — BLOCKS all user stories
- **Phase 3 (US1 Timeout)**: Depends on Phase 2 (library timeout functions)
- **Phase 4 (US2 Traps)**: Depends on Phase 2 (trap helpers)
- **Phase 5 (US3 PGID)**: Depends on Phase 2 (process group fix)
- **Phase 6 (US4 Lock)**: Depends on Phase 2 (lock fix)
- **Phase 7 (US5 TMPDIR)**: Depends on Phase 2 (TMPDIR fix)
- **Phase 8 (US6 Creds)**: Depends on Phase 2 (credential hardening)
- **Phase 9 (US7 JSON)**: Depends on Phase 2 (validate_json fix)
- **Phase 10 (US8+H8+H9)**: Depends on Phase 3 (timeout functions available)
- **Phase 11 (US9)**: Depends on Phase 2 (exit code clamp)
- **Phase 12 (Polish)**: Depends on all prior phases

### Parallel Opportunities

```
After Phase 2 (Foundational) completes:
  Phase 3 (US1 Timeout)    ─┐
  Phase 4 (US2 Traps)      ─┤
  Phase 5 (US3 PGID)       ─┤ can run in parallel
  Phase 6 (US4 Lock)       ─┤
  Phase 7 (US5 TMPDIR)     ─┤
  Phase 8 (US6 Creds)      ─┤
  Phase 9 (US7 JSON)       ─┤
  Phase 11 (US9 Exit Code) ─┘

Within Phase 2:
  T014, T015, T016, T017 can run in parallel (different functions)

Within Phase 3:
  T022, T023, T024 can run in parallel (different files)
```

---

## Implementation Strategy

### MVP First (Phases 1-3 Only)

1. Complete Phase 1: Setup helpers
2. Complete Phase 2: Foundational library fixes
3. Complete Phase 3: Timeout authority
4. **STOP AND VALIDATE**: `DOCKER_HOST=unix:///nonexistent make integrity-verify` completes in <60s

### Incremental Delivery

1. Phase 1+2 → Library hardened
2. Phase 3 → All Docker calls timeout-bounded (MVP)
3. Phase 4 → Trap integrity verified
4. Phase 5-9 → Each user story independently validated
5. Phase 10 → Remaining fixes (liveness, dispatch, first-run)
6. Phase 11 → Exit code safety
7. Phase 12 → Full integration test suite passes

---

## Summary

- **Total tasks**: 59 (T001-T059)
- **Phase 1 (Setup)**: 2 tasks
- **Phase 2 (Foundational)**: 16 tasks
- **Phase 3-11 (User Stories)**: 26 tasks
- **Phase 12 (Polish)**: 15 tasks
- **Parallel opportunities**: 8 phases can run in parallel after Phase 2
- **MVP scope**: Phase 1-3 (20 tasks) — all Docker calls timeout-bounded
