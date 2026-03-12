# Research: Hardening Guide Extension

**Plan**: [plan.md](plan.md) | **Spec**: [spec.md](spec.md) (Rev 29)
**Date**: 2026-03-11

## Research Tasks

All NEEDS CLARIFICATION items from Technical Context resolved below.

---

### R-001: n8n Docker Secrets (`_FILE` env var support)

**Context**: FR-057 specifies Docker secrets access pattern for containerized
path. Need to determine if n8n supports the `_FILE` suffix convention.

**Decision**: n8n has partial `_FILE` suffix support, but
`N8N_ENCRYPTION_KEY_FILE` has known bugs. Use entrypoint wrapper as fallback.

**Rationale**: n8n docs describe `_FILE` suffix support for loading secrets
from files. However, `N8N_ENCRYPTION_KEY_FILE` specifically fails in queue
mode (workers can't find the key). GitHub issues #14596 and #20175 document
these bugs. The guide should document both approaches:

1. **Primary**: Use `_FILE` suffix for env vars where it works reliably
2. **Fallback**: Entrypoint wrapper script for `N8N_ENCRYPTION_KEY` and any
   other vars with known `_FILE` bugs

**Implementation approach**: Reference docker-compose.yml should use Docker
secrets with an entrypoint wrapper for the encryption key:

```bash
#!/bin/sh
# Read Docker secrets that don't support _FILE suffix reliably
if [ -f /run/secrets/N8N_ENCRYPTION_KEY ]; then
  export N8N_ENCRYPTION_KEY="$(cat /run/secrets/N8N_ENCRYPTION_KEY)"
fi
exec n8n start
```

This must be documented in the guide (FR-057) and in the reference
docker-compose.yml (FR-058).

**Alternatives considered**:

- Direct env vars in compose file: rejected (exposes secrets in
  `docker inspect`)
- Rely solely on `_FILE` suffix: rejected (known bugs with encryption key)
- Kubernetes secrets: out of scope (single Mac Mini, not k8s)

**Sources**: n8n Configuration Methods docs, GitHub #14596, GitHub #20175

---

### R-002: n8n MFA/2FA Support

**Context**: FR-067 asks whether n8n supports multi-factor authentication.

**Decision**: n8n natively supports TOTP-based 2FA. Enforcement available
since v1.102.0 via `N8N_MFA_ENABLED` env var (default: `true`).

**Rationale**: TOTP via authenticator apps (Google Authenticator, Authy) is
built in. WebAuthn/FIDO2/U2F are not supported. The guide should recommend
enabling 2FA for the owner account and note the WebAuthn gap.

**Impact on spec**: FR-067 can recommend 2FA without compensating controls.
The "if n8n supports MFA" conditional in the spec resolves to "yes, it does."

**Sources**: n8n 2FA docs, n8n 2FA env vars docs

---

### R-003: n8n Security Environment Variables (Corrections)

**Context**: FR-059 references several env vars. Research found naming
corrections and deprecations that must be reflected in the guide.

**Decisions**:

| Spec Reference | Actual Name | Status | Notes |
|----------------|-------------|--------|-------|
| `N8N_PUBLIC_API_ENABLED` | `N8N_PUBLIC_API_DISABLED` | Active | Naming inverted: set `true` to disable |
| `EXECUTIONS_PROCESS` | N/A | **Deprecated** | Removed in v2.0. Setting to `own` causes startup failure |
| `N8N_BLOCK_ENV_ACCESS_IN_NODE` | Same | Active | Default is `true` in v2.0 (was `false` in v1.x) |
| `N8N_RESTRICT_FILE_ACCESS_TO` | Same | Active | Has a default restriction path in v2.0 |
| `N8N_DIAGNOSTICS_ENABLED` | Same | Active | Default `true`; telemetry sent every 6 hours |

**Impact on spec**: FR-059 env var reference table needs corrections:

- Replace `N8N_PUBLIC_API_ENABLED=false` with `N8N_PUBLIC_API_DISABLED=true`
- Remove `EXECUTIONS_PROCESS` (deprecated, causes errors in v2.0)
- Note that `N8N_BLOCK_ENV_ACCESS_IN_NODE` defaults to `true` in v2.0
  (guide should verify this is set, not instruct to set it)

**Sources**: n8n Security env vars docs, n8n v2.0 breaking changes,
Executions env vars docs

---

### R-004: n8n Node Type Restrictions

**Context**: FR-021 asks whether n8n supports disabling specific node types.

**Decision**: Yes. Use `NODES_EXCLUDE` env var with a JSON array.
In n8n v2.0, `ExecuteCommand` and `LocalFileTrigger` are blocked by default.

**Rationale**: The guide can recommend a concrete `NODES_EXCLUDE` value
for security-sensitive deployments. Example:

```text
NODES_EXCLUDE=["n8n-nodes-base.executeCommand","n8n-nodes-base.ssh",
"n8n-nodes-base.localFileTrigger"]
```

There is also `NODES_INCLUDE` for allowlist mode (stricter but requires
updating when new nodes are needed).

**Impact on spec**: FR-021 node restriction policy can reference specific
env var and node type strings. The v2.0 defaults already block the most
dangerous node.

**Sources**: n8n Block access to nodes docs, n8n v2.0 breaking changes

---

### R-005: n8n Webhook Authentication

**Context**: FR-039 needs to document webhook auth methods.

**Decision**: Four methods supported: None, Basic Auth, Header Auth, JWT Auth.

**Rationale**: Header Auth with a cryptographically random secret is the
recommended minimum (aligns with spec FR-039). JWT Auth provides stronger
validation for environments that already have JWT infrastructure. Basic Auth
is acceptable but weaker. "None" must be explicitly called out as dangerous.

**Sources**: n8n Webhook node docs

---

### R-006: Google Santa on Apple Silicon

**Context**: FR-032 recommends Santa as part of IDS stack. Need to confirm
Apple Silicon compatibility.

**Decision**: Santa fully supports Apple Silicon via universal binaries.
Project moved from `google/santa` (archived) to `northpolesec/santa`.

**Rationale**: Santa uses Apple's Endpoint Security framework, which is fully
supported on Apple Silicon. No compatibility issues found.

**Impact on guide**: Update all Santa references to use `northpolesec/santa`
as the canonical source. The `google/santa` repo is archived.

**Sources**: <https://github.com/northpolesec/santa>, <https://santa.dev/>

---

### R-007: Colima Security Defaults

**Context**: FR-017 uses Colima as primary runtime. Need to understand what
security is provided by default vs what must be configured.

**Decision**: Colima provides minimal security hardening by default.

**Key findings**:

- Docker socket at `~/.colima/<profile>/docker.sock` — no special access
  restrictions beyond Unix file permissions
- VM network: accepts connections on 0.0.0.0 but rejects non-loopback source
  IPs (basic port forwarding isolation)
- No AppArmor, seccomp, or other container security policies beyond Docker
  defaults
- macOS firewall/pf rules do NOT pass through to containers

**Impact on guide**: The guide must explicitly configure container security
(capabilities, seccomp, read-only fs) in docker-compose.yml rather than
relying on Colima defaults. FR-041 and FR-058 are correctly scoped.

**Sources**: Colima FAQ, GitHub discussions

---

### R-008: macOS pf for Container Outbound Filtering

**Context**: FR-030 specifies pf outbound filtering. Need to determine if
pf can filter container traffic.

**Decision**: macOS pf CANNOT directly see or filter container traffic from
Colima/Docker. Container traffic is NAT'd through the VM's networking stack.

**Architecture**:

```text
Container → Linux VM networking → vmnet NAT → host network interface
                                     ↑
                          macOS pf sees traffic here
                          (as vmnet, not per-container)
```

**Viable approaches for outbound filtering**:

1. **iptables inside the VM** (recommended): `colima ssh` into the VM and
   configure iptables/nftables rules. Container traffic is visible with
   proper source IPs inside the VM
2. **Filtering proxy inside VM**: Run Squid or similar for HTTP/HTTPS egress
3. **LuLu on host**: Can block the QEMU/vz process, but all-or-nothing
   (blocks all container traffic, not per-container)
4. **Docker network policies**: Use `--internal` flag for networks that
   don't need external access

**Impact on spec**: FR-030's pf allowlisting recommendation must be reframed.
For containerized path, outbound filtering happens inside the Colima VM
(iptables), not via macOS pf. For bare-metal path, macOS pf works as
described. The guide must clearly separate these approaches by deployment
path.

**Sources**: Lima VM network docs, community blog posts on macOS pf

---

### R-009: Apify Webhook Signing

**Context**: FR-060 asks about Apify webhook signature verification.

**Decision**: Apify does NOT support HMAC webhook signing.

**Security model**: Apify recommends a secret token in the webhook URL
(e.g., `?token=SECRET`). Informational headers (`X-Apify-Webhook`,
`X-Apify-Webhook-Dispatch-Id`) are included but not cryptographic.

**Impact on spec**: FR-060 must adjust the Apify webhook security
recommendation. Instead of "verify Apify webhook signatures," recommend:

- Use a secret token in the webhook URL
- Combine with n8n webhook authentication (Header Auth per FR-039)
- Optionally validate the dispatch ID against Apify's API
- IP allowlisting if Apify publishes source IP ranges

**Sources**: Apify webhook docs, Apify API v2 docs

---

### R-010: macOS Tahoe (26) Security Changes

**Context**: Guide targets both Tahoe and Sonoma. Need to document where
controls differ.

**Decision**: Tahoe introduces stricter Gatekeeper, SIP, TCC, and Local
Network Privacy enforcement.

**Key differences**:

| Area | Sonoma (14) | Tahoe (26) |
|------|-------------|------------|
| Gatekeeper | Standard notarization | Stricter runtime checks; apps flagged as "damaged" more aggressively |
| SIP | Standard enforcement | More components locked behind system volumes |
| TCC | Standard prompts | PPPC profile visibility fixed in 26.2; Terminal FDA grants full access to scripts |
| Local Network | Basic prompts | Stricter enforcement; documented bugs in prompt triggering |
| Firewall | Application Firewall + pf | No architectural changes |
| Background services | Login items management | More aggressive auditing of launch agents/daemons |

**Impact on guide**: Where controls differ, the guide should note
"Tahoe-specific" or "Sonoma-specific" behavior. Most controls apply
identically to both. The guide should note the TCC/Terminal FDA issue
as a known limitation.

**Sources**: Apple security release notes, ERNW macOS 26 Hardening Guide,
Secure Mac blog

---

### R-011: Objective-See Tools on Apple Silicon

**Context**: FR-032 recommends BlockBlock, LuLu, KnockKnock. Need to
confirm Apple Silicon support.

**Decision**: All three tools support Apple Silicon natively.

| Tool | Apple Silicon Support | Notes |
|------|----------------------|-------|
| LuLu | Universal binary | Native M1 since early 2021 |
| BlockBlock | Universal binary | Native support in recent versions |
| KnockKnock | Universal binary | Native since v2.2.0 (Feb 2021) |

**Impact on guide**: No compatibility warnings needed. Recommend latest
versions to ensure native ARM support (avoid Rosetta 2).

**Sources**: objective-see.org/tools.html, GitHub release pages

---

### R-012: Docker Compose Secrets — `file:` Source Only (Standalone Mode)

**Context**: FR-057/FR-058 reference Docker secrets. Need to clarify that
standalone `docker compose` (via Colima) only supports `file:` source
secrets, not Swarm-mode `external: true`.

**Decision**: All secret definitions in the reference docker-compose.yml
must use `file:` source pointing to host files with restricted permissions.

**Rationale**: Docker Compose in standalone mode (non-Swarm) only supports
the `file:` source for secrets. The `external: true` syntax requires Docker
Swarm mode, which Colima does not run. This is a common source of confusion
because Docker's documentation mixes standalone and Swarm examples.

**Implementation approach**: Reference docker-compose.yml must use:

```yaml
secrets:
  n8n_encryption_key:
    file: ./secrets/n8n_encryption_key.txt  # chmod 600, owned by user
```

The guide should include instructions for creating the secrets directory
with proper permissions (`chmod 700 ./secrets`, `chmod 600 ./secrets/*`).

**Sources**: Docker Compose secrets docs, Docker Compose file reference

---

### R-013: iptables Persistence Inside Colima VM

**Context**: R-008 recommends iptables inside the Colima VM for container
outbound filtering. Need to document persistence strategy since iptables
rules are lost on `colima stop/start` or `colima delete`.

**Decision**: Use a Lima provisioning script to inject iptables rules at
VM boot time.

**Rationale**: Colima wraps Lima, which supports `provision:` scripts in
its YAML config (`~/.colima/<profile>/colima.yaml`). These scripts run on
VM startup and can restore iptables rules. This is the only reliable
persistence mechanism — there is no Colima-native way to inject rules.

**Implementation approach**:

1. Define iptables rules in a shell script fragment
2. Add to Colima config via `provision:` block:

```yaml
provision:
  - mode: system
    script: |
      iptables -A OUTPUT -d 10.0.0.0/8 -j ACCEPT
      iptables -A OUTPUT -d 172.16.0.0/12 -j ACCEPT
      iptables -A OUTPUT -p tcp --dport 443 -d <n8n-allowed-hosts> -j ACCEPT
      iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
      iptables -A OUTPUT -j DROP
```

1. Document that `colima delete` destroys the config — backup strategy needed
1. Note that `colima template` can set defaults for new profiles

**Alternatives considered**:

- `iptables-save`/`iptables-restore` via cron inside VM: fragile, depends
  on cron being available in the Lima VM
- Docker network `--internal` flag: too coarse, blocks all external access
  (some outbound is needed for n8n webhooks, updates)

**Sources**: Lima provisioning docs, Colima GitHub issues

---

## Summary of Spec Corrections Needed

These findings identify factual corrections that should be applied during
implementation (not spec revision, since the spec describes intent, not
exact env var names):

1. **FR-059**: Replace `N8N_PUBLIC_API_ENABLED=false` with
   `N8N_PUBLIC_API_DISABLED=true`
2. **FR-059**: Remove `EXECUTIONS_PROCESS` (deprecated in v2.0)
3. **FR-059**: Note `N8N_BLOCK_ENV_ACCESS_IN_NODE` defaults to `true`
   in v2.0
4. **FR-057**: Document entrypoint wrapper for `N8N_ENCRYPTION_KEY` Docker
   secret (partial `_FILE` support — encryption key has known bugs)
5. **FR-060**: Apify webhooks use URL tokens, not HMAC signatures
6. **FR-030**: Containerized outbound filtering requires iptables inside
   Colima VM, not macOS pf
7. **FR-032**: Update Santa reference to `northpolesec/santa`
8. **FR-067**: n8n supports native TOTP 2FA; recommend enabling
