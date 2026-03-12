# Data Model: Hardening Guide Extension

**Plan**: [plan.md](plan.md) | **Spec**: [spec.md](spec.md) (Rev 29)

This feature produces documentation and a bash script, not application
software. The "data model" describes the structured entities that the guide
and audit script operate on. These entities drive the guide's organization,
the audit script's check logic, and the operator's mental model.

## Entities

### Control Area

A discrete security domain addressed by the guide. Each control area maps
to one or more guide sections, FRs, and audit checks.

| Field | Type | Description |
|-------|------|-------------|
| id | integer (1-39) | Sequential identifier |
| name | string | Human-readable name (e.g., "FileVault", "SSH Hardening") |
| layer | enum | Defensive layer: `prevent`, `detect`, `respond` |
| severity | enum | `critical` (FAIL if missing) or `recommended` (WARN if missing) |
| guide_section | string | Section anchor in HARDENING.md |
| primary_frs | string[] | FR identifiers that define this area |
| audit_checks | AuditCheck[] | Checks that verify this area |
| sources | string[] | Canonical source citations |
| deployment_paths | enum[] | Which paths apply: `containerized`, `bare-metal`, `both` |

**39 control areas** (from spec FR-002): FileVault, Firewall, SIP,
Gatekeeper, Software updates, DNS security, Screen lock, n8n hardening,
Credential management, Antivirus/EDR, IDS, Bluetooth, SSH, USB/Thunderbolt,
Sharing services, Outbound filtering, Logging and alerting, Backup and
recovery, PII protection, Launch daemon auditing, Physical security, Guest
account, Automatic login, IPv6, Container isolation, Injection defense,
Memory/swap, iCloud exposure, Lockdown Mode, XProtect/MRT, Supply chain
integrity, Workflow integrity, SSRF, Data exfiltration, Service binding,
Recovery mode, Secrets exposure, Clipboard security, Certificate trust.

### Audit Check

A single verifiable assertion executed by the audit script.

| Field | Type | Description |
|-------|------|-------------|
| id | string | Check identifier (e.g., `CHK-FILEVAULT`) |
| control_area | ControlArea | Parent control area |
| description | string | What this check verifies |
| command | string | Bash command that performs the check |
| expected | string | Expected output for PASS |
| severity | enum | `critical` → FAIL, `recommended` → WARN |
| deployment_path | enum | `containerized`, `bare-metal`, `both` |
| guide_section_ref | string | Section in HARDENING.md with remediation |
| json_key | string | Key name in `--json` output (FR-023) |

### Credential

A secret or authentication token managed in this deployment.

| Field | Type | Description |
|-------|------|-------------|
| name | string | Credential identifier (e.g., "N8N_ENCRYPTION_KEY") |
| type | enum | `api_key`, `password`, `token`, `certificate`, `encryption_key` |
| storage_containerized | string | Where stored on container path (Docker secrets) |
| storage_bare_metal | string | Where stored on bare-metal path (Keychain, env var) |
| rotation_interval | string | Recommended rotation period (e.g., "90 days") |
| revocation_procedure | string | Steps to revoke and replace |
| blast_radius | string | What an attacker gains with this credential |
| frs | string[] | Related FRs (FR-012, FR-043, FR-057) |

**Known credentials**: N8N_ENCRYPTION_KEY, LinkedIn session token,
Apify API key, SSH private key, SMTP relay credentials, n8n API key
(if enabled), n8n basic auth password, Docker registry credentials
(if private), N8N_USER_MANAGEMENT_JWT_SECRET.

### Deployment Path

One of two independent, complete deployment configurations.

| Field | Type | Description |
|-------|------|-------------|
| id | enum | `containerized` or `bare-metal` |
| name | string | Human-readable name |
| runtime | string | Container runtime or process model |
| isolation_mechanism | string | Container vs service account |
| credential_storage | string | Docker secrets vs Keychain |
| pros | string[] | Security advantages |
| cons | string[] | Limitations or tradeoffs |
| primary_frs | string[] | FRs specific to this path |

### Security Tool

A tool recommended by the guide for a specific defensive function.

