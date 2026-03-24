#!/usr/bin/env bash
# integrity-verify.sh — Pre-launch integrity verification
# Constitution VI: set -euo pipefail, shellcheck clean, idempotent, colored output
# FR-014: Verify all protected file checksums against manifest
# FR-015: Block agent launch on any integrity failure
# FR-016: Verify manifest HMAC signature
# FR-005: Detect symlinks in protected paths
# FR-012: Validate pending-drafts.json schema
# FR-013: Check sandbox configuration (warn only)
# FR-018: Compare n8n workflows against version-controlled copies
# FR-019: Check dangerous environment variables
# FR-020: Verify platform version matches manifest
# FR-024: Check monitoring service heartbeat
#
# Usage:
#   scripts/integrity-verify.sh             # check + start agent
#   scripts/integrity-verify.sh --dry-run   # check only, no launch
#   scripts/integrity-verify.sh --agent <id> # specify agent to launch
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/integrity.sh
source "${SCRIPT_DIR}/lib/integrity.sh"

REPO_ROOT="$(resolve_repo_root "$SCRIPT_DIR")"
readonly REPO_ROOT
readonly OPENCLAW_JSON="${HOME}/.openclaw/openclaw.json"
readonly WRITABLE_DATA_DIR="${HOME}/.openclaw/sandboxes/linkedin-persona/data"
readonly PENDING_DRAFTS="${WRITABLE_DATA_DIR}/pending-drafts.json"

DRY_RUN=false
AGENT_ID="linkedin-persona"
WARNINGS=0
ERRORS=0

warn() {
    log_warn "$1"
    WARNINGS=$((WARNINGS + 1))
}

fail() {
    log_error "$1"
    ERRORS=$((ERRORS + 1))
}

# --- 1. Manifest Signature Verification (FR-016) ---
check_manifest_signature() {
    log_step "Verifying manifest signature"

    if [[ ! -f "$INTEGRITY_MANIFEST" ]]; then
        fail "Manifest not found: ${INTEGRITY_MANIFEST}"
        fail "  Run 'make integrity-deploy' to create it"
        return
    fi

    if integrity_verify_signature "$INTEGRITY_MANIFEST"; then
        log_info "Manifest HMAC signature valid"
    else
        fail "Manifest signature verification failed — possible tampering"
    fi
}

# --- 2. File Checksum Verification (FR-014) ---
check_file_checksums() {
    log_step "Verifying protected file checksums"

    if [[ ! -f "$INTEGRITY_MANIFEST" ]]; then
        return  # Already reported in signature check
    fi

    local total=0
    local passed=0
    local failed=0
    local missing=0

    while IFS= read -r entry; do
        local path sha256_expected
        path=$(echo "$entry" | jq -r '.path')
        sha256_expected=$(echo "$entry" | jq -r '.sha256')
        total=$((total + 1))

        if [[ ! -f "$path" ]]; then
            fail "Protected file missing: ${path}"
            missing=$((missing + 1))
            continue
        fi

        local sha256_actual
        sha256_actual=$(integrity_compute_sha256 "$path")

        if [[ "$sha256_expected" == "$sha256_actual" ]]; then
            passed=$((passed + 1))
            log_debug "OK: ${path}"
        else
            fail "Checksum mismatch: ${path}"
            log_error "  expected: ${sha256_expected:0:16}..."
            log_error "  actual:   ${sha256_actual:0:16}..."
            failed=$((failed + 1))
        fi
    done < <(jq -c '.files[]' "$INTEGRITY_MANIFEST" 2>/dev/null)

    log_info "Checksums: ${passed}/${total} passed, ${failed} failed, ${missing} missing"
}

# --- 3. Symlink Detection (FR-005) ---
check_symlinks() {
    log_step "Checking for symlinks in protected paths"

    if integrity_check_symlinks "$REPO_ROOT"; then
        log_info "No symlinks detected"
    else
        fail "Symlinks found in protected paths — see errors above"
    fi
}

