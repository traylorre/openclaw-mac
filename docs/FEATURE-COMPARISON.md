# Feature Comparison: openclaw-mac vs NemoClaw

A feature-level comparison of two security architectures for OpenClaw
agent deployments: openclaw-mac (local macOS hardening) and NemoClaw
(NVIDIA's cloud-based sandbox).

For the security value of each openclaw-mac control, see
[SECURITY-VALUE.md](SECURITY-VALUE.md). For threat-level risk mappings,
see [ASI-MAPPING.md](ASI-MAPPING.md).

---

## Comparison Methodology

- **NemoClaw documentation reviewed**: NVIDIA NemoClaw docs at
  `docs.nvidia.com/nemoclaw/latest/` (accessed 2026-04-06)
- **openclaw-mac controls**: Based on audit checks in
  `scripts/hardening-audit.sh` and the integrity framework in
  `scripts/lib/integrity.sh`
- **Terminology**: NIST SP 800-53r5 control families, consistent with
  [SECURITY-VALUE.md](SECURITY-VALUE.md)
- **"Not documented"**: Where a NemoClaw capability is noted as "Not
  documented in NemoClaw as of 2026-04-06," this means the public
  documentation does not describe such a feature. It does not mean the
  feature definitively does not exist — NemoClaw is a proprietary NVIDIA
  product and may have undocumented capabilities.

---

## Feature Matrix

<!-- markdownlint-disable MD013 -->

| Dimension | NemoClaw | openclaw-mac | NIST Family |
|-----------|----------|-------------|-------------|
| Filesystem Isolation | Landlock LSM (kernel-enforced); writable /sandbox + /tmp; read-only system paths | `chflags uchg` (userspace BSD); root can remove flags | SC-28, CM-5 |
| Integrity Verification | Not documented in NemoClaw as of 2026-04-06 | HMAC-SHA256 manifest with Keychain-stored keys; signed state files | SI-7, SC-13 |
| Supply Chain Controls | Skill files copied to writable /sandbox — modifiable by agent at runtime | Skill allowlist with SHA-256 content hashes + HMAC signatures | SR-4, SA-12 |
| Runtime Monitoring | Not documented in NemoClaw as of 2026-04-06 | fswatch LaunchAgent with 30-second heartbeats; real-time alerts | SI-4, IR-4 |
| Network Policy | Deny-by-default; explicit allowlist (Anthropic API, GitHub, operator-specified) | pf firewall rules + localhost-only container binding + HMAC webhook authentication | SC-7 |
| Credential Management | Not documented in NemoClaw as of 2026-04-06 | macOS Keychain (HMAC keys) + Docker secrets (encryption key) + credential isolation | SC-13, AC-6 |
| Audit Automation | Not documented in NemoClaw as of 2026-04-06 | 84-check automated audit (weekly cron + on-demand); auto-fix capability | CA-7, AU-2 |
| Prompt Injection Detection | Not documented in NemoClaw as of 2026-04-06 | Skill hash mismatch triggers "Supply chain risk" warning | SI-7, SR-4 |

<!-- markdownlint-enable MD013 -->

---

## Gap Analysis

### What NemoClaw Provides That openclaw-mac Lacks

#### Kernel-Level Filesystem Isolation (Landlock LSM)

NemoClaw uses Linux Landlock, a kernel-level security module that
restricts filesystem access at the syscall level. A process constrained
by Landlock cannot escape its allowed paths — even with root privileges
(unless the LSM itself is disabled). macOS has no Landlock equivalent.
openclaw-mac's `chflags uchg` operates at the userspace level and can be
removed by root via `chflags nouchg`. This is a fundamental enforcement
strength difference: kernel-level (NemoClaw) vs userspace (openclaw-mac).

#### Deny-by-Default Network Policy

NemoClaw's network policy starts from "deny all" and explicitly allows
only specific endpoints (Anthropic API, GitHub, operator-configured
destinations). openclaw-mac uses pf firewall rules and localhost-only
container binding, but does not implement a full deny-all-then-allow
network model. This is an area for future development.

#### seccomp Process Filters

NemoClaw applies seccomp (secure computing mode) filters that restrict
which system calls the sandboxed process can make. macOS has sandbox
profiles (sandbox-exec) but openclaw-mac does not currently use them.
This limits the depth of process isolation available on the local
platform.

### What openclaw-mac Provides That NemoClaw Lacks

#### Cryptographic Integrity Verification

openclaw-mac signs every protected file with HMAC-SHA256 using a key
stored in macOS Keychain. Any modification — even a single byte — is
detectable. NemoClaw's documentation does not describe any integrity
verification mechanism for files within the sandbox.

#### Skill Allowlist with Content Hashing

openclaw-mac maintains a signed allowlist of approved SKILL.md files
with SHA-256 content hashes. A modified skill file triggers an explicit
supply chain risk warning. In NemoClaw, skill files are copied to the
writable `/sandbox` directory where the agent can modify them at
runtime.

#### Continuous Filesystem Monitoring

openclaw-mac runs an fswatch-based monitor as a LaunchAgent that watches
every protected file path. Changes trigger alerts within 30 seconds.
A heartbeat mechanism detects if the monitor itself is killed. NemoClaw's
documentation does not describe any runtime file monitoring capability.

#### Automated Security Audit

openclaw-mac runs 84 security checks across all domains — macOS
platform, containers, credentials, network, browser, and agent
configuration. The audit runs weekly on a schedule and on-demand via
`make audit`. It can auto-fix issues via `make fix`. NemoClaw's
documentation does not describe an automated audit capability.

#### Credential Management

openclaw-mac stores HMAC signing keys in macOS Keychain (hardware-backed
on Apple Silicon), Docker encryption keys in Docker secrets, and
enforces credential isolation so the agent never directly holds OAuth
tokens. NemoClaw's documentation does not describe credential management
controls.

#### Environment Variable Validation

openclaw-mac blocks 15 dangerous environment variables (NODE_OPTIONS,
DYLD_INSERT_LIBRARIES, PYTHONPATH, etc.) and prevents n8n Code nodes
from reading any environment variables. NemoClaw's documentation does
not describe environment variable controls.

#### Prompt Injection Detection

openclaw-mac detects modified SKILL.md files via content hash comparison
and flags them as supply chain risks. Since skill files are system
prompts, a modified skill IS a prompt injection. NemoClaw's documentation
does not describe prompt injection detection.

---

## Complementary Controls

NemoClaw and openclaw-mac address different parts of the security stack.
Combining both approaches would create defense in depth across
enforcement levels:

<!-- markdownlint-disable MD013 -->

| NemoClaw Control | openclaw-mac Control | Combined Value |
|-----------------|---------------------|---------------|
| Landlock (kernel-level prevent) | HMAC manifest (detect changes) | Prevent + Detect: even if kernel isolation is compromised, integrity verification catches modifications |
| Deny-by-default network | HMAC webhook authentication | Network isolation + authenticated communication: no unauthorized endpoints AND verified message integrity |
| seccomp (syscall filtering) | fswatch (filesystem monitoring) | Process restriction + runtime monitoring: syscalls are limited AND file changes are detected |
| Gateway-routed inference | Skill allowlist | Controlled model access + controlled instructions: both the model endpoint and the agent's instructions are locked down |

<!-- markdownlint-enable MD013 -->

A deployment using NemoClaw's kernel-level isolation with openclaw-mac's
integrity and monitoring layers would achieve stronger security than
either approach alone. NemoClaw prevents at the kernel level;
openclaw-mac detects and responds at the application level.

---

## Cross-References

- **Why each openclaw-mac control exists**:
  [SECURITY-VALUE.md](SECURITY-VALUE.md) — NIST/AICPA TSC mapping
- **Threat-level risk mapping**:
  [ASI-MAPPING.md](ASI-MAPPING.md) — OWASP Agentic ASI01-ASI10
- **Behavioral changes after hardening**:
  [BEHAVIORS.md](BEHAVIORS.md) — operational guide for forkers
