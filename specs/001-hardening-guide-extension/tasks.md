# Tasks: Hardening Guide Extension

**Input**: Design documents from `/specs/001-hardening-guide-extension/`
**Prerequisites**: plan.md, spec.md (Rev 29), research.md (13 items), data-model.md, contracts/ (audit-script-cli.md, guide-structure.md), quickstart.md

**Tests**: No automated tests requested. Validation is manual: `shellcheck` for the audit script, `markdownlint` for the guide, and section-by-section MacBook walkthrough (see plan.md Testing Strategy).

**Organization**: Tasks follow the section-by-section delivery strategy from plan.md. Each phase corresponds to one PR. User story tags indicate which story each task primarily serves. Since US-1 ("Operator Hardens a Fresh Mac Mini") spans the entire guide, it is implicit in all guide-writing tasks -- additional story tags indicate the most specific story served.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files or independent guide sections)
- **[Story]**: Which user story this task primarily serves (US1-US9)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create project directory structure, guide skeleton, and audit script framework

- [ ] T001 Create directory structure: `scripts/templates/` and `scripts/launchd/` directories per plan.md project structure
- [ ] T002 Create `docs/HARDENING.md` skeleton with preamble placeholder, all section heading stubs (SS1-SS11), and appendix headings (A-E) per `contracts/guide-structure.md`
- [ ] T003 [P] Create `scripts/hardening-audit.sh` framework with `set -euo pipefail`, CLI argument parsing (`--json`, `--section`, `--quiet`, `--no-color`, `--help`, `--version`), colored status output functions (PASS/FAIL/WARN/SKIP), deployment detection logic, `run_check` wrapper using subshell trap pattern, summary counters, and JSON output skeleton per `contracts/audit-script-cli.md`
- [ ] T004 [P] Add deprecation header to `docs/SONOMA-HARDENING.md` redirecting to `docs/HARDENING.md` SS2 per plan.md BS-10 resolution

**Checkpoint**: Guide skeleton and audit script framework ready. All subsequent phases build on these files.

---

## Phase 2: SS1 Threat Model + Preamble (US-1) -- MVP

**Goal**: Establish the threat model foundation and guide navigation structure

**Independent Test**: Read the threat model section and verify it names the specific platform (Mac Mini), workload (n8n + Apify), assets (credentials, PII, system integrity), and adversaries per FR-001

- [ ] T005 [US1] Write guide preamble in `docs/HARDENING.md`: purpose and scope, how to use this guide, deployment path decision tree (containerized vs bare-metal), cross-reference notation conventions (`SS X.Y`, `CHK-*`)
- [ ] T006 [US1] Write SS1 Threat Model in `docs/HARDENING.md`: platform description (Mac Mini + n8n + Apify + LinkedIn lead gen), assets to protect, adversary profiles, attack surface map, scope exclusions per FR-001
- [ ] T007 [US1] Write prioritized quick-start checklist in `docs/HARDENING.md` preamble: Immediate/Follow-up/Ongoing tiers with ordering constraints (SSH key before disabling password auth, Screen Sharing before disabling other remote access, FileVault authrestart before enabling FileVault, n8n auth before binding to network) and lockout warnings per FR-009

**Checkpoint**: Guide has navigable structure and threat context. MacBook operator can understand the deployment before hardening.

---

## Phase 3: SS2 OS Foundation (US-1)

**Goal**: Harden the macOS operating system foundation (FileVault, firewall, SIP, Gatekeeper, screen lock, guest/sharing, lockdown mode, recovery mode)

**Independent Test**: Follow SS2 on a fresh Sonoma MacBook and verify FileVault enabled, firewall on + stealth mode, SIP verified, guest disabled, auto-login off, sharing services disabled

