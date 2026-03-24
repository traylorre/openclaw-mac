#!/usr/bin/env bash
# sandbox-teardown.sh — Remove sandbox configuration from openclaw.json
# Constitution VI: set -euo pipefail, shellcheck clean, idempotent, colored output
# Restores agents to unsandboxed state (for debugging or maintenance)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

readonly OPENCLAW_JSON="${HOME}/.openclaw/openclaw.json"

usage() {
    cat <<'USAGE'
Usage: scripts/sandbox-teardown.sh [--debug]

Remove sandbox configuration from linkedin-persona and feed-extractor
agents in ~/.openclaw/openclaw.json. Does NOT delete agent entries or
the writable data directory.

Idempotent — safe to run if sandbox is already disabled.

Options:
  --debug    Verbose output
USAGE
}

remove_sandbox_config() {
    local config="$1"
    local agent_id="$2"

    local exists
    exists=$(echo "$config" | jq --arg id "$agent_id" '[.agents.list[] | select(.id == $id)] | length')

    if [[ "$exists" -eq 0 ]]; then
        log_warn "Agent not found in config: ${agent_id} (skipping)" >&2
        echo "$config"
        return
    fi

    config=$(echo "$config" | jq --arg id "$agent_id" '
        .agents.list = [.agents.list[] |
            if .id == $id then del(.sandbox, .tools, .writablePaths) else . end
        ]')
    log_info "Removed sandbox config from: ${agent_id}" >&2

    echo "$config"
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --debug) DEBUG=true; export DEBUG; shift ;;
            --help|-h) usage; exit 0 ;;
            *) log_error "Unknown: $1"; usage; exit 1 ;;
        esac
    done

    log_step "Sandbox Teardown — Removing agent isolation"

    if [[ ! -f "$OPENCLAW_JSON" ]]; then
        log_error "openclaw.json not found at ${OPENCLAW_JSON}"
        exit 1
    fi

    local config
    config=$(jq '.' "$OPENCLAW_JSON")

    config=$(remove_sandbox_config "$config" "linkedin-persona")
    config=$(remove_sandbox_config "$config" "feed-extractor")

    # Write updated config (atomic: write to temp, then rename)
    local tmpfile
    tmpfile=$(mktemp "${OPENCLAW_JSON}.XXXXXX")
    if echo "$config" | jq '.' > "$tmpfile"; then
        chmod 600 "$tmpfile"
        mv "$tmpfile" "$OPENCLAW_JSON"
    else
        rm -f "$tmpfile"
        log_error "Failed to write openclaw.json — config unchanged"
        exit 1
    fi

    log_info "Sandbox disabled. Agents will run without isolation."
    log_warn "Re-enable with: make sandbox-setup"
}

main "$@"
