# 002 Context Auto-Rotation — End-to-End Flowchart

**Date:** 2026-03-11 (updated from 2026-03-10)
**Covers:** All happy paths, unhappy paths, race conditions, crash recovery (SIGKILL/lid close), and cross-system integration points
**Updates:** Integration audit paths, session-scoped temp files, staleness window reduction, watcher SIGHUP protection, startup event coverage

> Render with any Mermaid viewer (GitHub markdown, VS Code extension, mermaid.live).
> Uses dark theme with high-contrast colors. If rendering in a light-themed viewer,
> the `%%{init}%%` block can be removed.

## Main Operational Flow

```mermaid
%%{init: {'theme': 'dark', 'themeVariables': {'fontSize': '16px', 'fontFamily': 'Consolas, monospace', 'lineColor': '#ecf0f1', 'primaryTextColor': '#ecf0f1'}}}%%

flowchart TD
    classDef ok fill:#0d6b38,stroke:#2ecc71,color:#fff,stroke-width:2px,font-weight:bold
    classDef warn fill:#7d5a00,stroke:#f1c40f,color:#fff,stroke-width:2px,font-weight:bold
    classDef fail fill:#7a0000,stroke:#e74c3c,color:#fff,stroke-width:2px,font-weight:bold
    classDef decide fill:#1a3a6c,stroke:#5dade2,color:#ecf0f1,stroke-width:2px,font-weight:bold
    classDef proc fill:#2c2c2c,stroke:#bdc3c7,color:#ecf0f1,stroke-width:1px
    classDef signal fill:#4a148c,stroke:#bb86fc,color:#fff,stroke-width:2px
    classDef crash fill:#b34700,stroke:#ff8c00,color:#fff,stroke-width:2px

    START(["Model writes CARRYOVER file<br/>PostToolUse hook fires"]):::proc

    START --> A

    %% ═══════════════════════════════════════════════════════
    %% PHASE 1 — PostToolUse Hook (carryover-detect.sh)
    %% ═══════════════════════════════════════════════════════
    subgraph P1["&nbsp; PHASE 1 — PostToolUse Hook &middot; carryover-detect.sh &nbsp;"]
        direction TB

        A{"require_tool jq"}:::decide
        A -->|Missing| A_FAIL["EXIT 2 &mdash; jq not installed<br/>Hook never runs. Model continues.<br/>No rotation occurs."]:::fail

        A -->|OK| B{"tool_name ==<br/>Write or Edit?"}:::decide
        B -->|"No &rarr; fast path"| B_OK["EXIT 0 in &lt; 1ms<br/>No output"]:::ok

        B -->|Yes| C["Extract basename<br/>from tool_input.file_path"]:::proc
        C --> D{"basename matches<br/>/^CONTEXT-CARRYOVER-[0-9]{'{'}2{'}'}.md$/"}:::decide
        D -->|No| D_OK["EXIT 0 &mdash; not a carryover"]:::ok

        D -->|Yes| E{".claude/recovery-marker.json<br/>exists? &lpar;FR-016&rpar;"}:::decide
        E -->|"Yes &rarr; 003 owns /clear"| E_SKIP["EXIT 0 &mdash; suppress entirely<br/>Recovery in progress"]:::proc

        E -->|No| F["Write .claude/carryover-pending"]:::signal
        F --> G{"$TMUX set?"}:::decide

        G -->|Yes| H["Spawn detached poller<br/>&lpar;nohup poller &lt;/dev/null &gt;/dev/null 2&gt;&amp;1 &&rpar;"]:::proc
        G -->|No| I["No poller &mdash; non-tmux path"]:::proc

        H --> J["Output JSON to stdout:<br/>continue: false<br/>stopReason: Type /clear to continue"]:::ok
        I --> J
    end

    %% Crash annotation — Phase 1
    F -. "SIGKILL after pending written" .-> CR1

    CR1{"Crash Recovery"}:::crash
    CR1 -->|"Carryover file on disk"| CR1_OK["SELF-HEALS: startup loader<br/>finds pending + file, loads it"]:::ok
    CR1 -->|"No carryover file"| CR1_WARN["WARNS: loader sees pending,<br/>no file, injects warning"]:::warn

    %% ═══════════════════════════════════════════════════════
    %% PHASE 2a — Poller (tmux path)
    %% ═══════════════════════════════════════════════════════
    J -->|"tmux path"| POLL_INIT
    J -->|"non-tmux path"| USER_MSG

    subgraph P2["&nbsp; PHASE 2a — Idle-Detection Poller &middot; carryover-poller.sh &nbsp;"]
        direction TB

        POLL_INIT["Install EXIT trap:<br/>rm -f .claude/carryover-pending.claimed"]:::proc
        POLL_INIT --> POLL["tmux capture-pane -p"]:::proc

        POLL --> SCAN{"Scan full pane for<br/>3 consecutive lines:<br/>^&boxh;{'{'}12,{'}'}<br/>^&rtrif; &lpar;U+276F&rpar;<br/>^&boxh;{'{'}12,{'}'}"}:::decide

        SCAN -->|"No match"| TMO{"Elapsed &ge; 60s?"}:::decide
        TMO -->|No| SLP["Sleep 1s"]:::proc
        SLP --> POLL

        TMO -->|"Yes &rarr; timeout"| FAIL_W["Write .claude/carryover-clear-needed<br/>Log error"]:::signal
        FAIL_W --> FAIL_X["EXIT &mdash; trap cleans .claimed"]:::warn

        POLL -. "capture-pane fails<br/>&lpar;pane closed&rpar;" .-> FAIL_W

        SCAN -->|"Match &rarr; prompt visible"| CLAIM{"Atomic mv:<br/>pending &rarr; .claimed"}:::decide

        CLAIM -->|"mv fails &mdash; file gone"| RACE_OK["User already typed /clear<br/>Poller exits silently"]:::ok

        CLAIM -->|"mv succeeds &mdash; poller owns /clear"| BANNER["Send banner via send-keys:<br/># &x23F3; Auto-clearing context &mdash; do NOT type /clear"]:::proc
        BANNER --> SEND["tmux send-keys '/clear' Enter"]:::proc
        SEND --> SEND_OK["EXIT &mdash; trap cleans .claimed"]:::ok
    end

    %% Crash annotations — Phase 2
    CLAIM -. "SIGKILL after claim<br/>before send-keys" .-> CR2
    CR2["SELF-HEALS: FR-029 cleans stale .claimed<br/>Loader finds carryover file, loads it"]:::crash

    SEND -. "SIGKILL after send-keys" .-> CR2B
    CR2B["/clear was already sent<br/>Session restarts normally"]:::crash

    %% ═══════════════════════════════════════════════════════
    %% PHASE 2b — Non-tmux manual path
    %% ═══════════════════════════════════════════════════════
    subgraph P2B["&nbsp; PHASE 2b — Non-tmux Manual Path &nbsp;"]
        USER_MSG["User sees stopReason message:<br/>Type /clear to continue<br/>ONE manual step required"]:::warn
        USER_MSG --> USER_ACT["User types /clear"]:::proc
    end

    %% All paths converge to SessionStart
    SEND_OK --> SESSION
    RACE_OK --> SESSION
    USER_ACT --> SESSION

    %% ═══════════════════════════════════════════════════════
    %% PHASE 3 — SessionStart Loader (carryover-loader.sh)
    %% ═══════════════════════════════════════════════════════
    subgraph P3["&nbsp; PHASE 3 — SessionStart Loader &middot; carryover-loader.sh &nbsp;"]
        direction TB

        SESSION["SessionStart event fires:<br/>clear | compact | startup"]:::proc

        SESSION --> JQ{"require_tool jq"}:::decide
        JQ -->|Missing| JQ_FAIL["EXIT 2 &mdash; carryover NOT loaded<br/>Model starts with no context"]:::fail

        JQ -->|OK| TRAPS["Install signal traps:<br/>SIGTERM, SIGINT, SIGHUP<br/>&rarr; undo .loaded rename on kill"]:::proc

        TRAPS --> EVT{"Event type?"}:::decide

        EVT -->|startup| LINEAR["FR-030 Linear signal scan:<br/>1. rm stale .claimed<br/>2. clear-needed &rarr; inject reminder<br/>3. pending checked below"]:::proc

        EVT -->|compact| COMPACT_REC{"FR-033: recovery-marker.json<br/>exists?"}:::decide
        COMPACT_REC -->|"Yes &rarr; recovery active"| COMPACT_SKIP["Log: compact suppressed<br/>Exit 0, no additionalContext"]:::ok
        COMPACT_REC -->|No| BRANCH

        EVT -->|clear| DBLCLR{"FR-032: .loaded mtime<br/>&le; 60s + no unconsumed<br/>+ no pending?"}:::decide
        DBLCLR -->|"Yes &rarr; double-/clear"| DBLCLR_OK["Log: double-/clear detected<br/>carryover already loaded &le;60s ago<br/>Exit 0, no additionalContext"]:::ok
        DBLCLR -->|No| BRANCH

        LINEAR --> BRANCH

        BRANCH["git branch --show-current<br/>&rarr; specs/$branch/"]:::proc
        BRANCH --> DIR{"Spec directory<br/>exists?"}:::decide

        DIR -->|"No &lpar;wrong branch, main, detached HEAD&rpar;"| DIR_WARN["Log warning, exit 0<br/>No carryover loaded.<br/>File persists for correct branch."]:::warn

        DIR -->|Yes| SEARCH["Search for unconsumed<br/>CONTEXT-CARRYOVER-NN.md"]:::proc

        SEARCH --> FOUND{"Files found?"}:::decide

        FOUND -->|Multiple| PICK["Select highest NN<br/>&lpar;FR-026&rpar;"]:::proc
        FOUND -->|One| USE["Use it"]:::proc
        FOUND -->|"None"| PEND_CHK{"carryover-pending<br/>signal exists?"}:::decide

        PEND_CHK -->|Yes| MISS_WARN["Inject warning:<br/>CARRYOVER expected but missing.<br/>Ask user for context.<br/>Delete pending marker."]:::warn

        PEND_CHK -->|No| NORM["Normal /clear &mdash; no carryover<br/>Exit 0"]:::ok

        PICK --> EMPTY
        USE --> EMPTY

        EMPTY{"File &lt; 100 bytes?"}:::decide
        EMPTY -->|"Yes &mdash; empty"| EMPTY_W["Rename &rarr; .loaded<br/>Inject empty-file warning"]:::warn
        EMPTY -->|No| BIG{"File &gt; 80KB?"}:::decide

        BIG -->|Yes| TRUNC["Tail-truncate to 80KB<br/>Prepend: truncated from N bytes"]:::proc
        BIG -->|No| READ["Read file contents"]:::proc

        TRUNC --> READ

        READ --> RENAME["Rename &rarr; .loaded<br/>&lpar;signal traps protect this&rpar;"]:::signal

        RENAME --> WRAP["Wrap in preamble:<br/>--- CARRYOVER CONTEXT ---<br/>... file contents ...<br/>--- END CARRYOVER CONTEXT ---"]:::proc

        WRAP --> OUTPUT["Output via jq:<br/>hookSpecificOutput.additionalContext"]:::ok

        OUTPUT --> CLEAN["Cleanup:<br/>Delete .loaded beyond 5 most recent<br/>Delete carryover-pending if present"]:::proc

        CLEAN --> DONE(["MODEL RESUMES<br/>with carryover context"]):::ok
    end

    %% Crash annotation — Phase 3 critical window
    RENAME -. "SIGKILL between<br/>rename and output" .-> CR3

    CR3{"Crash Recovery"}:::crash
    CR3 --> CR3_W["WARNS on next startup:<br/>.loaded exists but never loaded.<br/>pending still on disk.<br/>Loader injects missing warning.<br/>User provides context manually."]:::warn

    %% ═══════════════════════════════════════════════════════
    %% Cycle back — context eventually fills again
    %% ═══════════════════════════════════════════════════════
    DONE -. "Context fills up again &rarr;<br/>guardian fires &rarr; new rotation" .-> START

    %% ═══════════════════════════════════════════════════════
    %% LEGEND
    %% ═══════════════════════════════════════════════════════
    subgraph LEGEND["&nbsp; LEGEND &nbsp;"]
        direction LR
        L1["SELF-HEALS<br/>automatically"]:::ok
        L2["WARNS<br/>human input needed"]:::warn
        L3["BLOCKS<br/>fix required"]:::fail
        L4["CRASH POINT<br/>lid close / SIGKILL"]:::crash
    end
```

