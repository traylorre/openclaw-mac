# CONTEXT-CARRYOVER-05 — Integration Audit Report

**Session**: 2026-03-11
**Purpose**: Full integration audit of 002 + 003 scripts, flowchart reconciliation, blind spot analysis

---

## Q1: Symlink Verification — PASS

All symlinks verified correct:

- `~/.claude/settings.json` -> `~/dotfiles/claude/.claude/settings.json` (OK)
- All 11 scripts in `~/bin/` -> `~/dotfiles/scripts/bin/*` (OK)
- All scripts have executable permissions (OK)

## Q2: Dry-Run Integration Results

### Health Check — 14/14 PASS

- jq 1.7, git 2.43.0, tmux 3.4 all present
- All 5 recovery scripts exist and executable
- PreCompact, SessionStart(compact), SessionStart(clear) hooks registered
- compaction-audit.md with --batch support present
- .claude/ writable, recovery-logs/ exists

### Script-by-Script Dry-Run Results

| Script | Test | Result | Notes |
|---|---|---|---|
| context-guardian.sh | Fast-path (Read tool) | EXIT 0, no output | Correct |
| context-guardian.sh | Carryover write allow | EXIT 0, no output | Correct — always allows CARRYOVER writes |
| context-guardian.sh | Hard limit (75%) | EXIT 0, deny JSON | Correct — blocks at 70% threshold |
| context-monitor.sh | Normal (45%) | "CTX 45%" | Correct |
| context-monitor.sh | Danger (85%) | "CTX 85% DANGER" | Correct — BUT see BLIND SPOT #1 |
| recovery-precompact.sh | --dry-run | EXIT 0, all 3 priorities logged | Correct |
| recovery-detect.sh | --dry-run | EXIT 0, HALT context output | Correct |
| recovery-loader.sh | --dry-run (no marker) | EXIT 0, silent | Correct — normal /clear path |

---

## Q3: Flowchart Reconciliation — New Paths Discovered

### Paths in flowchart but NOT in implementation

The 002 flowchart describes **carryover-detect.sh**, **carryover-poller.sh**, and **carryover-loader.sh** — but these scripts have NOT been implemented. The 002 feature is fully specified but **not yet coded**. Only the 003 scripts (recovery-*) exist.

This means:

- **Phase 1 (PostToolUse carryover detection)**: NOT IMPLEMENTED
- **Phase 2a (tmux idle-detection poller)**: NOT IMPLEMENTED
- **Phase 2b (non-tmux manual path)**: NOT IMPLEMENTED
- **Phase 3 (SessionStart loader for carryover)**: NOT IMPLEMENTED

The flowchart is a design document for future implementation. The current live system only has:

1. **context-guardian.sh** (PreToolUse) — blocks tools at context thresholds, allows CARRYOVER writes
2. **context-monitor.sh** (statusLine) — writes usage % to /tmp/claude-context-usage
3. **003 recovery scripts** — handle compaction detection and recovery

### New paths discovered NOT in the flowchart

#### NEW-1: Shared-state pollution via /tmp/claude-context-usage

- **Path**: context-monitor.sh test writes fake % -> guardian reads it -> lockout
- **Impact**: Any test, stale data, or race condition on this file blocks all tool calls
- **Recovery**: File expires after 60s (guardian checks FILE_AGE < 60), or manual deletion
- **Should add to flowchart**: Yes — as a "WARNS" terminal state

#### NEW-2: python3 dependency in context-guardian.sh

- **Path**: guardian uses `python3 -c "import json..."` for JSON parsing
- **Impact**: If python3 unavailable, all fields default to empty strings, guardian exits 0 (allows everything)
- **Note**: All other scripts use `jq`. Guardian is the only script using python3.
- **Risk**: Silent failure — guardian becomes a no-op without python3

#### NEW-3: context-guardian Layer 2 session directory path construction

- **Path**: `pwd | sed 's|/|-|g'` constructs session dir path
- **Impact**: Leading slash preserved — produces `-home-zeebo-projects-foo`, not `home-zeebo-projects-foo`
- **This matches Claude Code's actual directory naming** (confirmed by checking .claude/projects/)
- **Risk**: Low — but fragile if Claude Code changes naming convention

#### NEW-4: guardian warn vs deny behavior mismatch with 002 spec

- **Path**: Guardian at 50-70% outputs `permissionDecision: "allow"` with warning reason
- **Impact**: Model sees warning but tool call PROCEEDS. Model may ignore warning and keep working.
- **Spec expectation**: 002 spec expects the model to start writing carryover at this point
- **Risk**: Model ignores soft warnings. No enforcement mechanism between 50% and 70%.

#### NEW-5: recovery-watcher idle detection patterns may not match Claude Code UI

- **Path**: `grep -qE '(^> |^\$ |^❯ |claude|Claude)'` on last tmux line
- **Impact**: Claude Code's actual prompt uses `❯` (U+276F) — the pattern includes it
- **BUT**: The prompt is rendered as horizontal bars + `❯` + horizontal bars (3-line pattern per 002 flowchart)
- **Risk**: The grep checks only the LAST line. If the prompt cursor is on an empty line after `❯`, the match fails.

