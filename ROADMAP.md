# Fledge: OpenClaw-Mac Roadmap

Hardened macOS deployment for OpenClaw — the self-hosted AI agent.
From security baseline to production LinkedIn automation in 5
milestones.

## Milestone 1: Gateway Live (`v0.1.0-gateway`) — DONE

**Goal**: n8n orchestration backbone running, callable from CLI.

- [x] n8n running in Docker on Mac Mini via Colima
- [x] Hello-world webhook callable from CLI
- [x] Bearer auth gate on all webhook endpoints
- [x] Gateway Switch node routing by `intent` field
- [x] Verify hardening audit passes with n8n container running

**Demo**: Gateway routes intents to sub-agent workflows.

---

## Milestone 2: Security Baseline (`v0.2.0-baseline`) — DONE

**Goal**: Establish the security posture of the deployment and
document what self-attestation can and cannot verify.

- [x] Run mSCP compliance script for OS-level checks (NIST 800-53r5 moderate: 30 PASS / 118 FAIL — most FAILs are federal requirements not applicable to standalone Mac: smartcard, MDM, iCloud lockdown, policy banners)
- [x] Run `hardening-audit.sh --json` for full 84-check audit (50 PASS, 0 FAIL)
- [x] Publish trust gap analysis: [docs/TRUST-GAPS.md](docs/TRUST-GAPS.md)

Results: [docs/mscp-800-53r5-moderate-results.json](docs/mscp-800-53r5-moderate-results.json)

**Demo**: Audit passes. Trust gaps documented. mSCP baseline run.
Foundation laid for TEA integration in M3/M5.

---

## Milestone 3: LinkedIn Automation (`v0.3.0-linkedin`)

**Goal**: Deploy OpenClaw on hardened macOS and configure it for
LinkedIn presence management. Hybrid approach: LinkedIn API for
posting/engagement, Playwright CDP for feed discovery, human-operated
connection requests.

### Deploy and configure

- [ ] Install OpenClaw natively (Bun/Node process, not Docker)
- [ ] Configure multi-provider LLM: Gemini (primary), Anthropic (secondary), Ollama (embeddings/fallback)
- [ ] Configure chat interface (Telegram or WhatsApp — built into OpenClaw)
- [ ] Add LinkedIn Share API as n8n workflow (OAuth token held by n8n, not OpenClaw)
- [ ] Add Playwright CDP as n8n workflow (feed browsing, post URN collection)
- [ ] Wire n8n execution history as AI-queryable activity log via webhook

### Security and trust boundaries

- [x] Add CHK-OPENCLAW-* audit checks — 15 checks total: 7 agent security (M3), 8 workspace integrity (M4-accelerated)
- [x] Add HMAC signature verification on n8n webhooks (prove caller is OpenClaw, not arbitrary localhost process)
- [ ] Document agent authority: what credentials each trust domain holds
- [ ] Collect trust boundary observations for TEA mapping (formalized in M5)
- [ ] Document OAuth token lifecycle as agent credential management pattern
- [x] Checksum OpenClaw workspace files (SOUL.md, AGENTS.md, TOOLS.md) to detect tampering — HMAC-signed manifest, 49 protected files
- [x] **011-workspace-integrity (pulled forward from M4)**: filesystem immutability (chflags uchg), agent sandbox isolation (ro workspace, tool restrictions), startup integrity verification (10 checks), continuous monitoring (fswatch + LaunchAgent), skill allowlist (content-hash identity), adversarial review (18 findings, 9 fixed). 46/58 tasks complete; 12 integration tests deferred until agent is running.

### Hardening observations

- [ ] Which activities work normally with hardening in place
- [ ] Which activities require workarounds (e.g., CDP Chrome flags)
- [ ] Which activities are not possible under hardened deployment

**Demo**: Operator messages OpenClaw via Telegram, LLM drafts
content, human approves, n8n workflow posts to LinkedIn and engages
with community. Agent never touches LinkedIn credentials directly.

---

## Milestone 3.5: Workspace Integrity (pulled forward from M4)

**Status**: 79% complete (46/58 tasks). Implementation done. Integration tests deferred until M3 agent is running.

**Why pulled forward**: ClawHavoc supply chain attack (1,184 malicious skills on ClawHub, Feb 2026) made workspace integrity controls a prerequisite for safely deploying M3's LinkedIn automation. A compromised skill can rewrite CLAUDE.md — the agent's system prompt loaded every turn.

