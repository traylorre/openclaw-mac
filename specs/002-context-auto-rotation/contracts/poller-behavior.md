# Contract: Idle-Detection Poller (carryover-poller.sh)

**Feature**: 002-context-auto-rotation
**Type**: Background process (not a hook — spawned by `carryover-detect.sh`)
**Lifecycle**: Spawned → polls tmux pane → sends /clear or times out → exits

## Spawn Method (FR-028)

```bash
(TMUX_PANE="$TMUX_PANE" nohup "$HOME/bin/carryover-poller.sh" </dev/null >/dev/null 2>&1 &)
```

- Outer `()` subshell: grandchild process (reparented to init on hook exit)
- `nohup`: ignores SIGHUP
- All fds → `/dev/null`: prevents corruption of hook's JSON stdout
- `$TMUX_PANE` explicitly passed as environment variable
- No `setsid` (not available on macOS)

## Initialization

1. Source `$HOME/bin/hook-common.sh` (with `HOOK_LOG_PREFIX="poller"`)
2. Validate `$TMUX_PANE` is set and non-empty — if empty, log error and exit 1 (cannot target pane)
3. Install EXIT trap: `trap 'rm -f .claude/carryover-pending.claimed' EXIT`
4. Record `start_time=$(date +%s)` for elapsed tracking
5. `mkdir -p .claude` (FR-031)

## Poll Loop

1. Run: `tmux capture-pane -p -t "$TMUX_PANE"`
2. If capture fails (non-zero exit): → timeout path
3. Strip ANSI escape codes: `sed 's/\x1b\[[0-9;]*m//g'`
4. Scan full pane output for 3 consecutive lines matching:
   - Line N: `^─{12,}` (separator — ≥12 box-drawing U+2500 characters)
   - Line N+1: `^❯` (prompt — U+276F heavy right-pointing angle quotation mark)
   - Line N+2: `^─{12,}` (separator)
5. Full pane scan required (not `tail -1`) because UI status elements may appear below prompt
6. If no match:
   - Calculate elapsed: `$(( $(date +%s) - start_time ))`
   - If elapsed ≥ 60 → timeout path
   - Else: `sleep 1`, goto step 1

## Claim Phase (prompt detected)

1. Atomic claim: `mv .claude/carryover-pending .claude/carryover-pending.claimed`
2. **mv fails** (source file gone): User already typed /clear → exit 0 silently
3. **mv succeeds** — poller owns /clear:
   a. Send banner: `tmux send-keys -t "$TMUX_PANE" '' Enter '# ⏳ Auto-clearing context — do NOT type /clear' Enter`
   b. Send /clear: `tmux send-keys -t "$TMUX_PANE" '/clear' Enter`
   c. Log: elapsed time, success
   d. Exit 0 (EXIT trap cleans `.claimed`)

## Timeout Path

Triggered by: 60-second timeout OR `tmux capture-pane` failure.

1. Write `.claude/carryover-clear-needed` (empty file)
2. Log error: reason (timeout or capture failure) + elapsed time
3. Exit 1 (EXIT trap cleans `.claimed` if it was created)

## Exit Behavior

All exits trigger the EXIT trap: `rm -f .claude/carryover-pending.claimed`

| Exit Code | Meaning |
|-----------|---------|
| 0 | /clear sent successfully, OR user already typed /clear |
| 1 | Timeout or capture-pane failure (carryover-clear-needed written) |

## Logging

All output via `hook-common.sh` to per-invocation file in `.claude/recovery-logs/` only (stderr is /dev/null).

Events logged:

| Event | Level | Content |
|-------|-------|---------|
| Poller started | INFO | `$TMUX_PANE` value |
| Prompt detected | INFO | Elapsed seconds |
| mv claim result | INFO | Success or "user already cleared" |
| Banner sent | INFO | — |
| /clear sent | INFO | Elapsed seconds |
| Timeout | ERROR | Elapsed seconds, reason |
| capture-pane failure | ERROR | Exit code |
| Exit | INFO | Final elapsed time |

## Timing Parameters

| Parameter | Value | FR |
|-----------|-------|-----|
| Poll interval | 1 second | FR-004 |
| Timeout | 60 seconds | FR-004 (updated from 30s, 2026-03-10) |
| Banner before /clear | Yes | FR-004 (added for double-/clear prevention) |

## Environment Variables

| Variable | Required | Usage |
|----------|----------|-------|
| `HOME` | Yes | Source hook-common.sh, locate scripts |
| `TMUX_PANE` | Yes | Target pane for capture-pane and send-keys |

## Crash Recovery

| Crash Point | Disk State | Recovery |
|-------------|-----------|----------|
| Before claim (polling) | `carryover-pending` exists | Startup loader finds pending + CARRYOVER, loads normally |
| After claim, before send-keys | `.claimed` exists | FR-029: startup loader deletes `.claimed`, loads CARRYOVER |
| After send-keys, before exit | `/clear` already sent | Session restarts normally; EXIT trap may not fire on SIGKILL |
| Timeout (clear-needed written) | `carryover-clear-needed` + `pending` | FR-030: startup injects reminder + loads CARRYOVER if present |
