#!/usr/bin/env bash
# integrity-monitor.sh — Continuous filesystem monitoring for protected files
# Constitution VI: set -euo pipefail, shellcheck clean, idempotent, colored output
# FR-022: Alert operator on unauthorized file changes
# FR-023: Suppress alerts during unlock grace periods
# FR-024: Write heartbeat every 30 seconds
# FR-025: Re-verify checksums on file change events
#
# Usage:
#   scripts/integrity-monitor.sh               # run monitor (foreground)
#   scripts/integrity-monitor.sh --install      # install LaunchAgent
#   scripts/integrity-monitor.sh --uninstall    # remove LaunchAgent
#   scripts/integrity-monitor.sh --status       # check service status
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/integrity.sh
source "${SCRIPT_DIR}/lib/integrity.sh"

REPO_ROOT="$(resolve_repo_root "$SCRIPT_DIR")"
readonly REPO_ROOT
readonly PLIST_NAME="com.openclaw.integrity-monitor"
readonly PLIST_SRC="${SCRIPT_DIR}/templates/${PLIST_NAME}.plist"
readonly PLIST_DST="${HOME}/Library/LaunchAgents/${PLIST_NAME}.plist"
readonly LOG_DIR="${HOME}/.openclaw/logs"
readonly HEARTBEAT_INTERVAL=30

# --- Install/Uninstall LaunchAgent ---

do_install() {
    log_step "Installing integrity monitor LaunchAgent"

    if [[ ! -f "$PLIST_SRC" ]]; then
        log_error "Plist template not found: ${PLIST_SRC}"
        exit 1
    fi

    # Create log directory
    mkdir -p "$LOG_DIR"

    # Expand template variables and install
    sed -e "s|__SCRIPT_PATH__|${SCRIPT_DIR}/integrity-monitor.sh|g" \
        -e "s|__REPO_ROOT__|${REPO_ROOT}|g" \
        -e "s|__LOG_DIR__|${LOG_DIR}|g" \
        "$PLIST_SRC" > "$PLIST_DST"

    # Load the agent
    if launchctl list | grep -q "$PLIST_NAME"; then
        launchctl unload "$PLIST_DST" 2>/dev/null || true
    fi
    launchctl load "$PLIST_DST"

    log_info "LaunchAgent installed and loaded: ${PLIST_NAME}"
    log_info "Logs: ${LOG_DIR}/integrity-monitor.{out,err}.log"
}

do_uninstall() {
    log_step "Removing integrity monitor LaunchAgent"

    if launchctl list | grep -q "$PLIST_NAME"; then
        launchctl unload "$PLIST_DST" 2>/dev/null || true
        log_info "LaunchAgent unloaded"
    fi

    if [[ -f "$PLIST_DST" ]]; then
        rm -f "$PLIST_DST"
        log_info "Plist removed: ${PLIST_DST}"
    else
        log_warn "Plist not found (already removed?)"
    fi

    # Clean up heartbeat
    rm -f "$INTEGRITY_HEARTBEAT"
    log_info "Heartbeat file removed"
}

do_status() {
    log_step "Integrity monitor status"

    # Check LaunchAgent loaded
    if launchctl list | grep -q "$PLIST_NAME"; then
        local pid
        pid=$(launchctl list | grep "$PLIST_NAME" | awk '{print $1}')
        log_info "LaunchAgent loaded (PID: ${pid:-unknown})"
    else
        log_warn "LaunchAgent not loaded"
    fi

    # Check heartbeat
    if [[ -f "$INTEGRITY_HEARTBEAT" ]]; then
        local ts pid files
        ts=$(jq -r '.timestamp' "$INTEGRITY_HEARTBEAT" 2>/dev/null)
        pid=$(jq -r '.pid' "$INTEGRITY_HEARTBEAT" 2>/dev/null)
        files=$(jq -r '.files_watched' "$INTEGRITY_HEARTBEAT" 2>/dev/null)

        if integrity_check_heartbeat 120; then
            log_info "Heartbeat: ${ts} (PID ${pid}, watching ${files} files)"
        else
            log_warn "Heartbeat stale: ${ts} (PID ${pid}) — service may be down"
        fi
    else
        log_warn "No heartbeat file found"
    fi
}

# --- Alert Delivery ---

