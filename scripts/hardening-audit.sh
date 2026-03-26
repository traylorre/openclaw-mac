#!/usr/bin/env bash
# macOS Hardening Audit Script for n8n + Apify Deployment
# See docs/HARDENING.md §11 for full reference

# --- Bash 5.x auto-detect (sudo + macOS /bin/bash = 3.x) ---
if [[ "${BASH_VERSINFO[0]}" -lt 5 ]]; then
    for _try_bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        if [[ -x "$_try_bash" ]]; then exec "$_try_bash" "$0" "$@"; fi
    done
    echo "Error: bash 5.x required. Install: brew install bash" >&2; exit 2
fi

set -euo pipefail

# --- Browser Registry ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=browser-registry.sh
source "${SCRIPT_DIR}/browser-registry.sh"

readonly VERSION="0.1.0"
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME

# --- Color Setup ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Auto-disable colors when stdout is not a terminal
if [[ ! -t 1 ]]; then
    RED='' GREEN='' YELLOW='' CYAN='' DIM='' NC=''
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
DEBUG=false
COMPARE_FILE=""
# NO_COLOR is a conventional env flag; --no-color sets color vars directly
# shellcheck disable=SC2034
NO_COLOR=false

# --- JSON accumulator ---
JSON_RESULTS="[]"

# --- Current section for grouped output ---
CURRENT_SECTION=""

# --- Summary collectors for end-of-audit report ---
declare -a FAIL_SUMMARIES=()
declare -a WARN_ACTIONABLE=()
declare -a WARN_OPTIONAL=()


# --- User Scope ---
# When run with sudo, user-scoped defaults reads must target the
# invoking user, not root. SUDO_USER is set automatically by sudo.
run_as_user() {
    if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
        sudo -u "$SUDO_USER" "$@"
    else
        "$@"
    fi
}

# --- JSON string escaper ---
# Escapes characters that would break JSON string values
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

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
    if command -v docker &>/dev/null && run_as_user docker ps 2>/dev/null | grep -q n8n; then
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
  --json         Output results in JSON format (FR-023)
  --section SEC  Run checks for a specific section only
  --quiet        Suppress PASS output, show only FAIL/WARN
  --compare FILE Compare results against a previous audit JSON file
                 and show regressions/improvements (drift report)
  --no-color     Disable colored output (for piping/logging)
  --debug        Enable bash trace output (set -x)
  --version      Show version and exit
  --help         Show this help message and exit

Exit Codes:
  0  All checks passed (zero FAIL results)
  1  One or more FAIL results
  2  Script error (missing dependency, permission denied)

See docs/HARDENING.md §11 for full documentation.
EOF
}

# --- Section Header ---
# Prints a section header for grouped human-readable output
print_section_header() {
    local section="$1"
    if ! $JSON_OUTPUT && [[ "$section" != "$CURRENT_SECTION" ]]; then
        CURRENT_SECTION="$section"
        echo ""
        echo "[Section: ${section}]"
    fi
}

# --- Result Reporting ---
# Usage: report_result ID SECTION DESCRIPTION STATUS GUIDE_REF [REMEDIATION] [BROWSER] [PRIORITY]
# PRIORITY: "recommended" = actionable WARN shown in Recommended summary
#           "" (default)  = informational WARN shown in Optional summary
report_result() {
    local id="$1"
    local section="$2"
    local description="$3"
    local status="$4"
    local guide_ref="$5"
    local remediation="${6:-}"
    local browser="${7:-}"  # optional: browser display name for CHK-BROWSER-* checks
    local priority="${8:-}" # optional: "recommended" for actionable WARNs

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

    # JSON accumulation (always, for --compare support even in terminal mode)
    local json_entry
    json_entry=$(printf '{"id":"%s","section":"%s","description":"%s","status":"%s","guide_ref":"§%s"' \
        "$(json_escape "$id")" "$(json_escape "$section")" \
        "$(json_escape "$description")" "$(json_escape "$status")" \
        "$(json_escape "$guide_ref")")
    if [[ -n "$browser" ]]; then
        json_entry="${json_entry},\"browser\":\"$(json_escape "$browser")\""
    fi
    if [[ -n "$remediation" ]]; then
        json_entry="${json_entry},\"remediation\":\"$(json_escape "$remediation")\"}"
    else
        json_entry="${json_entry}}"
    fi
    if [[ "$JSON_RESULTS" == "[]" ]]; then
        JSON_RESULTS="[${json_entry}]"
    else
        JSON_RESULTS="${JSON_RESULTS%]},$json_entry]"
    fi

    # JSON-only mode: skip terminal output
    if $JSON_OUTPUT; then
        return
    fi

    # Quiet mode: suppress PASS output, show FAIL/WARN
    if $QUIET && [[ "$status" == "PASS" ]]; then
        return
    fi

    # Print section header if new section
    print_section_header "$section"

    # Terminal output
    local color=""
    case "$status" in
        PASS) color="$GREEN" ;;
        FAIL) color="$RED" ;;
        WARN) color="$YELLOW" ;;
        SKIP) color="$CYAN" ;;
    esac

    printf "  ${color}%-4s${NC}  %-44s → §%s\n" "$status" "$description" "$guide_ref"

    # Show inline remediation hint for WARN/FAIL
    if [[ -n "$remediation" && ("$status" == "WARN" || "$status" == "FAIL") ]]; then
        printf "        ${CYAN}↳ %s${NC}\n" "$remediation"
    fi

    # Collect for end-of-audit summary
    if [[ "$status" == "FAIL" && -n "$remediation" ]]; then
        FAIL_SUMMARIES+=("$description|$remediation")
    elif [[ "$status" == "WARN" && "$priority" == "recommended" ]]; then
        WARN_ACTIONABLE+=("$description|${remediation:-See §${guide_ref}}")
    elif [[ "$status" == "WARN" ]]; then
        WARN_OPTIONAL+=("$description|${remediation:-}")
    fi
}

# --- Check Runner ---
# Runs a check function with || true to prevent set -e from aborting on failure.
# Must NOT use a subshell — counters and CURRENT_SECTION must propagate.
# Usage: run_check CHECK_FUNCTION_NAME
run_check() {
    local check_fn="$1"
    "$check_fn" || true
}

# --- Check Functions ---
# Each check function calls report_result with its findings.
# Checks are added by implementation tasks (T009, T014, T019, etc.)

check_sip() {
    local id="CHK-SIP"
    local output
    output=$(csrutil status 2>&1) || true
    if echo "$output" | grep -q "enabled"; then
        report_result "$id" "System Integrity Protection" "SIP is enabled" "PASS" "2.3"
    else
        report_result "$id" "System Integrity Protection" "SIP is disabled" "FAIL" "2.3" \
            "Enable SIP: boot to Recovery Mode and run 'csrutil enable'"
    fi
}

check_filevault() {
    local id="CHK-FILEVAULT"
    local output
    output=$(fdesetup status 2>&1) || true
    if echo "$output" | grep -q "On"; then
        report_result "$id" "Disk Encryption" "FileVault is enabled" "PASS" "2.1"
    else
        report_result "$id" "Disk Encryption" "FileVault is disabled" "FAIL" "2.1" \
            "Enable FileVault: sudo fdesetup enable"
    fi
}

check_firewall() {
    local id="CHK-FIREWALL"
    local output
    output=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>&1) || true
    if echo "$output" | grep -q "Firewall is enabled"; then
        report_result "$id" "Firewall" "Application firewall is enabled" "PASS" "2.2"
    else
        report_result "$id" "Firewall" "Application firewall is disabled" "FAIL" "2.2" \
            "Enable firewall: sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on"
    fi
}

check_stealth_mode() {
    local id="CHK-STEALTH"
    local output
    output=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode 2>&1) || true
    if echo "$output" | grep -q "Stealth mode enabled"; then
        report_result "$id" "Firewall" "Stealth mode is enabled" "PASS" "2.2"
    else
        report_result "$id" "Firewall" "Stealth mode is not enabled" "WARN" "2.2" \
            "Enable stealth mode: sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on"
    fi
}

# --- §2 OS Foundation Checks (T014) ---

check_gatekeeper() {
    local id="CHK-GATEKEEPER"
    local output
    output=$(spctl --status 2>&1) || true
    if echo "$output" | grep -q "assessments enabled"; then
        report_result "$id" "Gatekeeper" "Gatekeeper is enabled" "PASS" "2.4"
    else
        report_result "$id" "Gatekeeper" "Gatekeeper is disabled" "FAIL" "2.4" \
            "Enable Gatekeeper: sudo spctl --master-enable"
    fi
}

check_xprotect_fresh() {
    local id="CHK-XPROTECT-FRESH"
    local last_update
    last_update=$(system_profiler SPInstallHistoryDataType 2>/dev/null \
        | grep -B 1 "XProtect" | grep "Install Date" | tail -1 \
        | sed 's/.*Install Date: //' | xargs) || true
    if [[ -z "$last_update" ]]; then
        report_result "$id" "XProtect" "Cannot determine XProtect update date" "SKIP" "2.4"
        return
    fi
    local update_epoch current_epoch age_days
    # Try multiple date formats: zero-padded and ISO
    update_epoch=$(date -j -f "%m/%d/%y, %I:%M %p" "$last_update" "+%s" 2>/dev/null) || \
    update_epoch=$(date -j -f "%Y-%m-%d" "$last_update" "+%s" 2>/dev/null) || true
    if [[ -z "$update_epoch" ]]; then
        report_result "$id" "XProtect" "XProtect update date: ${last_update}" "WARN" "2.4" \
            "Verify XProtect is up to date via softwareupdate --list"
        return
    fi
    current_epoch=$(date "+%s")
    age_days=$(( (current_epoch - update_epoch) / 86400 ))
    if [[ $age_days -le 14 ]]; then
        report_result "$id" "XProtect" "XProtect updated ${age_days}d ago" "PASS" "2.4"
    else
        report_result "$id" "XProtect" "XProtect last updated ${age_days}d ago" "WARN" "2.4" \
            "Run: softwareupdate --list to check for XProtect updates"
    fi
}

check_auto_updates() {
    local id="CHK-AUTO-UPDATES"
    local auto_check
    auto_check=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled 2>/dev/null) || true
    local critical
    critical=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall 2>/dev/null) || true
    if [[ "$auto_check" == "1" && "$critical" == "1" ]]; then
        report_result "$id" "Software Updates" "Automatic updates enabled" "PASS" "2.5"
    else
        report_result "$id" "Software Updates" "Automatic updates not fully enabled" "WARN" "2.5" \
            "Enable: sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true"
    fi
}

check_ntp() {
    local id="CHK-NTP"
    local output
    output=$(systemsetup -getusingnetworktime 2>&1) || true
    if echo "$output" | grep -qi "on"; then
        report_result "$id" "NTP" "Network time is enabled" "PASS" "2.5"
    else
        report_result "$id" "NTP" "Network time is disabled" "WARN" "2.5" \
            "Enable: sudo systemsetup -setusingnetworktime on"
    fi
}

check_auto_login() {
    local id="CHK-AUTO-LOGIN"
    local output
    output=$(defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>&1) || true
    if echo "$output" | grep -q "does not exist"; then
        report_result "$id" "Login Security" "Auto-login is disabled" "PASS" "2.6"
    elif [[ -z "$output" ]]; then
        report_result "$id" "Login Security" "Auto-login is disabled" "PASS" "2.6"
    else
        report_result "$id" "Login Security" "Auto-login is enabled" "FAIL" "2.6" \
            "Disable: sudo defaults delete /Library/Preferences/com.apple.loginwindow autoLoginUser"
    fi
}

check_screen_lock() {
    local id="CHK-SCREEN-LOCK"
    local ask_pw
    ask_pw=$(run_as_user defaults read com.apple.screensaver askForPassword 2>/dev/null) || true
    local delay
    delay=$(run_as_user defaults read com.apple.screensaver askForPasswordDelay 2>/dev/null) || true
    if [[ "$ask_pw" == "1" && "$delay" == "0" ]]; then
        report_result "$id" "Login Security" "Screen lock requires password immediately" "PASS" "2.6"
    else
        report_result "$id" "Login Security" "Screen lock not configured optimally" "WARN" "2.6" \
            "Set: defaults write com.apple.screensaver askForPassword -int 1 && defaults write com.apple.screensaver askForPasswordDelay -int 0"
    fi
}

check_password_policy() {
    local id="CHK-PASSWORD-POLICY"
    # pwpolicy getaccountpolicies returns XML with policy rules
    local policy_xml
    policy_xml=$(pwpolicy getaccountpolicies 2>/dev/null) || policy_xml=""

    if [[ -z "$policy_xml" || "$policy_xml" == *"No account policies"* ]]; then
        report_result "$id" "Login Security" \
            "No password policy configured (no minimum length or lockout)" "WARN" "2.6" \
            "Requires MDM or manual pwpolicy configuration"
        return
    fi

    # Check for minimum length requirement (minChars or policyAttributePassword has minLength)
    local has_length=false has_lockout=false
    if echo "$policy_xml" | grep -qiE 'minLength|minChars|policyAttributePasswordMinLength'; then
        has_length=true
    fi
    # Check for account lockout (maxFailedLoginAttempts or policyAttributeMaximumFailedAuthentications)
    if echo "$policy_xml" | grep -qiE 'maxFailedLoginAttempts|policyAttributeMaximumFailedAuthentications|maximumFailedAuthentication'; then
        has_lockout=true
    fi

    if $has_length && $has_lockout; then
        report_result "$id" "Login Security" \
            "Password policy active (minimum length + account lockout)" "PASS" "2.6"
    elif $has_length; then
        report_result "$id" "Login Security" \
            "Password policy has minimum length but no account lockout" "WARN" "2.6" \
            "Add lockout via MDM or pwpolicy"
    elif $has_lockout; then
        report_result "$id" "Login Security" \
            "Password policy has account lockout but no minimum length" "WARN" "2.6" \
            "Add minimum length via MDM or pwpolicy"
    else
        report_result "$id" "Login Security" \
            "Password policy exists but lacks length and lockout rules" "WARN" "2.6" \
            "Requires MDM or manual pwpolicy configuration"
    fi
}

check_guest() {
    local id="CHK-GUEST"
    local output
    output=$(sudo defaults read /Library/Preferences/com.apple.loginwindow GuestEnabled 2>/dev/null) || true
    if [[ "$output" == "0" ]]; then
        report_result "$id" "Guest Account" "Guest account is disabled" "PASS" "2.7"
    else
        report_result "$id" "Guest Account" "Guest account is enabled" "FAIL" "2.7" \
            "Disable: sudo defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false"
    fi
}

check_sharing_file() {
    local id="CHK-SHARING-FILE"
    local output
    output=$(launchctl print system/com.apple.smbd 2>&1) || true
    if echo "$output" | grep -qi "could not find service"; then
        report_result "$id" "Sharing Services" "File Sharing (SMB) is disabled" "PASS" "2.7"
    elif echo "$output" | grep -q "state = running"; then
        report_result "$id" "Sharing Services" "File Sharing (SMB) is running" "FAIL" "2.7" \
            "Disable: sudo launchctl disable system/com.apple.smbd (reboot required, or also run: sudo launchctl bootout system/com.apple.smbd)"
    else
        report_result "$id" "Sharing Services" "File Sharing (SMB) is loaded but not running" "WARN" "2.7"
    fi
}

check_sharing_remote_events() {
    local id="CHK-SHARING-REMOTE-EVENTS"
    local output
    output=$(sudo systemsetup -getremoteappleevents 2>&1) || true
    if echo "$output" | grep -qi "off"; then
        report_result "$id" "Sharing Services" "Remote Apple Events is disabled" "PASS" "2.7"
    else
        report_result "$id" "Sharing Services" "Remote Apple Events is enabled" "FAIL" "2.7" \
            "Disable: sudo systemsetup -setremoteappleevents off (Terminal needs Full Disk Access)"
    fi
}

check_sharing_internet() {
    local id="CHK-SHARING-INTERNET"
    local output
    output=$(defaults read /Library/Preferences/SystemConfiguration/com.apple.nat NAT 2>/dev/null) || true
    if echo "$output" | grep -q "Enabled = 1"; then
        report_result "$id" "Sharing Services" "Internet Sharing is enabled" "FAIL" "2.7" \
            "Disable Internet Sharing in System Settings > General > Sharing"
    else
        report_result "$id" "Sharing Services" "Internet Sharing is disabled" "PASS" "2.7"
    fi
}

