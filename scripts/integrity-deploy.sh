#!/usr/bin/env bash
# integrity-deploy.sh — Deploy workspace files and create signed integrity manifest
# Constitution VI: set -euo pipefail, shellcheck clean, idempotent, colored output
# FR-006: Verify git clean tree before deploy
# FR-016: Sign manifest with Keychain HMAC key
# FR-017: Include CLAUDE.md, workflows, scripts, config in manifest
# FR-020: Record platform runtime version
# FR-028: Record skill content hashes in manifest
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/integrity.sh
source "${SCRIPT_DIR}/lib/integrity.sh"

REPO_ROOT="$(resolve_repo_root "$SCRIPT_DIR")"
readonly REPO_ROOT
readonly OPENCLAW_DIR="${HOME}/.openclaw"

usage() {
    cat <<'USAGE'
Usage: scripts/integrity-deploy.sh [--skip-git-check] [--force] [--verify-baseline] [--debug]

Deploy workspace files from the repository to agent directories,
compute checksums, sign the integrity manifest, and optionally
set immutable flags.

Options:
  --skip-git-check    Skip git clean tree verification (for development)
  --force             Skip first-run interactive confirmation
  --verify-baseline   Print current baseline summary and exit
  --debug             Verbose output
USAGE
}

verify_git_clean() {
    if ! command -v git &>/dev/null || [[ ! -d "${REPO_ROOT}/.git" ]]; then
        log_warn "Not a git repository — skipping git clean check"
        return 0
    fi

    # Check for uncommitted changes in protected directories
    if ! git -C "$REPO_ROOT" diff --quiet -- openclaw/ openclaw-extractor/ workflows/ scripts/ CLAUDE.md 2>/dev/null; then
        log_error "Git working tree has uncommitted changes in protected directories"
        log_error "Commit or stash changes before deploying: git status"
        return 1
    fi

    local branch
    branch=$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null)
    log_info "Deploying from branch: ${branch}"
}