- [ ] T008 [P] [US1] Write SS2.1 FileVault, SS2.2 Firewall, SS2.3 SIP in `docs/HARDENING.md` -- each with threat justification, canonical source citation, copy-pasteable CLI commands, verification command, and edge cases (FileVault `fdesetup authrestart` for headless reboot)
- [ ] T009 [P] [US1] Write SS2.4 Gatekeeper/XProtect, SS2.5 Software Updates in `docs/HARDENING.md` -- Tahoe vs Sonoma differences per research.md R-010, XProtect signature freshness check
- [ ] T010 [P] [US1] Write SS2.6 Screen Lock/Login Security, SS2.7 Guest Account and Sharing Services in `docs/HARDENING.md` -- comprehensive sharing services disable (File Sharing, Screen Sharing hardening, Remote Apple Events, etc.) per SC-033, process environment hardening (disable core dumps, command-line secret exposure)
- [ ] T011 [P] [US1] Write SS2.8 Lockdown Mode, SS2.9 Recovery Mode Password in `docs/HARDENING.md` -- Lockdown Mode compatibility warning with Colima/Docker/n8n web UI, recovery mode `[EDUCATIONAL]` tag per plan.md Article V exceptions
- [ ] T012 [US1] Add SS2 audit checks to `scripts/hardening-audit.sh`: CHK-FILEVAULT, CHK-FIREWALL, CHK-STEALTH, CHK-SIP, CHK-GATEKEEPER, CHK-AUTO-LOGIN, CHK-GUEST, CHK-SCREEN-LOCK, CHK-SHARING-* (9+ checks, severity assignments per data-model.md check categories)

**Checkpoint**: macOS OS foundation is hardened. Audit script verifies core OS controls.

---

## Phase 4: SS3 Network Security (US-1)

**Goal**: Harden network attack surface (SSH, DNS, outbound filtering, Bluetooth, IPv6, service binding)

**Independent Test**: Follow SS3 on MacBook. Verify SSH key auth only, encrypted DNS via Quad9, Bluetooth hardened, no unexpected listeners via `lsof -iTCP -sTCP:LISTEN`

- [ ] T013 [P] [US1] Write SS3.1 SSH Hardening, SS3.2 DNS Security in `docs/HARDENING.md` -- SSH lockout warning BEFORE disabling password auth (ordering dependency from FR-009), DoH/DoT via Quad9, DNS query logging for exfiltration detection per SC-038
- [ ] T014 [P] [US1] Write SS3.3 Outbound Filtering in `docs/HARDENING.md` -- separate approaches by deployment path: macOS pf rules for bare-metal, iptables inside Colima VM for containerized per research.md R-008/R-013; LuLu for host-level; Little Snitch `[PAID]` ~$59 comparison; Lima provisioning script for iptables persistence
- [ ] T015 [P] [US1] Write SS3.4 Bluetooth, SS3.5 IPv6, SS3.6 Service Binding and Port Exposure in `docs/HARDENING.md` -- Bluetooth "keep on but harden" path for keyboard/mouse, IPv6 disable or dual-stack pf rules, listening service baseline creation per SC-037
- [ ] T016 [US1] Add SS3 audit checks to `scripts/hardening-audit.sh`: CHK-SSH-KEY-ONLY, CHK-SSH-ROOT, CHK-DNS-ENCRYPTED, CHK-BLUETOOTH, CHK-IPV6, CHK-LISTENERS-BASELINE (6+ checks)

**Checkpoint**: Network attack surface minimized. Outbound filtering active per deployment path.

---

## Phase 5: SS4 Container Isolation (US-1, US-5)

**Goal**: Deploy n8n in a hardened Docker container via Colima with security annotations, Docker secrets, and localhost-only binding

**Independent Test**: Run `colima start && docker compose up` using the reference compose file. From inside the container, verify host filesystem not accessible, host network services not reachable, credentials provided via Docker secrets (not env vars visible in `docker inspect`)

