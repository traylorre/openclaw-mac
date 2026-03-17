# OpenClaw-Mac Roadmap

Multi-agent automation platform on hardened macOS. Each milestone is
a demo-able increment tagged in GitHub.

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

## Milestone 2: Lead Prospector (`v0.2.0-lead-prospector`)

**Goal**: First real sub-agent delivering scored leads.

- [ ] Lead Prospector sub-agent: webhook → Apify (LinkedIn/Google Maps) → Claude enrichment → Airtable/Notion
- [ ] Mem0 + Qdrant memory running (open-source mode, Ollama embeddings)
- [ ] Guardian script integrated with OpenClaw memory flush
- [ ] ICP scoring pipeline with configurable verticals

**Demo**: Scored leads for a target vertical, delivered to
Airtable/Notion with enrichment data.

---

## Milestone 3: Morning Briefing (`v0.3.0-briefing`)

**Goal**: Daily automated intelligence digest.

- [ ] 7am daily digest: overdue tasks, top news for target verticals, memory recall from Qdrant
- [ ] Weekly competitive landscape scan (GitHub stars/releases, LinkedIn activity of target companies)
- [ ] Delivery via Telegram or email

**Demo**: Every morning — a briefing. Every week — a competitive
scan. Zero manual effort.

---

## Milestone 4: Trust Audit Agent (`v0.4.0-trust-audit`)

**Goal**: Autonomous compliance auditing with verifiable output.

- [ ] Sub-agent runs `hardening-audit.sh`, parses JSON output
- [ ] Maps findings to CIS Benchmarks / NIST SP 800-179 references
- [ ] Generates structured compliance report (markdown + JSON)
- [ ] Outputs verifiable assertions suitable for trust frameworks

**Demo**: An autonomous agent audits trust infrastructure against
named standards and produces verifiable compliance artifacts.

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

## Milestone 6: Personal Productivity Agents (`v0.6.0-personal-agents`)

**Goal**: Agents that compound personal and project value.

- [ ] Content Repurposer: turn work outputs into LinkedIn posts, readme sections
- [ ] Repo Improver: static analysis diff, readme staleness, dependency drift on push
- [ ] API Cost Monitor: track LLM spend daily, alert on budget threshold

**Demo**: Automated content pipeline and repo maintenance with
zero manual intervention.

---

## Architecture Principles

These milestones follow two objectives:

1. **Engineering fundamentals**: Context protection and separation,
   vector + graph memory, scalable sub-agents, security-first design
2. **Real-world value**: Each milestone delivers something usable,
   not just infrastructure. Lead gen, briefings, compliance reports,
   content automation.

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
