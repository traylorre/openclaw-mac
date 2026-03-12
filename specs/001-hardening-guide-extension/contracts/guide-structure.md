# Contract: Hardening Guide Structure

**Artifact**: `docs/HARDENING.md`
**FRs**: FR-001 through FR-010 (meta-FRs defining guide structure)

## Document Structure

The guide follows a fixed section hierarchy. Each top-level section
addresses a defensive domain; subsections address individual controls.

```text
# macOS Hardening Guide for n8n + Apify Deployment

## Preamble
  - Purpose and scope
  - Threat model summary (FR-001)
  - How to use this guide
  - Deployment path decision tree (containerized vs bare-metal)

## 1. Threat Model
  - Platform description
  - Assets to protect
  - Adversaries
  - Attack surface map
  - What is NOT in scope

## 2. OS Foundation (Prevent)
  - §2.1 Disk Encryption (FileVault)
  - §2.2 Firewall
  - §2.3 System Integrity Protection (SIP)
  - §2.4 Gatekeeper and XProtect
  - §2.5 Software Updates
  - §2.6 Screen Lock and Login Security
  - §2.7 Guest Account and Sharing Services
  - §2.8 Lockdown Mode
  - §2.9 Recovery Mode Password

## 3. Network Security (Prevent)
  - §3.1 SSH Hardening
  - §3.2 DNS Security
  - §3.3 Outbound Filtering
  - §3.4 Bluetooth
  - §3.5 IPv6
  - §3.6 Service Binding and Port Exposure

## 4. Container Isolation (Prevent) — Containerized Path
  - §4.1 Colima Setup
  - §4.2 Docker Security Principles
  - §4.3 Reference docker-compose.yml (FR-058)
  - §4.4 Advanced Container Hardening (capabilities, seccomp, socket)
  - §4.5 Container Networking

## 5. n8n Platform Security (Prevent)
  - §5.1 Binding and Authentication
  - §5.2 User Management
  - §5.3 Security Environment Variables (FR-059)
  - §5.4 REST API Security
  - §5.5 Webhook Security
  - §5.6 Execution Model and Node Isolation
  - §5.7 Community Node Vetting
  - §5.8 Reverse Proxy (Caddy/nginx)
  - §5.9 Update and Migration Security

## 6. Bare-Metal Path (Prevent) — Bare-Metal Only
  - §6.1 Dedicated Service Account (_n8n)
  - §6.2 Keychain Integration
  - §6.3 launchd Execution
  - §6.4 Filesystem Permissions

## 7. Data Security (Prevent)
  - §7.1 Credential Management
  - §7.2 Credential Lifecycle (rotation, revocation)
  - §7.3 Scraped Data Input Security (injection defense)
  - §7.4 PII Protection (GDPR, CCPA, LinkedIn ToS)
  - §7.5 SSRF Defense
  - §7.6 Data Exfiltration Prevention
  - §7.7 Supply Chain Integrity
  - §7.8 Apify Actor Security
  - §7.9 Secure Deletion (APFS/SSD limitations)
  - §7.10 Clipboard Security

## 8. Detection and Monitoring (Detect)
  - §8.1 IDS Tools (Santa, BlockBlock, LuLu, KnockKnock)
  - §8.2 Launch Daemon Auditing
  - §8.3 Workflow Integrity Monitoring
  - §8.4 macOS Logging (unified log predicates)
  - §8.5 Credential Exposure Monitoring
  - §8.6 iCloud and Cloud Service Exposure
  - §8.7 Certificate Trust Monitoring

## 9. Response and Recovery (Respond)
  - §9.1 Incident Response Runbook
  - §9.2 Credential Rotation Procedures
  - §9.3 Backup and Recovery (Time Machine, n8n export)
  - §9.4 Restore Testing
  - §9.5 Physical Security (Find My Mac, USB/Thunderbolt)

## 10. Operational Maintenance
  - §10.1 Automated Audit Scheduling (launchd)
  - §10.2 Notification Setup (email, macOS notifications, webhook)
  - §10.3 Tool Maintenance (ClamAV, brew, n8n updates)
  - §10.4 Log Retention and Rotation
  - §10.5 Troubleshooting Common Failures

## 11. Audit Script Reference
  - §11.1 Running the Audit Script
  - §11.2 Check Reference Table
  - §11.3 JSON Output Schema
  - §11.4 Interpreting Results

## Appendices
  - A. Complete Security Environment Variable Reference
  - B. Credential Inventory Template
  - C. Incident Response Checklist
  - D. Tool Comparison Matrix (free vs paid)
  - E. PII Data Classification Table
```

## Section Format

Every control section follows this structure (per Constitution Article V
and CIS Benchmark pattern):

```markdown
### §X.Y Control Name

**Threat**: [What attack this prevents — name the adversary and technique]
**Layer**: Prevent | Detect | Respond
**Deployment**: Both | Containerized only | Bare-metal only
**Source**: [Canonical citation]

#### Why This Matters

[1-3 sentences explaining the attack in plain language for non-specialists]

#### How to Harden

[Copy-pasteable terminal commands or System Settings navigation path]

##### Containerized Path
[Commands specific to Docker/Colima deployment]

##### Bare-Metal Path
[Commands specific to bare-metal deployment]

#### Verification

~~~bash
# Command to verify this control is active
command_here
# Expected output: [what PASS looks like]
~~~

#### Edge Cases and Warnings

[Lockout risks, common mistakes, recovery procedures]

**Audit check**: `CHK-CONTROL-NAME` (FAIL|WARN) → script reference
```

## Constraints

- All code blocks must be copy-pasteable (no pseudocode)
- Every `[PAID]` tool mention must include cost and free alternative
- Section numbers are stable — do not renumber after initial publication
- Cross-references use `§X.Y` notation throughout
- The guide must pass markdownlint with MD013 disabled