check_sharing_screen() {
    local id="CHK-SHARING-SCREEN"
    local output
    output=$(launchctl print system/com.apple.screensharing 2>&1) || true
    if echo "$output" | grep -qi "could not find service"; then
        report_result "$id" "Sharing Services" "Screen Sharing is disabled" "PASS" "2.7"
    elif echo "$output" | grep -q "state = running"; then
        report_result "$id" "Sharing Services" "Screen Sharing is running" "WARN" "2.7" \
            "Disable if not needed: sudo launchctl disable system/com.apple.screensharing"
    else
        report_result "$id" "Sharing Services" "Screen Sharing is loaded" "WARN" "2.7"
    fi
}

check_airdrop() {
    local id="CHK-AIRDROP"
    local output
    output=$(run_as_user defaults read com.apple.NetworkBrowser DisableAirDrop 2>/dev/null) || true
    if [[ "$output" == "1" ]]; then
        report_result "$id" "Sharing Services" "AirDrop is disabled" "PASS" "2.7"
    else
        report_result "$id" "Sharing Services" "AirDrop is enabled" "WARN" "2.7" \
            "Disable: defaults write com.apple.NetworkBrowser DisableAirDrop -bool true"
    fi
}

check_startup_security() {
    local id="CHK-STARTUP-SECURITY"
    local arch
    arch=$(uname -m 2>/dev/null) || true
    if [[ "$arch" == "arm64" ]]; then
        # Apple Silicon — Recovery Mode auth is enforced by Secure Enclave
        report_result "$id" "Startup Security" "Apple Silicon — Secure Enclave enforces startup security" "PASS" "2.9"
    else
        # Intel — check firmware password
        local output
        output=$(sudo firmwarepasswd -check 2>&1) || true
        if echo "$output" | grep -q "Yes"; then
            report_result "$id" "Startup Security" "Firmware password is set" "PASS" "2.9"
        else
            report_result "$id" "Startup Security" "No firmware password set (Intel)" "WARN" "2.9" \
                "Requires Recovery Mode boot — see §2.9"
        fi
    fi
}

check_tcc() {
    local id="CHK-TCC"
    # Check if any sensitive TCC permissions are granted to unexpected apps
    local tcc_db="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
    if [[ ! -r "$tcc_db" ]]; then
        report_result "$id" "TCC" "Cannot read TCC database (FDA required)" "SKIP" "2.10"
        return
    fi
    local fda_count
    fda_count=$(sqlite3 "$tcc_db" \
        "SELECT COUNT(*) FROM access WHERE service = 'kTCCServiceSystemPolicyAllFiles' AND auth_value = 2;" 2>/dev/null) || true
    if [[ -z "$fda_count" || "$fda_count" == "0" ]]; then
        report_result "$id" "TCC" "No Full Disk Access grants detected" "PASS" "2.10"
    else
        report_result "$id" "TCC" "${fda_count} app(s) have Full Disk Access" "WARN" "2.10" \
            "Review: tccutil to audit and restrict TCC grants"
    fi
}

check_core_dumps() {
    local id="CHK-CORE-DUMPS"
    local core_files
    core_files=$(ls /cores/ 2>/dev/null | wc -l | tr -d ' ') || true
    local core_limit
    core_limit=$(launchctl limit core 2>/dev/null | awk '{print $2}') || true
    if [[ "$core_files" != "0" ]]; then
        report_result "$id" "Core Dumps" "Core dump files found in /cores/" "WARN" "2.10" \
            "Remove: sudo rm -f /cores/core.* and disable: sudo launchctl limit core 0"
    elif [[ "$core_limit" == "0" ]]; then
        report_result "$id" "Core Dumps" "Core dumps are disabled" "PASS" "2.10"
    else
        report_result "$id" "Core Dumps" "Core dumps are not disabled" "WARN" "2.10" \
            "Disable: sudo launchctl limit core 0"
    fi
}

check_privacy() {
    local id="CHK-PRIVACY"
    local siri
    siri=$(run_as_user defaults read com.apple.assistant.support "Assistant Enabled" 2>/dev/null) || true
    if [[ "$siri" == "0" ]]; then
        report_result "$id" "System Privacy" "Siri is disabled" "PASS" "2.10"
    else
        report_result "$id" "System Privacy" "Siri is enabled" "WARN" "2.10" \
            "Disable: defaults write com.apple.assistant.support 'Assistant Enabled' -bool false"
    fi
}

check_profiles() {
    local id="CHK-PROFILES"
    local output
    output=$(profiles list 2>&1) || true
    if echo "$output" | grep -qi "no profiles"; then
        report_result "$id" "Configuration Profiles" "No configuration profiles installed" "PASS" "2.10"
    elif echo "$output" | grep -qi "error"; then
        report_result "$id" "Configuration Profiles" "Cannot check profiles" "SKIP" "2.10"
    else
        local count
        count=$(echo "$output" | grep -c "profileIdentifier" 2>/dev/null) || count=0
        report_result "$id" "Configuration Profiles" "${count} profile(s) installed" "WARN" "2.10" \
            "Normal for unmanaged Macs — MDM profiles only"
    fi
}

check_spotlight() {
    local id="CHK-SPOTLIGHT"
    # Check if common sensitive paths are excluded from Spotlight
    # This is informational — we can't know the exact n8n data path
    local n8n_paths=("$HOME/.n8n" "$HOME/.colima")
    local indexed=0
    for path in "${n8n_paths[@]}"; do
        if [[ -d "$path" ]]; then
            local status
            status=$(mdutil -s "$path" 2>/dev/null) || true
            if echo "$status" | grep -q "Indexing enabled"; then
                indexed=$((indexed + 1))
            fi
        fi
    done
    if [[ $indexed -eq 0 ]]; then
        report_result "$id" "Spotlight" "Sensitive directories not indexed (or not present)" "PASS" "2.10"
    else
        report_result "$id" "Spotlight" "${indexed} sensitive dir(s) are Spotlight-indexed" "WARN" "2.10" \
            "Exclude: sudo mdutil -i off /path/to/sensitive/dir"
    fi
}

# --- §4.1 Container Runtime (Colima) ---

check_colima_running() {
    local id="CHK-COLIMA-RUNNING"
    if ! command -v colima &>/dev/null; then
        if run_as_user docker info &>/dev/null; then
            report_result "$id" "Container Runtime" \
                "Docker available but Colima not installed (non-standard runtime)" "WARN" "4.1" \
                "Install: brew install colima"
        else
            report_result "$id" "Container Runtime" \
                "Colima not installed" "SKIP" "4.1" \
                "Install: brew install colima docker"
        fi
        return
    fi

    if ! run_as_user colima status &>/dev/null; then
        report_result "$id" "Container Runtime" \
            "Colima is installed but not running" "WARN" "4.1" \
            "Start with: make setup-gateway"
        return
    fi

    # Verify Docker socket is actually reachable (catches stale socket after crash)
    if run_as_user docker info &>/dev/null; then
        local colima_ver
        colima_ver=$(run_as_user colima version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || colima_ver="unknown"
        report_result "$id" "Container Runtime" \
            "Colima running (${colima_ver}), Docker socket reachable" "PASS" "4.1"
    else
        report_result "$id" "Container Runtime" \
            "Colima reports running but Docker socket unreachable" "WARN" "4.1" \
            "Try: colima stop && colima start"
    fi
}

# --- §4.1b Colima VM Boundary (012 Phase 3, TP3-027/028, FR-P3-028/029/030) ---

check_colima_vm_mounts() {
    local id="CHK-COLIMA-VM-MOUNTS"
    # Resolve HOME symlinks for accurate path comparison (macOS APFS /Users → /System/Volumes/Data/Users)
    local resolved_home
    resolved_home=$(cd "$HOME" 2>/dev/null && pwd -P)

    if ! command -v colima &>/dev/null; then
        report_result "$id" "VM Boundary" "Colima not installed — skipping VM mount check" "SKIP" "4.1"
        return
    fi

    # Detect active Colima profile
    local profile="default"
    local colima_list
    colima_list=$(run_as_user colima list 2>/dev/null || true)
    if [[ -n "$colima_list" ]]; then
        # Parse the PROFILE column for running instances
        local running_profile
        running_profile=$(echo "$colima_list" | awk 'NR>1 && $2=="Running" {print $1}' | head -1)
        if [[ -n "$running_profile" ]]; then
            profile="$running_profile"
        fi
    fi

    local config_path="${HOME}/.colima/${profile}/colima.yaml"
    if [[ ! -f "$config_path" ]]; then
        report_result "$id" "VM Boundary" "Colima config not found at ${config_path}" "SKIP" "4.1" \
            "Profile '${profile}' may not exist or may use non-default location"
        return
    fi

    # Parse YAML mounts section
    local writable_home=false
    local mount_info=""

    # Check for empty array: mounts: [] (default = writable $HOME)
    if grep -qE '^\s*mounts:\s*\[\]' "$config_path"; then
        writable_home=true
        mount_info="mounts: [] (default — writable \$HOME)"
    # Check for missing mounts section entirely (same as default)
    elif ! grep -q '^\s*mounts:' "$config_path"; then
        writable_home=true
        mount_info="no mounts section (default — writable \$HOME)"
    else
        # Parse explicit mount entries
        # awk: capture mounts block, handling blank lines + EOF correctly
        local mount_block
        mount_block=$(awk '/^\s*mounts:/{found=1; next} found && /^[a-zA-Z]/{exit} found' "$config_path" \
            | grep -E 'location:|writable:' || true)
        if [[ -n "$mount_block" ]]; then
            local current_loc=""
            while IFS= read -r line; do
                if echo "$line" | grep -q 'location:'; then
                    current_loc=$(echo "$line" | sed 's/.*location:\s*//' | sed 's/#.*//' | tr -d '"' | tr -d "'" | tr -d ' ')
                    # Expand tilde to $HOME
                    current_loc="${current_loc/#\~/$HOME}"
                elif echo "$line" | grep -q 'writable:'; then
                    local is_writable
                    is_writable=$(echo "$line" | sed 's/.*writable:\s*//' | sed 's/#.*//' | tr -d ' ')
                    # Check if this is the home directory or a parent of it
                    # Resolve mount location for symlink-safe comparison
                    local resolved_loc
                    resolved_loc=$(cd "$current_loc" 2>/dev/null && pwd -P || echo "$current_loc")
                    # Directory boundary check: use trailing slash to avoid /Use matching /Users
                    if [[ -n "$resolved_loc" ]] && [[ "${resolved_home}/" == "${resolved_loc}/"* || "${resolved_loc}/" == "${resolved_home}/"* ]]; then
                        if [[ "$is_writable" == "true" ]]; then
                            writable_home=true
                            mount_info="explicit mount: ${current_loc} writable=true"
                        fi
                    fi
                    mount_info="${mount_info:+${mount_info}; }${current_loc}:writable=${is_writable}"
                fi
            done <<< "$mount_block"
        else
            writable_home=true
            mount_info="mounts section exists but no explicit entries (default behavior)"
        fi
    fi

    if $writable_home; then
        report_result "$id" "VM Boundary" \
            "Home directory mounted WRITABLE in Colima VM — container escape exposes all host files" "WARN" "4.1" \
            "Remediation: Edit ${config_path} and set restrictive mounts:
  mounts:
    - location: ${HOME}
      writable: false
    - location: $(pwd)
      writable: true
  Then restart: colima stop && colima start"
        # TP3-028: Audit log
        integrity_audit_log "vm_boundary_warning" "mount_info=${mount_info}, config=${config_path}" || true
    else
        report_result "$id" "VM Boundary" \
            "Colima VM mounts are restrictive (${mount_info})" "PASS" "4.1"
    fi
}

# --- §4 Container Isolation Checks (T024) ---

# CIS Docker Benchmark 5.x (non-root user) — also covered by docker-bench-security
check_container_root() {
    local id="CHK-CONTAINER-ROOT"
    local container_id
    container_id=$(run_as_user docker ps -q --filter "name=n8n" 2>/dev/null | head -1) || true
    if [[ -z "$container_id" ]]; then
        report_result "$id" "Container Security" "No n8n container running" "SKIP" "4.3"
        return
    fi
    local user
    user=$(run_as_user docker inspect "$container_id" --format '{{.Config.User}}' 2>/dev/null) || true
    if [[ -n "$user" && "$user" != "0" && "$user" != "root" ]]; then
        report_result "$id" "Container Security" "Container runs as non-root (${user})" "PASS" "4.3"
    else
        report_result "$id" "Container Security" "Container runs as root" "FAIL" "4.3" \
            "Set user: '1000:1000' in docker-compose.yml"
    fi
}

# CIS Docker Benchmark 5.13 (read-only rootfs) — also covered by docker-bench-security
check_container_readonly() {
    local id="CHK-CONTAINER-READONLY"
    local container_id
    container_id=$(run_as_user docker ps -q --filter "name=n8n" 2>/dev/null | head -1) || true
    if [[ -z "$container_id" ]]; then
        report_result "$id" "Container Security" "No n8n container running" "SKIP" "4.3"
        return
    fi
    local readonly_fs
    readonly_fs=$(run_as_user docker inspect "$container_id" --format '{{.HostConfig.ReadonlyRootfs}}' 2>/dev/null) || true
    if [[ "$readonly_fs" == "true" ]]; then
        report_result "$id" "Container Security" "Container filesystem is read-only" "PASS" "4.3"
    else
        report_result "$id" "Container Security" "Container filesystem is writable" "WARN" "4.3" \
            "Set read_only: true in docker-compose.yml with tmpfs for write paths"
    fi
}

# CIS Docker Benchmark 5.4 (restrict capabilities) — also covered by docker-bench-security
check_container_caps() {
    local id="CHK-CONTAINER-CAPS"
    local container_id
    container_id=$(run_as_user docker ps -q --filter "name=n8n" 2>/dev/null | head -1) || true
    if [[ -z "$container_id" ]]; then
        report_result "$id" "Container Security" "No n8n container running" "SKIP" "4.3"
        return
    fi
    local cap_drop
    cap_drop=$(run_as_user docker inspect "$container_id" --format '{{.HostConfig.CapDrop}}' 2>/dev/null) || true
    if echo "$cap_drop" | grep -qi "all"; then
        report_result "$id" "Container Security" "All capabilities dropped" "PASS" "4.3"
    else
        report_result "$id" "Container Security" "Capabilities not fully dropped" "WARN" "4.3" \
            "Set cap_drop: [ALL] in docker-compose.yml"
    fi
}

# CIS Docker Benchmark 5.5 (no privileged) — also covered by docker-bench-security
check_container_privileged() {
    local id="CHK-CONTAINER-PRIVILEGED"
    local container_id
    container_id=$(run_as_user docker ps -q --filter "name=n8n" 2>/dev/null | head -1) || true
    if [[ -z "$container_id" ]]; then
        report_result "$id" "Container Security" "No n8n container running" "SKIP" "4.3"
        return
    fi
    local privileged
    privileged=$(run_as_user docker inspect "$container_id" --format '{{.HostConfig.Privileged}}' 2>/dev/null) || true
    if [[ "$privileged" == "false" ]]; then
        report_result "$id" "Container Security" "Container is not privileged" "PASS" "4.3"
    else
        report_result "$id" "Container Security" "Container is running in privileged mode" "FAIL" "4.3" \
            "Remove privileged: true from docker-compose.yml immediately"
    fi
}

# CIS Docker Benchmark 5.32 (no docker.sock mount) — also covered by docker-bench-security
check_docker_socket() {
    local id="CHK-DOCKER-SOCKET"
    local container_id
    container_id=$(run_as_user docker ps -q --filter "name=n8n" 2>/dev/null | head -1) || true
    if [[ -z "$container_id" ]]; then
        report_result "$id" "Container Security" "No n8n container running" "SKIP" "4.3"
        return
    fi
    local mounts
    mounts=$(run_as_user docker inspect "$container_id" --format '{{json .Mounts}}' 2>/dev/null) || true
    if echo "$mounts" | grep -q "docker.sock"; then
        report_result "$id" "Container Security" "Docker socket is mounted — host escape possible" "FAIL" "4.3" \
            "Remove /var/run/docker.sock volume mount immediately"
    else
        report_result "$id" "Container Security" "Docker socket is not mounted" "PASS" "4.3"
    fi
}

check_secrets_env() {
    local id="CHK-SECRETS-ENV"
    local container_id
    container_id=$(run_as_user docker ps -q --filter "name=n8n" 2>/dev/null | head -1) || true
    if [[ -z "$container_id" ]]; then
        report_result "$id" "Container Security" "No n8n container running" "SKIP" "4.3"
        return
    fi
    local env_vars
    env_vars=$(run_as_user docker inspect "$container_id" --format '{{json .Config.Env}}' 2>/dev/null) || true
    if echo "$env_vars" | grep -qiE 'ENCRYPTION_KEY=|PASSWORD=|SECRET=|TOKEN=.*[a-zA-Z0-9]{8}|API_KEY='; then
        report_result "$id" "Container Security" "Secrets found in container environment" "WARN" "4.3" \
            "Use Docker secrets instead of environment variables — see §4.3"
    else
        report_result "$id" "Container Security" "No secrets in container environment" "PASS" "4.3"
    fi
}

# CIS Docker Benchmark 5.6 (sensitive host dirs) — partially covered by docker-bench-securitycheck_colima_mounts() {
    local id="CHK-COLIMA-MOUNTS"
    local container_id
    container_id=$(run_as_user docker ps -q --filter "name=n8n" 2>/dev/null | head -1) || true
    if [[ -z "$container_id" ]]; then
        report_result "$id" "Container Security" "No n8n container running" "SKIP" "4.3"
        return
    fi
    local mounts
    mounts=$(run_as_user docker inspect "$container_id" --format '{{json .Mounts}}' 2>/dev/null) || true
    if echo "$mounts" | grep -qE '"/Users/|"/home/|"/root"'; then
        report_result "$id" "Container Security" "Home directory mounted in container" "WARN" "4.3" \
            "Consider using named Docker volumes instead"
    else
        report_result "$id" "Container Security" "No home directory mounts" "PASS" "4.3"
    fi
}