## Crash Recovery Matrix

Every step where persistent state changes. "Disk state" is what survives a SIGKILL/power loss.

| Crash Point | Phase | Disk State After Crash | On Next Startup | Recovery Type |
|---|---|---|---|---|
| **Before any signal files** | P1 | Nothing written | Normal startup, no evidence of rotation | No impact |
| **After `carryover-pending` written, carryover file on disk** | P1 | `pending` + CARRYOVER file | Loader finds both, loads carryover | SELF-HEALS |
| **After `carryover-pending` written, no carryover file** | P1 | `pending` only | Loader injects "expected but missing" warning | WARNS |
| **After `continue:false` output, poller spawned** | P1/P2 | `pending` + CARRYOVER file + poller PID (dead) | Loader finds pending + file, loads it | SELF-HEALS |
| **Poller polling (before claim)** | P2 | `pending` + CARRYOVER file | Loader finds both, loads carryover | SELF-HEALS |
| **After `mv pending → .claimed`, before `send-keys`** | P2 | `.claimed` + CARRYOVER file | FR-029 deletes `.claimed`, loader finds file, loads it | SELF-HEALS |
| **After `send-keys`, before poller exit** | P2 | `/clear` already sent + `.claimed` | EXIT trap may not fire (SIGKILL). FR-029 cleans `.claimed`. `/clear` triggers loader normally | SELF-HEALS |
| **After banner sent, before /clear sent** | P2 | `.claimed` + CARRYOVER file, banner visible | EXIT trap may not fire. FR-029 cleans `.claimed`. Loader finds file, loads it | SELF-HEALS |
| **Poller timeout (60s), `clear-needed` written** | P2 | `clear-needed` + `pending` + CARRYOVER file | FR-030 linear scan: inject reminder, then load carryover | SELF-HEALS |
| **Poller timeout (60s), `clear-needed` written, no carryover** | P2 | `clear-needed` + `pending` | FR-030: inject reminder + inject "expected but missing" | WARNS (2x) |
| **Loader: before `.loaded` rename** | P3 | CARRYOVER file unconsumed | On next startup/clear, loader finds and loads it | SELF-HEALS |
| **Loader: after `.loaded` rename, before JSON output** | P3 | `.loaded` + `pending` (not yet deleted) | pending exists, no unconsumed file → "expected but missing" | WARNS |
| **Loader: after JSON output** | P3 | `.loaded`, pending deleted | Success already committed to stdout | No impact |

