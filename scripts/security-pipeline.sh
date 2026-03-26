#!/usr/bin/env bash
# security-pipeline.sh — Unified security pipeline: all verification layers
# Constitution VI: set -euo pipefail, shellcheck clean, idempotent, colored output
# FR-3B-014 through FR-3B-022: Orchestrate all security layers
#
# Layers: 1) Integrity Verify  2) CIS Benchmark  3) n8n Audit  4) Image Scan
# Exit codes: 0=PASS (all layers pass), 1=FAIL (any layer FAIL),
#             2=WARN (any layer WARN/SKIP but no FAIL)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/integrity.sh
source "${SCRIPT_DIR}/lib/integrity.sh"

readonly LAYER_TIMEOUT=600  # 10 minutes per layer (FR-3B-020) — Grype needs time for large images

# Layer definitions: name → script
declare -A LAYERS
LAYERS=(
    ["1_Integrity_Verify"]="${SCRIPT_DIR}/integrity-verify.sh --dry-run"
    ["2_CIS_Benchmark"]="${SCRIPT_DIR}/container-bench.sh"
    ["3_n8n_Audit"]="${SCRIPT_DIR}/n8n-audit.sh"
    ["4_Image_Scan"]="${SCRIPT_DIR}/scan-image.sh"
)

# Human-readable names
declare -A LAYER_NAMES
LAYER_NAMES=(
    ["1_Integrity_Verify"]="Integrity Verification"
    ["2_CIS_Benchmark"]="CIS Docker Benchmark"
    ["3_n8n_Audit"]="n8n Application Audit"
    ["4_Image_Scan"]="Image CVE Scan"
)

result_label() {
    case "$1" in
        0) echo "PASS" ;;
        1) echo "FAIL" ;;
        2) echo "WARN" ;;
        3) echo "SKIP" ;;
        124) echo "TIMEOUT" ;;
        *) echo "ERROR($1)" ;;
    esac
}

main() {
    log_step "Security Pipeline — All Layers"
    echo ""

    local has_fail=false
    local has_warn=false
    local has_skip=false
    local pass_count=0
    local total_count=0

    # Results storage
    declare -A RESULTS
    declare -A REASONS

    # FR-3B-017: Run all layers, don't stop on first failure
    for key in $(echo "${!LAYERS[@]}" | tr ' ' '\n' | sort); do
        local name="${LAYER_NAMES[$key]}"
        local cmd="${LAYERS[$key]}"
        total_count=$((total_count + 1))

        log_info "Running: ${name}..."

        # FR-3B-020: Run with timeout
        local layer_rc=0
        # shellcheck disable=SC2086
        integrity_run_with_timeout "$LAYER_TIMEOUT" bash $cmd >/dev/null 2>&1 || layer_rc=$?

        local result
        result=$(result_label "$layer_rc")
        RESULTS[$key]="$result"

        case "$layer_rc" in
            0) pass_count=$((pass_count + 1)) ;;
            1) has_fail=true ;;
            2) has_warn=true ;;
            3) has_skip=true; REASONS[$key]="tool not available" ;;
            124) has_skip=true; REASONS[$key]="exceeded ${LAYER_TIMEOUT}s timeout" ;;
            *) has_skip=true; REASONS[$key]="unexpected exit code ${layer_rc}" ;;
        esac
    done

    # FR-3B-015: Print consolidated summary table
    echo ""
    log_step "Security Pipeline Summary"
    echo ""
    printf "  %-28s %s\n" "Layer" "Result"
    printf "  %-28s %s\n" "────────────────────────────" "──────────"
    for key in $(echo "${!LAYERS[@]}" | tr ' ' '\n' | sort); do
        local name="${LAYER_NAMES[$key]}"
        local result="${RESULTS[$key]}"
        local reason=""
        if [[ -n "${REASONS[$key]:-}" ]]; then
            reason=" (${REASONS[$key]})"
        fi
        printf "  %-28s %s%s\n" "$name" "$result" "$reason"
    done
    printf "  %-28s %s\n" "────────────────────────────" "──────────"

    # FR-3B-016/021: Determine overall result
    local overall_rc=0
    local overall_label
    if $has_fail; then
        overall_label="FAIL"
        overall_rc=1
    elif $has_warn || $has_skip; then
        local skip_count=$((total_count - pass_count))
        overall_label="WARN (${pass_count} pass, ${skip_count} warn/skip)"
        overall_rc=2
    else
        overall_label="PASS (${pass_count}/${total_count} layers)"
        overall_rc=0
    fi
    printf "  %-28s %s\n" "Overall" "$overall_label"
    echo ""

    # Log to audit trail
    integrity_audit_log "security_pipeline" "overall=${overall_label}, pass=${pass_count}, total=${total_count}" || true

    exit "$overall_rc"
}

main "$@"
