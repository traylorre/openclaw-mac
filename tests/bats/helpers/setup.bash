#!/usr/bin/env bash
# Common BATS test setup — HOME isolation and shasum compatibility

# Resolve the repo root from this helper's location
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT_DIR="${REPO_ROOT}/scripts"

# shasum compatibility shim for Linux (Ubuntu has sha256sum, not shasum)
if ! command -v shasum &>/dev/null; then
    shasum() {
        if [[ "${1:-}" == "-a" && "${2:-}" == "256" ]]; then
            shift 2
            sha256sum "$@" | sed 's/  / /'
        fi
    }
    export -f shasum
fi

# stat -f %m compatibility shim for Linux (macOS stat vs GNU stat)
if stat --version &>/dev/null 2>&1; then
    # GNU stat (Linux) — wrap macOS-style calls
    _original_stat="$(command -v stat)"
    stat() {
        if [[ "${1:-}" == "-f" && "${2:-}" == "%m" ]]; then
            shift 2
            command stat -c %Y "$@" 2>/dev/null || echo 0
        else
            command stat "$@"
        fi
    }
    export -f stat
fi

# --- Per-test setup/teardown ---

setup() {
    # Sandbox HOME to avoid touching real ~/.openclaw/
    export REAL_HOME="$HOME"
    export HOME="${BATS_TMPDIR}/home_${BATS_TEST_NUMBER}"
    mkdir -p "$HOME"

    # Override manifest paths BEFORE sourcing manifest.sh
    export MANIFEST_DIR="${HOME}/.openclaw"
    export MANIFEST_FILE="${MANIFEST_DIR}/manifest.json"

    # Source the manifest library
    source "${SCRIPT_DIR}/lib/manifest.sh"

    # Source mock helpers if available
    if [[ -f "${BATS_TEST_DIRNAME}/../helpers/mocks.bash" ]]; then
        source "${BATS_TEST_DIRNAME}/../helpers/mocks.bash"
    fi
}

teardown() {
    # Clean up sandbox
    rm -rf "${BATS_TMPDIR}/home_${BATS_TEST_NUMBER}" 2>/dev/null || true
    rm -rf "${BATS_TMPDIR}/mocks" 2>/dev/null || true
    rm -f "${BATS_TMPDIR}/mock_calls.log" 2>/dev/null || true

    # Restore HOME
    export HOME="$REAL_HOME"
}
