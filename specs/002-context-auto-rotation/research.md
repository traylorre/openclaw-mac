# Research: Context Guardian Auto-Rotation

**Feature**: 002-context-auto-rotation
**Date**: 2026-03-10

## R-001: hook-common.sh Refactoring Strategy

**Context**: FR-020 requires extracting shared utilities from 003's `recovery-common.sh` into a new `hook-common.sh` that both features source.

**Finding**: `recovery-common.sh` (511 lines) contains two distinct categories:

- **Shared utilities** (~120 lines): logging, environment detection, JSON helpers, timestamps, permissions, tool validation
- **Recovery-specific** (~390 lines): marker management, interrupted task capture, recovery log management, abort handling, transcript parsing, dry-run support

Functions to extract into `hook-common.sh`:

| Function | Lines | Notes |
|----------|-------|-------|
| HOME/PATH validation | 8 | Move as-is |
| `require_tool()` | new | Currently inline `for _tool in jq git` — generalize to callable function |
| `log_info()`, `log_warn()`, `log_error()` | 9 | Add configurable `HOOK_LOG_PREFIX`, dual-write to stderr + file |
| `is_tmux()` | 3 | Move as-is |
| `project_root()` | 4 | Move as-is |
| `set_permissions()` | 3 | Move as-is |
| `iso_timestamp()`, `iso_timestamp_full()` | 7 | Move as-is |
| `parse_stdin_json()` | 9 | Move as-is |
| `json_field()`, `json_field_or_null()` | 8 | Move as-is |

**Decision**: Extract shared utilities into `hook-common.sh`. `recovery-common.sh` sources `hook-common.sh` at its top, retains only recovery-specific code. All 002 scripts source only `hook-common.sh`.

**Rationale**: Clean separation allows either feature to be uninstalled without breaking the other. The refactoring scope is surgical — move functions, add `source` line, test. No behavioral changes to existing 003 scripts.

**Alternatives considered**:

- *Copy shared functions into 002 scripts*: Duplication. Rejected per FR-020.
- *002 sources recovery-common.sh directly*: Creates dependency on 003. Rejected.

**Post-refactor structure**:

```bash
# hook-common.sh — Shared hook utilities (002 + 003)
HOOK_LOG_PREFIX="${HOOK_LOG_PREFIX:-hook}"
HOOK_LOG_DIR=".claude/recovery-logs"
# ... shared functions ...

# recovery-common.sh — Recovery-specific (003 only)
HOOK_LOG_PREFIX="recovery"
source "$HOME/bin/hook-common.sh"
# ... recovery functions (unchanged) ...
```

## R-002: PostToolUse Hook Matcher Strategy

**Context**: The PostToolUse hook needs to fire on CARRYOVER file writes. Should the platform-level matcher filter, or the script?

**Finding**: The existing PreToolUse hook uses `"matcher": ".*"` (matches all tools). PostToolUse matchers work the same way — regex against `tool_name`.

**Decision**: Use `"matcher": ".*"` and implement fast-path filtering in the script (FR-010). The script checks `tool_name` against "Write"/"Edit" before any further processing.

**Rationale**: The spec explicitly designs the fast-path in the script (FR-010, SC-005). Using `"matcher": ".*"` ensures defense-in-depth — if a new tool name could write files, the regex-based basename check would still catch it. The fast-path exit for non-Write/Edit tools is <1ms (single jq field extraction + string compare).

**Alternatives considered**:

- *`"matcher": "Write|Edit"`*: More efficient (no script spawn for non-matching tools). Could be applied as a P3 optimization. But reduces defense-in-depth and couples hook config to tool name assumptions. Rejected as default.

## R-003: `compact` Event Validation Approach

**Context**: FR-011 and User Story 3 depend on `compact` being a valid SessionStart event name. This is UNVALIDATED (Q38).

**Finding**: The Claude Code hooks API documentation lists SessionStart source matchers as: `startup`, `resume`, `clear`, `compact`. The 003 spec's FR-031 validation (2026-03-08) confirmed `compact` as a source matcher. However, Q38 notes this was not empirically tested against an actual compaction event.

**Decision**: Proceed with `compact` as the event name. Validate empirically during implementation using 003's health-check (FR-075) or a manual test. If wrong, the impact is limited: User Story 3 (P3 priority) doesn't fire, but the poller timeout fallback still works. Changing the event name requires only updating the settings.json matcher — no code changes.

**Rationale**: The API documentation and 003's FR-031 validation both list `compact`. Risk is low and contained.

## R-004: Poller Prompt Detection Reliability

**Context**: FR-004 specifies a 3-line pattern (separator, prompt U+276F, separator) to detect Claude Code's idle state.

**Finding**: The `❯` (U+276F) and `─` (U+2500) are Unicode codepoints unlikely to appear in normal model output. The pattern requires scanning the full pane because UI elements (like "accept edits on") may appear below the prompt.

Known risks and mitigations:

| Risk | Mitigation |
|------|------------|
| ANSI escape codes in tmux <3.3 | Always strip: `sed 's/\x1b\[[0-9;]*m//g'` (FR-004) |
| Claude Code UI changes | 60s timeout fallback writes `carryover-clear-needed` |
| Split panes (wrong pane targeted) | Capture `$TMUX_PANE` at spawn, use `-t "$TMUX_PANE"` (FR-028) |
| Pattern false positive | Unicode chars + 3-line structure make false positives near-impossible |

