# Spec Module: macOS Platform, Container & Network Security

**Parent spec**: [spec.md](spec.md) (Rev 23)
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
