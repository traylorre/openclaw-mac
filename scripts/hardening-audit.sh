#!/usr/bin/env bash
# macOS Hardening Audit Script for n8n + Apify Deployment
# See docs/HARDENING.md §11 for full reference
set -euo pipefail

readonly VERSION="0.1.0"
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME

# --- Color Setup ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Auto-disable colors when stdout is not a terminal
if [[ ! -t 1 ]]; then
    RED='' GREEN='' YELLOW='' CYAN='' BOLD='' NC=''
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
    if echo "$output" | grep -q "enabled"; then
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
    if echo "$output" | grep -q "enabled"; then
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
    if echo "$output" | grep -q "could not find service"; then
        report_result "$id" "Sharing Services" "File Sharing (SMB) is disabled" "PASS" "2.7"
    elif echo "$output" | grep -q "state = running"; then
        report_result "$id" "Sharing Services" "File Sharing (SMB) is running" "FAIL" "2.7" \
            "Disable: sudo launchctl disable system/com.apple.smbd"
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
            "Disable: sudo systemsetup -setremoteappleevents off"
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
    if echo "$output" | grep -q "could not find service"; then
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
                RED='' GREEN='' YELLOW='' CYAN='' BOLD='' NC=''
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

    # Additional check groups added by later tasks:
    # T032: Bare-Metal checks
    # T038: Data Security checks
    # T045: Detection and Monitoring checks
    # T050: Response and Recovery checks

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
