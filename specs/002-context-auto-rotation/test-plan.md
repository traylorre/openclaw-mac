# 002 Context Auto-Rotation — Test Plan

**Date:** 2026-03-09
**Derived from:** `flowchart.md` junction analysis + spec.md FRs
**Total tests:** 36 (13 MUST, 12 SHOULD, 11 boundary/edge)

## Test Harness

All scripts tested in isolation by feeding synthetic stdin JSON and checking
stdout, stderr, exit codes, and file side effects. Poller tests use a mock
tmux pane (stub `tmux` command that returns canned output). End-to-end tests
(T35, T36) run in a real Claude Code session.

### Conventions

- `$SPEC_DIR` = `specs/<branch>/` for the test branch
- `$SIGNAL_DIR` = `.claude/`
- All file paths relative to project root unless noted
- "MUST match" / "MUST NOT match" refers to the hook triggering `continue:false`

---

## Phase 1 — PostToolUse Hook (carryover-detect.sh)

### T01 — hook-common.sh not found [MUST] {G1}

**Junction:** Pre-entry (MISSING from flowchart)
**FR:** FR-020, FR-024

```text
Given: $HOME/bin/hook-common.sh does not exist (broken/missing symlink)
When:  carryover-detect.sh receives valid PostToolUse JSON on stdin
Then:  Script exits non-zero (bash source failure)
       No JSON on stdout (no Claude corruption)
       Claude Code treats hook as errored, model continues
```

**Why:** Every script sources this file first. If the symlink deploy is
broken, the entire feature silently fails with no logging.

---

### T02 — jq missing (Phase 1) [MUST] {J1}

**Junction:** A — `require_tool jq`
**FR:** FR-024

```text
Given: jq binary not in PATH (renamed temporarily)
When:  carryover-detect.sh receives valid PostToolUse JSON
Then:  EXIT 2
       stderr contains: remediation message (e.g., "install jq")
       stdout: empty (no JSON)
```

---

### T03 — Fast path: non-Write/Edit tool [MUST] {J2}

**Junction:** B — `tool_name == Write or Edit?`
**FR:** FR-010, SC-005

```text
Given: jq available, hook-common.sh present
When:  stdin JSON has tool_name set to each of:
       "Read", "Bash", "Grep", "Glob", "Agent", "Edit" (wait — Edit SHOULD match)
Then:  For "Read", "Bash", "Grep", "Glob", "Agent":
         EXIT 0, no stdout, completes in <10ms
       For "Edit":
         Proceeds to basename check (does NOT fast-path exit)
```

**Performance gate:** Measure wall-clock time. Must be <200ms (SC-005 target
is for non-matching Write/Edit — non-Write tools should be <10ms).

---

### T04 — Write but not a carryover file [SHOULD] {J2+J3}

**Junction:** B (yes) → D (no)
**FR:** FR-010

```text
Given: tool_name: "Write"
       file_path: "/home/user/project/README.md"
When:  carryover-detect.sh processes stdin
Then:  EXIT 0, no stdout
       No signal files created in .claude/
       No log entries (fast-path after basename check)
```

---

### T05 — Filename pattern: positive cases [MUST] {J3}

**Junction:** D — basename matches regex
**FR:** FR-001

```text
For each file_path below, the hook MUST trigger (continue:false):

  Basename variants (all must match):
    CONTEXT-CARRYOVER-00.md    (boundary: lowest valid NN)
    CONTEXT-CARRYOVER-01.md    (typical)
    CONTEXT-CARRYOVER-53.md    (mid-range)
    CONTEXT-CARRYOVER-99.md    (boundary: highest valid NN)

  Path variants (basename extraction must handle all):
    /home/user/project/specs/002/CONTEXT-CARRYOVER-01.md   (absolute)
    specs/002/CONTEXT-CARRYOVER-01.md                      (relative)
    ./CONTEXT-CARRYOVER-01.md                              (dot-relative)
    CONTEXT-CARRYOVER-01.md                                (bare basename)

  Tool name variants:
    tool_name: "Write"  + any of the above
    tool_name: "Edit"   + any of the above
```

---

### T06 — Filename pattern: negative cases [MUST] {J3}

