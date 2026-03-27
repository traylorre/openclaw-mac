#!/usr/bin/env bash
# integrity-rotate-key.sh — Rotate HMAC signing key and re-sign all state files
# Phase 4 T054: FR-036 — HMAC key rotation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/integrity.sh
source "${SCRIPT_DIR}/lib/integrity.sh"

REPO_ROOT="$(resolve_repo_root "$SCRIPT_DIR")"
readonly REPO_ROOT

main() {
    log_step "HMAC Key Rotation"

    # Confirm with operator
    if [[ "${1:-}" != "--yes" ]]; then
        echo ""
        echo "This will:"
        echo "  1. Generate a new HMAC signing key"
        echo "  2. Store it in macOS Keychain"
        echo "  3. Re-sign all state files (manifest, lock-state, container config, verify state)"
        echo "  4. Log the rotation to the audit trail"
        echo ""
        read -r -p "Continue? [y/N] " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "Aborted."
            exit 1
        fi
    fi

    # Acquire global lock to prevent concurrent verification
    local lockdir="${INTEGRITY_AUDIT_LOG}.rotate-lock"
    if ! mkdir "$lockdir" 2>/dev/null; then
        log_error "Another rotation or verification is in progress"
        exit 1
    fi
    trap 'rm -rf "$lockdir"' EXIT

    # Log last entry with OLD key
    integrity_audit_log "hmac_key_rotation_start" "initiating key rotation"

    # Generate new key
    local new_key
    new_key=$(openssl rand -hex 32)

    # Store in Keychain (overwrites existing)
    security delete-generic-password \
        -a "${INTEGRITY_KEYCHAIN_ACCOUNT}" \
        -s "${INTEGRITY_KEYCHAIN_SERVICE}" 2>/dev/null || true
    security add-generic-password \
        -a "${INTEGRITY_KEYCHAIN_ACCOUNT}" \
        -s "${INTEGRITY_KEYCHAIN_SERVICE}" \
        -w "$new_key" \
        -U 2>/dev/null

    log_info "New HMAC key stored in Keychain"

    # Re-sign all state files atomically
    local state_files=(
        "$INTEGRITY_MANIFEST"
        "$INTEGRITY_LOCKSTATE"
        "$INTEGRITY_CONTAINER_CONFIG"
        "$INTEGRITY_CONTAINER_VERIFY_STATE"
    )

    local resigned=0
    for sf in "${state_files[@]}"; do
        if [[ -f "$sf" ]]; then
            local content body sig
            content=$(cat "$sf")
            body=$(echo "$content" | jq --sort-keys -c 'del(.signature)')
            sig=$(integrity_sign_manifest "$body")
            local signed
            signed=$(echo "$content" | jq --arg sig "$sig" '. + {signature: $sig}')
            _integrity_safe_atomic_write "$sf" "$(echo "$signed" | jq '.')"
            chmod 600 "$sf"
            resigned=$((resigned + 1))
            log_info "Re-signed: ${sf}"
        fi
    done

    # Log with NEW key
    integrity_audit_log "hmac_key_rotated" "resigned ${resigned} state files"

    log_info "Key rotation complete: ${resigned} files re-signed"
}

main "$@"
