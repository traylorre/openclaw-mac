# Quickstart: Security Hardening Phase 2

## Prerequisites

- 011-workspace-integrity deployed and operational (PR #95 merged)
- macOS 13+ (Ventura or later) for chflags uappnd support
- Docker via Colima (M1 infrastructure)
- HMAC signing key in Keychain (`integrity-manifest-key`)

## Deploy Expanded Protection

```bash
# 1. Deploy with expanded file list (adds models.json, settings.local.json, etc.)
make integrity-deploy

# 2. Lock all files including newly protected ones
sudo make integrity-lock

# 3. Verify expanded coverage
make integrity-verify
```

## Enable Append-Only Audit Log

```bash
# Set append-only flag (requires sudo, one-time operation)
sudo chflags uappnd ~/.openclaw/integrity-audit.log

# Verify it's set
ls -lO ~/.openclaw/integrity-audit.log | grep uappnd

# Test: attempt to truncate (should fail)
echo "test" > ~/.openclaw/integrity-audit.log  # Expected: Operation not permitted
```

## Sign Skill Allowlist

```bash
# Re-approve all skills (now with HMAC signature)
for skill in linkedin-post linkedin-engage linkedin-activity config-update token-status; do
  bash scripts/skill-allowlist.sh add "$skill"
done

# Verify signatures
bash scripts/skill-allowlist.sh check
```

## Container Integrity Setup

```bash
# Record expected n8n image ID in manifest
make integrity-deploy  # Automatically captures container image ID

# Verify container integrity
make integrity-verify  # Now includes container image check
```

## Encrypt Browser Session

```bash
# Encrypt existing storageState (one-time)
bash scripts/session-encrypt.sh encrypt

# Verify encryption
file ~/.openclaw/sessions/linkedin-storageState.enc  # Should show "data", not JSON

# Decrypt for use (automated by Playwright workflow)
bash scripts/session-encrypt.sh decrypt --temp
```

## Enable Enforcement Gate

```bash
# Deploy enforcement configuration
bash scripts/enforcement-setup.sh

# Verify enforcement blocks on misconfiguration
make sandbox-teardown  # Disable sandbox
make integrity-verify  # Should FAIL (sandbox not enabled)
make sandbox-setup     # Re-enable
make integrity-verify  # Should PASS
```

## Verify Full Hardening

```bash
# Run complete audit with new checks
make audit --section "Workspace Integrity"

# Expected: all 8+ CHK-OPENCLAW-* checks PASS
```
