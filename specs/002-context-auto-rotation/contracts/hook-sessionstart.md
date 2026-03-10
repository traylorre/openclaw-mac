# Contract: SessionStart Hook (carryover-loader.sh)

**Feature**: 002-context-auto-rotation
**Hook Event**: SessionStart
**Matchers**: `clear`, `compact`, `startup` (NOT `resume` — FR-011)
**Script**: `~/bin/carryover-loader.sh`
**Timeout**: 30 seconds

## Input (stdin JSON)

```json
{
  "session_id": "abc123-def456",
  "transcript_path": "/home/user/.claude/projects/.../session.jsonl",
  "cwd": "/home/user/projects/openclaw-mac",
  "source": "clear",
  "model": "claude-opus-4-6"
}
```

### Required Fields

| Field | Type | Usage |
|-------|------|-------|
| `source` | string | Event type routing: behavior differs for `clear`, `compact`, `startup` |

### Unused Fields

`session_id`, `transcript_path`, `model` — available, logged for debugging but not used in logic.

## Output (stdout JSON)

### Carryover Loaded

```json
{
  "hookSpecificOutput": {
    "additionalContext": "--- CARRYOVER CONTEXT ---\nYou are resuming after a context rotation. The following is your previous session's carryover summary. Continue the task described below.\n\n<file contents>\n--- END CARRYOVER CONTEXT ---"
  }
}
```

### Signal File Messages (startup path, FR-030)

```json
{
  "hookSpecificOutput": {
    "additionalContext": "Previous rotation incomplete — type /clear to continue.\n\nCARRYOVER file was expected but not found or was empty. Ask the user for context about the previous task."
  }
}
```

Both reminder and warning are concatenated if both signal files exist. Each is independently true.

### No Carryover / Double-/clear / Wrong Branch

No output. Empty stdout. Exit 0.

## Exit Codes

| Code | Meaning | When |
|------|---------|------|
| 0 | Success (loaded, no-op, warning injected, or double-/clear detected) | Normal operation |
| 1 | Non-blocking error | File I/O error; model starts without carryover |
| 2 | Blocking error | `jq` not found (FR-025), `hook-common.sh` missing (FR-031) |

## Per-Event Behavior

### `clear` Events

1. **FR-032 guard**: Check if any `.loaded` file in spec directory has mtime ≤60 seconds ago
   - If recent `.loaded` exists AND no unconsumed CARRYOVER AND no `carryover-pending` → exit 0 (double-/clear no-op)
   - Log: `"double-/clear detected, carryover already loaded ≤60s ago"`
2. Derive spec directory from `git branch --show-current` → `specs/${branch}/`
3. Search for unconsumed `CONTEXT-CARRYOVER-NN.md` files
4. Select highest NN (FR-026), check size, load, rename to `.loaded`, output

### `compact` Events

1. **FR-033 guard**: Check for `.claude/recovery-marker.json` — if present, log `"compact suppressed — recovery active"` and exit 0 with no `additionalContext`
2. No FR-032 guard (only applies to `clear`)
3. No signal file cleanup (only on `startup`)
4. Search and load CARRYOVER file as compaction fallback (User Story 3)

### `startup` Events

1. **FR-030 linear signal scan** (mirroring creation timeline):
   - Step 1: Delete stale `.claude/carryover-pending.claimed` (FR-029)
   - Step 2: If `.claude/carryover-clear-needed` exists → collect reminder text, delete file
   - Step 3: If `.claude/carryover-pending` exists → check for CARRYOVER below
2. Search and load CARRYOVER file (if exists)
3. If pending exists but no CARRYOVER found → inject "expected but missing" warning (FR-022)
4. If both reminder and warning texts collected → concatenate into single `additionalContext`

## Side Effects

| Action | Condition | FR |
|--------|-----------|-----|
| Rename `CONTEXT-CARRYOVER-NN.md` → `.loaded` | File loaded successfully | FR-009 |
| Delete stale `.claimed` | `startup` event only | FR-029 |
| Delete `carryover-clear-needed` | `startup` event, file present | FR-030 |
| Delete `carryover-pending` | After processing (all events) | FR-022 |
| Delete oldest `.loaded` files beyond 5 | After successful load | FR-021 |
| `mkdir -p .claude` | Before any signal file operations | FR-031 |
| Log to per-invocation file in `.claude/recovery-logs/` (e.g., `carryover-loader.2026-03-10T14:32:01.log`) | All paths (best-effort) | FR-023 |

## Signal Traps (FR-025)

Installed at script entry for SIGTERM, SIGINT, SIGHUP:

- If a `.loaded` rename was performed, the trap undoes it (restores unconsumed state)
- Prevents data loss if process is killed between rename and stdout output
- SIGKILL cannot be trapped — `.loaded` persists (accepted risk, CR3 in flowchart)

## Size Handling

| File Size | Action | FR |
|-----------|--------|-----|
| < 100 bytes | Treat as empty: rename to `.loaded`, inject warning | FR-022 |
| 100 bytes – 80KB | Load as-is | — |
| > 80KB | `tail -c 81920` then `sed '1d'` (drop partial line), prepend truncation note | FR-019 |

Truncation note format: `[CARRYOVER truncated — showing last ~80KB of <original_size>]`

## Preamble Structure (FR-015, FR-018)

```text
--- CARRYOVER CONTEXT ---
You are resuming after a context rotation. The following is your previous session's carryover summary. Continue the task described below.

<carryover file contents, possibly truncated>
--- END CARRYOVER CONTEXT ---
```

~150 bytes overhead, within FR-018 delimiters and FR-019 size cap.

## JSON Output Construction (FR-027)

All JSON MUST be constructed via `jq`:

```bash
jq -n --arg ctx "$preamble_content" '{hookSpecificOutput:{additionalContext:$ctx}}'
```

Raw string interpolation (`printf`, `echo`) MUST NOT be used — carryover content may contain quotes, backslashes, and newlines.

## Performance

| Path | Target |
|------|--------|
| No carryover file (common case) | <500ms (SC-006) |
| With carryover file (≤80KB) | <1s |
| With oversized file (truncation) | <2s |

## Environment Variables

| Variable | Required | Usage |
|----------|----------|-------|
| `HOME` | Yes | Source hook-common.sh |
| `PATH` | Yes | Access `git`, `jq`, `find`, `stat` |
