# Specification Quality Checklist: Hardening Guide Extension

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-03-07
**Updated**: 2026-03-07 (Rev 23 -- 6 nation-state attacker rounds: Rev 18-23)
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Notes

- All items pass. Spec is ready for `/speckit.clarify` or `/speckit.plan`.
- **Rev 9 changes (injection: data flow and detection):**
  - Added US-7 (Operator Secures Workflows Against Injection) with
    4 acceptance scenarios: vulnerable Code node pattern, prompt
    injection resistance, logging of attempts, and bare-metal
    consequence awareness.
  - FR-021 expanded with data flow mapping (5-step pipeline showing
    where untrusted data enters and where it reaches code execution).
  - FR-021 expanded with n8n built-in security env vars
    (`N8N_BLOCK_ENV_ACCESS_IN_NODE`, `N8N_RESTRICT_FILE_ACCESS_TO`,
    community/node type restrictions).
  - FR-021 expanded with Detect layer: execution logging, anomaly
    monitoring, suspicious pattern detection, Docker log capture.
  - FR-021 sections now labeled by defensive layer (Prevent/Detect/
    Respond) per FR-008.
  - Fixed stale "25 control areas" reference in FR-020.
- **Rev 10 changes (injection: prompt injection depth):**
  - FR-021 prompt injection: added "never allow LLM output to modify
    workflows" (n8n API persistence attack). Added "system prompt
    hardening is a speed bump, not a wall" caveat.
  - FR-021: named specific vulnerable n8n AI/LLM nodes (OpenAI,
    AI Agent, LangChain, Anthropic, community AI nodes).
  - FR-021 bare-metal warning: expanded to list 5 concrete
    consequences (home directory, Keychain, persistence, lateral
    movement, data exfiltration). Added minimum bare-metal controls
    if operator declines containerization.
  - Edge cases added: subtle data exfiltration via HTTP Request
    nodes following attacker URLs; LLM tool-calling/function-calling
    exploitation.
- **Rev 11 changes (injection: audit and monitoring):**
  - FR-007: expanded injection audit checks beyond Execute Command
    to include `N8N_BLOCK_ENV_ACCESS_IN_NODE`, file access
    restrictions, execution logging enabled.
  - FR-009: added injection log review and workflow re-audit to
    ongoing maintenance tier.
  - SC-012 added: operator can audit any workflow for injection
    vulnerabilities in one pass using the guide's checklist.
  - Assumption added: AI/LLM nodes may or may not be in use;
    injection defense section must be useful regardless.
- **Rev 12 changes (low-touch automated audit scheduling):**
  - Added US-8 (Operator Configures Automated Security Monitoring)
    with 5 acceptance scenarios: launchd job setup, FAIL notification,
    WARN-only silence, 30-day log trail, notification failure fallback.
  - FR-022 added: scheduled audit via launchd with plist template,
    configurable schedule (default weekly), unattended execution.
  - FR-023 added: machine-readable audit output (`--json` flag) for
    downstream automation (notification, dashboards, trend tracking).
  - FR-009 ongoing tier updated: added monitoring infrastructure
    verification (launchd job, notification config, log directory).
  - FR-020 updated: post-update checklist must verify monitoring
    infrastructure intact; cross-references FR-022 through FR-027.
  - SC-013 added: routine maintenance burden < 15 min/month after
    automated monitoring setup.
  - Edge cases added: Mac asleep during audit (launchd handles),
    macOS update removes launchd job (post-update checklist catches).
  - Key Entity added: Scheduled Job (launchd plist).
- **Rev 13 changes (automated failure notification):**
  - FR-024 added: automated notification on FAIL via email (msmtp/
    mailx with SMTP relay) and macOS Notification Center (osascript/
    terminal-notifier), optional webhook. Config via file, not
    hardcoded. Notification includes FAIL counts and guide sections.
  - FR-025 added: alert design principles — only FAIL triggers
    active alert, WARN logged silently, prevents alert fatigue.
    Optional WARN notification for strict environments.
  - SC-014 added: all routine monitoring runs fully unattended after
    initial configuration.
  - Edge cases added: email failure (local fallback + log), alert
    fatigue prevention (FAIL-only active alerts).
  - Assumption added: SMTP relay availability (Gmail app password,
    ISP, self-hosted); macOS Notification Center as fallback.
