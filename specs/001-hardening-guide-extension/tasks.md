# Tasks: Hardening Guide Extension

**Input**: Design documents from `/specs/001-hardening-guide-extension/`
**Prerequisites**: plan.md, spec.md (Rev 29), research.md (13 items), data-model.md, contracts/ (audit-script-cli.md, guide-structure.md), quickstart.md

**Tests**: No automated tests requested. Validation is manual: `shellcheck` for the audit script, `markdownlint` for the guide, and section-by-section MacBook walkthrough (see plan.md Testing Strategy).

**Organization**: Tasks follow the section-by-section delivery strategy from plan.md. Each phase corresponds to one PR. User story tags indicate which story each task primarily serves. Since US-1 ("Operator Hardens a Fresh Mac Mini") spans the entire guide, it is implicit in all guide-writing tasks -- additional story tags indicate the most specific story served.

## Format: `- [ ] [ID] [P?] [Story?] Description with file path`

- **[P]**: Can run in parallel (different files or independent guide sections)
- **[Story]**: Which user story this task primarily serves (US1-US9)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create project directory structure, guide skeleton, audit script framework, and check ID registry

- [x] T001 Create directory structure: `scripts/templates/` and `scripts/launchd/` directories per plan.md project structure
- [x] T002 Create `docs/HARDENING.md` skeleton with preamble placeholder, all section heading stubs (§1-§11), and appendix headings (A-E) per `contracts/guide-structure.md`; include explicit table of contents at top for 30-second navigation per SC-011; migrate any still-accurate content from existing 68-line `docs/HARDENING.md` per FR-015
- [x] T003 [P] Create `scripts/hardening-audit.sh` framework with `set -euo pipefail`, CLI argument parsing (`--json`, `--section`, `--quiet`, `--no-color`, `--help`, `--version`), colored status output functions (PASS/FAIL/WARN/SKIP), deployment detection logic, `run_check` wrapper using subshell trap pattern, summary counters, and JSON output skeleton per `contracts/audit-script-cli.md`; incorporate existing 5-check verification script from current HARDENING.md per FR-015
- [x] T004 [P] Add deprecation header to `docs/SONOMA-HARDENING.md` redirecting to `docs/HARDENING.md` §2 per plan.md
- [x] T005 [P] Create `scripts/CHK-REGISTRY.md` check ID registry -- central list tracking every CHK-* ID, severity (FAIL/WARN), deployment path (both/containerized/bare-metal), guide section reference, and owning task; each subsequent audit task must update this file when adding checks

**Checkpoint**: Guide skeleton, audit script framework, and check ID registry ready. All subsequent phases build on these files.

---

## Phase 2: §1 Threat Model + Preamble (US-1) -- MVP 🎯

**Goal**: Establish the threat model foundation and guide navigation structure

**Independent Test**: Read the threat model section and verify it names the specific platform (Mac Mini), workload (n8n + Apify), assets (credentials, PII, system integrity), and adversaries per FR-001

- [x] T006 [P] [US1] Write guide preamble in `docs/HARDENING.md`: purpose and scope, how to use this guide, deployment path decision tree (containerized vs bare-metal), cross-reference notation conventions (`§X.Y`, `CHK-*`)
- [x] T007 [P] [US1] Write §1 Threat Model in `docs/HARDENING.md`: platform description (Mac Mini + n8n + Apify + LinkedIn lead gen), assets to protect, adversary profiles, attack surface map, scope exclusions per FR-001
- [x] T008 [P] [US1] Write prioritized quick-start checklist in `docs/HARDENING.md` preamble: Immediate/Follow-up/Ongoing tiers per FR-009 with all 39 control areas assigned to exactly one tier, ordering constraints (SSH key before disabling password auth, Screen Sharing before disabling other remote access, FileVault authrestart before enabling FileVault, n8n auth before binding to network), and lockout warnings; NOTE: FR-009 is ~50 lines of spec text with specific tier-to-control mappings -- implementer must read full FR-009 from spec.md

**Checkpoint**: Guide has navigable structure and threat context. MacBook operator can understand the deployment before hardening.

---

## Phase 3: §2 OS Foundation (US-1)

**Goal**: Harden the macOS operating system foundation (FileVault, firewall, SIP, Gatekeeper, screen lock, guest/sharing, lockdown mode, recovery mode, system privacy, TCC, memory security)

**Independent Test**: Follow §2 on a fresh Sonoma MacBook and verify FileVault enabled, firewall on + stealth mode, SIP verified, guest disabled, auto-login off, sharing services disabled, core dumps disabled, TCC permissions reviewed