#### NEW-6: recovery-detect outputs JSON then spawns watcher AFTER stdout

- **Path**: Line 226-248 of recovery-detect.sh — JSON output via jq, then watcher spawn
- **Impact**: The hook response (additionalContext) is committed to stdout before the watcher starts. If the watcher spawn fails, the HALT instruction was already injected. This is correct behavior.
- **BUT**: The watcher is spawned as `"$WATCHER_SCRIPT" "$PROJECT_DIR" &` (background process), not with nohup. If the parent shell exits, the watcher may receive SIGHUP.
- **Risk**: Watcher killed before it can send /clear. Falls through to non-tmux path (user must type /clear manually).

#### NEW-7: recovery-loader consumes marker AFTER outputting JSON

- **Path**: Lines 150-174 of recovery-loader.sh
- **Impact**: If recovery-loader crashes between JSON output and marker deletion, the marker persists. Next /clear re-injects recovery context (duplicate injection).
- **Risk**: Low severity — duplicate injection is annoying but not destructive.

#### NEW-8: No cross-feature signal coordination implemented

- **Path**: 002 flowchart Phase 1 checks for `.claude/recovery-marker.json` (FR-016) to suppress carryover rotation during recovery
- **Impact**: Since 002 is not implemented, this coordination doesn't exist yet. When 002 is implemented, this must be wired correctly.
- **Risk**: Future integration bug if 002 implementation misses this check.

---

## Q5: Confidence Assessment

### What works reliably RIGHT NOW

| Component | Confidence | Rationale |
|---|---|---|
| Symlinks & permissions | 100% | Verified, all pass |
| context-monitor.sh (statusLine) | 95% | Simple, correct, writes to known location. -5% for jq dependency |
| context-guardian.sh blocking at hard limit | 90% | Tested, works. -5% for python3 dep, -5% for shared /tmp file fragility |
| context-guardian.sh carryover exception | 98% | Tested, simple grep match. -2% for case-insensitive grep on non-standard filenames |
| recovery-precompact.sh | 85% | Dry-run works. -10% for untested transcript parsing with real data, -5% for signal handler edge cases |
| recovery-detect.sh | 80% | Dry-run works. -10% for watcher spawn reliability, -5% for staleness logic with date parsing, -5% for marker state machine complexity |
| recovery-loader.sh | 85% | Dry-run works (normal /clear path). -10% for untested preamble construction with real recovery data, -5% for truncation edge cases |
| recovery-watcher.sh | 70% | Not testable in dry-run without real sentinel. -15% for idle detection reliability, -10% for tmux pane lifecycle, -5% for timeout behavior |
| End-to-end compaction prevention | 75% | Guardian blocks at 70%. But 002 auto-rotation not implemented — the model must VOLUNTARILY write carryover and the USER must manually /clear |
| End-to-end compaction recovery | 65% | Full chain (precompact -> detect -> audit -> watcher -> clear -> loader) has many handoff points. Each is individually reasonable but untested as a chain with real compaction. |

### Overall confidence — 72%

**The system will probably prevent most compaction-induced data loss, but there are significant gaps:**

1. **002 auto-rotation is UNIMPLEMENTED** — the entire zero-touch carryover rotation that the flowchart describes does not exist as code. The user must manually manage context rotation.

2. **The guardian's soft warning (50-70%) has no enforcement** — the model may ignore it and keep working until the hard block at 70%.

3. **The gap between 70% (guardian hard block) and ~83% (Claude auto-compact) is the danger zone** — if the model has already committed a tool call that passes the guardian at 69%, and that tool call produces a large response pushing context to 83%+, compaction fires with no warning.

4. **The recovery chain is untested end-to-end** — each script works in isolation, but the full PreCompact -> SessionStart(compact) -> audit -> sentinel -> watcher -> /clear -> SessionStart(clear) chain has many handoff points.

---

## Q6: Blind Spots

### BLIND SPOT #1 — Shared /tmp file is a single point of fragile coupling (DEMONSTRATED LIVE)

**What happened**: Running `context-monitor.sh` with test data (85%) wrote to `/tmp/claude-context-usage`. The real guardian immediately read this value and blocked ALL subsequent tool calls. This created a **self-inflicted lockout** during testing.

**Root cause**: The `/tmp/claude-context-usage` file is a global shared state with no namespacing (no session ID, no PID). Any process that writes to it affects the guardian for ALL Claude sessions on the machine.

**Mitigations needed**:

- Namespace the file by session ID or PID: `/tmp/claude-context-usage-${SESSION_ID}`
- Add a staleness check (already exists: 60s expiry — but 60s is a long lockout)
- Add a "test mode" that writes to a different path

### BLIND SPOT #2 — python3 vs jq inconsistency in context-guardian.sh

All other scripts use `jq` for JSON parsing. context-guardian.sh uses `python3`. If python3 is unavailable:

