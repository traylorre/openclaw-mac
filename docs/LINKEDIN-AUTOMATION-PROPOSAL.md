# LinkedIn Automation Proposal

**Prepared by**: OpenClaw
**Date**: 2026-03-20
**Status**: Draft for review

---

## Executive Summary

This proposal outlines a hybrid approach to building a LinkedIn
presence as an industry thought leader and community voice. Rather
than relying entirely on browser automation (which carries account ban
risk), we combine LinkedIn's official API for safe content operations
with targeted browser automation only where the API has gaps.

The result: a chat-controlled content pipeline where Claude AI drafts
content, a human approves it, and the system posts and engages via
LinkedIn's legitimate API. Connection requests remain human-operated
to eliminate the highest-risk automation vector entirely.

---

## 1. The Problem with Pure Browser Automation

The initial approach considered was using Chrome DevTools Protocol (CDP)
to fully control a Chrome browser — automating all LinkedIn actions
(posting, commenting, connecting, browsing) through simulated browser
interactions.

**Why this is risky:**

- A brand new LinkedIn account with no real connections, posting
  AI-generated content, controlled via CDP automation, matches the exact
  pattern LinkedIn's ML detection has seen thousands of times.
- LinkedIn uses behavioral fingerprinting (click patterns, scroll speed,
  session timing), device/browser fingerprinting (CDP-controlled Chrome
  has detectable signatures), and new account throttling.
- If the account gets banned, LinkedIn flags the **phone number, device,
  and IP address** — recovery is not as simple as creating a new account.
- LinkedIn has sent cease-and-desist letters to companies doing
  automation. For a company in the "long cycle, high trust, B2B" space,
  getting caught violating LinkedIn ToS is itself a reputational risk
  with the exact audience you are trying to reach.
- CDP automation requires an account warmup period of 3-4 weeks before
  meaningful posting activity can begin.

**The alternative:** Use LinkedIn's own API for everything it supports
(which covers the majority of content operations), and reserve browser
automation for the narrow set of actions the API cannot perform.

---

## 2. LinkedIn API: What's Actually Available

LinkedIn provides official API access through their Developer Portal at
<https://www.linkedin.com/developers/>.

### Self-Serve Access (no approval needed, anyone can enable)

These are available immediately to any developer who creates a LinkedIn
app:

| Product | Permission | What It Does |
|---|---|---|
| **Share on LinkedIn** | `w_member_social` | Post, comment, and like posts on behalf of an authenticated member |
| Sign In with LinkedIn | `profile` | Retrieve member's name, headline, and photo |
| Sign In with LinkedIn | `email` | Retrieve member's primary email address |

**"Share on LinkedIn" is the key product.** It is free, instant, and
self-serve. Enable it under the Products tab of your LinkedIn developer
app.

### Requires Approval (Marketing Partner program)

These require applying as a LinkedIn Marketing Partner. Approval timeline
varies. Relevant for future phases (company page management, analytics):

| Permission | What It Does |
|---|---|
| `w_organization_social` | Post, comment, and like on behalf of a **company page** |
| `r_organization_social` | Read company page posts and comments |
| `rw_organization_admin` | Manage company pages, view analytics |
| `r_organization_admin` | Retrieve company page reporting data (followers, visitors, content analytics) |

For the initial phase, **only the self-serve "Share on LinkedIn" product
is needed.**

### What the API Supports for Content

The Share on LinkedIn API supports creating:

- **Text posts** — Plain text content shared to the feed
- **Article/URL shares** — Posts with a link, custom title, and description
- **Image shares** — Posts with uploaded images (two-step upload process)
- **Video shares** — Posts with uploaded video (same two-step process)
- **Comments** — On any post where you have the post's URN (unique
  identifier)
- **Likes** — On any post where you have the post's URN

All operations use OAuth 2.0 authentication and standard REST API calls.
No browser required.

### API Rate Limits

| Throttle Type | Daily Limit (UTC reset) |
|---|---|
| Per Member | 150 requests/day |
| Per Application | 100,000 requests/day |

150 requests per member per day is generous. Each post, comment, or like
is one request. A highly active human account might do 20-30 of these
actions per day. The limit is not a constraint.

### Authentication Lifecycle

LinkedIn OAuth access tokens expire after **60 days**. Programmatic
token refresh is only available to select LinkedIn partners. For
everyone else, refreshing requires the account holder to re-authorize
through a browser-based login flow.

