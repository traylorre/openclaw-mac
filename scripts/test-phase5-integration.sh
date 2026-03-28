#!/usr/bin/env bash
# test-phase5-integration.sh — Phase 5 integration tests (T046)
# Validates pipeline security hardening checks from 014-pipeline-security-hardening
# Phases 4-7 check functions in hardening-audit.sh

# --- Bash 5.x auto-detect (sudo + macOS /bin/bash = 3.x) ---
if [[ "${BASH_VERSINFO[0]}" -lt 5 ]]; then
    for _try_bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        if [[ -x "$_try_bash" ]]; then exec "$_try_bash" "$0" "$@"; fi
    done
    echo "Error: bash 5.x required. Install: brew install bash" >&2; exit 2
fi

set -uo pipefail
# Note: set -e intentionally omitted — tests need to handle non-zero exits

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Source hardening-audit.sh without running main ---
# We source a modified copy that has the final "main "$@"" call stripped,
# so all functions and globals are defined but the audit does not execute.

# Source common.sh and integrity.sh first (needed by check_pipeline_env_vars)
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || true
# shellcheck source=lib/integrity.sh
source "${SCRIPT_DIR}/lib/integrity.sh" 2>/dev/null || true

# Source hardening-audit.sh with the trailing "main "$@"" call removed.
# The temp copy must live alongside hardening-audit.sh so that its internal
# SCRIPT_DIR (derived from BASH_SOURCE[0]) resolves to the scripts/ dir,
# allowing its own source calls (browser-registry.sh, lib/cve-registry.sh)
# to find their targets.
_audit_tmp="${SCRIPT_DIR}/.hardening-audit-test-$$.sh"
sed '$d' "${SCRIPT_DIR}/hardening-audit.sh" > "$_audit_tmp"
# shellcheck disable=SC1090
source "$_audit_tmp"
rm -f "$_audit_tmp"
unset _audit_tmp

# hardening-audit.sh enables set -e; disable it for our test harness
# (tests need to handle non-zero exits from check functions)
set +e

# Force JSON mode to suppress terminal output from report_result
JSON_OUTPUT=true

REPO_ROOT="$(resolve_repo_root "$SCRIPT_DIR")"

# --- Test Harness ---
T_PASS=0
T_FAIL=0
T_SKIP=0

log_test() { echo ""; echo "=== TEST: $1 ==="; }
log_pass() { echo "  PASS: $1"; T_PASS=$((T_PASS + 1)); }
log_fail() { echo "  FAIL: $1"; T_FAIL=$((T_FAIL + 1)); }
log_skip() { echo "  SKIP: $1"; T_SKIP=$((T_SKIP + 1)); }

# Helper: reset report_result accumulators between test runs
reset_audit_state() {
    TOTAL=0
    PASS_COUNT=0
    FAIL_COUNT=0
    WARN_COUNT=0
    SKIP_COUNT=0
    JSON_RESULTS="[]"
    CURRENT_SECTION=""
    FAIL_SUMMARIES=()
    WARN_ACTIONABLE=()
    WARN_OPTIONAL=()
    CHECK_RESULTS=()
}

# Helper: count results with a given ID prefix in JSON_RESULTS
count_results_with_prefix() {
    local prefix="$1"
    echo "$JSON_RESULTS" | jq --arg pfx "$prefix" '[.[] | select(.id | startswith($pfx))] | length' 2>/dev/null || echo 0
}

# Helper: get status of a specific check ID from JSON_RESULTS
get_result_status() {
    local id="$1"
    echo "$JSON_RESULTS" | jq -r --arg id "$id" '[.[] | select(.id == $id)][0].status // "MISSING"' 2>/dev/null || echo "MISSING"
}

# --- Test 1: check_pipeline_cve_n8n exists and is callable ---
test_cve_n8n() {
    log_test "T046-01: check_pipeline_cve_n8n exists and is callable"

    if [[ "$(type -t check_pipeline_cve_n8n)" == "function" ]]; then
        log_pass "check_pipeline_cve_n8n is a defined function"
    else
        log_fail "check_pipeline_cve_n8n is not a function (type: $(type -t check_pipeline_cve_n8n 2>/dev/null || echo 'undefined'))"
        return
    fi

    # Run it and verify it produces a result with the expected ID prefix
    reset_audit_state
    check_pipeline_cve_n8n 2>/dev/null || true
    local count
    count=$(count_results_with_prefix "CHK-PIPELINE-CVE-N8N")
    if [[ "$count" -ge 1 ]]; then
        log_pass "check_pipeline_cve_n8n produced ${count} result(s) with CHK-PIPELINE-CVE-N8N prefix"
    else
        log_fail "check_pipeline_cve_n8n produced 0 results with CHK-PIPELINE-CVE-N8N prefix"
    fi
}

