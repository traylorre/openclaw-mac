# Feature Specification: Compaction Detection and Recovery

**Feature Branch**: `003-compaction-recovery`
**Created**: 2026-03-07
**Status**: Draft
**Input**: User description: "If auto-compaction occurs despite the context guardian's best efforts, detect it immediately, run the compaction-audit to identify tainted edits, rollback, /clear, and resume the interrupted work."
**Companion to**: `002-context-auto-rotation`

## Clarifications

### Session 2026-03-08

- Q: Does the Claude Code hook API support `additionalContext` in SessionStart hook output and `transcript_path` in SessionStart hook input? (FR-031 BLOCKING) → A: **YES — fully confirmed.** SessionStart input includes `session_id`, `transcript_path`, `cwd`, `source` (matchers: `startup`, `resume`, `clear`, `compact`), `model`. SessionStart output supports `hookSpecificOutput.additionalContext` (string injected into model context). Multiple hooks' `additionalContext` values are concatenated. Hooks run in parallel with 600s default timeout. Environment (PATH, HOME, TMUX) is inherited. `CLAUDE_ENV_FILE` available for persisting env vars to subsequent Bash commands. FR-031 is RESOLVED — no design adaptation required.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Automatic Compaction Detection and Audit (Priority: P1)

A developer is working in a long Claude Code session. Despite the context guardian blocking at 70%, a single large tool result pushes context past the compaction threshold and auto-compaction fires. The system immediately detects that compaction occurred, warns the developer that context integrity has been compromised, and automatically invokes the compaction-audit to identify which edits were made under tainted (post-compaction) context. The audit produces a report and revert plan so the developer can restore the codebase to a known-good state.

**Why this priority**: Compaction is the single worst failure mode — any work done after compaction cannot be trusted. Detecting it instantly and auditing the damage is the most critical recovery step. Without this, the developer may unknowingly build on tainted edits.

**Independent Test**: Can be tested by artificially triggering compaction (or simulating the SessionStart `compact` event) and verifying that the compaction-audit command is automatically invoked and produces a report.

**Acceptance Scenarios**:

1. **Given** a Claude Code session where auto-compaction has just occurred, **When** the session restarts after compaction, **Then** the system detects the compaction event and injects context instructing the model to immediately run the compaction-audit command.
2. **Given** the compaction-audit has been invoked, **When** the audit identifies tainted file edits, **Then** the model presents a revert plan and executes reverts. In the automated tmux path, the model performs reverts without individual confirmation (batch mode). In the manual path, the existing interactive confirmation workflow applies.
3. **Given** the compaction-audit finds no tainted edits (compaction occurred before any post-compaction work), **Then** the system proceeds directly to the /clear and resume workflow.
4. **Given** the recovery workflow has started, **When** the developer decides to abort recovery (e.g., compaction was intentional or the developer wants manual control), **Then** the developer can cancel the workflow, and the system cleans up the recovery state marker without triggering /clear.

---

### User Story 2 - Automated /clear and Resume After Recovery (Priority: P2)

After the compaction-audit completes and any tainted edits have been reverted, the system automatically triggers /clear to start a fresh session. The fresh session loads the most recent CARRYOVER file (from feature 002) along with additional context about what task was being performed when compaction occurred, so the model can resume the interrupted work seamlessly.

**Why this priority**: Detection and audit (P1) are useless if the developer must then manually piece together where they were. This story closes the loop by resuming the interrupted workflow automatically.

**Independent Test**: Can be tested by simulating a post-audit state (carryover file exists, interrupted task context saved), triggering /clear, and verifying the model receives both the carryover and the interrupted task context.

**Acceptance Scenarios**:

1. **Given** the compaction-audit has completed and reverts (if any) are done, **When** running in tmux, **Then** the system automatically sends `/clear` to the tmux pane.
2. **Given** /clear has fired after compaction recovery, **When** the fresh session starts, **Then** the model receives the CARRYOVER contents AND a description of the interrupted task AND a summary of reverted vs preserved edits, and resumes that task by first verifying current file state.
3. **Given** the compaction-audit has completed, **When** running outside tmux, **Then** the system displays a clear message instructing the developer to type `/clear` to complete recovery.
4. **Given** recovery completed unattended in tmux, **When** the developer returns, **Then** a persistent recovery log file exists documenting all recovery actions taken, and the fresh session's context references this log.

---

### User Story 3 - Interrupted Task Capture (Priority: P2)

Before or during the compaction event, the system captures what the model was working on — the most recent user prompt or active task — so that after recovery and /clear, the model knows not just the general CARRYOVER state but specifically what operation was interrupted and needs to be re-executed.

**Why this priority**: The CARRYOVER file captures general session state, but the specific command or task that was actively running when compaction hit is not in the CARRYOVER (which was written earlier, at the 70% guardian threshold). This context is essential for seamless resumption.

**Independent Test**: Can be tested by checking that after compaction recovery and /clear, the model's first response references the specific interrupted task, not just general carryover state.

**Acceptance Scenarios**:

1. **Given** a session where the model was executing a multi-step task, **When** compaction occurs, **Then** the system captures the most recent user prompt or task description from the session transcript.
2. **Given** the interrupted task context has been captured, **When** it is loaded into the fresh post-/clear session, **Then** the model's first response acknowledges both the carryover state and the specific interrupted task, and resumes that task.
3. **Given** the last user message before compaction was a trivial confirmation (e.g., "yes"), **When** interrupted task capture runs, **Then** the system scans backwards to find the most recent substantive task description, and that description is used as the interrupted task context.
4. **Given** the transcript file is unavailable or unreadable, **When** interrupted task capture runs, **Then** the system proceeds with recovery using only CARRYOVER context and displays a warning that the interrupted task could not be captured.

---

### Edge Cases