In practice this means: **every ~55 days, someone will need to click
through a quick re-authorization flow** (takes 30 seconds if already
logged into LinkedIn). The system will alert via chat when the token
is approaching expiry. If this step is missed, the posting pipeline
stops until someone re-authorizes.

---

## 3. The Gap: What the API Cannot Do

LinkedIn deliberately restricts its API to prevent automated account
operation. The "Share on LinkedIn" product was designed for apps that
want a "Share to LinkedIn" button (like Medium or WordPress), not for
operating a social media persona.

| Activity | API Support | Notes |
|---|---|---|
| Post original content (text, images, articles, video) | **YES** | Full support via Share API |
| Comment on a specific post | **YES** | Requires the post's URN |
| Like a specific post | **YES** | Requires the post's URN |
| Upload images/video | **YES** | Two-step register + upload process |
| **Discover posts in the feed** | **NO** | No feed browsing API exists |
| **Search for people or companies** | **NO** | Locked behind Talent/Sales partner programs |
| **Send connection requests** | **NO** | No API at all |
| **Browse profiles** | **NO** | No API |
| **Send messages or InMail** | **NO** | No API |
| **Reshare someone else's post** | **NO** | Not in the consumer API |
| **View who liked/commented on a post** | **NO** | Not in the consumer API |
| **Read the LinkedIn feed** | **NO** | No API |

**The core gap:** The API lets you **broadcast** (post your own content)
but not **discover** (find relevant content and people to engage with).

A thought leader that only posts but never comments on others' content,
never connects with people, and never browses is not a community
member — it is a billboard. This is why a pure API approach is
insufficient, and why the hybrid approach is necessary.

---

## 4. Hybrid Approach: API + Targeted CDP

The hybrid approach uses each tool for what it does best:

```text
                        +--- LinkedIn API (safest available option)
                        |    - Post content (text, images, articles)
                        |    - Comment on posts (when you have the URN)
                        |    - Like posts (when you have the URN)
                        |
  Chat --> n8n --> Claude +
                        |
                        +--- Playwright CDP (use sparingly for discovery)
                             - Browse feed to discover relevant posts
                             - Capture post URNs to feed back to the API
                             - Observe community activity and trends
```

**Connection requests are handled by a human** (see Section 6).

### Why This Is Better Than CDP-Only

1. **Posting via API leaves no browser fingerprint.** LinkedIn cannot
   distinguish it from any other legitimate application using their API.
2. **CDP usage drops dramatically.** Instead of using CDP for every
   action (posting, commenting, liking, connecting, browsing), you only
   use it for passive browsing/discovery — which looks like normal user
   behavior (no typing, no form submissions, no button clicks).
3. **If CDP gets flagged, the posting pipeline still works.** The API
   operates independently of the browser session.
4. **The account is a legitimate API consumer.** Many real tools and
   platforms use the Share on LinkedIn API, so this is normal behavior
   for a LinkedIn account.
5. **Rate limiting is built in.** The API enforces 150 requests/day,
   which naturally prevents over-activity.

### Important caveat on CDP browsing

While CDP-based feed browsing has a low risk of detection (it looks like
someone scrolling through their feed), it still technically violates
LinkedIn's Terms of Service. This is the same ToS that every
social media management tool with "discovery" features operates under.
The risk is low but not zero — it exists and should be understood.

---

## 5. Activity Risk Ranking

All planned activities ranked by risk level, with recommended method and
suggested daily volumes:

| Activity | Method | Risk Level | Suggested Volume | Notes |
|---|---|---|---|---|
| Post original content | LinkedIn API | **Very Low** | 1-3/day | Official API; safest available method |
| Comment on others' posts | LinkedIn API | **Very Low** | 5-10/day | Official API; randomize timing to avoid patterns |
| Like posts | LinkedIn API | **Very Low** | 10-20/day | Official API; spread throughout the day |
| Browse feed for content | Playwright CDP | **Low** | A few sessions/day | Passive observation only; ToS gray area |
| Capture post URNs | Playwright CDP | **Low** | Part of browsing | Extracting identifiers from DOM |
| Connect with people who engaged with you | **Human** | **None** | As needed | Human judgment, no automation risk at all |
| Cold connect with strangers | **Avoid entirely** | **HIGH** | 0 | Highest ban risk, worst for reputation |

### Risk Level Definitions

- **None**: Human action. No ToS concern. No detection possible.
- **Very Low**: Uses official LinkedIn API as designed. Extremely
  unlikely to cause issues, but LinkedIn retains the right to review
  API app usage. Randomize action timing to avoid mechanical patterns.
