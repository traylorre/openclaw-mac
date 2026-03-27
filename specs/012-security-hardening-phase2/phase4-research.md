# Research Decisions: Security Remediation & Hardening Depth (Phase 4)

## Decision 1: Process Group Creation on macOS

**Decision**: Use bash `set -m` (job control mode) for process group creation + `kill -TERM -$pgid` for group termination.

**Rationale**: `setsid` is not available on macOS. The `set -m` approach is simplest and works natively in bash without external dependencies. When `set -m` is active, background processes (`cmd &`) get their own PGID equal to their PID. The Perl `POSIX::setsid()` approach requires fork-then-setsid to avoid EPERM (the calling process must not be a process group leader), adding complexity.

**Alternatives considered**:
- `perl -e 'use POSIX; fork and exit; POSIX::setsid(); exec @ARGV'` — works but adds fork overhead and perl dependency assumption
- `python3 -c 'import os; os.setsid()'` — same EPERM caveat, python3 dependency
- `pkill -P $pid` — only kills direct children, NOT recursive (grandchildren survive as orphans reparented to PID 1)

**Implementation**: In `integrity_run_with_timeout`:
```
set -m  # Enable job control
"$@" &  # Runs in its own process group (PGID = PID)
local pgid=$!
# On timeout: kill -TERM -$pgid; sleep 2; kill -KILL -$pgid
```

## Decision 2: Atomic File Operations

**Decision**: Create temp files in `~/.openclaw/tmp/` (mode 700) using `mktemp`, write content, then `mv` to target.

**Rationale**: macOS `mktemp` creates files with mode 0600 regardless of umask (hardcoded in `mkstemp(3)`). `mv` is atomic on APFS when source and destination are on the same volume (uses `rename(2)`). Creating temp files in a 700-owned directory eliminates symlink TOCTOU because attackers cannot create symlinks in a directory they cannot access. Bash has no access to `O_NOFOLLOW`.

**Alternatives considered**:
- Adjacent temp files (`mktemp "${output_file}.XXXXXX"`) — current approach, vulnerable to symlink attack in world-writable parent directories
- `/tmp` with symlink check — TOCTOU race between check and write, sticky bit only prevents deletion
- Python `O_NOFOLLOW` wrapper — adds external dependency for each write

## Decision 3: Per-File Durability (fsync)

**Decision**: Use `F_FULLFSYNC` via python3 for critical state files (manifest, lock-state). Accept best-effort for audit log entries.

**Rationale**: macOS `fsync()` only flushes to the drive's write cache, NOT to persistent media. `F_FULLFSYNC` (fcntl value 51) is the only way to guarantee data reaches physical storage. Python3 is available on macOS (`/usr/bin/python3`). The audit log is hash-chained, so a lost tail entry is detectable on the next write (prev_hash mismatch).

**Implementation**:
```bash
python3 -c "import os, fcntl; fd = os.open('$file', os.O_RDONLY); fcntl.fcntl(fd, 51); os.close(fd)"
```

**Alternatives considered**:
- `/usr/bin/sync` — system-wide flush, not per-file, no durability guarantee
- `os.fsync()` — does NOT guarantee physical media persistence on macOS
- Accept no durability — insufficient for forensic audit trail

## Decision 4: PID-Based Lock Validation

**Decision**: Store PID + process start time in lockfile. Validate both on stale check.

**Rationale**: macOS PID space is 0-99999 with max 4176 concurrent processes. PIDs recycle — on busy systems, within minutes. Checking only `kill -0 $pid` can return false positive if the PID has been recycled. Adding `ps -o lstart= -p $pid` (process start time) makes validation unique per PID incarnation.

**Implementation**:
```bash
# Write lock
mkdir "$lockdir" && echo "$$ $(ps -o lstart= -p $$)" > "$lockdir/pid"

# Validate lock
read lock_pid lock_start < "$lockdir/pid"
current_start=$(ps -o lstart= -p "$lock_pid" 2>/dev/null)
[[ "$current_start" == "$lock_start" ]] && echo "valid" || echo "stale"
```

**Alternatives considered**:
- PID only (`kill -0`) — false positives on PID recycling
- Symlink-based lock (`ln -s $$ lockfile`) — atomic, but can't store start time
- Age-based detection — current approach, has TOCTOU race

## Decision 5: Docker Socket Integrity Check