# CIS Docker Benchmark 5.10 (no host network) — also covered by docker-bench-security
check_container_network() {
    local id="CHK-CONTAINER-NETWORK"
    local container_id
    container_id=$(run_as_user docker ps -q --filter "name=n8n" 2>/dev/null | head -1) || true
    if [[ -z "$container_id" ]]; then
        report_result "$id" "Container Security" "No n8n container running" "SKIP" "4.5"
        return
    fi
    local net_mode
    net_mode=$(run_as_user docker inspect "$container_id" --format '{{.HostConfig.NetworkMode}}' 2>/dev/null) || true
    if [[ "$net_mode" == "host" ]]; then
        report_result "$id" "Container Security" "Container uses host network — no isolation" "FAIL" "4.5" \
            "Use bridge networking, not --network host — see §4.5"
    else
        report_result "$id" "Container Security" "Container network mode: ${net_mode}" "PASS" "4.5"
    fi
}

# CIS Docker Benchmark 5.11/5.12 (memory/CPU limits) — also covered by docker-bench-security
check_container_resources() {
    local id="CHK-CONTAINER-RESOURCES"
    local container_id
    container_id=$(run_as_user docker ps -q --filter "name=n8n" 2>/dev/null | head -1) || true
    if [[ -z "$container_id" ]]; then
        report_result "$id" "Container Security" "No n8n container running" "SKIP" "4.3"
        return
    fi
    local mem_limit
    mem_limit=$(run_as_user docker inspect "$container_id" --format '{{.HostConfig.Memory}}' 2>/dev/null) || true
    if [[ "$mem_limit" == "0" || -z "$mem_limit" ]]; then
        report_result "$id" "Container Security" "No memory limit set — resource exhaustion possible" "WARN" "4.3" \
            "Set deploy.resources.limits.memory in docker-compose.yml — see §4.3"
    else
        report_result "$id" "Container Security" "Memory limit set (${mem_limit} bytes)" "PASS" "4.3"
    fi
}

# --- §5 n8n Platform Security Checks (T029) ---

check_n8n_bind() {
    local id="CHK-N8N-BIND"
    local deployment
    deployment=$(detect_deployment)
    if [[ "$deployment" == "containerized" ]]; then
        local container_id
        container_id=$(run_as_user docker ps -q --filter "name=n8n" 2>/dev/null | head -1) || true
        if [[ -z "$container_id" ]]; then
            report_result "$id" "n8n Platform" "No n8n container running" "SKIP" "5.1"
            return
        fi
        local port_binding
        port_binding=$(run_as_user docker port "$container_id" 5678 2>/dev/null) || true
        if echo "$port_binding" | grep -qE "^(127\.0\.0\.1|\[::1\]):"; then
            report_result "$id" "n8n Platform" "n8n bound to localhost (container)" "PASS" "5.1"
        elif [[ -z "$port_binding" ]]; then
            report_result "$id" "n8n Platform" "n8n port not mapped (internal only)" "PASS" "5.1"
        else
            report_result "$id" "n8n Platform" "n8n exposed beyond localhost (${port_binding})" "FAIL" "5.1" \
                "Change port mapping to 127.0.0.1:5678:5678 in docker-compose.yml"
        fi
    elif [[ "$deployment" == "bare-metal" ]]; then
        local bind_addr
        bind_addr=$(sudo lsof -iTCP:5678 -sTCP:LISTEN -P -n 2>/dev/null | awk 'NR>1{print $9}') || true
        if echo "$bind_addr" | grep -qE "^(127\.0\.0\.1|\[::1\]):"; then
            report_result "$id" "n8n Platform" "n8n bound to localhost (bare-metal)" "PASS" "5.1"
        elif [[ -z "$bind_addr" ]]; then
            report_result "$id" "n8n Platform" "n8n not listening on port 5678" "SKIP" "5.1"
        else
            report_result "$id" "n8n Platform" "n8n bound to ${bind_addr}" "FAIL" "5.1" \
                "Set N8N_HOST=localhost in launchd plist or shell profile"
        fi
    else
        report_result "$id" "n8n Platform" "n8n not detected" "SKIP" "5.1"
    fi
}

check_n8n_auth() {
    local id="CHK-N8N-AUTH"
    # Attempt unauthenticated access to the n8n REST API
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 \
        http://localhost:5678/rest/login 2>/dev/null) || true
    if [[ -z "$http_code" || "$http_code" == "000" ]]; then
        report_result "$id" "n8n Platform" "n8n not reachable on localhost:5678" "SKIP" "5.1"
    elif [[ "$http_code" == "401" || "$http_code" == "403" || "$http_code" == "200" ]]; then
        # 200 for login page is expected (login form returned), 401/403 also indicate auth is active
        report_result "$id" "n8n Platform" "n8n authentication is active" "PASS" "5.1"
    else
        report_result "$id" "n8n Platform" "n8n may lack authentication (HTTP ${http_code})" "FAIL" "5.1" \
            "Enable user management — see §5.1"
    fi
}

check_n8n_api() {
    local id="CHK-N8N-API"
    # Check if the public API endpoint is accessible
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 \
        http://localhost:5678/api/v1/workflows 2>/dev/null) || true
    if [[ -z "$http_code" || "$http_code" == "000" ]]; then
        report_result "$id" "n8n Platform" "n8n not reachable (API check skipped)" "SKIP" "5.4"
    elif [[ "$http_code" == "404" ]]; then
        report_result "$id" "n8n Platform" "Public API is disabled" "PASS" "5.4"
    elif [[ "$http_code" == "401" || "$http_code" == "403" ]]; then
        report_result "$id" "n8n Platform" "Public API requires authentication" "PASS" "5.4"
    else
        report_result "$id" "n8n Platform" "Public API may be accessible (HTTP ${http_code})" "WARN" "5.4" \
            "Set N8N_PUBLIC_API_DISABLED=true — see §5.4"
    fi
}

_get_n8n_env() {
    # Helper: get n8n environment variables from container or process
    local deployment
    deployment=$(detect_deployment)
    if [[ "$deployment" == "containerized" ]]; then
        local container_id
        container_id=$(run_as_user docker ps -q --filter "name=n8n" 2>/dev/null | head -1) || true
        if [[ -n "$container_id" ]]; then
            run_as_user docker inspect "$container_id" --format '{{json .Config.Env}}' 2>/dev/null
            return
        fi
    elif [[ "$deployment" == "bare-metal" ]]; then
        local pid
        pid=$(pgrep -f "n8n" 2>/dev/null | head -1) || true
        if [[ -n "$pid" ]]; then
            # macOS: read process environment from /proc is not available; use ps
            ps -p "$pid" -o command= 2>/dev/null
            return
        fi
    fi
    echo ""
}

check_n8n_env_block() {
    local id="CHK-N8N-ENV-BLOCK"
    local env_data
    env_data=$(_get_n8n_env)
    if [[ -z "$env_data" ]]; then
        report_result "$id" "n8n Platform" "n8n not detected (env block check skipped)" "SKIP" "5.3"
        return
    fi
    if echo "$env_data" | grep -qi "N8N_BLOCK_ENV_ACCESS_IN_NODE=true"; then
        report_result "$id" "n8n Platform" "Code node env access is blocked" "PASS" "5.3"
    elif echo "$env_data" | grep -qi "N8N_BLOCK_ENV_ACCESS_IN_NODE=false"; then
        report_result "$id" "n8n Platform" "Code node env access is NOT blocked" "WARN" "5.3" \
            "Set N8N_BLOCK_ENV_ACCESS_IN_NODE=true — see §5.3"
    else
        # Not explicitly set — default is true in v2.0+, false in v1.x
        report_result "$id" "n8n Platform" "N8N_BLOCK_ENV_ACCESS_IN_NODE not set (verify default)" "WARN" "5.3" \
            "Explicitly set N8N_BLOCK_ENV_ACCESS_IN_NODE=true — see §5.3"
    fi
}

check_n8n_env_diagnostics() {
    local id="CHK-N8N-ENV-DIAGNOSTICS"
    local env_data
    env_data=$(_get_n8n_env)
    if [[ -z "$env_data" ]]; then
        report_result "$id" "n8n Platform" "n8n not detected (diagnostics check skipped)" "SKIP" "5.3"
        return
    fi
    if echo "$env_data" | grep -qi "N8N_DIAGNOSTICS_ENABLED=false"; then
        report_result "$id" "n8n Platform" "Diagnostics/telemetry is disabled" "PASS" "5.3"
    else
        report_result "$id" "n8n Platform" "Diagnostics/telemetry may be enabled" "WARN" "5.3" \
            "Set N8N_DIAGNOSTICS_ENABLED=false — see §5.3"
    fi
}

check_n8n_env_api() {
    local id="CHK-N8N-ENV-API"
    local env_data
    env_data=$(_get_n8n_env)
    if [[ -z "$env_data" ]]; then
        report_result "$id" "n8n Platform" "n8n not detected (API env check skipped)" "SKIP" "5.3"
        return
    fi
    if echo "$env_data" | grep -qi "N8N_PUBLIC_API_DISABLED=true"; then
        report_result "$id" "n8n Platform" "Public API disabled via env var" "PASS" "5.3"
    else
        report_result "$id" "n8n Platform" "N8N_PUBLIC_API_DISABLED not set to true" "WARN" "5.3" \
            "Set N8N_PUBLIC_API_DISABLED=true — see §5.3"
    fi
}

check_n8n_nodes() {
    local id="CHK-N8N-NODES"
    local env_data
    env_data=$(_get_n8n_env)
    if [[ -z "$env_data" ]]; then
        report_result "$id" "n8n Platform" "n8n not detected (node exclusion check skipped)" "SKIP" "5.6"
        return
    fi
    if echo "$env_data" | grep -qi "NODES_EXCLUDE"; then
        if echo "$env_data" | grep -qi "executeCommand"; then
            report_result "$id" "n8n Platform" "Dangerous node types excluded" "PASS" "5.6"
        else
            report_result "$id" "n8n Platform" "NODES_EXCLUDE set but executeCommand not listed" "WARN" "5.6" \
                "Add executeCommand to NODES_EXCLUDE — see §5.6"
        fi
    else
        # v2.0 blocks executeCommand by default, but explicit is better
        report_result "$id" "n8n Platform" "NODES_EXCLUDE not set (verify v2.0 defaults)" "WARN" "5.6" \
            "Explicitly set NODES_EXCLUDE — see §5.6"
    fi
}

check_n8n_webhook() {
    local id="CHK-N8N-WEBHOOK"
    # Check if any n8n webhook endpoints are reachable without auth
    # This is a heuristic — we test the base webhook path
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 \
        http://localhost:5678/webhook-test/ 2>/dev/null) || true
    if [[ -z "$http_code" || "$http_code" == "000" ]]; then
        report_result "$id" "n8n Platform" "n8n not reachable (webhook check skipped)" "SKIP" "5.5"
    elif [[ "$http_code" == "404" || "$http_code" == "401" || "$http_code" == "403" ]]; then
        report_result "$id" "n8n Platform" "Webhook test endpoint not openly accessible" "PASS" "5.5"
    else
        report_result "$id" "n8n Platform" "Webhook test path returned HTTP ${http_code}" "WARN" "5.5" \
            "Expected if n8n is running — use production URLs in deployment"
    fi
}

# --- §3 Network Security Checks (T019) ---

check_ssh_key_only() {
    local id="CHK-SSH-KEY-ONLY"
    # Check if sshd is running
    if ! pgrep -q sshd 2>/dev/null; then
        report_result "$id" "SSH" "SSH daemon is not running" "PASS" "3.1"
        return
    fi
    local pw_auth
    pw_auth=$(sshd -T 2>/dev/null | grep -i "^passwordauthentication" | awk '{print $2}') || true
    if [[ "$pw_auth" == "no" ]]; then
        report_result "$id" "SSH" "SSH password auth is disabled" "PASS" "3.1"
    else
        report_result "$id" "SSH" "SSH password auth is enabled" "FAIL" "3.1" \
            "Disable: add 'PasswordAuthentication no' to /etc/ssh/sshd_config.d/hardening.conf"
    fi
}

check_ssh_root() {
    local id="CHK-SSH-ROOT"
    if ! pgrep -q sshd 2>/dev/null; then
        report_result "$id" "SSH" "SSH daemon is not running (root login N/A)" "PASS" "3.1"
        return
    fi
    local root_login
    root_login=$(sshd -T 2>/dev/null | grep -i "^permitrootlogin" | awk '{print $2}') || true
    if [[ "$root_login" == "no" ]]; then
        report_result "$id" "SSH" "SSH root login is disabled" "PASS" "3.1"
    else
        report_result "$id" "SSH" "SSH root login is allowed" "FAIL" "3.1" \
            "Disable: add 'PermitRootLogin no' to /etc/ssh/sshd_config.d/hardening.conf"
    fi
}

check_dns_encrypted() {
    local id="CHK-DNS-ENCRYPTED"
    # Check if a DNS configuration profile is installed
    local dns_profile
    dns_profile=$(profiles list 2>/dev/null | grep -i dns) || true
    if [[ -n "$dns_profile" ]]; then
        report_result "$id" "DNS" "DNS configuration profile installed" "PASS" "3.2"
        return
    fi
    # Check if DNS points to known encrypted providers
    local dns_servers
    dns_servers=$(scutil --dns 2>/dev/null | grep "nameserver\[0\]" | head -1 | awk '{print $3}') || true
    case "$dns_servers" in
        9.9.9.9|149.112.112.112|1.1.1.1|1.0.0.1|8.8.8.8|8.8.4.4)
            report_result "$id" "DNS" "DNS server ${dns_servers} (verify DoH/DoT enabled)" "WARN" "3.2" \
                "Install encrypted DNS profile for guaranteed DoH/DoT"
            ;;
        *)
            report_result "$id" "DNS" "DNS server: ${dns_servers:-unknown}" "WARN" "3.2" \
                "Configure encrypted DNS via Quad9 DoH profile" "" "recommended"
            ;;
    esac
}

