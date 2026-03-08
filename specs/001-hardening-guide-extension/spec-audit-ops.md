# Spec Module: Audit, Monitoring & Operations

**Parent spec**: [spec.md](spec.md) (Rev 23)
**Module scope**: Audit script, scheduled monitoring, notifications, incident response, backup/recovery, and operational limitations.

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
    sharing services disabled.
  - **Recommended (WARN):** Controls that add defense in depth but
    whose absence does not create an immediately exploitable gap —
    Bluetooth disabled, antivirus installed, IDS running, outbound
    filtering, USB restrictions, logging configured, DNS security,
    software updates current, launch daemons audited, IPv6
    disabled/hardened. Injection defense checks: Execute Command node
    disabled or restricted, `N8N_BLOCK_ENV_ACCESS_IN_NODE` set,
    `N8N_RESTRICT_FILE_ACCESS_TO` configured, n8n execution logging
    enabled. n8n API security checks: API disabled or key-protected.
    Webhook security checks: authentication configured on webhook
    nodes. Supply chain checks: Docker image pinned by digest,
    Homebrew packages verified. Credential lifecycle checks:
    credential age within rotation policy.
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
