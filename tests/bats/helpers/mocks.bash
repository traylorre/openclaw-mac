#!/usr/bin/env bash
# Mock framework for macOS commands — PATH-based stub generation

create_mock() {
    # Usage: create_mock <command_name> [exit_code] [stdout_output]
    local cmd_name="$1"
    local exit_code="${2:-0}"
    local stdout="${3:-}"

    local mock_dir="${BATS_TMPDIR}/mocks"
    mkdir -p "$mock_dir"

    cat > "${mock_dir}/${cmd_name}" <<MOCK
#!/usr/bin/env bash
echo "\$0 \$*" >> "${BATS_TMPDIR}/mock_calls.log"
${stdout:+printf '%s\\n' "$stdout"}
exit ${exit_code}
MOCK
    chmod +x "${mock_dir}/${cmd_name}"
}

setup_mock_path() {
    export ORIGINAL_PATH="$PATH"
    export PATH="${BATS_TMPDIR}/mocks:$PATH"
    rm -f "${BATS_TMPDIR}/mock_calls.log" 2>/dev/null
}

teardown_mock_path() {
    if [[ -n "${ORIGINAL_PATH:-}" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
}

assert_mock_called() {
    local cmd="$1"
    grep -q "$cmd" "${BATS_TMPDIR}/mock_calls.log" 2>/dev/null
}

assert_mock_called_with() {
    local pattern="$1"
    grep -q "$pattern" "${BATS_TMPDIR}/mock_calls.log" 2>/dev/null
}

assert_mock_not_called() {
    local cmd="$1"
    ! grep -q "$cmd" "${BATS_TMPDIR}/mock_calls.log" 2>/dev/null
}
