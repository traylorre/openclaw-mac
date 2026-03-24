# Data Model: Workspace Integrity

**Date**: 2026-03-23 | **Spec**: [spec.md](spec.md)

## Entities

### Integrity Manifest

The central record of all protected files and their expected state.

| Field | Description |
| --- | --- |
| version | Manifest schema version (integer) |
| created_at | ISO-8601 timestamp of manifest creation |
| updated_at | ISO-8601 timestamp of last update |
| platform_version | Expected AI agent platform runtime version |
| signature | HMAC-SHA256 of the manifest body, computed with key from macOS Keychain |
| files | Array of Protected File Entry records |

### Protected File Entry

One entry per file under integrity protection.

| Field | Description |
| --- | --- |
| path | Absolute filesystem path to the protected file |
| sha256 | SHA-256 hex digest of the file contents |
| category | Classification: workspace, skill, orchestration, workflow, script, config, secret |
| locked | Boolean: whether the immutable flag is currently set |
| locked_at | ISO-8601 timestamp of when the flag was last set |

### Skill Allowlist Entry

One entry per approved skill.

| Field | Description |
| --- | --- |
| name | Human-readable skill name (informational only) |
| content_hash | SHA-256 hex digest of the SKILL.md content (the identity) |
| version | Operator-assigned version label (optional, informational) |
| approved_at | ISO-8601 timestamp of when the operator approved this skill |

### Monitoring Heartbeat

Written by the monitoring service at regular intervals.

| Field | Description |
| --- | --- |
| pid | Process ID of the monitoring service |
| timestamp | ISO-8601 timestamp of last heartbeat |
| files_watched | Count of files currently under monitoring |

### Lock State Record

Tracks intentional unlock/lock operations for alert suppression.

| Field | Description |
| --- | --- |
| path | Absolute path to the unlocked file |
| unlocked_at | ISO-8601 timestamp of when the file was unlocked |
| timeout_minutes | Grace period before alerts resume for this file |
| operator | Username of the operator who unlocked |

## State Transitions

### Protected File Lifecycle

```text
[Untracked] → deploy → [Locked] → unlock → [Unlocked] → lock → [Locked]
                                                ↓ (timeout)
                                          [Alert: stale unlock]
```

### Monitoring Service Lifecycle

```text
[Stopped] → start (via launchd) → [Running] → heartbeat every 30s → [Running]
                                       ↓ (crash/kill)
                                  [Stopped] → auto-restart (launchd KeepAlive)
                                       ↓ (restart fails)
                                  [Stale heartbeat detected by audit/startup]
```

## File Storage

All integrity data stored as JSON files:

- `~/.openclaw/manifest.json` — Integrity Manifest (signed)
- `~/.openclaw/skill-allowlist.json` — Skill Allowlist
- `~/.openclaw/integrity-monitor-heartbeat.json` — Monitoring Heartbeat
- `~/.openclaw/lock-state.json` — Active Lock State Records (transient, cleared on lock)
