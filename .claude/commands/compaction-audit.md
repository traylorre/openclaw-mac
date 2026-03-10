---
description: Detect context compaction in Claude session history, identify tainted edits, and report what to revert.
---

## User Input

```text
$ARGUMENTS
```

**Mode detection**: Check if `$ARGUMENTS` contains `--batch` or `--abort`.

- **`--batch`**: Batch mode — auto-approve all reverts, no confirmation prompts. Used by recovery workflow.
- **`--abort`**: Abort mode — clean up recovery state and exit (FR-032).
- **No flag**: Interactive mode (default) — analyze the most recent non-current session, or a specific session if a session ID prefix is provided.

### Abort Mode (`--abort`)

If `--abort` is present:

1. Delete `.claude/recovery-marker.json` if it exists
2. Delete `.claude/recovery-interrupted-task.json` if it exists
3. Delete `.claude/recovery-audit-complete` if it exists
4. Report "Recovery state cleaned up. No /clear will be triggered."
5. Stop — do not proceed with audit.

### Batch Mode (`--batch`)

If `--batch` is present, analyze the **current** session (not a previous one). The recovery workflow has injected context telling you that compaction just occurred in THIS session. Follow the batch-specific steps described in each section below. Key differences from interactive mode:

- No confirmation prompts — auto-approve all reverts
- Stash uncommitted changes before reverting (FR-037)
- Produce progress output at each stage (FR-033)
- Write recovery log and create sentinel file when done
- Summarize output if >50 tainted edits (FR-068)

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

### 6. Execute Reverts

**Interactive mode**: Ask the user before making any changes. List each revert individually and get confirmation. Never auto-revert.

**Batch mode** (`--batch`): Execute all reverts automatically using the following procedure:

#### 6a. Pre-flight Checks (FR-034, FR-042, FR-059)

Before any reverts:

1. **Check `.git/index.lock`** — if it exists, another git operation may be in progress. Report this and skip git-based reverts. Provide manual revert instructions instead.
2. **Detached HEAD** — `git checkout <commit> -- <file>` works fine in detached HEAD. Do NOT assume a branch is checked out (FR-042).

#### 6b. Stash Uncommitted Changes (FR-037, FR-096)

```bash
# Check if working tree is dirty
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "⚠️ Working tree has uncommitted changes — stashing before reverts"
    # Note: --keep-index preserves staged/unstaged distinction but may flatten on restore
    git stash push --keep-index -m "recovery-auto-stash" || {
        echo "⚠️ WARNING: git stash failed. Staged/unstaged distinction may be lost."
        echo "Proceeding with reverts — files that would conflict will be skipped."
    }
    STASHED=true
fi
```

If stash fails, warn that staged/unstaged distinction will be flattened and proceed (FR-096, D-003).

#### 6c. Revert Loop (FR-033, FR-040, FR-041, FR-047, FR-048, FR-086)

Identify the last clean commit hash (the commit before any tainted edits):

```bash
CLEAN_COMMIT=$(git log --format='%H' -1 HEAD)  # or the commit identified in the audit
```

**Infrastructure files first** (FR-047, FR-048): If any tainted files match these patterns, revert them FIRST:
- `.claude/settings.json`, `.claude/commands/*`, `CLAUDE.md`, `.claude/*.json`

For each tainted file:

1. **Check if file is outside the git repo** — if so, skip with message "out-of-repo, manual review needed" (FR-086)
2. **Check for external modification** (FR-040) — compare the file's current content against what the tainted tool call produced. If they differ, someone else modified it. Flag for manual review instead of reverting.
3. **Modified files**: `git checkout <clean_commit> -- <file>` with `--no-verify` (FR-049)
4. **Created files** (FR-041): `rm <file>` (file didn't exist before compaction)
5. Report progress: `✓ <file> (<action>)` or `⚠ <file> (skipped: <reason>)`

If >50 tainted edits, use summarized output only (FR-068):
```
Reverted 45 files, skipped 5. See recovery log for details.
```

#### 6d. Handle Partial Failure (FR-034)

If a revert fails midway:
- Log which files were successfully reverted and which remain
- Update recovery marker with `stage: "reverts_partial"` and failure details
- Do NOT delete the marker — leave it for diagnosis
- Report what happened and what the developer should do

#### 6e. Restore Stash (FR-037)

```bash
if [[ "${STASHED:-}" == true ]]; then
    git stash pop || echo "⚠️ WARNING: stash pop failed — run 'git stash list' to recover"
fi
```

#### 6f. Verification Summary (FR-039)

After all reverts, produce:

```
## Verification
- Last clean commit: <hash>
- Files reverted: <count>
- Files skipped: <count> (with reasons)
- Current state diff: <summary of git diff against clean commit>
```

#### 6g. Write Recovery Log (FR-043)

Update the recovery log file at `.claude/recovery-logs/recovery-<timestamp>.md` (the path is in the recovery marker's `recovery_log_file` field). Populate the Tainted Edits table, Warnings, and Verification sections per the recovery-log.md contract. Update the front matter counts.

#### 6h. Create Sentinel and Update Marker

```bash
# Signal recovery-watcher.sh that audit is complete
touch .claude/recovery-audit-complete

# Update marker stage
# (The marker file is at .claude/recovery-marker.json)
```

Read the current marker, update `stage` to `"reverts_complete"`, and write it back. Use jq:

```bash
jq '.stage = "reverts_complete"' .claude/recovery-marker.json > .claude/recovery-marker.json.tmp \
    && mv .claude/recovery-marker.json.tmp .claude/recovery-marker.json
```

Report: "Recovery audit complete. Sentinel created. Waiting for /clear."

## Important Notes

- Multiple compactions can occur in a single session. Check for ALL of them.
- A compaction within the pre-compaction zone means there was an EARLIER compaction — the "clean" zone is only clean back to that point. Report this as a nested compaction risk.
- The `last-prompt` message type marks the end of the last user prompt before compaction. This is a reliable boundary marker.
- Session JSONL files store ALL messages including pre-compaction ones, even though they were discarded during the live session.
- File edits via `Edit` tool are the primary concern. Also check for `Write` tool and `Bash` tool calls that modify files (grep for redirect operators `>`, `>>`, `tee` in bash commands).
