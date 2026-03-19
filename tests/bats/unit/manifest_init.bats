#!/usr/bin/env bats
# Tests for manifest_init() and _manifest_atomic_write()

load '../helpers/setup'

@test "manifest_init creates ~/.openclaw/ directory" {
    manifest_init
    [ -d "$MANIFEST_DIR" ]
}

@test "manifest_init creates ~/.openclaw/ with mode 700" {
    manifest_init
    local perms
    perms=$(stat -f %Lp "$MANIFEST_DIR" 2>/dev/null || stat -c %a "$MANIFEST_DIR" 2>/dev/null)
    [ "$perms" = "700" ]
}

@test "manifest_init creates manifest.json" {
    manifest_init
    [ -f "$MANIFEST_FILE" ]
}

@test "manifest_init creates manifest.json with mode 600" {
    manifest_init
    local perms
    perms=$(stat -f %Lp "$MANIFEST_FILE" 2>/dev/null || stat -c %a "$MANIFEST_FILE" 2>/dev/null)
    [ "$perms" = "600" ]
}

@test "manifest_init produces valid JSON" {
    manifest_init
    jq empty "$MANIFEST_FILE"
}

@test "manifest_init sets version to 1.0.0" {
    manifest_init
    local ver
    ver=$(jq -r '.version' "$MANIFEST_FILE")
    [ "$ver" = "1.0.0" ]
}

@test "manifest_init creates empty artifacts array" {
    manifest_init
    local count
    count=$(jq '.artifacts | length' "$MANIFEST_FILE")
    [ "$count" -eq 0 ]
}

@test "manifest_init sets timestamps" {
    manifest_init
    local ts
    ts=$(jq -r '.created_at' "$MANIFEST_FILE")
    [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

@test "manifest_init is idempotent — does not overwrite existing manifest" {
    manifest_init
    manifest_add "test-id" "file" "tooling" "/tmp/test" "1.0" "" "test" false true ""
    local count_before
    count_before=$(jq '.artifacts | length' "$MANIFEST_FILE")
    manifest_init
    local count_after
    count_after=$(jq '.artifacts | length' "$MANIFEST_FILE")
    [ "$count_before" -eq "$count_after" ]
}

@test "_manifest_atomic_write rejects invalid JSON" {
    manifest_init
    local original
    original=$(cat "$MANIFEST_FILE")
    run bash -c "source '${SCRIPT_DIR}/lib/manifest.sh' && export MANIFEST_DIR='${MANIFEST_DIR}' && export MANIFEST_FILE='${MANIFEST_FILE}' && echo 'not json' | _manifest_atomic_write"
    [ "$status" -ne 0 ]
    [ "$(cat "$MANIFEST_FILE")" = "$original" ]
}

@test "_manifest_atomic_write leaves no .tmp file on success" {
    manifest_init
    jq '.version = "2.0.0"' "$MANIFEST_FILE" | _manifest_atomic_write
    [ ! -f "${MANIFEST_FILE}.tmp" ]
}
