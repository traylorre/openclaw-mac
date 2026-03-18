# Implementation Plan: Colima Lifecycle Management

**Branch**: `008-colima-lifecycle` | **Date**: 2026-03-17 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/008-colima-lifecycle/spec.md`

## Summary

Extend bootstrap.sh to install Colima and Docker CLI, add a
CHK-COLIMA-RUNNING audit check, add a fix function to start Colima
with hardened defaults, and update GETTING-STARTED guides. This
follows existing patterns in the codebase (bootstrap install checks,
audit report_result, fix prompt_confirm).

## Technical Context

**Language/Version**: Bash 5.x (POSIX-compatible subset per constitution)
**Primary Dependencies**: Homebrew (`brew install colima docker`),
existing hardening-audit.sh and hardening-fix.sh
**Storage**: N/A (no persistent state beyond Colima VM itself)
**Testing**: Manual test-operator walkthrough + shellcheck
**Target Platform**: macOS Sonoma/Tahoe on Apple Silicon and Intel Mac Mini
**Project Type**: CLI audit/fix scripts + documentation
**Performance Goals**: Colima start within 60 seconds
**Constraints**: shellcheck zero warnings, idempotent, no interactive input
**Scale/Scope**: 3 files modified (bootstrap, audit, fix), 2 docs updated

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Documentation-Is-the-Product | PASS | GETTING-STARTED guides updated alongside scripts |
| II. Threat-Model Driven | PASS | Container runtime is required for n8n workload isolation |
| III. Free-First | PASS | Colima and Docker CLI are free, open-source |
| IV. Cite Canonical Sources | PASS | Colima GitHub, Docker docs |
| V. Every Recommendation Is Verifiable | PASS | CHK-COLIMA-RUNNING is the verification |
| VI. Bash Scripts Are Infrastructure | PASS | set -euo pipefail, shellcheck, idempotent |
| VII. Defense in Depth | PASS | Detect (audit) + Respond (fix) layers covered |
| VIII. Explicit Over Clever | PASS | Clear error messages naming the problem |
| IX. Markdown Quality Gate | PASS | CI lint enforced |
| X. CLI-First | PASS | All setup via brew, colima CLI |

**Gate result**: PASS.

## Project Structure

### Source Code (repository root)

```text
scripts/
├── bootstrap.sh         # MODIFY: add colima + docker install step
├── hardening-audit.sh   # MODIFY: add CHK-COLIMA-RUNNING check
├── hardening-fix.sh     # MODIFY: add fix_colima_running function + FIX_REGISTRY entry
└── CHK-REGISTRY.md      # MODIFY: add CHK-COLIMA-RUNNING row

GETTING-STARTED.md       # MODIFY: add Colima setup commands
GETTING-STARTED-INTEL.md # MODIFY: add Colima setup commands
```

**Structure Decision**: No new files. All changes extend existing
scripts following their established patterns.

## Design Decisions

### D1: Colima start defaults

**Decision**: Start Colima with `colima start --cpus 2 --memory 4
--disk 60`. On Apple Silicon, add `--arch aarch64`.

**Rationale**: Matches the Mac Mini's resources. Kubernetes is
disabled by default (no flag needed). The `vz` VM type is the
default in Colima 0.10+ on both architectures. Resource limits
prevent the VM from starving the host.

**Note (post-implementation)**: Original plan specified
`--no-kubernetes`, `--cpu`, and `--vz-rosetta` flags. Runtime
testing revealed: `--no-kubernetes` doesn't exist (Kubernetes is
opt-in), `--cpu` should be `--cpus`, and `--vz-rosetta` is not
available in Colima 0.10.1.

**Alternatives rejected**:
- Default `colima start` (no resource limits): could starve the host

### D2: Bootstrap installs but does not start Colima

**Decision**: Bootstrap installs `colima` and `docker` packages only.
It does NOT run `colima start`. Starting is a separate step (manual
or via fix script).

**Rationale**: Starting a VM is a heavyweight operation that changes
system state. Bootstrap is for installing packages. The fix script
or GETTING-STARTED guide handles starting. This keeps bootstrap
fast and predictable.

### D3: Check uses `docker info` not `colima status`

**Decision**: CHK-COLIMA-RUNNING verifies both `colima status`
(VM is running) AND `docker info` (Docker socket is reachable).

**Rationale**: Colima can be "running" with a stale socket after a
crash. `docker info` confirms the full stack is functional. Both
checks together catch the edge case of a zombie VM.

### D4: Fix classification is SAFE (not CONFIRMATION)

**Decision**: `fix_colima_running` is classified as SAFE in the
FIX_REGISTRY (auto-applies without prompting in auto mode).

**Rationale**: Starting Colima is non-destructive and reversible
(`colima stop`). It doesn't modify data, credentials, or system
configuration. All other SAFE fixes follow this pattern (deploying
policies, updating packages).

## Complexity Tracking

> No constitution violations.
