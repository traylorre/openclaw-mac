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
readonly INTEGRITY_TMP_DIR="${HOME}/.openclaw/tmp"

# --- Phase 4B T001: Trap save/restore helpers (FR-010) ---
_integrity_save_err_trap() {
    _SAVED_ERR_TRAP=$(trap -p ERR 2>/dev/null || true)
}
_integrity_restore_err_trap() {
    if [[ -n "${_SAVED_ERR_TRAP:-}" ]]; then
        eval "$_SAVED_ERR_TRAP"
    else
        trap - ERR 2>/dev/null || true
    fi
    unset _SAVED_ERR_TRAP
}

# --- Phase 4B T002: Lock path validator (FR-044) ---
_integrity_validate_lock_path() {
    local path="$1"
    if [[ -z "$path" ]]; then
        echo "CRITICAL: empty lock path passed to rm -rf" >&2
        return 1
    fi
    if [[ "$path" != *"integrity-audit.log.lock"* ]]; then
        echo "CRITICAL: unexpected lock path: ${path}" >&2
        return 1
    fi
    return 0
}

# --- Phase 4: Secure temp directory initialization (T003, FR-006, FR-027) ---
_integrity_init_tmp_dir() {
    # Validate ~/.openclaw/ and parents are not symlinks
    local dir="${HOME}/.openclaw"
    while [[ "$dir" != "/" && "$dir" != "$HOME" ]]; do
        if [[ -L "$dir" ]]; then
            echo "CRITICAL: directory_symlink_detected: ${dir} -> $(readlink "$dir")" >&2
            return 1
        fi
        dir=$(dirname "$dir")
    done

    if [[ ! -d "$INTEGRITY_TMP_DIR" ]]; then
        mkdir -p "$INTEGRITY_TMP_DIR"
        chmod 700 "$INTEGRITY_TMP_DIR"
    fi

    # Verify mode is 700
    local mode
    mode=$(stat -f '%Lp' "$INTEGRITY_TMP_DIR" 2>/dev/null)
    if [[ "$mode" != "700" ]]; then
        chmod 700 "$INTEGRITY_TMP_DIR"
    fi
}
# Initialize on source
_INTEGRITY_INIT_OK=false
_integrity_init_tmp_dir && _INTEGRITY_INIT_OK=true

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

    # Container security state files (012 Phase 3: TP3-001)
    for f in "${openclaw_dir}/container-security-config.json" \
             "${openclaw_dir}/container-verify-state.json"; do
        [[ -f "$f" ]] && echo "$f"
    done

    # --- Phase 4: Expanded Protection Surface (T037-T039, FR-017/018/019) ---

    # T037: VCS configuration (FR-017) — always include
    if [[ -f "${repo_root}/.git/config" ]]; then
        echo "${repo_root}/.git/config"
    fi

    # T038: n8n workflow definitions (FR-018) — existence-gated
    if [[ -d "${repo_root}/n8n/workflows" ]]; then
        find "${repo_root}/n8n/workflows" -maxdepth 1 -name "*.json" -type f 2>/dev/null
    fi

    # T039: Agent constitution (FR-019) — existence-gated
    if [[ -f "${repo_root}/.specify/memory/constitution.md" ]]; then
        echo "${repo_root}/.specify/memory/constitution.md"
    fi

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

    [[ $violations -gt 0 ]] && return 1 || return 0
}

# --- HMAC Manifest Signing (FR-016) ---

integrity_get_signing_key() {
    local key
    key=$(security find-generic-password \
        -a "${INTEGRITY_KEYCHAIN_ACCOUNT}" \
        -s "${INTEGRITY_KEYCHAIN_SERVICE}" \
        -w 2>/dev/null)
    if [[ -z "$key" ]]; then
        echo "CRITICAL: HMAC key unavailable — Keychain locked or key missing" >&2
        return 1
    fi
    echo "$key"
}

