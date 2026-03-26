#!/usr/bin/env bash
# n8n-audit.sh — Run n8n built-in security audit
# Constitution VI: set -euo pipefail, shellcheck clean, idempotent, colored output
# FR-3B-006 through FR-3B-009: Application security hygiene via n8n audit
#
# Handles two output formats:
# - JSON with findings (normal case)
# - Plain text "No security issues found" (zero findings)
# - Non-JSON preamble lines (e.g., "Browser setup: skipped") stripped before parsing
#
# Exit codes: 0=PASS, 1=FAIL, 2=WARN, 3=SKIP
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/integrity.sh
source "${SCRIPT_DIR}/lib/integrity.sh"

readonly AUDIT_DIR="${HOME}/.openclaw/logs/audit"

main() {
    log_step "n8n Application Security Audit"

    # Discover container (FR-3B-009: handle not running)
    if ! command -v docker &>/dev/null; then
        log_warn "Docker CLI not found — skipping n8n audit"
        exit 3
    fi

    local cid
    cid=$(integrity_discover_container 2>/dev/null)
    if [[ -z "$cid" ]]; then
        # T3B-008: Retry once after 5 seconds (n8n initializing)
        log_info "Container not ready, retrying in 5 seconds..."
        sleep 5
        cid=$(integrity_discover_container 2>/dev/null)
        if [[ -z "$cid" ]]; then
            log_warn "Orchestration container not running — skipping n8n audit"
            exit 3
        fi
    fi

    mkdir -p "$AUDIT_DIR"

    log_info "Running n8n security audit (5 risk categories)..."

    # Run audit (FR-3B-006, FR-3B-007)
    local raw_output
    raw_output=$(docker exec -u node "$cid" n8n audit 2>/dev/null) || true

    if [[ -z "$raw_output" ]]; then
        log_warn "n8n audit returned empty output"
        exit 3
    fi

    # FR-3B-008: Handle two output formats
    local audit_json=""

    # Check for "No security issues found" plain text
    if echo "$raw_output" | grep -qi "no security issues found"; then
        audit_json='{}'
        log_info "n8n audit: No security issues found"
    else
        # Strip non-JSON preamble (e.g., "Browser setup: skipped")
        audit_json=$(echo "$raw_output" | sed -n '/^[{[]/,$p')

        # Validate JSON
        if [[ -z "$audit_json" ]] || ! echo "$audit_json" | jq empty 2>/dev/null; then
            log_warn "n8n audit output is not valid JSON after preamble stripping"
            # Save raw output for debugging
            echo "$raw_output" > "${AUDIT_DIR}/n8n-audit-raw.txt"
            log_info "  Raw output saved to ${AUDIT_DIR}/n8n-audit-raw.txt"
            exit 3
        fi
    fi

    # Save parsed JSON
    echo "$audit_json" | jq '.' > "${AUDIT_DIR}/n8n-audit.json"

    # FR-3B-008b: Determine result by category
    # Category is the top-level key name (e.g., "Credentials Risk Report")
    local critical_findings=0
    local warn_findings=0
    local total_findings=0

    if [[ "$audit_json" != "{}" ]]; then
        # Count findings in credentials/instance categories (FAIL-worthy)
        critical_findings=$(echo "$audit_json" | jq '
            [to_entries[] |
             select(.value.risk // "" | test("credentials|instance"; "i")) |
             (.value.sections // [] | length)] | add // 0' 2>/dev/null || echo 0)

        # Count findings in other categories (WARN-worthy)
        warn_findings=$(echo "$audit_json" | jq '
            [to_entries[] |
             select(.value.risk // "" | test("credentials|instance"; "i") | not) |
             (.value.sections // [] | length)] | add // 0' 2>/dev/null || echo 0)

        total_findings=$((critical_findings + warn_findings))
    fi

    # Summary
    log_info "n8n Audit Results:"
    log_info "  Total findings: ${total_findings}"
    if [[ "$total_findings" -gt 0 ]]; then
        # Print per-category summary
        echo "$audit_json" | jq -r '
            to_entries[] |
            "  \(.value.risk // "unknown"): \(.value.sections // [] | length) finding(s)"' 2>/dev/null || true
    fi
    log_info "  Report: ${AUDIT_DIR}/n8n-audit.json"

    # Determine exit code
    if [[ "$critical_findings" -gt 0 ]]; then
        log_error "FAIL: ${critical_findings} critical findings (credentials/instance)"
        exit 1
    elif [[ "$warn_findings" -gt 0 ]]; then
        log_warn "WARN: ${warn_findings} findings in non-critical categories"
        exit 2
    else
        log_info "PASS: No security issues found"
        exit 0
    fi
}

main "$@"