- **Low**: Passive browser activity that is hard to distinguish from
  normal usage at reasonable volumes. Technically a ToS gray area.
- **HIGH**: Actively monitored by LinkedIn's anti-spam systems. Multiple
  independent detection signals. Account restriction likely.

### Timing Randomization

Even when using the official API, posting 8 comments at exactly 9:00 AM
every day is a detectable pattern. The system will randomize:

- Time of day for posts (within configurable "active hours")
- Gaps between comments and likes (variable delays)
- Volume per day (vary within the suggested ranges, not exact same count
  every day)

This mimics natural human behavior and avoids triggering pattern-based
detection.

---

## 6. Connection Requests: Why Humans Should Handle These

Connection requests are the single highest-risk automated action on
LinkedIn. The risk is **not just about speed** — LinkedIn monitors
multiple independent signals:

| Signal | What LinkedIn Watches | Why It Is Dangerous |
|---|---|---|
| **Volume** | New accounts are throttled to ~100 requests/week, sometimes less | Hitting the cap triggers immediate flags |
| **Acceptance rate** | If you send 50 and only 5 accept, that is a 10% rate | Low acceptance rate = spam. LinkedIn starts showing CAPTCHAs or restricting the account |
| **Pattern** | 20 requests to people at the same company, or all from the same search results page, in order | Humans do not connect this way — sequential patterns are bot signatures |
| **Profile visit to connect timing** | A real person visits a profile, reads for 30-90 seconds, maybe checks posts, then connects | Bot pattern: visit then immediate connect then next. Under 5 seconds on a profile is suspicious |
| **Personalization** | Blank connection requests ("I'd like to add you to my network") vs. personalized notes | Mass blank requests are a spam signal |
| **Reciprocity** | Real users receive incoming requests, not just send outgoing | An account that only sends and never receives is anomalous |
| **Reports** | Every connection request gives the recipient a "Report / I don't know this person" option | A few reports and the account gets restricted |

**Key insight:** LinkedIn's connection request monitoring is their
**anti-spam system**, not their anti-bot system. Real humans doing
aggressive cold outreach get flagged by the same system. The risk is not
about "acting like a human" — it is about **not acting like a spammer**,
which is a different (and actually easier) problem.

### Why Human-Operated Connections Work

For a thought leader persona, the connection strategy works in your
favor when handled by a human:

**Low-risk connections** (people likely to accept):

- People who commented on or liked your content (they already know you)
- People who post about your industry (fellow enthusiasts welcome
  community members)
- People at companies relevant to your business goals

**High-risk connections** (likely to ignore or report):

- Random executives cold-connected with pitches
- Mass outreach to people outside your community
- Anyone who has never interacted with your content

A human can make these judgment calls naturally. Automation cannot.

---

## 7. Recommended Content Flow

The recommended daily operation flow, designed to build the persona
organically and safely:

### Step 1: Post Great Content (API)

Claude AI generates draft content about your industry. Topics include
analysis, technical breakdowns, industry news commentary, and thought
leadership. A human reviews and approves each post via chat before the
system publishes it through the LinkedIn API.

**Volume:** 1-3 posts per day, at randomized times during active hours.

### Step 2: People Engage Organically

Good content attracts likes, comments, and profile views from the
community. This is organic growth driven by content quality.

### Step 3: Discover Relevant Community Content (CDP)

Playwright browses the LinkedIn feed at human pace to find posts about
your industry, relevant discussions, and community activity. It captures
post URNs (unique identifiers) for posts worth engaging with.

**Volume:** A few browsing sessions per day, mimicking normal usage
patterns.

### Step 4: Engage with Community (API)

Using the post URNs collected in Step 3, Claude drafts thoughtful
comments and the system posts them via the LinkedIn API. Likes are also
applied via the API. Actions are spread throughout the day with
randomized timing.

**Volume:** 5-10 comments and 10-20 likes per day, varied.

### Step 5: Connect with Engaged People (Human)

A human reviews who engaged with your content and sends personalized
connection requests to relevant people. This is the relationship-building
step that requires human judgment about who is worth connecting with and
what message to send.

**Volume:** As appropriate, using human judgment.

### Step 6: Repeat

The network grows organically. As the connection base expands, organic
reach increases, which brings more engagement, which creates more
connection opportunities. This is how real community builders operate —
it happens to also be the safest automation pattern.

---

## 8. Keeping Claude's Content Sharp

