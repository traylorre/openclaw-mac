#!/usr/bin/env bash
# integrity.sh — Shared library for workspace integrity operations
# Source this file, do not execute it directly.
# Usage: source "${SCRIPT_DIR}/lib/integrity.sh"
#
# Provides: manifest read/write, HMAC signing, SHA-256 checksums,
# protected file enumeration, symlink detection, lock state management.

# --- Constants (exported for use by scripts that source this file) ---
# shellcheck disable=SC2034
readonly INTEGRITY_MANIFEST="${HOME}/.openclaw/manifest.json"
# shellcheck disable=SC2034
readonly INTEGRITY_ALLOWLIST="${HOME}/.openclaw/skill-allowlist.json"
# shellcheck disable=SC2034
readonly INTEGRITY_LOCKSTATE="${HOME}/.openclaw/lock-state.json"
# shellcheck disable=SC2034
readonly INTEGRITY_HEARTBEAT="${HOME}/.openclaw/integrity-monitor-heartbeat.json"
# shellcheck disable=SC2034
readonly INTEGRITY_AUDIT_LOG="${HOME}/.openclaw/integrity-audit.log"
readonly INTEGRITY_KEYCHAIN_SERVICE="integrity-manifest-key"
readonly INTEGRITY_KEYCHAIN_ACCOUNT="openclaw"
readonly INTEGRITY_MANIFEST_VERSION=1
# shellcheck disable=SC2034
readonly INTEGRITY_GRACE_MINUTES=5

# --- Protected File List (FR-004) ---
# All file categories requiring integrity protection.
# T001 + T003: workspace, skill, orchestration, workflow, script, config, secret

_integrity_protected_file_patterns() {
    local repo_root="$1"
    local openclaw_dir="${HOME}/.openclaw"

    # Workspace files (agent bootstrap — injected every turn)
    find "${openclaw_dir}/agents" -maxdepth 2 -name "*.md" -type f 2>/dev/null

    # Skill files (loaded on demand)
    find "${openclaw_dir}/agents" -path "*/skills/*/SKILL.md" -type f 2>/dev/null

    # Orchestration files
    if [[ -f "${repo_root}/CLAUDE.md" ]]; then
        echo "${repo_root}/CLAUDE.md"
    fi

    # Workflow definitions
    find "${repo_root}/workflows" -name "*.json" -type f 2>/dev/null

    # Deployment scripts
    find "${repo_root}/scripts" -name "*.sh" -type f 2>/dev/null

    # Docker configuration
    for f in "${repo_root}/scripts/templates/docker-compose.yml" \
             "${repo_root}/scripts/templates/n8n-entrypoint.sh"; do
        [[ -f "$f" ]] && echo "$f"
    done

    # Secrets
    find "${repo_root}/scripts/templates/secrets" -type f 2>/dev/null

    # Configuration files
    for f in "${openclaw_dir}/openclaw.json" \
             "${openclaw_dir}/.env" \
             "${repo_root}/.env"; do
        [[ -f "$f" ]] && echo "$f"
    done

    # --- 012: Expanded Protection Surface (FR-001 through FR-006) ---

    # LLM routing configuration (FR-001)
    find "${openclaw_dir}/agents" -name "models.json" -type f 2>/dev/null

    # Agent session state (FR-002)
    find "${openclaw_dir}/agents" -path "*/.openclaw/workspace-state.json" -type f 2>/dev/null

    # Development tool permissions (FR-003)
    if [[ -f "${repo_root}/.claude/settings.local.json" ]]; then
        echo "${repo_root}/.claude/settings.local.json"
    fi

    # Old configuration backups (FR-004)
    for f in "${openclaw_dir}"/openclaw.json.bak*; do
        [[ -f "$f" ]] && echo "$f"
    done

    # Restore scripts (FR-006)
    find "${openclaw_dir}/restore-scripts" -type f 2>/dev/null

    # Integrity state files (rollback counter, enforcement config, hooks allowlist)
    for f in "${openclaw_dir}/manifest-sequence.json" \
             "${openclaw_dir}/enforcement.json" \
             "${openclaw_dir}/hooks-allowlist.json"; do
        [[ -f "$f" ]] && echo "$f"
    done

    # LaunchAgent plists (templates + deployed)
    find "${repo_root}/scripts/launchd" -name "*.plist" -type f 2>/dev/null
    find "${repo_root}/scripts/templates" -name "*.plist" -type f 2>/dev/null
}