- [x] T009 [P] [US1] Write §2.1 FileVault, §2.2 Firewall, §2.3 SIP in `docs/HARDENING.md` -- FR-002 baseline control areas; each with threat justification, canonical source citation, copy-pasteable CLI commands, verification command, and edge cases (FileVault `fdesetup authrestart` for headless reboot); Tahoe-specific SIP changes per R-010
- [x] T010 [P] [US1] Write §2.4 Gatekeeper/XProtect, §2.5 Software Updates in `docs/HARDENING.md` -- Tahoe vs Sonoma differences per research.md R-010 (stricter Gatekeeper, TCC changes), XProtect/XProtect Remediator/MRT defense stack per FR-072, signature freshness check
- [x] T011 [P] [US1] Write §2.6 Screen Lock/Login Security, §2.7 Guest Account and Sharing Services in `docs/HARDENING.md` -- comprehensive sharing services disable (File Sharing, Remote Apple Events, etc.) per FR-073/SC-033; Screen Sharing/VNC hardening (require macOS account auth not legacy VNC password, SSH tunneling) per FR-069; memory/swap encryption verification, hibernation mode, core dump disable per FR-068/SC-031; multi-operator shared Mac Mini scenario (designate security owner, non-admin accounts for daily use)
- [x] T012 [P] [US1] Write §2.8 Lockdown Mode, §2.9 Recovery Mode Password in `docs/HARDENING.md` -- Lockdown Mode per FR-062 with compatibility warning for Colima/Docker/n8n web UI, recovery mode `[EDUCATIONAL]` tag per plan.md Article V exceptions, startup security levels per FR-076
- [x] T013 [P] [US1] Write §2.10 System Privacy and TCC in `docs/HARDENING.md` -- TCC permission audit and management per FR-050, system-level privacy hardening (disable Spotlight Suggestions, diagnostics sharing, Location Services, Siri) per FR-061, NTP/time synchronization verification per FR-074 (NTP placed here as OS-level system setting; plan.md does not explicitly map FR-074 to a section); Tahoe-specific TCC and Local Network Privacy changes per R-010
- [x] T014 [US1] Add §2 audit checks to `scripts/hardening-audit.sh` and update `scripts/CHK-REGISTRY.md`: CHK-FILEVAULT, CHK-FIREWALL, CHK-STEALTH, CHK-SIP, CHK-GATEKEEPER, CHK-AUTO-LOGIN, CHK-GUEST, CHK-SCREEN-LOCK, CHK-SHARING-*, CHK-CORE-DUMPS, CHK-TCC, CHK-NTP, CHK-PRIVACY (13+ checks, severity assignments per data-model.md)

**Checkpoint**: macOS OS foundation is hardened. Audit script verifies core OS controls. Running check count: ~17.

---

## Phase 4: §3 Network Security (US-1)

**Goal**: Harden network attack surface (SSH, DNS, outbound filtering, Bluetooth, IPv6, service binding, lateral movement defense)

**Independent Test**: Follow §3 on MacBook. Verify SSH key auth only, encrypted DNS via Quad9, Bluetooth hardened, no unexpected listeners via `lsof -iTCP -sTCP:LISTEN`, AirDrop/Handoff disabled

- [ ] T015 [P] [US1] Write §3.1 SSH Hardening, §3.2 DNS Security in `docs/HARDENING.md` -- SSH hardening per FR-028 (key-only auth, disable root, AllowUsers, ed25519), DNS security per FR-029 (DoH/DoT via Quad9), SSH lockout warning BEFORE disabling password auth (ordering dependency from FR-009) per SC-024, DNS query logging for exfiltration detection per SC-038
- [ ] T016 [P] [US1] Write §3.3 Outbound Filtering in `docs/HARDENING.md` -- per FR-030 (pf/LuLu/Little Snitch), FR-032 (IDS integration); separate approaches by deployment path: macOS pf rules for bare-metal, iptables inside Colima VM for containerized per research.md R-008/R-013; LuLu for host-level; Little Snitch `[PAID]` ~$59 comparison; Lima provisioning script for iptables persistence
- [ ] T017 [P] [US1] Write §3.4 Bluetooth, §3.5 IPv6, §3.6 Service Binding and Port Exposure in `docs/HARDENING.md` -- Bluetooth "keep on but harden" path for keyboard/mouse (FR-002 control area), IPv6 disable or dual-stack pf rules per FR-052, listening service baseline and network service binding audit per FR-075/FR-079, listening service baseline creation per SC-037
- [ ] T018 [P] [US1] Write lateral movement defense content in `docs/HARDENING.md` §3.3 or §3.6 -- network segmentation recommendations per FR-042, AirDrop/Handoff disable, mDNS/Bonjour restriction, Wi-Fi vs Ethernet security, bi-directional lateral movement defense (protect Mac Mini from LAN + prevent compromised Mac Mini from attacking LAN)
- [ ] T019 [US1] Add §3 audit checks to `scripts/hardening-audit.sh` and update `scripts/CHK-REGISTRY.md`: CHK-SSH-KEY-ONLY, CHK-SSH-ROOT, CHK-DNS-ENCRYPTED, CHK-BLUETOOTH, CHK-IPV6, CHK-LISTENERS-BASELINE, CHK-AIRDROP (7+ checks)

**Checkpoint**: Network attack surface minimized. Outbound filtering active per deployment path. Running check count: ~24.

---

## Phase 5: §4 Container Isolation (US-1, US-5)

**Goal**: Deploy n8n in a hardened Docker container via Colima with security annotations, Docker secrets, and localhost-only binding

**Independent Test**: Run `colima start && docker compose up` using the reference compose file. From inside the container, verify host filesystem not accessible, host network services not reachable, credentials provided via Docker secrets (not env vars visible in `docker inspect`)

