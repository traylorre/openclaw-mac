# Runbook: Compaction Recovery Setup & Validation

**Feature**: 003-compaction-recovery
**Date**: 2026-03-08

## #1 First Time Setup

Already done. To verify from scratch on a new machine:

```bash
# 1. Ensure directories exist
mkdir -p ~/dotfiles/scripts/bin ~/.claude/recovery-logs

# 2. Copy/clone the recovery scripts into ~/dotfiles/scripts/bin/
#    (recovery-common.sh, recovery-precompact.sh, recovery-detect.sh,
#     recovery-loader.sh, recovery-watcher.sh, recovery-health.sh)

# 3. Create symlinks
for s in recovery-common recovery-precompact recovery-detect recovery-loader recovery-watcher recovery-health; do
  ln -sf ~/dotfiles/scripts/bin/${s}.sh ~/bin/${s}.sh
done

# 4. Verify
~/bin/recovery-health.sh
```

All 14 checks should pass.

## #2 After Terminal Restart

**Nothing to do.** The scripts are on-disk, symlinks persist, hook config is in `settings.json`. Open a new terminal and run:

```bash
~/bin/recovery-health.sh
```

Should still be 14/14. The hooks fire automatically — they're registered in `~/.claude/settings.json` which Claude Code reads at session start.

## #3 After WSL Restart

Same as #2 — **nothing to do.** WSL preserves the filesystem. The only thing that won't survive a WSL restart is a running `recovery-watcher.sh` background process (if compaction happened mid-recovery and WSL restarted before /clear). In that case, the recovery marker file will still exist and the next `SessionStart(compact)` will detect it via the resume logic (T021).

Verify:

```bash
~/bin/recovery-health.sh
```

If you're paranoid, also check no stale marker was left behind:

```bash
cat .claude/recovery-marker.json 2>/dev/null && echo "STALE MARKER EXISTS" || echo "Clean — no marker"
```

## #4 Validate End-to-End

### Dry-run simulation (no real compaction needed)

```bash
# Step 1: Simulate PreCompact
echo '{"session_id":"e2e-test","transcript_path":"","cwd":"'$(pwd)'","hook_event_name":"PreCompact"}' \
  | ~/bin/recovery-precompact.sh --dry-run 2>&1

# Step 2: Simulate SessionStart(compact)
echo '{"session_id":"e2e-test","transcript_path":"","cwd":"'$(pwd)'","source":"compact","hook_event_name":"SessionStart"}' \
  | ~/bin/recovery-detect.sh --dry-run 2>&1

# Step 3: Simulate SessionStart(clear)
echo '{"session_id":"e2e-new","cwd":"'$(pwd)'","source":"clear","hook_event_name":"SessionStart"}' \
  | ~/bin/recovery-loader.sh --dry-run 2>&1
```

### Real flow simulation (creates actual files, cleans up after)

**Important**: Run this as a single paste into your shell so the mock transcript exists when PreCompact reads it.

```bash
# Create a mock transcript
cat > /tmp/mock-transcript.jsonl <<'EOF'
{"type":"user","message":{"content":"Implement the recovery system for feature 003"},"isSidechain":false}
{"type":"assistant","message":{"content":[{"type":"text","text":"Starting..."}]}}
{"type":"user","message":{"content":"yes"},"isSidechain":false}
EOF

# 1. Fire PreCompact
echo '{"session_id":"real-test","transcript_path":"/tmp/mock-transcript.jsonl","cwd":"'$(pwd)'"}' \
  | ~/bin/recovery-precompact.sh 2>&1
echo "--- Marker ---"
cat .claude/recovery-marker.json | jq '{stage, precompact_fired, capture_source}'
echo "--- Task ---"
cat .claude/recovery-interrupted-task.json | jq '{task_description, is_slash_command, preceding_messages}'

# 2. Fire SessionStart(compact)
echo '{"session_id":"real-test","transcript_path":"/tmp/mock-transcript.jsonl","cwd":"'$(pwd)'","source":"compact"}' \
  | ~/bin/recovery-detect.sh 2>&1
echo "--- Marker after detect ---"
cat .claude/recovery-marker.json | jq '{stage}'

# 3. Simulate audit completion (what the model would do)
jq '.stage = "reverts_complete"' .claude/recovery-marker.json > .claude/recovery-marker.json.tmp \
  && mv .claude/recovery-marker.json.tmp .claude/recovery-marker.json
touch .claude/recovery-audit-complete

# 4. Fire SessionStart(clear) — the recovery loader
echo '{"session_id":"new-session","cwd":"'$(pwd)'","source":"clear"}' \
  | ~/bin/recovery-loader.sh 2>&1

# 5. Verify cleanup
echo "--- Post-recovery ---"
ls .claude/recovery-marker.json 2>/dev/null && echo "FAIL: marker still exists" || echo "PASS: marker consumed"
ls .claude/recovery-interrupted-task.json 2>/dev/null && echo "FAIL: task file still exists" || echo "PASS: task file consumed"
echo "PASS: sentinel expected to persist (watcher deletes it, not loader)"
ls .claude/recovery-logs/recovery-*.md 2>/dev/null && echo "PASS: recovery log persisted"

# Cleanup
rm -f /tmp/mock-transcript.jsonl .claude/recovery-audit-complete .claude/recovery-logs/recovery-*.md
```

## How to Measure Success

| Check | Pass Criteria |
|-------|--------------|
| `recovery-health.sh` | 14/14 pass, 0 fail |
| PreCompact creates marker | `.claude/recovery-marker.json` exists with `stage: "detected"` or `"task_captured"` |
| Transcript parsing | `.claude/recovery-interrupted-task.json` has the correct substantive message, not "yes"/"ok" |
| SessionStart(compact) output | stdout is valid JSON with `hookSpecificOutput.additionalContext` containing "HALT" |
| SessionStart(clear) output | stdout is valid JSON with `additionalContext` containing "COMPACTION RECOVERY CONTEXT" |
| Marker consumed after /clear | `.claude/recovery-marker.json` deleted |
| Task file consumed after /clear | `.claude/recovery-interrupted-task.json` deleted |
| Sentinel persists until watcher | `.claude/recovery-audit-complete` remains after loader (watcher deletes it in live flow) |
| Recovery log persists | `.claude/recovery-logs/recovery-*.md` exists with front matter |
