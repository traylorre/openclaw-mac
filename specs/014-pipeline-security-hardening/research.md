# Research: Pipeline Security Hardening

**Feature**: 014-pipeline-security-hardening
**Date**: 2026-03-26

## R-001: n8n CVE Landscape (90-Day Window)

**Decision**: Pin n8n to >= 2.13.0 (current) which patches all known CVEs. Maintain a version-controlled CVE registry for ongoing verification.

**Findings**:

| CVE | CVSS | Date | Description | Fixed In |
|-----|------|------|-------------|----------|
| CVE-2025-68613 | 9.9 | Dec 2025 | RCE via expression injection | 1.73.0 |
| CVE-2025-68668 (N8scape) | 9.9 | 2025 | Python Code Node sandbox bypass (Pyodide) | 1.80.0 |
| CVE-2026-21858 (Ni8mare) | 10.0 | Jan 2026 | Unauthenticated RCE via Content-Type confusion | 1.121.0 |
| CVE-2026-25049 | 9.4 | Feb 2026 | System command execution via crafted expressions | 2.6.0 |
| CVE-2026-27577 | Critical | Mar 2026 | Expression compiler sandbox escape (process object) | 2.10.1 |
| CVE-2026-27498 | High | Mar 2026 | Command execution flaw | 2.10.1 |
| CVE-2026-27497 | High | Mar 2026 | Code execution flaw | 2.10.1 |

Our pinned version (2.13.0) is above the highest fix version (2.10.1). **Current version is patched.**

CISA warned that "one n8n server could expose your entire digital ecosystem." The Code Node sandbox has been bypassed 3 times in 6 months.

**Rationale**: Version pinning with digest verification is the primary defense. The CVE registry enables automated checking on each audit run.

**Sources**: NVD, The Hacker News, Aikido Security, Upwind Security, CISA

## R-002: OpenClaw CVE Landscape (6-Week Window)

**Decision**: Pin OpenClaw to >= 2026.3.13 (current). Verify against all 8 CVEs.

**Findings**:

| CVE | CVSS | Description | Fixed In |
|-----|------|-------------|----------|
| CVE-2026-25253 | Critical | One-click RCE via malicious link (WebSocket token theft) | 2026.2.8 |
| CVE-2026-32025 | Critical | Auth bypass on loopback deployments (brute-force) | 2026.2.12 |
| CVE-2026-32048 | Critical | Sandbox escape via cross-agent session spawning | 2026.3.2 |
| CVE-2026-32056 | Critical | Shell startup env var injection bypasses command allowlist | 2026.3.7 |
| CVE-2026-32049 | High | DoS via oversized media payloads | 2026.3.2 |
| CVE-2026-32913 | Critical (9.3) | Cross-origin header leak (API key forwarding) | 2026.3.7 |
| CVE-2026-33101 | High | Credential access via debug endpoint | 2026.3.13 |
| CVE-2026-33215 | High | Privilege escalation via hook token reuse | 2026.3.13 |

Our pinned version (2026.3.13) patches all 8. **Current version is patched.**

**Rationale**: OpenClaw is the most privileged component in the pipeline. Version currency is critical. Binary integrity verification is a documented residual risk (no signature mechanism available).

**Sources**: NVD, The Hacker News, ProArch, MintMCP, Koi Security

## R-003: LinkedIn OAuth Token Lifecycle (Updated)

**Decision**: Support both access tokens (60-day TTL) and refresh tokens (365-day TTL). Implement automated refresh.

**Findings**:
- LinkedIn added programmatic refresh token support for consumer apps with `w_member_social` scope in late 2025
- Access tokens: 60-day TTL from grant
- Refresh tokens: 365-day TTL from original issue
- When a refresh token generates a new access token, the refresh token TTL remains the same (365 days from original issue)
- 2-legged OAuth (client credentials): 30-minute access token lifespan (not applicable to our 3-legged flow)
- LinkedIn reserves the right to revoke tokens at any time

**This supersedes 010 spec R-006** which concluded "Programmatic refresh is only available to select LinkedIn partners." That conclusion was accurate at the time of writing but LinkedIn has since extended refresh token support to consumer apps.

**Rationale**: Automated refresh dramatically reduces operational burden (yearly re-auth vs. bi-monthly). The 010 spec's Credential Lifecycle State entity and token-check workflow must be updated.

**Alternatives considered**: Manual re-auth every 60 days (original design). Rejected because automated refresh is now available and reduces operational risk.

**Sources**: Microsoft Learn (LinkedIn API documentation), outx.ai LinkedIn API Guide

## R-004: LinkedIn API Rate Limits

**Decision**: Do not hardcode rate limit numbers. Query Developer Portal Analytics after first API call.

**Findings**:
- Rate limits are per-app and per-member, reset at midnight UTC daily
- **Specific limits are NOT published in documentation** — must check Developer Portal Analytics tab
- LinkedIn sends email alerts at 75% of quota (with 1-2 hour delay)
- 429 responses indicate rate limiting; may also be returned for infrastructure protection
- Industry estimates: ~100-150 posts/day practical ceiling for posting endpoints

