# Implementation Plan: Security Tool Integration (Phase 3B)

**Branch**: `012-security-hardening-phase2` | **Date**: 2026-03-25 | **Spec**: [phase3b-spec.md](phase3b-spec.md)

## Summary

Integrate three open-source security tools into the Makefile-based security pipeline: docker-bench-security (CIS compliance), n8n audit (application hygiene), and Grype (CVE scanning). Create a unified `make security` pipeline that orchestrates all layers with per-layer result parsing, timeout enforcement, and graceful skip handling. Annotate existing custom checks with CIS IDs. No custom code deletion — overlap is intentional defense-in-depth.

## Technical Context

**Language/Version**: Bash 5.x (POSIX-compatible subset per Constitution VI), Makefile
**Primary Dependencies**: docker-bench-security v1.6.1 (container), Grype (brew), n8n CLI (inside container), jq
**Storage**: JSON output files in `~/.openclaw/logs/audit/`
**Target Platform**: macOS (Apple Silicon or Intel) with Colima + Docker
**Constraints**: Zero custom code for the tools themselves — wrapper scripts only. All scripts pass shellcheck.

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Documentation-Is-the-Product | ✅ | Tool output is audit documentation |
| II. Threat-Model Driven | ✅ | Each tool addresses specific threats from research |
| III. Free-First | ✅ | All tools are free and open-source |
| IV. Cite Canonical Sources | ✅ | CIS Benchmark, NVD, n8n security docs |
| V. Every Recommendation Verifiable | ✅ | Each tool produces verifiable PASS/FAIL output |
| VI. Bash Scripts Are Infrastructure | ✅ | Wrapper scripts follow Constitution VI requirements |
| VII. Defense in Depth | ✅ | Three supplementary layers on top of custom verification |
| VIII. Explicit Over Clever | ✅ | Makefile targets with clear names |
| IX. Markdown Quality Gate | ✅ | N/A for this feature |
| X. CLI-First Infrastructure | ✅ | All tools invoked via CLI |

## Implementation Phases

### Phase A: Helpers (Socket Resolution + macOS Timeout)

Add two helper functions to `scripts/lib/integrity.sh`:

1. **Docker socket resolution** — dynamically resolve from Docker context, fall back to `$DOCKER_HOST`:
```bash
integrity_docker_socket_path() {
    local ctx_host
    ctx_host=$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null)
    if [[ -n "$ctx_host" ]]; then
        echo "$ctx_host" | sed 's|unix://||'
    elif [[ -n "${DOCKER_HOST:-}" ]]; then
        echo "$DOCKER_HOST" | sed 's|unix://||'
    else
        echo "$HOME/.colima/default/docker.sock"  # last resort
    fi
}
```

2. **macOS-compatible timeout** — `timeout` doesn't exist on macOS; implement via background + wait:
```bash
integrity_run_with_timeout() {
    local timeout_secs="$1"; shift
    "$@" &
    local cmd_pid=$!
    ( sleep "$timeout_secs"; kill "$cmd_pid" 2>/dev/null ) &
    local watchdog_pid=$!
    wait "$cmd_pid" 2>/dev/null
    local rc=$?
    # Check if watchdog is still running (command finished before timeout)
    if kill -0 "$watchdog_pid" 2>/dev/null; then
        kill "$watchdog_pid" 2>/dev/null; wait "$watchdog_pid" 2>/dev/null
    else
        # Watchdog finished first = timeout occurred
        rc=124
    fi
    return "$rc"
}
```

### Phase B: CIS Docker Benchmark Integration

