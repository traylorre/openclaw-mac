# Fledge: OpenClaw-Mac Roadmap

Multi-agent automation platform on hardened macOS. From hello world
to autonomous agents in 6 milestones. Each milestone is a demo-able
increment tagged in GitHub.

## Milestone 1: Gateway Live (`v0.1.0-gateway`)

**Goal**: n8n orchestration backbone running, callable from OpenClaw.

- [ ] n8n running in Docker on Mac Mini
- [ ] Hello-world webhook callable from CLI
- [ ] Bearer auth gate on all webhook endpoints
- [ ] Gateway Switch node routing by `intent` field
- [ ] Verify hardening audit passes with n8n container running

**Demo**: Gateway routes intents to sub-agent workflows. Single webhook
URL, n8n handles all routing.

---

## Milestone 2: Trust Audit Agent (`v0.2.0-trust-audit`)

**Goal**: Autonomous compliance auditing against established standards.

- [ ] Sub-agent runs `hardening-audit.sh`, parses JSON output
- [ ] Maps findings to CIS Benchmarks / NIST SP 800-179 references
- [ ] Maps findings to OWASP Top 10 for Agentic Applications (ASI01-ASI10)
- [ ] Generates structured compliance report (markdown + JSON)
- [ ] Documents where controls exist but fail to operate as intended (NIST 800-53A: control effectiveness vs existence)

**Demo**: An autonomous agent audits its own infrastructure against
OWASP and NIST standards, and reports where "passing" controls
aren't actually protecting you.

---

## Milestone 3: Lead Prospector (`v0.3.0-lead-prospector`)

**Goal**: First sub-agent with real-world authority (API keys, data writes).

- [ ] Lead Prospector sub-agent: webhook → Apify (LinkedIn/Google Maps) → Claude enrichment → Airtable/Notion
- [ ] Mem0 + Qdrant memory running (open-source mode, Ollama embeddings)
- [ ] Guardian script integrated with OpenClaw memory flush
- [ ] ICP scoring pipeline with configurable verticals
- [ ] Document exactly what authority the agent has and how scope is verified

**Demo**: Scored leads for a target vertical, delivered to
Airtable/Notion with enrichment data. Clear accounting of what
credentials the agent holds and what it can reach.

---

## Milestone 4: Automation & Productivity (`v0.4.0-automation`)

**Goal**: Daily intelligence and content pipeline.

- [ ] 7am daily digest: overdue tasks, top news for target verticals, memory recall from Qdrant
- [ ] Weekly competitive landscape scan (GitHub stars/releases, LinkedIn activity of target companies)
- [ ] Delivery via Telegram or email
- [ ] Content Repurposer: turn work outputs into LinkedIn posts, readme sections
- [ ] Repo Improver: static analysis diff, readme staleness, dependency drift on push
- [ ] API Cost Monitor: track LLM spend daily, alert on budget threshold

**Demo**: Automated briefings, content pipeline, and repo maintenance
with zero manual intervention.

---

## Milestone 5: Hybrid Memory (`v0.5.0-hybrid-memory`)

**Goal**: Graph + vector memory layer for deeper retrieval.

- [ ] Add Cognee or Zep/Graphiti alongside Qdrant
- [ ] Evaluate retrieval quality on real queries from milestones 2-4
- [ ] Compare vector-only vs. hybrid on multi-hop questions
- [ ] Document before/after results

**Demo**: Side-by-side retrieval comparison showing where graph
traversal finds answers that flat vector search misses.

---

## Milestone 6: Deployment Observations (`v0.6.0-observations`)

**Goal**: Contribute practitioner findings to trust framework discussions.

- [ ] Compile deployment observations from milestones 1-5: where agent security controls failed in practice, where audits passed but protection didn't hold
- [ ] Map observations against published frameworks (OWASP Agentic Top 10, NIST AI Agent Standards Initiative, CSA Agentic Trust Framework)
- [ ] Identify gaps that deployment experience reveals but current frameworks don't address
- [ ] Publish findings in a format suitable for working group contribution

**Demo**: A practitioner report grounded in real deployment data,
structured for contribution to ongoing trust framework work.

---

## Architecture Principles

These milestones follow two objectives:

1. **Engineering fundamentals**: Context protection and separation,
   vector + graph memory, scalable sub-agents, security-first design
2. **Real-world value**: Each milestone delivers something usable,
   not just infrastructure. Compliance auditing, lead gen, briefings,
   content automation, and practitioner observations that contribute
   back to the security community.

## Infrastructure Stack

```text
OpenClaw Gateway (native)
  ├── n8n (Docker) — orchestration + webhook routing
  ├── Qdrant v1.13.0 (Docker) — vector memory
  ├── Ollama (Docker) — local embeddings (nomic-embed-text)
  ├── Mem0 API (Docker) — memory middleware
  └── hardening-audit.sh — trust verification layer
```

See [docs/HARDENING.md](docs/HARDENING.md) for the security baseline
that underpins this stack.
