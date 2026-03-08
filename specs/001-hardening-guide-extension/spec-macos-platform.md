# Spec Module: macOS Platform, Container & Network Security

**Parent spec**: [spec.md](spec.md) (Rev 29)
**Module scope**: macOS OS-level hardening, container infrastructure (Colima/Docker), and network controls.

## Functional Requirements

- **FR-016**: The guide MUST include a container isolation section
  explaining why containerization reduces blast radius for this
  deployment, covering: running n8n as a non-root container user,
  read-only container filesystem where possible, no privileged mode,
  explicit port mapping (localhost only), credential injection via
  Docker secrets (not environment variables), named volumes for
  persistent data, and resource limits. All container setup MUST use
  CLI commands only (`colima`, `docker`, `docker compose`) per
  Constitution Article X. FR-016 establishes the security principles;
  FR-041 specifies advanced hardening (Docker socket prohibition,
  capabilities, seccomp); FR-058 provides the reference
  docker-compose.yml that implements all three FRs as a single
  deployable configuration.
  *Source: CIS Docker Benchmark v1.6 (Section 4: Container Images and Build Files, Section 5: Container Runtime); Docker security best practices documentation; NIST SP 800-190 (Application Container Security Guide).*

- **FR-017**: The guide MUST use Colima as the primary container
  runtime. Colima is free, open source, CLI-only, and runs a
  lightweight Linux VM that exposes the standard Docker socket —
  meaning all `docker` and `docker compose` commands work seamlessly.
  The guide MUST include a note that Docker Desktop is an alternative
  that also provides a VM with the same Docker CLI compatibility, but
  that it adds a GUI layer and has licensing restrictions (free for
  personal use and businesses <250 employees / <$10M revenue).
  *Source: Colima GitHub repository (github.com/abiosoft/colima); Docker Subscription Service Agreement.*

- **FR-028**: The guide MUST include an SSH hardening section covering
  the specific risks of SSH on a headless automation server and the
  controls to mitigate them:
  - Disable password authentication and require key-only access
    (prevents brute force attacks from the LAN)
  - Disable root login via SSH
  - Restrict SSH access to specific user accounts via `AllowUsers`
  - Configure idle session timeout (`ClientAliveInterval`,
    `ClientAliveCountMax`) to prevent abandoned sessions
  - Document modern key generation (`ssh-keygen -t ed25519`)
  - If SSH is not needed for remote management, document how to
    disable the SSH daemon entirely and the implications for
    headless operation (physical access becomes the only management
    path)
  - For containerized deployments: SSH MUST NOT be enabled inside the
    container; management is via `docker exec` from the host only
  - Verification: audit script checks SSH daemon configuration
    against each of these settings when sshd is running, and
    reports PASS if sshd is disabled entirely
  *Source: CIS Apple macOS Benchmarks (SSH configuration); NIST SP
  800-123 Section 4.2 (Remote Access); drduh/macOS-Security-and-
  Privacy-Guide (SSH hardening).*

- **FR-029**: The guide MUST include a DNS security section covering:
  - Why DNS security matters for this deployment: without encrypted
    DNS, any device on the LAN can observe DNS queries revealing
    what services the Mac Mini communicates with (LinkedIn, Apify,
    email relay); malicious DNS responses can redirect traffic to
    attacker-controlled endpoints
  - Configuring encrypted DNS (DNS-over-HTTPS or DNS-over-TLS) via
    macOS system settings (supported natively since macOS Monterey)
    or via a configuration profile
  - Selecting a DNS provider: Quad9 (free, malware-blocking) as the
    primary recommendation, Cloudflare 1.1.1.1 (free, privacy-
    focused) as alternative, with explicit tradeoff between malware
    filtering (Quad9) and speed/privacy (Cloudflare)
  - For containerized deployments: container DNS resolution uses the
    host's resolver by default; document how to explicitly set DNS
    in `docker-compose.yml` if the operator wants container-specific
    DNS settings
  - Verification: audit script checks that the configured DNS
    resolver supports encryption (DoH/DoT)
  *Source: NIST SP 800-81 Rev 2 (Secure Domain Name System
  Deployment Guide); CIS Apple macOS Benchmarks (DNS configuration);
  Apple Platform Security Guide (encrypted DNS).*

- **FR-030**: The guide MUST include an outbound filtering section
  covering:
  - Why outbound filtering is critical for this deployment: if n8n is
    compromised via injection (FR-021), the attacker will attempt
    data exfiltration and command-and-control communication via
    outbound connections. The macOS application firewall only blocks
    inbound traffic — it provides zero protection against outbound
    data theft
  - Free option: macOS pf (packet filter) for outbound allowlisting
    — configure rules that allow outbound connections only to known
    required destinations (LinkedIn API endpoints, Apify API, SMTP
    relay, DNS resolver, Homebrew update servers) and block all
    other outbound traffic. The guide MUST include a starter pf
    ruleset and instructions for loading it via pfctl
  - Free option: LuLu (Objective-See, free, open source) for per-
    application outbound firewall with interactive allow/deny
    prompts. Recommended for operators who prefer interactive
    outbound control over static pf rules
  - Paid option: Little Snitch `[PAID ~$59 one-time]` for advanced
    per-application outbound filtering with network monitor
    visualization. The guide MUST state what Little Snitch adds over
    LuLu/pf (network visualization, per-connection rules, automatic
    profile switching) and when the paid tool is justified
  - For containerized deployments: Docker network isolation provides
    a baseline — containers can only reach mapped ports and the
    default Docker bridge network. Document how to further restrict
    container outbound via Docker network options or pf rules on the
    host
  - Verification: audit script checks that either pf outbound rules
    are loaded, LuLu is running, or Little Snitch is installed
  *Source: CIS Apple macOS Benchmarks; NIST SP 800-41 Rev 1
  (Guidelines on Firewalls and Firewall Policy); MITRE ATT&CK
  T1041 (Exfiltration Over C2 Channel).*

- **FR-032**: The guide MUST include an intrusion detection section
  covering tools and techniques for detecting unauthorized activity:
  - **Binary authorization**: Google Santa (free, open source) for
    allowlisting/blocklisting binary execution. Santa prevents
    unauthorized binaries from running, providing a strong prevention
    layer against malware and unauthorized tools. The guide MUST
    explain monitor mode (log-only) vs lockdown mode (block
    unauthorized) and recommend starting in monitor mode
  - **Persistence monitoring**: BlockBlock (free, Objective-See)
    detects when software installs a persistent component (launch
    daemon, login item, kernel extension). The guide MUST explain
    that persistence is the key indicator of compromise — most
    malware and attacker tools install persistence to survive reboot
  - **Network monitoring**: LuLu (free, Objective-See) monitors
    outbound connections and alerts on new or unauthorized network
    activity. Cross-references FR-030 (outbound filtering) — LuLu
    serves double duty as both outbound filter and network IDS
  - **Persistence enumeration**: KnockKnock (free, Objective-See)
    scans for all persistent programs on the system. The guide MUST
    recommend running KnockKnock after initial hardening to establish
    a baseline, and periodically to detect changes
  - How these tools complement each other: Santa controls what runs,
    BlockBlock detects persistence attempts in real-time, LuLu
    monitors network connections, KnockKnock provides periodic
    persistence audits
  - For containerized deployments: host-level IDS is still critical
    because the host is the trust boundary — a container breakout
    would be detected by host-level IDS tools
  - Verification: audit script checks that at least one IDS tool
    (Santa or BlockBlock) is installed and running
  *Source: Google Santa documentation; Objective-See tool
  documentation; CIS Apple macOS Benchmarks (malware defenses);
  MITRE ATT&CK T1543 (Create or Modify System Process).*