# --- Test 2: check_pipeline_cve_openclaw exists ---
test_cve_openclaw() {
    log_test "T046-02: check_pipeline_cve_openclaw exists and is callable"

    if [[ "$(type -t check_pipeline_cve_openclaw)" == "function" ]]; then
        log_pass "check_pipeline_cve_openclaw is a defined function"
    else
        log_fail "check_pipeline_cve_openclaw is not a function"
        return
    fi

    reset_audit_state
    check_pipeline_cve_openclaw 2>/dev/null || true
    local count
    count=$(count_results_with_prefix "CHK-PIPELINE-CVE-OPENCLAW")
    if [[ "$count" -ge 1 ]]; then
        log_pass "check_pipeline_cve_openclaw produced ${count} result(s)"
    else
        log_fail "check_pipeline_cve_openclaw produced 0 results"
    fi
}

# --- Test 3: check_pipeline_cve_ollama exists ---
test_cve_ollama() {
    log_test "T046-03: check_pipeline_cve_ollama exists and is callable"

    if [[ "$(type -t check_pipeline_cve_ollama)" == "function" ]]; then
        log_pass "check_pipeline_cve_ollama is a defined function"
    else
        log_fail "check_pipeline_cve_ollama is not a function"
        return
    fi

    reset_audit_state
    check_pipeline_cve_ollama 2>/dev/null || true
    local count
    count=$(count_results_with_prefix "CHK-PIPELINE-CVE-OLLAMA")
    if [[ "$count" -ge 1 ]]; then
        log_pass "check_pipeline_cve_ollama produced ${count} result(s)"
    else
        log_fail "check_pipeline_cve_ollama produced 0 results"
    fi
}

# --- Test 4: check_pipeline_hmac_consistency exists ---
test_hmac_consistency() {
    log_test "T046-04: check_pipeline_hmac_consistency exists and is callable"

    if [[ "$(type -t check_pipeline_hmac_consistency)" == "function" ]]; then
        log_pass "check_pipeline_hmac_consistency is a defined function"
    else
        log_fail "check_pipeline_hmac_consistency is not a function"
        return
    fi

    reset_audit_state
    check_pipeline_hmac_consistency 2>/dev/null || true
    local count
    count=$(count_results_with_prefix "CHK-PIPELINE-HMAC")
    if [[ "$count" -ge 1 ]]; then
        log_pass "check_pipeline_hmac_consistency produced ${count} result(s)"
    else
        log_fail "check_pipeline_hmac_consistency produced 0 results"
    fi
}

# --- Test 5: check_sensitive_file_protections exists and produces output ---
test_sensitive_file_protections() {
    log_test "T046-05: check_sensitive_file_protections exists and produces output"

    if [[ "$(type -t check_sensitive_file_protections)" == "function" ]]; then
        log_pass "check_sensitive_file_protections is a defined function"
    else
        log_fail "check_sensitive_file_protections is not a function"
        return
    fi

    reset_audit_state
    check_sensitive_file_protections 2>/dev/null || true
    local count
    count=$(count_results_with_prefix "CHK-SENSITIVE-FILE")
    if [[ "$count" -ge 1 ]]; then
        log_pass "check_sensitive_file_protections produced ${count} result(s) with CHK-SENSITIVE-FILE prefix"
    else
        log_fail "check_sensitive_file_protections produced 0 results"
    fi
}

# --- Test 6: check_lock_state_signed exists ---
test_lock_state_signed() {
    log_test "T046-06: check_lock_state_signed exists and is callable"

    if [[ "$(type -t check_lock_state_signed)" == "function" ]]; then
        log_pass "check_lock_state_signed is a defined function"
    else
        log_fail "check_lock_state_signed is not a function"
        return
    fi

    reset_audit_state
    check_lock_state_signed 2>/dev/null || true
    local count
    count=$(count_results_with_prefix "CHK-SENSITIVE-LOCKSTATE")
    if [[ "$count" -ge 1 ]]; then
        log_pass "check_lock_state_signed produced ${count} result(s)"
    else
        log_fail "check_lock_state_signed produced 0 results"
    fi
}