- [ ] T020 [US5] Write §4.1 Colima Setup, §4.2 Docker Security Principles in `docs/HARDENING.md` -- Colima as primary runtime per FR-017, container isolation principles per FR-016 (non-root, read-only FS, no privileged, localhost ports, Docker secrets, resource limits), Colima install via Homebrew, minimal security defaults per research.md R-007, VM security per FR-048: SSH access verification, filesystem sharing restrictions (WARN if home directory fully shared), resource limits, VM update cadence, VM disk encryption; Docker socket never mounted per SC-017
- [ ] T021 [US5] Create `scripts/templates/docker-compose.yml` with security annotations per SC-027: non-root user, `read_only: true`, `cap_drop: ALL`, `security_opt: no-new-privileges`, localhost-only port mapping (`127.0.0.1:5678:5678`), Docker secrets via `file:` source per research.md R-012, named volumes for persistence, no Docker socket mount, `deploy.resources.limits` (memory, CPU), `restart: unless-stopped` per FR-058; include placeholder comments for security env vars from Phase 6
- [ ] T022 [P] [US5] Create `scripts/templates/n8n-entrypoint.sh` wrapper for Docker secrets that don't support `_FILE` suffix per research.md R-001 (N8N_ENCRYPTION_KEY bug workaround): read from `/run/secrets/`, export as env var, exec n8n
- [ ] T023 [US5] Write §4.3 Reference docker-compose.yml walkthrough, §4.4 Advanced Container Hardening (capabilities, seccomp), §4.5 Container Networking in `docs/HARDENING.md` -- annotated compose file explanation, advanced hardening per FR-041 (cap-drop ALL, seccomp, no-new-privileges, minimal image), troubleshooting each security option without removing it per SC-030, iptables persistence via Lima provisioning per research.md R-013; include FR-090 educational content (`docker inspect` credential exposure, `ps aux` argument exposure, Docker log credential leakage); NOTE: T026 may update docker-compose.yml with security env vars — walkthrough may need minor update after Phase 6
- [ ] T024 [US5] Add §4 audit checks to `scripts/hardening-audit.sh` and update `scripts/CHK-REGISTRY.md`: CHK-CONTAINER-ROOT, CHK-CONTAINER-READONLY, CHK-CONTAINER-CAPS, CHK-CONTAINER-PRIVILEGED, CHK-DOCKER-SOCKET, CHK-SECRETS-ENV, CHK-COLIMA-MOUNTS (7 containerized-only checks per data-model.md)

**Checkpoint**: Containerized n8n deployment complete and auditable. Running check count: ~30.

---

## Phase 6: §5 n8n Platform Security (US-1, US-4)

**Goal**: Lock down n8n: binding, auth, 2FA, env vars, API, webhooks, execution model, community nodes, reverse proxy, updates

**Independent Test**: Default n8n install hardened per §5. Verify n8n bound to 127.0.0.1, auth enabled with TOTP 2FA, encryption key secured, API disabled or authenticated, dangerous nodes blocked via NODES_EXCLUDE

- [ ] T025 [P] [US4] Write §5.1 Binding and Authentication, §5.2 User Management in `docs/HARDENING.md` -- n8n binding and auth per FR-011 (localhost binding, auth, credential encryption), user management per FR-067 (owner account, role separation, MFA/TOTP), N8N_HOST=127.0.0.1, auth enable, native TOTP 2FA per research.md R-002, multi-user caveats (no workflow-level isolation between users)
- [ ] T026 [P] [US4] Write §5.3 Security Environment Variables, §5.4 REST API Security in `docs/HARDENING.md` -- env var reference per FR-059/SC-028 with corrected names: `N8N_PUBLIC_API_DISABLED=true` (not ENABLED), `EXECUTIONS_PROCESS` removed in v2.0, `N8N_BLOCK_ENV_ACCESS_IN_NODE` defaults true per research.md R-003; REST API security per FR-038 (disable or require key auth), API disable or auth per SC-020; update `scripts/templates/docker-compose.yml` with security env vars discovered during this task
- [ ] T027 [P] [US4] Write §5.5 Webhook Security, §5.6 Execution Model and Node Isolation in `docs/HARDENING.md` -- webhook security per FR-039 (auth, unpredictable paths, rate limiting)/FR-060 (Apify actor webhook signing), execution model per FR-021 (injection defense via Code nodes)/FR-044 (n8n execution model, env var block, file access restrict); webhook auth methods (None/Basic/Header/JWT) per research.md R-005, Apify URL tokens (no HMAC) per research.md R-009, NODES_EXCLUDE per research.md R-004, Code node env access attack chain, n8n process isolation limitations
- [ ] T028 [P] [US4] Write §5.7 Community Node Vetting, §5.8 Reverse Proxy, §5.9 Update and Migration Security in `docs/HARDENING.md` -- community node vetting per FR-054 (source repo, maintainer, dependencies, code review), vetting checklist per SC-018, `--ignore-scripts` for npm; reverse proxy per FR-055: SSH tunneling, webhook-only exposure, containerized reverse proxy (Caddy vs nginx, free-first) in same Compose stack; update/migration per FR-064: pre-update backup, post-update env var verification, containerized update procedure, bare-metal update procedure, rollback procedure
- [ ] T029 [US4] Add §5 audit checks to `scripts/hardening-audit.sh` and update `scripts/CHK-REGISTRY.md`: CHK-N8N-BIND, CHK-N8N-AUTH, CHK-N8N-API, CHK-N8N-ENV-BLOCK, CHK-N8N-ENV-DIAGNOSTICS, CHK-N8N-ENV-API, CHK-N8N-NODES, CHK-N8N-WEBHOOK (8+ checks)

**Checkpoint**: n8n is secured as highest-risk component. Running check count: ~38.

---

## Phase 7: §6 Bare-Metal Path (US-1)

**Goal**: Provide complete alternative deployment without containers: dedicated service account, Keychain, launchd, filesystem permissions

**Independent Test**: Create `_n8n` service account, restrict permissions, run n8n via launchd. Verify n8n process cannot access operator's home directory, Keychain, or SSH keys per SC-015