- **FR-033**: The guide MUST include a launch daemon/agent auditing
  section covering:
  - Why this matters: launch daemons and agents are the primary macOS
    persistence mechanism. A compromised n8n (especially on bare-
    metal) or an attacker with shell access will install a launch
    agent to survive reboot. This is the most common macOS post-
    exploitation technique
  - What to audit: the four standard directories —
    `/Library/LaunchDaemons/`, `/Library/LaunchAgents/`,
    `~/Library/LaunchAgents/`, and `/System/Library/LaunchDaemons/`
    (read-only on SIP-protected systems, but should be verified)
  - Baseline creation: after initial hardening, enumerate all
    daemons/agents and save the list as a known-good baseline file.
    The guide MUST provide a command to generate this baseline
  - Drift detection: the audit script MUST compare the current state
    of launch daemons/agents against the baseline and flag any
    additions, modifications, or deletions as WARN (new entries
    could be legitimate software installations or malicious
    persistence)
  - Re-audit triggers: after installing any new software via
    Homebrew, after macOS updates, and on a monthly schedule
  - Integration with KnockKnock (FR-032): KnockKnock provides a
    GUI-based persistence scan that complements the script-based
    baseline comparison
  - Verification: audit script compares current launch daemons
    against baseline, flags unknown entries
  *Source: CIS Apple macOS Benchmarks (launch daemon controls);
  MITRE ATT&CK T1543.004 (Launch Daemon), T1543.001 (Launch Agent);
  Objective-See documentation.*

