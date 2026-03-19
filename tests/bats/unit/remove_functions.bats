#!/usr/bin/env bats
# Tests for artifact removal functions

load '../helpers/setup'

@test "remove_file removes existing file and returns 0" {
    local f="${BATS_TMPDIR}/removeme"
    echo "content" > "$f"
    run remove_file "$f"
    [ "$status" -eq 0 ]
    [ ! -f "$f" ]
}

@test "remove_file returns 1 for non-existent file" {
    run remove_file "/nonexistent"
    [ "$status" -eq 1 ]
}

@test "remove_file backs up drifted file before removing" {
    local f="${BATS_TMPDIR}/driftfile"
    echo "modified content" > "$f"
    local backup_dir="${BATS_TMPDIR}/backups"
    remove_file "$f" "wrong_checksum" "$backup_dir"
    [ ! -f "$f" ]
    [ -f "${backup_dir}${f}" ]
}

@test "remove_directory removes existing directory and returns 0" {
    local d="${BATS_TMPDIR}/removedir"
    mkdir -p "$d/sub"
    touch "$d/sub/file"
    run remove_directory "$d"
    [ "$status" -eq 0 ]
    [ ! -d "$d" ]
}

@test "remove_directory returns 1 for non-existent directory" {
    run remove_directory "/nonexistent"
    [ "$status" -eq 1 ]
}

@test "remove_shell_config_line removes matching line" {
    local rc="${BATS_TMPDIR}/testrc"
    cat > "$rc" <<'EOF'
export PATH="/usr/local/bin:$PATH"
[ -f ~/.openclaw/shellrc ] && source ~/.openclaw/shellrc
alias myalias='echo hello'
EOF
    run remove_shell_config_line "$rc" '[ -f ~/.openclaw/shellrc ] && source ~/.openclaw/shellrc'
    [ "$status" -eq 0 ]
    run grep -c "openclaw" "$rc"
    [ "$output" = "0" ]
    grep -qF "alias myalias" "$rc"
}

@test "remove_shell_config_line returns 1 when pattern not found" {
    local rc="${BATS_TMPDIR}/testrc2"
    echo "export PATH=something" > "$rc"
    run remove_shell_config_line "$rc" "nonexistent pattern"
    [ "$status" -eq 1 ]
}

@test "remove_shell_config_line handles all-lines-match without error" {
    local rc="${BATS_TMPDIR}/testrc3"
    echo '[ -f ~/.openclaw/shellrc ] && source ~/.openclaw/shellrc' > "$rc"
    run remove_shell_config_line "$rc" '[ -f ~/.openclaw/shellrc ] && source ~/.openclaw/shellrc'
    [ "$status" -eq 0 ]
}

@test "remove_shell_rc_file removes file and returns 0" {
    local f="${BATS_TMPDIR}/shellrc"
    echo "content" > "$f"
    run remove_shell_rc_file "$f"
    [ "$status" -eq 0 ]
    [ ! -f "$f" ]
}

@test "remove_shell_rc_file returns 1 for missing file" {
    run remove_shell_rc_file "/nonexistent"
    [ "$status" -eq 1 ]
}
