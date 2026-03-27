#!/usr/bin/env bash
# Fledge Gateway Setup — Automated n8n deployment
# Brings a fresh clone to a working gateway in one command.
#
# Usage:
#   bash scripts/gateway-setup.sh          # full setup
#   bash scripts/gateway-setup.sh --check  # verify existing setup
#
# Prerequisites: bootstrap.sh must have been run first.
# See GETTING-STARTED.md for full walkthrough.

set -euo pipefail

readonly VERSION="0.1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_DIR="${SCRIPT_DIR}/templates"
WORKFLOW_DIR="${REPO_ROOT}/n8n/workflows"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

if [[ ! -t 1 ]]; then
    RED='' GREEN='' YELLOW='' CYAN='' BOLD='' NC=''
fi

OK=0
FIXED=0
ERRORS=0

report() {
    local status="$1" msg="$2"
    case "$status" in
        OK)    printf "  %s✓%s  %s\n" "$GREEN" "$NC" "$msg"; OK=$((OK + 1)) ;;
        FIXED) printf "  %s+%s  %s\n" "$CYAN" "$NC" "$msg"; FIXED=$((FIXED + 1)) ;;
        FAIL)  printf "  %s✗%s  %s\n" "$RED" "$NC" "$msg"; ERRORS=$((ERRORS + 1)) ;;
        WARN)  printf "  %s!%s  %s\n" "$YELLOW" "$NC" "$msg" ;;
        INFO)  printf "  %sℹ%s  %s\n" "$BOLD" "$NC" "$msg" ;;
    esac
}

# --- Check Mode ---
CHECK_ONLY=false
if [[ "${1:-}" == "--check" ]]; then
    CHECK_ONLY=true
fi

# --- Step 1: Verify prerequisites ---
step_prerequisites() {
    printf "\n%s[1/6] Prerequisites%s\n" "$BOLD" "$NC"

    if ! command -v colima &>/dev/null; then
        report FAIL "Colima not installed (run: bash scripts/bootstrap.sh)"
        return 1
    fi
    report OK "Colima installed"

    if ! command -v docker &>/dev/null; then
        report FAIL "Docker CLI not installed (run: bash scripts/bootstrap.sh)"
        return 1
    fi
    report OK "Docker CLI installed"

    if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null; then
        report FAIL "Docker Compose not installed (run: brew install docker-compose)"
        return 1
    fi
    report OK "Docker Compose installed"

    if [[ ! -f "${COMPOSE_DIR}/docker-compose.yml" ]]; then
        report FAIL "docker-compose.yml not found at ${COMPOSE_DIR}"
        return 1
    fi
    report OK "docker-compose.yml found"

    if [[ ! -d "${REPO_ROOT}/node_modules" ]]; then
        report WARN "node_modules not found. Run 'npm install' from repo root for git hooks."
    fi
}

# --- Step 2: Start Colima ---
step_colima() {
    printf "\n%s[2/6] Colima Container Runtime%s\n" "$BOLD" "$NC"

    if colima status &>/dev/null && docker info &>/dev/null; then
        report OK "Colima running, Docker socket reachable"
        return 0
    fi

    if $CHECK_ONLY; then
        report FAIL "Colima not running"
        return 1
    fi

    report INFO "Starting Colima (this takes 30-60 seconds, warnings are normal)..."
    local hw_arch
    hw_arch=$(uname -m)
    local -a colima_args=(start --cpus 2 --memory 4 --disk 60)
    if [[ "$hw_arch" == "arm64" ]]; then
        colima_args+=(--arch aarch64)
    fi

    if colima "${colima_args[@]}" 2>/dev/null; then
        if docker info &>/dev/null; then
            report FIXED "Colima started, Docker socket reachable"
        else
            report FAIL "Colima started but Docker socket not reachable"
            return 1
        fi
    else
        report FAIL "Failed to start Colima"
        return 1
    fi
}