- [ ] T030 [P] [US1] Write §6.1 Dedicated Service Account, §6.2 Keychain Integration in `docs/HARDENING.md` -- service account per FR-036 (dedicated `_n8n` user), Keychain per FR-051 (separate Keychain, ACLs, lock behavior); `sysadminctl -addUser _n8n` with no home directory shell, separate Keychain with explicit ACLs, headless Keychain prompt behavior; blast radius limited to n8n data dir per SC-015
- [ ] T031 [P] [US1] Write §6.3 launchd Execution, §6.4 Filesystem Permissions in `docs/HARDENING.md` -- launchd and file permissions per FR-036 (service account isolation), launchd plist running n8n as `_n8n` user, restrictive directory permissions (700/600), temp file isolation, no command-line secrets per SC-043
- [ ] T032 [US1] Add §6 audit checks to `scripts/hardening-audit.sh` and update `scripts/CHK-REGISTRY.md`: CHK-SERVICE-ACCOUNT, CHK-SERVICE-HOME-PERMS, CHK-SERVICE-DATA-PERMS (3 bare-metal-only checks)

**Checkpoint**: Bare-metal path independently complete. Both deployment paths fully documented per SC-009. Running check count: ~41.

---

## Phase 8: §7 Data Security (US-1, US-7)

**Goal**: Protect credentials, defend against injection from scraped LinkedIn data, secure PII, prevent SSRF and data exfiltration, harden supply chain, secure temp files and metadata

**Independent Test**: Audit a test n8n workflow with scraped data flowing to a Code node. Verify injection patterns identified per SC-012 checklist. Confirm credential storage uses Docker secrets (containerized) or Keychain (bare-metal), not env vars visible in process listings

- [ ] T033 [P] [US1] Write §7.1 Credential Management, §7.2 Credential Lifecycle in `docs/HARDENING.md` -- credential management per FR-012/FR-057 (storage patterns, runtime access, Keychain lock behavior), credential lifecycle per FR-043 (rotation schedule, expiry detection, revocation), credential inventory template (cross-ref Appendix B), per-path storage (Docker secrets vs Keychain), Bitwarden CLI as free credential management option per FR-012, rotation schedule for all credential types per SC-019, credential reuse warning per SC-023
- [ ] T034 [P] [US7] Write §7.3 Scraped Data Input Security (Injection Defense) in `docs/HARDENING.md` -- injection defense per FR-021 (prompt injection, command injection, code injection, detection); concrete attack chain: scraped LinkedIn profile with shell metacharacters in job title flows to Code node via string interpolation = RCE; node type audit checklist (Code, Execute Command, LLM with tool-calling); safe patterns; monitoring for injection indicators per SC-012
- [ ] T035 [P] [US1] Write §7.4 PII Protection, §7.5 SSRF Defense in `docs/HARDENING.md` -- PII protection per FR-013 (data classification, minimization, retention, deletion), SSRF defense per FR-047 (HTTP Request node, internal targets, pf/Docker rules); data flow map showing PII at rest and in transit per SC-026, GDPR/CCPA/LinkedIn ToS obligations, execution log retention as PII concern, SSRF via Docker bridge/host gateway/metadata endpoints per SC-022, Spotlight exclusions for n8n data directories per FR-086/SC-041
- [ ] T036 [P] [US1] Write §7.6 Data Exfiltration Prevention, §7.7 Supply Chain Integrity, §7.8 Apify Actor Security in `docs/HARDENING.md` -- data exfiltration per FR-049 (HTTP Request, email, Slack, DB nodes; outbound filtering as defense), Apify security per FR-060 (actor trust, scoped tokens, webhook signing); HTTP Request node data leakage via attacker URLs, Docker Content Trust (`DOCKER_CONTENT_TRUST=1`) per FR-040, Docker image digest pinning and `docker history` layer inspection per FR-089, Homebrew tap verification, npm `--ignore-scripts` per SC-018, Apify actor vetting and URL-token webhook auth per research.md R-009, image scanning schedule per FR-089
- [ ] T037 [P] [US1] Write §7.9 Secure Deletion, §7.10 Clipboard Security in `docs/HARDENING.md` -- APFS/SSD copy-on-write limitations, crypto-shredding as only reliable method, Time Machine snapshot PII retention per FR-083, clipboard hygiene during credential operations per FR-087, temp file and cache security (`/var/folders/`, n8n temp, Docker build cache) per FR-082
- [ ] T038 [US1] Add §7 audit checks to `scripts/hardening-audit.sh` and update `scripts/CHK-REGISTRY.md`: CHK-CRED-ENV-VISIBLE, CHK-DOCKER-INSPECT-SECRETS, CHK-SPOTLIGHT-EXCLUSIONS, CHK-CONFIG-PROFILES (4+ checks)

**Checkpoint**: Data security layer complete. Operator can audit workflows for injection and manage credentials securely. Running check count: ~45.

---

## Phase 9: §8 Detection and Monitoring (US-1, US-3)

**Goal**: Deploy IDS tools, set up logging, establish baselines for persistence mechanisms, listeners, workflows, and certificates; deploy canary/tripwire detection

**Independent Test**: Install Santa, BlockBlock, LuLu per §8. Create persistence and listener baselines. Verify tool comparisons include `[PAID]` tags with approximate costs and free alternatives per SC-005

