# Quickstart: Security Remediation & Hardening Depth (Phase 4)

## What Changed

Phase 4 addresses 43 vulnerabilities found during adversarial review of the Phase 3/3B security system. It hardens the security tools themselves.

### Before Phase 4

- Container verification continues even when the container disappears mid-check
- Security tool parse failures silently report "0 findings" (false negatives)
- API keys briefly visible in process listings via bash here-strings
- Audit log can be corrupted by concurrent writers (lock TOCTOU race)
- External tools (docker-bench-security, grype) not verified for tampering
- Process timeouts only kill parent process; children survive

### After Phase 4

- Fail-fast cascade: high-trust check failure stops all downstream checks
- All JSON parsing validated; parse failures produce explicit errors
- API keys written to temp files in secure directory, never in process listings
- Audit log lock uses PID + start time for stale detection; hash chain guaranteed
- Docker-bench pinned to commit hash; grype verified by binary hash
- Process group isolation: timeout kills entire process tree

## Verify It Works

### 1. Fail-Fast Cascade

```bash
# Start n8n, run verification — should PASS
make integrity-verify
# Expected: all checks pass, result = PASS

# Kill the container mid-verification
docker stop openclaw-n8n &
make integrity-verify
# Expected: container_vanished detected, downstream checks SKIPPED, result = FAIL
```

### 2. JSON Validation

```bash
# Feed invalid JSON to container-bench wrapper
echo "not json" > /tmp/fake-bench.json
# The wrapper should reject it with "json_validation_failed"
# (manual test — modify bench JSON path temporarily)
```

### 3. Process Group Timeout

```bash
# The security pipeline should kill all descendants on timeout
make security
# Expected: each layer runs in its own process group
# If a layer hangs, timeout kills the entire group within 5 seconds
```

### 4. Supply Chain Verification

```bash
# Modify a file in the docker-bench-security clone
echo "tampered" >> ~/.openclaw/tools/docker-bench-security/docker-bench-security.sh

make container-bench
# Expected: "supply_chain_verification_failed" — refuses to run modified script

# Re-clone to fix
rm -rf ~/.openclaw/tools/docker-bench-security
make container-bench
# Expected: clones fresh, verifies hash, runs successfully
```

### 5. Credential Exposure

```bash
# During verification, check for API key exposure
make integrity-verify &
lsof -p $! 2>/dev/null | grep -i tmp
ps aux | grep curl
# Expected: no API key material in temp files or process listings
```

## New State Files

| File | Purpose | Permissions |
|------|---------|-------------|
| `~/.openclaw/tmp/` | Secure temp directory for credential passing | 700 |
| `~/.openclaw/tmp/curl-XXXXXX` | Ephemeral curl config (deleted after use) | 600 |

## Updated Protected Files

These files are now additionally protected:

| File | Reason |
|------|--------|
| `.git/config` | Prevents code exfiltration via remote URL modification |
| `n8n/workflows/*.json` | Detects workflow tampering (if directory exists) |
| `.specify/memory/constitution.md` | Controls agent automation framework (if file exists) |

## Recovery

### If audit log hash chain breaks

The hash chain may break if the system was running Phase 3 code during a concurrent access scenario. After Phase 4 deployment:

```bash
# Verify the chain
make integrity-verify
# If chain is broken, the log will indicate the break point
# The chain self-heals on the next write (new entry references current last hash)
```

### If docker-bench hash mismatch

```bash
# Clear the clone and let it re-fetch
rm -rf ~/.openclaw/tools/docker-bench-security
make container-bench
```

### If grype binary hash mismatch

```bash
# Re-install grype and update the stored hash
brew reinstall grype
make security-update-hashes
```
