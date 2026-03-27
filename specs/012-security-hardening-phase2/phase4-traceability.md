# Phase 4 Traceability Matrix

Maps each adversarial finding to implementing FR(s) and task(s).

| # | Finding | Severity | FR(s) | Task(s) | Status |
|---|---------|----------|-------|---------|--------|
| 1 | Verification continues after container disappears | CRITICAL | FR-001, FR-002, FR-003, FR-004 | T016-T020 | DONE |
| 2 | Process timeout kills only parent, children survive | CRITICAL | FR-007, FR-008, FR-009 | T006 | DONE |
| 3 | Silent false negatives from `|| echo 0` | HIGH | FR-011, FR-013, FR-037 | T007, T014, T023, T031, T034, T036 | DONE |
| 4 | mktemp+chmod TOCTOU symlink vulnerability | HIGH | FR-005, FR-006 | T003, T004 | DONE |
| 5 | API key visible via here-string temp files | HIGH | FR-026, FR-027 | T005, T024, T044, T045 | DONE |
| 6 | Audit log lock TOCTOU race | HIGH | FR-029 | T008 | DONE |
| 7 | chmod failures silently ignored | HIGH | FR-030 | T009 | DONE |
| 8 | No fsync/F_FULLFSYNC on critical writes | HIGH | FR-031 | T009 | DONE |
| 9 | Command injection via unquoted `$cmd` | HIGH | FR-021, FR-038 | T026 | DONE |
| 10 | Docker-bench not verified for tampering | HIGH | FR-014, FR-016 | T028, T029 | DONE |
| 11 | Grype binary not hash-verified | HIGH | FR-015 | T035 | DONE |
| 12 | TMPDIR validation too loose | MEDIUM | FR-032 | T011 | DONE |
| 13 | Container name allows regex injection | MEDIUM | FR-025 | T012 | DONE |
| 14 | PKG_DELIMITER can appear in package.json | MEDIUM | FR-012 | T013 | DONE |
| 15 | Audit log action not validated | MEDIUM | FR-023 | T010 | DONE |
| 16 | Audit log details not escaped | MEDIUM | FR-024 | T010 | DONE |
| 17 | .git/config not in protected files | MEDIUM | FR-017 | T037 | DONE |
| 18 | n8n/workflows not in protected files | MEDIUM | FR-018 | T038 | DONE |
| 19 | constitution.md not in protected files | MEDIUM | FR-019 | T039 | DONE |
| 20 | Secret files permissions not checked | MEDIUM | FR-020, FR-028 | T040 | DONE |
| 21 | Docker socket permissions not checked | MEDIUM | FR-034 | T041 | DONE |
| 22 | docker exec output unbounded (OOM risk) | MEDIUM | FR-010 | T022, T033 | DONE |
| 23 | docker inspect/ps/diff not timeout-bounded | MEDIUM | FR-010a | T025, T050 | DONE |
| 24 | sed-based JSON extraction in n8n-audit | MEDIUM | FR-022, FR-040 | T032 | DONE |
| 25 | Docker-bench `|| true` hides failures | MEDIUM | FR-039 | T030 | DONE |
| 26 | Security pipeline output suppressed | MEDIUM | - | T027 | DONE |
| 27 | Docker-bench JSON not validated | MEDIUM | FR-013 | T031 | DONE |
| 28 | Grype version prefix match too loose | MEDIUM | FR-015 | T035 | DONE |
| 29 | Monitor credential exposure | MEDIUM | FR-035 | T045 | DONE |
| 30 | Monitor docker calls unbounded | MEDIUM | FR-035 | T050 | DONE |
| 31 | Monitor JSON parsing unvalidated | MEDIUM | FR-035 | T051 | DONE |
| 32 | Monitor trap kills PIDs not groups | MEDIUM | FR-035 | T049 | DONE |
| 33 | Monitor cycle not timeout-bounded | MEDIUM | FR-035 | T052 | DONE |
| 34 | Monitor `|| true` hides cycle failures | LOW | FR-035 | T053 | DONE |
| 35 | No HMAC key rotation capability | LOW | FR-036 | T054, T055 | DONE |
| 36 | No trust boundary documentation | LOW | FR-033 | T021 | DONE |
| 37 | No protected file count verification | LOW | - | T042 | DONE |
| 38 | Manifest not using atomic writes | LOW | FR-005 | T046 | DONE |
| 39 | State signing not using atomic writes | LOW | FR-005 | T047 | DONE |
| 40 | Makefile hooks using /tmp for temp files | LOW | FR-005 | T048 | DONE |
| 41 | Permission check not integrated in verify | LOW | FR-020 | T043 | DONE |
| 42 | Docker-bind-mount secret needs 640 not 600 | LOW | FR-041 | T040 | DONE |
| 43 | `|| echo 0` in date parsing (integrity.sh) | LOW | FR-037 | T014 | DONE |

**Coverage**: 43/43 findings addressed (100%).
**Tasks**: 67 tasks (T001-T067), all completed.
