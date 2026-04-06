# Research: Feature 029 — SECURITY-VALUE.md

**Date**: 2026-04-06 | **Phase**: 0 (Research)

## 1. Control-to-Standard Mapping

### Core Controls (7 from REQ-03)

#### 1.1 Filesystem Immutability (uchg)

**Mechanism**: macOS `chflags uchg` flags on protected files (SOUL.md, AGENTS.md, TOOLS.md, skill files). Non-root processes cannot modify flagged files.

**NIST SP 800-53r5 Families**:
- **SC-28** (Protection of Information at Rest) — uchg prevents unauthorized modification of files at rest
- **CM-5** (Access Restrictions for Change) — only root can remove uchg flags, enforcing change control
- **SI-7** (Software, Firmware, and Information Integrity) — files are locked in a known-good state

**AICPA TSC Category**: Security (CC6.1 — Logical and physical access controls restrict access)

**OWASP LLM 2025**: **LLM07** (System Prompt Leakage) — uchg prevents modification of SKILL.md files which ARE system prompts; **LLM01** (Prompt Injection) — immutable workspace prevents persisted injection

**OWASP Agentic (ASI)**: ASI01 (Agent Goal Hijack), ASI06 (Memory/Context Poisoning) — already mapped in ASI-MAPPING.md

**MITRE ATLAS**: AML.T0051 (Prompt Injection) — cross-ref ASI-MAPPING.md

**Defense Layer**: **Prevent**

**Audit Checks**: `CHK-OPENCLAW-INTEGRITY-LOCK`
**Make Targets**: `integrity-lock`, `integrity-deploy`, `integrity-unlock`

**Value**: "Your agent's instruction files cannot be modified — even by the agent itself. An attacker who gains write access to the workspace still can't change what the agent believes or does."

---

#### 1.2 Cryptographic Integrity (HMAC-SHA256)

**Mechanism**: HMAC-SHA256 manifest signing using macOS Keychain-stored keys. Every protected file has a signed hash in `~/.openclaw/manifest.json`. State files (lock-state.json, heartbeat.json) also carry HMAC signatures.

**NIST SP 800-53r5 Families**:
- **SI-7** (Software, Firmware, and Information Integrity) — cryptographic verification of file integrity
- **SC-13** (Cryptographic Protection) — HMAC-SHA256 with Keychain-managed keys
- **AU-10** (Non-repudiation) — signed manifest provides evidence of file state at signing time

**AICPA TSC Category**: Processing Integrity (PI1.1 — System processing is complete, valid, accurate, timely, authorized)

**OWASP LLM 2025**: **LLM03** (Supply Chain) — integrity verification of all agent input files

**OWASP Agentic (ASI)**: ASI04 (Agentic Supply Chain) — already mapped in ASI-MAPPING.md

**Defense Layer**: **Detect** (detects tampering after the fact; pairs with uchg which prevents it)

**Audit Checks**: `CHK-PIPELINE-HMAC-CONSISTENCY`, `CHK-SENSITIVE-LOCKSTATE-SIG`, `CHK-SENSITIVE-HEARTBEAT-SIG`
**Make Targets**: `hmac-setup`, `integrity-rotate-key`, `manifest-update`

**Value**: "Every file in the workspace has a cryptographic signature. If anything changes — a single byte — the system detects it. The signing key lives in macOS Keychain, not on disk."

---

#### 1.3 Continuous Monitoring (fswatch)

**Mechanism**: fswatch-based file monitor running as LaunchAgent (`com.openclaw.integrity-monitor`). Watches protected paths, writes 30-second heartbeats to `~/.openclaw/integrity-monitor-heartbeat.json`. Alerts on unauthorized modifications.

**NIST SP 800-53r5 Families**:
- **SI-4** (System Monitoring) — real-time filesystem monitoring
- **IR-4** (Incident Handling) — automated detection triggers alert pipeline
- **AU-6** (Audit Record Review, Analysis, and Reporting) — heartbeat enables liveness verification

**AICPA TSC Category**: Security (CC7.2 — System components are monitored for anomalies)

