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

readonly VERSION="0.1.0"
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME

# --- Color Setup ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Auto-disable colors when stdout is not a terminal
if [[ ! -t 1 ]]; then
    RED='' GREEN='' YELLOW='' CYAN='' NC=''
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
# NO_COLOR is a conventional env flag; --no-color sets color vars directly
# shellcheck disable=SC2034
NO_COLOR=false

# --- JSON accumulator ---
JSON_RESULTS="[]"

# --- Current section for grouped output ---
CURRENT_SECTION=""

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
  --json         Output results in JSON format (FR-023)
  --section SEC  Run checks for a specific section only
  --quiet        Suppress PASS output, show only FAIL/WARN
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
        json_entry=$(printf '{"id":"%s","section":"%s","description":"%s","status":"%s","guide_ref":"§%s"' \
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
    # Try multiple date formats: zero-padded, single-digit, and ISO
    update_epoch=$(date -j -f "%m/%d/%y, %I:%M %p" "$last_update" "+%s" 2>/dev/null) || \
    update_epoch=$(date -j -f "%-m/%-d/%y, %-I:%M %p" "$last_update" "+%s" 2>/dev/null) || \
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
    ask_pw=$(defaults read com.apple.screensaver askForPassword 2>/dev/null) || true
    local delay
    delay=$(defaults read com.apple.screensaver askForPasswordDelay 2>/dev/null) || true
    if [[ "$ask_pw" == "1" && "$delay" == "0" ]]; then
        report_result "$id" "Login Security" "Screen lock requires password immediately" "PASS" "2.6"
    else
        report_result "$id" "Login Security" "Screen lock not configured optimally" "WARN" "2.6" \
            "Set: defaults write com.apple.screensaver askForPassword -int 1 && defaults write com.apple.screensaver askForPasswordDelay -int 0"
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
    output=$(defaults read com.apple.NetworkBrowser DisableAirDrop 2>/dev/null) || true
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
                "Set firmware password via Recovery Mode > Startup Security Utility"
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
    siri=$(defaults read com.apple.assistant.support "Assistant Enabled" 2>/dev/null) || true
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
            "Review: profiles list — remove unauthorized profiles with: sudo profiles remove -identifier <id>"
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

# --- §4 Container Isolation Checks (T024) ---

check_container_root() {
    local id="CHK-CONTAINER-ROOT"
    local container_id
    container_id=$(docker ps -q --filter "name=n8n" 2>/dev/null | head -1) || true
    if [[ -z "$container_id" ]]; then
        report_result "$id" "Container Security" "No n8n container running" "SKIP" "4.3"
        return
    fi
    local user
    user=$(docker inspect "$container_id" --format '{{.Config.User}}' 2>/dev/null) || true
    if [[ -n "$user" && "$user" != "0" && "$user" != "root" ]]; then
        report_result "$id" "Container Security" "Container runs as non-root (${user})" "PASS" "4.3"
    else
        report_result "$id" "Container Security" "Container runs as root" "FAIL" "4.3" \
            "Set user: '1000:1000' in docker-compose.yml"
    fi
}

check_container_readonly() {
    local id="CHK-CONTAINER-READONLY"
    local container_id
    container_id=$(docker ps -q --filter "name=n8n" 2>/dev/null | head -1) || true
    if [[ -z "$container_id" ]]; then
        report_result "$id" "Container Security" "No n8n container running" "SKIP" "4.3"
        return
    fi
    local readonly_fs
    readonly_fs=$(docker inspect "$container_id" --format '{{.HostConfig.ReadonlyRootfs}}' 2>/dev/null) || true
    if [[ "$readonly_fs" == "true" ]]; then
        report_result "$id" "Container Security" "Container filesystem is read-only" "PASS" "4.3"
    else
        report_result "$id" "Container Security" "Container filesystem is writable" "WARN" "4.3" \
            "Set read_only: true in docker-compose.yml with tmpfs for write paths"
    fi
}

check_container_caps() {
    local id="CHK-CONTAINER-CAPS"
    local container_id
    container_id=$(docker ps -q --filter "name=n8n" 2>/dev/null | head -1) || true
    if [[ -z "$container_id" ]]; then
        report_result "$id" "Container Security" "No n8n container running" "SKIP" "4.3"
        return
    fi
    local cap_drop
    cap_drop=$(docker inspect "$container_id" --format '{{.HostConfig.CapDrop}}' 2>/dev/null) || true
    if echo "$cap_drop" | grep -qi "all"; then
        report_result "$id" "Container Security" "All capabilities dropped" "PASS" "4.3"
    else
        report_result "$id" "Container Security" "Capabilities not fully dropped" "WARN" "4.3" \
            "Set cap_drop: [ALL] in docker-compose.yml"
    fi
}

check_container_privileged() {
    local id="CHK-CONTAINER-PRIVILEGED"
    local container_id
    container_id=$(docker ps -q --filter "name=n8n" 2>/dev/null | head -1) || true
    if [[ -z "$container_id" ]]; then
        report_result "$id" "Container Security" "No n8n container running" "SKIP" "4.3"
        return
    fi
    local privileged
    privileged=$(docker inspect "$container_id" --format '{{.HostConfig.Privileged}}' 2>/dev/null) || true
    if [[ "$privileged" == "false" ]]; then
        report_result "$id" "Container Security" "Container is not privileged" "PASS" "4.3"
    else
        report_result "$id" "Container Security" "Container is running in privileged mode" "FAIL" "4.3" \
            "Remove privileged: true from docker-compose.yml immediately"
    fi
}

check_docker_socket() {
    local id="CHK-DOCKER-SOCKET"
    local container_id
    container_id=$(docker ps -q --filter "name=n8n" 2>/dev/null | head -1) || true
    if [[ -z "$container_id" ]]; then
        report_result "$id" "Container Security" "No n8n container running" "SKIP" "4.3"
        return
    fi
    local mounts
    mounts=$(docker inspect "$container_id" --format '{{json .Mounts}}' 2>/dev/null) || true
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
    container_id=$(docker ps -q --filter "name=n8n" 2>/dev/null | head -1) || true
    if [[ -z "$container_id" ]]; then
        report_result "$id" "Container Security" "No n8n container running" "SKIP" "4.3"
        return
    fi
    local env_vars
    env_vars=$(docker inspect "$container_id" --format '{{json .Config.Env}}' 2>/dev/null) || true
    if echo "$env_vars" | grep -qiE 'ENCRYPTION_KEY=|PASSWORD=|SECRET=|TOKEN=.*[a-zA-Z0-9]{8}|API_KEY='; then
        report_result "$id" "Container Security" "Secrets found in container environment" "WARN" "4.3" \
            "Use Docker secrets instead of environment variables — see §4.3"
    else
        report_result "$id" "Container Security" "No secrets in container environment" "PASS" "4.3"
    fi
}

check_colima_mounts() {
    local id="CHK-COLIMA-MOUNTS"
    local container_id
    container_id=$(docker ps -q --filter "name=n8n" 2>/dev/null | head -1) || true
    if [[ -z "$container_id" ]]; then
        report_result "$id" "Container Security" "No n8n container running" "SKIP" "4.3"
        return
    fi
    local mounts
    mounts=$(docker inspect "$container_id" --format '{{json .Mounts}}' 2>/dev/null) || true
    if echo "$mounts" | grep -qE '"/Users/|"/home/|"/root"'; then
        report_result "$id" "Container Security" "Home directory mounted in container" "WARN" "4.3" \
            "Remove home directory mount — use named volumes instead"
    else
        report_result "$id" "Container Security" "No home directory mounts" "PASS" "4.3"
    fi
}

check_container_network() {
    local id="CHK-CONTAINER-NETWORK"
    local container_id
    container_id=$(docker ps -q --filter "name=n8n" 2>/dev/null | head -1) || true
    if [[ -z "$container_id" ]]; then
        report_result "$id" "Container Security" "No n8n container running" "SKIP" "4.5"
        return
    fi
    local net_mode
    net_mode=$(docker inspect "$container_id" --format '{{.HostConfig.NetworkMode}}' 2>/dev/null) || true
    if [[ "$net_mode" == "host" ]]; then
        report_result "$id" "Container Security" "Container uses host network — no isolation" "FAIL" "4.5" \
            "Use bridge networking, not --network host — see §4.5"
    else
        report_result "$id" "Container Security" "Container network mode: ${net_mode}" "PASS" "4.5"
    fi
}

check_container_resources() {
    local id="CHK-CONTAINER-RESOURCES"
    local container_id
    container_id=$(docker ps -q --filter "name=n8n" 2>/dev/null | head -1) || true
    if [[ -z "$container_id" ]]; then
        report_result "$id" "Container Security" "No n8n container running" "SKIP" "4.3"
        return
    fi
    local mem_limit
    mem_limit=$(docker inspect "$container_id" --format '{{.HostConfig.Memory}}' 2>/dev/null) || true
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
        container_id=$(docker ps -q --filter "name=n8n" 2>/dev/null | head -1) || true
        if [[ -z "$container_id" ]]; then
            report_result "$id" "n8n Platform" "No n8n container running" "SKIP" "5.1"
            return
        fi
        local port_binding
        port_binding=$(docker port "$container_id" 5678 2>/dev/null) || true
        if echo "$port_binding" | grep -q "^127\.0\.0\.1:"; then
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
        if echo "$bind_addr" | grep -q "^127\.0\.0\.1:"; then
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
        container_id=$(docker ps -q --filter "name=n8n" 2>/dev/null | head -1) || true
        if [[ -n "$container_id" ]]; then
            docker inspect "$container_id" --format '{{json .Config.Env}}' 2>/dev/null
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
            "Use production webhook URLs, not test URLs — see §5.5"
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
                "Configure encrypted DNS via Quad9 DoH profile"
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
        "Install LuLu (free) or configure pf rules per §3.3"
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
    local id="CHK-LISTENERS-BASELINE"
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
            "Review: sudo lsof -iTCP -sTCP:LISTEN -P -n — bind services to 127.0.0.1"
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
        container_id=$(docker ps -q --filter "name=n8n" 2>/dev/null | head -1) || true
        if [[ -z "$container_id" ]]; then
            report_result "$id" "Data Security" "No n8n container running" "SKIP" "7.1"
            return
        fi
        local env_vars
        env_vars=$(docker inspect "$container_id" --format '{{json .Config.Env}}' 2>/dev/null) || true
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
    container_id=$(docker ps -q --filter "name=n8n" 2>/dev/null | head -1) || true
    if [[ -z "$container_id" ]]; then
        report_result "$id" "Data Security" "No n8n container running" "SKIP" "7.1"
        return
    fi
    # Check if docker inspect reveals actual secret values in environment
    local env_output
    env_output=$(docker inspect "$container_id" --format '{{json .Config.Env}}' 2>/dev/null) || true
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
            "Review: profiles list — verify all profiles are expected"
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
            "Install: brew install santa — see §8.1"
    fi
}

check_blockblock() {
    local id="CHK-BLOCKBLOCK"
    if pgrep -x BlockBlock &>/dev/null || pgrep -x "BlockBlock Helper" &>/dev/null; then
        report_result "$id" "IDS Tools" "BlockBlock is running" "PASS" "8.1"
    elif [[ -d "/Applications/BlockBlock Helper.app" ]] || [[ -d "/Library/Objective-See/BlockBlock" ]]; then
        report_result "$id" "IDS Tools" "BlockBlock installed but not running" "WARN" "8.1" \
            "Start BlockBlock from Applications"
    else
        report_result "$id" "IDS Tools" "BlockBlock not installed" "WARN" "8.1" \
            "Install from objective-see.org — see §8.1"
    fi
}

check_lulu() {
    local id="CHK-LULU"
    if pgrep -x LuLu &>/dev/null || pgrep -f "com.objective-see.lulu" &>/dev/null; then
        report_result "$id" "IDS Tools" "LuLu is running" "PASS" "8.1"
    elif [[ -d "/Applications/LuLu.app" ]] || [[ -d "/Library/Objective-See/LuLu" ]]; then
        report_result "$id" "IDS Tools" "LuLu installed but not running" "WARN" "8.1" \
            "Start LuLu from Applications or brew install --cask lulu"
    else
        report_result "$id" "IDS Tools" "LuLu not installed" "WARN" "8.1" \
            "Install: brew install --cask lulu — see §8.1"
    fi
}

check_clamav() {
    local id="CHK-CLAMAV"
    if command -v clamscan &>/dev/null; then
        report_result "$id" "IDS Tools" "ClamAV is installed" "PASS" "8.1"
    else
        report_result "$id" "IDS Tools" "ClamAV not installed" "WARN" "8.1" \
            "Install: brew install clamav — see §8.1"
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
    if [[ -f "$db_dir/main.cvd" ]] || [[ -f "$db_dir/main.cld" ]]; then
        local age_days
        age_days=$(( ( $(date +%s) - $(stat -f %m "$db_dir/main.c"*d 2>/dev/null | head -1) ) / 86400 )) 2>/dev/null || age_days=999
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
            "Create baseline after hardening — see §8.2"
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
            "Export workflows and create baseline — see §8.3"
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
            "Compare against expected services for your deployment path"
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
            "Create certificate trust store baseline — see §8.7"
    fi
}

check_icloud_keychain() {
    local id="CHK-ICLOUD-KEYCHAIN"
    # iCloud Keychain detection is limited from CLI; check for iCloud-related config
    if defaults read MobileMeAccounts 2>/dev/null | grep -q "KEYCHAIN_SYNC"; then
        report_result "$id" "Cloud Services" "iCloud Keychain sync may be enabled" "WARN" "8.6" \
            "Disable: System Settings > Apple ID > iCloud > Keychain > OFF"
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
            "Deploy canary files for independent compromise detection — see §8.5"
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
            "Configure Time Machine or automated backup — see §9.3"
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
    fmm_enabled=$(defaults read com.apple.icloud.findmymac FMMEnabled 2>/dev/null || echo "")

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
        # Setting may not exist on older macOS or if never configured
        local macos_major
        macos_major=$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)
        if [[ "${macos_major:-0}" -ge 14 ]]; then
            report_result "$id" "Physical" "USB accessory security policy not configured" "WARN" "9.5" \
                "Configure: System Settings > Privacy & Security > Allow accessories to connect"
        else
            report_result "$id" "Physical" "USB accessory security not available on this macOS version" "SKIP" "9.5"
        fi
    elif [[ "$policy" -le 2 ]]; then
        report_result "$id" "Physical" "USB accessory security is configured (policy: $policy)" "PASS" "9.5"
    else
        report_result "$id" "Physical" "USB accessory security is set to permissive (policy: $policy)" "WARN" "9.5" \
            "Restrict to 'Ask for new accessories' — see §9.5"
    fi
}

