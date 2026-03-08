# Contract: SessionStart(compact) Hook

**Script**: `~/dotfiles/scripts/bin/recovery-detect.sh`
**Hook Event**: SessionStart
**Matcher**: `compact`
**Trigger**: Auto-compaction fires in a Claude Code session

## Input (stdin)

Platform-provided JSON:

```json
{
  "session_id": "abc123-def456",
  "transcript_path": "/home/user/.claude/projects/.../session.jsonl",
  "cwd": "/home/user/projects/openclaw-mac",
  "source": "compact",
  "model": "claude-opus-4-6",
  "permission_mode": "ask",
  "hook_event_name": "SessionStart"
}
```

| Field | Type | Used By | Notes |
|-------|------|---------|-------|
| `session_id` | string | Marker staleness check (FR-023) | Required |
| `transcript_path` | string | Fallback task capture (FR-005) | May be absent (FR-028) |
| `cwd` | string | Project directory detection | Required |
| `source` | string | Event routing (must be `"compact"`) | Required |
| `model` | string | Logged in recovery log (FR-071) | Optional |

## Output (stdout)

```json
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "⚠️ COMPACTION DETECTED — HALT ALL WORK ⚠️\n\nContext compaction has occurred. Your context is now TAINTED — any decisions or edits you make may be based on incomplete information.\n\nYou MUST:\n1. STOP all current work immediately. Do NOT make any file edits.\n2. Run `/compaction-audit --batch` RIGHT NOW.\n3. Wait for the audit to complete before doing anything else.\n4. After all reverts are done, create the file `.claude/recovery-audit-complete` using the Bash tool.\n\nDo NOT proceed with any other task until these steps are complete."
  }
}
```

## Side Effects

1. **Reads recovery marker** — if exists, checks staleness (FR-023):
   - Same session_id → re-entrant, skip (FR-016)
   - Different session, stale → clean up, proceed
2. **Writes/updates recovery marker** — `.claude/recovery-marker.json`
   (FR-010) with stage `"audit_pending"`
3. **Fallback task capture** — if PreCompact didn't fire
   (`precompact_fired: false` in marker OR no marker exists), parses
   transcript for interrupted task (FR-004, FR-005)
4. **Spawns recovery-watcher.sh** — in tmux environments only (FR-011),
   as a background process
5. **Suppresses CARRYOVER auto-clear** — via marker presence (FR-017)
6. **Creates recovery log** — initializes `.claude/recovery-logs/recovery-<ts>.md`
   with header metadata (FR-043)
7. **Log retention cleanup** — deletes oldest logs if >10 exist (FR-052, FR-069)

## Exit Codes

| Code | Meaning | Platform Behavior |
|------|---------|-------------------|
| 0 | Success | stdout (additionalContext) shown to model |
| 2 | Blocking error | stderr fed back to model as error |
| 1 | Non-blocking error | stderr logged, session continues |

## Error Handling

- **Marker write fails** (read-only FS): Fall back to additionalContext-only
  injection (tier 5), log warning to stderr
- **Transcript unavailable**: Proceed without task capture, note in marker
  warnings (FR-028)
- **jq not found**: Exit 2 with remediation message (FR-026, FR-072)
- **git not found**: Log warning, continue (reverts unavailable but detection
  still works)
- **Re-entrant call**: Exit 0 silently (FR-016)

## Environment Requirements

- `HOME`: Required (FR-072)
- `PATH`: Must include jq, git (FR-072)
- `TMUX`: Checked for tmux presence detection (FR-027)
- `TMUX_PANE`: Used by watcher for send-keys targeting

## Timing

- **Target**: <30 seconds total (SC-014)
- **Priority order**: (1) Write marker, (2) Inject context, (3) Parse transcript
  (FR-070)
- **Platform timeout**: 600 seconds (configurable)
