# Feature Specification: Security Tool Integration (Phase 3B)

**Feature Branch**: `012-security-hardening-phase2` (Phase 3B sub-spec)
**Created**: 2026-03-25
**Status**: Draft
**Input**: Integrate docker-bench-security, n8n audit, and Grype into the security pipeline as supplementary verification layers alongside existing custom integrity checks. Informed by principal engineering analysis showing 8 of 12 custom container checks reimplemented CIS benchmarks, and identification of three coverage gaps (comprehensive CIS compliance, application security hygiene, image vulnerability scanning) that existing open-source tools already solve.

---

## User Scenarios & Testing

### User Story 1 — CIS Docker Benchmark Compliance (Priority: P1)

The operator can run a comprehensive CIS Docker Benchmark audit against the orchestration container and Docker host configuration using an industry-standard tool. The audit covers 32 container runtime checks (CIS Section 5) plus host configuration, daemon configuration, and image checks — providing 25 checks beyond what the custom audit script implements. The output is machine-readable and can be reviewed alongside the existing hardening audit report. The operator runs a single command and receives a structured compliance report with PASS/WARN/INFO results per CIS check ID.

**Why this priority**: The custom hardening audit implements 8 of 32 CIS Section 5 container runtime checks. docker-bench-security provides the remaining 25 (AppArmor, PID namespace, IPC namespace, host devices, ulimits, mount propagation, UTS namespace, health checks, PIDs limit, default bridge, user namespaces, and more) plus Sections 1-4 and 6-7 that the custom audit doesn't cover at all. This is the highest-value integration because it closes the largest compliance gap with zero custom code.

**Independent Test**: Run the CIS benchmark command. Verify it produces JSON output with results for CIS Section 5 checks. Verify it filters to only the orchestration container. Verify the operator can review results in a structured format.

**Acceptance Scenarios**:

1. **Given** the orchestration container is running, **When** the operator runs the CIS benchmark command, **Then** the tool executes all applicable CIS Docker Benchmark checks and produces a structured report with per-check PASS/WARN/INFO/NOTE results.
2. **Given** the CIS benchmark runs, **When** it evaluates container runtime checks, **Then** it filters to only the orchestration container (not the benchmark container itself or other containers).
3. **Given** the CIS benchmark completes, **When** the operator reviews the output, **Then** a machine-readable report is available for programmatic parsing and archival.
4. **Given** the Docker host or container has a CIS violation (e.g., PIDs limit not set), **When** the benchmark runs, **Then** the specific violation is identified with its CIS check ID and remediation guidance.
5. **Given** Docker is not available (Colima not running), **When** the benchmark command is invoked, **Then** it fails gracefully with a clear error message.

---

### User Story 2 — Application Security Audit (Priority: P1)

The operator can run the orchestrator's built-in security audit to detect application-level risks that infrastructure checks cannot find: stale credentials, SQL injection patterns in workflow expressions, risky or community-installed nodes, unprotected webhooks, outdated software versions, and workflows that access the host filesystem. The audit output is machine-readable and complements the custom credential baseline and workflow integrity checks from Phase 3.

**Why this priority**: The custom integrity checks detect unauthorized changes (credential injection, workflow tampering). The application audit detects configuration hygiene issues (stale credentials never cleaned up, SQL injection patterns in workflow expressions, webhooks without authentication). These are fundamentally different risk classes — the integrity checks answer "was this changed by an attacker?" while the application audit answers "is this configured insecurely?"

**Independent Test**: Run the application audit command. Verify it produces JSON output with findings across 5 risk categories. Verify it can be invoked non-interactively.

**Acceptance Scenarios**:

1. **Given** the orchestration container is running, **When** the operator runs the application audit command, **Then** the audit checks 5 risk categories (credentials, database, nodes, instance, filesystem) and produces structured findings.
2. **Given** the audit finds stale credentials (unused in any active workflow), **When** the report is generated, **Then** each stale credential is identified by name with a recommendation.
3. **Given** the audit finds unprotected webhooks (no authentication configured), **When** the report is generated, **Then** each unprotected webhook is identified by workflow name and node.
4. **Given** the audit detects an outdated software version with known security fixes, **When** the report is generated, **Then** the current version and available security patches are listed.
5. **Given** the orchestration container is not running, **When** the audit command is invoked, **Then** it fails gracefully with a clear error message.