# --- Test 7: check_heartbeat_signed exists ---
test_heartbeat_signed() {
    log_test "T046-07: check_heartbeat_signed exists and is callable"

    if [[ "$(type -t check_heartbeat_signed)" == "function" ]]; then
        log_pass "check_heartbeat_signed is a defined function"
    else
        log_fail "check_heartbeat_signed is not a function"
        return
    fi

    reset_audit_state
    check_heartbeat_signed 2>/dev/null || true
    local count
    count=$(count_results_with_prefix "CHK-SENSITIVE-HEARTBEAT")
    if [[ "$count" -ge 1 ]]; then
        log_pass "check_heartbeat_signed produced ${count} result(s)"
    else
        log_fail "check_heartbeat_signed produced 0 results"
    fi
}

# --- Test 8: check_asi_controls produces 10 CHK-ASI-* results ---
test_asi_controls() {
    log_test "T046-08: check_asi_controls produces 10 CHK-ASI-* results"

    if [[ "$(type -t check_asi_controls)" == "function" ]]; then
        log_pass "check_asi_controls is a defined function"
    else
        log_fail "check_asi_controls is not a function"
        return
    fi

    reset_audit_state
    # ASI controls aggregates prior check results, so they will all be SKIP
    # without upstream checks. That is fine — we just verify 10 results appear.
    check_asi_controls 2>/dev/null || true
    local count
    count=$(count_results_with_prefix "CHK-ASI-")
    if [[ "$count" -eq 10 ]]; then
        log_pass "check_asi_controls produced exactly 10 CHK-ASI-* results"
    else
        log_fail "check_asi_controls produced ${count} CHK-ASI-* results (expected 10)"
    fi
}

# --- Test 9: check_defense_layer_prevent exists ---
test_defense_prevent() {
    log_test "T046-09: check_defense_layer_prevent exists and is callable"

    if [[ "$(type -t check_defense_layer_prevent)" == "function" ]]; then
        log_pass "check_defense_layer_prevent is a defined function"
    else
        log_fail "check_defense_layer_prevent is not a function"
        return
    fi

    reset_audit_state
    check_defense_layer_prevent 2>/dev/null || true
    local count
    count=$(count_results_with_prefix "CHK-DEFENSE-PREVENT")
    if [[ "$count" -ge 1 ]]; then
        log_pass "check_defense_layer_prevent produced ${count} result(s)"
    else
        log_fail "check_defense_layer_prevent produced 0 results"
    fi
}

# --- Test 10: check_defense_layer_contain exists ---
test_defense_contain() {
    log_test "T046-10: check_defense_layer_contain exists and is callable"

    if [[ "$(type -t check_defense_layer_contain)" == "function" ]]; then
        log_pass "check_defense_layer_contain is a defined function"
    else
        log_fail "check_defense_layer_contain is not a function"
        return
    fi

    reset_audit_state
    check_defense_layer_contain 2>/dev/null || true
    local count
    count=$(count_results_with_prefix "CHK-DEFENSE-CONTAIN")
    if [[ "$count" -ge 1 ]]; then
        log_pass "check_defense_layer_contain produced ${count} result(s)"
    else
        log_fail "check_defense_layer_contain produced 0 results"
    fi
}

# --- Test 11: check_defense_layer_detect exists ---
test_defense_detect() {
    log_test "T046-11: check_defense_layer_detect exists and is callable"

    if [[ "$(type -t check_defense_layer_detect)" == "function" ]]; then
        log_pass "check_defense_layer_detect is a defined function"
    else
        log_fail "check_defense_layer_detect is not a function"
        return
    fi

    reset_audit_state
    check_defense_layer_detect 2>/dev/null || true
    local count
    count=$(count_results_with_prefix "CHK-DEFENSE-DETECT")
    if [[ "$count" -ge 1 ]]; then
        log_pass "check_defense_layer_detect produced ${count} result(s)"
    else
        log_fail "check_defense_layer_detect produced 0 results"
    fi
}

