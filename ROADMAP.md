# Fledge: OpenClaw-Mac Roadmap

Multi-agent automation platform on hardened macOS. From hello world
to production agent pipelines in 5 milestones.

## Milestone 1: Gateway Live (`v0.1.0-gateway`) — DONE

**Goal**: n8n orchestration backbone running, callable from OpenClaw.

- [x] n8n running in Docker on Mac Mini
- [x] Hello-world webhook callable from CLI
- [x] Bearer auth gate on all webhook endpoints
- [x] Gateway Switch node routing by `intent` field
- [x] Verify hardening audit passes with n8n container running

**Demo**: Gateway routes intents to sub-agent workflows.

---

## Milestone 2: Security Baseline (`v0.2.0-baseline`)

**Goal**: Establish the security posture of the deployment and
document what self-attestation can and cannot verify.

- [ ] Run mSCP compliance script for OS-level checks (~30 CIS/NIST-mapped controls)
- [ ] Run `hardening-audit.sh --json` for full 84-check audit
- [ ] Publish trust gap analysis: [docs/TRUST-GAPS.md](docs/TRUST-GAPS.md)

**Demo**: Audit passes. Trust gaps documented. Foundation laid for
future TEA integration.

---

## Milestone 3: LinkedIn Automation (`v0.3.0-linkedin`)

**Goal**: Working LinkedIn presence pipeline for code19.ai.
Hybrid approach: LinkedIn API for posting/engagement, Playwright CDP
for feed discovery, human-operated connection requests.

- [ ] Telegram bot connected to n8n via webhook/polling
- [ ] Claude API content generation with human approval flow
- [ ] LinkedIn Share API integration (OAuth, posting, commenting, liking)
- [ ] Playwright CDP for feed browsing and post URN collection
- [ ] Google Sheets activity logging and content calendar
- [ ] Document agent authority: what credentials it holds, what it can reach

**Demo**: Operator sends topic via Telegram, Claude drafts content,
human approves, system posts to LinkedIn and engages with community.

---

## Milestone 4: Hybrid Memory (`v0.4.0-hybrid-memory`)

**Goal**: Vector + graph memory for deeper retrieval across agents.

- [ ] Qdrant vector store with Ollama embeddings
- [ ] Mem0 memory middleware
- [ ] Evaluate retrieval quality on real queries from M3
- [ ] Compare vector-only vs. hybrid on multi-hop questions

**Demo**: Agents recall context across sessions. Side-by-side
retrieval comparison showing where graph beats flat vector.

---

## Milestone 5: Deployment Observations (`v0.5.0-observations`)

**Goal**: Compile practitioner findings from M1-M4 into a report
suitable for NIST CAISI or working group input.

- [ ] Where CIS/NIST controls failed to cover agentic risks
- [ ] Where Examine-passing controls failed under real use
- [ ] OWASP ASI items that manifested vs. remained theoretical
- [ ] Publish as blog post or working group contribution

**Demo**: Practitioner report grounded in deployment data.

---

## Architecture

```text
M1-M3: n8n (no-code orchestration — learn agent patterns)

OpenClaw (native macOS)
  ├── n8n (Docker) — webhook routing + workflow orchestration
  ├── Telegram Bot — operator chat interface
  ├── LinkedIn API — posting, commenting, liking
  ├── Playwright — CDP browser control for feed discovery
  ├── Claude API — content generation + enrichment
  ├── Google Sheets — activity logging + prospect tracking
  ├── Qdrant (Docker) — vector memory (M4)
  ├── Mem0 (Docker) — memory middleware (M4)
  └── hardening-audit.sh — security verification
```

Security baseline: [docs/HARDENING.md](docs/HARDENING.md)
Trust gap analysis: [docs/TRUST-GAPS.md](docs/TRUST-GAPS.md)
