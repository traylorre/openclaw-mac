# Context Carryover 03: Spec Modular Split + Dotfiles

**Feature Branch:** `001-hardening-guide-extension`
**Date:** 2026-03-07
**Spec Revision:** Rev 23 (unchanged this session — structural split only)
**Constitution Version:** 1.3.0 (unchanged)

## Project: openclaw-mac

**Repo:** `https://github.com/traylorre/openclaw-mac`
**Branch:** `main`
**Purpose:** macOS hardening guides + audit tooling for a Mac Mini running n8n + Apify for LinkedIn lead gen

## Key Files

| File | What |
|------|------|
| `.specify/memory/constitution.md` | v1.3.0 -- 10 articles (I-X) |
| `specs/001-hardening-guide-extension/spec.md` | Rev 23 -- main hub: 12 meta-FRs, FR index, 9 user stories, 30 SCs, assumptions |
| `specs/001-hardening-guide-extension/spec-macos-platform.md` | 20 FRs: OS hardening, containers, network |
| `specs/001-hardening-guide-extension/spec-n8n-platform.md` | 10 FRs: n8n config, API, webhooks, nodes |
| `specs/001-hardening-guide-extension/spec-data-security.md` | 9 FRs: injection, PII, credentials, SSRF |
| `specs/001-hardening-guide-extension/spec-audit-ops.md` | 16 FRs: audit script, monitoring, IR, backups |
| `specs/001-hardening-guide-extension/CONTEXT-CARRYOVER-01.md` | Session 1 context (Rev 1-3) |
| `specs/001-hardening-guide-extension/CONTEXT-CARRYOVER-02.md` | Session 2 context (Rev 12-17) |
| `docs/HARDENING.md` | Current thin guide -- to be replaced |

## Session Summary

This session performed two tasks:

### 1. Dotfiles repo creation

Created `~/dotfiles/` managed by GNU Stow (private repo: github.com/traylorre/dotfiles).

Packages: bash, git, vim, claude, scripts. All symlinked into `$HOME`.

Key decisions:

- Consolidated vim to vim-plug only (removed pathogen)
- Split `.bash_aliases` into tracked + `.bash_aliases.local` (untracked, ssh_ec2 alias)
- Added `[include] path = ~/.gitconfig.local` for machine-specific git overrides
- Populated global gitconfig with `user.name = Scott Hazlett`, `user.email = 83501+traylorre@users.noreply.github.com`
- `~/bin/` scripts (context-guardian, context-monitor, notify-log, notify-windows) symlinked via stow
- `~/.claude/settings.json` symlinked via stow; all other `~/.claude/` content excluded (credentials, history, sessions, telemetry)

### 2. Spec modular split

spec.md (3,104 lines / 43k tokens) was too large for a single context window.
Split into 5 files using Option C (hybrid domain + size-balanced):

| File | Lines | FRs |
|------|-------|-----|
| spec.md (main) | 1,196 | 12 meta-FRs + FR index |
| spec-macos-platform.md | 664 | 20 |
| spec-n8n-platform.md | 392 | 10 |
| spec-data-security.md | 445 | 9 |
| spec-audit-ops.md | 533 | 16 |

All 67 FRs preserved verbatim. Zero missing, zero duplicates.

## Spec Rev 23 -- Cumulative State

| Metric | Count |
|--------|-------|
| Functional requirements | 67 (FR-001 to FR-067) |
| User stories | 9 (US-1 to US-9) |
| Success criteria | 30 (SC-001 to SC-030) |
| Edge cases | ~50 |
| Key Entities | 10 |
| Control areas | 32 |
| Assumptions | 15 |

## What's Next

- `/speckit.specify` -- more rounds if gaps remain
- `/speckit.clarify` -- resolve any remaining ambiguity
- `/speckit.plan` -- break spec into implementation tasks
- Implementation: rewrite `docs/HARDENING.md` with full content + audit script

## How to Resume

1. Read this file for context (current session state)
2. Read `specs/001-hardening-guide-extension/spec.md` for FR index + user stories + SCs
3. Read the relevant module file for the domain you're working on
4. Read `.specify/memory/constitution.md` for governance rules (v1.3.0)
5. Continue with `/speckit.specify`, `/speckit.clarify`, or `/speckit.plan`

## Convention: Context Carryover Files

Each CONTEXT-CARRYOVER-NN.md is a **historical snapshot** of one session.
Never edit a prior carryover — always create a new one. The highest-numbered
carryover is the most current. Prior carryovers provide provenance for how
the spec evolved.
