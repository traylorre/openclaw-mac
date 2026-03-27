#!/usr/bin/env bash
# integrity-lock.sh — Set immutable flags on all protected files
# Constitution VI: set -euo pipefail, shellcheck clean, idempotent, colored output
# FR-001: Set uchg flags preventing non-root modification
# FR-003: Re-lock files, update checksums, re-sign manifest
# FR-005: Verify no symlinks before locking
# Must be run with sudo (chflags uchg requires root)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/integrity.sh disable=SC1091
source "${SCRIPT_DIR}/lib/integrity.sh"

REPO_ROOT="$(resolve_repo_root "$SCRIPT_DIR")"
readonly REPO_ROOT

main() {
    log_step "Integrity Lock — Setting immutable flags on protected files"

    # Verify running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run with sudo (chflags uchg requires root)"
        exit 1
    fi

    # FR-005: Symlink check before locking
    if ! integrity_check_symlinks "$REPO_ROOT"; then
        log_error "Symlinks detected — refusing to lock. Remove symlinks first."
        exit 1
    fi

    local locked=0
    local skipped=0
    local errors=0

    while IFS= read -r f; do
        if [[ ! -f "$f" ]]; then
            log_warn "File not found (skipping): ${f}"
            skipped=$((skipped + 1))
            continue
        fi

        # Set user immutable flag (uchg) — prevents non-root modification
        if chflags uchg "$f" 2>/dev/null; then
            locked=$((locked + 1))
            log_debug "Locked: ${f}"
        else
            log_error "Failed to lock: ${f}"
            errors=$((errors + 1))
        fi
    done < <(integrity_list_protected_files "$REPO_ROOT")

    # Clear lock state (all files are now locked, no grace periods active)
    integrity_clear_lockstate

    # Re-build and sign manifest with updated lock states and checksums
    log_step "Updating signed manifest"
    local manifest
    manifest=$(integrity_build_manifest "$REPO_ROOT")
    echo "$manifest" > "$INTEGRITY_MANIFEST"
    chmod 600 "$INTEGRITY_MANIFEST"

    # Fix ownership — script runs as root but these files must be user-writable
    # (monitoring LaunchAgent and unlock both run as the real user)
    local real_user="${SUDO_USER:-$(whoami)}"
    if [[ "$real_user" != "root" ]]; then
        chown "$real_user" "$INTEGRITY_MANIFEST" "$INTEGRITY_LOCKSTATE" "$INTEGRITY_AUDIT_LOG" 2>/dev/null || true
    fi

    local file_count
    file_count=$(echo "$manifest" | jq '.files | length')

    log_info "Locked ${locked} files (${skipped} skipped, ${errors} errors)"
    log_info "Manifest updated: ${file_count} checksums, signature refreshed"

    if [[ $errors -gt 0 ]]; then
        log_error "Some files could not be locked — review errors above"
        exit 1
    fi
}

main "$@"
