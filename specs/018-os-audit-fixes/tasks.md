# Tasks: OS Audit FAIL Fixes

**Input**: Design documents from `/specs/018-os-audit-fixes/`
**Prerequisites**: plan.md (required), spec.md (required)

**Tests**: Not applicable — verification via `make audit`.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

**Purpose**: Verify prerequisites and capture baseline

- [ ] T001 Run `make audit` (or `sudo bash scripts/hardening-audit.sh`) and capture the current FAIL count — expect at least 4 FAILs for CHK-GUEST, CHK-SHARING-REMOTE-EVENTS, CHK-LAUNCHD-AUDIT-JOB, CHK-LOG-DIR
- [ ] T002 Verify launchd plist exists at `scripts/launchd/com.openclaw.audit-cron.plist`
- [ ] T003 Verify TCC Full Disk Access is granted to Terminal (System Settings → Privacy & Security → Full Disk Access) — needed for Remote Apple Events fix

---

## Phase 2: Foundational (Plist Installation)

**Purpose**: Install the launchd plist prerequisite that CHK-LAUNCHD-AUDIT-JOB needs

- [ ] T004 Install audit plist: `sudo cp scripts/launchd/com.openclaw.audit-cron.plist /Library/LaunchDaemons/ && sudo chown root:wheel /Library/LaunchDaemons/com.openclaw.audit-cron.plist && sudo chmod 644 /Library/LaunchDaemons/com.openclaw.audit-cron.plist`

**Checkpoint**: Plist installed — `make fix` can now bootstrap it

---

## Phase 3: User Story 1 - Apply Safe Fixes (Priority: P1)

**Goal**: All 4 audit checks change from FAIL to PASS

**Independent Test**: Run `make audit` — the 4 checks now PASS

### Implementation for User Story 1

- [ ] T005 [US1] Run `make fix` (or `sudo bash scripts/hardening-fix.sh --auto`) to apply all SAFE fixes
- [ ] T006 [US1] Verify CHK-GUEST passes: `sudo defaults read /Library/Preferences/com.apple.loginwindow GuestEnabled` returns 0
- [ ] T007 [US1] Verify CHK-SHARING-REMOTE-EVENTS passes: `sudo systemsetup -getremoteappleevents` reports "off"
- [ ] T008 [US1] Verify CHK-LAUNCHD-AUDIT-JOB passes: `launchctl list com.openclaw.audit-cron` returns success
- [ ] T009 [US1] Verify CHK-LOG-DIR passes: `test -d /opt/n8n/logs/audit && test -w /opt/n8n/logs/audit`
- [ ] T010 [US1] Run full `make audit` and confirm the 4 checks now PASS (and no other checks changed status)

**Checkpoint**: Clean audit baseline — 4 fewer FAILs

---

## Phase 4: User Story 2 - Verify Rollback (Priority: P2)

**Goal**: Confirm restore scripts were generated and work

**Independent Test**: Run `make fix-undo --list` — see rollback entries for the applied fixes

### Implementation for User Story 2

- [ ] T011 [US2] Verify restore script exists: `ls -la /opt/n8n/logs/audit/pre-fix-restore-*.sh`
- [ ] T012 [US2] Inspect restore script contents to confirm rollback commands are correct for CHK-GUEST and CHK-SHARING-REMOTE-EVENTS

**Checkpoint**: Rollback capability confirmed

---

## Phase 5: Polish & Verification

- [ ] T013 Run final `make audit` to confirm clean baseline
- [ ] T014 Verify no files in the git repo were modified (this is an operational task, no code changes): `git status`

---

## Dependencies & Execution Order

- **Phase 1**: No dependencies — T001, T002, T003 can run in parallel
- **Phase 2**: Depends on Phase 1 (plist must be verified before installation)
- **Phase 3 (US1)**: Depends on Phase 2 (plist must be installed before make fix)
- **Phase 4 (US2)**: Depends on US1 (fixes must be applied before rollback can be verified)
- **Phase 5**: Depends on all user stories

### Parallel Opportunities

- T006, T007, T008, T009 (individual fix verification) can all run in parallel after T005

---

## Notes

- This feature requires INTERACTIVE operator participation — sudo is required, TCC may need granting
- No files in the git repo are modified — all changes are to the OS/system state
- The implementation uses ONLY existing make targets (fix, fix-undo, audit) — no new code
- If any fix fails (e.g., TCC not granted for Remote Apple Events), document the failure and proceed with remaining fixes

## Adversarial Review #3

| Aspect | Finding |
|--------|---------|
| Highest-risk task | T005 (`make fix`) — applies system-level changes that affect daily-driver Mac behavior |
| Most likely rework | T003/T007 (TCC check / Remote Apple Events) — may need TCC grant before fix succeeds |
| Security | These ARE security fixes — reducing attack surface by disabling guest access and remote events |
| 3am scenario | N/A — operator-initiated, requires sudo interaction |
| 6-month neglect | Fixes persist across reboots. No maintenance needed unless OS updates reset settings. |

**READY FOR IMPLEMENTATION** — 0 CRITICAL, 0 HIGH. All 6 requirements covered by 14 tasks.
