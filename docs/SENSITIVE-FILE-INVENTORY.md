# Sensitive File Inventory

Pipeline security hardening (014). All files that store secrets, control agent
behavior, or configure trust boundaries.

## Critical Risk

| Path | Purpose | Protection | Expected State | ADV Ref |
|------|---------|-----------|----------------|---------|
| `.env` (repo root) | HMAC webhook secret | `.gitignore`, mode 600 | Not committed, readable only by owner | — |
| `~/.openclaw/.env` | HMAC secret (agent copy) | Mode 600 | Readable only by owner | — |
| `~/.openclaw/manifest.json` | Integrity checksums + signature | Mode 600, HMAC-signed | Signature valid against Keychain key | — |
| `~/.openclaw/lock-state.json` | Grace periods (alert suppression) | Mode 600, HMAC-signed | Signature valid (ADV-002 fixed) | ADV-002 |
| `scripts/lib/integrity.sh` | Integrity logic (trust root) | `uchg` immutable, manifest hash | Immutable flag set, checksum matches | ADV-008 |

## High Risk

| Path | Purpose | Protection | Expected State | ADV Ref |
|------|---------|-----------|----------------|---------|
| `~/.openclaw/openclaw.json` | Agent sandbox config, tool deny lists | Mode 600 | Owner-only access | — |
| `~/.openclaw/skill-allowlist.json` | Skill content hashes | Mode 600, HMAC-signed | Signature valid | — |
| `~/.openclaw/agents/linkedin-persona/SOUL.md` | Agent persona | `uchg` immutable, manifest hash | Immutable, checksum matches | — |
| `~/.openclaw/agents/linkedin-persona/AGENTS.md` | Operating rules, approval gates | `uchg` immutable, manifest hash | Immutable, checksum matches | — |
| `~/.openclaw/agents/linkedin-persona/TOOLS.md` | Available skills, credential boundaries | `uchg` immutable, manifest hash | Immutable, checksum matches | — |
| `workflows/*.json` (6 active) | n8n automation definitions | Mode 644 (repo), manifest checksum | Checksums match manifest | — |
| `scripts/templates/docker-compose.yml` | Container config, port bindings, env vars | Mode 644, manifest checksum | Checksum matches manifest | — |
| `scripts/templates/n8n-entrypoint.sh` | Container startup script | Mode 644, manifest checksum | Checksum matches manifest | — |

## Medium Risk

| Path | Purpose | Protection | Expected State | ADV Ref |
|------|---------|-----------|----------------|---------|
| `~/.openclaw/integrity-monitor-heartbeat.json` | Monitor liveness proof | Mode 600, HMAC-signed | Signature valid (ADV-004 fixed) | ADV-004 |
| `~/.openclaw/integrity-audit.log` | Audit trail | Mode 600 | Owner-only access | ADV-016 |
| `~/.openclaw/agents/linkedin-persona/USER.md` | Operator context | `uchg` immutable, manifest hash | Immutable, checksum matches | — |
| `~/.openclaw/agents/linkedin-persona/IDENTITY.md` | Agent identity | `uchg` immutable, manifest hash | Immutable, checksum matches | — |
| `~/.openclaw/agents/linkedin-persona/BOOT.md` | Startup recovery | `uchg` immutable, manifest hash | Immutable, checksum matches | — |

## Future (When US2 Implemented)

| Path | Purpose | Protection | Expected State | ADV Ref |
|------|---------|-----------|----------------|---------|
| `storageState.json` (browser profile) | LinkedIn session cookies | Must be HMAC-signed | Not yet implemented | — |

## Verification

Run `make audit` to verify all sensitive files match their expected protections.
The `CHK-SENSITIVE-FILE-*` audit checks iterate this inventory and report
per-file PASS/FAIL.

## Maintenance

When adding new sensitive files to the pipeline:

1. Add an entry to this inventory
2. Add corresponding verification logic to `check_sensitive_file_protections()`
   in `scripts/hardening-audit.sh`
3. Re-run `make audit` to confirm the new check passes
