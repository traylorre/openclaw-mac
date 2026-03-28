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

# ADV-008: Verify integrity of sourced library before sourcing.
# Uses only builtins (shasum) — cannot rely on integrity.sh functions yet.
_verify_lib_integrity() {
    local lib_path="${SCRIPT_DIR}/lib/integrity.sh"
    local manifest="${HOME}/.openclaw/manifest.json"

    if [[ ! -f "$manifest" || ! -f "$lib_path" ]]; then
        return 0  # No manifest yet — skip (first deploy)
    fi

    local actual_hash expected_hash
    actual_hash=$(shasum -a 256 "$lib_path" | awk '{print $1}')
    expected_hash=$(jq -r --arg p "$lib_path" '.files[] | select(.path == $p) | .sha256 // empty' "$manifest" 2>/dev/null)

    if [[ -n "$expected_hash" && "$actual_hash" != "$expected_hash" ]]; then
        printf "\033[0;31m[ERROR]\033[0m lib/integrity.sh integrity violation detected\n" >&2
        printf "\033[0;31m[ERROR]\033[0m   expected: %s\n" "$expected_hash" >&2
        printf "\033[0;31m[ERROR]\033[0m   actual:   %s\n" "$actual_hash" >&2
        printf "\033[0;31m[ERROR]\033[0m   Library may have been tampered with. Rebuild: make integrity-deploy\n" >&2
        exit 1
    fi
}
_verify_lib_integrity

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

# Phase 4 T017: fail() with severity parameter (FR-003)
fail() {
    local severity="${1:-WARNING}"
    local msg="$2"
    if [[ "$severity" == "CRITICAL" ]]; then
        log_error "CRITICAL: ${msg}"
        ERRORS=$((ERRORS + 1))
        _CASCADE_ABORT=true
    else
        log_error "${msg}"
        ERRORS=$((ERRORS + 1))
    fi
}

# --- 1. Manifest Signature Verification (FR-016) ---
check_manifest_signature() {
    log_step "Verifying manifest signature"

    if [[ ! -f "$INTEGRITY_MANIFEST" ]]; then
        fail WARNING "Manifest not found: ${INTEGRITY_MANIFEST}"
        fail WARNING "  Run 'make integrity-deploy' to create it"
        return
    fi

    if integrity_verify_signature "$INTEGRITY_MANIFEST"; then
        log_info "Manifest HMAC signature valid"
    else
        fail WARNING "Manifest signature verification failed — possible tampering"
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
            fail WARNING "Protected file missing: ${path}"
            missing=$((missing + 1))
            continue
        fi

        local sha256_actual
        sha256_actual=$(integrity_compute_sha256 "$path")

        if [[ "$sha256_expected" == "$sha256_actual" ]]; then
            passed=$((passed + 1))
            log_debug "OK: ${path}"
        else
            fail WARNING "Checksum mismatch: ${path}"
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
        fail WARNING "Symlinks found in protected paths — see errors above"
    fi
}

# --- 4. Environment Variable Validation (FR-019) ---
check_env_vars() {
    log_step "Checking environment variables"

    if integrity_check_env_vars; then
        log_info "No dangerous environment variables set"
    else
        fail WARNING "Dangerous environment variables detected — see errors above"
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
        fail WARNING "Platform version mismatch"
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
        fail WARNING "pending-drafts.json is not valid JSON"
        return
    fi

    # Must be an array
    local type
    type=$(jq -r 'type' "$PENDING_DRAFTS" 2>/dev/null)
    if [[ "$type" != "array" ]]; then
        fail WARNING "pending-drafts.json must be a JSON array, got: ${type}"
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
                fail WARNING "pending-drafts entry missing required field: ${field}"
                violations=$((violations + 1))
            fi
        done

        # Check for unexpected keys (injection vector)
        local extra_keys
        extra_keys=$(echo "$entry" | jq -r --argjson allowed "$allowed_keys" '
            keys - $allowed | .[]
        ' 2>/dev/null)
        if [[ -n "$extra_keys" ]]; then
            fail WARNING "pending-drafts entry has unexpected keys: ${extra_keys}"
            violations=$((violations + 1))
        fi

        # Check content length (prevent payload stuffing)
        local content_len
        content_len=$(echo "$entry" | jq -r '.content | length' 2>/dev/null)
        if [[ "$content_len" -gt "$max_content_length" ]]; then
            fail WARNING "pending-drafts content exceeds ${max_content_length} chars (got ${content_len})"
            violations=$((violations + 1))
        fi

        # ADV-014: Type validation — id must be UUID-like
        local id_val
        id_val=$(echo "$entry" | jq -r '.id // empty' 2>/dev/null)
        if [[ -n "$id_val" ]] && ! echo "$id_val" | grep -qE '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'; then
            fail WARNING "pending-drafts entry has non-UUID id: ${id_val:0:40}"
            violations=$((violations + 1))
        fi

        # ADV-014: Enum validation — status must be known value
        local status_val
        status_val=$(echo "$entry" | jq -r '.status // empty' 2>/dev/null)
        case "$status_val" in
            draft|presented|approved|rejected|published|failed) ;;
            *)
                fail WARNING "pending-drafts entry has invalid status: ${status_val}"
                violations=$((violations + 1))
                ;;
        esac

        # ADV-014: Enum validation — type must be known value
        local type_val
        type_val=$(echo "$entry" | jq -r '.type // empty' 2>/dev/null)
        case "$type_val" in
            post|comment|like|share|article) ;;
            *)
                fail WARNING "pending-drafts entry has invalid type: ${type_val}"
                violations=$((violations + 1))
                ;;
        esac

        # ADV-014: ISO-8601 format for created_at
        local created_val
        created_val=$(echo "$entry" | jq -r '.created_at // empty' 2>/dev/null)
        if [[ -n "$created_val" ]] && ! echo "$created_val" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then
            fail WARNING "pending-drafts entry has invalid created_at format: ${created_val}"
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
# --- Audit Log Chain Verification (FR-014b, T019) ---
check_audit_chain() {
    log_step "Verifying audit log hash chain"

    if [[ ! -f "$INTEGRITY_AUDIT_LOG" ]]; then
        log_info "No audit log (OK — first run)"
        return
    fi

    if integrity_verify_audit_chain; then
        local entry_count
        entry_count=$(wc -l < "$INTEGRITY_AUDIT_LOG" | tr -d ' ')
        log_info "Audit log chain valid (${entry_count} entries)"
    else
        fail WARNING "Audit log hash chain integrity violation — possible tampering"
    fi
}