- [ ] T017 [US5] Write SS4.1 Colima Setup, SS4.2 Docker Security Principles in `docs/HARDENING.md` -- Colima install via Homebrew, minimal security defaults per research.md R-007, VM security, Docker socket never mounted per SC-017
- [ ] T018 [US5] Create `scripts/templates/docker-compose.yml` with security annotations per SC-027: non-root user, `read_only: true`, `cap_drop: ALL`, `security_opt: no-new-privileges`, localhost-only port mapping (`127.0.0.1:5678:5678`), Docker secrets via `file:` source per research.md R-012, named volumes for persistence, no Docker socket mount
- [ ] T019 [P] [US5] Create `scripts/templates/n8n-entrypoint.sh` wrapper for Docker secrets that don't support `_FILE` suffix per research.md R-001 (N8N_ENCRYPTION_KEY bug workaround): read from `/run/secrets/`, export as env var, exec n8n
- [ ] T020 [US5] Write SS4.3 Reference docker-compose.yml walkthrough, SS4.4 Advanced Container Hardening (capabilities, seccomp), SS4.5 Container Networking in `docs/HARDENING.md` -- annotated compose file explanation, troubleshooting each security option without removing it per SC-030, iptables persistence via Lima provisioning per research.md R-013
- [ ] T021 [US5] Add SS4 audit checks to `scripts/hardening-audit.sh`: CHK-CONTAINER-ROOT, CHK-CONTAINER-READONLY, CHK-CONTAINER-CAPS, CHK-CONTAINER-PRIVILEGED, CHK-DOCKER-SOCKET, CHK-SECRETS-ENV (6 containerized-only checks per data-model.md)

**Checkpoint**: Containerized n8n deployment complete and auditable. `docker-compose.yml` is the security reference artifact.

---

## Phase 6: SS5 n8n Platform Security (US-1, US-4)

**Goal**: Lock down n8n: binding, auth, 2FA, env vars, API, webhooks, execution model, community nodes, reverse proxy, updates

**Independent Test**: Default n8n install hardened per SS5. Verify n8n bound to 127.0.0.1, auth enabled with TOTP 2FA, encryption key secured, API disabled or authenticated, dangerous nodes blocked via NODES_EXCLUDE

- [ ] T022 [P] [US4] Write SS5.1 Binding and Authentication, SS5.2 User Management in `docs/HARDENING.md` -- N8N_HOST=127.0.0.1, auth enable, native TOTP 2FA per research.md R-002, multi-user caveats (no workflow-level isolation between users)
- [ ] T023 [P] [US4] Write SS5.3 Security Environment Variables, SS5.4 REST API Security in `docs/HARDENING.md` -- comprehensive env var reference per SC-028 with corrected names: `N8N_PUBLIC_API_DISABLED=true` (not ENABLED), `EXECUTIONS_PROCESS` removed in v2.0, `N8N_BLOCK_ENV_ACCESS_IN_NODE` defaults true per research.md R-003; API disable or auth per SC-020
- [ ] T024 [P] [US4] Write SS5.5 Webhook Security, SS5.6 Execution Model and Node Isolation in `docs/HARDENING.md` -- webhook auth methods (None/Basic/Header/JWT) per research.md R-005, Apify URL tokens (no HMAC) per research.md R-009, NODES_EXCLUDE per research.md R-004, Code node env access attack chain, n8n process isolation limitations
- [ ] T025 [P] [US4] Write SS5.7 Community Node Vetting, SS5.8 Reverse Proxy, SS5.9 Update and Migration Security in `docs/HARDENING.md` -- vetting checklist per SC-018, `--ignore-scripts` for npm, Caddy vs nginx (free-first), post-update env var verification procedure
- [ ] T026 [US4] Add SS5 audit checks to `scripts/hardening-audit.sh`: CHK-N8N-BIND, CHK-N8N-AUTH, CHK-N8N-API, CHK-N8N-ENV-BLOCK, CHK-N8N-ENV-DIAGNOSTICS, CHK-N8N-ENV-API, CHK-N8N-NODES, CHK-N8N-WEBHOOK (8+ checks)

**Checkpoint**: n8n is secured as highest-risk component. Audit script detects misconfigured n8n instances.

---

## Phase 7: SS6 Bare-Metal Path (US-1)

**Goal**: Provide complete alternative deployment without containers: dedicated service account, Keychain, launchd, filesystem permissions

**Independent Test**: Create `_n8n` service account, restrict permissions, run n8n via launchd. Verify n8n process cannot access operator's home directory, Keychain, or SSH keys per SC-015

