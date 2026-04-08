# Security Value: Why Each Control Exists

This document maps each openclaw-mac security control to the threat it
mitigates, the industry standard it implements, and the value it provides
in plain English. It answers the forker's question: **"Why is this
restriction here?"**

For the complementary threat-centric view — what threats exist and what
addresses them — see [ASI-MAPPING.md](ASI-MAPPING.md).

For how these controls compare to NemoClaw's approach, see
[FEATURE-COMPARISON.md](FEATURE-COMPARISON.md).

---

## Control Matrix

Each row maps a security control to its justification. Columns:

- **Control**: What the control does
- **Threat**: The specific attack it mitigates
- **NIST Family**: NIST SP 800-53r5 control family identifiers
- **TSC Category**: AICPA Trust Services Criteria category (SOC 2)
- **Layer**: Defense-in-depth layer per the project constitution
  (Prevent / Detect / Respond)
- **Implementation**: Audit check IDs and make targets
- **Value**: One-sentence plain-English justification

<!-- markdownlint-disable MD013 -->

| Control | Threat | NIST Family | TSC Category | Layer | Implementation | Value |
|---------|--------|-------------|-------------|-------|----------------|-------|
| Filesystem Immutability (uchg) | Workspace file tampering by compromised agent or supply chain attack | SC-28 (integrity), CM-5, SI-7 | Security (CC6.1) | Prevent | `CHK-OPENCLAW-INTEGRITY-LOCK` · `make integrity-lock` | Agent instruction files cannot be modified — even by the agent itself |
| Cryptographic Integrity (HMAC-SHA256) | Undetected file modifications that bypass uchg (e.g., root compromise) | SI-7, SC-13 | Processing Integrity (PI1.1) | Detect | `CHK-PIPELINE-HMAC-CONSISTENCY` · `make manifest-update` | Every protected file has a cryptographic signature — a single changed byte triggers detection |
| Continuous Monitoring (fswatch) | Delayed discovery of unauthorized file changes | SI-4, IR-4, AU-6 | Security (CC7.2) | Detect | `CHK-OPENCLAW-MONITOR-STATUS` · `make monitor-setup` | A background process watches every protected file with 30-second heartbeats — changes trigger alerts within seconds |
| Skill Allowlist (Supply Chain) | Modified SKILL.md files injecting malicious instructions into the agent | SR-4, SA-12, CM-7 | Security (CC6.1) + Processing Integrity (PI1.1) | Prevent | `CHK-OPENCLAW-SKILLALLOW` · `make skillallow-add` | Every skill file is content-hashed and signed — a tampered skill triggers a supply chain risk warning |
| Environment Variable Validation | NODE_OPTIONS / DYLD_* / PYTHONPATH used to inject code at process startup | CM-6, SA-8 (design), AC-6 | Security (CC6.1) | Prevent | `CHK-PIPELINE-ENV-VARS` · `CHK-N8N-ENV-BLOCK` | 15 dangerous environment variables are blocked — Code nodes cannot read any env vars at all |
| Container Isolation | Container escape leading to host compromise | SC-7, SC-39, CM-7, AC-6 | Security (CC6.1, CC6.3) | Prevent + Respond | `CHK-PIPELINE-CONTAINER-HARDENING` · `make container-bench` | Even if n8n is compromised, the container cannot write to its own filesystem, escalate privileges, or reach anything outside localhost |
| Audit Automation | Configuration drift going unnoticed for weeks or months | CA-7, AU-2, SI-6 | Security (CC7.1) + Availability (A1.2) | Detect + Respond | `CHK-LAUNCHD-AUDIT-JOB` · `make audit` | Every Sunday at 3am, 84 security checks run automatically — the audit can also fix issues it finds |

<!-- markdownlint-enable MD013 -->

These 7 controls form the core security framework. An additional 84+
checks cover macOS platform hardening, browser security, network
controls, threat detection, and backup — run `make audit` for the full
assessment.

---

## Why This Matters

### Filesystem Immutability

Without uchg flags, a compromised agent — or anyone with write access to
the workspace — could modify SOUL.md, AGENTS.md, or TOOLS.md. These
files define the agent's identity, capabilities, and tool access. A
single modified line in SOUL.md changes what the agent believes it
should do. With uchg, those files are locked at the filesystem level.
Only root can remove the lock, and the integrity monitor alerts if
anyone tries.

### Cryptographic Integrity

