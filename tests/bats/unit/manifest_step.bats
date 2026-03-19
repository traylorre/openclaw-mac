#!/usr/bin/env bats
# Tests for manifest_begin_step/manifest_complete_step (interrupt recovery)

load '../helpers/setup'

@test "manifest_begin_step adds entry with status=pending" {
    manifest_init
    manifest_begin_step "test" "file" "tooling" "/tmp/x" "1.0" "test" false true ""
    [ "$(manifest_get "test" "status")" = "pending" ]
}

@test "manifest_begin_step returns 0 on first call" {
    manifest_init
    run manifest_begin_step "test" "file" "tooling" "/tmp/x" "1.0" "test" false true ""
    [ "$status" -eq 0 ]
}

@test "manifest_begin_step returns 1 if already installed (skip signal)" {
    manifest_init
    manifest_add "test" "file" "tooling" "/tmp/x" "1.0" "" "test" false true ""
    run manifest_begin_step "test" "file" "tooling" "/tmp/x" "1.0" "test" false true ""
    [ "$status" -eq 1 ]
}

@test "manifest_begin_step returns 1 if already skipped" {
    manifest_init
    manifest_add "test" "file" "tooling" "/tmp/x" "1.0" "" "test" true true ""
    run manifest_begin_step "test" "file" "tooling" "/tmp/x" "1.0" "test" true true ""
    [ "$status" -eq 1 ]
}

@test "manifest_begin_step retries pending entry without duplicating" {
    manifest_init
    manifest_begin_step "test" "file" "tooling" "/tmp/x" "1.0" "test" false true ""
    manifest_begin_step "test" "file" "tooling" "/tmp/x" "1.0" "test" false true ""
    local count
    count=$(jq '[.artifacts[] | select(.id == "test")] | length' "$MANIFEST_FILE")
    [ "$count" -eq 1 ]
}

@test "manifest_complete_step changes pending to installed" {
    manifest_init
    manifest_begin_step "test" "file" "tooling" "/tmp/x" "1.0" "test" false true ""
    manifest_complete_step "test" "abc123"
    [ "$(manifest_get "test" "status")" = "installed" ]
}

@test "manifest_complete_step sets checksum" {
    manifest_init
    manifest_begin_step "test" "file" "tooling" "/tmp/x" "1.0" "test" false true ""
    manifest_complete_step "test" "deadbeef"
    [ "$(manifest_get "test" "checksum")" = "deadbeef" ]
}

@test "manifest_complete_step with empty checksum sets null" {
    manifest_init
    manifest_begin_step "test" "file" "tooling" "/tmp/x" "1.0" "test" false true ""
    manifest_complete_step "test" ""
    [ "$(jq '.artifacts[0].checksum' "$MANIFEST_FILE")" = "null" ]
}

@test "full begin+complete cycle produces correct entry" {
    manifest_init
    if manifest_begin_step "test" "file" "tooling" "/tmp/x" "1.0" "test" false true "my note"; then
        manifest_complete_step "test" "checksum123"
    fi
    [ "$(manifest_get "test" "status")" = "installed" ]
    [ "$(manifest_get "test" "checksum")" = "checksum123" ]
}

@test "re-run after complete skips without duplicating" {
    manifest_init
    manifest_begin_step "test" "file" "tooling" "/tmp/x" "1.0" "test" false true ""
    manifest_complete_step "test" "abc"
    run manifest_begin_step "test" "file" "tooling" "/tmp/x" "1.0" "test" false true ""
    [ "$status" -eq 1 ]
    [ "$(jq '.artifacts | length' "$MANIFEST_FILE")" -eq 1 ]
}
