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
Usage: scripts/integrity-deploy.sh [--skip-git-check] [--debug]

Deploy workspace files from the repository to agent directories,
compute checksums, sign the integrity manifest, and optionally
set immutable flags.

Options:
  --skip-git-check  Skip git clean tree verification (for development)
  --debug           Verbose output
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
    echo "$manifest" > "$INTEGRITY_MANIFEST"
    chmod 600 "$INTEGRITY_MANIFEST"

    log_info "Manifest created: ${file_count} files checksummed"
    log_info "Saved to ${INTEGRITY_MANIFEST}"
}

main() {
    local skip_git=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip-git-check) skip_git=true; shift ;;
            --debug) DEBUG=true; export DEBUG; shift ;;
            --help|-h) usage; exit 0 ;;
            *) log_error "Unknown: $1"; usage; exit 1 ;;
        esac
    done

    log_step "Integrity Deploy"

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

    # Create signed manifest
    create_manifest

    log_info "Deploy complete. Run 'sudo make integrity-lock' to set immutable flags."
}

main "$@"
