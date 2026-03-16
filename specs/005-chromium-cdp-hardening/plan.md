# Implementation Plan: Chromium CDP Hardening

**Branch**: `005-chromium-cdp-hardening` | **Date**: 2026-03-16 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/005-chromium-cdp-hardening/spec.md`

## Summary

Add fix functions for the 3 remaining audit-only Chromium checks
(CDP port binding, dangerous flags, version freshness), create a
standalone browser data cleanup script, and add Chromium setup to
GETTING-STARTED.md. The audit checks already exist and are
well-implemented — this feature adds remediation capability.

## Technical Context

**Language/Version**: Bash 5.x
**Primary Dependencies**: macOS CLI tools (lsof, ps, brew), existing hardening-audit.sh and hardening-fix.sh
**Storage**: N/A (filesystem)
**Testing**: Manual + bash -n syntax check
**Target Platform**: macOS (Apple Silicon and Intel)
**Project Type**: Documentation / scripting repository
**Performance Goals**: N/A
**Constraints**: Must follow constitution (set -euo pipefail, shellcheck-clean, idempotent, no interactive input in audit)
**Scale/Scope**: 3 new fix functions, 1 new script, 1 guide update

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Documentation-Is-the-Product | PASS | Guide update + fix scripts improve operator experience |
| II. Threat-Model Driven | PASS | CDP = unauthenticated RCE, dangerous flags = weakened isolation, stale versions = known CVEs |
| III. Free-First | PASS | All tools are free (Homebrew, Chromium) |
| IV. Cite Canonical Sources | PASS | §2.11 already cites Chromium security architecture and MITRE ATT&CK |
| V. Every Recommendation Is Verifiable | PASS | All 3 checks already exist in audit script |
| VI. Bash Scripts Are Infrastructure | PASS | New script follows set -euo pipefail, shellcheck, idempotent |
| VII. Defense in Depth | PASS | CDP fix = Prevent, dangerous flags = Prevent, version = Prevent, cleanup = Respond |
| VIII. Explicit Over Clever | PASS | INSTRUCTED fixes explain what to change and why |
| IX. Markdown Quality Gate | PASS | Guide updates must pass markdownlint |
| X. CLI-First | PASS | All operations are CLI commands |

All gates pass.

## Project Structure

### Documentation (this feature)

```text
specs/005-chromium-cdp-hardening/
├── spec.md
├── plan.md              # This file
├── research.md          # Phase 0
├── data-model.md        # Phase 1
└── checklists/
    └── requirements.md
```

### Source Code (repository root)

```text
scripts/
├── hardening-fix.sh     # Add 3 fix functions (CDP, dangerflags, version)
├── browser-cleanup.sh   # NEW: standalone cleanup script
└── CHK-REGISTRY.md      # Update Auto-Fix column for 3 entries

docs/
└── HARDENING.md         # Update §2.11 badge from [AUTO-FIX] to reflect improved coverage

GETTING-STARTED.md       # Add Chromium section to Next Steps
```

**Structure Decision**: 1 new script (`browser-cleanup.sh`), 3 existing
files modified. The fix script sources the cleanup script rather than
duplicating its logic.
