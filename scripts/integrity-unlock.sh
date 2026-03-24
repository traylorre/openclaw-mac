#!/usr/bin/env bash
# integrity-unlock.sh — Unlock a specific protected file for editing
# Constitution VI: set -euo pipefail, shellcheck clean, idempotent, colored output
# FR-002: Explicit unlock command requiring elevated privileges
# FR-023: Record unlock in lock state for alert suppression (per-file, 5-min timeout)
# Must be run with sudo (chflags nouchg requires root)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/integrity.sh
source "${SCRIPT_DIR}/lib/integrity.sh"

REPO_ROOT="$(resolve_repo_root "$SCRIPT_DIR")"
readonly REPO_ROOT

usage() {
    cat <<'USAGE'
Usage: sudo scripts/integrity-unlock.sh --file <path>

Unlock a specific protected file for editing. Records the unlock in
the lock state file so the monitoring service suppresses alerts for
this file during the grace period (default: 5 minutes).

After editing, run 'sudo make integrity-lock' to re-lock all files
and update the manifest.

Options:
  --file <path>   Absolute path to the file to unlock (required)
  --debug         Verbose output
USAGE
}

main() {
    local target_file=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file) target_file="$2"; shift 2 ;;
            --debug) DEBUG=true; export DEBUG; shift ;;
            --help|-h) usage; exit 0 ;;
            *) log_error "Unknown: $1"; usage; exit 1 ;;
        esac
    done

    if [[ -z "$target_file" ]]; then
        log_error "No file specified. Usage: sudo make integrity-unlock FILE=<path>"
        exit 1
    fi

    # Verify running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run with sudo"
        exit 1
    fi

    # Verify file exists
    if [[ ! -f "$target_file" ]]; then
        log_error "File not found: ${target_file}"
        exit 1
    fi

    # Verify file is in the protected list
    local found=false
    while IFS= read -r f; do
        if [[ "$f" == "$target_file" ]]; then
            found=true
            break
        fi
    done < <(integrity_list_protected_files "$REPO_ROOT")

    if ! $found; then
        log_error "File is not in the protected file list: ${target_file}"
        log_error "Only protected files can be unlocked via this command"
        exit 1
    fi

    # Clear user immutable flag
    if chflags nouchg "$target_file" 2>/dev/null; then
        log_info "Unlocked: ${target_file}"
    else
        log_warn "File was not locked (flag not set): ${target_file}"
    fi

    # Record unlock for alert suppression (FR-023)
    # Run as real user (not root) for correct file ownership
    local real_user="${SUDO_USER:-$(whoami)}"
    sudo -u "$real_user" bash -c "
        source '${SCRIPT_DIR}/lib/integrity.sh'
        integrity_record_unlock '${target_file}'
    "

    log_info "Grace period: ${INTEGRITY_GRACE_MINUTES} minutes (monitoring alerts suppressed for this file)"
    log_info "After editing, run: sudo make integrity-lock"
}

main "$@"
