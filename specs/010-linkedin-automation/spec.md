# Feature Specification: LinkedIn Automation

**Feature Branch**: `010-linkedin-automation`
**Created**: 2026-03-21
**Status**: Draft (post-adversarial review)
**Input**: User description: "M3: LinkedIn Automation — Native OpenClaw process orchestrating n8n workflows for LinkedIn automation on behalf of benefactor (code19.ai, F1 autonomous racing team)"

## User Scenarios & Testing

### User Story 1 — Operator Drafts and Publishes Content (Priority: P1)

The operator messages the AI agent via chat asking it to draft a LinkedIn post about a specific topic (e.g., "Draft a post about the latest autonomous racing technology from CES"). The agent uses its configured LLM and the persona's knowledge base to generate a draft. The operator reviews the draft in the chat conversation, requests edits if needed, then explicitly approves it. Only after approval does the system publish the post to LinkedIn via the official API. The operator receives confirmation with a link to the published post.

Content types include text posts, article/URL shares, and image posts. For image posts, the operator provides the image (via chat attachment or file reference) along with the post text.

**Why this priority**: Content creation and publishing is the core value proposition. Without this, no LinkedIn presence exists. This story also establishes the human approval gate — the most critical trust boundary in the system.

**Independent Test**: Can be fully tested by sending a chat message requesting a post, reviewing the draft, approving it, and confirming the post appears on LinkedIn. Delivers immediate value: published content on the benefactor's LinkedIn profile.

**Acceptance Scenarios**:

1. **Given** the operator is connected to the agent via chat, **When** the operator requests a post about a specific topic, **Then** the agent generates a draft incorporating the persona's voice and industry knowledge.
2. **Given** a draft is presented in chat, **When** the operator types "approve" (or equivalent), **Then** the system publishes the post to LinkedIn and confirms with a link.
3. **Given** a draft is presented in chat, **When** the operator requests changes (e.g., "make it shorter", "add a stat about lap times"), **Then** the agent revises the draft and presents it again for approval.
4. **Given** a draft is presented in chat, **When** the operator rejects it, **Then** the post is discarded and the system confirms no action was taken.
5. **Given** the LinkedIn API credential has expired, **When** the operator approves a post, **Then** the system alerts the operator that re-authorization is needed and does not attempt to post.
6. **Given** the operator sends an image via chat along with a post request, **When** the operator approves the draft, **Then** the system uploads the image and publishes the post with the image attached.
7. **Given** the operator requests an image post but does not provide an image, **When** the agent presents the draft, **Then** it prompts the operator to provide an image before approval.

---

### User Story 3 — System Alerts on Credential Expiry and Failures (Priority: P3)

The system monitors the health of its integrations — particularly the LinkedIn API credential lifecycle (OAuth tokens expire every 60 days). It alerts the operator via chat when the token is approaching expiry (7 days before), when a workflow fails, or when an unusual condition is detected (e.g., rate limit approaching, API errors). The operator can then take action (re-authorize, investigate, adjust posting volume).

**Why this priority**: Without proactive alerting, the system silently stops working when the OAuth token expires. For a reputation-building operation, a multi-day gap in activity because nobody noticed the token expired is a real risk. This story ensures operational continuity.

**Independent Test**: Can be tested by simulating a token approaching expiry and confirming the alert is delivered via chat. Delivers value: operational reliability without constant manual monitoring.

**Acceptance Scenarios**:

1. **Given** the LinkedIn OAuth token expires in 7 days, **When** the alert check runs, **Then** the operator receives a chat message with re-authorization instructions.
2. **Given** a content publishing workflow fails, **When** the failure is detected, **Then** the operator receives a chat message describing the failure and the affected post.
3. **Given** the daily API request count exceeds 80% of the rate limit, **When** the threshold is crossed, **Then** the operator receives a warning to reduce activity volume.

---

### User Story 4 — Operator Reviews Activity History (Priority: P4)

The operator asks the agent via chat about past activity — "What did we post this week?", "How many comments did we make yesterday?", "Show me our last 5 posts." The agent queries the activity log and presents a summary. This enables the operator to track the persona's activity and ensure it aligns with the content strategy.

