# Implementation Plan: Prerequisite Validation (make doctor)

**Branch**: `017-prerequisite-validation` | **Date**: 2026-03-28 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/017-prerequisite-validation/spec.md`

## Summary

Create `scripts/doctor.sh` and `make doctor` Makefile target that validates all 11 required tools are installed, reports all missing tools at once with install instructions, and checks minimum versions where applicable (bash 5.x). Uses the existing accumulator pattern from bootstrap.sh and `require_command()` from lib/common.sh.

## Technical Context

**Language/Version**: Bash 5.x (POSIX-compatible subset per Constitution VI)
**Primary Dependencies**: lib/common.sh (require_command, logging functions)
**Storage**: N/A
**Testing**: Manual run on healthy system + deliberately missing tool
**Target Platform**: macOS (Apple Silicon Mac Mini)
**Project Type**: CLI/infrastructure tooling
**Performance Goals**: Completes in under 5 seconds
**Constraints**: Must be idempotent, no side effects (read-only checks)
**Scale/Scope**: 1 new script (~100 lines), 1 Makefile target

## Constitution Check

| Gate | Status | Notes |
|------|--------|-------|
| I. Documentation-Is-the-Product | PASS | Improves operator experience |
| II. Threat-Model Driven | PASS | Missing tools → failed security monitoring (fswatch incident) |
| VI. Bash Scripts Are Infrastructure | PASS | set -euo pipefail, shellcheck, idempotent, colored output |
| VIII. Explicit Over Clever | PASS | Clear output with install instructions |
| X. CLI-First Infrastructure | PASS | `make doctor` is the interface |

All gates pass.

## Project Structure

### Source Code

```text
scripts/
├── doctor.sh              # NEW — prerequisite validation
└── lib/
    └── common.sh          # EXISTING — require_command(), logging

Makefile                   # MODIFIED — add doctor target
```

**Structure Decision**: Single new script in existing `scripts/` directory. Follows the established pattern of bootstrap.sh.

## Adversarial Review #2

No drift between spec and plan. Tool list, output pattern, and scope are consistent across artifacts.

**Gate: 0 CRITICAL, 0 HIGH remaining.**