Claude AI can draft compelling general content, but a thought leader
persona needs specific, current knowledge about your industry that goes
beyond what any AI model has in its training data. Generic or
surface-level takes will damage credibility faster than not posting.

### How we address this

**Content knowledge base:** Before generating posts, Claude receives
context from a curated knowledge base that you maintain. This can be as
simple as a shared document or folder containing:

- Recent developments and news in your space
- Technical details and trends
- Key people and organizations
- Industry news links
- Opinions and angles you want to promote

**The human in the loop matters here.** Every post goes through human
approval before publishing. The approver catches anything that sounds
generic, gets a detail wrong, or misses the tone. Over time, Claude's
prompts get tuned based on what gets approved vs. rejected.

**RSS and news feeds:** The system can pull from industry news sources
to give Claude current context for each drafting session.

**What to expect:** Early content will need heavier editing. As the
prompt engineering improves (based on feedback from approved/rejected
posts), the approval rate will climb. Budget extra review time in the
first 2-3 weeks.

---

## 9. Architecture

The system runs on a Mac Mini with existing infrastructure from OpenClaw.

```text
Chat App <---> n8n (orchestration) <---> Claude API (content drafting)
                     |                           |
                     |                           v
                     |                    LinkedIn API (posting,
                     |                    commenting, liking)
                     |
                     +---> Playwright CDP (feed browsing,
                          post URN collection)
                                  |
                                  v
                            Google Sheets (activity log,
                            prospect tracking, content calendar)
```

### Components

| Component | Purpose | Status |
|---|---|---|
| **n8n** | Workflow orchestration, routes chat commands to appropriate actions | Running |
| **Chat Bot** | Human interface for approving content, issuing commands | New |
| **Claude API** | Content generation, comment drafting, trend analysis | New |
| **LinkedIn API** | Official posting, commenting, liking | New |
| **Playwright** | Browser control for feed discovery | New |
| **Google Sheets** | Activity logging, content calendar, prospect tracking | New |

### Chat Interface

The system needs a chat app for the operator to communicate with the
system. Two strong options:

**Telegram** — Free Bot API, no approval process, native n8n integration,
rich message formatting (approve/reject buttons), no phone verification
for the bot itself.

**WhatsApp** — WhatsApp Business API requires Meta business verification
and has usage costs. However, if your team already communicates via
WhatsApp, the familiarity may outweigh the setup friction.

**Question:** Which chat platform does your team prefer? Telegram is
faster to set up, but WhatsApp is supported if that is where your team
already operates.

### Network Security Note

For the chat bot to receive messages, the Mac Mini either needs a
publicly accessible URL (via Cloudflare Tunnel or similar), or the bot
can use **polling mode** — pulling messages instead of receiving pushes.
Polling requires no inbound ports, preserving the system's security
posture. The trade-off is slightly higher latency (seconds, not
milliseconds).

---

## 10. Costs

### Monthly operating costs

| Item | Cost | Notes |
|---|---|---|
| Claude API | ~$10-20/month | Content generation, comment drafting at proposed volumes |
| LinkedIn API | Free | Self-serve "Share on LinkedIn" product |
| Telegram Bot API | Free | Or WhatsApp Business: ~$0-15/month depending on volume |
| Google Sheets API | Free | Within standard usage limits |
| Playwright/Chrome | Free | Runs locally on the Mac Mini |
| Mac Mini operation | Already running | Existing infrastructure |
| **Total** | **~$10-35/month** | Primarily Claude API usage |

### One-time setup effort

The system requires initial development and configuration. Phase 1
(content pipeline) is the priority — see Section 13 for phasing.

---

## 11. Expected Outcomes

Building a LinkedIn presence from a new account is a long game. Here are
realistic expectations, not promises:

### Months 1-2 (Foundation)

- 30-60 published posts
- 50-150 followers (organic growth from content)
- Establishing the persona's voice and credibility
- Building initial engagement patterns
- Identifying key community members and conversations

### Months 3-4 (Traction)

- Recognizable name in the LinkedIn community
- Consistent engagement on community posts
- 200-500 followers
- Initial conversations with people at target companies
- Data on which content topics and formats perform best

### Months 5-6 (Leverage)

- Established credibility as a community voice
- Warm introductions becoming possible through built network
- Content strategy refined based on 4+ months of performance data
- 500-1,000+ followers (varies significantly by content quality and
  community size)

### What success is NOT

- This is not a lead gen machine that delivers 50 meetings in month one.
  This is a credibility and presence builder.