check_outbound_filter() {
    local id="CHK-OUTBOUND-FILTER"
    # Check for pf rules
    local pf_enabled
    pf_enabled=$(sudo pfctl -s info 2>/dev/null | grep "Status:" | awk '{print $2}') || true
    if [[ "$pf_enabled" == "Enabled" ]]; then
        report_result "$id" "Outbound Filtering" "pf is enabled" "PASS" "3.3"
        return
    fi
    # Check for LuLu
    if pgrep -f LuLu &>/dev/null; then
        report_result "$id" "Outbound Filtering" "LuLu is running" "PASS" "3.3"
        return
    fi
    # Check for Little Snitch
    if pgrep -f "Little Snitch" &>/dev/null; then
        report_result "$id" "Outbound Filtering" "Little Snitch is running" "PASS" "3.3"
        return
    fi
    report_result "$id" "Outbound Filtering" "No outbound filtering detected" "WARN" "3.3" \
        "Install LuLu or configure pf rules — see §3.3"
}

check_bluetooth() {
    local id="CHK-BLUETOOTH"
    local bt_state
    bt_state=$(defaults read /Library/Preferences/com.apple.Bluetooth ControllerPowerState 2>/dev/null) || true
    if [[ "$bt_state" == "0" ]]; then
        report_result "$id" "Bluetooth" "Bluetooth is disabled" "PASS" "3.4"
    elif [[ "$bt_state" == "1" ]]; then
        local discoverable
        discoverable=$(sudo defaults read /Library/Preferences/com.apple.Bluetooth DiscoverableState 2>/dev/null) || true
        if [[ "$discoverable" == "0" ]]; then
            report_result "$id" "Bluetooth" "Bluetooth on, discoverability off" "PASS" "3.4"
        else
            report_result "$id" "Bluetooth" "Bluetooth is on and discoverable" "WARN" "3.4" \
                "Disable discoverability: sudo defaults write /Library/Preferences/com.apple.Bluetooth DiscoverableState -bool false"
        fi
    else
        report_result "$id" "Bluetooth" "Cannot determine Bluetooth state" "SKIP" "3.4"
    fi
}

check_ipv6() {
    local id="CHK-IPV6"
    local ipv6_status
    # Check Ethernet first, then Wi-Fi
    ipv6_status=$(networksetup -getv6 "Ethernet" 2>/dev/null) || \
    ipv6_status=$(networksetup -getv6 "Wi-Fi" 2>/dev/null) || true
    if echo "$ipv6_status" | grep -qi "off"; then
        report_result "$id" "IPv6" "IPv6 is disabled" "PASS" "3.5"
    elif echo "$ipv6_status" | grep -qi "automatic\|manual"; then
        # Check if IPv6 pf rules exist
        local ipv6_rules
        ipv6_rules=$(sudo pfctl -sr 2>/dev/null | grep -c inet6) || ipv6_rules=0
        if [[ "$ipv6_rules" -gt 0 ]]; then
            report_result "$id" "IPv6" "IPv6 enabled with pf rules" "PASS" "3.5"
        else
            report_result "$id" "IPv6" "IPv6 enabled without firewall rules" "WARN" "3.5" \
                "Disable IPv6: networksetup -setv6off Ethernet — or add inet6 pf rules"
        fi
    else
        report_result "$id" "IPv6" "Cannot determine IPv6 status" "SKIP" "3.5"
    fi
}

check_listeners_baseline() {
    local id="CHK-LISTENER-BASELINE"
    # Check if any service is listening on 0.0.0.0 that shouldn't be
    local bad_listeners
    bad_listeners=$(sudo lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null \
        | grep -E '\*:|0\.0\.0\.0:' \
        | grep -v sshd \
        | grep -v launchd \
        | awk '{print $1 ":" $9}') || true
    if [[ -z "$bad_listeners" ]]; then
        report_result "$id" "Listening Services" "No unexpected wildcard listeners" "PASS" "3.6"
    else
        local count
        count=$(echo "$bad_listeners" | wc -l | tr -d ' ')
        report_result "$id" "Listening Services" "${count} service(s) on 0.0.0.0" "WARN" "3.6" \
            "Review with: sudo lsof -iTCP -sTCP:LISTEN -P -n"
    fi
}

# --- §6 Bare-Metal Path Checks (T032) ---

check_service_account() {
    local id="CHK-SERVICE-ACCOUNT"
    local deployment
    deployment=$(detect_deployment)
    if [[ "$deployment" == "containerized" ]]; then
        report_result "$id" "Bare-Metal" "Containerized deployment (service account N/A)" "SKIP" "6.1"
        return
    fi
    # Check if _n8n service account exists
    if dscl . -read /Users/_n8n &>/dev/null; then
        local shell
        shell=$(dscl . -read /Users/_n8n UserShell 2>/dev/null | awk '{print $2}') || true
        if [[ "$shell" == "/usr/bin/false" || "$shell" == "/usr/sbin/nologin" ]]; then
            # Verify n8n is running as _n8n
            local n8n_user
            n8n_user=$(ps -eo user,command 2>/dev/null | grep "[n]8n" | awk '{print $1}' | head -1) || true
            if [[ "$n8n_user" == "_n8n" ]]; then
                report_result "$id" "Bare-Metal" "n8n runs as _n8n service account" "PASS" "6.1"
            elif [[ -z "$n8n_user" ]]; then
                report_result "$id" "Bare-Metal" "_n8n account exists (n8n not running)" "PASS" "6.1"
            else
                report_result "$id" "Bare-Metal" "n8n runs as ${n8n_user} (not _n8n)" "FAIL" "6.1" \
                    "Configure launchd to run n8n as _n8n — see §6.3"
            fi
        else
            report_result "$id" "Bare-Metal" "_n8n has interactive shell: ${shell}" "FAIL" "6.1" \
                "Set shell to /usr/bin/false: sudo dscl . -change /Users/_n8n UserShell ${shell} /usr/bin/false"
        fi
    else
        if [[ "$deployment" == "bare-metal" ]]; then
            report_result "$id" "Bare-Metal" "No _n8n service account (n8n runs as admin)" "FAIL" "6.1" \
                "Create service account: sudo sysadminctl -addUser _n8n -shell /usr/bin/false"
        else
            report_result "$id" "Bare-Metal" "n8n not detected and no _n8n account" "SKIP" "6.1"
        fi
    fi
}

check_service_home_perms() {
    local id="CHK-SERVICE-HOME-PERMS"
    local deployment
    deployment=$(detect_deployment)
    if [[ "$deployment" == "containerized" ]]; then
        report_result "$id" "Bare-Metal" "Containerized deployment (home perms N/A)" "SKIP" "6.4"
        return
    fi
    if ! dscl . -read /Users/_n8n &>/dev/null; then
        report_result "$id" "Bare-Metal" "No _n8n account (home perms check skipped)" "SKIP" "6.4"
        return
    fi
    # Verify _n8n cannot access operator home directory
    local admin_home
    admin_home=$(eval echo "~$(whoami)") || true
    if sudo -u _n8n test -r "$admin_home" 2>/dev/null; then
        report_result "$id" "Bare-Metal" "_n8n can read operator home directory" "FAIL" "6.4" \
            "Restrict: chmod 750 ${admin_home} or chmod 700 ${admin_home}"
    else
        report_result "$id" "Bare-Metal" "_n8n cannot access operator home" "PASS" "6.4"
    fi
}

check_service_data_perms() {
    local id="CHK-SERVICE-DATA-PERMS"
    local deployment
    deployment=$(detect_deployment)
    if [[ "$deployment" == "containerized" ]]; then
        report_result "$id" "Bare-Metal" "Containerized deployment (data perms N/A)" "SKIP" "6.4"
        return
    fi
    if [[ ! -d /opt/n8n/data ]]; then
        if [[ "$deployment" == "bare-metal" ]]; then
            report_result "$id" "Bare-Metal" "n8n data directory /opt/n8n/data not found" "FAIL" "6.4" \
                "Create: sudo mkdir -p /opt/n8n/data && sudo chown _n8n:_n8n /opt/n8n/data && sudo chmod 700 /opt/n8n/data"
        else
            report_result "$id" "Bare-Metal" "n8n data directory not found (n8n not detected)" "SKIP" "6.4"
        fi
        return
    fi
    local perms
    perms=$(stat -f "%A" /opt/n8n/data 2>/dev/null) || true
    local owner
    owner=$(stat -f "%Su" /opt/n8n/data 2>/dev/null) || true
    if [[ "$owner" == "_n8n" && "$perms" == "700" ]]; then
        report_result "$id" "Bare-Metal" "n8n data dir: 700 owned by _n8n" "PASS" "6.4"
    else
        report_result "$id" "Bare-Metal" "n8n data dir: ${perms} owned by ${owner}" "FAIL" "6.4" \
            "Fix: sudo chown _n8n:_n8n /opt/n8n/data && sudo chmod 700 /opt/n8n/data"
    fi
}

# --- §7 Data Security Checks (T038) ---

check_cred_env_visible() {
    local id="CHK-CRED-ENV-VISIBLE"
    local deployment
    deployment=$(detect_deployment)
    if [[ "$deployment" == "containerized" ]]; then
        # Reuse CHK-SECRETS-ENV logic — check container env for secrets
        local container_id
        container_id=$(run_as_user docker ps -q --filter "name=n8n" 2>/dev/null | head -1) || true
        if [[ -z "$container_id" ]]; then
            report_result "$id" "Data Security" "No n8n container running" "SKIP" "7.1"
            return
        fi
        local env_vars
        env_vars=$(run_as_user docker inspect "$container_id" --format '{{json .Config.Env}}' 2>/dev/null) || true
        if echo "$env_vars" | grep -qiE 'ENCRYPTION_KEY=[a-fA-F0-9]{8}|PASSWORD=[^ ]{4}|_SECRET=[a-zA-Z0-9]{8}'; then
            report_result "$id" "Data Security" "Secrets visible in container environment" "WARN" "7.1" \
                "Use Docker secrets instead of environment variables — see §4.3"
        else
            report_result "$id" "Data Security" "No secrets in container environment" "PASS" "7.1"
        fi
    elif [[ "$deployment" == "bare-metal" ]]; then
        local pid
        pid=$(pgrep -f "n8n" 2>/dev/null | head -1) || true
        if [[ -z "$pid" ]]; then
            report_result "$id" "Data Security" "n8n not running (credential check skipped)" "SKIP" "7.1"
            return
        fi
        local args
        args=$(ps -p "$pid" -o args= 2>/dev/null) || true
        if echo "$args" | grep -qiE 'encryption.key=|password=|secret=|token='; then
            report_result "$id" "Data Security" "Secrets visible in process arguments" "WARN" "7.1" \
                "Use Keychain or env vars in launchd plist — never command-line args (§6.2)"
        else
            report_result "$id" "Data Security" "No secrets in process arguments" "PASS" "7.1"
        fi
    else
        report_result "$id" "Data Security" "n8n not detected" "SKIP" "7.1"
    fi
}

check_docker_inspect_secrets() {
    local id="CHK-DOCKER-INSPECT-SECRETS"
    local deployment
    deployment=$(detect_deployment)
    if [[ "$deployment" != "containerized" ]]; then
        report_result "$id" "Data Security" "Not containerized (docker inspect N/A)" "SKIP" "7.1"
        return
    fi
    local container_id
    container_id=$(run_as_user docker ps -q --filter "name=n8n" 2>/dev/null | head -1) || true
    if [[ -z "$container_id" ]]; then
        report_result "$id" "Data Security" "No n8n container running" "SKIP" "7.1"
        return
    fi
    # Check if docker inspect reveals actual secret values in environment
    local env_output
    env_output=$(run_as_user docker inspect "$container_id" --format '{{json .Config.Env}}' 2>/dev/null) || true
    local has_secrets
    has_secrets=$(echo "$env_output" | grep -ciE 'N8N_ENCRYPTION_KEY=[a-fA-F0-9]{16}|JWT_SECRET=[a-zA-Z0-9]{16}') || true
    if [[ "$has_secrets" -gt 0 ]]; then
        report_result "$id" "Data Security" "docker inspect exposes secret values" "WARN" "7.1" \
            "Move N8N_ENCRYPTION_KEY to Docker secrets (/run/secrets/) — see §4.3"
    else
        report_result "$id" "Data Security" "No high-value secrets in docker inspect" "PASS" "7.1"
    fi
}

check_spotlight_exclusions() {
    local id="CHK-SPOTLIGHT-EXCLUSIONS"
    local deployment
    deployment=$(detect_deployment)
    local indexed=0
    # Check bare-metal n8n data directory
    if [[ -d /opt/n8n ]]; then
        local mdutil_status
        mdutil_status=$(mdutil -s /opt/n8n 2>/dev/null) || true
        if echo "$mdutil_status" | grep -qi "enabled"; then
            indexed=$((indexed + 1))
        fi
    fi
    # Check Docker data directory (if it exists on host)
    if [[ -d /var/lib/docker ]]; then
        local docker_mdutil
        docker_mdutil=$(mdutil -s /var/lib/docker 2>/dev/null) || true
        if echo "$docker_mdutil" | grep -qi "enabled"; then
            indexed=$((indexed + 1))
        fi
    fi
    if [[ $indexed -eq 0 ]]; then
        report_result "$id" "Data Security" "Sensitive directories excluded from Spotlight" "PASS" "7.4"
    else
        report_result "$id" "Data Security" "${indexed} sensitive dir(s) are Spotlight-indexed" "WARN" "7.4" \
            "Exclude: sudo mdutil -i off /opt/n8n (or Docker data dir)"
    fi
}

check_config_profiles() {
    local id="CHK-CONFIG-PROFILES"
    # Check for unexpected configuration profiles that could weaken security
    local profiles
    profiles=$(profiles list 2>/dev/null) || true
    if [[ -z "$profiles" ]] || echo "$profiles" | grep -qi "no profiles"; then
        report_result "$id" "Data Security" "No configuration profiles installed" "PASS" "7.10"
    else
        local count
        count=$(echo "$profiles" | grep -c "attribute" 2>/dev/null) || count=0
        report_result "$id" "Data Security" "${count} configuration profile(s) installed" "WARN" "7.10" \
            "Normal for unmanaged Macs"
    fi
}

# --- §8 Detection and Monitoring Checks (T045) ---

check_santa() {
    local id="CHK-SANTA"
    if command -v santactl &>/dev/null; then
        local mode
        mode=$(santactl status 2>/dev/null | grep -i "mode" | head -1) || true
        report_result "$id" "IDS Tools" "Santa installed (${mode:-status unknown})" "PASS" "8.1"
    else
        report_result "$id" "IDS Tools" "Santa not installed" "WARN" "8.1" \
            "Binary allowlisting tool: brew install santa"
    fi
}

check_blockblock() {
    local id="CHK-BLOCKBLOCK"
    if pgrep -x BlockBlock &>/dev/null || pgrep -x "BlockBlock Helper" &>/dev/null; then
        report_result "$id" "IDS Tools" "BlockBlock is running" "PASS" "8.1"
    elif [[ -d "/Applications/BlockBlock Helper.app" ]] || [[ -d "/Library/Objective-See/BlockBlock" ]]; then
        report_result "$id" "IDS Tools" "BlockBlock installed but not running" "WARN" "8.1" \
            "Start from Applications"
    else
        report_result "$id" "IDS Tools" "BlockBlock not installed" "WARN" "8.1" \
            "Persistence monitor: objective-see.org"
    fi
}

check_lulu() {
    local id="CHK-LULU"
    if pgrep -x LuLu &>/dev/null || pgrep -f "com.objective-see.lulu" &>/dev/null; then
        report_result "$id" "IDS Tools" "LuLu is running" "PASS" "8.1"
    elif [[ -d "/Applications/LuLu.app" ]] || [[ -d "/Library/Objective-See/LuLu" ]]; then
        report_result "$id" "IDS Tools" "LuLu installed but not running" "WARN" "8.1" \
            "Start from Applications"
    else
        report_result "$id" "IDS Tools" "LuLu not installed" "WARN" "8.1" \
            "Outbound firewall: brew install --cask lulu"
    fi
}

check_clamav() {
    local id="CHK-CLAMAV"
    if command -v clamscan &>/dev/null; then
        report_result "$id" "IDS Tools" "ClamAV is installed" "PASS" "8.1"
    else
        report_result "$id" "IDS Tools" "ClamAV not installed" "WARN" "8.1" \
            "Antivirus scanner: brew install clamav"
    fi
}

