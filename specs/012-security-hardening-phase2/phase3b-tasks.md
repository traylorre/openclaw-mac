# Tasks: Security Tool Integration (Phase 3B)

**Input**: Design documents from `/specs/012-security-hardening-phase2/`
**Prerequisites**: phase3b-plan.md, phase3b-spec.md, phase3b-research-brief.md

**Tests**: Not explicitly requested. Verification tasks included as checkpoint tasks.

**Organization**: Tasks grouped by user story. US1-US2 are P1, US3-US4 are P2. All depend on Phase 1 (helpers).

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: Setup (Helpers)

**Purpose**: Docker socket resolution + macOS-compatible timeout.

- [x] T3B-001 Implement `integrity_docker_socket_path()` in `scripts/lib/integrity.sh`: resolve Docker socket from active Docker context via `docker context inspect --format '{{.Endpoints.docker.Host}}'`, fall back to `$DOCKER_HOST`, then `~/.colima/default/docker.sock`. Strip `unix://` prefix.
- [x] T3B-002 [P] Implement `integrity_run_with_timeout()` in `scripts/lib/integrity.sh`: accepts timeout_secs as first arg, remaining args as command. Runs command in background, starts watchdog timer, waits for command. If command exceeds timeout: kill command, return exit code 124 (same as GNU timeout convention). Clean up watchdog on normal completion.
- [x] T3B-003 [P] Create `~/.openclaw/logs/audit/` directory in `scripts/integrity-deploy.sh` if it doesn't exist (Phase B-E scripts write output here).

**Checkpoint**: Socket helper resolves Colima socket path. Timeout function works.

---

## Phase 2: US1 — CIS Docker Benchmark (Priority: P1)

**Story goal**: Run docker-bench-security against the n8n container, parse JSON output, produce PASS/WARN/FAIL result.

- [x] T3B-004 [US1] Create `scripts/container-bench.sh`: wrapper script that:
  (1) Sources `lib/common.sh` and `lib/integrity.sh`,
  (2) Resolves Docker socket via `integrity_docker_socket_path()`,
  (3) Checks Docker availability,
  (4) Runs docker-bench-security as container: `docker run --rm --net host --pid host --userns host -v /etc:/etc:ro -v "$socket_path":/var/run/docker.sock:ro -v "$audit_dir":/output docker/docker-bench-security@sha256:<pinned-digest> -l /output/docker-bench.log -b -i openclaw-n8n -x docker-bench`,
  (5) Post-filter JSON: discard results where container name does not exactly match `openclaw-n8n` (the `-i` flag is substring — could match `openclaw-n8n-debug`),
  (6) Parses filtered JSON to determine result: count Section 5 WARNs via `jq '[.tests[] | select(.id == "5") | .results[] | select(.result == "WARN")] | length'`. FAIL if > 0, else count other section WARNs → WARN if > 0, else PASS,
  (7) Prints summary (total checks, pass count, warn count per section),
  (8) Exits: 0=PASS, 1=FAIL, 2=WARN. Uses `set -euo pipefail`. Handles Docker unavailable → exit 3 (SKIP).
- [x] T3B-005 [US1] Pin the docker-bench-security Docker image by digest: pull the v1.6.1 image, record its digest, embed in `container-bench.sh`. Document the pinning in the script header.

### Verification

- [ ] T3B-006 [US1] Verification: run `bash scripts/container-bench.sh` → verify JSON output in `~/.openclaw/logs/audit/` → verify Section 5 results cover n8n container → verify script exits 0/1/2 based on findings.

---

## Phase 3: US2 — Application Security Audit (Priority: P1)

**Story goal**: Run n8n built-in audit, parse output (JSON or plain text), produce PASS/WARN/FAIL result.

- [x] T3B-007 [US2] Create `scripts/n8n-audit.sh`: wrapper script that:
  (1) Sources `lib/common.sh` and `lib/integrity.sh`,
  (2) Discovers container via `integrity_discover_container()`,
  (3) Runs `docker exec -u node "$cid" n8n audit 2>/dev/null`,
  (4) Strips non-JSON preamble: `sed -n '/^[{[]/,$p'` (same pattern as workflow export fix),
  (5) Detects "No security issues found" plain text → output PASS JSON `{}`,
  (6) Validates remaining output is JSON (`jq empty`),
  (7) Saves output to `~/.openclaw/logs/audit/n8n-audit.json`,
  (8) Determines result: count findings per category. The category IS the top-level key name (not a `.risk` field). FAIL if entries with key "credentials" or "instance" exist: `jq 'to_entries[] | select(.key | test("credentials|instance"; "i")) | .value.sections | length' | awk '{s+=$1} END{print s}'`. WARN if findings in other categories. PASS if output is empty `{}`,
  (9) Prints summary (findings per category),
  (10) Exits: 0=PASS, 1=FAIL, 2=WARN, 3=SKIP.
- [x] T3B-008 [P] [US2] Handle edge case: n8n still initializing → retry once after 5 seconds. Handle container not running → exit 3 (SKIP).

### Verification

- [ ] T3B-009 [US2] Verification: run `bash scripts/n8n-audit.sh` → verify output in `~/.openclaw/logs/audit/` → verify findings are categorized → verify exit code matches finding severity.

---

## Phase 4: US3 — Image Vulnerability Scan (Priority: P2)

**Story goal**: Scan container image for CVEs with Grype, exit non-zero on high/critical findings.