**Decision**: Verify Colima socket permissions (expected: 0600, user-owned) as a heuristic.

**Rationale**: Colima's socket is at `~/.colima/default/docker.sock` with mode 0600 owned by the user. This is more restrictive than Docker Desktop (root-owned with docker group). If the socket has unexpected permissions (e.g., world-writable), it indicates potential tampering. This is a heuristic — not proof of daemon integrity — but raises the bar.

**Alternatives considered**:
- Docker binary hash verification — useful but doesn't verify the daemon process
- Colima VM image verification — complex, requires understanding Colima internals
- Skip daemon verification — insufficient for the threat model

## Decision 6: Output Size Limiting

**Decision**: Use `head -c 1048576` (1MB) with SIGPIPE handling for docker exec output.

**Rationale**: `head -c` sends SIGPIPE to the writer when it closes, which docker exec handles gracefully. Truncation is detected by checking the pipeline exit status (141 = SIGPIPE). The limit applies to stdout only (stderr is typically small diagnostic output).

**Alternatives considered**:
- `dd bs=1M count=1` — silently truncates, harder to detect
- Custom read loop — adds latency and complexity
- No limit — OOM risk from compromised container

## Decision 7: JSON Validation Strategy

**Decision**: Combined validation+extraction in a single jq pass using error-raising expressions.

**Rationale**: A separate `jq -e empty` validation pass doubles CPU cost and doesn't validate structure (a bare string `"hello"` passes). Using `jq -e '.field // error("missing .field")'` validates structure AND extracts in one pass. If the input is not valid JSON, jq errors immediately.

**Alternatives considered**:
- Separate `jq -e empty` gate — doubles parsing, doesn't validate structure
- Python JSON validation — adds dependency, slower for small inputs
- No validation (`2>/dev/null || echo 0`) — current approach, produces false negatives

## Decision 8: Credential Passing to curl

**Decision**: Write API key to temp file in `~/.openclaw/tmp/` (mode 600), pass via `curl --config <file>`, delete via trap.

**Rationale**: Bash here-strings (`<<<`) create temporary files that are briefly visible via `lsof`. `curl --config -` with stdin redirection still creates a temp file. Writing to a controlled directory (mode 700) and passing the explicit file path to `curl --config` avoids both issues. Trap-based cleanup ensures deletion on all exit paths.

**Implementation**:
```bash
local tmpconf
tmpconf=$(mktemp "${HOME}/.openclaw/tmp/curl-XXXXXX")
trap 'rm -f "$tmpconf"' RETURN
printf 'header = "X-N8N-API-KEY: %s"\n' "$api_key" > "$tmpconf"
curl -s --config "$tmpconf" "$url" --max-time 10
```

**Alternatives considered**:
- Here-string (`<<<`) — creates temp file in /dev/shm or /tmp, briefly readable
- `curl -H` — API key visible in `ps` output
- Environment variable — visible in /proc/pid/environ on Linux (less relevant on macOS but still a leak vector)

## Decision 9: n8n Audit JSON Extraction

**Decision**: Use `grep -m1 -n '^[{[]'` to find first JSON line + `tail -n +$N` + jq validation.

**Rationale**: jq cannot process mixed text-and-JSON input natively. The n8n audit output includes a "Browser setup: skipped" preamble before JSON. A text extraction step is required before jq can parse. The current `sed -n '/^[{[]/,$p'` approach works but accepts injected JSON. Adding a jq validation gate after extraction ensures the extracted content is valid.

**Alternatives considered**:
- Pure jq — impossible with mixed text/JSON input
- Current sed approach — works but accepts injected JSON without validation
- Python JSON extractor — adds dependency

## Decision 10: Audit Log Action Validation

**Decision**: Regex validation (`^[a-z][a-z0-9_]{2,48}$`) rather than explicit allowlist.

**Rationale**: New action strings are frequently added (this phase alone adds ~8 new actions). An explicit allowlist requires code changes for each new action, creating maintenance burden. The regex prevents injection (no spaces, newlines, special characters) while allowing evolution. jq `--arg` handles escaping for the details field, preventing JSONL injection.

**Alternatives considered**:
- Explicit allowlist — more secure but high maintenance overhead
- No validation — current approach, allows log injection
- Allowlist with fallback to regex for unknown actions — complex, marginal benefit
