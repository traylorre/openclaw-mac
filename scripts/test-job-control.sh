#!/usr/bin/env bash
# test-job-control.sh — Validate set -m job control on macOS for process group isolation
# Phase 4, T001: Tests that set -m + kill -TERM -$pgid works correctly
# If any test fails, documents fallback to Perl POSIX::setsid()

PASS=0
FAIL=0

log_test() { echo "  TEST: $1"; }
log_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
log_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== Job Control Validation (macOS $(sw_vers -productVersion 2>/dev/null || echo 'unknown')) ==="
echo ""

# --- Test 1: set -m creates new process group ---
log_test "set -m + background creates new process group (PGID = PID)"
set -m 2>/dev/null
sleep 3600 &
T1_PID=$!
T1_PGID=$(ps -o pgid= -p "$T1_PID" 2>/dev/null | tr -d ' ')
kill "$T1_PID" 2>/dev/null; wait "$T1_PID" 2>/dev/null || true
set +m 2>/dev/null
if [[ "$T1_PGID" == "$T1_PID" ]]; then
    log_pass "PGID equals PID for background process under set -m"
else
    log_fail "PGID ($T1_PGID) does not equal PID ($T1_PID)"
fi

# --- Test 2: kill -TERM -$pgid kills entire process group ---
log_test "kill -TERM -\$pgid kills entire process group"
set -m 2>/dev/null
# Spawn a script that creates child sleeps then waits forever
bash -c 'sleep 3600 & sleep 3600 & sleep 3600 & sleep 3600' &
T2_PID=$!
sleep 0.3
T2_CHILDREN_BEFORE=$(pgrep -g "$T2_PID" 2>/dev/null | wc -l | tr -d ' ')
kill -TERM -"$T2_PID" 2>/dev/null || true
sleep 0.5
kill -KILL -"$T2_PID" 2>/dev/null || true
wait "$T2_PID" 2>/dev/null || true
T2_CHILDREN_AFTER=$(pgrep -g "$T2_PID" 2>/dev/null | wc -l | tr -d ' ')
set +m 2>/dev/null
if [[ "${T2_CHILDREN_BEFORE:-0}" -gt 0 && "${T2_CHILDREN_AFTER:-0}" -eq 0 ]]; then
    log_pass "All group members killed (${T2_CHILDREN_BEFORE} before, ${T2_CHILDREN_AFTER} after)"
else
    log_fail "Group kill incomplete (${T2_CHILDREN_BEFORE:-?} before, ${T2_CHILDREN_AFTER:-?} after)"
fi

# --- Test 3: set -m inside function does NOT affect caller ---
log_test "set -m inside function does not affect caller's job control mode"
_inner_func() {
    set -m 2>/dev/null
    sleep 0.01 &
    wait $! 2>/dev/null || true
    set +m 2>/dev/null
}
T3_BEFORE=$(set -o | grep monitor | awk '{print $2}')
_inner_func
T3_AFTER=$(set -o | grep monitor | awk '{print $2}')
if [[ "$T3_BEFORE" == "$T3_AFTER" ]]; then
    log_pass "Caller job control state preserved after function with set -m"
else
    log_fail "Caller job control state changed by function's set -m"
fi

# --- Test 4: Nested set -m contexts ---
log_test "Nested set -m contexts behave predictably"
set -m 2>/dev/null
(
    set -m 2>/dev/null
    sleep 3600 &
    INNER_PID=$!
    INNER_PGID=$(ps -o pgid= -p "$INNER_PID" 2>/dev/null | tr -d ' ')
    kill "$INNER_PID" 2>/dev/null; wait "$INNER_PID" 2>/dev/null || true
    set +m 2>/dev/null
    [[ "$INNER_PGID" == "$INNER_PID" ]] && exit 0 || exit 1
) 2>/dev/null
T4_RC=$?
set +m 2>/dev/null
if [[ $T4_RC -eq 0 ]]; then
    log_pass "Nested set -m contexts create independent process groups"
else
    log_fail "Nested set -m contexts do not work correctly"
fi

# --- Test 5: Interaction with set -euo pipefail and trap handlers ---
log_test "set -m works with set -euo pipefail and trap handlers"
(
    set -euo pipefail
    trap 'true' EXIT
    set -m 2>/dev/null
    sleep 0.01 &
    wait $! 2>/dev/null || true
    set +m 2>/dev/null
    exit 0
) 2>/dev/null
if [[ $? -eq 0 ]]; then
    log_pass "set -m compatible with set -euo pipefail + trap handlers"
else
    log_fail "set -m conflicts with set -euo pipefail or trap handlers"
fi

# --- Test 6: set -m works inside subshells ---
log_test "set -m works inside subshells (for monitor heartbeat/poll loops)"
(
    set -m 2>/dev/null
    sleep 3600 &
    SUB_PID=$!
    SUB_PGID=$(ps -o pgid= -p "$SUB_PID" 2>/dev/null | tr -d ' ')
    kill "$SUB_PID" 2>/dev/null; wait "$SUB_PID" 2>/dev/null || true
    set +m 2>/dev/null
    [[ "$SUB_PGID" == "$SUB_PID" ]] && exit 0 || exit 1
) 2>/dev/null
if [[ $? -eq 0 ]]; then
    log_pass "set -m functions correctly in subshells"
else
    log_fail "set -m does not work in subshells"
fi

# --- Summary ---
echo ""
echo "=== Results ==="
echo "  Passed: ${PASS}"
echo "  Failed: ${FAIL}"
echo ""

if [[ $FAIL -gt 0 ]]; then
    echo "WARNING: Some tests failed. Fallback to Perl POSIX::setsid() recommended."
    echo ""
    echo "Perl fallback command:"
    echo "  perl -e 'use POSIX; fork and exit; POSIX::setsid(); exec @ARGV' -- \"\$@\""
    echo ""
    echo "Update phase4-research.md Decision 1 to note Perl fallback needed."
    exit 1
else
    echo "All tests passed. set -m is safe for production use on this platform."
    exit 0
fi