send_alert() {
    local file="$1"
    local expected="$2"
    local actual="$3"

    local message="INTEGRITY ALERT: ${file} modified without authorization"
    message+=" (expected ${expected:0:12}..., got ${actual:0:12}...)"

    log_error "$message"

    # Try to deliver alert via OpenClaw inbound hook
    local hook_url="http://localhost:5678/webhook/integrity-alert"
    local payload
    payload=$(jq -n \
        --arg file "$file" \
        --arg expected "$expected" \
        --arg actual "$actual" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{event: "integrity_violation", file: $file, expected_hash: $expected, actual_hash: $actual, timestamp: $ts}')

    # Non-blocking — don't let alert delivery failure crash the monitor
    curl -s -X POST "$hook_url" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        --max-time 5 >/dev/null 2>&1 || \
        log_warn "Could not deliver alert to n8n webhook (is n8n running?)"
}

# --- File Change Handler ---

handle_change() {
    local changed_file="$1"

    log_debug "Change detected: ${changed_file}"

    # Check if file is in grace period (FR-023)
    if integrity_is_in_grace_period "$changed_file"; then
        log_debug "File in grace period (unlock active), suppressing alert: ${changed_file}"
        return
    fi

    # Verify against manifest
    if [[ ! -f "$INTEGRITY_MANIFEST" ]]; then
        log_warn "No manifest — cannot verify change"
        return
    fi

    local expected_hash
    expected_hash=$(jq -r --arg p "$changed_file" \
        '.files[] | select(.path == $p) | .sha256 // empty' \
        "$INTEGRITY_MANIFEST" 2>/dev/null)

    if [[ -z "$expected_hash" ]]; then
        log_debug "Changed file not in manifest (ignoring): ${changed_file}"
        return
    fi

    if [[ ! -f "$changed_file" ]]; then
        send_alert "$changed_file" "$expected_hash" "FILE_DELETED"
        return
    fi

    local actual_hash
    actual_hash=$(integrity_compute_sha256 "$changed_file")

    if [[ "$expected_hash" != "$actual_hash" ]]; then
        send_alert "$changed_file" "$expected_hash" "$actual_hash"
    fi
}

# --- Main Monitor Loop ---

run_monitor() {
    log_step "Integrity Monitor — starting"

    # Verify fswatch is installed
    if ! command -v fswatch &>/dev/null; then
        log_error "fswatch not found. Install with: brew install fswatch"
        exit 1
    fi

    if [[ ! -f "$INTEGRITY_MANIFEST" ]]; then
        log_error "No manifest found. Run 'make integrity-deploy' first."
        exit 1
    fi

    # Build watch list from manifest
    local watch_files=()
    while IFS= read -r path; do
        if [[ -e "$path" || -L "$path" ]]; then
            watch_files+=("$path")
        fi
    done < <(jq -r '.files[].path' "$INTEGRITY_MANIFEST" 2>/dev/null)

    local file_count=${#watch_files[@]}
    log_info "Watching ${file_count} protected files"

    # Write initial heartbeat
    integrity_write_heartbeat "$file_count"

    # Start heartbeat in background
    (
        while true; do
            sleep "$HEARTBEAT_INTERVAL"
            integrity_write_heartbeat "$file_count"
        done
    ) &
    local heartbeat_pid=$!
    # shellcheck disable=SC2064
    trap "kill ${heartbeat_pid} 2>/dev/null; exit" INT TERM EXIT

    # Start fswatch — FSEvents backend, 1s latency
    fswatch --latency 1 --event-flags "${watch_files[@]}" | while IFS= read -r event_line; do
        # fswatch output: /path/to/file flags
        local changed_file
        changed_file=$(echo "$event_line" | awk '{print $1}')

        if [[ -n "$changed_file" ]]; then
            handle_change "$changed_file"
        fi
    done
}

main() {
    case "${1:-}" in
        --install)   do_install ;;
        --uninstall) do_uninstall ;;
        --status)    do_status ;;
        --help|-h)
            echo "Usage: scripts/integrity-monitor.sh [--install|--uninstall|--status]"
            echo "  (no args)     Run monitor in foreground"
            echo "  --install     Install and start LaunchAgent"
            echo "  --uninstall   Stop and remove LaunchAgent"
            echo "  --status      Check service status and heartbeat"
            ;;
        "")          run_monitor ;;
        *)           log_error "Unknown: $1"; exit 1 ;;
    esac
}

main "$@"