# --- Step 3: Create secrets ---
step_secrets() {
    printf "\n%s[3/6] Docker Secrets%s\n" "$BOLD" "$NC"

    local secrets_dir="${COMPOSE_DIR}/secrets"
    local key_file="${secrets_dir}/n8n_encryption_key.txt"

    if [[ -f "$key_file" ]]; then
        report OK "Encryption key exists"
        return 0
    fi

    if $CHECK_ONLY; then
        report FAIL "Encryption key not found at ${key_file}"
        return 1
    fi

    mkdir -p "$secrets_dir"
    chmod 700 "$secrets_dir"
    openssl rand -hex 32 > "$key_file"
    chmod 600 "$key_file"
    report FIXED "Generated encryption key"
}

# --- Step 4: Start n8n ---
step_n8n() {
    printf "\n%s[4/6] n8n Container%s\n" "$BOLD" "$NC"

    # Check if already running
    if docker compose -f "${COMPOSE_DIR}/docker-compose.yml" ps 2>/dev/null | grep -q "n8n.*Up"; then
        report OK "n8n container running"

        # Verify it responds
        if curl -s -o /dev/null -w "" http://localhost:5678/ 2>/dev/null; then
            report OK "n8n responding on localhost:5678"
        else
            report WARN "n8n container running but not responding yet (may still be starting)"
        fi
        return 0
    fi

    if $CHECK_ONLY; then
        report FAIL "n8n container not running"
        return 1
    fi

    report INFO "Starting n8n (this may take a minute on first run)..."
    if docker compose -f "${COMPOSE_DIR}/docker-compose.yml" up -d 2>&1 | tail -3; then
        report FIXED "n8n container started"
    else
        report FAIL "Failed to start n8n container"
        return 1
    fi

    # Wait for n8n to be ready
    report INFO "Waiting for n8n to respond..."
    local attempts=0
    while [[ $attempts -lt 30 ]]; do
        if curl -s -o /dev/null http://localhost:5678/ 2>/dev/null; then
            report OK "n8n responding on localhost:5678"
            return 0
        fi
        sleep 2
        attempts=$((attempts + 1))
    done
    report FAIL "n8n did not respond within 60 seconds"
    return 1
}

# --- Step 5: Import workflows ---
step_workflows() {
    printf "\n%s[5/6] Workflow Import%s\n" "$BOLD" "$NC"

    local container_name
    container_name=$(docker compose -f "${COMPOSE_DIR}/docker-compose.yml" ps -q n8n 2>/dev/null) || true

    if [[ -z "$container_name" ]]; then
        report FAIL "n8n container not found"
        return 1
    fi

    for workflow in gateway.json hello-world.json; do
        local src="${WORKFLOW_DIR}/${workflow}"
        if [[ ! -f "$src" ]]; then
            report FAIL "Workflow file not found: ${src}"
            continue
        fi

        if $CHECK_ONLY; then
            report OK "Workflow file exists: ${workflow}"
            continue
        fi

        # Import via the mounted volume
        if docker compose -f "${COMPOSE_DIR}/docker-compose.yml" exec -T n8n \
            n8n import:workflow --input="/tmp/workflows/${workflow}" 2>&1 | grep -q "Successfully"; then
            report FIXED "Imported ${workflow}"
        else
            report WARN "Import of ${workflow} returned unexpected output (may already exist)"
        fi
    done

    if ! $CHECK_ONLY; then
        # Activate workflows (publish:workflow may show deprecation warnings)
        for id in 1 2; do
            docker compose -f "${COMPOSE_DIR}/docker-compose.yml" exec -T n8n \
                n8n publish:workflow --id="$id" 2>/dev/null || \
            docker compose -f "${COMPOSE_DIR}/docker-compose.yml" exec -T n8n \
                n8n update:workflow --id="$id" --active=true 2>/dev/null || true
        done
        report INFO "Workflows published (restart needed for activation)"

        # Restart to activate
        docker compose -f "${COMPOSE_DIR}/docker-compose.yml" restart n8n 2>/dev/null
        report INFO "Restarting n8n to activate workflows..."
        sleep 15

        if curl -s -o /dev/null http://localhost:5678/ 2>/dev/null; then
            report OK "n8n restarted and responding"
        else
            report WARN "n8n restarting (may take a few more seconds)"
        fi
    fi
}

