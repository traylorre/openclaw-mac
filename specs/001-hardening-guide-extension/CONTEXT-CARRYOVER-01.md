# Context Carryover 01: Hardening Guide Extension

**Feature Branch:** `001-hardening-guide-extension`
**Date:** 2026-03-07
**Spec Revision:** Rev 3
**Constitution Version:** 1.2.0

## Project: openclaw-mac

**Repo:** `https://github.com/traylorre/openclaw-mac`
**Branch:** `001-hardening-guide-extension`
**Purpose:** macOS hardening guides + audit tooling for a Mac Mini running n8n + Apify for LinkedIn lead gen

## Key Files

| File | What |
|------|------|
| `.specify/memory/constitution.md` | v1.1.0 -- 10 articles (I-X) |
| `specs/001-hardening-guide-extension/spec.md` | Rev 3 -- 19 FRs, 5 user stories, 9 success criteria |
| `specs/001-hardening-guide-extension/checklists/requirements.md` | All items pass |
| `docs/HARDENING.md` | Current thin guide (68 lines) -- to be replaced |
| `docs/SONOMA-HARDENING.md` | Separate addendum, out of scope |
| `audit/HARDENING-AUDIT.md` | Local working file (gitignored), full audit findings |
| `.github/workflows/lint.yml` | CI: markdownlint-cli2 + lychee link checker |
| `.markdownlint-cli2.jsonc` | MD013 disabled, ignores node_modules/audit/.claude/.specify |
| `.githooks/pre-push` | Runs markdownlint before push |
| `package.json` | `npm install` sets up linter + git hooks via `prepare` script |

## Constitution v1.1.0 -- Key Articles

- **I.** Documentation-is-the-product
- **II.** Threat-model driven (NON-NEGOTIABLE)
- **III.** Free-first with cost transparency (`[PAID]` tags)
- **IV.** Cite canonical sources (NON-NEGOTIABLE) -- CIS, NIST, Apple, Objective-See, MITRE, CIS Docker Benchmark
- **V.** Every recommendation is verifiable
- **VI.** Bash scripts are infrastructure (shellcheck, `set -euo pipefail`)
- **VII.** Defense in depth by layer (Prevent/Detect/Respond)
- **VIII.** Explicit over clever
- **IX.** Markdown quality gate
- **X.** CLI-first infrastructure, UI for business logic only (n8n workflow composition + monitoring)

## Spec Rev 3 -- Key Decisions

- **Colima** = primary container runtime (free, CLI-only, no licensing)
- **Docker Desktop** = noted alternative (same `docker` CLI, adds GUI + licensing)
- **Two deployment paths:** containerized (recommended) + bare-metal (alternative), independently complete
- **19 FRs**, including: threat model, 18 control areas, canonical sources, verification methods, free-first, CLI-only infra, Colima primary, container backup, PII/GDPR
- **5 user stories:** fresh hardening (P1), audit existing (P2), free vs paid eval (P2), n8n hardening (P1), container isolation (P1)
- **9 success criteria:** 18 control areas covered, 100% sourced, 100% verifiable, 20+ audit checks, shellcheck clean, markdownlint clean, both paths independent

## Threat Model

- **Platform:** Mac Mini (Apple Silicon or Intel), headless
- **Workload:** n8n orchestrating Apify actors for LinkedIn scraping
- **Assets:** LinkedIn creds, Apify API keys, PII lead data, n8n workflow IP
- **Adversaries:** network scanners, credential stuffing, npm supply chain, physical theft, LAN-adjacent

## Work Completed This Session

1. Fixed markdownlint CI failures across all .md files
2. Created `.markdownlint-cli2.jsonc` config (MD013 disabled, ignores set)
3. Created PR #1, auto-merged to main
4. Created `docs/HARDENING-AUDIT.md` with comprehensive blind spot analysis
5. Moved audit file to `audit/` folder (gitignored)
6. Initialized Spec-Kit, wrote constitution v1.0.0
7. Added pre-push git hook for markdownlint
8. Added setup instructions to README
9. Ran `/speckit.specify` Rev 1 -- base spec with 15 FRs
10. Ran `/speckit.specify` Rev 2 -- added Docker/container isolation (FR-016 to FR-018)
11. Ran `/speckit.constitution` v1.1.0 -- added Article X (CLI-first infra, UI for business logic)
12. Ran `/speckit.specify` Rev 3 -- Colima primary, Docker Desktop as note, FR-019 (CLI-only infra), all user stories updated
13. Ran `/speckit.constitution` v1.2.0 -- added Iterative Specification (Context Carryover) workflow to Development Workflow section

## What's Next

- More `/speckit.specify` rounds for further refinement
- Then `/speckit.plan` to break into implementation tasks
- Then implementation: rewrite `docs/HARDENING.md` with full content

## How to Resume

1. Read this file for context
2. Read `specs/001-hardening-guide-extension/spec.md` for current spec
3. Read `.specify/memory/constitution.md` for governance rules
4. Optionally read `audit/HARDENING-AUDIT.md` for detailed audit findings
5. Continue with `/speckit.specify` or proceed to `/speckit.plan`
