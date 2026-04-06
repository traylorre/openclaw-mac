# Behaviors: The New Normal After Hardening

After running the setup guide, your repository behaves differently from
a normal git checkout. Files are locked, background services monitor
changes, and some operations require `sudo`. This document explains what
changed and how to work within the new constraints.

For **why** each restriction exists, see
[SECURITY-VALUE.md](SECURITY-VALUE.md). For how this compares to
NemoClaw's approach, see [FEATURE-COMPARISON.md](FEATURE-COMPARISON.md).

---

## Before vs After

| Behavior | Before Hardening | After Hardening |
|----------|-----------------|----------------|
| Edit any file | Open and save normally | Protected files are locked with `uchg` — edits silently fail |
| Run scripts | Execute directly | Some scripts require Bash 5.x (macOS ships 3.x) |
| Use `sudo` | Rarely needed | Required for integrity operations and audit fixes |
| Background processes | None from this repo | Two LaunchAgent/Daemon services running |
| Environment variables | Set freely | 15 dangerous vars are blocked; will prevent agent startup |
| Agent skill files | Edit freely | Must be approved via allowlist after any change |
| Keychain | Not used by this repo | HMAC signing key stored in Keychain; required for startup |

---

## Critical — Will Block You

These issues will stop you in your tracks if you don't know about them.

### uchg Flags Prevent Edits Silently

