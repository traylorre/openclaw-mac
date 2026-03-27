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
    # T033: Output bounding — 30s timeout, 1MB limit (FR-010)
    raw_output=$(integrity_run_with_timeout 30 docker exec -u node "$cid" n8n audit 2>/dev/null | head -c 1048576) || true

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
        # T032: Replace sed with grep+tail+jq validation (FR-022, FR-040)
        local json_start_line
        json_start_line=$(echo "$raw_output" | grep -m1 -n '^[{[]' | cut -d: -f1)
        if [[ -n "$json_start_line" ]]; then
            audit_json=$(echo "$raw_output" | tail -n +"$json_start_line")
        fi

        # Validate JSON
        if [[ -z "$audit_json" ]] || ! echo "$audit_json" | jq empty 2>/dev/null; then
            log_error "no_valid_json_in_output: n8n audit"
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
        # T034: Replace || echo 0 with _integrity_validate_json() (FR-011)
        critical_findings=$(_integrity_validate_json '
            [to_entries[] |
             select(.value.risk // "" | test("credentials|instance"; "i")) |
             (.value.sections // [] | length)] | add // 0' "$audit_json" "n8n_audit_critical" 2>/dev/null) || {
            log_error "json_validation_failed: n8n audit critical findings parse"
            exit 1
        }
        warn_findings=$(_integrity_validate_json '
            [to_entries[] |
             select(.value.risk // "" | test("credentials|instance"; "i") | not) |
             (.value.sections // [] | length)] | add // 0' "$audit_json" "n8n_audit_warn" 2>/dev/null) || {
            log_error "json_validation_failed: n8n audit warn findings parse"
            exit 1
        }

        total_findings=$((critical_findings + warn_findings))
    fi

    # Summary
    log_info "n8n Audit Results:"
    log_info "  Total findings: ${total_findings}"
    if [[ "$total_findings" -gt 0 ]]; then
        # Print per-category summary
        echo "$audit_json" | jq -r '
            to_entries[] |
            "  \(.value.risk // "unknown"): \(.value.sections // [] | length) finding(s)"' 2>/dev/null || log_warn "Failed to parse audit categories"
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
