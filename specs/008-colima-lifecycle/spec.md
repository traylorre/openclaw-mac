# Feature Specification: Colima Lifecycle Management

**Feature Branch**: `008-colima-lifecycle`
**Created**: 2026-03-17
**Status**: Draft
**Input**: Add Colima lifecycle management: bootstrap.sh installs colima and docker CLI via Homebrew if missing, new CHK-COLIMA-RUNNING audit check verifies Colima VM is started, fix function starts Colima if stopped, GETTING-STARTED guides updated with Colima setup commands. Colima is the container runtime required for n8n and all future Docker workloads.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Bootstrap Installs Colima and Docker (Priority: P1)

An operator runs the bootstrap script on a fresh Mac Mini. The script
detects that Colima and Docker CLI are not installed, installs them
via Homebrew, and reports success. After bootstrap completes, the
operator can run `colima version` and `docker version` without errors.

**Why this priority**: Without Colima and Docker, no container
workloads can run. This is a prerequisite for n8n, Qdrant, Ollama,
and every future Fledge milestone.

**Independent Test**: Run `bash scripts/bootstrap.sh` on a Mac
without Colima installed. Verify both `colima` and `docker` commands
are available afterward.

**Acceptance Scenarios**:

1. **Given** Colima is not installed, **When** the bootstrap script
   runs, **Then** Colima is installed via Homebrew and
   `colima version` succeeds.
2. **Given** Docker CLI is not installed, **When** the bootstrap
   script runs, **Then** Docker CLI is installed via Homebrew and
   `docker version` returns the client version (daemon connection
   may fail if Colima is not yet started).
3. **Given** Colima and Docker CLI are already installed, **When**
   the bootstrap script runs, **Then** both are reported as
   already present (idempotent, no reinstall).

---

### User Story 2 — Audit Detects Colima Not Running (Priority: P1)

An operator runs the hardening audit. If Colima is installed but not
running, the audit reports a WARN for `CHK-COLIMA-RUNNING` with a
clear message explaining that container workloads cannot function.
If Colima is running, it reports PASS.

**Why this priority**: The existing container checks (CHK-CONTAINER-*)
silently skip when Docker is unavailable. A dedicated Colima check
makes the dependency visible and actionable instead of leaving the
operator to wonder why container checks are being skipped.

**Independent Test**: Stop Colima, run the audit, verify
`CHK-COLIMA-RUNNING` shows WARN. Start Colima, run the audit,
verify it shows PASS.

**Acceptance Scenarios**:

1. **Given** Colima is installed and running, **When** the hardening
   audit runs, **Then** `CHK-COLIMA-RUNNING` reports PASS with
   Colima version and VM status.
2. **Given** Colima is installed but stopped, **When** the hardening
   audit runs, **Then** `CHK-COLIMA-RUNNING` reports WARN with
   remediation "Start Colima: colima start".
3. **Given** Colima is not installed, **When** the hardening audit
   runs, **Then** `CHK-COLIMA-RUNNING` reports SKIP with
   remediation "Install: brew install colima docker".
4. **Given** Colima is running, **When** the hardening audit runs,
   **Then** all existing container checks (CHK-CONTAINER-*) continue
   to function as before (zero regressions).

---

### User Story 3 — Fix Script Starts Colima (Priority: P2)

The operator runs the fix script to remediate a `CHK-COLIMA-RUNNING`
WARN. The fix function starts Colima with secure defaults (limited
CPU, memory, no Kubernetes). After the fix, Colima is running and
Docker commands work.

**Why this priority**: Operators should not need to remember Colima
start commands. The fix script provides a single remediation path
consistent with the existing fix pattern for other checks.

**Independent Test**: Stop Colima, run the fix script targeting
`CHK-COLIMA-RUNNING`, verify Colima starts and `docker info` works.

**Acceptance Scenarios**:

1. **Given** Colima is stopped, **When** the fix script runs for
   `CHK-COLIMA-RUNNING`, **Then** Colima is started with hardened
   defaults and `docker info` succeeds.
2. **Given** Colima is already running, **When** the fix script runs
   for `CHK-COLIMA-RUNNING`, **Then** it reports SKIPPED (already
   running, no action needed).
3. **Given** Colima is not installed, **When** the fix script runs
   for `CHK-COLIMA-RUNNING`, **Then** it reports FAILED with
   instruction to run bootstrap first.

---

### User Story 4 — GETTING-STARTED Guides Include Colima Setup (Priority: P3)

