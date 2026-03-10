# Data Model: Context Guardian Auto-Rotation

**Feature**: 002-context-auto-rotation
**Date**: 2026-03-10

## Entities

### CARRYOVER File

**Path**: `specs/<branch>/CONTEXT-CARRYOVER-NN.md`
**Written by**: Model (via Write tool call — out of scope for 002)
**Lifecycle**: Created by model → detected by PostToolUse hook → loaded by SessionStart hook → renamed to `.loaded`

002 does not control this file's content — it only detects, transports, and loads it.

| Attribute | Value |
|-----------|-------|
| Filename pattern | `/^CONTEXT-CARRYOVER-[0-9]{2}\.md$/` (case-sensitive, FR-001) |
| Sequence range | 00–99 |
| Max size before truncation | 80KB (FR-019) |
| Min meaningful size | 100 bytes (FR-022), smaller treated as empty |
| Encoding | UTF-8 markdown |
| Selection rule | Highest NN among unconsumed files (FR-026) |
| Location | Active spec directory: `specs/${branch_name}/` |

### Consumed Marker (.loaded)

**Path**: `specs/<branch>/CONTEXT-CARRYOVER-NN.md.loaded`
**Created by**: `carryover-loader.sh` (atomic rename from CARRYOVER file)
**Lifecycle**: Created on consumption → oldest pruned to keep ≤5 (FR-021)

| Attribute | Value |
|-----------|-------|
| Filename | Original name + `.loaded` suffix |
| Content | Unchanged from original CARRYOVER file |
| Retention | 5 most recent by mtime, oldest deleted first (FR-021) |
| FR-032 role | mtime ≤60s indicates recent load (double-/clear guard) |
| Protected by | Signal traps undo rename on SIGTERM/SIGINT/SIGHUP (FR-025) |

### Signal: carryover-pending

**Path**: `.claude/carryover-pending`
**Written by**: `carryover-detect.sh` (PostToolUse hook)
**Lifecycle**: Created before `continue:false` → consumed by poller (`mv` → `.claimed`) or loader (`rm`)

| Attribute | Value |
|-----------|-------|
| Content | Empty file (presence is the signal) |
| Permissions | Default (not sensitive data) |
| Purpose | Rotation initiated, /clear expected |
| Consumed by | Poller: `mv` to `.claimed`; Loader: `rm` after processing |
| Orphan risk | Sub-ms window if hook crashes between write and JSON output (Q40, accepted) |

### Signal: carryover-pending.claimed

**Path**: `.claude/carryover-pending.claimed`
**Written by**: `carryover-poller.sh` (atomic `mv` from `carryover-pending`)
**Lifecycle**: Created by poller claim → deleted by EXIT trap → cleaned on startup (FR-029)

| Attribute | Value |
|-----------|-------|
| Content | Empty file (renamed from carryover-pending) |
| Purpose | Poller has claimed ownership of sending /clear |
| Cleanup (normal) | EXIT trap deletes on all termination paths (except SIGKILL) |
| Cleanup (stale) | Loader deletes on `startup` events (FR-029, defense against SIGKILL) |

### Signal: carryover-clear-needed

**Path**: `.claude/carryover-clear-needed`
**Written by**: `carryover-poller.sh` (on 60s timeout or capture-pane failure)
**Lifecycle**: Created on poller failure → consumed by loader on `startup`

| Attribute | Value |
|-----------|-------|
| Content | Empty file (presence is the signal) |
| Purpose | Poller failed — user must type /clear manually |
| Consumed by | Loader on `startup`: injects reminder, deletes file (FR-030) |

### Signal: recovery-marker.json (read-only by 002)

**Path**: `.claude/recovery-marker.json`
**Owned by**: Feature 003 (compaction-recovery)
**002's interaction**: Existence check only (FR-016)

002 checks for this file in two places: (1) PostToolUse hook suppresses the entire auto-clear cycle (FR-016), (2) SessionStart loader suppresses carryover injection on `compact` events (FR-033). If present, 003 owns the lifecycle during active recovery. 002 never writes, modifies, or deletes this file.

## State Transitions

### PostToolUse Hook (carryover-detect.sh)

```text
stdin JSON
  → validate tool_name exists (exit 0 if null)
  → fast-path: tool_name != "Write" and != "Edit" → exit 0
  → extract basename from tool_input.file_path
  → regex match /^CONTEXT-CARRYOVER-[0-9]{2}\.md$/ → exit 0 if no match
  → check .claude/recovery-marker.json → exit 0 if present (FR-016)
  → mkdir -p .claude
  → write .claude/carryover-pending
  → if $TMUX set: spawn poller (detached, passing $TMUX_PANE)
  → output {continue:false, stopReason:...} to stdout
```