**Decision**: Implement the 3-line pattern with ANSI stripping. Accept the 60s timeout fallback as robust degradation.

**Rationale**: Specific enough to avoid false positives, defensive ANSI stripping, and timeout fallback ensures the system never hangs.

## R-005: Signal File Namespace Coordination

**Context**: Both features use `.claude/` for signal files. Need to ensure no collisions.

**Finding**: Signal file namespace analysis:

| Feature | Files |
|---------|-------|
| 002 | `carryover-pending`, `carryover-pending.claimed`, `carryover-clear-needed` |
| 003 | `recovery-marker.json`, `recovery-interrupted-task.json`, `recovery-audit-complete` |

No naming collisions. The single cross-feature read is FR-016: 002's PostToolUse hook checks for `recovery-marker.json` and suppresses if present.

**Decision**: Current naming is clean. The only cross-feature interaction is 002 reading (not writing) 003's recovery marker.

## R-006: settings.json Integration

**Context**: Hook definitions must be added for 002 without breaking 003's existing hooks.

**Finding**: Current settings.json has hooks for PreToolUse, PreCompact, SessionStart(compact), SessionStart(clear), Stop, and Notification. No PostToolUse hooks exist.

Required changes:

| Hook Event | Matcher | Action |
|------------|---------|--------|
| PostToolUse | `.*` | NEW entry: `carryover-detect.sh` |
| SessionStart | `compact` | ADD `carryover-loader.sh` to existing hooks array |
| SessionStart | `clear` | ADD `carryover-loader.sh` to existing hooks array |
| SessionStart | `startup` | NEW matcher entry: `carryover-loader.sh` |

**Decision**: Add hooks as described. Multiple hooks per matcher are supported — platform runs them in parallel and concatenates `additionalContext`. 003's existing hooks remain untouched.

**Rationale**: Minimal changes to existing config. Additive only.

## R-007: File-Based Logging Strategy

**Context**: FR-023 requires logging to `.claude/recovery-logs/`. The poller runs detached with fd isolation (stdout/stderr to /dev/null).

**Finding**: Hook scripts log to stderr (platform captures). The poller cannot use stderr. Both need persistent logging.

**Decision**: `hook-common.sh` logging functions dual-write to stderr AND a per-invocation timestamped log file in `.claude/recovery-logs/` (e.g., `carryover-detect.2026-03-10T14:32:01.log`). Each script invocation writes to its own file — no shared append-only log. On `startup` events, the loader deletes log files older than 7 days (FR-034). The dual-write means:

- **Hook scripts**: Platform captures stderr; per-invocation file captures for debugging
- **Poller**: stderr silently discarded; per-invocation file captures all events
- **File logging**: Best-effort (write errors silently ignored)

```bash
_log() {
    local level="$1"; shift
    local msg="[$HOOK_LOG_PREFIX] $level: $*"
    echo "$msg" >&2
    if [[ -d "$HOOK_LOG_DIR" ]]; then
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $msg" >> "$HOOK_LOG_FILE" 2>/dev/null || true
    fi
}
# HOOK_LOG_FILE set at script entry: "$HOOK_LOG_DIR/${HOOK_LOG_PREFIX}.$(date -u +%Y-%m-%dT%H:%M:%S).log"
```

**Rationale**: Per-invocation files eliminate write races between concurrent scripts (detect hook, poller, loader, 003's hooks). `rm -f` of old files during cleanup is idempotent and race-free. Single logging API works for all scripts regardless of fd state.

**Alternatives considered**:

- *Shared append-only hooks.log*: Concurrent rotation schemes (size/count-based) race between writers. POSIX O_APPEND is atomic for short lines but rotation (read-then-write) is not. Rejected for race safety.
- *Separate log API for poller*: Adds complexity for one script. Rejected.
- *stderr-only*: Poller loses all logging. Rejected.

## R-008: 003 Refactoring Impact Assessment

**Context**: Extracting `hook-common.sh` from `recovery-common.sh` requires modifying 003 files that are already implemented and deployed.

**Finding**: The refactoring touches:

1. `recovery-common.sh` — Remove shared functions, add `source "$HOME/bin/hook-common.sh"` at top
2. All 003 scripts that source `recovery-common.sh` — No changes needed (they still source `recovery-common.sh`, which now sources `hook-common.sh`)
3. `~/bin/` symlinks — Add `hook-common.sh` symlink

The refactoring is backwards-compatible: `recovery-common.sh` still exports all the same functions (shared ones via `hook-common.sh`, recovery-specific ones directly). No 003 script changes required.

**Decision**: Implement as a single atomic refactoring step before deploying any 002 scripts. Validate with 003's health-check after refactoring.

**Risk**: Low — the only change visible to 003 scripts is that shared functions come from `hook-common.sh` instead of being defined inline. Same functions, same signatures, same behavior. The `HOOK_LOG_PREFIX` variable defaults to `"hook"` but `recovery-common.sh` sets it to `"recovery"` before sourcing, preserving the existing log format.
