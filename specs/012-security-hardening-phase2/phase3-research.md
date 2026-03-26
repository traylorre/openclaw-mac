# Research: Container & Orchestration Integrity (Phase 3)

**Date**: 2026-03-24
**Spec**: [phase3-spec.md](phase3-spec.md)

---

## R-P3-001: Container Name Resolution Strategy

**Decision**: Use `docker ps -q --filter "name=n8n"` for container ID discovery, then pin the returned container ID for all subsequent commands in a verification cycle.

**Rationale**: The codebase has an inconsistency: `workflow-sync.sh` uses `openclaw-n8n` (exact), `integrity-verify.sh` uses `n8n` (exact grep), and `hardening-audit.sh` uses `--filter "name=n8n"` (substring). The filter approach is the most resilient — it matches both `n8n` and `openclaw-n8n` (and `compose_n8n_1` if applicable). By immediately resolving to a container ID, all subsequent commands use an immutable reference, satisfying FR-P3-036 (TOCTOU prevention).

**Alternatives considered**:
- Exact name `openclaw-n8n`: Breaks if docker-compose service naming changes
- Exact name `n8n`: Breaks with current docker-compose which names it `openclaw-n8n`
- Container label-based discovery: More robust but not currently configured

---

## R-P3-002: Atomic Docker Inspect Strategy

**Decision**: Use `docker inspect "$container_id" --format '{{json .}}'` to capture the entire container state in a single call, then parse with `jq` to extract all required properties.

**Rationale**: FR-P3-012b requires all runtime configuration properties to be captured in a single atomic call. The existing `hardening-audit.sh` makes 13 separate `docker inspect` calls with individual format strings — each is a separate Docker API call, creating a TOCTOU window. A single `{{json .}}` call returns the complete container state as one JSON blob. Parsing with `jq` is fast and doesn't require additional Docker API calls.

**Implementation pattern**:
```bash
container_json=$(docker inspect "$container_id" --format '{{json .}}' 2>/dev/null) || return 1
# Extract all properties from the cached JSON
privileged=$(echo "$container_json" | jq -r '.HostConfig.Privileged')
cap_drop=$(echo "$container_json" | jq -r '.HostConfig.CapDrop | join(",")')
# ... etc
```

**Alternatives considered**:
- Multiple `docker inspect` calls with individual format strings: Current pattern, has TOCTOU
- `docker inspect` with a complex Go template: Fragile, hard to maintain
- Docker API via curl: Adds HTTP dependency, no benefit over CLI

---

## R-P3-003: Image Digest Field Selection

**Decision**: Use the `.Image` field from container inspect (which returns `sha256:<hex>`) as the image digest. For the manifest, also record the human-readable image name and tag for operator reference.

**Rationale**: The Docker documentation distinguishes between:
- `.Id` — the container's unique ID (changes on every `docker create`)
- `.Image` — the image ID (SHA-256 of image config JSON) that the container was created from
- `.RepoDigests` — the registry-specific digest (only populated for pulled images, not locally built ones)

Our `openclaw-n8n:latest` image is locally built (via `docker build -t openclaw-n8n:latest`), so `.RepoDigests` will be empty. The `.Image` field is the correct choice — it's a SHA-256 hash of the image content and changes when the image is rebuilt.

The parent spec's FR-015/FR-016 used the term "image ID" while the Phase 3 spec uses "image digest." Both refer to the `.Image` field from `docker inspect` on the container.

**Alternatives considered**:
- `.RepoDigests[0]`: Only works for pulled images, empty for locally built
- `docker images --digests`: Returns repo digests, same limitation
- Building a content hash of the image layers: Overly complex, `.Image` already does this

---

## R-P3-004: n8n Version Extraction

**Decision**: Extract the n8n version from the container's environment variables or by running `docker exec n8n --version` inside the container. Record in the manifest as a string.

**Rationale**: The n8n version is critical for CVE tracking (8 CVEs with CVSS ≥ 9.0 in 3 months). The version can be extracted from:
1. `docker exec "$container_id" n8n --version` — runs inside container, subject to partial compromise limitation
2. `docker inspect` environment variables — may contain `N8N_VERSION` if set
3. The image labels — `docker inspect <image_id> --format '{{index .Config.Labels "n8n.version"}}'` if the image has version labels

Option 1 is simplest and most reliable. Since this runs at deploy time (not verification time), the partial compromise limitation is less concerning — the operator is explicitly recording the baseline.

**Minimum safe version threshold**: Store in `~/.openclaw/container-security-config.json` (HMAC-signed, in protected file set). Initial threshold: n8n >= 1.121.0 (patches CVE-2026-21858, CVSS 10.0).

**Alternatives considered**:
- Hardcoded threshold in script: Not updatable without code change
- Fetching from a CVE database at runtime: Network dependency, complexity
- No version check: Unacceptable given the CVE density

---

## R-P3-005: Credential Enumeration Mechanism

**Decision**: Use `docker exec "$container_id" n8n list:credentials --format=json | jq '.[].name'` to enumerate credential names. Record as an ordered list in the manifest.

**Rationale**: The n8n CLI `list:credentials` command returns credential metadata (name, type, ID) without exposing secret values. This is the same pattern used in the existing `gateway-setup.sh` workflow import process. The command runs inside the container and is subject to the partial-compromise limitation (FR-P3-039) — a fully compromised container could return fabricated results. This is documented and accepted.

**Consecutive failure tracking**: Store failure count in a state file (`~/.openclaw/container-verify-state.json`). Increment on enumeration failure, reset on success. Escalate to hard failure after 3 consecutive failures (FR-P3-016).