- Follower count alone is not the metric. Quality of connections and
  conversations in your space is what matters.
- If the content is not good, the system will post into the void
  regardless of how well the automation works.

---

## 12. What You Need to Provide

Before development begins:

1. **LinkedIn account** — Create the account that will serve as the
   persona. Use a real phone number and email. Important: let the account
   exist for a few days before registering a developer app against it.
   Fill in the profile fully (photo, headline, summary, work history)
   before any automated activity begins.
2. **LinkedIn developer app** — Create at
   <https://www.linkedin.com/developers/>, enable "Share on LinkedIn"
   product. This grants the `w_member_social` permission.
3. **Chat account** — For the operator who will approve content and
   manage the system. Telegram is recommended (see Section 9 for
   discussion), but confirm your preference.
4. **Google account** — For the Google Sheets output (activity log,
   content calendar).
5. **Content direction** — Key topics, tone of voice, any content
   boundaries or topics to avoid. What does the persona sound like?
   Provide 3-5 example posts or articles you admire for tone reference.
6. **Target community** — Specific people, companies, hashtags, or
   groups in your space to follow and engage with.
7. **Content knowledge base** — An initial set of links, facts, and
   context about your industry that Claude should know. This grows over
   time. Even a bullet-point doc is a good start.

---

## 13. Steps to Get Started

### Phase 1: Content Pipeline

- Set up LinkedIn developer app with Share on LinkedIn API access
- Create chat bot (Telegram or WhatsApp based on preference)
- Build n8n workflow: chat command -> Claude draft -> chat approval ->
  LinkedIn API post
- Set up Google Sheets activity logging
- Implement token expiry alerts (warn 7 days before the 60-day OAuth
  expiry)
- Begin posting content (1-2 posts/day during warmup)

**Effort estimate:** This is the core build. It involves OAuth
integration, n8n workflow design, Claude prompt engineering, and
Google Sheets setup. Expect iteration on the content prompts during
the first weeks of operation.

### Phase 2: Feed Discovery

- Add Playwright for feed browsing and post URN collection
- Build n8n workflow for automated commenting via API using collected
  URNs
- Human begins making connection requests to people who engage with
  content

**Effort estimate:** Playwright integration requires building a
lightweight browsing service and mapping LinkedIn's DOM to extract
post URNs. LinkedIn updates their DOM periodically, so this component
will need occasional maintenance.

### Phase 3: Optimization

- Tune Claude prompts based on content performance
- Expand engagement volume as the account establishes credibility
- Evaluate Marketing Partner application for company page management
  and analytics
- Consider additional social platforms (X/Twitter, YouTube) for
  presence expansion

---

## 14. Risks and Limitations

### Account risk

Even with the hybrid approach, there is no guarantee that the LinkedIn
account will not be flagged or restricted. The approach described here
significantly reduces risk compared to pure browser automation, but it
does not eliminate it. If the account is restricted, recovery options
are limited.

### Single point of failure

The system runs on one Mac Mini. If that machine goes down, all
automation stops until it is back online. There is no redundancy or
automatic failover. For an early-stage system, this is acceptable.
If reliability becomes critical, cloud hosting can be explored later.

### API stability

LinkedIn's consumer Share API currently uses the `ugcPosts` endpoint.
LinkedIn has been migrating their Marketing API to a newer Posts API.
While the consumer endpoint appears stable for now, LinkedIn could
deprecate or change it. If that happens, the posting integration will
need to be updated. We will monitor LinkedIn's developer changelog for
breaking changes.

### New account + developer app

Creating a brand new LinkedIn account and immediately registering a
developer app is an unusual combination. Most legitimate Share on
LinkedIn integrations come from established accounts. To mitigate:
set up the account first, complete the profile, browse manually for
a few days, then register the developer app. Do not rush this
sequencing.

### LinkedIn's AI content policy

LinkedIn has been increasingly flagging and de-prioritizing content
it detects as AI-generated. The human approval step helps here — the
approver can edit content to add personal voice, specific details, and
natural language that pure AI output often lacks. Posting AI-generated
content without any human editing is likely to perform poorly in
LinkedIn's algorithm over time.

### Token renewal

Every ~60 days, someone must re-authorize the LinkedIn OAuth token
through a browser login. This takes 30 seconds but must not be
forgotten. The system will alert via chat 7 days before expiry.

---

*This document is a proposal for review. Implementation details,
timeline, and chat platform preference are subject to discussion
and confirmation.*
