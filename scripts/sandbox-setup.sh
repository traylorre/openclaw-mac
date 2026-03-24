#!/usr/bin/env bash
# sandbox-setup.sh — Configure agent sandbox isolation in openclaw.json
# Constitution VI: set -euo pipefail, shellcheck clean, idempotent, colored output
# FR-007: Read-only workspace for primary agent
# FR-008: Restricted tool set for primary agent
# FR-009: Workspace-only filesystem access
# FR-010: Zero tools for extraction agent
# FR-011: Writable data directory outside workspace
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

readonly OPENCLAW_JSON="${HOME}/.openclaw/openclaw.json"
readonly WRITABLE_DATA_DIR="${HOME}/.openclaw/sandboxes/linkedin-persona/data"

usage() {
    cat <<'USAGE'
Usage: scripts/sandbox-setup.sh [--debug]

Configure sandbox isolation for both agents in ~/.openclaw/openclaw.json:
  - linkedin-persona: read-only workspace, restricted tools, writable data dir
  - feed-extractor: no workspace access, zero tools

Idempotent — safe to run multiple times.

Options:
  --debug    Verbose output
USAGE
}

# linkedin-persona sandbox config (FR-007, FR-008, FR-009, FR-011)
persona_sandbox_config() {
    cat <<'JSON'
{
  "sandbox": {
    "mode": "all",
    "scope": "agent",
    "workspaceAccess": "ro"
  },
  "tools": {
    "fs": {
      "workspaceOnly": true
    },
    "allow": [
      "read",
      "web_fetch",
      "sessions_list",
      "sessions_history",
      "sessions_send",
      "sessions_spawn",
      "session_status"
    ],
    "deny": [
      "write",
      "edit",
      "apply_patch",
      "exec",
      "process",
      "browser"
    ]
  },
  "writablePaths": []
}
JSON
}

# feed-extractor sandbox config (FR-010)
extractor_sandbox_config() {
    cat <<'JSON'
{
  "sandbox": {
    "mode": "all",
    "scope": "agent",
    "workspaceAccess": "none"
  },
  "tools": {
    "allow": [],
    "deny": [
      "read", "write", "edit", "apply_patch",
      "exec", "process", "browser", "canvas",
      "nodes", "cron", "gateway", "image"
    ]
  }
}
JSON
}

upsert_agent() {
    local config="$1"
    local agent_id="$2"
    local sandbox_json="$3"

    # Check if agent already exists in list
    local exists
    exists=$(echo "$config" | jq --arg id "$agent_id" '[.agents.list[] | select(.id == $id)] | length')

    if [[ "$exists" -gt 0 ]]; then
        # Update existing entry — merge sandbox config
        config=$(echo "$config" | jq --arg id "$agent_id" --argjson sb "$sandbox_json" '
            .agents.list = [.agents.list[] |
                if .id == $id then . * $sb else . end
            ]')
        # Log to stderr — stdout is the JSON return channel
        log_info "Updated sandbox config for agent: ${agent_id}" >&2
    else
        # Add new agent entry
        local entry
        entry=$(echo "$sandbox_json" | jq -c --arg id "$agent_id" '. + {id: $id}')
        config=$(echo "$config" | jq --argjson entry "$entry" '.agents.list += [$entry]')
        log_info "Added agent with sandbox config: ${agent_id}" >&2
    fi

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

    log_step "Sandbox Setup — Configuring agent isolation"

    # Verify openclaw.json exists
    if [[ ! -f "$OPENCLAW_JSON" ]]; then
        log_error "openclaw.json not found at ${OPENCLAW_JSON}"
        log_error "Run 'openclaw' at least once to generate it"
        exit 1
    fi

    local config
    config=$(jq '.' "$OPENCLAW_JSON")

    # Ensure agents.list exists
    if ! echo "$config" | jq -e '.agents.list' &>/dev/null; then
        config=$(echo "$config" | jq '.agents.list = []')
    fi

    # Configure linkedin-persona (FR-007, FR-008, FR-009)
    log_info "Configuring linkedin-persona sandbox"
    local persona_sb
    persona_sb=$(persona_sandbox_config)
    # Add writable data dir path to sandbox config
    persona_sb=$(echo "$persona_sb" | jq --arg path "$WRITABLE_DATA_DIR" '.writablePaths = [$path]')
    config=$(upsert_agent "$config" "linkedin-persona" "$persona_sb")

    # Configure feed-extractor (FR-010)
    log_info "Configuring feed-extractor sandbox"
    local extractor_sb
    extractor_sb=$(extractor_sandbox_config)
    config=$(upsert_agent "$config" "feed-extractor" "$extractor_sb")

    # Create writable data directory (FR-011)
    mkdir -p "$WRITABLE_DATA_DIR"
    chmod 700 "$WRITABLE_DATA_DIR"
    log_info "Writable data directory: ${WRITABLE_DATA_DIR}"

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

    # Summary
    local agent_count
    agent_count=$(echo "$config" | jq '.agents.list | length')
    log_info "Sandbox configured for 2 agents (${agent_count} total in list)"
    log_info "linkedin-persona: ro workspace, restricted tools, writable data dir"
    log_info "feed-extractor: no workspace, zero tools"
}

main "$@"
