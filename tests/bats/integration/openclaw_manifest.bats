#!/usr/bin/env bats
# Integration tests for openclaw manifest commands

load '../helpers/setup'

@test "openclaw manifest shows 'No manifest found' when missing" {
    run bash "${SCRIPT_DIR}/openclaw.sh" manifest
    [ "$status" -eq 2 ]
    [[ "$output" == *"No manifest found"* ]]
}

@test "openclaw manifest --json outputs valid JSON" {
    manifest_init
    manifest_add "test" "file" "tooling" "/tmp/x" "1.0" "" "test" false true ""
    run bash -c "export HOME='${HOME}' && export MANIFEST_DIR='${MANIFEST_DIR}' && export MANIFEST_FILE='${MANIFEST_FILE}' && bash '${SCRIPT_DIR}/openclaw.sh' manifest --json"
    [ "$status" -eq 0 ]
    echo "$output" | jq empty
}

@test "openclaw manifest --json includes artifacts" {
    manifest_init
    manifest_add "test" "file" "tooling" "/tmp/x" "1.0" "" "test" false true ""
    local result
    result=$(HOME="$HOME" MANIFEST_DIR="$MANIFEST_DIR" MANIFEST_FILE="$MANIFEST_FILE" bash "${SCRIPT_DIR}/openclaw.sh" manifest --json)
    [ "$(echo "$result" | jq '.artifacts | length')" -eq 1 ]
}

@test "openclaw manifest table shows artifact count" {
    manifest_init
    manifest_add "a" "file" "tooling" "/a" "1.0" "" "test" false true ""
    manifest_add "b" "file" "tooling" "/b" "1.0" "" "test" false true ""
    run bash -c "export HOME='${HOME}' && export MANIFEST_DIR='${MANIFEST_DIR}' && export MANIFEST_FILE='${MANIFEST_FILE}' && bash '${SCRIPT_DIR}/openclaw.sh' manifest"
    [ "$status" -eq 0 ]
    [[ "$output" == *"2 artifacts"* ]]
}

@test "openclaw --help shows usage" {
    run bash "${SCRIPT_DIR}/openclaw.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "openclaw --version shows version" {
    run bash "${SCRIPT_DIR}/openclaw.sh" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"openclaw v"* ]]
}

@test "openclaw unknown command exits 2" {
    run bash "${SCRIPT_DIR}/openclaw.sh" nonsense
    [ "$status" -eq 2 ]
}

@test "openclaw manifest --rebuild creates manifest from scratch" {
    setup_mock_path
    create_mock "brew" 1     # no brew packages found
    create_mock "colima" 1   # no colima
    create_mock "docker" 1   # no docker
    create_mock "security" 1 # no keychain entries
    run bash -c "export HOME='${HOME}' && export MANIFEST_DIR='${MANIFEST_DIR}' && export MANIFEST_FILE='${MANIFEST_FILE}' && export PATH='${BATS_TMPDIR}/mocks:${PATH}' && bash '${SCRIPT_DIR}/openclaw.sh' manifest --rebuild"
    [ "$status" -eq 0 ]
    [ -f "$MANIFEST_FILE" ]
    teardown_mock_path
}
