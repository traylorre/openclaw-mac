#!/usr/bin/env bash
# doctor.sh — Validate all prerequisite tools are installed
# Constitution VI: set -euo pipefail, shellcheck clean, idempotent, colored output
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

# --- Color Setup ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

if [[ ! -t 1 ]]; then
    RED='' GREEN='' YELLOW='' BOLD='' NC=''
fi

# --- Counters ---
OK=0
ERRORS=0

report() {
    local status="$1" msg="$2"
    case "$status" in
        OK)   printf "  %s✓%s  %s\n" "$GREEN" "$NC" "$msg"; OK=$((OK + 1)) ;;
        FAIL) printf "  %s✗%s  %s\n" "$RED" "$NC" "$msg"; ERRORS=$((ERRORS + 1)) ;;
        WARN) printf "  %s!%s  %s\n" "$YELLOW" "$NC" "$msg" ;;
    esac
}

check_tool() {
    local cmd="$1"
    local hint="${2:-}"
    local version=""

    if ! command -v "$cmd" &>/dev/null; then
        if [[ -n "$hint" ]]; then
            report FAIL "$cmd — not found (install: $hint)"
        else
            report FAIL "$cmd — not found"
        fi
        return
    fi

    # Try --version first, then version (for openssl), then fall back to path
    version=$("$cmd" --version 2>/dev/null | head -1) || true
    if [[ -z "$version" ]]; then
        version=$("$cmd" version 2>/dev/null | head -1) || true
    fi

    if [[ -n "$version" ]]; then
        report OK "$cmd — $version"
    else
        report OK "$cmd — installed ($(command -v "$cmd"))"
    fi
}

check_bash_version() {
    local bash_path
    bash_path=$(command -v bash 2>/dev/null) || true

    if [[ -z "$bash_path" ]]; then
        report FAIL "bash — not found"
        return
    fi

    local version
    version=$("$bash_path" --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1) || true
    local major
    major=$(echo "$version" | cut -d. -f1)

    if [[ "$major" -ge 5 ]]; then
        report OK "bash $version — ($bash_path)"
    else
        report FAIL "bash $version — requires >= 5.0 (install: brew install bash)"
    fi
}

main() {
    echo ""
    printf "%sOpenClaw Doctor%s\n" "$BOLD" "$NC"
    echo "═══════════════════════════════════════"

    echo ""
    printf "%sCore Tools%s\n" "$BOLD" "$NC"

    check_bash_version
    check_tool jq "brew install jq"
    check_tool shellcheck "brew install shellcheck"

    echo ""
    printf "%sContainer Runtime%s\n" "$BOLD" "$NC"

    check_tool docker "brew install docker"
    check_tool colima "brew install colima"

    echo ""
    printf "%sMonitoring & Security%s\n" "$BOLD" "$NC"

    check_tool fswatch "brew install fswatch"
    check_tool openssl "brew install openssl"

    echo ""
    printf "%sAI & Automation%s\n" "$BOLD" "$NC"

    check_tool ollama "brew install ollama"

    echo ""
    printf "%sSystem Utilities%s\n" "$BOLD" "$NC"

    check_tool shasum ""
    check_tool curl ""

    # security (Keychain CLI) - no --version flag, handle separately
    if command -v security &>/dev/null; then
        report OK "security — Keychain CLI ($(command -v security))"
    else
        report FAIL "security — Keychain CLI not found (system tool, should always be present)"
    fi

    echo ""
    echo "═══════════════════════════════════════"
    printf "  %s%s OK%s  |  " "$GREEN" "$OK" "$NC"
    if [[ $ERRORS -gt 0 ]]; then
        printf "%s%s FAIL%s\n" "$RED" "$ERRORS" "$NC"
    else
        printf "%s0 FAIL%s\n" "$GREEN" "$NC"
    fi
    echo "═══════════════════════════════════════"

    if [[ $ERRORS -gt 0 ]]; then
        echo ""
        printf "%sFix the errors above, then re-run: make doctor%s\n" "$RED" "$NC"
        exit 1
    fi

    echo ""
    printf "%sAll prerequisites satisfied.%s\n" "$GREEN" "$NC"
    exit 0
}

main "$@"
