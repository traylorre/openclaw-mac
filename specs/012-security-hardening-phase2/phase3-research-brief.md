# Phase 3 Research Brief: Container & Orchestration Integrity

**Date**: 2026-03-24
**Scope**: Defense-in-depth container hardening for n8n orchestration layer (Colima → Docker → n8n)
**Classification**: Security-critical — shapes enforcement gates and pre-launch verification

---

## 1. Threat Intelligence

### 1.1 ClawHavoc Campaign (Container-Relevant Findings)

The ClawHavoc campaign (1,184 malicious skills) explicitly targets Docker configurations:
- Skills exploit Docker socket mounting for full host control
- AMOS (Atomic macOS Stealer) harvests credentials from 19 browsers + Keychain
- Reverse shells persist through container restarts via mounted volumes
- Credential exfiltration to webhook.site endpoints — no outbound network restriction = trivial exfil

### 1.2 OpenClaw CVEs (Container Escape Chain)

| CVE | CVSS | Vector | Relevance |
|-----|------|--------|-----------|
| CVE-2026-24763 | 8.8 | PATH injection in `docker exec` | Commands injected via env vars |
| CVE-2026-27002 | High | Sandbox config: `network:host`, `seccompProfile:unconfined`, docker.sock mounts | Attacker-controlled sandbox config escapes container |
| CVE-2026-25253 | 8.8 | Auth token theft → config.patch → host execution | 40,000+ exposed instances, 12,000 confirmed exploitable |

### 1.3 n8n CVEs (Orchestration Layer — 8 Critical in 3 Months)

| CVE | CVSS | Name | Attack |
|-----|------|------|--------|
| CVE-2026-21858 | 10.0 | "Ni8mare" | Unauth RCE: content-type confusion → file read → encryption key → session forge → RCE |
| CVE-2025-68613 | 9.9 | "N8scape" | Expression injection → system command execution. CISA KEV. 24,700 still exposed |
| CVE-2026-25049 | 9.4 | Sandbox bypass | Type confusion bypasses CVE-2025-68613 fix |
| CVE-2026-27493 | 9.5 | Form injection | Unauth command injection via form submissions |
| CVE-2026-27495 | 9.4 | Task runner escape | Prototype climbing → process.exec → read all credentials |
| CVE-2026-27497 | 9.4 | Merge node | SQL query mode → arbitrary code + file write |
| CVE-2026-25631 | 5.3 | Credential domain bypass | HTTP Request node sends creds to unintended domains |
| CVE-2026-1470 | High | Sandbox escape | Code injection via node execution context |

**Key insight**: n8n's credential encryption uses AES-256-CBC with MD5 key derivation (weak). The encryption key in `process.env` is readable by Code nodes when `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` (our current config for HMAC verification).

### 1.4 Container Runtime CVEs

| CVE | CVSS | Vector |
|-----|------|--------|
| CVE-2025-31133 | High | runC: /dev/null symlink → host file write |
| CVE-2025-52565 | High | runC: timing race → bypass maskedPaths |
| CVE-2025-52881 | High | runC: redirect writes → host crash or breakout |
| CVE-2025-9074 | 9.3 | Docker Desktop: internal HTTP API reachable from containers |

### 1.5 Supply Chain Attacks

- **n8n community nodes (Jan 2026)**: 8 malicious npm packages. Decrypted credentials using master key, exfiltrated OAuth tokens. 3,498 weekly downloads before removal.
- **Trivy (Mar 2026)**: 76 of 77 release tags poisoned via git tag repointing. Docker Hub images contained TeamPCP infostealer.
- **Docker "Ask Gordon"**: Image LABEL metadata used for prompt injection against Docker's AI assistant.
- **MCP Shadow Escape**: Zero-click attack via tool metadata. 270% surge in MCP vulnerabilities Q3 2025.

---

## 2. Security Framework Requirements

### 2.1 CIS Docker Benchmark v1.6.0 (Applicable Checks)

