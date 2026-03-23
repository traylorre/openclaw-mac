#!/usr/bin/env bash
# workflow-sync.sh — Export/import n8n workflows for version control
# Constitution VI: set -euo pipefail, shellcheck clean, idempotent, colored output
# Constitution X: CLI-first infrastructure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

REPO_ROOT="$(resolve_repo_root "$SCRIPT_DIR")"
readonly REPO_ROOT

readonly CONTAINER_NAME="openclaw-n8n"
readonly WORKFLOWS_DIR="${REPO_ROOT}/workflows"

usage() {
    cat <<'USAGE'
Usage: scripts/workflow-sync.sh <export|import> [--dry-run] [--debug]

  export     Export all n8n workflows to workflows/ directory (one JSON per workflow)
  import     Import all workflows from workflows/ directory into n8n

Options:
  --dry-run  Show what would be done without doing it
  --debug    Verbose output

Workflows are exported/imported as individual JSON files for git version control.
Credential secrets are NOT included in exports (only names and IDs).
USAGE
}

check_container() {
    require_command docker "Install Docker via Colima: brew install colima docker"

    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        log_error "Container '${CONTAINER_NAME}' is not running"
        log_error "Start it with: docker compose up -d"
        # Show container status for debugging
        log_debug "All running containers:"
        docker ps --format '{{.Names}}\t{{.Status}}' 2>/dev/null | while read -r line; do
            log_debug "  ${line}"
        done
        exit 1
    fi
    log_debug "Container ${CONTAINER_NAME} is running"
}

export_workflows() {
    local dry_run="$1"
    check_container
    mkdir -p "$WORKFLOWS_DIR"

    # Use a unique temp dir to avoid conflicts
    local tmp_dir="/tmp/workflow-export-$$"

    log_info "Exporting workflows from n8n to ${WORKFLOWS_DIR}/"

    # Warn if local workflow files have uncommitted changes
    if command -v git &>/dev/null && [[ -d "${REPO_ROOT}/.git" ]]; then
        if ! git -C "$REPO_ROOT" diff --quiet -- workflows/ 2>/dev/null; then
            log_warn "Local workflow files have uncommitted changes that will be overwritten"
            log_warn "Consider: git stash -- workflows/ (or commit first)"
        fi
    fi

    if [[ "$dry_run" == "true" ]]; then
        local count
        count=$(docker exec -u node "$CONTAINER_NAME" n8n list:workflow 2>/dev/null | wc -l | tr -d ' ')
        log_info "Would export ${count} workflow(s) — dry run, no files changed"
        return 0
    fi

    # Export to tmpfs inside container, then pipe each file out via exec.
    # docker cp fails on read-only containers (read_only: true in compose).
    docker exec -u node "$CONTAINER_NAME" \
        n8n export:workflow --all --separate --output="${tmp_dir}/"

    # List exported files and copy each via stdout pipe
    docker exec "$CONTAINER_NAME" sh -c "ls ${tmp_dir}/*.json 2>/dev/null" | while IFS= read -r remote_path; do
        local name
        name=$(basename "$remote_path")
        docker exec "$CONTAINER_NAME" cat "$remote_path" > "${WORKFLOWS_DIR}/${name}"
    done
    docker exec "$CONTAINER_NAME" rm -rf "$tmp_dir"

    # List exported files
    local count=0
    while IFS= read -r f; do
        count=$((count + 1))
        local name
        name=$(basename "$f" .json)
        log_debug "  Exported: ${name}"
    done < <(find "$WORKFLOWS_DIR" -name "*.json" -type f 2>/dev/null)

    log_info "Exported ${count} workflow(s) to ${WORKFLOWS_DIR}/"
    log_info "Review changes: git diff ${WORKFLOWS_DIR}/"
}