## Terminal States Summary

Every possible end state of the system, classified by outcome:

### Self-Healing (no human intervention)

| State | How It Recovers |
|---|---|
| Carryover file + pending on disk after any crash | Startup loader finds both, loads carryover normally |
| Stale `.claimed` after poller SIGKILL | FR-029 deletes on startup, then loads carryover |
| `/clear` sent but poller didn't clean up | Session already restarted; loader runs normally |
| Carryover file exists from prior crashed rotation | Startup event triggers loader, file loaded if on correct branch |
| Double-/clear from keystroke queuing (FR-032) | Loader detects `.loaded` mtime ≤60s, exits as no-op |

### Warns (pauses for human input)

| State | What User Sees |
|---|---|
| `pending` exists, no carryover file | Model told: "CARRYOVER expected but missing. Ask user for context." |
| `clear-needed` exists on startup | Model told: "Previous rotation incomplete — type /clear" |
| Empty carryover file (<100 bytes) | Model warned, file renamed to `.loaded` |
| Wrong git branch / no spec dir | Log warning, no carryover loaded. File persists for correct branch. |
| Non-tmux environment | User sees "Type /clear to continue" — one manual step |
| `.loaded` rename done but output lost (SIGKILL) | pending exists, no unconsumed file → missing-carryover warning |