check_clamav_sigs() {
    local id="CHK-CLAMAV-SIGS"
    if ! command -v clamscan &>/dev/null; then
        report_result "$id" "IDS Tools" "ClamAV not installed (sig check skipped)" "SKIP" "8.1"
        return
    fi
    local db_dir="/opt/homebrew/share/clamav"
    if [[ ! -d "$db_dir" ]]; then
        db_dir="/usr/local/share/clamav"
    fi
    local sig_file=""
    if [[ -f "$db_dir/main.cvd" ]]; then
        sig_file="$db_dir/main.cvd"
    elif [[ -f "$db_dir/main.cld" ]]; then
        sig_file="$db_dir/main.cld"
    fi
    if [[ -n "$sig_file" ]]; then
        local mod_epoch
        mod_epoch=$(stat -f %m "$sig_file" 2>/dev/null) || true
        if [[ -z "$mod_epoch" ]]; then
            report_result "$id" "IDS Tools" "Cannot determine ClamAV signature age" "WARN" "8.1" \
                "Check file permissions: stat $sig_file"
            return
        fi
        local age_days=$(( ($(date +%s) - mod_epoch) / 86400 ))
        if [[ $age_days -lt 7 ]]; then
            report_result "$id" "IDS Tools" "ClamAV signatures current (${age_days}d old)" "PASS" "8.1"
        else
            report_result "$id" "IDS Tools" "ClamAV signatures stale (${age_days}d old)" "WARN" "8.1" \
                "Update: sudo freshclam"
        fi
    else
        report_result "$id" "IDS Tools" "ClamAV signatures not initialized" "WARN" "8.1" \
            "Initialize: sudo freshclam"
    fi
}

check_persistence_baseline() {
    local id="CHK-PERSISTENCE-BASELINE"
    local baseline_dir="/opt/n8n/baselines"
    if [[ ! -d "$baseline_dir" ]]; then
        baseline_dir="$HOME/openclaw-baselines"
    fi
    if [[ -f "$baseline_dir/launchdaemons.txt" ]]; then
        report_result "$id" "Persistence" "Persistence baseline exists" "PASS" "8.2"
    else
        report_result "$id" "Persistence" "No persistence baseline found" "WARN" "8.2" \
            "Create after setup is complete — see §8.2"
    fi
}

check_workflow_baseline() {
    local id="CHK-WORKFLOW-BASELINE"
    local baseline_dir="/opt/n8n/baselines"
    if [[ ! -d "$baseline_dir" ]]; then
        baseline_dir="$HOME/openclaw-baselines"
    fi
    if [[ -f "$baseline_dir/workflow-manifest.sha256" ]]; then
        report_result "$id" "Workflow Integrity" "Workflow baseline exists" "PASS" "8.3"
    else
        report_result "$id" "Workflow Integrity" "No workflow baseline found" "WARN" "8.3" \
            "Export n8n workflows and create baseline — see §8.3"
    fi
}

check_listener_baseline() {
    local id="CHK-LISTENER-BASELINE"
    # Check for unexpected listeners beyond known services
    local listeners
    listeners=$(sudo lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null | awk 'NR>1{print $1, $9}' | sort -u) || true
    if [[ -z "$listeners" ]]; then
        report_result "$id" "Network" "No TCP listeners detected" "PASS" "8.2"
    else
        local count
        count=$(echo "$listeners" | wc -l | tr -d ' ')
        report_result "$id" "Network" "${count} TCP listener(s) — review for unexpected services" "WARN" "8.2" \
            "Review with: sudo lsof -iTCP -sTCP:LISTEN -P -n"
    fi
}

check_cert_baseline() {
    local id="CHK-CERT-BASELINE"
    local baseline_dir="/opt/n8n/baselines"
    if [[ ! -d "$baseline_dir" ]]; then
        baseline_dir="$HOME/openclaw-baselines"
    fi
    if [[ -f "$baseline_dir/cert-trust-store.txt" ]]; then
        report_result "$id" "Certificates" "Certificate trust store baseline exists" "PASS" "8.7"
    else
        report_result "$id" "Certificates" "No certificate baseline found" "WARN" "8.7" \
            "Create trust store baseline — see §8.7"
    fi
}

check_icloud_keychain() {
    local id="CHK-ICLOUD-KEYCHAIN"
    # iCloud Keychain detection is limited from CLI; check for iCloud-related config
    if run_as_user defaults read MobileMeAccounts 2>/dev/null | grep -q "KEYCHAIN_SYNC"; then
        report_result "$id" "Cloud Services" "iCloud Keychain sync may be enabled" "WARN" "8.6" \
            "Disable: System Settings > Apple ID > iCloud > Keychain > OFF" "" "recommended"
    else
        report_result "$id" "Cloud Services" "iCloud Keychain sync not detected" "PASS" "8.6"
    fi
}

check_icloud_drive() {
    local id="CHK-ICLOUD-DRIVE"
    # Check if iCloud Drive is syncing
    if brctl status 2>/dev/null | grep -qi "enabled"; then
        report_result "$id" "Cloud Services" "iCloud Drive appears enabled" "WARN" "8.6" \
            "Disable iCloud Drive sync in System Settings > Apple ID > iCloud"
    else
        report_result "$id" "Cloud Services" "iCloud Drive not detected as enabled" "PASS" "8.6"
    fi
}

check_canary() {
    local id="CHK-CANARY"
    local canary_found=false
    # Check for canary files in expected locations
    if [[ -f /opt/n8n/data/admin-credentials.txt ]]; then
        canary_found=true
    fi
    if [[ -f "$HOME/aws-root-credentials.txt" ]]; then
        canary_found=true
    fi
    if $canary_found; then
        report_result "$id" "Canary" "Canary files are in place" "PASS" "8.5"
    else
        report_result "$id" "Canary" "No canary files detected" "WARN" "8.5" \
            "Advanced: deploy tripwire files — see §8.5"
    fi
}

# --- §9 Response and Recovery checks (T050) ---

check_backup_configured() {
    local id="CHK-BACKUP-CONFIGURED"
    local backup_found=false

    # Check for Time Machine configuration
    if tmutil destinationinfo 2>/dev/null | grep -q "Mount Point"; then
        backup_found=true
    fi

    # Check for backup directory with recent files
    local backup_dir="/opt/n8n/backups"
    if [[ -d "$backup_dir" ]] && find "$backup_dir" -name "*.tar.gz*" -mtime -30 2>/dev/null | grep -q .; then
        backup_found=true
    fi

    if $backup_found; then
        report_result "$id" "Backup" "Backup configuration detected" "PASS" "9.3"
    else
        report_result "$id" "Backup" "No backup configuration detected" "WARN" "9.3" \
            "Configure Time Machine or automated backup — see §9.3" "" "recommended"
    fi
}

check_backup_encrypted() {
    local id="CHK-BACKUP-ENCRYPTED"
    local backup_dir="/opt/n8n/backups"

    # Check if Time Machine encryption is enabled
    local tm_encrypted=false
    if tmutil destinationinfo 2>/dev/null | grep -qi "encrypted"; then
        tm_encrypted=true
    fi

    # Check for unencrypted backup files in the backup directory
    local unencrypted_found=false
    if [[ -d "$backup_dir" ]]; then
        # Look for .tar.gz files that don't have a corresponding .gpg or .enc
        while IFS= read -r -d '' tarfile; do
            if [[ ! -f "${tarfile}.gpg" && ! -f "${tarfile}.enc" ]]; then
                unencrypted_found=true
                break
            fi
        done < <(find "$backup_dir" -name "*.tar.gz" -not -name "*.gpg" -not -name "*.enc" -print0 2>/dev/null)
    fi

    if $unencrypted_found; then
        report_result "$id" "Backup" "Unencrypted backup files found in $backup_dir" "WARN" "9.3" \
            "Encrypt backups with GPG or OpenSSL before storage — see §9.3"
    elif $tm_encrypted || [[ -d "$backup_dir" ]]; then
        report_result "$id" "Backup" "No unencrypted backup files detected" "PASS" "9.3"
    else
        report_result "$id" "Backup" "No backup directory found to check encryption" "SKIP" "9.3" \
            "Configure backups first — see §9.3"
    fi
}

check_find_my_mac() {
    local id="CHK-FIND-MY-MAC"
    local fmm_enabled
    fmm_enabled=$(run_as_user defaults read com.apple.icloud.findmymac FMMEnabled 2>/dev/null || echo "")

    if [[ "$fmm_enabled" == "1" ]]; then
        report_result "$id" "Physical" "Find My Mac is enabled" "PASS" "9.5"
    elif [[ -z "$fmm_enabled" ]]; then
        report_result "$id" "Physical" "Find My Mac status could not be determined" "WARN" "9.5" \
            "Enable: System Settings > Apple ID > iCloud > Find My Mac"
    else
        report_result "$id" "Physical" "Find My Mac is not enabled" "WARN" "9.5" \
            "Enable: System Settings > Apple ID > iCloud > Find My Mac"
    fi
}

check_usb() {
    local id="CHK-USB"
    local policy
    policy=$(defaults read /Library/Preferences/com.apple.security.accessory AccessorySecurityPolicy 2>/dev/null || echo "")

    if [[ -z "$policy" ]]; then
        # Accessory security requires T2 chip or Apple Silicon (Ventura 13+)
        local has_secure_enclave
        has_secure_enclave=$(system_profiler SPiBridgeDataType 2>/dev/null | grep -qi "T2\|Apple" && echo "yes" || echo "")
        if [[ -z "$has_secure_enclave" ]]; then
            has_secure_enclave=$(sysctl -n hw.optional.arm64 2>/dev/null | grep -q "1" && echo "yes" || echo "")
        fi
        if [[ -n "$has_secure_enclave" ]]; then
            report_result "$id" "Physical" "USB accessory security policy not configured" "WARN" "9.5" \
                "System Settings > Privacy & Security > Allow accessories"
        else
            report_result "$id" "Physical" "USB accessory security not available (requires T2 or Apple Silicon)" "SKIP" "9.5"
        fi
    elif [[ "$policy" -le 2 ]]; then
        report_result "$id" "Physical" "USB accessory security is configured (policy: $policy)" "PASS" "9.5"
    else
        report_result "$id" "Physical" "USB accessory security is set to permissive (policy: $policy)" "WARN" "9.5" \
            "Restrict to 'Ask for new accessories' in System Settings"
    fi
}

# --- §10 Operational Maintenance checks (T058) ---

check_launchd_audit_job() {
    local id="CHK-LAUNCHD-AUDIT-JOB"
    if launchctl list com.openclaw.audit-cron &>/dev/null; then
        report_result "$id" "Infrastructure" "Audit launchd job is loaded" "PASS" "10.1"
    elif [[ -f /Library/LaunchDaemons/com.openclaw.audit-cron.plist ]]; then
        report_result "$id" "Infrastructure" "Audit plist exists but job is not loaded" "FAIL" "10.1" \
            "Load: sudo launchctl bootstrap system /Library/LaunchDaemons/com.openclaw.audit-cron.plist"
    else
        report_result "$id" "Infrastructure" "Audit launchd job not found" "FAIL" "10.1" \
            "Install audit plist — see §10.1"
    fi
}

check_notification_config() {
    local id="CHK-NOTIFICATION-CONFIG"
    local conf="/opt/n8n/etc/notify.conf"
    if [[ -f "$conf" ]]; then
        report_result "$id" "Infrastructure" "Notification configuration exists" "PASS" "10.2"
    else
        report_result "$id" "Infrastructure" "Notification configuration not found" "WARN" "10.2" \
            "Run make install to create default config"
    fi
}

check_log_dir() {
    local id="CHK-LOG-DIR"
    local log_dir="/opt/n8n/logs/audit"
    if [[ -d "$log_dir" && -w "$log_dir" ]]; then
        # Check if logs are being generated (most recent log not older than 2x weekly = 14 days)
        local latest
        latest=$(find "$log_dir" -name "audit-*.log" -mtime -14 2>/dev/null | head -1) || true
        if [[ -n "$latest" ]]; then
            report_result "$id" "Infrastructure" "Audit log directory exists with recent logs" "PASS" "10.4"
        else
            report_result "$id" "Infrastructure" "Audit log directory exists but no recent logs (>14 days)" "WARN" "10.4" \
                "Verify scheduled audit is running — see §10.1" "" "recommended"
        fi
    elif [[ -d "$log_dir" ]]; then
        report_result "$id" "Infrastructure" "Audit log directory exists but is not writable" "FAIL" "10.4" \
            "Fix permissions: sudo chmod 755 $log_dir"
    else
        report_result "$id" "Infrastructure" "Audit log directory does not exist" "FAIL" "10.4" \
            "Create: sudo mkdir -p $log_dir && sudo chmod 755 $log_dir"
    fi
}

check_clamav_freshness() {
    local id="CHK-CLAMAV-FRESHNESS"
    if ! command -v sigtool &>/dev/null; then
        report_result "$id" "Tools" "ClamAV not installed — cannot check signature freshness" "SKIP" "10.3" \
            "Install: brew install clamav"
        return
    fi

    local sig_file=""
    for f in /usr/local/share/clamav/main.cvd /opt/homebrew/share/clamav/main.cvd /var/lib/clamav/main.cvd; do
        if [[ -f "$f" ]]; then
            sig_file="$f"
            break
        fi
    done

    if [[ -z "$sig_file" ]]; then
        report_result "$id" "Tools" "ClamAV signature database not found" "WARN" "10.3" \
            "Run: sudo freshclam"
        return
    fi

    # Check file age — warn if older than 7 days
    local age_days
    if [[ "$(uname -s)" == "Darwin" ]]; then
        local mod_epoch
        mod_epoch=$(stat -f %m "$sig_file" 2>/dev/null || echo 0)
        local now_epoch
        now_epoch=$(date +%s)
        age_days=$(( (now_epoch - mod_epoch) / 86400 ))
    else
        age_days=$(( ( $(date +%s) - $(stat -c %Y "$sig_file" 2>/dev/null || echo 0) ) / 86400 ))
    fi

    if [[ "$age_days" -le 7 ]]; then
        report_result "$id" "Tools" "ClamAV signatures are fresh (${age_days} days old)" "PASS" "10.3"
    else
        report_result "$id" "Tools" "ClamAV signatures are stale (${age_days} days old)" "WARN" "10.3" \
            "Update: sudo freshclam"
    fi
}

# ===========================================================================
# §2.11 — Browser Security (Chromium / Chrome / Edge)
# Uses browser registry from scripts/browser-registry.sh
# ===========================================================================

check_browser_policy() {
    local browser="$1"
    local id="CHK-BROWSER-POLICY"
    local name="${BROWSER_NAME[$browser]}"
    local plist="/Library/Managed Preferences/${BROWSER_PLIST_DOMAIN[$browser]}.plist"

    if [[ -f "$plist" ]]; then
        report_result "$id" "Browser Security" \
            "[${name}] Managed security policies deployed" "PASS" "2.11" "" "$name"
    else
        report_result "$id" "Browser Security" \
            "[${name}] No managed policy plist found" "WARN" "2.11" \
            "Deploy policy: see §2.11.2 in hardening guide" "$name"
    fi
}

check_browser_autofill() {
    local browser="$1"
    local id="CHK-BROWSER-AUTOFILL"
    local name="${BROWSER_NAME[$browser]}"
    local plist="/Library/Managed Preferences/${BROWSER_PLIST_DOMAIN[$browser]}"

    if [[ ! -f "${plist}.plist" ]]; then
        report_result "$id" "Browser Security" \
            "[${name}] Cannot check autofill — no managed policy plist" "WARN" "2.11" \
            "Deploy policy with autofill disabled: §2.11.2" "$name"
        return
    fi

    local pw_mgr autofill_addr autofill_cc
    pw_mgr=$(defaults read "$plist" PasswordManagerEnabled 2>/dev/null) || pw_mgr=""
    autofill_addr=$(defaults read "$plist" AutofillAddressEnabled 2>/dev/null) || autofill_addr=""
    autofill_cc=$(defaults read "$plist" AutofillCreditCardEnabled 2>/dev/null) || autofill_cc=""

    if [[ "$pw_mgr" == "0" && "$autofill_addr" == "0" && "$autofill_cc" == "0" ]]; then
        report_result "$id" "Browser Security" \
            "[${name}] Password manager and autofill disabled via policy" "PASS" "2.11" "" "$name"
    else
        report_result "$id" "Browser Security" \
            "[${name}] Password manager or autofill not fully disabled" "WARN" "2.11" \
            "Set PasswordManagerEnabled, AutofillAddressEnabled, AutofillCreditCardEnabled to false" "$name"
    fi
}

