# Feature Specification: Prerequisite Validation (make doctor)

**Feature Branch**: `017-prerequisite-validation`
**Created**: 2026-03-28
**Status**: Draft
**Input**: New scripts/doctor.sh + make doctor Makefile target that checks ALL prerequisites with install instructions.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Validate All Prerequisites (Priority: P1)

As the platform operator, I need a single command (`make doctor`) that checks whether all required tools are installed and reports any gaps with install instructions, so that I can quickly diagnose environment issues without discovering missing tools at runtime (as happened with fswatch crashing the integrity monitor).

**Why this priority**: Runtime tool-not-found errors are the worst kind of failure — they happen when you need the tool, not when you're setting up. A proactive check prevents this class of error entirely.

**Independent Test**: Run `make doctor` on a correctly configured system — all checks pass. Temporarily rename a tool (e.g., `brew unlink fswatch`) and re-run — the missing tool is reported with install instructions.

**Acceptance Scenarios**:

1. **Given** all required tools are installed, **When** the operator runs `make doctor`, **Then** all checks display a pass indicator and the script exits with code 0.
2. **Given** one or more tools are missing, **When** the operator runs `make doctor`, **Then** all checks still run (no fail-on-first), each missing tool displays a fail indicator with install instructions, and the script exits with code 1.
3. **Given** a tool requires a minimum version (e.g., bash 5.x), **When** the installed version is below the minimum, **Then** the check fails with the current version, required version, and upgrade instructions.

---

### User Story 2 - Report Version Information (Priority: P2)

As the platform operator, I need `make doctor` to show the installed version of each tool alongside the check result, so that I can quickly assess whether tools are current without running separate version commands.

**Why this priority**: Version mismatches can cause subtle failures. Showing versions proactively helps catch issues before they manifest.

**Independent Test**: Run `make doctor` — each passing check shows the tool version (e.g., `bash 5.2.37`, `jq 1.7.1`).

**Acceptance Scenarios**:

1. **Given** a tool is installed, **When** `make doctor` runs, **Then** the pass line includes the installed version string.
2. **Given** a tool has a minimum version requirement, **When** the installed version meets or exceeds the requirement, **Then** the pass line shows the version in green.

---

### Edge Cases

- What if a tool is installed but not in PATH? The check uses `command -v` which only finds PATH-accessible tools. This is correct behavior — a tool not in PATH is effectively missing.
- What if the system has both macOS built-in and Homebrew versions (e.g., bash 3.x vs 5.x)? The version check validates the `command -v` result, which should be the Homebrew version if PATH is configured correctly.
- What if `security` (Keychain CLI) exists but Keychain access is denied? The check verifies command existence, not Keychain permissions. Permission issues are separate from prerequisite validation.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `scripts/doctor.sh` MUST check all required tools: bash 5.x, jq, shellcheck, docker, colima, fswatch, ollama, openssl, shasum, curl, security (Keychain CLI).
- **FR-002**: The script MUST report ALL missing tools at once (accumulate errors, not fail on first).
- **FR-003**: Each missing tool MUST include install instructions (e.g., `brew install fswatch`).
- **FR-004**: The script MUST check minimum version requirements where applicable (bash >= 5.0).
- **FR-005**: The script MUST use the existing `require_command()` function from `lib/common.sh` for tool existence checks.
- **FR-006**: The script MUST follow Constitution VI (set -euo pipefail, shellcheck clean, idempotent, colored output).
- **FR-007**: A `make doctor` target MUST be added to the Makefile.
- **FR-008**: The script MUST exit with code 0 if all checks pass, code 1 if any fail.
- **FR-009**: The script MUST use the bootstrap.sh accumulator pattern (OK/FAIL counters with summary line).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Running `make doctor` on a correctly configured system exits with code 0 and shows all tools as passing.
- **SC-002**: Running `make doctor` with a missing tool reports the specific tool with install instructions and exits with code 1.
- **SC-003**: The script checks all 11 required tools in a single run.
- **SC-004**: The script completes in under 5 seconds on a healthy system.

## Assumptions

- All 11 tools listed in FR-001 are the complete set of prerequisites for the current project state.
- `lib/common.sh` and its `require_command()` function are available and stable.
- The bootstrap.sh accumulator pattern (OK/FIXED/ERRORS counters) is the established project convention for reporting.
- shellcheck is available to validate the new script before merge.

## Clarifications

### Session 2026-03-28

No critical ambiguities. Tool list is explicit, output pattern is established (bootstrap.sh), and scope is bounded.

## Adversarial Review #1

| Severity | Finding | Resolution |
|----------|---------|------------|
| MEDIUM | FR-005 says use `require_command()` but that function returns 1 on failure (fail-on-first). The accumulator pattern (FR-009) needs to catch the return code without exiting due to `set -e`. | Implementation must use `require_command cmd hint || errors=$((errors + 1))` pattern to prevent `set -e` from aborting. Consistent with bootstrap.sh approach. |
| LOW | FR-001 lists 11 tools but the tool list may grow. No extensibility mechanism specified. | Acceptable for now — new tools can be added to the script as the project evolves. No extensibility framework needed for a single-file script. |
| LOW | Version checking (FR-004) is only specified for bash. Other tools may benefit from version checks in the future. | Start with bash 5.x only. Add version checks for other tools when minimum versions become relevant. |

**Gate: 0 CRITICAL, 0 HIGH remaining.**
