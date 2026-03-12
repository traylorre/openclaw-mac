# Context Carryover 04: Plan Complete + 14 Blind Spots Found

**Feature Branch:** `001-hardening-guide-extension`
**Date:** 2026-03-11
**Spec Revision:** Rev 29 (unchanged)
**Constitution Version:** 1.3.0 (unchanged)

## Project: openclaw-mac

**Repo:** `https://github.com/traylorre/openclaw-mac`
**Current Branch:** `002-context-auto-rotation` (but working on 001 spec via `SPECIFY_FEATURE` override)
**Purpose:** macOS hardening guides + audit tooling for Mac Mini running n8n + Apify for LinkedIn lead gen

## Session Summary

This session completed `/speckit.plan` for feature 001 and then performed a
deep blind spot analysis that found 14 issues, 7 of which need patching into
plan artifacts before `/speckit.tasks`.

### Work Completed

1. **Ran `/speckit.plan`** — generated all Phase 0 and Phase 1 artifacts:
   - `plan.md` — technical context, constitution check (pre + post-design), project structure
   - `research.md` — 11 research items resolved (n8n env vars, Docker secrets, Santa, Colima, pf, Apify, Tahoe changes)
   - `data-model.md` — 8 entities with fields, state transitions, relationships
   - `contracts/audit-script-cli.md` — CLI interface, output formats, deployment detection
   - `contracts/guide-structure.md` — 11 top-level sections, CIS-pattern section format
   - `quickstart.md` — prerequisites, build/verify commands, implementation order
   - `CLAUDE.md` — updated with 001 technology stack via `update-agent-context.sh`

2. **Deep blind spot analysis** — found 14 issues (analysis complete, patches NOT yet applied)

3. **Memory saved** — `user_macbook_test_env.md` created in memory dir but MEMORY.md index not yet updated

### Key Research Findings (already in research.md)