integrity_sign_manifest() {
    if [[ "${_INTEGRITY_INIT_OK:-}" != "true" ]]; then
        echo "CRITICAL: integrity library not initialized" >&2
        return 1
    fi
    local manifest_body="$1"
    local key
    key=$(integrity_get_signing_key)
    if [[ -z "$key" ]]; then
        log_error "No manifest signing key in Keychain. Run: make integrity-keygen"
        return 1
    fi
    # T018: Mitigate key exposure — key through temp file (FR-023, RD-015)
    local _hmac_keyfile
    _hmac_keyfile=$(mktemp "${INTEGRITY_TMP_DIR}/hmac-XXXXXX")
    chmod 600 "$_hmac_keyfile"
    printf '%s' "$key" > "$_hmac_keyfile"
    local _hmac_key_val
    _hmac_key_val=$(cat "$_hmac_keyfile")
    rm -f "$_hmac_keyfile"
    echo -n "$manifest_body" | openssl dgst -sha256 -hmac "$_hmac_key_val" -hex 2>/dev/null | awk '{print $NF}'
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
    if [[ "${_INTEGRITY_INIT_OK:-}" != "true" ]]; then
        echo "CRITICAL: integrity library not initialized" >&2
        return 1
    fi
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

    # T047: Use safe atomic write (FR-005)
    local content
    content=$(echo "$signed" | jq '.')
    if ! _integrity_safe_atomic_write "$output_file" "$content"; then
        return 1
    fi
    chmod 600 "$output_file"
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
    if [[ "${_INTEGRITY_INIT_OK:-}" != "true" ]]; then
        echo "CRITICAL: integrity library not initialized" >&2
        return 1
    fi
    local action="$1"
    local details="${2:-}"

    # T010: Action validation (FR-023)
    if ! [[ "$action" =~ ^[a-z][a-z0-9_]{2,48}$ ]]; then
        echo "ERROR: Invalid audit log action: ${action}" >&2
        return 1
    fi

    local operator="${SUDO_USER:-$(whoami)}"
    local _audit_lockdir="${INTEGRITY_AUDIT_LOG}.lock"
    local _audit_lock_acquired=false

    local _lock_attempt
    for _lock_attempt in $(seq 1 20); do
        if mkdir "$_audit_lockdir" 2>/dev/null; then
            echo "${BASHPID:-$$} $(ps -o lstart= -p "${BASHPID:-$$}" 2>/dev/null)" > "$_audit_lockdir/pid" 2>/dev/null
            _audit_lock_acquired=true
            # FR-013: Signal trap for lock cleanup (INT/TERM only — explicit release handles normal path)
            # shellcheck disable=SC2064
            trap "rm -f '${_audit_lockdir}/pid' 2>/dev/null; rmdir '${_audit_lockdir}' 2>/dev/null || true" INT TERM
            break
        fi
        # PID-based stale detection (FR-029)
        if [[ -d "$_audit_lockdir" ]]; then
            if [[ -f "$_audit_lockdir/pid" ]] && [[ -s "$_audit_lockdir/pid" ]]; then
                local _lock_pid _lock_start _current_start
                read -r _lock_pid _lock_start < "$_audit_lockdir/pid" 2>/dev/null || true
                if [[ -n "$_lock_pid" ]]; then
                    _current_start=$(ps -o lstart= -p "$_lock_pid" 2>/dev/null || true)
                    if [[ -z "$_current_start" ]] || [[ "$_current_start" != *"$_lock_start"* ]]; then
                        # PID not running or recycled — stale lock
                        if _integrity_validate_lock_path "$_audit_lockdir"; then
                            rm -rf "$_audit_lockdir"
                        fi
                        continue
                    fi
                fi
            else
                # Missing/empty PID file — stale after 30s
                local _lock_age
                _lock_age=$(( $(date +%s) - $(stat -f '%m' "$_audit_lockdir" 2>/dev/null || echo 0) ))
                if [[ $_lock_age -gt 30 ]]; then
                    if _integrity_validate_lock_path "$_audit_lockdir"; then
                        rm -rf "$_audit_lockdir"
                    fi
                    continue
                fi
            fi
        fi
        sleep 0.2
    done

    # If lock acquisition failed after all retries, warn but still write (audit log must not be lost)
    if ! $_audit_lock_acquired; then
        echo "WARNING: audit log lock acquisition failed after 5 retries — writing without lock" >&2
    fi

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
    local _write_rc=0
    if ! echo "$entry" >> "$INTEGRITY_AUDIT_LOG"; then
        # FR-009 edge case: detect write failure (disk full, permissions)
        log_error "CRITICAL: Failed to write audit log entry — disk full or permissions issue" >&2
        log_error "  Action: ${action}, Details: ${details}" >&2
        _write_rc=1
    fi
    if ! chmod 600 "$INTEGRITY_AUDIT_LOG" 2>/dev/null; then
        log_error "Failed to set permissions on audit log" >&2
        _write_rc=1
    fi

    # T016: F_FULLFSYNC with explicit fallback (FR-041)
    if command -v python3 &>/dev/null; then
        python3 -c "import os,fcntl,sys; fd=os.open(sys.argv[1],os.O_RDONLY); fcntl.fcntl(fd,51); os.close(fd)" "$INTEGRITY_AUDIT_LOG" 2>/dev/null || {
            log_error "F_FULLFSYNC failed, falling back to sync" >&2
            sync
        }
    else
        log_error "python3 not available for F_FULLFSYNC, falling back to sync" >&2
        sync
    fi

    # Release lock and clear trap
    if $_audit_lock_acquired; then
        rm -f "$_audit_lockdir/pid" 2>/dev/null
        rmdir "$_audit_lockdir" 2>/dev/null || true
        _audit_lock_acquired=false
        trap - INT TERM 2>/dev/null || true
    fi

    return "$_write_rc"
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
        return 1
    fi
    return 0
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
            entries=$(jq -c '.entries // []' "$INTEGRITY_LOCKSTATE") || {
                log_warn "Failed to parse verified lock state — resetting entries"
                entries='[]'
            }
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
    unlock_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$entry" +%s 2>/dev/null)
    if [[ -z "$unlock_epoch" ]]; then
        log_error "Failed to parse unlock timestamp: ${entry}" >&2
        return 1
    fi
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

    # T011: TMPDIR validation with .. rejection and canonicalization (FR-021, FR-022)
    if [[ -n "${TMPDIR:-}" ]]; then
        # FR-021: Reject paths containing .. as a component
        if [[ "$TMPDIR" == *".."* ]]; then
            log_error "TMPDIR contains path traversal component (..): ${TMPDIR}"
            violations=$((violations + 1))
        elif ! [[ "$TMPDIR" =~ ^(/tmp|/private/tmp|/var/folders/[a-zA-Z0-9_+]{2}/[^/]+/T)(/.*)?$ ]]; then
            log_error "TMPDIR override detected: ${TMPDIR} (does not match allowed macOS paths)"
            violations=$((violations + 1))
        else
            # FR-022: Canonicalize and re-validate
            local _canonical_tmpdir
            _canonical_tmpdir=$(cd "$TMPDIR" 2>/dev/null && pwd -P) || true
            if [[ -n "$_canonical_tmpdir" ]] && ! [[ "$_canonical_tmpdir" =~ ^(/tmp|/private/tmp|/var/folders/[a-zA-Z0-9_+]{2}/[^/]+/T)(/.*)?$ ]]; then
                log_error "TMPDIR canonical path does not match allowed paths: ${_canonical_tmpdir} (original: ${TMPDIR})"
                violations=$((violations + 1))
            fi
        fi
    fi

    [[ $violations -gt 0 ]] && return 1 || return 0
}