**Junction:** D — basename does NOT match
**FR:** FR-001, FR-010

```text
For each file_path below, the hook MUST NOT trigger:

  CONTEXT-CARRYOVER-1.md           (single digit — requires 2)
  CONTEXT-CARRYOVER-001.md         (triple digit)
  CONTEXT-CARRYOVER-AB.md          (letters, not digits)
  context-carryover-01.md          (lowercase — case-sensitive)
  CONTEXT-CARRYOVER-01.txt         (wrong extension)
  CONTEXT-CARRYOVER.md             (no sequence number)
  CONTEXT-CARRYOVER-01.md.loaded   (consumed marker suffix)
  my-CONTEXT-CARRYOVER-01.md       (prefix before pattern)
  CONTEXT-CARRYOVER-01.md.bak      (suffix after pattern)
  CONTEXT-CARRYOVER-01             (no .md extension)
  /CONTEXT-CARRYOVER-01/foo.md     (pattern in directory, not basename)
```

---

### T07 — Recovery marker suppression [MUST] {J4}

**Junction:** E — `.claude/recovery-marker.json` exists
**FR:** FR-016

```text
Given: .claude/recovery-marker.json exists (even if empty/zero bytes)
       stdin: matching Write + CONTEXT-CARRYOVER-01.md
When:  carryover-detect.sh processes stdin
Then:  EXIT 0, no stdout
       .claude/carryover-pending NOT created
       Log entry: "recovery in progress, suppressing"

Verify marker check is file-existence only (not JSON parsing).
```

---

### T08 — Full trigger: tmux path [MUST] {J4→J5}

**Junction:** E (no marker) → G ($TMUX set)
**FR:** FR-002, FR-003, FR-022, FR-028

```text
Given: No .claude/recovery-marker.json
       $TMUX = "/tmp/tmux-1000/default,12,0" (realistic value)
       stdin: matching Write + CONTEXT-CARRYOVER-01.md
When:  carryover-detect.sh processes stdin
Then:  .claude/carryover-pending created
       Background poller process spawned (verify with: ps aux | grep poller)
       stdout is valid JSON:
         {"continue":false,"stopReason":"Context rotation: CARRYOVER saved..."}
       Poller does NOT inherit hook stdout (verify no extra bytes on stdout)
```

---

### T09 — Full trigger: non-tmux path [MUST] {J5}

**Junction:** G — $TMUX unset
**FR:** FR-002, FR-005, FR-022

```text
Given: $TMUX unset (unset TMUX)
       Also test: TMUX="" (empty string — must behave same as unset)
       stdin: matching Write + CONTEXT-CARRYOVER-01.md
When:  carryover-detect.sh processes stdin
Then:  .claude/carryover-pending created
       No poller process spawned
       stdout is valid JSON: {"continue":false,"stopReason":"..."}
```

---

### T10 — Malformed stdin JSON [SHOULD] {G2}

**Junction:** MISSING from flowchart
**FR:** FR-024 (implicit: graceful error handling)

```text
Given: Each of the following stdin inputs:
       (empty)
       {"incomplete json
       {"tool_name": "Write"}                   (missing tool_input)
       {"tool_name": "Write", "tool_input": {}} (missing file_path)
       not json at all
When:  carryover-detect.sh processes stdin
Then:  EXIT 0 or EXIT 1 (never EXIT 2 — jq IS available)
       No stdout (never output continue:false on bad input)
       No signal files created
       No crash / no hang
```

---

## Phase 2a — Idle-Detection Poller (carryover-poller.sh)

### T11 — Prompt pattern: positive match [MUST] {J6}

**Junction:** SCAN — 3-line consecutive pattern
**FR:** FR-004

```text
Given: Mock tmux capture-pane returns:
       Some Claude output text here...
       ─────────────────────────────────────────────────────────────
       ❯
       ─────────────────────────────────────────────────── ··· ─
       ⏵⏵ accept edits on (shift+tab to cycle)
When:  Poller scans the output
Then:  Pattern matches (3 consecutive: separator, prompt, separator)
       Proceeds to atomic mv claim

Also test these positive variants:
  - ❯ followed by cursor block character (❯ █)
  - Separators of different lengths (12 chars, 80 chars, 200 chars)
  - Extra blank lines after the second separator
  - No status line below second separator (clean prompt)
```