- **Rev 14 changes (maintainability and self-monitoring):**
  - FR-026 added: automated security tool maintenance — ClamAV
    freshclam scheduling, Homebrew `brew outdated` for tool version
    awareness, n8n update checks. Notify without auto-installing.
    Uses same notification channel as FR-024.
  - FR-027 added: audit log retention (90-day default), log rotation
    (newsyslog or launchd pruning), self-monitoring meta-audit
    (launchd job loaded, notification config valid, log directory
    writable, logs generated on schedule). Infrastructure health
    checks appear in audit output.
  - Edge cases added: silent freshclam failure (audit checks
    signature freshness), disk exhaustion from logs (rotation),
    monitoring bootstrap problem (broken system can't alert about
    own absence — post-update checklist is manual backstop).
  - Assumption added: Mac Mini runs continuously or on regular
    sleep/wake schedule; launchd timing is approximate.
- **Rev 15 changes (network/perimeter controls + incident response):**
  - Top-10 weakness analysis identified 10 underspecified control
    areas; Revs 15-17 systematically address each one.
  - FR-028 added: SSH hardening — key-only auth, disable root login,
    AllowUsers, idle timeout, ed25519 keys, disable sshd if not
    needed, no SSH in containers.
  - FR-029 added: DNS security — encrypted DNS (DoH/DoT), Quad9 vs
    Cloudflare provider comparison, container DNS resolution,
    audit script verification.
  - FR-030 added: outbound filtering — pf packet filter allowlisting
    (free), LuLu (free, Objective-See), Little Snitch [PAID ~$59],
    container network isolation, audit script verification. Closes
    the critical exfiltration gap.
  - FR-031 added: incident response procedure — triage, containment,
    evidence preservation, assessment, credential blast radius,
    recovery from backup, GDPR/CCPA notification obligations.
    Addresses Respond layer gap.
  - US-9 added: Operator Responds to a Suspected Breach (P2) with
    4 acceptance scenarios covering triage, containment, recovery,
    and PII notification.
  - Edge cases added: uncertain compromise triage, SSH key blast
    radius, pf rule conflicts with legitimate workflows.
  - Fixed FR-002: "25 control areas" → "26 control areas" (bug).
- **Rev 16 changes (host-level detection and advanced controls):**
  - FR-032 added: IDS / intrusion detection — Google Santa (binary
    authorization, monitor vs lockdown mode), BlockBlock (persistence
    monitoring), LuLu (network monitoring, cross-ref FR-030),
    KnockKnock (persistence enumeration). Explains how tools
    complement each other. Host IDS needed even with containers.
  - FR-033 added: launch daemon auditing — 4 audit directories,
    known-good baseline creation, drift detection vs baseline,
    re-audit triggers, KnockKnock integration.
  - FR-034 added: USB/Thunderbolt restrictions — BadUSB/DMA threat
    explanation, macOS accessory security setting, Apple Silicon
    IOMMU mitigations, headless server tradeoffs.
  - FR-035 added: macOS-level security logging — unified log
    predicates for security events (failed logins, sudo, firewall,
    Gatekeeper, XProtect, SSH, TCC), log review cadence, n8n
    execution log locations, optional log forwarding to syslog.
  - Edge cases added: IDS blocking legitimate n8n binaries
    (allowlist exceptions), lost baseline (regeneration procedure).
- **Rev 17 changes (bare-metal parity + restore testing):**
  - FR-036 added: bare-metal service account hardening — dedicated
    `_n8n` user, no login shell, restricted filesystem permissions,
    Keychain isolation, launchd-based execution, restricted groups.
    Bare-metal equivalent of container isolation.
  - FR-037 added: restore testing procedure — non-destructive
    restore test for both deployment paths, validation checks (n8n
    starts, workflows present, credentials decrypt, test execution),
    quarterly schedule, backup encryption key escrow.
  - SC-015 added: bare-metal service account limits blast radius to
    n8n data directory only.
  - SC-016 added: restore procedure completes in under 30 minutes
    with verified recovery.
  - Key Entities added: Launch Daemon Baseline (known-good snapshot),
    Incident (breach triggering response procedure).
  - Edge cases added: temporary admin-user debugging, lost encryption
    keys, corrupted backup data.