# --- Phase 4 T040: Permission verification (FR-020, FR-028, FR-041) ---
_integrity_check_permissions() {
    local repo_root="$1"
    local violations=0

    # Check secret files for mode 600
    local secrets_dir="${repo_root}/scripts/templates/secrets"
    if [[ -d "$secrets_dir" ]]; then
        while IFS= read -r secret_file; do
            [[ -z "$secret_file" ]] && continue
            local mode
            mode=$(stat -f '%Lp' "$secret_file" 2>/dev/null)

            # T040/FR-041: Check if bind-mounted in Docker — use 640 if so
            local expected_mode="600"
            if [[ -f "${repo_root}/scripts/templates/docker-compose.yml" ]]; then
                if grep -qF "$(basename "$secret_file")" "${repo_root}/scripts/templates/docker-compose.yml" 2>/dev/null; then
                    expected_mode="640"
                fi
            fi

            if [[ "$mode" != "$expected_mode" ]]; then
                echo "secret_file_overly_permissive: ${secret_file} (mode=${mode}, expected=${expected_mode})" >&2
                violations=$((violations + 1))
            fi
        done < <(find "$secrets_dir" -type f 2>/dev/null)
    fi

    # Check audit directories for mode 700
    local audit_dirs=(
        "${HOME}/.openclaw/logs"
        "${HOME}/.openclaw/reports"
    )
    for adir in "${audit_dirs[@]}"; do
        if [[ -d "$adir" ]]; then
            local mode
            mode=$(stat -f '%Lp' "$adir" 2>/dev/null)
            if [[ "$mode" != "700" ]]; then
                echo "audit_data_world_readable: ${adir} (mode=${mode}, expected=700)" >&2
                violations=$((violations + 1))
            fi
        fi
    done

    [[ $violations -gt 0 ]] && return 1 || return 0
}

# --- Phase 4 T041: Docker socket permission check (FR-034) ---
_integrity_check_docker_socket() {
    local socket_path
    socket_path="${HOME}/.colima/default/docker.sock"

    if [[ ! -S "$socket_path" ]]; then
        # Try to resolve from Docker context
        socket_path=$(integrity_docker_socket_path 2>/dev/null)
    fi

    if [[ -z "$socket_path" ]] || [[ ! -S "$socket_path" ]]; then
        return 0  # No socket found — nothing to check
    fi

    local mode owner
    mode=$(stat -f '%Lp' "$socket_path" 2>/dev/null)
    owner=$(stat -f '%Su' "$socket_path" 2>/dev/null)
    local current_user
    current_user=$(whoami)

    if [[ "$mode" != "600" ]] || [[ "$owner" != "$current_user" ]]; then
        echo "docker_socket_permissions: ${socket_path} (mode=${mode}, owner=${owner}, expected=600/${current_user})" >&2
        return 1
    fi
    return 0
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
    hb_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null)
    if [[ -z "$hb_epoch" ]]; then
        return 1  # Cannot determine heartbeat age
    fi

    local age=$((now_epoch - hb_epoch))
    if [[ "$age" -gt "$max_age_seconds" ]]; then
        return 1
    fi
    return 0
}