Both getting-started guides include Colima installation and startup
commands in the container setup section, so operators know exactly
how to get Docker working before running n8n or other containers.

**Why this priority**: The guides currently mention Colima as a
prerequisite but don't provide the install or start commands inline.
Operators must search elsewhere for setup instructions.

**Independent Test**: Read the container setup section in each guide
and verify Colima install, start, and verification commands are
present.

**Acceptance Scenarios**:

1. **Given** GETTING-STARTED.md is open, **When** the reader reaches
   the container setup section, **Then** they see `brew install
   colima docker` and `colima start` commands with verification
   steps.

---

### Edge Cases

- Colima is installed via a non-Homebrew method (manual binary).
  Detection should check `command -v colima`, not Homebrew metadata.
- Colima start fails due to insufficient disk space or a conflicting
  VM (VirtualBox, Docker Desktop). The fix function should report
  the error output, not silently fail.
- Docker Desktop is installed instead of Colima. The audit should
  detect Docker availability regardless of runtime and not fail,
  but should WARN that Colima is the recommended runtime per the
  hardening guide.
- Colima is running but the Docker socket is not reachable (stale
  socket after crash). The audit check should verify `docker info`
  succeeds, not just that the Colima process exists.
- The operator runs bootstrap with `--check` flag (dry-run mode).
  Colima installation should be reported as needed but not executed.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The bootstrap script MUST install Colima via Homebrew
  if not already present (`command -v colima` fails).
- **FR-002**: The bootstrap script MUST install Docker CLI via
  Homebrew if not already present (`command -v docker` fails).
- **FR-003**: The bootstrap script MUST NOT reinstall Colima or
  Docker if already present (idempotent).
- **FR-004**: A `CHK-COLIMA-RUNNING` audit check MUST verify that
  Colima is running and `docker info` succeeds.
- **FR-005**: `CHK-COLIMA-RUNNING` MUST report PASS when Colima is
  running, WARN when stopped, SKIP when not installed.
- **FR-006**: `CHK-COLIMA-RUNNING` MUST be registered in
  CHK-REGISTRY.md with section §4.1 and auto-fix: yes.
- **FR-007**: A `fix_colima_running` function MUST start Colima with
  hardened defaults if it is stopped.
- **FR-008**: The fix function MUST NOT start Colima if it is already
  running (idempotent).
- **FR-009**: The fix function MUST report FAILED if Colima is not
  installed (cannot fix what is not present).
- **FR-010**: Colima start defaults MUST limit resources (CPU and
  memory) and disable Kubernetes.
- **FR-011**: The GETTING-STARTED guides MUST include Colima
  installation and startup commands with verification steps.
- **FR-012**: All changes MUST NOT introduce regressions in existing
  container checks (CHK-CONTAINER-*).

### Key Entities

- **Colima VM**: The lightweight Linux VM that provides the Docker
  runtime on macOS. Has states: not installed, stopped, running.
- **Docker Socket**: The Unix socket at
  `~/.colima/default/docker.sock` that Docker CLI uses to
  communicate with the Colima VM.
- **CHK-COLIMA-RUNNING**: New audit check that verifies the Colima
  VM is running and Docker commands are functional.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An operator can go from zero container runtime to a
  working Docker environment in under 5 minutes using only the
  bootstrap script and getting-started guide.
- **SC-002**: The audit clearly indicates whether container workloads
  can function (PASS/WARN/SKIP) without the operator needing to
  diagnose Docker connectivity issues manually.
- **SC-003**: Running the fix script on a stopped Colima brings
  Docker back online within 60 seconds.
- **SC-004**: All existing container checks (CHK-CONTAINER-*,
  CHK-COLIMA-MOUNTS, CHK-DOCKER-SOCKET) continue to pass with
  zero regressions.

## Assumptions

- Homebrew is already installed (bootstrap.sh handles this in an
  earlier step).
- The Mac Mini has sufficient resources for Colima (2 CPU, 2GB RAM
  minimum, already met by Mac Mini hardware).
- No conflicting VM software (Docker Desktop, VirtualBox) is running.
  If present, the guide documents how to resolve conflicts.
- The operator has internet access for Homebrew downloads during
  bootstrap.

## Out of Scope

- Docker Desktop support (Colima is the mandated runtime per
  constitution).
- Colima VM customization beyond secure defaults (custom CPU, disk,
  network configuration).
- Automatic Colima updates or version pinning (handled by Homebrew).
- Colima profiles (only the default profile is used).
- Remote Docker contexts or multi-host Docker setups.