integrity_list_protected_files() {
    local repo_root="$1"
    _integrity_protected_file_patterns "$repo_root" | sort -u
}

# --- SHA-256 Checksums ---

integrity_compute_sha256() {
    local file="$1"
    shasum -a 256 "$file" | awk '{print $1}'
}

# --- Symlink Detection (FR-005) ---

integrity_check_symlinks() {
    local repo_root="$1"
    local violations=0

    # Check enumerated protected files and their parent directories
    while IFS= read -r f; do
        if [[ -L "$f" ]]; then
            log_error "Symlink detected in protected path: ${f} -> $(readlink "$f")"
            violations=$((violations + 1))
        fi
        local dir
        dir=$(dirname "$f")
        while [[ "$dir" != "/" && "$dir" != "$HOME" ]]; do
            if [[ -L "$dir" ]]; then
                log_error "Symlink directory in protected path: ${dir} -> $(readlink "$dir")"
                violations=$((violations + 1))
                break
            fi
            dir=$(dirname "$dir")
        done
    done < <(integrity_list_protected_files "$repo_root")

    # Scan protected directories for ANY symlinks (catches planted files
    # that find -type f would miss, e.g. attacker replaces SOUL.md with a symlink)
    local openclaw_dir="${HOME}/.openclaw"
    local protected_dirs=(
        "${openclaw_dir}/agents"
        "${openclaw_dir}/sandboxes"
        "${repo_root}/workflows"
        "${repo_root}/scripts"
        "${repo_root}/scripts/templates/secrets"
    )
    for pdir in "${protected_dirs[@]}"; do
        [[ -d "$pdir" ]] || continue
        while IFS= read -r link; do
            log_error "Symlink found in protected directory: ${link} -> $(readlink "$link")"
            violations=$((violations + 1))
        done < <(find "$pdir" -type l 2>/dev/null)
    done

    return "$violations"
}

# --- HMAC Manifest Signing (FR-016) ---

integrity_get_signing_key() {
    security find-generic-password \
        -a "${INTEGRITY_KEYCHAIN_ACCOUNT}" \
        -s "${INTEGRITY_KEYCHAIN_SERVICE}" \
        -w 2>/dev/null
}

integrity_sign_manifest() {
    local manifest_body="$1"
    local key
    key=$(integrity_get_signing_key)
    if [[ -z "$key" ]]; then
        log_error "No manifest signing key in Keychain. Run: make integrity-keygen"
        return 1
    fi
    echo -n "$manifest_body" | openssl dgst -sha256 -hmac "$key" -hex 2>/dev/null | awk '{print $NF}'
}

integrity_verify_signature() {
    local manifest_file="$1"
    local stored_sig
    local body
    local computed_sig

    stored_sig=$(jq -r '.signature // empty' "$manifest_file" 2>/dev/null)
    if [[ -z "$stored_sig" ]]; then
        log_error "Manifest has no signature"
        return 1
    fi

    # Extract body (everything except the signature field)
    # ADV-015: --sort-keys ensures deterministic key ordering across jq versions
    body=$(jq --sort-keys -c 'del(.signature)' "$manifest_file" 2>/dev/null)
    computed_sig=$(integrity_sign_manifest "$body")

    if [[ "$stored_sig" != "$computed_sig" ]]; then
        log_error "Manifest signature mismatch — possible tampering"
        return 1
    fi
    return 0
}

# --- Manifest Read/Write ---