### Blocks (fix required, no self-healing)

| State | What Happens | Fix |
|---|---|---|
| `jq` not installed (Phase 1) | EXIT 2 — hook never runs, model continues without rotation | `brew install jq` / `apt install jq` |
| `jq` not installed (Phase 3) | EXIT 2 — carryover not loaded, model starts fresh | `brew install jq` / `apt install jq` |

### Silent Failures (system cannot detect)

| State | Why Silent | Mitigation |
|---|---|---|
| Model never writes carryover file after guardian denies | 002 cannot force model behavior (out of scope) | Guardian instructions must emphasize carryover writing |
| Carryover file partially written (crash mid-Write) | File may be truncated but >100 bytes, loaded as-is | Partial data is better than none; model can ask for clarification |
| Concurrent sessions load wrong carryover | "Most recent unconsumed" heuristic — accepted risk | Rare edge case; not worth session-scoping complexity |

## Integration Audit — 2026-03-11

New paths discovered during live integration testing. These apply to the **pre-Phase-1 layer** (context-guardian.sh) and **cross-feature coordination** (003 recovery scripts).

### Pre-Phase 1: Context Guardian Integration Points

These paths exist in the currently deployed context-guardian.sh (PreToolUse hook) which operates upstream of the 002 carryover rotation system.

