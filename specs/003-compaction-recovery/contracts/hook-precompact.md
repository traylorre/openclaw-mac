# Contract: PreCompact Hook

**Script**: `~/dotfiles/scripts/bin/recovery-precompact.sh`
**Hook Event**: PreCompact
**Matcher**: (default — fires on all PreCompact events)
**Trigger**: Claude Code is about to perform auto-compaction

## Context

This hook was identified during research (R-001) as a design improvement over
the spec's original assumption that "no pre-compaction hook exists" (FR-004).
PreCompact fires *before* compaction, allowing state capture while the full
transcript is still available.

**This is the primary capture path.** SessionStart(`compact`) provides the
fallback if PreCompact did not fire.

## Input (stdin)

Platform-provided JSON (expected — validate defensively):

```json
{
  "session_id": "abc123-def456",
  "transcript_path": "/home/user/.claude/projects/.../session.jsonl",
  "cwd": "/home/user/projects/openclaw-mac",
  "hook_event_name": "PreCompact"
}
```

| Field | Type | Notes |
|-------|------|-------|
| `session_id` | string | Used for marker and task file naming |
| `transcript_path` | string | Used for interrupted task extraction |
| `cwd` | string | Project directory |

**Note**: PreCompact input format is not as well-documented as SessionStart.
The script must validate field existence before use (FR-064) and degrade
gracefully if fields are missing.

## Output (stdout)

No `additionalContext` injection needed — PreCompact runs before compaction,
and the session will be restarted by compaction anyway. Output is minimal:

```json
{}
```

Or exit 0 with no output.

## Side Effects

1. **Creates recovery marker** — `.claude/recovery-marker.json` with
   stage `"detected"`, `precompact_fired: true` (FR-010)
2. **Captures interrupted task** — parses transcript (last 1MB) for
   substantive user messages (FR-004, FR-025, FR-065)
3. **Updates marker stage** — to `"task_captured"` after successful capture
4. **Initializes recovery log** — creates log file with header metadata

## Priority Order (FR-070)

The hook MUST complete these operations in priority order:

1. **Write recovery marker** (most critical — 1-2 seconds)
2. **Parse transcript for interrupted task** (bounded to last 1MB — 5-20 seconds)
3. **Initialize recovery log** (nice to have)

If killed by platform timeout or signal at any point, the marker exists
for the next session to detect.

## Transcript Parsing Algorithm

```text
1. Seek to max(0, file_size - 1MB) in transcript file
2. Skip first (potentially partial) line
3. Read remaining lines as JSONL
4. Filter: type == "user" AND isSidechain != true
5. Reverse iterate (newest first)
6. For each user message:
   a. Extract message.content (string)
   b. If slash command (starts with "/"): mark is_slash_command, capture full command
   c. If trivial (≤10 chars OR matches confirmation pattern): skip
   d. Else: this is the substantive task → capture
7. Continue backwards for up to 3 more substantive messages (preceding_messages)
8. If no substantive message found: set substantive_message_found: false
```

## Signal Handling (FR-062)

```bash
trap 'persist_marker_state; exit 130' INT
trap 'persist_marker_state; exit 143' TERM
trap 'persist_marker_state; exit 129' HUP
```

`persist_marker_state` writes the marker with whatever stage was last completed.

## Error Handling

- **Transcript unavailable**: Write marker with `capture_source: null`,
  no interrupted task file. SessionStart fallback will attempt capture.
- **jq not available**: Write marker using printf/echo (no JSON parsing
  of transcript). Task capture skipped.
- **Write permission denied**: Log to stderr, exit 1. SessionStart fallback
  handles detection.
- **Malformed trailing JSONL line** (FR-019): Discard last line, proceed
  with valid entries.

## Timing

- **Target**: <10 seconds (minimal work — just marker + transcript scan)
- **Platform timeout**: 600 seconds