---

### T12 — Prompt pattern: negative match [MUST] {J6}

**Junction:** SCAN — no match
**FR:** FR-004

```text
Test each — poller MUST continue polling (no match):

  a) Claude still generating (no ❯ line, no separators):
     "Analyzing the code..."

  b) ❯ in model output text (not between separators):
     "The prompt character ❯ is used for..."

  c) Separators present but no ❯ between them:
     ─────────────────────
     (blank line)
     ─────────────────────

  d) ❯ present but only ONE separator (above only):
     ─────────────────────
     ❯
     Some other content

  e) Permission prompt (different UI state):
     "Allow Read access to /foo? (y/n)"
```

---

### T13 — ANSI escape codes in pane output [MUST] {G3}

**Junction:** SCAN — LIKELY BUG
**FR:** FR-004

```text
Given: Mock tmux capture-pane returns ANSI-wrapped output:
       \e[38;5;246m─────────────────────\e[0m
       \e[0m❯ \e[0m
       \e[38;5;246m─────────────────────\e[0m
When:  Poller scans with pattern regex
Then:  VERIFY: does the regex match through ANSI codes?

If NO (expected): implementation MUST strip ANSI before matching:
  sed 's/\x1b\[[0-9;]*m//g'
  OR verify tmux capture-pane -p strips escapes in target tmux version

Resolution: determine tmux capture-pane -p behavior:
  tmux 3.3+: -p flag outputs plain text (no escapes) by default
  tmux <3.3: -p may include escapes
  Add defensive ANSI stripping regardless of version.
```

---

### T14 — Poller timeout [SHOULD] {J7}

**Junction:** TMO — elapsed >= 30s
**FR:** FR-004

```text
Given: Mock tmux capture-pane always returns non-matching content
When:  Poller runs for 30+ seconds
Then:  .claude/carryover-clear-needed created
       Log entry: timeout error
       .claude/carryover-pending.claimed cleaned by EXIT trap
       Poller exits (not hung)

Also test: exactly 30 iterations of 1s sleep = 30s boundary
```

---

### T15 — Atomic mv: user typed /clear first [MUST] {J8}

**Junction:** CLAIM — mv fails (pending already deleted)
**FR:** FR-004

```text
Given: Poller detects prompt pattern
       .claude/carryover-pending was already deleted (user typed /clear,
       loader consumed it)
When:  Poller attempts: mv carryover-pending carryover-pending.claimed
Then:  mv fails (source file gone)
       Poller exits 0 silently
       No /clear sent via tmux send-keys
       No carryover-clear-needed written
```

---

### T16 — Atomic mv: poller wins the race [SHOULD] {J8}

**Junction:** CLAIM — mv succeeds
**FR:** FR-004

```text
Given: .claude/carryover-pending exists
       Poller detects prompt
When:  Poller claims: mv carryover-pending carryover-pending.claimed
Then:  mv succeeds
       tmux send-keys '/clear' Enter is executed
       EXIT trap cleans .claimed on exit
       .claimed does NOT persist after poller exits
```

---

### T17 — capture-pane failure: pane closed [SHOULD] {J9}

**Junction:** POLL → FAIL_W (capture-pane returns non-zero)
**FR:** FR-004

```text
Given: Poller running
When:  tmux pane is killed (tmux kill-pane) mid-poll
Then:  capture-pane returns non-zero on next attempt
       .claude/carryover-clear-needed created
       Log entry: capture-pane failure
       Poller exits, trap cleans .claimed if it existed
```

---

### T18 — Poller fd isolation: no stdout corruption [MUST] {FR-028}

**Junction:** N/A (invariant)
**FR:** FR-028

```text
Given: Hook spawns poller via (nohup ... </dev/null >/dev/null 2>&1 &)
When:  Poller runs, logs messages, writes files
Then:  Hook stdout contains ONLY the JSON output (no poller output mixed in)
       Poller log messages appear in .claude/recovery-logs/ only
       Verify: capture hook stdout, assert valid JSON, no extra bytes
```

---

## Phase 2b — Non-tmux Manual Path

