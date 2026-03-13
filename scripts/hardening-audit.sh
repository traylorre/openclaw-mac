#!/usr/bin/env bash
# macOS Hardening Audit Script for n8n + Apify Deployment
# See docs/HARDENING.md §11 for full reference
set -euo pipefail

readonly VERSION="0.1.0"
readonly SCRIPT_NAME="$(basename "$0")"

# --- Color Setup ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Auto-disable colors when stdout is not a terminal
if [[ ! -t 1 ]]; then
    RED='' GREEN='' YELLOW='' BOLD='' NC=''
fi

# --- Counters ---
TOTAL=0
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
SKIP_COUNT=0

# --- Options ---
JSON_OUTPUT=false
FILTER_SECTION=""
QUIET=false
NO_COLOR=false

# --- JSON accumulator ---
JSON_RESULTS="[]"

# --- Platform Check ---
check_platform() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        echo "Error: This script requires macOS." >&2
        exit 2
    fi
    if ! bash --version | head -1 | grep -q 'version [5-9]'; then
        echo "Error: This script requires bash 5.x or later." >&2
        exit 2
    fi
}

# --- Deployment Detection ---
# Docker+n8n container → containerized; native n8n process → bare-metal; else → unknown
detect_deployment() {
    if command -v docker &>/dev/null && docker ps 2>/dev/null | grep -q n8n; then
        echo "containerized"
    elif pgrep -f "n8n" &>/dev/null; then
        echo "bare-metal"
    else
        echo "unknown"
    fi
}

# --- Usage ---
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

macOS hardening audit for n8n + Apify deployments.

Options:
  --json         Output results as JSON
  --section SEC  Run only checks for the given section (e.g., "os", "network")
  --quiet        Suppress PASS and WARN results (show only FAIL)
  --no-color     Disable colored output
  --version      Show version and exit
  --help         Show this help message and exit

Exit Codes:
  0  All checks passed
  1  One or more checks failed
  2  Script error

See docs/HARDENING.md §11 for full documentation.
EOF
}

# --- Result Reporting ---
# Usage: report_result ID SECTION DESCRIPTION STATUS GUIDE_REF [REMEDIATION]
report_result() {
    local id="$1"
    local section="$2"
    local description="$3"
    local status="$4"
    local guide_ref="$5"
    local remediation="${6:-}"

    # Filter by section if requested
    if [[ -n "$FILTER_SECTION" && "$section" != "$FILTER_SECTION" ]]; then
        return
    fi

    TOTAL=$((TOTAL + 1))
    case "$status" in
        PASS) PASS_COUNT=$((PASS_COUNT + 1)) ;;
        FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
        WARN) WARN_COUNT=$((WARN_COUNT + 1)) ;;
        SKIP) SKIP_COUNT=$((SKIP_COUNT + 1)) ;;
    esac

    # JSON accumulation
    if $JSON_OUTPUT; then
        local json_entry
        json_entry=$(printf '{"id":"%s","section":"%s","description":"%s","status":"%s","guide_ref":"%s"' \
            "$id" "$section" "$description" "$status" "$guide_ref")
        if [[ -n "$remediation" ]]; then
            json_entry="${json_entry},\"remediation\":\"${remediation}\"}"
        else
            json_entry="${json_entry}}"
        fi
        # Append to results array
        if [[ "$JSON_RESULTS" == "[]" ]]; then
            JSON_RESULTS="[${json_entry}]"
        else
            JSON_RESULTS="${JSON_RESULTS%]},$json_entry]"
        fi
        return
    fi

    # Quiet mode: suppress PASS and WARN
    if $QUIET && [[ "$status" == "PASS" || "$status" == "WARN" ]]; then
        return
    fi

    # Terminal output
    local color=""
    case "$status" in
        PASS) color="$GREEN" ;;
        FAIL) color="$RED" ;;
        WARN) color="$YELLOW" ;;
        SKIP) color="" ;;
    esac

    printf "${color}[%s]${NC} %-8s %s -> §%s\n" "$status" "$id" "$description" "$guide_ref"
}

# --- Check Runner ---
# Runs a check function in a subshell with || true to avoid set -e termination
# Usage: run_check CHECK_FUNCTION_NAME
run_check() {
    local check_fn="$1"
    ( "$check_fn" ) || true
}

# --- Check Functions ---
# Each check function calls report_result with its findings.
# Checks are added by implementation tasks (T009, T014, T019, etc.)

