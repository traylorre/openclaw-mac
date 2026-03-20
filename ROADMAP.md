# Fledge: OpenClaw-Mac Roadmap

Multi-agent automation platform on hardened macOS. From hello world
to production agent pipelines in 6 milestones.

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

## Milestone 3: Lead Prospector (`v0.3.0-lead-prospector`)

**Goal**: Working lead generation pipeline for a real client.
OpenClaw + Apify + n8n, delivering enriched leads.

- [ ] Apify actor for LinkedIn/Google Maps scraping
- [ ] n8n workflow: webhook trigger → Apify → Claude enrichment → output
- [ ] ICP scoring with configurable verticals
- [ ] Output to Airtable or Notion
- [ ] Document agent authority: what credentials it holds, what it can reach

**Demo**: Scored leads for a target vertical, delivered to client's
preferred tool.

---

## Milestone 4: LangGraph Agent (`v0.4.0-langgraph`)

**Goal**: Reimplement the pipeline in Python/LangGraph. Demonstrate
multi-agent orchestration with production patterns.

- [ ] Python CLI wrapping the audit + lead gen pipeline
- [ ] LangGraph multi-agent workflow: Planner → Executor → Reviewer
- [ ] Tool use: Apify, audit script, Claude as LangGraph tools
- [ ] RAG over HARDENING.md for security-aware remediation
- [ ] Production patterns: retry, circuit breaker, structured output
- [ ] pytest test suite

**Demo**: Same pipeline, built with LangGraph. Shows progression
from no-code orchestration to code-first agent systems.

---

## Milestone 5: Hybrid Memory (`v0.5.0-hybrid-memory`)

**Goal**: Vector + graph memory for deeper retrieval across agents.

- [ ] Qdrant vector store with Ollama embeddings
- [ ] Mem0 memory middleware
- [ ] Evaluate retrieval quality on real queries from M3-M4
- [ ] Compare vector-only vs. hybrid on multi-hop questions

**Demo**: Agents recall context across sessions. Side-by-side
retrieval comparison showing where graph beats flat vector.

---

## Milestone 6: Deployment Observations (`v0.6.0-observations`)

**Goal**: Compile practitioner findings from M1-M5 into a report
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
M4+:   LangGraph (code-first Python — production agent systems)

OpenClaw (native macOS)
  ├── n8n (Docker) — webhook routing + workflow orchestration
  ├── Apify — web scraping (LinkedIn, Google Maps)
  ├── Claude API — enrichment + analysis
  ├── Qdrant (Docker) — vector memory (M5)
  ├── Mem0 (Docker) — memory middleware (M5)
  └── hardening-audit.sh — security verification
```

Security baseline: [docs/HARDENING.md](docs/HARDENING.md)
Trust gap analysis: [docs/TRUST-GAPS.md](docs/TRUST-GAPS.md)
