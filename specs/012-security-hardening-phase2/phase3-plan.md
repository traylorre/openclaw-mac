# Implementation Plan: Container & Orchestration Integrity (Phase 3)

**Branch**: `012-security-hardening-phase2` | **Date**: 2026-03-24 | **Spec**: [phase3-spec.md](phase3-spec.md)
**Input**: Phase 3 sub-spec, phase3-research-brief.md, adversarial review (21 findings addressed)

## Summary

Implement defense-in-depth container integrity verification for the n8n Docker orchestration layer. 8 user stories across 7 verification layers: image digest pinning, runtime configuration verification (10 properties), credential set baseline comparison, workflow integrity checking, filesystem drift detection, community node supply chain verification, VM boundary auditing, and continuous monitoring integration. All verification runs within a container-ID-pinned scope to prevent TOCTOU attacks. Informed by 8 n8n CVEs (CVSS ≥ 9.0), ClawHavoc campaign findings, CIS Docker Benchmark, NIST SP 800-190, and OWASP Docker Security.

## Technical Context

**Language/Version**: Bash 5.x (POSIX-compatible subset per Constitution VI)
**Primary Dependencies**: jq (JSON manipulation), openssl (HMAC signing), Docker CLI, macOS `security` (Keychain)
**Storage**: JSON state files (`~/.openclaw/`), JSONL audit log
**Testing**: Manual verification scripts (Constitution V — every recommendation verifiable)
**Target Platform**: macOS (Apple Silicon or Intel) with Colima + Docker
**Project Type**: Security verification tooling (scripts + documentation)
**Constraints**: Zero new dependencies beyond existing toolchain; all scripts pass `shellcheck` with zero warnings; idempotent and safe to re-run

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Documentation-Is-the-Product | ✅ PASS | Quickstart and verification tables are documentation artifacts |
| II. Threat-Model Driven | ✅ PASS | Every FR maps to specific CVEs, MITRE techniques, or CIS benchmarks |
| III. Free-First | ✅ PASS | All tools are free: Docker CLI, jq, shellcheck. No paid dependencies |
| IV. Cite Canonical Sources | ✅ PASS | Research brief cites CIS, NIST, OWASP, MITRE, specific CVEs |
| V. Every Recommendation Verifiable | ✅ PASS | Each check produces PASS/FAIL/WARN/SKIP output |
| VI. Bash Scripts Are Infrastructure | ✅ PASS | All scripts use set -euo pipefail, pass shellcheck, are idempotent |
| VII. Defense in Depth | ✅ PASS | 7 verification layers, each independently valuable |
| VIII. Explicit Over Clever | ✅ PASS | Quickstart provides copy-pasteable commands with expected output |
| IX. Markdown Quality Gate | ✅ PASS | All documentation follows markdownlint rules |
| X. CLI-First Infrastructure | ✅ PASS | All verification via CLI commands, no GUI dependencies |

## Project Structure

### Documentation (this feature)

```text
specs/012-security-hardening-phase2/
├── phase3-spec.md              # Feature specification
├── phase3-plan.md              # This file
├── phase3-research.md          # Research decisions (10 decisions)
├── phase3-research-brief.md    # Threat intelligence + framework analysis
├── phase3-data-model.md        # Data model extensions
├── phase3-quickstart.md        # Operator quickstart guide
└── checklists/
    └── phase3-requirements.md  # Quality validation checklist
```

### Source Code (repository root)

```text
scripts/
├── lib/
│   └── integrity.sh            # MODIFY: manifest extensions, container helper functions
├── integrity-deploy.sh         # MODIFY: container baseline capture
├── integrity-verify.sh         # MODIFY: 6 new check functions
├── integrity-monitor.sh        # MODIFY: container heartbeat checks
├── hardening-audit.sh          # MODIFY: VM boundary check, container config audit
└── Makefile                    # MODIFY: new targets

~/.openclaw/
├── manifest.json               # EXTENDS: container attestation fields
├── container-security-config.json  # NEW: signed security configuration
├── container-verify-state.json     # NEW: signed verification state
└── integrity-audit.jsonl       # EXTENDS: container audit events
```

