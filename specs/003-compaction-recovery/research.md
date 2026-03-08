# Research: Compaction Detection and Recovery

**Feature**: 003-compaction-recovery
**Date**: 2026-03-08

## R-001: PreCompact Hook Event Discovery

**Context**: The spec (FR-004) assumes "no pre-compaction hook exists" and
designs all interrupted task capture as post-hoc transcript parsing in the
SessionStart hook. Research into the hooks API revealed a `PreCompact` event.

**Finding**: The Claude Code hooks API lists `PreCompact` as an available hook
event. This event fires *before* context compaction occurs, meaning:

- The full transcript is still available (not yet compacted)
- The session context is still intact
- The model has not yet lost any context
- The hook can write files and perform I/O before compaction

**Decision**: Use PreCompact as the **primary path** for recovery marker
creation and interrupted task capture. Keep SessionStart(`compact`) transcript
parsing as a **fallback** if PreCompact didn't fire (version incompatibility,
hook failure, timeout).

**Rationale**: PreCompact closes the timing gap the spec was concerned about.
With PreCompact, the marker and interrupted task are captured *before*
compaction — no post-hoc transcript reconstruction needed. The SessionStart
hook becomes a verification and injection step rather than the primary capture
mechanism.

**Alternatives considered**:

- *Transcript-only approach* (spec's original design): Works but has a timing
  gap — between compaction and SessionStart, the model may operate on tainted
  context. Retained as fallback.
- *PreCompact-only approach*: Fragile — if PreCompact doesn't fire (new
  platform version, hook error), all capture is lost. Rejected as sole path.

**Risk**: PreCompact may not be available in all Claude Code versions or may
have different input/output semantics than SessionStart. The fallback ensures
robustness. Implementation must validate PreCompact availability during
health-check (FR-075).

## R-002: additionalContext Size Limits

**Context**: FR-030 and FR-073 reference size limits for the `additionalContext`
field in hook output.

**Finding**: No documented platform limit was found in the hooks API
documentation. The API confirms that multiple hooks' `additionalContext` values
are concatenated (not overwritten).

**Decision**: Assume a conservative 100KB ceiling per FR-073. Implement
proactive truncation per FR-030 priority rules: interrupted task context takes
priority over CARRYOVER. The recovery preamble itself is capped at 2KB per
FR-083.

**Rationale**: Without a documented limit, a conservative assumption prevents
silent truncation. 100KB is generous for the expected payload (2KB preamble +
~5KB interrupted task + ~20KB CARRYOVER = ~27KB typical). The truncation logic
is insurance, not expected to fire in normal operation.

**Alternatives considered**:

- *No limit assumed*: Risky — platform may silently truncate, corrupting the
  injected context. Rejected.
- *Sentinel-based detection* (FR-073): Append a sentinel string and check for
  it in the session. Adds complexity for minimal benefit. Deferred to P3.

## R-003: Tmux /clear Sequencing

**Context**: FR-006, FR-007, and FR-020 require that /clear is sent only after
the audit and reverts complete, and only when the model is idle.

**Finding**: The model cannot invoke `/clear` itself — it is a UI command
processed by Claude Code's input handler. In tmux, `tmux send-keys` can
deliver `/clear` to the pane's input buffer, but timing matters.

**Decision**: Use a **background watcher process** (`recovery-watcher.sh`)
spawned by the SessionStart(`compact`) hook:

1. Watcher polls for a sentinel file (`.claude/recovery-audit-complete`)
2. Model creates the sentinel (via Bash tool) after completing all reverts
3. Watcher detects sentinel, polls tmux pane for idle state (prompt visible)
4. Watcher sends `/clear` via `tmux send-keys`
5. Watcher cleans up sentinel and exits

**Prompt detection method**: Capture the last line of the tmux pane via
`tmux capture-pane -p -t "$TMUX_PANE" | tail -1` and check for the Claude Code
input indicator pattern. Poll every 2 seconds with a 5-minute timeout.

**Rationale**: This decouples audit completion (model-driven) from /clear
delivery (script-driven), respecting FR-007's sequencing requirement. The
sentinel file is the handoff mechanism — simple, observable, and debuggable.

**Alternatives considered**:

- *Model sends /clear via Bash*: The model could run
  `tmux send-keys "/clear" Enter`, but this would fire during the model's
  response generation, potentially interleaving with output. Rejected.
- *PostToolUse hook*: Could detect the sentinel write. But PostToolUse fires
  per tool call and adds overhead to every tool call in the session. Rejected.
- *Fixed delay*: Wait N seconds after SessionStart. Unreliable — audit
  duration varies. Rejected.

**Risk**: Prompt detection pattern may vary across Claude Code versions. The
health-check should verify the pattern works.

## R-004: Transcript JSONL Structure

**Context**: FR-004, FR-019, FR-025, FR-064, FR-065 require parsing the
session transcript to extract the interrupted task.

**Finding**: The transcript is a JSONL file (one JSON object per line) stored at
`~/.claude/projects/<project-path>/<session-id>.jsonl`. Each entry has:

- `type`: "user" | "assistant" | "system" | "file-history-snapshot"
- `message.role`: "user" | "assistant"
- `message.content`: string or array of content blocks
- `timestamp`: ISO 8601
- `uuid`: unique message ID
- `parentUuid`: threading reference
- `isSidechain`: boolean (subagent indicator)

User messages have `type: "user"` with `message.content` as a string.
Assistant messages have `type: "assistant"` with `message.content` as an
array of content blocks (text, tool_use, tool_result).

Compaction boundaries are identified by a user message containing "continued
from a previous conversation" — this is the compacted summary injected by the
platform.