- What happens if compaction occurs before the model has written any CARRYOVER file? The system should still detect compaction and run the audit, but the resume step will lack carryover context. The interrupted task capture becomes the sole recovery context.
- What happens if compaction occurs multiple times in a single session (nested compaction)? The audit handles this (it detects all compaction boundaries), and recovery should proceed based on the last compaction event.
- What happens if the compaction-audit itself consumes significant context in the post-compaction session? The audit should complete quickly, and /clear follows immediately, so this is a brief transient state.
- What happens if the tmux send-keys for `/clear` fires before the audit is complete? The /clear must be scheduled only AFTER the audit and reverts are done, not immediately on compaction detection.
- What happens if the session transcript file is not accessible from the hook? The hook receives `transcript_path` in its input JSON, which provides the path.
- What happens if the interrupted task was a subagent operation? The captured task context should include the subagent's original prompt if available.
- What happens if the recovery state marker is stale from a previously crashed recovery (e.g., machine rebooted mid-recovery)? The marker MUST include a session identifier or timestamp so stale markers can be detected and cleaned up rather than blocking all future sessions.
- What happens if the CARRYOVER auto-clear mechanism (from feature 002) fires while compaction recovery is in progress? The CARRYOVER-triggered /clear must be suppressed — recovery owns the /clear lifecycle during active recovery.
- What happens if tmux send-keys delivers `/clear` while the model is mid-response? The `/clear` may be dropped or interleaved with output. The system must wait for the model to finish its current response before sending `/clear`.
- What happens if the model begins executing a new task (using tainted context) in the window between compaction occurring and the audit starting? The injected context must instruct the model to halt all work and run the audit before doing anything else.
- What happens if the transcript JSONL file is being appended to while the hook reads it for interrupted task capture? The hook must handle incomplete trailing lines gracefully rather than failing on malformed JSON.
- What happens if a file edit is partially applied (e.g., the model was mid-write) when compaction fires? The audit must still detect and report the partial edit as tainted, and the recovery workflow must not assume files are in a consistent state.
- What happens if the model ignores the "halt all work" instruction (FR-018) and makes additional tainted edits before running the audit? The audit still catches them (they are post-compaction), but the recovery should warn the developer that the model did not comply, since those edits were not just tainted-by-compaction but actively produced against instructions.
- What happens if the last user message before compaction is trivial (e.g., "yes", "continue", "ok", a single-word confirmation)? A trivial prompt provides no useful task context. The system must scan backwards through prior user messages for a substantive task description.
- What happens if the user has multiple Claude Code sessions open in the same directory? The recovery state marker could be created by one session and consumed by another, causing cross-session interference. The marker must be scoped by session identifier.
- What happens if the tmux pane is closed or the tmux session is detached during recovery? The system must detect pane unavailability and fall back to the non-tmux manual instruction path rather than failing silently or hanging.
- What happens if required command-line tools (jq, git) are not available in the hook execution environment? The system should detect this early and display clear error messages with remediation steps.
- What happens if CARRYOVER context and interrupted task context together exceed a reasonable size for injection? The interrupted task context (more immediately actionable) should take priority, with CARRYOVER truncated if necessary.
- What happens if the `transcript_path` field is missing from the SessionStart hook input, or the file at that path is unreadable? Recovery must proceed without interrupted task context, using only CARRYOVER (if available), and log a warning.
- What happens if the hook output format for SessionStart does not support `additionalContext` as assumed? The entire injection mechanism for both features 002 and 003 depends on this — it must be validated against the actual Claude Code hook API before implementation.
- What happens if the developer wants to abort recovery (e.g., compaction was intentional, or the developer prefers manual control)? The system must allow aborting at any stage and clean up state without side effects.
- What happens if the recovery workflow fails midway (audit crashes, a revert fails, script error)? Partial reverts must not be lost, and the system must leave enough state for the developer to diagnose and complete recovery manually.
- What happens if the model does not begin the compaction-audit within a reasonable time after context injection? In tmux, the system should use send-keys as a fallback. Outside tmux, the instructions are already visible.
- What happens if the compaction-audit is invoked in batch mode (auto-revert) and a revert fails (e.g., file was modified externally between compaction and audit)? The system must report the failed revert, continue with remaining reverts, and flag the failed file for manual attention.
- What happens if tainted edits were made via the Bash tool (e.g., `echo "..." > file`, `sed -i`, `tee`) rather than Edit/Write? The audit must detect these as tainted too — the compaction-audit already checks for Bash tool file modifications, but the recovery workflow must not assume only Edit/Write edits exist.
- What happens if the git working tree has uncommitted changes (dirty state) when recovery begins? Reverts via `git checkout` could conflict with or overwrite uncommitted work. The system must check for dirty state and warn before reverting.
- What happens if the developer wants to keep some post-compaction edits (e.g., the model happened to make a correct edit despite tainted context)? The system must allow selective revert — the developer can choose which tainted edits to revert and which to keep. Batch mode should still present the full list for post-hoc review.
- What happens after reverts complete — how does the developer verify the codebase is in a known-good state? The system must provide a verification step (e.g., the audit report includes a `git diff` summary and the last known-clean commit hash).
- What happens if the compaction-audit produces a false positive — marks a clean edit (made before compaction) as tainted? The developer must be able to review and override individual revert decisions, even after batch mode completes.
- What happens if a file marked as tainted was also modified externally (by another process, IDE auto-save, or manual edit) between compaction and the audit? The git-based revert may clobber the external change. The system must detect this conflict (file modified since last Claude edit) and flag it.
- What happens if the revert target for a Write tool call is not recoverable (file was created by the tainted Write, with no prior version in git)? The revert should delete the file rather than trying to restore a non-existent prior version.
- What happens if git is in a detached HEAD state when recovery runs? Some revert strategies (e.g., `git checkout <commit> -- <file>`) still work, but others may not. The system must handle detached HEAD gracefully.
- What happens if the developer stepped away and recovery completes unattended (in tmux)? The developer returns to a fresh session with no visible history of what happened. The system must leave a persistent artifact (e.g., a recovery log file) so the developer can see what was recovered.
- What does the post-recovery model know about partial progress? If the interrupted task was 60% done (some edits clean, some tainted), the model should know which steps were completed successfully (pre-compaction) vs which need to be redone.
- What if the interrupted task description alone is insufficient for resumption — the model also needs to know which files were already correctly modified and which were reverted? The recovery context should include a summary of reverted vs preserved edits.
- What if the captured interrupted task context contains text that resembles system instructions or prompt injection (e.g., the user was asking the model to "ignore previous instructions")? The injected context must be clearly delimited so the model treats it as data (a quoted user prompt), not as new system instructions.
- What if one of the tainted files IS a hook configuration file (e.g., `settings.json`) or the compaction-audit command itself? Reverting these is critical — tainted infrastructure means the recovery system itself is compromised. But reverting hook config mid-recovery could change hook behavior during the current session.
- What if one of the tainted files is CLAUDE.md or a constitution file? These affect model behavior in the fresh session. Reverting them is essential but must happen before /clear so the fresh session loads clean governance files.
- What if git pre-commit or pre-push hooks fire during reverts and block the revert operation (e.g., a markdown lint hook rejects a reverted file)? Recovery reverts must not be blocked by git hooks.
- What if feature 002 is partially implemented or has a bug — CARRYOVER loading fails in the fresh session? The recovery workflow must not fail entirely if CARRYOVER loading is broken; interrupted task context alone should be sufficient for basic resumption.
- What if the developer wants to test the recovery workflow without actually triggering compaction? The system should support a dry-run or simulation mode for verifying that recovery scripts and hooks are correctly configured.
- What happens to old recovery log files over time? They accumulate in the project directory. The system should have a cleanup policy or at minimum not create logs that grow unboundedly.
- What if the recovery workflow itself consumes significant context in the post-compaction session (audit report + revert operations + progress output)? The workflow must be context-efficient — it operates in a session that already lost context to compaction, so every token matters.
- What happens to the interrupted task context temp file if /clear never fires (developer aborts, closes terminal, system crashes)? Stale temp files must be cleaned up automatically on the next session start.
- What if the automatic stash (in batch mode) fails because git cannot stash (e.g., no commits exist, or conflicts)? The system must warn and proceed with reverts only for files that won't conflict with uncommitted changes, skipping conflicting files.
- What if disk space is exhausted during recovery — the system cannot write the recovery state marker, log, or interrupted task temp file? Recovery should not fail silently; it must fall back to in-memory/conversation tracking.
- What if tainted edits target symbolic links — should the revert operate on the symlink itself or the resolved target? The revert must resolve the symlink and operate on the target, but the report should show both paths.
- What if the recovery state marker or temp files have restrictive permissions from a prior session run as a different user? The system must detect and warn about permission issues rather than silently failing.
- What if the git index is locked (`index.lock` exists) when recovery tries to perform reverts? The system must detect this and avoid hanging on git operations.
- What if tainted edits were made inside a git submodule? The revert must target the submodule's own git history, not the parent repo.
- What if a git merge or rebase is in progress when compaction occurs? Automatic reverts could conflict with the in-progress operation.
- What if the repository is a shallow clone with insufficient history for file-level reverts? The target commit may not exist locally.
- What if the recovery hook script receives SIGTERM or SIGINT mid-execution (e.g., user hits Ctrl+C, system shutdown)? Partial state must be persisted so the next session can diagnose what happened.
- What if the terminal is disconnected (SSH drops, tmux server crashes) during recovery? The recovery must be resumable from the point of interruption.
- What if the hook is killed by the platform (hook timeout enforcement) before completing transcript parsing? The hook must prioritize writing the recovery marker before parsing the transcript.
- What if the transcript format changes between Claude Code versions (field names or structure differ)? The parser must not crash on unrecognized fields.
- What if transcript entries contain very large tool results (multi-megabyte file reads) that slow down scanning for the last user message? The parser must bound its scan window.
- What if the transcript contains entries from subagent invocations that interleave with the main session? The parser must filter for top-level user messages only.
- What if a single file was edited multiple times post-compaction (e.g., three successive Edit calls)? The revert must target the pre-compaction state, not an intermediate tainted version.
- What if a tainted edit renamed or moved a file? The revert must restore the original path and remove the new-path copy.
- What if a tainted edit changed a file's type (e.g., deleted a file and created a directory with the same name)? The revert must restore the original file type.
- What if there are more than 100 tainted edits? The conversation-based output would consume the entire remaining context budget. The system must switch to summarized output.
- What if the recovery hook exceeds a platform-enforced execution timeout? The hook must complete its most critical work (writing the marker) within the first few seconds.
- What if the `additionalContext` field has a platform-imposed size limit that is smaller than the combined CARRYOVER + interrupted task context? The system must truncate to fit.
- What if hook scripts execute in a restricted environment where HOME, PATH, or TMUX are not inherited? The scripts must validate their environment before proceeding.
- What if the project is in a Docker container with a read-only filesystem layer? The system must fall back to stdout-only reporting.
- What if the dry-run mode (FR-051) exercises different code paths than the real recovery, giving false confidence? The dry-run must share code paths with real recovery.
- What if the developer upgrades Claude Code and the hook configuration becomes stale? A health-check command should catch this.
- What if the recovery workflow is interrupted and resumes, but the transcript file has been rotated or deleted between the interruption and resumption? The resumed recovery must proceed without the transcript.
- What if a subagent is running when compaction fires? The subagent operates in its own context, but its file edits land in the same working directory. The audit must detect subagent-originated edits as tainted if they occurred post-compaction.
- What if another user-defined SessionStart hook runs alongside the recovery hook and both attempt to inject `additionalContext`? The platform may only accept one value, causing one to be silently dropped.
- What if the developer has customized the compaction-audit command (added steps, changed output format) since recovery was configured? The recovery workflow must not assume a specific audit output format.
- What if the recovery hook and a PreToolUse hook conflict — e.g., the PreToolUse hook blocks the audit's tool calls? Recovery-related tool calls must not be blocked by other hooks.
- What if the recovery log is machine-parsed by external tooling (CI, monitoring) and the format changes? The log should have a stable, versioned structure.
- What if the developer wants a desktop or terminal notification when compaction recovery completes (especially for unattended tmux sessions)? The system should support a notification hook point.
- What if the interrupted task description is ambiguous without the surrounding conversation context (e.g., "fix the bug in the auth module" — which bug?)? The recovery context should include enough surrounding messages to disambiguate.
- What if the recovery preamble (FR-029) itself consumes significant context in the fresh session, leaving less room for the model's actual work? The preamble must be concise.
- What if the model misinterprets the recovery context and starts working on the wrong task? The preamble should instruct the model to confirm its understanding before proceeding.
- What if tainted edits occurred to files outside the git repository (e.g., files in `/tmp`, `~/.config`, or other absolute paths)? Git-based reverts cannot handle these; the system needs a fallback.
- What if the project is not a git repository at all? The audit can still identify tainted edits from the transcript, but all revert mechanisms that depend on git history are unavailable.
- What if the developer wants to see aggregate statistics across multiple recovery events (e.g., "compaction happened 5 times this week, averaging 12 tainted edits")? The recovery logs should support aggregation.
- What if the recovery context validation (verifying that injected context is well-formed and complete) fails? The system should have a fallback that injects minimal context rather than injecting nothing.
- What if file paths in tainted edits contain unicode characters, spaces, or shell-special characters (e.g., `$`, backticks, newlines)? The revert commands and log entries must handle these without corruption or injection.
- What if the interrupted task description contains credentials, API keys, or other secrets the developer typed into the prompt? The recovery log and injected context would persist these secrets to disk and into the fresh session.
- What if the recovery marker or log file is tampered with by a malicious process between compaction and the next session start? The system could be tricked into skipping recovery or injecting attacker-controlled context.
- What if multiple failure modes compound — e.g., no git, no transcript, no CARRYOVER, and read-only filesystem? What is the absolute minimum viable recovery?
- What if the developer was in the middle of a multi-step slash command (e.g., `/speckit.plan`) when compaction fired? The interrupted task capture should identify the slash command, not just the raw user prompt.
- What if the developer has staged but uncommitted changes (a partial commit in progress) when recovery runs? The stash-and-revert flow must preserve the staged/unstaged distinction.
- What if an IDE (VS Code, Cursor) has unsaved buffers for files that recovery wants to revert? The IDE may re-save its buffer after the revert, undoing the recovery.
- What if the recovery log contains diffs or file content snippets that include sensitive data? The log should avoid embedding full file contents.