check_browser_extensions() {
    local browser="$1"
    local id="CHK-BROWSER-EXTENSIONS"
    local name="${BROWSER_NAME[$browser]}"
    local plist="/Library/Managed Preferences/${BROWSER_PLIST_DOMAIN[$browser]}"

    if [[ ! -f "${plist}.plist" ]]; then
        report_result "$id" "Browser Security" \
            "[${name}] Cannot check extension policy — no managed policy plist" "WARN" "2.11" \
            "Deploy policy with ExtensionInstallBlocklist: §2.11.2" "$name"
        return
    fi

    local blocklist
    blocklist=$(defaults read "$plist" ExtensionInstallBlocklist 2>/dev/null) || blocklist=""
    if echo "$blocklist" | grep -qF '"*"' || echo "$blocklist" | grep -qF "'*'"; then
        report_result "$id" "Browser Security" \
            "[${name}] All extensions blocked by policy (allowlist-only)" "PASS" "2.11" "" "$name"
    elif [[ -n "$blocklist" ]]; then
        report_result "$id" "Browser Security" \
            "[${name}] Extension blocklist set but not blocking all (*)" "WARN" "2.11" \
            "Set ExtensionInstallBlocklist to [\"*\"] to block all, then allowlist specific IDs" "$name"
    else
        report_result "$id" "Browser Security" \
            "[${name}] No extension blocklist policy configured" "WARN" "2.11" \
            "Set ExtensionInstallBlocklist to [\"*\"]: §2.11.8" "$name"
    fi
}

check_browser_urlblock() {
    local browser="$1"
    local id="CHK-BROWSER-URLBLOCK"
    local name="${BROWSER_NAME[$browser]}"
    local plist="/Library/Managed Preferences/${BROWSER_PLIST_DOMAIN[$browser]}"

    if [[ ! -f "${plist}.plist" ]]; then
        report_result "$id" "Browser Security" \
            "[${name}] Cannot check URL blocklist — no managed policy plist" "WARN" "2.11" \
            "Deploy policy with URLBlocklist: §2.11.2" "$name"
        return
    fi

    local blocklist
    blocklist=$(defaults read "$plist" URLBlocklist 2>/dev/null) || blocklist=""
    if echo "$blocklist" | grep -qF '"*"' || echo "$blocklist" | grep -qF "'*'"; then
        report_result "$id" "Browser Security" \
            "[${name}] URLBlocklist deny-all-by-default configured" "PASS" "2.11" "" "$name"
    elif [[ -n "$blocklist" ]]; then
        report_result "$id" "Browser Security" \
            "[${name}] URLBlocklist is set but not deny-all-by-default" "WARN" "2.11" \
            "Set URLBlocklist to [\"*\"] for deny-all, then use URLAllowlist for permitted domains" "$name"
    else
        report_result "$id" "Browser Security" \
            "[${name}] No URLBlocklist configured — browser can navigate anywhere" "WARN" "2.11" \
            "Deploy URLBlocklist policy: §2.11.7 Defense Layer 1" "$name"
    fi
}

check_browser_cdp() {
    local browser="$1"
    local id="CHK-BROWSER-CDP"
    local name="${BROWSER_NAME[$browser]}"

    # Check CDP ports: 9222 (browser default) and 18800 (OpenClaw default)
    local cdp_listeners="" port exposed=false localhost_only=true active_ports=""
    for port in 9222 18800; do
        local listeners
        listeners=$(lsof -i :"$port" -sTCP:LISTEN 2>/dev/null) || true
        if [[ -n "$listeners" ]]; then
            cdp_listeners+="$listeners"$'\n'
            active_ports+="${active_ports:+, }$port"
            if echo "$listeners" | grep -q '0\.0\.0\.0:\|:\*:'; then
                exposed=true
            fi
            if ! echo "$listeners" | grep -qE '127\.0\.0\.1:|localhost:|\[::1\]:'; then
                localhost_only=false
            fi
        fi
    done

    if [[ -z "$cdp_listeners" ]]; then
        report_result "$id" "Browser Security" \
            "[${name}] No process listening on CDP ports (9222, 18800)" "PASS" "2.11" "" "$name"
        return
    fi

    if $exposed; then
        report_result "$id" "Browser Security" \
            "[${name}] CDP port(s) $active_ports bound to all interfaces (network-exposed)" "WARN" "2.11" \
            "Ensure --remote-debugging-address=127.0.0.1 and add pf rule: §2.11.3" "$name"
    elif $localhost_only; then
        report_result "$id" "Browser Security" \
            "[${name}] CDP port(s) $active_ports bound to localhost only" "PASS" "2.11" "" "$name"
    else
        report_result "$id" "Browser Security" \
            "[${name}] CDP port(s) $active_ports active — verify binding address" "WARN" "2.11" \
            "Run: lsof -i :9222 -i :18800 -sTCP:LISTEN to check binding" "$name"
    fi
}

check_browser_tcc() {
    local browser="$1"
    local id="CHK-BROWSER-TCC"
    local name="${BROWSER_NAME[$browser]}"
    local tcc_bundle="${BROWSER_TCC_BUNDLE[$browser]}"

    local tcc_db="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
    if [[ ! -f "$tcc_db" ]]; then
        report_result "$id" "Browser Security" \
            "[${name}] Cannot read TCC database" "SKIP" "2.11" "" "$name"
        return
    fi

    # Check for camera or microphone grants (auth_value=2 means allowed)
    local grants
    grants=$(sqlite3 "$tcc_db" \
        "SELECT service FROM access WHERE client='${tcc_bundle}' AND auth_value=2 AND service IN ('kTCCServiceCamera','kTCCServiceMicrophone')" \
        2>/dev/null) || grants=""

    if [[ -z "$grants" ]]; then
        report_result "$id" "Browser Security" \
            "[${name}] No camera/microphone TCC grants" "PASS" "2.11" "" "$name"
    else
        report_result "$id" "Browser Security" \
            "[${name}] Has camera/microphone TCC access: ${grants}" "WARN" "2.11" \
            "Reset: tccutil reset Camera ${tcc_bundle} && tccutil reset Microphone ${tcc_bundle}" "$name"
    fi
}

check_browser_version() {
    local browser="$1"
    local id="CHK-BROWSER-VERSION"
    local name="${BROWSER_NAME[$browser]}"
    local binary="${BROWSER_BINARY_PATH[$browser]}"
    local cask="${BROWSER_CASK[$browser]}"

    # Get browser version string
    local version_str=""
    if [[ -x "$binary" ]]; then
        version_str=$("$binary" --version 2>/dev/null) || true
    fi

    if [[ -z "$version_str" ]]; then
        report_result "$id" "Browser Security" \
            "[${name}] Could not determine version" "WARN" "2.11" \
            "Verify ${name} is installed and accessible" "$name"
        return
    fi

    # Extract major version number
    local major_version
    major_version=$(echo "$version_str" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1 | cut -d. -f1)

    if [[ -z "$major_version" ]]; then
        report_result "$id" "Browser Security" \
            "[${name}] Could not parse version: ${version_str}" "WARN" "2.11" "" "$name"
        return
    fi

    # All Chromium-based browsers follow the same major version cadence.
    # Chromium 100 shipped 2022-03-29 (epoch 1648512000). We estimate the
    # current major version from the date, then flag if installed version
    # is more than 2 major versions behind.
    local now_epoch chromium100_epoch=1648512000 secs_per_version=2419200  # 28 days
    now_epoch=$(date +%s)
    local estimated_current=$(( 100 + (now_epoch - chromium100_epoch) / secs_per_version ))
    local min_acceptable=$(( estimated_current - 2 ))

    if [[ "$major_version" -lt "$min_acceptable" ]]; then
        local update_hint="Update: brew upgrade --cask ${cask}"
        if ! run_as_user brew list --cask "$cask" &>/dev/null 2>&1; then
            update_hint="Update from ${name} menu > About or re-download from vendor"
        fi
        report_result "$id" "Browser Security" \
            "[${name}] Version $major_version may be outdated (expected ≥${min_acceptable})" "WARN" "2.11" \
            "$update_hint" "$name" "recommended"
    else
        report_result "$id" "Browser Security" \
            "[${name}] Version $major_version ($version_str)" "PASS" "2.11" "" "$name"
    fi
}

check_browser_dangerflags() {
    local browser="$1"
    local id="CHK-BROWSER-DANGERFLAGS"
    local name="${BROWSER_NAME[$browser]}"
    local process_name="${BROWSER_PROCESS_NAME[$browser]}"

    # Check running browser processes for dangerous flags
    local dangerous_flags="--disable-web-security|--allow-running-insecure-content|--disable-site-isolation-trials|--disable-features=IsolateOrigins|--remote-debugging-address=0\.0\.0\.0"
    local bad_flags
    bad_flags=$(ps aux 2>/dev/null | grep -F "$process_name" | grep -v grep | grep -oE -e "$dangerous_flags" | sort -u) || true

    if [[ -z "$bad_flags" ]]; then
        report_result "$id" "Browser Security" \
            "[${name}] No dangerous launch flags detected" "PASS" "2.11" "" "$name"
    else
        report_result "$id" "Browser Security" \
            "[${name}] Dangerous flags in use: ${bad_flags//$'\n'/, }" "WARN" "2.11" \
            "Remove dangerous flags from ${name} launch configuration: §2.11.9" "$name"
    fi

    # Also check OpenClaw config for dangerous browser.launchArgs
    local oc_config="$HOME/.openclaw/openclaw.json"
    if [[ -f "$oc_config" ]] && command -v jq &>/dev/null; then
        local bad_args
        bad_args=$(jq -r '.browser.launchArgs // [] | .[]' "$oc_config" 2>/dev/null \
            | grep -E "$dangerous_flags") || true
        if [[ -n "$bad_args" ]]; then
            report_result "$id" "Browser Security" \
                "[${name}] Dangerous flags in OpenClaw config: ${bad_args//$'\n'/, }" "WARN" "2.11" \
                "Edit ~/.openclaw/openclaw.json and remove dangerous browser.launchArgs" "$name"
        fi
    fi
}

# --- Multi-Browser Check Wrapper ---
# Iterates all installed browsers and runs all 8 checks for each.
run_browser_security_checks() {
    local installed
    installed=$(get_installed_browsers)

    if [[ -z "$installed" ]]; then
        report_result "CHK-BROWSER-POLICY" "Browser Security" \
            "No supported browser installed (browser checks skipped)" "SKIP" "2.11"
        return
    fi

    local browser
    for browser in $installed; do
        check_browser_policy "$browser"
        check_browser_autofill "$browser"
        check_browser_extensions "$browser"
        check_browser_urlblock "$browser"
        check_browser_cdp "$browser"
        check_browser_tcc "$browser"
        check_browser_version "$browser"
        check_browser_dangerflags "$browser"
    done
}

check_script_integrity() {
    local id="CHK-SCRIPT-INTEGRITY"
    local baseline_dir="/opt/n8n/baselines"
    if [[ ! -d "$baseline_dir" ]]; then
        baseline_dir="$HOME/openclaw-baselines"
    fi
    local hash_file="$baseline_dir/script-hashes.sha256"

    # Locate the scripts directory relative to this script
    local script_dir
    script_dir="$(cd "$(dirname "$0")" && pwd)"
    local audit_script="$script_dir/hardening-audit.sh"
    local fix_script="$script_dir/hardening-fix.sh"

    if [[ ! -f "$hash_file" ]]; then
        report_result "$id" "Operational" \
            "No script integrity baseline found" "WARN" "10.1" \
            "Checksums detect tampering — create after setup"
        return
    fi

    # Verify hashes — shasum -c returns 0 only if all hashes match
    local check_output
    if check_output=$(cd / && shasum -a 256 -c "$hash_file" 2>&1); then
        report_result "$id" "Operational" \
            "Audit and fix scripts match integrity baseline" "PASS" "10.1"
    else
        local mismatches
        mismatches=$(echo "$check_output" | grep -i "FAILED" | head -3) || true
        report_result "$id" "Operational" \
            "Script integrity mismatch: ${mismatches}" "WARN" "10.1" \
            "If scripts were intentionally updated, regenerate baseline: shasum -a 256 $audit_script $fix_script > $hash_file"
    fi
}

# --- Main ---
# ===========================================================================
# §11 — OpenClaw Agent Security (M3)
# Verifies agent deployment security: process binding, credential isolation,
# workspace integrity, webhook auth, extraction agent isolation.
# ===========================================================================

## Note: These checks run under sudo (via make audit). All $HOME references
## must use the real user's home, not root's. We use SUDO_USER where available.
_openclaw_home() {
    if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
        dscl . -read "/Users/${SUDO_USER}" NFSHomeDirectory 2>/dev/null | awk '{print $2}'
    else
        echo "$HOME"
    fi
}

check_openclaw_process() {
    local id="CHK-OPENCLAW-PROCESS"
    # Check if OpenClaw (or bun) process is running and bound to localhost
    # Use specific patterns to avoid matching editor sessions, greps, or this audit script
    local oc_pid
    oc_pid=$(pgrep -f "openclaw (start|serve|gateway)" 2>/dev/null \
          || pgrep -f "bun.*/openclaw" 2>/dev/null \
          || echo "")

    if [[ -z "$oc_pid" ]]; then
        report_result "$id" "OpenClaw Agent" \
            "OpenClaw process not running" "SKIP" "11.1" \
            "Start OpenClaw: openclaw start"
        return
    fi

    # Check if bound to localhost only (port 18789 for hooks)
    local listen_check
    listen_check=$(lsof -i -P -n 2>/dev/null | grep "$oc_pid" | grep "LISTEN" || true)

    if [[ -z "$listen_check" ]]; then
        report_result "$id" "OpenClaw Agent" \
            "OpenClaw running (PID ${oc_pid}), no listening ports detected" "PASS" "11.1"
    elif echo "$listen_check" | grep -qv "127.0.0.1\|localhost\|\*:"; then
        report_result "$id" "OpenClaw Agent" \
            "OpenClaw bound to non-localhost address" "FAIL" "11.1" \
            "Configure OpenClaw to bind to 127.0.0.1 only"
    else
        report_result "$id" "OpenClaw Agent" \
            "OpenClaw running (PID ${oc_pid}), localhost-only binding" "PASS" "11.1"
    fi
}

check_openclaw_creds() {
    local id="CHK-OPENCLAW-CREDS"
    local openclaw_dir
    openclaw_dir="$(_openclaw_home)/.openclaw"
    local found_creds=false

    # Scan OpenClaw environment for LinkedIn credentials that should NOT be there
    local scan_files=(
        "${openclaw_dir}/.env"
        "${openclaw_dir}/openclaw.json"
    )

    # Also scan agent workspace files
    if [[ -d "${openclaw_dir}/agents" ]]; then
        while IFS= read -r -d '' f; do
            scan_files+=("$f")
        done < <(find "${openclaw_dir}/agents" \( -name ".env" -o -name "*.json" \) -print0 2>/dev/null)
    fi

    local offending_file=""
    local offending_pattern=""
    for f in "${scan_files[@]}"; do
        if [[ -f "$f" ]]; then
            # Check for LinkedIn OAuth tokens, li_at cookies, JSESSIONID
            local match
            match=$(grep -iE 'li_at|JSESSIONID|linkedin.*token|linkedin.*secret|w_member_social' "$f" 2>/dev/null | head -1 || true)
            if [[ -n "$match" ]]; then
                found_creds=true
                offending_file="$f"
                offending_pattern="$match"
                break
            fi
        fi
    done

    if [[ "$found_creds" == "true" ]]; then
        report_result "$id" "OpenClaw Agent" \
            "LinkedIn credentials found in ${offending_file} — credential isolation violated" "FAIL" "11.2" \
            "Remove from ${offending_file}: ${offending_pattern}"
    else
        report_result "$id" "OpenClaw Agent" \
            "No LinkedIn credentials in OpenClaw environment" "PASS" "11.2"
    fi
}

