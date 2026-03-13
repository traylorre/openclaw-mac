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

## 4. Container Isolation (Prevent) — Containerized Path

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

## 5. n8n Platform Security (Prevent)

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

## 6. Bare-Metal Path (Prevent) — Bare-Metal Only

### 6.1 Dedicated Service Account

<!-- Content: T029 -->

### 6.2 Keychain Integration

<!-- Content: T029 -->

### 6.3 launchd Execution

<!-- Content: T029 -->

### 6.4 Filesystem Permissions

<!-- Content: T029 -->

---

## 7. Data Security (Prevent)

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