- **FR-034**: The guide MUST include a USB/Thunderbolt restriction
  section covering:
  - Why this matters for a headless server: USB devices can be attack
    vectors — BadUSB devices masquerade as keyboards to inject
    commands, USB mass storage can introduce malware, and
    Thunderbolt has historically enabled DMA attacks
  - macOS accessory security (Sonoma+): the "Allow accessories to
    connect" setting restricts new USB/Thunderbolt devices from
    connecting while the screen is locked. The guide MUST recommend
    setting this to "Ask for new accessories" or "Never" for
    headless servers
  - Apple Silicon mitigations: Apple Silicon Macs include IOMMU
    protection that blocks classic Thunderbolt DMA attacks. The
    guide MUST note this but explain that USB HID and mass storage
    attacks are still relevant regardless of architecture
  - Physical access implications: for a headless server, once
    initial setup is complete (keyboard/mouse configured if needed),
    USB ports should accept minimal new devices. The guide MUST
    explain the tradeoff between convenience (plugging in a keyboard
    for maintenance) and security (restricting USB)
  - Verification: audit script checks the accessory security setting
    on supported macOS versions (WARN if not configured, SKIP on
    versions that don't support this setting)
  *Source: Apple Platform Security Guide (Accessory security); CIS
  Apple macOS Benchmarks; MITRE ATT&CK T1200 (Hardware Additions).*

- **FR-035**: The guide MUST expand the logging and alerting control
  area (control area #17) beyond the audit script to cover continuous
  macOS-level security event monitoring:
  - **Unified log queries**: macOS's unified log captures security-
    relevant events. The guide MUST provide specific log predicates
    (query strings) for: failed login attempts, sudo usage, firewall
    blocks, Gatekeeper blocks, XProtect malware detections, SSH
    authentication events, and TCC (Transparency, Consent, and
    Control) permission changes
  - **Log review cadence**: the guide MUST recommend a periodic log
    review schedule (weekly for high-security, monthly for standard)
    and provide a script or command sequence that extracts security
    events from the unified log for the review period
  - **n8n execution logs**: where they are stored for each deployment
    path (bare-metal file path vs Docker container logs), how to
    search for anomalous execution patterns, and retention
    configuration. Cross-references FR-021 (injection detection
    logging)
  - **Log forwarding (optional)**: for operators who want centralized
    logging, document how to forward macOS unified logs to an
    external syslog server using the built-in syslogd configuration
    (free, no additional tools)
  - This complements the audit script (which checks point-in-time
    configuration) with continuous event monitoring
  *Source: Apple Developer Documentation (Unified Logging); CIS
  Apple macOS Benchmarks (logging configuration); NIST SP 800-92
  (Guide to Computer Security Log Management).*

- **FR-036**: For the bare-metal deployment path, the guide MUST
  include detailed instructions for setting up a dedicated service
  account that limits the blast radius of a compromised n8n:
  - Creating a dedicated macOS user account (e.g., `_n8n`) for
    running n8n — NOT the operator's admin account
  - Configuring the account with no login shell or a restricted
    shell so it cannot be used for interactive login
  - Setting filesystem permissions so the service account can only
    access the n8n data directory and required configuration files —
    no access to the operator's home directory, Desktop, Documents,
    or SSH keys
  - Preventing the service account from accessing the macOS Keychain
    (or creating a separate Keychain with only n8n-required
    credentials)
  - Running n8n as the service account via launchd (not as a login
    item under the admin user)
  - Restricting the service account's group memberships — no admin
    group, no staff group if possible
  - Why this matters: on bare-metal without a service account, a
    compromised n8n process runs as the operator's admin user with
    full access to everything. A dedicated service account limits
    the compromise to the n8n data directory only. This is the
    bare-metal equivalent of container isolation
  *Source: NIST SP 800-123 Section 4.1 (Least Privilege); CIS Apple
  macOS Benchmarks (user account controls); principle of least
  privilege.*

- **FR-041**: The guide MUST expand the container isolation section
  (FR-016) with advanced container security hardening that addresses
  container escape and privilege escalation risks:
  - **Docker socket prohibition**: the guide MUST explicitly state
    that the Docker socket (`/var/run/docker.sock`) MUST NEVER be
    mounted into the n8n container. Mounting the Docker socket gives
    the container full root access to the host — it can create
    privileged containers, mount the host filesystem, and escape
    isolation entirely. This is the single most common Docker
    misconfiguration and completely negates container isolation
    (MITRE ATT&CK T1611 Escape to Host)
  - **Linux capabilities dropping**: the guide MUST recommend running
    the n8n container with `--cap-drop=ALL` and adding back only
    required capabilities (if any). n8n typically needs no special
    Linux capabilities. Dropping capabilities prevents privilege
    escalation inside the container
  - **seccomp profile**: the guide MUST recommend using Docker's
    default seccomp profile (which blocks ~44 dangerous syscalls) and
    MUST NOT recommend running with `--security-opt seccomp=unconfined`
  - **No new privileges flag**: the guide MUST recommend
    `--security-opt=no-new-privileges:true` to prevent privilege
    escalation via setuid binaries inside the container
  - **Container image minimization**: recommend using the smallest
    possible base image (Alpine-based n8n images if available) to
    reduce the attack surface inside the container — fewer binaries
    means fewer tools available to an attacker who achieves container
    code execution
  - **Container escape CVE awareness**: the guide MUST note that
    container escapes via kernel CVEs are a known risk (cite recent
    examples) and that keeping Colima's underlying VM and Docker
    engine updated is critical. The Colima VM provides an additional
    isolation layer (the container runs inside a Linux VM, not
    directly on macOS), which provides defense in depth against
    container escape
  - **Read-only root filesystem**: reinforce FR-016 — use
    `--read-only` with explicit tmpfs mounts for directories that
    need write access. This prevents an attacker from modifying
    container binaries or installing tools
  - Verification: audit script checks for Docker socket mounts
    (FAIL), privileged mode (FAIL), cap-drop configuration (WARN),
    no-new-privileges flag (WARN), and read-only filesystem (WARN)
  *Source: CIS Docker Benchmark v1.6 (Section 5: Container Runtime);
  NIST SP 800-190 (Application Container Security Guide); MITRE
  ATT&CK T1611 (Escape to Host), T1610 (Deploy Container).*

- **FR-042**: The guide MUST include a network segmentation and
  lateral movement defense section addressing the risk that the Mac
  Mini's LAN position makes it both a target for lateral movement
  from compromised LAN devices and a pivot point for lateral movement
  to other LAN devices if it is compromised:
  - **Inbound LAN threats**: the Mac Mini shares a network with other
    devices (phones, IoT, other computers) that may be compromised.
    A compromised device on the same LAN can:
    - ARP spoof to intercept Mac Mini traffic (MITRE ATT&CK T1557
      Adversary-in-the-Middle)
    - Scan for open ports and services (SSH, n8n, Docker API)
    - Attempt credential stuffing against SSH or n8n
    - Perform DNS spoofing if the LAN DNS resolver is compromised
  - **Outbound lateral movement**: if the Mac Mini is compromised, an
    attacker will pivot to other LAN devices. The guide MUST cover:
    - pf rules that restrict outbound connections to only required
      destinations (cross-reference FR-030)
    - Disabling mDNS/Bonjour responses where not needed (reduces
      discoverability on the LAN)
    - Disabling AirDrop and Handoff (reduces attack surface from
      LAN-adjacent Apple devices)
  - **Network segmentation recommendation**: the guide MUST recommend
    placing the Mac Mini on a dedicated VLAN or subnet separate from
    general-use devices, with firewall rules between segments. This
    is the single most effective control against lateral movement.
    The guide MUST acknowledge that not all home routers support
    VLANs and provide the pf-based controls above as a fallback
  - **Wi-Fi vs Ethernet**: the guide MUST recommend wired Ethernet
    over Wi-Fi for the Mac Mini. Wi-Fi adds attack surface
    (deauthentication attacks, evil twin APs, WPA key compromise)
    that is unnecessary for a headless server. If Wi-Fi is used,
    document how to disable it when Ethernet is connected
  - Verification: audit script checks for mDNS/Bonjour status (WARN
    if enabled), AirDrop status (WARN if enabled), and network
    interface configuration (informational — report which interfaces
    are active)
  *Source: CIS Apple macOS Benchmarks (network configuration); MITRE
  ATT&CK T1557 (Adversary-in-the-Middle), T1021 (Remote Services),
  T1018 (Remote System Discovery); NIST SP 800-123 Section 4
  (Securing the OS).*

- **FR-048**: The guide MUST include a Colima VM security section
  addressing the security of the VM that provides the container
  runtime isolation layer. Colima runs a lightweight Linux VM
  (Lima-based) that provides the Linux kernel required for Docker
  containers on macOS. The VM itself is a security boundary — the
  section MUST cover:
  - **VM SSH access**: Colima exposes an SSH port for VM management
    (`colima ssh`). The guide MUST document that this SSH access
    exists, is bound to localhost by default, and uses a key
    generated at VM creation. The guide MUST recommend verifying that
    the VM SSH port is not exposed to the network
  - **VM filesystem sharing**: Colima shares macOS filesystem paths
    with the VM by default (typically the user's home directory). The
    guide MUST recommend restricting mounts to only the directories
    needed for Docker volumes — not the entire home directory. A
    container escape + shared home directory = full host access
  - **VM resource limits**: the guide MUST recommend setting CPU and
    memory limits on the Colima VM (`colima start --cpu N --memory N`)
    to prevent a compromised container from consuming all host
    resources (denial of service)
  - **VM update cadence**: the Colima VM runs a Linux kernel and
    Docker engine that need separate updates from macOS. The guide
    MUST include Colima VM updates in the maintenance schedule
    (FR-020) and explain how to update the VM (`colima delete &&
    colima start` with updated config)
  - **VM disk encryption**: the Colima VM disk stores container data,
    including n8n data volumes. On macOS with FileVault enabled, the
    VM disk file is encrypted at rest as part of the host filesystem.
    The guide MUST confirm this and note that FileVault is the
    encryption mechanism for VM data at rest
  - Verification: audit script checks Colima VM status, mount
    configuration (WARN if home directory is fully shared), and
    resource limits (informational)
  *Source: Colima documentation (github.com/abiosoft/colima); Lima
  documentation (github.com/lima-vm/lima); CIS Docker Benchmark v1.6
  (Section 1: Host Configuration).*

- **FR-050**: The guide MUST address macOS TCC (Transparency, Consent,
  and Control) permissions as a security boundary for the n8n
  process. TCC controls access to sensitive macOS resources (camera,
  microphone, contacts, calendar, full disk access, screen recording,
  accessibility). The section MUST cover:
  - **Bare-metal TCC implications**: on bare-metal, the n8n process
    (and its Code/Execute Command nodes) inherits the TCC permissions
    of the user account running it. If n8n runs as the admin user
    with Full Disk Access, a compromised Code node can read any file
    on the system. The guide MUST recommend:
    - Running n8n as the dedicated service account (FR-036) which has
      NO TCC permissions granted
    - Never granting Full Disk Access to the n8n process or its
      parent terminal
    - Auditing TCC grants via `tccutil` or the TCC database to
      verify the n8n user has minimal permissions
  - **Containerized TCC implications**: Docker containers on macOS
    do not interact with TCC directly — the Colima VM provides
    isolation from macOS permission system. The guide MUST note this
    as an advantage of containerization
  - **TCC as persistence detection**: attackers may attempt to grant
    themselves TCC permissions (e.g., Full Disk Access, Accessibility)
    to expand access. The guide MUST recommend monitoring TCC
    database changes as an indicator of compromise. The unified log
    (FR-035) captures TCC permission changes — the guide MUST
    include a log predicate for TCC events
  - **TCC reset after incident**: during incident recovery (FR-031),
    the guide MUST recommend resetting TCC permissions for the n8n
    service account to revoke any attacker-granted permissions:
    `tccutil reset All <bundle-id-or-path>`
  - Verification: audit script checks TCC grants for the n8n user
    account (WARN if any sensitive permissions are granted beyond
    what is required)
  *Source: Apple Platform Security Guide (TCC); CIS Apple macOS
  Benchmarks (privacy controls); MITRE ATT&CK T1548 (Abuse Elevation
  Control Mechanism).*

- **FR-051**: The guide MUST address macOS Keychain security model
  limitations when used for n8n credential storage on the bare-metal
  deployment path. The Keychain is recommended in FR-012, but its
  security model has nuances that operators must understand:
  - **Keychain access control model**: by default, Keychain items in
    the login Keychain are accessible to the application that created
    them. However, any process running as the same user can prompt
    for Keychain access (the user sees a dialog), and on a headless
    server without a GUI session, Keychain prompts may behave
    differently or be suppressed. The guide MUST explain this
  - **Separate Keychain for n8n**: the guide MUST recommend creating
    a separate Keychain (not the login Keychain) for n8n credentials
    when running on bare-metal. This Keychain should:
    - Be created with a strong, unique password (not the user's login
      password)
    - Have ACLs restricting access to only the n8n binary path
    - Be locked when n8n is not running (auto-lock on timeout)
    - NOT auto-unlock on login (requires the operator to explicitly
      unlock it when starting n8n, or use a launchd pre-start script)
  - **Keychain vs environment variables**: for containerized
    deployments, Docker secrets are the recommended mechanism (not
    Keychain). The guide MUST NOT recommend mounting the macOS
    Keychain into a Docker container. For bare-metal, the guide MUST
    explain that Keychain is more secure than environment variables
    (which are visible via `/proc` or `ps`) but less secure than a
    dedicated secrets manager
  - **Keychain on headless servers**: when no GUI session is active,
    the login Keychain is not automatically unlocked. The guide MUST
    document how to handle Keychain access for a headless n8n
    process — either via `security unlock-keychain` in a launchd
    pre-start script or by using the system Keychain (which has
    different ACL behavior)
  - **Credential reuse warning**: the guide MUST explicitly warn
    against credential reuse — using the same password for the Mac
    Mini login, n8n web UI, email/SMTP, and any other service. Each
    credential MUST be unique. The guide MUST recommend a password
    manager (Bitwarden CLI, free) for generating and storing unique
    credentials. Credential reuse is the #1 enabler of lateral
    movement (MITRE ATT&CK T1078.001 Default Accounts)
  - Verification: audit script checks whether the n8n service
    account has a separate Keychain (WARN if using login Keychain)
    and whether Keychain auto-lock is configured (WARN if not)
  *Source: Apple Developer Documentation (Keychain Services); CIS
  Apple macOS Benchmarks (Keychain configuration); NIST SP 800-63B
  Section 5.1 (Authenticator Management); MITRE ATT&CK T1555.001
  (Credentials from Password Stores: Keychain).*

- **FR-052**: The guide MUST include a dedicated IPv6 hardening
  section. IPv6 is a critical blind spot because the macOS application
  firewall and many pf rulesets only filter IPv4 traffic by default.
  If IPv6 is enabled and only IPv4 firewall rules are configured, the
  entire firewall is bypassed for IPv6 traffic. The section MUST
  cover:
  - **Disable if not needed**: for most home/office LAN deployments,
    IPv6 is not required. The guide MUST provide the command to
    disable IPv6 on all active interfaces and explain why this is the
    safest default for a headless server
  - **Harden if needed**: if IPv6 must remain enabled (ISP requires
    it, specific services need it), the guide MUST cover:
    - Ensure the macOS application firewall covers IPv6 (it does on
      Sonoma+ but behavior differs by version)
    - Add pf rules for IPv6 traffic (pf supports IPv6 natively via
      `inet6` address family) — the guide MUST include IPv6 pf rules
      alongside any IPv4 rules
    - Disable IPv6 privacy extensions if not needed (they generate
      random temporary addresses that complicate logging and
      forensics)
    - Disable IPv6 router advertisement acceptance if the Mac Mini
      has a static IPv6 configuration (prevents rogue router
      advertisement attacks, MITRE ATT&CK T1557.002)
  - **Container implications**: Docker on Colima uses IPv4 by default
    for container networking. The guide MUST verify that IPv6 is not
    creating an unfiltered path into or out of containers
  - Verification: audit script checks whether IPv6 is disabled (PASS)
    or, if enabled, whether IPv6 firewall rules exist (WARN if no
    IPv6 pf rules alongside IPv4 rules)
  *Source: CIS Apple macOS Benchmarks (IPv6 configuration); NIST SP
  800-119 (Guidelines for the Secure Deployment of IPv6); MITRE
  ATT&CK T1557.002 (ARP Cache Poisoning — IPv6 variant via router
  advertisements).*

- **FR-053**: The guide MUST include a dedicated physical security
  section that goes beyond "basics" to address the specific risks of
  a headless Mac Mini in a home/office environment. Physical access
  bypasses most software security controls. The section MUST cover:
  - **Boot security**: on Apple Silicon, configure Startup Security
    Utility to "Full Security" (prevents booting from external media
    or unsigned kernels). On Intel, set a firmware password to prevent
    booting from external media (prevents target disk mode attacks and
    unauthorized OS reinstallation). The guide MUST provide commands
    or System Settings paths for both architectures
  - **Find My Mac**: enable Find My Mac to allow remote locking and
    wiping if the Mac Mini is stolen. The guide MUST note that Find
    My Mac requires an Apple ID and iCloud connection, and that
    Activation Lock prevents a thief from erasing and reusing the
    machine. The guide MUST also note the privacy tradeoff: Find My
    Mac sends location data to Apple
  - **Physical port security**: on a headless server, USB and
    Thunderbolt ports are attack vectors (cross-reference FR-034).
    The guide MUST recommend positioning the Mac Mini in a location
    where ports are not easily accessible to visitors or unauthorized
    personnel
  - **Cable lock**: Mac Mini supports Kensington security slots. The
    guide MUST recommend a cable lock for environments where physical
    theft is a risk (shared offices, accessible server locations)
  - **Location considerations**: the Mac Mini should be in a locked
    room, cabinet, or area not accessible to visitors. The guide MUST
    note that in a home office, "locked room" may not be feasible and
    suggest alternatives (locked drawer, hidden location, cable lock)
  - **What happens if stolen**: the guide MUST document the post-theft
    procedure:
    - Use Find My Mac to lock and wipe
    - FileVault protects data at rest — the thief cannot read the
      disk without the password
    - Immediately rotate ALL credentials (per FR-043 rotation
      procedures) — assume complete credential compromise because SSH
      keys, n8n encryption key, and other secrets were on the disk
    - Notify relevant parties per FR-013 if PII was on the device
  - Verification: audit script checks firmware password status (Intel)
    or Startup Security level (Apple Silicon) where programmatically
    checkable, and Find My Mac status (WARN if not enabled)
  *Source: Apple Platform Security Guide (Startup Security, Find My);
  CIS Apple macOS Benchmarks (physical security controls); MITRE
  ATT&CK T1200 (Hardware Additions), T1195.003 (Compromise Hardware
  Supply Chain).*

- **FR-058**: The guide MUST include a Docker Compose security
  configuration section. The `docker-compose.yml` file IS the security
  configuration for containerized deployments — a single
  misconfiguration undoes all container isolation. The guide MUST
  provide a reference `docker-compose.yml` with security annotations
  explaining every directive, and the section MUST cover:
  - **Port binding**: all port mappings MUST bind to `127.0.0.1`, not
    `0.0.0.0`. Example: `"127.0.0.1:5678:5678"` not `"5678:5678"`.
    Binding to `0.0.0.0` exposes n8n to the entire network and
    bypasses the localhost-binding protection. The guide MUST explain
    why Docker's default port mapping behavior (`0.0.0.0`) is
    dangerous
  - **Volume mounts**: only named volumes for persistent data (n8n
    data directory). NEVER mount the host's home directory, Docker
    socket, or any directory outside the n8n data path. Each volume
    mount MUST be annotated with why it exists
  - **Environment variables**: security-sensitive variables MUST NOT
    appear in plaintext in the compose file. Use Docker secrets or a
    `.env` file with restrictive permissions (600). The guide MUST
    list which variables are sensitive (N8N_ENCRYPTION_KEY, database
    credentials, SMTP credentials) and which are safe for the compose
    file (port settings, feature flags)
  - **Security options**: the compose file MUST include:
    - `security_opt: [no-new-privileges:true]`
    - `cap_drop: [ALL]`
    - `read_only: true` with explicit tmpfs mounts for write paths
    - `user: "1000:1000"` (non-root)
    - No `privileged: true`
    - No `network_mode: host`
  - **Resource limits**: the compose file MUST include memory and CPU
    limits (`deploy.resources.limits`) to prevent a compromised
    container from exhausting host resources
  - **Restart policy**: recommend `restart: unless-stopped` so n8n
    recovers from crashes but does not restart after intentional
    shutdown (containment)
  - **Compose file integrity**: the guide MUST recommend storing the
    compose file in version control and checking it for unauthorized
    modifications (similar to workflow baseline in FR-046)
  - Verification: audit script checks running container configuration
    for port bindings (FAIL if any port bound to 0.0.0.0), privileged
    mode (FAIL), Docker socket mount (FAIL), capability drops (WARN),
    read-only filesystem (WARN)
  *Source: CIS Docker Benchmark v1.6 (Section 5: Container Runtime);
  Docker Compose security documentation; NIST SP 800-190.*

- **FR-061**: The guide MUST include a macOS system-level privacy
  hardening section covering settings that reduce information leakage
  and attack surface beyond the individual control areas already
  specified. These settings are relevant because a headless automation
  server has no need for consumer-oriented features that transmit data
  to Apple or third parties:
  - **Spotlight network search**: disable Spotlight Suggestions and
    Siri Suggestions in search results — these send search queries to
    Apple's servers, leaking information about what the operator
    searches for on the machine
  - **Diagnostics and usage data**: disable sharing diagnostics data
    with Apple and app developers — this telemetry can reveal
    installed applications, crash patterns, and usage information
  - **Location Services**: disable Location Services unless required
    for Find My Mac (FR-053). If Find My Mac is enabled, restrict
    Location Services to only the Find My app
  - **Siri**: disable Siri entirely on a headless server — Siri has
    no function on a machine without a microphone or display, and
    Siri sends voice/text data to Apple
  - **Safari suggestions and preloading**: if Safari is present,
    disable preloading and suggestions (these make network requests
    to Apple)
  - **Advertising tracking**: limit ad tracking and reset advertising
    identifier — minimal impact on a server but reduces data leakage
  - **Analytics sharing with app developers**: disable to prevent
    installed applications from sending usage analytics
  - The guide MUST note that these settings are defense-in-depth
    privacy controls — disabling them reduces the information an
    attacker can gather about the system if they compromise Apple's
    analytics pipeline, and reduces unnecessary outbound connections
    that complicate outbound filtering (FR-030)
  - Verification: audit script checks Spotlight network suggestions
    (WARN if enabled), diagnostics sharing (WARN if enabled),
    Location Services status (informational)
  *Source: CIS Apple macOS Benchmarks (privacy settings); Apple
  Platform Security Guide; drduh/macOS-Security-and-Privacy-Guide.*

- **FR-062**: The guide MUST include a Lockdown Mode assessment
  section that evaluates macOS Lockdown Mode for this specific
  deployment. Lockdown Mode significantly reduces attack surface but
  also restricts functionality. The guide MUST NOT simply recommend
  enabling or disabling it — it MUST provide an informed analysis:
  - **What Lockdown Mode restricts**: blocks most message attachment
    types, disables complex web technologies (JIT JavaScript
    compilation), blocks incoming FaceTime calls from unknown
    contacts, restricts wired connections, blocks configuration
    profiles, restricts certain Apple services
  - **Impact on this deployment**:
    - n8n web UI: Lockdown Mode disables JIT JavaScript in Safari and
      WebKit. If the operator accesses the n8n UI from the Mac Mini
      itself (via Screen Sharing or local browser), the UI may break
      or perform extremely slowly. If accessed from a separate
      machine (recommended), Lockdown Mode on the server does not
      affect the client browser
    - SSH: Lockdown Mode does NOT disable SSH. Remote management via
      SSH continues to work
    - Docker/Colima: Lockdown Mode's impact on Colima and Docker is
      not well-documented. The guide MUST note this uncertainty and
      recommend testing before enabling
    - Homebrew: JIT restrictions may affect some Homebrew-installed
      tools
    - Network connections: Lockdown Mode blocks incoming connections
      from unknown devices — this may affect webhook ingress if n8n
      receives webhooks directly (mitigated by reverse proxy per
      FR-055)
  - **Recommendation**: the guide MUST recommend testing Lockdown
    Mode on a non-production instance before enabling it on the
    production Mac Mini. For operators who manage the Mac Mini
    exclusively via SSH from a separate machine, Lockdown Mode is
    likely compatible and provides significant additional protection
    against zero-day exploits
  - The guide MUST NOT mark Lockdown Mode as required — it is an
    optional, advanced hardening measure with known compatibility
    risks
  *Source: Apple Platform Security Guide (Lockdown Mode); Apple
  Support documentation on Lockdown Mode restrictions.*

- **FR-068**: The guide MUST include a memory, swap, and core dump
  security section addressing volatile data exposure. Secrets
  (N8N_ENCRYPTION_KEY, API keys, credentials, PII) exist in process
  memory while n8n is running and can persist in swap files,
  hibernation images, and core dumps after the process terminates or
  the system sleeps. The section MUST cover:
  - **Swap encryption**: macOS encrypts swap when FileVault is
    enabled. The guide MUST verify FileVault is active (FR-001 cross-
    ref) and explain that without FileVault, swap files in
    `/private/var/vm/` can be read by an attacker with physical disk
    access, exposing any secret that was paged out of RAM
  - **Hibernation image**: when a Mac sleeps in hibernation mode
    (standby), a full RAM image is written to
    `/private/var/vm/sleepimage`. This image contains all in-memory
    secrets. FileVault encrypts this file at rest. The guide MUST
    recommend setting `standbydelaylow` and `standbydelayhigh` values
    appropriate for a headless server (or disabling hibernation
    entirely via `sudo pmset -a hibernatemode 0` if the Mac Mini is on
    a UPS and sleep is not desired)
  - **Core dumps**: a crashing n8n process (bare-metal) can generate
    a core dump containing all process memory. The guide MUST
    recommend disabling core dumps for the n8n service account
    (`ulimit -c 0` in the launchd plist or shell profile) and
    verifying that `/cores/` does not contain unexpected dump files
  - **Container memory**: for containerized deployments, Docker
    containers respect the `--security-opt=no-new-privileges:true`
    and `ulimit` settings. The guide MUST recommend setting
    `ulimits: core: 0` in docker-compose.yml to prevent core dumps
    inside the container
  - **Secure memory deallocation**: macOS does not zero-fill freed
    memory by default. The guide MUST note this limitation and
    explain that container isolation + FileVault + disabled core
    dumps is the practical mitigation stack — there is no user-
    accessible control for memory scrubbing on macOS
  - Verification: audit script checks FileVault status (cross-ref),
    core dump settings (`ulimit -c`), hibernation mode, and presence
    of core dump files in `/cores/`
  *Source: Apple Platform Security Guide (FileVault, memory
  protection); CIS Apple macOS Benchmarks (core dump restrictions);
  MITRE ATT&CK T1003.007 (OS Credential Dumping: Proc Filesystem),
  T1005 (Data from Local System).*

- **FR-069**: The guide MUST include a Screen Sharing and Remote
  Management hardening section. Screen Sharing (VNC-based) is
  commonly enabled on headless Mac Minis for GUI management, but it
  exposes a significant attack surface. The section MUST cover:
  - **Disable if not needed**: for operators who manage the Mac Mini
    exclusively via SSH, Screen Sharing should be disabled entirely.
    The guide MUST provide the command to disable it
    (`sudo launchctl disable system/com.apple.screensharing`) and
    explain that SSH provides all management capabilities documented
    in this guide
  - **Harden if needed**: if Screen Sharing must remain enabled
    (operator needs GUI access for n8n web UI on the local machine
    or for macOS System Settings that lack CLI equivalents), the
    guide MUST cover:
    - Require macOS account authentication (not VNC password) —
      VNC passwords are limited to 8 characters and use weak
      encryption
    - Restrict access to specific users via the Screen Sharing
      preference pane or `kickstart` command
    - Ensure Screen Sharing is bound to the LAN interface only —
      verify it is not accessible from the internet
    - Enable "Show Screen Sharing status in menu bar" for awareness
    - Consider pairing with SSH tunneling: disable network access to
      Screen Sharing and access it only via an SSH tunnel
      (`ssh -L 5900:localhost:5900`), combining VNC convenience with
      SSH security
  - **Apple Remote Desktop (ARD) vs Screen Sharing**: ARD is the
    enterprise version of Screen Sharing with additional features
    (remote scripting, package deployment). If ARD is installed, the
    guide MUST cover the same hardening as Screen Sharing plus:
    disabling features not needed (remote scripting, package install),
    restricting admin privileges to specific accounts
  - **VNC protocol risks**: the guide MUST note that VNC (even with
    macOS auth) transmits display data without encryption by default.
    If Screen Sharing is used across an untrusted network, it MUST
    be tunneled through SSH or a VPN
  - Verification: audit script checks Screen Sharing status (WARN if
    enabled — informational, since it may be intentional), VNC
    password type (FAIL if legacy VNC password is used instead of
    macOS account auth)
  *Source: CIS Apple macOS Benchmarks (Remote Management controls);
  Apple Platform Security Guide (Screen Sharing); MITRE ATT&CK T1021
  (Remote Services), T1563 (Remote Service Session Hijacking).*

- **FR-070**: The guide MUST expand the persistence mechanism auditing
  section (FR-033) to cover ALL macOS persistence mechanisms, not just
  launch daemons and agents. A nation-state attacker has many
  persistence options beyond LaunchDaemons — limiting the audit to
  one mechanism leaves blind spots. The section MUST cover:
  - **cron jobs**: check `crontab -l` for all users and `/etc/crontab`
    for system-wide entries. cron is deprecated on macOS in favor of
    launchd but still functional. Unexpected cron entries are a strong
    indicator of compromise
  - **at jobs**: check `/var/at/` directory. `at` is disabled by
    default on macOS but can be re-enabled. The guide MUST verify
    `atrun` is not loaded
  - **Login Items**: check `~/Library/Application Support/
    com.apple.backgroundtaskmanagementagent/backgrounditems.btm` and
    the System Settings > Login Items list. Login Items run at user
    login — on a headless server that auto-logs-in, these run at boot
  - **Authorization Plugins**: check `/Library/Security/
    SecurityAgentPlugins/`. These plugins execute during the
    authentication process and can capture passwords or bypass
    authentication entirely. Unauthorized plugins are a critical
    indicator of compromise
  - **Periodic scripts**: check `/etc/periodic/daily/`,
    `/etc/periodic/weekly/`, `/etc/periodic/monthly/`. These scripts
    run via the system's periodic task mechanism. Unexpected scripts
    in these directories are suspicious
  - **Shell profile persistence**: check `/etc/profile`,
    `/etc/bashrc`, `/etc/zshrc`, `~/.bash_profile`, `~/.bashrc`,
    `~/.zshrc`, `~/.zprofile` for unauthorized modifications.
    Attackers can add commands to shell profiles that execute on
    every shell invocation
  - **XPC services**: check for unauthorized XPC services registered
    with launchd. XPC is macOS's inter-process communication
    mechanism and can be used for stealthy persistence
  - **Configuration profiles**: check `profiles list` for MDM-style
    configuration profiles. Malicious profiles can modify system
    settings, install certificates, or configure persistent network
    connections
  - **Baseline for all mechanisms**: the guide MUST extend the
    baseline creation procedure (FR-033) to capture all persistence
    types, not just launch daemons. The comprehensive baseline should
    be generated after initial hardening and stored securely
  - Verification: audit script checks all persistence mechanisms
    against the comprehensive baseline and flags unknown entries
    (WARN for new items, cross-referencing the mechanism type)
  *Source: CIS Apple macOS Benchmarks (persistence controls); MITRE
  ATT&CK T1543 (Create or Modify System Process), T1053 (Scheduled
  Task/Job), T1547 (Boot or Logon Autostart Execution), T1556
  (Modify Authentication Process); Objective-See documentation
  (KnockKnock persistence enumeration).*

- **FR-073**: The guide MUST include a comprehensive sharing services
  hardening section that audits and controls ALL macOS sharing
  services. A headless automation server has no need for most sharing
  services, and each enabled service adds attack surface. The section
  MUST cover every sharing service with a disable/harden decision:
  - **File Sharing (SMB/AFP)**: MUST be disabled on a headless
    server. SMB exposes the system to credential brute force and
    relay attacks (MITRE ATT&CK T1021.002). If the operator needs
    file transfer, use `scp` or `rsync` over SSH instead
  - **Printer Sharing**: MUST be disabled. No headless server needs
    to share printers
  - **Remote Login (SSH)**: covered by FR-028. If enabled, MUST be
    hardened per FR-028. If not needed, disable entirely
  - **Remote Management (ARD)**: covered by FR-069
  - **Remote Apple Events**: MUST be disabled. Remote Apple Events
    allow external applications to send Apple Events to the Mac Mini,
    enabling remote scripting. This is a direct code execution vector
  - **Internet Sharing**: MUST be disabled. Turning the Mac Mini into
    a NAT gateway adds attack surface and can allow LAN devices to
    route traffic through the Mac Mini
  - **Bluetooth Sharing**: MUST be disabled. Bluetooth file transfer
    has no use on a headless server and exposes a short-range attack
    surface
  - **Content Caching**: MUST be disabled. Content Caching stores
    Apple software updates for LAN distribution. It consumes disk
    space, adds network services, and has no security benefit for
    this deployment
  - **Media Sharing**: MUST be disabled. Home Sharing and media
    streaming have no use on a headless server
  - **AirPlay Receiver**: MUST be disabled. AirPlay Receiver accepts
    incoming connections from other Apple devices on the LAN. It adds
    a network service and has been a target for remote code execution
    vulnerabilities
  - The guide MUST provide both the System Settings path and the CLI
    command for each service (per FR-019 CLI-first principle)
  - The guide MUST note that macOS updates sometimes re-enable sharing
    services — the post-update checklist (FR-020) MUST verify all
    sharing services remain in the expected state
  - Verification: audit script checks the status of every sharing
    service listed above. Services that should be disabled produce
    FAIL if enabled (critical: File Sharing, Remote Apple Events,
    Internet Sharing) or WARN if enabled (informational: Content
    Caching, Media Sharing, AirPlay Receiver)
  *Source: CIS Apple macOS Benchmarks (sharing services); Apple
  Platform Security Guide; NIST SP 800-123 Section 4 (Securing the
  OS); MITRE ATT&CK T1021 (Remote Services).*

- **FR-076**: The guide MUST include a recovery mode and startup
  security section that extends physical security (FR-053) to cover
  macOS recovery and alternate boot modes that can bypass software
  security controls. The section MUST cover:
  - **Recovery Mode (macOS Recovery)**: provides a recovery
    environment with Terminal access, Disk Utility, and the ability
    to reset passwords. On Apple Silicon, Recovery Mode requires
    authentication with an administrator account (strong protection).
    On Intel Macs without a firmware password, anyone with physical
    access can boot into Recovery Mode and reset passwords, disable
    FileVault, or modify the system volume. The guide MUST:
    - For Intel: confirm firmware password is set (FR-053) to prevent
      unauthorized Recovery Mode access
    - For Apple Silicon: confirm that Startup Security Utility is set
      to Full Security
    - Document what Recovery Mode can and cannot do when FileVault is
      enabled (it cannot read encrypted data without the FileVault
      password)
  - **Single User Mode**: disabled by SIP on modern macOS (Catalina+)
    and unavailable on Apple Silicon. The guide MUST verify that SIP
    is enabled (FR-002 control area #3) as the primary protection
    against single user mode abuse
  - **Target Disk Mode / Mac Sharing Mode**: Intel Macs support
    Target Disk Mode (hold T at boot) which exposes the internal disk
    as an external drive to another Mac. Apple Silicon uses "Mac
    Sharing Mode" with similar functionality but requires
    authentication. The guide MUST:
    - For Intel: firmware password prevents Target Disk Mode access.
      FileVault encrypts the disk even if Target Disk Mode is entered
    - For Apple Silicon: Mac Sharing Mode requires authentication.
      The guide MUST verify this is configured
  - **External boot media**: the guide MUST verify that booting from
    external media is restricted (Startup Security Utility on Apple
    Silicon, firmware password on Intel). An attacker with physical
    access and a bootable USB can bypass all OS-level security
    controls
  - **DFU Mode (Apple Silicon)**: Device Firmware Update mode allows
    restoring the Mac at the firmware level. The guide MUST note
    that DFU mode erases all data (FileVault protects existing data)
    but an attacker could use it to install a clean macOS and
    repurpose the hardware. Activation Lock (Find My Mac, FR-053)
    is the defense
  - Verification: audit script checks Startup Security level (Apple
    Silicon) or firmware password status (Intel) where programmatically
    verifiable, and SIP status (FAIL if disabled)
  *Source: Apple Platform Security Guide (Startup Security, Recovery
  Mode, DFU); CIS Apple macOS Benchmarks (boot security); MITRE
  ATT&CK T1542 (Pre-OS Boot), T1200 (Hardware Additions).*

- **FR-079**: The guide MUST include a network service binding audit
  section that provides a comprehensive inventory of all listening
  network services on the Mac Mini. Individual FRs cover specific
  services (n8n in FR-011, SSH in FR-028, Screen Sharing in FR-069),
  but an attacker will scan all ports — the operator needs to know
  every service listening on the network. The section MUST cover:
  - **Service inventory procedure**: the guide MUST provide commands
    to enumerate all listening TCP and UDP services:
    - `lsof -iTCP -sTCP:LISTEN -P -n` for TCP listeners
    - `lsof -iUDP -P -n` for UDP listeners
    - `netstat -an | grep LISTEN` as a cross-check
  - **Expected vs unexpected services**: the guide MUST document
    which services are expected to be listening for each deployment
    path:
    - Containerized: SSH (if enabled), Docker/Colima VM port,
      n8n mapped port (127.0.0.1:5678). No other services expected
    - Bare-metal: SSH (if enabled), n8n (127.0.0.1:5678). No other
      services expected
  - **Unexpected listener response**: if the inventory reveals
    services not in the expected list, the guide MUST provide a
    triage procedure:
    - Identify the process: `lsof -i :PORT` to find the owning
      process
    - Determine if it is legitimate (macOS system service, installed
      tool) or suspicious (unknown binary, unexpected path)
    - If suspicious: follow incident response procedure (FR-031)
    - If legitimate but unnecessary: disable it and document why
  - **Container port binding verification**: for containerized
    deployments, verify that all Docker port mappings bind to
    127.0.0.1 (cross-reference FR-058). The guide MUST show how to
    check actual container port bindings using `docker port` and
    `docker inspect`
  - **Regular re-audit**: the listening service inventory MUST be
    part of the periodic audit (FR-007) and the post-update
    checklist (FR-020) — macOS updates and new software installations
    can introduce new listening services
  - Verification: audit script enumerates all listening services,
    compares against an expected-services baseline, and flags
    unexpected listeners (WARN for unknown services, FAIL if a
    service is listening on 0.0.0.0 or a non-localhost interface
    when it should be localhost-only)
  *Source: CIS Apple macOS Benchmarks (network configuration); NIST
  SP 800-123 Section 4.2 (Network Security); MITRE ATT&CK T1046
  (Network Service Discovery).*

- **FR-080**: The guide MUST address DNS as a covert data exfiltration
  channel. Outbound filtering (FR-030) and pf rules block direct TCP/UDP
  connections to unauthorized destinations, but DNS traffic is typically
  permitted because it is required for name resolution. An attacker who
  achieves code execution (via injection per FR-021 or container escape)
  can exfiltrate data by encoding it in DNS subdomain queries (e.g.,
  `base64encodeddata.attacker-domain.com`), bypassing all outbound
  filtering that does not inspect DNS payloads. The section MUST cover:
  - **DNS tunneling attack**: explain how DNS tunneling works — data is
    encoded in subdomain queries to an attacker-controlled domain, and
    responses carry return data. This bypasses standard outbound
    filtering because DNS is allowed. n8n nodes that could be leveraged
    include Execute Command (calling `dig`, `nslookup`, or `host`),
    Code nodes (using Node.js `dns.lookup` or `dns.resolve`), and HTTP
    Request nodes (following attacker-controlled URLs triggers DNS
    resolution that leaks the domain to the attacker's nameserver)
  - **DNS query logging**: the guide MUST recommend enabling DNS query
    logging to detect anomalous patterns. macOS's mDNSResponder can be
    configured for verbose logging (`sudo log config --subsystem
    com.apple.mDNSResponder --mode level:debug`), or a local DNS
    forwarder (such as dnsmasq via Homebrew, free) can log all queries
    with timestamps. Container DNS queries pass through Colima's VM
    DNS resolver and then the host's resolver
  - **Anomalous query detection heuristics**: the guide MUST describe
    DNS exfiltration indicators for manual log review: high volume of
    queries to a single uncommon domain, unusually long subdomain labels
    (>30 characters of high-entropy content), queries with base64 or
    hex-encoded strings in subdomains, repeated queries to newly
    registered or uncommon TLDs. These patterns can be reviewed from
    DNS query logs during periodic log review (FR-009 ongoing tier)
  - **Container DNS isolation**: for containerized deployments, Docker
    containers resolve DNS through the Colima VM's resolver. The guide
    MUST document how to configure container DNS to use only the
    host-configured trusted resolvers (the same encrypted DNS providers
    from FR-029), preventing containers from querying arbitrary DNS
    servers by configuring the `dns` directive in docker-compose.yml
  - **Encrypted DNS and exfiltration**: the guide MUST note that DoH/DoT
    (FR-029) encrypts DNS queries in transit but does NOT prevent DNS
    exfiltration — the queries still reach the DNS provider's resolver,
    which resolves the attacker's domain normally. Encrypted DNS
    protects query privacy from network observers but does not prevent
    the attacker from receiving the exfiltrated data via their
    authoritative nameserver
  - Verification: audit script checks whether DNS query logging is
    enabled (WARN if not configured), container DNS configuration (WARN
    if containers use default DNS instead of host-configured encrypted
    DNS)
  *Source: MITRE ATT&CK T1048.003 (Exfiltration Over Alternative
  Protocol: DNS); SANS Institute (Detecting DNS Tunneling); CIS
  Controls v8 (Control 9); NIST SP 800-81-2 (Secure Domain Name System
  Deployment Guide).*

- **FR-082**: The guide MUST address sensitive data residue in temporary
  files and caches. n8n, Docker, and macOS all create temporary files
  that may contain PII, credentials, or intermediate processing data.
  While FileVault encrypts these at rest, a running attacker with
  filesystem access can read them. The section MUST cover:
  - **macOS temp directories**: `/tmp` (symlinked to `/private/tmp`) and
    `/var/folders/` (per-user temp directories created by macOS's confstr
    system). These directories accumulate data from all processes. The
    guide MUST recommend:
    - Verifying temp directory permissions are appropriate for the
      deployment path (bare-metal: the n8n service account's temp
      directory should not be readable by other non-root users)
    - Periodic cleanup of stale temp data (macOS performs automatic
      cleanup but timing is unpredictable)
    - For bare-metal: the n8n service account's temp directory
      (`/var/folders/xx/.../`) may contain scraped data and intermediate
      processing artifacts from workflow executions
  - **n8n temporary data**: n8n writes temporary files during workflow
    execution (binary data processing, file uploads/downloads, execution
    snapshots). The guide MUST document that these temporary files
    typically reside within the n8n data directory or the system temp
    directory, and recommend that these locations are covered by
    FileVault and excluded from Time Machine if PII sensitivity warrants
    it
  - **Docker build cache**: `docker build` operations cache intermediate
    layers. If custom Dockerfiles are used, build cache may contain
    sensitive data. The guide MUST recommend `docker builder prune` as
    part of periodic maintenance (FR-020) and MUST warn against putting
    secrets in Dockerfile instructions (which persist in layer history);
    use multi-stage builds with `--mount=type=secret` instead
  - **Container /tmp isolation**: in the reference docker-compose.yml
    (FR-058), `read_only: true` prevents writing to most container
    paths, but tmpfs mounts are provided for `/tmp` and other write
    paths. The guide MUST verify that container tmpfs mounts are
    appropriately sized and that container temp data does not persist
    across restarts (tmpfs is RAM-backed and cleared on container stop)
  - **macOS application caches**: macOS applications and services cache
    data in `~/Library/Caches/` and `/Library/Caches/`. If any
    macOS-level tools interact with n8n data (e.g., a web browser
    accessing the n8n UI stores page data, forms, and responses in
    browser cache), this cache may contain PII. The guide MUST recommend
    clearing browser caches after accessing the n8n UI from the Mac Mini
    itself, or using Private Browsing / Incognito mode
  - Verification: audit script checks for unexpected files in `/cores/`
    (cross-ref FR-068), Docker build cache size (informational), and
    container tmpfs configuration in running containers (WARN if tmpfs
    is not configured for write paths)
  *Source: Apple Platform Security Guide (Data Protection); CIS Apple
  macOS Benchmarks (temporary file management); NIST SP 800-88 Rev 1
  (Guidelines for Media Sanitization); Docker security best practices.*

- **FR-084**: The guide MUST address the macOS certificate trust store
  as a critical security boundary. An attacker who gains admin access
  can install a root CA certificate in the System Keychain, enabling
  man-in-the-middle interception of ALL HTTPS traffic from the Mac
  Mini — including Apify API calls, LinkedIn authentication, SMTP relay
  connections, Docker registry pulls, and Homebrew downloads. This
  single action compromises every encrypted connection without
  triggering certificate warnings. The section MUST cover:
  - **Trust store attack**: installing a rogue root CA certificate
    allows the attacker to generate valid-looking certificates for any
    domain, intercepting and modifying HTTPS traffic. On macOS,
    certificates can be installed via `security add-trusted-cert`
    (requires admin) or via a configuration profile (FR-085). The guide
    MUST explain this attack and why it is devastating — it silently
    defeats TLS for every service the Mac Mini connects to
  - **Trust store audit**: the guide MUST recommend periodically
    auditing the System Keychain and System Roots keychain for
    unexpected CA certificates. The command `security find-certificate
    -a -p /Library/Keychains/System.keychain | openssl x509 -noout
    -subject -fingerprint` lists all certificates with fingerprints.
    The guide MUST provide instructions for comparing against a
    known-good baseline
  - **Trust store baseline**: after initial hardening, the operator
    MUST record the list of trusted root CA certificates (subject and
    SHA256 fingerprint) as a baseline. The audit script MUST compare
    the current trust store against this baseline and flag any
    additions (WARN for new certificates — could be legitimate macOS
    updates or attacker-installed)
  - **Certificate pinning awareness**: the guide MUST note that macOS
    does not support user-configured certificate pinning for arbitrary
    applications. Applications that use the system trust store (most
    CLI tools, Docker, Homebrew) are vulnerable to rogue CA attack.
    Some applications perform their own pinning (e.g., Apple services)
    which provides partial protection
  - **Post-incident trust store reset**: during incident recovery
    (FR-031), the guide MUST recommend reviewing and resetting the
    certificate trust store — removing any certificates that were not
    part of the original baseline
  - Verification: audit script compares current root CA certificate
    count and fingerprints against baseline (WARN if certificates were
    added since baseline creation)
  *Source: Apple Platform Security Guide (Certificate Trust); CIS Apple
  macOS Benchmarks (certificate management); MITRE ATT&CK T1553.004
  (Subvert Trust Controls: Install Root Certificate); NIST SP 800-52
  Rev 2 (TLS Implementation Guidelines).*

- **FR-085**: The guide MUST address macOS configuration profiles
  (.mobileconfig) as both a management tool and an attack vector.
  Configuration profiles can modify virtually any macOS setting —
  including disabling FileVault, installing root CA certificates
  (bypassing FR-084), configuring VPN connections, changing DNS
  settings, and adding email accounts. A malicious profile achieves
  persistent system modification without requiring ongoing root access.
  The section MUST cover:
  - **Profile installation vectors**: profiles can be installed via
    MDM (enterprise), downloaded from websites (user clicks to
    install), sent via email attachments, or installed via `profiles
    install` command line. The guide MUST warn that profiles downloaded
    from untrusted sources can silently modify security settings
  - **Profile audit**: the guide MUST recommend running `profiles list`
    to enumerate all installed configuration profiles and their
    payloads. Any profile the operator did not intentionally install
    is suspicious and should be investigated
  - **Lockdown Mode protection**: macOS Lockdown Mode (FR-062) blocks
    configuration profile installation from untrusted sources. If
    Lockdown Mode is enabled, this provides strong protection against
    profile-based attacks
  - **Profile-based attacks**: the guide MUST document specific attacks
    that profiles can enable:
    - Installing a root CA certificate for MITM (cross-ref FR-084)
    - Disabling FileVault or modifying security settings silently
    - Configuring a rogue VPN that routes all traffic through an
      attacker-controlled server
    - Adding an email account that syncs data to an attacker-controlled
      server
    - Modifying DNS configuration to redirect resolution to attacker
      infrastructure
  - **Baseline and monitoring**: after initial hardening, the operator
    MUST record all installed profiles as a baseline. The audit script
    MUST check for configuration profiles not in the baseline (WARN)
  - **Profile removal**: the guide MUST document how to remove unwanted
    profiles (`profiles remove -identifier <id>`) and verify that
    system settings were restored to expected state after removal
  - Verification: audit script checks for installed configuration
    profiles (WARN if any profiles are installed that are not in the
    operator's baseline, FAIL if a profile modifies security-critical
    settings like FileVault or certificate trust)
  *Source: Apple Platform Security Guide (Configuration Profiles); CIS
  Apple macOS Benchmarks (MDM configuration); MITRE ATT&CK T1562
  (Impair Defenses — profiles can disable security controls), T1553.004
  (Install Root Certificate — via profile payload).*

- **FR-086**: The guide MUST address macOS Spotlight indexing as a
  privacy and security concern for the n8n data directory. Spotlight
  indexes file contents, names, and metadata system-wide, making this
  data searchable by any process on the system. If the n8n data
  directory, backup archives, or credential files are indexed, an
  attacker who gains user-level access can use Spotlight (`mdfind`) to
  rapidly locate PII, credentials, and sensitive configuration without
  knowing file paths. The section MUST cover:
  - **Spotlight indexing risk**: Spotlight indexes file contents by
    default. If n8n's database (containing PII lead data and encrypted
    credentials), workflow export JSON files, or backup archives are
    in an indexed location, their contents appear in Spotlight search
    results and metadata queries. An attacker can use
    `mdfind "linkedin"` or `mdfind "password"` to locate sensitive
    data instantly without manual filesystem traversal
  - **Spotlight exclusions**: the guide MUST recommend adding the
    following directories to Spotlight's exclusion list:
    - n8n data directory (bare-metal path)
    - Docker volume mount points (if mounted on the host filesystem)
    - Backup storage directories
    - The Colima VM data directory (`~/.colima`)
    - Any directory containing exported credentials or configuration
  - **CLI configuration**: the guide MUST provide the `mdutil` command
    to disable indexing for specific volumes (`mdutil -i off /path`)
    and `defaults write` to configure Spotlight exclusions via CLI
    (per FR-019 CLI-first principle)
  - **Stale index data**: even after adding exclusions, previously
    indexed data remains in the Spotlight database until it is rebuilt.
    The guide MUST document how to force a Spotlight re-index
    (`mdutil -E /`) to clear stale indexed data that may contain PII
    or credential references
  - **FR-061 cross-reference**: Spotlight Suggestions (sending queries
    to Apple's servers) is already covered in FR-061. This FR
    specifically addresses local Spotlight indexing of sensitive n8n
    data as a lateral movement and data discovery aid
  - Verification: audit script checks whether the n8n data directory
    is excluded from Spotlight indexing (WARN if indexed)
  *Source: Apple Platform Security Guide (Spotlight); CIS Apple macOS
  Benchmarks (privacy settings); MITRE ATT&CK T1005 (Data from Local
  System), T1083 (File and Directory Discovery).*

- **FR-089**: The guide MUST address Docker image security beyond digest
  pinning (FR-040) to cover image provenance verification and build
  hygiene. While FR-040 covers supply chain integrity for pulling
  images, this FR addresses how to verify that images are trustworthy
  and how to avoid introducing vulnerabilities through custom image
  builds. The section MUST cover:
  - **Image provenance**: the guide MUST recommend verifying Docker
    image provenance using Docker's built-in provenance attestations
    (available for official images on Docker Hub). The guide MUST
    document how to check attestations when available and explain that
    provenance attestations confirm the image was built from a specific
    source repository via a specific CI pipeline
  - **Image vulnerability scanning**: the guide MUST recommend running
    a vulnerability scan on the n8n Docker image before deployment.
    Free options include:
    - Trivy (`trivy image n8nio/n8n`, free, open source, installable
      via Homebrew) — recommended as the primary scanner
    - Docker Scout (`docker scout cves n8nio/n8n`, free tier available
      with Docker Desktop or Docker Hub account)
    - Grype (`grype n8nio/n8n`, free, open source)
    - The guide MUST recommend scanning before first deployment and
      after each image update, documenting the scan results alongside
      the image digest
  - **Custom Dockerfile security**: if the operator builds a custom
    Docker image (e.g., adding system packages to the n8n image), the
    guide MUST cover:
    - Never put secrets in Dockerfile instructions (RUN, ENV, COPY) —
      they persist in layer history visible via `docker history
      --no-trunc`
    - Use multi-stage builds to prevent build-time dependencies from
      appearing in the final image
    - Use `--mount=type=secret` for build-time secrets (Docker
      BuildKit)
    - Pin base image by digest in the FROM instruction
    - Minimize installed packages to reduce attack surface
  - **Layer history inspection**: the guide MUST show how to inspect
    image layers (`docker history --no-trunc <image>`) to verify no
    secrets are embedded in any layer. The guide MUST warn that secrets
    in any layer — even intermediate layers from a multi-stage build
    prior to the final stage — may be extractable if the intermediate
    images are not cleaned up
  - **Image scanning schedule**: the guide MUST recommend rescanning
    images periodically (monthly or when the vulnerability database
    updates) to catch newly discovered CVEs in previously deployed
    images. This should be included in the maintenance schedule
    (FR-020) alongside tool updates (FR-026)
  - Verification: audit script checks whether the running n8n container
    image is pinned by digest (cross-ref FR-040) and reports the image
    age (WARN if the image is older than 90 days without a documented
    scan)
  *Source: Docker documentation (Image Provenance, Docker Scout); CIS
  Docker Benchmark v1.6 (Section 4: Container Images and Build Files);
  NIST SP 800-190 (Application Container Security Guide); Trivy
  documentation.*
