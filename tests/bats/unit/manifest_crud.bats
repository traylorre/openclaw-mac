#!/usr/bin/env bats
# Tests for manifest_add, manifest_has, manifest_get, manifest_update

load '../helpers/setup'

@test "manifest_add creates entry with correct id and type" {
    manifest_init
    manifest_add "brew-jq" "brew-package" "tooling" "jq" "1.7.1" "null" "bootstrap.sh" false true ""
    [ "$(jq -r '.artifacts[0].id' "$MANIFEST_FILE")" = "brew-jq" ]
    [ "$(jq -r '.artifacts[0].type' "$MANIFEST_FILE")" = "brew-package" ]
}

@test "manifest_add sets status=installed for new artifacts" {
    manifest_init
    manifest_add "test" "file" "tooling" "/tmp/x" "1.0" "" "test" false true ""
    [ "$(jq -r '.artifacts[0].status' "$MANIFEST_FILE")" = "installed" ]
}

@test "manifest_add sets status=skipped for pre_existing artifacts" {
    manifest_init
    manifest_add "test" "file" "tooling" "/tmp/x" "1.0" "" "test" true true ""
    [ "$(jq -r '.artifacts[0].status' "$MANIFEST_FILE")" = "skipped" ]
}

@test "manifest_add stores pre_existing as boolean true, not string" {
    manifest_init
    manifest_add "test" "file" "tooling" "/tmp/x" "1.0" "" "test" true true ""
    local val
    val=$(jq '.artifacts[0].pre_existing' "$MANIFEST_FILE")
    [ "$val" = "true" ]
    # Verify it's not the string "true"
    val=$(jq '.artifacts[0].pre_existing | type' "$MANIFEST_FILE")
    [ "$val" = '"boolean"' ]
}

@test "manifest_add skips duplicate id silently" {
    manifest_init
    manifest_add "test" "file" "tooling" "/tmp/x" "1.0" "" "test" false true ""
    manifest_add "test" "file" "tooling" "/tmp/x" "2.0" "" "test" false true ""
    local count
    count=$(jq '.artifacts | length' "$MANIFEST_FILE")
    [ "$count" -eq 1 ]
    [ "$(jq -r '.artifacts[0].version' "$MANIFEST_FILE")" = "1.0" ]
}

@test "manifest_add handles empty checksum as null" {
    manifest_init
    manifest_add "test" "file" "tooling" "/tmp/x" "1.0" "" "test" false true ""
    [ "$(jq '.artifacts[0].checksum' "$MANIFEST_FILE")" = "null" ]
}

@test "manifest_add handles 'null' string checksum as null" {
    manifest_init
    manifest_add "test" "file" "tooling" "/tmp/x" "1.0" "null" "test" false true ""
    [ "$(jq '.artifacts[0].checksum' "$MANIFEST_FILE")" = "null" ]
}

@test "manifest_add stores real checksum as string" {
    manifest_init
    manifest_add "test" "file" "tooling" "/tmp/x" "1.0" "abc123" "test" false true ""
    [ "$(jq -r '.artifacts[0].checksum' "$MANIFEST_FILE")" = "abc123" ]
}

@test "manifest_add stores notes when provided" {
    manifest_init
    manifest_add "test" "file" "tooling" "/tmp/x" "1.0" "" "test" false true "my note"
    [ "$(jq -r '.artifacts[0].notes' "$MANIFEST_FILE")" = "my note" ]
}

@test "manifest_add sets notes to null when empty" {
    manifest_init
    manifest_add "test" "file" "tooling" "/tmp/x" "1.0" "" "test" false true ""
    [ "$(jq '.artifacts[0].notes' "$MANIFEST_FILE")" = "null" ]
}

@test "manifest_add preserves multiple entries in order" {
    manifest_init
    manifest_add "a" "file" "tooling" "/a" "1.0" "" "test" false true ""
    manifest_add "b" "file" "tooling" "/b" "1.0" "" "test" false true ""
    manifest_add "c" "file" "tooling" "/c" "1.0" "" "test" false true ""
    [ "$(jq '.artifacts | length' "$MANIFEST_FILE")" -eq 3 ]
    [ "$(jq -r '.artifacts[0].id' "$MANIFEST_FILE")" = "a" ]
    [ "$(jq -r '.artifacts[2].id' "$MANIFEST_FILE")" = "c" ]
}

@test "manifest_has returns 0 for existing entry" {
    manifest_init
    manifest_add "brew-jq" "brew-package" "tooling" "jq" "1.7.1" "" "test" false true ""
    manifest_has "brew-jq"
}

@test "manifest_has returns non-zero for non-existent entry" {
    manifest_init
    ! manifest_has "nonexistent"
}

@test "manifest_has returns 1 when manifest file is missing" {
    run manifest_has "anything"
    [ "$status" -eq 1 ]
}

@test "manifest_get returns specific field value" {
    manifest_init
    manifest_add "brew-jq" "brew-package" "tooling" "jq" "1.7.1" "" "test" false true ""
    local result
    result=$(manifest_get "brew-jq" "version")
    [ "$result" = "1.7.1" ]
}

@test "manifest_update changes string field" {
    manifest_init
    manifest_add "test" "file" "tooling" "/tmp/x" "1.0" "" "test" false true ""
    manifest_update "test" "status" "removed"
    [ "$(manifest_get "test" "status")" = "removed" ]
}

@test "manifest_update preserves boolean type for true/false" {
    manifest_init
    manifest_add "test" "file" "tooling" "/tmp/x" "1.0" "" "test" false true ""
    manifest_update "test" "removable" "false"
    local val
    val=$(jq '.artifacts[0].removable' "$MANIFEST_FILE")
    [ "$val" = "false" ]
    val=$(jq '.artifacts[0].removable | type' "$MANIFEST_FILE")
    [ "$val" = '"boolean"' ]
}

@test "manifest_update preserves null type" {
    manifest_init
    manifest_add "test" "file" "tooling" "/tmp/x" "1.0" "" "test" false true "has notes"
    manifest_update "test" "notes" "null"
    [ "$(jq '.artifacts[0].notes' "$MANIFEST_FILE")" = "null" ]
}
