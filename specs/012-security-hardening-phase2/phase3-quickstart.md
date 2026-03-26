# Quickstart: Container & Orchestration Integrity (Phase 3)

**Spec**: [phase3-spec.md](phase3-spec.md)
**Plan**: [phase3-plan.md](phase3-plan.md)

---

## Prerequisites

- Phase 1A (Expanded Protection Surface) complete
- Phase 2 (Hash-Chained Audit Log) complete
- Colima running with Docker daemon accessible
- `openclaw-n8n` container running
- macOS Keychain unlocked (for HMAC signing)

## Deploy Container Baseline

```bash
# Record the container's image digest, n8n version,
# credential names, and community node inventory
make integrity-deploy

# Verify the manifest now includes container attestation fields
jq '.container_image_digest, .container_n8n_version, .expected_credentials' \
    ~/.openclaw/manifest.json
```

## Pre-Launch Verification

```bash
# Run full integrity verification (includes container checks)
make integrity-verify

# Expected output (all container checks):
# [PASS] Container image digest matches manifest
# [PASS] Container runtime configuration verified (10/10 properties)
# [PASS] Credential set matches baseline (3/3)
# [PASS] All workflows match repository versions (11/11)
# [PASS] No unexpected community nodes
# [PASS] No container filesystem drift detected
# [PASS] Container ID stable throughout verification
```

## Continuous Monitoring

```bash
# Start the monitoring service (includes container heartbeat checks)
make integrity-monitor

# Monitor checks in each heartbeat cycle:
# - Image digest comparison
# - Credential name set comparison
# - Filesystem drift detection
# - Container reachability
```

## VM Boundary Audit

```bash
# Run the hardening audit (includes Colima mount check)
make audit

# Look for:
# [WARN] CHK-COLIMA-MOUNTS: Home directory mounted writable
#        Remediation: Edit ~/.colima/default/colima.yaml
```

## Operator Commands

### After Upgrading n8n

```bash
# 1. Rebuild the custom image
make docker-image-setup

# 2. Restart the container
docker compose -f scripts/templates/docker-compose.yml up -d

# 3. Re-deploy the baseline (captures new image digest + version)
make integrity-deploy

# 4. Verify the new baseline
make integrity-verify
```

### After Adding a Credential to n8n

```bash
# Re-deploy to update the credential baseline
make integrity-deploy
```

### After Installing a Community Node

```bash
# Re-deploy to update the community node inventory
make integrity-deploy
```

### Updating the Minimum Safe n8n Version

```bash
# Edit the container security configuration
# (requires re-signing and re-deploying)
make container-security-config-update MIN_VERSION=1.123.0
```

## Verification Order

The system enforces this execution order:

1. Container discovery → pin container ID
2. Image digest verification (BLOCKING)
3. Runtime configuration verification (BLOCKING)
4. Application-level checks (only if 2-3 pass):
   - Credential enumeration
   - Workflow comparison
   - Community node verification
   - Filesystem drift detection
5. Container ID re-verification (invalidate if changed)

## After Phase 3 Upgrade (Migration)

The workflow comparison now includes the `.meta` field (previously excluded). On first verification after upgrade, all workflows may report as mismatched. To resolve:

```bash
# Re-export workflows from the running container to sync .meta fields
make workflow-export
git add workflows/
git commit -m "Sync workflow .meta fields for Phase 3 comparison"
make integrity-deploy
```

## Recovery Procedures

| Failure | Recovery |
|---------|----------|
| Image digest mismatch | Confirm correct image is running, then `make integrity-deploy` to re-baseline |
| Unexpected credential | Investigate the credential in n8n UI. If legitimate, `make integrity-deploy`. If not, remove it |
| Runtime config violation | Fix `docker-compose.yml`, restart container, then `make integrity-verify` |
| Workflow mismatch | `make workflow-export && make integrity-deploy` (or investigate if unexpected) |
| Community node unexpected | Investigate the package. If legitimate, `make integrity-deploy`. If not, remove it |
| All workflows meta-only mismatch | Run the migration step above |

## What the Checks Detect

**Important caveat (FR-P3-039):** Credential enumeration, workflow export, and community node listing run inside the container via `docker exec`. They detect artifacts of **partial** compromise (attacker adds credentials but doesn't modify the n8n binary). A **fully** compromised container where the attacker controls the n8n binary can return fabricated results. Image digest verification is the primary defense against total container takeover.

| Check | Detects | Does NOT Detect | Trust Level |
|-------|---------|-----------------|-------------|
| Image digest | Container replacement, supply chain image tampering | In-container modifications | Host-side (high trust) |
| Runtime config | Privilege escalation, Docker socket mount, network escape | Config changes that don't survive restart | Host-side (high trust) |
| Credential enum | Unauthorized credential injection | Credential value changes, full takeover | Container-side (partial trust) |
| Workflow comparison | Workflow modification, exfiltration node injection | Runtime-only changes, full takeover | Container-side (partial trust) |
| Community nodes | Supply chain package injection | Malicious code in legit packages, full takeover | Container-side (partial trust) |
| Filesystem drift | Added/modified files in overlay | Changes in Docker volumes | Host-side (high trust) |
| VM boundary | Writable home directory mount | Runtime VM escape vulnerabilities | Host-side (high trust) |

## Framework Coverage

This phase addresses:
- CIS Docker Benchmark: 5.1, 5.2, 5.3, 5.4, 5.7, 5.16, 5.25
- NIST SP 800-190: Image integrity, runtime protection, credential management
- OWASP Docker: Rules #1, #2, #3, #4, #8
- MITRE ATT&CK: T1610, T1611, T1525, T1613