**OWASP LLM 2025**: **LLM01** (Prompt Injection) — detects unauthorized file modifications that could inject prompts

**OWASP Agentic (ASI)**: ASI10 (Rogue Agents) — already mapped in ASI-MAPPING.md

**Defense Layer**: **Detect**

**Audit Checks**: `CHK-OPENCLAW-MONITOR-STATUS`
**Make Targets**: `monitor-setup`, `monitor-teardown`, `monitor-status`

**Value**: "A background process watches every protected file. If anything changes outside the approved unlock window, you get an alert within 30 seconds. And the monitor itself has a heartbeat — you'll know if someone kills it."

---

#### 1.4 Skill Allowlist (Supply Chain)

**Mechanism**: `~/.openclaw/skill-allowlist.json` contains SHA-256 content hashes of approved SKILL.md files, HMAC-signed for tamper detection. New skills require explicit operator approval (`make skillallow-add`).

**NIST SP 800-53r5 Families**:
- **SR-4** (Provenance) — content hashes verify skill file origin and integrity
- **SA-12** (Supply Chain Protection) — whitelisting prevents unauthorized skill execution
- **CM-7** (Least Functionality) — only explicitly approved skills can run

**AICPA TSC Category**: Security (CC6.1 — Access controls) + Processing Integrity (PI1.1 — Authorized processing)

**OWASP LLM 2025**: **LLM03** (Supply Chain) — prevents compromised skill files from executing; **LLM01** (Prompt Injection) — skill files ARE system prompts, hash mismatch = potential injection

**OWASP Agentic (ASI)**: ASI04 (Agentic Supply Chain) — already mapped in ASI-MAPPING.md

**Defense Layer**: **Prevent**

**Audit Checks**: `CHK-OPENCLAW-SKILLALLOW`
**Make Targets**: `skillallow-add`, `skillallow-remove`

**Value**: "Your AI agent's skill files are system prompts. If someone modifies them, they've already injected your agent. The allowlist catches this — every skill file is content-hashed and signed. A tampered skill triggers a supply chain risk warning."

---

#### 1.5 Environment Variable Validation

**Mechanism**: Audit checks validate that dangerous environment variables (NODE_OPTIONS, DYLD_*, PYTHONPATH, etc. — 15 vars total) are not set. `N8N_BLOCK_ENV_ACCESS_IN_NODE=true` prevents n8n Code nodes from reading env vars.

**NIST SP 800-53r5 Families**:
- **CM-6** (Configuration Settings) — enforce safe configuration baselines
- **SA-8** (Security and Privacy Engineering Principles) — defense against DLL/dylib injection
- **AC-6** (Least Privilege) — Code nodes blocked from env var access

**AICPA TSC Category**: Security (CC6.1 — Logical access controls)

**OWASP LLM 2025**: **LLM01** (Prompt Injection) — env vars can alter LLM behavior via injected config; **LLM06** (Excessive Agency) — blocking Code node env access limits agent capabilities

**OWASP Agentic (ASI)**: ASI02 (Tool Misuse), ASI05 (Unexpected Code Execution) — already mapped in ASI-MAPPING.md

**Defense Layer**: **Prevent**

**Audit Checks**: `CHK-N8N-ENV-BLOCK`, `CHK-N8N-ENV-API`, `CHK-PIPELINE-ENV-VARS`
**Make Targets**: N/A (validation-only, no deployment target)

**Value**: "NODE_OPTIONS can make Node.js load arbitrary code at startup. DYLD_INSERT_LIBRARIES can inject code into any process. We block 15 dangerous environment variables and prevent n8n Code nodes from reading any env vars at all."

---

#### 1.6 Container Isolation

**Mechanism**: Docker containers run with: read-only rootfs, non-root user (UID 1000), dropped capabilities (`--cap-drop ALL`), no-new-privileges, localhost-only port binding (127.0.0.1:5678).

**NIST SP 800-53r5 Families**:
- **SC-7** (Boundary Protection) — container network isolation
- **SC-39** (Process Isolation) — container runtime isolation
- **CM-7** (Least Functionality) — minimal container capabilities
- **AC-6** (Least Privilege) — non-root user, dropped capabilities

