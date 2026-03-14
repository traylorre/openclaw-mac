#!/usr/bin/env bash
# OpenClaw Audit Cron — Unified scheduling wrapper
# Runs audit + notify + optional auto-fix in a single pipeline.
# Replaces separate com.openclaw.audit and com.openclaw.notify plists.
# See docs/HARDENING.md §10.1 for scheduling guide.
set -euo pipefail

readonly VERSION="0.1.0"
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME

# --- Color Setup ---
RED='\033[0;31m'
# shellcheck disable=SC2034
GREEN='\033[0;32m'
# shellcheck disable=SC2034
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

if [[ ! -t 1 ]]; then
    RED='' GREEN='' YELLOW='' CYAN='' NC=''
fi

# --- Defaults ---
LOG_DIR="/opt/n8n/logs/audit"
AUDIT_SCRIPT="/opt/n8n/scripts/hardening-audit.sh"
NOTIFY_SCRIPT="/opt/n8n/scripts/audit-notify.sh"
FIX_SCRIPT="/opt/n8n/scripts/hardening-fix.sh"
LOCK_DIR="${LOG_DIR}/.audit-cron.lock"
HEALTH_FILE="${LOG_DIR}/.last-run"
RETENTION_COUNT=30
MODE="audit-only"  # audit-only | auto-fix

# --- Usage ---
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Unified audit pipeline: run audit, send notifications, optional auto-fix.

Options:
  --audit-only    Run audit + notify only (default)
  --auto-fix      Run audit + auto-fix SAFE checks + re-audit + notify
  --retention N   Keep last N audit log pairs (default: 30)
  --log-dir DIR   Log directory (default: /opt/n8n/logs/audit)
  --no-color      Disable colored output
  --version       Show version and exit
  --help          Show this help message and exit

Exit Codes:
  0  Pipeline completed (audit may still have FAILs)
  1  Pipeline error (script missing, lock held)
  2  Script error (missing dependency, permission denied)

Designed for launchd scheduling. See docs/HARDENING.md §10.1.
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

# --- Lock Management (mkdir-based, POSIX-safe) ---
acquire_lock() {
    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        # Check if stale (PID file inside lock dir)
        local lock_pid
        lock_pid=$(cat "${LOCK_DIR}/pid" 2>/dev/null) || true
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            printf "${RED}ERROR${NC}: Another audit-cron is running (PID %s)\n" "$lock_pid" >&2
            exit 1
        fi
        # Stale lock — remove and retry
        rm -rf "$LOCK_DIR"
        if ! mkdir "$LOCK_DIR" 2>/dev/null; then
            printf "${RED}ERROR${NC}: Cannot acquire lock at %s\n" "$LOCK_DIR" >&2
            exit 1
        fi
    fi
    echo $$ > "${LOCK_DIR}/pid"
    # shellcheck disable=SC2064
    trap "rm -rf '${LOCK_DIR}'" EXIT
}

# --- Log Rotation ---
rotate_logs() {
    local count="$RETENTION_COUNT"
    # Keep only the last N JSON files (and their matching .log files)
    local json_files
    json_files=$(ls -t "${LOG_DIR}"/audit-*.json 2>/dev/null) || true
    if [[ -z "$json_files" ]]; then
        return
    fi

    local excess
    excess=$(echo "$json_files" | tail -n +"$((count + 1))")
    if [[ -z "$excess" ]]; then
        return
    fi

    while IFS= read -r json_file; do
        rm -f "$json_file"
        # Remove matching .log file
        local log_file="${json_file%.json}.log"
        rm -f "$log_file"
        # Remove matching post-fix files
        local base="${json_file%.json}"
        rm -f "${base}-post-fix.json" "${base}-post-fix.log"
    done <<< "$excess"
}

# --- Health Check ---
write_health() {
    local exit_code="$1"
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    printf '{"timestamp":"%s","exit_code":%d,"mode":"%s"}\n' \
        "$ts" "$exit_code" "$MODE" > "$HEALTH_FILE"
}