- [ ] T039 [P] [US3] Write §8.1 IDS Tools in `docs/HARDENING.md` -- IDS tools per FR-032 (Santa, BlockBlock, LuLu, KnockKnock), continuous monitoring gap coverage per SC-029; Santa (`northpolesec/santa` per research.md R-006), BlockBlock, LuLu, KnockKnock (all Apple Silicon per research.md R-011); ClamAV (free) vs SentinelOne `[PAID]` ~$5/mo comparison per US-3; cross-ref tool comparison matrix in Appendix D
- [ ] T040 [P] [US1] Write §8.2 Launch Daemon and Persistence Auditing in `docs/HARDENING.md` -- launch daemon baseline per FR-033 (drift detection), comprehensive persistence audit covering ALL types (launch daemons/agents, cron, login items, authorization plugins, shell profiles, periodic scripts, XPC services, configuration profiles per FR-085) per SC-032/FR-070; baseline creation and drift detection
- [ ] T041 [P] [US1] Write §8.3 Workflow Integrity Monitoring in `docs/HARDENING.md` -- workflow baseline hashing with SHA256 manifest per SC-021/FR-046, detecting unauthorized workflow modifications (attacker persistence via scheduled workflows), baseline regeneration after intentional changes
- [ ] T042 [P] [US1] Write §8.4 macOS Logging, §8.5 Credential Exposure Monitoring in `docs/HARDENING.md` -- unified log predicates, DNS query logging and anomalous pattern detection per SC-038/FR-080, log integrity (hash chain, permissions, external forwarding) per SC-039/FR-081, continuous monitoring via persistent `log stream` launchd jobs per FR-063, create log review command/script for periodic security event extraction per FR-035
- [ ] T043 [P] [US1] Write §8.6 iCloud and Cloud Service Exposure, §8.7 Certificate Trust Monitoring in `docs/HARDENING.md` -- iCloud services disable (except Find My Mac) per SC-034/FR-071, certificate trust store baseline and drift detection per SC-040/FR-084
- [ ] T044 [P] [US1] Write canary and tripwire detection content in `docs/HARDENING.md` §8.5 Credential Exposure Monitoring -- canary files in sensitive directories, honey credentials, canary DNS hostnames per FR-088/SC-042; monitoring for canary access as independent compromise detection layer
- [ ] T045 [US1] Add §8 audit checks to `scripts/hardening-audit.sh` and update `scripts/CHK-REGISTRY.md`: CHK-SANTA, CHK-BLOCKBLOCK, CHK-LULU, CHK-CLAMAV, CHK-PERSISTENCE-BASELINE, CHK-WORKFLOW-BASELINE, CHK-LISTENER-BASELINE, CHK-CERT-BASELINE, CHK-CLAMAV-SIGS, CHK-ICLOUD-KEYCHAIN, CHK-ICLOUD-DRIVE, CHK-CANARY (12+ checks)

**Checkpoint**: Detection layer deployed. Baselines established for drift detection. Running check count: ~57.

---

## Phase 10: §9 Response and Recovery (US-1, US-9)

**Goal**: Provide actionable incident response runbook, credential rotation procedures, backup/recovery, restore testing, and physical security guidance

**Independent Test**: Simulate a compromise (add unauthorized launch agent, modify an n8n workflow). Follow IR runbook. Verify containment, evidence preservation, and recovery to known-good state per SC-025

- [ ] T046 [P] [US9] Write §9.1 Incident Response Runbook in `docs/HARDENING.md` -- per FR-031: triage steps for uncertain incidents, severity classification, containment (stop n8n + network isolation), evidence preservation with chain of custody (logs, filesystem snapshots, timeline reconstruction), credential blast radius assessment (which credentials were accessible from compromised component), when to engage external help (forensics firm, legal counsel, law enforcement thresholds), post-incident review process (root cause, timeline, remediation verification, lessons learned); cross-reference to §8 detection sources, breach notification obligations (GDPR/CCPA/LinkedIn ToS timelines) per SC-025
- [ ] T047 [P] [US9] Write §9.2 Credential Rotation Procedures in `docs/HARDENING.md` -- emergency rotation runbook per FR-077 `[EDUCATIONAL]`: dependency-ordered rotation for every credential in inventory (N8N_ENCRYPTION_KEY must re-encrypt DB first), per-credential instructions (where to change, what breaks, how to verify), 2-hour completion target per SC-035, practice run recommendation
- [ ] T048 [P] [US9] Write §9.3 Backup and Recovery, §9.4 Restore Testing in `docs/HARDENING.md` -- backup strategy per FR-018 (Docker volume export, n8n workflow export, Time Machine, RPO/RTO), restore testing per FR-037 (non-destructive verify, quarterly schedule, backup encryption key safety); backup encryption and access control (600 permissions, service account cannot read backups) per FR-045, backup integrity verification (SHA256 checksums) per FR-045, offsite backup security, restore procedure under 30 min per SC-016, emergency rebuild from scratch when all backups corrupted, corrupted backup diagnosis
- [ ] T049 [P] [US9] Write §9.5 Physical Security in `docs/HARDENING.md` -- physical security per FR-034 (USB/Thunderbolt restriction, accessory security)/FR-053 (Find My Mac, cable lock, post-theft procedure); Find My Mac (with Apple ID 2FA risk tradeoff), USB/Thunderbolt restriction policy `[EDUCATIONAL]`, post-theft credential rotation procedure, firmware password for Intel Target Disk Mode
- [ ] T050 [US9] Add §9 audit checks to `scripts/hardening-audit.sh` and update `scripts/CHK-REGISTRY.md`: CHK-BACKUP-CONFIGURED, CHK-BACKUP-ENCRYPTED, CHK-FIND-MY-MAC, CHK-USB (4+ checks)

**Checkpoint**: Respond layer complete. IR runbook is actionable without consulting external docs. Running check count: ~60.