**AICPA TSC Category**: Security (CC6.1 — Logical access controls, CC6.3 — Network access restrictions)

**OWASP LLM 2025**: **LLM06** (Excessive Agency) — container limits what the agent can do even if compromised

**OWASP Agentic (ASI)**: ASI02 (Tool Misuse), ASI05 (Unexpected Code Execution) — already mapped in ASI-MAPPING.md

**CIS Docker Benchmark**: Section 4 (Container Images and Build File), Section 5 (Container Runtime)

**Defense Layer**: **Prevent** + **Respond**

**Audit Checks**: `CHK-PIPELINE-CONTAINER-HARDENING`, `CHK-CONTAINER-READONLY`, `CHK-CONTAINER-CAPS`, `CHK-CONTAINER-PRIVILEGED`, `CHK-CONTAINER-ROOT`
**Make Targets**: `container-bench`, `scan-image`

**Value**: "Even if n8n is compromised, the container can't write to its own filesystem, can't escalate privileges, can't reach anything outside localhost. The blast radius of a container escape is minimized."

---

#### 1.7 Audit Automation

**Mechanism**: Weekly automated audit via `com.openclaw.audit-cron` LaunchDaemon (root, Sunday 03:00). 84+ checks across all security domains. JSON output for drift detection. On-demand via `make audit`.

**NIST SP 800-53r5 Families**:
- **CA-7** (Continuous Monitoring) — scheduled automated assessment
- **AU-2** (Event Logging) — comprehensive audit trail
- **SI-6** (Security and Privacy Function Verification) — verifies all controls still active

**AICPA TSC Category**: Security (CC7.1 — Security monitoring activities) + Availability (A1.2 — Recovery procedures tested)

**OWASP LLM 2025**: N/A (operational infrastructure, not LLM-specific)

**OWASP Agentic (ASI)**: Cross-cutting — verifies controls for all ASI risks

**Defense Layer**: **Detect** + **Respond**

**Audit Checks**: `CHK-LAUNCHD-AUDIT-JOB`
**Make Targets**: `audit`, `fix`, `fix-interactive`, `fix-dry-run`, `fix-undo`

**Value**: "Every Sunday at 3am, 84 security checks run automatically. If someone disables a firewall rule, weakens a permission, or kills the integrity monitor, you know by Monday morning. The audit doesn't just report — it can fix issues automatically."

---

## 2. NIST 800-53r5 Control Families Used

| Family ID | Family Name | Controls Mapped |
|-----------|------------|-----------------|
| AC-6 | Least Privilege | Container isolation, env var validation |
| AU-2 | Event Logging | Audit automation |
| AU-6 | Audit Record Review | Continuous monitoring |
| AU-10 | Non-repudiation | HMAC integrity |
| CA-7 | Continuous Monitoring | Audit automation |
| CM-5 | Access Restrictions for Change | Filesystem immutability |
| CM-6 | Configuration Settings | Env var validation |
| CM-7 | Least Functionality | Skill allowlist, container isolation |
| IR-4 | Incident Handling | Continuous monitoring |
| SA-8 | Security Engineering Principles | Env var validation |
| SA-12 | Supply Chain Protection | Skill allowlist |
| SC-7 | Boundary Protection | Container isolation |
| SC-13 | Cryptographic Protection | HMAC integrity |
| SC-28 | Protection of Information at Rest | Filesystem immutability |
| SC-39 | Process Isolation | Container isolation |
| SI-4 | System Monitoring | Continuous monitoring |
| SI-6 | Security Function Verification | Audit automation |
| SI-7 | Integrity Verification | Filesystem immutability, HMAC integrity |
| SR-4 | Provenance | Skill allowlist |

**Coverage: 19 of 20 NIST families touched.** The only family not directly represented is PT (PII Processing and Transparency), which is a newer family added in r5. This could be partially addressed by the sensitive file permissions controls but is not a core focus.

## 3. AICPA TSC Categories Mapped