- [ ] T027 [P] [US1] Write SS6.1 Dedicated Service Account, SS6.2 Keychain Integration in `docs/HARDENING.md` -- `sysadminctl -addUser _n8n` with no home directory shell, separate Keychain with explicit ACLs, headless Keychain prompt behavior
- [ ] T028 [P] [US1] Write SS6.3 launchd Execution, SS6.4 Filesystem Permissions in `docs/HARDENING.md` -- launchd plist running n8n as `_n8n` user, restrictive directory permissions (700/600), temp file isolation, no command-line secrets per SC-043
- [ ] T029 [US1] Add SS6 audit checks to `scripts/hardening-audit.sh`: CHK-SERVICE-ACCOUNT, CHK-SERVICE-HOME-PERMS, CHK-SERVICE-DATA-PERMS (3 bare-metal-only checks)

**Checkpoint**: Bare-metal path independently complete. Both deployment paths fully documented per SC-009.

---

## Phase 8: SS7 Data Security (US-1, US-7)

**Goal**: Protect credentials, defend against injection from scraped LinkedIn data, secure PII, prevent SSRF and data exfiltration, harden supply chain

**Independent Test**: Audit a test n8n workflow with scraped data flowing to a Code node. Verify injection patterns identified per SC-012 checklist. Confirm credential storage uses Docker secrets (containerized) or Keychain (bare-metal), not env vars visible in process listings

- [ ] T030 [P] [US7] Write SS7.1 Credential Management, SS7.2 Credential Lifecycle in `docs/HARDENING.md` -- credential inventory template (cross-ref Appendix B), per-path storage (Docker secrets vs Keychain), rotation schedule for all credential types per SC-019, credential reuse warning per SC-023
- [ ] T031 [P] [US7] Write SS7.3 Scraped Data Input Security (Injection Defense) in `docs/HARDENING.md` -- concrete attack chain: scraped LinkedIn profile with shell metacharacters in job title flows to Code node via string interpolation = RCE; node type audit checklist (Code, Execute Command, LLM with tool-calling); safe patterns; monitoring for injection indicators per SC-012
- [ ] T032 [P] [US7] Write SS7.4 PII Protection, SS7.5 SSRF Defense in `docs/HARDENING.md` -- data flow map showing PII at rest and in transit per SC-026, GDPR/CCPA/LinkedIn ToS obligations, execution log retention as PII concern, SSRF via Docker bridge/host gateway/metadata endpoints per SC-022
- [ ] T033 [P] [US7] Write SS7.6 Data Exfiltration Prevention, SS7.7 Supply Chain Integrity, SS7.8 Apify Actor Security in `docs/HARDENING.md` -- HTTP Request node data leakage via attacker URLs, Docker image digest pinning, Homebrew tap verification, npm `--ignore-scripts` per SC-018, Apify actor vetting and URL-token webhook auth per research.md R-009
- [ ] T034 [P] [US7] Write SS7.9 Secure Deletion, SS7.10 Clipboard Security in `docs/HARDENING.md` -- APFS/SSD copy-on-write limitations, crypto-shredding as only reliable method, Time Machine snapshot PII retention, clipboard hygiene during credential operations
- [ ] T035 [US7] Add SS7 audit checks to `scripts/hardening-audit.sh`: CHK-CRED-ENV-VISIBLE, CHK-DOCKER-INSPECT-SECRETS, CHK-ICLOUD-KEYCHAIN, CHK-ICLOUD-DRIVE, CHK-SPOTLIGHT-EXCLUSIONS, CHK-CORE-DUMPS (6+ checks)

**Checkpoint**: Data security layer complete. Operator can audit workflows for injection and manage credentials securely.

---

## Phase 9: SS8 Detection and Monitoring (US-1, US-3)

**Goal**: Deploy IDS tools, set up logging, establish baselines for persistence mechanisms, listeners, workflows, and certificates

**Independent Test**: Install Santa, BlockBlock, LuLu per SS8. Create persistence and listener baselines. Verify tool comparisons include `[PAID]` tags with approximate costs and free alternatives per SC-005

