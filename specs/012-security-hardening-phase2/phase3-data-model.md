# Data Model: Container & Orchestration Integrity (Phase 3)

**Spec**: [phase3-spec.md](phase3-spec.md)
**Research**: [phase3-research.md](phase3-research.md)

---

## Manifest Extensions

The existing `manifest.json` structure is extended with container attestation fields. All new fields are added at the top level alongside existing `files`, `skills`, and `signature` fields.

### New Fields

```json
{
  "version": 1,
  "created_at": "2026-03-24T10:00:00Z",
  "updated_at": "2026-03-24T10:00:00Z",
  "platform_version": "v2026.3.13",

  "container_image_digest": "sha256:abc123...",
  "container_image_name": "openclaw-n8n:latest",
  "container_n8n_version": "1.72.1",
  "expected_credentials": ["LinkedIn OAuth2", "N8N API Key", "Telegram Bot"],
  "expected_community_nodes": [
    {"name": "n8n-nodes-playwright", "version": "0.3.2"}
  ],

  "files": [ ... ],
  "skills": [ ... ],
  "signature": "hmac_sha256_hex"
}
```

### Field Definitions

| Field | Type | Source | When Captured | When Verified |
|-------|------|--------|---------------|---------------|
| `container_image_digest` | string | `docker inspect $cid --format '{{json .}}'` → `.Image` | Deploy | Pre-launch, heartbeat |
| `container_image_name` | string | `docker inspect $cid --format '{{json .}}'` → `.Config.Image` | Deploy | Display only |
| `container_n8n_version` | string | `docker exec $cid n8n --version` | Deploy | Pre-launch (vs threshold) |
| `expected_credentials` | string[] | `docker exec $cid n8n list:credentials --format=json` → `.name` | Deploy | Pre-launch, heartbeat |
| `expected_community_nodes` | object[] | `docker exec $cid` → read `package.json` files | Deploy | Pre-launch |

---

## Container Security Configuration

New signed state file: `~/.openclaw/container-security-config.json`

```json
{
  "min_n8n_version": "1.121.0",
  "min_n8n_version_reason": "CVE-2026-21858 (CVSS 10.0), CVE-2026-27495 (CVSS 9.4)",
  "container_name_pattern": "n8n",
  "expected_runtime_config": {
    "privileged": false,
    "cap_drop": ["ALL"],
    "network_mode_not": "host",
    "readonly_rootfs": true,
    "no_new_privileges": true,
    "seccomp_not_unconfined": true,
    "user_not_root": true,
    "no_docker_socket": true,
    "ports_localhost_only": true,
    "required_env": {
      "NODES_EXCLUDE": "[\"n8n-nodes-base.executeCommand\",\"n8n-nodes-base.ssh\",\"n8n-nodes-base.localFileTrigger\"]",
      "N8N_RESTRICT_FILE_ACCESS_TO": "/home/node/.n8n"
    }
  },
  "drift_safe_paths": [
    "/tmp", "/var/tmp", "/home/node/.cache",
    "/home/node/.local", "/run"
  ],
  "signature": "hmac_sha256_hex"
}
```

### Field Definitions

| Field | Type | Purpose |
|-------|------|---------|
| `min_n8n_version` | string | Minimum safe n8n version (FR-P3-004) |
| `min_n8n_version_reason` | string | CVEs addressed by minimum version |
| `container_name_pattern` | string | Docker filter pattern for container discovery |
| `expected_runtime_config` | object | Expected container security properties (FR-P3-005 through FR-P3-011d) |
| `drift_safe_paths` | string[] | Paths excluded from drift detection (FR-P3-022) |
| `signature` | string | HMAC-SHA256 signature (same signing pattern as other state files) |

**Protection**: This file MUST be added to the protected file set (`_integrity_protected_file_patterns`) and locked with `uchg`. An attacker who modifies this file (e.g., lowering `min_n8n_version` or adding `docker.sock` to safe paths) would be detected by the manifest integrity check.

---

## Container Verification State

New state file: `~/.openclaw/container-verify-state.json`

