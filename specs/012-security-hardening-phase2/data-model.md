# Data Model: Security Hardening Phase 2

## Audit Event (hash-chained)

**Persistence**: Appended to `~/.openclaw/integrity-audit.log` (JSONL, append-only flag)

| Field | Type | Description |
|-------|------|-------------|
| timestamp | string (ISO-8601) | Event time in UTC |
| action | string (enum) | lock, unlock, deploy, verify, skill_add, skill_remove, sandbox_config, monitor_alert, session_decrypt, key_rotate, enforcement_bypass |
| operator | string | $SUDO_USER or $(whoami) |
| pid | integer | Process ID of the operation |
| details | string | Structured context (file path, hash, count, error) |
| prev_hash | string (SHA-256) | Hash of the previous log entry (hash chain). First entry uses "GENESIS" |

**Validation**: Each entry must be valid JSON. The `prev_hash` must match the SHA-256 of the raw bytes of the immediately preceding line in the file.

## Manifest Sequence State

**Persistence**: `~/.openclaw/manifest-sequence.json` (HMAC-signed state file)

| Field | Type | Description |
|-------|------|-------------|
| sequence | integer | Monotonically increasing counter, incremented on each deploy |
| last_verified_at | string (ISO-8601) | Timestamp of the last successful verification |
| last_deployed_at | string (ISO-8601) | Timestamp of the last deploy |
| signature | string (HMAC-SHA256) | Signature of all fields except signature |

**State transitions**: sequence only increases. A decrease triggers a rollback alert. A `--force` deploy resets the sequence with an audit log entry.

## Enforcement Configuration

**Persistence**: `~/.openclaw/enforcement.json` (HMAC-signed, in protected file list)

| Field | Type | Description |
|-------|------|-------------|
| enforced_checks | array of string | Check IDs that block agent launch on failure |
| advisory_checks | array of string | Check IDs that warn but don't block |
| hardcoded_minimum | array of string | Non-configurable enforced checks (for documentation only — actual hardcoded set is in code) |
| signature | string (HMAC-SHA256) | Signature of all fields except signature |

**Default enforced_checks**: `["sandbox_enabled", "manifest_signature", "files_locked", "allowlist_valid"]`

## Container Attestation (manifest extension)

Added to the existing manifest.json structure:

| Field | Type | Description |
|-------|------|-------------|
| container_image_id | string (SHA-256) | Expected n8n container image digest |
| container_name | string | Expected container name (e.g., "n8n") |
| expected_credentials | array of string | Expected n8n credential names |
| manifest_sequence | integer | Current sequence counter |

## Encrypted Session File

**Persistence**: `~/.openclaw/sessions/linkedin-storageState.enc` (AES-256-GCM encrypted)

| Component | Description |
|-----------|-------------|
| Header | 12-byte random nonce (IV) |
| Ciphertext | AES-256-GCM encrypted JSON |
| Auth tag | 16-byte GCM authentication tag |
| Key storage | macOS Keychain, service: "session-encryption-key", account: "openclaw" |

## Extended Protected File List

Files added to `_integrity_protected_file_patterns()` in `scripts/lib/integrity.sh`:

| Pattern | Category | New in 012? |
|---------|----------|:-----------:|
| `~/.openclaw/agents/*/models.json` | configuration | YES |
| `~/.openclaw/agents/*/.openclaw/workspace-state.json` | state | YES |
| `~/.openclaw/openclaw.json.bak*` | configuration | YES |
| `~/.openclaw/restore-scripts/*` | script | YES |
| `.claude/settings.local.json` | configuration | YES |
| `~/.openclaw/manifest-sequence.json` | state | YES |
| `~/.openclaw/enforcement.json` | governance | YES |
| `~/.openclaw/agents/*/.git/hooks/*` | script | YES |