- All JSON field extractions silently return empty strings
- The guardian exits 0 (allows everything)
- No error message, no warning, no log entry

This means the guardian **silently degrades to a no-op** without python3. It should use jq like everything else, or at minimum fail loudly.

### BLIND SPOT #3 — No integration between 002 (context rotation) and guardian behavior

The guardian blocks at 70% and says "write a CONTEXT-CARRYOVER file." But:

- There's no code that automatically writes the carryover file
- There's no code that automatically triggers /clear after the carryover is written
- The model must understand and follow the instructions in the deny reason
- If the model doesn't comply, the user is stuck in a blocked state

The 002 flowchart assumes carryover-detect.sh (PostToolUse hook) exists to handle this. It doesn't yet.

### BLIND SPOT #4 — Guardian deny message is instruction injection into model context

The `permissionDecisionReason` string contains imperative instructions ("DO THIS NOW", "Write a CONTEXT-CARRYOVER file"). This relies on:

1. Claude Code passing the deny reason to the model as context
2. The model treating it as authoritative instructions
3. The model successfully writing a carryover file

If any of these assumptions fail, the user gets blocked tool calls with no automatic recovery.

### BLIND SPOT #5 — StatusLine polling frequency vs guardian check timing

The statusLine (context-monitor.sh) runs "every ~5 seconds" per the comment. The guardian reads the temp file on every tool call. Sequence:

1. StatusLine writes 69% -> guardian allows
2. Model makes a tool call that generates a large response
3. Context jumps to 78% but statusLine hasn't run yet
4. Model makes another tool call within the same 5s window
5. Guardian reads stale 69% -> allows
6. Context hits 83% -> auto-compaction

**The 5-second polling gap means the guardian can miss rapid context growth.** The Layer 2 JSONL fallback doesn't help because it checks file size, not actual context percentage.

### BLIND SPOT #6 — PreCompact hook event name "compact" is unvalidated

The spec notes (Assumption #8) that the `compact` event name for SessionStart is unvalidated. If Claude Code uses a different string (e.g., "compaction", "auto-compact"), the SessionStart matcher won't match, and the entire 003 recovery system silently fails.

**This is the single highest-risk assumption in the entire system.** If it's wrong, no recovery fires.

UPDATE: spec.md notes FR-031 was validated — the matchers "compact" and "clear" were confirmed against the Claude Code hooks API. This blind spot may be resolved.

### BLIND SPOT #7 — Watcher spawned without nohup or disown

`recovery-detect.sh` line 241: `"$WATCHER_SCRIPT" "$PROJECT_DIR" &`

If the detect script's parent shell exits and sends SIGHUP to children, the watcher dies. Should use:

```bash
nohup "$WATCHER_SCRIPT" "$PROJECT_DIR" </dev/null >/dev/null 2>&1 &
disown
```

### BLIND SPOT #8 — No mechanism to verify THIS session's hooks are actually firing

The health check validates configuration exists, but there's no way to confirm hooks are actually being invoked during this session. If Claude Code has a bug where hooks stop firing, the entire system silently fails.

**Possible mitigation**: The statusLine provides indirect evidence (it runs, meaning Claude Code is executing scripts). But there's no equivalent heartbeat for PreToolUse hooks.

### BLIND SPOT #9 — /clear in tmux race with user input

If the user is typing when the watcher sends `/clear` via `tmux send-keys`, the keystrokes interleave. User types "fix th" + watcher sends "/clear" + user types "e bug" = garbled input. The 002 flowchart addresses this with a banner, but the 003 watcher has no banner and no input protection.

### BLIND SPOT #10 — Recovery-loader.sh is registered for SessionStart "clear" only

`settings.json` line 38-45: matcher is `"clear"`. The loader only fires on `/clear`, not on new session start. If the user closes the terminal and starts a fresh `claude` invocation instead of typing `/clear`, the recovery context is never injected. The marker persists on disk but the loader never fires because it's not listening for startup events.

---

## Summary

### What is working

- Guardian correctly blocks at high context usage
- Guardian correctly allows carryover file writes (escape hatch)
- StatusLine correctly displays and persists context %
- Recovery scripts correctly handle dry-run mode
- Health check validates all infrastructure
- All symlinks and permissions are correct

### What is missing

- **002 auto-rotation scripts are not implemented** — the entire carryover lifecycle is manual
- **End-to-end chain is untested** with real compaction events
- **Several race conditions** and edge cases identified above

### Recommended priority fixes

1. **Fix /tmp/claude-context-usage namespacing** (Blind Spot #1) — prevents cross-session and test pollution
2. **Replace python3 with jq in context-guardian.sh** (Blind Spot #2) — eliminates silent degradation
3. **Add nohup/disown to watcher spawn** (Blind Spot #7) — prevents premature watcher death
4. **Add startup matcher to recovery-loader** (Blind Spot #10) — allows recovery after terminal restart
5. **Implement 002 scripts** — the spec is ready, the implementation is not
