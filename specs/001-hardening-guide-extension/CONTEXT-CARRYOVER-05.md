# Context Carryover 05: Blind Spots Patched + 002 Bugs Fixed + Deep Dive Started

**Feature Branch:** `001-hardening-guide-extension`
**Date:** 2026-03-11
**Spec Revision:** Rev 29 (unchanged)
**Constitution Version:** 1.3.0 (unchanged)
**Current Branch:** `002-context-auto-rotation` (working on 001 spec via `SPECIFY_FEATURE` override)

## Project: openclaw-mac

**Repo:** `https://github.com/traylorre/openclaw-mac`
**Purpose:** macOS hardening guides + audit tooling for Mac Mini running n8n + Apify for LinkedIn lead gen

## Session Summary

This session completed three things:

### 1. Patched All 14 Blind Spots Into Plan Artifacts

All 14 blind spots from CONTEXT-CARRYOVER-04.md have been applied:

| BS | File Patched | What Changed |
|----|-------------|-------------|
| BS-01 (CRITICAL) | plan.md | Added "Testing Strategy" section — section-by-section MacBook validation |
| BS-02 (HIGH) | plan.md, quickstart.md | Multi-PR delivery strategy with PR sequence table |
| BS-03 (MEDIUM) | plan.md | Added `scripts/templates/n8n-entrypoint.sh` to project structure |
| BS-04 (MEDIUM) | research.md | Added R-012 — Docker Compose `file:` source secrets only |
| BS-05 (MEDIUM) | research.md | Added R-013 — iptables persistence via Lima provisioning script |
| BS-06 (MEDIUM) | audit-script-cli.md | Added subshell trap pattern design decision for `set -euo pipefail` |
| BS-07 (LOW) | guide-structure.md | Renamed §3.3 to "Outbound Filtering" (removed "pf + LuLu") |
| BS-08 (LOW-MED) | plan.md | Added FR → §X.Y mapping table (90 FRs across ~55 sections) |
| BS-09 (LOW) | audit-script-cli.md | Added SKIP status to output format and JSON schema |
| BS-10 (LOW) | plan.md | Marked SONOMA-HARDENING.md as DEPRECATED with redirect |
| BS-11 (LOW) | plan.md | Added minimum n8n version v2.0+ to technical context |
| BS-12 (LOW) | plan.md | Acknowledged educational FR exceptions (FR-083, FR-087, FR-044) |
| BS-13 (LOW) | plan.md | Added SMTP relay as external dependency |
| BS-14 (LOW) | data-model.md | Changed Credential ↔ Deployment Path to many-to-many |

### 2. Fixed Two 002 Context Auto-Rotation Bugs

User reported three issues from previous session:
1. `/clear` did not auto-fire despite running in tmux
2. After manual `/clear`, context was not auto-loaded
3. Had to manually specify next steps

**Root causes found and fixed:**

**Bug 1: Poller stale prompt detection (0s elapsed)**
- The poller spawns BEFORE `continue:false` is output by detect hook
- First `tmux capture-pane` matches stale prompt from previous interaction
- `/clear` sent prematurely while model still processing the stop
- **Fix:** Added `sleep 3` before poll loop in `~/dotfiles/scripts/bin/carryover-poller.sh`

**Bug 2: Loader uses branch-derived spec dir, misses SPECIFY_FEATURE override**
- Loader derives `specs/002-context-auto-rotation/` from branch name
- CARRYOVER was written to `specs/001-hardening-guide-extension/` (via SPECIFY_FEATURE)
- Loader never finds the carryover file
- **Fix:** Detect hook now writes actual spec dir (dirname of CARRYOVER file) into `carryover-pending` instead of just `touch`. Loader reads this as spec dir override before searching.
- Files changed: `carryover-detect.sh`, `carryover-loader.sh`, `carryover-poller.sh`
- All pass shellcheck (only known SC2034 false positive for HOOK_LOG_PREFIX)

### 3. Deep Dive Started (INCOMPLETE — context exhausted)

User requested: "deep dive and cross-reference spec vs plan for gaps and over-engineering"