**Why this priority**: Visibility into past activity is essential for strategy refinement and ensuring the persona's behavior matches the plan. Lower priority than the core posting/engagement loop because the system still functions without it.

**Independent Test**: Can be tested by posting several pieces of content, then asking the agent for a summary and confirming accuracy. Delivers value: operational awareness without digging through LinkedIn manually.

**Acceptance Scenarios**:

1. **Given** the system has published 3 posts this week, **When** the operator asks "What did we post this week?", **Then** the agent lists each post with date, topic summary, and link.
2. **Given** the system has made 12 comments today, **When** the operator asks "How active were we today?", **Then** the agent provides a count of posts, comments, and likes with a brief summary.

---

### User Story 5 — Security Audit Covers Agent Deployment (Priority: P5)

The existing hardening audit is extended with new checks that verify the agent deployment is secure: the agent process is bound to localhost, credentials are not stored in the agent's accessible files, workspace files have not been tampered with, and the webhook communication channel between agent and orchestrator requires authentication.

**Why this priority**: The security posture established in M2 must extend to cover the new agent components. This is not blocking for initial operation (the trust boundary model handles credential isolation at the architecture level), but it provides ongoing verification.

**Independent Test**: Can be tested by running the security audit and confirming all new agent-related checks pass. Delivers value: continuous security verification of the agent deployment.

**Acceptance Scenarios**:

1. **Given** the agent is deployed and running, **When** the security audit runs, **Then** new agent-specific checks verify process binding, credential isolation, and workspace file integrity.
2. **Given** a workspace file (persona definition) has been modified outside of version control, **When** the audit runs, **Then** the tampering is detected and flagged.
3. **Given** the webhook channel between agent and orchestrator, **When** the audit runs, **Then** it verifies that authentication is required on all webhook endpoints.
4. **Given** the system's credential isolation architecture, **When** the audit runs, **Then** it verifies that LinkedIn credentials are not present in the agent's environment, configuration files, or accessible filesystem paths.

---

### Edge Cases

- What happens when the operator approves a post but the API returns an error? The system retries once, then alerts the operator with the error details. The post is saved for later retry.
- What happens when the LinkedIn account is restricted or flagged? The system classifies API errors by type: 401 (token expired — prompt re-auth), 429 (rate limited — reduce volume), 403 (account restricted or permission error — halt all automated activity and alert operator). On 403, all automated activity stops until the operator manually investigates and re-enables it via configuration.
- What happens when the LLM provider is unavailable? The system falls back to the next configured provider. If all providers are unavailable, it alerts the operator and queues the request.
- What happens when the operator sends a chat message while a workflow is in progress? The system processes messages sequentially and informs the operator if there is a pending operation.
- What happens when the agent process restarts? Pending content drafts are persisted and re-prompted to the operator. Activity log and configuration survive restarts.
- What happens when the operator sends an unsupported content type (e.g., "reshare this post")? The system informs the operator which content types are supported and suggests an alternative (e.g., "I can't reshare, but I can draft a post commenting on that article").

## Requirements

### Functional Requirements

#### Content and Approval

- **FR-001**: The system MUST provide a chat interface for the operator to interact with the agent (content requests, approvals, activity queries).
- **FR-002**: The system MUST generate content drafts using the configured LLM, informed by the persona's knowledge base, voice definition, and operating rules.
- **FR-003**: The system MUST NOT publish any content (posts or comments) to LinkedIn without explicit operator approval via chat.
- **FR-004**: The system MUST publish approved content to LinkedIn using the official API (text posts, article shares, image shares, comments, likes).
- **FR-005**: The system MUST support image posts, accepting images from the operator via chat and handling the upload process transparently.

#### Security and Credential Isolation

- **FR-006**: The system MUST isolate LinkedIn credentials from the agent process — the agent triggers actions but never accesses, stores, or transmits LinkedIn authentication tokens.
- **FR-007**: The system MUST authenticate all communication between the agent and the workflow orchestrator to prevent unauthorized localhost processes from triggering LinkedIn actions.

#### Operational Configuration

