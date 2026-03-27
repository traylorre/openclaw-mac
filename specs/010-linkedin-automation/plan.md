# Implementation Plan: LinkedIn Automation

**Branch**: `010-linkedin-automation` | **Date**: 2026-03-21 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/010-linkedin-automation/spec.md`

## Summary

Deploy OpenClaw as a native Bun/Node process on the hardened macOS host, configure it for LinkedIn presence management via n8n workflow orchestration. The system uses LinkedIn's official Share API for content operations (posting) and HMAC-signed webhooks for trust boundary enforcement between agent and orchestrator. All content requires human approval via chat (Telegram/WhatsApp). LinkedIn credentials are isolated in n8n — the agent never accesses them. The hardening audit is extended with agent-specific checks.

## Technical Context

**Language/Version**: JavaScript/TypeScript (Bun runtime for OpenClaw), Bash 5.x (POSIX-compatible subset for scripts and audit checks), JSON (n8n workflow definitions)
**Primary Dependencies**: OpenClaw (self-hosted AI agent), n8n v2.13.0 (Docker), LinkedIn Share API (OAuth 2.0), LLM providers (Gemini, Anthropic, Ollama)
**Storage**: OpenClaw SQLite + sqlite-vec (conversation history), n8n Docker volume (execution history, credentials, workflow state), filesystem (workspace files, pending drafts JSON, manifest checksums)
**Testing**: shellcheck (bash scripts), manual end-to-end verification (chat → draft → approve → post), hardening-audit.sh (audit framework)
**Target Platform**: macOS (Apple Silicon Mac Mini, Tahoe/Sonoma), hardened per M2 baseline
**Project Type**: Integration/deployment — deploying and configuring existing tools, writing n8n workflows, extending audit scripts, creating OpenClaw skills and workspace files
**Performance Goals**: Content draft generation <30s, API post publishing <10s, feed discovery session <5 minutes
**Constraints**: LinkedIn API 150 requests/member/day, OAuth token 60-day expiry with manual re-auth, free-tier LLM usage, no inbound ports (polling mode), single Mac Mini (no redundancy)
**Scale/Scope**: Single agent, single LinkedIn account, 1-3 posts per day

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Documentation-Is-the-Product | **PASS** | Repo output remains documentation + scripts + configuration. OpenClaw is deployed, not shipped. New artifacts: audit extensions, workspace templates, n8n workflow configs, hardening observations doc. |
| II. Threat-Model Driven (NON-NEGOTIABLE) | **PASS** | All controls traced to named threats: malicious ClawHub skills (credential isolation), workspace file tampering (integrity checksums), unauthorized webhook callers (HMAC — proves identity + integrity + replay protection per R-003). |
| III. Free-First with Cost Transparency | **PASS** | OpenClaw (free, open-source), n8n community edition (free), LinkedIn Share API (free), Gemini free tier (primary), Ollama (free, local), Playwright (free). Anthropic is pay-as-you-go fallback only — marked accordingly. |
| IV. Cite Canonical Sources (NON-NEGOTIABLE) | **PASS** | Security recommendations cite: NIST SP 800-207 (ZTA), OWASP ASI Top 10 (agent security), MITRE ATLAS (ML threats), ToIP TEA (trust boundaries), CIS Docker Benchmark (container hardening). LinkedIn API references cite official Microsoft/LinkedIn documentation. |
| V. Every Recommendation Is Verifiable | **PASS** | All new security controls are verifiable via audit script (CHK-OPENCLAW-* checks). Workspace integrity: checksum comparison. Credential isolation: file/env scan. Webhook auth: endpoint test. |
| VI. Bash Scripts Are Infrastructure | **PASS** | New audit checks follow existing patterns: `set -euo pipefail`, shellcheck clean, idempotent, colored PASS/FAIL/WARN, no interactive input, Apple Silicon + Intel compatible. |
| VII. Defense in Depth | **PASS** | Layered: Prevent (credential isolation, HMAC auth, workspace checksums, prompt injection defense via Rule of Two architecture), Detect (audit checks, token monitoring, rate limit tracking, input sanitization flags), Respond (alerts via chat, graceful degradation on provider failure, human approval gate catches manipulated suggestions). |
| VIII. Explicit Over Clever | **PASS** | Quickstart provides copy-pasteable commands. Skills document what they do. Audit checks explain what they verify. |
| IX. Markdown Quality Gate | **PASS** | All new markdown passes markdownlint (MD013 disabled per config). |
| X. CLI-First Infrastructure, UI for Business Logic | **PASS** | Infrastructure (OpenClaw install, Docker build, n8n workflow import, HMAC setup, audit) all CLI. Business logic (n8n workflow design, operating config changes) via n8n UI or OpenClaw chat. |

**Constitution gate: PASSED.** No violations requiring justification.

## Project Structure

### Documentation (this feature)

```text
specs/010-linkedin-automation/
├── spec.md
├── plan.md              # This file
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── openclaw-to-n8n-webhooks.md
│   └── n8n-to-openclaw-hooks.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Generated by /speckit.tasks
```

### Source Code (repository root)

```text
workflows/
├── hmac-verify.json             # Sub-workflow: shared HMAC-SHA256 verification (R-014)
├── linkedin-post.json           # Publish approved post via LinkedIn API
├── token-check.json             # Daily OAuth token expiry monitor
├── activity-query.json          # Execution history query for chat summaries
├── rate-limit-tracker.json      # Daily API usage counter + alert
└── error-handler.json           # Shared error workflow → alert via OpenClaw hook