- [ ] T036 [P] [US3] Write SS8.1 IDS Tools in `docs/HARDENING.md` -- Santa (`northpolesec/santa` per research.md R-006), BlockBlock, LuLu, KnockKnock (all Apple Silicon per research.md R-011); ClamAV (free) vs SentinelOne `[PAID]` ~$5/mo comparison per US-3; cross-ref tool comparison matrix in Appendix D
- [ ] T037 [P] [US1] Write SS8.2 Launch Daemon Auditing, SS8.3 Workflow Integrity Monitoring in `docs/HARDENING.md` -- comprehensive persistence audit covering ALL types (launch daemons/agents, cron, login items, authorization plugins, shell profiles, periodic scripts, XPC services, config profiles) per SC-032; workflow baseline hashing per SC-021
- [ ] T038 [P] [US1] Write SS8.4 macOS Logging, SS8.5 Credential Exposure Monitoring, SS8.6 iCloud and Cloud Service Exposure, SS8.7 Certificate Trust Monitoring in `docs/HARDENING.md` -- unified log predicates, DNS query logging and anomalous pattern detection per SC-038, iCloud services disable (except Find My Mac) per SC-034, certificate trust baseline per SC-040, log integrity (hash chain, permissions, external forwarding) per SC-039
- [ ] T039 [US1] Add SS8 audit checks to `scripts/hardening-audit.sh`: CHK-SANTA, CHK-BLOCKBLOCK, CHK-LULU, CHK-CLAMAV, CHK-PERSISTENCE-BASELINE, CHK-WORKFLOW-BASELINE, CHK-LISTENER-BASELINE, CHK-CERT-BASELINE, CHK-CLAMAV-SIGS (9+ checks)

**Checkpoint**: Detection layer deployed. Baselines established for drift detection.

---

## Phase 10: SS9 Response and Recovery (US-1, US-9)

**Goal**: Provide actionable incident response runbook, credential rotation procedures, backup/recovery, restore testing, and physical security guidance

**Independent Test**: Simulate a compromise (add unauthorized launch agent, modify an n8n workflow). Follow IR runbook. Verify containment, evidence preservation, and recovery to known-good state per SC-025

- [ ] T040 [P] [US9] Write SS9.1 Incident Response Runbook in `docs/HARDENING.md` -- triage steps for uncertain incidents, severity classification, containment (stop n8n + network isolation), evidence preservation (logs, filesystem snapshots), cross-reference to SS8 detection sources, breach notification obligations (GDPR/CCPA/LinkedIn ToS timelines) per SC-025
- [ ] T041 [P] [US9] Write SS9.2 Credential Rotation Procedures in `docs/HARDENING.md` -- emergency rotation runbook: dependency-ordered rotation for every credential in inventory (N8N_ENCRYPTION_KEY must re-encrypt DB first), per-credential instructions (where to change, what breaks, how to verify), 2-hour completion target per SC-035
- [ ] T042 [P] [US9] Write SS9.3 Backup and Recovery, SS9.4 Restore Testing in `docs/HARDENING.md` -- Time Machine + n8n export, Docker volume backup, backup encryption requirement, restore procedure under 30 min per SC-016, emergency rebuild from scratch when all backups corrupted, corrupted backup diagnosis
- [ ] T043 [P] [US9] Write SS9.5 Physical Security in `docs/HARDENING.md` -- Find My Mac (with Apple ID 2FA risk tradeoff), USB/Thunderbolt restriction policy `[EDUCATIONAL]`, post-theft credential rotation procedure, firmware password for Intel Target Disk Mode
- [ ] T044 [US9] Add SS9 audit checks to `scripts/hardening-audit.sh`: CHK-BACKUP-CONFIGURED, CHK-BACKUP-ENCRYPTED, CHK-FIND-MY-MAC (3+ checks)

**Checkpoint**: Respond layer complete. IR runbook is actionable without consulting external docs.

---

## Phase 11: SS10 Operational Maintenance (US-1, US-6, US-8)

**Goal**: Automate security maintenance: scheduled audits via launchd, failure notifications (email + local fallback), tool updates, log rotation, post-update checklist

