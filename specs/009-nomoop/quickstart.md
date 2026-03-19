# Quickstart: 009-nomoop

**Date**: 2026-03-18

## What NoMOOP Does

NoMOOP (No Matter Out Of Place) adds installation tracking and clean
uninstall to openclaw. Every file, directory, package, and config
change placed on your system is recorded in a manifest. You can
inspect what's installed, verify nothing has drifted, and cleanly
uninstall everything.

## Usage

### After Installation

```bash
# View what openclaw installed
openclaw manifest

# Verify all artifacts are present and unmodified
openclaw manifest --verify

# Get JSON output (for scripting)
openclaw manifest --json
```

### Clean Uninstall

```bash
# Preview what would be removed
openclaw uninstall --dry-run

# Remove everything (interactive confirmation)
openclaw uninstall

# Remove everything, skip confirmations
openclaw uninstall --force

# Remove everything except n8n data volumes
openclaw uninstall --keep-data

# Keep security hardening in place
openclaw uninstall --keep-hardening

# Approve each sudo command individually
openclaw uninstall --confirm

# Verify with JSON output (for scripting/audit)
openclaw manifest --verify --json
```

### Recovery

```bash
# Manifest was deleted or corrupted — rebuild from disk
openclaw manifest --rebuild

# Install was interrupted — just re-run
bash scripts/bootstrap.sh    # resumes from where it left off
```

## How It Works

1. **Install**: `bootstrap.sh`, `gateway-setup.sh`, and `hardening-fix.sh`
   record each artifact to `~/.openclaw/manifest.json` as they create it.
2. **Track**: The manifest stores path, type, checksum, version, timestamp,
   and whether the artifact pre-existed.
3. **Verify**: `openclaw manifest --verify` compares each entry
   against disk state (PRESENT, MISSING, DRIFTED, VERSION_DRIFT).
4. **Uninstall**: `openclaw uninstall` reads the manifest and removes
   artifacts in reverse order, respecting dependencies, shared
   packages, and pre-existing items. Hardening removals show security warnings.
5. **Report**: After uninstall, `~/.openclaw/uninstall-report.txt`
   documents what was removed, skipped, backed up, and what needs manual cleanup.
6. **Hardening Only**: `openclaw install --hardening-only` applies only
   security hardening without the full stack.

## File Layout

```text
~/.openclaw/
├── manifest.json          # Installation manifest (source of truth)
├── shellrc                # Shell config (aliases, exports)
├── backups/               # Modified files backed up during uninstall
└── uninstall-report.txt   # Generated after uninstall

scripts/
├── openclaw.sh            # CLI dispatcher (openclaw <command>)
├── lib/
│   └── manifest.sh        # Shared manifest + removal functions (460+ lines)
├── bootstrap.sh           # Updated: records artifacts to manifest
├── gateway-setup.sh       # Updated: records artifacts to manifest
└── hardening-fix.sh       # Updated: records hardening artifacts to manifest
```
