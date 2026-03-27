# OWASP ASI Top 10 Control Mapping

INTERNAL — Operator Reference Only

Pipeline security hardening (014). Maps the OWASP Top 10 for Agentic
Applications (December 2025) to pipeline-specific controls, verification
methods, and residual risk assessments.

Note: ASI01-ASI10 are local identifiers mapped to the official OWASP Top 10
for Agentic Applications risk categories for brevity.

## ASI01 — Agent Goal Hijack

**Controls**:

- Human approval gate — operator reviews each post before publishing
- Workspace immutability — `uchg` flags on SOUL.md, AGENTS.md, TOOLS.md
  prevent persona/rule modification
- Persona boundaries — SOUL.md defines acceptable content topics and tone

**Verification**: `CHK-OPENCLAW-INTEGRITY-LOCK` (workspace immutability),
`CHK-OPENCLAW-SANDBOX-MODE` (sandbox enforced)

**MITRE ATLAS**: AML.T0051 (Prompt Injection)

**Residual Risk**: LLM provider compromise could subtly bias content. The human
approval gate is the primary mitigation. No automated detection of subtle
content manipulation is feasible at current posting volume (1-3 posts/day).

**Residual Severity**: Medium

## ASI02 — Tool Misuse and Exploitation

**Controls**:

- Sandbox mode ON with tool deny lists (exec, process, browser, write)
- n8n dangerous node exclusion (`NODES_EXCLUDE`: executeCommand, ssh,
  localFileTrigger)
- HMAC-signed webhooks prevent unauthorized tool invocation

**Verification**: `CHK-OPENCLAW-SANDBOX-TOOLS` (tool deny lists),
`CHK-N8N-NODES` (node exclusion)

**MITRE ATLAS**: AML.T0061 (Agent Tools)

**Residual Risk**: The n8n Code Node sandbox has been bypassed 3 times in 6
months (CVE-2025-68613, CVE-2025-68668/N8scape, CVE-2026-27577). Version
pinning to >= 2.13.0 mitigates known bypasses but the pattern suggests future
bypasses are likely. `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` weakens Code Node
isolation (see ASI04).

**Residual Severity**: Medium

## ASI03 — Identity and Privilege Abuse

**Controls**:

- Credential isolation — agent never holds LinkedIn tokens directly
- HMAC-SHA256 webhook authentication with replay protection (5-min window)
- n8n credential encryption with Docker-secret-stored encryption key

**Verification**: `CHK-OPENCLAW-CREDS` (agent lacks tokens),
`CHK-OPENCLAW-N8N-CREDS` (n8n encryption key present),
`CHK-OPENCLAW-WEBHOOK-AUTH` (HMAC authentication)

**MITRE ATLAS**: AML.T0062 (Exfiltration via Tools)

**Residual Risk**: Keychain HMAC key accessible to same-user processes
(ADV-001). Credential isolation protects LinkedIn tokens but not the HMAC root
of trust.

**Residual Severity**: Medium

## ASI04 — Agentic Supply Chain

**Controls**:

- Skill allowlist with content-hash HMAC signatures
- Version pinning for n8n, OpenClaw, Ollama with CVE registry verification
- Container image digest verification (sha256 in manifest)
- Manual skill review before deployment

**Verification**: `CHK-OPENCLAW-SKILLALLOW` (allowlist enforced),
`CHK-PIPELINE-CVE-N8N`, `CHK-PIPELINE-CVE-OPENCLAW`, `CHK-PIPELINE-CVE-OLLAMA`
(version currency)

**MITRE ATLAS**: AML.T0054 (ML Supply Chain Compromise)

**Residual Risk**: OpenClaw binary has no signature verification or provenance
attestation (FR-027). The agent binary is the most privileged component and the
security tools protecting it cannot detect its own compromise.
`N8N_BLOCK_ENV_ACCESS_IN_NODE=false` means a malicious community node could read
the n8n encryption key and decrypt all stored credentials (FR-019 trade-off).

**Residual Severity**: High

**Remediation Roadmap** (target: M4):

1. Short-term: Set `N8N_BLOCK_ENV_ACCESS_IN_NODE=true` when community node
   compatibility is confirmed
2. Short-term: Binary checksum verification against published release hashes
3. Medium-term: OpenClaw provenance attestation support when available

## ASI05 — Unexpected Code Execution

**Controls**:

- Sandbox mode (deny exec, process, browser tools)
- n8n `NODES_EXCLUDE` for dangerous nodes (executeCommand, ssh,
  localFileTrigger)
- Container hardening (read-only rootfs, non-root user, dropped capabilities,
  no-new-privileges)

**Verification**: `CHK-OPENCLAW-SANDBOX-MODE` (sandbox enforced),
`CHK-N8N-NODES` (node exclusion),
`CHK-PIPELINE-CONTAINER-HARDENING` (container lockdown)

**MITRE ATLAS**: AML.T0040 (ML Supply Chain Compromise)

**Residual Risk**: Code Node sandbox bypass history (3 times in 6 months)
makes this the most tested attack surface. Version pinning mitigates known
issues.

**Residual Severity**: Medium

## ASI06 — Memory and Context Poisoning

**Controls**:

- Docker volume isolation protects n8n Workflow Static Data
- Manifest HMAC integrity covers workspace files
- Workspace immutability (`uchg` flags) prevents instruction tampering