check_openclaw_creds_n8n_api() {
    local id="CHK-OPENCLAW-CREDS-N8N-API"
    local openclaw_dir
    openclaw_dir="$(_openclaw_home)/.openclaw"
    local found_api_key=false

    local scan_files=(
        "${openclaw_dir}/.env"
        "${openclaw_dir}/openclaw.json"
    )

    if [[ -d "${openclaw_dir}/agents" ]]; then
        while IFS= read -r -d '' f; do
            scan_files+=("$f")
        done < <(find "${openclaw_dir}/agents" -name ".env" -print0 2>/dev/null)
    fi

    local offending_file=""
    for f in "${scan_files[@]}"; do
        if [[ -f "$f" ]]; then
            if grep -qE 'N8N_API_KEY' "$f" 2>/dev/null; then
                found_api_key=true
                offending_file="$f"
                break
            fi
        fi
    done

    if [[ "$found_api_key" == "true" ]]; then
        report_result "$id" "OpenClaw Agent" \
            "N8N_API_KEY found in ${offending_file} — privilege escalation risk (R-002)" "FAIL" "11.2" \
            "Remove N8N_API_KEY from ${offending_file}. Use config-update webhook instead of direct n8n API."
    else
        report_result "$id" "OpenClaw Agent" \
            "N8N_API_KEY not in OpenClaw environment" "PASS" "11.2"
    fi
}

check_openclaw_workspace() {
    local id="CHK-OPENCLAW-WORKSPACE"
    local manifest
    manifest="$(_openclaw_home)/.openclaw/manifest.json"

    if [[ ! -f "$manifest" ]]; then
        report_result "$id" "OpenClaw Agent" \
            "Workspace manifest not found — run 'make manifest-update' to initialize" "SKIP" "11.3" \
            "Run: make manifest-update"
        return
    fi

    local mismatch_count=0
    local checked_count=0

    # Read manifest entries and verify checksums
    while IFS= read -r entry; do
        local file_path checksum_expected
        file_path=$(echo "$entry" | jq -r '.path')
        checksum_expected=$(echo "$entry" | jq -r '.sha256')

        if [[ ! -f "$file_path" ]]; then
            mismatch_count=$((mismatch_count + 1))
            continue
        fi

        local checksum_actual
        checksum_actual=$(shasum -a 256 "$file_path" | awk '{print $1}')
        checked_count=$((checked_count + 1))

        if [[ "$checksum_actual" != "$checksum_expected" ]]; then
            mismatch_count=$((mismatch_count + 1))
        fi
    done < <(jq -c '.files[]' "$manifest" 2>/dev/null)

    if [[ "$checked_count" -eq 0 ]]; then
        report_result "$id" "OpenClaw Agent" \
            "Workspace manifest empty or malformed" "WARN" "11.3" \
            "Run: make manifest-update" "" "" "recommended"
    elif [[ "$mismatch_count" -gt 0 ]]; then
        report_result "$id" "OpenClaw Agent" \
            "Workspace file integrity: ${mismatch_count} file(s) modified since last manifest update" "WARN" "11.3" \
            "If intentional, run: make manifest-update. If not, investigate unauthorized changes." "" "" "recommended"
    else
        report_result "$id" "OpenClaw Agent" \
            "Workspace file integrity: ${checked_count} file(s) match manifest checksums" "PASS" "11.3"
    fi
}

check_openclaw_webhook_auth() {
    local id="CHK-OPENCLAW-WEBHOOK-AUTH"

    # Test if n8n is reachable
    if ! curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:5678" --max-time 3 &>/dev/null; then
        report_result "$id" "OpenClaw Agent" \
            "n8n not reachable at localhost:5678 — cannot verify webhook auth" "SKIP" "11.4" \
            "Ensure n8n is running: docker compose up -d"
        return
    fi

    # Test multiple webhook endpoints with unsigned requests — all should reject
    # We test actual endpoints (not a dummy path) because we need to verify
    # the HMAC sub-workflow is wired in. But we send no X-Signature header,
    # so the hmac-verify step should reject before any LinkedIn API call.
    local endpoints=("linkedin-post" "linkedin-comment" "linkedin-like")
    local all_pass=true
    local any_found=false
    local tested=0
    local failed_endpoint=""

    for ep in "${endpoints[@]}"; do
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" \
            -X POST "http://127.0.0.1:5678/webhook/${ep}" \
            -H "Content-Type: application/json" \
            -d '{"action":"auth-test"}' \
            --max-time 5 2>/dev/null || echo "000")

        if [[ "$http_code" == "404" ]]; then
            continue  # Workflow not imported yet — skip
        fi

        any_found=true
        tested=$((tested + 1))

        if [[ "$http_code" == "200" ]]; then
            all_pass=false
            failed_endpoint="$ep"
            break
        fi
        # 401, 403, 500 (hmac rejection) all count as "auth is working"
    done

    if [[ "$any_found" == "false" ]]; then
        report_result "$id" "OpenClaw Agent" \
            "No webhook endpoints found (HTTP 404) — workflows may not be imported yet" "SKIP" "11.4" \
            "Import workflows: make workflow-import"
    elif [[ "$all_pass" == "true" ]]; then
        report_result "$id" "OpenClaw Agent" \
            "All ${tested} webhook endpoint(s) reject unsigned requests" "PASS" "11.4"
    else
        report_result "$id" "OpenClaw Agent" \
            "Webhook /webhook/${failed_endpoint} accepted unsigned request — HMAC verification not working" "FAIL" "11.4" \
            "Verify hmac-verify sub-workflow is called as first step in ${failed_endpoint} workflow"
    fi
}

check_openclaw_n8n_creds() {
    local id="CHK-OPENCLAW-N8N-CREDS"

    # Check if N8N_ENCRYPTION_KEY is set in Docker environment
    local enc_key
    enc_key=$(docker exec openclaw-n8n printenv N8N_ENCRYPTION_KEY 2>/dev/null || echo "")

    if [[ -z "$enc_key" ]]; then
        # Check if it's loaded via Docker secrets instead
        if docker exec openclaw-n8n test -f /run/secrets/n8n_encryption_key 2>/dev/null; then
            report_result "$id" "OpenClaw Agent" \
                "n8n encryption key loaded via Docker secret" "PASS" "11.5"
        else
            report_result "$id" "OpenClaw Agent" \
                "N8N_ENCRYPTION_KEY not set — credential store may not be encrypted" "WARN" "11.5" \
                "Set N8N_ENCRYPTION_KEY in docker-compose.yml or use Docker secrets" "" "" "recommended"
        fi
    else
        report_result "$id" "OpenClaw Agent" \
            "n8n encryption key is set" "PASS" "11.5"
    fi
}

check_openclaw_extraction_agent() {
    local id="CHK-OPENCLAW-EXTRACTION-AGENT"
    # OpenClaw workspace files live at agent root, not in agent/ subdir
    local extractor_dir
    extractor_dir="$(_openclaw_home)/.openclaw/agents/feed-extractor"

    if [[ ! -d "$extractor_dir" ]]; then
        report_result "$id" "OpenClaw Agent" \
            "Extraction agent (feed-extractor) not deployed" "SKIP" "11.6" \
            "Deploy extraction agent: copy openclaw-extractor/ to ~/.openclaw/agents/feed-extractor/agent/"
        return
    fi

    local has_tools=false
    local has_skills=false

    # Check for any tool configuration
    if [[ -d "${extractor_dir}/tools" ]] && [[ -n "$(ls -A "${extractor_dir}/tools" 2>/dev/null)" ]]; then
        has_tools=true
    fi

    # Check for any skill folders
    if [[ -d "${extractor_dir}/skills" ]] && [[ -n "$(ls -A "${extractor_dir}/skills" 2>/dev/null)" ]]; then
        has_skills=true
    fi

    if [[ "$has_tools" == "true" || "$has_skills" == "true" ]]; then
        report_result "$id" "OpenClaw Agent" \
            "Extraction agent has tools or skills — Rule of Two violated (R-012)" "FAIL" "11.6" \
            "Remove all tools and skills from feed-extractor workspace. It must have zero capabilities."
    else
        report_result "$id" "OpenClaw Agent" \
            "Extraction agent has zero tools and zero skills (Rule of Two enforced)" "PASS" "11.6"
    fi
}

# ===========================================================================
# §12 Workspace Integrity checks (M4 — T040-T047)
# ===========================================================================

# Source integrity library for shared functions
# shellcheck source=lib/integrity.sh
source "${SCRIPT_DIR}/lib/integrity.sh" 2>/dev/null || true

check_openclaw_integrity_lock() {
    local id="CHK-OPENCLAW-INTEGRITY-LOCK"
    local manifest="${HOME}/.openclaw/manifest.json"

    if [[ ! -f "$manifest" ]]; then
        report_result "$id" "Workspace Integrity" \
            "Integrity manifest not found" "SKIP" "12.1" \
            "Run: make integrity-deploy && sudo make integrity-lock"
        return
    fi

    local total=0 locked=0 unlocked_files=""
    while IFS= read -r entry; do
        local path
        path=$(echo "$entry" | jq -r '.path')
        total=$((total + 1))
        if [[ -f "$path" ]] && ls -lO "$path" 2>/dev/null | grep -q "uchg"; then
            locked=$((locked + 1))
        elif [[ -f "$path" ]]; then
            unlocked_files="${unlocked_files}${path} "
        fi
    done < <(jq -c '.files[]' "$manifest" 2>/dev/null)

    if [[ $locked -eq $total ]]; then
        report_result "$id" "Workspace Integrity" \
            "All ${total} protected files have uchg flag" "PASS" "12.1"
    elif [[ $locked -gt 0 ]]; then
        report_result "$id" "Workspace Integrity" \
            "${locked}/${total} files locked (some unlocked)" "WARN" "12.1" \
            "Unlocked: ${unlocked_files:0:100}" "" "recommended"
    else
        report_result "$id" "Workspace Integrity" \
            "No protected files are locked" "FAIL" "12.1" \
            "Run: sudo make integrity-lock"
    fi
}

check_openclaw_integrity_manifest() {
    local id="CHK-OPENCLAW-INTEGRITY-MANIFEST"
    local manifest="${HOME}/.openclaw/manifest.json"

    if [[ ! -f "$manifest" ]]; then
        report_result "$id" "Workspace Integrity" \
            "Integrity manifest not found" "SKIP" "12.2" \
            "Run: make integrity-deploy"
        return
    fi

    # Verify HMAC signature
    if ! type integrity_verify_signature &>/dev/null; then
        report_result "$id" "Workspace Integrity" \
            "integrity.sh not loaded — cannot verify manifest" "SKIP" "12.2"
        return
    fi

    if ! integrity_verify_signature "$manifest" 2>/dev/null; then
        report_result "$id" "Workspace Integrity" \
            "Manifest HMAC signature invalid — possible tampering" "FAIL" "12.2" \
            "Rebuild: make integrity-deploy && sudo make integrity-lock"
        return
    fi

    # Verify checksums
    local total=0 mismatched=0
    while IFS= read -r entry; do
        local path expected actual
        path=$(echo "$entry" | jq -r '.path')
        expected=$(echo "$entry" | jq -r '.sha256')
        total=$((total + 1))
        if [[ -f "$path" ]]; then
            actual=$(shasum -a 256 "$path" | awk '{print $1}')
            [[ "$expected" != "$actual" ]] && mismatched=$((mismatched + 1))
        fi
    done < <(jq -c '.files[]' "$manifest" 2>/dev/null)

    if [[ $mismatched -eq 0 ]]; then
        report_result "$id" "Workspace Integrity" \
            "Manifest signature valid, all ${total} checksums match" "PASS" "12.2"
    else
        report_result "$id" "Workspace Integrity" \
            "${mismatched}/${total} file checksums do not match manifest" "FAIL" "12.2" \
            "Rebuild: make integrity-deploy && sudo make integrity-lock"
    fi
}

check_openclaw_sandbox_mode() {
    local id="CHK-OPENCLAW-SANDBOX-MODE"
    local config="${HOME}/.openclaw/openclaw.json"

    if [[ ! -f "$config" ]]; then
        report_result "$id" "Workspace Integrity" \
            "openclaw.json not found" "SKIP" "12.3" \
            "Run: make sandbox-setup"
        return
    fi

    local persona_mode extractor_mode
    persona_mode=$(jq -r '.agents.list[] | select(.id == "linkedin-persona") | .sandbox.mode // empty' "$config" 2>/dev/null)
    extractor_mode=$(jq -r '.agents.list[] | select(.id == "feed-extractor") | .sandbox.mode // empty' "$config" 2>/dev/null)

    if [[ "$persona_mode" == "all" && "$extractor_mode" == "all" ]]; then
        report_result "$id" "Workspace Integrity" \
            "Sandbox mode enabled for both agents" "PASS" "12.3"
    else
        local missing=""
        [[ "$persona_mode" != "all" ]] && missing="linkedin-persona "
        [[ "$extractor_mode" != "all" ]] && missing="${missing}feed-extractor"
        report_result "$id" "Workspace Integrity" \
            "Sandbox not configured: ${missing}" "FAIL" "12.3" \
            "Run: make sandbox-setup"
    fi
}

check_openclaw_sandbox_tools() {
    local id="CHK-OPENCLAW-SANDBOX-TOOLS"
    local config="${HOME}/.openclaw/openclaw.json"

    if [[ ! -f "$config" ]]; then
        report_result "$id" "Workspace Integrity" \
            "openclaw.json not found" "SKIP" "12.4"
        return
    fi

    local persona_deny extractor_allow
    persona_deny=$(jq -r '.agents.list[] | select(.id == "linkedin-persona") | .tools.deny | length // 0' "$config" 2>/dev/null)
    extractor_allow=$(jq -r '.agents.list[] | select(.id == "feed-extractor") | .tools.allow | length // 0' "$config" 2>/dev/null)

    local issues=""
    [[ "$persona_deny" -eq 0 ]] 2>/dev/null && issues="linkedin-persona has no denied tools; "
    [[ "$extractor_allow" != "0" ]] 2>/dev/null && issues="${issues}feed-extractor has allowed tools"

    if [[ -z "$issues" ]]; then
        report_result "$id" "Workspace Integrity" \
            "Tool restrictions configured (persona deny=${persona_deny}, extractor allow=0)" "PASS" "12.4"
    else
        report_result "$id" "Workspace Integrity" \
            "Tool restrictions misconfigured: ${issues}" "FAIL" "12.4" \
            "Run: make sandbox-setup"
    fi
}

check_openclaw_monitor_status() {
    local id="CHK-OPENCLAW-MONITOR-STATUS"
    local plist_name="com.openclaw.integrity-monitor"
    local heartbeat="${HOME}/.openclaw/integrity-monitor-heartbeat.json"

    if ! launchctl list 2>/dev/null | grep -q "$plist_name"; then
        report_result "$id" "Workspace Integrity" \
            "Integrity monitor LaunchAgent not loaded" "FAIL" "12.5" \
            "Run: make monitor-setup"
        return
    fi

    if [[ ! -f "$heartbeat" ]]; then
        report_result "$id" "Workspace Integrity" \
            "Monitor loaded but no heartbeat file" "WARN" "12.5" \
            "Check logs: ~/.openclaw/logs/integrity-monitor.err.log" "" "recommended"
        return
    fi

    local ts now_epoch hb_epoch age
    ts=$(jq -r '.timestamp' "$heartbeat" 2>/dev/null)
    now_epoch=$(date +%s)
    hb_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null || echo 0)
    age=$((now_epoch - hb_epoch))

    if [[ $age -lt 60 ]]; then
        report_result "$id" "Workspace Integrity" \
            "Monitor running, heartbeat ${age}s ago" "PASS" "12.5"
    else
        report_result "$id" "Workspace Integrity" \
            "Monitor heartbeat stale (${age}s old)" "WARN" "12.5" \
            "Restart: make monitor-teardown && make monitor-setup" "" "recommended"
    fi
}