### Poller (carryover-poller.sh)

```text
start
  → install EXIT trap: rm -f .claude/carryover-pending.claimed
  → record start_time
  → LOOP:
      → tmux capture-pane -p -t "$TMUX_PANE"
      → if capture fails → write carryover-clear-needed → exit 1
      → strip ANSI codes
      → scan for 3-line pattern (separator/prompt/separator)
      → if no match:
          → if elapsed >= 60s → write carryover-clear-needed → exit 1
          → sleep 1 → LOOP
      → if match:
          → mv carryover-pending → carryover-pending.claimed
          → if mv fails → exit 0 (user already typed /clear)
          → if mv succeeds:
              → send banner via tmux send-keys
              → send /clear via tmux send-keys
              → exit 0 (trap cleans .claimed)
```

### Loader (carryover-loader.sh)

```text
SessionStart event (clear | compact | startup)
  → validate jq (exit 2 if missing)
  → install signal traps (SIGTERM/SIGINT/SIGHUP → undo .loaded rename)
  → parse source from stdin JSON

  → if startup:
      → FR-029: rm -f .claude/carryover-pending.claimed
      → FR-030: if carryover-clear-needed exists → collect reminder, rm file
      → FR-022: if carryover-pending exists → check for CARRYOVER below

  → if clear:
      → FR-032: check .loaded mtime ≤60s in spec dir
      → if recent .loaded + no unconsumed CARRYOVER + no pending → exit 0 (double-/clear)

  → derive spec_dir from git branch --show-current
  → if branch empty (detached HEAD) → log warn, exit 0
  → if spec_dir doesn't exist → log warn, exit 0

  → search for unconsumed CONTEXT-CARRYOVER-NN.md files
  → if none found:
      → if carryover-pending exists → inject "expected but missing" warning, rm pending
      → else → exit 0 (normal /clear)
  → select highest NN

  → if file < 100 bytes → rename to .loaded, inject empty-file warning
  → if file > 80KB → tail-truncate to 80KB, drop partial first line
  → read file contents

  → rename to .loaded (protected by signal traps)
  → wrap in preamble (--- CARRYOVER CONTEXT --- ... --- END CARRYOVER CONTEXT ---)
  → output via jq: {hookSpecificOutput:{additionalContext:$ctx}}

  → cleanup: rm carryover-pending if present
  → prune .loaded files beyond 5 most recent (FR-021)
```

### Signal File Lifecycle

```text
                          carryover-detect.sh writes
                                    │
                                    ▼
                          carryover-pending
                           /              \
                    poller mv          loader rm (on startup/clear)
                      /                      \
           carryover-pending.claimed     (deleted)
                      │
                 EXIT trap rm
                      │
                 (deleted)

    Timeout/failure path:
    poller writes → carryover-clear-needed → loader rm on startup → (deleted)
```

## Directory Layout (Runtime)

```text
.claude/
├── carryover-pending              # Transient (rotation in progress)
├── carryover-pending.claimed      # Transient (poller owns /clear)
├── carryover-clear-needed         # Transient (poller failed)
├── recovery-marker.json           # 003's marker (002 reads only, never writes)
└── recovery-logs/
    └── *.log                      # Per-invocation timestamped log files (7-day retention, shared 002+003)

specs/<branch>/
├── CONTEXT-CARRYOVER-01.md        # Unconsumed carryover (model writes)
├── CONTEXT-CARRYOVER-02.md        # Unconsumed carryover
├── CONTEXT-CARRYOVER-01.md.loaded # Consumed (renamed by loader)
└── ...
```

## Relationships

```text
Model (Write tool) ──creates──► CARRYOVER File

PostToolUse hook ──detects──► CARRYOVER File (basename match)
                 ──reads──► recovery-marker.json (suppress check)
                 ──creates──► carryover-pending
                 ──spawns──► Poller

Poller ──claims──► carryover-pending (mv → .claimed)
       ──sends──► /clear (tmux)
       ──creates──► carryover-clear-needed (on failure)

SessionStart hook ──reads──► carryover-pending (warning trigger)
                  ──reads──► carryover-clear-needed (reminder trigger)
                  ──reads──► CARRYOVER File (load contents)
                  ──renames──► CARRYOVER File → .loaded
                  ──deletes──► carryover-pending, carryover-clear-needed, stale .claimed
                  ──prunes──► old .loaded files (keep 5)
                  ──outputs──► additionalContext (via jq)
```
