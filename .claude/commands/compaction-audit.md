---
description: Detect context compaction in Claude session history, identify tainted edits, and report what to revert.
---

## User Input

```text
$ARGUMENTS
```

If user input is empty, analyze the most recent non-current session. If user input is a session ID prefix (e.g., `6e2e7e61`), analyze that specific session.

## Goal

Determine exactly when context compaction occurred in a session, which file edits happened post-compaction (tainted), and produce a revert plan. Compaction is unacceptable — any work produced after compaction has degraded context and cannot be trusted.

## Definitions

- **Compaction boundary**: The JSONL line where a `user` message contains "This session is being continued from a previous conversation that ran out of context" — this is injected by the system when prior messages are compressed.
- **Pre-compaction zone**: All messages before the compaction boundary. Work here is clean (unless an earlier compaction exists — check recursively).
- **Post-compaction zone**: All messages after the compaction boundary. File edits here are **tainted**.
- **Compaction signal sequence**: `last-prompt` type → `system` type → `user` type with summary text. This is the 3-line pattern immediately before the compaction boundary.

## Execution Steps

### 1. Identify Target Session

Find session JSONL files:

```bash
ls -lt ~/.claude/projects/$(pwd | sed 's|/|-|g; s|^-||')/  *.jsonl 2>/dev/null
```

If user provided a session ID prefix, match it. Otherwise pick the most recent file by modification time that is NOT the current session.

### 2. Detect Compaction Events

Run this analysis on the target session JSONL:

```python
import json, sys

with open(SESSION_FILE) as f:
    lines = f.readlines()

compactions = []
for i, line in enumerate(lines):
    try:
        obj = json.loads(line)
        content = str(obj.get('message', {}).get('content', ''))
        if 'continued from a previous conversation' in content:
            compactions.append(i)
    except:
        pass

print(f"Total lines: {len(lines)}")
print(f"Compaction events: {len(compactions)}")
for c in compactions:
    print(f"  Line {c}")
```

Report the number of compactions. If zero, report "No compaction detected — session is clean" and stop.

### 3. For Each Compaction, Map the Timeline

For each compaction boundary line, extract:

**A. Last clean edit before compaction** — scan backwards from the boundary for the last `tool_use` of type `Edit` or `Write` that has a successful `tool_result`.

**B. First tainted action after compaction** — scan forwards from the boundary for the first `tool_use` of any type.

**C. All post-compaction file edits** — scan from boundary to end of file, collect every `Edit` and `Write` tool_use with their parameters (`file_path`, `old_string`, `new_string` for Edit; `file_path` for Write). These are the tainted changes.

Use this script pattern:

```python
# For each compaction at line C:
tainted_edits = []
for i in range(C, len(lines)):
    obj = json.loads(lines[i])
    content = obj.get('message', {}).get('content', '')
    if isinstance(content, list):
        for item in content:
            if isinstance(item, dict) and item.get('type') == 'tool_use':
                if item.get('name') in ('Edit', 'Write'):
                    inp = item.get('input', {})
                    tainted_edits.append({
                        'line': i,
                        'tool': item['name'],
                        'file': inp.get('file_path', ''),
                        'old': inp.get('old_string', '')[:100],
                        'new': inp.get('new_string', '')[:100],
                    })
```

### 4. Map User Prompts to Rounds

Scan the pre-compaction zone for user messages that triggered `/speckit.specify` or other skill invocations. Count them and identify which revision each round produced. This establishes which revisions are clean vs tainted.

Pattern: look for `Launching skill:` in tool_results, and `Round N` or `Rev N` in user/assistant text messages.

### 5. Produce the Report

Output a structured report:

```
## Compaction Audit Report

**Session**: <session_id>
**Total lines**: N
**Compaction events**: N (at lines: ...)

### Timeline
| Zone | Lines | Status | Revisions |
|------|-------|--------|-----------|
| Pre-compaction | 0–<boundary-1> | CLEAN | Rev X–Y |
| Post-compaction | <boundary>–end | TAINTED | Rev Z (partial) |

### Tainted File Edits
| Line | Tool | File | Change |
|------|------|------|--------|
| ... | Edit | spec.md | "Rev 23" → "Rev 24" |

### Revert Plan
For each tainted edit, show the reverse edit needed:
- File: <path>
  - Revert: change "<new_string>" back to "<old_string>"
  - OR: if Write, restore from git (`git checkout <commit> -- <file>`)

### Verification
After reverting, verify:
- Spec header revision matches last clean revision
- Checklist cumulative counts match spec content
- `git diff` shows only the intended reverts
```

### 6. Offer to Execute Reverts

Ask the user before making any changes. List each revert individually and get confirmation. Never auto-revert.

## Important Notes

- Multiple compactions can occur in a single session. Check for ALL of them.
- A compaction within the pre-compaction zone means there was an EARLIER compaction — the "clean" zone is only clean back to that point. Report this as a nested compaction risk.
- The `last-prompt` message type marks the end of the last user prompt before compaction. This is a reliable boundary marker.
- Session JSONL files store ALL messages including pre-compaction ones, even though they were discarded during the live session.
- File edits via `Edit` tool are the primary concern. Also check for `Write` tool and `Bash` tool calls that modify files (grep for redirect operators `>`, `>>`, `tee` in bash commands).
