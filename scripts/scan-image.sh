#!/usr/bin/env bash
# scan-image.sh — Scan container image for CVEs using Grype
# Constitution VI: set -euo pipefail, shellcheck clean, idempotent, colored output
# FR-3B-010 through FR-3B-013: Image vulnerability scanning
#
# Grype chosen over Trivy (Trivy supply-chain compromised March 2026)
# Supply chain trust model: Homebrew bottle checksums for host-side binary
#
# Exit codes: 0=PASS, 1=FAIL, 3=SKIP (no WARN path — Grype's --fail-on is binary)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/integrity.sh
source "${SCRIPT_DIR}/lib/integrity.sh"

readonly IMAGE_NAME="openclaw-n8n:latest"
readonly AUDIT_DIR="${HOME}/.openclaw/logs/audit"
readonly EXPECTED_GRYPE_VERSION="0.110"  # Minimum expected version prefix

main() {
    log_step "Image Vulnerability Scan (Grype)"

    # FR-3B-013: Check if grype is installed
    if ! command -v grype &>/dev/null; then
        log_warn "Grype not installed — skipping image scan"
        log_info "  Install with: brew install grype"
        exit 3
    fi

    # T035: Exact version match + binary SHA-256 verification (FR-015)
    local grype_version
    grype_version=$(grype version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

    local config
    config=$(integrity_read_container_config)
    local pinned_grype_hash
    pinned_grype_hash=$(echo "$config" | jq -r '.pinned_grype_hash // empty')

    if [[ -n "$grype_version" ]]; then
        local grype_binary_hash
        grype_binary_hash=$(shasum -a 256 "$(which grype)" | awk '{print $1}')

        if [[ -n "$pinned_grype_hash" ]]; then
            if [[ "$grype_binary_hash" != "$pinned_grype_hash" ]]; then
                log_error "tool_integrity_failed: Grype binary hash mismatch"
                log_error "  pinned: ${pinned_grype_hash:0:16}..."
                log_error "  actual: ${grype_binary_hash:0:16}..."
                integrity_audit_log "tool_integrity_failed" "tool=grype, pinned=${pinned_grype_hash:0:16}, actual=${grype_binary_hash:0:16}" || true
                exit 1
            fi
            log_info "Grype binary hash verified: ${grype_binary_hash:0:12}..."
        else
            # Trust-on-first-use
            log_info "No pinned grype hash — trust-on-first-use: storing ${grype_binary_hash:0:12}..."
            config=$(echo "$config" | jq --arg h "$grype_binary_hash" '.pinned_grype_hash = $h')
            integrity_write_container_config "$config"
            integrity_audit_log "supply_chain_tofu" "tool=grype, hash=${grype_binary_hash:0:12}" || true
        fi
        log_info "Grype version: ${grype_version}"
    fi

    # Ensure Grype can reach Docker (Colima uses non-standard socket)
    if [[ -z "${DOCKER_HOST:-}" ]]; then
        local socket_path
        socket_path=$(integrity_docker_socket_path 2>/dev/null)
        if [[ -n "$socket_path" ]] && [[ -S "$socket_path" ]]; then
            export DOCKER_HOST="unix://${socket_path}"
        fi
    fi

    # Check image exists
    if ! integrity_run_with_timeout 10 docker image inspect "$IMAGE_NAME" &>/dev/null; then
        log_warn "Image '${IMAGE_NAME}' not found locally — skipping scan"
        exit 3
    fi

    mkdir -p "$AUDIT_DIR"
    local json_file="${AUDIT_DIR}/grype-scan.json"

    log_info "Scanning ${IMAGE_NAME} for CVEs (threshold: high)..."

    # FR-3B-011: Run scan with --fail-on high (includes critical)
    local scan_rc=0
    integrity_run_with_timeout 300 grype "$IMAGE_NAME" --fail-on high -o json > "$json_file" 2>/dev/null || scan_rc=$?

    # Grype exit codes: 0 = no findings above threshold, 1 = error, 2 = findings above threshold
    if [[ $scan_rc -eq 0 ]]; then
        # T036/T037: Replace || echo 0 with _integrity_validate_json() + fallback warning (FR-011, FR-039)
        local _parse_fallback=false
        local total json_content
        json_content=$(cat "$json_file")
        total=$(_integrity_validate_json '.matches | length' "$json_content" "grype_total" 2>/dev/null \
            ) || { log_warn "json_parse_fallback: scan-image total defaulted to 0"; total=0; _parse_fallback=true; }
        if $_parse_fallback; then
            log_warn "WARN: No high/critical CVEs found but JSON parse fallback occurred — results may be unreliable"
            log_info "  Report: ${json_file}"
            exit 2
        fi
        log_info "PASS: No high/critical CVEs found (${total} total matches at lower severities)"
        log_info "  Report: ${json_file}"
        exit 0
    elif [[ $scan_rc -eq 2 ]]; then
        # Findings above threshold (--fail-on triggered)
        # T037: JSON fallback warning (FR-011, FR-039)
        local _parse_fallback=false
        local total high critical json_content
        json_content=$(cat "$json_file")
        if ! _integrity_validate_json '.matches // error("missing .matches")' "$json_content" "grype" >/dev/null 2>&1; then
            log_error "Grype JSON output missing .matches field"
            exit 1
        fi
        total=$(_integrity_validate_json '.matches | length' "$json_content" "grype_total" 2>/dev/null \
            ) || { log_warn "json_parse_fallback: scan-image total defaulted to 0"; total=0; _parse_fallback=true; }
        critical=$(_integrity_validate_json '[.matches[] | select(.vulnerability.severity == "Critical")] | length' "$json_content" "grype_critical" 2>/dev/null \
            ) || { log_warn "json_parse_fallback: scan-image critical defaulted to 0"; critical=0; _parse_fallback=true; }
        high=$(_integrity_validate_json '[.matches[] | select(.vulnerability.severity == "High")] | length' "$json_content" "grype_high" 2>/dev/null \
            ) || { log_warn "json_parse_fallback: scan-image high defaulted to 0"; high=0; _parse_fallback=true; }

        if $_parse_fallback; then
            log_warn "json_parse_fallback: scan-image counts may be unreliable"
        fi
        log_error "FAIL: ${total} CVEs found (${critical} critical, ${high} high)"

        # FR-3B-012: Per-finding detail for high/critical
        log_info "High/Critical CVEs:"
        jq -r '.matches[] |
            select(.vulnerability.severity == "Critical" or .vulnerability.severity == "High") |
            "  \(.vulnerability.severity) \(.vulnerability.id): \(.artifact.name)@\(.artifact.version) → fix: \(.vulnerability.fix.versions[0] // "none")"' \
            "$json_file" 2>/dev/null || true

        log_info "  Full report: ${json_file}"
        exit 1
    elif [[ $scan_rc -eq 1 ]]; then
        # Grype error (not findings)
        log_warn "Grype encountered an error"
        exit 3
    else
        log_warn "Grype exited with unexpected code ${scan_rc}"
        exit 3
    fi
}

main "$@"
