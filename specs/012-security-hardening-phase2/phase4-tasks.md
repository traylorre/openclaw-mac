# Tasks: Security Remediation & Hardening Depth (Phase 4)

**Input**: Design documents from `/specs/012-security-hardening-phase2/phase4-*.md`
**Prerequisites**: phase4-plan.md, phase4-spec.md, phase4-research.md, phase4-quickstart.md

**Organization**: Tasks follow the plan's 6 implementation phases (A-F), with US labels mapping to spec user stories 1-9.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1-US9 maps to spec user stories

---

## Phase 1: Setup (Validation)

**Purpose**: Validate platform-specific primitives before production use

- [X] T001 Create `set -m` job control validation test in `scripts/test-job-control.sh` — tests: process group creation, `kill -TERM -$pgid`, nested contexts, interaction with `set -euo pipefail`, subshell behavior, trap handlers. If any test fails, document fallback to Perl `POSIX::setsid()`.
- [X] T002 Run `scripts/test-job-control.sh` on macOS Ventura and record results. If `set -m` fails nested context test, switch plan to Perl approach and update phase4-research.md Decision 1.

**Checkpoint**: Platform primitives validated — foundational implementation can begin.

---

## Phase 2: Foundational (Safe Primitives Library)

**Purpose**: Core safe operation primitives in `scripts/lib/integrity.sh` that ALL subsequent phases depend on.

**CRITICAL**: No user story work can begin until this phase is complete.

