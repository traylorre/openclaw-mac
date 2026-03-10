# Contract: PostToolUse Hook (carryover-detect.sh)

**Feature**: 002-context-auto-rotation
**Hook Event**: PostToolUse
**Matcher**: `.*` (all tool calls)
**Script**: `~/bin/carryover-detect.sh`
**Timeout**: Platform default (no override — hook completes in <200ms)

## Input (stdin JSON)

```json
{
  "session_id": "abc123-def456",
  "transcript_path": "/home/user/.claude/projects/.../session.jsonl",
  "cwd": "/home/user/projects/openclaw-mac",
  "permission_mode": "default",
  "hook_event_name": "PostToolUse",
  "tool_name": "Write",
  "tool_input": {
    "file_path": "/home/user/projects/openclaw-mac/specs/002/CONTEXT-CARRYOVER-01.md",
    "content": "..."
  },
  "tool_response": { "result": "..." },
  "tool_use_id": "toolu_..."
}
```

### Required Fields

| Field | Type | Usage |
|-------|------|-------|
| `tool_name` | string | Fast-path: only proceed for "Write" or "Edit" (FR-010) |
| `tool_input.file_path` | string | Basename extraction → regex match (FR-001) |

### Unused Fields

`session_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`, `tool_response`, `tool_use_id` — available but not read by this hook.

## Output (stdout JSON)

### Trigger Case (CARRYOVER detected, no recovery active)

```json
{
  "continue": false,
  "stopReason": "Context rotation: CARRYOVER saved. Type /clear to continue (auto-clear in progress if tmux detected)."
}
```

### Non-Trigger Case

No output. Empty stdout. Applies to:

- Non-Write/Edit tool calls (fast-path)
- Write/Edit of non-CARRYOVER files
- CARRYOVER match but recovery marker present (FR-016 suppression)
- Malformed/missing stdin JSON fields

## Exit Codes

| Code | Meaning | When |
|------|---------|------|
| 0 | Success (trigger or non-trigger) | Normal operation |
| 1 | Non-blocking error | Unexpected error during processing |
| 2 | Blocking error | `jq` not found (FR-024), `hook-common.sh` missing (FR-031) |

## Side Effects

| Action | Condition | FR |
|--------|-----------|-----|
| Write `.claude/carryover-pending` | CARRYOVER match + no recovery marker | FR-022 |
| `mkdir -p .claude` | Before signal file writes | FR-031 |
| Spawn `carryover-poller.sh` (background) | `$TMUX` is set and non-empty | FR-003, FR-028 |
| Log to per-invocation file in `.claude/recovery-logs/` (e.g., `carryover-detect.2026-03-10T14:32:01.log`) | All paths (best-effort) | FR-023 |

## Spawn Protocol (poller)

```bash
(TMUX_PANE="$TMUX_PANE" nohup "$HOME/bin/carryover-poller.sh" </dev/null >/dev/null 2>&1 &)
```

- Outer `()` subshell: poller becomes grandchild (reparented to init)
- `nohup`: ignores SIGHUP
- All fds → `/dev/null`: prevents stdout/stderr corruption of hook JSON output
- `$TMUX_PANE` explicitly passed: poller targets correct pane (FR-028)
- No `setsid`: not available on macOS

## Performance

| Path | Target | Notes |
|------|--------|-------|
| Non-Write/Edit tool | <10ms | Single jq field extraction + string compare |
| Write/Edit, non-CARRYOVER file | <200ms (SC-005) | Basename extraction + regex |
| CARRYOVER match (full trigger) | <200ms | JSON output; poller spawn is async |

## Environment Variables

| Variable | Required | Usage |
|----------|----------|-------|
| `HOME` | Yes | Source hook-common.sh, locate scripts |
| `TMUX` | No | Detect tmux for poller spawn decision |
| `TMUX_PANE` | No | Passed to poller for pane targeting |

## Validation Rules

1. `tool_name` must be non-null string (exit 0 silently if missing — FR-010)
2. Remaining fields filter naturally: null `file_path` → empty basename → regex fails
3. No full schema validation required
