# Tasks: NoMOOP (No Matter Out Of Place)

**Input**: Design documents from `/specs/009-nomoop/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/cli-commands.md

**Tests**: Not explicitly requested. Tasks include manual verification steps at checkpoints.

**Organization**: Tasks grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Exact file paths included in descriptions

## Path Conventions

- Scripts: `scripts/` at repository root
- Library: `scripts/lib/` (new)
- Specs: `specs/009-nomoop/`

---

## Phase 1: Setup

**Purpose**: Create directory structure and script skeletons

- [x] T001 Create `scripts/lib/` directory and `scripts/lib/manifest.sh` skeleton with `set -euo pipefail`, color output functions (matching bootstrap.sh pattern), and function stubs for all manifest operations
- [x] T002 [P] Create `scripts/openclaw.sh` dispatcher skeleton with usage/help/version flags, command routing for `manifest` and `uninstall` subcommands, and `report()` function matching bootstrap.sh/gateway-setup.sh pattern

---

## Phase 2: Foundational (Manifest Library)

**Purpose**: Core manifest CRUD and helper functions that ALL user stories depend on

**CRITICAL**: No user story work can begin until this phase is complete

- [x] T003 Implement `manifest_init()` and `manifest_lock()` in `scripts/lib/manifest.sh` — `manifest_init()`: create `~/.openclaw/` directory (mode 700), initialize empty `manifest.json` (mode 600) with version "1.0.0", repo_root (auto-detected from script location), created_at/updated_at timestamps, and empty artifacts array. No-op if manifest already exists. Uses jq for JSON creation (atomic write per FR-021). `manifest_lock()`: acquire `flock -n /tmp/openclaw-manifest.lock` at script start; exit with clear error "Another openclaw process is running" if lock is held. All consumer scripts call manifest_lock() before any manifest operations.
- [x] T004 Implement `manifest_add()`, `manifest_begin_step()`, and `manifest_complete_step()` in `scripts/lib/manifest.sh` — `manifest_add()` appends entry with status="installed" (for pre-existing/skip cases) or status="skipped". `manifest_begin_step()` adds entry with status="pending" BEFORE the action executes. `manifest_complete_step()` updates status to "installed" AFTER success. On re-run, both functions check if entry exists: if status="installed", verify artifact on disk and skip; if status="pending", retry the action. All entries include fields: id, type, category (tooling/hardening), path, version, checksum, installed_at, installed_by, pre_existing, removable, status, notes. Validate id uniqueness. Update updated_at timestamp. CRITICAL per FR-021: ALL jq writes MUST use atomic write pattern: `jq '...' manifest.json > manifest.json.tmp && mv manifest.json.tmp manifest.json`. Never write directly to manifest.json. Also implement `manifest_setup_traps()` per FR-022: set `trap 'echo "Interrupted. Re-run to resume." >&2; exit 130' INT HUP TERM` — all consumer scripts call this at startup. Also implement `manifest_sudo_keepalive()` and `manifest_sudo_keepalive_stop()` per FR-024: start a background `while true; do sudo -v; sleep 240; done &` loop, capture PID, kill on exit via trap.
- [x] T005 [P] Implement `manifest_has()` and `manifest_get()` in `scripts/lib/manifest.sh` — `manifest_has <id>` returns 0/1. `manifest_get <id> [field]` returns entry JSON or specific field value. Uses jq queries on `~/.openclaw/manifest.json`.
- [x] T006 [P] Implement `manifest_update()` in `scripts/lib/manifest.sh` — update fields of existing entry by id: `manifest_update <id> <field> <value>`. Supports status, checksum, notes, removable fields. Uses jq select-and-update.
- [x] T007 [P] Implement `manifest_checksum()` in `scripts/lib/manifest.sh` — compute SHA-256 of a file via `shasum -a 256`, return hex string. Handle non-existent files gracefully (return empty string). Per research R-002.
- [x] T008 Implement `manifest_detect_preexisting()` in `scripts/lib/manifest.sh` — for brew packages: check `brew list <pkg> 2>/dev/null`; for files/dirs: check `[[ -e "$path" ]]`; for commands: check `command -v <cmd>`. Returns 0 (pre-existing) or 1 (new). Per research R-003.
- [x] T009 [P] Implement `manifest_detect_shell()` in `scripts/lib/manifest.sh` — read `$SHELL`, validate it is bash or zsh. If `$SHELL` is ksh, fish, or unknown: warn operator and default to `~/.zshrc` (macOS default since Catalina). Return correct rc file path: bash → `~/.bash_profile`, zsh → `~/.zshrc`. Validate file exists (create if not). Per research R-004.
- [x] T010 Implement `shellrc_setup()` in `scripts/lib/manifest.sh` — create `~/.openclaw/shellrc` with header comment, openclaw alias (pointing to repo scripts/openclaw.sh), and n8n-token alias. Add guarded source line `[ -f ~/.openclaw/shellrc ] && source ~/.openclaw/shellrc` to detected shell rc file (skip if already present). Track both `shell-rc-file` and `shell-config-line` artifacts in manifest via `manifest_add()`. Per FR-008, FR-009.

**Checkpoint**: Manifest library complete. Run `shellcheck scripts/lib/manifest.sh` — zero warnings required.

---

## Phase 3: User Story 1 — Fresh Install With Manifest Tracking (Priority: P1) MVP

**Goal**: Every artifact placed on the system by bootstrap.sh, gateway-setup.sh, and hardening-fix.sh is recorded in the manifest. Operator can view what's installed.

**Independent Test**: Run `bash scripts/bootstrap.sh`, then `bash scripts/openclaw.sh manifest`. Verify every artifact in the table corresponds to a real file/package on disk.

### Implementation for User Story 1

- [x] T011 [US1] Integrate manifest tracking into `scripts/bootstrap.sh` — source `lib/manifest.sh`, call `manifest_setup_traps()`, `manifest_lock()`, and `manifest_sudo_keepalive()` at start (FR-021, FR-022, FR-024). Add disk space pre-flight check: `df -g / | awk 'NR==2{print $4}'`, warn if <8GB. IMPORTANT: reorder check_tools() to install jq FIRST (before bash) so manifest operations are available for all subsequent steps. Wrap `brew install` calls with `timeout 300` to prevent indefinite hangs on network issues. After jq is confirmed: call `manifest_init()`, then retroactively record jq in manifest (with correct pre_existing flag). Use `manifest_begin_step()`/`manifest_complete_step()` pattern for each artifact. Record version for brew packages via `brew info --json <pkg> | jq -r '.[0].installed[0].version'` (FR-023). Artifact types: brew packages (bash, colima, docker, docker-compose) with type=brew-package, category=tooling; directories (/opt/n8n/*) with type=directory; deployed scripts with type=file and checksum; launchd plist with type=launchd-plist; notify.conf with type=file; /etc/shells line with type=system-config-line, category=hardening. Call `shellrc_setup()` at end. Call `manifest_sudo_keepalive_stop()` in exit trap.
- [x] T012 [P] [US1] Integrate manifest tracking into `scripts/gateway-setup.sh` — source `lib/manifest.sh`. Use `manifest_begin_step()`/`manifest_complete_step()` pattern for each artifact: `colima start` → type=colima-vm, category=tooling. `docker compose up -d` → type=docker-container and type=docker-volume, category=tooling. Secrets generation → type=file. Keychain entry (documented in manual steps) → type=keychain-entry. Docker image pull → type=docker-image.
- [x] T013 [P] [US1] Integrate manifest tracking into `scripts/hardening-fix.sh` — source `lib/manifest.sh`. Use `manifest_begin_step()`/`manifest_complete_step()` pattern in fix functions that create artifacts: `fix_ssh_hardening` → type=system-config-file, category=hardening, path=/etc/ssh/sshd_config.d/hardening.conf. `fix_chromium_policy` → type=managed-preference, category=hardening. `fix_n8n_service_account` → type=system-account, category=hardening. `fix_pf_rules` → type=system-config-file + type=system-config-line, category=hardening. `fix_spotlight` → type=spotlight-exclusion, category=hardening.
- [x] T014 [US1] Implement `openclaw manifest` display command in `scripts/openclaw.sh` — read `~/.openclaw/manifest.json`, display formatted table with TYPE, PATH, CATEGORY, STATUS columns. Show artifact count header and repo_root. Handle missing manifest gracefully ("No manifest found — run bootstrap.sh first"). Per contracts/cli-commands.md output format.
- [x] T015 [US1] Implement `openclaw manifest --json` flag in `scripts/openclaw.sh` — output raw manifest JSON to stdout for scripting. Composable with --verify (Phase 7).

**Checkpoint**: US1 complete. Run bootstrap.sh on a system, then `openclaw manifest`. Every entry in the table should correspond to a real artifact on disk. Run bootstrap.sh again — manifest should not have duplicate entries (FR-004 idempotency).

---

## Phase 4: User Story 2 — Clean Uninstall (Priority: P1)

**Goal**: Operator runs `openclaw uninstall` and all tracked artifacts are removed. System returns to pre-install state.

**Independent Test**: Install fully, then `openclaw uninstall`. Verify only `~/.openclaw/uninstall-report.txt` remains.

### Implementation for User Story 2

- [x] T016 [US2] Implement artifact removal functions in `scripts/lib/manifest.sh` — one function per artifact type: `remove_brew_package()` (check `brew uses --installed` per FR-007, skip if shared), `remove_file()` (sudo if needed, backup if drifted), `remove_directory()` (recursive, sudo if needed), `remove_shell_config_line()` (sed removal from rc file), `remove_shell_rc_file()`, `remove_keychain_entry()` (security delete-generic-password), `remove_launchd_plist()` (launchctl bootout then rm), `remove_docker_container()` (docker rm -f), `remove_docker_volume()` (docker volume rm), `remove_docker_image()` (docker rmi), `remove_colima_vm()` (colima delete), `remove_system_account()` (sysadminctl -deleteUser), `remove_system_config_file()` (backup + sudo rm), `remove_system_config_line()` (sudo sed), `remove_managed_preference()` (sudo rm), `remove_spotlight_exclusion()` (sudo mdutil -i on). Each returns 0=removed, 1=skipped, 2=failed.
- [x] T017 [US2] Implement sudo handling in `scripts/openclaw.sh` uninstall flow — at start: list which steps need elevation, run `sudo -v` to cache credentials (FR-016). Call `manifest_sudo_keepalive()` for background refresh (FR-024). Implement `--confirm` flag: before each sudo command, display the command and prompt `Execute? [y/N]` (FR-017). Call `manifest_sudo_keepalive_stop()` in exit trap.
- [x] T018 [US2] Implement `openclaw uninstall` core logic in `scripts/openclaw.sh` — read manifest, filter to removable entries, process in reverse installation order (per research R-006). IMPORTANT per FR-006: reverse order ensures Docker containers are stopped/removed before volumes, and Colima is stopped before its VM is deleted — verify this ordering explicitly. For each entry: check pre_existing (skip), check category vs --keep-hardening (skip if kept), call appropriate remove_* function, display progress `[N/M]` with colored output, update manifest entry status to "removed". Handle --force (skip confirmation), --dry-run (display only), --keep-data (skip docker-volume type).
- [x] T019 [US2] Implement hardening artifact warnings in `scripts/openclaw.sh` uninstall — before removing any hardening-category artifact, display security implication warning per FR-019: system-config-file (SSH) → "This re-enables SSH password authentication", system-config-line (pf) → "This weakens the firewall", managed-preference → "This loosens Chromium browser policy", system-account → "This may orphan files owned by _n8n". Use YELLOW colored output.
- [x] T020 [US2] Implement uninstall report and backup in `scripts/openclaw.sh` — generate `~/.openclaw/uninstall-report.txt` with sections: REMOVED, SKIPPED (pre-existing), SKIPPED (shared), KEPT (hardening, if --keep-hardening), BACKED UP (drifted files), MANUAL CLEANUP REQUIRED. Before removing drifted files: copy to `~/.openclaw/backups/<ISO-timestamp>/<original-path>` (FR-015). Report format per data-model.md uninstall report entity.

**Checkpoint**: US2 complete. Full install → `openclaw uninstall` → verify only `~/.openclaw/uninstall-report.txt` and (optional) `~/.openclaw/backups/` remain. Pre-existing packages untouched (SC-004). Shared packages not removed (FR-007).

---

## Phase 5: User Story 3 — Interrupted Install/Uninstall Recovery (Priority: P2)

**Goal**: Interrupted install or uninstall can be resumed by re-running the same command.

**Independent Test**: Start bootstrap.sh, Ctrl+C midway, re-run. Verify no duplicates and remaining steps complete.

### Implementation for User Story 3

- [x] T021 [US3] Verify interrupt recovery end-to-end in `scripts/bootstrap.sh` — the `manifest_begin_step()`/`manifest_complete_step()` pattern (implemented in T004, used by T011-T013) already enables resume. This task validates the full flow: start bootstrap, Ctrl+C at step 4, re-run, confirm steps 1-3 are verified (not re-executed) and steps 4+ proceed. Fix any edge cases found (e.g., partial jq writes, interrupted sudo operations). Per FR-013, research R-005.
- [x] T022 [US3] Implement `openclaw manifest --rebuild` in `scripts/openclaw.sh` — scan hardcoded list of known artifact locations (all paths from bootstrap.sh, gateway-setup.sh, hardening-fix.sh artifact creation points), check each on disk, reconstruct manifest entries with best-effort field values (type from path pattern, checksum for files, category from location). Report found/not-found counts. Per FR-012.

**Checkpoint**: US3 complete. Interrupt bootstrap.sh at step 4, re-run — steps 1-3 verified (not re-executed), steps 4-8 proceed. Delete manifest, run `openclaw manifest --rebuild` — manifest reconstructed from disk state.

---

## Phase 6: User Story 4 — Shell Config Isolation (Priority: P2)

**Goal**: All openclaw shell additions live in `~/.openclaw/shellrc`. Only one source line in the operator's shell config.

**Independent Test**: Install, check shell config has exactly one openclaw line. Uninstall, verify that line is gone.

### Implementation for User Story 4

- [x] T023 [US4] Update `scripts/gateway-setup.sh` step_manual() to remove manual alias instructions — replace "Add alias to ~/.bashrc or ~/.bash_profile" instructions with note that aliases are automatically configured in `~/.openclaw/shellrc`. The `shellrc_setup()` call (from T010) already handles creation.
- [x] T024 [US4] Implement shell config migration in `scripts/lib/manifest.sh` — add `shellrc_migrate()` function that scans operator's shell rc file for existing openclaw-related lines (n8n-token alias, openclaw alias, any line containing "openclaw" or "n8n-gateway-bearer"), moves them to `~/.openclaw/shellrc`, and removes originals. Called during bootstrap.sh for operators upgrading from pre-NoMOOP installs.

**Checkpoint**: US4 complete. Install, run `grep -c openclaw ~/.bash_profile` — result is 1 (only the source line). Uninstall, run same grep — result is 0. Open new shell — no openclaw aliases defined.

---

## Phase 7: User Story 5 — Manifest Inspection and Drift Detection (Priority: P3)

**Goal**: Operator can verify installed artifacts and detect drift (modifications or deletions since install).

**Independent Test**: Install, modify `/opt/n8n/etc/notify.conf`, run `openclaw manifest --verify`. See DRIFTED for that file.

### Implementation for User Story 5

- [x] T025 [US5] Implement `openclaw manifest --verify` in `scripts/openclaw.sh` — iterate manifest entries, check each against disk: files → exists + checksum comparison, brew-packages → `brew list` + version comparison via `brew info --json`, directories → `-d`, docker → `docker ps`/`docker volume ls` + image tag check, keychain → `security find-generic-password`, colima → `colima status` + `colima version`, launchd → file exists + `launchctl print`. Report PRESENT, MISSING, DRIFTED (checksum changed), or VERSION_DRIFT (version changed but artifact present) per FR-023. Print summary line: "N PRESENT, N DRIFTED, N VERSION_DRIFT, N MISSING". Exit 0 if all present with matching versions, 1 otherwise. Per FR-011, FR-023.
- [x] T026 [US5] Implement `openclaw manifest --verify --json` combined flag in `scripts/openclaw.sh` — output verify results as JSON array with entry id, path, type, verify_status, expected_checksum, current_checksum fields. Useful for piping to jq or M2 trust audit agent.

**Checkpoint**: US5 complete. Install, verify all PRESENT. Modify a file, verify shows DRIFTED. Delete a tracked file, verify shows MISSING. `--json` output parseable with jq.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Features that span multiple user stories and final validation

- [x] T027 [P] Implement `openclaw install --hardening-only` flag in `scripts/openclaw.sh` — dispatch to `hardening-fix.sh` with manifest tracking enabled, skip bootstrap/gateway steps. Records only hardening-category artifacts. Per FR-020.
- [x] T028 [P] Run `shellcheck` on all new and modified scripts — `scripts/lib/manifest.sh`, `scripts/openclaw.sh`, `scripts/bootstrap.sh`, `scripts/gateway-setup.sh`, `scripts/hardening-fix.sh`. Fix all warnings to zero. Per constitution Principle VI.
- [x] T029 [P] Update `specs/009-nomoop/quickstart.md` with final verified command examples and any output format changes from implementation
- [ ] T030 End-to-end validation (MANUAL: requires running full install/uninstall cycle) — execute full operator journey: `bootstrap.sh` → `gateway-setup.sh` → `openclaw manifest` → modify a file → `openclaw manifest --verify` → `openclaw uninstall --dry-run` → `openclaw uninstall` → verify only report remains. Document any issues found.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 completion — BLOCKS all user stories
- **US1 (Phase 3)**: Depends on Phase 2 — MVP delivery
- **US2 (Phase 4)**: Depends on Phase 2 + US1 (needs populated manifest to uninstall from)
- **US3 (Phase 5)**: Depends on Phase 2 — can run parallel with US1
- **US4 (Phase 6)**: Depends on Phase 2 — can run parallel with US1
- **US5 (Phase 7)**: Depends on Phase 2 + US1 (needs populated manifest to verify)
- **Polish (Phase 8)**: Depends on all user stories being complete

### User Story Dependencies

- **US1 (P1)**: Depends on Foundational only — primary MVP target
- **US2 (P1)**: Depends on US1 (needs manifest entries to remove)
- **US3 (P2)**: Depends on Foundational only — can start parallel with US1
- **US4 (P2)**: Depends on Foundational only — can start parallel with US1
- **US5 (P3)**: Depends on US1 (needs manifest entries to verify)

### Within Each User Story

- Library functions before script integration
- Script integration before CLI commands
- Core logic before flags/options

### Parallel Opportunities

- Phase 1: T001 and T002 can run in parallel (different files)
- Phase 2: T005, T006, T007, T009 can run in parallel (independent functions in same file — different function blocks)
- Phase 3: T011, T012, T013 can run in parallel (different script files)
- Phase 4: All tasks sequential (same files, dependent logic)
- Phase 7: T025 and T026 sequential (T026 extends T025)
- Phase 8: T027, T028, T029 can run in parallel (different files)
- Cross-phase: US3 and US4 can start as soon as Phase 2 completes (don't need to wait for US1)

---

## Parallel Example: User Story 1

```bash
# After Phase 2 (Foundational) completes, launch all script integrations in parallel:
Task: "T011 [US1] Integrate manifest tracking into scripts/bootstrap.sh"
Task: "T012 [US1] Integrate manifest tracking into scripts/gateway-setup.sh"
Task: "T013 [US1] Integrate manifest tracking into scripts/hardening-fix.sh"

