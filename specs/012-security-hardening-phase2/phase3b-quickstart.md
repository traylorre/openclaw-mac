# Quickstart: Security Tool Integration (Phase 3B)

## Run Everything

```bash
make security
```

This runs all 4 security layers in sequence with a 5-minute timeout per layer:

| Layer | Tool | What it checks |
|-------|------|---------------|
| Integrity Verification | Custom (Phase 3) | Image digest, runtime config, credentials, workflows, drift |
| CIS Docker Benchmark | docker-bench-security v1.6.1 | 117 CIS checks (32 container runtime) |
| n8n Application Audit | n8n audit (built-in) | Stale creds, SQL injection, risky nodes, unprotected webhooks |
| Image CVE Scan | Grype | Known vulnerabilities in container image |

## Individual Commands

```bash
make integrity-verify    # Custom runtime integrity checks
make container-bench     # CIS Docker Benchmark (auto-installs on first run)
make n8n-audit           # n8n built-in security audit
make scan-image          # Image CVE scan (requires: brew install grype)
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | PASS — all layers clean |
| 1 | FAIL — critical findings detected |
| 2 | WARN — non-critical findings or skipped layers |
| 3 | SKIP — tool not available (individual layer) |

## Prerequisites

- **docker-bench-security**: Auto-installed on first `make container-bench` run (git clone v1.6.1)
- **Grype**: `brew install grype` (optional — pipeline skips if missing)
- **n8n audit**: Built into n8n, no installation needed

## Supply Chain Trust Model

| Tool | Trust Mechanism |
|------|----------------|
| docker-bench-security | Git clone pinned to v1.6.1 tag |
| Grype | Homebrew bottle (checksum-verified by Homebrew) |
| n8n audit | Built-in CLI command (no external dependency) |
| Custom integrity checks | HMAC-signed manifests, hash-chained audit log |

**Why not Trivy?** Trivy was supply-chain compromised in March 2026 (76/77 release tags poisoned, malicious Docker Hub images). Grype provides equivalent CVE scanning without the compromised supply chain.