- [x] T3B-010 [US3] Create `scripts/scan-image.sh`: wrapper script that:
  (1) Checks `command -v grype` — if missing: print `brew install grype` guidance, exit 3 (SKIP),
  (2) Checks installed Grype version (`grype version`): define `EXPECTED_GRYPE_VERSION` constant (determine current stable version at implementation time), warn if installed version differs or is older,
  (3) Runs `grype openclaw-n8n:latest --fail-on high -o json`,
  (4) Saves output to `~/.openclaw/logs/audit/grype-scan.json`,
  (5) Disambiguates exit codes: if exit 0 → PASS; if exit 1 → check JSON for `.matches` array (findings present = FAIL, error message = SKIP with details); if other → SKIP,
  (6) Prints summary: total CVEs by severity, plus per-finding detail for high and critical CVEs (CVE ID, severity, affected package, installed version, fix version) via `jq '.matches[] | select(.vulnerability.severity == "Critical" or .vulnerability.severity == "High") | {cve: .vulnerability.id, severity: .vulnerability.severity, package: .artifact.name, installed: .artifact.version, fix: .vulnerability.fix.versions[0]}'`,
  (7) Exits: 0=PASS, 1=FAIL, 3=SKIP. No WARN (exit 2) path — Grype's `--fail-on high` is binary (above threshold or not). Medium-severity-only findings produce PASS (operator reviews JSON for details).

### Verification

- [ ] T3B-011 [US3] Verification: run `bash scripts/scan-image.sh` → verify JSON output → verify exit code reflects CVE severity.

---

## Phase 5: US4 — Unified Pipeline (Priority: P2)

**Story goal**: Single command runs all security layers with timeout, collects results, unified summary.

- [x] T3B-012 [US4] Create `scripts/security-pipeline.sh`: orchestrator that:
  (1) Defines layer array: `integrity-verify.sh --dry-run`, `container-bench.sh`, `n8n-audit.sh`, `scan-image.sh`,
  (2) For each layer: run via `integrity_run_with_timeout 300 bash "$script"`, capture exit code,
  (3) Map exit codes to layer results: 0=PASS, 1=FAIL, 2=WARN, 3=SKIP, 124=TIMEOUT(→SKIP),
  (4) Print consolidated summary table:
  ```
  Layer                  Result
  ─────────────────────  ──────
  Integrity Verify       PASS
  CIS Docker Benchmark   WARN
  n8n Application Audit  PASS
  Image CVE Scan         SKIP (grype not installed)
  ─────────────────────  ──────
  Overall: WARN (1 warn, 1 skip)
  ```
  (5) Determine overall: FAIL (exit 1) if any FAIL; WARN (exit 2) if any WARN or SKIP but no FAIL; PASS (exit 0) if all PASS,
  (6) Log pipeline summary to audit trail.
- [x] T3B-013 [US4] Add Makefile targets:
  ```makefile
  container-bench: ## M4: Run CIS Docker Benchmark against n8n container
  n8n-audit:       ## M4: Run n8n application security audit
  scan-image:      ## M4: Scan container image for CVEs (requires: brew install grype)
  security:        ## M4: Run all security layers (unified pipeline)
  ```
  Add all four to `.PHONY`. Wire: `container-bench` → `bash scripts/container-bench.sh`, `n8n-audit` → `bash scripts/n8n-audit.sh`, `scan-image` → `bash scripts/scan-image.sh`, `security` → `bash scripts/security-pipeline.sh`.

### Verification

- [ ] T3B-014 [US4] Verification: run `make security` → verify all 4 layers execute → verify summary table printed → verify exit code reflects worst result.

---

## Phase 6: Polish (CIS Annotations + Shellcheck)

**Purpose**: Annotate overlapping checks, shellcheck, integration test.

- [x] T3B-015 Annotate container check functions in `scripts/hardening-audit.sh` with CIS IDs: add comment `# CIS Docker Benchmark 5.x` to each overlapping function: `check_container_root` (CIS 5.x/user), `check_container_readonly` (CIS 5.13), `check_container_caps` (CIS 5.4), `check_container_privileged` (CIS 5.5), `check_docker_socket` (CIS 5.32), `check_container_network` (CIS 5.10), `check_container_resources` (CIS 5.11/5.12), `check_colima_mounts` (CIS 5.6).
- [x] T3B-016 Run shellcheck on all new scripts: `scripts/container-bench.sh`, `scripts/n8n-audit.sh`, `scripts/scan-image.sh`, `scripts/security-pipeline.sh` — zero warnings required.
- [x] T3B-017 [P] Document supply chain trust model in `specs/012-security-hardening-phase2/phase3b-quickstart.md`: docker-bench pinned by digest, Grype via Homebrew (bottle checksums), n8n audit built-in. Document expected tool versions.
- [x] T3B-018 [P] Capture content notes for findings during implementation.

---

## Dependencies and Execution Order

- **Phase 1 (Setup)**: No dependencies
- **Phase 2 (US1 — CIS)**: Depends on Phase 1 (socket helper)
- **Phase 3 (US2 — n8n audit)**: Depends on Phase 1 (container discovery)
- **Phase 4 (US3 — Grype)**: No Phase 1 dependency (standalone binary)
- **Phase 5 (US4 — Pipeline)**: Depends on Phases 2-4 (all layer scripts)
- **Phase 6 (Polish)**: Depends on all previous

### Parallel Opportunities

- T3B-002 and T3B-003 can run in parallel with T3B-001
- US1 (CIS) and US2 (n8n audit) can be implemented in parallel (different scripts)
- US3 (Grype) can be implemented in parallel with US1/US2
- T3B-017 and T3B-018 can run in parallel with T3B-015/T3B-016

### Implementation Strategy

1. **MVP**: Phase 1 + Phase 5 (unified pipeline + Makefile) with stubs for each layer
2. **Layer integration**: Phases 2-4 fill in the real implementations
3. **Production ready**: Phase 6 polish