- **FR-011**: The system MUST support an operator-editable configuration that controls: quiet hours, volume limits per action type, and warmup/steady-state mode selection. This configuration MUST persist across system restarts.

#### Alerting and Monitoring

- **FR-014**: The system MUST alert the operator via chat at least 7 days before the LinkedIn API credential expires.
- **FR-015**: The system MUST alert the operator via chat when any workflow fails, including the failure reason and affected content.
- **FR-016**: The system MUST respect LinkedIn API rate limits (150 requests per member per day) and warn the operator when approaching the limit.

#### Activity and State

- **FR-017**: The system MUST maintain an activity log of all actions taken (posts, comments, likes, feed discoveries) that is queryable by the operator via chat.
- **FR-018**: The system MUST persist pending content drafts (not yet approved or rejected) across agent restarts, re-prompting the operator when the system recovers.
- **FR-019**: The system MUST support multiple LLM providers with fallback: a primary provider, a secondary provider, and a local fallback for embeddings and basic tasks.

#### Security Audit Integration

- **FR-020**: The system MUST verify the integrity of persona workspace files (voice definition, operating rules, tool definitions) to detect unauthorized modifications.
- **FR-021**: The system MUST NOT automate connection requests — these are explicitly reserved for human operation.
- **FR-022**: The system MUST integrate with the existing hardening audit, adding checks for agent process security, credential isolation, and workspace file integrity.
- **FR-023**: The system MUST support configurable daily volume limits for each action type (posts, comments, likes) within the ranges defined by the content strategy.

### Key Entities

- **Content Draft**: A piece of content (post, comment, article share, image post) generated by the agent, pending operator review. Has a lifecycle: drafted → presented → approved/rejected/edited → published/discarded. Persists across agent restarts.
- **Activity Record**: A log entry for any action taken by the system — posts published, comments made, likes given, feed sessions conducted, alerts sent. Includes timestamp, action type, target, and outcome.
- **Persona Configuration**: The set of files defining the agent's voice, knowledge, operating rules, and boundaries. Version-controlled and integrity-checked.
- **Credential Lifecycle State**: The current status of the LinkedIn API credential — healthy, expiring soon, expired, or refresh failed. Covers both the OAuth access token (60-day TTL, automated refresh) and the refresh token (365-day TTL, manual re-auth on expiry). Automated refresh occurs when the access token has ≤7 days remaining and the refresh token is valid. Note: increased blast radius under ASI04 — a compromised refresh token grants persistent access for up to 365 days vs. the previous 60-day window. Mitigated by n8n credential isolation (agent never holds tokens) and the circuit breaker pattern in the token-check workflow.
- **Operating Configuration**: The operator-defined parameters controlling system behavior — quiet hours, volume limits, warmup/steady-state mode. Persists across restarts. Editable without restarting the system.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Operator can go from content request to published LinkedIn post in under 5 minutes (including draft generation, review, and approval).
- **SC-002**: The hardening audit verifies that LinkedIn credentials are architecturally isolated from the agent process — credentials are absent from the agent's environment, config files, and accessible filesystem paths.
- **SC-003**: All content published to LinkedIn has been explicitly approved by a human operator — zero unapproved posts.
- **SC-004**: The system publishes 1-3 posts per day, with timing randomized across configurable active hours.
- **SC-005**: The operator is alerted at least 7 days before credential expiry, with zero instances of the system silently stopping due to expired credentials.
- **SC-006**: The existing hardening audit is extended with agent-specific checks that all pass.
- **SC-007**: Activity history is queryable via chat — the operator can retrieve a summary of the past 7 days of activity in under 30 seconds.
- **SC-008**: When the primary LLM provider is unavailable, the system automatically falls back to the secondary provider with no operator intervention required.
- **SC-010**: Workspace file integrity checks detect unauthorized modifications within one audit cycle.
- **SC-011**: Pending content drafts survive agent restarts — the operator is re-prompted with any drafts that were awaiting approval.

## Assumptions