| Path | Description | Resolution |
|---|---|---|
| **Session-scoped temp file** | context-monitor.sh writes to `/tmp/claude-context-usage.<session_id>` and guardian reads matching file. Prevents cross-session and test pollution. | **FIXED 2026-03-11**: Both scripts now use session-scoped paths with unsession-scoped fallback. |
| **Stale Layer 1 data** | Guardian reads statusLine data from temp file. If file is >30s old, falls through to Layer 2 (JSONL size). | **FIXED 2026-03-11**: Staleness window reduced from 60s to 30s. |
| **StatusLine polling gap** | statusLine runs every ~5s. If context jumps from 65% to 85% in one tool response, guardian reads stale % and allows next tool. | **ACCEPTED RISK**: 5-second gap is inherent to polling architecture. Mitigated by: (1) 30s staleness window triggers Layer 2 fallback, (2) 003 recovery system handles compaction if guardian misses it. |
| **Guardian warn vs deny gap** | At 50-70%, guardian outputs `allow` with warning. Model may ignore soft warning and keep working. | **ACCEPTED RISK**: No enforcement between 50% and 70%. Hard block at 70% provides the safety net. |
| **jq dependency** | Guardian now uses jq (was python3). If jq missing, all JSON parsing fails silently, guardian exits 0 (allows everything). | **FIXED 2026-03-11**: Replaced python3 with jq, consistent with all other scripts. jq is validated by recovery-health.sh. |

### Cross-Feature Integration Points (003 Recovery)

| Path | Description | Resolution |
|---|---|---|
| **Watcher SIGHUP protection** | recovery-detect.sh spawns watcher with nohup/disown, preventing premature death if parent shell exits. | **FIXED 2026-03-11**: `nohup ... </dev/null >/dev/null 2>&1 & disown`. |
| **Startup event coverage** | recovery-loader.sh now fires on ALL SessionStart events (via `.*` matcher), not just `clear`. Allows recovery preamble injection on fresh `claude` invocations. | **FIXED 2026-03-11**: Added `.*` catch-all matcher + compact event guard in recovery-loader.sh. |
| **Loader compact guard** | recovery-loader.sh skips compact events (recovery-detect.sh handles those). Prevents double-injection of conflicting context. | **FIXED 2026-03-11**: `if SOURCE == "compact" then exit 0`. |
| **Watcher /clear race with user input** | If user is typing when watcher sends `/clear` via tmux send-keys, keystrokes interleave. 002 poller has banner protection; 003 watcher does not. | **ACCEPTED RISK**: 003 watcher polls for idle state before sending /clear. Interleaving is unlikely but possible. |

## Integration Audit — 2026-03-11 (Round 2)

Second-pass integration testing with dry-run validation of all deployed scripts. Focused on end-to-end flow verification, edge cases, and ground-truth reconciliation.

### Implementation Status