- **5.1**: Do not use `--privileged` ✅ (already enforced)
- **5.2**: Drop all capabilities ✅ (cap_drop: ALL)
- **5.3**: Do not mount Docker socket ✅ (not mounted, SC-017)
- **5.4**: Use `--read-only` filesystem ✅ (read_only: true)
- **5.7**: Set memory limits ✅ (2G limit)
- **5.12**: Mount volumes read-only where possible ✅ (entrypoint, workflows :ro)
- **5.15**: Do not share host network ✅ (bridge network)
- **5.16**: Bind ports to localhost ✅ (127.0.0.1:5678:5678)
- **5.25**: No new privileges ✅ (no-new-privileges:true)
- **4.5**: Enable Content Trust ❌ (DCT retired, Cosign not available for n8n image)
- **NEW**: Verify image by digest ❌ (currently using :latest tag)
- **NEW**: Runtime drift detection ❌ (no `docker diff` monitoring)
- **NEW**: Container environment audit ❌ (secrets visible in docker inspect)

### 2.2 NIST SP 800-190 (Application Container Security)

- **Image integrity**: Pin by digest, verify provenance, generate SBOM ❌
- **Runtime protection**: Process whitelisting, behavioral baselines, drift detection ❌
- **Credential management**: Secrets outside images, encrypt at rest ⚠️ (partial — Docker secrets used, but env access leaks key)
- **Network segmentation**: Per-container network policies, outbound restrictions ❌

### 2.3 OWASP Docker Security (14 Rules)

Currently compliant with 10 of 14 rules. Gaps:
- **Rule #5a**: Docker bypasses host firewalls — need explicit port binding verification ⚠️
- **Rule #9**: No image scanning in deployment pipeline ❌
- **Rule #12**: Encryption key accessible via Code node env access ⚠️
- **Rule #13**: No image signing or SBOM ❌

### 2.4 MITRE ATT&CK for Containers

| Technique | ID | Current Mitigation | Gap |
|-----------|----|--------------------|-----|
| Deploy Container | T1610 | Image recorded in manifest | No digest pinning, no runtime config verification |
| Escape to Host | T1611 | caps dropped, no-new-privileges | Colima writable $HOME mount |
| Container Discovery | T1613 | N/A | Docker socket on host accessible to any user process |
| Implant Internal Image | T1525 | Workflow comparison | No image integrity audit, community node supply chain |

---

## 3. Critical Findings (Current Deployment)

### FINDING 1: Colima Mounts Entire $HOME Writable (CRITICAL)

**Current state**: `colima.yaml` has `mounts: []` (empty = default = $HOME writable via virtiofs)
**Impact**: Container escape → VM → full read-write access to:
- `~/.ssh/` (SSH keys for lateral movement)
- `~/.gnupg/` (GPG keys)
- `~/.openclaw/` (all integrity infrastructure, signing keys, audit log)
- `~/.zshrc` (persistence via shell initialization)
- `~/projects/openclaw-mac/.env` (webhook secret)
- `~/projects/openclaw-mac/scripts/templates/secrets/` (encryption key)

**Remediation**: Configure Colima with explicit restrictive mounts:
```yaml
mounts:
  - location: /Users/scotthazlett
    writable: false
  - location: /Users/scotthazlett/projects/openclaw-mac
    writable: true
```

### FINDING 2: n8n Encryption Key File Permissions (HIGH)

**Current state**: `scripts/templates/secrets/n8n_encryption_key.txt` has permissions 644 (world-readable)
**Impact**: Any process on the host can read the master key that decrypts ALL n8n credentials
**Remediation**: `chmod 600` + add to integrity verification checks

### FINDING 3: Base Image Uses Mutable Tag (HIGH)

**Current state**: Dockerfile uses `FROM docker.n8n.io/n8nio/n8n:latest`
**Impact**: Image content changes silently on rebuild. No provenance verification. Supply chain attack via tag repointing (Trivy precedent).
**Remediation**: Pin by digest: `FROM docker.n8n.io/n8nio/n8n@sha256:<digest>`

### FINDING 4: Community Node Runtime Installation (HIGH)

**Current state**: `n8n-nodes-playwright` installed via `npm install` in entrypoint.sh on every container start
**Impact**: npm registry compromise = malicious code with access to n8n runtime and all decrypted credentials (January 2026 precedent)
**Remediation**: Pre-install at image build time only. Set `N8N_COMMUNITY_PACKAGES_ENABLED=false` at runtime.

### FINDING 5: No Container Runtime Configuration Verification (MEDIUM)