**Independent Test**: Configure launchd audit job and notification per SS10. Deliberately disable firewall. Wait for scheduled audit. Verify FAIL notification received listing which checks failed and which guide sections to consult per US-8 acceptance scenarios

- [ ] T045 [US8] Write SS10.1 Automated Audit Scheduling in `docs/HARDENING.md` -- launchd plist configuration, `StartCalendarInterval` behavior during sleep (runs at next wake), timestamped log output, `launchctl load` instructions
- [ ] T046 [US8] Create `scripts/launchd/com.openclaw.audit.plist` -- launchd plist template for scheduled weekly audit runs, configurable schedule, log output to timestamped file in audit log directory
- [ ] T047 [US8] Write SS10.2 Notification Setup in `docs/HARDENING.md` -- msmtp for email alerts (SMTP relay dependency: Gmail app passwords, SendGrid, etc. per plan.md BS-13), macOS Notification Center fallback via `osascript`, FAIL-only active alerts (no WARN notifications) per alert fatigue prevention, local log fallback when email fails
- [ ] T048 [P] [US8] Create `scripts/launchd/com.openclaw.notify.plist` -- launchd plist for notification delivery triggered by audit FAIL results
- [ ] T049 [P] [US6] Write SS10.3 Tool Maintenance, SS10.4 Log Retention and Rotation, SS10.5 Troubleshooting Common Failures in `docs/HARDENING.md` -- ClamAV freshclam schedule, `brew update` cadence, n8n update procedure with post-update env var verification, newsyslog or launchd-based log rotation (90-day prune), comprehensive post-update checklist per SC-010, troubleshooting without removing security controls per SC-030
- [ ] T050 [US8] Add SS10 audit checks to `scripts/hardening-audit.sh`: CHK-LAUNCHD-AUDIT-JOB, CHK-NOTIFICATION-CONFIG, CHK-LOG-DIR, CHK-CLAMAV-FRESHNESS (4+ checks including self-check per FR-027 -- verify own scheduled execution and log directory are intact)

**Checkpoint**: Automated monitoring active. Operator receives FAIL-only notifications. 15 min/month maintenance burden per SC-013.

---

## Phase 12: SS11 Audit Script Reference + Appendices (US-1, US-2)

**Goal**: Complete audit script documentation, finalize all checks, and provide operator reference appendices

**Independent Test**: Run `hardening-audit.sh` on unhardened MacBook. Verify it reports FAIL for every critical control, SKIP for missing tools, correct guide section references for remediation, and `--json` output matches schema per US-2 acceptance scenarios

- [ ] T051 [US2] Write SS11.1 Running the Audit Script, SS11.2 Check Reference Table, SS11.3 JSON Output Schema, SS11.4 Interpreting Results in `docs/HARDENING.md` -- document every CHK-* ID with severity, deployment path, description, and guide section reference; JSON schema per `contracts/audit-script-cli.md`; interpretation guidance (all-PASS does not mean uncompromised per SC-036)
- [ ] T052 [US2] Finalize `scripts/hardening-audit.sh`: verify all checks from SS2-SS10 are wired up, JSON output validates against documented schema, `--section` filter correctly limits checks, exit codes correct (0=all pass, 1=any fail, 2=script error), audit script limitations disclosure per FR-065, validation guidance per FR-056
- [ ] T053 [P] [US1] Write Appendix A: Complete Security Environment Variable Reference in `docs/HARDENING.md` -- all n8n security env vars with recommended values, risk explanations, and corrected names per research.md R-003
- [ ] T054 [P] [US1] Write Appendix B: Credential Inventory Template in `docs/HARDENING.md` -- all known credentials per data-model.md (N8N_ENCRYPTION_KEY, LinkedIn session token, Apify API key, SSH key, SMTP credentials, n8n API key, JWT secret, Docker registry creds), storage locations per path, rotation intervals, blast radius
- [ ] T055 [P] [US1] Write Appendix C: Incident Response Checklist in `docs/HARDENING.md` -- condensed, printable checklist version of SS9.1 runbook for use under time pressure
- [ ] T056 [P] [US3] Write Appendix D: Tool Comparison Matrix in `docs/HARDENING.md` -- all tools from data-model.md Security Tool inventory with cost, function, defensive layer, `[PAID]` alternatives, and free alternatives per SC-005
- [ ] T057 [P] [US1] Write Appendix E: PII Data Classification Table in `docs/HARDENING.md` -- LinkedIn data fields (full_name, email, phone, job_title, etc.) with sensitivity classification, storage locations, retention recommendations, GDPR relevance per data-model.md PII entity

