#!/usr/bin/env bats
# Tests for manifest_checksum()

load '../helpers/setup'

@test "manifest_checksum returns 64-char hex for existing file" {
    local f="${BATS_TMPDIR}/checksumtest"
    echo "hello world" > "$f"
    local result
    result=$(manifest_checksum "$f")
    [ -n "$result" ]
    [ ${#result} -eq 64 ]
}

@test "manifest_checksum returns empty string for missing file" {
    local result
    result=$(manifest_checksum "/nonexistent/path")
    [ -z "$result" ]
}

@test "manifest_checksum is deterministic" {
    local f="${BATS_TMPDIR}/checksumtest2"
    echo "deterministic" > "$f"
    local r1 r2
    r1=$(manifest_checksum "$f")
    r2=$(manifest_checksum "$f")
    [ "$r1" = "$r2" ]
}

@test "manifest_checksum detects content change" {
    local f="${BATS_TMPDIR}/checksumtest3"
    echo "version 1" > "$f"
    local r1
    r1=$(manifest_checksum "$f")
    echo "version 2" > "$f"
    local r2
    r2=$(manifest_checksum "$f")
    [ "$r1" != "$r2" ]
}
