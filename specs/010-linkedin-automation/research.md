# Research: LinkedIn Automation (010)

**Date**: 2026-03-21
**Status**: Complete
**Spec**: [spec.md](spec.md)

## R-001: OpenClaw State Management and Draft Persistence

**Decision**: Use a hybrid approach — rely on OpenClaw's SQLite conversation history for draft content, and persist draft approval state in a mounted JSON file readable by both OpenClaw skills and n8n workflows.

**Rationale**: OpenClaw stores conversation history in SQLite (survives restarts), but its in-memory approval queue does NOT survive a full stop/start — only graceful SIGUSR1 restarts preserve queued entries (Issue #49692). Since conversation history persists, the agent can re-read the last unapproved draft from its conversation context on restart. A sidecar JSON file (`~/.openclaw/agents/<agentId>/pending-drafts.json`) tracks approval state explicitly, allowing the BOOT.md startup sequence to detect and re-prompt pending drafts.

**Alternatives considered**:
- n8n Workflow Static Data: Survives workflow restarts but not accessible to OpenClaw directly. Creates coupling.
- SQLite direct writes: OpenClaw's schema is not publicly documented; writing to it risks corruption.
- SIGUSR1-only restarts via launchd: Fragile — doesn't cover crashes or power loss.

## R-002: Operating Configuration Format

**Decision**: Use n8n Custom Variables for operator-configurable parameters (discovery schedule, volume limits, quiet hours, warmup mode). Expose a configuration skill in OpenClaw that updates these variables via the n8n REST API.

**Rationale**: n8n Custom Variables are the best fit — they persist across workflow executions, are readable via `$vars.myVariable` in workflow expressions, and can be updated via the n8n UI (for direct access) or the n8n REST API (for chat-based updates via an OpenClaw skill). This gives the operator two paths to change configuration: via chat ("set quiet hours to 10pm-7am") or via the n8n UI directly.

**Alternatives considered**:
- Mounted JSON config file: Requires container restart to pick up changes (n8n caches file reads). More complex to update from chat.
- Environment variables: Immutable at runtime. Cannot be changed without restarting the n8n container.
- Workflow Static Data: Read-write from within workflows but not accessible from n8n UI. Harder for operator to inspect/modify.

## R-003: HMAC Webhook Authentication

**Decision**: Implement HMAC-SHA256 signature verification using a Code node placed immediately after each Webhook trigger node in n8n. The shared secret is stored in n8n environment variables.

**Rationale**: n8n does not have built-in HMAC verification for webhooks (feature request pending: GitHub #13146). The established community pattern is a Code node that computes `HMAC-SHA256(secret, rawBody)` and compares it to the `X-Signature` header using `crypto.timingSafeEqual()`. The raw body must be used (not parsed-and-reserialized JSON) to ensure signature validity.

On the OpenClaw side, the skill that calls n8n webhooks computes the HMAC signature using the shared secret stored in an environment variable and sends it in the `X-Signature` header.

**Alternatives considered**:
- Header Auth (pre-shared token): Simpler but doesn't prove request integrity — only proves the caller knows the token. A replay attack could modify the body.
- JWT Auth: Overkill for localhost communication. Adds token generation complexity.
- Basic Auth: Weakest option. Credential transmitted in every request.

## R-004: Chat Interface Selection

**Decision**: Default to Telegram with polling mode. Document WhatsApp as an alternative.

**Rationale**: Telegram uses the official Bot API with long-polling (grammY runner). No inbound ports required. Stable, well-documented, and the most reliable OpenClaw channel integration. WhatsApp uses the unofficial Baileys library (reverse-engineers WhatsApp Web protocol), which can break on protocol updates. The benefactor's preference is unknown — the spec lists this as a benefactor input. Telegram is recommended as the default unless the benefactor specifically requests WhatsApp.

**Alternatives considered**:
- WhatsApp (Baileys): No inbound ports needed (persistent connection). But uses unofficial protocol — fragility risk. No Twilio/Business API needed (uses personal WhatsApp).
- Signal, Discord, Slack: All supported but less natural for a 1:1 operator-agent workflow.

## R-005: Playwright in n8n Docker

**Status: Future**

**Decision**: Use the `n8n-nodes-playwright` community node installed in a custom Docker image extending the official n8n image.

**Rationale**: The community node provides a dedicated Playwright node with operations for navigate, screenshot, extract text, click, and execute custom JavaScript. It supports headless Chromium in Docker. Requires a custom Dockerfile that installs system dependencies (~1GB additional disk for browser binaries). This is preferable to raw Code node usage because it provides structured operations and error handling.

**Alternatives considered**:
- Code node with raw Playwright: More flexible but less maintainable. No structured operations.
- Separate Playwright container (Browserless): Additional infrastructure. Overkill for periodic feed browsing.
- Apify actor for LinkedIn browsing: Third-party dependency. Costs money. Violates Free-First principle.

## R-006: LinkedIn OAuth Token Lifecycle

**Decision**: Track dual tokens — access token (60-day TTL) and refresh token (365-day TTL) — in n8n Workflow Static Data. Automate access token refresh when ≤7 days remain. Alert the operator when the refresh token approaches expiry (30-day warning) or when automated refresh fails.

**Rationale**: LinkedIn extended programmatic refresh token support to consumer apps with `w_member_social` scope in late 2025. This supersedes the original conclusion that programmatic refresh was partner-only. Consumer apps now receive a 365-day refresh token alongside the 60-day access token during the OAuth authorization flow. When a refresh token generates a new access token, the refresh token TTL remains fixed at 365 days from original issue (it does not reset). This reduces the manual re-authorization cadence from every 60 days to approximately once per year. The token-check workflow implements automated refresh with error handling, circuit breaker logic, and retry with backoff for transient LinkedIn API failures.

**Reference**: Microsoft Learn — LinkedIn API OAuth documentation (updated late 2025)

**Alternatives considered**:
- Manual re-auth every 60 days (original design): Rejected — automated refresh is now available and reduces operational burden from bi-monthly to yearly.
- Error-based detection: Wait for API calls to fail with 401, then alert. Too late — the operator needs advance warning.
- n8n credential metadata API: Does not exist. Credentials are opaque to workflows.
- External cron job: Adds complexity outside the n8n ecosystem.

## R-007: Activity Log via n8n Execution History

**Decision**: Use n8n's REST API (`GET /api/v1/executions`) to query execution history. Build an OpenClaw skill that calls this API and formats results for chat.

**Rationale**: n8n's execution history stores per-execution metadata (workflow ID, status, start/stop times) and with `includeData=true`, full node-level input/output data. This is queryable via the REST API using an API key. An OpenClaw skill can call this API, filter by workflow ID and date range, and present a formatted summary to the operator. This avoids building a separate activity log — the orchestrator's execution history IS the activity log until M4 adds persistent memory.

**Alternatives considered**:
- Separate activity log file: Duplicates data already in n8n. Maintenance burden.
- SQLite activity database: Over-engineering for M3. Deferred to M4 (Qdrant + Mem0).
- n8n workflow that writes to a log file: Adds complexity to every workflow. Fragile.

## R-008: Workspace File Integrity Verification

**Decision**: Store SHA-256 checksums of workspace files in the manifest (`~/.openclaw/manifest.json`, managed by jq). The hardening audit script compares current checksums against stored values.

**Rationale**: This aligns with the existing `009-nomoop` feature's manifest pattern — checksums are already used for other integrity verification in this project. The audit script reads the manifest, computes current checksums of SOUL.md, AGENTS.md, TOOLS.md, USER.md, IDENTITY.md, and compares. Mismatches are flagged as WARN (not FAIL) because the operator may have intentionally updated the files — the check detects *unauthorized* changes, and the operator can update the manifest after intentional edits.

**Alternatives considered**:
- Git-based detection (`git diff`): Only works if workspace is in a git repo. The workspace directory (`~/.openclaw/agents/`) is not in the openclaw-mac repo.
- inotify/FSEvents watch: Real-time but requires a persistent daemon. Over-engineering for an audit-based approach.
- HMAC of files: Provides authentication (who changed it) in addition to integrity, but requires key management. Overkill for local tampering detection.

## R-009: n8n Workflow Version Control

**Decision**: Export workflows as individual JSON files using `n8n export:workflow --all --separate` into a `workflows/` directory in the repo. Import via `n8n import:workflow --separate --input=./workflows/`.

**Rationale**: The `--separate` flag creates one JSON file per workflow, ideal for git diffs and per-workflow change tracking. Exported JSON contains nodes, connections, and metadata but NOT credential secrets (only names/IDs). This aligns with Constitution Principle X (CLI-First Infrastructure). A Makefile target can automate export/import.

**Alternatives considered**:
- n8n built-in Git integration: Enterprise-only. Not available on community edition.
- Single combined JSON file: Poor git diffs. Can't track per-workflow changes.
- REST API export: More complex scripting. CLI is simpler and more reliable.

## R-010: Defensive CDP Anti-Detection Strategy

**Status: Future**

**Decision**: Implement multiple anti-detection layers for Playwright CDP feed browsing: randomized session timing, human-like scroll patterns, configurable session duration caps, no form interactions during discovery, and stealth browser configuration.

**Rationale**: LinkedIn uses behavioral fingerprinting (click patterns, scroll speed, session timing), device fingerprinting (CDP-controlled Chrome has detectable signatures), and new-account throttling. Passive browsing (scrolling, reading) has the lowest detection risk because it generates no write signals (no typing, clicking buttons, or form submissions). The defensive layers mimic natural browsing behavior:
1. Randomized gaps between scroll actions (2-8 seconds)
2. Variable scroll distances (not uniform pixel jumps)
3. Session durations that vary between 3-10 minutes
4. Sessions spaced throughout the day (not clustered)
5. Stealth Playwright configuration (evade `navigator.webdriver` detection)
6. No mouse movements to specific elements (only scroll-based browsing)

**Alternatives considered**:
- No anti-detection (rely on low volume): Risky for a new account. Volume alone doesn't prevent detection — behavioral patterns do.
- Residential proxy: Overkill and adds cost. The Mac Mini's IP is a residential IP already.
- Full CDP avoidance (API-only): Would eliminate US2 entirely. The API cannot discover feed content — this is the core gap that CDP fills.

## R-011: Playwright LinkedIn Session Management

**Status: Future**

**Decision**: Use Playwright `storageState` JSON (Option B) stored as a Docker volume-mounted file. Initial login performed manually in a headed, non-incognito browser. A health check at the start of each discovery session verifies the session is valid before browsing.

**Rationale**: LinkedIn's `li_at` cookie officially expires after 1 year, but real-world sessions last weeks to months. Critical gotcha: cookies from headless/incognito browsers may expire within ~1 hour. The initial login must be performed in a headed, non-incognito browser for session longevity. `storageState` JSON is lightweight (single file), inspectable, and easy to back up. The browser session lives inside n8n's Docker container — credential isolation model holds (OpenClaw never sees it).

**Session invalidation triggers** (from PhantomBuster research):
- "Slide and Spike" pattern: activity decline followed by sudden surge
- Erratic usage patterns
- IP address changes
- Tuesday/Wednesday peak enforcement

**Health check pattern**: Before each discovery session, attempt to load the LinkedIn feed. If redirected to login page, alert the operator for manual re-login. Do not attempt automated login.

**Alternatives considered**:
- Persistent browser context (`launchPersistentContext`): Full profile (~500MB+). Profile corruption risk. Only one instance at a time. Heavier than needed.
- Cookie injection (`li_at` + `JSESSIONID` only): Fragile — LinkedIn may add required cookies. Misses localStorage state.

## R-012: Feed Data Prompt Injection Defense

**Status: Future**

**Decision**: Three-layer defense: (1) input sanitization before any LLM processing, (2) separate extraction agent with no tools/skills processes sanitized content and produces structured facts, (3) main agent generates comment suggestions from structured facts only, never raw LinkedIn text. Human approval gate (already in spec) is the fourth layer.

**Rationale**: The "Attacker Moves Second" paper (Oct 2025) tested 12 published prompt injection defenses and bypassed all at 90%+ success rates with adaptive attacks. No prompting technique alone is sufficient. Meta AI's "Rule of Two" states an agent must satisfy no more than two of: (A) process untrusted input, (B) access sensitive data, (C) take external actions. Our architecture:
- Extraction agent: satisfies only (A) — no tools, no credentials, no actions
- Main agent: satisfies (B) and (C) — credentials and actions, but never sees raw untrusted content
- Human gate: catches any manipulation that survives extraction

**Input sanitization layer** (before extraction agent):
1. Strip HTML tags, hidden text, zero-width characters, invisible Unicode
2. Normalize whitespace, remove encoded payloads (base64, ROT13 strings)
3. Character length cap (~10K chars per post)
4. Detect and flag spoiler tags, collapsed sections (exact technique used in Perplexity Comet attack, Aug 2025)

**Extraction agent output contract**: Structured JSON only — `{author, topic, key_claims[], sentiment, relevance_score}`. No free-text passthrough of LinkedIn content.

**Alternatives considered**:
- Prompt-only defense (sandwich + delimiters): Bypassed at 90%+ rates per research. Insufficient alone.
- Output classifier (LLM Guard): High false positive rate on technical content. Good as additional layer but not primary defense.
- Human review only: Operator fatigue risk. Subtle manipulation (wrong technical claims, biased framing) may slip through. Perplexity Comet showed humans don't always notice.
- No defense (trust the LLM): Unacceptable given Constitution Principle II and the documented threat of adversarial content in scraped web data.

**References**:
- OWASP LLM01:2025 — Prompt Injection (#1 risk)
- Simon Willison: Dual LLM Pattern, Lethal Trifecta
- Meta AI: Rule of Two paper (Oct 2025)
- Anthropic: Prompt Injection Defenses (Opus 4.5 still ~1% breach rate)
- Brave/Perplexity Comet incident (Aug 2025) — injection via hidden Reddit content
- Google DeepMind CaMeL (Mar 2025) — formal data provenance tracking

## R-013: OAuth Grant Timestamp Recording

**Decision**: Use first-successful-API-call pattern. The first time any LinkedIn API workflow succeeds and no grant timestamp exists in Workflow Static Data, it records "now" as the grant timestamp. M4 (Qdrant+Mem0) will replace this with proper credential lifecycle tracking.

**Rationale**: Zero operator burden, automatic, close enough. Being off by a few hours on a 60-day window doesn't matter — the alert fires at 7 days remaining. n8n Community Edition does not support credential lifecycle events (Enterprise-only log streaming). The REST API does not expose credential creation timestamps. This is the simplest approach that works for M3.

**Alternatives considered**:
- Manual recording: Depends on operator remembering. Easy to forget.
- OAuth callback interception: Complex with n8n's built-in credential system. The OAuth flow is handled by n8n internally.
- Punt to M4: Risky — token will expire during M3 before M4 is built. System would silently stop.

## R-014: HMAC Centralization via Sub-Workflow

**Decision**: Use n8n sub-workflow pattern. A shared `hmac-verify` workflow handles all HMAC verification logic. Each webhook workflow calls it via "Execute Sub-workflow" as its first step. Single source of truth for HMAC logic.

**Rationale**: n8n has no gateway-level auth mechanism (no middleware, no global webhook settings). The sub-workflow pattern is the closest to centralized auth. Internal workflow calls add negligible latency for this use case. If n8n adds native HMAC support later, the sub-workflow becomes a thin wrapper.

**Community consensus**: For production deployments, the community recommends a reverse proxy (nginx/Caddy) in front of n8n for centralized auth. For localhost-only setups, per-webhook auth is standard. Our sub-workflow approach is a middle ground — centralized logic without additional infrastructure.

**Alternatives considered**:
- Duplicated Code nodes: N copies of same code. Maintenance burden when updating HMAC logic.
- Reverse proxy (nginx): True centralization but adds infrastructure. Over-engineering for localhost.

## R-015: Scheduled Action Queue for Engagement Timing

**Status: Future**

**Decision**: Implement a scheduled action queue. When the operator approves engagement actions (likes, comments), each action gets a scheduled timestamp spread across the day's active hours. A periodic action-runner workflow (every 5-10 minutes) checks the queue and executes actions whose timestamp has passed.

**Rationale**: Firing a batch of 8 likes with 2-5 minute delays still looks like a burst. Spreading them across hours (9:14am, 10:47am, 11:32am...) is indistinguishable from natural human behavior. The action runner wakes periodically and processes any due actions, naturally integrating with other system activity.

**Queue storage**: n8n Workflow Static Data (the action-runner workflow reads/writes the queue). Each queue entry: `{action_type, target_urn, content, scheduled_at, status}`.

**Alternatives considered**:
- Immediate execution with random delays: Still creates detectable bursts within a 10-30 minute window.
- n8n Schedule Trigger per action: Creates N scheduled workflow instances. Does not scale cleanly.
- External job queue: Over-engineering for the volume (10-20 actions/day).