check_openclaw_skillallow() {
    local id="CHK-OPENCLAW-SKILLALLOW"
    local allowlist="${HOME}/.openclaw/skill-allowlist.json"

    if [[ ! -f "$allowlist" ]]; then
        report_result "$id" "Workspace Integrity" \
            "Skill allowlist not found" "WARN" "12.6" \
            "Run: make skillallow-add NAME=<skill> for each skill" "" "recommended"
        return
    fi

    local repo_root
    repo_root="$(resolve_repo_root "$SCRIPT_DIR" 2>/dev/null || echo "")"
    local total=0 passed=0

    # Check both repo skills and deployed agent skills
    local -a skill_dirs=()
    [[ -d "${repo_root}/openclaw/skills" ]] && skill_dirs+=("${repo_root}/openclaw/skills")
    while IFS= read -r d; do
        [[ -d "$d" ]] && skill_dirs+=("$d")
    done < <(find "${HOME}/.openclaw/agents" -type d -name "skills" 2>/dev/null)

    local -A seen_skills
    for parent in "${skill_dirs[@]}"; do
        for skill_dir in "${parent}"/*/; do
            local skill_file="${skill_dir}SKILL.md"
            [[ -f "$skill_file" ]] || continue
            local name
            name=$(basename "$skill_dir")
            [[ -n "${seen_skills[$name]:-}" ]] && continue
            seen_skills[$name]=1
            total=$((total + 1))

            local hash approved
            hash=$(shasum -a 256 "$skill_file" | awk '{print $1}')
            approved=$(jq -r --arg n "$name" '.skills[] | select(.name == $n) | .content_hash // empty' "$allowlist" 2>/dev/null)

            [[ "$hash" == "$approved" ]] && passed=$((passed + 1))
        done
    done

    if [[ $total -eq 0 ]]; then
        report_result "$id" "Workspace Integrity" \
            "No skills installed" "PASS" "12.6"
    elif [[ $passed -eq $total ]]; then
        report_result "$id" "Workspace Integrity" \
            "All ${total} skills match allowlist hashes" "PASS" "12.6"
    else
        report_result "$id" "Workspace Integrity" \
            "$((total - passed))/${total} skills have hash mismatches" "FAIL" "12.6" \
            "Re-approve: make skillallow-add NAME=<skill>"
    fi
}

check_openclaw_symlink() {
    local id="CHK-OPENCLAW-SYMLINK"

    if ! type integrity_check_symlinks &>/dev/null; then
        report_result "$id" "Workspace Integrity" \
            "integrity.sh not loaded — cannot check symlinks" "SKIP" "12.7"
        return
    fi

    local repo_root
    repo_root="$(resolve_repo_root "$SCRIPT_DIR" 2>/dev/null || echo "")"

    if integrity_check_symlinks "$repo_root" 2>/dev/null; then
        report_result "$id" "Workspace Integrity" \
            "No symlinks in protected directories" "PASS" "12.7"
    else
        report_result "$id" "Workspace Integrity" \
            "Symlinks found in protected directories" "FAIL" "12.7" \
            "Remove symlinks from agent workspace and scripts directories"
    fi
}

check_openclaw_platform_version() {
    local id="CHK-OPENCLAW-PLATFORM-VERSION"
    local manifest="${HOME}/.openclaw/manifest.json"

    if [[ ! -f "$manifest" ]]; then
        report_result "$id" "Workspace Integrity" \
            "Manifest not found — cannot verify platform version" "SKIP" "12.8"
        return
    fi

    local manifest_ver current_ver
    manifest_ver=$(jq -r '.platform_version // empty' "$manifest" 2>/dev/null)
    current_ver=$(openclaw --version 2>/dev/null || echo "unknown")

    if [[ -z "$manifest_ver" ]]; then
        report_result "$id" "Workspace Integrity" \
            "No platform version in manifest" "WARN" "12.8" \
            "Rebuild manifest: make integrity-deploy"
        return
    fi

    if [[ "$manifest_ver" == "$current_ver" ]]; then
        report_result "$id" "Workspace Integrity" \
            "Platform version matches manifest: ${current_ver}" "PASS" "12.8"
    else
        report_result "$id" "Workspace Integrity" \
            "Platform version changed (manifest: ${manifest_ver}, current: ${current_ver})" "FAIL" "12.8" \
            "Rebuild after update: make integrity-deploy && sudo make integrity-lock"
    fi
}

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
            --compare)
                COMPARE_FILE="${2:-}"
                if [[ -z "$COMPARE_FILE" ]]; then
                    echo "Error: --compare requires a JSON file path" >&2
                    exit 2
                fi
                if [[ ! -f "$COMPARE_FILE" ]]; then
                    echo "Error: Compare file not found: ${COMPARE_FILE}" >&2
                    exit 2
                fi
                shift 2
                ;;
            --no-color)
                # shellcheck disable=SC2034
                NO_COLOR=true
                RED='' GREEN='' YELLOW='' CYAN='' NC=''
                shift
                ;;
            --debug)
                DEBUG=true
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

    if [[ "$DEBUG" == true ]]; then set -x; fi

    # Warn if --json used without jq
    if $JSON_OUTPUT && ! command -v jq &>/dev/null; then
        echo "Warning: jq not found — JSON output will not be pretty-printed" >&2
    fi

    check_platform

    local deployment
    deployment=$(detect_deployment)
    local macos_version
    macos_version=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
    local hardware
    hardware=$(uname -m 2>/dev/null || echo "unknown")

    if ! $JSON_OUTPUT; then
        echo "================================================================"
        echo "  OpenClaw Mac Hardening Audit"
        printf "  Version: %s | Date: %s\n" "$VERSION" "$(date +%Y-%m-%d)"
        printf "  Deployment: %s | macOS: %s\n" "$deployment" "$macos_version"
        echo "================================================================"
    fi

    # --- Run All Checks ---
    # OS Foundation checks (migrated from existing verification script)
    run_check check_sip
    run_check check_filevault
    run_check check_firewall
    run_check check_stealth_mode

    # §2 OS Foundation — extended checks (T014)
    run_check check_gatekeeper
    run_check check_xprotect_fresh
    run_check check_auto_updates
    run_check check_ntp
    run_check check_auto_login
    run_check check_screen_lock
    run_check check_password_policy
    run_check check_guest
    run_check check_sharing_file
    run_check check_sharing_remote_events
    run_check check_sharing_internet
    run_check check_sharing_screen
    run_check check_airdrop
    run_check check_startup_security
    run_check check_tcc
    run_check check_core_dumps
    run_check check_privacy
    run_check check_profiles
    run_check check_spotlight

    # §3 Network Security checks (T019)
    run_check check_ssh_key_only
    run_check check_ssh_root
    run_check check_dns_encrypted
    run_check check_outbound_filter
    run_check check_bluetooth
    run_check check_ipv6
    run_check check_listeners_baseline

    # §4.1 Container Runtime
    run_check check_colima_running
    run_check check_colima_vm_mounts

    # §4 Container Isolation checks (T024) — containerized only
    if [[ "$deployment" == "containerized" ]]; then
        run_check check_container_root
        run_check check_container_readonly
        run_check check_container_caps
        run_check check_container_privileged
        run_check check_docker_socket
        run_check check_secrets_env
        run_check check_colima_mounts
        run_check check_container_network
        run_check check_container_resources
    fi

    # §5 n8n Platform Security checks (T029)
    run_check check_n8n_bind
    run_check check_n8n_auth
    run_check check_n8n_api
    run_check check_n8n_env_block
    run_check check_n8n_env_diagnostics
    run_check check_n8n_env_api
    run_check check_n8n_nodes
    run_check check_n8n_webhook

    # §2.11 Browser Security (Chromium / Chrome / Edge)
    run_check run_browser_security_checks

    # §6 Bare-Metal Path checks (T032) — bare-metal only
    if [[ "$deployment" == "bare-metal" || "$deployment" == "unknown" ]]; then
        run_check check_service_account
        run_check check_service_home_perms
        run_check check_service_data_perms
    fi

    # §7 Data Security checks (T038)
    run_check check_cred_env_visible
    run_check check_docker_inspect_secrets
    run_check check_spotlight_exclusions
    run_check check_config_profiles

    # §8 Detection and Monitoring checks (T045)
    run_check check_santa
    run_check check_blockblock
    run_check check_lulu
    run_check check_clamav
    run_check check_clamav_sigs
    run_check check_persistence_baseline
    run_check check_workflow_baseline
    run_check check_listener_baseline
    run_check check_cert_baseline
    run_check check_icloud_keychain
    run_check check_icloud_drive
    run_check check_canary

    # §9 Response and Recovery checks (T050)
    run_check check_backup_configured
    run_check check_backup_encrypted
    run_check check_find_my_mac
    run_check check_usb

    # §10 Operational Maintenance checks (T058)
    run_check check_launchd_audit_job
    run_check check_notification_config
    run_check check_log_dir
    run_check check_clamav_freshness
    run_check check_script_integrity

    # §11 OpenClaw Agent Security checks (M3 — T071-T077)
    run_check check_openclaw_process
    run_check check_openclaw_creds
    run_check check_openclaw_creds_n8n_api
    run_check check_openclaw_workspace
    run_check check_openclaw_webhook_auth
    run_check check_openclaw_n8n_creds
    run_check check_openclaw_extraction_agent

    # §12 Workspace Integrity checks (M4 — T040-T047)
    run_check check_openclaw_integrity_lock
    run_check check_openclaw_integrity_manifest
    run_check check_openclaw_sandbox_mode
    run_check check_openclaw_sandbox_tools
    run_check check_openclaw_monitor_status
    run_check check_openclaw_skillallow
    run_check check_openclaw_symlink
    run_check check_openclaw_platform_version

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
        echo ""
        echo "================================================================"
        printf "  Results: ${GREEN}%d PASS${NC} | ${RED}%d FAIL${NC} | ${YELLOW}%d WARN${NC}" \
            "$PASS_COUNT" "$FAIL_COUNT" "$WARN_COUNT"
        if [[ $SKIP_COUNT -gt 0 ]]; then
            printf " | ${CYAN}%d SKIP${NC}" "$SKIP_COUNT"
        fi
        echo ""

        if [[ $FAIL_COUNT -eq 0 && $WARN_COUNT -eq 0 ]]; then
            printf "  ${GREEN}All checks passed.${NC}\n"
        elif [[ $FAIL_COUNT -eq 0 ]]; then
            printf "  ${GREEN}No critical issues.${NC} %d optional improvement(s) below.\n" "$WARN_COUNT"
        else
            printf "  ${RED}Action required:${NC} Fix %d FAIL item(s).\n" "$FAIL_COUNT"
        fi
        echo "================================================================"

        # --- End-of-audit summary ---
        if [[ ${#FAIL_SUMMARIES[@]} -gt 0 ]]; then
            echo ""
            printf "  ${RED}Fix these (%d):${NC}\n" "${#FAIL_SUMMARIES[@]}"
            for entry in "${FAIL_SUMMARIES[@]}"; do
                local desc="${entry%%|*}"
                local fix="${entry#*|}"
                printf "    • %s\n" "$desc"
                printf "      ${CYAN}%s${NC}\n" "$fix"
            done
        fi

        if [[ ${#WARN_ACTIONABLE[@]} -gt 0 ]]; then
            echo ""
            printf "  ${YELLOW}Recommended (%d):${NC}\n" "${#WARN_ACTIONABLE[@]}"
            for entry in "${WARN_ACTIONABLE[@]}"; do
                local desc="${entry%%|*}"
                local fix="${entry#*|}"
                printf "    • %s\n" "$desc"
                printf "      ${CYAN}%s${NC}\n" "$fix"
            done
        fi

        if [[ ${#WARN_OPTIONAL[@]} -gt 0 ]]; then
            echo ""
            printf "  Optional (%d):\n" "${#WARN_OPTIONAL[@]}"
            for entry in "${WARN_OPTIONAL[@]}"; do
                local desc="${entry%%|*}"
                local fix="${entry#*|}"
                printf "    • %s\n" "$desc"
                if [[ -n "$fix" ]]; then
                    printf "      ${CYAN}%s${NC}\n" "$fix"
                fi
            done
        fi
    fi

    # --- Drift Comparison ---
    if [[ -n "$COMPARE_FILE" ]] && command -v jq &>/dev/null; then
        local current_tmp
        current_tmp=$(mktemp /tmp/openclaw-current.XXXXXX)
        printf '{"results":%s}' "$JSON_RESULTS" > "$current_tmp"
        _compare_results "$COMPARE_FILE" "$current_tmp"
        rm -f "$current_tmp"
    fi

    # Exit code: 1 if any FAIL, 0 otherwise
    if [[ $FAIL_COUNT -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

# --- Drift Comparison ---
# Compares the current audit results against a previous JSON file.
# Reports regressions (PASS→FAIL/WARN), improvements (FAIL→PASS), and net change.
_compare_results() {
    local baseline="$1"
    local current_file="$2"

    if ! jq empty "$baseline" 2>/dev/null; then
        echo ""
        printf "  ${RED}Compare: Invalid JSON in baseline file${NC}\n"
        return
    fi

    if ! jq empty "$current_file" 2>/dev/null; then
        echo ""
        printf "  ${YELLOW}Compare: Could not build current results for comparison${NC}\n"
        return
    fi

    local regressions=0 improvements=0

    # Use jq to compute the diff (file-based to avoid arg size limits)
    local diff_output
    diff_output=$(jq -s '
        def status_map: [.[] | {(.id): .status}] | add // {};
        (.[0] | status_map) as $old |
        (.[1] | status_map) as $new |
        {
            regressions: [$new | to_entries[] |
                select($old[.key] != null and
                    (($old[.key] == "PASS" and (.value == "FAIL" or .value == "WARN")) or
                     ($old[.key] == "WARN" and .value == "FAIL"))) |
                {id: .key, was: $old[.key], now: .value}],
            improvements: [$new | to_entries[] |
                select($old[.key] != null and
                    (($old[.key] == "FAIL" and (.value == "PASS" or .value == "WARN")) or
                     ($old[.key] == "WARN" and .value == "PASS"))) |
                {id: .key, was: $old[.key], now: .value}],
            summary_old: {
                pass: ([$old | to_entries[] | select(.value == "PASS")] | length),
                fail: ([$old | to_entries[] | select(.value == "FAIL")] | length)
            },
            summary_new: {
                pass: ([$new | to_entries[] | select(.value == "PASS")] | length),
                fail: ([$new | to_entries[] | select(.value == "FAIL")] | length)
            }
        }
        ' <(jq '.results' "$baseline") <(jq '.results' "$current_file") 2>/dev/null) || true

    if [[ -z "$diff_output" || "$diff_output" == "null" ]]; then
        echo ""
        printf "  ${YELLOW}Compare: Could not compute diff (jq error)${NC}\n"
        return
    fi

    regressions=$(echo "$diff_output" | jq '.regressions | length')
    improvements=$(echo "$diff_output" | jq '.improvements | length')

    echo ""
    echo "================================================================"
    echo "  Drift Report (compared to baseline)"
    echo "================================================================"

    if [[ "$regressions" -gt 0 ]]; then
        printf "  ${RED}Regressions (%d):${NC}\n" "$regressions"
        echo "$diff_output" | jq -r '.regressions[] | "    \(.id): \(.was) → \(.now)"'
    fi

    if [[ "$improvements" -gt 0 ]]; then
        printf "  ${GREEN}Improvements (%d):${NC}\n" "$improvements"
        echo "$diff_output" | jq -r '.improvements[] | "    \(.id): \(.was) → \(.now)"'
    fi

    if [[ "$regressions" -eq 0 && "$improvements" -eq 0 ]]; then
        printf "  ${GREEN}No drift detected — security posture unchanged${NC}\n"
    fi

    # Net summary
    local old_pass new_pass old_fail new_fail
    old_pass=$(echo "$diff_output" | jq '.summary_old.pass')
    new_pass=$(echo "$diff_output" | jq '.summary_new.pass')
    old_fail=$(echo "$diff_output" | jq '.summary_old.fail')
    new_fail=$(echo "$diff_output" | jq '.summary_new.fail')
    printf "  Net: PASS %d→%d | FAIL %d→%d\n" "$old_pass" "$new_pass" "$old_fail" "$new_fail"
    echo "================================================================"
}

main "$@"
