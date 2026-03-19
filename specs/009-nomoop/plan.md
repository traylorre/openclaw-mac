# Implementation Plan: NoMOOP (No Matter Out Of Place)

**Branch**: `009-nomoop` | **Date**: 2026-03-18 | **Spec**: `specs/009-nomoop/spec.md`
**Input**: Feature specification from `/specs/009-nomoop/spec.md`

## Summary

Add installation manifest tracking and clean uninstall to openclaw.
Every artifact placed on the system (files, directories, Homebrew
packages, shell config lines, Keychain entries, Docker volumes,
launchd plists) is recorded in `~/.openclaw/manifest.json` with
version tracking per artifact. Operators can verify installed state,
detect drift (checksum and version), and cleanly remove all openclaw
artifacts with a single command. The manifest library is integrated
into existing `bootstrap.sh`, `gateway-setup.sh`, and
`hardening-fix.sh` scripts so tracking is automatic across all
artifact types (tooling and hardening).

**Robustness**: All manifest writes use atomic write pattern (tmp +
mv) to survive interrupts (FR-021). Signal traps handle INT, HUP,
TERM for clean exit on Ctrl+C, terminal close, or SSH disconnect
(FR-022). Background sudo credential refresh prevents hang during
long operations (FR-024). File locking prevents concurrent manifest
corruption.

## Technical Context

**Language/Version**: Bash 5.x (POSIX-compatible subset per constitution)
**Primary Dependencies**: jq (JSON manifest manipulation), shasum (checksums), macOS CLI tools (security, launchctl, defaults)
**Storage**: Filesystem — `~/.openclaw/manifest.json` (JSON, managed with jq)
**Testing**: Manual verification + `openclaw manifest --verify` self-test + shellcheck
**Target Platform**: macOS (Intel + Apple Silicon Mac Mini)
**Project Type**: CLI tooling (shell scripts)
**Performance Goals**: N/A — artifact count <100, all operations are instant
**Constraints**: Must work without sudo for manifest reads; sudo only for privileged removals. Atomic writes (FR-021), signal traps (FR-022), version tracking (FR-023), sudo keepalive (FR-024).
**Scale/Scope**: 16 artifact types (11 tooling + 5 hardening), ~20-60 tracked artifacts per install, version tracked per artifact

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Documentation-Is-the-Product | PASS | NoMOOP makes the install/uninstall experience auditable and professional |
| II. Threat-Model Driven | PASS | Manifest supports system integrity verification (detect unauthorized changes) |
| III. Free-First | PASS | All tools free: bash, jq, shasum, security CLI |
| IV. Cite Canonical Sources | N/A | Tooling scripts, not security recommendations |
| V. Every Recommendation Verifiable | PASS | `openclaw manifest --verify` IS the verification mechanism |
| VI. Bash Scripts Are Infrastructure | PASS | set -euo pipefail, shellcheck, idempotent, colored output |
| VII. Defense in Depth | PASS | Manifest is a Detect layer control (file integrity monitoring) |
| VIII. Explicit Over Clever | PASS | Human-readable table output, clear uninstall report |
| IX. Markdown Quality Gate | PASS | Docs will pass markdownlint |
| X. CLI-First | PASS | Entirely CLI-based, no GUI |

**Gate result**: PASS — no violations, no complexity tracking needed.

**Post-Phase 1 re-check**: PASS — design adds no new dependencies,
no new abstractions beyond a single shared library file. Shell config
isolation (FR-008/FR-009) aligns with Principle VIII (Explicit Over Clever).

## Project Structure

### Documentation (this feature)

```text
specs/009-nomoop/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0: research decisions
├── data-model.md        # Phase 1: manifest schema
├── quickstart.md        # Phase 1: operator quickstart
├── contracts/
│   └── cli-commands.md  # Phase 1: CLI interface contract
└── tasks.md             # Phase 2 output (speckit.tasks)
```

### Source Code (repository root)

```text
scripts/
├── openclaw.sh              # NEW: CLI dispatcher (manifest, uninstall)
├── lib/
│   └── manifest.sh          # NEW: Shared manifest read/write functions
├── bootstrap.sh             # MODIFIED: add manifest tracking calls
├── gateway-setup.sh         # MODIFIED: add manifest tracking calls
└── hardening-fix.sh         # MODIFIED: add manifest tracking calls
```

**Structure Decision**: NoMOOP adds two new files (`openclaw.sh` and
`lib/manifest.sh`) and modifies three existing files. No new top-level
directories. The `lib/` directory under `scripts/` is a natural
location for shared functions that multiple scripts source. The
`openclaw.sh` dispatcher follows the pattern established by
`bootstrap.sh` and `gateway-setup.sh` (same color output, report
functions, --check/--help flags).

## Complexity Tracking

No violations to track. The design uses:
- 1 shared library file (manifest.sh) — justified by 4 consumers
  (bootstrap.sh, gateway-setup.sh, hardening-fix.sh, openclaw.sh)
- 1 new CLI script (openclaw.sh) — justified by spec requirement
  for `openclaw manifest` and `openclaw uninstall` commands
- 0 new external dependencies
