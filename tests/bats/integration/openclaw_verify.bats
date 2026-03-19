#!/usr/bin/env bats
# Integration tests for openclaw manifest --verify

load '../helpers/setup'

@test "verify reports PRESENT for existing file with matching checksum" {
    manifest_init
    local f="${BATS_TMPDIR}/verifyfile"
    echo "test content" > "$f"
    local cksum
    cksum=$(manifest_checksum "$f")
    manifest_add "test-file" "file" "tooling" "$f" "N/A" "$cksum" "test" false true ""

    run bash -c "export HOME='${HOME}' && export MANIFEST_DIR='${MANIFEST_DIR}' && export MANIFEST_FILE='${MANIFEST_FILE}' && bash '${SCRIPT_DIR}/openclaw.sh' manifest --verify"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PRESENT"* ]]
}

@test "verify reports DRIFTED for file with changed content" {
    manifest_init
    local f="${BATS_TMPDIR}/driftfile"
    echo "original" > "$f"
    local cksum
    cksum=$(manifest_checksum "$f")
    manifest_add "test-file" "file" "tooling" "$f" "N/A" "$cksum" "test" false true ""
    echo "modified" > "$f"

    run bash -c "export HOME='${HOME}' && export MANIFEST_DIR='${MANIFEST_DIR}' && export MANIFEST_FILE='${MANIFEST_FILE}' && bash '${SCRIPT_DIR}/openclaw.sh' manifest --verify"
    [ "$status" -eq 1 ]
    [[ "$output" == *"DRIFTED"* ]]
}

@test "verify reports MISSING for deleted file" {
    manifest_init
    manifest_add "test-file" "file" "tooling" "/nonexistent/path" "N/A" "abc" "test" false true ""

    run bash -c "export HOME='${HOME}' && export MANIFEST_DIR='${MANIFEST_DIR}' && export MANIFEST_FILE='${MANIFEST_FILE}' && bash '${SCRIPT_DIR}/openclaw.sh' manifest --verify"
    [ "$status" -eq 1 ]
    [[ "$output" == *"MISSING"* ]]
}

@test "verify reports MISSING for deleted directory" {
    manifest_init
    manifest_add "test-dir" "directory" "tooling" "/nonexistent/dir" "N/A" "" "test" false true ""

    run bash -c "export HOME='${HOME}' && export MANIFEST_DIR='${MANIFEST_DIR}' && export MANIFEST_FILE='${MANIFEST_FILE}' && bash '${SCRIPT_DIR}/openclaw.sh' manifest --verify"
    [ "$status" -eq 1 ]
    [[ "$output" == *"MISSING"* ]]
}

@test "verify --json produces valid JSON array" {
    manifest_init
    local f="${BATS_TMPDIR}/jsonverify"
    echo "content" > "$f"
    local cksum
    cksum=$(manifest_checksum "$f")
    manifest_add "test-file" "file" "tooling" "$f" "N/A" "$cksum" "test" false true ""

    local result
    result=$(HOME="$HOME" MANIFEST_DIR="$MANIFEST_DIR" MANIFEST_FILE="$MANIFEST_FILE" bash "${SCRIPT_DIR}/openclaw.sh" manifest --verify --json)
    echo "$result" | jq empty
    [ "$(echo "$result" | jq 'length')" -eq 1 ]
    [ "$(echo "$result" | jq -r '.[0].verify_status')" = "PRESENT" ]
}

@test "verify skips removed entries" {
    manifest_init
    manifest_add "test" "file" "tooling" "/tmp/x" "1.0" "" "test" false true ""
    manifest_update "test" "status" "removed"

    run bash -c "export HOME='${HOME}' && export MANIFEST_DIR='${MANIFEST_DIR}' && export MANIFEST_FILE='${MANIFEST_FILE}' && bash '${SCRIPT_DIR}/openclaw.sh' manifest --verify"
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 PRESENT"* ]]
}
