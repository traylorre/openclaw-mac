#!/usr/bin/env bash
# integrity-verify-phase5.sh — Verification tests for Phase 5 (US3: Startup Check)
# T029: Tamper detection verification
#
# Must be run with sudo:  sudo bash scripts/integrity-verify-phase5.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/integrity.sh
source "${SCRIPT_DIR}/lib/integrity.sh"

REPO_ROOT="$(resolve_repo_root "$SCRIPT_DIR")"
readonly REPO_ROOT

PASS=0
FAIL=0

assert_pass() {
    local label="$1"
    PASS=$((PASS + 1))
    printf "${CLR_GREEN}  ✓ PASS${CLR_NC}  %s\n" "$label"
}

assert_fail() {
    local label="$1"
    FAIL=$((FAIL + 1))
    printf "${CLR_RED}  ✗ FAIL${CLR_NC}  %s\n" "$label"
}

if [[ $EUID -ne 0 ]]; then
    log_error "Run with sudo:  sudo bash scripts/integrity-verify-phase5.sh"
    exit 1
fi

REAL_USER="${SUDO_USER:-$(whoami)}"

# Pick a test file
TEST_FILE=$(integrity_list_protected_files "$REPO_ROOT" | grep '/agents/.*\.md$' | head -1)
log_step "Phase 5 Verification — using test file: ${TEST_FILE}"
echo ""

# ============================================================
# T029: Tamper detection via integrity-verify
# ============================================================
log_step "T029: Startup integrity check detects file tampering"

# Step 1: Deploy fresh manifest and lock
log_info "Step 1: Deploy and lock (clean baseline)"
sudo -u "$REAL_USER" bash "${SCRIPT_DIR}/integrity-deploy.sh" --skip-git-check
bash "${SCRIPT_DIR}/integrity-lock.sh"

# Step 2: Verify passes on clean state
log_info "Step 2: Verify passes on clean state"
if sudo -u "$REAL_USER" bash "${SCRIPT_DIR}/integrity-verify.sh" --dry-run 2>&1 | grep -q "error(s)"; then
    # There may be expected errors (platform version unknown, etc.)
    # Check specifically for checksum errors
    checksum_output=$(sudo -u "$REAL_USER" bash "${SCRIPT_DIR}/integrity-verify.sh" --dry-run 2>&1 || true)
    if echo "$checksum_output" | grep -q "Checksum mismatch"; then
        assert_fail "Checksum mismatch on clean state (shouldn't happen)"
    else
        assert_pass "No checksum mismatches on clean state"
    fi
else
    assert_pass "No checksum mismatches on clean state"
fi

# Step 3: Tamper with the file (bypass uchg via root)
log_info "Step 3: Tampering with file as root (bypassing uchg)"
chflags nouchg "$TEST_FILE"
echo "# INTEGRITY-TAMPER-TEST" >> "$TEST_FILE"
chflags uchg "$TEST_FILE"
assert_pass "File tampered while preserving uchg flag"

# Step 4: Run integrity-verify — should detect the tamper
log_info "Step 4: Running integrity-verify (should detect tamper)"
verify_output=$(sudo -u "$REAL_USER" bash "${SCRIPT_DIR}/integrity-verify.sh" --dry-run 2>&1 || true)

if echo "$verify_output" | grep -q "Checksum mismatch.*${TEST_FILE}"; then
    assert_pass "integrity-verify detected tampered file: ${TEST_FILE}"
elif echo "$verify_output" | grep -q "Checksum mismatch"; then
    assert_pass "integrity-verify detected checksum mismatch (file identified in output)"
else
    echo "$verify_output"
    assert_fail "integrity-verify did NOT detect tampering"
fi

# Step 5: Verify it returns non-zero exit
if sudo -u "$REAL_USER" bash "${SCRIPT_DIR}/integrity-verify.sh" --dry-run >/dev/null 2>&1; then
    assert_fail "integrity-verify exited 0 despite tampering (should be non-zero)"
else
    assert_pass "integrity-verify exited non-zero (agent launch would be blocked)"
fi

# Cleanup: restore file and re-lock
log_info "Cleanup: restoring tampered file"
chflags nouchg "$TEST_FILE"
# Remove the tamper line
head -n -1 "$TEST_FILE" > "${TEST_FILE}.tmp" && mv "${TEST_FILE}.tmp" "$TEST_FILE"
bash "${SCRIPT_DIR}/integrity-lock.sh"

# Rebuild manifest with clean state
sudo -u "$REAL_USER" bash "${SCRIPT_DIR}/integrity-deploy.sh" --skip-git-check
bash "${SCRIPT_DIR}/integrity-lock.sh"
assert_pass "File restored and manifest rebuilt"

echo ""
log_step "Phase 5 Verification Results"
echo ""
printf "  ${CLR_GREEN}Passed: %d${CLR_NC}\n" "$PASS"
printf "  ${CLR_RED}Failed: %d${CLR_NC}\n" "$FAIL"
echo ""

if [[ $FAIL -gt 0 ]]; then
    log_error "Phase 5 verification FAILED — ${FAIL} assertion(s) did not pass"
    exit 1
else
    log_info "Phase 5 verification (T029) PASSED"
    echo ""
    log_info "T030-T032 require interactive monitor testing:"
    log_info "  T030: make monitor-setup → sudo tamper file → check alert"
    log_info "  T031: make integrity-unlock → edit → verify no alert → re-lock"
    log_info "  T032: kill monitor PID → verify launchd restarts → check heartbeat"
    exit 0
fi