# ============================================================================
# --- Container & Orchestration Integrity (012 Phase 3) ---
# Defense-in-depth verification for the n8n Docker container.
# Implements FR-P3-001 through FR-P3-039.
# ============================================================================

# shellcheck disable=SC2034
readonly INTEGRITY_CONTAINER_CONFIG="${HOME}/.openclaw/container-security-config.json"
# shellcheck disable=SC2034
readonly INTEGRITY_CONTAINER_VERIFY_STATE="${HOME}/.openclaw/container-verify-state.json"

# --- TP3-002: Default container security configuration ---

_integrity_default_container_config() {
    jq -n '{
        min_n8n_version: "1.121.0",
        min_n8n_version_reason: "CVE-2026-21858 (CVSS 10.0), CVE-2026-27495 (CVSS 9.4)",
        container_name_pattern: "n8n",
        expected_runtime_config: {
            privileged: false,
            cap_drop: ["ALL"],
            network_mode_not: "host",
            readonly_rootfs: true,
            no_new_privileges: true,
            seccomp_not_unconfined: true,
            user_not_root: true,
            no_docker_socket: true,
            ports_localhost_only: true,
            required_env: {
                NODES_EXCLUDE: "[\"n8n-nodes-base.executeCommand\",\"n8n-nodes-base.ssh\",\"n8n-nodes-base.localFileTrigger\"]",
                N8N_RESTRICT_FILE_ACCESS_TO: "/home/node/.n8n"
            }
        },
        drift_safe_paths: ["/tmp", "/var/tmp", "/home/node/.cache", "/home/node/.local", "/run", "/data", "/entrypoint.sh", "/home", "/var"]
    }'
}

# --- TP3-003: Container discovery (FR-P3-036) ---

integrity_discover_container() {
    local pattern="${1:-}"

    # Read pattern from config if not provided
    if [[ -z "$pattern" ]]; then
        if [[ -f "$INTEGRITY_CONTAINER_CONFIG" ]]; then
            pattern=$(jq -r '.container_name_pattern // "n8n"' "$INTEGRITY_CONTAINER_CONFIG" 2>/dev/null)
        fi
        pattern="${pattern:-n8n}"
    fi

    # T012: Validate container name pattern (FR-025)
    if ! _integrity_validate_container_name "$pattern"; then
        # Migration: invalid config value → fall back to default "n8n"
        echo "WARNING: Container name pattern failed validation, falling back to 'n8n'" >&2
        pattern="n8n"
    fi

    # Check Docker availability
    if ! command -v docker &>/dev/null; then
        echo "Docker CLI not found" >&2
        return 1
    fi

    local ids
    # T004: Timeout-bounded docker ps (FR-003)
    ids=$(integrity_run_with_timeout 10 docker ps -q --filter "name=${pattern}" 2>/dev/null)

    if [[ -z "$ids" ]]; then
        echo "No container matching '${pattern}' is running" >&2
        return 1
    fi

    # Validate output: must be hex container IDs, not error messages
    local validated_ids=""
    local count=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^[0-9a-f]{12,64}$ ]]; then
            validated_ids="${validated_ids}${line}"$'\n'
            count=$((count + 1))
        else
            echo "Docker returned unexpected output: ${line}" >&2
            return 1
        fi
    done <<< "$ids"

    if [[ $count -eq 0 ]]; then
        echo "No valid container ID in docker output" >&2
        return 1
    fi

    if [[ $count -gt 1 ]]; then
        echo "CRITICAL: Multiple containers match '${pattern}' — ambiguous discovery" >&2
        echo "$validated_ids" >&2
        integrity_audit_log "container_discovery_ambiguous" \
            "pattern=${pattern}, count=${count}" || true
        return 2
    fi

    # Single valid match
    echo "${validated_ids}" | head -1 | tr -d '\n'
    return 0
}

# --- TP3-004: Atomic container snapshot (FR-P3-012b) ---

integrity_capture_container_snapshot() {
    local cid="$1"

    if [[ -z "$cid" ]]; then
        echo "Container ID required" >&2
        return 1
    fi

    local snapshot
    # T003: Timeout-bounded docker inspect (FR-002)
    snapshot=$(integrity_run_with_timeout 30 docker inspect "$cid" --format '{{json .}}' 2>/dev/null)
    local rc=$?

    if [[ $rc -ne 0 ]] || [[ -z "$snapshot" ]]; then
        echo "Failed to inspect container ${cid}" >&2
        return 1
    fi

    # Validate the output is parseable JSON (not a Docker error message)
    if ! echo "$snapshot" | jq empty 2>/dev/null; then
        echo "Container snapshot is not valid JSON for ${cid}" >&2
        return 1
    fi

    echo "$snapshot"
    return 0
}

# --- TP3-005: Container ID verification (FR-P3-037) ---

integrity_verify_container_id() {
    local expected_id="$1"
    local current_id="$2"

    if [[ "$expected_id" == "$current_id" ]]; then
        return 0
    fi

    integrity_audit_log "container_id_changed" "expected=${expected_id:0:12}, actual=${current_id:0:12}" || true
    return 1
}

