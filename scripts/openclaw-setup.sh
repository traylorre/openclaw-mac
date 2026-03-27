#!/usr/bin/env bash
# openclaw-setup.sh — Install and configure OpenClaw for LinkedIn automation (M3)
# Automates Phase 1 setup tasks T001-T006
# Constitution VI: set -euo pipefail, shellcheck clean, idempotent, colored output
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

REPO_ROOT="$(resolve_repo_root "$SCRIPT_DIR")"
readonly REPO_ROOT

# Refuse sudo — this is all user-space
refuse_sudo

readonly AGENT_NAME="linkedin-persona"
readonly OPENCLAW_DIR="${HOME}/.openclaw"
readonly OPENCLAW_CONFIG="${OPENCLAW_DIR}/openclaw.json"

# Track step outcomes for final summary
declare -A STEP_STATUS=()

run_step() {
    local name="$1"
    local func="$2"
    log_step "${name}"
    # Run in subshell so that set -e failures within the function don't
    # kill the entire script. The subshell inherits set -e but its exit
    # code is captured by the 'if', allowing the parent to continue.
    if (set -e; "$func"); then
        STEP_STATUS["$name"]="PASS"
    else
        STEP_STATUS["$name"]="FAIL"
        log_warn "Step failed: ${name} — continuing with remaining steps"
    fi
}

# --- Preflight ---
preflight_checks() {
    local ok=true

    # macOS check
    if [[ "$(uname)" != "Darwin" ]]; then
        log_error "This script is for macOS only"
        return 1
    fi
    log_debug "macOS $(sw_vers -productVersion) on $(uname -m)"

    # Homebrew
    if ! command -v brew &>/dev/null; then
        log_error "Homebrew not found. Install from https://brew.sh"
        ok=false
    fi

    # Disk space (Ollama model is ~4GB)
    local free_gb
    free_gb=$(df -g "$HOME" | awk 'NR==2 {print $4}')
    if [[ "$free_gb" -lt 10 ]]; then
        log_warn "Low disk space: ${free_gb}GB free. Ollama model needs ~4GB."
    fi
    log_debug "Disk space: ${free_gb}GB free"

    # Node.js (OpenClaw requires >=22.16.0)
    if command -v node &>/dev/null; then
        local node_version
        node_version=$(node --version | sed 's/^v//')
        log_debug "Node.js: ${node_version}"
        # Compare major.minor.patch — need >=22.16.0
        local node_major node_minor
        node_major=$(echo "$node_version" | cut -d. -f1)
        node_minor=$(echo "$node_version" | cut -d. -f2)
        if [[ "$node_major" -lt 22 ]] || { [[ "$node_major" -eq 22 ]] && [[ "$node_minor" -lt 16 ]]; }; then
            log_error "Node.js ${node_version} is too old. OpenClaw requires >=22.16.0"
            log_error "Upgrade: brew upgrade node (or: bun install -g n && n install 22)"
            ok=false
        fi
    else
        log_error "Node.js not found. OpenClaw requires Node >=22.16.0"
        log_error "Install: brew install node"
        ok=false
    fi

    # Docker (for later steps)
    if ! command -v docker &>/dev/null; then
        log_warn "Docker CLI not found — Docker steps will be skipped"
    fi

    if [[ "$ok" == "false" ]]; then return 1; fi
    log_info "Preflight checks passed"
}

# --- T001: Bun + OpenClaw ---
install_bun_and_openclaw() {
    if command -v bun &>/dev/null; then
        log_info "Bun already installed: $(bun --version)"
    else
        log_info "Installing Bun..."
        curl -fsSL https://bun.sh/install | bash
        export PATH="${HOME}/.bun/bin:${PATH}"
        log_info "Bun installed: $(bun --version)"
    fi

    if command -v openclaw &>/dev/null; then
        log_info "OpenClaw already installed: $(openclaw --version 2>/dev/null || echo 'installed')"
    else
        log_info "Installing OpenClaw..."
        bun install -g openclaw
        log_info "OpenClaw installed: $(openclaw --version 2>/dev/null || echo 'installed')"
    fi
}

# --- T002: Ollama ---
install_ollama() {
    if command -v ollama &>/dev/null; then
        log_info "Ollama already installed"
    else
        log_info "Installing Ollama via Homebrew..."
        brew install ollama
    fi

    # Ensure ollama is serving via launchd (not orphan background process)
    if ! curl -s http://127.0.0.1:11434/api/tags &>/dev/null; then
        log_info "Starting Ollama service via brew services..."
        brew services start ollama 2>/dev/null || {
            log_warn "brew services failed, starting ollama directly..."
            ollama serve &>/dev/null &
        }
        # Wait for the API to become available
        local retries=0
        while ! curl -s http://127.0.0.1:11434/api/tags &>/dev/null && [[ "$retries" -lt 10 ]]; do
            sleep 1
            retries=$((retries + 1))
        done
        if [[ "$retries" -ge 10 ]]; then
            log_warn "Ollama API not responding after 10s — model pull may fail"
        fi
    fi

    if ollama list 2>/dev/null | grep -q "llama3.3"; then
        log_info "llama3.3 model already available"
    else
        log_info "Pulling llama3.3 model (~4GB, this takes a while)..."
        ollama pull llama3.3
    fi
}