# --- Run Pipeline ---
run_pipeline() {
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local log_file="${LOG_DIR}/audit-${timestamp}.log"
    local json_file="${LOG_DIR}/audit-${timestamp}.json"

    mkdir -p "$LOG_DIR"

    local pipeline_errors=0

    # Step 1: Run audit (human-readable log)
    printf "${CYAN}[1/4]${NC} Running audit (text)...\n"
    if [[ -x "$AUDIT_SCRIPT" ]]; then
        "$AUDIT_SCRIPT" --no-color > "$log_file" 2>&1 || true
    else
        printf "  ${RED}SKIP${NC}  Audit script not found: %s\n" "$AUDIT_SCRIPT"
        pipeline_errors=$((pipeline_errors + 1))
    fi

    # Step 2: Run audit (JSON output)
    printf "${CYAN}[2/4]${NC} Running audit (JSON)...\n"
    if [[ -x "$AUDIT_SCRIPT" ]]; then
        "$AUDIT_SCRIPT" --json > "$json_file" 2>&1 || true
    else
        printf "  ${RED}SKIP${NC}  Audit script not found\n"
        pipeline_errors=$((pipeline_errors + 1))
    fi

    # Step 3: Optional auto-fix
    if [[ "$MODE" == "auto-fix" ]]; then
        printf "${CYAN}[3/4]${NC} Running auto-fix (SAFE checks only)...\n"
        if [[ -x "$FIX_SCRIPT" ]]; then
            local fix_json="${LOG_DIR}/fix-${timestamp}.json"
            "$FIX_SCRIPT" --auto --json --audit-file "$json_file" > "$fix_json" 2>&1 || true

            # Re-audit after fixes
            printf "  Re-auditing after fixes...\n"
            "$AUDIT_SCRIPT" --no-color > "${LOG_DIR}/audit-${timestamp}-post-fix.log" 2>&1 || true
            "$AUDIT_SCRIPT" --json > "${LOG_DIR}/audit-${timestamp}-post-fix.json" 2>&1 || true
        else
            printf "  ${RED}SKIP${NC}  Fix script not found: %s\n" "$FIX_SCRIPT"
            pipeline_errors=$((pipeline_errors + 1))
        fi
    else
        printf "${CYAN}[3/4]${NC} Auto-fix skipped (use --auto-fix to enable)\n"
    fi

    # Step 4: Notify
    printf "${CYAN}[4/4]${NC} Sending notifications...\n"
    if [[ -x "$NOTIFY_SCRIPT" ]]; then
        "$NOTIFY_SCRIPT" --log-dir "$LOG_DIR" 2>&1 || true
    else
        printf "  ${YELLOW}SKIP${NC}  Notify script not found: %s\n" "$NOTIFY_SCRIPT"
    fi

    # Step 5: Rotate old logs
    rotate_logs

    # Step 6: Write health check
    local audit_exit=0
    if [[ -f "$json_file" ]]; then
        local fails
        fails=$(jq -r '.summary.fail // 0' "$json_file" 2>/dev/null) || fails=0
        [[ "$fails" -gt 0 ]] && audit_exit=1
    fi
    write_health "$audit_exit"

    # Summary
    echo ""
    if [[ -f "$json_file" ]]; then
        local total pass fail warn
        total=$(jq -r '.summary.total // 0' "$json_file" 2>/dev/null) || total="?"
        pass=$(jq -r '.summary.pass // 0' "$json_file" 2>/dev/null) || pass="?"
        fail=$(jq -r '.summary.fail // 0' "$json_file" 2>/dev/null) || fail="?"
        warn=$(jq -r '.summary.warn // 0' "$json_file" 2>/dev/null) || warn="?"
        printf "Audit complete: %s PASS | %s FAIL | %s WARN (%s total)\n" "$pass" "$fail" "$warn" "$total"
    fi
    printf "Logs: %s\n" "$LOG_DIR/audit-${timestamp}.*"
    printf "Health: %s\n" "$HEALTH_FILE"

    if [[ $pipeline_errors -gt 0 ]]; then
        return 1
    fi
    return 0
}

# --- Main ---
main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --audit-only)  MODE="audit-only"; shift ;;
            --auto-fix)    MODE="auto-fix"; shift ;;
            --retention)   RETENTION_COUNT="$2"; shift 2 ;;
            --log-dir)     LOG_DIR="$2"; LOCK_DIR="${LOG_DIR}/.audit-cron.lock"; HEALTH_FILE="${LOG_DIR}/.last-run"; shift 2 ;;
            --no-color)    RED='' GREEN='' YELLOW='' CYAN='' NC=''; shift ;;
            --version)     echo "${SCRIPT_NAME} v${VERSION}"; exit 0 ;;
            --help)        usage; exit 0 ;;
            *)             echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
        esac
    done

    check_platform
    acquire_lock

    local rc=0
    run_pipeline || rc=$?

    exit "$rc"
}

main "$@"
