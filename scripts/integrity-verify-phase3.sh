#!/usr/bin/env bash
# integrity-verify-phase3.sh — Verification tests for Phase 3 (US1: Filesystem Immutability)
# T012: Lock/unlock round-trip verification
# T013: Symlink violation verification
#
# Must be run with sudo:  sudo bash scripts/integrity-verify-phase3.sh
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

# --- Pre-flight ---

if [[ $EUID -ne 0 ]]; then
    log_error "Run with sudo:  sudo bash scripts/integrity-verify-phase3.sh"
    exit 1
fi

# Pick a test file — use the first .md in agents/
TEST_FILE=$(integrity_list_protected_files "$REPO_ROOT" | grep '/agents/.*\.md$' | head -1)
if [[ -z "$TEST_FILE" ]]; then
    log_error "No agent .md files found in protected list. Is test-probe agent deployed?"
    exit 1
fi

log_step "Phase 3 Verification — using test file: ${TEST_FILE}"
echo ""

# ============================================================
# T012: Lock/unlock round-trip
# ============================================================
log_step "T012: Lock/unlock round-trip verification"

# --- Step 1: Deploy manifest ---
log_info "Step 1: Running integrity-deploy to build manifest"
# Deploy runs as non-root, switch to real user
REAL_USER="${SUDO_USER:-$(whoami)}"
sudo -u "$REAL_USER" bash "${SCRIPT_DIR}/integrity-deploy.sh" --skip-git-check

if [[ -f "$INTEGRITY_MANIFEST" ]]; then
    assert_pass "Manifest created at ${INTEGRITY_MANIFEST}"
else
    assert_fail "Manifest not created"
fi

# --- Step 2: Lock all files ---
log_info "Step 2: Locking all protected files"
bash "${SCRIPT_DIR}/integrity-lock.sh"

if ls -lO "$TEST_FILE" 2>/dev/null | grep -q "uchg"; then
    assert_pass "uchg flag set on ${TEST_FILE}"
else
    assert_fail "uchg flag NOT set on ${TEST_FILE}"
fi

# --- Step 3: Attempt tamper as non-root ---
log_info "Step 3: Attempting write to locked file as non-root user"
if sudo -u "$REAL_USER" bash -c "echo 'tampered' >> '$TEST_FILE'" 2>/dev/null; then
    assert_fail "Write SUCCEEDED on locked file (should have been denied)"
else
    assert_pass "Write denied on locked file (Operation not permitted)"
fi

# Record checksum before unlock/edit/relock cycle
CHECKSUM_BEFORE=$(jq -r --arg p "$TEST_FILE" '.files[] | select(.path == $p) | .sha256' "$INTEGRITY_MANIFEST")
log_info "Checksum before edit: ${CHECKSUM_BEFORE:0:16}..."

# --- Step 4: Unlock the file ---
log_info "Step 4: Unlocking test file"
bash "${SCRIPT_DIR}/integrity-unlock.sh" --file "$TEST_FILE"

if ls -lO "$TEST_FILE" 2>/dev/null | grep -q "uchg"; then
    assert_fail "uchg flag still set after unlock"
else
    assert_pass "uchg flag cleared after unlock"
fi

# --- Step 5: Verify edit succeeds ---
log_info "Step 5: Writing to unlocked file as non-root"
# Append a test marker, then remove it
ORIGINAL_CONTENT=$(cat "$TEST_FILE")
if sudo -u "$REAL_USER" bash -c "echo '# INTEGRITY-TEST-MARKER' >> '$TEST_FILE'" 2>/dev/null; then
    assert_pass "Write succeeded on unlocked file"
else
    assert_fail "Write still denied after unlock"
fi

# --- Step 6: Re-lock and verify manifest updated ---
log_info "Step 6: Re-locking all files"
bash "${SCRIPT_DIR}/integrity-lock.sh"

CHECKSUM_AFTER=$(jq -r --arg p "$TEST_FILE" '.files[] | select(.path == $p) | .sha256' "$INTEGRITY_MANIFEST")
log_info "Checksum after edit: ${CHECKSUM_AFTER:0:16}..."

if [[ "$CHECKSUM_BEFORE" != "$CHECKSUM_AFTER" ]]; then
    assert_pass "Manifest checksum updated after file edit"
else
    assert_fail "Manifest checksum unchanged (should reflect edit)"
fi

# --- Cleanup: restore original file content ---
log_info "Cleanup: restoring original file content"
chflags nouchg "$TEST_FILE"
echo "$ORIGINAL_CONTENT" > "$TEST_FILE"
bash "${SCRIPT_DIR}/integrity-lock.sh"
assert_pass "Test file restored to original content and re-locked"

echo ""

# ============================================================
# T013: Symlink violation
# ============================================================
log_step "T013: Symlink violation verification"

# First, unlock all files so we can test the lock path cleanly
log_info "Unlocking files before symlink test"
while IFS= read -r f; do
    [[ -f "$f" ]] && chflags nouchg "$f" 2>/dev/null || true
done < <(integrity_list_protected_files "$REPO_ROOT")

# Create a symlink inside a protected directory
SYMLINK_DIR=$(dirname "$TEST_FILE")
SYMLINK_PATH="${SYMLINK_DIR}/SYMLINK-TEST-LINK.md"

log_info "Creating test symlink: ${SYMLINK_PATH} -> /etc/passwd"
ln -sf /etc/passwd "$SYMLINK_PATH"

if [[ -L "$SYMLINK_PATH" ]]; then
    assert_pass "Test symlink created"
else
    assert_fail "Failed to create test symlink"
fi

# Attempt to lock — should refuse due to symlink
log_info "Attempting integrity-lock with symlink present"
if bash "${SCRIPT_DIR}/integrity-lock.sh" 2>&1; then
    assert_fail "Lock succeeded despite symlink (should have refused)"
else
    assert_pass "Lock refused with symlink violation"
fi

# Cleanup symlink
log_info "Cleanup: removing test symlink"
rm -f "$SYMLINK_PATH"
assert_pass "Test symlink removed"

# Re-lock cleanly
log_info "Re-locking files after cleanup"
bash "${SCRIPT_DIR}/integrity-lock.sh"
assert_pass "Files re-locked after symlink cleanup"

echo ""

# ============================================================
# Summary
# ============================================================
log_step "Phase 3 Verification Results"
echo ""
printf "  ${CLR_GREEN}Passed: %d${CLR_NC}\n" "$PASS"
printf "  ${CLR_RED}Failed: %d${CLR_NC}\n" "$FAIL"
echo ""

if [[ $FAIL -gt 0 ]]; then
    log_error "Phase 3 verification FAILED — ${FAIL} assertion(s) did not pass"
    exit 1
else
    log_info "Phase 3 verification PASSED — all ${PASS} assertions passed"
    exit 0
fi
