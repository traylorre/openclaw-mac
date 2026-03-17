# Research: Colima Lifecycle Management

**Feature**: 008-colima-lifecycle | **Date**: 2026-03-17

## R1: Colima start flags for Apple Silicon

**Decision**: `colima start --cpu 2 --memory 4 --disk 60 --vm-type vz
--vz-rosetta --no-kubernetes`

**Rationale**: The `vz` VM type uses Apple's Virtualization.framework,
which is significantly faster than QEMU on Apple Silicon. `--vz-rosetta`
enables transparent x86 emulation for containers that need it (common
for older Docker images). Kubernetes disabled to save ~500MB RAM.

**For Intel Macs**: `colima start --cpu 2 --memory 4 --disk 60
--no-kubernetes` (no vz or rosetta flags, uses QEMU by default).

**Source**: https://github.com/abiosoft/colima

## R2: Detecting Colima state

**Decision**: Three-state detection:
1. Not installed: `command -v colima` fails
2. Installed but stopped: `colima status 2>&1` contains "not running"
3. Running: `colima status 2>&1` contains "Running" AND `docker info`
   succeeds

**Rationale**: `colima status` alone can report "Running" even when
the Docker socket is stale. `docker info` confirms end-to-end
connectivity.

## R3: Bootstrap pattern for optional-becomes-required

**Decision**: Change Docker/Colima from SKIP (optional) to
FAIL/FIXED (required) in bootstrap.sh. Install both via
`brew install colima docker`.

**Rationale**: With n8n Gateway (Milestone 1) and future workloads,
Colima is no longer optional. The bootstrap should install it
automatically, matching the pattern used for bash, jq, and other
required tools.

## R4: Hardware detection for VM type

**Decision**: Detect Apple Silicon vs Intel via `uname -m` and
choose VM flags accordingly.

**Rationale**: `uname -m` returns `arm64` on Apple Silicon and
`x86_64` on Intel. The `--vm-type vz --vz-rosetta` flags only work
on Apple Silicon. Using them on Intel causes `colima start` to fail.

## R5: FIX_REGISTRY classification

**Decision**: SAFE (not CONFIRMATION).

**Rationale**: Starting Colima is non-destructive, reversible
(`colima stop`), and doesn't modify user data or system configuration.
Consistent with other SAFE fixes (policy deployment, package updates).