check_skill_allowlist() {
    log_step "Verifying skill allowlist"

    if [[ ! -f "$INTEGRITY_ALLOWLIST" ]]; then
        warn "Skill allowlist not found: ${INTEGRITY_ALLOWLIST}"
        warn "  Run 'make skillallow-add NAME=<skill>' to populate"
        return
    fi

    # FR-008: Verify allowlist HMAC signature before trusting entries
    if ! integrity_verify_state_file "$INTEGRITY_ALLOWLIST"; then
        fail WARNING "Skill allowlist signature invalid — possible tampering"
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
            fail WARNING "Unapproved skill: ${name} (not in allowlist)"
            unapproved=$((unapproved + 1))
        elif [[ "$content_hash" == "$approved_hash" ]]; then
            log_debug "Skill OK: ${name}"
            passed=$((passed + 1))
        else
            fail WARNING "Skill hash mismatch: ${name}"
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

# ============================================================================
# --- 012 Phase 3: Container & Orchestration Integrity ---
# Defense-in-depth verification: FR-P3-001 through FR-P3-039
# ============================================================================

# Script-level state for container ID pinning (FR-P3-036)
_CONTAINER_PINNED_CID=""
_CONTAINER_SNAPSHOT=""

# Phase 4 T016: Trust tier constants (FR-001)
_CASCADE_ABORT=false
_INITIAL_IMAGE_DIGEST=""

# Phase 4 T018: Container liveness gate (FR-002)
_verify_container_alive() {
    if [[ -z "$_CONTAINER_PINNED_CID" ]]; then
        return 1
    fi
    local alive
    alive=$(integrity_run_with_timeout 5 docker ps -q --filter "id=${_CONTAINER_PINNED_CID}" 2>/dev/null)
    local rc=$?
    if [[ $rc -eq 124 ]]; then
        # Timeout — daemon unresponsive
        fail CRITICAL "Docker daemon unresponsive (timeout on container liveness check)"
        return 1
    fi
    if [[ -z "$alive" ]]; then
        fail CRITICAL "container_vanished: pinned CID ${_CONTAINER_PINNED_CID:0:12} no longer running"
        integrity_audit_log "container_vanished" "cid=${_CONTAINER_PINNED_CID:0:12}" || true
        return 1
    fi
    # Check paused state from snapshot
    if [[ -n "$_CONTAINER_SNAPSHOT" ]]; then
        local paused
        paused=$(echo "$_CONTAINER_SNAPSHOT" | jq -r '.State.Paused // false')
        if [[ "$paused" == "true" ]]; then
            fail CRITICAL "container_paused: pinned CID ${_CONTAINER_PINNED_CID:0:12} is paused"
            return 1
        fi
    fi
    return 0
}

# --- TP3-011: Container Image Integrity (FR-P3-001/003, US1) ---
check_container_image() {
    log_step "Verifying container image digest"

    if [[ ! -f "$INTEGRITY_MANIFEST" ]]; then
        return 1
    fi

    # Check if manifest has container fields (may be pre-Phase-3)
    local expected_digest
    expected_digest=$(jq -r '.container_image_digest // empty' "$INTEGRITY_MANIFEST" 2>/dev/null)
    if [[ -z "$expected_digest" ]]; then
        log_info "No container baseline in manifest — skipping container checks"
        log_info "  Re-run 'make integrity-deploy' with container running to capture baseline"
        return 1
    fi

    # Discover container → pin ID (FR-P3-036) with retry on restart
    local cid
    cid=$(integrity_discover_container 2>/dev/null)
    if [[ -z "$cid" ]]; then
        sleep 2
        cid=$(integrity_discover_container 2>/dev/null)
    fi
    if [[ -z "$cid" ]]; then
        fail CRITICAL "Orchestration container not running — cannot verify"
        return 1
    fi
    _CONTAINER_PINNED_CID="$cid"

    # Atomic snapshot (FR-P3-012b)
    _CONTAINER_SNAPSHOT=$(integrity_capture_container_snapshot "$cid")
    if [[ -z "$_CONTAINER_SNAPSHOT" ]]; then
        fail CRITICAL "Failed to inspect container ${cid:0:12}"
        _CONTAINER_PINNED_CID=""
        return 1
    fi

    # Compare image digest
    local actual_digest
    actual_digest=$(echo "$_CONTAINER_SNAPSHOT" | jq -r '.Image // empty')

    if [[ "$actual_digest" != "$expected_digest" ]]; then
        fail CRITICAL "Container image digest mismatch"
        log_error "  expected: ${expected_digest:0:24}..."
        log_error "  actual:   ${actual_digest:0:24}..."
        integrity_audit_log "container_image_mismatch" "expected=${expected_digest:0:20}, actual=${actual_digest:0:20}"
        return 1
    fi
    log_info "Container image digest verified: ${actual_digest:0:20}..."

    # T021: Store initial image digest for final re-verification (FR-004)
    _INITIAL_IMAGE_DIGEST="$actual_digest"

    # Version threshold check (FR-P3-004)
    local manifest_version
    manifest_version=$(jq -r '.container_n8n_version // empty' "$INTEGRITY_MANIFEST" 2>/dev/null)
    if [[ -n "$manifest_version" ]]; then
        local config
        config=$(integrity_read_container_config)
        local min_version
        min_version=$(echo "$config" | jq -r '.min_n8n_version // empty')
        if [[ -n "$min_version" ]] && ! integrity_version_gte "$manifest_version" "$min_version"; then
            local reason
            reason=$(echo "$config" | jq -r '.min_n8n_version_reason // "unknown"')
            warn "n8n version ${manifest_version} is below minimum safe version ${min_version}"
            log_warn "  Reason: ${reason}"
            log_warn "  Upgrade n8n and re-deploy to resolve"
        else
            log_info "n8n version ${manifest_version} meets minimum threshold"
        fi
    fi

    return 0
}

# --- TP3-014: Container Runtime Configuration (FR-P3-005 through FR-P3-012b, US2) ---
check_container_config() {
    log_step "Verifying container runtime configuration (10 properties)"

    if [[ -z "$_CONTAINER_SNAPSHOT" ]]; then
        fail CRITICAL "No container snapshot available — image check must run first"
        return 1
    fi

    local config
    config=$(integrity_read_container_config)
    local violations=0
    local snapshot="$_CONTAINER_SNAPSHOT"

    # 1. Privileged mode (FR-P3-005, CIS 5.1)
    local privileged
    privileged=$(echo "$snapshot" | jq -r '.HostConfig.Privileged')
    if [[ "$privileged" == "true" ]]; then
        fail WARNING "Container running in PRIVILEGED mode — full host access"
        integrity_audit_log "container_config_violation" "property=privileged, expected=false, actual=true"
        violations=$((violations + 1))
    fi

    # 2. Capabilities dropped (FR-P3-006, CIS 5.2)
    local cap_drop
    cap_drop=$(echo "$snapshot" | jq -r '.HostConfig.CapDrop | join(",")' 2>/dev/null)
    if ! echo "$cap_drop" | grep -qi "ALL"; then
        fail WARNING "Container does not drop ALL capabilities: ${cap_drop:-none}"
        integrity_audit_log "container_config_violation" "property=cap_drop, expected=ALL, actual=${cap_drop:-none}"
        violations=$((violations + 1))
    fi

    # 3. Network mode (FR-P3-007)
    local net_mode
    net_mode=$(echo "$snapshot" | jq -r '.HostConfig.NetworkMode')
    if [[ "$net_mode" == "host" ]]; then
        fail WARNING "Container using HOST network — bypasses network isolation"
        integrity_audit_log "container_config_violation" "property=network_mode, expected=!host, actual=host"
        violations=$((violations + 1))
    fi

    # 4. Docker socket mount (FR-P3-008, CIS 5.3, OWASP #1)
    local has_socket
    has_socket=$(echo "$snapshot" | jq '[.Mounts[]? | select(.Source != null) | select(.Source | test("docker.sock"))] | length')
    if [[ "$has_socket" -gt 0 ]]; then
        fail WARNING "Docker socket mounted in container — grants full host control"
        integrity_audit_log "container_config_violation" "property=docker_socket, expected=not_mounted, actual=mounted"
        violations=$((violations + 1))
    fi

    # 5. Port bindings localhost only (FR-P3-009, CIS 5.16)
    local bad_ports
    # Empty HostIp or 0.0.0.0 means all interfaces (bad). Only 127.0.0.1 and ::1 are safe.
    bad_ports=$(echo "$snapshot" | jq -r '
        [.NetworkSettings.Ports // {} | to_entries[] |
         select(.value != null) |
         .value[] |
         select(.HostIp == null or (.HostIp != "127.0.0.1" and .HostIp != "::1")) |
         (.HostIp // "0.0.0.0") + ":" + .HostPort] | join(", ")')
    if [[ -n "$bad_ports" ]]; then
        fail WARNING "Container ports exposed on non-localhost interfaces: ${bad_ports}"
        integrity_audit_log "container_config_violation" "property=port_binding, expected=127.0.0.1, actual=${bad_ports}"
        violations=$((violations + 1))
    fi

    # 6. Read-only root filesystem (FR-P3-010, CIS 5.4)
    local readonly_fs
    readonly_fs=$(echo "$snapshot" | jq -r '.HostConfig.ReadonlyRootfs')
    if [[ "$readonly_fs" != "true" ]]; then
        fail WARNING "Container root filesystem is NOT read-only"
        integrity_audit_log "container_config_violation" "property=readonly_rootfs, expected=true, actual=${readonly_fs}"
        violations=$((violations + 1))
    fi

    # 7. No new privileges (FR-P3-011, CIS 5.25)
    local sec_opts
    sec_opts=$(echo "$snapshot" | jq -r '.HostConfig.SecurityOpt // [] | join(",")' 2>/dev/null)
    if ! echo "$sec_opts" | grep -q "no-new-privileges"; then
        fail WARNING "Container does not enforce no-new-privileges"
        integrity_audit_log "container_config_violation" "property=no_new_privileges, expected=set, actual=missing"
        violations=$((violations + 1))
    fi

    # 8. Seccomp not unconfined (FR-P3-011b)
    if echo "$sec_opts" | grep -q "seccomp=unconfined"; then
        fail WARNING "Container seccomp profile is UNCONFINED — syscall filtering disabled"
        integrity_audit_log "container_config_violation" "property=seccomp, expected=!unconfined, actual=unconfined"
        violations=$((violations + 1))
    fi

    # 9. Non-root user (FR-P3-011c, CIS 5.2/user, OWASP #2)
    local user
    user=$(echo "$snapshot" | jq -r '.Config.User // empty')
    if [[ -z "$user" || "$user" == "0" || "$user" == "root" ]]; then
        fail WARNING "Container running as root user"
        integrity_audit_log "container_config_violation" "property=user, expected=non-root, actual=${user:-unset}"
        violations=$((violations + 1))
    fi

    # 10. Critical environment variables (FR-P3-011d)
    # NODES_EXCLUDE — JSON-aware comparison
    local actual_nodes_exclude
    actual_nodes_exclude=$(echo "$snapshot" | jq -r '.Config.Env // [] | .[] | select(startswith("NODES_EXCLUDE=")) | sub("NODES_EXCLUDE=";"")' 2>/dev/null)
    local expected_nodes_exclude
    expected_nodes_exclude=$(echo "$config" | jq -r '.expected_runtime_config.required_env.NODES_EXCLUDE // empty')
    if [[ -n "$expected_nodes_exclude" ]]; then
        if [[ -z "$actual_nodes_exclude" ]]; then
            fail WARNING "NODES_EXCLUDE environment variable not set in container"
            integrity_audit_log "container_config_violation" "property=NODES_EXCLUDE, expected=set, actual=unset"
            violations=$((violations + 1))
        else
            local actual_sorted expected_sorted
            actual_sorted=$(echo "$actual_nodes_exclude" | jq -cS '.' 2>/dev/null) || actual_sorted="PARSE_FAILED"
            expected_sorted=$(echo "$expected_nodes_exclude" | jq -cS '.' 2>/dev/null) || expected_sorted="PARSE_EXPECTED"
            if [[ "$actual_sorted" != "$expected_sorted" ]]; then
                fail WARNING "NODES_EXCLUDE does not match expected exclusion list"
                integrity_audit_log "container_config_violation" "property=NODES_EXCLUDE, expected=${expected_sorted:0:40}, actual=${actual_sorted:0:40}"
                violations=$((violations + 1))
            fi
        fi
    fi

    # N8N_RESTRICT_FILE_ACCESS_TO
    local actual_restrict
    actual_restrict=$(echo "$snapshot" | jq -r '.Config.Env // [] | .[] | select(startswith("N8N_RESTRICT_FILE_ACCESS_TO=")) | sub("N8N_RESTRICT_FILE_ACCESS_TO=";"")' 2>/dev/null)
    if [[ -z "$actual_restrict" ]]; then
        warn "N8N_RESTRICT_FILE_ACCESS_TO not set — Code nodes may access arbitrary files"
        integrity_audit_log "container_config_violation" "property=N8N_RESTRICT_FILE_ACCESS_TO, expected=set, actual=unset"
    fi

    if [[ $violations -eq 0 ]]; then
        log_info "All 10 runtime configuration properties verified"
        integrity_audit_log "container_verify_pass" "runtime_config: 10/10 properties passed"
    else
        integrity_audit_log "container_verify_fail" "runtime_config: ${violations} violations"
    fi

    [[ $violations -eq 0 ]] && return 0 || return 1
}

# --- TP3-017/018: Credential Set Verification (FR-P3-013/014/015/016, US3) ---
check_container_credentials() {
    log_step "Verifying container credential set"

    if [[ -z "$_CONTAINER_PINNED_CID" ]]; then
        warn "No pinned container ID — skipping credential check"
        return
    fi

    local expected_creds
    expected_creds=$(jq -c '.expected_credentials // empty' "$INTEGRITY_MANIFEST" 2>/dev/null)
    if [[ -z "$expected_creds" || "$expected_creds" == "null" ]]; then
        log_info "No credential baseline in manifest — skipping"
        return
    fi

    # Enumerate current credentials with retry (TP3-018)
    local actual_creds="" exec_output rc
    local attempt max_retries=3
    for attempt in $(seq 1 $max_retries); do
        local api_key
        api_key=$(security find-generic-password -a "openclaw" -s "n8n-api-key" -w 2>/dev/null)
        if [[ -z "$api_key" ]]; then
            exec_output="No n8n API key in Keychain"
            rc=1
        else
            # T024: Fix credential exposure — use temp file instead of here-string (FR-026)
            # T028: Credential trap protection (FR-015, FR-025)
            local _prev_exit_trap
            _prev_exit_trap=$(trap -p EXIT 2>/dev/null || true)
            local _cred_tmpfile
            _cred_tmpfile=$(_integrity_safe_credential_write "$api_key")
            trap "rm -f '$_cred_tmpfile' 2>/dev/null; ${_prev_exit_trap:+eval \"$_prev_exit_trap\"}" EXIT
            exec_output=$(curl -s --config "$_cred_tmpfile" \
                "http://localhost:5678/api/v1/credentials" --max-time 10)
            rc=$?
            rm -f "$_cred_tmpfile"
            # Restore original EXIT trap
            if [[ -n "$_prev_exit_trap" ]]; then
                eval "$_prev_exit_trap"
            else
                trap - EXIT
            fi
        fi
        if [[ $rc -eq 0 ]]; then
            local parsed
            parsed=$(_integrity_validate_json '[.data[].name // empty] | sort' "$exec_output" "credential_enum" 2>/dev/null)
            if [[ -n "$parsed" ]]; then
                actual_creds="$parsed"
                break
            fi
        fi
        # Verify container is still running (curl errors don't contain "no such container")
        if ! integrity_run_with_timeout 5 docker ps -q --filter "id=${_CONTAINER_PINNED_CID}" 2>/dev/null | grep -q .; then
            fail CRITICAL "Container disappeared during credential enumeration"
            integrity_audit_log "container_disappeared" "during credential enum" || true
            return
        fi
        if [[ $attempt -lt $max_retries ]]; then
            log_info "Credential enumeration attempt ${attempt}/${max_retries} failed — retrying in 5s"
            sleep 5
        fi
    done

    # Single state variable for both paths (avoid duplicate local declaration)
    local verify_state
    verify_state=$(integrity_read_verify_state)

    # Handle enumeration failure
    if [[ -z "$actual_creds" ]]; then
        local failures
        failures=$(echo "$verify_state" | jq -r '.credential_enum_failures // 0')
        failures=$((failures + 1))
        verify_state=$(echo "$verify_state" | jq --argjson f "$failures" '.credential_enum_failures = $f')
        integrity_write_verify_state "$verify_state"
        integrity_audit_log "container_enum_failure" "consecutive_failures=${failures}" || true

        if [[ $failures -ge 3 ]]; then
            fail WARNING "Credential enumeration failed ${failures} consecutive times — escalating to hard failure"
        else
            warn "Credential enumeration failed (attempt ${failures}/3 before escalation)"
        fi
        return
    fi

    # Reset failure counter on success
    verify_state=$(echo "$verify_state" | jq '.credential_enum_failures = 0')
    integrity_write_verify_state "$verify_state"

    # Compare against baseline
    local unexpected missing
    unexpected=$(jq -n --argjson actual "$actual_creds" --argjson expected "$expected_creds" \
        '[$actual[] | select(. as $a | $expected | index($a) | not)]')
    missing=$(jq -n --argjson actual "$actual_creds" --argjson expected "$expected_creds" \
        '[$expected[] | select(. as $e | $actual | index($e) | not)]')

    local unexpected_count missing_count
    unexpected_count=$(echo "$unexpected" | jq 'length')
    missing_count=$(echo "$missing" | jq 'length')

    if [[ "$unexpected_count" -gt 0 ]]; then
        local names
        names=$(echo "$unexpected" | jq -r 'join(", ")')
        fail WARNING "Potential compromise indicator — unexpected credentials: ${names}"
        integrity_audit_log "container_credential_unexpected" "credentials=${names}"
    fi

    if [[ "$missing_count" -gt 0 ]]; then
        local names
        names=$(echo "$missing" | jq -r 'join(", ")')
        warn "Missing credentials (service disruption risk): ${names}"
        integrity_audit_log "container_credential_missing" "credentials=${names}"
    fi

    if [[ "$unexpected_count" -eq 0 && "$missing_count" -eq 0 ]]; then
        local count
        count=$(echo "$actual_creds" | jq 'length')
        log_info "Credential set verified: ${count} credentials match baseline"
    fi
}

# --- TP3-020: Workflow Integrity (FR-P3-017/018/019/020, US4) ---
# Replaces old check_n8n_workflows() — uses pinned container ID, includes .meta
check_container_workflows() {
    log_step "Verifying container workflow integrity"

    if [[ -z "$_CONTAINER_PINNED_CID" ]]; then
        warn "No pinned container ID — skipping workflow check"
        return
    fi

    # Check both workflow directories (automation + gateway)
    local workflow_dirs=()
    [[ -d "${REPO_ROOT}/workflows" ]] && workflow_dirs+=("${REPO_ROOT}/workflows")
    [[ -d "${REPO_ROOT}/n8n/workflows" ]] && workflow_dirs+=("${REPO_ROOT}/n8n/workflows")

    if [[ ${#workflow_dirs[@]} -eq 0 ]]; then
        warn "No workflows/ directory found"
        return
    fi

    # Export all workflows from container (FR-P3-017)
    # n8n may output non-JSON lines (e.g. "Browser setup: skipped") before the JSON array
    local raw_export
    # T043: Write to temp file, then truncate (FR-039) — avoids PIPESTATUS race
    local _export_tmpfile="${HOME}/.openclaw/tmp/wf-export-$$.json"
    mkdir -p "${HOME}/.openclaw/tmp"
    integrity_run_with_timeout 30 docker exec "$_CONTAINER_PINNED_CID" n8n export:workflow --all > "$_export_tmpfile" 2>/dev/null
    local docker_rc=$?

    # Truncate and detect
    local _export_size
    _export_size=$(wc -c < "$_export_tmpfile" 2>/dev/null || echo 0)
    if [[ "$_export_size" -gt 1048576 ]]; then
        log_warn "output_truncated: workflow export exceeded 1MB (${_export_size} bytes)"
        head -c 1048576 "$_export_tmpfile" > "${_export_tmpfile}.trunc" && mv "${_export_tmpfile}.trunc" "$_export_tmpfile"
    fi

    raw_export=$(cat "$_export_tmpfile" 2>/dev/null)
    rm -f "$_export_tmpfile"

    # Strip non-JSON preamble and validate
    local all_wf_json=""
    if [[ $docker_rc -eq 0 ]] && [[ -n "$raw_export" ]]; then
        # T023: Use grep-based JSON extraction with validation
        local json_start_line
        json_start_line=$(echo "$raw_export" | grep -m1 -n '^\[' | cut -d: -f1)
        if [[ -n "$json_start_line" ]]; then
            all_wf_json=$(echo "$raw_export" | tail -n +"$json_start_line")
        fi
        if [[ -n "$all_wf_json" ]] && ! echo "$all_wf_json" | jq empty 2>/dev/null; then
            all_wf_json=""  # Corrupted — treat as export failure
        fi
    fi
    if [[ -z "$all_wf_json" ]]; then
        if integrity_run_with_timeout 5 docker exec "$_CONTAINER_PINNED_CID" true 2>/dev/null; then
            warn "Failed to export workflows from container (n8n may not be ready)"
        else
            fail CRITICAL "Container disappeared during workflow export"
            integrity_audit_log "container_disappeared" "during workflow export"
        fi
        return
    fi

    # Normalize function: remove volatile fields, sort nodes by name (FR-P3-018)
    # Keep .meta (adversarial review: can contain attacker-planted data)
    # Normalize: strip volatile/runtime-only fields, sort nodes by name
    _normalize_workflow() {
        jq -cS 'del(.updatedAt, .createdAt, .versionId, .id,
                     .activeVersionId, .shared, .staticData, .tags,
                     .triggerCount, .versionCounter, .versionMetadata,
                     .description, .isArchived, .active, .pinData) |
                 if (.nodes | type) == "array" then .nodes |= sort_by(.name // "") else . end'
    }

    local compared=0 mismatched=0 meta_only_mismatches=0
    local all_repo_wfs=()
    for wdir in "${workflow_dirs[@]}"; do
        for f in "${wdir}"/*.json; do
            [[ -f "$f" ]] && all_repo_wfs+=("$f")
        done
    done

    for repo_wf in "${all_repo_wfs[@]}"; do
        [[ -f "$repo_wf" ]] || continue
        local wf_name
        wf_name=$(jq -r '.name // empty' "$repo_wf" 2>/dev/null)
        [[ -z "$wf_name" ]] && wf_name=$(basename "$repo_wf" .json)

        # Find matching workflow in container export
        local n8n_raw
        n8n_raw=$(echo "$all_wf_json" | jq -c --arg name "$wf_name" '.[] | select(.name == $name)' 2>/dev/null)
        if [[ -z "$n8n_raw" ]]; then
            log_debug "Workflow not in container: ${wf_name}"
            continue
        fi

        local n8n_normalized
        n8n_normalized=$(echo "$n8n_raw" | _normalize_workflow)
        if [[ -z "$n8n_normalized" ]]; then
            fail WARNING "Workflow normalization failed: ${wf_name} (possible tampering)"
            mismatched=$((mismatched + 1))
            continue
        fi

        local repo_normalized
        repo_normalized=$(cat "$repo_wf" | _normalize_workflow)
        if [[ -z "$repo_normalized" ]]; then
            fail WARNING "Cannot parse repo workflow as JSON: ${repo_wf}"
            mismatched=$((mismatched + 1))
            continue
        fi
        compared=$((compared + 1))

        if [[ "$n8n_normalized" == "$repo_normalized" ]]; then
            log_debug "Workflow matches: ${wf_name}"
        else
            # Check if meta is the only difference (migration detection)
            local n8n_no_meta repo_no_meta
            n8n_no_meta=$(echo "$n8n_normalized" | jq -cS 'del(.meta)')
            repo_no_meta=$(echo "$repo_normalized" | jq -cS 'del(.meta)')
            if [[ "$n8n_no_meta" == "$repo_no_meta" ]]; then
                meta_only_mismatches=$((meta_only_mismatches + 1))
            fi
            mismatched=$((mismatched + 1))
            integrity_audit_log "container_workflow_mismatch" "workflow=${wf_name}"
        fi
    done

    # Detect unexpected workflows (FR-P3-019)
    local container_wf_names
    container_wf_names=$(echo "$all_wf_json" | jq -r '.[].name' 2>/dev/null)
    while IFS= read -r cwf; do
        [[ -z "$cwf" ]] && continue
        # Check if any repo workflow has this name (across all dirs)
        local found=false
        for repo_wf in "${all_repo_wfs[@]}"; do
            local rname
            rname=$(jq -r '.name // empty' "$repo_wf" 2>/dev/null)
            if [[ "$rname" == "$cwf" ]]; then
                found=true
                break
            fi
        done
        if ! $found; then
            fail WARNING "Unexpected workflow in container: ${cwf} (no repo counterpart)"
            integrity_audit_log "container_workflow_mismatch" "type=unexpected, workflow=${cwf}"
        fi
    done <<< "$container_wf_names"

    # Migration graceful degradation (TP3-020 step 8)
    if [[ $mismatched -gt 0 && $meta_only_mismatches -eq $mismatched && $compared -eq $mismatched ]]; then
        warn "All ${mismatched} workflow mismatches are meta-only"
        log_warn "  Run 'make workflow-export && git add workflows/ && git commit' to sync .meta fields"
    elif [[ $mismatched -gt 0 ]]; then
        fail WARNING "${mismatched}/${compared} workflows differ from repository versions"
    fi

    if [[ $compared -gt 0 && $mismatched -eq 0 ]]; then
        log_info "All ${compared} workflows match repository versions"
    fi
}

# --- TP3-023: Container Filesystem Drift (FR-P3-021/022/023/024, US5) ---
check_container_drift() {
    log_step "Checking container filesystem drift"

    if [[ -z "$_CONTAINER_PINNED_CID" ]]; then
        warn "No pinned container ID — skipping drift check"
        return
    fi

    local diff_output
    # T025: Wrap docker diff with timeout (FR-010a)
    diff_output=$(integrity_run_with_timeout 30 docker diff "$_CONTAINER_PINNED_CID" 2>/dev/null)
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        warn "Failed to get container diff (container may not be running)"
        return
    fi

    if [[ -z "$diff_output" ]]; then
        log_info "No container filesystem changes detected"
        return
    fi

    # Read safe paths from config (FR-P3-022)
    local config
    config=$(integrity_read_container_config)
    local safe_paths
    safe_paths=$(echo "$config" | jq -r '.drift_safe_paths // [] | .[]' 2>/dev/null)

    # Filter safe paths — use array to avoid echo -e issues with backslashes in paths
    local -a unexpected_lines=()
    local safe_count=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local change_path
        change_path="${line:2}"

        # Check if path matches any safe prefix
        local is_safe=false
        while IFS= read -r sp; do
            [[ -z "$sp" ]] && continue
            if [[ "$change_path" == "$sp"* || "$change_path" == "$sp" ]]; then
                is_safe=true
                break
            fi
        done <<< "$safe_paths"

        if $is_safe; then
            safe_count=$((safe_count + 1))
        else
            unexpected_lines+=("$line")
        fi
    done <<< "$diff_output"

    local unexpected_count=${#unexpected_lines[@]}

    if [[ $unexpected_count -eq 0 ]]; then
        log_info "Container drift: ${safe_count} expected changes, 0 unexpected"
        return
    fi

    # Classify unexpected changes (FR-P3-023 amended)
    local readonly_fs
    readonly_fs=$(echo "$_CONTAINER_SNAPSHOT" | jq -r '.HostConfig.ReadonlyRootfs')

    if [[ "$readonly_fs" == "true" ]]; then
        fail CRITICAL "Container filesystem drift on read-only rootfs — ${unexpected_count} unexpected changes"
    else
        warn "Container filesystem drift detected — ${unexpected_count} unexpected changes (rootfs writable)"
    fi

    local changes_summary
    changes_summary=$(printf '%s;' "${unexpected_lines[@]:0:5}")
    integrity_audit_log "container_drift_detected" "unexpected_count=${unexpected_count}, changes=${changes_summary}" || true
    for l in "${unexpected_lines[@]}"; do
        log_debug "  ${l}"
    done
}

# --- TP3-025: Community Node Supply Chain (FR-P3-025/026/027, US6) ---
check_container_community_nodes() {
    log_step "Verifying community node inventory"

    if [[ -z "$_CONTAINER_PINNED_CID" ]]; then
        warn "No pinned container ID — skipping community node check"
        return
    fi

    local expected_nodes
    expected_nodes=$(jq -c '.expected_community_nodes // empty' "$INTEGRITY_MANIFEST" 2>/dev/null)
    if [[ -z "$expected_nodes" || "$expected_nodes" == "null" ]]; then
        log_info "No community node baseline in manifest — skipping"
        return
    fi

    # Read package.json files from container (FR-P3-025)
    # Cat all package.json files with delimiter, parse on host (container has no jq)
    local actual_nodes='[]'
    local pkg_output
    # T022: Output bounding (FR-010)
    pkg_output=$(integrity_run_with_timeout 30 docker exec "$_CONTAINER_PINNED_CID" sh -c '
        for f in /home/node/.n8n/nodes/node_modules/n8n-nodes-*/package.json; do
            [ -f "$f" ] && cat "$f" && printf "\n---PKG_DELIMITER---\n"
        done' 2>/dev/null)

    if ! integrity_run_with_timeout 5 docker ps -q --filter "id=${_CONTAINER_PINNED_CID}" 2>/dev/null | grep -q .; then
        fail CRITICAL "Container disappeared during node enumeration"
        integrity_audit_log "container_disappeared" "during community node enum" || true
        return
    fi

    if [[ -n "$pkg_output" ]] && [[ "$pkg_output" != *"No such file"* ]]; then
        local block=""
        while IFS= read -r line; do
            if [[ "$line" == "---PKG_DELIMITER---" ]]; then
                if [[ -n "$block" ]]; then
                    local pname pver
                    pname=$(echo "$block" | jq -r '.name // empty' 2>/dev/null)
                    pver=$(echo "$block" | jq -r '.version // empty' 2>/dev/null)
                    if [[ -n "$pname" ]]; then
                        actual_nodes=$(echo "$actual_nodes" | jq --arg n "$pname" --arg v "$pver" \
                            '. + [{"name": $n, "version": $v}]')
                    fi
                fi
                block=""
            else
                block="${block}${line}"$'\n'
            fi
        done <<< "$pkg_output"
    fi

    # Compare against baseline
    local expected_names actual_names
    expected_names=$(echo "$expected_nodes" | jq -c '[.[].name] | sort')
    actual_names=$(echo "$actual_nodes" | jq -c '[.[].name] | sort')

    # Unexpected packages (FR-P3-026)
    local unexpected
    unexpected=$(jq -n --argjson actual "$actual_names" --argjson expected "$expected_names" \
        '[$actual[] | select(. as $a | $expected | index($a) | not)]')
    local unexpected_count
    unexpected_count=$(echo "$unexpected" | jq 'length')

    if [[ "$unexpected_count" -gt 0 ]]; then
        local names
        names=$(echo "$unexpected" | jq -r 'join(", ")')
        fail WARNING "Potential supply chain compromise — unexpected packages: ${names}"
        integrity_audit_log "container_community_node_unexpected" "packages=${names}"
    fi

    # Version changes (FR-P3-027)
    while IFS= read -r exp_entry; do
        [[ -z "$exp_entry" ]] && continue
        local ename ever
        ename=$(echo "$exp_entry" | jq -r '.name')
        ever=$(echo "$exp_entry" | jq -r '.version')
        local aver
        aver=$(echo "$actual_nodes" | jq -r --arg n "$ename" '.[] | select(.name == $n) | .version // empty')
        if [[ -n "$aver" && "$aver" != "$ever" ]]; then
            warn "Community node version changed: ${ename} ${ever} → ${aver}"
            integrity_audit_log "container_community_node_version" "package=${ename}, expected=${ever}, actual=${aver}"
        fi
    done < <(echo "$expected_nodes" | jq -c '.[]' 2>/dev/null)

    # Missing packages
    local missing
    missing=$(jq -n --argjson actual "$actual_names" --argjson expected "$expected_names" \
        '[$expected[] | select(. as $e | $actual | index($e) | not)]')
    local missing_count
    missing_count=$(echo "$missing" | jq 'length')
    if [[ "$missing_count" -gt 0 ]]; then
        local names
        names=$(echo "$missing" | jq -r 'join(", ")')
        warn "Missing community nodes: ${names}"
    fi

    if [[ "$unexpected_count" -eq 0 && "$missing_count" -eq 0 ]]; then
        local count
        count=$(echo "$actual_nodes" | jq 'length')
        log_info "Community node inventory verified: ${count} packages match baseline"
    fi
}


# --- Phase 4 T043: Permission and Docker socket verification ---
check_permissions() {
    log_step "Checking file permissions and Docker socket"

    if _integrity_check_permissions "$REPO_ROOT"; then
        log_info "File permissions verified"
    else
        warn "File permission violations detected — see errors above"
    fi

    if ! _integrity_check_docker_socket 2>/dev/null; then
        warn "Docker socket permissions non-standard"
    fi
}

# --- 014 T034: Behavioral Baseline Comparison ---

check_behavioral_baseline() {
    local baseline_file="${HOME}/.openclaw/behavioral-baseline.json"

    if [[ ! -f "$baseline_file" ]]; then
        warn "Behavioral baseline not established — run integrity-deploy.sh"
        return
    fi

    # Need n8n API key from Keychain
    local api_key
    api_key=$(security find-generic-password -a "openclaw" -s "n8n-api-key" -w 2>/dev/null) || true
    if [[ -z "$api_key" ]]; then
        log_info "No n8n API key — skipping behavioral baseline comparison"
        return
    fi

    # Check if n8n is reachable
    if ! curl -s --max-time 5 "http://localhost:5678/healthz" &>/dev/null; then
        log_info "n8n not reachable — skipping behavioral baseline comparison"
        return
    fi

    log_step "Comparing behavioral baseline"

    # Fetch current execution frequency
    local _prev_exit_trap _cred_tmpfile exec_output
    _prev_exit_trap=$(trap -p EXIT 2>/dev/null || true)
    _cred_tmpfile=$(_integrity_safe_credential_write "$api_key")
    trap "rm -f '$_cred_tmpfile' 2>/dev/null; ${_prev_exit_trap:+eval \"$_prev_exit_trap\"}" EXIT

    exec_output=$(curl -s --config "$_cred_tmpfile" \
        "http://localhost:5678/api/v1/executions?limit=250&status=success" --max-time 15 2>/dev/null) || true

    rm -f "$_cred_tmpfile"
    if [[ -n "$_prev_exit_trap" ]]; then
        eval "$_prev_exit_trap"
    else
        trap - EXIT
    fi

    if [[ -z "$exec_output" ]] || ! echo "$exec_output" | jq -e '.data' &>/dev/null; then
        warn "Could not fetch execution history for baseline comparison"
        return
    fi

    # Aggregate current frequency
    local current_freq
    current_freq=$(echo "$exec_output" | jq -c '
        [.data[] | .workflowData.name // "unknown"] |
        group_by(.) | map({key: .[0], value: length}) |
        from_entries
    ' 2>/dev/null)

    # Load baseline
    local baseline_freq threshold
    baseline_freq=$(jq -c '.webhook_call_frequency // {}' "$baseline_file" 2>/dev/null)
    threshold=$(jq -r '.deviation_threshold // 200' "$baseline_file" 2>/dev/null)

    # Compare: check each workflow's execution count deviation
    local deviations=0
    local wf_name
    for wf_name in $(echo "$baseline_freq" | jq -r 'keys[]' 2>/dev/null); do
        local baseline_count current_count
        baseline_count=$(echo "$baseline_freq" | jq -r --arg k "$wf_name" '.[$k] // 0')
        current_count=$(echo "$current_freq" | jq -r --arg k "$wf_name" '.[$k] // 0')

        if [[ "$baseline_count" -gt 0 ]]; then
            local pct=$(( (current_count * 100) / baseline_count ))
            if [[ $pct -gt $threshold ]]; then
                warn "Behavioral deviation: ${wf_name} — ${current_count} executions vs baseline ${baseline_count} (${pct}%)"
                deviations=$((deviations + 1))
            fi
        fi
    done

    # Detect new workflows not in baseline (potential injection)
    local new_wf
    for new_wf in $(echo "$current_freq" | jq -r 'keys[]' 2>/dev/null); do
        local in_baseline
        in_baseline=$(echo "$baseline_freq" | jq -r --arg k "$new_wf" '.[$k] // empty')
        if [[ -z "$in_baseline" ]]; then
            local new_count
            new_count=$(echo "$current_freq" | jq -r --arg k "$new_wf" '.[$k] // 0')
            if [[ "$new_count" -gt 0 ]]; then
                warn "New workflow detected not in baseline: ${new_wf} (${new_count} executions)"
                deviations=$((deviations + 1))
            fi
        fi
    done

    # Update last_comparison_date
    local updated
    updated=$(jq --arg d "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '.last_comparison_date = $d' "$baseline_file")
    echo "$updated" | jq '.' > "$baseline_file"

    if [[ $deviations -eq 0 ]]; then
        log_info "Behavioral baseline comparison: no deviations detected"
    else
        warn "Behavioral baseline: ${deviations} workflow(s) exceeded ${threshold}% deviation threshold"
    fi
}

# --- TP3-015: Container Verification Orchestration Wrapper (FR-P3-036/037/038) ---
_run_container_checks() {
    log_step "Container & Orchestration Integrity Checks"

    # Step 0: Docker CLI availability
    if ! command -v docker &>/dev/null; then
        log_info "Docker CLI not found — container checks skipped"
        return
    fi

    # Step 1: check_container_image handles discovery + pinning + retry internally
    # Step 2: Image digest verification — BLOCKING (FR-P3-038)
    if ! check_container_image; then
        log_warn "Image check failed — skipping remaining container checks"
        return
    fi

    # Step 3: Runtime configuration — BLOCKING (FR-P3-038)
    # T019: Cascade abort gate before config check
    [[ "$_CASCADE_ABORT" == "true" ]] && { log_warn "SKIPPED: upstream CRITICAL failure"; return; }
    if ! check_container_config; then
        log_warn "Config check failed — skipping application-level checks"
        return
    fi

    # Step 4: Application-level checks with cascade abort gate (T019)
    if [[ "$_CASCADE_ABORT" != "true" ]]; then
        _verify_container_alive || return
        type -t check_container_credentials &>/dev/null && check_container_credentials
    fi
    if [[ "$_CASCADE_ABORT" != "true" ]]; then
        _verify_container_alive || return
        type -t check_container_workflows &>/dev/null && check_container_workflows
    fi
    # T039: Liveness gate before drift check (FR-002)
    if [[ "$_CASCADE_ABORT" != "true" ]]; then
        _verify_container_alive || return
        type -t check_container_drift &>/dev/null && check_container_drift
    fi
    # T040: Liveness gate before community nodes check (FR-002)
    if [[ "$_CASCADE_ABORT" != "true" ]]; then
        _verify_container_alive || return
        type -t check_container_community_nodes &>/dev/null && check_container_community_nodes
    fi

    # Step 5: Final re-verification — container ID AND image digest (FR-004, T020)
    if [[ "$_CASCADE_ABORT" != "true" && -n "$_CONTAINER_PINNED_CID" ]]; then
        local current_cid
        current_cid=$(integrity_run_with_timeout 5 docker ps -q --filter "id=${_CONTAINER_PINNED_CID}" 2>/dev/null)
        if [[ -z "$current_cid" ]]; then
            fail CRITICAL "Container disappeared during verification — results invalidated"
            integrity_audit_log "container_id_changed" "pinned=${_CONTAINER_PINNED_CID:0:12}, status=disappeared" || true
            return
        fi
        # Compare image digest against start-of-pipeline value
        if [[ -n "$_INITIAL_IMAGE_DIGEST" ]]; then
            local current_digest
            current_digest=$(integrity_run_with_timeout 5 docker inspect "$_CONTAINER_PINNED_CID" --format '{{.Image}}' 2>/dev/null)
            if [[ "$current_digest" != "$_INITIAL_IMAGE_DIGEST" ]]; then
                fail CRITICAL "container_replaced_during_verification: image digest changed"
                integrity_audit_log "container_replaced" "initial_digest=${_INITIAL_IMAGE_DIGEST:0:20}, final_digest=${current_digest:0:20}" || true
                return
            fi
        fi
        integrity_audit_log "container_verify_pass" "all container checks completed, cid=${_CONTAINER_PINNED_CID:0:12}" || true
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

    # Audit log chain verification (T019)
    check_audit_chain

    # Advisory checks (warnings only)
    check_heartbeat
    check_sandbox_config

    # Phase 4 T043: Permission verification (advisory)
    check_permissions

    # 014 T034: Behavioral baseline comparison (advisory)
    check_behavioral_baseline

    # 012 Phase 3: Container & Orchestration Integrity (replaces check_n8n_workflows)
    _run_container_checks

    # Summary
    echo ""

    # T021: Trust assumptions in verification output (FR-033)
    if [[ -n "$_CONTAINER_PINNED_CID" ]]; then
        log_info "Trust assumptions: Docker daemon integrity assumed, Colima VM integrity assumed, Keychain integrity assumed"
    fi

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