---

## Phase 11: §10 Operational Maintenance (US-1, US-6, US-8)

**Goal**: Automate security maintenance: scheduled audits via launchd, failure notifications (email + local fallback), tool updates, log rotation, post-update checklist, hardening validation tests

**Independent Test**: Configure launchd audit job and notification per §10. Deliberately disable firewall. Wait for scheduled audit. Verify FAIL notification received listing which checks failed and which guide sections to consult per US-8 acceptance scenarios

- [ ] T051 [US8] Write §10.1 Automated Audit Scheduling in `docs/HARDENING.md` -- scheduled audit per FR-022 (weekly default, unattended, timestamped logs); launchd plist configuration, `StartCalendarInterval` behavior during sleep (runs at next wake), timestamped log output, `launchctl load` instructions; fully unattended after setup per SC-014
- [ ] T052 [US8] Create `scripts/launchd/com.openclaw.audit.plist` -- launchd plist template for scheduled weekly audit runs, configurable schedule, log output to timestamped file in audit log directory
- [ ] T053 [US8] Write §10.2 Notification Setup in `docs/HARDENING.md` -- msmtp for email alerts (SMTP relay dependency), macOS Notification Center fallback via `osascript`, webhook notification as advanced option per FR-024, FAIL-only active alerts with explicit filtering logic (parse audit JSON output, check for FAIL count > 0, only then notify) per FR-025/SC-013, local log fallback when email fails
- [ ] T054 [US8] Create `scripts/launchd/com.openclaw.notify.plist` -- launchd plist for notification delivery triggered by audit FAIL results, includes the FAIL-only filtering logic; NOTE: depends on T053 notification design (email method, webhook URL, alert threshold) — not parallelizable
- [ ] T055 [P] [US6] Write §10.3 Tool Maintenance, §10.4 Log Retention and Rotation in `docs/HARDENING.md` -- tool maintenance per FR-020 (re-audit schedule, configuration drift after macOS updates)/FR-026 (ClamAV freshclam, brew outdated), log retention per FR-027 (90-day retention, newsyslog rotation, meta-audit); ClamAV freshclam schedule, `brew update` cadence, n8n update procedure with post-update env var verification, tool update checking embedded in audit script checks (CHK-CLAMAV-FRESHNESS etc.) not a separate launchd plist, comprehensive post-update checklist per SC-010
- [ ] T056 [P] [US1] Write §10.5 Troubleshooting Common Failures in `docs/HARDENING.md` -- per-failure-mode entries for both deployment paths: container startup failures (read_only, cap_drop, no-new-privileges), service account permission errors, SSH lockout recovery, firewall conflicts, Keychain prompts on headless server; each entry resolves without removing the security control per SC-030/FR-066
- [ ] T057 [P] [US1] Write hardening validation tests content in `docs/HARDENING.md` §10.6 Hardening Validation Tests -- safe, non-destructive test procedures per FR-078/SC-036: firewall validation (attempt blocked connection), outbound filtering validation, n8n auth validation (attempt unauthenticated access), container isolation validation (attempt host filesystem access from container), injection defense validation (benign test payload), persistence detection validation (add test launch agent)
- [ ] T058 [US8] Add §10 audit checks to `scripts/hardening-audit.sh` and update `scripts/CHK-REGISTRY.md`: CHK-LAUNCHD-AUDIT-JOB, CHK-NOTIFICATION-CONFIG, CHK-LOG-DIR, CHK-CLAMAV-FRESHNESS (4+ checks including self-check per FR-027 -- verify own scheduled execution and log directory are intact)

**Checkpoint**: Automated monitoring active. Operator receives FAIL-only notifications. 15 min/month maintenance burden per SC-013. Running check count: ~64.

---

## Phase 12: §11 Audit Script Reference + Appendices (US-1, US-2)

**Goal**: Complete audit script documentation, finalize all checks, and provide operator reference appendices

**Independent Test**: Run `hardening-audit.sh` on unhardened MacBook. Verify it reports FAIL for every critical control, SKIP for missing tools, correct guide section references for remediation, and `--json` output matches schema per US-2 acceptance scenarios

- [ ] T059 [US2] Write §11.1 Running the Audit Script, §11.2 Check Reference Table, §11.3 JSON Output Schema, §11.4 Interpreting Results in `docs/HARDENING.md` -- document every CHK-* ID from `scripts/CHK-REGISTRY.md` with severity, deployment path, description, and guide section reference; JSON schema per `contracts/audit-script-cli.md`; interpretation guidance (all-PASS does not mean uncompromised); audit script limitations per FR-065, validation guidance per FR-056
- [ ] T060 [US2] Finalize `scripts/hardening-audit.sh`: verify all checks from §2-§10 are wired up against `scripts/CHK-REGISTRY.md`, JSON output validates against documented schema, `--section` filter correctly limits checks, exit codes correct (0=all pass, 1=any fail, 2=script error)
- [ ] T061 [P] [US1] Write Appendix A: Complete Security Environment Variable Reference in `docs/HARDENING.md` -- all n8n security env vars with recommended values, risk explanations, and corrected names per research.md R-003; satisfies SC-028 (comprehensive env var reference)
- [ ] T062 [P] [US1] Write Appendix B: Credential Inventory Template in `docs/HARDENING.md` -- all known credentials per data-model.md (N8N_ENCRYPTION_KEY, LinkedIn session token, Apify API key, SSH key, SMTP credentials, n8n API key, JWT secret, Docker registry creds), storage locations per path, rotation intervals, blast radius
- [ ] T063 [P] [US1] Write Appendix C: Incident Response Checklist in `docs/HARDENING.md` -- condensed, printable checklist version of §9.1 runbook for use under time pressure per SC-025
- [ ] T064 [P] [US3] Write Appendix D: Tool Comparison Matrix in `docs/HARDENING.md` -- all tools from data-model.md Security Tool inventory with cost, function, defensive layer, `[PAID]` alternatives, and free alternatives per SC-005
- [ ] T065 [P] [US1] Write Appendix E: PII Data Classification Table in `docs/HARDENING.md` -- LinkedIn data fields (full_name, email, phone, job_title, etc.) with sensitivity classification, storage locations, retention recommendations, GDPR relevance per data-model.md PII entity; satisfies SC-026 (data flow map and retention)

