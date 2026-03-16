#!/usr/bin/env bash
# OpenClaw Audit Notification Script
# Parses the latest audit JSON and sends FAIL-only alerts.
# See docs/HARDENING.md §10.2 for configuration guide.

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
# shellcheck disable=SC2034
YELLOW='\033[1;33m'
# shellcheck disable=SC2034
CYAN='\033[0;36m'
NC='\033[0m'

if [[ ! -t 1 ]]; then
    RED='' GREEN='' YELLOW='' CYAN='' NC=''
fi

# --- Defaults ---
LOG_DIR="/opt/n8n/logs/audit"
CONF_FILE="/opt/n8n/etc/notify.conf"
NOTIFY_EMAIL_ENABLED=false
NOTIFY_EMAIL_TO=""
NOTIFY_EMAIL_FROM="openclaw-audit@localhost"
NOTIFY_OSASCRIPT_ENABLED=true
NOTIFY_WEBHOOK_ENABLED=false
NOTIFY_WEBHOOK_URL=""
NOTIFY_WARN_THRESHOLD=10

# --- Usage ---
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Parse latest audit JSON and send FAIL-only notifications.

Options:
  --conf FILE    Path to notify.conf (default: /opt/n8n/etc/notify.conf)
  --log-dir DIR  Path to audit log directory (default: /opt/n8n/logs/audit)
  --no-color     Disable colored output
  --debug        Enable bash trace output (set -x)
  --version      Show version and exit
  --help         Show this help message and exit

Exit Codes:
  0  Success (includes "no FAILs, nothing to send")
  1  Notification dispatch failure
  2  Script error (missing config, missing jq, no JSON file)

See docs/HARDENING.md §10.2 for full documentation.
EOF
}

# --- Platform Check ---
check_platform() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        echo "Error: This script requires macOS." >&2
        exit 2
    fi
    if ! command -v jq &>/dev/null; then
        echo "Error: jq is required. Install with: brew install jq" >&2
        exit 2
    fi
}

# --- Logging ---
log_notify() {
    local notify_log="${LOG_DIR}/notify.log"
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    printf "[%s] %s\n" "$ts" "$*" >> "$notify_log" 2>/dev/null || true
}

# --- Load Configuration ---
load_config() {
    if [[ ! -f "$CONF_FILE" ]]; then
        echo "Warning: Config file not found: ${CONF_FILE}" >&2
        echo "Using defaults (osascript only). See docs/HARDENING.md §10.2." >&2
        return
    fi

    # Validate permissions (must be 600 — config is sourced as shell code)
    local perms
    perms=$(stat -f '%Lp' "$CONF_FILE" 2>/dev/null || stat -c '%a' "$CONF_FILE" 2>/dev/null || echo "")
    if [[ -n "$perms" && "$perms" != "600" ]]; then
        echo "Error: ${CONF_FILE} has permissions ${perms} (must be 600). Refusing to source." >&2
        echo "Fix: sudo chmod 600 ${CONF_FILE}" >&2
        exit 2
    fi

    # Source config (key=value pairs)
    # shellcheck source=/dev/null
    source "$CONF_FILE"
}

# --- Find Latest Audit JSON ---
find_latest_json() {
    local latest
    latest=$(ls -t "${LOG_DIR}"/audit-*.json 2>/dev/null | head -1)
    if [[ -z "$latest" || ! -f "$latest" ]]; then
        echo "Error: No audit JSON files found in ${LOG_DIR}/" >&2
        exit 2
    fi

    # Validate it's parseable JSON
    if ! jq empty "$latest" 2>/dev/null; then
        echo "Error: Invalid JSON in ${latest}" >&2
        exit 2
    fi

    echo "$latest"
}