# --- TP3-006: Semantic version comparison (FR-P3-004) ---

integrity_version_gte() {
    local current="$1"
    local minimum="$2"

    if [[ -z "$current" ]] || [[ -z "$minimum" ]]; then
        return 1  # Fail safe on empty input
    fi

    # Split on '.' into arrays
    IFS='.' read -ra cur_parts <<< "$current"
    IFS='.' read -ra min_parts <<< "$minimum"

    # Pad to 3 segments
    while [[ ${#cur_parts[@]} -lt 3 ]]; do cur_parts+=("0"); done
    while [[ ${#min_parts[@]} -lt 3 ]]; do min_parts+=("0"); done

    # Compare each segment numerically
    local i
    for i in 0 1 2; do
        local c="${cur_parts[$i]}"
        local m="${min_parts[$i]}"

        # Non-numeric → fail safe
        if ! [[ "$c" =~ ^[0-9]+$ ]] || ! [[ "$m" =~ ^[0-9]+$ ]]; then
            return 1
        fi

        if [[ "$c" -gt "$m" ]]; then
            return 0
        elif [[ "$c" -lt "$m" ]]; then
            return 1
        fi
    done

    # All segments equal → current == minimum → gte is true
    return 0
}

# --- TP3-007: Container baseline capture (FR-P3-001, FR-P3-002, FR-P3-013, FR-P3-025) ---

integrity_capture_container_baseline() {
    local cid="$1"
    local baseline='{}'

    # Image digest and name from snapshot
    local snapshot
    snapshot=$(integrity_capture_container_snapshot "$cid")
    if [[ -z "$snapshot" ]]; then
        echo "Failed to capture container snapshot" >&2
        return 1
    fi

    local image_digest image_name
    image_digest=$(echo "$snapshot" | jq -r '.Image // empty')
    image_name=$(echo "$snapshot" | jq -r '.Config.Image // empty')

    baseline=$(echo "$baseline" | jq \
        --arg digest "$image_digest" \
        --arg name "$image_name" \
        '. + {container_image_digest: $digest, container_image_name: $name}')

    # n8n version — trap "no such container" explicitly
    local n8n_version=""
    local exec_output
    exec_output=$(integrity_run_with_timeout 10 docker exec "$cid" n8n --version 2>&1)
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        if echo "$exec_output" | grep -qi "no such container"; then
            echo "CRITICAL: Container disappeared during baseline capture" >&2
            integrity_audit_log "container_disappeared" "during baseline capture, cid=${cid:0:12}"
            return 1
        fi
        echo "Warning: Could not get n8n version: ${exec_output}" >&2
    else
        # n8n --version may output "1.72.1" or "n8n 1.72.1" — extract version
        n8n_version=$(echo "$exec_output" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    fi
    baseline=$(echo "$baseline" | jq --arg ver "$n8n_version" '. + {container_n8n_version: $ver}')

    # Credential names via n8n REST API from host
    # Use --config to avoid leaking API key in process list
    local cred_json=""
    local cred_enum_failed=false
    local api_key
    api_key=$(security find-generic-password -a "openclaw" -s "n8n-api-key" -w 2>/dev/null)
    if [[ -z "$api_key" ]]; then
        echo "Warning: No n8n API key in Keychain (n8n-api-key) — cannot enumerate credentials" >&2
        cred_enum_failed=true
    else
        # T044: Fix credential exposure — use temp file (FR-026)
        # T030: Credential trap protection (FR-015, FR-025)
        local _prev_exit_trap
        _prev_exit_trap=$(trap -p EXIT 2>/dev/null || true)
        local _cred_tmpfile
        _cred_tmpfile=$(_integrity_safe_credential_write "$api_key")
        trap "rm -f '$_cred_tmpfile' 2>/dev/null; ${_prev_exit_trap:+eval \"$_prev_exit_trap\"}" EXIT
        local api_response
        api_response=$(curl -s --config "$_cred_tmpfile" \
            "http://localhost:5678/api/v1/credentials" --max-time 10)
        rm -f "$_cred_tmpfile"
        # Restore original EXIT trap
        if [[ -n "$_prev_exit_trap" ]]; then
            eval "$_prev_exit_trap"
        else
            trap - EXIT
        fi
        if [[ -z "$api_response" ]]; then
            echo "Warning: n8n API returned empty response — is n8n running?" >&2
            cred_enum_failed=true
        elif ! echo "$api_response" | jq '.data' &>/dev/null; then
            echo "Warning: n8n API credential response not valid JSON" >&2
            cred_enum_failed=true
        else
            cred_json=$(echo "$api_response" | jq -c '[.data[].name // empty] | sort')
            if [[ -z "$cred_json" ]]; then
                echo "Warning: jq failed to extract credential names" >&2
                cred_enum_failed=true
            fi
        fi
    fi
    # Only include credentials in baseline if enumeration succeeded
    # An empty-but-successful result [] is different from a failed enumeration
    if $cred_enum_failed; then
        echo "Warning: Credential baseline not recorded — re-run deploy when n8n is accessible" >&2
    else
        baseline=$(echo "$baseline" | jq --argjson creds "$cred_json" '. + {expected_credentials: $creds}')
    fi

    # Community node packages — cat all package.json files in one exec, parse on host
    # (container doesn't have jq)
    local nodes_json='[]'
    local pkg_output
    pkg_output=$(integrity_run_with_timeout 30 docker exec "$cid" sh -c '
        for f in /home/node/.n8n/nodes/node_modules/n8n-nodes-*/package.json; do
            [ -f "$f" ] && cat "$f" && printf "\n---PKG_DELIMITER---\n"
        done' 2>/dev/null)
    rc=$?
    if [[ $rc -ne 0 ]] && ! integrity_run_with_timeout 5 docker ps -q --filter "id=${cid}" 2>/dev/null | grep -q .; then
        echo "CRITICAL: Container disappeared during node enumeration" >&2
        integrity_audit_log "container_disappeared" "during node enum, cid=${cid:0:12}" || true
        return 1
    fi
    if [[ -n "$pkg_output" ]] && [[ "$pkg_output" != *"No such file"* ]]; then
        # Split on delimiter, extract name+version from each block on the host
        local tmp_nodes='[]'
        local IFS_backup="$IFS"
        local block=""
        while IFS= read -r line; do
            if [[ "$line" == "---PKG_DELIMITER---" ]]; then
                if [[ -n "$block" ]]; then
                    # T013: Validate each segment as JSON before extraction (FR-012)
                    local pname pver
                    pname=$(_integrity_validate_json '.name // error("missing .name")' "$block" "community_node_parse" 2>/dev/null) || {
                        echo "WARNING: Skipping invalid community node block (${block:0:200})" >&2
                        block=""
                        continue
                    }
                    pver=$(echo "$block" | jq -r '.version // empty' 2>/dev/null)
                    if [[ -n "$pname" ]]; then
                        tmp_nodes=$(echo "$tmp_nodes" | jq --arg n "$pname" --arg v "$pver" \
                            '. + [{"name": $n, "version": $v}]')
                    fi
                fi
                block=""
            else
                block="${block}${line}"$'\n'
            fi
        done <<< "$pkg_output"
        IFS="$IFS_backup"
        nodes_json="$tmp_nodes"
    fi
    baseline=$(echo "$baseline" | jq --argjson nodes "$nodes_json" '. + {expected_community_nodes: $nodes}')

    echo "$baseline"
    return 0
}

# --- TP3-008: Container security config read/write ---

integrity_read_container_config() {
    if [[ ! -f "$INTEGRITY_CONTAINER_CONFIG" ]]; then
        _integrity_default_container_config
        return 0
    fi

    # Read once, verify in-memory (avoids TOCTOU between verify and read)
    local content
    content=$(cat "$INTEGRITY_CONTAINER_CONFIG" 2>/dev/null)
    if [[ -z "$content" ]]; then
        _integrity_default_container_config
        return 0
    fi

    local stored_sig body computed_sig
    stored_sig=$(echo "$content" | jq -r '.signature // empty' 2>/dev/null)
    if [[ -z "$stored_sig" ]]; then
        integrity_audit_log "container_config_tampered" "CRITICAL: no signature — using safe defaults" || true
        _integrity_default_container_config
        return 0
    fi
    body=$(echo "$content" | jq --sort-keys -c 'del(.signature)' 2>/dev/null)
    computed_sig=$(integrity_sign_manifest "$body")
    if [[ "$stored_sig" != "$computed_sig" ]]; then
        integrity_audit_log "container_config_tampered" "CRITICAL: signature invalid — using safe defaults" || true
        _integrity_default_container_config
        return 0
    fi

    echo "$content" | jq '.'
}

integrity_write_container_config() {
    local config_json="$1"
    if ! integrity_sign_state_file "$config_json" "$INTEGRITY_CONTAINER_CONFIG"; then
        integrity_audit_log "container_config_write_failed" "sign_state_file returned non-zero" || true
        return 1
    fi
}

# --- TP3-009: Container verify state read/write ---

_integrity_default_verify_state() {
    jq -n '{
        last_verified_at: "",
        last_container_id: "",
        credential_enum_failures: 0,
        last_alert_states: {
            image_digest: {"state": "healthy", "since": ""},
            runtime_config: {"state": "healthy", "since": ""},
            credentials: {"state": "healthy", "since": ""},
            drift: {"state": "healthy", "since": ""},
            reachability: {"state": "healthy", "since": ""}
        }
    }'
}

integrity_read_verify_state() {
    if [[ ! -f "$INTEGRITY_CONTAINER_VERIFY_STATE" ]]; then
        _integrity_default_verify_state
        return 0
    fi

    # Read once, verify in-memory (avoids TOCTOU)
    local content
    content=$(cat "$INTEGRITY_CONTAINER_VERIFY_STATE" 2>/dev/null)
    if [[ -z "$content" ]]; then
        _integrity_default_verify_state
        return 0
    fi

    local stored_sig body computed_sig
    stored_sig=$(echo "$content" | jq -r '.signature // empty' 2>/dev/null)
    if [[ -z "$stored_sig" ]]; then
        integrity_audit_log "container_verify_state_tampered" "CRITICAL: no signature — safe defaults" || true
        _integrity_safe_verify_state
        return 0
    fi
    body=$(echo "$content" | jq --sort-keys -c 'del(.signature)' 2>/dev/null)
    computed_sig=$(integrity_sign_manifest "$body")
    if [[ "$stored_sig" != "$computed_sig" ]]; then
        integrity_audit_log "container_verify_state_tampered" "CRITICAL: signature invalid — safe defaults" || true
        _integrity_safe_verify_state
        return 0
    fi

    echo "$content" | jq '.'
}

# Safe defaults: max failures, all alerts unhealthy (triggers re-fire on every check)
_integrity_safe_verify_state() {
    jq -n '{
        last_verified_at: "",
        last_container_id: "",
        credential_enum_failures: 3,
        last_alert_states: {
            image_digest: {"state": "unhealthy", "since": ""},
            runtime_config: {"state": "unhealthy", "since": ""},
            credentials: {"state": "unhealthy", "since": ""},
            drift: {"state": "unhealthy", "since": ""},
            reachability: {"state": "unhealthy", "since": ""}
        }
    }'
}

integrity_write_verify_state() {
    local state_json="$1"
    if ! integrity_sign_state_file "$state_json" "$INTEGRITY_CONTAINER_VERIFY_STATE"; then
        integrity_audit_log "container_verify_state_write_failed" "sign_state_file returned non-zero" || true
        return 1
    fi
}

# ============================================================================
# --- Phase 3B: Security Tool Integration Helpers ---
# ============================================================================

# --- T3B-001: Docker socket path resolution ---
integrity_docker_socket_path() {
    # Resolve from active Docker context (supports non-default Colima profiles)
    local ctx_host
    # T005: Timeout-bounded docker context inspect (FR-009)
    ctx_host=$(integrity_run_with_timeout 5 docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null)
    if [[ -n "$ctx_host" ]]; then
        echo "$ctx_host" | sed 's|unix://||'
        return 0
    fi

    # Fall back to DOCKER_HOST env var
    if [[ -n "${DOCKER_HOST:-}" ]]; then
        echo "$DOCKER_HOST" | sed 's|unix://||'
        return 0
    fi

    # Last resort: default Colima path
    local default_path="${HOME}/.colima/default/docker.sock"
    if [[ -S "$default_path" ]]; then
        echo "$default_path"
        return 0
    fi

    echo "Cannot resolve Docker socket path" >&2
    return 1
}

# --- Phase 4B T006: Safe atomic write with trap preservation (FR-010, FR-011, FR-012) ---
_integrity_safe_atomic_write() {
    local target_file="$1"
    local content="$2"

    # Check init guard
    if [[ "${_INTEGRITY_INIT_OK:-}" != "true" ]]; then
        echo "CRITICAL: integrity library not initialized" >&2
        return 1
    fi

    # Save caller's ERR trap
    _integrity_save_err_trap

    # Validate target parent is not a symlink
    local target_dir
    target_dir=$(dirname "$target_file")
    if [[ -L "$target_dir" ]]; then
        _integrity_restore_err_trap
        echo "CRITICAL: directory_symlink_detected: ${target_dir}" >&2
        return 1
    fi

    # Save and set umask 077 (FR-011)
    local _prev_umask
    _prev_umask=$(umask)
    umask 077

    # Create temp file in secure directory
    local tmpfile
    tmpfile=$(mktemp "${INTEGRITY_TMP_DIR}/atomic-XXXXXX")

    # Restore umask immediately
    umask "$_prev_umask"

    # RETURN trap for cleanup (function-scoped in Bash 5.x)
    # shellcheck disable=SC2064
    trap "rm -f '$tmpfile' 2>/dev/null" RETURN

    # Post-creation symlink check
    if [[ -L "$tmpfile" ]]; then
        _integrity_restore_err_trap
        echo "CRITICAL: symlink_attack_detected on temp file: ${tmpfile}" >&2
        rm -f "$tmpfile"
        return 1
    fi

    # Write content
    if ! printf '%s' "$content" > "$tmpfile"; then
        _integrity_restore_err_trap
        rm -f "$tmpfile"
        return 1
    fi

    # Atomic move to target
    if ! mv "$tmpfile" "$target_file"; then
        _integrity_restore_err_trap
        rm -f "$tmpfile"
        return 1
    fi

    # Success — clear cleanup trap (FR-012: file is now at target, don't delete it)
    trap - RETURN

    # Restore caller's ERR trap
    _integrity_restore_err_trap

    return 0
}

# --- Phase 4 T005: Safe credential write for curl config (FR-026) ---
_integrity_safe_credential_write() {
    if [[ "${_INTEGRITY_INIT_OK:-}" != "true" ]]; then
        echo "CRITICAL: integrity library not initialized" >&2
        return 1
    fi
    local api_key="$1"
    local tmpconf
    tmpconf=$(mktemp "${INTEGRITY_TMP_DIR}/curl-XXXXXX")
    chmod 600 "$tmpconf"

    # Post-creation symlink check
    if [[ -L "$tmpconf" ]]; then
        rm -f "$tmpconf"
        return 1
    fi

    # Write curl config format
    printf 'header = "X-N8N-API-KEY: %s"\n' "$api_key" > "$tmpconf"

    # Return path — caller is responsible for cleanup via trap
    echo "$tmpconf"
    return 0
}

# --- Phase 4B T014: JSON validation with separated stderr (FR-026) ---
_integrity_validate_json() {
    local jq_expr="$1"
    local input="$2"
    local context="${3:-unknown}"

    local result
    local jq_rc=0
    result=$(echo "$input" | jq -e "$jq_expr" 2>/dev/null) || jq_rc=$?

    if [[ $jq_rc -ne 0 ]]; then
        # Re-run to capture diagnostic stderr
        local jq_err
        jq_err=$(echo "$input" | jq -e "$jq_expr" 2>&1 >/dev/null) || true
        echo "json_validation_failed: context=${context}, expr=${jq_expr}, error=${jq_err:0:200}" >&2
        return 1
    fi

    echo "$result"
    return 0
}

# --- Phase 4 T012: Container name validation (FR-025) ---
_integrity_validate_container_name() {
    local name="$1"
    if [[ "$name" =~ ^[a-zA-Z][a-zA-Z0-9_-]{0,63}$ ]]; then
        return 0
    fi
    echo "Invalid container name pattern: ${name}" >&2
    return 1
}

# --- T3B-002 / Phase 4 T006: Process group isolation timeout (FR-007, FR-008, FR-009) ---
integrity_run_with_timeout() {
    local timeout_secs="$1"; shift

    # Enable job control for process group creation
    set -m 2>/dev/null

    "$@" &
    local cmd_pid=$!

    # T010: Verify process group creation (FR-017, FR-018)
    local _use_pgid_kill=true
    local _cmd_pgid
    _cmd_pgid=$(ps -o pgid= -p "$cmd_pid" 2>/dev/null | tr -d ' ')
    if [[ "$_cmd_pgid" != "$cmd_pid" ]]; then
        echo "WARNING: set -m did not create new process group (PGID=$_cmd_pgid, PID=$cmd_pid), falling back to pkill -P" >&2
        _use_pgid_kill=false
    fi

    # Restore job control before launching watchdog (so watchdog is in parent's group)
    set +m 2>/dev/null

    # Watchdog: SIGTERM → grace period → SIGKILL on the entire process group
    if $_use_pgid_kill; then
        (
            sleep "$timeout_secs"
            kill -TERM -"$cmd_pid" 2>/dev/null
            sleep 2
            kill -KILL -"$cmd_pid" 2>/dev/null
        ) &
    else
        (
            sleep "$timeout_secs"
            pkill -TERM -P "$cmd_pid" 2>/dev/null; kill -TERM "$cmd_pid" 2>/dev/null
            sleep 2
            pkill -KILL -P "$cmd_pid" 2>/dev/null; kill -KILL "$cmd_pid" 2>/dev/null
        ) &
    fi
    local watchdog_pid=$!

    # Wait for command to finish (may be killed by watchdog)
    wait "$cmd_pid" 2>/dev/null
    local rc=$?

    # Determine if timeout occurred: if command was killed by signal (rc > 128)
    # and the process is no longer running, check if watchdog initiated it
    if kill -0 "$watchdog_pid" 2>/dev/null; then
        # Watchdog still alive — command finished before timeout
        kill "$watchdog_pid" 2>/dev/null
        wait "$watchdog_pid" 2>/dev/null || true
    else
        # Watchdog already exited — it fired the kill, this was a timeout
        rc=124
    fi

    # If command was killed by signal (rc > 128) and we haven't set 124, it was a timeout
    if [[ $rc -gt 128 && $rc -ne 124 ]]; then
        # Check if it was our watchdog that killed it
        if ! kill -0 "$cmd_pid" 2>/dev/null; then
            rc=124
        fi
    fi

    # Clean up any escapees
    if [[ $rc -eq 124 ]]; then
        if $_use_pgid_kill && pgrep -g "$cmd_pid" &>/dev/null; then
            echo "WARNING: Process group escapees detected after timeout (pgid=$cmd_pid)" >&2
            kill -KILL -"$cmd_pid" 2>/dev/null || true
        fi
    fi

    return "$rc"
}