**Checkpoint**: Audit script is complete with 60+ checks. All appendices provide self-contained operator reference material.

---

## Phase 13: Polish and Cross-Cutting Concerns

**Purpose**: Quality gates, cross-cutting validation, final integration

- [ ] T058 Verify all `[PAID]` tool mentions in `docs/HARDENING.md` include approximate cost and free alternative per FR-005, FR-006, SC-005
- [ ] T059 [P] Verify all control sections in `docs/HARDENING.md` follow CIS pattern (Threat/Why/How/Verify/Edge Cases) per `contracts/guide-structure.md` section format
- [ ] T060 [P] Verify both deployment paths in `docs/HARDENING.md` are independently complete -- operator can follow either containerized or bare-metal without referencing the other per SC-009
- [ ] T061 [P] Run `shellcheck --severity=warning scripts/hardening-audit.sh` and fix all warnings per SC-008
- [ ] T062 [P] Run `npx markdownlint-cli2 docs/HARDENING.md` and fix all errors per FR-014, SC-007
- [ ] T063 Verify FR coverage: all 90 FRs across 4 spec modules are addressed in `docs/HARDENING.md` per SC-001 (39 control areas, zero gaps)
- [ ] T064 Verify all 43 success criteria (SC-001 through SC-043) pass against `docs/HARDENING.md` and `scripts/hardening-audit.sh`
- [ ] T065 Run full `scripts/hardening-audit.sh` on hardened MacBook and verify zero FAIL results per US-1 acceptance scenario #1

---

## Dependencies and Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies -- start immediately
- **SS1 Threat Model (Phase 2)**: Depends on Phase 1 (guide skeleton)
- **SS2-SS10 (Phases 3-11)**: Each depends on Phase 1 (guide skeleton + audit framework); sections are independent of each other and CAN proceed in parallel, but the MacBook validation strategy recommends sequential order (SS2, SS3, ..., SS10) so each section is tested on real hardware before the next begins
- **SS11 + Appendices (Phase 12)**: Depends on Phases 3-11 (all audit checks must exist before reference documentation)
- **Polish (Phase 13)**: Depends on all content phases complete

### User Story Coverage

| Story | Priority | Primary Phases | Key Tasks |
|-------|----------|---------------|-----------|
| US-1: Harden Fresh Mac | P1 | ALL phases | T005-T016, T027-T029, T037-T038, T053-T055, T057 |
| US-2: Audit Existing Mac | P2 | Phase 12 | T051-T052 + all audit check tasks (T012, T016, T021, T026, T029, T035, T039, T044, T050) |
| US-3: Evaluate Free vs Paid | P2 | Phases 9, 12, 13 | T036, T056, T058 |
| US-4: Secure n8n | P1 | Phase 6 | T022-T026 |
| US-5: Container Isolation | P1 | Phase 5 | T017-T021 |
| US-6: Maintain Over Time | P2 | Phase 11 | T049 |
| US-7: Injection Defense | P1 | Phase 8 | T030-T035 |
| US-8: Automated Monitoring | P2 | Phase 11 | T045-T048, T050 |
| US-9: Incident Response | P2 | Phase 10 | T040-T044 |

### Within Each Phase

1. Guide subsections marked [P] within a phase can be written in parallel (independent content in same file)
2. Audit check tasks depend on their section's guide content being written first (verification commands come from the guide)
3. Supporting files (docker-compose.yml, plists, entrypoint.sh) can be written in parallel with guide content

### Parallel Opportunities