# --- Parse Audit JSON ---
# Sets global vars: FAIL_COUNT, WARN_COUNT, PASS_COUNT, TOTAL, FAIL_DETAILS, AUDIT_TIMESTAMP
parse_audit_json() {
    local json_file="$1"

    FAIL_COUNT=$(jq -r '.summary.fail // 0' "$json_file")
    WARN_COUNT=$(jq -r '.summary.warn // 0' "$json_file")
    PASS_COUNT=$(jq -r '.summary.pass // 0' "$json_file")
    TOTAL=$(jq -r '.summary.total // 0' "$json_file")
    AUDIT_TIMESTAMP=$(jq -r '.timestamp // "unknown"' "$json_file")

    FAIL_DETAILS=""
    if [[ "$FAIL_COUNT" -gt 0 ]]; then
        FAIL_DETAILS=$(jq -r '
            .results[]
            | select(.status == "FAIL")
            | "  - \(.id): \(.description) (\(.guide_ref // "N/A"))\n    Fix: \(.remediation // "See hardening guide")"
        ' "$json_file")
    fi
}

# --- Build Notification Body ---
build_notification_body() {
    local body=""
    body+="OpenClaw Security Audit — ${FAIL_COUNT} FAIL(s) detected"
    body+=$'\n'
    body+="Timestamp: ${AUDIT_TIMESTAMP}"
    body+=$'\n'
    body+="Summary: ${PASS_COUNT} PASS | ${FAIL_COUNT} FAIL | ${WARN_COUNT} WARN (${TOTAL} total)"
    body+=$'\n\n'
    body+="Failed checks:"
    body+=$'\n'
    body+="${FAIL_DETAILS}"
    body+=$'\n\n'
    body+="Run 'hardening-audit.sh' for full results."
    body+=$'\n'
    body+="Run 'hardening-fix.sh --interactive' to remediate."
    echo "$body"
}

# --- Build Short Summary (for osascript, max ~200 chars) ---
build_short_summary() {
    echo "${FAIL_COUNT} security check(s) FAILED. Run audit for details."
}

# --- Send Email ---
send_email() {
    local subject="$1"
    local body="$2"

    if ! command -v msmtp &>/dev/null; then
        log_notify "ERROR: email enabled but msmtp not found"
        printf "  ${RED}FAIL${NC}  Email: msmtp not installed (brew install msmtp)\n"
        return 1
    fi

    local from="${NOTIFY_EMAIL_FROM}"
    local to="${NOTIFY_EMAIL_TO}"

    if [[ -z "$to" ]]; then
        log_notify "ERROR: NOTIFY_EMAIL_TO is empty"
        printf "  ${RED}FAIL${NC}  Email: NOTIFY_EMAIL_TO not configured\n"
        return 1
    fi

    local rc=0
    printf "From: %s\nTo: %s\nSubject: %s\n\n%s" \
        "$from" "$to" "$subject" "$body" \
        | msmtp -a default "$to" 2>/dev/null || rc=$?

    if [[ $rc -eq 0 ]]; then
        log_notify "OK: email sent to ${to}"
        printf "  ${GREEN}SENT${NC}  Email → %s\n" "$to"
    else
        log_notify "ERROR: email dispatch failed to ${to}"
        printf "  ${RED}FAIL${NC}  Email → %s\n" "$to"
        return 1
    fi
}

# --- Send macOS Notification ---
send_osascript() {
    local message="$1"

    # Escape backslashes and double quotes for AppleScript string interpolation
    local escaped_message="${message//\\/\\\\}"
    escaped_message="${escaped_message//\"/\\\"}"

    local rc=0
    osascript -e "display notification \"${escaped_message}\" with title \"OpenClaw Security Audit\" subtitle \"Action Required\"" 2>/dev/null || rc=$?

    if [[ $rc -eq 0 ]]; then
        log_notify "OK: osascript notification sent"
        printf "  ${GREEN}SENT${NC}  macOS Notification Center\n"
    else
        log_notify "ERROR: osascript notification failed"
        printf "  ${RED}FAIL${NC}  macOS Notification Center\n"
        return 1
    fi
}

# --- Send Webhook ---
send_webhook() {
    local subject="$1"
    local body="$2"

    if [[ -z "$NOTIFY_WEBHOOK_URL" ]]; then
        log_notify "ERROR: NOTIFY_WEBHOOK_URL is empty"
        printf "  ${RED}FAIL${NC}  Webhook: URL not configured\n"
        return 1
    fi

    # Build JSON payload safely with jq
    local payload
    payload=$(jq -n \
        --arg title "$subject" \
        --arg text "$body" \
        --argjson fail_count "$FAIL_COUNT" \
        --argjson warn_count "$WARN_COUNT" \
        --arg timestamp "$AUDIT_TIMESTAMP" \
        '{
            title: $title,
            text: $text,
            fail_count: $fail_count,
            warn_count: $warn_count,
            timestamp: $timestamp
        }')

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$NOTIFY_WEBHOOK_URL" 2>/dev/null) || http_code="000"

    if [[ "$http_code" =~ ^2 ]]; then
        log_notify "OK: webhook sent (HTTP ${http_code})"
        printf "  ${GREEN}SENT${NC}  Webhook → %s (HTTP %s)\n" "$NOTIFY_WEBHOOK_URL" "$http_code"
    else
        log_notify "ERROR: webhook failed (HTTP ${http_code})"
        printf "  ${RED}FAIL${NC}  Webhook → %s (HTTP %s)\n" "$NOTIFY_WEBHOOK_URL" "$http_code"
        return 1
    fi
}

# --- Main ---
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --conf)    CONF_FILE="$2"; shift 2 ;;
            --log-dir) LOG_DIR="$2"; shift 2 ;;
            --no-color) RED='' GREEN='' YELLOW='' CYAN='' NC=''; shift ;;
            --debug)   DEBUG=true; shift ;;
            --version) echo "${SCRIPT_NAME} v${VERSION}"; exit 0 ;;
            --help)    usage; exit 0 ;;
            *)         echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
        esac
    done

    if [[ "${DEBUG:-false}" == true ]]; then set -x; fi

    check_platform
    load_config

    # Find and parse latest audit JSON
    local json_file
    json_file=$(find_latest_json)
    parse_audit_json "$json_file"

    log_notify "Checking audit results from ${json_file}"

    # Exit silently if no FAILs and WARN count is below threshold
    if [[ "$FAIL_COUNT" -eq 0 ]]; then
        if [[ "$WARN_COUNT" -gt "$NOTIFY_WARN_THRESHOLD" ]]; then
            log_notify "No FAILs but ${WARN_COUNT} WARN(s) exceeds threshold (${NOTIFY_WARN_THRESHOLD}) — dispatching notifications"
        else
            log_notify "No FAIL results — no notification needed"
            exit 0
        fi
    else
        log_notify "${FAIL_COUNT} FAIL(s) detected — dispatching notifications"
    fi

    local subject body short_msg
    if [[ "$FAIL_COUNT" -gt 0 ]]; then
        subject="[OpenClaw] Security Audit: ${FAIL_COUNT} FAIL(s)"
        body=$(build_notification_body)
        short_msg=$(build_short_summary)
    else
        subject="[OpenClaw] Security Audit: ${WARN_COUNT} WARN(s) exceed threshold"
        body="OpenClaw Security Audit — ${WARN_COUNT} WARN(s) exceed threshold (${NOTIFY_WARN_THRESHOLD})"
        body+=$'\n'
        body+="Timestamp: ${AUDIT_TIMESTAMP}"
        body+=$'\n'
        body+="Summary: ${PASS_COUNT} PASS | ${FAIL_COUNT} FAIL | ${WARN_COUNT} WARN (${TOTAL} total)"
        body+=$'\n\n'
        body+="Run 'hardening-audit.sh' for full results."
        short_msg="${WARN_COUNT} WARN(s) exceed threshold (${NOTIFY_WARN_THRESHOLD}). Run audit for details."
    fi

    local dispatch_errors=0

    # Dispatch to each enabled method
    if [[ "$NOTIFY_EMAIL_ENABLED" == "true" ]]; then
        send_email "$subject" "$body" || dispatch_errors=$((dispatch_errors + 1))
    fi

    if [[ "$NOTIFY_OSASCRIPT_ENABLED" == "true" ]]; then
        send_osascript "$short_msg" || dispatch_errors=$((dispatch_errors + 1))
    fi

    if [[ "$NOTIFY_WEBHOOK_ENABLED" == "true" ]]; then
        send_webhook "$subject" "$body" || dispatch_errors=$((dispatch_errors + 1))
    fi

    # Summary
    if [[ $dispatch_errors -gt 0 ]]; then
        log_notify "Completed with ${dispatch_errors} dispatch error(s)"
        exit 1
    fi

    log_notify "All notifications dispatched successfully"
    exit 0
}

main "$@"
