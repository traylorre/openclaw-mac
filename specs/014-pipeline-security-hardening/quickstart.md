# Quickstart: Pipeline Security Hardening

**Prerequisites**: M3.5 workspace integrity deployed, n8n container running, OpenClaw configured

## 1. Verify Current Security Posture

```bash
make audit
```

Review the output for any FAIL results. The new CVE verification checks will report the version status of n8n, OpenClaw, and Ollama.

## 2. Update Dependencies (if needed)

Follow the procedures in `docs/DEPENDENCY-UPDATE-PROCEDURE.md` for any components with FAIL results.

```bash
# Example: Update n8n Docker image
docker compose -f scripts/templates/docker-compose.yml pull n8n
docker compose -f scripts/templates/docker-compose.yml up -d --no-deps n8n
make integrity-deploy --force   # Re-baseline manifest with new image digest
make audit                      # Verify updated version passes CVE checks
```

## 3. Harden Sensitive Files

```bash
# Re-deploy to HMAC-sign lock-state.json and heartbeat (ADV-002, ADV-004 fixes)
make integrity-deploy --force

# Verify all sensitive files have correct protections
make audit   # Look for CHK-SENSITIVE-FILE-* results
```

## 4. Review Security Documentation

| Document | Path | Purpose |
|----------|------|---------|
| ASI Mapping | `docs/ASI-MAPPING.md` | OWASP ASI Top 10 control mapping |
| Trust Boundary Model | `docs/TRUST-BOUNDARY-MODEL.md` | 5 trust zones with known gaps |
| Sensitive File Inventory | `docs/SENSITIVE-FILE-INVENTORY.md` | All files with protections |
| Update Procedures | `docs/DEPENDENCY-UPDATE-PROCEDURE.md` | How to update/rollback each dependency |

## 5. Verify Defense-in-Depth Layers

```bash
make audit   # Look for CHK-DEFENSE-LAYER-* results (5 layers: Prevent, Contain, Detect, Respond, Recover)
```

## Key Files

| File | Purpose |
|------|---------|
| `data/cve-registry.json` | Known CVE database (version-controlled) |
| `scripts/lib/cve-registry.sh` | CVE lookup functions |
| `docs/ASI-MAPPING.md` | OWASP ASI Top 10 control mapping |
| `docs/TRUST-BOUNDARY-MODEL.md` | Trust zones with gaps and roadmap |
| `docs/SENSITIVE-FILE-INVENTORY.md` | Sensitive file protections |
| `docs/DEPENDENCY-UPDATE-PROCEDURE.md` | Update/rollback procedures |