```json
{
  "last_verified_at": "2026-03-24T10:00:00Z",
  "last_container_id": "abc123def456...",
  "credential_enum_failures": 0,
  "last_alert_states": {
    "image_digest": {"state": "healthy", "since": "2026-03-24T10:00:00Z"},
    "runtime_config": {"state": "healthy", "since": "2026-03-24T10:00:00Z"},
    "credentials": {"state": "healthy", "since": "2026-03-24T10:00:00Z"},
    "drift": {"state": "healthy", "since": "2026-03-24T10:00:00Z"},
    "reachability": {"state": "healthy", "since": "2026-03-24T10:00:00Z"}
  },
  "signature": "hmac_sha256_hex"
}
```

### Field Definitions

| Field | Type | Purpose |
|-------|------|---------|
| `last_verified_at` | ISO-8601 | Timestamp of last successful full verification |
| `last_container_id` | string | Container ID from last verification (for change detection) |
| `credential_enum_failures` | integer | Consecutive credential enumeration failure count (FR-P3-016) |
| `last_alert_states` | object | Per-check-type alert state for deduplication (FR-P3-035b) |
| `signature` | string | HMAC-SHA256 signature |

**Protection**: This file is in the protected file set. HMAC-signed to prevent an attacker from resetting the `credential_enum_failures` counter.

---

## Runtime Container Snapshot

This is NOT persisted to disk. It exists only in memory during a verification cycle.

```json
{
  "container_id": "abc123def456...",
  "image": "sha256:abc123...",
  "config_user": "1000:1000",
  "config_env": ["N8N_HOST=localhost", "NODES_EXCLUDE=[...]", ...],
  "host_config_privileged": false,
  "host_config_cap_drop": ["ALL"],
  "host_config_readonly_rootfs": true,
  "host_config_network_mode": "templates_default",
  "host_config_security_opt": ["no-new-privileges:true"],
  "mounts": [...],
  "network_settings_ports": {
    "5678/tcp": [{"HostIp": "127.0.0.1", "HostPort": "5678"}]
  }
}
```

Captured in a single `docker inspect --format '{{json .}}'` call, parsed with `jq`. Used for all runtime configuration verification. Discarded after the verification cycle completes.

---

## Verification Flow (Entity Relationships)

```
manifest.json
  ├── container_image_digest ──────→ compare with ──→ snapshot.image
  ├── expected_credentials ────────→ compare with ──→ docker exec list:credentials
  └── expected_community_nodes ───→ compare with ──→ docker exec ls package.json

container-security-config.json
  ├── expected_runtime_config ────→ compare with ──→ snapshot.host_config_*
  ├── min_n8n_version ────────────→ compare with ──→ manifest.container_n8n_version
  └── drift_safe_paths ───────────→ filter ─────────→ docker diff output

container-verify-state.json
  ├── credential_enum_failures ──→ escalation logic ──→ warning vs hard fail
  └── last_alert_states ──────────→ deduplication ────→ alert webhook
```

---

## Audit Log Events (New for Phase 3)

All container events are appended to the existing `~/.openclaw/integrity-audit.jsonl` using the hash-chained audit log from Phase 2.

| Action | Details Fields |
|--------|---------------|
| `container_deploy` | `image_digest`, `n8n_version`, `credential_count`, `community_node_count` |
| `container_verify_pass` | `container_id`, `checks_passed`, `duration_ms` |
| `container_verify_fail` | `container_id`, `failed_checks`, `details` |
| `container_image_mismatch` | `expected_digest`, `actual_digest` |
| `container_config_violation` | `property`, `expected`, `actual` |
| `container_credential_unexpected` | `credential_names` |
| `container_credential_missing` | `credential_names` |
| `container_workflow_mismatch` | `workflow_name`, `type` (modified/unexpected) |
| `container_drift_detected` | `changes` (list of A/C/D entries) |
| `container_community_node_unexpected` | `package_name`, `version` |
| `container_unreachable` | `reason` |
| `container_id_changed` | `old_id`, `new_id` |
| `container_enum_failure` | `consecutive_failures`, `escalated` |
| `vm_boundary_warning` | `mount_paths`, `writable_status` |