## Requirements *(mandatory)*

### FR Priority Classification

FRs are classified into tiers to guide implementation phasing:

- **P1-Core** (implement first — the feature doesn't work without these):
  FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, FR-012, FR-013, FR-014, FR-015, FR-018, FR-021, FR-029, FR-031, FR-033, FR-035, FR-043, FR-098

- **P2-Robustness** (implement second — race conditions, blind spots, correctness):
  FR-016, FR-017, FR-019, FR-020, FR-022, FR-023, FR-024, FR-025, FR-026, FR-027, FR-028, FR-030, FR-032, FR-034, FR-036, FR-037, FR-039, FR-040, FR-041, FR-042, FR-044, FR-045, FR-046, FR-047, FR-048, FR-049, FR-050, FR-053, FR-054, FR-055, FR-066, FR-088, FR-091

- **P3-Hardening** (implement third — edge cases, scale, polish):
  FR-038, FR-052, FR-056, FR-057, FR-058, FR-059, FR-061, FR-062, FR-063, FR-064, FR-065, FR-067, FR-068, FR-069, FR-070, FR-071, FR-072, FR-073, FR-074, FR-075, FR-076, FR-077, FR-078, FR-079, FR-080, FR-082, FR-083, FR-084, FR-089, FR-090, FR-092, FR-093, FR-094, FR-095, FR-096, FR-097, FR-099, FR-100

- **P4-YAGNI** (defer or remove — unlikely scenarios for this project):
  FR-060, FR-081, FR-085, FR-086, FR-087

### Functional Requirements

- **FR-001**: System MUST detect compaction events via a SessionStart hook with matcher `compact`.
- **FR-002**: Upon detecting compaction, the system MUST inject context into the session instructing the model to immediately run the `/compaction-audit` slash command. This is the primary trigger mechanism. In tmux, the system MAY additionally send the command via tmux send-keys as a backup if the model does not act on the injected context within a reasonable window.
- **FR-003**: The system MUST NOT re-implement the compaction-audit logic — it invokes the existing `.claude/commands/compaction-audit.md` command. However, the recovery workflow MAY invoke the audit in a batch mode (auto-revert without individual confirmation) to enable zero-manual-step recovery in tmux. If batch mode is used, the audit report MUST still be presented to the developer for review after reverts complete.
- **FR-004**: The system MUST capture the most recent user prompt or active task description from the session transcript during compaction detection. Primary capture happens in the PreCompact hook handler (preferred, per R-001), with SessionStart(compact) as fallback if PreCompact did not fire. The captured task is stored in a temporary file for later use. Capture happens by reading the transcript file at hook execution time.
- **FR-005**: The transcript path provided in the hook input (`transcript_path` field) MUST be used to read the session history for interrupted task capture.
- **FR-006**: After the compaction-audit completes and the model has performed any necessary reverts, the system MUST trigger /clear (automatically in tmux, or via user instruction outside tmux).
- **FR-007**: The /clear MUST NOT be triggered until the audit and reverts are complete. The system must use a sequencing mechanism (e.g., the model signals completion, or a PostToolUse hook detects the final revert).
- **FR-008**: After /clear, the fresh session MUST load both the CARRYOVER file (per feature 002) and the interrupted task context.
- **FR-009**: The interrupted task context MUST be included in the `additionalContext` provided to the model on session start, clearly labeled as the task that was interrupted by compaction.
- **FR-010**: The system MUST distinguish between a compaction-triggered SessionStart (needs recovery) and other SessionStart events. A state marker (flag file) written during compaction detection and consumed on the next /clear achieves this.
- **FR-011**: In tmux environments, the system MUST automate the full recovery cycle. The audit is triggered primarily via injected context (FR-002); tmux send-keys is used for `/clear` after audit completion (gated by FR-007). If the model does not begin the audit within a reasonable window after context injection, tmux send-keys MAY be used as a fallback to send `/compaction-audit`.
- **FR-012**: Outside tmux, the system MUST display step-by-step instructions for the developer to follow manually.
- **FR-013**: All new scripts MUST reside in `~/dotfiles/scripts/bin/` and be symlinked to `~/bin/`.
- **FR-014**: Hook definitions MUST be added to `~/dotfiles/claude/.claude/settings.json`.
- **FR-015**: The system MUST NOT modify the existing `context-guardian.sh` or `context-monitor.sh` scripts.

#### Race Condition Safeguards

- **FR-016**: The recovery state marker MUST prevent re-entrant recovery. If the marker already exists when a new compaction event is detected, the system MUST NOT start a second parallel recovery process — it MUST treat the new compaction as part of the ongoing recovery cycle.
- **FR-017**: While the recovery state marker is present, the CARRYOVER auto-clear mechanism (from feature 002) MUST be suppressed. Recovery owns the /clear lifecycle during active recovery; a CARRYOVER-triggered /clear firing mid-audit would abort the recovery.
- **FR-018**: The injected compaction-detection context MUST instruct the model to halt all other work immediately — no file edits, no task execution, no tool calls unrelated to the audit — until the compaction-audit is complete and all reverts are done. This closes the window between compaction detection and audit start.
- **FR-019**: The system MUST read the transcript file for interrupted task capture in a crash-safe manner. It MUST handle incomplete trailing lines (partial JSON) gracefully — by discarding the incomplete final line — since the file may be actively appended to by the session process.
- **FR-020**: In tmux environments, the system MUST NOT send `/clear` via send-keys while the model is actively generating a response. The system MUST wait for the model's current response to complete (e.g., by detecting the command prompt or input indicator reappearing) before sending `/clear`.
- **FR-021**: The post-recovery /clear session start MUST NOT match the `compact` SessionStart pattern. The system MUST ensure that /clear-triggered sessions are distinguishable from compaction-triggered sessions to prevent infinite recovery loops. (SessionStart `compact` fires only on auto-compaction; /clear fires SessionStart with a different event type. This requirement makes that distinction explicit and testable.)
- **FR-022**: The recovery state marker MUST be consumed (deleted) only AFTER the interrupted task context has been successfully captured and stored, but BEFORE the /clear trigger fires, ensuring exactly-once recovery semantics. If marker deletion fails, the system MUST warn the developer rather than silently re-triggering recovery.
- **FR-023**: The recovery state marker MUST include a session identifier (or timestamp) so that stale markers from a previously crashed recovery can be detected. On compaction detection, if a marker already exists with a different session identifier, the system MUST treat it as stale, clean it up, and proceed with fresh recovery for the current session.

#### Blind Spot Safeguards

- **FR-024**: The recovery workflow MUST NOT depend on model compliance for correctness — only for optimality. If the model ignores the halt instruction (FR-018) and makes file edits before running the audit, those edits are still post-compaction and MUST be detected by the audit. The system MUST warn the developer that model non-compliance occurred.
- **FR-025**: If the last user message in the pre-compaction zone is trivial (10 characters or fewer, or a common confirmation pattern like "yes", "ok", "continue", "y", "go"), the system MUST scan backwards through prior user messages until it finds a substantive task description (more than 10 characters and not a confirmation pattern). If no substantive message is found within the pre-compaction zone, the interrupted task context MUST note "task description unavailable — manual context required."
- **FR-026**: The system MUST validate that required tools are available in the hook execution environment before attempting to use them. If unavailable, the system MUST display an error with specific remediation steps rather than failing with cryptic errors or producing incorrect output.
- **FR-027**: The system MUST handle tmux pane unavailability gracefully. If the tmux environment indicates tmux is present but the target pane is no longer accessible (closed, detached, killed), the system MUST fall back to the non-tmux manual instruction path (FR-012) rather than failing silently or hanging.
- **FR-028**: The system MUST validate that the `transcript_path` field exists in the hook input and points to a readable file before attempting to extract interrupted task context. If the field is missing or the file is unreadable, the system MUST proceed with recovery using only CARRYOVER context (if available) and log a warning visible to the developer.
- **FR-029**: When CARRYOVER and interrupted task contexts are both loaded into the post-recovery session, they MUST be combined with a preamble that clearly distinguishes: (a) the source of each context piece (CARRYOVER vs interrupted task), (b) that this is a compaction recovery (not a normal context rotation), and (c) that the interrupted task should take priority for immediate resumption.
- **FR-030**: If the combined CARRYOVER + interrupted task context exceeds 50KB (or the platform-documented limit for additionalContext, whichever is smaller), the interrupted task context (more immediately actionable) MUST take priority. CARRYOVER MUST be truncated from the middle (preserving the header and the most recent state sections) before interrupted task context is reduced.
- **FR-031**: ~~BLOCKING — validated 2026-03-08.~~ The hook API confirms: SessionStart input provides `session_id`, `transcript_path`, `cwd`, `source` (with matchers `startup`/`resume`/`clear`/`compact`), and `model`. SessionStart output supports `hookSpecificOutput.additionalContext` for context injection. Multiple hooks' `additionalContext` values are concatenated (not overwritten). Hooks run in parallel with a 600-second default timeout. `CLAUDE_ENV_FILE` is available for persisting environment variables to the session. All assumptions verified — no design adaptation required.

#### Structural Integrity Safeguards

- **FR-032**: The developer MUST be able to abort the recovery workflow at any point. Aborting MUST clean up the recovery state marker and any temporary files without triggering /clear. The system MUST provide a clear abort mechanism (e.g., a cancel command or Ctrl+C handling that performs cleanup).
- **FR-033**: The recovery workflow MUST produce visible output at each stage — compaction detected, audit started, N tainted edits found, reverts in progress, /clear pending — so the developer can observe progress. This output MUST be visible in both tmux and non-tmux environments.
- **FR-034**: If the recovery workflow fails partway through (audit crashes, revert fails, marker stuck), the system MUST leave the codebase in a state the developer can manually recover from. Partial reverts MUST be committed or stashed so they are not lost. The recovery state marker MUST remain (not be consumed) so the developer can diagnose the failure, and the system MUST display what happened and what steps remain.
- **FR-035**: SC-004 (zero manual steps in tmux) requires that the compaction-audit operate in batch mode when invoked by the recovery workflow — performing all reverts without individual confirmation. The audit report (including all reverts performed) MUST still be displayed to the developer after completion. This batch mode is specific to recovery-triggered invocation; manual invocation of /compaction-audit MUST retain its interactive confirmation behavior.

#### Coverage & Completeness

- **FR-036**: The compaction-audit MUST detect tainted file modifications made via the Bash tool (e.g., redirects `>`, `>>`, pipes to `tee`, `sed -i`) in addition to Edit and Write tool calls. The recovery workflow MUST treat Bash-based file modifications identically to Edit/Write modifications for revert purposes.
- **FR-037**: Before performing any reverts, the system MUST check the git working tree for uncommitted changes. If the working tree is dirty (unstaged or staged changes unrelated to the recovery), the system MUST warn the developer. In interactive mode (non-tmux), the system offers to stash uncommitted changes before proceeding. In batch mode (tmux), the system MUST automatically stash uncommitted changes before reverting and restore the stash after reverts complete. Reverts MUST NOT silently overwrite uncommitted work.
- **FR-038**: The system MUST support selective revert. Even in batch mode, the developer MUST be able to review the full revert list after completion and undo specific reverts (restoring post-compaction edits they want to keep). The audit report MUST include enough detail for each revert to support this.
- **FR-039**: After reverts complete, the system MUST provide a verification summary: the last known-clean commit hash, a summary of files reverted, and a diff of the current state against that clean commit. This gives the developer confidence the codebase is in a known-good state.

#### Real-World Failure Handling

- **FR-040**: If a file marked as tainted was modified by an external process (not by Claude) between the tainted edit and the audit, the system MUST detect this conflict (file mtime or content differs from what the tainted tool call produced) and flag the file for manual review rather than blindly reverting.
- **FR-041**: If a tainted Write tool call created a new file (no prior version exists in git), the revert MUST delete the file rather than attempting to restore a non-existent prior version. The audit report MUST distinguish between "revert to prior version" and "delete created file."
- **FR-042**: The system MUST handle git detached HEAD state gracefully. File-level reverts (`git checkout <commit> -- <file>`) work in detached HEAD; the system MUST NOT assume a branch is checked out.

#### Developer Experience & Resumption Quality

- **FR-043**: The recovery workflow MUST produce a persistent recovery log file (not just terminal output) documenting: timestamp, session ID, number of tainted edits found, list of files reverted, list of files skipped or flagged, and the interrupted task description. This log MUST be preserved across /clear so the developer can review what happened even if they were away.
- **FR-044**: The post-recovery context injected into the fresh session MUST include not just the interrupted task description but also a summary of what was reverted vs what was preserved. This allows the model to understand which steps of the interrupted task were completed successfully (pre-compaction) and which need to be redone.
- **FR-045**: The post-recovery context MUST clearly instruct the model to verify the current file state before re-executing any steps of the interrupted task, rather than blindly replaying the entire task from scratch. The model should read reverted files to understand what work remains.

#### Security & Integrity

- **FR-046**: The interrupted task context injected into the fresh session MUST be clearly delimited as a quoted user prompt (data), not as system instructions. The preamble MUST explicitly state that the following text is "the user's original prompt that was interrupted" to prevent the model from interpreting captured prompt text as new directives or system-level instructions.
- **FR-047**: If any tainted file is a hook configuration file (e.g., `settings.json`), a slash command definition (e.g., `compaction-audit.md`), or a governance file (e.g., `CLAUDE.md`, constitution), the system MUST flag these as **critical infrastructure files** and prioritize their revert. Tainted infrastructure files mean the recovery system itself may be operating on compromised definitions.
- **FR-048**: Reverts of infrastructure files (hook config, slash commands, CLAUDE.md) MUST complete before /clear fires. If these files are tainted and not reverted, the fresh session would load compromised governance or hook definitions, undermining the entire recovery.

#### Cross-Feature Integration

- **FR-049**: Git hooks (pre-commit, pre-push, etc.) MUST NOT block recovery reverts. If the recovery workflow performs reverts via git operations that trigger hooks, and those hooks fail (e.g., a lint hook rejects a reverted file), the revert MUST still proceed. The recovery workflow MUST bypass or suppress git hooks during revert operations.
- **FR-050**: The recovery workflow MUST degrade gracefully if feature 002 (CARRYOVER loading) is not implemented or fails. The interrupted task context alone MUST be sufficient for basic resumption. The system MUST NOT fail or abort recovery because CARRYOVER loading is unavailable.
- **FR-051**: The system SHOULD support a simulation or dry-run mode that allows the developer to verify recovery scripts and hook configuration are correctly wired without requiring an actual compaction event. This can be triggered by a manual command or test hook invocation.

#### Operational Maturity

- **FR-052**: Recovery log files MUST be limited to prevent unbounded accumulation. The system MUST retain at most the 10 most recent recovery logs and automatically delete older ones when a new log is created.
- **FR-053**: The recovery workflow MUST be context-efficient. The audit, revert operations, and progress output in the post-compaction session MUST minimize context consumption — using concise output, avoiding verbose diffs in conversation, and deferring detailed information to the recovery log file rather than conversation output.

#### Lifecycle & Cleanup

- **FR-054**: The interrupted task context temporary file MUST be deleted after it has been successfully loaded into the fresh post-/clear session. If the file is not deleted (e.g., /clear never fires, or loading fails), it MUST be cleaned up on the next successful session start — stale interrupted task files (older than 24 hours) MUST be automatically removed.
- **FR-055**: All temporary artifacts created by the recovery workflow (recovery state marker, interrupted task context file, stash refs) MUST be tracked so that cleanup can be performed reliably. If the recovery workflow is aborted (FR-032), all tracked artifacts MUST be cleaned up as part of the abort.

#### Filesystem & Resource Constraints

- **FR-056**: Before writing recovery artifacts (marker, log, interrupted task file), the system MUST verify that the target directory is writable. If the filesystem is read-only or the directory is not writable, the system MUST fall back to stdout-only reporting — injecting recovery context entirely via `additionalContext` and writing nothing to disk. The system MUST log that file-based artifacts were skipped due to filesystem constraints.
- **FR-057**: If a tainted edit targets a symbolic link, the system MUST resolve the link and revert the target file's content. The revert report MUST note the symlink relationship, showing both the symlink path (as referenced by the tool call) and the resolved target path (where the actual content change occurred).
- **FR-058**: All recovery artifacts (marker, log, temp files) MUST be created with mode `0600` (owner read/write only) per FR-091, since these files may contain sensitive data. The system MUST NOT create files with overly permissive modes. If a pre-existing artifact from a prior session has restrictive permissions (e.g., owned by a different user), the system MUST detect this, warn the developer, and attempt to recreate the file rather than silently failing.

#### Git Operational Edge Cases

- **FR-059**: Before performing git-based reverts, the system MUST check for `.git/index.lock`. If present, the system MUST warn the developer that another git operation may be in progress and skip git-based reverts for the current cycle, providing manual revert instructions instead. The system MUST NOT delete the lock file or wait indefinitely.
- **FR-060** *(P4-YAGNI)*: The recovery workflow SHOULD detect tainted edits within git submodules if submodules are present. This project does not use submodules; this FR is deferred unless the project structure changes. If implemented, reverts for submodule files MUST operate within the submodule's own git context.
- **FR-061**: If a merge or rebase operation is in progress (`.git/MERGE_HEAD`, `.git/rebase-merge`, or `.git/rebase-apply` exists), the system MUST warn the developer and skip automatic reverts for files involved in the merge/rebase. Recovery proceeds with reverts for non-conflicting tainted files only. The recovery report MUST note skipped files and the reason.

#### Signal & Interrupt Handling

- **FR-062**: Recovery hook scripts MUST install signal handlers (via `trap`) for SIGTERM, SIGINT, and SIGHUP. Upon receiving a termination signal, the handler MUST persist current recovery state to the marker file — recording what stage was reached (detection, transcript parsing, audit pending) — before exiting. This ensures the next session can diagnose an interrupted recovery.
- **FR-063**: The recovery workflow MUST be resumable. If recovery was interrupted (signal, crash, disconnect, hook timeout), the next session start MUST detect the partial recovery state from the marker file (which records the last completed stage). The system MUST present the developer with the partial state and the option to resume from the interruption point or start fresh. In tmux batch mode, the system MUST automatically resume from the interruption point.

#### Transcript Parsing Robustness

- **FR-064**: The transcript parser MUST use defensive parsing — checking for the existence of expected fields (`role`, `content`, `type`) before accessing them and skipping entries with unrecognized structure. If more than 10% of entries are unrecognized, the system MUST log a format compatibility warning and proceed with whatever valid entries were found.
- **FR-065**: When scanning the transcript for the last substantive user message, the parser MUST limit its read to the last 1MB of the transcript file (seeking from the end). If no substantive message is found within this window, the system MUST proceed with CARRYOVER-only context and note "interrupted task not found within scan window."

#### Revert Correctness & Granularity

- **FR-066**: When a file was edited multiple times post-compaction, the revert MUST restore the file to its pre-compaction state (the version at or before the last pre-compaction commit or the file content immediately before the first post-compaction edit). The audit report MUST group all post-compaction edits for the same file together, showing the cumulative change.
- **FR-067**: If a tainted operation moved or renamed a file (detected by analyzing Bash tool calls with `mv`, `git mv`, or by a Write to a new path followed by deletion of the old path), the revert MUST restore the file to its original path and remove the new-path copy. The audit report MUST note rename/move operations distinctly from content edits.

#### Scale & Performance Boundaries

- **FR-068**: If the number of tainted edits exceeds 50, the system MUST switch to summarized conversation output — listing only file paths and edit types (created/modified/deleted/moved), with full per-edit details deferred to the recovery log file. This prevents large-scale tainted edits from consuming the post-compaction context budget (per FR-053).
- **FR-069**: The recovery log retention cleanup (FR-052) MUST execute before writing a new log, not after. This ensures that even during rapid compaction cycling, the log directory never exceeds 11 files (10 retained + 1 being written).

#### Platform Compatibility & Versioning

- **FR-070**: The SessionStart hook script SHOULD complete quickly to minimize session startup delay. The platform allows up to 600 seconds, but the hook SHOULD target completion within 30 seconds. The hook MUST prioritize writing the recovery marker before transcript parsing, so that if the hook is interrupted or times out, the marker exists for the next session. Transcript scanning SHOULD be bounded (e.g., last 1MB per FR-065) to avoid long delays on large transcripts.
- **FR-071**: The system MUST log the Claude Code version (if exposed via hook input metadata or `claude --version`) in the recovery log for debugging compatibility issues. If the hook input format deviates from expectations (missing expected fields, unexpected structure), the system MUST log the discrepancy and proceed with best-effort recovery rather than failing.

#### Environment & Context Inheritance

- **FR-072**: The hook script MUST validate critical environment variables (HOME, PATH) at startup and verify that required tools (jq, git) are accessible via the current PATH. If essential variables are missing or required tools are not found, the script MUST log a diagnostic error listing exactly what is missing and expected, then exit gracefully with a non-zero code rather than producing undefined behavior.
- **FR-073**: If the `additionalContext` field has a platform-imposed size limit, the system MUST detect truncation (e.g., by appending a sentinel string at the end of the context and checking for its presence) or defensively assume a conservative limit (e.g., 100KB) and truncate proactively per FR-030 priority rules.

#### Testing & Validation Infrastructure

- **FR-074**: The dry-run mode (FR-051) MUST exercise the same code paths as the real recovery workflow, differing only in final actions: reverts are reported but not executed, /clear is not triggered, and no git state is modified. The dry-run MUST produce a full report of what would have happened, including which files would be reverted, what context would be injected, and whether any edge cases were encountered.
- **FR-075**: The system SHOULD provide a health-check command that validates recovery infrastructure readiness: (a) hook definitions exist and are correctly formatted in settings.json, (b) required scripts exist and are executable, (c) required tools (jq, git, optionally tmux) are available, (d) the recovery artifact directory is writable, and (e) a sample SessionStart input can be processed without errors. The health-check MUST report pass/fail for each item with specific remediation instructions for failures.

#### Multi-Hook & Subagent Coordination

- **FR-076**: Tainted edits made by subagents (launched via the Agent tool) MUST be treated identically to main-session edits for detection and revert purposes. The audit MUST scan for tool_use entries from subagent contexts in the transcript, not just top-level tool calls. The recovery report MUST note which tainted edits originated from subagents.
- **FR-077**: The recovery hook MUST coexist with other user-defined SessionStart hooks. The platform runs all matching hooks in parallel and concatenates their `additionalContext` values. The recovery context MUST be self-contained and clearly delimited (e.g., with a header like `--- COMPACTION RECOVERY CONTEXT ---`) so that concatenation with other hooks' context does not cause ambiguity. The recovery hook MUST NOT assume ordering relative to other hooks' output.
- **FR-078**: The recovery workflow MUST NOT assume a specific output format from the compaction-audit command. It MUST detect audit completion by the model's explicit signal (e.g., "audit complete, N files reverted") or by the absence of further audit-related tool calls, rather than by parsing specific audit output text. This allows the developer to customize the audit command without breaking recovery.

#### Observability & Post-Mortem

- **FR-079**: The recovery log MUST use a stable, versioned format. The first line of each log MUST include a format version identifier (e.g., `format: recovery-log-v1`). This enables external tools and scripts to parse recovery logs reliably and detect format changes across upgrades.
- **FR-080**: The recovery log MUST include structured metadata at the top: timestamp, session ID, Claude Code version (if available), total tainted edits, total reverted, total skipped/flagged, recovery duration, and outcome (success/partial/aborted). This supports aggregation across multiple recovery events.
- **FR-081** *(P4-YAGNI)*: After recovery completes in tmux (batch mode), the system SHOULD emit a terminal bell (`\a`) to alert the developer. Configurable notification commands are deferred — terminal bell is sufficient for this project's single-developer, single-machine deployment.

#### Recovery Context Quality

- **FR-082**: The interrupted task context MUST include not just the last substantive user message but also up to 3 preceding user messages (if they exist within the pre-compaction zone and are substantive), separated by clear delimiters. This provides enough conversational context for the model to disambiguate tasks like "fix the bug" that require surrounding context to understand.
- **FR-083**: The recovery preamble injected via `additionalContext` (FR-029) MUST NOT exceed 2KB. The preamble is overhead — every byte consumed by the preamble is unavailable for the model's actual work. The preamble MUST be structured as: (1) one-line recovery summary, (2) reverted/preserved file list, (3) interrupted task context. Verbose explanations MUST be deferred to the recovery log.
- **FR-084**: The recovery preamble MUST instruct the model to confirm its understanding of the interrupted task before resuming execution. The model's first response MUST include a brief statement of what it understands the interrupted task to be and what it plans to do next, giving the developer a chance to correct before work begins.

#### Non-Git & Alternative Recovery Paths

- **FR-085** *(P4-YAGNI)*: If the working directory is not a git repository, the system SHOULD still detect compaction and capture the interrupted task. Revert operations are unavailable without git history — the system MUST warn the developer and provide manual guidance. This project is git-managed; full non-git support is deferred.
- **FR-086**: If tainted edits target files outside the git repository root (e.g., absolute paths like `/tmp/output.txt`, `~/.config/app.conf`, or paths above the repo root), the system MUST detect these as out-of-repo edits, report them in the audit, and skip automatic revert. The recovery report MUST list these files with their full paths and recommend manual review.
- **FR-087** *(P4-YAGNI — depends on FR-085)*: Deferred. File-backup retention policy for non-git environments is not needed while FR-085 is deferred.

#### Encoding & Path Safety

- **FR-088**: All file path handling in recovery scripts (marker paths, log paths, revert targets) MUST be safe for paths containing spaces, unicode characters, and shell-special characters (`$`, backticks, `'`, `"`, `*`, `?`). Paths MUST be quoted in all shell operations. Log entries MUST use a delimiter-safe encoding (e.g., JSON strings) for file paths rather than bare whitespace-separated lists.
- **FR-089**: The interrupted task context extracted from the transcript MUST be treated as opaque binary data during storage and transport. The system MUST NOT interpret, transform, or truncate the text at encoding boundaries (e.g., mid-multibyte UTF-8 character). The temp file MUST be written with the same encoding as the transcript source.

#### Recovery Artifact Security

- **FR-090**: The recovery log MUST NOT embed full file contents or complete diffs. It MUST record only file paths, edit types (created/modified/deleted/moved), line count deltas, and the first 200 characters of each diff hunk. This prevents sensitive file contents (credentials, keys, PII) from being persisted in plaintext recovery logs.
- **FR-091**: The interrupted task context temp file and recovery log MUST be created with mode `0600` (owner read/write only), regardless of umask. These files may contain user prompts that include sensitive data (API keys, credentials, internal URLs). The recovery marker MUST also use `0600` since it contains session metadata.
- **FR-092**: On loading the recovery marker at session start, the system MUST validate the marker's structural integrity — it MUST be valid JSON (or the chosen format), contain expected fields (session ID, stage, timestamp), and have a file size within expected bounds (under 10KB). If validation fails, the marker MUST be treated as corrupted, renamed to `.corrupt`, and the system MUST warn the developer and proceed without recovery state.

#### Graceful Degradation Hierarchy

- **FR-093**: The recovery workflow MUST follow a defined degradation hierarchy when components are unavailable. From richest to minimal recovery, the tiers are: (1) Full recovery — git reverts + CARRYOVER + interrupted task + recovery log + auto-/clear. (2) No CARRYOVER — git reverts + interrupted task + recovery log + auto-/clear. (3) No transcript — git reverts + CARRYOVER + recovery log + auto-/clear (interrupted task unavailable). (4) No git — file-backup reverts + CARRYOVER + interrupted task + recovery log + auto-/clear. (5) No filesystem writes — additionalContext injection only (detection + context, no reverts, no log). (6) Minimal — compaction detected, developer warned via injected context, no automated action. Each tier MUST produce a warning stating which capabilities are degraded and why.
- **FR-094**: When multiple failure modes compound (e.g., no git AND no transcript AND read-only filesystem), the system MUST degrade to the lowest applicable tier from FR-093 without crashing. The system MUST NOT attempt operations that are known to be unavailable — it MUST skip them cleanly and proceed to the next available capability.

#### User Workflow Integration

- **FR-095**: If the interrupted task captured from the transcript is a slash command invocation (e.g., `/speckit.plan`, `/commit`), the recovery context MUST identify it as a slash command and include the full command with arguments, not just the slash command name. The post-recovery model MUST be instructed to re-invoke the slash command rather than attempting to manually replicate its behavior.
- **FR-096**: Before performing git stash operations (FR-037), the system MUST preserve the staged/unstaged distinction of the developer's working tree. The stash MUST use `git stash push --keep-index` followed by a separate stash of the index, or an equivalent mechanism that allows restoring both staged and unstaged changes independently after recovery. If this level of preservation is not feasible, the system MUST warn the developer that their staging state will be flattened.
- **FR-097**: The recovery report MUST include a warning if any reverted files are likely open in an external editor or IDE. The system SHOULD detect this by checking for common lock files (`.swp`, `.~lock.*`) or by noting files with very recent mtime that differs from the reverted content. The warning MUST advise the developer to reload files in their editor to avoid the editor re-saving stale buffers over the recovery.

#### Gap Coverage

- **FR-098**: If the compaction-audit finds zero tainted edits (compaction occurred before any post-compaction file modifications), the recovery workflow MUST short-circuit — skipping the revert phase entirely and proceeding directly to /clear and resume. The recovery log MUST still be written, noting "0 tainted edits found." The recovery context injected into the fresh session MUST note that no reverts were necessary.
- **FR-099**: If a git-based revert fails because the target commit is not available locally (e.g., shallow clone with insufficient history, or the pre-compaction version predates the shallow boundary), the system MUST skip that file's revert, flag it for manual review in the recovery report, and continue with remaining reverts. The report MUST note the cause ("commit not in local history — shallow clone?") and suggest `git fetch --unshallow` as remediation.
- **FR-100**: If a tainted operation changed a path's type (e.g., deleted a file and created a directory at the same path, or vice versa), the revert MUST remove the new entity and restore the original type. The system MUST detect type mismatches by comparing the current filesystem state against the pre-compaction git tree. The recovery report MUST flag type-change reverts distinctly as they require special handling.

### Key Entities

- **Compaction Event**: A system-triggered context compression, detected via SessionStart with `compact` source. Marks the boundary between trusted and untrusted context.
- **Interrupted Task Context**: The most recent user prompt or task description captured from the session transcript at compaction time. Stored as a temporary file for injection into the post-recovery session.
- **Recovery State Marker**: A flag file that indicates compaction recovery is in progress. Contains a session identifier (or timestamp) for staleness detection. Created when compaction is detected, consumed when /clear fires after recovery. Prevents the recovery workflow from re-triggering on unrelated session events and guards against re-entrancy, CARRYOVER interference, and stale marker accumulation.
- **CARRYOVER File**: (From feature 002) The model-written context summary. Used alongside the interrupted task context to provide full resumption state.
- **Recovery Log**: A persistent file documenting the recovery workflow's actions — timestamp, session ID, tainted edits found, files reverted, files flagged, interrupted task description. Survives /clear for post-hoc review by the developer.

## Assumptions

- The `transcript_path` field in SessionStart hook input points to a readable JSONL file containing the full session history (including pre-compaction messages).
- The compaction-audit slash command outputs its findings as conversation text that the model can read and act on (reverting files, etc.).
- The model will follow the instruction to run `/compaction-audit` when it is injected as SessionStart context. If the model ignores it, the developer will see the instruction and can invoke it manually.
- Feature 002 (context-auto-rotation) is implemented. The SessionStart hook for `/clear` (from 002) handles CARRYOVER loading. This feature adds the interrupted task context to that same loading mechanism.
- The interrupted task context is extracted from the last `user` message in the pre-compaction zone of the transcript. This is a reasonable approximation of "what was being done."
- The `$TMUX` environment variable is available inside hook execution to detect tmux presence.
- The `jq` command-line tool is available on the system.
- JSONL transcript files are append-only during a session; lines are not modified after being written. Only the trailing line may be incomplete at read time.
- The SessionStart event type for /clear is distinct from the SessionStart event type for auto-compaction (i.e., `clear` vs `compact` matchers do not overlap). This is a Claude Code platform guarantee.
- The model will honor "halt all work" instructions injected via SessionStart context. If the model ignores the halt and makes tainted edits before running the audit, the audit will still catch them (since they are post-compaction edits).
- Only one Claude Code session is active per working directory at any given time. Concurrent sessions in the same directory are out of scope.
- The tmux pane's command prompt (input indicator) is detectable by the hook or script to determine when the model has finished responding.
- Hook scripts execute in the user's default shell with the user's full PATH inherited, including access to installed tools (jq, git, tmux). If this is not the case, the planning phase must discover and document the actual hook execution environment.
- SessionStart hook output supports `hookSpecificOutput.additionalContext` (string) which the platform injects into the model's initial context for the new session. Multiple hooks' values are concatenated. **Validated 2026-03-08 against Claude Code hooks API (FR-031 resolved).**
- The `transcript_path` field may not be present in all SessionStart event types. The system must handle its absence gracefully (see FR-028).
- Multi-session scenarios (multiple Claude Code instances in the same working directory) could cause undefined behavior with shared marker files and are explicitly excluded from scope (see Assumption about single session). The marker's session identifier (FR-023) provides partial mitigation but not full isolation.
- The compaction-audit command (invoked via FR-003) runs entirely within the post-compaction session and does not itself trigger additional compaction. If the audit's output is large enough to push context toward compaction again, the /clear that follows immediately terminates that session.
- The compaction-audit command can be extended to support a batch mode (auto-revert without individual confirmation) for recovery-triggered invocation. This may require modifying the compaction-audit.md command to accept a mode parameter, which is a controlled extension (not a reimplementation) and is compatible with FR-003.
- The recovery workflow is expected to complete within 2 minutes in the common case (fewer than 20 tainted edits). No hard timeout is enforced, but if recovery takes significantly longer, the developer can abort.
- The working directory is a git repository with at least one commit. File-level reverts depend on git history. If the directory is not a git repository, the audit can still identify tainted edits but cannot perform git-based reverts — manual revert guidance must be provided instead.
- Bash tool file modifications are detectable in the transcript by scanning tool_use entries with name `Bash` and inspecting the command string for file-writing patterns (redirects, `tee`, `sed -i`). This is heuristic and may miss obfuscated writes; the assumption is that normal model behavior produces recognizable file-modification commands.
- The recovery log file location should be within the project directory (e.g., `.claude/recovery-log-<timestamp>.md`) so it is accessible after /clear. It should not be placed in a temporary directory that might be cleaned up.
- The post-compaction session has limited remaining context budget. The recovery workflow (audit + reverts + progress output) must operate within this budget. If the audit output alone would consume most of the remaining context, the system should write details to the recovery log file and keep conversation output minimal.
- Infrastructure files (hook config, slash commands, CLAUDE.md) are identifiable by their known paths. The system can maintain a list of critical paths to check against tainted edits.
- Git hooks can be bypassed during recovery reverts using standard mechanisms (e.g., `--no-verify` for commits, environment variables for other hooks). This is acceptable during recovery because the reverts are restoring known-good state, not introducing new changes that need validation.
- Hook scripts have a platform default timeout of 600 seconds (configurable via `timeout` field). The hook should still complete quickly (marker creation first, transcript parsing second) but the platform timeout is not a constraint for normal recovery operations. **Validated 2026-03-08.**
- The filesystem may be read-only in certain environments (containers, CI). File-based recovery artifacts are best-effort; core recovery functionality (context injection via `additionalContext`) must work without filesystem writes.
- Git submodules, if present, maintain their own git history and require per-submodule revert operations. The parent repo's git context cannot revert files inside submodules.
- The Claude Code transcript format may evolve between versions. The parser must be defensive and forward-compatible — skipping unrecognized entries rather than crashing.
- File-level reverts for renamed or moved files require reconstructing the rename from tool call analysis (Bash `mv` commands or Write+Delete pairs). This is heuristic and may miss complex rename chains.
- The recovery workflow may be interrupted at any point by signals, crashes, or platform timeouts. The marker file serves as the persistence mechanism for interrupted recovery state, and must be updated incrementally as stages complete.
- The `additionalContext` field may have a platform-imposed size limit. If no documented limit exists, the system should assume a conservative 100KB ceiling and truncate proactively.
- Subagent tool calls appear in the session transcript alongside top-level tool calls. The transcript format distinguishes subagent-originated entries (e.g., via a context or agent identifier field). If this distinction is not present in the transcript, all post-compaction tool calls are treated as tainted regardless of origin.
- The platform supports multiple SessionStart hooks running in parallel. Each hook's `additionalContext` is concatenated. Identical handlers are deduplicated by command string. **Validated 2026-03-08.**
- The compaction-audit command's output format is not guaranteed to be stable across customizations. The recovery workflow must not parse audit output — it relies on the model's behavior (running the audit, performing reverts) and detects completion via model signaling, not output parsing.
- Non-git directories can still benefit from compaction recovery (tainted edit detection, interrupted task capture, context injection) even though automated reverts require a file-backup fallback instead of git history.
- The recovery preamble (injected via `additionalContext`) should be kept under 2KB to minimize overhead in the fresh session's context budget.
- File paths in the working directory may contain spaces, unicode, and shell-special characters. All path handling must use proper quoting and escaping.
- Recovery artifacts (marker, log, temp files) may contain sensitive data from user prompts or file contents. They must be protected with restrictive file permissions.
- The developer may have files open in an external editor or IDE that does not auto-reload on disk changes. Recovery reverts may be silently overwritten by the editor re-saving its buffer.
- Slash command invocations (e.g., `/speckit.plan "arg"`) appear in the transcript as user messages. The interrupted task capture can identify them by the leading `/` pattern.
- The recovery workflow has a defined degradation hierarchy (FR-093). Each component failure removes one or more capabilities but never causes a crash or undefined behavior.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Compaction is detected within the same session restart event — the model's first response after compaction references the audit, not the previous task.
- **SC-002**: 100% of tainted file edits identified by the audit are presented to the developer for revert before /clear fires.
- **SC-003**: After the full recovery cycle (detect, audit, revert, /clear, resume), the model's first response in the fresh session references both the carryover state and the specific interrupted task.
- **SC-004**: In tmux, the recovery cycle from compaction detection to model resuming work completes with zero manual steps (the audit runs in batch mode, performing all reverts without individual confirmation, per FR-035).
- **SC-005**: Outside tmux, the recovery cycle requires at most two manual steps (typing `/compaction-audit` and typing `/clear`), with clear instructions displayed for each.
- **SC-006**: The recovery workflow does not re-trigger on subsequent /clear or session restarts that are not compaction events.
- **SC-007**: The recovery workflow is idempotent with respect to race conditions — a stale recovery marker, a concurrent CARRYOVER write, or a double compaction event does not cause data loss, infinite loops, or silent failure.
- **SC-008**: The recovery workflow degrades gracefully under all identified failure modes — missing transcript, unavailable tmux pane, missing tools, trivial interrupted task, model non-compliance — without data loss or silent failure. Each degraded path produces a visible warning to the developer.
- **SC-009**: ~~The hook input/output format assumptions are validated before implementation.~~ **RESOLVED 2026-03-08**: SessionStart provides `transcript_path`, `session_id`, `source` (with `compact`/`clear` matchers), and supports `additionalContext` injection via `hookSpecificOutput`. All assumptions confirmed.
- **SC-010**: After recovery, the model's first action in the fresh session is to verify current file state (not blindly replay the interrupted task). The model references both what was reverted and what was preserved before resuming work.
- **SC-011**: A persistent recovery log is available after /clear that documents all recovery actions taken — enabling post-hoc review even if the developer was away during automated recovery.
- **SC-012**: If any tainted file is an infrastructure file (hook config, slash command, CLAUDE.md), it is reverted before /clear fires, ensuring the fresh session operates on clean governance and hook definitions.
- **SC-013**: The recovery workflow's conversation output in the post-compaction session consumes no more than 20% of the remaining context budget, with detailed information deferred to the recovery log file.
- **SC-014**: The recovery hook script completes execution within 30 seconds, including transcript parsing, even for sessions with large transcripts (>10,000 entries). The platform allows 600 seconds but fast startup is preferred.
- **SC-015**: The recovery workflow is resumable — if interrupted mid-recovery by signal, crash, or disconnect, the next session detects the partial state and enables completion without data loss or repeated reverts.
- **SC-016**: A health-check command validates the full recovery infrastructure (hook config, scripts, tools, permissions) without requiring actual compaction, enabling pre-flight verification after initial setup or Claude Code upgrade.
- **SC-017** *(P4-YAGNI)*: Deferred — project does not use git submodules.
- **SC-018**: On a read-only filesystem, the recovery workflow still completes successfully — detecting compaction, injecting context, and reporting tainted edits — using `additionalContext` injection alone, without writing any files to disk.
- **SC-019**: Tainted edits originating from subagent operations are detected and included in the audit report with the same reliability as main-session edits.
- **SC-020**: The recovery preamble injected into the fresh session does not exceed 2KB, ensuring minimal overhead on the post-recovery context budget.
- **SC-021** *(P4-YAGNI)*: Deferred — project is git-managed.
- **SC-022**: The model's first response after recovery confirms its understanding of the interrupted task before resuming execution, giving the developer an opportunity to correct misinterpretation.
- **SC-023**: Recovery logs have a stable, versioned format that enables external tooling to parse and aggregate recovery events across sessions.
- **SC-024**: Recovery artifacts (marker, log, interrupted task file) are created with `0600` permissions, preventing other users or processes from reading potentially sensitive content.
- **SC-025**: Under compound failure (no git + no transcript + read-only filesystem), the recovery workflow still detects compaction and injects a warning into the fresh session — the minimum viable recovery never silently fails.
- **SC-026**: Recovery logs do not contain full file contents or credentials — only file paths, edit types, and truncated diff summaries (≤200 chars per hunk).
- **SC-027**: File paths containing spaces, unicode, or shell-special characters are handled correctly throughout the recovery workflow — no path corruption, shell injection, or truncation at encoding boundaries.
- **SC-028**: If the interrupted task was a slash command invocation, the post-recovery model re-invokes the slash command rather than manually replicating its behavior.