| Component | Status | Notes |
|---|---|---|
| **context-guardian.sh** (PreToolUse) | DEPLOYED | Blocks at 70%, warns at 50%, carryover write exception |
| **context-monitor.sh** (statusLine) | DEPLOYED | Writes context % to temp file every ~5s |
| **recovery-precompact.sh** (PreCompact) | DEPLOYED | Captures interrupted task before compaction |
| **recovery-detect.sh** (SessionStart compact) | DEPLOYED | Injects HALT instructions, spawns watcher |
| **recovery-loader.sh** (SessionStart clear/.*) | DEPLOYED | Loads 003 recovery context after /clear |
| **recovery-watcher.sh** (background) | DEPLOYED | Sends /clear after audit sentinel appears |
| **recovery-common.sh** + **hook-common.sh** | DEPLOYED | Shared libraries for all hooks |
| **carryover-detect.sh** (PostToolUse) | NOT IMPLEMENTED | 002 tasks T005 — auto-detect CARRYOVER writes |
| **carryover-poller.sh** (background) | NOT IMPLEMENTED | 002 tasks T006 — idle detection + auto-/clear |
| **carryover-loader.sh** (SessionStart) | NOT IMPLEMENTED | 002 tasks T007a/T007b — load CARRYOVER files into fresh session |

### New Blind Spots Found (Round 2)

| ID | Path | Description | Resolution |
|---|---|---|---|
| **BS-R2-01** | session_id path mismatch | `context-monitor.sh` reads `.session.session_id` (nested) but Claude Code statusLine JSON provides `session_id` at top level. Session-scoped temp file never created; all sessions share unsession-scoped `/tmp/claude-context-usage`. | **BUG — FIX NEEDED**: Change jq path from `.session.session_id` to `.session_id` in context-monitor.sh. Also update `.session.session_id` fallback for backwards compatibility. |
| **BS-R2-02** | No carryover auto-loading | After guardian blocks at 70% and model writes CARRYOVER file, no hook loads that file after /clear. 002 carryover-loader.sh (T005-T009) not implemented. recovery-loader.sh only handles 003 recovery markers. | **GAP — 002 NOT YET IMPLEMENTED**: Carryover files persist on disk but are not automatically injected. User must manually instruct model to read the file. |
| **BS-R2-03** | Loader fires on "resume" events | `.*` SessionStart matcher fires recovery-loader.sh on session resume. If stale recovery marker exists, injects recovery context into a resumed session that already has its own context. | **BUG — FIX NEEDED**: Add `if [[ "${SOURCE:-}" == "resume" ]]; then exit 0; fi` guard in recovery-loader.sh, analogous to the compact guard. |
| **BS-R2-04** | TMUX_PANE inheritance uncertainty | recovery-detect.sh spawns recovery-watcher.sh which requires `$TMUX_PANE`. Claude Code's hook environment may not inherit this variable. $TMUX_PANE is present in Bash tool environment but hook env is untested. | **UNVERIFIED**: Cannot test without triggering actual compaction. If TMUX_PANE is missing, watcher fails with error log and exits. Non-fatal — user can manually /clear. |
| **BS-R2-05** | Text generation without tools | Guardian only blocks tool calls. Model can continue generating text responses at 70%+, consuming context tokens toward compaction. Guardian has no mechanism to halt text-only output. | **ACCEPTED RISK**: Model is instructed via denial reason to stop all work. Text-only generation is lower token consumption than tool calls. 003 recovery system is the safety net. |
| **BS-R2-06** | Watcher idle detection fragility | recovery-watcher.sh uses `grep -qE '(^> \|^\$ \|^❯ \|claude\|Claude)'` — matches "Claude" anywhere in last tmux line, causing false positives. The 002 spec's 3-line separator pattern is more robust but not used in 003's watcher. | **ACCEPTED RISK**: False positive causes premature /clear send, which is benign (triggers loader). False negative causes timeout (60s) then exits — user must manually /clear. |
| **BS-R2-07** | Guardian malformed JSON fail-open | When guardian receives malformed JSON on stdin, jq fails silently, TOOL_NAME becomes empty, guardian exits 0 (allows tool). Fail-open behavior. | **ACCEPTED RISK**: Hook system should always send valid JSON. Fail-open is preferred over fail-closed (which would block all tools). |
| **BS-R2-08** | Double-hook dedup uncertainty | Both "clear" and `.*` matchers fire recovery-loader.sh on /clear. Claude Code deduplicates identical commands, but behavior unverified. If not deduped, second invocation finds no marker (consumed by first) and exits 0. | **ACCEPTED RISK**: Benign worst case — second invocation is a no-op. Both entries have identical command and timeout (30s). |