Protected files (SOUL.md, AGENTS.md, TOOLS.md, skill files) have the
macOS `uchg` (user immutable) flag set. GUI editors (VS Code, Sublime)
may appear to save successfully but the changes will not persist.
Terminal editors (vim, nano) will show "Operation not permitted" errors.
Either way, the file remains unchanged.
([Why?](SECURITY-VALUE.md#filesystem-immutability))

**Fix**: Use the unlock/edit/lock workflow described below.

### Missing Keychain Key Blocks All Startups

The integrity framework requires an HMAC signing key stored in macOS
Keychain (service: `integrity-manifest-key`, account: `openclaw`). If
this key is missing — because you migrated to a new machine, restored
from a non-Keychain backup, or never ran `make hmac-setup` — all
integrity operations fail and the agent cannot start.

**Fix**: Run `make hmac-setup` to create a new key. Then run
`make manifest-update` to re-sign all files with the new key.

### Dangerous Environment Variables Block Agent Startup

If any of these 15 environment variables are set, the audit will FAIL
and agent startup may be blocked:

`DYLD_INSERT_LIBRARIES`, `DYLD_FRAMEWORK_PATH`, `DYLD_LIBRARY_PATH`,
`NODE_OPTIONS`, `LD_PRELOAD`, `BASH_ENV`, `ENV`, `PERL5OPT`,
`PYTHONPATH`, `PYTHONSTARTUP`, `RUBYOPT`, `JAVA_TOOL_OPTIONS`,
`_JAVA_OPTIONS`, `GIT_SSH`, `GIT_PROXY_COMMAND`

The audit also checks `HOME`, `PATH`, and `TMPDIR` for unexpected
values (18 total checks).

**Fix**: Unset the offending variable: `unset NODE_OPTIONS` (or remove
it from your shell profile).

### Do Not Run `make install` with sudo

Homebrew cannot run as root. Running `make install` with `sudo` will
break the bootstrap. The Makefile handles elevated privileges internally
where needed.

**Fix**: If you already ran with sudo, run `make uninstall` first, then
`make install` without sudo.

### Setup Order Matters

There is no dependency checking between make targets. Running them out
of order will fail silently or produce broken state:

1. `make install` (prerequisites)
2. `make audit` + `make fix` (baseline hardening)
3. `make runtime-setup` (before agents-setup)
4. `make agents-setup` (requires runtime)
5. `make integrity-deploy` + `make integrity-lock` (after agents)
6. `make monitor-setup` (after integrity)

---

## Good to Know — May Surprise You

### 5-Minute Grace Period During Unlock

When you run `make integrity-unlock`, there is a 5-minute grace period
during which the integrity monitor suppresses ALL alerts. This means
malicious edits made during the unlock window will not trigger
notifications. Always re-lock promptly.

### manifest.json Must Not Be Version-Controlled

`~/.openclaw/manifest.json` contains HMAC signatures specific to your
Keychain key. Committing it to git would break integrity verification
for anyone else who clones the repo (they have a different key).

### Moving the Repo Breaks Monitor Paths

The integrity monitor LaunchAgent uses absolute paths to the repository.
If you move the repo directory after running `make monitor-setup`, the
monitor breaks silently. Fix: run `make monitor-teardown` then
`make monitor-setup` from the new location.

### Audit Runs Sunday at 3am

The `com.openclaw.audit-cron` LaunchDaemon runs a full security audit
every Sunday at 03:00 as root. Results are saved to
`/opt/n8n/logs/audit/`. If your Mac is asleep at 3am, launchd will run
the audit when it next wakes.

### Bash 5.x Required

All scripts require Bash 5.x features (`set -euo pipefail`, associative
arrays, `[[ ]]`). macOS ships with Bash 3.x (due to GPL licensing).
`make install` installs Bash 5.x via Homebrew, but your shell profile
must use the Homebrew version: `/opt/homebrew/bin/bash` (Apple Silicon)
or `/usr/local/bin/bash` (Intel).

---

## How to Edit a Protected File

```bash
# 1. Unlock the workspace (starts 5-minute grace period)
make integrity-unlock

# 2. Make your edits
# (edit the file with any editor)

# 3. Re-lock the workspace
make integrity-lock

# 4. Re-sign the manifest
make manifest-update
```

> Always re-lock and re-sign immediately after editing. The 5-minute
> grace period suppresses ALL monitoring alerts.

---

## How to Add or Modify a Skill

```bash
# 1. Unlock the workspace
make integrity-unlock

# 2. Edit the SKILL.md file
# (edit with any editor)

# 3. Approve the new content hash
make skillallow-add

# 4. Re-lock the workspace
make integrity-lock

# 5. Re-sign the manifest
make manifest-update
```

If you skip step 3, the audit will flag the skill as a potential supply
chain risk (hash mismatch).

---

## What to Do When You See

### "Operation not permitted"

**Cause**: The file has the `uchg` (user immutable) flag set.

**Fix**: Run `make integrity-unlock`, edit the file, then
`make integrity-lock` and `make manifest-update`.

### "manifest signature mismatch"

**Cause**: A protected file was modified without re-signing the
manifest. This could be a legitimate edit you forgot to sign, or it
could indicate tampering.

**Fix**: If you made the edit intentionally, run `make manifest-update`.
If you did not make the edit, investigate — check `git diff` and the
audit log in `/opt/n8n/logs/audit/`.

### "Dangerous environment variable detected"

**Cause**: One of the 15 blocked environment variables is set in your
shell.

**Fix**: Unset it: `unset VARIABLE_NAME`. Check your `~/.zshrc` or
`~/.bashrc` for the offending export and remove or comment it out.

### "Keychain item not found"

**Cause**: The HMAC signing key is missing from macOS Keychain.

**Fix**: Run `make hmac-setup` to create a new key, then
`make manifest-update` to re-sign all files.

### "integrity monitor heartbeat stale"

**Cause**: The fswatch monitor process has stopped running. Either it
crashed, was killed, or the LaunchAgent failed to start.

**Fix**: Run `make monitor-status` to check. If down, run
`make monitor-teardown` then `make monitor-setup` to restart.

---

## Services Running in Background

| Service | Type | Level | Schedule | Purpose |
|---------|------|-------|----------|---------|
| `com.openclaw.integrity-monitor` | LaunchAgent | User | KeepAlive (always running) | Watches protected files via fswatch; writes 30-second heartbeats |
| `com.openclaw.audit-cron` | LaunchDaemon | Root | Weekly, Sunday 03:00 | Runs full 84-check security audit; saves results to audit log |

Check status: `make monitor-status` (integrity monitor) or
`launchctl list | grep openclaw` (both services).

---

## Files Outside the Repo

These files live in `~/.openclaw/` and are NOT version-controlled:

| File | Purpose |
|------|---------|
| `manifest.json` | HMAC-signed integrity manifest (file hashes + signatures) |
| `lock-state.json` | Per-file unlock records with timestamps |
| `skill-allowlist.json` | Approved skill content hashes with HMAC signatures |
| `openclaw.json` | Agent configuration |
| `.env` | Webhook secrets and API keys |

**Keychain entry**: `integrity-manifest-key` (service) /
`openclaw` (account) — the HMAC signing key used for manifest and
allowlist signatures.

> These files are machine-specific. Do not copy them between machines
> or commit them to git.

---

## Operations That Require sudo

| Operation | Why sudo? |
|-----------|----------|
| `make fix` | Modifies macOS system settings (firewall, sharing, etc.) |
| `make integrity-lock` | Sets `uchg` flags (requires root on some files) |
| `make integrity-unlock` | Removes `uchg` flags |
| `make monitor-setup` | Installs LaunchAgent plist |
| Scheduled audit | LaunchDaemon runs as root to access system settings |
| `visudo` | Edits the sudoers file (inherently privileged) |
