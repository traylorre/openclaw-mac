# Research: Chromium CDP Hardening

**Date**: 2026-03-16
**Feature**: 005-chromium-cdp-hardening

## R-001: Fix Classification for CDP and Dangerous Flags

**Decision**: Both `CHK-CHROMIUM-CDP` and `CHK-CHROMIUM-DANGERFLAGS`
fixes are classified as CONFIRMATION/INSTRUCTED — they print specific
remediation instructions but do not modify the system.

**Rationale**: The CDP port binding and launch flags are controlled
by whichever process launches Chromium (typically OpenClaw or a
custom automation script). The fix script cannot modify another
tool's configuration. The best it can do is tell the operator exactly
what to change and where.

**Alternatives considered**: Auto-killing the Chromium process and
restarting with correct flags. Rejected because this could disrupt
an active automation session and is destructive.

## R-002: Fix Classification for Version Update

**Decision**: `CHK-CHROMIUM-VERSION` fix is classified as SAFE —
it runs `brew upgrade --cask chromium` (or `google-chrome` if
Chrome is detected instead).

**Rationale**: Updating Chromium via Homebrew is idempotent and
non-destructive. If the browser is already current, the command
is a no-op. If Chromium is not installed via Homebrew, the fix
skips with a SKIPPED status and prints manual instructions.

**Alternatives considered**: Downloading the latest .dmg directly.
Rejected because it bypasses Homebrew's integrity verification
and doesn't integrate with the existing update workflow.

## R-003: Browser Profile Detection

**Decision**: Detect the active browser profile by checking these
paths in order:
1. `~/Library/Application Support/Chromium/Default/`
2. `~/Library/Application Support/Google/Chrome/Default/`
3. Accept a `--profile` argument for custom paths.

**Rationale**: These are the standard macOS profile directories for
Chromium and Chrome. Checking in order (Chromium first) matches the
audit script's preference for Chromium over Chrome.

**Alternatives considered**: Parsing `Local State` JSON for active
profiles. Rejected as overengineered — the Default profile is the
standard single-user case.

## R-004: What Session Data to Clean

**Decision**: Remove these files/directories from the profile:
- `Cookies` and `Cookies-journal` (SQLite)
- `Local Storage/` directory
- `Session Storage/` directory
- `History` and `History-journal` (SQLite)
- `Cache/` directory (or `Default/Cache/`)
- `Code Cache/` directory
- `Service Worker/` directory
- `GPUCache/` directory

**Rationale**: These contain the artifacts that expose an operator
after an automation session — session cookies (LinkedIn login),
browsing history, cached page content, and stored web data. Removing
them eliminates the persistence window.

**What we preserve**: Bookmarks, Extensions, managed policies,
preferences. These are configuration, not session data.

## R-005: Running Browser Detection

**Decision**: Check if Chromium is running by testing
`pgrep -f "Chromium|Google Chrome"`. If running, refuse cleanup
and warn the operator.

**Rationale**: Removing files from a running browser's profile
directory can cause data corruption or crashes. The browser must be
closed first.

**Alternatives considered**: Force-killing the browser before cleanup.
Rejected because it could interrupt an active automation session.

## R-006: Snapshot Integration

**Decision**: The version update fix (SAFE) records a snapshot entry.
The INSTRUCTED fixes (CDP, dangerflags) do not record snapshots
because they don't modify the system.

**Rationale**: Snapshots capture state changes so they can be
reversed. INSTRUCTED fixes only print instructions — there's nothing
to reverse. The version update is reversible via
`brew install --cask chromium@<old-version>` but Homebrew doesn't
support version pinning for casks natively, so the snapshot command
is informational only.
