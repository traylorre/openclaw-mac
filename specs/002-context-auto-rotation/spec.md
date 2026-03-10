# Feature Specification: Context Guardian Auto-Rotation

**Feature Branch**: `002-context-auto-rotation`
**Created**: 2026-03-07
**Status**: Draft
**Input**: User description: "Fully automate the context rotation cycle when the context guardian detects usage approaching the hard limit, with zero manual steps."

## Clarifications

### Session 2026-03-08

- Q: Does the Claude Code PostToolUse hook API support `tool_name`/`tool_input` in its input and `continue: false` in its output? (FR-001, FR-002, FR-010 — BLOCKING) → A: **YES — fully confirmed.** PostToolUse input includes `session_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`, `tool_name` (string, e.g. "Write"), `tool_input` (object with tool-specific args including `file_path`), `tool_response` (object with result), and `tool_use_id`. PostToolUse output supports `continue` (boolean, default true — if `false`, Claude stops processing entirely; takes precedence over all other fields), `stopReason` (string shown to user when stopped), `decision` ("block" to prompt Claude with reason), and `hookSpecificOutput.additionalContext`. **Note:** Feature 003 rejected PostToolUse for sentinel detection (R-003) due to per-call overhead, but that rejection does not apply here — 002 requires `continue: false` to halt the model mid-stream after CARRYOVER writes, which no other mechanism can achieve. Fast-path optimization (check `tool_name` before parsing `tool_input`) makes SC-005's 200ms target trivially achievable. FR-001, FR-002, FR-010 are RESOLVED — no design adaptation required.
- Q: Should 002's PostToolUse hook suppress auto-clear when 003's recovery marker (`.claude/recovery-marker.json`) is present? (FR-017 cross-feature integration) → A: **YES — full suppression.** 002's PostToolUse hook MUST check for the recovery marker before triggering the auto-clear cycle. If the marker exists, the hook suppresses entirely: no `continue: false`, no `/clear` scheduling. Recovery owns the /clear lifecycle during active recovery (003 FR-017). This prevents a CARRYOVER-triggered /clear from aborting 003's audit mid-flight.
- Q: Should FR-004 use a fixed 1-2 second delay or a smarter mechanism for /clear delivery after `continue: false`? → A: **Idle-detection polling.** Spawn a background process that polls the tmux pane (via `tmux capture-pane -p | tail -1`) for the Claude Code prompt indicator every 1 second with a 30-second timeout. No sentinel file needed — `continue: false` stops Claude immediately, so the only variable is how long the UI takes to return to the input prompt. This is simpler than 003's full watcher (no sentinel handoff) but more reliable than a blind fixed delay.
- Q: Should 002's SessionStart hook be a standalone script or merged into 003's hooks? → A: **Standalone `carryover-loader.sh`**, running in parallel with 003's hooks. Platform concatenates all hooks' `additionalContext`. 002's context is delimited with `--- CARRYOVER CONTEXT ---` / `--- END CARRYOVER CONTEXT ---` markers. This aligns with 003's R-005 decision which explicitly rejected the merged approach ("creates coupling between features, violates FR-050"). Each feature works independently; composition happens at the platform level.
- Q: What is the CARRYOVER file size limit and truncation strategy? → A: **80KB cap (~24K tokens, ~12% of 200K context window).** If the CARRYOVER file exceeds 80KB, tail-truncate (keep end of file — most recent task state and next-steps are at the bottom). This leaves ~88% of the context window for working context. The constraint is context budget, not a platform limit (003 R-002 found no documented `additionalContext` size limit). 003's recovery context (~2KB) is independent and additive.
- Q: Should 002 reuse 003's shared infrastructure or maintain its own? → A: **Extract shared utils into `hook-common.sh`** that both features source. Shared functions: `is_tmux()`, `project_root()`, `log_info()`/`log_warn()`/`log_error()`, `require_tool()`. Both 002 and 003 depend on the neutral shared library, not on each other. Requires refactoring 003's `recovery-common.sh` to split shared utils into `hook-common.sh` + recovery-specific code. This maintains symmetric independence — either feature can be uninstalled without breaking the other. Future features (004+) source `hook-common.sh` naturally.
- Q: How should concurrent sessions in the same project directory be handled? → A: **Accept the race.** "Most recent unconsumed" heuristic is good enough. Concurrent sessions are a rare edge case not worth the complexity of session-scoped filenames or subdirectories.
- Q: What is the cleanup policy for consumed `.loaded` files? → A: **Count-based: keep last 5 `.loaded` files, delete oldest.** Checked during `carryover-loader.sh` runs. Matches 003's retention pattern (FR-052).
- Q: How should empty/malformed/missing CARRYOVER files be handled? → A: **Inject a warning context.** If no unconsumed CARRYOVER file exists when the loader runs (model didn't write one, or file is empty <100 bytes), inject `additionalContext` warning the model that carryover was expected but missing, so it can ask the user for context. If the file exists but is empty, skip loading it and rename to `.loaded` (consumed) to prevent re-checking.
- Q: What is the observability/logging strategy? → A: **Log to 003's shared `.claude/recovery-logs/` directory.** Use `hook-common.sh` logging functions (`log_info`, `log_warn`, `log_error`). Carryover events (load, skip, truncate, cleanup) logged alongside recovery events in a shared location. Single place to look when debugging any hook behavior.
- Q: Should FR-022's "missing carryover" warning fire on every SessionStart or only when auto-rotation was initiated? → A: **Signal file.** PostToolUse hook writes `.claude/carryover-pending` when it fires `continue: false`. The SessionStart loader checks for this marker — if present, carryover was expected and warning is injected if no file found; if absent, this is a normal /clear and no warning. Marker is deleted after check. Same coordination pattern as 003's recovery marker.
- Q: Should the SessionStart hook also trigger on `startup` and `resume` events? → A: **Add `startup`, skip `resume`.** If a stale unconsumed CARRYOVER file exists from a crashed rotation, load it on fresh `claude` launch. `resume` already has existing context — loading carryover would duplicate or conflict.
- Q: What should the `stopReason` message content be? → A: **Single message covering both paths:** `"Context rotation: CARRYOVER saved. Type /clear to continue (auto-clear in progress if tmux detected)."` Always correct regardless of environment. In tmux, user sees it briefly before auto-clear fires; in non-tmux, it's the primary instruction.
- Q: What happens when the idle-detection poller fails (tmux pane closed, timeout)? → A: **Fallback file.** If `tmux capture-pane` fails or the 30-second timeout expires, the poller writes `.claude/carryover-clear-needed` and logs an error. On next `startup`, the loader detects this file and injects a "previous rotation incomplete — type /clear" reminder into `additionalContext`. File is deleted after the reminder is injected.
- Q: What error handling should the PostToolUse hook implement? → A: **Minimal: `require_tool jq` + exit codes.** Validate jq availability at entry (exit 2 with remediation if missing). Use exit code conventions: 0 = success, 1 = non-blocking error, 2 = blocking error. No signal handling — the hook runs <200ms with no multi-step state to persist, unlike 003's 10-30 second hooks where signals are a real risk.
- Q: What is the CARRYOVER file search scope? → A: **Active spec directory only** (`specs/<feature>/`). CARRYOVER files are written into the active spec directory by convention (e.g., `specs/003-compaction-recovery/CONTEXT-CARRYOVER-01.md`). No recursive project-wide search. Fast, predictable, no false matches from other spec directories.
- Q: What is explicitly out of scope for 002? → A: (1) Writing CARRYOVER content — model's responsibility; (2) Compaction detection and recovery — 003's responsibility; (3) Context guardian behavior / threshold tuning — existing system; (4) Modifying Claude Code platform internals.
- Q: What is the preamble content structure for FR-015? → A: `"--- CARRYOVER CONTEXT ---\nYou are resuming after a context rotation. The following is your previous session's carryover summary. Continue the task described below.\n\n<carryover file contents>\n--- END CARRYOVER CONTEXT ---"` — ~150 bytes overhead, fits within FR-018 delimiters, FR-019 size cap.
- Q: What error handling should the SessionStart `carryover-loader.sh` implement? → A: **Full pattern: `require_tool jq`, signal traps, exit codes.** The loader does multi-step I/O with state changes (rename to `.loaded`, delete old files, delete pending marker). A signal between rename and stdout output would cause data loss — carryover consumed but never loaded. Signal traps undo the rename before exiting. Matches 003's SessionStart hook pattern.
- Q: When multiple unconsumed CARRYOVER files exist, which is loaded? → A: **Highest sequence number (NN) wins.** Sort by the numeric suffix in `CONTEXT-CARRYOVER-NN.md`, not by filesystem modification time. Sequence numbers are deterministic and immune to timestamp quirks (copy, touch, rsync).

### Session 2026-03-09

- Q: How should CARRYOVER content be serialized into JSON `additionalContext` output without breaking on quotes, backslashes, and newlines? → A: **Use `jq` for all JSON output construction** (e.g., `jq -n --arg ctx "$content" '{hookSpecificOutput:{additionalContext:$ctx}}'`). Never use raw string interpolation (`printf`, `echo`) for JSON containing user/model-generated content. This applies to both `carryover-loader.sh` and the PostToolUse hook. The assumption that "carryover content can be safely injected without escaping issues" is removed — `jq` handles escaping automatically.
- Q: How should the loader resolve the active spec directory when the git branch doesn't map to a `specs/` subdirectory? → A: **Log and skip.** Derive spec directory from `git branch --show-current` → `specs/${branch_name}/`. If the directory doesn't exist, log a warning (`"No spec directory for branch '${branch_name}', skipping carryover load"`) and exit 0 with no `additionalContext`. No self-healing, no branch switching, no scanning other spec directories. The carryover file persists on disk and will be found when the user checks out the correct branch.
- Q: How should the double `/clear` race condition be prevented (user types `/clear` before poller sends it)? → A: **Atomic `mv` claim.** Before sending `/clear`, the poller attempts `mv carryover-pending carryover-pending.claimed` (atomic on POSIX). If `mv` succeeds, poller owns the clear and sends it; if `mv` fails (file gone), the user already typed `/clear` and the loader handled it — poller exits silently. Zero race window. The loader deletes `carryover-pending` normally; it never sees `.claimed` because the poller only renames it in the instant before sending `/clear`.
- Q: How should the idle-detection poller be spawned to survive hook exit and avoid corrupting hook stdout? → A: **Portable detachment with fd isolation:** `(nohup ./carryover-poller.sh </dev/null >/dev/null 2>&1 &)`. The outer `()` subshell makes the poller a grandchild (reparented to init on exit). `nohup` ignores SIGHUP. All fds redirected to `/dev/null` — poller logs via `hook-common.sh` to log file, never to stdout. Fully POSIX-portable (no `setsid` — not available on macOS).
- Q: When multiple signal files coexist on startup, what is the loader's processing order? → A: **Linear scan mirroring creation timeline:** (1) delete stale `.claimed` (FR-029), (2) check `carryover-clear-needed` — inject reminder and delete if present, (3) check `carryover-pending` — inject missing-carryover warning and delete if present and no CARRYOVER file found. Both reminders concatenated if both files exist (independently true conditions). FR-030 added.
- Q: How should scripts discover and source `hook-common.sh`? → A: **`source "$HOME/bin/hook-common.sh"`** — all scripts use `$HOME/bin/` as the canonical path. Symlink deploy: `~/dotfiles/scripts/bin/*` symlinked to `~/bin/`. Bash sources through symlinks transparently. `$HOME` used instead of `~` for POSIX compatibility. No `readlink` or self-location logic needed. FR-020 updated.
- Q: What exact filename pattern should the PostToolUse hook match for CARRYOVER detection? → A: **`/^CONTEXT-CARRYOVER-[0-9]{2}\.md$/`** — case-sensitive, fixed 2-digit sequence number, basename only (e.g., `CONTEXT-CARRYOVER-53.md`). Hook extracts basename from `tool_input.file_path` before matching. No path-level filtering at detection time. FR-001, FR-010 updated.
- Q: How should the poller handle `.claimed` file cleanup to prevent stale locks? → A: **EXIT trap + startup defense-in-depth.** The poller installs `trap 'rm -f .claude/carryover-pending.claimed' EXIT` at entry, which fires on all termination paths (success, failure, timeout, signals) except SIGKILL. For SIGKILL resilience, the startup loader also deletes any stale `.claimed` file it finds. FR-004 and FR-029 updated.
- Q: What pattern should the poller match to detect the Claude Code idle prompt in tmux? → A: **Three consecutive lines: separator (`^─{12,}`), prompt (`^❯`), separator (`^─{12,}`).** The `❯` (U+276F) and `─` (U+2500) are Unicode characters that won't appear in normal model output. The full pane must be scanned (not `tail -1`) because UI status elements (e.g., `⏵⏵ accept edits on`) may appear below the prompt. FR-004 updated accordingly.
- Q: What if the model writes the CARRYOVER file across multiple tool calls (Write then Edit)? → A: **Assumption: single Write call.** The CARRYOVER file is written in a single Write tool call. `continue: false` fires on the FIRST matching PostToolUse event — there is no second chance. The guardian's instructions to the model (out of scope for 002) must specify "write the complete carryover in one Write call." Document this as an assumption.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Zero-Touch Context Rotation (Priority: P1)

A developer is working in a long Claude Code session inside tmux. As the session progresses, context usage climbs toward the guardian's hard limit (70%). The guardian blocks tool calls and instructs the model to write a CONTEXT-CARRYOVER file. Once the model writes the carryover file, the system automatically stops Claude, clears the session, loads the carryover into the fresh session, and the model resumes work — all without the developer typing anything.

**Why this priority**: This is the core value proposition. Without it, the developer must manually type `/clear` after every context rotation, breaking flow and risking forgotten context.

**Independent Test**: Can be fully tested by running a Claude Code session in tmux, artificially setting context usage to 70%+, and observing that the full rotation cycle (carryover write → stop → /clear → carryover load → resume) happens without user intervention.

**Acceptance Scenarios**:

1. **Given** a Claude Code session running in tmux with context at 70%+, **When** the guardian denies a tool call and the model writes a CONTEXT-CARRYOVER file, **Then** the system automatically stops Claude processing, sends `/clear` to the tmux pane, and the fresh session loads the carryover contents as context.
2. **Given** the auto-rotation has completed and a fresh session has started, **When** the model receives the carryover context, **Then** the model understands what was being worked on and continues from where it left off without user prompting.
3. **Given** a CARRYOVER file was loaded into a fresh session, **When** the user later runs `/clear` manually, **Then** the already-consumed carryover is NOT loaded again.

---

### User Story 2 - Graceful Degradation Without tmux (Priority: P2)

A developer is working in Claude Code outside of tmux (e.g., plain terminal, Windows Terminal on WSL2). The context guardian fires and the model writes a CARRYOVER file. Since tmux is not available, the system cannot auto-send `/clear`. Instead, it stops Claude and displays a clear message telling the developer to type `/clear` to continue. When the developer types `/clear`, the carryover is automatically loaded.

**Why this priority**: Not all users run tmux. The system must degrade gracefully to a semi-automated workflow (one manual step: typing `/clear`) rather than failing silently.

**Independent Test**: Can be tested by running Claude Code outside tmux, triggering the guardian, and verifying that a clear message is shown and that `/clear` loads the carryover.

**Acceptance Scenarios**:

1. **Given** a Claude Code session NOT running in tmux with context at 70%+, **When** the model writes a CONTEXT-CARRYOVER file, **Then** the system stops Claude and displays a message instructing the user to type `/clear` to resume.
2. **Given** the user has been instructed to type `/clear`, **When** the user types `/clear`, **Then** the fresh session automatically loads the most recent carryover and the model resumes work.

---

### User Story 3 - Carryover Loading on Compaction Fallback (Priority: P3)

If auto-compaction occurs despite the guardian (e.g., a single large tool result pushes context past the compaction threshold), the system detects the compaction event and loads any existing carryover file to help the model recover context that may have been lost during compression.

**Why this priority**: This is a safety net for when the guardian's architectural limitation is hit (context jumping from <70% to >83% in a single tool result). It doesn't prevent compaction but mitigates its damage.

**Independent Test**: Can be tested by triggering compaction (if possible to simulate) and verifying that the SessionStart hook loads the carryover on the `compact` event.

**Acceptance Scenarios**:

1. **Given** a CARRYOVER file exists and auto-compaction occurs, **When** the session restarts after compaction, **Then** the carryover contents are loaded as additional context for the model.

---

### Edge Cases

- What happens when the model writes a CARRYOVER file but the tmux send-keys fails (e.g., pane was closed)? → Resolved: poller writes `.claude/carryover-clear-needed` on failure/timeout; startup loader detects and reminds user (FR-004).
- What happens when multiple CARRYOVER files exist from previous sessions? → Resolved: highest sequence number (NN) wins (FR-026). Only one loaded per cycle.
- What happens when the CARRYOVER file is empty or malformed? → Resolved: empty (<100 bytes) files skipped, renamed to `.loaded`, warning context injected (FR-022).
- What happens if the model never writes a CARRYOVER file after being denied? → Resolved: loader injects warning context telling model to ask user for context (FR-022).
- What happens if two Claude Code sessions are running in the same project directory simultaneously? → Accepted risk: "most recent unconsumed" heuristic may load wrong session's carryover. Concurrent sessions are rare; not worth session-scoping complexity.
- What happens if `/clear` fires before Claude has fully stopped processing? → Resolved: idle-detection polling (FR-004) ensures `/clear` is only sent after the prompt is visible.
- What happens if the CARRYOVER file is very large (>50KB)? → Resolved: 80KB cap with tail-truncation (FR-019). Keeps ~88% of context window for working context.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST detect when the model writes or edits a file whose basename matches `/^CONTEXT-CARRYOVER-[0-9]{2}\.md$/` (case-sensitive, fixed 2-digit sequence number, e.g. `CONTEXT-CARRYOVER-01.md` through `CONTEXT-CARRYOVER-99.md`) via a PostToolUse hook. The hook receives `tool_name` (e.g. "Write", "Edit") and `tool_input` (containing `file_path`) in its stdin JSON input. The hook MUST extract the basename from `file_path` before matching. *(API validated 2026-03-08; pattern confirmed 2026-03-09)*
- **FR-002**: Upon detecting a CARRYOVER file write, the system MUST return `{"continue": false, "stopReason": "Context rotation: CARRYOVER saved. Type /clear to continue (auto-clear in progress if tmux detected)."}` to stop Claude processing immediately. The `continue: false` field halts all model processing and takes precedence over other output fields. *(API validated 2026-03-08)*
- **FR-003**: Upon detecting a CARRYOVER file write in a tmux environment, the system MUST schedule a `/clear` command to be sent to the current tmux pane after a brief delay.
- **FR-004**: After `continue: false` stops Claude, the system MUST spawn a background process that polls the tmux pane for the Claude Code idle prompt pattern every 1 second. The idle prompt is detected by scanning `tmux capture-pane -p` output for three consecutive lines matching: (1) `^─{12,}` (separator line of box-drawing characters U+2500), (2) `^❯` followed by a space (prompt character U+276F), (3) `^─{12,}` (separator line). The full pane output MUST be scanned (not `tail -1`, as UI status elements may appear below the prompt). Once the prompt is detected, the poller MUST attempt an atomic `mv .claude/carryover-pending .claude/carryover-pending.claimed`. The poller MUST install `trap 'rm -f .claude/carryover-pending.claimed' EXIT` at entry to ensure `.claimed` is deleted on all termination paths (success, failure, timeout, signals — except SIGKILL). If `mv` succeeds, the poller sends `/clear` via `tmux send-keys` (the EXIT trap handles `.claimed` cleanup). If `mv` fails (file already deleted by loader), the poller exits silently — the user already typed `/clear`. Timeout: 30 seconds. If `tmux capture-pane` fails or the timeout expires, the poller MUST write `.claude/carryover-clear-needed` and log an error. The SessionStart loader MUST detect this file on `startup` and inject a reminder into `additionalContext`, then delete the file. *(Replaces fixed delay per 003 R-003 findings; prompt pattern confirmed 2026-03-09)*
- **FR-005**: Upon detecting a CARRYOVER file write outside a tmux environment, the system MUST display a message to the user instructing them to type `/clear`.
- **FR-006**: Upon session start after `/clear`, compaction, or startup, the system MUST derive the active spec directory from `git branch --show-current` → `specs/${branch_name}/`. If the directory exists, search for the most recent unconsumed CARRYOVER file there. If the directory does not exist (wrong branch, `main`, detached HEAD), log a warning and exit 0 — no carryover loaded, no branch switching, no fallback scanning of other spec directories.
- **FR-007**: The system MUST load the contents of the found CARRYOVER file as additional context for the model.
- **FR-008**: After loading a CARRYOVER file, the system MUST mark it as consumed so it is not loaded again on subsequent `/clear` or session restarts.
- **FR-009**: The consumed marker MUST be a rename (appending `.loaded` to the filename) to preserve the file for reference.
- **FR-010**: The PostToolUse hook MUST implement a fast-path exit: check `tool_name` field first (O(1) string compare against "Write"/"Edit"), and only extract the basename from `tool_input.file_path` and match against `/^CONTEXT-CARRYOVER-[0-9]{2}\.md$/` (case-sensitive) if the tool name matches. Non-matching tool calls MUST exit immediately with no output. *(API validated 2026-03-08; pattern confirmed 2026-03-09)*
- **FR-016**: The PostToolUse hook MUST check for the recovery marker (`.claude/recovery-marker.json`) before triggering the auto-clear cycle. If the marker exists, the hook MUST suppress entirely — no `continue: false`, no `/clear` scheduling. Recovery (feature 003) owns the /clear lifecycle during active recovery. *(Cross-feature: 003 FR-017)*
- **FR-017**: The SessionStart hook MUST be a standalone script (`carryover-loader.sh`) separate from 003's hooks. It MUST NOT be merged into 003's `recovery-loader.sh` or `recovery-detect.sh`. Composition happens via platform-level `additionalContext` concatenation. *(Aligned with 003 R-005)*
- **FR-018**: The CARRYOVER context injected via `additionalContext` MUST be delimited with `--- CARRYOVER CONTEXT ---` and `--- END CARRYOVER CONTEXT ---` markers so the model can distinguish it from 003's recovery context when both are present.
- **FR-019**: If the CARRYOVER file exceeds 80KB, the system MUST tail-truncate it (discard the beginning, keep the end) to fit within the 80KB cap. The truncated output MUST prepend a note: `[CARRYOVER truncated — showing last 80KB of <original_size>]`.
- **FR-020**: Shared hook utilities (`is_tmux`, `project_root`, logging, `require_tool`) MUST live in `hook-common.sh`, sourced by both 002's and 003's scripts via `source "$HOME/bin/hook-common.sh"`. All scripts are deployed to `~/dotfiles/scripts/bin/` and symlinked to `~/bin/` (FR-013). `$HOME` MUST be used instead of `~` for POSIX sourcing compatibility. 002 MUST NOT source 003-specific files directly. *(Requires 003 refactor: split `recovery-common.sh` into `hook-common.sh` + recovery-specific code)*
- **FR-021**: The `carryover-loader.sh` script MUST delete consumed `.loaded` files beyond the 5 most recent. Cleanup runs during each loader invocation, sorted by modification time, oldest deleted first.
- **FR-022**: The PostToolUse hook MUST write a signal file (`.claude/carryover-pending`) when it fires `continue: false`. The SessionStart loader MUST check for this marker: if present AND no unconsumed CARRYOVER file is found (or file is empty <100 bytes), inject `additionalContext` warning the model: `"CARRYOVER file was expected but not found or was empty. Ask the user for context about the previous task."` If the marker is absent, this is a normal /clear — no warning. The marker MUST be deleted after the check regardless of outcome. Empty CARRYOVER files MUST be renamed to `.loaded`.
- **FR-023**: All 002 hook scripts MUST log key events (carryover detected, loaded, skipped, truncated, cleanup, errors) to `.claude/recovery-logs/` using `hook-common.sh` logging functions. Shared log directory with 003.
- **FR-024**: The PostToolUse hook MUST validate `jq` availability at entry via `require_tool` from `hook-common.sh`. If missing, exit 2 with remediation message. Exit code conventions: 0 = success, 1 = non-blocking error, 2 = blocking error. No signal handling required (hook runs <200ms).
- **FR-025**: The `carryover-loader.sh` MUST validate `jq` at entry (exit 2 if missing), use exit code conventions (0/1/2), and install signal traps (SIGTERM, SIGINT, SIGHUP) that undo the `.loaded` rename before exiting. This prevents data loss if the process is killed between file rename and stdout output.
- **FR-026**: When multiple unconsumed CARRYOVER files exist, the loader MUST select the one with the highest sequence number (NN in `CONTEXT-CARRYOVER-NN.md`), not by filesystem modification time.
- **FR-027**: All hook scripts MUST construct JSON output using `jq` (e.g., `jq -n --arg ctx "$content" '{hookSpecificOutput:{additionalContext:$ctx}}'`). Raw string interpolation (`printf`, `echo`) MUST NOT be used for JSON containing model-generated content. This prevents broken JSON from quotes, backslashes, and newlines in CARRYOVER files.
- **FR-028**: The idle-detection poller MUST be spawned with portable full detachment: `(nohup ./carryover-poller.sh </dev/null >/dev/null 2>&1 &)`. The poller MUST NOT inherit the hook's stdout (would corrupt JSON output). All poller logging MUST go through `hook-common.sh` log functions to the log file. `setsid` MUST NOT be used (not available on macOS).
- **FR-029**: The `carryover-loader.sh` MUST delete any stale `.claude/carryover-pending.claimed` file on `startup` events as defense-in-depth against SIGKILL of a prior poller. This is a no-op if the file does not exist.
- **FR-030**: On `startup`, the `carryover-loader.sh` MUST process signal files in linear order mirroring their creation timeline: (1) delete stale `.claimed` (FR-029), (2) if `.claude/carryover-clear-needed` exists, inject a reminder into `additionalContext` ("previous rotation incomplete — type /clear") and delete the file, (3) if `.claude/carryover-pending` exists and no unconsumed CARRYOVER file is found, inject the missing-carryover warning (FR-022) and delete the marker. If both (2) and (3) fire, both messages MUST be concatenated into `additionalContext`. Each step is independent — the presence of one signal file does not suppress processing of another.
- **FR-011**: The SessionStart hook MUST trigger on `clear`, `compact`, and `startup` session start events. It MUST NOT trigger on `resume` (existing context would conflict with carryover injection).
- **FR-012**: The system MUST NOT modify the existing `context-guardian.sh` (PreToolUse) or `context-monitor.sh` (statusLine) scripts.
- **FR-013**: All new scripts MUST reside in `~/dotfiles/scripts/bin/` and be symlinked to `~/bin/`.
- **FR-014**: Hook definitions MUST be added to `~/dotfiles/claude/.claude/settings.json`.
- **FR-015**: The CARRYOVER context loaded into a new session MUST be wrapped in the following preamble: `"--- CARRYOVER CONTEXT ---\nYou are resuming after a context rotation. The following is your previous session's carryover summary. Continue the task described below.\n\n<carryover file contents>\n--- END CARRYOVER CONTEXT ---"` (~150 bytes overhead, within FR-018 delimiters and FR-019 size cap).

### Key Entities

- **CARRYOVER File**: A markdown file written by the model containing a summary of in-progress work, current task state, and any information needed to resume. Named `CONTEXT-CARRYOVER-NN.md` (where NN is a sequence number). Located in the project directory.
- **Consumed Marker**: A renamed CARRYOVER file with `.loaded` appended (e.g., `CONTEXT-CARRYOVER-01.md.loaded`), indicating it has been loaded into a session and should not be loaded again.

## Out of Scope

- **Writing CARRYOVER content** — the model decides what to include in the carryover file; 002 only detects, transports, and loads it.
- **Compaction detection and recovery** — owned by feature 003. 002 loads CARRYOVER on `compact` events as a fallback but does not detect, audit, or revert compaction damage.
- **Context guardian behavior / threshold tuning** — the existing `context-guardian.sh` (PreToolUse) and `context-monitor.sh` (statusLine) are untouched (FR-012).
- **Claude Code platform internals** — 002 operates entirely through the documented hooks API; no platform source modifications.

## Assumptions

- The user runs Claude Code inside tmux for the fully automated (zero-touch) experience. Non-tmux environments receive a degraded but functional workflow.
- The `$TMUX` environment variable is available inside hook execution to detect tmux presence.
- The `tmux send-keys` command is available on the system when `$TMUX` is set.
- CARRYOVER files are written to the active spec directory (`specs/<feature>/`). The search scope is limited to this directory, derived from the feature branch name or hook's `cwd`.
- Only one CARRYOVER file should be loaded per `/clear` cycle. If multiple unconsumed files exist, the one with the highest sequence number (NN) is loaded.
- The `jq` command-line tool is available on the system.
- The carryover file content is plain text/markdown. All JSON output MUST be constructed via `jq` to handle escaping automatically (FR-027).
- The CARRYOVER file is written by the model in a single Write tool call. `continue: false` fires on the first matching PostToolUse event — incomplete multi-call writes are not supported. The guardian's instructions (out of scope for 002) must enforce this.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: When running in tmux, the full context rotation cycle (guardian deny → carryover write → stop → /clear → carryover load → model resumes) completes with zero user interaction.
- **SC-002**: When running outside tmux, the rotation requires exactly one manual step (typing `/clear`), with a clear message guiding the user.
- **SC-003**: After rotation, the model demonstrates awareness of the previous task by referencing specific details from the carryover file in its first response.
- **SC-004**: Consumed carryover files are never loaded twice, even after multiple `/clear` cycles.
- **SC-005**: The PostToolUse hook adds less than 200ms of latency to Write/Edit tool calls that are not CARRYOVER files (fast path for non-matching files).
- **SC-006**: The SessionStart hook adds less than 500ms of latency to session startup when no carryover file exists.
