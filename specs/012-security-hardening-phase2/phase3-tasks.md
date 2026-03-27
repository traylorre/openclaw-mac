# Tasks: Container & Orchestration Integrity (Phase 3)

**Input**: Design documents from `/specs/012-security-hardening-phase2/`
**Prerequisites**: phase3-plan.md, phase3-spec.md, phase3-research.md, phase3-data-model.md, phase3-quickstart.md

**Tests**: Not explicitly requested. Verification tasks included as checkpoint tasks within each phase.

**Organization**: Tasks grouped by user story. Each story is independently testable after Phase 2 (Foundational) completes. US1 and US2 are blocking (must complete first); US3-US6 can run in parallel; US7-US8 depend on US1-US3.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story (US1-US8)
- Exact file paths included in all descriptions

---

## Phase 1: Setup (Protected File Patterns & Configuration Schema)

**Purpose**: Establish protected file patterns and configuration structures BEFORE any deployment creates the new state files.

- [x] TP3-001 Add `container-security-config.json` and `container-verify-state.json` to `_integrity_protected_file_patterns()` in `scripts/lib/integrity.sh`. Add patterns: `${OPENCLAW_DIR}/container-security-config.json` and `${OPENCLAW_DIR}/container-verify-state.json`.
- [x] TP3-002 [P] Define default `container-security-config.json` structure in `scripts/lib/integrity.sh` as a function `_integrity_default_container_config()` that outputs the JSON from phase3-data-model.md (min_n8n_version: "1.121.0", expected_runtime_config with all 10 properties, drift_safe_paths). Include HMAC signing via existing `integrity_sign_state_file()` pattern.

**Checkpoint**: Protected file patterns include the two new config files. Default config structure is defined.

---

## Phase 2: Foundational (Container Helper Library)

**Purpose**: Core container utility functions that ALL user stories depend on. MUST complete before any US implementation.

- [x] TP3-003 Implement `integrity_discover_container()` in `scripts/lib/integrity.sh`: accepts a name pattern argument (default: read from container-security-config.json `container_name_pattern`). Uses `docker ps -q --filter "name=$pattern"`. Asserts exactly one result: zero → return 1 with "container not running" message; multiple → return 2 with CRITICAL log listing all matching IDs. Returns the single container ID on stdout.
- [x] TP3-004 Implement `integrity_capture_container_snapshot()` in `scripts/lib/integrity.sh`: accepts container ID argument. Runs single `docker inspect "$cid" --format '{{json .}}'` call. Returns full JSON blob on stdout. On failure: returns empty string and logs error to stderr.
- [x] TP3-005 [P] Implement `integrity_verify_container_id()` in `scripts/lib/integrity.sh`: accepts expected container ID and current container ID. Returns 0 if match, 1 if mismatch. On mismatch: logs CRITICAL audit event `container_id_changed` with old and new IDs.
- [x] TP3-006 [P] Implement `integrity_version_gte()` in `scripts/lib/integrity.sh`: accepts two version strings ($1=current, $2=minimum). Splits on `.`, compares each numeric segment left-to-right. Returns 0 if $1 >= $2, 1 otherwise. Does NOT use `sort -V`. Handles `major.minor.patch` format. Edge cases: missing patch (e.g., "1.121" treated as "1.121.0"), non-numeric segments → return 1 (fail safe).
- [x] TP3-007 Implement `integrity_capture_container_baseline()` in `scripts/lib/integrity.sh`: accepts container ID. Calls `integrity_capture_container_snapshot()` for image digest (`.Image`) and image name (`.Config.Image`). Calls `docker exec "$cid" n8n --version` for n8n version. Calls `docker exec "$cid" n8n list:credentials --format=json` and extracts `.name` array. Calls `docker exec "$cid" sh -c "ls /home/node/.n8n/nodes/node_modules/*/package.json 2>/dev/null"` and reads each `package.json` for name+version. Returns JSON blob with all fields. Each `docker exec` call MUST trap "no such container" errors explicitly (return code check, not `set -e`).
- [x] TP3-008 Implement `integrity_read_container_config()` and `integrity_write_container_config()` in `scripts/lib/integrity.sh`: read verifies HMAC signature via `integrity_verify_state_file()`. On invalid signature: log CRITICAL audit event, return safe defaults (credential_enum_failures at max, all alert states "unhealthy"). Write creates/updates file and signs with `integrity_sign_state_file()`.
- [x] TP3-009 Implement `integrity_read_verify_state()` and `integrity_write_verify_state()` in `scripts/lib/integrity.sh`: same pattern as TP3-008. Track `last_verified_at`, `last_container_id`, `credential_enum_failures`, `last_alert_states` per phase3-data-model.md. On invalid signature: log CRITICAL, reset to safe defaults.