# --- T003: Create Agents ---
create_agents() {
    if [[ -d "${OPENCLAW_DIR}/agents/${AGENT_NAME}" ]]; then
        log_info "Agent '${AGENT_NAME}' already exists"
    else
        log_info "Creating agent: ${AGENT_NAME}"
        openclaw agents add "${AGENT_NAME}" --non-interactive --workspace "${OPENCLAW_DIR}/agents/${AGENT_NAME}"
    fi

}

# --- T004: Configure LLM Providers ---
configure_llm() {
    if [[ ! -f "$OPENCLAW_CONFIG" ]]; then
        log_warn "openclaw.json not found at ${OPENCLAW_CONFIG} — skipping LLM config"
        return 1
    fi

    # Set primary model via CLI
    log_info "Setting primary model to Gemini..."
    openclaw models set google/gemini-3.1-pro-preview 2>/dev/null || log_warn "Could not set primary model via CLI"

    # Check for API keys in environment
    if [[ -f "${OPENCLAW_DIR}/.env" ]]; then
        if grep -q "GEMINI_API_KEY" "${OPENCLAW_DIR}/.env"; then
            log_info "GEMINI_API_KEY found in .env"
        else
            log_warn "GEMINI_API_KEY not set in ${OPENCLAW_DIR}/.env"
            log_warn "  Add: GEMINI_API_KEY=your-key-here"
        fi
        if grep -q "ANTHROPIC_API_KEY" "${OPENCLAW_DIR}/.env"; then
            log_info "ANTHROPIC_API_KEY found in .env (fallback)"
        else
            log_warn "ANTHROPIC_API_KEY not set (fallback provider)"
            log_warn "  Add: ANTHROPIC_API_KEY=your-key-here"
        fi
    else
        log_warn "No .env file at ${OPENCLAW_DIR}/.env — API keys not configured"
        log_warn "  Create it with GEMINI_API_KEY and ANTHROPIC_API_KEY"
    fi
}

# --- T005: Configure Telegram ---
configure_chat() {
    # Check if Telegram is already configured
    if [[ -f "$OPENCLAW_CONFIG" ]] && jq -e '.channels.telegram.enabled' "$OPENCLAW_CONFIG" &>/dev/null; then
        log_info "Telegram channel already configured"
        return 0
    fi

    # Check if TELEGRAM_BOT_TOKEN is in env
    if [[ -f "${OPENCLAW_DIR}/.env" ]] && grep -q "TELEGRAM_BOT_TOKEN" "${OPENCLAW_DIR}/.env"; then
        log_info "TELEGRAM_BOT_TOKEN found in .env — Telegram should auto-configure"
        return 0
    fi

    log_warn "Telegram not yet configured (pending operator input — not a failure)"
    log_warn "  1. Create a bot via @BotFather on Telegram"
    log_warn "  2. Add to ${OPENCLAW_DIR}/.env: TELEGRAM_BOT_TOKEN=your-bot-token"
    log_warn "  3. Or run interactively: openclaw channels add telegram"
    # Return 0 — this is "pending user input", not a broken step
    return 0
}

# --- T006: Configure Inbound Hooks ---
configure_hooks() {
    if [[ ! -f "$OPENCLAW_CONFIG" ]]; then
        log_warn "openclaw.json not found — skipping hooks config"
        return 1
    fi

    # Check if hooks already configured
    if jq -e '.hooks.enabled' "$OPENCLAW_CONFIG" &>/dev/null; then
        log_info "Inbound hooks already configured"
        return 0
    fi

    # Generate hook token and write config
    local hook_token
    hook_token=$(openssl rand -hex 32)

    log_info "Configuring inbound hooks in openclaw.json..."
    local tmp
    tmp=$(mktemp)
    jq --arg token "$hook_token" '. + {"hooks": {"enabled": true, "token": $token, "path": "/hooks"}}' \
        "$OPENCLAW_CONFIG" > "$tmp" && mv "$tmp" "$OPENCLAW_CONFIG"

    log_info "Hooks configured (token: ${hook_token:0:8}...)"
    log_info "Hooks will listen on 127.0.0.1:18789"

    # Also save the hook token to .env for n8n to use
    local env_file="${OPENCLAW_DIR}/.env"
    if [[ ! -f "$env_file" ]]; then
        touch "$env_file"
        chmod 600 "$env_file"
    fi
    if grep -q "^OPENCLAW_HOOK_TOKEN=" "$env_file" 2>/dev/null; then
        local tmp_env
        tmp_env=$(mktemp)
        chmod 600 "$tmp_env"
        sed "s|^OPENCLAW_HOOK_TOKEN=.*|OPENCLAW_HOOK_TOKEN=${hook_token}|" "$env_file" > "$tmp_env"
        mv "$tmp_env" "$env_file"
        chmod 600 "$env_file"
    else
        echo "OPENCLAW_HOOK_TOKEN=${hook_token}" >> "$env_file"
    fi
    log_info "Hook token also saved to ${env_file} (mode 600)"
}

