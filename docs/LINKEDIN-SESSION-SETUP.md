# LinkedIn Browser Session Setup

> **Status: Future** — This feature is deferred to a future milestone.

This document describes how to create and maintain the Playwright browser
session used for LinkedIn feed discovery.

## Why Manual Login Is Required

LinkedIn's feed is only visible to logged-in users. The browser session
(stored as a Playwright `storageState` JSON file) provides authenticated
access for feed browsing. This session is a credential — it lives inside
the n8n Docker container, never in OpenClaw.

## Critical: Use a Headed, Non-Incognito Browser

**Sessions created in headless or incognito browsers expire within ~1 hour.**
You MUST use a regular, headed browser window for the initial login.
This produces a long-lived session (weeks to months).

## Setup Procedure

### 1. Start Playwright in Headed Mode

On the Mac Mini (not remotely), run Playwright with a visible browser:

```bash
# From the openclaw-mac directory
npx playwright open --save-storage=linkedin-state.json https://www.linkedin.com/login
```

This opens a visible Chromium browser window.

### 2. Log In Manually

1. Enter the LinkedIn account credentials (email + password)
2. Complete any 2FA challenges
3. Wait for the LinkedIn feed to fully load
4. Verify you can see posts in the feed

### 3. Close the Browser

Close the Playwright browser window. The `linkedin-state.json` file is
now saved in the current directory with all cookies and localStorage.

### 4. Copy to Docker Volume

```bash
# Copy storageState to the Docker volume mount point
docker cp linkedin-state.json openclaw-n8n:/data/browser-profile/linkedin-state.json
```

Or if using a bind mount:

```bash
cp linkedin-state.json /path/to/browser-profile-volume/linkedin-state.json
```

### 5. Verify

Trigger a feed discovery session via chat ("scan the feed now") and
verify that posts are returned.

## Session Maintenance

### Session Expiry

LinkedIn sessions last weeks to months under normal conditions. The system
checks session health before each discovery session and daily via a
scheduled health check.

### Re-Login Triggers

You will receive a chat alert when the session expires. Triggers include:

- LinkedIn server-side session invalidation
- IP address change
- "Slide and Spike" activity pattern (decline followed by sudden surge)
- Extended inactivity

### Re-Login Procedure

When you receive a session expired alert:

1. Repeat steps 1-4 above
2. The system will automatically detect the fresh session on the next
   discovery attempt

### Avoid These Patterns

- **Tuesday/Wednesday** are peak LinkedIn enforcement days — avoid
  unusually high activity
- **Activity spikes** after a decline: maintain consistent daily activity
  levels
- **IP changes**: If the Mac Mini's IP changes, the session may be
  invalidated
