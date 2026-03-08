# Quickstart: Compaction Detection and Recovery

**Feature**: 003-compaction-recovery
**Prerequisites**: jq, git, tmux (optional, for zero-manual-step recovery)

## What This Does

When Claude Code auto-compacts your session context, this system:

1. **Detects** the compaction event via hooks
2. **Captures** what you were working on from the session transcript
3. **Audits** all post-compaction edits (which may be based on tainted context)
4. **Reverts** tainted edits automatically (in tmux) or with minimal manual steps
5. **Clears** the session and resumes the interrupted task with full context

## Setup

### 1. Install Scripts

Copy the recovery scripts to your dotfiles and symlink them:

```bash
# Scripts are in ~/dotfiles/scripts/bin/ (symlinked to ~/bin/)
chmod +x ~/dotfiles/scripts/bin/recovery-detect.sh
chmod +x ~/dotfiles/scripts/bin/recovery-precompact.sh
chmod +x ~/dotfiles/scripts/bin/recovery-loader.sh
chmod +x ~/dotfiles/scripts/bin/recovery-watcher.sh
chmod +x ~/dotfiles/scripts/bin/recovery-health.sh

# Ensure symlinks exist
ls -la ~/bin/recovery-*.sh
```

### 2. Configure Hooks

Add to `~/dotfiles/claude/.claude/settings.json` (which is symlinked to
`~/.claude/settings.json`):

```json
{
  "hooks": {
    "PreCompact": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/home/zeebo/bin/recovery-precompact.sh",
            "timeout": 30
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "compact",
        "hooks": [
          {
            "type": "command",
            "command": "/home/zeebo/bin/recovery-detect.sh",
            "timeout": 60
          }
        ]
      },
      {
        "matcher": "clear",
        "hooks": [
          {
            "type": "command",
            "command": "/home/zeebo/bin/recovery-loader.sh",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

**Note**: These hooks are added alongside the existing PreToolUse
(context-guardian.sh) and Stop/Notification hooks. The existing hooks
are not modified (FR-015).

### 3. Update compaction-audit Command

The existing `.claude/commands/compaction-audit.md` is extended with
`--batch` support. No new command file is needed.

### 4. Verify Installation

Run the health-check:

```bash
~/bin/recovery-health.sh
```

Expected output:

```text
Recovery Health Check
─────────────────────
✓ jq found (version 1.7)
✓ git found (version 2.43)
✓ tmux found (version 3.4)
✓ recovery-detect.sh exists and is executable
✓ recovery-precompact.sh exists and is executable
✓ recovery-loader.sh exists and is executable
✓ recovery-watcher.sh exists and is executable
✓ Hook config: PreCompact hook registered
✓ Hook config: SessionStart(compact) hook registered
✓ Hook config: SessionStart(clear) hook registered
✓ compaction-audit.md exists and contains --batch support
✓ .claude/ directory is writable
✓ recovery-logs/ directory exists
All checks passed.
```

## How It Works

### In tmux (fully automated — SC-004)

```text
You're working → compaction fires → PreCompact captures state
  → SessionStart injects "HALT, run audit" → model runs audit
  → model reverts tainted edits → watcher sends /clear
  → fresh session loads recovery context → model resumes your task
```

Zero manual steps required.

### Outside tmux (two manual steps — SC-005)

```text
You're working → compaction fires → hooks capture state
  → model tells you: "Run /compaction-audit"
  → you type: /compaction-audit
  → model shows revert plan, you confirm
  → model tells you: "Type /clear"
  → you type: /clear
  → fresh session loads recovery context → model resumes your task
```

## Dry Run (FR-051)

Test the recovery workflow without actual compaction:

```bash
# Simulate a PreCompact event
echo '{"session_id":"test-123","transcript_path":"","cwd":"'$(pwd)'","hook_event_name":"PreCompact"}' | ~/bin/recovery-precompact.sh --dry-run

# Simulate a SessionStart(compact) event
echo '{"session_id":"test-123","transcript_path":"","cwd":"'$(pwd)'","source":"compact","hook_event_name":"SessionStart"}' | ~/bin/recovery-detect.sh --dry-run

# Check what would be injected on /clear
echo '{"session_id":"test-456","cwd":"'$(pwd)'","source":"clear","hook_event_name":"SessionStart"}' | ~/bin/recovery-loader.sh --dry-run
```

## Troubleshooting

### Recovery didn't trigger after compaction

1. Run `~/bin/recovery-health.sh` to verify setup
2. Check if `.claude/recovery-marker.json` exists (PreCompact may have failed)
3. Check hook registration in `~/.claude/settings.json`

### Recovery log says "interrupted task unavailable"

The transcript was unavailable during capture. Possible causes:

- `transcript_path` field missing from hook input
- Transcript file permissions prevent reading
- Large transcript caused timeout during scanning

### Stale recovery marker blocking sessions

```bash
# Check marker age and session ID
cat .claude/recovery-marker.json | jq '{session_id, timestamp, stage}'

# If stale (>24h or wrong session), remove it
rm .claude/recovery-marker.json
```

### Recovery watcher didn't send /clear (tmux)

1. Check if `.claude/recovery-audit-complete` sentinel exists
2. Check if tmux pane is still accessible: `tmux list-panes`
3. Check watcher log output in the recovery log
