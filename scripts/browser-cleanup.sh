#!/usr/bin/env bash
# OpenClaw Browser Data Cleanup
# Removes session data (cookies, cache, history, local storage) from Chromium
# or Chrome profile directories. Safe to run after each automation session.
#
# Usage:
#   bash scripts/browser-cleanup.sh                  # auto-detect profile
#   bash scripts/browser-cleanup.sh --profile /path   # custom profile path
#   bash scripts/browser-cleanup.sh --dry-run         # show what would be removed
#
# Can also be sourced by hardening-fix.sh:
#   source scripts/browser-cleanup.sh
#   run_browser_cleanup [--profile /path] [--dry-run]
#
# See docs/HARDENING.md §2.11 and §7.11 for context.

set -euo pipefail

# --- Color Setup ---
_BC_RED='\033[0;31m'
_BC_GREEN='\033[0;32m'
_BC_YELLOW='\033[1;33m'
_BC_CYAN='\033[0;36m'
_BC_NC='\033[0m'

if [[ ! -t 1 ]]; then
    _BC_RED='' _BC_GREEN='' _BC_YELLOW='' _BC_CYAN='' _BC_NC=''
fi

# --- User Scope ---
_bc_run_as_user() {
    if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
        sudo -u "$SUDO_USER" "$@"
    else
        "$@"
    fi
}

# --- Detect Browser Profile ---
_bc_detect_profile() {
    local user_home
    if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
        user_home=$(eval echo "~${SUDO_USER}")
    else
        user_home="$HOME"
    fi

    # Prefer Chromium over Chrome
    local chromium_profile="${user_home}/Library/Application Support/Chromium/Default"
    local chrome_profile="${user_home}/Library/Application Support/Google/Chrome/Default"

    if [[ -d "$chromium_profile" ]]; then
        echo "$chromium_profile"
        return
    fi
    if [[ -d "$chrome_profile" ]]; then
        echo "$chrome_profile"
        return
    fi
    echo ""
}

# --- Detect Browser Type ---
_bc_detect_browser_type() {
    local profile="$1"
    if echo "$profile" | grep -qi "chromium"; then
        echo "Chromium"
    elif echo "$profile" | grep -qi "chrome"; then
        echo "Google Chrome"
    else
        echo "Unknown"
    fi
}

# --- Check if Browser is Running ---
_bc_is_browser_running() {
    if pgrep -f "Chromium" &>/dev/null || pgrep -f "Google Chrome" &>/dev/null; then
        return 0
    fi
    return 1
}

# --- Session Data Targets ---
# These are the files/directories that contain session artifacts.
# Bookmarks, Extensions, Preferences, and Managed Preferences are preserved.
_BC_CLEANUP_TARGETS=(
    "Cookies"
    "Cookies-journal"
    "Local Storage"
    "Session Storage"
    "History"
    "History-journal"
    "Cache"
    "Code Cache"
    "Service Worker"
    "GPUCache"
)

# --- Main Cleanup Function ---
# This is the entry point when sourced by hardening-fix.sh
run_browser_cleanup() {
    local profile_path=""
    local dry_run=false
    local cleaned=0
    local skipped=0

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --profile) profile_path="$2"; shift 2 ;;
            --dry-run) dry_run=true; shift ;;
            --help)
                echo "Usage: browser-cleanup.sh [--profile PATH] [--dry-run]"
                echo ""
                echo "Removes browser session data (cookies, cache, history, local storage)."
                echo "Preserves bookmarks, extensions, and preferences."
                echo ""
                echo "Options:"
                echo "  --profile PATH  Use a specific profile directory"
                echo "  --dry-run       Show what would be removed without deleting"
                return 0
                ;;
            *) echo "Unknown option: $1" >&2; return 2 ;;
        esac
    done

    # Auto-detect profile if not specified
    if [[ -z "$profile_path" ]]; then
        profile_path=$(_bc_detect_profile)
    fi

    if [[ -z "$profile_path" ]]; then
        printf "  ${_BC_YELLOW}SKIP${_BC_NC}  No Chromium or Chrome profile directory found\n"
        return 0
    fi

    if [[ ! -d "$profile_path" ]]; then
        printf "  ${_BC_YELLOW}SKIP${_BC_NC}  Profile directory does not exist: %s\n" "$profile_path"
        return 0
    fi

    local browser_type
    browser_type=$(_bc_detect_browser_type "$profile_path")

    # Safety: refuse to run if browser is active
    if _bc_is_browser_running; then
        printf "  ${_BC_RED}ABORT${_BC_NC}  %s is running — close the browser before cleanup\n" "$browser_type"
        return 1
    fi

    if ! $dry_run; then
        printf "  ${_BC_CYAN}CLEAN${_BC_NC}  %s profile: %s\n" "$browser_type" "$profile_path"
    else
        printf "  ${_BC_CYAN}DRY-RUN${_BC_NC}  %s profile: %s\n" "$browser_type" "$profile_path"
    fi

    # Remove each target
    for target in "${_BC_CLEANUP_TARGETS[@]}"; do
        local target_path="${profile_path}/${target}"
        if [[ -e "$target_path" ]]; then
            if $dry_run; then
                printf "    Would remove: %s\n" "$target"
            else
                _bc_run_as_user rm -rf "$target_path"
                printf "    ${_BC_GREEN}Removed${_BC_NC}: %s\n" "$target"
            fi
            cleaned=$((cleaned + 1))
        else
            skipped=$((skipped + 1))
        fi
    done

    if $dry_run; then
        printf "  ${_BC_CYAN}DRY-RUN${_BC_NC}  Would remove %d items (%d not present)\n" "$cleaned" "$skipped"
    elif [[ $cleaned -gt 0 ]]; then
        printf "  ${_BC_GREEN}DONE${_BC_NC}  Removed %d session data items (%d not present)\n" "$cleaned" "$skipped"
    else
        printf "  ${_BC_YELLOW}SKIP${_BC_NC}  No session data found to clean\n"
    fi

    return 0
}

# --- Standalone Entry Point ---
# Only run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_browser_cleanup "$@"
fi