## Implementation Phases

### Phase A: Foundation (Container Helper Library)

Add container-related utility functions to `scripts/lib/integrity.sh`:

1. `integrity_discover_container()` — Find container by name pattern, return container ID. Uses `docker ps -q --filter "name=$pattern"`. **MUST assert exactly one result**: zero results = fail (not running), multiple results = CRITICAL fail (ambiguous discovery is a security event, list all matching IDs). Return the single container ID.

2. `integrity_capture_container_snapshot()` — Single atomic `docker inspect --format '{{json .}}'` call on container ID. Parse with `jq` into structured variables. Returns JSON blob for downstream verification functions.

3. `integrity_verify_container_id()` — Compare current container ID against pinned ID. Returns 0 if match, 1 if changed.

4. `integrity_version_gte()` — Semantic version comparison function for bash. Splits version strings on `.`, compares each numeric segment left-to-right. Handles `major.minor.patch` format. Returns 0 if `$1 >= $2`, 1 otherwise. Does NOT use `sort -V` (GNU extension, not POSIX). Example: `integrity_version_gte "1.121.0" "1.9.0"` → 0 (true).

5. `integrity_capture_container_baseline()` — **Separate function from `integrity_build_manifest()`**. Captures container attestation data (image digest, n8n version, credentials, community nodes) and returns a JSON blob. The manifest builder remains Docker-agnostic. The deploy script merges this blob into the manifest ONLY when Docker is available. When Docker is unavailable, container fields are **omitted entirely** (not set to null) — this preserves HMAC compatibility with pre-Phase-3 manifests.

6. Add `container-security-config.json` and `container-verify-state.json` to `_integrity_protected_file_patterns()` **in this phase** (not Phase E). These patterns must be in place BEFORE the first deploy that creates the files.

7. Create `container-security-config.json` management functions:
   - `integrity_read_container_config()` — read + verify HMAC signature. On invalid signature: log CRITICAL, treat as if `credential_enum_failures` is at maximum (safe default), treat all alert states as "unhealthy" (re-fire all alerts as resync).
   - `integrity_write_container_config()` — write + sign

8. Create `container-verify-state.json` management functions:
   - `integrity_read_verify_state()` / `integrity_write_verify_state()`
   - On invalid signature: log CRITICAL, reset to safe defaults (max failures, all alerts unhealthy)

### Phase B: Deploy-Time Capture

Extend `scripts/integrity-deploy.sh` to capture the container baseline:

1. Call `integrity_discover_container()` to find the running container.
2. Capture image digest from the snapshot (`.Image` field).
3. Capture n8n version via `docker exec ... n8n --version`.
4. Enumerate credential names via `docker exec ... n8n list:credentials --format=json`.
5. Enumerate community node packages by reading `package.json` files.
6. Store all captured data in the manifest via `integrity_build_manifest()`.
7. Create initial `container-security-config.json` if it doesn't exist (with default thresholds).
8. Log `container_deploy` event to audit trail.

### Phase C: Pre-Launch Verification

Add 6 new check functions to `scripts/integrity-verify.sh`:

1. **`check_container_image()`** (FR-P3-001/003):
   - Discover container → pin ID
   - Capture snapshot (single atomic inspect)
   - Compare `.Image` against `manifest.container_image_digest`
   - Check n8n version against `min_n8n_version` threshold
   - BLOCKING: fail stops all subsequent container checks

2. **`check_container_config()`** (FR-P3-005 through FR-P3-012b):
   - Uses the already-captured snapshot (no additional Docker API calls)
   - Verify all 10 runtime properties against `container-security-config.json`
   - BLOCKING: fail stops application-level checks

3. **`check_container_credentials()`** (FR-P3-013/014/015/016):
   - `docker exec` credential enumeration
   - Compare names against `manifest.expected_credentials`
   - Track consecutive failures in `container-verify-state.json`
   - Escalate after 3 consecutive failures