# --- Test 12: check_defense_layer_respond exists ---
test_defense_respond() {
    log_test "T046-12: check_defense_layer_respond exists and is callable"

    if [[ "$(type -t check_defense_layer_respond)" == "function" ]]; then
        log_pass "check_defense_layer_respond is a defined function"
    else
        log_fail "check_defense_layer_respond is not a function"
        return
    fi

    reset_audit_state
    check_defense_layer_respond 2>/dev/null || true
    local count
    count=$(count_results_with_prefix "CHK-DEFENSE-RESPOND")
    if [[ "$count" -ge 1 ]]; then
        log_pass "check_defense_layer_respond produced ${count} result(s)"
    else
        log_fail "check_defense_layer_respond produced 0 results"
    fi
}

# --- Test 13: check_defense_layer_recover exists ---
test_defense_recover() {
    log_test "T046-13: check_defense_layer_recover exists and is callable"

    if [[ "$(type -t check_defense_layer_recover)" == "function" ]]; then
        log_pass "check_defense_layer_recover is a defined function"
    else
        log_fail "check_defense_layer_recover is not a function"
        return
    fi

    reset_audit_state
    check_defense_layer_recover 2>/dev/null || true
    local count
    count=$(count_results_with_prefix "CHK-DEFENSE-RECOVER")
    if [[ "$count" -ge 1 ]]; then
        log_pass "check_defense_layer_recover produced ${count} result(s)"
    else
        log_fail "check_defense_layer_recover produced 0 results"
    fi
}

# --- Test 14: check_pipeline_env_vars produces PASS when no dangerous vars set ---
test_env_vars() {
    log_test "T046-14: check_pipeline_env_vars produces PASS in clean environment"

    if [[ "$(type -t check_pipeline_env_vars)" == "function" ]]; then
        log_pass "check_pipeline_env_vars is a defined function"
    else
        log_fail "check_pipeline_env_vars is not a function"
        return
    fi

    # Save and unset any potentially dangerous env vars
    local orig_ld_preload="${LD_PRELOAD:-}"
    local orig_ld_library_path="${LD_LIBRARY_PATH:-}"
    local orig_dyld_insert="${DYLD_INSERT_LIBRARIES:-}"
    local orig_bash_env="${BASH_ENV:-}"
    local orig_env="${ENV:-}"
    unset LD_PRELOAD LD_LIBRARY_PATH DYLD_INSERT_LIBRARIES BASH_ENV ENV 2>/dev/null || true

    reset_audit_state
    check_pipeline_env_vars 2>/dev/null || true

    local status
    status=$(get_result_status "CHK-PIPELINE-ENV-VARS")

    if [[ "$status" == "PASS" ]]; then
        log_pass "check_pipeline_env_vars returned PASS in clean environment"
    elif [[ "$status" == "SKIP" ]]; then
        log_skip "check_pipeline_env_vars returned SKIP (integrity_check_env_vars not available)"
    else
        log_fail "check_pipeline_env_vars returned ${status} in clean environment (expected PASS)"
    fi

    # Restore env vars
    [[ -n "$orig_ld_preload" ]] && export LD_PRELOAD="$orig_ld_preload"
    [[ -n "$orig_ld_library_path" ]] && export LD_LIBRARY_PATH="$orig_ld_library_path"
    [[ -n "$orig_dyld_insert" ]] && export DYLD_INSERT_LIBRARIES="$orig_dyld_insert"
    [[ -n "$orig_bash_env" ]] && export BASH_ENV="$orig_bash_env"
    [[ -n "$orig_env" ]] && export ENV="$orig_env"
}

# --- Run all tests ---
run_all_tests() {
    echo "=== Phase 5 Integration Tests (014-pipeline-security-hardening) ==="
    echo ""

    test_cve_n8n
    test_cve_openclaw
    test_cve_ollama
    test_hmac_consistency
    test_sensitive_file_protections
    test_lock_state_signed
    test_heartbeat_signed
    test_asi_controls
    test_defense_prevent
    test_defense_contain
    test_defense_detect
    test_defense_respond
    test_defense_recover
    test_env_vars

    echo ""
    echo "=== Results ==="
    echo "  Passed: ${T_PASS}"
    echo "  Failed: ${T_FAIL}"
    echo "  Skipped: ${T_SKIP}"
    echo ""

    if [[ $T_FAIL -gt 0 ]]; then
        echo "SOME TESTS FAILED"
        exit 1
    else
        echo "ALL TESTS PASSED"
        exit 0
    fi
}

run_all_tests "$@"