**Checkpoint**: Audit script is complete with 64+ checks. All appendices provide self-contained operator reference material.

---

## Phase 13: Polish and Cross-Cutting Concerns

**Purpose**: Quality gates, cross-cutting validation, final integration

- [ ] T066 Verify all `[PAID]` tool mentions in `docs/HARDENING.md` include approximate cost and free alternative per FR-005, FR-006, SC-005
- [ ] T067 [P] Verify all control sections in `docs/HARDENING.md` follow CIS pattern (Threat/Why/How/Verify/Edge Cases) per `contracts/guide-structure.md` section format; verify all infrastructure instructions are CLI-only per FR-019; verify n8n CLI alternatives (`n8n export`, `n8n import`) are documented per FR-019
- [ ] T068 [P] Verify both deployment paths in `docs/HARDENING.md` are independently complete -- operator can follow either containerized or bare-metal without referencing the other per SC-009
- [ ] T069 [P] Run `shellcheck --severity=warning scripts/hardening-audit.sh` and fix all warnings per SC-008
- [ ] T070 [P] Run `npx markdownlint-cli2 docs/HARDENING.md` and fix all errors per FR-014, SC-007
- [ ] T071 Verify FR coverage: all 90 FRs across 4 spec modules are addressed in `docs/HARDENING.md` per SC-001 (39 control areas, zero gaps); also verify SC-002 (100% canonical source citations) and SC-003 (100% verification methods)
- [ ] T072 Verify all 43 success criteria (SC-001 through SC-043) pass against `docs/HARDENING.md` and `scripts/hardening-audit.sh`
- [ ] T073 Verify `scripts/CHK-REGISTRY.md` is complete: all CHK-* IDs in the audit script match the registry, no duplicates, no gaps, counts meet SC-004 (60+ total, 10+ container-specific)
- [ ] T074 [P] Verify Tahoe vs Sonoma callouts per research.md R-010 appear in all 6 affected areas (Gatekeeper, SIP, TCC, Local Network Privacy, background services, firewall) across `docs/HARDENING.md`
- [ ] T075 Run full `scripts/hardening-audit.sh` on hardened MacBook and verify zero FAIL results per US-1 acceptance scenario #1; validates SC-006 (operator can follow end-to-end without external docs)

---

## Dependencies and Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies -- start immediately
- **§1 Threat Model (Phase 2)**: Depends on Phase 1 (guide skeleton)
- **§2-§10 (Phases 3-11)**: Each depends on Phase 1 (guide skeleton + audit framework + CHK registry); sections are independent of each other and CAN proceed in parallel, but the MacBook validation strategy recommends sequential order so each section is tested on real hardware before the next begins
- **§11 + Appendices (Phase 12)**: Depends on Phases 3-11 (all audit checks must exist before reference documentation; T059 uses CHK-REGISTRY.md as source of truth)
- **Polish (Phase 13)**: Depends on all content phases complete

### Cross-Phase Artifact Dependencies

- **`scripts/templates/docker-compose.yml`**: Created in T021 (Phase 5), updated in T026 (Phase 6) when security env vars are discovered. T026 must explicitly update the compose file.
- **`scripts/CHK-REGISTRY.md`**: Created in T005 (Phase 1), updated by every audit check task (T014, T019, T024, T029, T032, T038, T045, T050, T058). T059 (Phase 12) uses it as source of truth. T073 (Phase 13) validates completeness.
- **`docs/HARDENING.md`**: Written sequentially by all guide tasks. Tasks marked [P] within a phase write to independent sections of the same file -- true parallelism requires merge capability or sequential execution within the file.

### User Story Coverage

| Story | Priority | Primary Phases | Key Tasks |
|-------|----------|---------------|-----------|
| US-1: Harden Fresh Mac | P1 | ALL phases | T006-T019, T030-T032, T040-T041, T044, T056-T057, T061-T063, T065 |
| US-2: Audit Existing Mac | P2 | Phase 12 | T059-T060 + all audit check tasks (T014, T019, T024, T029, T032, T038, T045, T050, T058) |
| US-3: Evaluate Free vs Paid | P2 | Phases 9, 12, 13 | T039, T064, T066 |
| US-4: Secure n8n | P1 | Phase 6 | T025-T029 |
| US-5: Container Isolation | P1 | Phase 5 | T020-T024 |
| US-6: Maintain Over Time | P2 | Phase 11 | T055 |
| US-7: Injection Defense | P1 | Phase 8 | T034 |
| US-8: Automated Monitoring | P2 | Phase 11 | T051-T054, T058 |
| US-9: Incident Response | P2 | Phase 10 | T046-T050 |

### Within Each Phase