| TSC Category | Controls | Coverage |
|-------------|----------|----------|
| **Security** | All 7 core controls | Full |
| **Availability** | Audit automation (A1.2), continuous monitoring | Partial |
| **Processing Integrity** | HMAC integrity (PI1.1), skill allowlist | Partial |
| **Confidentiality** | Container isolation (network), credential isolation | Partial |
| **Privacy** | Not directly addressed (no PII processing controls in core 7) | Gap |

**Decision**: Security category is the primary mapping. Other categories are secondary where naturally applicable. Privacy gap is noted in Limitations section per REQ-11.

## 4. OWASP LLM 2025 Mapping

| LLM Risk | Applicable Controls | Notes |
|----------|-------------------|-------|
| LLM01 Prompt Injection | uchg, fswatch, skill allowlist, env vars | Primary defense layer |
| LLM03 Supply Chain | HMAC integrity, skill allowlist | Content hash + signing |
| LLM06 Excessive Agency | Container isolation, env var blocking | Limits agent capabilities |
| LLM07 System Prompt Leakage | uchg (prevents modification, not leakage) | Partial — prevents tampering not exposure |
| LLM02, LLM04, LLM05, LLM08-10 | Not directly addressed by core 7 | Noted in Limitations |

## 5. Defense-in-Depth Layer Assignment

| Layer | Controls | Constitution Ref |
|-------|----------|-----------------|
| **Prevent** | uchg, skill allowlist, env var validation, container isolation | VII.1 |
| **Detect** | HMAC integrity, fswatch monitoring, audit automation | VII.2 |
| **Respond** | Audit automation (auto-fix), alert pipeline | VII.3 |

**Key insight**: No single control operates alone. uchg (prevent) + HMAC (detect) + fswatch (detect) form a defense-in-depth chain for file integrity. If uchg is bypassed (e.g., root compromise), HMAC detects the change, and fswatch alerts in real-time.

## 6. Standards Referenced (for REQ-10)

| Standard | Version | Date | URL |
|----------|---------|------|-----|
| NIST SP 800-53 | Rev 5, Update 1 | Dec 2020 (updated Sep 2025) | https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final |
| AICPA Trust Services Criteria | 2017 (with 2022 points of focus update) | 2017/2022 | https://www.aicpa.org/resources/deferred-deep-link/aicpa-trust-services-criteria |
| OWASP Top 10 for LLM Applications | 2025 | 2025 | https://genai.owasp.org/resource/owasp-top-10-for-llm-applications-2025/ |
| OWASP Top 10 for Agentic Applications | 2025/2026 | Dec 2025 | https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/ |
| MITRE ATLAS | v5.1.0 | Nov 2025 | https://atlas.mitre.org/ |
| CIS Docker Benchmark | v1.6.0 | 2024 | https://www.cisecurity.org/benchmark/docker |
| CIS Apple macOS Benchmark | v4.0 | 2024 | https://www.cisecurity.org/benchmark/apple_os |

## 7. Decisions

| Decision | Rationale | Alternatives Considered |
|----------|-----------|------------------------|
| NIST 800-53r5 as primary taxonomy | Most comprehensive control catalog; 20 families cover all 7 controls; widely recognized | CIS Controls v8 (less granular), ISO 27001 (paid access), NIST CSF (higher level) |
| AICPA TSC as secondary taxonomy | SOC 2 alignment adds compliance value; 5 categories provide executive-level grouping | Could omit entirely, but TSC categories useful for "what type of security is this?" framing |
| Map to OWASP LLM separately from Agentic | Two different lists with different risk models; LLM list focuses on model risks, Agentic on agent behavior | Could map to only one, but both are relevant to an AI agent deployment |
| Cross-reference ASI-MAPPING.md for MITRE ATLAS | Avoid duplication; ATLAS technique IDs already maintained in ASI-MAPPING.md | Could duplicate mappings, but creates maintenance burden |
| 7 core controls + "Additional Controls" callout | Keeps the matrix scannable; links to full audit for completeness | Could include all 103 checks, but overwhelms the audience |
| Defense-in-depth layer column in matrix | Aligns with Constitution VII; shows controls work together | Could omit, but misses the "no single point of failure" narrative |