- [X] T003 [US2] Create `~/.openclaw/tmp/` directory (mode 700) initialization in `scripts/lib/integrity.sh` — add to existing directory setup, validate `~/.openclaw/` and parents are not symlinks (FR-006, FR-027).
- [X] T004 [US2] Implement `_integrity_safe_atomic_write()` in `scripts/lib/integrity.sh` — mktemp in `~/.openclaw/tmp/`, post-creation symlink check, content write, `mv` to target, trap-based cleanup on RETURN/ERR/EXIT/INT/TERM (FR-005). Deploy for heartbeat file ONLY first.
- [X] T005 [US8] Implement `_integrity_safe_credential_write()` in `scripts/lib/integrity.sh` — temp file in `~/.openclaw/tmp/`, format as curl config, EXIT trap cleanup (not RETURN — RETURN doesn't fire on SIGTERM in subshells), return path for `curl --config` (FR-026).
- [X] T006 [US3] Rewrite `integrity_run_with_timeout()` in `scripts/lib/integrity.sh` — `set -m` + `"$@" &` for process group, `kill -TERM -$pgid` + 2s grace + `kill -KILL -$pgid` on timeout, `pgrep -P $pgid` escapee detection, watchdog cleanup on normal completion, restore `set +m` (FR-007, FR-008, FR-009).
- [X] T007 [US4] Implement `_integrity_validate_json()` in `scripts/lib/integrity.sh` — combined validation+extraction via `jq -e '$expr // error("missing $field")'`, replaces all `2>/dev/null || echo 0` patterns. Takes jq expression + input, returns extracted value or exits non-zero with logged error (FR-011).
- [X] T008 [US9] Rewrite audit log lock in `integrity_audit_log()` in `scripts/lib/integrity.sh` — atomic `mkdir` + PID+start-time file (`$$ $(ps -o lstart= -p $$)`), trap cleanup for both PID file and lock dir, stale detection via `kill -0` + start time comparison, missing PID file = stale after 30s (FR-029).
- [X] T009 [US9] Harden audit log write in `integrity_audit_log()` in `scripts/lib/integrity.sh` — remove `chmod ... || true` (detect and return errors), F_FULLFSYNC via `python3 -c "import os,fcntl,sys; fd=os.open(sys.argv[1],os.O_RDONLY); fcntl.fcntl(fd,51); os.close(fd)" "$file"` for manifest/lock-state (FR-030, FR-031).
- [X] T010 [US7] Add audit log action validation in `integrity_audit_log()` in `scripts/lib/integrity.sh` — regex `^[a-z][a-z0-9_]{2,48}$`, reject invalid actions with error. Ensure all detail values go through jq `--arg` for newline escaping (FR-023, FR-024).
- [X] T011 [US7] Fix TMPDIR validation in `scripts/lib/integrity.sh` — replace case statement (lines 546-556) with regex `^(/tmp|/private/tmp|/var/folders/[a-zA-Z0-9_+]{2}/[^/]+/T)(/.*)?$` (FR-032).
- [X] T012 [US7] Implement `_integrity_validate_container_name()` in `scripts/lib/integrity.sh` — regex `^[a-zA-Z][a-zA-Z0-9_-]{0,63}$`, called before `docker ps --filter name=`. Migration: if existing config value fails, log warning, fall back to default `"n8n"` (FR-025).
- [X] T013 [US4] Fix PKG_DELIMITER injection in community node parsing in `scripts/lib/integrity.sh` (lines 867-898) — validate each parsed segment with `_integrity_validate_json()` before field extraction, log and count parse failures (FR-012).
- [X] T014 [US9] Remove all `|| echo 0` patterns in `scripts/lib/integrity.sh` (lines 352, 508, 592) — date parsing failures produce hard error (return 1), not epoch 0 fallback. Lock stat failures use PID-based liveness check (FR-037).
- [X] T015 Validate `_integrity_safe_atomic_write()` works in monitor daemon loop — deploy for heartbeat file, run monitor for 1 cycle, verify file written correctly. Then expand to manifest, lock-state, container-security-config, container-verify-state.

**Checkpoint**: Foundation ready — all safe primitives tested. User story implementation can begin.

---

## Phase 3: Fail-Fast Verification Cascade (US1, Priority: P1) MVP

**Goal**: When a high-trust check fails, all downstream checks abort immediately.

**Independent Test**: Kill the container during verification. Verify downstream checks are SKIPPED and result is FAIL.

- [X] T016 [US1] Define trust tier constants in `scripts/integrity-verify.sh` — HIGH = {container_exists, image_digest, runtime_config}, PARTIAL = {credential_enum, workflow_compare}, ADVISORY = {drift_detection, community_node_scan} (FR-001).
- [X] T017 [US1] Implement `fail()` with severity parameter in `scripts/integrity-verify.sh` — `fail CRITICAL "msg"` sets `_CASCADE_ABORT=true` + increments ERRORS, `fail WARNING "msg"` increments WARNINGS only. Scoped to container check pipeline, not global (FR-003).
- [X] T018 [US1] Implement `_verify_container_alive()` in `scripts/integrity-verify.sh` — `docker ps -q --filter "id=$CID"` with 5s timeout via `integrity_run_with_timeout`, check `.State.Paused`, distinguish timeout (exit 124 → UNKNOWN) from absent (→ FAIL). Called before every docker inspect/exec/diff (FR-002).
- [X] T019 [US1] Add cascade abort gate before each check function in `scripts/integrity-verify.sh` — `[[ "$_CASCADE_ABORT" == "true" ]] && { log_warn "SKIPPED: upstream CRITICAL"; return 0; }`. Reconcile with existing early-return pattern in `_run_container_checks` (lines 1101-1131) (FR-001).
- [X] T020 [US1] Add final re-verification at end of check pipeline in `scripts/integrity-verify.sh` — compare container ID AND image digest against start-of-pipeline values. Container replaced → FAIL "container_replaced_during_verification" (FR-004).
- [X] T021 [US1] Add `trust_assumptions` field to verification result JSON in `scripts/integrity-verify.sh` — list: "Docker daemon integrity assumed", "Colima VM integrity assumed", "Keychain integrity assumed" (FR-033).
- [X] T022 [US1] Add output bounding to all `docker exec` calls in `scripts/integrity-verify.sh` — wrap with `integrity_run_with_timeout 30`, pipe stdout through `head -c 1048576`, detect truncation via exit status 141, log "output_truncated" (FR-010).
- [X] T023 [US1] Replace all `2>/dev/null || echo 0` and `|| true` patterns in `scripts/integrity-verify.sh` with `_integrity_validate_json()` calls — credential enum (line 690), workflow compare, community node parsing (FR-011).
- [X] T024 [US1] Fix credential exposure in `scripts/integrity-verify.sh` (line 687) — replace `<<<` here-string with `_integrity_safe_credential_write()` + `curl --config "$tmpfile"` (FR-026).
- [X] T025 [US1] Wrap all `docker inspect`, `docker ps`, `docker diff` calls in `scripts/integrity-verify.sh` **and** `scripts/lib/integrity.sh` with `integrity_run_with_timeout 30` (FR-010a).

**Checkpoint**: `make integrity-verify` with fail-fast cascade working. Kill container mid-check → SKIPPED + FAIL.

---

## Phase 4: Security Tool Hardening (US5 + US7, Priority: P1/P2)

**Goal**: Security tools verified for tampering, command injection eliminated, parse failures produce errors.

**Independent Test**: Modify docker-bench clone → refused. Feed invalid JSON → error (not "0 findings").

- [X] T026 [US7] Fix command injection in `scripts/security-pipeline.sh` (line 73) — change `bash $cmd` to `bash -c "$cmd"`, each layer runs through `integrity_run_with_timeout` with process group isolation (FR-021, FR-038).
- [X] T027 [US7] Remove output suppression in `scripts/security-pipeline.sh` — capture layer output to `~/.openclaw/tmp/layer-$N.log` for debugging instead of `>/dev/null 2>&1`.
- [X] T028 [US5] Implement trust-on-first-use hash storage in `Makefile` — new `security-update-hashes` target: computes docker-bench commit hash + grype binary SHA-256, stores in container-security-config.json via HMAC-signed write, logs to audit trail. If no pinned hash exists, compute and store on first run (FR-016). **Must complete before T029, T035.**
- [X] T029 [US5] Add commit hash verification to `scripts/container-bench.sh` — after clone: `git rev-parse HEAD` must match pinned hash from config. Before each run: re-verify existing clone hash. Mismatch → delete clone, log "supply_chain_verification_failed" (FR-014).
- [X] T030 [US5] Remove `|| true` from docker-bench-security execution in `scripts/container-bench.sh` (line 61) — capture exit code, non-zero after supply-chain pass → FAIL (not SKIP) (FR-039).
- [X] T031 [P] [US4] Add JSON validation to `scripts/container-bench.sh` — replace `jq ... 2>/dev/null || echo 0` (lines 71-75) with `_integrity_validate_json()` pattern. Validate `.tests` field exists before counting (FR-011, FR-013).
- [X] T032 [US7] Replace sed-based JSON extraction in `scripts/n8n-audit.sh` (line 66) — use `grep -m1 -n '^[{[]'` + `tail -n +$N` + `jq -e` validation. If no JSON-starting line found, report "no_valid_json_in_output" (FR-022, FR-040).
- [X] T033 [US4] Add output bounding to docker exec in `scripts/n8n-audit.sh` (line 50) — wrap with `integrity_run_with_timeout 30`, pipe through `head -c 1048576` (FR-010).
- [X] T034 [P] [US4] Replace `|| echo 0` patterns in `scripts/n8n-audit.sh` (lines 79, 89-92) with `_integrity_validate_json()` (FR-011).
- [X] T035 [US5] Enforce exact Grype version match in `scripts/scan-image.sh` — change from prefix match to exact: `[[ "$grype_version" == "$EXPECTED" ]]`. Add binary SHA-256 hash verification: `shasum -a 256 "$(which grype)"` vs pinned hash. Either mismatch → FAIL "tool_integrity_failed" (FR-015).
- [X] T036 [P] [US4] Replace `|| echo 0` patterns in `scripts/scan-image.sh` (lines 72, 80) with `_integrity_validate_json()` — validate `.matches` field exists before counting (FR-011, FR-013).

**Checkpoint**: `make security` — all tools hash-verified, parse failures produce errors, no command injection.

---

## Phase 5: Protection Surface Expansion (US6, Priority: P2)

**Goal**: All sensitive files protected, permissions enforced, Docker socket verified.

**Independent Test**: Modify `.git/config` → detected. Check secrets have mode 600.

- [X] T037 [US6] Add `.git/config` to `_integrity_protected_file_patterns()` in `scripts/lib/integrity.sh` — always include (FR-017).
- [X] T038 [US6] Add `n8n/workflows/*.json` to `_integrity_protected_file_patterns()` in `scripts/lib/integrity.sh` — existence-gated with `find -maxdepth 1` (FR-018).
- [X] T039 [US6] Add `.specify/memory/constitution.md` to `_integrity_protected_file_patterns()` in `scripts/lib/integrity.sh` — existence-gated with `[[ -f ]]` check (FR-019).
- [X] T040 [US6] Implement `_integrity_check_permissions()` in `scripts/lib/integrity.sh` — check secrets (`scripts/templates/secrets/*`) for mode 600, audit dirs (`~/.openclaw/logs/`, `~/.openclaw/reports/`) for mode 700. Check if secret is Docker-bind-mounted (grep docker-compose.yml): if yes, use 640 with Docker GID (FR-020, FR-028, FR-041).
- [X] T041 [US6] Add Docker socket permission check in `scripts/lib/integrity.sh` — verify `~/.colima/default/docker.sock` has mode 0600, owned by current user. Non-matching → WARNING "docker_socket_permissions" (FR-034).
- [X] T042 [US6] Update `scripts/integrity-deploy.sh` — after expanded protection surface, `make integrity-deploy` must include new files in manifest. Add auto-detection: `integrity-verify.sh` warns if protected files exist but are not in manifest.
- [X] T043 [US6] Integrate permission check into `scripts/integrity-verify.sh` — call `_integrity_check_permissions()` as an ADVISORY-tier check after container checks.

**Checkpoint**: `make integrity-verify` — 80+ protected files, permissions enforced, Docker socket checked.

---

## Phase 6: Credential Exposure + Atomic Write Expansion (US8 + US2, Priority: P2)

**Goal**: No API key material in process listings. All state files use safe atomic writes.

**Independent Test**: Run verification, check `lsof` and `ps` for API key exposure — none found.

- [X] T044 [US8] Fix credential exposure in `scripts/lib/integrity.sh` (line 840) — replace `<<<` here-string with `_integrity_safe_credential_write()` + `curl --config "$tmpfile"` (FR-026).
- [X] T045 [US8] Fix credential exposure in `scripts/integrity-monitor.sh` (line 304) — replace `<<<` with `_integrity_safe_credential_write()`. Add `rm -f ~/.openclaw/tmp/curl-*` to monitor's SIGTERM handler (line 417) for orphaned credential cleanup (FR-026, FR-035).
- [X] T046 [US2] Expand `_integrity_safe_atomic_write()` usage to manifest write in `scripts/integrity-deploy.sh` (lines 226-235) — replace mktemp+chmod+mv with safe function. Add manifest merge validation: verify merge succeeded before re-signing (FR-005).
- [X] T047 [P] [US2] Expand `_integrity_safe_atomic_write()` usage to state file signing in `scripts/lib/integrity.sh` (lines 302-312) — replace existing mktemp+chmod+mv (FR-005).
- [X] T048 [P] [US2] Expand `_integrity_safe_atomic_write()` usage to Makefile (lines 284, 296) — replace mktemp+chmod+mv in hooks-setup/teardown targets (FR-005).

**Checkpoint**: Zero credential exposure via lsof/ps. All state files use atomic writes.

---

## Phase 7: Monitor Daemon Remediation (Cross-cutting, all P1/P2 stories)

**Goal**: All Phase 2-6 fixes applied to the long-running integrity-monitor.sh daemon.

**Independent Test**: Run monitor for 1 cycle — no credential exposure, all docker calls timeout-bounded, JSON validated.

- [X] T049 [US3] Update monitor trap handler in `scripts/integrity-monitor.sh` (line 417) — send SIGTERM to process groups (not individual PIDs) for heartbeat and container-poll subshells (FR-035).
- [X] T050 [US4] Wrap all `docker exec`, `docker diff`, `docker inspect` calls in monitor polling loops in `scripts/integrity-monitor.sh` with `integrity_run_with_timeout 30` (FR-010a, FR-035).
- [X] T051 [US4] Replace all JSON parsing in monitor API response handling in `scripts/integrity-monitor.sh` with `_integrity_validate_json()` — no `2>/dev/null || echo 0` patterns (FR-011, FR-035).
- [X] T052 [US3] Run `_container_monitor_cycle` through `integrity_run_with_timeout $CONTAINER_POLL_TIMEOUT` in `scripts/integrity-monitor.sh` (FR-035).
- [X] T053 Remove `|| true` from `_container_monitor_cycle` invocation in `scripts/integrity-monitor.sh` (line 409) — replace with `|| log_warn "container monitor cycle failed"` (FR-035).

**Checkpoint**: Monitor daemon fully hardened — same security posture as one-shot tools.

---

## Phase 8: Key Rotation + Integration Testing (Polish)

**Purpose**: HMAC key rotation capability and validation of all success criteria.

- [X] T054 Create `scripts/integrity-rotate-key.sh` — generate new HMAC key, store in Keychain, re-sign all state files (manifest, lock-state, container-security-config, container-verify-state) atomically, last audit entry with old key, subsequent with new key. Hold global lock during rotation to prevent concurrent verification (FR-036).
- [X] T055 Add `make integrity-rotate-key` target to `Makefile` — invokes `scripts/integrity-rotate-key.sh` with operator confirmation prompt.
- [X] T056 Integration test: container disappearance — start container, begin verification, kill container, verify downstream checks SKIPPED and result FAIL (SC-002).
- [X] T057 Integration test: concurrent audit log writes — run 2 verification processes simultaneously, verify hash chain valid after both complete (SC-007).
- [X] T058 Integration test: process group timeout — create test script spawning 10 children with `sleep 3600`, run through timeout with 5s limit, verify zero descendants remain via `pgrep -P` (SC-003).
- [X] T059 Integration test: invalid JSON to each wrapper — feed non-JSON to container-bench, n8n-audit, scan-image wrappers, verify non-zero exit and logged error (not "0 findings") (SC-001).
- [X] T060 Integration test: docker-bench hash tamper — modify file in clone, run container-bench, verify "supply_chain_verification_failed" (SC-008).
- [X] T061 Integration test: permission enforcement — verify secrets have 600, audit dirs have 700, Docker socket has 600 (SC-009).
- [X] T062 Integration test: credential exposure — run verification, check `lsof` for temp files containing API key, check `ps` for API key strings, verify none found (SC-006).
- [X] T063 Integration test: protected file expansion — verify `_integrity_protected_file_patterns()` includes `.git/config`, `n8n/workflows/*.json` (if exists), `.specify/memory/constitution.md` (if exists). Count must exceed 77 (SC-005).
- [X] T064 Integration test: TMPDIR traversal rejection — set `TMPDIR=/var/folders/../../../tmp/evil`, run TMPDIR validation, verify rejection. Set `TMPDIR=/var/folders/Xb/abc123/T`, verify acceptance (SC-010).
- [X] T065 Create traceability matrix — table mapping each of 43 adversarial findings to implementing FR(s) and task(s). Verify 100% coverage (SC-004). Save to `specs/012-security-hardening-phase2/phase4-traceability.md`.
- [X] T066 Run `phase4-quickstart.md` validation end-to-end — all verification procedures produce expected results.
- [X] T067 Update `specs/012-security-hardening-phase2/phase4-spec.md` status from Draft to Complete.

**Checkpoint**: All 10 success criteria validated. Phase 4 complete.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 (set -m validation) — BLOCKS all user stories
- **Phase 3 (Cascade)**: Depends on Phase 2 — US1 MVP
- **Phase 4 (Security Tools)**: Depends on Phase 2 — can run in parallel with Phase 3
- **Phase 5 (Protection Surface)**: Depends on Phase 2 — can run in parallel with Phase 3/4
- **Phase 6 (Credentials + Atomic)**: Depends on Phase 2 (safe write function) — can run in parallel with Phase 3/4/5
- **Phase 7 (Monitor)**: Depends on Phase 2+3+6 (needs safe primitives, cascade, and credential functions)
- **Phase 8 (Polish)**: Depends on Phase 3-7 completion

### User Story Mapping

| US | Spec Story | Plan Phase | Task Phase | Priority |
|----|-----------|------------|------------|----------|
| US1 | Fail-Fast Cascade | B | 3 | P1 |
| US2 | Atomic File Ops | A+D | 2+6 | P1 |
| US3 | Process Group Isolation | A | 2+7 | P1 |
| US4 | Output Bounding + JSON | A+B+C | 2+3+4 | P1 |
| US5 | Supply Chain Verification | C | 4 | P2 |
| US6 | Protection Surface | D | 5 | P2 |
| US7 | Command Injection Prevention | A+C | 2+4 | P1 |
| US8 | Credential Exposure | A+D | 2+6 | P2 |
| US9 | Audit Log Hardening | A | 2 | P2 |

### Parallel Opportunities

```
After Phase 2 (Foundational) completes:
  Phase 3 (US1 Cascade)     ─┐
  Phase 4 (US5+7 Tools)     ─┼─ can run in parallel
  Phase 5 (US6 Protection)  ─┤
  Phase 6 (US8+2 Creds)     ─┘

Within Phase 2:
  T011, T012, T013 can run in parallel (different functions, no deps)

Within Phase 4:
  T031, T034, T036 can run in parallel (different files)

Within Phase 5:
  T038, T039 can run in parallel (different patterns in same function)

Within Phase 6:
  T047, T048 can run in parallel (different files)
```

---

## Implementation Strategy

### MVP First (Phase 3 Only)

1. Complete Phase 1: Validate `set -m`
2. Complete Phase 2: Safe primitives
3. Complete Phase 3: Fail-fast cascade
4. **STOP AND VALIDATE**: Kill container mid-verify → FAIL + SKIPPED

### Incremental Delivery

1. Phase 1+2 → Foundation ready
2. Phase 3 → Cascade abort working (MVP)
3. Phase 4 → Security tools hardened
4. Phase 5 → Protection surface expanded
5. Phase 6 → Credentials secured, atomic writes expanded
6. Phase 7 → Monitor daemon hardened
7. Phase 8 → Integration tests + polish

---

## Summary

- **Total tasks**: 67 (T001-T067)
- **Phase 1 (Setup)**: 2 tasks (T001-T002)
- **Phase 2 (Foundational)**: 13 tasks (T003-T015)
- **Phase 3 (US1 MVP)**: 10 tasks (T016-T025)
- **Phase 4 (US5+7)**: 11 tasks (T026-T036)
- **Phase 5 (US6)**: 7 tasks (T037-T043)
- **Phase 6 (US8+2)**: 5 tasks (T044-T048)
- **Phase 7 (Monitor)**: 5 tasks (T049-T053)
- **Phase 8 (Polish)**: 14 tasks (T054-T067)
- **Parallel opportunities**: 6 task groups can run in parallel (same-file [P] markers removed)