# Then sequentially:
Task: "T014 [US1] Implement openclaw manifest display command"
Task: "T015 [US1] Implement openclaw manifest --json flag"
```

---

## Implementation Strategy

### MVP First (US1 Only)

1. Complete Phase 1: Setup (T001-T002)
2. Complete Phase 2: Foundational (T003-T010) — CRITICAL
3. Complete Phase 3: US1 (T011-T015)
4. **STOP and VALIDATE**: Run `bootstrap.sh`, then `openclaw manifest`. Every artifact tracked.
5. This alone delivers SC-002 (100% artifact tracking) and enables all other stories.

### Incremental Delivery

1. Setup + Foundational → Library ready
2. US1 → Manifest tracking live → Deploy (MVP!)
3. US2 → Clean uninstall works → Deploy (full install/uninstall cycle)
4. US3 → Interrupt recovery works → Deploy (robustness)
5. US4 → Shell config isolated → Deploy (clean shell experience)
6. US5 → Drift detection works → Deploy (audit capability)
7. Polish → Shellcheck clean, --hardening-only, end-to-end validated

### PR Strategy (Suggested)

- **PR 1**: Phase 1 + Phase 2 (library) — reviewable without side effects
- **PR 2**: Phase 3 (US1 bootstrap+gateway integration) — the big one
- **PR 3**: Phase 3 (US1 hardening-fix integration) — can be separate if large
- **PR 4**: Phase 4 (US2 uninstall) — operator-facing feature
- **PR 5**: Phase 5-7 (US3+US4+US5) — can bundle P2+P3 stories
- **PR 6**: Phase 8 (polish) — cleanup pass

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story is independently testable at its checkpoint
- Commit after each task or logical group
- All scripts must pass `shellcheck` (constitution Principle VI)
- All manifest JSON operations use `jq` (already a bootstrap dependency)
- Manifest file: `~/.openclaw/manifest.json` (mode 600)
- Manifest directory: `~/.openclaw/` (mode 700)
- 16 artifact types across 2 categories (tooling/hardening) — see spec taxonomy
