# Phase 4B Traceability Matrix

Maps all 26 adversarial review findings to functional requirements (FRs) and implementation tasks. All items DONE.

| # | Finding | Severity | FR(s) | Task(s) | Status |
|---|---------|----------|-------|---------|--------|
| 1 | `integrity_capture_container_snapshot()` — unbounded `docker inspect` | CRITICAL | FR-002 | T001 | DONE |
| 2 | `integrity_discover_container()` — unbounded `docker ps` | CRITICAL | FR-003 | T002 | DONE |
| 3 | `_integrity_safe_atomic_write()` — clobbers caller ERR trap | CRITICAL | FR-010, FR-011, FR-012 | T005, T006 | DONE |
| 4 | `integrity_audit_log()` — lock has no trap-based cleanup | CRITICAL | FR-013, FR-019, FR-020 | T007, T008 | DONE |
| 5 | `integrity_sign_manifest()` — HMAC key in process listing | CRITICAL | FR-023, FR-025 | T015, T016 | DONE |
| 6 | `_integrity_init_tmp_dir()` — symlink attack continues via `\|\| true` | CRITICAL | FR-016 | T010 | DONE |
| 7 | `integrity_run_with_timeout()` — no PGID verification | CRITICAL | FR-017, FR-018 | T011, T012 | DONE |
| 8 | Stale lock race — `rm -f pid; rmdir lockdir` not atomic | CRITICAL | FR-019, FR-020, FR-044 | T008, T042 | DONE |
| 9 | `grype` scan — unbounded in standalone mode | HIGH | FR-004 | T003 | DONE |
| 10 | `docker info` reachability — unbounded | HIGH | FR-005 | T003 | DONE |
| 11 | `docker exec true` liveness — unbounded | HIGH | FR-006 | T004 | DONE |
| 12 | `docker image inspect` — unbounded | HIGH | FR-007 | T003 | DONE |
| 13 | `docker inspect` re-verification — unbounded | HIGH | FR-008 | T004 | DONE |
| 14 | `docker context inspect` — unbounded | HIGH | FR-009 | T004 | DONE |
| 15 | `_integrity_safe_credential_write()` — no chmod 600 | HIGH | FR-014, FR-015 | T009 | DONE |
| 16 | TMPDIR traversal — `..` bypasses regex validation | HIGH | FR-021, FR-022 | T013, T014 | DONE |
| 17 | `_integrity_validate_json()` — stderr mixed into return value | HIGH | FR-026 | T017 | DONE |
| 18 | `\|\| var=0` fallback — silent false negatives | HIGH | FR-027, FR-028 | T018, T019 | DONE |
| 19 | `check_container_drift()` — missing liveness gate | HIGH | FR-029 | T020 | DONE |
| 20 | `check_container_community_nodes()` — missing liveness gate | HIGH | FR-030 | T020 | DONE |
| 21 | `workflow-sync.sh` — API key in process listing | HIGH | FR-024 | T016 | DONE |
| 22 | `_integrity_check_permissions()` — returns count, not boolean | MEDIUM | FR-031, FR-033 | T021, T022 | DONE |
| 23 | `integrity_check_env_vars()` — returns count, not boolean | MEDIUM | FR-032, FR-033 | T021, T022 | DONE |
| 24 | `security-pipeline.sh` — `bash -c "$cmd"` dispatch | MEDIUM | FR-036 | T023 | DONE |
| 25 | First-run baseline — no operator confirmation | MEDIUM | FR-037, FR-038 | T024, T025 | DONE |
| 26 | PIPESTATUS subshell — wrong pipeline exit code | MEDIUM | FR-039 | T026 | DONE |

## Additional Hardening (edge cases promoted to FRs)

| # | Finding | FR | Task(s) | Status |
|---|---------|------|---------|--------|
| E1 | `python3` F_FULLFSYNC fallback | FR-041 | T027 | DONE |
| E2 | Keychain locked during HMAC signing | FR-042 | T028 | DONE |
| E3 | Concurrent key rotation | FR-043 | T055 | DONE |
| E4 | Lock path validation before `rm -rf` | FR-044 | T042 | DONE |
| E5 | Fixed-string grep for file-derived patterns | FR-040 | T029 | DONE |
| E6 | `docker exec` in deploy baseline — unbounded | FR-034 | T030 | DONE |
| E7 | `docker ps` in liveness checks — unbounded | FR-035 | T031 | DONE |
