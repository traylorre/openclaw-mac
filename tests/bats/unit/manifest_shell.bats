#!/usr/bin/env bats
# Tests for shell detection, shellrc_setup, shellrc_migrate

load '../helpers/setup'

@test "manifest_detect_shell returns ~/.bash_profile for bash" {
    SHELL="/bin/bash"
    local result
    result=$(manifest_detect_shell)
    [ "$result" = "${HOME}/.bash_profile" ]
}

@test "manifest_detect_shell returns ~/.zshrc for zsh" {
    SHELL="/bin/zsh"
    local result
    result=$(manifest_detect_shell)
    [ "$result" = "${HOME}/.zshrc" ]
}

@test "manifest_detect_shell defaults to zshrc for unsupported shell" {
    SHELL="/bin/fish"
    local result
    result=$(manifest_detect_shell 2>/dev/null)
    [ "$result" = "${HOME}/.zshrc" ]
}

@test "manifest_detect_shell creates rc file if missing" {
    SHELL="/bin/zsh"
    [ ! -f "${HOME}/.zshrc" ]
    manifest_detect_shell >/dev/null
    [ -f "${HOME}/.zshrc" ]
}

@test "shellrc_setup creates ~/.openclaw/shellrc" {
    manifest_init
    SHELL="/bin/zsh"
    shellrc_setup "test"
    [ -f "${MANIFEST_DIR}/shellrc" ]
}

@test "shellrc_setup adds source line to rc file" {
    manifest_init
    SHELL="/bin/zsh"
    touch "${HOME}/.zshrc"
    shellrc_setup "test"
    grep -qF 'openclaw/shellrc' "${HOME}/.zshrc"
}

@test "shellrc_setup does not duplicate source line" {
    manifest_init
    SHELL="/bin/zsh"
    touch "${HOME}/.zshrc"
    shellrc_setup "test"
    shellrc_setup "test"
    local count
    count=$(grep -cF 'openclaw/shellrc' "${HOME}/.zshrc")
    [ "$count" -eq 1 ]
}

@test "shellrc_setup tracks artifacts in manifest" {
    manifest_init
    SHELL="/bin/zsh"
    touch "${HOME}/.zshrc"
    shellrc_setup "test"
    manifest_has "shell-rc-file"
    # The config line id uses the rc filename suffix
    local rc_name
    rc_name="$(basename "$(manifest_detect_shell)")"
    manifest_has "shell-config-line-${rc_name}"
}

@test "shellrc_migrate moves openclaw alias from rc to shellrc" {
    manifest_init
    SHELL="/bin/zsh"
    cp "${REPO_ROOT}/tests/fixtures/sample_rc_with_openclaw.bash" "${HOME}/.zshrc"
    touch "${MANIFEST_DIR}/shellrc"
    shellrc_migrate
    # Aliases removed from rc
    run grep -c "alias openclaw=" "${HOME}/.zshrc"
    [ "$output" = "0" ]
    # Aliases moved to shellrc
    grep -qF "alias openclaw=" "${MANIFEST_DIR}/shellrc"
}

@test "shellrc_migrate preserves non-openclaw lines" {
    manifest_init
    SHELL="/bin/zsh"
    cp "${REPO_ROOT}/tests/fixtures/sample_rc_with_openclaw.bash" "${HOME}/.zshrc"
    touch "${MANIFEST_DIR}/shellrc"
    shellrc_migrate
    grep -qF "export PATH" "${HOME}/.zshrc"
    grep -qF "alias myalias" "${HOME}/.zshrc"
    grep -qF "export EDITOR" "${HOME}/.zshrc"
}

@test "shellrc_migrate preserves comments mentioning openclaw" {
    manifest_init
    SHELL="/bin/zsh"
    cp "${REPO_ROOT}/tests/fixtures/sample_rc_with_openclaw.bash" "${HOME}/.zshrc"
    touch "${MANIFEST_DIR}/shellrc"
    shellrc_migrate
    grep -qF "# This comment mentions openclaw" "${HOME}/.zshrc"
}
