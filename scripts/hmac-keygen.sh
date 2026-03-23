#!/usr/bin/env bash
# hmac-keygen.sh — Generate and distribute HMAC shared secret for OpenClaw ↔ n8n webhook auth
# Constitution VI: set -euo pipefail, shellcheck clean, idempotent, colored output
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

REPO_ROOT="$(resolve_repo_root "$SCRIPT_DIR")"
readonly REPO_ROOT

readonly SECRET_LENGTH=32  # 32 bytes = 64 hex chars
USER_HOME="$(resolve_user_home)"
readonly USER_HOME
readonly OPENCLAW_ENV="${USER_HOME}/.openclaw/.env"
readonly COMPOSE_FILE="${REPO_ROOT}/scripts/templates/docker-compose.yml"
readonly PROJECT_ENV="${REPO_ROOT}/.env"

usage() {
    cat <<'USAGE'
Usage: scripts/hmac-keygen.sh [--rotate] [--dry-run] [--debug]

Generates a 32-byte HMAC shared secret and distributes it to:
  - OpenClaw environment: ~/.openclaw/.env (N8N_WEBHOOK_SECRET)
  - Project .env file: .env (OPENCLAW_WEBHOOK_SECRET for docker-compose)

Options:
  --rotate   Replace existing secret (default: skip if already set)
  --dry-run  Print the secret without writing to files
  --debug    Show verbose diagnostic output
USAGE
}

generate_secret() {
    require_command openssl "brew install openssl"
    openssl rand -hex "${SECRET_LENGTH}"
}

update_env_file() {
    local file="$1"
    local key="$2"
    local value="$3"
    # Note: sed delimiter '|' is safe because HMAC secrets are hex-only [0-9a-f]

    local dir
    dir="$(dirname "$file")"
    mkdir -p "$dir"

    if [[ ! -f "$file" ]]; then
        # Create file with restricted permissions BEFORE writing secrets.
        # touch + chmod first avoids a TOCTOU window where the file exists
        # with default (644) permissions and contains the secret.
        touch "$file"
        chmod 600 "$file"
        log_debug "Created ${file} with mode 600"
    fi

    if grep -q "^${key}=" "$file" 2>/dev/null; then
        local tmp
        tmp=$(mktemp)
        chmod 600 "$tmp"
        sed "s|^${key}=.*|${key}=${value}|" "$file" > "$tmp"
        mv "$tmp" "$file"
        chmod 600 "$file"
        log_info "Updated ${key} in ${file}"
    else
        echo "${key}=${value}" >> "$file"
        log_info "Added ${key} to ${file}"
    fi

    # Ensure permissions are correct regardless of path taken
    chmod 600 "$file"
    log_debug "File ${file} now contains ${key}=<${#value}-char value> (mode 600)"
}

main() {
    local rotate=false
    local dry_run=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --rotate)  rotate=true; shift ;;
            --dry-run) dry_run=true; shift ;;
            --debug)   DEBUG=true; export DEBUG; shift ;;
            --help|-h) usage; exit 0 ;;
            *) log_error "Unknown option: $1"; usage; exit 1 ;;
        esac
    done

    log_debug "Repo root: ${REPO_ROOT}"
    log_debug "User home: ${USER_HOME}"
    log_debug "OpenClaw env: ${OPENCLAW_ENV}"
    log_debug "Compose file: ${COMPOSE_FILE}"
    log_debug "Project .env: ${PROJECT_ENV}"

    # Check if secret already exists
    if [[ -f "$OPENCLAW_ENV" ]] && grep -q "^N8N_WEBHOOK_SECRET=" "$OPENCLAW_ENV" && [[ "$rotate" == "false" ]]; then
        local existing
        existing=$(grep "^N8N_WEBHOOK_SECRET=" "$OPENCLAW_ENV" | cut -d= -f2)
        if [[ -n "$existing" ]]; then
            log_info "HMAC secret already exists in ${OPENCLAW_ENV} (${#existing} chars)"
            log_info "Use --rotate to generate a new secret"
            return 0
        fi
    fi

    # Generate secret
    local secret
    secret=$(generate_secret)
    log_info "Generated ${SECRET_LENGTH}-byte HMAC secret (${#secret} hex chars)"

    if [[ "$dry_run" == "true" ]]; then
        echo ""
        echo "N8N_WEBHOOK_SECRET=${secret}"
        echo "OPENCLAW_WEBHOOK_SECRET=${secret}"
        echo ""
        log_info "Dry run — no files modified"
        return 0
    fi

    # Distribute to OpenClaw env
    update_env_file "$OPENCLAW_ENV" "N8N_WEBHOOK_SECRET" "$secret"

    # Write to project .env for docker-compose to read
    # docker-compose.yml uses ${OPENCLAW_WEBHOOK_SECRET} which reads from .env
    update_env_file "$PROJECT_ENV" "OPENCLAW_WEBHOOK_SECRET" "$secret"

    # Verify docker-compose references the variable
    if [[ -f "$COMPOSE_FILE" ]]; then
        if grep -q 'OPENCLAW_WEBHOOK_SECRET' "$COMPOSE_FILE"; then
            log_info "docker-compose.yml references OPENCLAW_WEBHOOK_SECRET"
        else
            log_warn "OPENCLAW_WEBHOOK_SECRET not found in ${COMPOSE_FILE}"
            log_warn "Add to n8n environment: OPENCLAW_WEBHOOK_SECRET=\${OPENCLAW_WEBHOOK_SECRET}"
        fi
    else
        log_warn "Compose file not found at ${COMPOSE_FILE}"
    fi

    echo ""
    log_info "HMAC secret distributed to:"
    log_info "  OpenClaw: ${OPENCLAW_ENV} (N8N_WEBHOOK_SECRET)"
    log_info "  Docker:   ${PROJECT_ENV} (OPENCLAW_WEBHOOK_SECRET)"
    log_info ""
    log_info "Next: restart n8n to pick up the new secret"
    log_info "  docker compose -f ${COMPOSE_FILE} down && docker compose -f ${COMPOSE_FILE} up -d"
}

main "$@"
