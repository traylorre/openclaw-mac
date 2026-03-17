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

# --- Browser Registry ---
_BC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=browser-registry.sh
source "${_BC_SCRIPT_DIR}/browser-registry.sh"

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

# --- Clean One Browser Profile ---
_bc_clean_profile() {
    local browser="$1"
    local profile_path="$2"
    local dry_run="$3"
    local name="${BROWSER_NAME[$browser]}"
    local cleaned=0
    local skipped=0

    if [[ ! -d "$profile_path" ]]; then
        printf "  ${_BC_YELLOW}SKIP${_BC_NC}  [%s] Profile directory does not exist: %s\n" "$name" "$profile_path"
        return 0
    fi

    # Safety: refuse to run if this browser is active
    if is_browser_running "$browser"; then
        printf "  ${_BC_RED}ABORT${_BC_NC}  %s is running — close the browser before cleanup\n" "$name"
        return 1
    fi

    if ! $dry_run; then
        printf "  ${_BC_CYAN}CLEAN${_BC_NC}  %s profile: %s\n" "$name" "$profile_path"
    else
        printf "  ${_BC_CYAN}DRY-RUN${_BC_NC}  %s profile: %s\n" "$name" "$profile_path"
    fi

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
        printf "  ${_BC_CYAN}DRY-RUN${_BC_NC}  [%s] Would remove %d items (%d not present)\n" "$name" "$cleaned" "$skipped"
    elif [[ $cleaned -gt 0 ]]; then
        printf "  ${_BC_GREEN}DONE${_BC_NC}  [%s] Removed %d session data items (%d not present)\n" "$name" "$cleaned" "$skipped"
    else
        printf "  ${_BC_YELLOW}SKIP${_BC_NC}  [%s] No session data found to clean\n" "$name"
    fi

    return 0
}

# --- Main Cleanup Function ---
# This is the entry point when sourced by hardening-fix.sh
run_browser_cleanup() {
    local profile_path=""
    local dry_run=false
    local cleanup_all=false
    local cleanup_target=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --profile) profile_path="$2"; shift 2 ;;
            --dry-run) dry_run=true; shift ;;
            --all) cleanup_all=true; shift ;;
            --browser) cleanup_target="$2"; shift 2 ;;
            --help)
                echo "Usage: browser-cleanup.sh [OPTIONS]"
                echo ""
                echo "Removes browser session data (cookies, cache, history, local storage)."
                echo "Preserves bookmarks, extensions, and preferences."
                echo ""
                echo "Options:"
                echo "  --profile PATH   Use a specific profile directory"
                echo "  --all            Clean all installed browsers"
                echo "  --browser NAME   Clean a specific browser (chromium, chrome, edge)"
                echo "  --dry-run        Show what would be removed without deleting"
                echo ""
                echo "Default (no flags): cleans preferred browser (Chromium > Chrome > Edge)"
                return 0
                ;;
            *) echo "Unknown option: $1" >&2; return 2 ;;
        esac
    done

    # If --profile is specified, clean that path directly (legacy mode)
    if [[ -n "$profile_path" ]]; then
        # Determine which browser this profile belongs to
        local detected_browser="chromium"  # default fallback
        local browser
        for browser in "${BROWSER_PREFERENCE_ORDER[@]}"; do
            if echo "$profile_path" | grep -qi "${BROWSER_NAME[$browser]}"; then
                detected_browser="$browser"
                break
            fi
        done
        _bc_clean_profile "$detected_browser" "$profile_path" "$dry_run"
        return $?
    fi

    # Determine which browsers to clean
    local -a targets=()
    if $cleanup_all; then
        local installed
        installed=$(get_installed_browsers)
        if [[ -z "$installed" ]]; then
            printf "  ${_BC_YELLOW}SKIP${_BC_NC}  No supported browser installed\n"
            return 0
        fi
        read -ra targets <<< "$installed"
    elif [[ -n "$cleanup_target" ]]; then
        if [[ -z "${BROWSER_NAME[$cleanup_target]+x}" ]]; then
            printf "  ${_BC_RED}ERROR${_BC_NC}  Unknown browser: %s (valid: chromium, chrome, edge)\n" "$cleanup_target" >&2
            return 2
        fi
        targets=("$cleanup_target")
    else
        local preferred
        if ! preferred=$(get_preferred_browser); then
            printf "  ${_BC_YELLOW}SKIP${_BC_NC}  No supported browser installed\n"
            return 0
        fi
        targets=("$preferred")
    fi

    local browser
    for browser in "${targets[@]}"; do
        local profile
        profile=$(get_browser_profile_path "$browser")
        _bc_clean_profile "$browser" "$profile" "$dry_run"
    done

    return 0
}

# --- Standalone Entry Point ---
# Only run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_browser_cleanup "$@"
fi