# --- §10 Operational Maintenance checks (T058) ---

check_launchd_audit_job() {
    local id="CHK-LAUNCHD-AUDIT-JOB"
    if launchctl list com.openclaw.audit &>/dev/null; then
        report_result "$id" "Infrastructure" "Audit launchd job is loaded" "PASS" "10.1"
    elif [[ -f /Library/LaunchDaemons/com.openclaw.audit.plist ]]; then
        report_result "$id" "Infrastructure" "Audit plist exists but job is not loaded" "FAIL" "10.1" \
            "Load: sudo launchctl bootstrap system /Library/LaunchDaemons/com.openclaw.audit.plist"
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
            "Create notification config at $conf — see §10.2"
    fi
}

check_log_dir() {
    local id="CHK-LOG-DIR"
    local log_dir="/opt/n8n/logs/audit"
    if [[ -d "$log_dir" && -w "$log_dir" ]]; then
        # Check if logs are being generated (most recent log not older than 2x weekly = 14 days)
        local latest
        latest=$(find "$log_dir" -name "audit-*.log" -mtime -14 2>/dev/null | head -1)
        if [[ -n "$latest" ]]; then
            report_result "$id" "Infrastructure" "Audit log directory exists with recent logs" "PASS" "10.4"
        else
            report_result "$id" "Infrastructure" "Audit log directory exists but no recent logs (>14 days)" "WARN" "10.4" \
                "Verify scheduled audit is running — see §10.1"
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
        if [[ $FAIL_COUNT -gt 0 ]]; then
            printf "  Action required: Fix %d FAIL item(s) (see referenced sections)\n" "$FAIL_COUNT"
        fi
        echo "================================================================"
    fi

    # Exit code: 1 if any FAIL, 0 otherwise
    if [[ $FAIL_COUNT -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