### T19 — User never types /clear (walks away) [SHOULD]

**Junction:** N/A (non-tmux timeout behavior)
**FR:** FR-022

```text
Given: Non-tmux trigger completed (carryover-pending exists)
       User closes terminal / walks away
When:  User opens new Claude session later (startup event)
Then:  Loader finds carryover-pending + carryover file → loads it
       Self-heals without user typing /clear
```

---

## Phase 3 — SessionStart Loader (carryover-loader.sh)

### T20 — jq missing (Phase 3) [MUST] {J10}

**Junction:** JQ — require_tool jq
**FR:** FR-025

```text
Given: jq not in PATH
When:  carryover-loader.sh runs (any SessionStart event)
Then:  EXIT 2
       stderr: remediation message
       stdout: empty (no additionalContext)
```

---

### T21 — Startup: full linear signal scan [MUST] {J11}

**Junction:** STARTUP (yes) → LINEAR (FR-030)
**FR:** FR-029, FR-030

```text
Given: Event = "startup"
       .claude/carryover-pending.claimed exists (stale from SIGKILL)
       .claude/carryover-clear-needed exists (poller timed out)
       .claude/carryover-pending exists (rotation was initiated)
       $SPEC_DIR/CONTEXT-CARRYOVER-01.md exists (carryover was written)
When:  carryover-loader.sh runs
Then:  Step 1: .claimed deleted
       Step 2: clear-needed detected → reminder injected, file deleted
       Step 3: pending exists + file found → carryover loaded
       additionalContext contains BOTH reminder text AND carryover content
       All signal files cleaned up
```

---

### T22 — Clear event: skip signal cleanup [SHOULD] {J11}

**Junction:** STARTUP (no — clear or compact)
**FR:** FR-011, FR-030

```text
Given: Event = "clear"
       .claude/carryover-clear-needed exists (stale)
       .claude/carryover-pending.claimed exists (stale)
When:  carryover-loader.sh runs
Then:  clear-needed NOT deleted (only on startup)
       .claimed NOT deleted (only on startup)
       Carryover file loaded if present (normal load path)
```

---

### T23 — Compact event: load carryover as fallback [SHOULD] {J11}

**Junction:** STARTUP (no — compact)
**FR:** FR-011, User Story 3

```text
Given: Event = "compact"
       $SPEC_DIR/CONTEXT-CARRYOVER-01.md exists
When:  carryover-loader.sh runs
Then:  Carryover loaded into additionalContext
       Renamed to .loaded
       Model receives carryover to recover lost compaction context
```

---

### T24 — Wrong branch: no spec directory [SHOULD] {J12}

**Junction:** DIR — spec directory does not exist
**FR:** FR-006

```text
Given: git branch --show-current returns "main"
       specs/main/ does NOT exist
When:  carryover-loader.sh runs
Then:  Log warning: "No spec directory for branch 'main'"
       EXIT 0, no additionalContext
       Carryover file persists on disk for correct branch

Also test: branch = "develop", "feature/foo", any non-spec branch
```

---

### T25 — Detached HEAD: empty branch name [MUST] {J12, G4}

**Junction:** DIR — POTENTIAL BUG
**FR:** FR-006

```text
Given: Detached HEAD (git branch --show-current returns "")
When:  Loader constructs path: specs/${branch}/
Then:  Path = "specs//"
       VERIFY: [ -d "specs//" ] does NOT accidentally match specs/
       Expected: directory check fails, log warning, exit 0

Implementation note: add explicit guard:
  branch=$(git branch --show-current)
  if [ -z "$branch" ]; then log_warn "detached HEAD"; exit 0; fi
```

---

### T26 — Single carryover file [SHOULD] {J13}

**Junction:** FOUND — one file
**FR:** FR-006, FR-007

```text
Given: $SPEC_DIR/ contains only CONTEXT-CARRYOVER-01.md (unconsumed)
When:  Loader searches
Then:  Selects CONTEXT-CARRYOVER-01.md
       Proceeds to size check
```

---

### T27 — Multiple carryover files: highest NN wins [MUST] {J13}

**Junction:** FOUND — multiple files
**FR:** FR-026

