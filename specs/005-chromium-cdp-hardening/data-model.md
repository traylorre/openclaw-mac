# Data Model: Chromium CDP Hardening

**Date**: 2026-03-16
**Feature**: 005-chromium-cdp-hardening

## Entities

### CDP Port Binding

Represents a detected Chrome DevTools Protocol listener.

| Attribute | Type | Description |
|-----------|------|-------------|
| port | integer | TCP port number (e.g., 9222, 18800) |
| bind_address | string | IP address bound to (127.0.0.1 or 0.0.0.0) |
| process_name | string | Name of the listening process |
| is_exposed | boolean | True if bound to non-localhost address |

### Dangerous Flag

A Chromium launch flag that weakens security.

| Attribute | Type | Description |
|-----------|------|-------------|
| flag | string | The full flag string (e.g., --no-sandbox) |
| source | enum | "process" (running) or "config" (openclaw.json) |
| risk | string | One-line explanation of what the flag disables |

**Known dangerous flags**:
- `--disable-web-security` — Disables same-origin policy
- `--no-sandbox` — Disables Chromium sandbox
- `--disable-site-isolation-trials` — Disables process-per-site
- `--disable-features=IsolateOrigins` — Disables origin isolation
- `--allow-running-insecure-content` — Allows HTTP on HTTPS pages
- `--remote-debugging-address=0.0.0.0` — Exposes CDP to network

### Browser Profile

A directory containing Chromium session data.

| Attribute | Type | Description |
|-----------|------|-------------|
| path | string | Absolute path to the profile directory |
| browser_type | enum | "chromium" or "chrome" |
| is_running | boolean | Whether the browser process is active |
| has_session_data | boolean | Whether cleanup-eligible files exist |

**Session data files** (cleanup targets):
- `Cookies`, `Cookies-journal`
- `Local Storage/`
- `Session Storage/`
- `History`, `History-journal`
- `Cache/`, `Code Cache/`
- `Service Worker/`
- `GPUCache/`

**Preserved files** (not cleaned):
- `Bookmarks`
- `Extensions/`
- `Preferences`
- `Managed Preferences/`

### Installation Method

How Chromium was installed, determining the update command.

| Method | Detection | Update Command |
|--------|-----------|----------------|
| Homebrew Chromium | `brew list --cask chromium` | `brew upgrade --cask chromium` |
| Homebrew Chrome | `brew list --cask google-chrome` | `brew upgrade --cask google-chrome` |
| Manual (.dmg) | App exists but not in Homebrew | INSTRUCTED (download from vendor) |

## Fix Function Registry

| CHK ID | Fix Type | Classification | Behavior |
|--------|----------|----------------|----------|
| CHK-CHROMIUM-CDP | INSTRUCTED | CONFIRMATION | Print correct launch flags |
| CHK-CHROMIUM-DANGERFLAGS | INSTRUCTED | CONFIRMATION | Name each bad flag with explanation |
| CHK-CHROMIUM-VERSION | AUTOMATED | SAFE | Run brew upgrade |