- The benefactor will provide a LinkedIn account with a completed profile (photo, headline, summary, work history) before automation begins.
- The benefactor will create a LinkedIn developer app and enable the "Share on LinkedIn" self-serve product.
- The benefactor will specify their preferred chat platform (Telegram or WhatsApp) for operator interaction.
- The benefactor will provide initial content direction: key topics, tone references, content boundaries, and target community context.
- The benefactor will follow the recommended account warmup sequence: complete profile, browse manually for several days, then register developer app, then enable automation in warmup mode.
- The existing n8n gateway (deployed in M1) is operational and will be extended with new workflows.
- The existing macOS hardening (established in M2) remains in place and provides the platform security baseline.
- The LinkedIn Share API (`w_member_social` permission) remains available as a self-serve product with the current capabilities and rate limits.
- The primary LLM provider's free tier provides sufficient capacity for LinkedIn content generation volumes (1-3 posts + 5-10 comments per day).
- Connection requests are entirely human-operated and out of scope for this system.
- Persistent memory (vector store + memory middleware) is out of scope for this milestone — activity logging uses the workflow orchestrator's built-in execution history.

## Scope Boundaries

### In Scope

- Agent deployment and configuration (native process, multi-provider LLM, chat interface)
- Content generation (text, article, image), human approval workflow, and API-based publishing
- Credential isolation architecture and webhook authentication
- Activity logging via orchestrator execution history
- Hardening audit extensions for agent-specific checks
- OAuth token lifecycle management and expiry alerting
- Timing randomization for all automated actions
- Operator-editable configuration (volumes, quiet hours, warmup mode)
- Warmup mode with stricter approval gates and reduced volumes
- Pending draft persistence across restarts

### Out of Scope

- Automated connection requests (explicitly human-operated)
- Company page management (requires Marketing Partner approval)
- Persistent vector memory (deferred to M4)
- Multi-agent deployment (future capability, single agent for M3)
- Cloud migration or redundancy
- Analytics dashboards or reporting beyond chat-based activity queries
- RSS/news feed integration for content inspiration (nice-to-have, not required for M3)
- External logging platforms
- Video post support (can be added later; image and text are sufficient for launch)

## Deliverables

- **Hardening Observations Document**: A record of which activities work normally under the hardened macOS deployment, which require workarounds (e.g., CDP Chrome flags), and which are not possible. This document informs the M5 practitioner report and is maintained throughout M3 as observations accumulate.

## Dependencies

- **M1 (Gateway Live)**: Workflow orchestration backbone must be operational.
- **M2 (Security Baseline)**: macOS hardening and audit framework must be in place.
- **Benefactor inputs**: LinkedIn account, developer app, chat platform choice, content direction, and target community context.
- **LinkedIn API availability**: The Share on LinkedIn self-serve product must remain available with current capabilities.

## Future Scope

The following features are deferred to a future milestone.

### User Story 2 — Operator Engages with Community Content (Priority: P2)

The system discovers relevant posts in the LinkedIn feed (industry conversations, community discussions about autonomous racing, F1, motorsport technology). Discovery runs on a configurable schedule defined by the operator. The system presents summaries of discovered posts to the operator via chat with suggested comments. The operator can approve, edit, or skip each suggestion. Approved comments and likes are posted via the official API.

The operator controls discovery behavior through a persistent configuration: topics to watch, discovery schedule, quiet hours (when not to send notifications), and volume limits. The operator can also trigger discovery on demand via chat ("scan the feed now").

**Why this priority**: A thought leader who only broadcasts but never engages is a billboard, not a community member. Engagement drives organic growth and relationship-building. This is the second most important capability after posting.

**Independent Test**: Can be tested by triggering a feed discovery session, reviewing the presented posts and suggested comments, approving one, and confirming the comment appears on LinkedIn. Delivers value: active community participation.

**Acceptance Scenarios**:

1. **Given** the system has discovered relevant feed posts, **When** it presents them to the operator, **Then** each post summary includes the author, a snippet, and a suggested comment.
2. **Given** a suggested comment is presented, **When** the operator approves it, **Then** the comment is posted to the correct LinkedIn post via the API.
3. **Given** a suggested comment is presented, **When** the operator edits it before approving, **Then** the edited version is posted.
4. **Given** a post is presented, **When** the operator requests "like only", **Then** the system likes the post without commenting.
5. **Given** feed discovery finds no relevant posts, **When** the system reports to the operator, **Then** it suggests broadening topics or checking back later.
6. **Given** the operator has configured quiet hours (e.g., 10pm-7am), **When** discovery runs during quiet hours, **Then** results are queued and presented when the next active period begins.
7. **Given** the operator sends "scan the feed now" via chat, **When** the system receives the message, **Then** it triggers an immediate discovery session regardless of schedule.
8. **Given** the system is in warmup mode, **When** discovery presents posts for engagement, **Then** each like requires individual operator approval (no batch likes).
9. **Given** the system is in steady-state mode, **When** the operator approves a batch of likes (e.g., "like all 8"), **Then** the system likes all specified posts with randomized timing.

### Deferred Functional Requirements

#### Feed Discovery and Engagement

- **FR-008**: The system MUST discover relevant LinkedIn feed content for community engagement (posts about autonomous racing, F1, motorsport technology).
- **FR-009**: All browser-based feed discovery MUST be designed defensively to minimize bot detection risk per the documented anti-detection strategy: human-like browsing patterns, randomized session timing, configurable session duration, and no form interactions during discovery. Validated by SC-009. (Note: FR-009 applies to Playwright browsing sessions; FR-010 applies to all API-based actions.)
- **FR-010**: The system MUST randomize the timing of all automated actions (posts, comments, likes) to avoid detectable mechanical patterns. Engagement actions approved in batch MUST be spread across the day's active hours via a scheduled action queue, not executed in a burst.
- **FR-024**: The system MUST defend against indirect prompt injection (OWASP LLM01:2025) in content ingested from external feeds. Untrusted feed content MUST be sanitized (strip hidden text, zero-width characters, encoded payloads) and then processed through a restricted extraction process that produces structured facts only — never forwarding raw external text to the primary agent. The operator approval gate provides a final defense layer.
- **FR-025**: The system MUST manage the browser session used for feed discovery as a credential: monitor session health before each discovery session, alert the operator when the session expires, and provide documented procedures for manual re-login. Browser sessions MUST NOT be created via headless or incognito browsers (sessions expire within ~1 hour).

#### Operational Configuration (Deferred)

- **FR-012**: The system MUST support a warmup operating mode with reduced volumes and stricter approval gates (all actions including likes require individual approval, lower daily limits). The operator transitions to steady-state mode via configuration when the account is established.
- **FR-013**: The system MUST support on-demand discovery triggered by the operator via chat, in addition to scheduled discovery.

### Deferred Key Entities

- **Feed Discovery Result**: A relevant LinkedIn post found during feed browsing, including post identifier, author, content summary, and suggested engagement actions.
- **Browser Session State**: The authenticated browser session used for feed discovery. Created via manual headed browser login (not headless/incognito). Health-checked before each discovery session. Expires independently of OAuth tokens. Operator alerted on expiry for manual re-login.
- **Scheduled Action**: An engagement action (like, comment) approved by the operator and queued for execution at a computed future time. Actions are spread across the day's active hours to prevent burst patterns. Processed by a periodic runner.
- **Extraction Result**: Structured facts extracted from feed content by the restricted extraction process. Contains author, topic, key claims, sentiment, and relevance score. The primary agent receives only this structured output — never raw external content. This is the data boundary enforced by FR-024.

### Deferred Success Criteria

- **SC-004 (engagement)**: The system engages with 5-10 community posts per day, with timing randomized across configurable active hours.
- **SC-009**: Feed discovery sessions complete without triggering LinkedIn account restrictions over a 30-day observation period.

### Deferred Scope Items

- Feed discovery via browser automation for post identifiers, built defensively for anti-detection
- Community engagement (commenting, liking) via official API

### Deferred Assumptions

- If browser-based feed discovery proves incompatible with the hardened macOS deployment, the project scope may require fundamental re-evaluation (not just a workaround).

### Deferred Edge Cases

- What happens when feed discovery finds posts but the agent cannot generate relevant comments? The system presents the posts without comment suggestions and asks the operator if they want to engage manually.