**This supersedes 010 spec FR-016** which stated "150 requests per member per day" as a concrete number.

**Rationale**: Hardcoding an unpublished number creates false confidence. The system should detect rate limiting dynamically via 429 responses and the Developer Portal alert emails.

**Sources**: Microsoft Learn (LinkedIn API Rate Limits documentation)

## R-005: OWASP Top 10 for Agentic Applications

**Decision**: Map all 10 risks to pipeline controls using local identifiers ASI01-ASI10.

**Findings**:

| ID | Risk | Pipeline Control | Residual Risk |
|----|------|-----------------|---------------|
| ASI01 | Agent Goal Hijack | Human approval gate, workspace immutability, SOUL.md persona boundaries | LLM provider compromise could subtly bias content |
| ASI02 | Tool Misuse & Exploitation | Sandbox mode, tool deny lists, HMAC-signed webhooks | N8N_BLOCK_ENV_ACCESS=false weakens Code node isolation |
| ASI03 | Identity & Privilege Abuse | Credential isolation (agent never holds LinkedIn tokens), HMAC authentication | Keychain HMAC key accessible to same-user processes (ADV-001) |
| ASI04 | Agentic Supply Chain | Skill allowlist, version pinning, container image digest verification | OpenClaw binary has no signature verification; community nodes can read env vars |
| ASI05 | Unexpected Code Execution | Sandbox mode (deny exec, process, browser tools), NODES_EXCLUDE for n8n | Code Node sandbox bypassed 3 times (n8n CVEs) |
| ASI06 | Memory & Context Poisoning | Not applicable in M3 (no persistent memory). Deferred to M4 (Qdrant/Mem0) | When M4 is implemented, memory integrity checks needed |
| ASI07 | Insecure Inter-Agent Communication | HMAC-SHA256 webhook auth with replay protection (5-min timestamp window) | n8n-to-OpenClaw callbacks are unsigned (acceptable for localhost alerts) |
| ASI08 | Cascading Failures | Human approval gate prevents automated cascading; daily post limit; rate limit monitoring | No circuit breaker between agent and n8n |
| ASI09 | Human-Agent Trust Exploitation | Operator reviews each post; time-delayed approval possible via quiet hours | Subtle bias in LLM output may pass human review |
| ASI10 | Rogue Agents | Behavioral baseline monitoring (webhook frequency, skill invocations); audit logging | No continuous behavioral analysis beyond frequency tracking |

**Note on naming**: "ASI01-ASI10" are local identifiers for convenience. The official OWASP project is "OWASP Top 10 for Agentic Applications" (released December 10, 2025 by the OWASP GenAI Security Project).

**Sources**: OWASP GenAI Security Project, Human Security, Practical DevSecOps, Koi Security, Aikido

## R-006: ClawHavoc Supply Chain Context

**Decision**: Existing controls (skill-allowlist.json, sandbox mode) are correct. Document context.

**Findings**:
- February 2026: 1,184 malicious skills uploaded to ClawHub by attackers using newly created GitHub accounts
- 335 traced to a single coordinated campaign (ClawHavoc)
- 40,000+ OpenClaw instances exposed, 63% assessed as vulnerable
- Attack vectors: staged downloads, reverse shells, credential theft, ClickFix social engineering
- macOS-specific: Atomic macOS Stealer (AMOS) targeting Keychain, browser creds, crypto wallets, SSH keys
- ClawHub vetting: minimal (only requires 1-week-old GitHub account)

**Our mitigations**:
- `skill-allowlist.json` with content-hash HMAC signatures
- Sandbox mode ON with deny lists (exec, process, browser, write)
- chflags uchg immutability on workspace files
- Continuous fswatch monitoring
- Manual skill review before deployment

**Rationale**: Defense-in-depth against supply chain is the right approach. No single control is sufficient, but layered controls (allowlist + sandbox + immutability + monitoring) make exploitation significantly harder.

**Sources**: CyberPress, eSecurity Planet, Repello AI, Conscia

## R-007: Defense-in-Depth Layer Model

**Decision**: Five layers (Prevent, Contain, Detect, Respond, Recover) mapped to NIST CSF functions.

**Mapping**:

| Defense Layer | NIST CSF | MITRE ATLAS Techniques Defended | Controls |
|--------------|----------|--------------------------------|----------|
| **Prevent** | Protect | AML.T0051 (Prompt Injection), AML.T0054 (Supply Chain) | Credential isolation, HMAC auth, workspace immutability, sandbox mode, skill allowlist |
| **Contain** | Protect | AML.T0040 (ML Supply Chain Compromise) | Docker isolation (read-only FS, non-root, dropped caps), OpenClaw sandbox (ro workspace, tool deny lists), dangerous node exclusion |
| **Detect** | Detect | AML.T0043 (Craft Adversarial Data), AML.T0048 (Command & Control) | Pre-launch attestation, continuous monitoring (fswatch), behavioral baseline (webhook frequency), manifest signature verification |
| **Respond** | Respond | All | Alert delivery (webhook callback to operator), audit logging (hardening-audit.sh --json), manual remediation (make integrity-lock) |
| **Recover** | Recover | All | Credential rotation procedures, manifest re-baseline, dependency rollback, post-incident verification |

