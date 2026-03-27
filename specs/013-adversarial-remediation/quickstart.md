# Quickstart: Verifying Phase 4B Remediation

**Branch**: `013-adversarial-remediation` | **Date**: 2026-03-26

Operator-facing verification steps. Run each after implementation to confirm the fix is working.

---

## 1. Timeout Verification

Confirm every Docker CLI call is timeout-bounded and no operation hangs against an unresponsive daemon.

```bash
# Point Docker at a nonexistent socket (simulates hung daemon)
DOCKER_HOST=unix:///nonexistent make integrity-verify
```

**Expected**: Pipeline completes with FAIL/SKIP results (not hangs) within 60 seconds. Time it:

```bash
time DOCKER_HOST=unix:///nonexistent make integrity-verify
```

**Pass criteria**: Wall clock < 60s. Every Docker-related check reports timeout or connection error, not silence.

**Audit all Docker calls are wrapped**:

```bash
grep -rn '\bdocker\b' scripts/ | grep -v 'integrity_run_with_timeout' | grep -v '^.*:#'
```

**Pass criteria**: Zero lines returned (all Docker calls wrapped or in comments).

---

## 2. Trap Preservation

Confirm library functions do not clobber the caller's ERR trap.

```bash
source scripts/lib/integrity.sh

# Set a caller ERR trap
trap 'echo CALLER_ERR_TRAP_ACTIVE' ERR

# Call the function that previously clobbered ERR
_integrity_safe_atomic_write /tmp/trap-test-$$ "test content"

# Verify caller trap is still set
trap -p ERR | grep -q 'CALLER_ERR_TRAP_ACTIVE' && echo "PASS: ERR trap preserved" || echo "FAIL: ERR trap clobbered"

# Cleanup
rm -f /tmp/trap-test-$$
trap - ERR
```

**Pass criteria**: Output includes `PASS: ERR trap preserved`.

---

## 3. Lock Crash Recovery

Confirm no stale lock persists after a crash during audit log write.

```bash
LOCKDIR="${HOME}/.openclaw/integrity-audit.log.lock"

# Start an audit write in background, then kill it
(
  source scripts/lib/integrity.sh
  integrity_audit_log "crash-test-entry" &
  sleep 0.1
  kill -TERM $!
  wait $! 2>/dev/null
)

# Check for stale lock
if [[ -d "$LOCKDIR" ]]; then
    echo "FAIL: Stale lock remains at $LOCKDIR"
    # Check if PID inside is dead
    if [[ -f "$LOCKDIR/pid" ]]; then
        stale_pid=$(cat "$LOCKDIR/pid")
        kill -0 "$stale_pid" 2>/dev/null && echo "  Lock holder PID $stale_pid is alive" || echo "  Lock holder PID $stale_pid is dead (stale lock)"
    fi
else
    echo "PASS: No stale lock after crash"
fi
```

**Pass criteria**: Output includes `PASS: No stale lock after crash`.

**Concurrent write test** (hash chain integrity):

```bash
# Run 10 concurrent writers, 10 entries each
for i in $(seq 1 10); do
    (
        source scripts/lib/integrity.sh
        for j in $(seq 1 10); do
            integrity_audit_log "concurrent-test-p${i}-e${j}"
        done
    ) &
done
wait

# Verify hash chain
scripts/integrity-verify.sh --audit-chain-only
```

**Pass criteria**: Hash chain valid, 100 entries written, zero corruption.

---

## 4. TMPDIR Traversal Rejection

Confirm path traversal attempts are rejected.

```bash
source scripts/lib/integrity.sh

# These must ALL be rejected
for path in \
    "/var/folders/ab/x/T/../../etc/shadow" \
    "/var/folders/../../../tmp" \
    "/tmp/../etc/passwd" \
    "/var/folders/Xb/abc123/T/foo/../../.." \
    "/var/folders/Xb/abc123/T/.."; do

    TMPDIR="$path" _integrity_init_tmp_dir 2>/dev/null
    if [[ $? -ne 0 ]]; then
        echo "PASS: Rejected $path"
    else
        echo "FAIL: Accepted $path"
    fi
done

# This must be accepted
TMPDIR="/var/folders/Xb/abc123def/T" _integrity_init_tmp_dir 2>/dev/null
if [[ $? -eq 0 ]]; then
    echo "PASS: Accepted valid path"
else
    echo "FAIL: Rejected valid path"
fi
```

**Pass criteria**: All traversal paths rejected, valid path accepted.

---

## 5. Credential Opacity

Confirm no secrets appear in process listings during verification.

**Terminal 1** (monitor):

```bash
# Watch for any openssl or curl processes with key material
while true; do
    ps aux | grep -E '(openssl|curl)' | grep -v grep
    sleep 0.1
done
```

**Terminal 2** (run verification):

```bash
make integrity-verify
```

**Pass criteria in Terminal 1**:
- No HMAC key material visible in openssl process arguments
- No API keys visible in curl process arguments
- Curl processes show `--config /path/to/tmpfile` instead of `-H "X-N8N-API-KEY: ..."`

**Automated check** (run alongside verify):

```bash
make integrity-verify &
verify_pid=$!
while kill -0 "$verify_pid" 2>/dev/null; do
    if ps aux | grep -v grep | grep -qE '(-hmac |X-N8N-API-KEY)'; then
        echo "FAIL: Credential visible in process listing"
        break
    fi
    sleep 0.05
done
wait "$verify_pid"
echo "PASS: No credentials observed in process listings"
```

---

## 6. Process Group Verification

Confirm timeout kills only the target process group with zero survivors.

```bash
source scripts/lib/integrity.sh

# Run a command that spawns children, with a short timeout
integrity_run_with_timeout 2 bash -c 'sleep 100 & sleep 100 & wait'

# Check for survivors (the sleep processes)
sleep 0.5
survivors=$(pgrep -f 'sleep 100' | wc -l | tr -d ' ')
if [[ "$survivors" -eq 0 ]]; then
    echo "PASS: 0 survivors after timeout"
else
    echo "FAIL: $survivors survivor(s) after timeout"
    pgrep -af 'sleep 100'
fi
```

**Pass criteria**: `PASS: 0 survivors after timeout`. Exit code from `integrity_run_with_timeout` is 124 (timeout).

**Subshell context test** (verifies fallback to pkill -P):

```bash
source scripts/lib/integrity.sh

# Run inside a pipeline where set -m may not create a new PGID
echo "trigger" | (
    integrity_run_with_timeout 2 bash -c 'sleep 100 & sleep 100 & wait'
)

sleep 0.5
survivors=$(pgrep -f 'sleep 100' | wc -l | tr -d ' ')
if [[ "$survivors" -eq 0 ]]; then
    echo "PASS: Fallback killing worked in subshell context"
else
    echo "FAIL: $survivors survivor(s) in subshell context"
    pkill -f 'sleep 100'  # cleanup
fi
```

**Pass criteria**: `PASS: Fallback killing worked in subshell context`.