1. Guide subsections marked [P] within a phase write to independent sections of `docs/HARDENING.md` -- can run in parallel if implementer can merge, otherwise run sequentially
2. Audit check tasks depend on their section's guide content being written first (verification commands come from the guide)
3. Every audit check task must update `scripts/CHK-REGISTRY.md` alongside `scripts/hardening-audit.sh`
4. Supporting files (docker-compose.yml, plists, entrypoint.sh) can be written in parallel with guide content

### Parallel Opportunities

- **Phase 1**: T003 || T004 || T005
- **Phase 2**: T006 || T007 || T008
- **Phase 3**: T009 || T010 || T011 || T012 || T013, then T014
- **Phase 4**: T015 || T016 || T017 || T018, then T019
- **Phase 5**: T020 || T021 || T022, then T023, then T024
- **Phase 6**: T025 || T026 || T027 || T028, then T029
- **Phase 7**: T030 || T031, then T032
- **Phase 8**: T033 || T034 || T035 || T036 || T037, then T038
- **Phase 9**: T039 || T040 || T041 || T042 || T043 || T044, then T045
- **Phase 10**: T046 || T047 || T048 || T049, then T050
- **Phase 11**: T051 || T055 || T056 || T057, then T052, then T053, then T054, then T058
- **Phase 12**: T061 || T062 || T063 || T064 || T065 (all appendices parallel), T059 then T060
- **Phase 13**: T067 || T068 || T069 || T070 || T074

---

## Parallel Example: Phase 5 (Container Isolation)

```text
# Round 1 -- start in parallel (different files or independent sections):
Task T020: "Write §4.1-§4.2 in docs/HARDENING.md"
Task T021: "Create scripts/templates/docker-compose.yml"
Task T022: "Create scripts/templates/n8n-entrypoint.sh"

# Round 2 -- after T020-T022 complete (references compose file):
Task T023: "Write §4.3-§4.5 in docs/HARDENING.md"

# Round 3 -- after T023 complete (needs verification commands):
Task T024: "Add §4 audit checks to scripts/hardening-audit.sh"
```

---

## Implementation Strategy

### MVP First (Phases 1-2)

1. Complete Phase 1: Setup -- guide skeleton + audit framework + CHK registry
2. Complete Phase 2: §1 Threat Model + Preamble
3. **STOP and VALIDATE**: Operator reads threat model and preamble for accuracy
4. This establishes the tone, structure, and delivery cadence for all subsequent sections

### Section-by-Section Delivery (Phases 3-12)

1. Each phase = one PR = one guide section + corresponding audit checks + CHK registry update + supporting files
2. After each PR merges, operator follows the section on the fresh Sonoma MacBook
3. MacBook gets Homebrew, git, Colima, etc. ONLY after reading the hardening guidance for that tool
4. The fresh MacBook state IS the integration test -- operator literally IS US-1
5. Audit script grows incrementally (new checks added with each section)
6. Running check count tracked at each phase checkpoint to catch SC-004 shortfalls early
7. Context window is never overwhelmed (one section at a time)

### PR Sequence

| PR | Phase | Content | MacBook Validates |
|----|-------|---------|-------------------|
| 1 | 1-2 | Setup + §1 Threat Model + Preamble | N/A (narrative) |
| 2 | 3 | §2 OS Foundation | FileVault, firewall, SIP, Gatekeeper, TCC, NTP |
| 3 | 4 | §3 Network Security | SSH, DNS, pf/iptables, lateral movement |
| 4 | 5 | §4 Container Isolation | Colima install, Docker hardening |
| 5 | 6 | §5 n8n Platform Security | n8n deploy, env vars, webhooks |
| 6 | 7 | §6 Bare-Metal Path | Service account, Keychain |
| 7 | 8 | §7 Data Security | Credentials, injection, PII, temp files |
| 8 | 9 | §8 Detection and Monitoring | Santa, BlockBlock, LuLu, baselines, canary |
| 9 | 10 | §9 Response and Recovery | IR runbook, backups |
| 10 | 11 | §10 Operational Maintenance | launchd scheduling, notifications, validation tests |
| 11 | 12 | §11 Audit Script Ref + Appendices | Full audit run |
| 12 | 13 | Polish | Final cross-cutting validation |

---

## Known Risks

- **Same-file parallelism**: Tasks marked [P] within a phase write to independent sections of `docs/HARDENING.md` or `scripts/hardening-audit.sh`. True parallel execution requires merge capability. For serial LLM implementation, run [P] tasks sequentially within each phase.
- **WSL2 dev vs macOS target**: All audit script checks use macOS-only commands (`defaults`, `csrutil`, `fdesetup`, etc.) that cannot be tested on the dev machine. Bugs in check commands will surface during MacBook validation. Mitigate by referencing Apple man pages and CIS Benchmark expected output formats during implementation.
- **Tahoe vs Sonoma differences**: research.md R-010 identifies 6 areas with OS-specific behavior. Only T010 explicitly references R-010. Other tasks must check R-010 when writing macOS commands that may differ between versions.

---

## Notes

- [P] tasks = different files or independent sections, no dependencies on incomplete tasks
- [Story] label maps task to its primary user story for traceability
- No automated tests -- validation is manual (shellcheck, markdownlint, MacBook walkthrough)
- Each phase checkpoint = one PR merged + MacBook validation + running check count verified
- Research corrections (R-001 through R-013) are applied during implementation, not as separate tasks -- specific corrections are cited in relevant task descriptions
- Constitution compliance verified in Phase 13 (T067, T071, T072)
- Commit after each task or logical group within a phase
- Guide sections use `§` prefix to avoid confusion with spec `FR` prefix