**Sources**: NIST Cybersecurity Framework, MITRE ATLAS (October 2025 update with 14 agent techniques), NIST AI RMF 1.0

## R-008: Trust Boundary Model (ToIP TEA Context)

**Decision**: Document 5 trust zones with known gaps. Reference TEA/TSP as candidate framework for future trust establishment.

**Trust Zones**:

| Zone | Component | Trust Anchor | Known Gap |
|------|-----------|-------------|-----------|
| TZ1: Operator Authority | Human + sudo | macOS login credentials | Cannot protect against operator's own credentials being stolen |
| TZ2: Instruction Governance | manifest.json (HMAC-signed) | Keychain HMAC key | ADV-001: same-user process can read key |
| TZ3: Runtime Isolation | OpenClaw sandbox | openclaw.json config | Config can be modified before launch (ADV-003: no out-of-band verification) |
| TZ4: Detection Layer | integrity-verify.sh + fswatch | Filesystem events | ADV-008: lib/integrity.sh sourced before verification |
| TZ5: External Services | n8n Docker container | Docker isolation | ADV-009: no image hash verification before docker exec |

**ToIP TEA mapping** (future, documentation only):
- The agent would hold a Verifiable Identifier (VID) issued by the operator's governance framework
- The orchestrator (n8n) would verify the agent's VID via Trust Spanning Protocol (TSP) before accepting webhook payloads
- `did:peer` is the candidate DID method for localhost pairwise trust (no external resolver needed)
- Trust Tasks would model atomic verifiable actions (post approval, credential check)
- This replaces the current HMAC-only trust model with cryptographically stronger, standards-based trust establishment
- TSP specification is at Revision 2 (November 2025); practical implementation for AI agents is being defined by the ToIP/DIF working groups

**Sources**: ToIP Trust Spanning Protocol specification, ToIP Technology Architecture, DIF/ToIP Working Groups announcement

## R-009: Sensitive File Inventory

**Decision**: Document all 14+ sensitive files with protections. HMAC-sign lock-state.json and heartbeat.

**Complete inventory**:

| File | Risk | Protection | Status |
|------|------|-----------|--------|
| `.env` (repo root) | HMAC secret in cleartext | Mode 600, .gitignore | Must verify .gitignore |
| `~/.openclaw/.env` | HMAC secret (agent copy) | Mode 600 | Enforced by hmac-keygen.sh |
| `~/.openclaw/manifest.json` | Integrity checksums + signature | Mode 600, HMAC-signed | Enforced |
| `~/.openclaw/lock-state.json` | Grace periods (alert suppression) | Mode 600, **UNSIGNED** | ADV-002: must add HMAC |
| `~/.openclaw/openclaw.json` | Agent sandbox config | Mode 600 | User-editable (by design) |
| `~/.openclaw/skill-allowlist.json` | Skill content hashes | Mode 600, HMAC-signed | Enforced |
| `~/.openclaw/integrity-monitor-heartbeat.json` | Monitor liveness | Mode 600, **UNSIGNED** | ADV-004: must add HMAC |
| `~/.openclaw/agents/linkedin-persona/SOUL.md` | Agent persona | uchg immutable, manifest hash | Enforced |
| `~/.openclaw/agents/linkedin-persona/AGENTS.md` | Operating rules | uchg immutable, manifest hash | Enforced |
| `~/.openclaw/agents/linkedin-persona/TOOLS.md` | Tool documentation | uchg immutable, manifest hash | Enforced |
| `workflows/*.json` (6 active) | n8n automation definitions | Mode 644 (repo), checksummed | Manifest-protected |
| `scripts/templates/docker-compose.yml` | Container config | Mode 644 (repo), checksummed | Manifest-protected |
| `scripts/templates/n8n-entrypoint.sh` | Container startup | Mode 644 (repo), checksummed | Manifest-protected |
| `scripts/lib/integrity.sh` | Integrity logic (trust root) | uchg immutable | ADV-008: sourced before verification |

**Future (when US2 implemented)**:
| `storageState.json` (browser profile) | LinkedIn session cookies | Not yet implemented | Must be HMAC-signed |

## R-010: Environment Variable Validation (ADV-007)

**Decision**: Expand validation to 7 dangerous environment variables.

**Variables to check**:

| Variable | Attack | Current Check | Required |
|----------|--------|--------------|----------|
| DYLD_INSERT_LIBRARIES | Library injection | Yes (existing) | Keep |
| NODE_OPTIONS | Node.js flag injection | Yes (existing) | Keep |
| DYLD_FRAMEWORK_PATH | Framework path hijack | **No** | Add |
| DYLD_LIBRARY_PATH | Library path hijack | **No** | Add |
| LD_PRELOAD | Library preload injection | **No** | Add |
| HOME (if overridden) | Redirect config paths | **No** | Add |
| TMPDIR (if overridden) | Redirect temp file paths | **No** | Add |

**Sources**: MITRE ATT&CK T1574 (Hijack Execution Flow), macOS developer documentation