integrity_build_manifest() {
    local repo_root="$1"
    local manifest='{"version":'"${INTEGRITY_MANIFEST_VERSION}"'}'

    manifest=$(echo "$manifest" | jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '. + {created_at: $ts, updated_at: $ts}')

    # Platform version (FR-020)
    local platform_ver
    platform_ver=$(openclaw --version 2>/dev/null || echo "unknown")
    manifest=$(echo "$manifest" | jq --arg pv "$platform_ver" '. + {platform_version: $pv}')

    # Protected files
    local files_arr='[]'
    while IFS= read -r f; do
        local hash category locked
        hash=$(integrity_compute_sha256 "$f")
        category=$(integrity_categorize_file "$f" "$repo_root")
        locked=$(integrity_is_locked "$f")
        files_arr=$(echo "$files_arr" | jq \
            --arg path "$f" \
            --arg sha256 "$hash" \
            --arg cat "$category" \
            --argjson locked "$locked" \
            --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '. + [{"path": $path, "sha256": $sha256, "category": $cat, "locked": $locked, "locked_at": $ts}]')
    done < <(integrity_list_protected_files "$repo_root")

    manifest=$(echo "$manifest" | jq --argjson files "$files_arr" '. + {files: $files}')

    # Skill hashes in manifest (FR-028)
    if [[ -f "$INTEGRITY_ALLOWLIST" ]]; then
        local skills
        skills=$(jq -c '.skills // []' "$INTEGRITY_ALLOWLIST" 2>/dev/null)
        manifest=$(echo "$manifest" | jq --argjson skills "$skills" '. + {skills: $skills}')
    fi

    # Sign — ADV-015: --sort-keys for deterministic HMAC
    local body sig
    body=$(echo "$manifest" | jq --sort-keys -c '.')
    sig=$(integrity_sign_manifest "$body")
    manifest=$(echo "$manifest" | jq --arg sig "$sig" '. + {signature: $sig}')

    echo "$manifest" | jq '.'
}

integrity_categorize_file() {
    local file="$1"
    local repo_root="$2"

    case "$file" in
        */agents/*/skills/*/SKILL.md) echo "skill" ;;
        */agents/*.md)                echo "workspace" ;;
        */CLAUDE.md)                  echo "orchestration" ;;
        */workflows/*.json)           echo "workflow" ;;
        */scripts/*.sh)               echo "script" ;;
        */docker-compose.yml|*/n8n-entrypoint.sh) echo "config" ;;
        */secrets/*)                  echo "secret" ;;
        */.env|*/openclaw.json)       echo "config" ;;
        *)                            echo "other" ;;
    esac
}

integrity_is_locked() {
    local file="$1"
    # Check if uchg flag is set
    # macOS-specific: no alternative to ls -lO for BSD file flags
    # shellcheck disable=SC2010
    if ls -lO "$file" 2>/dev/null | grep -q "uchg"; then
        echo "true"
    else
        echo "false"
    fi
}

# --- Signed State File Operations (ADV-002, ADV-004) ---
# Generic sign/verify for state files (lock-state.json, heartbeat.json)
# All state files use the same HMAC key as the manifest.

integrity_sign_state_file() {
    local json_data="$1"
    local output_file="$2"

    local body sig
    body=$(echo "$json_data" | jq --sort-keys -c 'del(.signature)')
    sig=$(integrity_sign_manifest "$body")
    if [[ -z "$sig" ]]; then
        return 1
    fi

    local signed
    signed=$(echo "$json_data" | jq --arg sig "$sig" '. + {signature: $sig}')

    # ADV-011: Atomic write (mktemp + mv)
    local tmpfile
    tmpfile=$(mktemp "${output_file}.XXXXXX")
    if echo "$signed" | jq '.' > "$tmpfile"; then
        chmod 600 "$tmpfile"
        mv "$tmpfile" "$output_file"
    else
        rm -f "$tmpfile"
        return 1
    fi
}

integrity_verify_state_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        return 1
    fi

    local stored_sig body computed_sig
    stored_sig=$(jq -r '.signature // empty' "$file" 2>/dev/null)
    if [[ -z "$stored_sig" ]]; then
        return 1
    fi

    body=$(jq --sort-keys -c 'del(.signature)' "$file" 2>/dev/null)
    computed_sig=$(integrity_sign_manifest "$body")
    [[ "$stored_sig" == "$computed_sig" ]]
}

# --- Audit Log (ADV-006) ---
# Append-only log for all privileged operations. Survives lock/unlock cycles.

