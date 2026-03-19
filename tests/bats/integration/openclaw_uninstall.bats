#!/usr/bin/env bats
# Integration tests for openclaw uninstall

load '../helpers/setup'

_setup_manifest_with_artifacts() {
    manifest_init
    # Create real files to remove
    mkdir -p "${BATS_TMPDIR}/opt/n8n"
    echo "content" > "${BATS_TMPDIR}/opt/n8n/testfile"
    local cksum
    cksum=$(manifest_checksum "${BATS_TMPDIR}/opt/n8n/testfile")

    manifest_add "test-file" "file" "tooling" "${BATS_TMPDIR}/opt/n8n/testfile" "N/A" "$cksum" "test" false true ""
    manifest_add "test-dir" "directory" "tooling" "${BATS_TMPDIR}/opt/n8n" "N/A" "" "test" false true ""
    manifest_add "pre-existing" "file" "tooling" "/some/path" "N/A" "" "test" true true ""
}

@test "uninstall --dry-run does not remove anything" {
    _setup_manifest_with_artifacts
    run bash -c "export HOME='${HOME}' && export MANIFEST_DIR='${MANIFEST_DIR}' && export MANIFEST_FILE='${MANIFEST_FILE}' && bash '${SCRIPT_DIR}/openclaw.sh' uninstall --dry-run --force"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN"* ]]
    # Files should still exist
    [ -f "${BATS_TMPDIR}/opt/n8n/testfile" ]
}

@test "uninstall --dry-run skips pre-existing artifacts" {
    _setup_manifest_with_artifacts
    run bash -c "export HOME='${HOME}' && export MANIFEST_DIR='${MANIFEST_DIR}' && export MANIFEST_FILE='${MANIFEST_FILE}' && bash '${SCRIPT_DIR}/openclaw.sh' uninstall --dry-run --force"
    [[ "$output" == *"pre-existing"* ]]
}

@test "uninstall --force removes files and creates report" {
    _setup_manifest_with_artifacts
    run bash -c "export HOME='${HOME}' && export MANIFEST_DIR='${MANIFEST_DIR}' && export MANIFEST_FILE='${MANIFEST_FILE}' && bash '${SCRIPT_DIR}/openclaw.sh' uninstall --force"
    [ "$status" -eq 0 ]
    # File should be removed
    [ ! -f "${BATS_TMPDIR}/opt/n8n/testfile" ]
    # Report should exist
    [ -f "${MANIFEST_DIR}/uninstall-report.txt" ]
}

@test "uninstall --force updates manifest status to removed" {
    _setup_manifest_with_artifacts
    bash -c "export HOME='${HOME}' && export MANIFEST_DIR='${MANIFEST_DIR}' && export MANIFEST_FILE='${MANIFEST_FILE}' && bash '${SCRIPT_DIR}/openclaw.sh' uninstall --force"
    # Check directory (processed first in reverse order — successfully removed)
    local status_val
    status_val=$(jq -r '.artifacts[] | select(.id == "test-dir") | .status' "$MANIFEST_FILE")
    [ "$status_val" = "removed" ]
}

@test "uninstall report contains REMOVED and SKIPPED sections" {
    _setup_manifest_with_artifacts
    bash -c "export HOME='${HOME}' && export MANIFEST_DIR='${MANIFEST_DIR}' && export MANIFEST_FILE='${MANIFEST_FILE}' && bash '${SCRIPT_DIR}/openclaw.sh' uninstall --force"
    grep -q "REMOVED:" "${MANIFEST_DIR}/uninstall-report.txt"
    grep -q "SKIPPED" "${MANIFEST_DIR}/uninstall-report.txt"
}

@test "uninstall without manifest exits 2" {
    run bash -c "export HOME='${HOME}' && export MANIFEST_DIR='${MANIFEST_DIR}' && export MANIFEST_FILE='${MANIFEST_FILE}' && bash '${SCRIPT_DIR}/openclaw.sh' uninstall --force"
    [ "$status" -eq 2 ]
    [[ "$output" == *"No manifest found"* ]]
}

@test "uninstall processes artifacts in reverse order" {
    manifest_init
    # Add file then directory — reverse order should remove file first, dir second
    manifest_add "dir" "directory" "tooling" "${BATS_TMPDIR}/revtest" "N/A" "" "test" false true ""
    mkdir -p "${BATS_TMPDIR}/revtest"
    echo "x" > "${BATS_TMPDIR}/revtest/child"
    manifest_add "child" "file" "tooling" "${BATS_TMPDIR}/revtest/child" "N/A" "" "test" false true ""

    run bash -c "export HOME='${HOME}' && export MANIFEST_DIR='${MANIFEST_DIR}' && export MANIFEST_FILE='${MANIFEST_FILE}' && bash '${SCRIPT_DIR}/openclaw.sh' uninstall --force"
    [ "$status" -eq 0 ]
    # Both should be removed (child first due to reverse, then dir)
    [ ! -d "${BATS_TMPDIR}/revtest" ]
}

@test "uninstall --keep-hardening skips hardening artifacts" {
    manifest_init
    # Use "file" type for both to avoid sudo (test runs as normal user)
    local f="${BATS_TMPDIR}/hardenfile"
    echo "x" > "$f"
    manifest_add "hard" "file" "hardening" "$f" "N/A" "" "test" false true ""
    echo "y" > "${BATS_TMPDIR}/toolfile"
    manifest_add "tool" "file" "tooling" "${BATS_TMPDIR}/toolfile" "N/A" "" "test" false true ""

    run bash -c "export HOME='${HOME}' && export MANIFEST_DIR='${MANIFEST_DIR}' && export MANIFEST_FILE='${MANIFEST_FILE}' && bash '${SCRIPT_DIR}/openclaw.sh' uninstall --force --keep-hardening"
    [ "$status" -eq 0 ]
    # Hardening file should still exist
    [ -f "$f" ]
    # Tooling file should be removed
    [ ! -f "${BATS_TMPDIR}/toolfile" ]
}