```text
Given: $SPEC_DIR/ contains:
       CONTEXT-CARRYOVER-01.md          (unconsumed)
       CONTEXT-CARRYOVER-03.md          (unconsumed)
       CONTEXT-CARRYOVER-07.md          (unconsumed)
       CONTEXT-CARRYOVER-03.md.loaded   (consumed — must be excluded)
       CONTEXT-CARRYOVER-12.md.loaded   (consumed — must be excluded)
When:  Loader searches and selects
Then:  Selected: CONTEXT-CARRYOVER-07.md (highest NN among unconsumed)
       .loaded files are NOT considered
```

---

### T28 — No files + pending signal: missing warning [MUST] {J13+J14}

**Junction:** FOUND (none) → PEND_CHK (yes)
**FR:** FR-022

```text
Given: $SPEC_DIR/ exists, no unconsumed CONTEXT-CARRYOVER-NN.md files
       .claude/carryover-pending exists
When:  carryover-loader.sh runs
Then:  additionalContext: "CARRYOVER file was expected but not found
       or was empty. Ask the user for context about the previous task."
       .claude/carryover-pending deleted
```

---

### T29 — No files + no pending: normal /clear [SHOULD] {J13+J14}

**Junction:** FOUND (none) → PEND_CHK (no)
**FR:** FR-022

```text
Given: $SPEC_DIR/ exists, no CARRYOVER files, no carryover-pending
When:  carryover-loader.sh runs (triggered by normal /clear)
Then:  EXIT 0, no additionalContext, no warnings, no errors
       This is the most common path — /clear without any rotation context
```

---

### T30 — Empty carryover file [SHOULD] {J15}

**Junction:** EMPTY — file < 100 bytes
**FR:** FR-022

```text
Given: CONTEXT-CARRYOVER-01.md exists, contents = "# Carryover\n" (14 bytes)
When:  Loader processes it
Then:  File renamed to CONTEXT-CARRYOVER-01.md.loaded
       additionalContext: empty-file warning

Boundary tests:
  File =  99 bytes → treated as empty (< 100)
  File = 100 bytes → treated as non-empty (>= 100) [verify boundary]
  File = 101 bytes → treated as non-empty
```

---

### T31 — Oversized carryover: truncation [SHOULD] {J16}

**Junction:** BIG — file > 80KB
**FR:** FR-019

```text
Given: CONTEXT-CARRYOVER-01.md is 120KB of markdown content
When:  Loader processes it
Then:  additionalContext contains last ~80KB of file content
       Prepended with: "[CARRYOVER truncated — showing last 80KB of 122880]"
       File renamed to .loaded
       Total additionalContext size ≤ 80KB + preamble overhead

Boundary tests:
  File = 81919 bytes (80KB - 1)  → NOT truncated
  File = 81920 bytes (exactly 80KB) → NOT truncated [verify boundary: > not >=]
  File = 81921 bytes (80KB + 1)  → truncated
```

---

### T32 — Truncation preserves valid UTF-8 [SHOULD] {J16, G5}

**Junction:** BIG — POTENTIAL BUG
**FR:** FR-019

```text
Given: CONTEXT-CARRYOVER-01.md is 100KB
       Content includes multi-byte UTF-8 characters (emoji 🎉, CJK 漢字)
       placed near the 80KB boundary
When:  Tail-truncation cuts at byte offset
Then:  VERIFY: output is valid UTF-8 (no split characters)
       Run: echo "$output" | iconv -f UTF-8 -t UTF-8 > /dev/null
       If invalid: implementation must truncate on line boundary

Implementation recommendation: use `tail -c 81920` then trim to last
complete line with `sed '1{/^$/d; /^[^[:print:]]/d}'` or equivalent.
```

---

### T33 — Signal trap: undo .loaded rename on SIGTERM [MUST] {FR-025}

**Junction:** Between RENAME and OUTPUT
**FR:** FR-025

```text
Given: Loader has renamed CONTEXT-CARRYOVER-01.md → .loaded
When:  SIGTERM sent to loader PID (kill $PID)
Then:  Trap fires: .loaded renamed back to CONTEXT-CARRYOVER-01.md
       File is unconsumed again, will be loaded on next cycle
       EXIT code is non-zero

Also test: SIGINT (Ctrl-C), SIGHUP (terminal hangup)
Negative: SIGKILL cannot be trapped — .loaded persists (expected, CR4)
```