integrity_audit_log() {
    local action="$1"
    local details="${2:-}"
    local operator="${SUDO_USER:-$(whoami)}"

    # FR-014b: Compute hash of previous entry for hash chain
    local prev_hash="GENESIS"
    if [[ -f "$INTEGRITY_AUDIT_LOG" ]] && [[ -s "$INTEGRITY_AUDIT_LOG" ]]; then
        local last_line
        last_line=$(tail -1 "$INTEGRITY_AUDIT_LOG")
        if [[ -n "$last_line" ]]; then
            prev_hash=$(echo -n "$last_line" | shasum -a 256 | awk '{print $1}')
        fi
    fi

    # FR-011: Include all required fields + prev_hash for hash chain
    local entry
    entry=$(jq -n -c \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg action "$action" \
        --arg op "$operator" \
        --arg details "$details" \
        --argjson pid "$$" \
        --arg prev_hash "$prev_hash" \
        '{timestamp: $ts, action: $action, operator: $op, pid: $pid, details: $details, prev_hash: $prev_hash}')

    # Append to audit log (create if needed)
    if ! echo "$entry" >> "$INTEGRITY_AUDIT_LOG" 2>/dev/null; then
        # FR-009 edge case: detect write failure (disk full, permissions)
        log_error "CRITICAL: Failed to write audit log entry — disk full or permissions issue" >&2
        log_error "  Action: ${action}, Details: ${details}" >&2
        return 1
    fi
    chmod 600 "$INTEGRITY_AUDIT_LOG" 2>/dev/null || true
}

# FR-014b: Verify audit log hash chain integrity
integrity_verify_audit_chain() {
    if [[ ! -f "$INTEGRITY_AUDIT_LOG" ]]; then
        return 0  # No log = no violations
    fi

    local violations=0
    local expected_prev="GENESIS"
    local line_num=0

    while IFS= read -r line; do
        line_num=$((line_num + 1))
        [[ -z "$line" ]] && continue

        # Extract prev_hash from this entry
        local entry_prev
        entry_prev=$(echo "$line" | jq -r '.prev_hash // empty' 2>/dev/null)

        if [[ -z "$entry_prev" ]]; then
            log_error "Audit log line ${line_num}: missing prev_hash field"
            violations=$((violations + 1))
        elif [[ "$entry_prev" != "$expected_prev" ]]; then
            log_error "Audit log line ${line_num}: hash chain broken"
            log_error "  expected prev_hash: ${expected_prev:0:16}..."
            log_error "  actual prev_hash:   ${entry_prev:0:16}..."
            violations=$((violations + 1))
        fi

        # Compute hash of this line for next iteration
        expected_prev=$(echo -n "$line" | shasum -a 256 | awk '{print $1}')
    done < "$INTEGRITY_AUDIT_LOG"

    if [[ $violations -gt 0 ]]; then
        log_error "Audit log chain verification: ${violations} violation(s) in ${line_num} entries"
    fi
    return "$violations"
}

# --- Lock State Management (FR-023, ADV-002) ---

integrity_record_unlock() {
    local file="$1"
    # ADV-017: Use SUDO_USER for operator identity, not whoami
    local operator="${SUDO_USER:-$(whoami)}"
    local entries='[]'

    if [[ -f "$INTEGRITY_LOCKSTATE" ]]; then
        # ADV-002: Verify signature before trusting existing state
        if integrity_verify_state_file "$INTEGRITY_LOCKSTATE"; then
            entries=$(jq -c '.entries // []' "$INTEGRITY_LOCKSTATE" 2>/dev/null || echo '[]')
        else
            log_warn "Lock state signature invalid — resetting"
            entries='[]'
        fi
    fi

    entries=$(echo "$entries" | jq \
        --arg path "$file" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg op "$operator" \
        --argjson timeout "$INTEGRITY_GRACE_MINUTES" \
        '. + [{"path": $path, "unlocked_at": $ts, "timeout_minutes": $timeout, "operator": $op}]')

    local state_json
    state_json=$(jq -n --argjson entries "$entries" '{entries: $entries}')
    integrity_sign_state_file "$state_json" "$INTEGRITY_LOCKSTATE"

    # ADV-006: Append to audit log
    integrity_audit_log "unlock" "$file"
}

