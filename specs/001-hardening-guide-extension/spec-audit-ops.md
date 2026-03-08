# Spec Module: Audit, Monitoring & Operations

**Parent spec**: [spec.md](spec.md) (Rev 29)
**Module scope**: Audit script, scheduled monitoring, notifications, incident response, backup/recovery, operational limitations, and hardening validation.

## Functional Requirements

- **FR-007**: The guide MUST be accompanied by a standalone executable
  bash audit script (a separate `.sh` file, not only a code block in
  the guide). The script MUST check at least one control per control
  area and use colored PASS/FAIL/WARN output, `set -euo pipefail`,
  and shellcheck-clean syntax. The guide MUST reference the script by
  path and explain how to run it. The script MUST be deployment-aware:
  when Docker is detected, it checks container-specific controls;
  otherwise it checks bare-metal controls. Each check MUST output the
  guide section it corresponds to so the operator can find remediation
  steps. Controls MUST be classified as either **critical** (FAIL
  when missing) or **recommended** (WARN when missing):
  - **Critical (FAIL):** Controls whose absence exposes the system to
    immediate, high-severity risk — FileVault, firewall, SIP,
    Gatekeeper, guest account disabled, automatic login disabled, n8n
    authentication, n8n localhost binding, screen lock enabled,
    sharing services disabled (File Sharing, Remote Apple Events,
    Internet Sharing per FR-073), Screen Sharing using legacy VNC
    password (FR-069).
  - **Recommended (WARN):** Controls that add defense in depth but
    whose absence does not create an immediately exploitable gap —
    Bluetooth disabled, antivirus installed, IDS running, outbound
    filtering, USB restrictions, logging configured, DNS security,
    software updates current, persistence mechanisms audited (all
    types per FR-070), IPv6 disabled/hardened. Injection defense
    checks: Execute Command node disabled or restricted,
    `N8N_BLOCK_ENV_ACCESS_IN_NODE` set,
    `N8N_RESTRICT_FILE_ACCESS_TO` configured, n8n execution logging
    enabled. n8n API security checks: API disabled or key-protected.
    Webhook security checks: authentication configured on webhook
    nodes. Supply chain checks: Docker image pinned by digest,
    Homebrew packages verified. Credential lifecycle checks:
    credential age within rotation policy. Memory/swap checks: core
    dumps disabled, hibernation mode appropriate (FR-068). iCloud
    checks: unnecessary services disabled (FR-071). NTP checks:
    network time enabled (FR-074). Listening service checks:
    inventory matches baseline (FR-075). XProtect checks: signature
    freshness within 14 days (FR-072). Apple built-in security:
    Gatekeeper notarization enforcement, automatic security updates
    enabled (FR-072). DNS exfiltration defense checks: DNS query
    logging enabled (FR-080). Log integrity checks: log file
    permissions, hash chain integrity, log gap detection (FR-081).
    Temp file checks: container tmpfs configuration (FR-082).
    Certificate trust store checks: baseline comparison for
    unauthorized root CAs (FR-084). Configuration profile checks:
    installed profiles not in baseline (FR-085). Spotlight checks:
    n8n data directory excluded from indexing (FR-086). Canary
    mechanism checks: canary files present and unmodified (FR-088).
    Container metadata checks: secrets in docker inspect environment
    variables (FR-090).
  Every control area in FR-002 MUST be classified as either critical
  or recommended. Areas not explicitly named above default to
  recommended. Physical security controls that cannot be verified
  programmatically (e.g., cable lock, secure location) MUST be
  documented in the guide but MAY be excluded from the audit script
  with a comment explaining why.
  The script MUST print a summary line at the end (e.g., "15 PASS,
  3 FAIL, 7 WARN") and exit with code 0 if no FAILs were found or
  non-zero if any FAIL was reported. This enables automated periodic
  execution (cron, launchd) with alerting on non-zero exit. The
  script MUST also detect when it is run without sufficient
  privileges and report a clear SKIP (not a false FAIL) for checks
  that require admin access, with a message explaining how to re-run
  with appropriate privileges.
  *Source: Constitution Article VI; Google Shell Style Guide; CIS
  Benchmark scoring (Scored vs Not Scored controls).*

- **FR-018**: The guide MUST cover backup and recovery for BOTH
  deployment paths, since each path has different backup targets:
  - **Containerized path:** Docker volume export, credential secret
    backup, container image versioning, Colima VM snapshot (if
    applicable), and `docker compose` configuration backup.
  - **Bare-metal path:** n8n workflow export (`n8n export:workflow`),
    credential file backup, Time Machine configuration for the n8n
    data directory, and service account configuration backup.
  - **Both paths:** Backup encryption, offsite/remote copy strategy,
    and a tested restore procedure so the operator can verify backups
    actually work.
  - **Backup frequency and schedule**: the guide MUST recommend a
    backup schedule appropriate for this deployment:
    - n8n workflow and credential backup: daily (workflows and
      credentials change frequently during active development)
    - Full system backup (Time Machine or equivalent): continuous or
      hourly (macOS Time Machine default)
    - Offsite/remote copy: weekly at minimum
    - The schedule MUST be automated via launchd (bare-metal) or a
      scheduled container job (containerized)
  - **Recovery objectives**: the guide MUST document target recovery
    objectives so the operator can make informed backup decisions:
    - RPO (Recovery Point Objective): maximum acceptable data loss is
      24 hours of workflow changes and execution data (achievable with
      daily backups). Operators with higher-frequency workflow changes
      should increase backup frequency
    - RTO (Recovery Time Objective): target recovery time is under 2
      hours from backup — including system restore, re-hardening
      verification via audit script, and credential rotation if
      compromise is suspected. This aligns with SC-016 (30-minute
      restore) plus verification and credential rotation time
  *Source: NIST SP 800-123 Section 5.3 (Backup Procedures); CIS
  Docker Benchmark Section 5 (Container Runtime); NIST SP 800-34
  Rev 1 (Contingency Planning Guide).*

- **FR-020**: The guide MUST include an ongoing maintenance section
  covering: a recommended re-audit schedule (how often to re-run the
  audit script), how to detect and remediate configuration drift after
  macOS updates (which are known to reset firewall rules, sharing
  settings, and privacy permissions), keeping security tools updated
  (ClamAV signatures, Objective-See tools, Santa rules), and a
  procedure for re-hardening after major macOS upgrades. The
  maintenance section MUST include a "post-update checklist" — a
  curated list of settings known to be reset by macOS updates, that
  the operator runs after every macOS update. The post-update
  checklist complements (does not replace) the full audit script:
  - **Post-update checklist:** Quick, targeted — checks only the
    specific settings Apple is known to reset (firewall rules,
    sharing services, privacy permissions, Gatekeeper). Designed to
    be run immediately after every macOS update.
  - **Full audit script (FR-007):** Comprehensive — checks all 32
    control areas. Designed for periodic re-audit (monthly or after
    significant system changes).
  The post-update checklist MUST also verify that the automated
  monitoring infrastructure is intact: launchd audit job loaded,
  notification configuration present, and log directory accessible.
  See FR-022 through FR-027 for the full automated monitoring
  specification.
  The post-update checklist MAY be implemented as a flag or mode of
  the main audit script (e.g., `--post-update`) or as a separate
  section in the guide. The implementation detail is deferred to
  planning.
  *Source: CIS Apple macOS Benchmarks (maintenance cadence); NIST SP
  800-123 Section 5 (Maintaining Server Security).*

- **FR-022**: The guide MUST include instructions for scheduling the
  audit script to run automatically via launchd (macOS-native task
  scheduler). launchd is preferred over cron on macOS because it
  handles sleep/wake correctly (runs missed jobs at next wake),
  integrates with the system's security model, and persists across
  reboots without additional configuration. The guide MUST provide:
  - A ready-to-use launchd plist template that runs the audit script
    on a configurable schedule (default: weekly)
  - Instructions for loading, unloading, and verifying the job
  - Configuration for logging output to a timestamped file
  - The scheduled job MUST run the audit script with no TTY and no
    user interaction required (fully unattended)
  *Source: Apple Developer Documentation (launchd); NIST SP 800-123
  Section 5 (Maintaining Server Security).*

- **FR-023**: The audit script (FR-007) MUST support a machine-readable
  output mode (e.g., `--json` flag) that produces structured results
  in addition to the default colored human-readable output. The
  machine-readable output MUST include: check name, status
  (PASS/FAIL/WARN/SKIP), guide section reference, and timestamp.
  This enables downstream automation: notification scripts,
  dashboards, trend tracking, and integration with external
  monitoring tools.
  *Source: NIST SP 800-137 (Information Security Continuous
  Monitoring); Google Shell Style Guide (structured output for
  machine consumption).*

- **FR-024**: The guide MUST include instructions for automated failure
  notification so the operator is alerted when the scheduled audit
  detects any FAIL result. The guide MUST document at least two
  notification methods, both using free tools:
  1. **Email** via a lightweight CLI mail tool (e.g., msmtp, ssmtp,
     or mailx with SMTP relay). The guide MUST include configuration
     steps for at least one free SMTP relay option (e.g., Gmail SMTP
     with app password, or a self-hosted relay). Email is the primary
     recommended channel because it reaches the operator regardless
     of whether they are near the machine.
  2. **macOS Notification Center** via `osascript` or `terminal-
     notifier` (free, Homebrew-installable). This provides a local
     alert visible on the machine's screen or forwarded to the
     operator's iPhone/iPad via Apple's notification sync.
  Optionally, the guide MAY document a third method:
  3. **Webhook** (HTTP POST to a configurable URL), enabling
     integration with Slack, Discord, n8n, or any webhook-capable
     service. This is documented as an advanced option.
  Each notification MUST include: total PASS/FAIL/WARN counts, which
  specific checks failed, and the guide section references for
  remediation. The notification mechanism MUST be configured via a
  simple configuration file or environment variables, not hardcoded
  in the audit script.
  *Source: NIST SP 800-92 (Guide to Computer Security Log
  Management); CIS Controls v8 (Control 8: Audit Log Management).*

- **FR-025**: The notification system MUST follow alert design
  principles that prevent alert fatigue and ensure critical alerts
  retain urgency:
  - Only FAIL results (critical security controls missing) trigger
    active notifications (email, system alert, webhook)
  - WARN-only audit runs (all critical controls pass, some
    recommended controls missing) are logged but do NOT trigger
    active notification
  - PASS-only audit runs (everything passing) are logged silently
  - The operator MAY optionally configure WARN notifications for
    environments requiring stricter monitoring, but this MUST NOT be
    the default behavior
  - Each notification MUST clearly state the severity: "CRITICAL:
    [N] security controls failed" to distinguish from informational
    messages
  *Source: NIST SP 800-92 Section 4 (Log Management Operational
  Processes); incident response best practices.*

- **FR-026**: The guide MUST include instructions for automating
  routine security tool maintenance to reduce the operator's ongoing
  workload:
  - **ClamAV signature updates**: Configure the freshclam daemon or a
    launchd job to update virus signatures automatically (daily
    recommended). The guide MUST explain how to verify freshclam is
    running and how to check signature freshness.
  - **Security tool update awareness**: Include a launchd job or
    script that periodically checks whether Objective-See tools,
    Colima, Docker, and other security tools have newer versions
    available (using Homebrew's `brew outdated`). Notify the operator
    of available updates without auto-installing them (automatic
    installation of security tools can break running services).
  - **n8n update awareness**: For containerized deployments, document
    how to check for newer n8n Docker images. For bare-metal, check
    `npm outdated -g n8n`.
  These automations MUST follow the same notification channel
  configured in FR-024 (email, system alert, or webhook).
  *Source: CIS Controls v8 (Control 7: Continuous Vulnerability
  Management); NIST SP 800-40 Rev 4 (Guide to Enterprise Patch
  Management Planning).*

- **FR-027**: The guide MUST address audit log retention, rotation, and
  monitoring infrastructure self-check:
  - **Log retention**: Scheduled audit results MUST be retained as
    timestamped log files for a minimum of 90 days (configurable).
    This provides a historical record for trend analysis and incident
    investigation.
  - **Log rotation**: The guide MUST include log rotation
    configuration (via macOS newsyslog or a launchd-based pruning
    job) to prevent audit logs from consuming unbounded disk space.
  - **Self-monitoring**: The audit script MUST include a "meta-audit"
    section that checks the health of the monitoring infrastructure
    itself:
    - Is the launchd audit job loaded and scheduled? (FAIL if missing)
    - Is the notification configuration present and valid? (WARN if
      missing — the operator may intentionally run manual-only)
    - Does the log directory exist and is it writable? (FAIL if not)
    - Are audit logs being generated on schedule? (WARN if the most
      recent log is older than 2x the scheduled interval)
    The self-monitoring checks MUST appear in the audit output
    alongside the security checks, clearly labeled as infrastructure
    health checks.
  *Source: NIST SP 800-92 (Guide to Computer Security Log
  Management); CIS Controls v8 (Control 8: Audit Log Management).*

- **FR-031**: The guide MUST include an incident response section
  covering what to do when a security breach or active compromise is
  suspected. This addresses the Respond defensive layer:
  - **Triage**: How to distinguish a real incident from a false
    positive — specific checks to run (unexpected processes, unknown
    launch daemons, modified workflows, unexplained outbound
    connections, files in unexpected locations)
  - **Containment**: Immediate steps to limit damage — disconnect
    from network (disable Wi-Fi/Ethernet), stop n8n and Docker
    containers, do NOT reboot (preserves volatile evidence in memory
    and running process state)
  - **Evidence preservation**: Before any remediation, preserve
    audit logs, n8n execution logs, macOS unified logs, Docker
    container logs, launch daemon listings, and running process
    snapshots. The guide MUST provide specific commands for each
  - **Assessment**: Determine what was compromised — check for
    unauthorized user accounts, unexpected SSH authorized_keys,
    new launch daemons/agents, modified crontab entries, Docker
    images that differ from expected, n8n workflows changed without
    operator action (use workflow integrity baseline from FR-046 to
    detect workflow-based persistence), TCC permission changes
    (FR-050), Docker Compose file modifications (FR-058)
  - **Credential blast radius**: List all credentials and services
    that may be compromised if the Mac Mini is breached — LinkedIn
    account, Apify API keys, n8n encryption key, SSH keys (and all
    systems those keys access), email/SMTP credentials, any API
    keys stored in n8n credentials
  - **Recovery**: Restore from known-good backup (FR-018), re-harden
    from the guide, rotate ALL credentials (not just the ones known
    to be compromised — assume complete compromise), verify restore
    with the audit script
  - **Notification obligations**: Cross-reference FR-013 for GDPR/
    CCPA breach notification timelines if PII lead data was exposed.
    LinkedIn ToS violations may require notification to LinkedIn
  - **Incident classification**: the guide MUST define severity levels
    to help the operator prioritize response:
    - **Critical**: active attacker presence confirmed (unauthorized
      processes, data exfiltration in progress, modified workflows
      with unknown Code nodes, new SSH authorized_keys)
    - **High**: strong indicators of compromise without confirmed
      active presence (unexpected launch daemons, n8n API access from
      unknown source, failed audit checks that previously passed)
    - **Medium**: suspicious activity that may be benign (new outbound
      connections to unknown IPs, unfamiliar process names, minor
      configuration drift)
    - **Low**: informational anomalies (audit WARN results, failed
      login attempts within normal bounds, software update available)
    Critical and High require immediate containment; Medium requires
    investigation within 24 hours; Low is logged for trend analysis
  - **Evidence chain of custody**: if the incident may involve law
    enforcement or legal proceedings (e.g., GDPR breach, data theft),
    evidence must be handled to preserve admissibility:
    - Document what was found, when, and by whom
    - Create forensic copies (disk images) before modifying any
      system state — the guide MUST provide a command to create a
      disk image or snapshot
    - Store evidence on a separate, trusted device (not the
      compromised Mac Mini)
    - Record SHA256 hashes of all evidence files at collection time
  - **When to engage external help**: the guide MUST provide guidance
    on when the operator should seek external assistance:
    - Law enforcement: if PII was stolen, if the attack appears
      targeted (nation-state, corporate espionage), or if the
      operator's insurance requires it
    - Incident response firm: if the operator cannot determine the
      scope of compromise or if the attacker appears to have
      persistent access that cannot be removed
    - Legal counsel: if GDPR/CCPA notification timelines are
      triggered (72 hours for GDPR)
  - **Post-incident review**: after recovery, the guide MUST recommend
    a post-incident review covering:
    - How the attacker gained access (root cause)
    - What controls failed and why
    - What changes to the hardening configuration are needed
    - Whether the backup/restore procedure worked as expected
    - Whether the incident response process itself had gaps
    - Document findings and update the hardening guide's local notes
  *Source: NIST SP 800-61 Rev 2 (Computer Security Incident Handling
  Guide); NIST Cybersecurity Framework (Respond function); GDPR
  Article 33 (72-hour notification requirement); NIST SP 800-86
  (Guide to Integrating Forensic Techniques).*

- **FR-037**: The guide MUST include a restore testing procedure that
  the operator can follow to validate that their backups actually
  work. Untested backups provide false confidence:
  - **Containerized path**: stop the running container, rename (not
    delete) the Docker volume, restore from backup, verify n8n
    starts and all workflows/credentials are intact, then clean up
    the renamed volume. The procedure MUST be non-destructive —
    the operator can roll back to their current state if the restore
    fails
  - **Bare-metal path**: stop n8n, rename the n8n data directory,
    restore from backup, verify functionality, then clean up. Same
    non-destructive guarantee
  - **Validation checks**: after restore, the operator MUST verify:
    n8n starts successfully, all workflows are present and
    functional, all stored credentials decrypt correctly, a test
    workflow execution completes without errors
  - **Schedule**: the restore test SHOULD be performed at least once
    after initial backup setup, and quarterly thereafter
  - **Backup encryption key safety**: the guide MUST address backup
    encryption key storage — if the encryption key is only on the
    Mac Mini, a disk failure means both the machine and the backups
    are lost. The guide MUST recommend storing the encryption key
    in a separate location (password manager, printed copy in a
    secure location)
  *Source: NIST SP 800-123 Section 5.3 (Backup Procedures); CIS
  Controls v8 (Control 11: Data Recovery).*

- **FR-045**: The guide MUST expand the backup security coverage
  (FR-018, FR-037) to address backup data as a high-value attack
  target. Backups contain ALL secrets — n8n encryption key, stored
  credentials, workflow IP, PII lead data. An attacker who can read
  backups has achieved the same impact as compromising the live
  system:
  - **Backup encryption at rest**: ALL backups MUST be encrypted
    before being written to disk or transferred offsite. The guide
    MUST specify:
    - For Time Machine: enable Time Machine encryption (built-in,
      free) — note that Time Machine encryption uses the user's
      password and is decryptable by anyone with the password
    - For Docker volume exports: encrypt using `gpg` (free) or
      `openssl` before storing
    - For n8n workflow exports (`n8n export:workflow`): these export
      workflows in plaintext JSON. If workflows contain hardcoded
      values or credential references, they MUST be encrypted before
      storage
  - **Backup access control**: backup files MUST have restrictive
    filesystem permissions (600 or 400) so only the backup user can
    read them. On bare-metal, backups MUST NOT be readable by the
    n8n service account (a compromised n8n should not be able to read
    its own backups). On containerized deployments, backup volumes
    MUST NOT be mounted into the n8n container
  - **Offsite backup security**: if backups are transferred to cloud
    storage or a remote server, the guide MUST cover:
    - Encryption in transit (TLS/SSH)
    - Encryption at rest at the destination
    - Access control at the destination (dedicated credentials, not
      the operator's main account)
    - Retention and deletion policy at the destination
  - **Backup integrity verification**: the guide MUST recommend
    generating and storing checksums (SHA256) alongside backups so
    the operator can detect backup tampering or corruption before
    relying on them during recovery
  - **N8N_ENCRYPTION_KEY backup**: this key decrypts all stored n8n
    credentials. If lost, all credentials must be re-entered. If
    stolen, all credentials are compromised. The guide MUST recommend
    storing it separately from the data backup (e.g., in a password
    manager or physical safe) and NEVER in the same backup archive
    as the n8n data it encrypts
  *Source: NIST SP 800-123 Section 5.3 (Backup Procedures); CIS
  Controls v8 (Control 11: Data Recovery); MITRE ATT&CK T1005 (Data
  from Local System), T1530 (Data from Cloud Storage).*

- **FR-046**: The guide MUST include a workflow integrity monitoring
  section that enables the operator to detect unauthorized workflow
  modifications. An attacker who gains access to the n8n API or web
  UI can create or modify workflows to establish persistence — this
  persistence survives n8n restarts, container rebuilds, and even
  backup/restore cycles (because workflows are backed up and
  restored). The section MUST cover:
  - **Workflow baseline**: after initial deployment and workflow
    creation, the operator MUST export all workflows to JSON
    (`n8n export:workflow --all`) and generate a SHA256 hash manifest
    of the export. This becomes the known-good baseline
  - **Drift detection**: the audit script MUST include a check that
    exports current workflows, compares them against the baseline
    manifest, and flags any additions, deletions, or modifications
    as WARN. New or modified workflows could be legitimate changes
    or attacker persistence — the operator must investigate
  - **Change triggers**: the guide MUST recommend re-baselining after
    every intentional workflow change, and running drift detection
    after any security event (FAIL notifications, suspicious log
    entries)
  - **n8n execution log audit**: the guide MUST document how to query
    n8n's execution log for workflow creation and modification events
    (via the n8n API or database). Unexpected modifications outside
    the operator's normal working hours are a strong indicator of
    compromise
  - **Persistence attack chain**: the guide MUST explain the specific
    attack chain — (1) attacker gains n8n API access or injects via
    webhook, (2) creates a scheduled workflow with a Code node that
    runs on a timer, (3) the Code node phones home or installs
    further persistence, (4) this workflow survives restarts and
    backups. The operator must understand this to know what to look
    for (MITRE ATT&CK T1053.003 Cron, T1059.007 JavaScript)
  - Verification: audit script compares workflow count and hash
    manifest against baseline (WARN on mismatch)
  *Source: MITRE ATT&CK T1053.003 (Scheduled Task/Job: Cron),
  T1059.007 (Command and Scripting Interpreter: JavaScript); NIST SP
  800-137 (Information Security Continuous Monitoring); n8n API
  documentation.*

- **FR-056**: The guide MUST address audit script validation — how
  the operator can trust that the audit script itself is producing
  accurate results. A false PASS is worse than no check at all
  because it creates false confidence. The section MUST cover:
  - **Known-good baseline test**: the guide MUST include a procedure
    for validating the audit script against a known state — run the
    script on an unhardened macOS install and verify it produces the
    expected FAIL/WARN results. If a control is known to be missing
    and the script reports PASS, the script has a bug
  - **Deliberate regression test**: the guide MUST include a procedure
    for testing specific checks by deliberately disabling a hardened
    control (e.g., disable the firewall) and verifying the script
    catches it. This confirms the check works in both directions
    (PASS when configured, FAIL when not)
  - **Script integrity**: the audit script file itself should have
    its SHA256 hash recorded. If the script is modified (by an
    attacker to suppress FAIL results, or by a macOS update that
    changes file permissions), the hash comparison catches it. The
    guide MUST recommend storing the script hash in the credential
    inventory or a separate file
  - **Version tracking**: the audit script MUST include a version
    string that is printed at the start of every run. This ensures
    the operator knows which version of the script produced each
    audit log and can identify if an old version is running
  - **Cross-validation**: the guide MUST recommend periodically
    running a manual spot-check of 3-5 audit checks by manually
    verifying the control state and comparing with the script's
    output. This catches script drift (macOS changes that break the
    check logic)
  *Source: CIS Controls v8 (Control 8: Audit Log Management); NIST
  SP 800-53 Rev 5 (AU-6 Audit Review, Analysis, and Reporting).*

- **FR-063**: The guide MUST include a continuous monitoring section
  that addresses the detection gap between periodic audit script runs.
  The audit script (FR-007) is a point-in-time assessment — it cannot
  detect attacks that happen between runs. The section MUST cover:
  - **Real-time detection tools** (already specified but MUST be
    cross-referenced as the continuous monitoring layer):
    - BlockBlock (FR-032): alerts on new persistence mechanisms in
      real-time
    - LuLu (FR-030/032): alerts on new outbound connections in
      real-time
    - Santa (FR-032): blocks/logs unauthorized binary execution in
      real-time
    - These tools provide continuous monitoring while the audit script
      provides periodic comprehensive assessment
  - **macOS unified log monitoring**: the guide MUST provide specific
    `log stream` commands (or launchd jobs running `log stream`) that
    continuously monitor for critical security events:
    - Failed authentication attempts (SSH, screen lock)
    - New TCC permission grants (FR-050)
    - Firewall blocks
    - Process execution anomalies
    The guide MUST recommend running these as background launchd jobs
    that pipe filtered events to a log file for review, rather than
    requiring the operator to manually run `log stream`
  - **n8n execution monitoring**: for containerized deployments,
    `docker logs -f` can stream n8n logs. The guide MUST recommend
    monitoring for unexpected workflow executions (especially outside
    business hours) and failed authentication attempts
  - **Integration between detection and response**: the guide MUST
    document the escalation path — when a real-time detection tool
    (BlockBlock, LuLu) fires an alert, the operator should:
    1. Check the alert details against known-good baselines
    2. If suspicious, run the full audit script immediately
    3. If the audit script confirms anomalies, follow the incident
       response procedure (FR-031)
    This closes the gap between automated monitoring (US-8) and
    incident response (US-9)
  *Source: Apple Developer Documentation (Unified Logging); NIST SP
  800-137 (Information Security Continuous Monitoring); MITRE ATT&CK
  detection techniques.*

- **FR-065**: The guide MUST explicitly document the limitations of
  the audit script and overall monitoring approach so the operator
  understands what is NOT covered:
  - **Time-of-check/time-of-use**: the audit script checks
    configuration at a point in time. An attacker can modify
    configuration after the audit runs and before the next run. The
    guide MUST state this limitation and cross-reference continuous
    monitoring (FR-063) as the complementary control
  - **What the audit script cannot detect**: the guide MUST list
    categories of attacks that the audit script is not designed to
    detect:
    - In-memory malware that leaves no disk artifacts
    - Kernel-level rootkits (SIP protects against most of these, but
      the audit script cannot verify kernel integrity beyond checking
      SIP status)
    - Zero-day exploits in n8n, Docker, Colima, or macOS itself
    - Insider threats from operators with legitimate admin access
    - Network-level attacks (MITM, ARP spoofing) that don't modify
      host configuration
  - **Defense in depth**: the guide MUST reinforce that no single
    control is sufficient — the audit script is one layer alongside
    continuous monitoring (FR-063), IDS tools (FR-032), outbound
    filtering (FR-030), and container isolation (FR-016/041/058).
    A nation-state attacker may bypass any individual control; the
    goal is to make the combined defensive stack expensive to
    penetrate and likely to detect intrusion
  - **False sense of security**: the guide MUST warn that an all-PASS
    audit result does not mean the system is uncompromised — it means
    the checked configurations are in the expected state. The audit
    script validates configuration, not absence of compromise
  *Source: NIST SP 800-53 Rev 5 (CA-7 Continuous Monitoring); NIST
  Cybersecurity Framework (Limitations of compliance-based security).*

- **FR-072**: The guide MUST include a section documenting Apple's
  built-in malware defense layers (XProtect, XProtect Remediator,
  MRT, Gatekeeper notarization) and how they interact with the
  guide's recommended security tools. Operators often install third-
  party tools without understanding the baseline protection macOS
  already provides. The section MUST cover:
  - **XProtect**: Apple's built-in signature-based malware scanner.
    XProtect runs automatically when applications are first opened,
    when apps are updated, and when XProtect signatures are updated.
    The guide MUST:
    - Explain that XProtect updates are delivered silently via
      Software Update, independent of macOS version updates
    - Document how to check XProtect version and signature freshness
      (`system_profiler SPInstallHistoryDataType | grep XProtect`)
    - Note that XProtect provides a baseline and is NOT a substitute
      for ClamAV (which has a much larger signature database) or
      behavioral detection (Santa, BlockBlock per FR-032)
  - **XProtect Remediator** (macOS Ventura+): an automated malware
    remediation tool that scans for and removes known malware. Unlike
    XProtect (which prevents execution), Remediator removes malware
    that is already on the system. The guide MUST document its
    existence and how to verify it is running
  - **MRT (Malware Removal Tool)**: legacy malware removal that runs
    after Software Update. Being replaced by XProtect Remediator on
    newer macOS versions. The guide MUST note this transition
  - **Gatekeeper notarization**: beyond code signing (control area
    #4), Apple requires apps to be notarized (submitted to Apple for
    malware scanning) before Gatekeeper allows them. The guide MUST
    explain the notarization chain: developer signs → submits to
    Apple → Apple scans → issues a notarization ticket → Gatekeeper
    verifies the ticket at launch. CLI tools installed via Homebrew
    may not be notarized — the guide MUST explain how to handle
    Gatekeeper prompts for Homebrew-installed security tools
  - **Apple security response updates**: rapid security responses
    that patch critical vulnerabilities between major macOS updates.
    The guide MUST recommend enabling automatic security response
    installation
  - Verification: audit script checks XProtect signature freshness
    (WARN if last update is older than 14 days), Gatekeeper status
    (FAIL if disabled — cross-ref existing check), automatic security
    update settings (WARN if disabled)
  *Source: Apple Platform Security Guide (XProtect, Gatekeeper,
  notarization); CIS Apple macOS Benchmarks (malware protection);
  NIST SP 800-83 Rev 1 (Guide to Malware Incident Prevention).*

- **FR-074**: The guide MUST include a time synchronization (NTP)
  integrity section. Accurate system time is a security dependency
  for multiple controls in this guide. Time manipulation can undermine
  log forensics, certificate validation, credential expiry detection,
  and scheduled task execution. The section MUST cover:
  - **Why time integrity matters for this deployment**:
    - Log timestamps: if an attacker can skew the clock, forensic
      log analysis (FR-035, FR-027) becomes unreliable — events
      appear out of order or at incorrect times
    - TLS certificate validation: certificate expiry checks depend
      on accurate time. A sufficiently skewed clock can make expired
      certificates appear valid or valid certificates appear expired,
      disrupting HTTPS connections to Apify, LinkedIn, SMTP relays
    - Credential expiry: credential rotation detection (FR-043)
      relies on comparing creation timestamps against rotation
      policy. Clock skew can mask overdue rotations
    - Scheduled tasks: launchd audit scheduling (FR-022) depends on
      the system clock. Clock manipulation can delay or prevent
      scheduled audit runs
  - **macOS NTP configuration**: macOS uses `timed` for time
    synchronization, defaulting to `time.apple.com`. The guide MUST
    verify NTP is enabled (`systemsetup -getusingnetworktime`) and
    recommend keeping Apple's default time server (which uses NTS —
    Network Time Security — for authenticated time on newer macOS
    versions)
  - **NTP attack surface**: on a LAN, an attacker can spoof NTP
    responses to skew the clock (MITRE ATT&CK T1070.006 Timestomp).
    The guide MUST note that NTS (Network Time Security) protects
    against NTP spoofing on supported macOS versions, and that
    certificate-based TLS connections provide an independent time
    verification (TLS handshake will fail if time skew is too large)
  - **Container time**: Docker containers inherit the host's clock.
    The guide MUST verify that the Colima VM's time sync is working
    (Colima uses Lima's time sync mechanism). A drifted VM clock
    affects all container operations
  - Verification: audit script checks NTP status (WARN if network
    time is disabled), clock skew (WARN if system time differs from
    NTP source by more than 60 seconds)
  *Source: NIST SP 800-86 (Guide to Integrating Forensic Techniques
  — timestamp reliability); CIS Apple macOS Benchmarks (time
  synchronization); MITRE ATT&CK T1070.006 (Timestomp); RFC 8915
  (Network Time Security).*

- **FR-075**: The guide MUST include a listening service inventory
  section that is integrated into the audit script (FR-007) as a
  baseline-comparison check. While individual FRs cover specific
  services, an attacker will enumerate all listening ports — the
  audit must do the same. The section MUST:
  - **Baseline creation**: after initial hardening, enumerate all
    listening TCP and UDP services and save the list as a known-good
    baseline (similar to launch daemon baseline in FR-033). The
    baseline MUST record: port number, protocol, bound address,
    owning process name and PID
  - **Automated comparison**: the audit script MUST compare current
    listening services against the baseline on every run and flag
    new listeners (WARN), missing expected listeners (informational),
    and listeners that changed their binding address (WARN — e.g.,
    a service that was bound to 127.0.0.1 is now on 0.0.0.0)
  - **Expected services documentation**: the guide MUST list the
    expected listening services for each deployment path (cross-
    reference FR-079 in spec-macos-platform.md for the detailed
    inventory procedure)
  - Verification: audit script performs the baseline comparison as
    described above
  *Source: CIS Apple macOS Benchmarks (network configuration); NIST
  SP 800-123 Section 4.2 (Network Security); CIS Controls v8
  (Control 9: Email and Web Browser Protections — adapted for
  network service inventory).*

- **FR-077**: The guide MUST include an emergency credential rotation
  runbook — a step-by-step procedure for rotating ALL credentials in
  priority order during an incident response (FR-031). The current
  spec includes credential rotation schedules (FR-043) and revocation
  procedures, but does not provide an ordered, time-pressured
  emergency rotation sequence. During an active breach, the operator
  needs a concrete checklist they can execute without decision-making
  under pressure. The runbook MUST:
  - **Rotation order**: rotate credentials in dependency order —
    credentials that protect other credentials are rotated first:
    1. Mac Mini login password (protects physical and SSH access)
    2. SSH keys (protects remote access; revoke old keys from all
       `authorized_keys` on remote systems)
    3. N8N_ENCRYPTION_KEY (protects all n8n-stored credentials; must
       re-encrypt the n8n database after rotation)
    4. n8n web UI / owner account password
    5. n8n API keys (if enabled per FR-038)
    6. Apify API key
    7. LinkedIn session tokens / cookies (force re-authentication)
    8. SMTP relay credentials (email notifications)
    9. Docker registry credentials (if applicable)
    10. Any additional credentials in the credential inventory
        (FR-043)
  - **Per-credential rotation steps**: for each credential, document:
    - Where to change it (specific settings page, CLI command, config
      file)
    - What breaks immediately when changed (which workflows, services,
      or connections will fail)
    - What to update after changing (which config files, environment
      variables, or n8n credential entries reference the old value)
    - How to verify the rotation worked (test command or workflow
      execution)
  - **N8N_ENCRYPTION_KEY special handling**: rotating this key
    requires re-encrypting all n8n credentials. The guide MUST
    provide the exact procedure: export credentials, change the key,
    re-import with the new key. Loss of the old key before re-
    encryption means all credentials are unrecoverable
  - **Time target**: the complete emergency rotation MUST be
    achievable within the SC-019 target (2 hours) by an operator
    following the runbook step-by-step
  - **Practice runs**: the guide MUST recommend performing a dry run
    of the emergency rotation procedure (without actually changing
    production credentials) to verify the operator can complete it
    within the time target
  - Verification: not automated — this is a procedural document.
    The guide MUST recommend scheduling an annual practice rotation
    (similar to restore testing in FR-037)
  *Source: NIST SP 800-61 Rev 2 (Incident Handling — eradication
  steps); NIST SP 800-63B Section 5.1 (Authenticator Lifecycle);
  CIS Controls v8 (Control 5: Account Management).*

- **FR-078**: The guide MUST include an attack simulation / hardening
  validation section that provides safe, non-destructive test
  procedures for verifying that hardening controls actually work.
  FR-056 covers audit script validation (does the script detect
  misconfigurations); this FR covers control validation (do the
  controls actually prevent attacks). The section MUST cover:
  - **Firewall validation**: from another device on the LAN, attempt
    to connect to the Mac Mini on ports that should be blocked. The
    guide MUST provide specific test commands (`nc -z <ip> <port>`)
    and expected results (connection refused or timeout)
  - **Outbound filtering validation**: from the Mac Mini, attempt an
    outbound connection to a non-allowlisted destination. The guide
    MUST provide a test command (`curl -s -o /dev/null -w "%{http_code}"
    http://example.com`) and expected result (blocked by pf or LuLu)
  - **n8n authentication validation**: attempt to access the n8n web
    UI and API without credentials. The guide MUST provide the test
    URL and expected result (401 Unauthorized or login page redirect)
  - **Container isolation validation**: from inside the running n8n
    container, attempt to access host resources:
    - Try to read host filesystem outside mounted volumes
    - Try to access the Docker socket (should not be mounted)
    - Try to reach host services on the gateway IP
    - Try to execute privileged operations (should fail with
      cap-drop and no-new-privileges)
  - **Injection defense validation**: create a test n8n workflow that
    processes a benign test payload containing shell metacharacters
    and prompt injection strings. Verify that:
    - The payload does not execute as code
    - The attempt is logged (FR-021 detection)
    - `N8N_BLOCK_ENV_ACCESS_IN_NODE` prevents env var access
  - **Persistence detection validation**: create a temporary test
    launch agent (with a harmless payload like `echo test`). Run the
    audit script and verify it detects the new agent. Remove the
    test agent afterward
  - **Notification validation**: deliberately introduce a security
    regression (e.g., disable the firewall temporarily), trigger an
    audit run, and verify the notification is delivered. Re-enable
    the firewall immediately after the test
  - **Non-destructive guarantee**: every test procedure MUST include
    cleanup steps that return the system to its hardened state. The
    guide MUST warn against running validation tests during active
    production workloads
  - **Schedule**: the guide MUST recommend running validation tests
    after initial hardening setup and after any major configuration
    change (not on a recurring schedule — the audit script covers
    ongoing monitoring)
  *Source: NIST SP 800-115 (Technical Guide to Information Security
  Testing and Assessment); CIS Controls v8 (Control 18: Penetration
  Testing); OWASP Testing Guide.*

- **FR-081**: The guide MUST address log integrity as a forensic
  prerequisite. All detection and incident response capabilities
  (FR-031, FR-035, FR-063) depend on logs being trustworthy. An attacker
  who gains shell access (especially root/admin on bare-metal) can
  modify, truncate, or delete logs to hide their activity — rendering
  the entire detection stack useless. The section MUST cover:
  - **Log file permissions**: audit log files (FR-027) MUST be owned by
    root and writable only by the audit script process. The n8n service
    account (bare-metal) and container process MUST NOT have write
    access to audit logs. This prevents a compromised n8n from tampering
    with audit output
  - **Append-only protection**: where feasible, the guide MUST recommend
    macOS extended attributes (`chflags uappend`) on active log files to
    prevent modification of existing entries. This is not foolproof
    (root can remove the flag), but it raises the attacker's required
    privilege level and creates a forensic indicator if the flag is
    removed
  - **Log hash chain**: the guide MUST recommend that the audit script
    include a running hash chain — each audit log entry includes a
    SHA256 hash of the previous entry, creating a tamper-evident chain.
    If an attacker deletes or modifies a middle entry, the hash chain
    breaks, and this break is detectable at the next audit run. The
    first entry in the chain uses a random initialization value stored
    separately from the logs
  - **Log gap detection**: the audit script's self-monitoring (FR-027)
    MUST check for suspicious log gaps — if the most recent log
    timestamp is older than expected, or if log file sizes have
    decreased between runs (indicating truncation), this MUST be
    reported as WARN with a recommendation to investigate
  - **External log forwarding**: the guide MUST recommend forwarding
    critical logs (audit results, n8n execution events, security events
    from FR-035) to an external destination that the Mac Mini cannot
    modify. Options: a remote syslog server, a cloud logging service
    (many free tiers available), or a simple `scp` to a separate server
    on a schedule via launchd. The guide MUST note that external
    forwarding is the strongest log integrity control — an attacker who
    compromises the Mac Mini cannot modify logs that have already been
    forwarded
  - **Container log separation**: for containerized deployments, Docker
    logs are separate from host logs. The guide MUST recommend that
    Docker logs be captured to the host filesystem via Docker's logging
    driver configuration (not only inside the container) and included
    in the log forwarding pipeline
  - Verification: audit script checks log file permissions (WARN if
    writable by non-root), log hash chain integrity (WARN if chain is
    broken or missing), log gap detection (WARN if expected logs are
    missing or truncated)
  *Source: NIST SP 800-92 (Guide to Computer Security Log Management);
  NIST SP 800-86 (Guide to Integrating Forensic Techniques); MITRE
  ATT&CK T1070.001 (Indicator Removal: Clear Linux or Mac System
  Logs); CIS Controls v8 (Control 8: Audit Log Management).*

- **FR-088**: The guide MUST include tripwire and canary detection
  mechanisms that provide independent compromise detection beyond
  periodic auditing and continuous monitoring tools. The existing
  detection stack (FR-007 audit script, FR-032 IDS tools, FR-063
  continuous monitoring) relies on checking for known indicators.
  Canary mechanisms detect compromise by monitoring for access to
  resources that should never be legitimately accessed — if triggered,
  an attacker is present. The section MUST cover:
  - **Canary files**: the guide MUST recommend creating files in
    sensitive locations that should never be accessed during normal
    operations:
    - A file in the n8n data directory with an attractive name (e.g.,
      `admin-credentials.txt`) containing a unique identifier. If the
      file is accessed, the attacker was browsing the filesystem for
      credentials
    - On bare-metal: a file in the operator's home directory with a
      credential-like name containing a unique token
    - The guide MUST document how to set up macOS file access auditing
      via OpenBSM (`/etc/security/audit_control`) or `log stream` with
      a file open predicate to detect when these files are read
  - **Honey credentials**: the guide MUST recommend creating a separate
    n8n credential entry with an attractive name (e.g., "AWS Root
    Account") containing a unique token or a URL pointing to a canary
    service. If the token appears in any outbound traffic or the URL
    is accessed, an attacker is testing stolen credentials. Free
    canary token services exist (e.g., Canarytokens.org)
  - **Canary DNS**: the guide MUST recommend using a canary DNS hostname
    (via a free canary token service) placed in a configuration file
    or credential store. If this hostname is ever resolved (appearing
    in DNS logs per FR-080), it indicates that an attacker is exploring
    the environment and testing discovered credentials
  - **Detection integration**: canary alerts MUST integrate with the
    existing notification infrastructure (FR-024) or use the canary
    service's built-in notification. The guide MUST provide specific
    log predicates or monitoring commands for detecting canary file
    access
  - **Limitations**: the guide MUST note that canary mechanisms are
    not foolproof — a sophisticated attacker may recognize canary
    files (common names, zero-byte content, obvious honeypot patterns)
    and avoid triggering them. However, they provide an independent
    detection layer that does not rely on configuration checking (audit
    script) or behavioral analysis (IDS tools), and most automated
    attack tools will trigger them
  - Verification: audit script checks that canary files exist and have
    not been modified or deleted (WARN if missing — could indicate
    attacker cleanup or accidental deletion)
  *Source: Thinkst Canary documentation (canary detection concepts);
  MITRE D3FEND (Decoy Object, Decoy Credentials); NIST SP 800-53
  Rev 5 (SI-4 Information System Monitoring — deception techniques).*