**Checkpoint**: All 7 container utility functions exist and are callable. `integrity_discover_container()` finds the running container. `integrity_capture_container_baseline()` returns a complete JSON blob with image digest, n8n version, credentials, and community nodes.

---

## Phase 3: US1 — Container Image Integrity Verification (Priority: P1)

**Story goal**: Verify container image digest matches manifest baseline. Block agent launch on mismatch. Warn on outdated n8n version.

**Independent test**: Record image digest → replace container → verify (mismatch blocked) → restore → verify (passes).

- [x] TP3-010 [US1] Extend `scripts/integrity-deploy.sh` to call `integrity_capture_container_baseline()` when Docker is available. Before capture, verify n8n readiness: retry `docker exec "$cid" n8n --version` up to 3 times with 5-second backoff. If n8n is not ready after retries, warn the operator and abort container baseline capture (do NOT record an empty credential baseline — this would cause all credentials to appear as "unexpected" on next verification). Merge the returned JSON blob into the manifest: add `container_image_digest`, `container_image_name`, `container_n8n_version`, `expected_credentials`, `expected_community_nodes` fields. When Docker is unavailable, omit container fields entirely (not null) to preserve HMAC compatibility. Log `container_deploy` audit event with image digest, n8n version, credential count, community node count.
- [x] TP3-011 [US1] Implement `check_container_image()` in `scripts/integrity-verify.sh`: (1) Call `integrity_discover_container()` to get container ID, (2) Call `integrity_capture_container_snapshot()` for atomic inspect, (3) Extract `.Image` field and compare against `manifest.container_image_digest`, (4) On mismatch: log `container_image_mismatch` audit event, return FAIL with expected and actual digests, (5) Read `container_n8n_version` from manifest, read `min_n8n_version` from container-security-config.json, call `integrity_version_gte()` — warn if below threshold, (6) Store pinned container ID and snapshot in script-level variables for downstream checks. BLOCKING: fail stops all subsequent container checks.
- [x] TP3-012 [US1] Create initial `container-security-config.json` in `scripts/integrity-deploy.sh` if it doesn't exist: call `_integrity_default_container_config()` from TP3-002, write to `~/.openclaw/container-security-config.json`, sign with HMAC.

### Verification

- [ ] TP3-013 [US1] Verification: deploy with container running → verify manifest contains `container_image_digest` and `container_n8n_version` → stop container → start different image with same name → run integrity-verify → verify FAIL with digest mismatch → restore correct image → verify PASS.

**Checkpoint**: US1 complete. Image digest recorded at deploy, verified at startup. Mismatch blocks launch.

---

## Phase 4: US2 — Container Runtime Configuration Verification (Priority: P1)

**Story goal**: Verify 10 container security properties in a single atomic check. Block agent launch on any violation.

**Independent test**: Restart container with `--privileged` → verify (violation detected and blocked).