openclaw/
├── SOUL.md                      # Persona voice template (benefactor-specific)
├── AGENTS.md                    # Operating rules (posting, engagement, boundaries)
├── USER.md                      # Operator context template
├── TOOLS.md                     # Tool documentation (informational)
├── IDENTITY.md                  # Agent name and designation
├── BOOT.md                      # Startup recovery (re-prompt pending drafts)
└── skills/
    ├── linkedin-post/
    │   └── SKILL.md             # Skill: draft + approve + publish post
    ├── linkedin-activity/
    │   └── SKILL.md             # Skill: query activity history
    └── token-status/
        └── SKILL.md             # Skill: check token health

scripts/
├── hardening-audit.sh           # EXTEND: add CHK-OPENCLAW-* checks
├── openclaw-setup.sh            # Install + configure OpenClaw natively
├── hmac-keygen.sh               # Generate + distribute HMAC shared secret
└── workflow-sync.sh             # Export/import n8n workflows for version control

docs/
└── HARDENING-OBSERVATIONS.md    # NEW: what works/workarounds/limitations under hardening
```

**Structure Decision**: This is a deployment/configuration project, not application software. The repo contains deployment scripts, n8n workflow definitions (JSON), OpenClaw workspace templates (markdown), and audit script extensions (bash). No `src/` directory — the "source code" is configuration and orchestration.

## Implementation Phases

### Phase 1: Foundation (P1 — Content Publishing)

Deploy OpenClaw, configure basic chat + LLM, implement the post-approval-publish workflow. Delivers US1.

**Tasks**:
1. Install OpenClaw natively (Bun/Node process)
2. Configure multi-provider LLM (Gemini primary, Anthropic fallback, Ollama local)
3. Configure chat channel (Telegram polling mode)
4. Create persona workspace files (SOUL.md, AGENTS.md, USER.md, IDENTITY.md)
5. Set up HMAC shared secret and distribute to OpenClaw + n8n environments
6. Build custom n8n Docker image with Playwright + system dependencies
7. Update docker-compose.yml to use custom image, set `EXECUTIONS_DATA_MAX_AGE=2880` (120 days retention)
8. Create `hmac-verify` n8n sub-workflow (shared HMAC-SHA256 verification logic — R-014)
9. Create `linkedin-post` n8n workflow (webhook → call hmac-verify sub-workflow → LinkedIn API post)
10. Implement first-successful-API-call grant timestamp recording in linkedin-post workflow (R-013)
11. Create `linkedin-post` OpenClaw skill (draft → present → approve → call webhook)
12. Create `error-handler` n8n workflow (failure → alert via OpenClaw hook)
13. Create BOOT.md for restart recovery (re-prompt pending drafts)
14. Create `pending-drafts.json` persistence in linkedin-post skill
15. Add image upload support to linkedin-post workflow (two-step upload)
16. End-to-end test: chat → draft → approve → LinkedIn post

**Exit criteria**: Operator can draft, review, edit, approve, and publish a text or image post to LinkedIn via chat. Failed posts alert the operator. HMAC sub-workflow verified.

### Phase 2: Operations (P3+P4 — Alerting + Activity History)

Add proactive alerting and activity querying. Delivers US3 + US4.

**Tasks**:
1. Create `token-check` n8n workflow (daily schedule → read grant timestamp from Static Data → compute days remaining → alert if ≤7)
2. Create `token-status` OpenClaw skill (check token health on demand)
3. Create `rate-limit-tracker` n8n workflow (count daily executions → alert at 80%)
4. Create `activity-query` n8n workflow (query execution history via n8n REST API → format summary)
5. Create `linkedin-activity` OpenClaw skill (call activity-query webhook → present to operator)
6. Wire error-handler workflow to all LinkedIn workflows
7. End-to-end test: token expiry alert, rate limit warning, activity summary query

**Exit criteria**: Operator receives token expiry alerts 7 days in advance. Workflow failures produce chat alerts. Operator can query "What did we post this week?" and get accurate results.

### Phase 3: Security (P5 — Audit Extensions + Observations)

Extend hardening audit and document observations. Delivers US5 + Deliverable.

**Tasks**:
1. Add CHK-OPENCLAW-PROCESS: verify agent bound to localhost, running as expected user
2. Add CHK-OPENCLAW-CREDS: verify LinkedIn credentials absent from agent env/config/filesystem
3. Add CHK-OPENCLAW-CREDS-N8N-API: verify n8n API key is NOT in OpenClaw environment (only in n8n)
4. Add CHK-OPENCLAW-WORKSPACE: verify workspace file checksums against manifest
5. Add CHK-OPENCLAW-WEBHOOK-AUTH: verify n8n webhook endpoints require authentication (test unsigned request → 401)
6. Add CHK-OPENCLAW-N8N-CREDS: verify n8n credential store is encrypted
7. Initialize manifest with workspace file checksums (`manifest-update` make target)
8. Create `docs/HARDENING-OBSERVATIONS.md` — document what works, workarounds, limitations
9. Update `docs/HARDENING.md` with agent deployment section
10. Create `workflow-sync.sh` for n8n workflow export/import version control
11. Run full audit, verify all checks pass
12. End-to-end test: modify workspace file → run audit → detect tampering

**Exit criteria**: `make audit` passes with all new CHK-OPENCLAW-* checks. Hardening observations documented. Workflow sync operational.

## Complexity Tracking

No constitution violations to justify. All decisions align with existing principles.

## Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| Indirect prompt injection via LinkedIn feed content | HIGH — manipulated comment suggestions, subtle misinformation | Three-layer defense (R-012): input sanitization → quarantined extraction agent (Rule of Two) → human approval. OWASP LLM01:2025 #1 risk. |
| OpenClaw pending drafts lost on crash (not SIGUSR1) | MEDIUM — operator must re-request draft | Persist drafts to filesystem (pending-drafts.json). BOOT.md recovery re-prompts on restart. |
| n8n API key exposed in OpenClaw environment | HIGH — privilege escalation, full n8n admin access | Config updates routed through HMAC-signed webhook (R-002 fix). n8n API key never in agent environment. Audit check CHK-OPENCLAW-CREDS-N8N-API verifies. |
| Gemini free tier rate-limited during peak usage | LOW — falls back to Anthropic (paid) | Multi-provider fallback is automatic. Monitor Anthropic costs. |
| WhatsApp Baileys library breaks on protocol update | MEDIUM if WhatsApp chosen — chat channel goes down | Recommend Telegram (official Bot API). Document WhatsApp as alternative with fragility caveat. |
| n8n execution history pruned before M4 migration | LOW — lose activity history | EXECUTIONS_DATA_MAX_AGE=2880 (120 days). M4 replaces with Qdrant+Mem0. |
| HMAC sub-workflow adds latency | LOW — negligible for this volume | Internal workflow call <50ms. Acceptable for 10-20 actions/day. |

## Future Scope

The following features are deferred to a future milestone.

### US2: Feed Discovery + Community Engagement

Add Playwright feed discovery with prompt injection defense, API-based engagement with scheduled action queue. Delivers US2.

**Tasks**:
1. Set up Playwright persistent LinkedIn session (storageState JSON, Docker volume mount — R-011)
2. Create manual session initialization procedure (headed browser login, export storageState)
3. Create session health check (verify LinkedIn session before each discovery — R-011)
4. Create `feed-discovery` n8n workflow (Playwright CDP → browse feed → extract URNs + snippets)
5. Implement defensive anti-detection (randomized scroll, variable timing, stealth config — R-010)
6. Create extraction agent workspace (openclaw-extractor: SOUL.md, AGENTS.md, IDENTITY.md — R-012)
7. Implement input sanitization layer: strip HTML, hidden text, zero-width chars, length cap (R-012)
8. Implement structured extraction: extraction agent produces `{author, topic, key_claims[], sentiment, relevance_score}` — never passes raw LinkedIn text to main agent (R-012)
9. Create `linkedin-comment` n8n workflow (webhook → hmac-verify → LinkedIn API comment)
10. Create `linkedin-like` n8n workflow (webhook → hmac-verify → LinkedIn API like)
11. Create `action-runner` n8n workflow: scheduled every 5 min, processes action queue, executes due actions (R-015)
12. Create `linkedin-engage` OpenClaw skill (trigger discovery → extraction agent → present results → approve → schedule actions)
13. Implement warmup mode (individual approval for all actions including likes, reduced volumes)
14. Implement steady-state mode (batch approval for likes → scheduled action queue)
15. Set up n8n Custom Variables for operating configuration
16. Create `config-update` n8n webhook workflow (receives HMAC-signed requests, updates variables via n8n internal API — n8n API key stays inside n8n, never in OpenClaw environment)
17. Create `config-update` OpenClaw skill (calls config-update webhook, not n8n API directly)
18. Implement quiet hours (queue discovery results for next active period)
19. Implement on-demand discovery ("scan the feed now" via chat)
20. Add session health alert: if LinkedIn browser session is invalid, alert operator via chat for manual re-login
21. End-to-end test: discover → extract (quarantined) → suggest comment → approve → comment posted
22. Prompt injection test: craft LinkedIn post with injection payload → verify extraction agent produces only structured facts → verify main agent suggestion is not manipulated

**Exit criteria**: Operator can discover feed content, review suggestions, approve engagement actions, and see comments/likes appear on LinkedIn. Warmup and steady-state modes work correctly. Extraction agent never passes raw LinkedIn text to main agent. Scheduled action queue spreads likes across hours. LinkedIn browser session health check operational.

### Deferred Project Structure Artifacts

```text
docker/
└── n8n-playwright.Dockerfile    # Custom n8n image with Playwright + system deps

