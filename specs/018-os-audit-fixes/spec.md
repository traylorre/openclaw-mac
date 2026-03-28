# Feature Specification: OS Audit FAIL Fixes

**Feature Branch**: `018-os-audit-fixes`
**Created**: 2026-03-28
**Status**: Draft
**Input**: Fix 4 pre-existing audit FAILs using existing automated fixes in hardening-fix.sh (all SAFE). Auto-rollback generated.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Apply Safe OS Hardening Fixes (Priority: P1)

As the platform operator, I need the 4 pre-existing audit FAILs resolved so that `make audit` reports a clean baseline, allowing me to detect new regressions rather than being desensitized to persistent false failures.

**Why this priority**: Persistent FAILs create alert fatigue. When 4 checks always fail, operators learn to ignore the audit output — which means they'll also ignore a real security regression. A clean baseline is essential for the audit system to function as intended.

**Independent Test**: Run `make audit` before fixes — observe 4 FAILs. Run `make fix`. Run `make audit` again — the 4 checks now PASS.

**Acceptance Scenarios**:

1. **Given** CHK-GUEST fails (guest account enabled), **When** `make fix` runs, **Then** the guest account is disabled and CHK-GUEST passes on next audit.
2. **Given** CHK-SHARING-REMOTE-EVENTS fails (Remote Apple Events on), **When** `make fix` runs, **Then** Remote Apple Events is disabled and the check passes.
3. **Given** CHK-LAUNCHD-AUDIT-JOB fails (audit plist not loaded), **When** `make fix` runs, **Then** the plist is bootstrapped into launchd and the check passes.
4. **Given** CHK-LOG-DIR fails (audit log directory not writable), **When** `make fix` runs, **Then** the directory is created with correct permissions and the check passes.

---

### User Story 2 - Verify Rollback Capability (Priority: P2)

As the platform operator, I need a rollback script generated automatically when fixes are applied, so that I can revert any change that causes unexpected issues on my daily-driver Mac.

**Why this priority**: Even SAFE fixes should be reversible. The rollback script provides a safety net for the operator.

**Independent Test**: After `make fix`, verify a restore script exists in `/opt/n8n/logs/audit/`. Run `make fix-undo --list` to see available rollback options.

**Acceptance Scenarios**:

1. **Given** `make fix` has been run, **When** the operator checks for restore scripts, **Then** a `pre-fix-restore-*.sh` file exists with rollback commands for each applied fix.
2. **Given** a restore script exists, **When** the operator runs `make fix-undo`, **Then** the fixes are reverted and the original state is restored.

---

### Edge Cases

- What if the launchd plist doesn't exist on disk? The fix function returns SKIPPED with instructions to install it first (see HARDENING.md §10.1).
- What if Remote Apple Events `systemsetup` requires TCC Full Disk Access? The fix may fail with a permission error — the operator must grant Terminal Full Disk Access in System Settings.
- What if the audit log directory already exists but is not writable? The fix adjusts permissions (chmod 755) rather than recreating.
- What if `make fix` is run without sudo? The hardening-fix.sh script requires sudo for system-level changes.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `make fix` MUST apply all 4 SAFE fixes: CHK-GUEST, CHK-SHARING-REMOTE-EVENTS, CHK-LAUNCHD-AUDIT-JOB, CHK-LOG-DIR.
- **FR-002**: Each fix MUST be classified as SAFE in the hardening-fix.sh FIX_REGISTRY.
- **FR-003**: A pre-fix restore script MUST be generated automatically before any changes are applied.
- **FR-004**: After fixes are applied, `make audit` MUST show all 4 checks passing.
- **FR-005**: The operator MUST be able to selectively undo fixes via `make fix-undo`.
- **FR-006**: The fix process MUST NOT modify any settings beyond the 4 specified checks.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The 4 specified audit checks change from FAIL to PASS after running `make fix`.
- **SC-002**: A restore script is generated in `/opt/n8n/logs/audit/` after `make fix`.
- **SC-003**: Running `make fix-undo --all` reverts all 4 changes and the checks return to FAIL.
- **SC-004**: No other audit checks change status (no collateral damage).

## Assumptions

- All 4 fixes are already implemented in `scripts/hardening-fix.sh` and classified as SAFE.
- The `make fix`, `make fix-interactive`, and `make fix-undo` targets already exist in the Makefile.
- The operator will run the fixes with sudo access.
- TCC Full Disk Access may be needed for the Remote Apple Events fix — the operator will handle this manually if prompted.
- The launchd plist file (`com.openclaw.audit-cron.plist`) exists in `scripts/launchd/` and needs to be installed to `/Library/LaunchDaemons/` before it can be bootstrapped.

## Clarifications

### Session 2026-03-28

No critical ambiguities. All 4 fixes are pre-existing in hardening-fix.sh. This is an operational task (run existing tooling), not a code-writing task.

## Adversarial Review #1

| Severity | Finding | Resolution |
|----------|---------|------------|
| MEDIUM | CHK-LAUNCHD-AUDIT-JOB fix will SKIP if the plist is not installed in /Library/LaunchDaemons/. The plist must be copied from scripts/launchd/ first. | Add a prerequisite step: install the plist before running make fix. The fix function handles the "plist exists but not loaded" case. |
| MEDIUM | Remote Apple Events fix requires TCC Full Disk Access for Terminal. If not granted, systemsetup fails silently or with permission error. | Document as a prerequisite. The operator must verify TCC access before running. This is an OS-level constraint, not something the script can work around. |
| LOW | The restore script captures pre-fix state, but CHK-LAUNCHD-AUDIT-JOB has no meaningful restore (launchctl unload is idempotent). | Acceptable — the restore mechanism is best-effort for launchd operations. |

**Gate: 0 CRITICAL, 0 HIGH remaining.**