# --- 4. Environment Variable Validation (FR-019) ---
check_env_vars() {
    log_step "Checking environment variables"

    if integrity_check_env_vars; then
        log_info "No dangerous environment variables set"
    else
        fail "Dangerous environment variables detected — see errors above"
    fi
}

# --- 5. Platform Version Match (FR-020) ---
check_platform_version() {
    log_step "Checking platform version"

    if [[ ! -f "$INTEGRITY_MANIFEST" ]]; then
        return
    fi

    local manifest_version
    manifest_version=$(jq -r '.platform_version // empty' "$INTEGRITY_MANIFEST" 2>/dev/null)

    if [[ -z "$manifest_version" ]]; then
        warn "No platform version recorded in manifest"
        return
    fi

    local current_version
    current_version=$(openclaw --version 2>/dev/null || echo "unknown")

    if [[ "$manifest_version" == "$current_version" ]]; then
        log_info "Platform version matches: ${current_version}"
    else
        fail "Platform version mismatch"
        log_error "  manifest: ${manifest_version}"
        log_error "  current:  ${current_version}"
    fi
}

# --- 6. Pending Drafts Schema Validation (FR-012) ---
check_pending_drafts() {
    log_step "Validating pending-drafts.json"

    if [[ ! -f "$PENDING_DRAFTS" ]]; then
        log_info "No pending-drafts.json (OK — no pending drafts)"
        return
    fi

    # Must be valid JSON
    if ! jq empty "$PENDING_DRAFTS" 2>/dev/null; then
        fail "pending-drafts.json is not valid JSON"
        return
    fi

    # Must be an array
    local type
    type=$(jq -r 'type' "$PENDING_DRAFTS" 2>/dev/null)
    if [[ "$type" != "array" ]]; then
        fail "pending-drafts.json must be a JSON array, got: ${type}"
        return
    fi

    # Validate each entry: required fields, no unexpected keys, content length
    local violations=0
    local allowed_keys='["id","type","content","image_path","status","created_at"]'
    local max_content_length=5000

    while IFS= read -r entry; do
        # Check required fields exist
        for field in id type content status created_at; do
            if [[ $(echo "$entry" | jq --arg f "$field" 'has($f)') != "true" ]]; then
                fail "pending-drafts entry missing required field: ${field}"
                violations=$((violations + 1))
            fi
        done

        # Check for unexpected keys (injection vector)
        local extra_keys
        extra_keys=$(echo "$entry" | jq -r --argjson allowed "$allowed_keys" '
            keys - $allowed | .[]
        ' 2>/dev/null)
        if [[ -n "$extra_keys" ]]; then
            fail "pending-drafts entry has unexpected keys: ${extra_keys}"
            violations=$((violations + 1))
        fi

        # Check content length (prevent payload stuffing)
        local content_len
        content_len=$(echo "$entry" | jq -r '.content | length' 2>/dev/null)
        if [[ "$content_len" -gt "$max_content_length" ]]; then
            fail "pending-drafts content exceeds ${max_content_length} chars (got ${content_len})"
            violations=$((violations + 1))
        fi
    done < <(jq -c '.[]' "$PENDING_DRAFTS" 2>/dev/null)

    if [[ $violations -eq 0 ]]; then
        local count
        count=$(jq 'length' "$PENDING_DRAFTS")
        log_info "pending-drafts.json valid (${count} entries)"
    fi
}

# --- 7. Monitoring Heartbeat Check (FR-024) ---
check_heartbeat() {
    log_step "Checking monitoring service heartbeat"

    if [[ ! -f "$INTEGRITY_HEARTBEAT" ]]; then
        warn "No heartbeat file — monitoring service may not be running"
        warn "  Run 'make monitor-setup' to install"
        return
    fi

    if integrity_check_heartbeat 120; then
        local pid
        pid=$(jq -r '.pid' "$INTEGRITY_HEARTBEAT" 2>/dev/null)
        log_info "Monitoring service alive (PID ${pid})"
    else
        warn "Monitoring heartbeat is stale (>120s) — service may be down"
    fi
}

# --- 8. Sandbox Configuration Check (FR-013, T017b) ---
# Warn but do not block — sandbox is an independent defense layer
check_sandbox_config() {
    log_step "Checking sandbox configuration"

    if [[ ! -f "$OPENCLAW_JSON" ]]; then
        warn "openclaw.json not found — cannot verify sandbox config"
        return
    fi

    local config
    config=$(jq '.' "$OPENCLAW_JSON" 2>/dev/null)
    if [[ -z "$config" ]]; then
        warn "openclaw.json is empty or invalid JSON"
        return
    fi

    local persona_mode
    persona_mode=$(echo "$config" | jq -r '
        .agents.list[] | select(.id == "linkedin-persona") | .sandbox.mode // empty
    ' 2>/dev/null)

    if [[ "$persona_mode" == "all" ]]; then
        log_info "linkedin-persona: sandbox mode = all (OK)"
    else
        warn "linkedin-persona: sandbox not configured (expected sandbox.mode = \"all\")"
        warn "  Run 'make sandbox-setup' to enable sandbox isolation"
    fi

    local extractor_mode
    extractor_mode=$(echo "$config" | jq -r '
        .agents.list[] | select(.id == "feed-extractor") | .sandbox.mode // empty
    ' 2>/dev/null)

    if [[ "$extractor_mode" == "all" ]]; then
        log_info "feed-extractor: sandbox mode = all (OK)"
    else
        warn "feed-extractor: sandbox not configured (expected sandbox.mode = \"all\")"
    fi

    local writable_dir="${HOME}/.openclaw/sandboxes/linkedin-persona/data"
    if [[ -d "$writable_dir" ]]; then
        log_info "Writable data directory exists: ${writable_dir}"
    else
        warn "Writable data directory missing: ${writable_dir}"
    fi
}

# --- 9. Skill Allowlist Verification (FR-027, FR-029, T034) ---
check_skill_allowlist() {
    log_step "Verifying skill allowlist"

    if [[ ! -f "$INTEGRITY_ALLOWLIST" ]]; then
        warn "Skill allowlist not found: ${INTEGRITY_ALLOWLIST}"
        warn "  Run 'make skillallow-add NAME=<skill>' to populate"
        return
    fi

    local skills_dir="${REPO_ROOT}/openclaw/skills"
    local openclaw_dir="${HOME}/.openclaw"
    local total=0
    local passed=0
    local failed=0
    local unapproved=0

    # Collect all SKILL.md files (repo + deployed)
    declare -A seen_skills
    local skill_files=()
    while IFS= read -r f; do
        skill_files+=("$f")
    done < <(find "$skills_dir" -name "SKILL.md" -type f 2>/dev/null)
    while IFS= read -r f; do
        skill_files+=("$f")
    done < <(find "${openclaw_dir}/agents" -path "*/skills/*/SKILL.md" -type f 2>/dev/null)

    for f in "${skill_files[@]}"; do
        local name
        name=$(basename "$(dirname "$f")")
        [[ -n "${seen_skills[$name]:-}" ]] && continue
        seen_skills[$name]=1
        total=$((total + 1))

        local content_hash
        content_hash=$(integrity_compute_sha256 "$f")

        local approved_hash
        approved_hash=$(jq -r --arg n "$name" \
            '.skills[] | select(.name == $n) | .content_hash // empty' \
            "$INTEGRITY_ALLOWLIST" 2>/dev/null)

        if [[ -z "$approved_hash" ]]; then
            fail "Unapproved skill: ${name} (not in allowlist)"
            unapproved=$((unapproved + 1))
        elif [[ "$content_hash" == "$approved_hash" ]]; then
            log_debug "Skill OK: ${name}"
            passed=$((passed + 1))
        else
            fail "Skill hash mismatch: ${name}"
            log_error "  allowlist: ${approved_hash:0:16}..."
            log_error "  installed: ${content_hash:0:16}..."
            failed=$((failed + 1))
        fi
    done

    if [[ $total -eq 0 ]]; then
        log_info "No skills installed"
    else
        log_info "Skills: ${passed}/${total} approved, ${failed} mismatched, ${unapproved} unapproved"
    fi
}

# --- 10. n8n Workflow Comparison (FR-018, T024) ---
check_n8n_workflows() {
    log_step "Comparing n8n workflows against version-controlled copies"

    local workflow_dir="${REPO_ROOT}/workflows"
    if [[ ! -d "$workflow_dir" ]]; then
        warn "No workflows/ directory found"
        return
    fi

    # Check if n8n container is running
    local container_name="n8n"
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container_name}$"; then
        warn "n8n container not running — skipping workflow comparison"
        return
    fi

    # Metadata keys to ignore when comparing (change on every save)
    local ignore_keys='.updatedAt, .createdAt, .versionId, .id, .meta'

    local compared=0
    local mismatched=0

    for repo_wf in "${workflow_dir}"/*.json; do
        local wf_name
        wf_name=$(basename "$repo_wf" .json)

        # Export workflow from n8n by name
        local n8n_wf
        n8n_wf=$(docker exec "$container_name" n8n export:workflow --all 2>/dev/null \
            | jq -c --arg name "$wf_name" '.[] | select(.name == $name) | del('"$ignore_keys"')' 2>/dev/null)

        if [[ -z "$n8n_wf" ]]; then
            log_debug "Workflow not found in n8n: ${wf_name} (may not be imported yet)"
            continue
        fi

        local repo_normalized
        repo_normalized=$(jq -c 'del('"$ignore_keys"')' "$repo_wf" 2>/dev/null)

        compared=$((compared + 1))

        if [[ "$n8n_wf" == "$repo_normalized" ]]; then
            log_debug "Workflow matches: ${wf_name}"
        else
            fail "Workflow mismatch: ${wf_name} (n8n differs from repo)"
            mismatched=$((mismatched + 1))
        fi
    done

    if [[ $compared -eq 0 ]]; then
        log_info "No workflows compared (n8n may have no matching workflows)"
    elif [[ $mismatched -eq 0 ]]; then
        log_info "All ${compared} compared workflows match"
    fi
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=true; shift ;;
            --agent) AGENT_ID="$2"; shift 2 ;;
            --debug) DEBUG=true; export DEBUG; shift ;;
            --help|-h)
                echo "Usage: scripts/integrity-verify.sh [--dry-run] [--agent <id>] [--debug]"
                exit 0
                ;;
            *) log_error "Unknown: $1"; exit 1 ;;
        esac
    done

    log_step "Integrity Verification"
    echo ""

    # Critical checks (errors block launch)
    check_manifest_signature
    check_file_checksums
    check_symlinks
    check_env_vars
    check_platform_version
    check_pending_drafts
    check_skill_allowlist

    # Advisory checks (warnings only)
    check_heartbeat
    check_sandbox_config
    check_n8n_workflows

    # Summary
    echo ""
    if [[ $ERRORS -gt 0 ]]; then
        log_error "Verification FAILED: ${ERRORS} error(s), ${WARNINGS} warning(s)"
        log_error "Agent launch blocked. Fix errors above and retry."
        exit 1
    elif [[ $WARNINGS -gt 0 ]]; then
        log_warn "Verification passed with ${WARNINGS} warning(s)"
    else
        log_info "All checks passed"
    fi

    if $DRY_RUN; then
        log_info "Dry run — not launching agent"
        exit 0
    fi

    # FR-014: exec directly into the agent process (eliminates TOCTOU window)
    log_info "Launching agent: ${AGENT_ID}"
    exec openclaw --agent "$AGENT_ID"
}

main "$@"