integrity_clear_lockstate() {
    local state_json
    state_json=$(jq -n '{entries: []}')
    integrity_sign_state_file "$state_json" "$INTEGRITY_LOCKSTATE"

    # ADV-006: Append to audit log
    integrity_audit_log "lock_all" "cleared lock state, all files re-locked"
}

integrity_is_in_grace_period() {
    local file="$1"
    if [[ ! -f "$INTEGRITY_LOCKSTATE" ]]; then
        return 1
    fi

    # ADV-002: Verify signature before trusting grace period
    if ! integrity_verify_state_file "$INTEGRITY_LOCKSTATE"; then
        log_error "Lock state signature invalid — refusing to trust grace period"
        return 1
    fi

    local now_epoch
    now_epoch=$(date +%s)

    # Find matching entry, check if within grace period
    local entry
    entry=$(jq -r --arg path "$file" '.entries[] | select(.path == $path) | .unlocked_at' "$INTEGRITY_LOCKSTATE" 2>/dev/null)

    if [[ -z "$entry" ]]; then
        return 1
    fi

    local unlock_epoch grace_end
    unlock_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$entry" +%s 2>/dev/null || echo 0)
    grace_end=$((unlock_epoch + INTEGRITY_GRACE_MINUTES * 60))

    if [[ "$now_epoch" -lt "$grace_end" ]]; then
        return 0  # In grace period
    fi
    return 1  # Grace period expired
}

# --- Environment Variable Validation (FR-019, ADV-007) ---

integrity_check_env_vars() {
    local violations=0

    # Dangerous env vars that should NOT be set (ADV-007: expanded list)
    local dangerous_vars=(
        DYLD_INSERT_LIBRARIES
        DYLD_FRAMEWORK_PATH
        DYLD_LIBRARY_PATH
        NODE_OPTIONS
        LD_PRELOAD
    )

    for var in "${dangerous_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            log_error "Dangerous environment variable set: ${var}=${!var}"
            violations=$((violations + 1))
        fi
    done

    # HOME must point to expected location (ADV-007)
    local expected_home
    expected_home=$(dscl . -read "/Users/$(whoami)" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
    if [[ -n "$expected_home" && "$HOME" != "$expected_home" ]]; then
        log_error "HOME override detected: ${HOME} (expected ${expected_home})"
        violations=$((violations + 1))
    fi

    # TMPDIR must be system default or unset (FR-035)
    if [[ -n "${TMPDIR:-}" ]]; then
        case "$TMPDIR" in
            /tmp|/tmp/|/private/tmp|/private/tmp/|/var/folders/*)
                ;; # macOS default locations are safe
            *)
                log_error "TMPDIR override detected: ${TMPDIR} (expected /tmp, /private/tmp, or /var/folders/*)"
                violations=$((violations + 1))
                ;;
        esac
    fi

    return "$violations"
}

# --- Heartbeat (FR-024, ADV-004) ---

integrity_write_heartbeat() {
    local files_watched="$1"
    local hb_json
    hb_json=$(jq -n \
        --argjson pid "$$" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --argjson count "$files_watched" \
        '{pid: $pid, timestamp: $ts, files_watched: $count}')

    # ADV-004: Sign heartbeat with HMAC
    integrity_sign_state_file "$hb_json" "$INTEGRITY_HEARTBEAT"
}

integrity_check_heartbeat() {
    local max_age_seconds="${1:-60}"

    if [[ ! -f "$INTEGRITY_HEARTBEAT" ]]; then
        return 1
    fi

    # ADV-004: Verify heartbeat signature
    if ! integrity_verify_state_file "$INTEGRITY_HEARTBEAT"; then
        log_error "Heartbeat signature invalid — possible forgery"
        return 1
    fi

    local ts now_epoch hb_epoch
    ts=$(jq -r '.timestamp' "$INTEGRITY_HEARTBEAT" 2>/dev/null)
    now_epoch=$(date +%s)
    hb_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null || echo 0)

    local age=$((now_epoch - hb_epoch))
    if [[ "$age" -gt "$max_age_seconds" ]]; then
        return 1
    fi
    return 0
}
