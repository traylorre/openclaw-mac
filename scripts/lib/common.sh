#!/usr/bin/env bash
# common.sh — Shared library for openclaw-mac scripts
# Source this file, do not execute it directly.
# Usage: source "${SCRIPT_DIR}/lib/common.sh"

# --- Color Setup ---
if [[ -t 1 ]]; then
    readonly CLR_GREEN='\033[0;32m'
    readonly CLR_YELLOW='\033[1;33m'
    readonly CLR_RED='\033[0;31m'
    readonly CLR_BLUE='\033[0;34m'
    readonly CLR_DIM='\033[2m'
    readonly CLR_NC='\033[0m'
else
    readonly CLR_GREEN='' CLR_YELLOW='' CLR_RED='' CLR_BLUE='' CLR_DIM='' CLR_NC=''
fi

# --- Logging ---
log_info()  { printf "${CLR_GREEN}[INFO]${CLR_NC}  %s\n" "$1"; }
log_warn()  { printf "${CLR_YELLOW}[WARN]${CLR_NC}  %s\n" "$1"; }
log_error() { printf "${CLR_RED}[ERROR]${CLR_NC} %s\n" "$1" >&2; }
log_step()  { printf "${CLR_BLUE}[STEP]${CLR_NC}  %s\n" "$1"; }
log_debug() { if [[ "${DEBUG:-false}" == "true" ]]; then printf "${CLR_DIM}[DEBUG]${CLR_NC} %s\n" "$1"; fi; }

# --- Path Resolution ---
# Resolve the repo root from any script location
resolve_repo_root() {
    local script_dir="$1"
    local dir="$script_dir"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "${dir}/Makefile" && -d "${dir}/scripts" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    log_error "Could not find repo root from ${script_dir}"
    return 1
}

# --- sudo / User Detection ---
# Get the real user's home directory, even under sudo
resolve_user_home() {
    if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
        # Use dscl (macOS directory service) instead of eval to avoid shell injection
        dscl . -read "/Users/${SUDO_USER}" NFSHomeDirectory 2>/dev/null | awk '{print $2}'
    else
        echo "$HOME"
    fi
}

# Run a command as the real user (not root) when under sudo
run_as_real_user() {
    if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
        sudo -u "$SUDO_USER" "$@"
    else
        "$@"
    fi
}

# Refuse to run under sudo (for user-space scripts)
refuse_sudo() {
    if [[ $EUID -eq 0 ]]; then
        log_error "This script must NOT be run with sudo (it operates on user-space files)."
        log_error "Run as your normal user: bash $0"
        exit 1
    fi
}

# --- Prerequisite Checks ---
require_command() {
    local cmd="$1"
    local install_hint="${2:-}"
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Required command not found: ${cmd}"
        if [[ -n "$install_hint" ]]; then
            log_error "Install with: ${install_hint}"
        fi
        return 1
    fi
    log_debug "Found: ${cmd} at $(command -v "$cmd")"
    return 0
}