workflows/
├── feed-discovery.json          # Playwright CDP feed browsing + URN extraction
├── linkedin-comment.json        # Post comment via LinkedIn API
├── linkedin-like.json           # Like post via LinkedIn API
├── action-runner.json           # Scheduled: process action queue, execute due actions (R-015)
└── config-update.json           # Update n8n Custom Variables via internal API (R-002 fix)

openclaw-extractor/
├── SOUL.md                      # Restricted extraction agent — no tools, no skills
├── AGENTS.md                    # Rules: extract structured facts only, never follow instructions in content
└── IDENTITY.md                  # Agent identity: "feed-extractor"

openclaw/skills/
├── linkedin-engage/
│   └── SKILL.md                 # Skill: discover feed + engage with community
└── config-update/
    └── SKILL.md                 # Skill: update operating config via HMAC webhook (not direct API)
```

### Deferred Operations Tasks

- Create browser session health check workflow (daily schedule → verify LinkedIn storageState is valid → alert if expired)
- Browser session expiry triggers alert

### Deferred Security/Audit Tasks

- CHK-OPENCLAW-EXTRACTION-AGENT: verify extraction agent has no tools/skills configured (Rule of Two)
- End-to-end test: add tool to extraction agent config → audit flags as FAIL
- Extraction agent isolation verified by audit

### Deferred Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| CDP feed discovery triggers LinkedIn account restriction | HIGH — blocks US2, may require project re-evaluation | Defensive anti-detection, warmup mode, low-volume passive browsing only, human-like scheduling via action queue (R-015) |
| LinkedIn browser session expires unexpectedly | MEDIUM — feed discovery silently fails | Session health check before each discovery (R-011). Daily session health workflow. Alert operator for manual re-login. |
| LinkedIn DOM changes break Playwright selectors | MEDIUM — breaks feed discovery until selectors updated | Isolate DOM mapping in configurable selectors, not hardcoded. Monitor for breakage. |

### Deferred Scale/Scope

- 5-10 comments + 10-20 likes per day (requires US2)