---

### User Story 3 — Image Vulnerability Scanning (Priority: P2)

The operator can scan the orchestration container image for known vulnerabilities (CVEs) before or after deployment. The scanner checks the image's installed packages against vulnerability databases (NVD, GitHub Security Advisories, distribution-specific trackers). The operator can gate deployments on vulnerability severity — refusing to deploy an image with critical CVEs.

**Why this priority**: Runtime verification (Phase 3) detects tampering after deployment. Vulnerability scanning detects known weaknesses before deployment. Neither substitutes for the other. An image can pass all integrity checks (correct digest, correct config) while containing 47 critical CVEs in its OS packages. The operator needs both perspectives.

**Independent Test**: Scan the orchestration image. Verify it produces a report listing CVEs by severity (Critical, High, Medium, Low). Verify the operator can set a severity threshold that fails the scan.

**Acceptance Scenarios**:

1. **Given** the orchestration image exists locally, **When** the operator runs the vulnerability scan, **Then** the scanner checks all image layers against vulnerability databases and produces a report with CVE IDs, severity, affected packages, and fix versions.
2. **Given** the image has known critical CVEs, **When** the scan completes, **Then** the critical CVEs are highlighted and the scan exits with a non-zero code.
3. **Given** the image has no known critical CVEs, **When** the scan completes, **Then** the scan exits with zero and reports the total count by severity.
4. **Given** the scanner is not installed, **When** the scan command is invoked, **Then** it fails with a clear error and installation guidance.

---

### User Story 4 — Unified Security Pipeline (Priority: P2)

The operator can run all security checks — custom integrity verification, CIS benchmark compliance, application security audit, and image vulnerability scanning — with a single command. The pipeline runs each layer in sequence, collects results, and provides a unified pass/fail summary. If any layer finds critical issues, the pipeline exits with a non-zero code.

**Why this priority**: Defense in depth requires multiple verification layers, but operational overhead must be minimal. A single entry point that runs all layers and produces a consolidated result makes the security pipeline as easy to use as `make test`.

**Independent Test**: Run the unified security command. Verify all four layers execute. Verify the exit code reflects the worst result across all layers. Verify the operator can see which layers passed and which failed.

**Acceptance Scenarios**:

1. **Given** all security tools are available, **When** the operator runs the unified security command, **Then** all four layers execute in sequence: custom integrity verification, CIS benchmark, application audit, image scan.
2. **Given** one layer finds critical issues (e.g., CIS violations), **When** the pipeline completes, **Then** the overall result is FAIL with a summary showing which layers passed and which failed.
3. **Given** all layers pass, **When** the pipeline completes, **Then** the overall result is PASS with a summary of checks performed.
4. **Given** a tool is not installed (e.g., vulnerability scanner missing), **When** the pipeline runs, **Then** it skips the missing tool with a warning and continues with the remaining layers, noting the gap in the summary.

---

5. **Given** multiple tools are not installed, **When** the pipeline completes, **Then** the overall result is WARN (not PASS) with a summary clearly stating N of M layers were skipped. Skipped layers produce a non-zero exit code (distinct from FAIL) so automation cannot silently pass a pipeline where most tools were absent.
6. **Given** a security tool hangs or takes unreasonably long, **When** the layer exceeds the configured timeout (default: 5 minutes), **Then** it is terminated and recorded as SKIP with reason "timeout."

---

### Edge Cases

