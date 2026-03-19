# CLI Contract: openclaw commands

**Date**: 2026-03-18 | **Feature**: 009-nomoop

## Entry Point

```text
scripts/openclaw.sh <command> [options]
```

Invoked via alias set in `~/.openclaw/shellrc`:
```bash
alias openclaw='bash /path/to/repo/scripts/openclaw.sh'
```

Or directly: `bash scripts/openclaw.sh <command> [options]`

---

## Command: `openclaw manifest`

Display the current installation manifest in human-readable table format.

**Usage**: `openclaw manifest [--verify] [--rebuild] [--json]`

### Subcommands / Flags

| Flag | Description |
|------|-------------|
| (none) | Print human-readable artifact table |
| `--verify` | Check each artifact against disk, report PRESENT/MISSING/DRIFTED |
| `--rebuild` | Scan known locations, reconstruct manifest from disk state |
| `--json` | Output raw JSON instead of table (composable with --verify) |

### Output: `openclaw manifest` (no flags)

```text
OpenClaw Manifest — 14 artifacts tracked
Repo: /Users/operator/projects/openclaw-mac

  TYPE               PATH                                          STATUS
  ─────────────────  ────────────────────────────────────────────  ──────────
  brew-package       colima                                        installed
  brew-package       docker                                        installed
  brew-package       docker-compose                                installed
  brew-package       jq                                            skipped (pre-existing)
  brew-package       bash                                          skipped (pre-existing)
  directory          /opt/n8n                                      installed
  file               /opt/n8n/scripts/hardening-audit.sh           installed
  file               /opt/n8n/etc/notify.conf                      installed
  launchd-plist      /Library/LaunchDaemons/com.openclaw.audit-cron.plist  installed
  keychain-entry     n8n-gateway-bearer                            installed
  docker-volume      templates_n8n_data                            installed
  shell-config-line  ~/.bash_profile                               installed
  shell-rc-file      ~/.openclaw/shellrc                           installed
  colima-vm          default                                       installed
```

**Exit code**: 0

### Output: `openclaw manifest --verify`

```text
OpenClaw Manifest Verify — 14 artifacts

  TYPE               PATH                                          STATUS
  ─────────────────  ────────────────────────────────────────────  ──────────
  brew-package       colima                                        PRESENT
  brew-package       docker                                        PRESENT
  file               /opt/n8n/scripts/hardening-audit.sh           PRESENT
  file               /opt/n8n/etc/notify.conf                      DRIFTED
                       Expected: a1b2c3...  Current: d4e5f6...
  launchd-plist      /Library/LaunchDaemons/com.openclaw...        MISSING
  ...

Summary: 12 PRESENT, 1 DRIFTED, 1 MISSING
```

**Exit codes**:
- 0: All artifacts PRESENT
- 1: One or more MISSING or DRIFTED

### Output: `openclaw manifest --rebuild`

```text
OpenClaw Manifest Rebuild
Scanning known artifact locations...

  Found: /opt/n8n/scripts/hardening-audit.sh (file)
  Found: /opt/n8n/etc/notify.conf (file)
  Found: colima (brew-package)
  ...
  Not found: /Library/LaunchDaemons/com.openclaw.audit-cron.plist

Rebuilt manifest with 12 artifacts (2 not found on disk).
Written to: ~/.openclaw/manifest.json
```

**Exit code**: 0 (always succeeds, reports what it found)

---

## Command: `openclaw uninstall`

Remove all openclaw artifacts tracked by the manifest.

**Usage**: `openclaw uninstall [--dry-run] [--force] [--keep-data]`

### Flags

| Flag | Description |
|------|-------------|
| (none) | Interactive: confirm before proceeding |
| `--dry-run` | Show what would be removed without removing |
| `--force` | Skip confirmation prompt |
| `--keep-data` | Remove everything except Docker volumes (preserve n8n data) |
| `--keep-hardening` | Skip removal of hardening-category artifacts; list as KEPT in report |
| `--confirm` | Show each sudo command and wait for y/N approval before executing |

### Output: `openclaw uninstall` (interactive)

```text
OpenClaw Uninstall
This will remove 14 tracked artifacts.
2 pre-existing items will be skipped.

Continue? [y/N] y

  [1/14] Stopping Docker containers...
  ✓ Stopped templates-n8n-1
  [2/14] Removing Docker containers...
  ✓ Removed templates-n8n-1
  [3/14] Removing Docker volumes...
  ✓ Removed templates_n8n_data
  [4/14] Stopping Colima...
  ✓ Stopped Colima VM
  [5/14] Removing Colima VM...
  ✓ Deleted Colima VM (default)
  ...
  [12/14] Removing shell source line from ~/.bash_profile...
  ✓ Removed source line
  [13/14] Removing ~/.openclaw/shellrc...
  ✓ Removed shellrc
  [14/14] Checking shared Homebrew packages...
  — docker: shared (used by docker-compose), not removed
  ✓ Removed docker-compose

Uninstall complete.
Report: ~/.openclaw/uninstall-report.txt
To fully clean up: rm -rf ~/.openclaw
```

**Exit codes**:
- 0: Uninstall completed successfully
- 1: One or more artifacts could not be removed (details in report)
- 2: No manifest found (suggest `openclaw manifest --rebuild`)

### Output: `openclaw uninstall --dry-run`

Same as above but prefixed with `[DRY RUN]` and no actual removal.

**Exit code**: 0 (always)

---

## Command: `openclaw install`

Not a new command — this documents the manifest-tracking additions
to existing `bootstrap.sh` and `gateway-setup.sh`.

These scripts gain a `--manifest` mode (default: on) that records
each artifact to `~/.openclaw/manifest.json` as it is created.

**Backward compatibility**: Scripts continue to work without the
manifest. The manifest functions are sourced from a shared library
(`scripts/lib/manifest.sh`) and gracefully no-op if jq is not
available.

**Usage**: `openclaw install [--hardening-only]`

| Flag | Description |
|------|-------------|
| (none) | Run bootstrap.sh + gateway-setup.sh with manifest tracking |
| `--hardening-only` | Apply only hardening artifacts (SSH config, pf rules, Chromium policy, service account, Spotlight exclusion) and record to manifest. Skips bootstrap/gateway. |
