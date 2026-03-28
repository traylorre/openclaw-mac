# Implementation Plan: OS Audit FAIL Fixes

**Branch**: `018-os-audit-fixes` | **Date**: 2026-03-28 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/018-os-audit-fixes/spec.md`

## Summary

Apply 4 pre-existing SAFE audit fixes using the existing `make fix` infrastructure. Install the launchd plist prerequisite. Verify all 4 checks pass after fixes. Confirm rollback capability via restore scripts.

## Technical Context

**Language/Version**: Bash 5.x (existing scripts), macOS system commands (defaults, systemsetup, launchctl, mkdir)
**Primary Dependencies**: scripts/hardening-fix.sh (existing), scripts/hardening-audit.sh (existing)
**Storage**: N/A
**Testing**: Run `make audit` before and after — observe 4 checks change from FAIL to PASS
**Target Platform**: macOS (Apple Silicon Mac Mini)
**Project Type**: Operational task (run existing tooling)
**Performance Goals**: Fixes complete in under 30 seconds
**Constraints**: Requires sudo. Remote Apple Events fix may need TCC Full Disk Access.
**Scale/Scope**: 4 fix operations using existing automation

## Constitution Check

| Gate | Status | Notes |
|------|--------|-------|
| II. Threat-Model Driven | PASS | Guest account = physical theft risk, Remote Apple Events = remote code execution risk |
| V. Every Recommendation Is Verifiable | PASS | `make audit` verifies each fix |
| VI. Bash Scripts Are Infrastructure | PASS | All fixes use existing shellcheck-clean scripts |
| X. CLI-First Infrastructure | PASS | `make fix` is the interface |

All gates pass.

## Project Structure

No new files. Uses existing infrastructure:

```text
scripts/
├── hardening-fix.sh           # EXISTING — contains all 4 fix functions
├── hardening-audit.sh         # EXISTING — contains all 4 check functions
└── launchd/
    └── com.openclaw.audit-cron.plist  # EXISTING — needs installation to /Library/LaunchDaemons/

Makefile                       # EXISTING — fix, fix-interactive, fix-undo targets
```

**Structure Decision**: No new files. Pure operational task using existing tooling.

## Adversarial Review #2

No drift. Spec and plan are aligned. This is an operational feature with no code changes.

**Gate: 0 CRITICAL, 0 HIGH remaining.**