deploy_workspace_files() {
    log_step "Deploying workspace files to agent directories"

    # linkedin-persona agent
    local persona_dir="${OPENCLAW_DIR}/agents/linkedin-persona"
    if [[ -d "$persona_dir" ]]; then
        cp "${REPO_ROOT}"/openclaw/*.md "${persona_dir}/"
        mkdir -p "${persona_dir}/skills"
        cp -Rp "${REPO_ROOT}"/openclaw/skills/* "${persona_dir}/skills/"
        log_info "Deployed workspace files to linkedin-persona"
    else
        log_warn "linkedin-persona agent dir not found — skipping workspace deploy"
    fi

    # feed-extractor agent
    local extractor_dir="${OPENCLAW_DIR}/agents/feed-extractor"
    if [[ -d "$extractor_dir" ]]; then
        cp "${REPO_ROOT}"/openclaw-extractor/*.md "${extractor_dir}/"
        log_info "Deployed workspace files to feed-extractor"
    else
        log_warn "feed-extractor agent dir not found — skipping workspace deploy"
    fi
}

create_manifest() {
    log_step "Creating signed integrity manifest"

    local manifest
    manifest=$(integrity_build_manifest "$REPO_ROOT")

    local file_count
    file_count=$(echo "$manifest" | jq '.files | length')

    mkdir -p "$(dirname "$INTEGRITY_MANIFEST")"
    # T046: Use safe atomic write for manifest (FR-005)
    _integrity_safe_atomic_write "$INTEGRITY_MANIFEST" "$(echo "$manifest" | jq '.')"
    chmod 600 "$INTEGRITY_MANIFEST"

    log_info "Manifest created: ${file_count} files checksummed"
    log_info "Saved to ${INTEGRITY_MANIFEST}"
}

# --- Phase 4 T042: Manifest coverage check ---
_check_manifest_coverage() {
    if [[ ! -f "$INTEGRITY_MANIFEST" ]]; then
        return
    fi

    local manifest_paths
    manifest_paths=$(jq -r '.files[].path' "$INTEGRITY_MANIFEST" 2>/dev/null)
    local missing=0

    while IFS= read -r protected_file; do
        [[ -z "$protected_file" ]] && continue
        [[ ! -f "$protected_file" ]] && continue
        if ! echo "$manifest_paths" | grep -qF "$protected_file"; then
            log_warn "Protected file not in manifest: ${protected_file}"
            missing=$((missing + 1))
        fi
    done < <(integrity_list_protected_files "$REPO_ROOT")

    if [[ $missing -gt 0 ]]; then
        log_warn "${missing} protected file(s) not in manifest — re-run deploy"
    fi
}

main() {
    local skip_git=false
    local _force=false
    local _verify_baseline=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip-git-check) skip_git=true; shift ;;
            --force) _force=true; shift ;;
            --verify-baseline) _verify_baseline=true; shift ;;
            --debug) DEBUG=true; export DEBUG; shift ;;
            --help|-h) usage; exit 0 ;;
            *) log_error "Unknown: $1"; usage; exit 1 ;;
        esac
    done

    # T042: --verify-baseline prints current baseline summary and exits (FR-037, FR-038)
    if [[ "${_verify_baseline}" == "true" ]]; then
        if [[ ! -f "$INTEGRITY_MANIFEST" ]]; then
            log_error "No manifest to verify. Run 'make integrity-deploy' first."
            exit 1
        fi
        log_step "Current Baseline Summary"
        local _fc _id _nv
        _fc=$(jq '.files | length' "$INTEGRITY_MANIFEST" 2>/dev/null || echo "?")
        _id=$(jq -r '.container_image_digest // "none"' "$INTEGRITY_MANIFEST" 2>/dev/null)
        _nv=$(jq -r '.container_n8n_version // "none"' "$INTEGRITY_MANIFEST" 2>/dev/null)
        echo "  Protected files: ${_fc}"
        echo "  Image digest: ${_id:0:20}..."
        echo "  n8n version: ${_nv}"
        exit 0
    fi

    log_step "Integrity Deploy"

    # T042: First-run baseline confirmation (FR-037, FR-038)
    local _is_first_run=false
    if [[ ! -f "$INTEGRITY_MANIFEST" ]]; then
        _is_first_run=true
    fi

    # FR-006: Git clean verification
    if ! $skip_git; then
        verify_git_clean || exit 1
    fi

    # Check symlinks (FR-005)
    if ! integrity_check_symlinks "$REPO_ROOT"; then
        log_error "Symlinks detected in protected paths — aborting deploy"
        exit 1
    fi

    # Deploy workspace files
    deploy_workspace_files

    # 012 T002: Neutralize git hooks in agent workspaces (FR-005)
    neutralize_git_hooks

    # 012 T003: Tighten restore script permissions (FR-006)
    tighten_restore_scripts

    # Create signed manifest
    create_manifest

    # T042: First-run baseline confirmation prompt (FR-037, FR-038)
    if $_is_first_run && [[ "${_force}" != "true" ]]; then
        local _file_count
        _file_count=$(jq '.files | length' "$INTEGRITY_MANIFEST" 2>/dev/null)
        echo ""
        log_step "First-Run Baseline Summary"
        echo "  Protected files: ${_file_count}"
        echo ""
        if [[ -t 0 ]]; then
            read -r -p "Confirm baseline? [y/N] " _confirm
            if [[ "$_confirm" != "y" && "$_confirm" != "Y" ]]; then
                log_error "Baseline not confirmed — manifest removed"
                rm -f "$INTEGRITY_MANIFEST"
                exit 1
            fi
        else
            log_error "First-run requires interactive confirmation. Use --force to bypass."
            rm -f "$INTEGRITY_MANIFEST"
            exit 1
        fi
    fi

    # T042: Warn if protected files exist but are not in manifest
    _check_manifest_coverage

    # Phase 3B: Ensure audit output directory exists
    mkdir -p "${HOME}/.openclaw/logs/audit"

    # 012 Phase 3: Container baseline capture (TP3-010, TP3-012)
    capture_container_baseline

    # 014: Ollama model baseline capture
    capture_ollama_baseline

    integrity_audit_log "deploy" "manifest created with $(jq '.files | length' "$INTEGRITY_MANIFEST" 2>/dev/null) files"
    log_info "Deploy complete. Run 'sudo make integrity-lock' to set immutable flags."
}

# --- 012 Phase 3: Container Baseline Capture (TP3-010, TP3-012) ---

capture_container_baseline() {
    log_step "Capturing container baseline"

    # TP3-012: Create container-security-config.json if it doesn't exist
    if [[ ! -f "$INTEGRITY_CONTAINER_CONFIG" ]]; then
        log_info "Creating initial container-security-config.json with default thresholds"
        local default_config
        default_config=$(_integrity_default_container_config)
        integrity_write_container_config "$default_config"
    fi

    # Check Docker availability
    if ! command -v docker &>/dev/null; then
        log_warn "Docker not available — skipping container baseline capture"
        return 0
    fi

    # Discover container
    local cid
    cid=$(integrity_discover_container 2>/dev/null)
    if [[ -z "$cid" ]]; then
        log_warn "No orchestration container found — skipping container baseline"
        return 0
    fi

    # TP3-010: Verify n8n readiness with retry
    local ready=false
    local attempt
    for attempt in 1 2 3; do
        if integrity_run_with_timeout 10 docker exec "$cid" n8n --version &>/dev/null; then
            ready=true
            break
        fi
        log_info "n8n not ready (attempt ${attempt}/3) — waiting 5 seconds..."
        sleep 5
    done

    if ! $ready; then
        log_warn "n8n not ready after 3 attempts — aborting container baseline capture"
        log_warn "Container baseline NOT recorded. Re-run deploy after n8n is ready."
        return 0
    fi

    # Capture baseline
    local baseline
    baseline=$(integrity_capture_container_baseline "$cid")
    if [[ -z "$baseline" ]]; then
        log_error "Failed to capture container baseline"
        return 0
    fi

    # Merge container fields into existing manifest
    local manifest_body
    manifest_body=$(jq --sort-keys -c 'del(.signature)' "$INTEGRITY_MANIFEST")
    if [[ -z "$manifest_body" ]]; then
        log_error "Failed to read existing manifest for container merge — aborting"
        return 1
    fi

    local image_digest n8n_version
    image_digest=$(echo "$baseline" | jq -r '.container_image_digest // empty')
    n8n_version=$(echo "$baseline" | jq -r '.container_n8n_version // empty')

    # Build merge object — only include fields that exist in baseline (avoid null injection)
    local merge_obj
    merge_obj=$(echo "$baseline" | jq -c '{
        container_image_digest: .container_image_digest,
        container_image_name: .container_image_name,
        container_n8n_version: .container_n8n_version
    } | with_entries(select(.value != null))')

    # Conditionally add credentials and community nodes (only if capture succeeded)
    local cred_count=0 node_count=0
    if echo "$baseline" | jq -e '.expected_credentials' &>/dev/null; then
        merge_obj=$(echo "$merge_obj" | jq --argjson c "$(echo "$baseline" | jq '.expected_credentials')" '. + {expected_credentials: $c}')
        cred_count=$(echo "$baseline" | jq '.expected_credentials | length')
    fi
    if echo "$baseline" | jq -e '.expected_community_nodes' &>/dev/null; then
        merge_obj=$(echo "$merge_obj" | jq --argjson n "$(echo "$baseline" | jq '.expected_community_nodes')" '. + {expected_community_nodes: $n}')
        node_count=$(echo "$baseline" | jq '.expected_community_nodes | length')
    fi

    # Merge into manifest
    local updated_manifest
    updated_manifest=$(echo "$manifest_body" | jq --argjson merge "$merge_obj" '. + $merge')

    # Re-sign the manifest
    local body sig
    body=$(echo "$updated_manifest" | jq --sort-keys -c '.')
    sig=$(integrity_sign_manifest "$body")
    updated_manifest=$(echo "$updated_manifest" | jq --arg sig "$sig" '. + {signature: $sig}')

    # T046: Use safe atomic write for manifest (FR-005)
    local manifest_content
    manifest_content=$(echo "$updated_manifest" | jq '.')
    _integrity_safe_atomic_write "$INTEGRITY_MANIFEST" "$manifest_content"
    chmod 600 "$INTEGRITY_MANIFEST"

    log_info "Container baseline captured:"
    log_info "  Image digest: ${image_digest:0:20}..."
    log_info "  n8n version: ${n8n_version}"
    log_info "  Credentials: ${cred_count}"
    log_info "  Community nodes: ${node_count}"

    integrity_audit_log "container_deploy" "image_digest=${image_digest:0:20}, n8n_version=${n8n_version}, credentials=${cred_count}, community_nodes=${node_count}"
}

capture_ollama_baseline() {
    if ! command -v ollama &>/dev/null; then
        log_info "Ollama not installed — skipping model digest capture"
        return 0
    fi

    log_step "Capturing Ollama model baseline"

    # Attempt to get digest for the configured model (default: gemma3:4b)
    local model="${OLLAMA_MODEL:-gemma3:4b}"
    local digest
    digest=$(ollama show "$model" --modelfile 2>/dev/null | grep -oE 'sha256:[a-f0-9]+' | head -1 || true)

    if [[ -z "$digest" ]]; then
        log_warn "Could not capture Ollama model digest for ${model}"
        return 0
    fi

    # Merge into manifest
    if [[ ! -f "$INTEGRITY_MANIFEST" ]]; then
        log_warn "Manifest not found — cannot add Ollama digest"
        return 0
    fi

    local manifest_body
    manifest_body=$(jq --sort-keys -c 'del(.signature)' "$INTEGRITY_MANIFEST")
    local updated
    updated=$(echo "$manifest_body" | jq --arg d "$digest" --arg m "$model" \
        '. + {ollama_model_digest: $d, ollama_model_name: $m}')

    local body sig
    body=$(echo "$updated" | jq --sort-keys -c '.')
    sig=$(integrity_sign_manifest "$body")
    updated=$(echo "$updated" | jq --arg sig "$sig" '. + {signature: $sig}')

    local manifest_content
    manifest_content=$(echo "$updated" | jq '.')
    _integrity_safe_atomic_write "$INTEGRITY_MANIFEST" "$manifest_content"
    chmod 600 "$INTEGRITY_MANIFEST"

    log_info "Ollama baseline captured: model=${model}, digest=${digest:0:20}..."
    integrity_audit_log "ollama_deploy" "model=${model}, digest=${digest:0:20}"
}

neutralize_git_hooks() {
    log_step "Neutralizing git hooks in protected directories"
    local openclaw_dir="${HOME}/.openclaw"
    local hooks_neutralized=0

    # Load hooks allowlist (if exists and signed)
    local allowed_hooks=()
    if [[ -f "${openclaw_dir}/hooks-allowlist.json" ]]; then
        if integrity_verify_state_file "${openclaw_dir}/hooks-allowlist.json"; then
            while IFS= read -r h; do
                allowed_hooks+=("$h")
            done < <(jq -r '.allowed_hooks[]' "${openclaw_dir}/hooks-allowlist.json" 2>/dev/null)
        else
            log_warn "Hooks allowlist signature invalid — treating all hooks as unauthorized"
        fi
    fi

    # Scan agent workspaces and repo root
    local hook_dirs=()
    while IFS= read -r d; do
        hook_dirs+=("$d")
    done < <(find "${openclaw_dir}/agents" -type d -name "hooks" -path "*/.git/*" 2>/dev/null)
    [[ -d "${REPO_ROOT}/.git/hooks" ]] && hook_dirs+=("${REPO_ROOT}/.git/hooks")

    for hooks_dir in "${hook_dirs[@]}"; do
        while IFS= read -r hook; do
            local hook_name
            hook_name=$(basename "$hook")

            # Check allowlist
            local is_allowed=false
            for allowed in "${allowed_hooks[@]}"; do
                if [[ "$hook_name" == "$allowed" ]]; then
                    is_allowed=true
                    break
                fi
            done

            if $is_allowed; then
                log_debug "Hook allowed: ${hook}"
                continue
            fi

            # Remove execute permission
            if [[ -x "$hook" ]]; then
                chmod -x "$hook"
                hooks_neutralized=$((hooks_neutralized + 1))
                log_debug "Neutralized: ${hook}"
            fi
        done < <(find "$hooks_dir" -type f 2>/dev/null)
    done

    if [[ $hooks_neutralized -gt 0 ]]; then
        log_info "Neutralized ${hooks_neutralized} git hooks (chmod -x)"
    else
        log_info "No active git hooks to neutralize"
    fi
}

tighten_restore_scripts() {
    local restore_dir="${HOME}/.openclaw/restore-scripts"
    if [[ ! -d "$restore_dir" ]]; then
        return
    fi

    local tightened=0
    while IFS= read -r f; do
        local current_perms
        current_perms=$(stat -f '%Lp' "$f" 2>/dev/null)
        if [[ "$current_perms" != "700" ]]; then
            chmod 700 "$f" 2>/dev/null || log_debug "Cannot chmod (may be locked): ${f}"
            tightened=$((tightened + 1))
        fi
    done < <(find "$restore_dir" -type f 2>/dev/null)

    log_info "Restore scripts permissions tightened to 700"
}

main "$@"