Without HMAC signing, an attacker who bypasses uchg (via root compromise
or by rebooting into recovery mode) could modify files undetected. The
system would continue operating with tampered instructions, trusting
files that can no longer be trusted. With HMAC-SHA256, every protected
file has a signature stored in a manifest. The signing key lives in
macOS Keychain — not on disk, not in the repo.

### Continuous Monitoring

Without fswatch, a compromised file might not be discovered until the
next manual audit — days or weeks later. The attacker has that entire
window to operate. With continuous monitoring, the system watches every
protected file path and writes a heartbeat every 30 seconds. If someone
kills the monitor, the stale heartbeat reveals the compromise.

### Skill Allowlist

Without the allowlist, SKILL.md files are just markdown files that
anyone can edit. But skill files ARE system prompts — they are injected
at agent session start. A modified skill IS a prompt injection. With the
allowlist, every skill file has a SHA-256 content hash signed with HMAC.
A tampered skill triggers an explicit "Supply chain risk" warning.

### Environment Variable Validation

Without validation, an attacker who can set NODE_OPTIONS could make
Node.js load arbitrary code at startup. DYLD_INSERT_LIBRARIES can inject
code into any macOS process. PYTHONPATH can redirect Python imports.
These are not exotic attacks — they are well-documented persistence
techniques. The audit blocks 15 dangerous variables and
`N8N_BLOCK_ENV_ACCESS_IN_NODE=true` prevents n8n Code nodes from reading
any environment variables at all.

### Container Isolation

Without isolation, a compromised n8n instance has the same access as the
user running Docker. It could read files, open network connections, and
escalate privileges. With hardening — read-only rootfs, non-root user,
dropped capabilities, localhost-only binding — even a fully compromised
container cannot write to its own filesystem, reach the network, or
escalate to root. The blast radius is contained.

### Audit Automation