# --- T007-T008: HMAC Secret ---
generate_hmac_secret() {
    if [[ -x "${SCRIPT_DIR}/hmac-keygen.sh" ]]; then
        bash "${SCRIPT_DIR}/hmac-keygen.sh"
    else
        log_warn "hmac-keygen.sh not found at ${SCRIPT_DIR}/hmac-keygen.sh"
        return 1
    fi
}

# --- Deploy Workspace Files ---
deploy_workspace_files() {
    local src_main="${REPO_ROOT}/openclaw"
    # OpenClaw workspace files live at the agent root, NOT in agent/ subdir
    local dst_main="${OPENCLAW_DIR}/agents/${AGENT_NAME}"

    if [[ ! -d "$src_main" ]]; then
        log_warn "Workspace templates not found at ${src_main}"
        return 1
    fi

    # Deploy main agent workspace (active skills only)
    if [[ -d "$dst_main" ]]; then
        log_info "Deploying workspace files to ${dst_main}"
        cp "${src_main}"/*.md "$dst_main/"
        mkdir -p "${dst_main}/skills"
        for skill in linkedin-post linkedin-activity token-status; do
            if [[ -d "${src_main}/skills/${skill}" ]]; then
                cp -Rp "${src_main}/skills/${skill}" "${dst_main}/skills/"
            fi
        done
        log_info "  Deployed: $(find "${src_main}" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ') md files + active skills"
    else
        log_warn "Agent directory not found: ${dst_main}"
        log_warn "Run 'openclaw agents add ${AGENT_NAME}' first"
        return 1
    fi
}

# --- Summary ---
print_summary() {
    echo ""
    echo "================================================================"
    echo "  OpenClaw M3 Setup Summary"
    echo "================================================================"

    for step_name in "${!STEP_STATUS[@]}"; do
        local status="${STEP_STATUS[$step_name]}"
        if [[ "$status" == "PASS" ]]; then
            printf "  ${CLR_GREEN}PASS${CLR_NC}  %s\n" "$step_name"
        else
            printf "  ${CLR_RED}FAIL${CLR_NC}  %s\n" "$step_name"
        fi
    done | sort

    echo "================================================================"

    # Count failures
    local fail_count=0
    for status in "${STEP_STATUS[@]}"; do
        if [[ "$status" == "FAIL" ]]; then
            fail_count=$((fail_count + 1))
        fi
    done

    if [[ "$fail_count" -gt 0 ]]; then
        echo ""
        log_warn "${fail_count} step(s) need attention. Review warnings above."
    fi

    echo ""
    log_info "Remaining manual steps (if any):"
    if [[ -z "${GEMINI_API_KEY:-}" ]] && ! (grep -q "GEMINI_API_KEY" "${OPENCLAW_DIR}/.env" 2>/dev/null); then
        log_info "  - Add GEMINI_API_KEY to ${OPENCLAW_DIR}/.env"
    fi
    if ! (grep -q "TELEGRAM_BOT_TOKEN" "${OPENCLAW_DIR}/.env" 2>/dev/null); then
        log_info "  - Add TELEGRAM_BOT_TOKEN to ${OPENCLAW_DIR}/.env"
    fi
    log_info "  - Create n8n API key: n8n web UI → Settings → API"
    log_info "  - Set up LinkedIn OAuth: n8n web UI → Credentials → OAuth2"
    echo ""
}

main() {
    # Parse args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --debug) DEBUG=true; export DEBUG; shift ;;
            --help|-h)
                echo "Usage: scripts/openclaw-setup.sh [--debug]"
                echo "Install and configure OpenClaw for M3 LinkedIn Automation."
                exit 0 ;;
            *) log_error "Unknown option: $1"; exit 1 ;;
        esac
    done

    echo ""
    log_info "OpenClaw M3 Setup — LinkedIn Automation"
    log_info "========================================"
    echo ""

    run_step "Preflight checks" preflight_checks
    run_step "Install Bun + OpenClaw" install_bun_and_openclaw
    run_step "Install Ollama + llama3.3" install_ollama
    run_step "Create agents" create_agents
    run_step "Configure LLM providers" configure_llm
    run_step "Configure Telegram" configure_chat
    run_step "Configure inbound hooks" configure_hooks
    run_step "Generate HMAC secret" generate_hmac_secret
    run_step "Deploy workspace files" deploy_workspace_files

    print_summary
}

main "$@"