- **Rev 18 changes (nation-state attack surface analysis — round 1):**
  - Identified 10 weakest areas through nation-state attacker analysis:
    n8n API, webhooks, supply chain, container escape, lateral movement,
    credential lifecycle, execution model, backup security, update
    integrity, memory/swap.
  - FR-038 added: n8n REST API security — disable or key-protect the
    API, API key storage, workflow modification detection, rate limiting.
    MITRE ATT&CK T1106, T1059.007.
  - FR-039 added: webhook security — Header Auth, path unpredictability,
    IP allowlisting, rate limiting, payload validation, reverse proxy
    for internet-facing webhooks. MITRE ATT&CK T1190.
  - FR-040 added: software supply chain integrity — Docker image digest
    pinning, Docker Content Trust, Homebrew tap security, npm supply
    chain (typosquatting, dependency confusion, postinstall scripts),
    community node vetting. MITRE ATT&CK T1195.
  - FR-041 added: container security hardening — Docker socket
    prohibition (T1611), cap-drop=ALL, seccomp profiles,
    no-new-privileges, image minimization, container escape CVE
    awareness, Colima VM isolation layer.
  - FR-042 added: network segmentation and lateral movement — inbound
    LAN threats (ARP spoofing, scanning), outbound pivot defense,
    mDNS/Bonjour/AirDrop reduction, VLAN recommendation, Wi-Fi vs
    Ethernet. MITRE ATT&CK T1557, T1021, T1018.
  - FR-043 added: credential lifecycle management — rotation schedules
    per credential type, expiry detection, revocation procedures,
    credential inventory for incident response. MITRE ATT&CK T1078,
    T1528.
  - FR-044 added: n8n execution model documentation — no sandbox
    (Code nodes share n8n process), credential cross-access,
    process.env access, Execute Command process model, workflow-level
    isolation limitations. MITRE ATT&CK T1059.007, T1059.004.
  - FR-045 added: backup security — encryption at rest (Time Machine,
    gpg, openssl), access control (600 permissions, container
    separation), offsite backup security, integrity verification,
    N8N_ENCRYPTION_KEY separation. MITRE ATT&CK T1005, T1530.
  - FR-002 updated: 26 → 30 control areas (added #27 n8n API security,
    #28 webhook security, #29 supply chain integrity, #30 credential
    lifecycle).
  - FR-007 updated: added check classifications for new control areas.
  - FR-009 updated: new control areas assigned to tiers (#27/#28
    immediate, #29 follow-up, #30 ongoing).
  - FR-011 updated: cross-references to FR-038 and FR-039.
  - SC-001 updated: 26 → 30 control areas.
  - SC-004 updated: 30 → 40 minimum audit checks.
  - SC-017 added: Docker socket mount prohibition.
  - SC-018 added: supply chain integrity verification in all install
    commands.
  - SC-019 added: credential inventory + rotation within 2 hours during
    incident.
  - SC-020 added: n8n API disabled or auth-protected.
  - 10 edge cases added covering: API access, webhook scanning, Docker
    image compromise, npm postinstall, Docker socket mount, Code node
    env access, lateral movement, credential rotation, backup exposure.
  - Key Entities added: Credential Inventory, Supply Chain Source.
- **Rev 19 changes (adjacent attack surface expansion — round 2):**
  - Expanded scope around 10 weakest areas with adjacent attack
    surfaces, thinking like a nation-state attacker.
  - FR-046 added: workflow integrity monitoring — SHA256 baseline,
    drift detection, change triggers, execution log audit, persistence
    attack chain documentation. MITRE ATT&CK T1053.003, T1059.007.
  - FR-047 added: SSRF defense — HTTP Request node as SSRF vector,
    internal target risks (Docker bridge, host gateway, cloud metadata),
    URL allowlisting, pf rules for internal network access, Docker
    --internal networks. OWASP A10, MITRE ATT&CK T1090, T1571.
  - FR-048 added: Colima VM security — VM SSH access, filesystem
    sharing restrictions, resource limits, update cadence, disk
    encryption via FileVault. Colima/Lima documentation.
  - FR-049 added: data exfiltration via non-dangerous nodes — HTTP
    Request, Email, Slack, database nodes as exfiltration paths;
    scraped URL exfiltration; outbound filtering as primary defense.
    MITRE ATT&CK T1041, T1567, T1048.
  - FR-050 added: TCC permission management — bare-metal TCC
    implications, containerized TCC isolation advantage, TCC as
    persistence detection, TCC reset during incident response. Apple
    Platform Security Guide, MITRE ATT&CK T1548.
  - FR-051 added: Keychain security model — access control model,
    separate Keychain recommendation, Keychain vs env vars, headless
    server behavior, credential reuse warning. Apple Keychain
    Services, MITRE ATT&CK T1555.001.
  - FR-002 updated: 30 → 32 control areas (added #31 SSRF defense,
    #32 TCC permission management).
  - SC-001 updated: 30 → 32 control areas.
  - SC-004 updated: 40 → 45 minimum checks, 5 → 8 container checks.
  - SC-021 added: workflow integrity baseline and drift detection.
  - SC-022 added: SSRF mitigation with container network isolation.
  - SC-023 added: credential uniqueness across all services.
  - 10 edge cases added covering: workflow persistence, SSRF chains,
    Colima mount exposure, safe-node exfiltration, credential reuse,
    Time Machine snapshots, TCC abuse, Keychain access, encryption
    key leakage, package MITM.
  - Key Entity added: Workflow Baseline.
- **Rev 20 changes (flesh out underspecified areas — round 3):**
  - FR-013 expanded: PII protection from 3 lines to full section with
    data classification (public/semi-private/derived), data
    minimization, data flow mapping (at rest and in transit), retention
    limits, secure deletion, access control, encryption, breach
    notification obligations (GDPR 72hr, CCPA, LinkedIn ToS).
  - FR-018 expanded: backup frequency (daily workflow, hourly system,
    weekly offsite) and recovery objectives (RPO: 24 hours, RTO: 2
    hours including re-hardening and credential rotation).
  - FR-031 expanded: incident classification (Critical/High/Medium/Low
    severity levels), evidence chain of custody (forensic copies, hash
    verification), when to engage external help (law enforcement,
    IR firm, legal counsel), post-incident review process.
  - FR-052 added: IPv6 hardening — disable if not needed, IPv6 pf
    rules if needed, router advertisement attacks, container IPv6
    implications. MITRE ATT&CK T1557.002.
  - FR-053 added: physical security — boot security (Startup Security
    Utility / firmware password), Find My Mac, cable lock, location,
    post-theft procedure with credential rotation.
  - FR-054 added: community node vetting checklist — source repo,
    maintainer reputation, download volume, version history, dependency
    audit, code review for eval/obfuscation/outbound requests.
  - FR-055 added: reverse proxy — Caddy/nginx for TLS + auth, SSH
    tunnel for occasional access, webhook-only exposure, request
    logging, containerized reverse proxy in Docker Compose.
  - FR-056 added: audit script validation — known-good baseline test,
    deliberate regression test, script integrity hashing, version
    tracking, manual cross-validation.
  - FR-057 added: credential access patterns — bare-metal Keychain
    retrieval, Docker secrets file-to-env bridging, headless Keychain
    lock behavior, n8n internal credential storage model.
  - US-1 expanded: added adversarial acceptance scenario #4 (lockout
    recovery for common hardening mistakes).
  - SC-024 added: lockout warning before dangerous hardening steps.
  - SC-025 added: incident response self-sufficiency.
  - SC-026 added: PII data flow map with retention/deletion.
  - 8 edge cases added covering: SSH lockout, IPv6 firewall bypass,
    device theft, audit script false PASS, community node compromise
    post-install, PII in execution logs, remote access without TLS.
- **Rev 21 changes (configuration security and detection gaps — round 4):**
  - FR-058 added: Docker Compose security configuration — reference
    compose file with security annotations, port binding to 127.0.0.1,
    volume mount restrictions, security options (cap_drop, read_only,
    no-new-privileges, non-root user), resource limits, restart policy,
    compose file integrity monitoring.
  - FR-059 added: n8n security environment variable reference — complete
    table covering authentication, execution security, telemetry
    (N8N_DIAGNOSTICS_ENABLED, N8N_TEMPLATES_ENABLED, etc.), credential
    security, logging settings. Recommended values with rationale.
  - FR-060 added: Apify actor security — actor trust (official/verified),
    API key scoping and rotation, actor output validation, Apify webhook
    signature verification, data residency and retention on Apify platform.
  - FR-061 added: macOS system-level privacy hardening — Spotlight
    network search, diagnostics sharing, Location Services, Siri,
    Safari preloading, advertising tracking, analytics sharing.
  - FR-062 added: Lockdown Mode assessment — what it restricts, impact
    on n8n/Docker/Colima/SSH/Homebrew, recommendation to test before
    enabling, compatibility analysis for this deployment stack.
  - FR-063 added: continuous monitoring — real-time detection tools
    cross-reference (BlockBlock, LuLu, Santa), unified log streaming
    via launchd, n8n execution monitoring, escalation path from
    detection to incident response (closing US-8 → US-9 integration gap).
  - FR-031 expanded: assessment step now cross-references FR-046
    (workflow integrity), FR-050 (TCC), FR-058 (compose file).
  - US-9 expanded: added acceptance scenario #5 testing automated
    monitoring → incident response integration path.
  - SC-027 added: reference compose file with zero FAIL audit results.
  - SC-028 added: comprehensive n8n env var reference.
  - SC-029 added: continuous monitoring covers inter-audit gaps.
  - 6 edge cases added: compose port binding, telemetry leakage, Apify
    actor compromise, Lockdown Mode compatibility, inter-audit attacks,
    compose security option removal.
- **Rev 22 changes (consolidation and strengthening — round 5):**
  - FR-016 expanded: added cross-references to FR-041 and FR-058,
    establishing FR-058 as the single deployable configuration.
  - FR-064 added: n8n update/migration security — pre-update checklist
    (backup, baseline, release notes), post-update verification (env
    vars, node types, credential decryption), containerized and bare-
    metal update procedures, rollback procedure.
  - FR-065 added: audit script limitations — time-of-check/time-of-use
    gap, what the script cannot detect (in-memory malware, kernel
    rootkits, zero-days, insider threats, network attacks), defense in
    depth reinforcement, false sense of security warning.
  - 4 edge cases added: n8n upgrade breaking security defaults, all
    backups corrupted/unavailable, multi-user operator scenarios,
    audit script false confidence.
  - 6 assumptions added: docker-compose.yml as config source of truth,
    Apify actor trust model, single operator assumption, audit script
    as point-in-time only, continuous monitoring complement,
    acknowledgment that no hardening is impenetrable.
- **Rev 23 changes (final strengthening — round 6):**
  - FR-009 expanded: hardening ordering constraints — SSH key before
    password disable, Screen Sharing before disabling other remote
    access, FileVault authrestart before enabling on headless,
    n8n auth before network binding. Cross-refs US-1 scenario #4.
  - FR-066 added: troubleshooting guidance for container startup
    failures (read_only, cap_drop, pf rules, encryption key), bare-
    metal failures (service account perms, Keychain access, npm),
    common failures (SSH lockout, firewall blocks, audit false FAILs).
  - FR-067 added: n8n built-in user management — relationship to
    basic auth, owner account security, no workflow-level isolation,
    MFA recommendation.
  - US-3 expanded: acceptance scenario #3 added for reverse proxy
    tool evaluation (Caddy vs nginx vs SSH tunnel).
  - SC-030 added: troubleshooting resolves issues without removing
    security controls.
  - 3 edge cases added: n8n multi-user, container startup failure,
    headless SSH/Screen Sharing lockout.
  - Audit check coverage verified across all 32 control areas — all
    have explicit checks in FR-007 or individual FR verification
    sections.
- Cumulative counts (Rev 23):
  - FR count: 67
  - User story count: 9
  - Success criteria count: 30
  - Edge case count: 70
  - Control areas: 32
  - Key Entities: 10
  - Assumptions: 16 (checklist previously said 17; verified 16 on disk, likely miscount)