**Defense layers implemented**:

- **Prevent**: `chflags uchg` immutable flags on 49 protected files (kernel-enforced)
- **Contain**: OpenClaw sandbox — read-only workspace, tool deny lists, zero-tool extraction agent
- **Detect**: Pre-launch attestation (HMAC-signed manifest, checksums, env vars, symlinks, skill allowlist, platform version, pending-drafts schema) + continuous fswatch monitoring with signed heartbeat
- **Verify**: 8 new CHK-OPENCLAW-* audit checks in hardening-audit.sh

**Adversarial review**: 18 findings (3 CRITICAL, 6 HIGH, 6 MEDIUM, 3 LOW). 9 fixed. Key residual: HMAC trust anchor in Keychain accessible to same-user processes. Report: `specs/011-workspace-integrity/ADVERSARIAL-REVIEW-01.md`

---

## Milestone 4: Hybrid Memory (`v0.4.0-hybrid-memory`)

**Goal**: Vector + graph memory for deeper retrieval across agents.
Replaces n8n execution history logging from M3 with persistent,
queryable memory.

- [ ] Qdrant v1.13.0 vector store (Docker via Colima)
- [ ] Mem0 open-source mode with Ollama embeddings (no external API keys)
- [ ] Single Qdrant instance, per-agent collections for isolation
- [ ] Wire OpenClaw to Mem0 for cross-session context
- [ ] Evaluate retrieval quality on real queries from M3
- [ ] Compare vector-only vs. hybrid on multi-hop questions

**Demo**: OpenClaw recalls past posts, engagement patterns, and
prospect context across sessions. "What did we post about X last
week?" works.

---

## Milestone 5: Deployment Observations (`v0.5.0-observations`)

**Goal**: Compile practitioner findings from M1-M4 into a report
suitable for NIST CAISI or working group input.

- [ ] Where CIS/NIST controls failed to cover agentic risks
- [ ] Where Examine-passing controls failed under real use
- [ ] OWASP ASI items that manifested vs. remained theoretical
- [ ] Hardening-vs-functionality matrix from M3 observations
- [ ] Formalize TEA trust boundary mapping from M3 observations (agent → orchestrator → platform)
- [ ] Agent credential lifecycle findings (OAuth rotation, trust delegation)
- [ ] Workspace file integrity findings (SOUL.md tampering as local prompt injection vector)
- [ ] Publish as blog post or working group contribution

**Demo**: Practitioner report grounded in deployment data.

---

## Architecture

```text
Operator (Telegram / WhatsApp)
  └── OpenClaw (native Bun/Node process)
        ├── LLM providers: Gemini (primary) / Anthropic / Ollama
        ├── n8n (Docker) — multi-step workflow orchestration
        │     ├── LinkedIn API — credentials held HERE, not by agent
        │     └── Playwright — CDP feed discovery + URN capture
        ├── Qdrant v1.13.0 (Docker) — vector memory (M4)
        └── Mem0 (Docker) — memory middleware + Ollama embeddings (M4)

Platform: openclaw-mac (this repo)
  ├── Colima + Docker runtime
  ├── macOS hardening (make audit, make fix)
  ├── n8n gateway (M1)
  └── Workspace integrity (M3.5)
        ├── chflags uchg on 49 protected files
        ├── HMAC-signed manifest + skill allowlist
        ├── fswatch continuous monitoring
        └── Adversarial review: 18 findings

Trust boundaries (TSP model):
  Operator ──── agent (OpenClaw) ──── orchestrator (n8n) ──── platform
  human         holds: LLM API keys   holds: LinkedIn OAuth   enforces: 84
  approval      (Gemini/Anthropic/    cannot: act without     security
  gate          Ollama as configured)  HMAC-signed webhook     checks
                cannot: access         trigger from agent
                LinkedIn creds
```

Security baseline: [docs/HARDENING.md](docs/HARDENING.md)
Trust gap analysis: [docs/TRUST-GAPS.md](docs/TRUST-GAPS.md)
LinkedIn automation design: [docs/LINKEDIN-AUTOMATION-PROPOSAL.md](docs/LINKEDIN-AUTOMATION-PROPOSAL.md)