**Alternatives considered**:
- Direct SQLite query on the Docker volume: Requires VM-level access, architecturally complex
- n8n REST API: Requires API key, adds authentication complexity
- Skip credential enumeration entirely: Loses compromise detection capability

---

## R-P3-006: Community Node Enumeration Mechanism

**Decision**: Use `docker exec "$container_id" sh -c "ls /home/node/.n8n/nodes/node_modules/*/package.json 2>/dev/null"` followed by `docker exec cat` to read each `package.json` and extract name + version.

**Rationale**: Community nodes are npm packages installed in `/home/node/.n8n/nodes/node_modules/`. Each has a `package.json` with `name` and `version` fields. Reading `package.json` directly is more reliable than `npm list` (which depends on npm being available and honest). This is still a `docker exec` based check and is subject to the partial-compromise limitation.

**Alternatives considered**:
- `npm list --json`: Depends on npm binary integrity inside container
- Host-side Docker volume inspection: Requires Colima VM access, not portable
- `docker cp` to extract files: Creates temporary files on host, cleanup needed

---

## R-P3-007: Colima Mount Configuration Check

**Decision**: Parse `~/.colima/default/colima.yaml` using `grep` and `awk` for the specific `mounts:` section. Do NOT add a `yq` dependency.

**Rationale**: The constitution (Article III — Free-First) and existing toolchain use only standard CLI tools. Adding `yq` for a single check creates a new dependency. The Colima YAML structure for mounts is predictable:
```yaml
mounts:
  - location: /path
    writable: true
```
A targeted `grep`/`awk` approach can detect:
1. Empty `mounts: []` (default writable $HOME)
2. `writable: true` on paths containing the home directory
3. Missing `mounts:` section (default behavior)

If the YAML structure becomes too complex for reliable grep-based parsing, the check should skip with a warning recommending manual verification.

**Alternatives considered**:
- `yq` (Go YAML processor): New dependency, violates minimal toolchain principle
- Python/Ruby YAML parsing: Adds runtime dependency
- Skip the check entirely: Misses CRITICAL finding from research (writable $HOME)

---

## R-P3-008: Container Drift Detection Strategy

**Decision**: Use `docker diff "$container_id"` for overlay filesystem monitoring. Acknowledge the volume blind spot explicitly. Supplement with credential and community node enumeration for volume-mounted paths.

**Rationale**: `docker diff` is zero-dependency, runs from the host, and returns in milliseconds. Its primary limitation (doesn't cover Docker volumes) is well-documented in the spec. Since the container has `read_only: true` on the root filesystem, the overlay should have minimal changes. Any change is suspicious.

**Filter list for known-safe paths**:
- `/tmp/*` — tmpfs mount
- `/var/tmp/*` — tmpfs mount
- `/home/node/.cache/*` — tmpfs mount
- `/home/node/.local/*` — tmpfs mount
- `/run/*` — runtime data

**Executable detection**: Since the root filesystem is read-only (FR-P3-010), added files in the overlay require a writable layer exception (e.g., `--tmpfs` path). Added files outside tmpfs paths are impossible if read-only is enforced, making FR-P3-023 effectively a redundancy check. If read-only verification fails AND drift is detected, the combination is a stronger signal than either alone.

**Alternatives considered**:
- Falco with eBPF: Excessive for single-container deployment
- Periodic `docker cp` and hashing: Slow, creates temp files
- Skip drift detection: Loses a zero-cost detection layer

---

## R-P3-009: Verification Execution Order

**Decision**: Strict sequential order within a pinned container ID scope:

1. **Container discovery**: `docker ps -q --filter "name=n8n"` → pin container ID
2. **Container state check**: Verify container is in `running` state
3. **Image digest verification** (FR-P3-003): Compare `.Image` against manifest — BLOCKING
4. **Runtime configuration verification** (FR-P3-005 through FR-P3-012b): Single atomic inspect — BLOCKING
5. **Application-level checks** (run only if steps 3-4 pass):
   a. Credential enumeration (FR-P3-013/014)
   b. Workflow comparison (FR-P3-017/018/019/020)
   c. Community node verification (FR-P3-025/026/027)
   d. Filesystem drift detection (FR-P3-021/022/023/024)
6. **Container ID re-verification** (FR-P3-037): Confirm container ID unchanged — invalidate if changed

**Rationale**: Image digest and runtime configuration must pass before application-level checks. If the image is wrong, everything inside the container is untrusted. Application-level checks can run in any order relative to each other since they all operate on the same pinned container ID.

**Alternatives considered**:
- Parallel execution of all checks: TOCTOU risk, harder to reason about
- No ordering enforcement: Implementer might run workflow check before image check

---

## R-P3-010: Alert Deduplication Strategy

**Decision**: Track last alert state per check type. Only fire alerts on state *transitions* (healthy → unhealthy, unhealthy → healthy). Batch repeated violations within a 5-minute window into a single "still occurring" notification.

**Rationale**: Without deduplication, a flapping container would fire alerts every 30 seconds. Alert fatigue is a documented attack enabler — the operator mutes notifications, then the attacker performs the real attack. State-based alerting (transitions only) plus time-windowed batching provides operator-relevant notifications without noise.

**State tracking**: Add a `last_container_alert_state` field to the monitor heartbeat JSON. Store the last alert type and timestamp for each check category.

**Alternatives considered**:
- No deduplication: Alert fatigue
- Cooldown period (suppress all alerts for N minutes): Misses rapid state changes
- Exponential backoff on alerts: Overly complex for a single-container deployment