- [x] TP3-014 [US2] Implement `check_container_config()` in `scripts/integrity-verify.sh`: uses the snapshot captured by `check_container_image()` (no additional Docker API calls). Read `expected_runtime_config` from `container-security-config.json`. Verify all 10 properties via jq extraction from cached snapshot:
  1. `.HostConfig.Privileged` == false
  2. `.HostConfig.CapDrop` contains "ALL"
  3. `.HostConfig.NetworkMode` != "host"
  4. `.Mounts` has no entry with `docker.sock` in Source or Destination
  5. `.NetworkSettings.Ports` — all entries have HostIp == "127.0.0.1"
  6. `.HostConfig.ReadonlyRootfs` == true
  7. `.HostConfig.SecurityOpt` contains "no-new-privileges"
  8. `.HostConfig.SecurityOpt` does NOT contain "seccomp=unconfined"
  9. `.Config.User` != "" and != "0" and != "root"
  10. `.Config.Env` — `NODES_EXCLUDE` contains expected list (JSON-aware comparison: extract the value from the env array with `jq -r '.[] | select(startswith("NODES_EXCLUDE=")) | sub("NODES_EXCLUDE=";"")' `, parse both expected and actual as JSON arrays, sort each with `jq 'sort'`, compare sorted output), `N8N_RESTRICT_FILE_ACCESS_TO` is set (string comparison). For ports check (#5): skip with PASS if no ports published (empty object), skip entries where value is null (exposed but not published), only fail when a port IS published with `HostIp != "127.0.0.1"`.
  Log each violation as `container_config_violation` audit event with property name, expected value, actual value. BLOCKING: any violation stops application-level checks.
- [x] TP3-015 [US2] Implement verification orchestration wrapper `_run_container_checks()` in `scripts/integrity-verify.sh`: (0) Check `command -v docker &>/dev/null` — if Docker unavailable, skip ALL container checks with SKIPPED status and log "Docker CLI not found — container checks skipped", return. (1) Call `integrity_discover_container()` — if fails, wait 2 seconds and retry once before reporting unreachable (spec edge case: container restart during check), (2) call `check_container_image()` — if FAIL, skip remaining container checks and return, (3) call `check_container_config()` — if FAIL, skip application-level checks and return, (4) call application-level checks in sequence, using `type -t` guard for each: `type -t check_container_credentials &>/dev/null && check_container_credentials` (allows incremental implementation — functions defined in later phases are gracefully skipped), (5) call `integrity_verify_container_id()` to re-verify pinned ID hasn't changed — if changed, log CRITICAL `container_id_changed`, invalidate results. Wire `_run_container_checks()` into the main verification flow after existing checks.

### Verification

- [ ] TP3-016 [US2] Verification: stop container → restart with `--privileged --cap-add=ALL` → run integrity-verify → verify FAIL with specific "privileged=true" violation → restore correct docker-compose config → restart → verify PASS.

**Checkpoint**: US2 complete. All 10 runtime properties verified atomically. Violations block launch.

---

## Phase 5: US3 — Credential Set Verification (Priority: P1)

**Story goal**: Detect unauthorized credential injection or removal by comparing credential names against deploy-time baseline.

**Independent test**: Add unexpected credential → verify (flagged) → remove → verify (passes).

- [x] TP3-017 [US3] Implement `check_container_credentials()` in `scripts/integrity-verify.sh`: (1) Read `expected_credentials` from manifest, (2) Run `docker exec "$pinned_cid" n8n list:credentials --format=json 2>/dev/null` with explicit error trapping (if "no such container" → log CRITICAL + abort cycle; if other error → increment failure counter), (3) Extract `.name` array from result, (4) Compare against baseline: unexpected names → log `container_credential_unexpected` + report as "potential compromise indicator"; missing names → log `container_credential_missing` + report as warning, (5) On enumeration failure: read `credential_enum_failures` from verify-state, increment, write back. If ≥ 3 consecutive failures: escalate to hard FAIL. On success: reset counter to 0.
- [x] TP3-018 [US3] Handle n8n API not-ready state in `check_container_credentials()`: if `docker exec` returns non-zero but container exists (n8n still initializing), retry up to 3 times with 5-second backoff. Log retry attempts. After 3 retries: treat as enumeration failure per TP3-017 step 5.

### Verification

- [ ] TP3-019 [US3] Verification: deploy (baseline credentials recorded) → add an unexpected credential via n8n UI → run integrity-verify → verify "potential compromise indicator" reported with the credential name → remove the credential → run integrity-verify → verify PASS.

**Checkpoint**: US3 complete. Credential set baseline comparison works. Consecutive failure escalation implemented.

---

## Phase 6: US4 — Workflow Integrity Verification (Priority: P2)

**Story goal**: Detect workflow modifications inside the container by comparing against version-controlled repository copies.

**Independent test**: Modify a workflow inside the container → verify (mismatch detected with workflow name).

- [x] TP3-020 [US4] Implement `check_container_workflows()` in `scripts/integrity-verify.sh` — **replace** existing `check_n8n_workflows()` entirely. New implementation: (1) Use pinned container ID (not name) for all `docker exec` calls, (2) Export all workflows: `docker exec "$pinned_cid" n8n export:workflow --all 2>/dev/null`, (3) For each workflow in repo `workflows/*.json`: normalize both versions with jq — `del(.updatedAt, .createdAt, .versionId, .id)` (keep `.meta`), sort `.nodes` array by `.name` field to prevent serialization order false positives, (4) Compare normalized JSON strings, (5) Report mismatches with specific workflow name and log `container_workflow_mismatch`, (6) Detect workflows in container with no repo counterpart → report as "potential compromise indicator" and log, (7) Handle container not running / export failure gracefully (warning, not crash), (8) **Migration graceful degradation**: if ALL workflows mismatch AND the only difference for each is the `.meta` field, log a single WARNING: "All workflow mismatches are meta-only — run `make workflow-export && git add workflows/ && git commit` to sync .meta fields after Phase 3 upgrade" instead of reporting N individual "potential compromise" events.
- [x] TP3-021 [P] [US4] Document workflow migration step in `specs/012-security-hardening-phase2/phase3-quickstart.md`: after Phase 3 upgrade, operator must re-export workflows (`make workflow-export`) and commit to repo to sync `.meta` fields that are now included in comparison. Add to "After upgrading" section.

### Verification

- [ ] TP3-022 [US4] Verification: deploy all workflows → modify a workflow inside the container (add a Code node) → run integrity-verify → verify mismatch detected with the specific workflow name → restore via `make workflow-import` → run integrity-verify → verify PASS.

**Checkpoint**: US4 complete. Workflow comparison uses pinned ID, includes `.meta`, normalizes node ordering.

---

## Phase 7: US5 — Container Filesystem Drift Detection (Priority: P2)

**Story goal**: Detect unauthorized filesystem changes in the container overlay using `docker diff`.

**Independent test**: Create a file inside the container → verify (drift detected).

- [x] TP3-023 [US5] Implement `check_container_drift()` in `scripts/integrity-verify.sh`: (1) Run `docker diff "$pinned_cid" 2>/dev/null`, (2) Read `drift_safe_paths` from container-security-config.json, (3) Filter output: remove lines matching any safe path prefix (/tmp, /var/tmp, /home/node/.cache, /home/node/.local, /run), (4) If remaining changes exist: classify — on a read-only rootfs (FR-P3-010 passed), ANY added file outside safe paths is a CRITICAL event (should be impossible, indicates rootfs compromise or misconfiguration). On a non-read-only rootfs (degraded posture), added files outside safe paths are WARNING. Note: `docker diff` does not report file permissions, so executable detection is not possible without `docker exec` — classify all unexpected added files by the rootfs-read-only heuristic instead (FR-P3-023 amended), (5) Log `container_drift_detected` audit event with full list of unexpected changes, (6) If no unexpected changes: PASS, log count of filtered (expected) changes. Handle container not running gracefully (skip with warning).

### Verification

- [ ] TP3-024 [US5] Verification: start clean container → run drift check (expect PASS with 0 unexpected) → `docker exec "$cid" touch /tmp/safe-file` → run drift check (still PASS, /tmp filtered) → note: with read-only rootfs, creating files outside tmpfs is not possible. If rootfs were writable, `docker exec "$cid" touch /usr/local/bin/evil` → drift check → verify CRITICAL reported.

**Checkpoint**: US5 complete. Filesystem drift detected and classified by severity.

---

## Phase 8: US6 — Community Node Supply Chain Verification (Priority: P2)

**Story goal**: Detect unauthorized community node installations or version changes.

**Independent test**: Record node baseline → install unexpected node → verify (flagged).

- [x] TP3-025 [US6] Implement `check_container_community_nodes()` in `scripts/integrity-verify.sh`: (1) Read `expected_community_nodes` from manifest (array of {name, version} objects), (2) Run `docker exec "$pinned_cid" sh -c "for f in /home/node/.n8n/nodes/node_modules/*/package.json; do cat \"\$f\" 2>/dev/null; done"` to read all package.json files, (3) Extract name and version from each with jq, (4) Compare against baseline: unexpected packages → log `container_community_node_unexpected` + report as "potential supply chain compromise"; version changes → log as warning; missing packages → log as warning, (5) Handle empty node_modules (no community nodes installed) gracefully — if baseline is also empty, PASS.

### Verification

- [ ] TP3-026 [US6] Verification: deploy with n8n-nodes-playwright as the only community node → run verify (PASS) → verify manifest contains `expected_community_nodes` with correct name and version.

**Checkpoint**: US6 complete. Community node inventory baseline comparison works.

---

## Phase 9: US7 — VM Boundary Verification (Priority: P3)

**Story goal**: Warn operator if Colima mounts `$HOME` writable. Advisory check in hardening audit.

**Independent test**: Check Colima config → verify warning if writable $HOME.

- [x] TP3-027 [US7] Implement `check_colima_mounts()` in `scripts/hardening-audit.sh`: (1) Detect active Colima profile: run `colima list 2>/dev/null` and parse for running profile name (the "PROFILE" column in output). Fall back to "default" if detection fails or colima not installed, (2) Construct config path: `~/.colima/<profile>/colima.yaml`, (3) Parse YAML mounts section with grep/awk. Three patterns to detect:
  - **Empty array**: `mounts: []` → means Colima uses default behavior (writable $HOME). Detect with `grep -E '^\s*mounts:\s*\[\]'`
  - **Missing section**: no `mounts:` key at all → same as empty, default writable $HOME. Detect with `! grep -q '^\s*mounts:' colima.yaml`
  - **Explicit entries**: indented `- location:` and `writable:` pairs under `mounts:`. Extract with `awk '/^\s*mounts:/,/^[^ ]/' | grep -E 'location:|writable:'` and pair them.
  (4) If any mount has the home directory writable (or default behavior detected): report WARNING with remediation guidance showing the restrictive mount configuration, (5) If restrictive mounts configured: report PASS with mount summary, (6) Graceful skip if colima not installed or config not found. Wire into the container security audit section of hardening-audit.sh.
- [x] TP3-028 [US7] Add audit logging to `check_colima_mounts()` from TP3-027: log `vm_boundary_warning` audit event when writable $HOME detected, including mount paths and writability status. This is part of the TP3-027 function implementation, not a separate function.

### Verification

- [ ] TP3-029 [US7] Verification: run `make audit` → verify CHK-COLIMA-MOUNTS check appears → if default Colima config (no explicit mounts), verify WARNING with remediation guidance.

**Checkpoint**: US7 complete. VM boundary check integrated into hardening audit.

---

## Phase 10: US8 — Continuous Container Monitoring (Priority: P3)

**Story goal**: Extend monitoring service with container polling loop on 60-second interval. Detect image changes, credential set changes, drift, and container loss between heartbeats. Deduplicate alerts.

**Independent test**: Start monitor → replace container image → verify alert fires.

- [x] TP3-030 [US8] Add container polling loop to `scripts/integrity-monitor.sh`: create a new `_container_monitor_cycle()` function that runs: (1) `integrity_discover_container()` — if fails, trigger `container_unreachable` alert, (2) `integrity_capture_container_snapshot()` — extract `.Image` and compare against `manifest.container_image_digest`, (3) credential name set comparison via `docker exec n8n list:credentials`, (4) `docker diff` with safe path filtering. The loop runs on a 60-second interval (separate from the 30-second file heartbeat). Add execution time budget: if any check exceeds 15 seconds total, log warning and skip remaining checks for that cycle.
- [x] TP3-031 [US8] Implement alert deduplication in `scripts/integrity-monitor.sh`: read `last_alert_states` from `container-verify-state.json` (this persists across monitor restarts — on restart, the monitor reads the last known state and only fires if the current state differs). For each check type (image_digest, runtime_config, credentials, drift, reachability): compare current state vs last state. Fire webhook alert ONLY on state transitions (healthy→unhealthy, unhealthy→healthy). On recovery: send "resolved" notification. Within a 5-minute window: batch repeated unhealthy states into a single "still occurring" notification (compare `since` timestamp in state file against current time). Update `last_alert_states` after each cycle.
- [x] TP3-032 [US8] Wire the container polling loop into the monitor's main process: start `_container_monitor_cycle` in a background subshell with its own `while true; do ... sleep 60; done` loop (separate from the 30-second file heartbeat timer and the fswatch event loop). The three concurrent loops are: (1) fswatch event handler (file changes), (2) heartbeat timer (30s liveness signal), (3) container poll (60s container checks). Ensure clean shutdown: trap SIGTERM/SIGINT to kill all three background subshells.

### Verification

- [ ] TP3-033 [US8] Verification: start integrity-monitor → verify container checks appear in heartbeat logs → stop monitor → replace container image → restart monitor → verify alert webhook fires with image digest mismatch → restore correct image → verify "resolved" notification.

**Checkpoint**: US8 complete. Container polling loop runs every 60 seconds with alert deduplication.

---

## Phase 11: Polish & Cross-Cutting Concerns

**Purpose**: Shellcheck, Makefile targets, quickstart, and verification scenarios.

- [x] TP3-034 Run shellcheck on all modified scripts: `scripts/lib/integrity.sh`, `scripts/integrity-deploy.sh`, `scripts/integrity-verify.sh`, `scripts/integrity-monitor.sh`, `scripts/hardening-audit.sh` — zero warnings required per Constitution VI.
- [x] TP3-035 [P] Add Makefile targets: `container-security-config-update` (accepts MIN_VERSION argument, updates min_n8n_version in container-security-config.json, re-signs). Verify existing `integrity-deploy` and `integrity-verify` targets work with the new container checks.
- [x] TP3-036 [P] Update `specs/012-security-hardening-phase2/phase3-quickstart.md` with verified commands. Add recovery procedures for each failure mode: image mismatch, unexpected credential, config violation, workflow mismatch, community node unexpected. Document the migration step for `.meta` field inclusion (re-export workflows). Document the partial-compromise-only limitation of `docker exec`-based checks (FR-P3-039): credential enumeration, workflow export, and community node listing detect artifacts of partial compromise but are defeated by full container takeover. Image digest verification is the primary defense against total takeover. Add this caveat to the "What the Checks Detect" table.
- [ ] TP3-037 Full verification scenario: run complete deploy → verify → replace image → verify (mismatch) → add credential → verify (unexpected) → modify workflow → verify (mismatch) → restart with --privileged → verify (config violation) → restore all → verify (PASS). Document results.
- [x] TP3-038 [P] Capture content notes for findings: write content notes to `inbox/` for any surprising discoveries during implementation (docker diff behavior, HMAC compatibility, semver edge cases, etc.)

---

## Dependencies and Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 (protected file patterns must exist)
- **Phase 3 (US1 — Image)**: Depends on Phase 2 (discovery + snapshot functions)
- **Phase 4 (US2 — Config)**: Depends on Phase 3/US1 (snapshot captured by image check, orchestration wrapper)
- **Phase 5 (US3 — Credentials)**: Depends on Phase 3/US1 (pinned container ID, image check must pass first)
- **Phase 6 (US4 — Workflows)**: Depends on Phase 3/US1 (pinned container ID, image check must pass first)
- **Phase 7 (US5 — Drift)**: Depends on Phase 3/US1 (pinned container ID)
- **Phase 8 (US6 — Community Nodes)**: Depends on Phase 3/US1 (pinned container ID)
- **Phase 9 (US7 — VM Boundary)**: No US dependencies (hardening audit, independent of verification flow)
- **Phase 10 (US8 — Monitoring)**: Depends on US1, US3, US5 (reuses image, credential, drift checks)
- **Phase 11 (Polish)**: Depends on all previous phases

### Parallel Opportunities

Within each phase, tasks marked [P] can run in parallel. Across phases:

- **US5 (Drift) and US6 (Community Nodes)** code can be written in parallel (different check functions, no shared state)
- **US7 (VM Boundary)** can be written in parallel with US3-US6 (different script file: hardening-audit.sh)
- **US4 (Workflows)** migration documentation (TP3-021) can be written in parallel with the implementation (TP3-020)

### Implementation Strategy

1. **MVP**: Phase 1 + 2 + 3 (US1) + 4 (US2) = container image verification + runtime config check. Agent launch blocked on mismatch.
2. **Compromise Detection**: Add US3 (Credentials) + US4 (Workflows) + US6 (Community Nodes) = detect artifacts of partial compromise.
3. **Full Coverage**: Add US5 (Drift) + US7 (VM Boundary) + US8 (Monitoring) = continuous monitoring + outermost layer.
4. **Production Ready**: Phase 11 = shellcheck, quickstart, full verification.