# --- Step 6: Manual steps ---
step_manual() {
    printf "\n%s[6/6] Manual Steps Required%s\n" "$BOLD" "$NC"

    printf "\n  The following steps require the n8n web editor.\n"
    printf "  Open %shttp://localhost:5678%s in Chrome (not Safari).\n\n" "$CYAN" "$NC"

    printf "  %sA. Create owner account%s (first time only)\n" "$BOLD" "$NC"
    printf "     Fill in email, name, password. This is local-only.\n"
    printf "     Do NOT check 'receive updates'. Skip the tutorial.\n\n"

    printf "  %sB. Create Bearer auth credential%s\n" "$BOLD" "$NC"
    printf "     1. Home → Credentials tab → Add Credential\n"
    printf "     2. Search 'Header Auth', select it\n"
    printf "     3. Name: gateway-bearer-token\n"
    printf "     4. Name field: Authorization\n"
    printf "     5. Value field: Bearer <token>\n"
    printf "        Generate token:  openssl rand -hex 32\n"
    printf "        (use leading space to avoid history)\n"
    printf "     6. Allowed HTTP Request Domains: None\n"
    printf "     7. Save\n\n"

    printf "  %sC. Attach credential to webhooks%s\n" "$BOLD" "$NC"
    printf "     For each workflow (Gateway, Hello World):\n"
    printf "     1. Open workflow → click Webhook node\n"
    printf "     2. Authentication → Header Auth\n"
    printf "     3. Credential → gateway-bearer-token\n"
    printf "     4. Click Publish (top-right orange button)\n\n"

    printf "  %sD. Store token in macOS Keychain%s\n" "$BOLD" "$NC"
    printf "     Run (with leading space to avoid history):\n"
    printf "      security add-generic-password -a 'openclaw' -s 'n8n-gateway-bearer' -w 'YOUR_TOKEN'\n\n"

    printf "  %sE. Shell aliases%s (automatically configured)\n" "$BOLD" "$NC"
    printf "     The n8n-token and openclaw aliases are in ~/.openclaw/shellrc\n"
    printf "     Open a new terminal for them to take effect.\n\n"

    printf "  %sF. Test%s\n" "$BOLD" "$NC"
    printf "     curl -s -X POST http://localhost:5678/webhook/gateway \\\\\n"
    printf "       -H \"Authorization: Bearer \$(n8n-token)\" \\\\\n"
    printf "       -H \"Content-Type: application/json\" \\\\\n"
    printf "       -d '{\"intent\": \"hello\"}'\n\n"

    printf "  %sStop / Restart%s\n" "$BOLD" "$NC"
    printf "     Stop gateway:  docker compose -f scripts/templates/docker-compose.yml down\n"
    printf "     Stop Colima:   colima stop\n"
    printf "     Restart all:   bash scripts/gateway-setup.sh\n\n"
}

# --- Main ---
main() {
    printf "%sFledge Gateway Setup v%s%s\n" "$BOLD" "$VERSION" "$NC"
    if $CHECK_ONLY; then
        printf "Mode: %scheck only%s\n" "$YELLOW" "$NC"
    else
        printf "Mode: %ssetup%s\n" "$GREEN" "$NC"
    fi

    step_prerequisites || { printf "\n%sPrerequisites not met. Run bootstrap.sh first.%s\n" "$RED" "$NC"; exit 1; }
    step_colima || exit 1
    step_secrets || exit 1
    step_n8n || exit 1
    step_workflows || true
    step_manual

    # Summary
    printf "%s════════════════════════════════════════%s\n" "$BOLD" "$NC"
    printf "  %s%d OK%s  |  %s%d FIXED%s  |  %s%d ERRORS%s\n" "$GREEN" "$OK" "$NC" "$CYAN" "$FIXED" "$NC" "$RED" "$ERRORS" "$NC"
    printf "%s════════════════════════════════════════%s\n" "$BOLD" "$NC"

    if [[ $ERRORS -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