4. **`check_container_workflows()`** (FR-P3-017/018/019/020):
   - **Replace** (not enhance) existing `check_n8n_workflows()` function. The old function uses container names for `docker exec`; the new one MUST use the pinned container ID. Remove the old function entirely.
   - Include `meta` field in comparison (adversarial review fix). **Migration step required**: after Phase 3 upgrade, operator must re-export workflows from the running container and commit to repo to sync `.meta` fields. Document in quickstart.
   - Normalize workflow JSON before comparison: sort `nodes` array by node name to prevent false positives from serialization order changes.
   - Detect unexpected workflows (no repo counterpart)
   - Run AFTER image digest verification passes

5. **`check_container_community_nodes()`** (FR-P3-025/026/027):
   - `docker exec` to read `package.json` files
   - Compare against `manifest.expected_community_nodes`
   - Report unexpected packages and version changes

6. **`check_container_drift()`** (FR-P3-021/022/023/024):
   - `docker diff` from host
   - Filter safe paths from `container-security-config.json`
   - Classify remaining changes by severity

7. **Orchestration wrapper** (FR-P3-036/037/038):
   - Pin container ID at start
   - Enforce execution order
   - **Each `docker exec` call MUST handle "no such container" errors explicitly** (trap return code, do not rely on `set -e`). If any container command fails with "no such container," log a CRITICAL event ("container disappeared during verification") and abort the verification cycle cleanly. This is distinct from "container ID changed" — it signals active container manipulation.
   - Re-verify container ID at end
   - Log verification result to audit trail

### Phase D: Continuous Monitoring

**Architecture note**: The existing `integrity-monitor.sh` uses an fswatch event loop (file change driven) plus a heartbeat timer (liveness signal). Container checks are polling-based, not event-driven. Phase D adds a **new container polling loop** that runs on a separate 60-second interval (longer than the 30-second heartbeat to account for `docker exec` latency). The heartbeat timer and the container poll loop run concurrently within the monitor process.

Add container polling loop to `scripts/integrity-monitor.sh`:

1. Add container image digest comparison (FR-P3-031)
2. Add credential name set comparison — full name set, not just count (FR-P3-032)
3. Add filesystem drift detection (FR-P3-033)
4. Add container reachability check (FR-P3-035)
5. **Execution time budget**: image digest (< 1s), credential enumeration (3-10s), drift detection (< 1s), reachability (< 1s). Total budget: 15s maximum within 60s interval. If checks exceed budget, log a warning and skip remaining checks for that cycle.
6. Implement alert deduplication (FR-P3-035b):
   - Track alert states in `container-verify-state.json`
   - Fire on state transitions only
   - Batch within 5-minute windows
   - Send "resolved" on recovery

### Phase E: VM Boundary & Audit Integration

1. Add `check_colima_mounts()` to `scripts/hardening-audit.sh` (FR-P3-028/029/030):
   - **Detect active Colima profile**: parse `colima list` output or check `colima status` to find the running profile name. Construct YAML path as `~/.colima/<profile>/colima.yaml`. Fall back to `default` if detection fails.
   - Parse YAML for mounts section using grep/awk (no yq dependency)
   - Detect writable home directory mount
   - Provide remediation guidance
   - If multiple profiles are running, check all and warn on any writable $HOME mount

2. Add Makefile targets:
   - `container-security-config-update` — update minimum version threshold
   - Extend existing `integrity-deploy`, `integrity-verify` targets

3. Add recovery procedures to quickstart for each failure mode:
   - Image mismatch → `make integrity-deploy` after confirming correct image
   - Unexpected credential → investigate, then `make integrity-deploy`
   - Config violation → fix docker-compose.yml, restart, verify
   - Workflow mismatch → `make workflow-export && make integrity-deploy`
   - **No `--skip-container-check` flag**: deploy is the re-baseline mechanism

### Phase F: Verification & Polish

1. Manual verification: deploy → verify → replace image → verify (mismatch detected) → restore → verify (pass)
2. Manual verification: deploy → verify → add credential → verify (unexpected credential flagged)
3. Manual verification: deploy → verify → modify workflow → verify (mismatch detected)
4. Manual verification: deploy → verify → restart with `--privileged` → verify (config violation detected)
5. Shellcheck all modified scripts: zero warnings required
6. Update quickstart with verified commands

## Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Container ID pinning | Pin at start, use for all commands, re-verify at end | Prevents TOCTOU between checks (spec adversarial CRITICAL-2) |
| Atomic docker inspect | Single `{{json .}}` call + jq parsing | Prevents TOCTOU between property checks (FR-P3-012b) |
| Container discovery | `docker ps -q --filter` + assert exactly one result | Multiple matches = security event (plan adversarial HIGH-4) |
| Image field | `.Image` from container inspect | Works for locally-built images (`.RepoDigests` is empty) |
| Semver comparison | Custom `integrity_version_gte()` splitting on `.` | No `sort -V` (GNU, not POSIX per Constitution VI) (plan adversarial CRITICAL-2) |
| Manifest builder | Separate `integrity_capture_container_baseline()` function | Keeps `integrity_build_manifest()` Docker-agnostic (plan adversarial CRITICAL-3, HIGH-15) |
| Container fields when Docker absent | Omitted entirely (not null) | Preserves HMAC compatibility with pre-Phase-3 manifests |
| Credential enumeration | `docker exec` + `n8n list:credentials` | Simplest, documented as partial-compromise-only |
| Community nodes | Read `package.json` directly | More reliable than `npm list`, avoids npm binary trust |
| Workflow comparison | Replace `check_n8n_workflows()`, include `.meta` | Old function uses names not IDs; `.meta` can hide payloads (plan adversarial CRITICAL-1, HIGH-8) |
| Colima YAML | grep/awk parsing with profile detection, no yq | Follows Constitution III; detects active profile (plan adversarial MEDIUM-9) |
| Alert deduplication | State-transition based + 5-min batching | Prevents alert fatigue (spec adversarial MEDIUM-19) |
| Verification order | Image → Config → Application-level | No point checking inside untrusted container (FR-P3-038) |
| Mid-cycle container loss | Explicit "no such container" trapping per docker exec | Distinct from ID-change; signals active manipulation (plan adversarial HIGH-5) |
| Monitoring architecture | New 60-second container poll loop (separate from fswatch) | Existing monitor is event-driven, container checks are polling (plan adversarial HIGH-6) |
| Drift detection | `docker diff` from host | Zero-dependency, runs in milliseconds |
| Config storage | HMAC-signed JSON in protected file set | Prevents attacker from weakening thresholds |
| State file corruption | Reset to safe defaults (max failures, all unhealthy) | Attacker can corrupt but gains nothing (plan adversarial MEDIUM-11) |
| Env var comparison | JSON-aware for array values (NODES_EXCLUDE), string for others | Prevents false positives from JSON key ordering (plan adversarial MEDIUM-12) |

## Dependencies

- `scripts/lib/integrity.sh` — existing functions: `integrity_audit_log()`, `integrity_get_signing_key()`, `integrity_build_manifest()`, `_integrity_sign_state_file()`, `_integrity_verify_state_signature()`
- `scripts/integrity-deploy.sh` — existing deploy flow (Phase 1A complete)
- `scripts/integrity-verify.sh` — existing 12 check functions
- `scripts/integrity-monitor.sh` — existing heartbeat cycle
- `scripts/hardening-audit.sh` — existing 20+ container audit checks
- Phase 2 hash-chained audit log — for all container event logging

## Risk Mitigations

| Risk | Mitigation |
|------|-----------|
| Container replaced between checks | Container ID pinning (FR-P3-036/037) |
| TOCTOU in property verification | Atomic docker inspect (FR-P3-012b) |
| Credential enumeration spoofing | Documented as partial-compromise-only (FR-P3-039), image digest is primary defense |
| Alert fatigue | Deduplication + state-transition alerting (FR-P3-035b) |
| Attacker lowers version threshold | Config file in protected set, HMAC-signed |
| Volume blind spot in docker diff | Compensated by credential + community node enumeration |
| Colima YAML parsing failure | Graceful skip with warning, manual verification guidance |