- **Phase 1**: T003 || T004
- **Phase 3**: T008 || T009 || T010 || T011, then T012
- **Phase 4**: T013 || T014 || T015, then T016
- **Phase 5**: T017 || T018 || T019, then T020, then T021
- **Phase 6**: T022 || T023 || T024 || T025, then T026
- **Phase 7**: T027 || T028, then T029
- **Phase 8**: T030 || T031 || T032 || T033 || T034, then T035
- **Phase 9**: T036 || T037 || T038, then T039
- **Phase 10**: T040 || T041 || T042 || T043, then T044
- **Phase 11**: T045 || T048 || T049, then T046 (needs scheduling section), then T047, then T050
- **Phase 12**: T053 || T054 || T055 || T056 || T057 (all appendices parallel), T051 then T052
- **Phase 13**: T059 || T060 || T061 || T062

---

## Parallel Example: Phase 5 (Container Isolation)

```text
# Round 1 -- start in parallel (different files or independent sections):
Task T017: "Write SS4.1-SS4.2 in docs/HARDENING.md"
Task T018: "Create scripts/templates/docker-compose.yml"
Task T019: "Create scripts/templates/n8n-entrypoint.sh"

# Round 2 -- after T017-T019 complete (references compose file):
Task T020: "Write SS4.3-SS4.5 in docs/HARDENING.md"

# Round 3 -- after T020 complete (needs verification commands):
Task T021: "Add SS4 audit checks to scripts/hardening-audit.sh"
```

---

## Implementation Strategy

### MVP First (Phases 1-2)

1. Complete Phase 1: Setup -- guide skeleton + audit framework
2. Complete Phase 2: SS1 Threat Model + Preamble
3. **STOP and VALIDATE**: Operator reads threat model and preamble for accuracy
4. This establishes the tone, structure, and delivery cadence for all subsequent sections

### Section-by-Section Delivery (Phases 3-12)

1. Each phase = one PR = one guide section + corresponding audit checks + supporting files
2. After each PR merges, operator follows the section on the fresh Sonoma MacBook
3. MacBook gets Homebrew, git, Colima, etc. ONLY after reading the hardening guidance for that tool
4. The fresh MacBook state IS the integration test -- operator literally IS US-1
5. Audit script grows incrementally (new checks added with each section)
6. Context window is never overwhelmed (one section at a time)

### PR Sequence

| PR | Phase | Content | MacBook Validates |
|----|-------|---------|-------------------|
| 1 | 1-2 | Setup + SS1 Threat Model + Preamble | N/A (narrative) |
| 2 | 3 | SS2 OS Foundation | FileVault, firewall, SIP, Gatekeeper |
| 3 | 4 | SS3 Network Security | SSH, DNS, pf/iptables |
| 4 | 5 | SS4 Container Isolation | Colima install, Docker hardening |
| 5 | 6 | SS5 n8n Platform Security | n8n deploy, env vars, webhooks |
| 6 | 7 | SS6 Bare-Metal Path | Service account, Keychain |
| 7 | 8 | SS7 Data Security | Credentials, injection, PII |
| 8 | 9 | SS8 Detection and Monitoring | Santa, BlockBlock, LuLu, baselines |
| 9 | 10 | SS9 Response and Recovery | IR runbook, backups |
| 10 | 11 | SS10 Operational Maintenance | launchd scheduling, notifications |
| 11 | 12 | SS11 Audit Script Ref + Appendices | Full audit run |
| 12 | 13 | Polish | Final cross-cutting validation |

---

## Notes

- [P] tasks = different files or independent sections, no dependencies on incomplete tasks
- [Story] label maps task to its primary user story for traceability
- No automated tests -- validation is manual (shellcheck, markdownlint, MacBook walkthrough)
- Each phase checkpoint = one PR merged + MacBook validation
- Research corrections (R-001 through R-013) are applied during implementation, not as separate tasks
- Constitution compliance verified in Phase 13 (T059, T063, T064)
- Commit after each task or logical group within a phase
- Guide sections use `SS` prefix (Section) to avoid confusion with spec `FR` prefix