---

### T34 — .loaded cleanup: keep 5, delete oldest [SHOULD] {FR-021}

**Junction:** After OUTPUT → CLEAN
**FR:** FR-021

```text
Given: $SPEC_DIR/ contains .loaded files with distinct modification times:
       CONTEXT-CARRYOVER-01.md.loaded  (oldest)
       CONTEXT-CARRYOVER-02.md.loaded
       CONTEXT-CARRYOVER-03.md.loaded
       CONTEXT-CARRYOVER-04.md.loaded
       CONTEXT-CARRYOVER-05.md.loaded
       CONTEXT-CARRYOVER-06.md.loaded
       CONTEXT-CARRYOVER-07.md.loaded
       CONTEXT-CARRYOVER-08.md.loaded  (newest)
When:  Loader runs cleanup after successful load
Then:  01, 02, 03 .loaded files deleted (3 oldest)
       04, 05, 06, 07, 08 .loaded files kept (5 most recent)

Boundary: exactly 5 .loaded files → no deletion
          6 .loaded files → 1 deleted (oldest)
```

---

### T35 — JSON output with special characters [MUST] {FR-027}

**Junction:** OUTPUT — jq serialization
**FR:** FR-027

```text
Given: CONTEXT-CARRYOVER-01.md contains:
       Line with "double quotes"
       Line with 'single quotes'
       Line with \backslashes\
       Line with $dollar and `backticks`
       Line with newlines
       (embedded)
       Line with unicode: 🎉 漢字 ñ
       Line with JSON-like content: {"key": "value"}
       Line with null bytes: (if possible in markdown)
When:  Loader constructs jq output
Then:  stdout is valid JSON (jq . < stdout succeeds)
       Content survives round-trip:
         actual=$(echo "$json" | jq -r '.hookSpecificOutput.additionalContext')
         diff <(cat original) <(echo "$actual") shows only preamble additions
```

---

## Crash Recovery Simulations

### T36 — Crash sim: pending + carryover on startup [SHOULD] {CR1}

**Junction:** CR1 — SIGKILL after carryover-pending written
**FR:** FR-022, FR-030

```text
Given: Event = startup
       .claude/carryover-pending exists
       $SPEC_DIR/CONTEXT-CARRYOVER-01.md exists (model completed write)
When:  carryover-loader.sh runs
Then:  Carryover file loaded normally
       carryover-pending deleted in cleanup
       Self-healing: no user intervention needed
```

---

### T37 — Crash sim: pending but no carryover on startup [SHOULD] {CR1}

**Junction:** CR1 — SIGKILL before model finished writing
**FR:** FR-022, FR-030

```text
Given: Event = startup
       .claude/carryover-pending exists
       No CONTEXT-CARRYOVER-NN.md files in $SPEC_DIR/
When:  carryover-loader.sh runs
Then:  additionalContext: "CARRYOVER expected but missing..."
       carryover-pending deleted
       Warning: model asks user for context
```

---

### T38 — Crash sim: stale .claimed + carryover on startup [SHOULD] {CR2}

**Junction:** CR2 — SIGKILL after poller claimed
**FR:** FR-029

```text
Given: Event = startup
       .claude/carryover-pending.claimed exists (stale from killed poller)
       $SPEC_DIR/CONTEXT-CARRYOVER-01.md exists
When:  carryover-loader.sh runs
Then:  .claimed deleted (FR-029 step 1)
       Carryover file loaded normally
       Self-healing
```

---

### T39 — Crash sim: .loaded + pending on startup [SHOULD] {CR4}

**Junction:** CR3 — SIGKILL between rename and output
**FR:** FR-022, FR-025

```text
Given: Event = startup
       .claude/carryover-pending exists (not yet cleaned)
       $SPEC_DIR/CONTEXT-CARRYOVER-01.md.loaded exists (consumed)
       No unconsumed CONTEXT-CARRYOVER-NN.md files
When:  carryover-loader.sh runs
Then:  pending found + no unconsumed file → injects "expected but missing"
       pending deleted
       Warning: user must provide context
       Note: data IS recoverable — user can rename .loaded back manually
```

