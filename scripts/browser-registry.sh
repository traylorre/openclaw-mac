#!/usr/bin/env bash
# Browser Registry for Multi-Browser Hardening Support
# Sourced by hardening-audit.sh, hardening-fix.sh, and browser-cleanup.sh.
# To add a new Chromium-based browser: add one block below.

# Guard against double-sourcing
if [[ -n "${_BROWSER_REGISTRY_LOADED:-}" ]]; then return 0; fi
readonly _BROWSER_REGISTRY_LOADED=1

# ── Browser Metadata Arrays ─────────────────────────────────────────
declare -A BROWSER_NAME BROWSER_APP_PATH BROWSER_BINARY_PATH
declare -A BROWSER_PLIST_DOMAIN BROWSER_PROFILE_DIR BROWSER_TCC_BUNDLE
declare -A BROWSER_CASK BROWSER_PROCESS_NAME

# Preference order: first installed wins for default browser selection
BROWSER_PREFERENCE_ORDER=(chromium chrome edge)

# --- Chromium ---
BROWSER_NAME[chromium]="Chromium"
BROWSER_APP_PATH[chromium]="/Applications/Chromium.app"
BROWSER_BINARY_PATH[chromium]="/Applications/Chromium.app/Contents/MacOS/Chromium"
BROWSER_PLIST_DOMAIN[chromium]="org.chromium.Chromium"
BROWSER_PROFILE_DIR[chromium]="Library/Application Support/Chromium/Default"
BROWSER_TCC_BUNDLE[chromium]="org.chromium.Chromium"
BROWSER_CASK[chromium]="chromium"
BROWSER_PROCESS_NAME[chromium]="Chromium"

# --- Google Chrome ---
BROWSER_NAME[chrome]="Google Chrome"
BROWSER_APP_PATH[chrome]="/Applications/Google Chrome.app"
BROWSER_BINARY_PATH[chrome]="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
BROWSER_PLIST_DOMAIN[chrome]="com.google.Chrome"
BROWSER_PROFILE_DIR[chrome]="Library/Application Support/Google/Chrome/Default"
BROWSER_TCC_BUNDLE[chrome]="com.google.Chrome"
BROWSER_CASK[chrome]="google-chrome"
BROWSER_PROCESS_NAME[chrome]="Google Chrome"

# --- Microsoft Edge ---
BROWSER_NAME[edge]="Microsoft Edge"
BROWSER_APP_PATH[edge]="/Applications/Microsoft Edge.app"
BROWSER_BINARY_PATH[edge]="/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"
BROWSER_PLIST_DOMAIN[edge]="com.microsoft.Edge"
BROWSER_PROFILE_DIR[edge]="Library/Application Support/Microsoft Edge/Default"
BROWSER_TCC_BUNDLE[edge]="com.microsoft.edgemac"
BROWSER_CASK[edge]="microsoft-edge"
BROWSER_PROCESS_NAME[edge]="Microsoft Edge"

# ── Helper Functions ─────────────────────────────────────────────────

# List installed browsers (short names), in preference order.
# Output: space-separated list, e.g. "chromium edge"
get_installed_browsers() {
    local -a installed=()
    for browser in "${BROWSER_PREFERENCE_ORDER[@]}"; do
        if [[ -d "${BROWSER_APP_PATH[$browser]}" ]]; then
            installed+=("$browser")
        fi
    done
    echo "${installed[*]}"
}

# Return the preferred browser (first installed in preference order).
# Exit 1 if no supported browser is installed.
get_preferred_browser() {
    for browser in "${BROWSER_PREFERENCE_ORDER[@]}"; do
        if [[ -d "${BROWSER_APP_PATH[$browser]}" ]]; then
            echo "$browser"
            return 0
        fi
    done
    return 1
}

# Check if a specific browser is currently running.
# Usage: is_browser_running "chromium"
is_browser_running() {
    local browser="$1"
    pgrep -x "${BROWSER_PROCESS_NAME[$browser]}" &>/dev/null
}

# Resolve the full profile directory path for a browser, respecting
# sudo context (uses SUDO_USER's home when running as root).
get_browser_profile_path() {
    local browser="$1"
    local user_home
    if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
        user_home=$(eval echo "~${SUDO_USER}")
    else
        user_home="$HOME"
    fi
    echo "${user_home}/${BROWSER_PROFILE_DIR[$browser]}"
}