import_workflows() {
    local dry_run="$1"
    check_container

    if [[ ! -d "$WORKFLOWS_DIR" ]]; then
        log_error "Directory '${WORKFLOWS_DIR}' does not exist"
        exit 1
    fi

    local count=0
    local files=()
    while IFS= read -r f; do
        files+=("$f")
        count=$((count + 1))
    done < <(find "$WORKFLOWS_DIR" -name "*.json" -type f 2>/dev/null)

    if [[ "$count" -eq 0 ]]; then
        log_warn "No JSON files found in ${WORKFLOWS_DIR}/"
        exit 0
    fi

    log_info "Importing ${count} workflow(s) from ${WORKFLOWS_DIR}/"

    # Show what will be imported
    for f in "${files[@]}"; do
        local name
        name=$(basename "$f" .json)
        log_debug "  Will import: ${name}"
    done

    if [[ "$dry_run" == "true" ]]; then
        log_info "Dry run — ${count} workflow(s) would be imported"
        return 0
    fi

    # Import each workflow individually via stdin pipe to tmpfs.
    # docker cp fails on read-only containers (read_only: true in compose),
    # but docker exec can write to tmpfs-mounted /tmp.
    local imported=0
    for f in "${files[@]}"; do
        local name
        name=$(basename "$f")
        log_debug "  Importing: ${name}"
        cat "$f" | docker exec -i "$CONTAINER_NAME" sh -c "cat > /tmp/${name}"
        if docker exec -u node "$CONTAINER_NAME" \
            n8n import:workflow --input="/tmp/${name}" 2>&1; then
            imported=$((imported + 1))
        else
            log_warn "Import of ${name} returned errors (see above)"
        fi
        docker exec "$CONTAINER_NAME" rm -f "/tmp/${name}"
    done

    log_info "Imported ${imported}/${count} workflow(s)"

    # Activate imported workflows via n8n public API.
    # Requires API key in macOS Keychain (created via n8n UI, stored with make gateway-setup).
    # If no key, import still succeeds — activation is skipped with a warning.
    activate_workflows "${files[@]}"
}

activate_workflows() {
    local files=("$@")
    local api_key

    api_key=$(security find-generic-password -a "openclaw" -s "n8n-api-key" -w 2>/dev/null) || true

    if [[ -z "$api_key" ]]; then
        log_warn "No n8n API key in Keychain — workflows imported but inactive"
        log_warn "Create API key in n8n UI (Settings → API), then store it:"
        log_warn "  security add-generic-password -a openclaw -s n8n-api-key -w 'YOUR_KEY'"
        log_warn "Re-run 'make workflow-import' to activate."
        return 0
    fi

    # Sort files so hmac-verify activates first (other workflows depend on it).
    local sorted_files=()
    for f in "${files[@]}"; do
        if [[ "$(basename "$f")" == "hmac-verify.json" ]]; then
            sorted_files=("$f" "${sorted_files[@]}")
        else
            sorted_files+=("$f")
        fi
    done

    local activated=0
    local failed=0
    for f in "${sorted_files[@]}"; do
        local wf_id
        wf_id=$(python3 -c "import json; print(json.load(open('$f')).get('id',''))" 2>/dev/null) || continue
        [[ -z "$wf_id" ]] && continue

        # Deactivate then activate to ensure webhook registration
        curl -s -X POST -H "X-N8N-API-KEY: ${api_key}" \
            "http://localhost:5678/api/v1/workflows/${wf_id}/deactivate" >/dev/null 2>&1

        local result
        result=$(curl -s -X POST -H "X-N8N-API-KEY: ${api_key}" \
            "http://localhost:5678/api/v1/workflows/${wf_id}/activate" 2>&1)

        if echo "$result" | grep -q '"active":true\|"active": true'; then
            activated=$((activated + 1))
            log_debug "  Activated: ${wf_id}"
        else
            failed=$((failed + 1))
            log_warn "  Failed to activate: ${wf_id}"
        fi
    done

    if [[ $failed -eq 0 ]]; then
        log_info "Activated ${activated} workflow(s)"
    else
        log_warn "Activated ${activated}, failed ${failed} workflow(s)"
    fi
}

main() {
    local command=""
    local dry_run=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            export|import) command="$1"; shift ;;
            --dry-run) dry_run=true; shift ;;
            --debug) DEBUG=true; export DEBUG; shift ;;
            --help|-h) usage; exit 0 ;;
            *) log_error "Unknown: $1"; usage; exit 1 ;;
        esac
    done

    if [[ -z "$command" ]]; then
        usage
        exit 1
    fi

    case "$command" in
        export) export_workflows "$dry_run" ;;
        import) import_workflows "$dry_run" ;;
    esac
}

main "$@"