---

## End-to-End Integration Tests

### T40 — E2E happy path: tmux zero-touch [MUST] {SC-001}

**FR:** SC-001, User Story 1

```text
Given: Claude Code session running in tmux
       Context usage approaches guardian threshold
When:  Guardian denies tool call
       Model writes CONTEXT-CARRYOVER-NN.md
Then:  1. PostToolUse hook fires: continue:false, poller spawned
       2. Poller detects idle prompt: mv claim succeeds
       3. tmux send-keys '/clear' Enter
       4. SessionStart fires (event=clear)
       5. Loader finds carryover, loads into additionalContext
       6. Model resumes with carryover context
       Zero user interaction throughout.
       Log file in .claude/recovery-logs/ records all steps.
```

---

### T41 — E2E happy path: non-tmux one-step [MUST] {SC-002}

**FR:** SC-002, User Story 2

```text
Given: Claude Code session in plain terminal (no tmux)
       Context at threshold
When:  Guardian denies, model writes CARRYOVER
Then:  1. PostToolUse hook fires: continue:false, no poller
       2. User sees: "Type /clear to continue"
       3. User types /clear
       4. SessionStart fires (event=clear)
       5. Loader finds carryover, loads into additionalContext
       6. Model resumes
       Exactly one manual step (typing /clear).
```

---

### T42 — E2E: consumed carryover not reloaded [MUST] {SC-004}

**FR:** SC-004

```text
Given: Carryover was loaded in a previous /clear cycle
       File is now CONTEXT-CARRYOVER-01.md.loaded
When:  User types /clear again (no new rotation)
Then:  Loader does NOT load the .loaded file
       No additionalContext injected
       No carryover-pending signal → no "expected but missing" warning
```

---

## Gaps Found During Analysis

Issues discovered that are NOT covered in the flowchart or spec.
Listed for tracking; should be resolved before or during implementation.

| ID | Gap | Severity | Test | Recommendation |
|----|-----|----------|------|----------------|
| G1 | `hook-common.sh` not found — no flowchart junction | Medium | T01 | Add pre-entry check; flowchart update |
| G2 | Stdin JSON malformed/empty — no junction | Medium | T10 | Handle gracefully; exit 0 on parse failure |
| G3 | ANSI codes in `tmux capture-pane -p` output | **High** | T13 | Strip ANSI defensively before regex match |
| G4 | Detached HEAD → empty branch → `specs//` path | Medium | T25 | Guard: `[ -z "$branch" ] && exit 0` |
| G5 | Truncation splits UTF-8 multi-byte character | Medium | T32 | Truncate on line boundary, not raw byte |
| G6 | Poller spawn failure — no detection or fallback | Low | — | Check spawn success; log if failed |
| G7 | `.claude/` directory might not exist | Low | — | `mkdir -p .claude` before signal file writes |
| G8 | `git` not installed / not a git repo | Low | — | Add `require_tool git` or guard in loader |

---

## Coverage Summary

| Phase | Junctions | Tests | Coverage |
|-------|-----------|-------|----------|
| Phase 1 — PostToolUse Hook | 5 + 2 missing | T01–T10 | All edges |
| Phase 2a — Poller | 4 + 1 missing | T11–T18 | All edges |
| Phase 2b — Non-tmux | 0 (linear) | T19 | Timeout behavior |
| Phase 3 — Loader | 7 + 1 missing | T20–T35 | All edges |
| Crash Recovery | 4 points | T36–T39 | All crash states |
| End-to-End | — | T40–T42 | Happy paths + SC-004 |
| **Total** | **16 + 4 missing** | **42** | **All known edges** |

### Priority Breakdown

| Priority | Count | Tests |
|----------|-------|-------|
| MUST | 15 | T01–T03, T05–T09, T11, T13, T15, T18, T20–T21, T25, T27–T28, T33, T35, T40–T42 |
| SHOULD | 16 | T04, T14, T16–T17, T19, T22–T24, T26, T29–T32, T34, T36–T39 |
| Boundary | 11 | Included within T05, T06, T27, T30, T31, T34 as sub-cases |