| Field | Type | Description |
|-------|------|-------------|
| name | string | Tool name (e.g., "Google Santa") |
| cost | enum | `free`, `paid` |
| cost_amount | string | null if free, approximate price if paid |
| function | string | What security function it provides |
| layer | enum | `prevent`, `detect`, `respond` |
| control_areas | string[] | Which control areas it serves |
| install_method | string | How to install (e.g., "brew install") |
| platform_support | string | Apple Silicon, Intel, or both |
| source_url | string | Official project URL |
| paid_alternative | string | null if free; what paid tool fills the gap |
| free_alternative | string | null if paid; what free tool covers the same |

**Tool inventory**:

| Tool | Cost | Function | Layer |
|------|------|----------|-------|
| Colima | Free | Container runtime (Lightweight Linux VM) | Prevent |
| Docker CLI | Free | Container management | Prevent |
| ClamAV | Free | Antivirus scanning | Detect |
| Google Santa | Free | Binary allow/blocklisting | Prevent |
| BlockBlock | Free | Persistence mechanism detection | Detect |
| LuLu | Free | Application-level outbound firewall | Detect |
| KnockKnock | Free | Persistence audit | Detect |
| Quad9 | Free | Malware-blocking DNS | Prevent |
| Caddy | Free | Reverse proxy with auto-TLS | Prevent |
| msmtp | Free | SMTP relay for notifications | Respond |
| Bitwarden CLI | Free | Password/secret management | Prevent |
| shellcheck | Free | Bash static analysis | N/A (dev tool) |
| Docker Desktop | $7/mo | Container runtime (GUI + VM) | Prevent |
| Little Snitch | $59 | Advanced outbound firewall | Detect |
| SentinelOne | ~$5/mo | EDR/antivirus | Detect |

### PII Data Field

A field containing personally identifiable information from LinkedIn scraping.

| Field | Type | Description |
|-------|------|-------------|
| name | string | Field name (e.g., "full_name") |
| sensitivity | enum | `public`, `semi-private`, `derived` |
| source | string | Where this data originates |
| storage_locations | string[] | Where this data lives at rest |
| retention_recommendation | string | How long to keep |
| gdpr_relevant | boolean | Subject to GDPR obligations |

### Notification Channel

A method for delivering audit failure alerts.

| Field | Type | Description |
|-------|------|-------------|
| type | enum | `email`, `macos_notification`, `webhook` |
| priority | enum | `primary`, `fallback`, `optional` |
| setup_complexity | string | How hard to configure |
| requires | string[] | Prerequisites |
| fr | string | FR-024 |

### Scheduled Job

A launchd-managed recurring task.

| Field | Type | Description |
|-------|------|-------------|
| name | string | Job identifier (e.g., "com.openclaw.audit") |
| plist_path | string | Path to launchd plist |
| interval | string | Default schedule (e.g., "weekly") |
| script | string | Script that runs |
| output | string | Where output goes |
| fr | string | FR-022 |

## State Transitions

### Audit Check Result Flow

```text
                    ┌──────────┐
                    │  PENDING  │  (check not yet run)
                    └─────┬────┘
                          │ run check command
                          ▼
              ┌───────────┴───────────┐
              │                       │
        ┌─────▼─────┐          ┌─────▼─────┐
        │   PASS    │          │ NOT PASS   │
        └───────────┘          └─────┬──────┘
                                     │
                         ┌───────────┴───────────┐
                         │                       │
                   ┌─────▼─────┐          ┌─────▼─────┐
                   │   FAIL    │          │   WARN    │
                   │ (critical)│          │(recommend)│
                   └───────────┘          └───────────┘
```

### Credential Lifecycle

```text
  ┌──────────┐   rotate    ┌──────────┐   compromise   ┌──────────┐
  │  ACTIVE  │────────────▶│  ROTATED │    detected    │  REVOKED │
  │          │◀────────────│  (new)   │───────────────▶│          │
  └─────┬────┘   expires   └──────────┘                └──────────┘
        │                                                    │
        │              ┌──────────┐                          │
        └─────────────▶│ EXPIRED  │◀─────────────────────────┘
           age > limit └──────────┘    post-revocation cleanup
```

## Relationships

```text
Control Area 1──* Audit Check        (each area has 1+ checks)
Control Area *──* Deployment Path    (areas apply to one or both paths)
Control Area *──* Security Tool      (tools serve one or more areas)
Control Area 1──* FR                 (FRs define areas)
Credential   *──* Deployment Path   (most credentials exist in both paths with per-path storage)
Scheduled Job 1──1 Audit Check[]    (job runs the audit script)
```