### Dry-Run Test Results Summary

| Test | Input | Expected | Actual | Status |
|---|---|---|---|---|
| Guardian: low context (Read tool) | 29% context, Read tool | Silent allow | exit 0 | PASS |
| Guardian: carryover Write | Write to CARRYOVER file | Allow (exception) | exit 0 | PASS |
| Guardian: 75% deny | 75% context, Bash tool | Deny | permissionDecision: deny | PASS |
| Guardian: 55% warn | 55% context, Bash tool | Allow with warning | permissionDecision: allow + warning | PASS |
| Guardian: 75% + carryover Write | 75% context, Write CARRYOVER | Allow (exception overrides) | exit 0 | PASS |
| Guardian: stale context file | 80% but file >30s old | Fall through to Layer 2 | exit 0 (no JSONL) | PASS |
| Guardian: empty session_id | 60%, unsession-scoped fallback | Warn via fallback | permissionDecision: allow + warning | PASS |
| Guardian: malformed JSON | Invalid stdin | Fail-open allow | exit 0 | PASS |
| Guardian: boundary 70% | Exactly 70% | Deny | deny | PASS |
| Guardian: boundary 69% | Exactly 69% | Allow with warning | allow | PASS |
| Guardian: Edit to CARRYOVER | Edit (not Write) to CARRYOVER | Allow | exit 0 | PASS |
| Guardian: case-insensitive match | Write to lowercase carryover | Allow | exit 0 | PASS |
| Monitor: writes context % | 42% with session_id | Write session-scoped file | CTX 42% + file created | PASS |
| Monitor: no session_id | Missing session field | Write unsession-scoped file | CTX 42% + fallback file | PASS |
| PreCompact: dry-run | Valid JSON + --dry-run | Log stages, no writes | All stages logged | PASS |
| PreCompact: malformed JSON | Invalid stdin | Graceful error exit | exit 1 with error log | PASS |
| Detect: dry-run (no marker) | compact event, no existing marker | Create marker + inject HALT | HALT context injected | PASS |
| Detect: re-entrant (same session) | compact event, same session marker | Skip creation, still inject | Skipped + HALT injected | PASS |
| Loader: no marker (normal /clear) | clear event, no marker | Silent exit | exit 0 | PASS |
| Loader: with marker | clear event, valid marker | Inject recovery context | Recovery context injected | PASS |
| Loader: compact guard | compact event | Skip entirely | exit 0 | PASS |
| Loader: startup event | startup, no marker | Silent exit | exit 0 | PASS |
| Loader: resume event + stale marker | resume, old marker present | **Should skip** | **Injects stale context** | **FAIL (BS-R2-03)** |
| Health check | All scripts + hooks | 14/14 pass | 14/14 pass | PASS |

## Verified Path Count

- **Happy paths:** 2 (tmux zero-touch, non-tmux one-step)
- **Unhappy logic branches:** 23 (previous 19 + session_id path fallback, resume event injection, text-only generation gap, double-hook dedup)
- **Crash recovery paths:** 12 (see matrix above, added banner crash point)
- **Total distinct terminal states:** 25
- **Self-healing:** 5 scenarios (added double-/clear detection)
- **Warns:** 6 scenarios
- **Blocks:** 2 scenarios (both: install jq)
- **Silent failures:** 3 scenarios (all accepted risks with mitigations)
- **Accepted risks:** 7 scenarios (previous 3 + text generation, watcher idle, malformed JSON, double-hook)
- **Bugs requiring fix:** 2 (session_id path BS-R2-01, resume guard BS-R2-03)
- **Implementation gaps:** 1 (carryover auto-loading BS-R2-02, blocked on 002 tasks T005-T009)