check_sip() {
    local id="CHK-OS-001"
    local output
    output=$(csrutil status 2>&1) || true
    if echo "$output" | grep -q "enabled"; then
        report_result "$id" "os" "System Integrity Protection enabled" "PASS" "2.3"
    else
        report_result "$id" "os" "System Integrity Protection disabled" "FAIL" "2.3" \
            "Enable SIP: boot to Recovery Mode and run 'csrutil enable'"
    fi
}

check_filevault() {
    local id="CHK-OS-002"
    local output
    output=$(fdesetup status 2>&1) || true
    if echo "$output" | grep -q "On"; then
        report_result "$id" "os" "FileVault disk encryption enabled" "PASS" "2.1"
    else
        report_result "$id" "os" "FileVault disk encryption disabled" "FAIL" "2.1" \
            "Enable FileVault: sudo fdesetup enable"
    fi
}

check_firewall() {
    local id="CHK-OS-003"
    local output
    output=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>&1) || true
    if echo "$output" | grep -q "enabled"; then
        report_result "$id" "os" "Application firewall enabled" "PASS" "2.2"
    else
        report_result "$id" "os" "Application firewall disabled" "FAIL" "2.2" \
            "Enable firewall: sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on"
    fi
}

check_stealth_mode() {
    local id="CHK-OS-004"
    local output
    output=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode 2>&1) || true
    if echo "$output" | grep -q "enabled"; then
        report_result "$id" "os" "Firewall stealth mode enabled" "PASS" "2.2"
    else
        report_result "$id" "os" "Firewall stealth mode disabled" "WARN" "2.2" \
            "Enable stealth mode: sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on"
    fi
}

# --- Main ---
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            --section)
                FILTER_SECTION="${2:-}"
                if [[ -z "$FILTER_SECTION" ]]; then
                    echo "Error: --section requires an argument" >&2
                    exit 2
                fi
                shift 2
                ;;
            --quiet)
                QUIET=true
                shift
                ;;
            --no-color)
                NO_COLOR=true
                RED='' GREEN='' YELLOW='' BOLD='' NC=''
                shift
                ;;
            --version)
                echo "${SCRIPT_NAME} v${VERSION}"
                exit 0
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                echo "Error: Unknown option '$1'" >&2
                usage >&2
                exit 2
                ;;
        esac
    done

    check_platform

    local deployment
    deployment=$(detect_deployment)
    local macos_version
    macos_version=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
    local hardware
    hardware=$(uname -m 2>/dev/null || echo "unknown")

    if ! $JSON_OUTPUT; then
        echo "${BOLD}macOS Hardening Audit${NC}"
        echo "macOS ${macos_version} | ${hardware} | Deployment: ${deployment}"
        echo "---"
    fi

    # --- Run All Checks ---
    # OS Foundation checks (migrated from existing verification script)
    run_check check_sip
    run_check check_filevault
    run_check check_firewall
    run_check check_stealth_mode

    # Additional check groups added by later tasks:
    # T009: OS Foundation checks
    # T014: Network Security checks
    # T019: Container Isolation checks
    # T024: n8n Platform checks
    # T029: Bare-Metal checks
    # T034: Data Security checks
    # T039: Detection and Monitoring checks
    # T044: Response and Recovery checks

    # --- Output ---
    if $JSON_OUTPUT; then
        local json_output
        json_output=$(printf '{
  "version": "%s",
  "timestamp": "%s",
  "system": {
    "macos_version": "%s",
    "hardware": "%s",
    "deployment": "%s"
  },
  "results": %s,
  "summary": {
    "total": %d,
    "pass": %d,
    "fail": %d,
    "warn": %d,
    "skip": %d
  }
}' "$VERSION" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   "$macos_version" "$hardware" "$deployment" \
   "$JSON_RESULTS" \
   "$TOTAL" "$PASS_COUNT" "$FAIL_COUNT" "$WARN_COUNT" "$SKIP_COUNT")

        if command -v jq &>/dev/null; then
            echo "$json_output" | jq .
        else
            echo "$json_output"
        fi
    else
        echo "---"
        printf "Results: ${GREEN}%d PASS${NC} | ${RED}%d FAIL${NC} | ${YELLOW}%d WARN${NC}" \
            "$PASS_COUNT" "$FAIL_COUNT" "$WARN_COUNT"
        if [[ $SKIP_COUNT -gt 0 ]]; then
            printf " | %d SKIP" "$SKIP_COUNT"
        fi
        echo ""
    fi

    # Exit code: 1 if any FAIL, 0 otherwise
    if [[ $FAIL_COUNT -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