Without automated auditing, configuration drift accumulates silently. A
firewall rule gets disabled during debugging and is never re-enabled. A
permission change goes unnoticed. Six months later, the security posture
has eroded without anyone realizing. With weekly automated audits, every
control is verified on schedule. The audit doesn't just report — `make
fix` can remediate issues automatically, and `make fix-undo` can reverse
any change.

### Defense in Depth: How They Work Together

No single control is sufficient. The controls are designed to layer:

1. **uchg prevents** file modifications (Prevent layer)
2. If uchg is bypassed, **HMAC detects** the change (Detect layer)
3. If HMAC finds a mismatch, **fswatch alerts** in real-time (Detect
   layer)
4. The **audit automation** verifies all controls are still active
   (Detect + Respond layer)
5. **Container isolation** limits the blast radius of a compromised
   component (Respond layer)

An attacker must defeat every layer to avoid detection. Each layer
operates independently — compromising one does not disable the others.
A sufficiently privileged attacker (root) could attempt to defeat all
layers simultaneously, but each additional layer increases the
likelihood of detection before the attack completes.

---

## OWASP Top 10 for LLM Applications (2025) Mapping

The OWASP GenAI Security Project publishes two complementary Top 10
lists. The Agentic list (ASI01-ASI10) is mapped in
[ASI-MAPPING.md](ASI-MAPPING.md). Below is the LLM list (LLM01-LLM10).

<!-- markdownlint-disable MD013 -->

| LLM Risk | Applicable Controls | Notes |
|----------|-------------------|-------|
| LLM01 Prompt Injection | Filesystem immutability, fswatch, skill allowlist, env var validation | Primary defense layer — prevents persisted injection |
| LLM02 Sensitive Information Disclosure | Not directly addressed | Gap — no output filtering for sensitive data |
| LLM03 Supply Chain | HMAC integrity, skill allowlist, CVE registry | Content hash + signing + version pinning |
| LLM04 Data and Model Poisoning | Not directly addressed | Gap — no training data integrity controls (not applicable to inference-only deployment) |
| LLM05 Improper Output Handling | Not directly addressed | Gap — human approval gate is the primary control (see ASI-MAPPING.md ASI09) |
| LLM06 Excessive Agency | Container isolation, env var blocking, sandbox mode | Limits agent capabilities even if compromised |
| LLM07 System Prompt Leakage | Filesystem immutability (prevents modification, not leakage) | Partial — prevents tampering but not exposure of prompt content |
| LLM08 Vector and Embedding Weaknesses | Not directly addressed | Gap — no RAG system deployed currently |
| LLM09 Misinformation | Not directly addressed | Gap — human review is the primary control |
| LLM10 Unbounded Consumption | Not directly addressed | Gap — no rate limiting beyond LinkedIn API empirical limits |

<!-- markdownlint-enable MD013 -->

4 of 10 LLM risks have dedicated technical controls. The remaining 6
are either not applicable to this deployment model (LLM04, LLM08) or
mitigated by operational controls (human approval gate) rather than
technical controls.

---

## Standards Referenced

| Standard | Version | Date | URL |
|----------|---------|------|-----|
| NIST SP 800-53 | Rev 5, Update 1 | Dec 2020 (updated Sep 2025) | <https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final> |
| AICPA Trust Services Criteria | 2017 (with 2022 points of focus) | 2017/2022 | <https://www.aicpa-cima.com/resources/download/2017-trust-services-criteria-with-revised-points-of-focus-2022> |
| OWASP Top 10 for LLM Applications | 2025 | 2025 | <https://genai.owasp.org/resource/owasp-top-10-for-llm-applications-2025/> |
| OWASP Top 10 for Agentic Applications | 2025/2026 | Dec 2025 | <https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/> |
| MITRE ATLAS | v5.1.0 | Nov 2025 | <https://atlas.mitre.org/> |
| CIS Docker Benchmark | v1.6.0 (v1.8.0 available Aug 2025) | 2024 | <https://www.cisecurity.org/benchmark/docker> |
| CIS Apple macOS Benchmarks | Tahoe 26 v1.0.0, Sequoia 15 v2.0.0, Sonoma 14 v3.0.0 | 2025-2026 | <https://www.cisecurity.org/benchmark/apple_os> |

> CIS Benchmark documents require free registration to download. The
> landing pages above are publicly accessible.

---

## Trust Assumptions

These controls assume the following components are not compromised.
If any assumption is violated, the controls above may be insufficient:

- **macOS kernel and SIP**: System Integrity Protection is enabled and
  the kernel has not been modified. uchg flags and Keychain security
  depend on kernel-level enforcement.
- **macOS Keychain**: The Keychain is accessible only to authorized
  processes. The HMAC signing key's security depends entirely on
  Keychain access controls.
- **Homebrew supply chain**: Packages installed via Homebrew (bash, jq,
  shellcheck, fswatch, grype) are authentic. A compromised Homebrew
  package could bypass all controls.
- **Docker runtime**: The container runtime (Colima/Docker) correctly
  enforces isolation. Container escape vulnerabilities undermine
  container isolation controls.
- **The operator**: The human operator is trusted. These controls
  protect the system from the agent, from external attackers, and from
  supply chain compromise — not from a malicious operator who holds
  root access and the Keychain password.
- **Physical access**: An attacker with physical access can boot into
  Recovery Mode, disable SIP, remove uchg flags, and extract Keychain
  data. Physical security is out of scope (see the project
  constitution's threat model).

---

## Limitations and Exclusions

This project addresses a specific threat model (see the project
constitution). The following security domains are **not covered**:

- **Network intrusion detection (IDS/IPS)**: No deep packet inspection
  or network anomaly detection. pf firewall rules and localhost binding
  provide basic network controls.
- **Application-level authentication**: The agent does not authenticate
  users. The human approval gate is an operational control, not a
  technical authentication mechanism.
- **Runtime memory protection**: No address space layout randomization
  (ASLR) enforcement beyond what macOS provides by default. No memory
  integrity verification for running processes.
- **LLM output filtering**: No automated detection of sensitive data in
  agent outputs (LLM02). Human review is the primary control.
- **Rate limiting**: No automated rate limit enforcement for LinkedIn
  API calls. Limits are unpublished and must be determined empirically.
- **Multi-tenant isolation**: This is a single-machine deployment. No
  controls for isolating multiple agents or users on the same system.

- **Non-repudiation (NIST AU-10)**: HMAC-SHA256 provides integrity
  verification and authentication but NOT non-repudiation. Non-repudiation
  requires asymmetric cryptography (digital signatures) so that the signer
  cannot deny having signed. HMAC uses a shared symmetric key — either
  party holding the key could have produced the signature. If
  non-repudiation is needed for audit log entries or manifest signing,
  the project would need to adopt asymmetric key pairs (e.g., Ed25519).

These gaps are acknowledged, not hidden. For some (LLM04, LLM08), the
gap reflects the deployment model (inference-only, no RAG). For others
(LLM02, rate limiting), the gap reflects a conscious tradeoff where
operational controls are preferred over technical ones at current scale.