**Decision**: Parse from the end of the file (last 1MB per FR-065). Filter for
entries where `type == "user"` and `isSidechain != true`. Extract `message.content`
(or `message.content` string for user messages). Skip entries matching trivial
patterns per FR-025.

**Rationale**: Reverse scanning from EOF is efficient for large transcripts and
avoids reading the entire file. The `isSidechain` filter excludes subagent
messages per FR-076 (subagent messages are in their own context).

## R-005: Feature 002 Integration Architecture

**Context**: Feature 002 (context-auto-rotation) is specified but not
implemented. Feature 003 is its companion and must integrate with 002's planned
CARRYOVER loading mechanism.

**Finding**: Feature 002 requires:

- SessionStart(`clear`): Load CARRYOVER file into additionalContext
- SessionStart(`startup`/`resume`): Load CARRYOVER on session start
- PostToolUse hook: Detect CARRYOVER file writes for auto-clear trigger

Feature 003 extends the SessionStart(`clear`) hook to also load interrupted
task context when a recovery marker is present.

**Decision**: Implement `recovery-loader.sh` as a **standalone script** that
handles recovery-specific context loading on `/clear`. Feature 002's CARRYOVER
loading will be a separate hook that runs in parallel. The platform concatenates
all hooks' `additionalContext`, so they compose naturally.

The recovery-loader.sh script will:

1. Check for recovery marker — if absent, exit 0 (no recovery in progress)
2. Load interrupted task context from temp file
3. Build recovery preamble (FR-029, FR-083)
4. Output `additionalContext` with recovery context
5. Consume marker and clean up temp files

Feature 002's CARRYOVER loader will independently inject CARRYOVER context.
The two contexts concatenate in the fresh session.

**Rationale**: Separate hooks maintain clean separation of concerns. Feature
003 works correctly without 002 (FR-050). When 002 is implemented, both hooks
fire in parallel and their contexts are concatenated by the platform.

**Alternatives considered**:

- *Single combined script*: Handles both CARRYOVER and recovery. Creates
  coupling between features. Rejected — violates FR-050 requirement that 003
  degrades gracefully without 002.
- *Recovery-loader reads CARRYOVER itself*: Duplicates 002's logic. Rejected.

## R-006: Batch Mode for compaction-audit

**Context**: FR-003 and FR-035 require batch mode (auto-revert without
individual confirmation) when the audit is invoked by the recovery workflow.

**Finding**: The existing `compaction-audit.md` is a slash command (model
prompt) that instructs the model to:

1. Find the transcript JSONL file
2. Detect compaction boundaries
3. Identify tainted edits
4. Present a report
5. Ask for confirmation before reverting

**Decision**: Extend `compaction-audit.md` to recognize a `--batch` argument.
When `--batch` is present:

- Skip individual confirmation prompts
- Auto-approve all reverts
- Stash uncommitted changes before reverting (FR-037)
- Present the full report after all reverts complete
- Write the audit-complete sentinel file (`.claude/recovery-audit-complete`)
  for the watcher to detect

The recovery context (injected by `recovery-detect.sh`) will instruct the
model: "Run `/compaction-audit --batch` immediately. Do not perform any other
work until the audit is complete."

**Rationale**: Extending the existing command preserves FR-003 (no
reimplementation) while adding the batch capability needed for SC-004 (zero
manual steps in tmux). The `--batch` flag is a controlled extension that
doesn't change interactive behavior.

**Alternatives considered**:

- *Separate batch command*: Creates duplication. Rejected.
- *Context-only instruction*: Tell model to "auto-approve all reverts" without
  a flag. The audit's own instructions say "ask for confirmation," creating
  conflicting instructions. Rejected — explicit flag resolves the conflict.

## R-007: Signal Handling in Hook Scripts

**Context**: FR-062 requires hook scripts to handle SIGTERM, SIGINT, SIGHUP
gracefully and persist state before exiting.

**Finding**: Bash `trap` command is the standard mechanism. The priority order
for the recovery hook is:

1. Write/update the recovery marker (most critical — enables next session
   to detect interrupted recovery)
2. Capture interrupted task (second priority)
3. Clean up temp files (lowest priority)

The platform enforces a 600s default timeout for hooks. If the hook exceeds
this, it is killed with SIGTERM.

**Decision**: Install trap handlers at script entry:

```bash
trap 'persist_recovery_state; exit 130' INT
trap 'persist_recovery_state; exit 143' TERM
trap 'persist_recovery_state; exit 129' HUP
```

The `persist_recovery_state` function writes the current stage to the marker
file. The marker's `stage` field records how far the hook got, enabling the
next session to resume or report the interrupted state.

**Rationale**: Writing the marker first (FR-070) ensures that even if the hook
is killed during transcript parsing, the next session knows compaction occurred
and recovery was attempted.

## R-008: Recovery Marker Staleness Detection

**Context**: FR-023 requires detecting stale markers from crashed recoveries.

**Finding**: The marker contains `session_id` and `timestamp`. A marker is
stale if:

- Its `session_id` does not match the current session's ID, OR
- Its `timestamp` is older than 24 hours

**Decision**: On compaction detection, if a marker already exists:

1. Compare `session_id` — if same session, treat as re-entrant (FR-016),
   skip new detection
2. If different session, check age — if >24h, treat as stale, clean up,
   proceed with fresh recovery
3. If different session but <24h, warn developer (recent crash or concurrent
   session), clean up, proceed with fresh recovery

**Rationale**: Session ID comparison is the primary staleness signal.
The 24-hour threshold is a safety net for cases where session IDs are
recycled or unavailable. Conservative cleanup prevents permanent recovery
blocking.
