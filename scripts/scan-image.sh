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

    # T3B-010 step 2: Version check
    local grype_version
    grype_version=$(grype version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [[ -n "$grype_version" ]]; then
        if ! [[ "$grype_version" == "${EXPECTED_GRYPE_VERSION}"* ]]; then
            log_warn "Grype version ${grype_version} differs from expected ${EXPECTED_GRYPE_VERSION}.x"
            log_warn "  Vulnerability database may be stale. Update: brew upgrade grype"
        else
            log_info "Grype version: ${grype_version}"
        fi
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
    if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
        log_warn "Image '${IMAGE_NAME}' not found locally — skipping scan"
        exit 3
    fi

    mkdir -p "$AUDIT_DIR"
    local json_file="${AUDIT_DIR}/grype-scan.json"

    log_info "Scanning ${IMAGE_NAME} for CVEs (threshold: high)..."

    # FR-3B-011: Run scan with --fail-on high (includes critical)
    local scan_rc=0
    grype "$IMAGE_NAME" --fail-on high -o json > "$json_file" 2>/dev/null || scan_rc=$?

    # Grype exit codes: 0 = no findings above threshold, 1 = error, 2 = findings above threshold
    if [[ $scan_rc -eq 0 ]]; then
        # No CVEs above threshold
        local total
        total=$(jq '.matches | length' "$json_file" 2>/dev/null || echo 0)
        log_info "PASS: No high/critical CVEs found (${total} total matches at lower severities)"
        log_info "  Report: ${json_file}"
        exit 0
    elif [[ $scan_rc -eq 2 ]]; then
        # Findings above threshold (--fail-on triggered)
        local total high critical
        total=$(jq '.matches | length' "$json_file" 2>/dev/null || echo 0)
        critical=$(jq '[.matches[] | select(.vulnerability.severity == "Critical")] | length' "$json_file" 2>/dev/null || echo 0)
        high=$(jq '[.matches[] | select(.vulnerability.severity == "High")] | length' "$json_file" 2>/dev/null || echo 0)

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