**What was read before guardian blocked:**
- spec.md: FULL (1399 lines) — all user stories, edge cases, meta-FRs, FR index, key entities, success criteria, assumptions
- spec-n8n-platform.md: FULL (393 lines) — FR-011, FR-038, FR-039, FR-044, FR-054, FR-055, FR-059, FR-064, FR-066, FR-067
- spec-data-security.md: FULL (653 lines) — FR-012, FR-013, FR-021, FR-040, FR-043, FR-047, FR-049, FR-057, FR-060, FR-071, FR-083, FR-087, FR-090
- spec-macos-platform.md: PARTIAL (200 of ~600 lines) — FR-016, FR-017, FR-028, FR-029, FR-030, FR-032, FR-033, FR-034 read; remaining FRs NOT read
- spec-audit-ops.md: NOT READ

**What was NOT read:**
- spec-macos-platform.md lines 200+: FR-035, FR-036, FR-041, FR-042, FR-048, FR-050-053, FR-058, FR-061-062, FR-068-070, FR-073, FR-076, FR-079-080, FR-082, FR-084-086, FR-089
- spec-audit-ops.md: ALL FRs — FR-007, FR-018, FR-020, FR-022-027, FR-031, FR-037, FR-045-046, FR-056, FR-063, FR-065, FR-072, FR-074-075, FR-077-078, FR-081, FR-088

**All plan artifacts were already read in full:**
- plan.md (with all BS patches applied)
- research.md (with R-012, R-013 added)
- data-model.md (with BS-14 fix)
- contracts/audit-script-cli.md (with BS-06, BS-09 patches)
- contracts/guide-structure.md (with BS-07 patch)
- quickstart.md (with BS-02 patch)

**Preliminary observations from what was read (analysis NOT complete):**

The spec is extremely thorough — 90 FRs, 43 success criteria, 9 user stories, ~80 edge cases. The plan artifacts are solid but the cross-reference was interrupted. The next session should:

1. Read the remaining unread spec modules (spec-macos-platform.md 200+, spec-audit-ops.md full)
2. Complete the gap analysis: spec FRs vs plan coverage, plan items with no spec backing
3. Look specifically for over-engineering (plan artifacts that add complexity beyond what spec requires)
4. Then run `/speckit.tasks` for 001

### 4. Memory Updated

- Created `MEMORY.md` index in memory dir
- Added `user_macbook_test_env.md` pointer (was created last session, index missing)
- Created `feedback_002_rotation_bugs.md` — documents poller stale prompt + branch/spec mismatch bugs

## Key Files

| File | Status |
|------|--------|
| `specs/001-hardening-guide-extension/plan.md` | All 14 BS patches applied |
| `specs/001-hardening-guide-extension/research.md` | R-012, R-013 added |
| `specs/001-hardening-guide-extension/data-model.md` | BS-14 fixed |
| `specs/001-hardening-guide-extension/contracts/audit-script-cli.md` | BS-06, BS-09 applied |
| `specs/001-hardening-guide-extension/contracts/guide-structure.md` | BS-07 applied |
| `specs/001-hardening-guide-extension/quickstart.md` | BS-02 applied |
| `~/dotfiles/scripts/bin/carryover-detect.sh` | Bug fix: writes spec dir to pending |
| `~/dotfiles/scripts/bin/carryover-poller.sh` | Bug fix: sleep 3 before poll loop |
| `~/dotfiles/scripts/bin/carryover-loader.sh` | Bug fix: reads spec dir override from pending |

## Git Status (uncommitted)

Modified in openclaw-mac:
- `CLAUDE.md` (minor)
- `specs/001-hardening-guide-extension/plan.md` (BS patches)
- `specs/001-hardening-guide-extension/research.md` (R-012, R-013)
- `specs/001-hardening-guide-extension/data-model.md` (BS-14)
- `specs/001-hardening-guide-extension/contracts/audit-script-cli.md` (BS-06, BS-09)
- `specs/001-hardening-guide-extension/contracts/guide-structure.md` (BS-07)
- `specs/001-hardening-guide-extension/quickstart.md` (BS-02)
- New: `specs/001-hardening-guide-extension/CONTEXT-CARRYOVER-05.md` (this file)

Modified in ~/dotfiles/scripts/bin/:
- `carryover-detect.sh` (bug fix)
- `carryover-poller.sh` (bug fix)
- `carryover-loader.sh` (bug fix)

## What's Next

1. **Finish the deep dive**: Read remaining spec modules, complete spec↔plan cross-reference
2. **Look for gaps and over-engineering** in plan artifacts vs spec requirements
3. **Run `/speckit.tasks`** for 001 after analysis is complete
4. **Commit** the BS patches and 002 bug fixes (two separate commits — different repos/features)
