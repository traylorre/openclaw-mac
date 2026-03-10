# Quickstart: Context Guardian Auto-Rotation

**Feature**: 002-context-auto-rotation
**Prerequisite**: Feature 003 (compaction-recovery) deployed to `~/bin/`

## Prerequisites

- Bash 5.x
- `jq` (`brew install jq` or `apt install jq`)
- `git`
- `tmux` (optional — required for zero-touch automation)
- Claude Code CLI installed
- Feature 003 scripts deployed: `~/bin/recovery-*.sh` symlinked from `~/dotfiles/scripts/bin/`
- Symlink infrastructure: `~/dotfiles/scripts/bin/` → `~/bin/`

## Step 1: Refactor hook-common.sh (003 prerequisite)

Extract shared utilities from 003's `recovery-common.sh` into a new `hook-common.sh`:

```bash
# 1. Create hook-common.sh with shared functions
#    (see research.md R-001 for function list)
vi ~/dotfiles/scripts/bin/hook-common.sh

# 2. Update recovery-common.sh to source hook-common.sh at top:
#    HOOK_LOG_PREFIX="recovery"
#    source "$HOME/bin/hook-common.sh"
#    (remove extracted functions from recovery-common.sh)

# 3. Symlink
ln -sf ~/dotfiles/scripts/bin/hook-common.sh ~/bin/hook-common.sh

# 4. Verify 003 still works
~/bin/recovery-health.sh
```

## Step 2: Deploy 002 scripts

```bash
# Copy scripts to dotfiles
# (implementation generates these files)

# Create symlinks
ln -sf ~/dotfiles/scripts/bin/carryover-detect.sh ~/bin/carryover-detect.sh
ln -sf ~/dotfiles/scripts/bin/carryover-poller.sh ~/bin/carryover-poller.sh
ln -sf ~/dotfiles/scripts/bin/carryover-loader.sh ~/bin/carryover-loader.sh

# Verify executable
chmod +x ~/dotfiles/scripts/bin/carryover-{detect,poller,loader}.sh
```

## Step 3: Update settings.json

Edit `~/dotfiles/claude/.claude/settings.json` to add these entries:

```json
{
  "hooks": {
    "PreToolUse": [
      "... existing context-guardian.sh (UNTOUCHED) ..."
    ],
    "PostToolUse": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "/home/zeebo/bin/carryover-detect.sh"
          }
        ]
      }
    ],
    "PreCompact": [
      "... existing recovery-precompact.sh (UNTOUCHED) ..."
    ],
    "SessionStart": [
      {
        "matcher": "compact",
        "hooks": [
          { "type": "command", "command": "/home/zeebo/bin/recovery-detect.sh", "timeout": 60 },
          { "type": "command", "command": "/home/zeebo/bin/carryover-loader.sh", "timeout": 30 }
        ]
      },
      {
        "matcher": "clear",
        "hooks": [
          { "type": "command", "command": "/home/zeebo/bin/recovery-loader.sh", "timeout": 30 },
          { "type": "command", "command": "/home/zeebo/bin/carryover-loader.sh", "timeout": 30 }
        ]
      },
      {
        "matcher": "startup",
        "hooks": [
          { "type": "command", "command": "/home/zeebo/bin/carryover-loader.sh", "timeout": 30 }
        ]
      }
    ],
    "Stop": [ "... existing (UNTOUCHED) ..." ],
    "Notification": [ "... existing (UNTOUCHED) ..." ]
  }
}
```

## Step 4: Verify installation

```bash
# Fast-path test: non-matching tool (should exit 0, no output)
echo '{"tool_name":"Read","tool_input":{}}' | ~/bin/carryover-detect.sh
echo "Exit: $?"

# Non-matching file (should exit 0, no output)
echo '{"tool_name":"Write","tool_input":{"file_path":"/tmp/README.md"}}' | ~/bin/carryover-detect.sh
echo "Exit: $?"

# Loader with no carryover (should exit 0, no output)
echo '{"source":"clear","session_id":"test"}' | ~/bin/carryover-loader.sh
echo "Exit: $?"

# Check log file was created
cat .claude/recovery-logs/hooks.log
```

## Step 5: End-to-end smoke test

1. Start a Claude Code session in tmux on a feature branch (e.g., `002-context-auto-rotation`)
2. Manually create a test carryover file:
   ```bash
   echo -e "# Test Carryover\n\nThis is a test carryover file for smoke testing." \
     > specs/002-context-auto-rotation/CONTEXT-CARRYOVER-99.md
   ```
3. Type `/clear` in the Claude Code session
4. Observe: the model's first response should include the carryover content
5. Verify: `ls specs/002-context-auto-rotation/CONTEXT-CARRYOVER-99.md.loaded` (file was consumed)

## Troubleshooting

| Symptom | Check | Fix |
|---------|-------|-----|
| Hook never fires | `cat .claude/recovery-logs/hooks.log` | Verify settings.json syntax, script permissions |
| "jq not found" | `which jq` | `brew install jq` / `apt install jq` |
| "hook-common.sh not found" | `ls -la ~/bin/hook-common.sh` | Re-run symlink setup |
| Poller not spawning | `echo $TMUX` (should be non-empty in tmux) | Run inside tmux session |
| Wrong pane targeted | `echo $TMUX_PANE` | Verify pane ID matches Claude Code pane |
| Carryover not loaded | `git branch --show-current` → check `specs/<branch>/` exists | Switch to feature branch |
| Double-/clear warning | Check `.claude/recovery-logs/hooks.log` for "double-/clear detected" | Normal — FR-032 guard working |
