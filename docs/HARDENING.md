# macOS Hardening Guide for n8n + Apify Deployment

<!-- markdownlint-disable MD013 -->

## Table of Contents

- [Preamble](#preamble)
- [1. Threat Model](#1-threat-model)
- [2. OS Foundation](#2-os-foundation)
- [3. Network Security](#3-network-security)
- [4. Container Isolation — Containerized Path](#4-container-isolation--containerized-path)
- [5. n8n Platform Security](#5-n8n-platform-security)
- [6. Bare-Metal Path — Bare-Metal Only](#6-bare-metal-path--bare-metal-only)
- [7. Data Security](#7-data-security)
- [8. Detection and Monitoring](#8-detection-and-monitoring)
- [9. Response and Recovery](#9-response-and-recovery)
- [10. Operational Maintenance](#10-operational-maintenance)
- [11. Audit Script Reference](#11-audit-script-reference)
- [Appendix A: Security Environment Variable Reference](#appendix-a-security-environment-variable-reference)
- [Appendix B: Credential Inventory Template](#appendix-b-credential-inventory-template)
- [Appendix C: Incident Response Checklist](#appendix-c-incident-response-checklist)
- [Appendix D: Tool Comparison Matrix](#appendix-d-tool-comparison-matrix)
- [Appendix E: PII Data Classification Table](#appendix-e-pii-data-classification-table)

---

## Preamble

### Purpose and Scope

This guide provides a comprehensive, CLI-first hardening procedure for a Mac Mini running **n8n** (workflow automation) and **Apify** (web scraping) in a LinkedIn lead-generation pipeline. It covers macOS Sonoma (14) and Tahoe (26) and is written for an operator who manages the system but is not a macOS security specialist.

The guide assumes:

- A dedicated Mac Mini (Apple Silicon or Intel) running n8n and Apify actors
- The system processes LinkedIn profile data, which may include PII
- The operator has administrator access and a working internet connection
- All instructions are CLI-only — no GUI-only steps

### How to Use This Guide

1. Read §1 (Threat Model) to understand what you are protecting and from whom.
2. Choose your deployment path using the decision tree below.
3. Follow the Quick-Start Checklist to prioritize your hardening actions.
4. Work through each section relevant to your deployment path.
5. Schedule the audit script (`scripts/hardening-audit.sh`) to run regularly (§10).

### Deployment Path Decision Tree

Choose **one** deployment path. Both paths produce equivalent security posture; they differ in isolation strategy.

```text
Do you need workflow-level process isolation?
├── YES → Containerized Path (§4 + §5)
│         Uses Colima + Docker to run n8n in a container.
│         Better blast-radius containment.
│         Requires: Docker CLI, Colima, ~4 GB RAM overhead.
│
└── NO  → Bare-Metal Path (§6 + §5)
          Runs n8n natively via launchd.
          Simpler setup, fewer moving parts.
          Requires: dedicated macOS service account.
```

Sections §2, §3, §7, §8, §9, §10, and §11 apply to **both** paths. Sections marked "Containerized Path" or "Bare-Metal Only" apply only to their respective path.

### Notation Conventions

| Notation | Meaning |
|----------|---------|
| `§X.Y` | Cross-reference to section X.Y of this guide |
| `CHK-*` | Audit check identifier (see §11.2 and `scripts/CHK-REGISTRY.md`) |
| `[PAID]` | Paid tool — cost and free alternative noted inline |
| **Prevent** / **Detect** / **Respond** | Defensive layer labels per defense-in-depth |
| `[Containerized]` / `[Bare-Metal]` | Deployment-path-specific instruction |

### Quick-Start Checklist

Complete these actions in the order shown. Each item links to the relevant guide section.

> **WARNING — Lockout Prevention**: Several immediate actions have ordering dependencies. Read the warnings below each constraint before proceeding.

#### Tier 1: Immediate (do first)

These controls close critical attack vectors with minimal effort and no tool installation.

1. [ ] Enable FileVault disk encryption (§2.1)
   - > **WARNING**: On a headless server, configure `fdesetup authrestart` BEFORE enabling FileVault — otherwise the server cannot reboot unattended.
2. [ ] Enable application firewall + stealth mode (§2.2)
3. [ ] Verify SIP is enabled (§2.3)
4. [ ] Verify Gatekeeper is enabled (§2.4)
5. [ ] Enable automatic software updates (§2.5)
6. [ ] Enable screen lock and set login window security (§2.6)
7. [ ] Disable guest account (§2.7)
8. [ ] Disable automatic login (§2.6)
9. [ ] Disable sharing services — Screen Sharing, File Sharing, Remote Login, Remote Management, AirDrop, Handoff (§2.7)
   - > **WARNING**: On a headless server, verify SSH or Screen Sharing is working BEFORE disabling other remote access methods.
10. [ ] Change SSH defaults — key-only auth, disable root login, `AllowUsers`, ed25519 keys (§3.1)
    - > **WARNING**: Install and test your SSH key BEFORE disabling password authentication — otherwise you are locked out of a headless server.
11. [ ] Disable or restrict n8n REST API access — set `N8N_PUBLIC_API_DISABLED=true` (§5.4)
12. [ ] Configure n8n webhook authentication (§5.5)
    - > **WARNING**: Enable n8n authentication BEFORE binding n8n to a network interface if remote access is needed.
13. [ ] Enable NTP time synchronization integrity (§2.5)
14. [ ] Disable core dumps (§2.10)
15. [ ] Disable unnecessary iCloud services (§8.6)
16. [ ] Physical security basics — recovery mode password, secure location (§9.5)

#### Tier 2: Follow-up (do next)

These controls require tool installation or more complex configuration.

17. [ ] Install antivirus/EDR — Santa (`northpolesec/santa`) or ClamAV (§8.1)
18. [ ] Set up IDS — osquery, Santa file monitoring (§8.1)
19. [ ] Configure outbound filtering — LuLu (free) or Little Snitch `[PAID]` ~$59 (§3.3)
    - Containerized: iptables inside Colima VM, not macOS pf (§3.3)
20. [ ] Deploy n8n in a container via Colima + Docker `[Containerized]` (§4)
21. [ ] Set up credential management — macOS Keychain or Bitwarden (§7.1)
22. [ ] Configure DNS security — DoH/DoT via Quad9 (§3.2)
23. [ ] Harden Bluetooth — keep on for keyboard/mouse, disable discoverability (§3.4)
24. [ ] Restrict USB/Thunderbolt (§9.5)
25. [ ] Audit all persistence mechanisms — LaunchAgents, LaunchDaemons, login items (§8.2)
26. [ ] Configure IPv6 — disable or dual-stack pf rules (§3.5)
27. [ ] Set up macOS logging and configure log review (§8.4)
28. [ ] Configure Time Machine or other backup (§9.3)
29. [ ] Implement PII data controls for scraped LinkedIn data (§7.4)
30. [ ] Audit n8n workflows for injection vulnerabilities — Execute Command nodes, Code nodes processing scraped data, LLM nodes without input validation (§5.6)
31. [ ] Pin Docker images by digest and verify Homebrew package integrity (§7.7)
32. [ ] Establish credential rotation schedule (§7.2)
33. [ ] Create listening service baseline via `lsof -iTCP -sTCP:LISTEN` (§3.6)
34. [ ] Run hardening validation tests (§10.6)
35. [ ] Harden Screen Sharing/VNC if enabled (§2.7)
36. [ ] Configure DNS query logging and covert channel defense (§3.2)
37. [ ] Harden temp file and cache security (§2.10)
38. [ ] Create certificate trust store baseline (§8.7)
39. [ ] Audit and remove unauthorized configuration profiles (§2.10)
40. [ ] Configure Spotlight exclusions for n8n data directories (§2.10)
41. [ ] Deploy canary files and honey credentials (§8.5)
42. [ ] Scan Docker images for vulnerabilities `[Containerized]` (§4.4)
43. [ ] Migrate secrets from environment variables to Docker secrets `[Containerized]` (§7.1)
44. [ ] Set up dedicated service account `[Bare-Metal]` (§6.1)
45. [ ] Configure launchd execution `[Bare-Metal]` (§6.3)
46. [ ] Set filesystem permissions `[Bare-Metal]` (§6.4)

#### Tier 3: Ongoing (maintain)

These controls require periodic action.

47. [ ] Re-run audit script (`scripts/hardening-audit.sh`) — weekly recommended (§11.1)
48. [ ] Update security tool signatures (Santa rules, ClamAV defs) (§10.3)
49. [ ] Review macOS and n8n logs (§8.4)
50. [ ] Run post-update checklist after macOS updates (§5.9)
51. [ ] Rotate credentials per lifecycle policy (§7.2)
52. [ ] Re-audit persistence mechanisms after software changes (§8.2)
53. [ ] Review n8n execution logs for injection indicators — unexpected commands, anomalous outbound connections, LLM behavior changes (§5.6)
54. [ ] Re-audit workflows after adding or modifying nodes that process scraped data (§5.6)
55. [ ] Verify monitoring infrastructure is intact — launchd job, notification config, log directory (§10.1)
56. [ ] Verify Docker image digests against known-good values after pulls `[Containerized]` (§7.7)
57. [ ] Review webhook access logs for abuse patterns (§5.5)
58. [ ] Verify listening service inventory against baseline (§3.6)
59. [ ] Annual emergency credential rotation practice run (§7.2)
60. [ ] Review DNS query logs for anomalous exfiltration patterns (§3.2)
61. [ ] Verify audit log integrity via hash chain (§8.4)
62. [ ] Verify certificate trust store against baseline (§8.7)
63. [ ] Clipboard hygiene during credential management operations (§7.10)
64. [ ] Verify canary file integrity (§8.5)
65. [ ] Rescan Docker images for newly discovered CVEs `[Containerized]` (§4.4)

---

## 1. Threat Model

### Platform Description

This guide secures a **Mac Mini** (Apple Silicon or Intel) running:

- **n8n**: Open-source workflow automation platform handling LinkedIn lead-generation pipelines
- **Apify**: Web scraping platform whose actors collect LinkedIn profile data and feed it into n8n workflows
- **LinkedIn lead generation**: The combined workload scrapes public LinkedIn profiles, enriches data, and stores it for outreach campaigns

The system operates as an always-on, headless (or semi-headless) server on a home or office network.

### Assets to Protect

| Asset | Impact if Compromised |
|-------|----------------------|
| **LinkedIn session cookies and API tokens** | Account ban, legal liability, loss of scraping capability |
| **n8n encryption key** | All stored credentials decryptable — full lateral movement |
| **Apify API tokens** | Unauthorized actor execution, data exfiltration, billing abuse |
| **Scraped PII** (names, emails, job titles, profile URLs) | GDPR/CCPA breach notification obligations, reputational damage |
| **macOS Keychain contents** | Cross-service credential theft |
| **Workflow definitions** | Business logic exposure, injection of malicious nodes |
| **System integrity** (SIP, Gatekeeper, FileVault) | Persistent rootkit, undetectable surveillance |
| **Network position** | Pivot point into home/office LAN, SSRF to internal services |
| **Backup data** (Time Machine, exports) | Offline extraction of all of the above |

### Adversary Profiles

| Adversary | Motivation | Capability | Likely Attack Vector |
|-----------|-----------|------------|---------------------|
| **Opportunistic attacker** | Cryptocurrency mining, botnet recruitment | Automated scanning, known CVE exploitation | Exposed n8n instance, default credentials, unpatched macOS |
| **Credential harvester** | Resale of API tokens and session cookies | Phishing, supply chain compromise, public repo scanning | n8n webhook endpoints, leaked `.env` files, clipboard sniffing |
| **Competitor / scraping rival** | Disrupt lead-gen capability, steal pipeline logic | Targeted reconnaissance, social engineering | Workflow exfiltration, Apify actor tampering |
| **LinkedIn platform enforcement** | Terms of Service enforcement | IP blocking, account suspension, legal action | Detection of scraping patterns, session anomalies |
| **Nation-state (advanced)** | Espionage, PII harvesting | Zero-day exploits, supply chain attacks, physical access | SIP bypass, firmware implants, network interception |

### Attack Surface Map

```text
Internet
  │
  ├── n8n webhook endpoints (inbound HTTP)
  ├── Apify API calls (outbound HTTPS)
  ├── LinkedIn scraping traffic (outbound HTTPS)
  ├── DNS queries (potential exfiltration channel)
  ├── Software update channels (supply chain)
  │
  ├── Local Network
  │     ├── SSH (if enabled)
  │     ├── Screen Sharing / VNC (if enabled)
  │     ├── AirDrop / Handoff / Bonjour
  │     ├── Shared folders (SMB/AFP)
  │     └── mDNS service discovery
  │
  └── Physical
        ├── USB / Thunderbolt ports
        ├── Recovery Mode (firmware password)
        └── Disk access (FileVault protection)

Internal
  ├── n8n REST API (if bound to 0.0.0.0)
  ├── n8n execution engine (Code nodes, Execute Command)
  ├── Docker socket (if containerized)
  ├── LaunchAgents / LaunchDaemons (persistence)
  ├── macOS Keychain
  ├── TCC database (privacy permissions)
  ├── Swap / core dumps (memory artifacts)
  └── iCloud sync (credential/document leakage)
```

### Scope Exclusions

This guide does **not** cover:

- **Cloud-hosted n8n deployments** (AWS, GCP, Azure) — different threat model entirely
- **iOS/iPadOS devices** connected to the same Apple ID
- **Mail server hardening** — out of scope unless n8n sends email
- **Web application penetration testing** of n8n itself — n8n is treated as a trusted platform; we harden its configuration, not its code
- **Hardware supply chain verification** — we assume the Mac Mini hardware is genuine
- **Compliance framework certification** (SOC 2, ISO 27001) — this guide informs but does not certify

---

## 2. OS Foundation

### 2.1 Disk Encryption (FileVault)

<!-- Content: T009 -->

### 2.2 Firewall

<!-- Content: T009 -->

### 2.3 System Integrity Protection (SIP)

<!-- Content: T009 -->

### 2.4 Gatekeeper and XProtect

<!-- Content: T009 -->

### 2.5 Software Updates

<!-- Content: T009 -->

### 2.6 Screen Lock and Login Security

<!-- Content: T009 -->

### 2.7 Guest Account and Sharing Services

<!-- Content: T009 -->

### 2.8 Lockdown Mode

<!-- Content: T009 -->

### 2.9 Recovery Mode Password

<!-- Content: T009 -->

### 2.10 System Privacy and TCC

<!-- Content: T009 -->

---

## 3. Network Security

### 3.1 SSH Hardening

<!-- Content: T014 -->

### 3.2 DNS Security

<!-- Content: T014 -->

### 3.3 Outbound Filtering

<!-- Content: T014 -->

### 3.4 Bluetooth

<!-- Content: T014 -->

### 3.5 IPv6

<!-- Content: T014 -->

### 3.6 Service Binding and Port Exposure

<!-- Content: T014 -->

---

## 4. Container Isolation — Containerized Path

### 4.1 Colima Setup

<!-- Content: T019 -->

### 4.2 Docker Security Principles

<!-- Content: T019 -->

### 4.3 Reference docker-compose.yml

<!-- Content: T019 -->

### 4.4 Advanced Container Hardening

<!-- Content: T019 -->

### 4.5 Container Networking

<!-- Content: T019 -->

---

## 5. n8n Platform Security

### 5.1 Binding and Authentication

<!-- Content: T024 -->

### 5.2 User Management

<!-- Content: T024 -->

### 5.3 Security Environment Variables

<!-- Content: T024 -->

### 5.4 REST API Security

<!-- Content: T024 -->

### 5.5 Webhook Security

<!-- Content: T024 -->

### 5.6 Execution Model and Node Isolation

<!-- Content: T024 -->

### 5.7 Community Node Vetting

<!-- Content: T024 -->

### 5.8 Reverse Proxy

<!-- Content: T024 -->

### 5.9 Update and Migration Security

<!-- Content: T024 -->

---

## 6. Bare-Metal Path — Bare-Metal Only

### 6.1 Dedicated Service Account

<!-- Content: T029 -->

### 6.2 Keychain Integration

<!-- Content: T029 -->

### 6.3 launchd Execution

<!-- Content: T029 -->

### 6.4 Filesystem Permissions

<!-- Content: T029 -->

---

## 7. Data Security

### 7.1 Credential Management

<!-- Content: T034 -->

### 7.2 Credential Lifecycle

<!-- Content: T034 -->

### 7.3 Scraped Data Input Security

<!-- Content: T034 -->

### 7.4 PII Protection

<!-- Content: T034 -->

### 7.5 SSRF Defense

<!-- Content: T034 -->

### 7.6 Data Exfiltration Prevention

<!-- Content: T034 -->

### 7.7 Supply Chain Integrity

<!-- Content: T034 -->

### 7.8 Apify Actor Security

<!-- Content: T034 -->

### 7.9 Secure Deletion

<!-- Content: T034 -->

### 7.10 Clipboard Security

<!-- Content: T034 -->

---

## 8. Detection and Monitoring

### 8.1 IDS Tools

<!-- Content: T039 -->

### 8.2 Launch Daemon and Persistence Auditing

<!-- Content: T039 -->

### 8.3 Workflow Integrity Monitoring

<!-- Content: T039 -->

### 8.4 macOS Logging

<!-- Content: T039 -->

### 8.5 Credential Exposure Monitoring

<!-- Content: T039 -->

### 8.6 iCloud and Cloud Service Exposure

<!-- Content: T039 -->

### 8.7 Certificate Trust Monitoring

<!-- Content: T039 -->

---

## 9. Response and Recovery

### 9.1 Incident Response Runbook

<!-- Content: T044 -->

### 9.2 Credential Rotation Procedures

<!-- Content: T044 -->

### 9.3 Backup and Recovery

<!-- Content: T044 -->

### 9.4 Restore Testing

<!-- Content: T044 -->

### 9.5 Physical Security

<!-- Content: T044 -->

---

## 10. Operational Maintenance

### 10.1 Automated Audit Scheduling

<!-- Content: T049 -->

### 10.2 Notification Setup

<!-- Content: T049 -->

### 10.3 Tool Maintenance

<!-- Content: T049 -->

### 10.4 Log Retention and Rotation

<!-- Content: T049 -->

### 10.5 Troubleshooting Common Failures

<!-- Content: T049 -->

### 10.6 Hardening Validation Tests

<!-- Content: T049 -->

---

## 11. Audit Script Reference

### 11.1 Running the Audit Script

<!-- Content: T054 -->

### 11.2 Check Reference Table

<!-- Content: T054 -->

### 11.3 JSON Output Schema

<!-- Content: T054 -->

### 11.4 Interpreting Results

<!-- Content: T054 -->

---

## Appendix A: Security Environment Variable Reference

<!-- Content: T059 -->

## Appendix B: Credential Inventory Template

<!-- Content: T060 -->

## Appendix C: Incident Response Checklist

<!-- Content: T061 -->

## Appendix D: Tool Comparison Matrix

<!-- Content: T062 -->

## Appendix E: PII Data Classification Table

<!-- Content: T063 -->