Create `scripts/container-bench.sh` — a thin wrapper that:
1. Resolves the Docker socket path via the helper
2. Runs docker-bench-security as a container with:
   - Socket mount (read-only)
   - Filter: `-i openclaw-n8n` (note: `-i` is substring match — post-filter JSON output to exclude partial matches like `openclaw-n8n-debug`)
   - Section: all sections (not just container_runtime)
   - Exclude: `-x docker-bench` (exclude the benchmark's own container)
   - Post-filter: parse JSON `.tests[].results[].items[]` and discard entries not matching the exact container name
   - Output: JSON to `~/.openclaw/logs/audit/docker-bench.log.json`
3. Parses the JSON output to determine layer result:
   - FAIL if any Section 5 check result is WARN
   - WARN if other section checks are WARN but Section 5 is clean
   - PASS if no WARN results
4. Prints a summary to stdout

**Image pinning**: Pull `docker/docker-bench-security` by digest. Document the v1.6.1 digest.

### Phase C: n8n Audit Integration

Create `scripts/n8n-audit.sh` — a thin wrapper that:
1. Discovers the orchestration container (reuse `integrity_discover_container`)
2. Runs `docker exec -u node "$cid" n8n audit`
3. Handles output parsing:
   - Strip non-JSON preamble (lines before `{` or `[`)
   - Detect "No security issues found" plain text → PASS
   - Parse JSON findings → count by category
4. Determines layer result:
   - FAIL if findings in "credentials" or "instance" categories
   - WARN if findings only in "database", "nodes", or "filesystem"
   - PASS if zero findings
5. Prints summary to stdout, saves JSON to `~/.openclaw/logs/audit/n8n-audit.json`

### Phase D: Grype Image Scan Integration

Create `scripts/scan-image.sh` — a thin wrapper that:
1. Checks if `grype` is installed (`command -v grype`)
2. If not: print installation guidance and exit with SKIP code
3. Runs `grype openclaw-n8n:latest --fail-on high -o json`
4. Saves output to `~/.openclaw/logs/audit/grype-scan.json`
5. Disambiguate Grype exit codes: exit 0 = PASS (no CVEs above threshold); exit 1 = check if JSON output has `matches` array (findings) or error message (crash). If `matches` array present → FAIL; if error → SKIP with error details.
6. Check installed Grype version (`grype version`) against expected minimum version. Warn if version is older than expected (vulnerability database may be stale).

**Version pinning**: Pin to a specific Grype version (e.g., `0.87.0`) in documentation. The wrapper checks the installed version and warns on mismatch. Homebrew bottles are checksum-verified (accepted supply chain trust model for host-side tools — document in quickstart).

### Phase E: Unified Pipeline + Makefile Targets

Create `scripts/security-pipeline.sh` — orchestrates all layers:
1. Run each layer via `integrity_run_with_timeout 300 <script>` (macOS-compatible timeout from Phase A)
2. Collect per-layer results: PASS (0), WARN (specific code), FAIL (1), SKIP (specific code)
3. Print consolidated summary table
4. Determine overall result:
   - FAIL (exit 1) if any layer is FAIL
   - WARN (exit 2) if any layer is WARN or SKIP but no FAIL
   - PASS (exit 0) if all layers PASS
5. Record summary in audit log

Add Makefile targets:
```makefile
container-bench: ## Run CIS Docker Benchmark
n8n-audit:       ## Run n8n application security audit
scan-image:      ## Scan container image for CVEs
security:        ## Run all security layers (unified pipeline)
```

### Phase F: CIS Annotation + Integration Test + Polish

1. Annotate existing `hardening-audit.sh` container check functions with CIS IDs in comments
2. Shellcheck all new scripts
3. **Integration test** (moved from separate phase — test early): verify each Makefile target works individually (`make container-bench`, `make n8n-audit`, `make scan-image`), then verify `make security` orchestrates all layers
4. Document supply chain trust model in `phase3b-quickstart.md`: docker-bench pinned by digest, Grype installed via Homebrew (bottle checksums), n8n audit is built-in (no external dependency)

## Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Tool invocation | Container for docker-bench, docker exec for n8n audit, host binary for Grype | Each tool's native execution model |
| Socket resolution | Dynamic from Docker context | Supports non-default Colima profiles (adversarial HIGH-4) |
| Container name filter | Full name `-i openclaw-n8n` | Prevents substring false matches (adversarial LOW-10) |
| CIS threshold | Section 5 WARN = FAIL | Container runtime is our primary concern |
| n8n audit parsing | Strip preamble + detect plain text | Handles both JSON and "No issues" output (adversarial HIGH-1/2) |
| Grype severity | `--fail-on high` | Includes both high and critical (adversarial MEDIUM-6) |
| SKIP handling | Non-zero exit (code 3); timeout returns 124 | Distinguishes "tools missing" (3) and "timeout" (124) from "findings" (1) and "warnings" (2) |
| Timeout | 5 minutes per layer | Prevents hung tools from blocking pipeline (adversarial LOW-11) |
| docker-bench image | Pinned by digest | Supply chain defense (adversarial MEDIUM-5) |
| Custom check overlap | Keep both | Intentional redundancy; custom provides unified report integration |

## Dependencies

- Phase 3 (Container & Orchestration Integrity) — COMPLETE
- Docker CLI available via Colima
- Homebrew available for Grype installation
- n8n CLI available inside the container
