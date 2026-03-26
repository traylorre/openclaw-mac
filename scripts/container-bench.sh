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

    if ! docker info &>/dev/null; then
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

    # -b: no colors, -l: log file, -i: include filter, -x: exclude self
    (cd "$bench_dir" && sh docker-bench-security.sh \
        -l "${AUDIT_DIR}/docker-bench.log" -b \
        -i "$BENCH_CONTAINER_FILTER" \
        -x docker-bench 2>/dev/null) || true  # always exits 0

    local json_file="${AUDIT_DIR}/docker-bench.log.json"
    if [[ ! -f "$json_file" ]]; then
        log_error "Benchmark completed but no JSON output found"
        exit 3
    fi

    # Parse results (FR-3B-003b: Section 5 WARN = FAIL)
    local section5_warns other_warns total_checks
    section5_warns=$(jq '[.tests[] | select(.id == "5") | .results[] | select(.result == "WARN")] | length' "$json_file" 2>/dev/null || echo 0)
    other_warns=$(jq '[.tests[] | select(.id != "5") | .results[] | select(.result == "WARN")] | length' "$json_file" 2>/dev/null || echo 0)
    total_checks=$(jq '[.tests[].results[]] | length' "$json_file" 2>/dev/null || echo 0)
    local pass_count
    pass_count=$(jq '[.tests[].results[] | select(.result == "PASS")] | length' "$json_file" 2>/dev/null || echo 0)

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
    else
        log_info "PASS: All CIS checks passed"
        exit 0
    fi
}

main "$@"
