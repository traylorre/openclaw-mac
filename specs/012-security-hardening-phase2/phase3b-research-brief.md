# Phase 3B Research Brief: Security Tool Integration

**Date**: 2026-03-25
**Scope**: Integrate docker-bench-security and n8n audit into the security pipeline; supplement (not replace) custom verification

---

## 1. docker-bench-security

- **Version**: v1.6.1 (December 2024), implements CIS Docker Benchmark v1.6.0
- **Install**: `git clone --branch v1.6.1` or `docker pull docker/docker-bench-security:1.6.1`
- **macOS/Colima**: Requires socket mapping: `-v "$HOME/.colima/default/docker.sock":/var/run/docker.sock:ro`
- **Single container filter**: `-i n8n` (substring match)
- **Section filter**: `-c container_runtime` (Section 5 only)
- **Output**: JSON automatically at `<logfile>.json`; structured as `{tests: [{id, desc, results: [{id, desc, result, details, items}]}]}`
- **Non-interactive**: Fully automated, no prompts, exit 0 on completion (does NOT exit non-zero on check failures)

### Section 5 Checks (32 total) — Overlap Analysis

| Our Check | CIS ID | docker-bench-security |
|-----------|--------|----------------------|
| check_container_root | 5.x (user) | Yes — checks non-root |
| check_container_readonly | 5.13 | Yes — ReadonlyRootfs |
| check_container_caps | 5.4 | Yes — CapAdd restrictions |
| check_container_privileged | 5.5 | Yes — Privileged flag |
| check_docker_socket | 5.32 | Yes — socket mount |
| check_container_network | 5.10 | Yes — host network |
| check_container_resources | 5.11/5.12 | Yes — memory/CPU limits |
| check_colima_mounts | 5.6 | Partial — sensitive host dirs |
| check_secrets_env | N/A | No — custom secret patterns |
| check_n8n_bind | 5.14 | Partial — port binding |
| check_colima_running | N/A | No — Colima-specific |
| check_colima_vm_mounts | N/A | No — VM boundary (macOS-specific) |

**25 additional CIS checks** we don't implement: AppArmor (5.2), SELinux (5.3), sshd (5.7), privileged ports (5.8), PID namespace (5.16), IPC namespace (5.17), host devices (5.18), ulimits (5.19), mount propagation (5.20), UTS namespace (5.21), health checks (5.27), PIDs limit (5.29), default bridge (5.30), user namespaces (5.31), plus more.

### Decision: Keep Custom + Add docker-bench-security

- Custom checks stay for unified PASS/FAIL/WARN report integration
- docker-bench-security adds as supplementary CIS compliance layer
- Overlap is intentional redundancy (defense in depth)
- Net line savings from trimming: only 56 lines — not worth the integration loss

## 2. n8n audit

- **CLI**: `n8n audit` or `n8n audit -c credentials,nodes`
- **Docker exec**: `docker exec -u node "$cid" n8n audit`
- **Output**: JSON structured as `{[reportTitle]: {risk, sections: [{title, description, recommendation, location}]}}`
- **5 categories**: credentials (stale creds), database (SQL injection patterns), nodes (risky/community/custom), instance (unprotected webhooks, outdated version, security settings), filesystem (nodes accessing host FS)
- **Requires**: Running n8n instance with database access
- **REST API**: `POST /api/v1/audit` with API key auth

### Complementary to Our Checks

| n8n audit checks | Our Phase 3 checks |
|------------------|-------------------|
| Stale credentials (unused/inactive) | Unauthorized credentials (added outside pipeline) |
| Community node existence flagged | Community node baseline COMPARISON |
| Unprotected webhooks | Workflow integrity (hash comparison) |
| Outdated n8n version | n8n minimum safe version threshold |
| SQL injection patterns in nodes | Not covered (out of scope) |
| Risky official nodes | NODES_EXCLUDE env var verification |

**Key gap n8n audit fills that we don't**: SQL injection pattern detection in workflow expressions, stale credential hygiene, unprotected webhook flagging.

**Key gap we fill that n8n audit doesn't**: Credential injection detection, workflow tampering detection, container image replacement, runtime config verification, filesystem drift, supply chain node inventory.

## 3. Trivy Status (March 2026)

**COMPROMISED**: 76/77 release tags poisoned via git tag repointing. Malicious Docker Hub images (tags 0.69.5, 0.69.6) contained TeamPCP infostealer. Vulnerability database updates suspended.

**Recommendation**: Use **Grype** (Anchore) for vulnerability scanning instead. Narrower scope (CVE matching only) but uncompromised supply chain. `brew install grype`.

## 4. Architecture Decision

```
make audit          → runs hardening-audit.sh (unified report, custom + CIS checks)
make container-bench → runs docker-bench-security (comprehensive CIS compliance)
make n8n-audit      → runs n8n audit (application hygiene)
make integrity-verify → runs integrity-verify.sh (runtime attestation)
make scan-image     → runs grype (CVE scanning)

make security       → all of the above in sequence
```

Three layers, five targets, one `make security` to run them all.