- n8n v2.0: `EXECUTIONS_PROCESS` removed; `ExecuteCommand` blocked by default; `N8N_BLOCK_ENV_ACCESS_IN_NODE` defaults `true`
- n8n `_FILE` suffix: partial support; `N8N_ENCRYPTION_KEY_FILE` has bugs — entrypoint wrapper needed
- `N8N_PUBLIC_API_ENABLED` → actually `N8N_PUBLIC_API_DISABLED` (naming inverted)
- n8n supports native TOTP 2FA (enforcement since v1.102.0)
- n8n node restriction: `NODES_EXCLUDE` env var with JSON array
- n8n webhook auth: None, Basic Auth, Header Auth, JWT Auth
- macOS pf CANNOT filter Colima container traffic (NAT'd through VM)
- Containerized outbound filtering: iptables inside Colima VM
- Apify: no HMAC webhook signing; URL-token approach only
- Santa moved to `northpolesec/santa` (google/santa archived)
- Colima: minimal security defaults; no AppArmor/seccomp beyond Docker defaults
- All Objective-See tools (LuLu, BlockBlock, KnockKnock) support Apple Silicon
- macOS Tahoe: stricter Gatekeeper, SIP, TCC, Local Network Privacy vs Sonoma

## 14 Blind Spots — PATCHES NEEDED

These were identified but NOT yet applied to plan artifacts. The next session
must patch these before running `/speckit.tasks`.

### CRITICAL

#### BS-01: WSL2 dev environment vs macOS target

- Dev is on WSL2; audit script uses macOS-only commands
- RESOLUTION: User has a fresh Sonoma MacBook (freshly wiped, nothing installed)
- MacBook is the perfect US-1 test environment
- ADVICE GIVEN: Don't clone yet — fresh state is more valuable as test subject
- STILL NEEDED: Add macOS testing strategy to plan (section-by-section delivery where user follows guide on fresh Mac as integration test)

### HIGH

#### BS-02: HARDENING.md as single ~5,000-line file

- Spec itself had to be split at 3,100 lines for context limits
- Guide will be bigger than the spec
- NEEDED: Multi-PR delivery strategy; consider splitting guide or implementing section-by-section
- OPPORTUNITY: Section-by-section delivery where user follows each section on fresh Mac = perfect integration test loop

### MEDIUM

#### BS-03: Missing deliverable — entrypoint wrapper script

- Research R-001 says docker-compose needs entrypoint wrapper for N8N_ENCRYPTION_KEY
- `scripts/templates/n8n-entrypoint.sh` not in project structure
- PATCH: Add to plan.md project structure

#### BS-04: Docker Compose `secrets:` requires file source, not Swarm

- Standalone `docker compose` (Colima) only supports `file:` source secrets
- Swarm-mode `external: true` won't work
- PATCH: Add research note R-012; ensure compose template uses `file:` source

#### BS-05: iptables persistence inside Colima VM

- iptables rules don't survive `colima stop/start` or `colima delete`
- No Colima mechanism to inject rules at VM boot
- PATCH: Add research note R-013; document persistence strategy (Lima config override or provisioning script)

#### BS-06: `set -euo pipefail` vs failing check commands

- Constitution mandates strict bash; but check commands intentionally fail
- PATCH: Add design decision to audit contract — check functions use subshell trap pattern

### LOW-MEDIUM

#### BS-08: No FR → guide section mapping

- 90 FRs across 4 modules, ~45 guide subsections, no allocation table
- PATCH: Create FR → §X.Y mapping table (can be in plan.md or separate file)

### LOW

#### BS-07: Guide §3.3 title says "pf + LuLu" — misleading for containerized path

- PATCH: Rename to "§3.3 Outbound Filtering" (discuss tools within by path)

#### BS-09: Audit script SKIP status missing from contract

- Spec says SKIP when lacking admin privileges; contract only has PASS/FAIL/WARN
- PATCH: Add SKIP to audit contract output format and JSON schema

#### BS-10: SONOMA-HARDENING.md left dangling

- New guide covers Sonoma; old addendum becomes dead content
- PATCH: Add deprecation note or redirect to plan

#### BS-11: n8n version targeting undefined

- Major v1.x vs v2.0 differences; plan doesn't state minimum version
- PATCH: Add minimum n8n version (v2.0+) to plan technical context

#### BS-12: Constitution Article V tension with educational FRs

- FR-083, FR-087, FR-044 say "Verification: not automated — educational"
- Article V says unverifiable = no control
- PATCH: Acknowledge in constitution check as known exceptions

#### BS-13: Notification setup assumes SMTP relay access

- msmtp needs SMTP relay (Gmail app passwords, SendGrid, etc.)
- Not a simple config step; has its own security implications
- PATCH: Note in plan as dependency

#### BS-14: Data model Credential relationship wrong

- Says `Credential 1──1 Deployment Path` but most credentials exist in both paths
- Entity already has per-path storage fields, contradicting the relationship
- PATCH: Change to `Credential *──* Deployment Path` or note per-path storage

## MacBook Test Strategy (NOT YET DOCUMENTED)

User has a fresh Sonoma MacBook. Recommended approach:

1. **DO NOT clone repo yet** — the fresh state IS the test
2. Implement guide section-by-section (§1 Threat Model → §2 OS Foundation → §3 Network → etc.)
3. After each section is written, user follows it on the fresh Mac
4. This is the ultimate integration test — and it solves BS-02 (single-file size) by forcing incremental delivery
5. User installs Homebrew, git, etc. AFTER following the relevant hardening section
6. Clone repo on Mac only when needed for audit script testing

This approach means:

- Each PR adds one guide section (manageable diff, reviewable)
- Each section is validated on real hardware before merging
- Context window is never overwhelmed (one section at a time)
- The audit script grows incrementally alongside the guide

## Key Files

| File | Status |
|------|--------|
| `specs/001-hardening-guide-extension/plan.md` | Complete but needs BS patches |
| `specs/001-hardening-guide-extension/research.md` | Complete (11 items) |
| `specs/001-hardening-guide-extension/data-model.md` | Complete but BS-14 fix needed |
| `specs/001-hardening-guide-extension/contracts/audit-script-cli.md` | Complete but BS-06, BS-09 patches needed |
| `specs/001-hardening-guide-extension/contracts/guide-structure.md` | Complete but BS-07 patch needed |
| `specs/001-hardening-guide-extension/quickstart.md` | Complete but needs MacBook strategy |
| `specs/001-hardening-guide-extension/spec.md` | Rev 29 (unchanged) |
| `specs/001-hardening-guide-extension/spec-*.md` | 4 module files (unchanged) |
| `.specify/memory/constitution.md` | v1.3.0 (unchanged) |

## What's Next

1. **Patch blind spots** into plan artifacts (BS-01 through BS-14)
2. **Update MEMORY.md** index to include `user_macbook_test_env.md`
3. **Run `/speckit.tasks`** to generate implementation task breakdown
4. **Begin implementation** — section-by-section with MacBook validation

## How to Resume

1. Read this file for session context (blind spot analysis + MacBook strategy)
2. Read `specs/001-hardening-guide-extension/plan.md` for current plan state
3. Read `specs/001-hardening-guide-extension/research.md` for resolved unknowns
4. Apply the 14 blind spot patches listed above
5. Then run `/speckit.tasks` or `/speckit.analyze`
