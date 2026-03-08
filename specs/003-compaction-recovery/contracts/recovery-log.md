# Contract: Recovery Log Format

**Version**: `recovery-log-v1`
**Location**: `.claude/recovery-logs/recovery-<timestamp>.md`
**Permissions**: `0600` (FR-091)
**Retention**: Max 10 files, oldest deleted before new write (FR-052, FR-069)

## Format

Markdown with YAML front matter. The front matter provides structured metadata
for machine parsing (FR-079). The body provides human-readable detail.

## Schema

### Front Matter (YAML)

```yaml
---
format: recovery-log-v1
timestamp: "2026-03-08T14:30:00Z"
session_id: "abc123-def456"
claude_code_version: "1.2.3"
tainted_edits_total: 5
reverted_count: 4
skipped_count: 1
recovery_duration_seconds: 45
outcome: "success"
degradation_tier: 1
capture_source: "precompact"
interrupted_task_available: true
carryover_available: true
---
```

| Field | Type | Required | Values |
|-------|------|----------|--------|
| `format` | string | yes | Always `"recovery-log-v1"` |
| `timestamp` | string | yes | ISO 8601 |
| `session_id` | string | yes | Compacted session ID |
| `claude_code_version` | string | no | From hook input or `claude --version` |
| `tainted_edits_total` | integer | yes | Total tainted edits found by audit |
| `reverted_count` | integer | yes | Successfully reverted |
| `skipped_count` | integer | yes | Skipped (conflicts, out-of-repo, etc.) |
| `recovery_duration_seconds` | integer | no | Wall-clock time from detection to /clear |
| `outcome` | enum | yes | `"success"`, `"partial"`, `"aborted"` |
| `degradation_tier` | integer | yes | 1-6 per FR-093 |
| `capture_source` | enum | yes | `"precompact"`, `"transcript_parse"`, `"none"` |
| `interrupted_task_available` | boolean | yes | Whether task was captured |
| `carryover_available` | boolean | yes | Whether CARRYOVER existed |

### Body (Markdown)

```markdown
# Recovery Log — <timestamp>

## Summary

- **Session**: <session_id>
- **Tainted edits**: <total> found, <reverted> reverted, <skipped> skipped
- **Interrupted task**: "<first 100 chars of task>..."
- **Outcome**: <outcome>
- **Degradation tier**: <tier> (<tier description>)

## Tainted Edits

| # | File | Type | Tool | Action | Status |
|---|------|------|------|--------|--------|
| 1 | path/to/file | modified | Edit | reverted to <commit> | reverted |
| 2 | path/to/new | created | Write | deleted | reverted |

## Infrastructure Files

(Only present if tainted edits touched critical files per FR-047)

- `.claude/settings.json` — CRITICAL, reverted before /clear

## Warnings

- <warning text>

## Verification

- Last clean commit: <hash>
- Files reverted: <count>
- Diff summary: <lines added/removed>
```

## Content Restrictions (FR-090)

- **No full file contents** — only paths and edit types
- **No complete diffs** — first 200 characters of each diff hunk maximum
- **No credentials or PII** — interrupted task description is included but
  reviewed for obvious secrets (API key patterns) and redacted if found
- **File paths**: JSON-encoded strings in front matter, markdown in body

## Lifecycle

1. **Created by**: `recovery-precompact.sh` or `recovery-detect.sh`
   (header + summary stub)
2. **Updated by**: Model during audit (tainted edits table, verification)
3. **Read by**: `recovery-loader.sh` (for preamble file list)
4. **Retained**: Max 10 files, cleanup on new log creation

## Aggregation Support (FR-080)

The YAML front matter enables external tools to:

```bash
# Count recoveries in last 7 days
for f in .claude/recovery-logs/recovery-*.md; do
  head -20 "$f" | grep -E '^(timestamp|tainted_edits_total|outcome):'
done
```

All metadata fields use consistent types and naming across logs.
