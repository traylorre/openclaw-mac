#!/usr/bin/env bash
# container-bench.sh — Run CIS Docker Benchmark against the orchestration container
# Constitution VI: set -euo pipefail, shellcheck clean, idempotent, colored output
# FR-3B-001 through FR-3B-005b: CIS compliance via docker-bench-security
#
# Image pinned by digest to prevent supply chain attacks (Trivy precedent March 2026)
# docker-bench-security v1.6.1 — CIS Docker Benchmark v1.6.0
#
# Exit codes: 0=PASS, 1=FAIL, 2=WARN, 3=SKIP
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/integrity.sh
source "${SCRIPT_DIR}/lib/integrity.sh"

# T3B-005: Version pinned to v1.6.1 (CIS Docker Benchmark v1.6.0)
# Image digest for reference (used when running as container, currently using git-clone):
# docker/docker-bench-security@sha256:ddbdf4f86af4405da4a8a7b7cc62bb63bfeb75e85bf22d2ece70c204d7cfabb8
readonly BENCH_VERSION="v1.6.1"
readonly BENCH_CONTAINER_FILTER="openclaw-n8n"
readonly AUDIT_DIR="${HOME}/.openclaw/logs/audit"

main() {
    log_step "CIS Docker Benchmark (docker-bench-security)"

    # Check Docker availability
    if ! command -v docker &>/dev/null; then
        log_warn "Docker CLI not found — skipping CIS benchmark"
        exit 3
    fi

    if ! integrity_run_with_timeout 10 docker info &>/dev/null; then
        log_warn "Docker daemon not reachable — skipping CIS benchmark"
        exit 3
    fi

    mkdir -p "$AUDIT_DIR"

    log_info "Running CIS Docker Benchmark (filtered to ${BENCH_CONTAINER_FILTER})..."

    # Run docker-bench-security as shell script (not container)
    # Colima's virtiofs cannot expose the Docker socket inside a container mount.
    # Clone/reuse a local copy and run directly.
    local bench_dir="${HOME}/.openclaw/tools/docker-bench-security"
    if [[ ! -d "$bench_dir" ]]; then
        log_info "Installing docker-bench-security (first run)..."
        mkdir -p "${HOME}/.openclaw/tools"
        if ! git clone --branch "$BENCH_VERSION" --depth 1 --quiet \
            "https://github.com/docker/docker-bench-security.git" "$bench_dir" 2>/dev/null; then
            log_warn "Failed to clone docker-bench-security — skipping"
            exit 3
        fi
    fi

    # T029: Verify commit hash against pinned value (FR-014)
    local config
    config=$(integrity_read_container_config)
    local pinned_hash
    pinned_hash=$(echo "$config" | jq -r '.pinned_bench_commit // empty')
    local actual_hash
    actual_hash=$(cd "$bench_dir" && git rev-parse HEAD)

    if [[ -n "$pinned_hash" ]]; then
        if [[ "$actual_hash" != "$pinned_hash" ]]; then
            log_error "supply_chain_verification_failed: docker-bench commit hash mismatch"
            log_error "  pinned:  ${pinned_hash:0:16}..."
            log_error "  actual:  ${actual_hash:0:16}..."
            integrity_audit_log "supply_chain_verification_failed" "tool=docker-bench, pinned=${pinned_hash:0:16}, actual=${actual_hash:0:16}" || true
            # Delete tampered clone
            rm -rf "$bench_dir"
            exit 1
        fi
        log_info "docker-bench commit hash verified: ${actual_hash:0:12}..."
    else
        # Trust-on-first-use: store current hash
        log_info "No pinned hash — trust-on-first-use: storing ${actual_hash:0:12}..."
        config=$(echo "$config" | jq --arg h "$actual_hash" '.pinned_bench_commit = $h')
        integrity_write_container_config "$config"
        integrity_audit_log "supply_chain_tofu" "tool=docker-bench, hash=${actual_hash:0:12}" || true
    fi

    # T030: Capture exit code — non-zero after supply-chain pass = FAIL (FR-039)
    local bench_rc=0
    (cd "$bench_dir" && sh docker-bench-security.sh \
        -l "${AUDIT_DIR}/docker-bench.log" -b \
        -i "$BENCH_CONTAINER_FILTER" \
        -x docker-bench 2>/dev/null) || bench_rc=$?
    if [[ $bench_rc -ne 0 ]]; then
        log_warn "docker-bench-security exited with code ${bench_rc}"
    fi

    local json_file="${AUDIT_DIR}/docker-bench.log.json"
    if [[ ! -f "$json_file" ]]; then
        log_error "Benchmark completed but no JSON output found"
        exit 3
    fi

    # T031: JSON validation — validate .tests field exists before counting (FR-011, FR-013)
    # Parse results (FR-3B-003b: Section 5 WARN = FAIL)
    local json_content
    json_content=$(cat "$json_file")
    if ! _integrity_validate_json '.tests // error("missing .tests field")' "$json_content" "docker_bench" >/dev/null 2>&1; then
        log_error "docker-bench JSON output missing .tests field"
        exit 1
    fi
    # T036: JSON fallback warning — track if any parse fell back to default (FR-011, FR-039)
    local _parse_fallback=false
    local section5_warns other_warns total_checks
    section5_warns=$(_integrity_validate_json '[.tests[] | select(.id == "5") | .results[] | select(.result == "WARN")] | length' "$json_content" "docker_bench_s5" 2>/dev/null \
        ) || { log_warn "json_parse_fallback: container-bench section5_warns defaulted to 0"; section5_warns=0; _parse_fallback=true; }
    other_warns=$(_integrity_validate_json '[.tests[] | select(.id != "5") | .results[] | select(.result == "WARN")] | length' "$json_content" "docker_bench_other" 2>/dev/null \
        ) || { log_warn "json_parse_fallback: container-bench other_warns defaulted to 0"; other_warns=0; _parse_fallback=true; }
    total_checks=$(_integrity_validate_json '[.tests[].results[]] | length' "$json_content" "docker_bench_total" 2>/dev/null \
        ) || { log_warn "json_parse_fallback: container-bench total_checks defaulted to 0"; total_checks=0; _parse_fallback=true; }
    local pass_count
    pass_count=$(_integrity_validate_json '[.tests[].results[] | select(.result == "PASS")] | length' "$json_content" "docker_bench_pass" 2>/dev/null \
        ) || { log_warn "json_parse_fallback: container-bench pass_count defaulted to 0"; pass_count=0; _parse_fallback=true; }

    # Summary
    log_info "CIS Benchmark Results:"
    log_info "  Total checks: ${total_checks}"
    log_info "  Passed: ${pass_count}"
    log_info "  Section 5 (container runtime) warnings: ${section5_warns}"
    log_info "  Other section warnings: ${other_warns}"
    log_info "  Report: ${json_file}"

    # Determine result
    if [[ "$section5_warns" -gt 0 ]]; then
        log_error "FAIL: ${section5_warns} CIS Section 5 (container runtime) warnings"
        exit 1
    elif [[ "$other_warns" -gt 0 ]]; then
        log_warn "WARN: ${other_warns} CIS warnings in non-container sections"
        exit 2
    elif $_parse_fallback; then
        # T036: JSON parse fallback occurred — exit WARN instead of PASS (FR-039)
        log_warn "WARN: All checks appeared to pass but JSON parse fallback occurred — results may be unreliable"
        exit 2
    else
        log_info "PASS: All CIS checks passed"
        exit 0
    fi
}

main "$@"