**Current state**: `integrity-verify.sh` checks workflow content but not container runtime config
**Impact**: Attacker could restart container with weaker config (privileged, host network, docker.sock mount)
**Remediation**: Verify at pre-launch: privileged=false, caps=ALL dropped, network!=host, no docker.sock, ports localhost-only

### FINDING 6: No Container Drift Detection (MEDIUM)

**Current state**: No monitoring for container filesystem changes
**Impact**: Attacker modifies container filesystem (adds backdoor executables, modifies node_modules) undetected
**Remediation**: `docker diff` in heartbeat cycle, alert on unexpected additions/changes

### FINDING 7: No Outbound Network Restriction (MEDIUM)

**Current state**: Container on bridge network with unrestricted outbound
**Impact**: Compromised Code node can exfiltrate to any endpoint (ClawHavoc used webhook.site)
**Remediation**: Document in quickstart; future: pf rules or Docker network egress policy

### FINDING 8: n8n Version Not Verified (MEDIUM)

**Current state**: No check that running n8n version is patched for known CVEs
**Impact**: Operator runs outdated n8n with CVSS 10.0 vulnerabilities
**Remediation**: Record n8n version at deploy, verify at startup, warn if below minimum safe version

---

## 4. Defense-in-Depth Layer Model

```
Layer 0: VM Boundary (Colima)
  └─ Mount restrictions, VM resource limits
Layer 1: Image Provenance
  └─ Digest pinning, version verification, SBOM
Layer 2: Image Integrity at Runtime
  └─ Digest comparison vs manifest baseline
Layer 3: Container Configuration
  └─ Privileged=false, caps dropped, network mode, port bindings, no docker.sock
Layer 4: Runtime Drift Detection
  └─ docker diff monitoring, alert on filesystem changes
Layer 5: Application-Level Verification
  └─ Credential enumeration, workflow comparison, n8n version check
Layer 6: Network Policy
  └─ Localhost-only ports, outbound restriction awareness
Layer 7: Continuous Monitoring
  └─ Heartbeat cycle: image ID, drift, credential count, config
```

---

## 5. Sensitive File Inventory (Container Attack Surface)

### Inside Container (Writable)
| Path | Contents | Attacker Impact |
|------|----------|-----------------|
| `/home/node/.n8n/database.sqlite` | All workflows, encrypted credentials, execution history, user accounts | Decrypt all creds with master key |
| `/home/node/.n8n/config` | Auto-generated config | Change encryption key |
| `/home/node/.n8n/nodes/` | Community node packages | Supply chain backdoor |
| `/data/browser-profile/` | LinkedIn session state | Account hijack |

### Inside Container (Read-Only)
| Path | Contents | Attacker Impact if Modified on Host |
|------|----------|-------------------------------------|
| `/entrypoint.sh` | Startup script | Exfiltrate encryption key during startup |
| `/tmp/workflows/*.json` | Workflow definitions | Add exfiltration nodes |
| `/run/secrets/n8n_encryption_key` | Master encryption key | N/A (read-only, but readable by Code nodes via process.env) |

### On Host (Container Escape via Colima)
| Path | Contents | Attacker Impact |
|------|----------|-----------------|
| `~/.ssh/` | SSH keys | Lateral movement |
| `~/.openclaw/` | All integrity infrastructure | Forge manifests, disable checks |
| `scripts/templates/secrets/` | Encryption key (644!) | Decrypt all n8n credentials |
| `~/.zshrc` | Shell init | Persistence |
| `.env` files | Webhook secret | Forge authenticated webhooks |

---

## 6. Content Note Candidates

1. **"Your container boundary is only as strong as your VM mount policy"** — Colima's default writable $HOME mount negates container isolation. One escape and the attacker has your SSH keys.

2. **"8 CVEs with CVSS ≥ 9.0 in 3 months: n8n's security quarter from hell"** — Timeline of the n8n CVE storm and what it means for AI orchestration platforms.

3. **"`docker diff`: the zero-dependency drift detector nobody uses"** — How a single built-in command provides lightweight runtime integrity monitoring.

4. **"Your encryption key's file permissions are the weakest link"** — The gap between Docker secrets (correct) and host-side file permissions (644) that undoes the entire credential isolation model.