- What happens when docker-bench-security runs as a container and reports warnings about itself? The benchmark container is excluded from results via the full container name filter (not substring).
- What happens when n8n audit emits non-JSON preamble lines (e.g., "Browser setup: skipped") to stdout before JSON? The wrapper strips non-JSON preamble before parsing. This is a known n8n behavior.
- What happens when n8n audit finds zero issues? It outputs plain text "No security issues found" instead of JSON. The wrapper detects this and synthesizes a PASS result.
- What happens when n8n audit encounters a broken workflow? The audit command handles this internally and reports it as a finding, not a crash.
- What happens when the vulnerability scanner's database is outdated? The scanner reports the database age. The operator is advised to update before trusting results.
- What happens when the operator runs the unified pipeline but Colima is not running? All Docker-dependent layers skip with warnings. The summary shows which layers were skipped and why.
- What happens when the operator uses a non-default Colima profile? The Docker socket path is dynamically resolved from the active Docker context, not hardcoded to the default profile.
- What happens when multiple containers match the benchmark filter? The benchmark uses the full container name (exact match) to prevent false matches.

## Requirements

### Functional Requirements

**CIS Docker Benchmark (US1)**:

- **FR-3B-001**: System MUST provide a command that runs the CIS Docker Benchmark against the orchestration container and Docker host.
- **FR-3B-002**: The benchmark MUST filter results to only the orchestration container using the full container name (not a substring), excluding the benchmark tool's own container and any other containers.
- **FR-3B-003**: The benchmark MUST produce machine-readable output that can be parsed programmatically. The tool always exits 0 regardless of findings — the wrapper MUST parse the JSON output to determine PASS/WARN/FAIL.
- **FR-3B-003b**: The CIS benchmark layer result MUST be: FAIL if any container runtime check (Section 5) reports WARN; WARN if checks in other sections report WARN but Section 5 is clean; PASS if no WARN results.
- **FR-3B-004**: The benchmark MUST run non-interactively with no operator prompts.
- **FR-3B-005**: The benchmark command MUST dynamically resolve the Docker socket path from the active Docker context (`docker context inspect`), not hardcode a default path. This supports non-default Colima profiles.
- **FR-3B-005b**: The benchmark tool image MUST be pulled by digest (not tag) to prevent supply chain attacks analogous to the Trivy compromise. The expected digest MUST be documented.

**Application Security Audit (US2)**:

- **FR-3B-006**: System MUST provide a command that runs the orchestrator's built-in security audit.
- **FR-3B-007**: The audit MUST check all 5 risk categories: credentials, database, nodes, instance, filesystem.
- **FR-3B-008**: The audit MUST produce machine-readable output. The wrapper MUST handle two output formats: (a) JSON with findings, and (b) plain text "No security issues found" when zero findings exist. Non-JSON preamble lines (e.g., browser setup messages) MUST be stripped before parsing. The tool always exits 0 — the wrapper MUST parse output to determine results.
- **FR-3B-008b**: The application audit layer result MUST be: FAIL if any finding in the "credentials" or "instance" categories (stale credentials, unprotected webhooks, outdated version); WARN if findings only in "database", "nodes", or "filesystem" categories; PASS if zero findings.
- **FR-3B-009**: The audit command MUST handle the case where the orchestration container is not running (fail gracefully).

**Image Vulnerability Scanning (US3)**:

- **FR-3B-010**: System MUST provide a command that scans the orchestration container image for known CVEs.
- **FR-3B-011**: The scan MUST exit with a non-zero code when CVEs at high severity or above are found. This maps to the scanner's severity floor threshold (high includes both high and critical).
- **FR-3B-012**: The scanner MUST report CVE ID, severity, affected package, and fix version for each finding.
- **FR-3B-013**: The scan command MUST handle the case where the scanner is not installed (fail with installation guidance).

**Unified Pipeline (US4)**:

- **FR-3B-014**: System MUST provide a single command that runs all security layers in sequence: integrity verification, CIS benchmark, application audit, image scan.
- **FR-3B-015**: The pipeline MUST produce a summary showing which layers passed, failed, or were skipped.
- **FR-3B-016**: The pipeline MUST exit with a non-zero code if any layer finds critical issues.
- **FR-3B-017**: The pipeline MUST continue executing remaining layers when one layer fails (collect all results, don't stop on first failure).
- **FR-3B-018**: The pipeline MUST skip layers gracefully when their required tool is not installed, noting the gap in the summary.

**Cross-Cutting**:

- **FR-3B-019**: Existing custom container checks in the hardening audit MUST be annotated with their corresponding CIS benchmark IDs to document the intentional overlap with the CIS benchmark tool.
- **FR-3B-020**: Each pipeline layer MUST complete within a configurable timeout (default: 5 minutes). If a layer exceeds the timeout, it is terminated and recorded as SKIP with reason "timeout."
- **FR-3B-021**: Skipped layers (tool missing or timeout) MUST cause the pipeline to exit with a distinct non-zero code (different from FAIL) so that automation can distinguish "tools unavailable" from "critical findings detected."
- **FR-3B-022**: All third-party security tool versions MUST be pinned. The vulnerability scanner MUST be installed at a specific version. Version pinning is documented alongside each tool's integration. The accepted supply chain trust model (Homebrew bottle checksums for host-side tools, digest-pinned images for container-based tools) MUST be documented.

### Key Entities

- **Security Layer**: A distinct verification concern (infrastructure compliance, application hygiene, vulnerability scanning, runtime integrity) implemented by a specific tool and invoked via a specific command.
- **Layer Result**: The outcome of running a security layer — PASS (no critical findings), WARN (non-critical findings), FAIL (critical findings), or SKIP (tool unavailable).
- **Pipeline Summary**: A consolidated report showing per-layer results, total findings by severity, and an overall pass/fail determination.

## Success Criteria

### Measurable Outcomes

- **SC-3B-001**: The CIS Docker Benchmark audit covers at least 30 container runtime checks per run (vs 8 in the custom audit) — a 3.75x increase in CIS compliance coverage.
- **SC-3B-002**: The application security audit detects stale credentials, unprotected webhooks, and risky node usage that the custom integrity checks cannot detect — covering at least 3 risk categories not addressed by Phase 3.
- **SC-3B-003**: The vulnerability scanner identifies known CVEs in the container image, providing pre-deployment visibility that no runtime check can offer.
- **SC-3B-004**: The operator can run the complete security pipeline (all 4 layers) with a single command, receiving a unified pass/fail result.
- **SC-3B-005**: All security tools degrade gracefully when unavailable — no crashes, clear skip messages, pipeline continues with remaining tools.

## Assumptions

- Docker CLI is available on the host and can communicate with the container runtime VM.
- The operator has internet access for vulnerability database updates (scanner needs CVE data).
- The orchestration container exposes a CLI that supports the built-in security audit command.
- The CIS benchmark tool can run as a container or shell script on macOS.
- The container runtime VM's Docker socket is accessible from the host.

## Scope and Boundaries

**In scope**:

- Adding operator-facing commands for CIS benchmark, application audit, and image scan
- Creating a unified pipeline command that orchestrates all security layers
- Annotating existing custom checks with CIS benchmark IDs
- Handling tool unavailability gracefully (skip with warning)

**Out of scope**:

- Modifying the CIS benchmark tool, application audit, or vulnerability scanner
- Replacing custom integrity checks with standard tools (Phase 3 checks stay)
- Deleting overlapping custom checks from the hardening audit (intentional redundancy)
- Kubernetes-scale tooling (admission controllers, OPA, network policies)
- Using Trivy for vulnerability scanning (supply chain compromised March 2026)
- Automated remediation of findings (operator must act on results)
- CI/CD pipeline integration (this feature covers local operator commands; CI/CD is future work)

## Dependencies

- Phase 3 (Container & Orchestration Integrity) — COMPLETE: custom verification provides the runtime integrity layer
- Phase 1A (Expanded Protection Surface) — COMPLETE: protected file list established
- Phase 2 (Hash-Chained Audit Log) — COMPLETE: audit logging available
- 011-workspace-integrity merged to main (DONE — PR #95)
- Docker CLI available via Colima infrastructure (established in M1)