**Verification**: `CHK-OPENCLAW-INTEGRITY-LOCK` (workspace integrity),
`CHK-SENSITIVE-FILE-PERM-openclaw.json` (SQLite DB host permissions if
applicable)

**MITRE ATLAS**: AML.T0043 (Craft Adversarial Data)

**Residual Risk**: OpenClaw SQLite conversation history has no integrity
verification. An attacker with write access to the conversation DB could inject
poisoned context that influences future agent outputs. n8n Workflow Static Data
is protected only by container isolation. Full memory integrity checks deferred
to M4 (Qdrant/Mem0 integration).

**Residual Severity**: Medium

## ASI07 — Insecure Inter-Agent Communication

**Controls**:

- HMAC-SHA256 webhook authentication between agent and n8n orchestrator
- Replay protection via 5-minute timestamp window
- Localhost-only communication (127.0.0.1:5678)

**Verification**: `CHK-OPENCLAW-WEBHOOK-AUTH` (HMAC authentication),
`CHK-PIPELINE-HMAC-CONSISTENCY` (secret synchronization)

**MITRE ATLAS**: AML.T0048 (Command and Control)

**Residual Risk**: n8n-to-OpenClaw alert callbacks are unsigned (acceptable for
localhost-only alerts that do not trigger actions). Network isolation is the
primary defense.

**Residual Severity**: Low

## ASI08 — Cascading Failures

**Controls**:

- Human approval gate prevents automated cascading (no post published without
  operator review)
- Sandbox mode prevents agent from acting autonomously beyond its defined scope
- Rate limit monitoring via 429 response detection

**Verification**: `CHK-OPENCLAW-SANDBOX-MODE` (sandbox prevents autonomous
cascading)

**MITRE ATLAS**: N/A (operational risk, not adversarial technique)

**Residual Risk**: No circuit breaker between agent and n8n. No automated rate
limit enforcement (rate limits are unpublished by LinkedIn, must be determined
empirically). The human approval gate is the primary cascade prevention.

**Residual Severity**: Low

## ASI09 — Human-Agent Trust Exploitation

**Controls**:

- Process control: Operator reviews each post before publishing
- Technical proxy: Sandbox mode prevents agent from posting directly, enforcing
  the human gate architecturally
- Time-delayed approval possible via quiet hours configuration

**Verification**: `CHK-OPENCLAW-SANDBOX-MODE` (agent cannot bypass human gate
when sandbox enforces no direct posting). Note: process control (human review)
is not verifiable by automation.

**MITRE ATLAS**: N/A (social engineering vector)

**Residual Risk**: Subtle bias in LLM output may pass human review. At low
posting volume (1-3 posts/day), the operator's attention per post should be
sufficient, but fatigue over time is a risk. No automated content quality
analysis is implemented.

**Residual Severity**: Medium

## ASI10 — Rogue Agents

**Controls**:

- Behavioral baseline monitoring — webhook call frequency tracking with
  deviation alerting (200% threshold)
- Continuous filesystem monitoring via fswatch (heartbeat-verified)
- Audit logging of all privileged operations (JSONL format)

**Verification**: `CHK-OPENCLAW-MONITOR-STATUS` (fswatch heartbeat),
behavioral baseline comparison (Phase 6 enhancement)

**MITRE ATLAS**: AML.T0048 (Command and Control), TA0006 (Exfiltration)

**Residual Risk**: No continuous behavioral analysis beyond frequency tracking.
Content of webhook calls is not inspected. Skill invocation logging deferred
until OpenClaw agent produces structured logs. The fswatch monitor can be killed
by a same-user process (ADV-001 scope).

**Residual Severity**: Medium

## Summary

| ASI | Risk | Residual Severity | Verification Check |
|-----|------|-------------------|-------------------|
| ASI01 | Agent Goal Hijack | Medium | CHK-OPENCLAW-INTEGRITY-LOCK, CHK-OPENCLAW-SANDBOX-MODE |
| ASI02 | Tool Misuse | Medium | CHK-OPENCLAW-SANDBOX-TOOLS, CHK-N8N-NODES |
| ASI03 | Identity & Privilege | Medium | CHK-OPENCLAW-CREDS, CHK-OPENCLAW-N8N-CREDS, CHK-OPENCLAW-WEBHOOK-AUTH |
| ASI04 | Supply Chain | **High** | CHK-OPENCLAW-SKILLALLOW, CHK-PIPELINE-CVE-* |
| ASI05 | Code Execution | Medium | CHK-OPENCLAW-SANDBOX-MODE, CHK-N8N-NODES, CHK-PIPELINE-CONTAINER-HARDENING |
| ASI06 | Memory Poisoning | Medium | CHK-OPENCLAW-INTEGRITY-LOCK |
| ASI07 | Inter-Agent Comms | Low | CHK-OPENCLAW-WEBHOOK-AUTH, CHK-PIPELINE-HMAC-CONSISTENCY |
| ASI08 | Cascading Failures | Low | CHK-OPENCLAW-SANDBOX-MODE |
| ASI09 | Human-Agent Trust | Medium | CHK-OPENCLAW-SANDBOX-MODE |
| ASI10 | Rogue Agents | Medium | CHK-OPENCLAW-MONITOR-STATUS |

10/10 ASI risks mapped. 1 rated High (ASI04) with remediation roadmap.
