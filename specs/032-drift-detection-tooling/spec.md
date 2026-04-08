# 032 — Drift Detection Tooling (Vale + spec-check + link-check)

## Problem Statement

The documentation suite (SECURITY-VALUE.md, FEATURE-COMPARISON.md, BEHAVIORS.md, GETTING-STARTED.md) was adversarial-reviewed and found to have: incorrect env var lists (8 of 15 wrong), a wrong NIST mapping (AU-10), and no automated way to catch these classes of errors. Three complementary tools address three drift categories: terminology drift (Vale), reference drift (spec-check), and external link decay (markdown-link-check).

## User Stories

- **US-01**: As a contributor, I want `make vale` to catch terminology errors (wrong NIST format, missing date qualifiers) before they reach main.
- **US-02**: As a maintainer, I want `make spec-check` to verify that every `CHK-*` identifier referenced in docs actually exists in the audit script.
- **US-03**: As a maintainer, I want `make link-check` to find dead external URLs before a security researcher does.

## Requirements

### Feature A: Vale Prose Linter (US-01)

- **REQ-A1**: Add `brew "vale"` to `~/dotfiles/Brewfile`.
- **REQ-A2**: Create `.vale.ini` in openclaw-mac repo root configuring: MinAlertLevel, StylesPath, glob patterns for `docs/*.md` and `*.md` at root.
- **REQ-A3**: Create custom Vale style `styles/OpenClaw/` with rules:
  - `NistFormat.yml`: NIST family IDs must match `[A-Z]{2}-\d+` pattern (warn on bare references like "SC28" without hyphen).
  - `VersionPinning.yml`: Standard references (NIST, CIS, OWASP, MITRE) should include version or date qualifier.
  - `NemoClawDateQualifier.yml`: "Not documented in NemoClaw" must include "as of YYYY-MM-DD".
  - `RejectTSP.yml`: Flag bare "TSP" without "AICPA" or "Trust Services" context — prevent regression of the C-001 fix.
- **REQ-A4**: Add `vale` target to Makefile that runs `vale docs/ *.md`.
- **REQ-A5**: Vale must NOT conflict with existing markdownlint — they check different things (prose vs format).
- **REQ-A6**: Exclude `specs/`, `node_modules/`, `.claude/`, `.specify/` from Vale scope (same ignores as markdownlint).

### Feature B: make spec-check (US-02)

- **REQ-B1**: Add `spec-check` target to Makefile.
- **REQ-B2**: Script extracts all `CHK-*` identifiers from `docs/*.md` files.
- **REQ-B3**: Script verifies each identifier exists as a function name or string in `scripts/hardening-audit.sh`.
- **REQ-B4**: Report PASS (all found) or FAIL (list missing identifiers).
- **REQ-B5**: Also check reverse direction: warn if audit script has checks not referenced in any doc (coverage gap).
- **REQ-B6**: Pure bash — no additional dependencies beyond grep/sort/comm.

### Feature C: markdown-link-check (US-03)

- **REQ-C1**: Create `.markdown-link-check.json` in repo root with: `retryOn429: true`, `retryCount: 3`, `timeout: 10000`, `aliveStatusCodes: [200, 201, 301, 302, 403]`.
- **REQ-C2**: Add `ignorePatterns` for: localhost URLs, relative file paths (verified by markdownlint instead), `linkedin.com` (blocks all bots).
- **REQ-C3**: Add `link-check` target to Makefile that runs `npx markdown-link-check` on `docs/*.md` and root `*.md`.
- **REQ-C4**: WARN-only — exit code 0 even on failures. Print warnings but do not gate CI.
- **REQ-C5**: No new global npm install — use `npx` for zero-footprint execution.

## Scope Boundary

This feature adds tooling infrastructure only. It does NOT:
- Fix any content (content was fixed in PR #113)
- Add these tools to CI pipeline (future work — evaluate false positive rates first)
- Modify any existing documentation content

## Files Created/Modified

- `~/dotfiles/Brewfile` — add `brew "vale"` (dotfiles repo)
- `.vale.ini` — Vale configuration (NEW)
- `styles/OpenClaw/*.yml` — 4 custom Vale rules (NEW)
- `.markdown-link-check.json` — link checker config (NEW)
- `Makefile` — add 3 targets: `vale`, `spec-check`, `link-check`

## Adversarial Review #1

**Reviewed:** 2026-04-07 | **Input:** spec.md

### Findings

| # | Severity | Finding | Resolution |
|---|----------|---------|------------|
| H-001 | **HIGH** | REQ-A3 NistFormat rule matching `[A-Z]{2}-\d+` would flag legitimate text like "SC-28 (integrity)" in the parenthetical. Need word boundary awareness. | **Fixed:** Rule should match bare IDs without hyphens (e.g., "SC28") as warnings. Properly hyphenated "SC-28" is correct and should not be flagged. |
| H-002 | **HIGH** | REQ-B5 reverse check (audit checks not in docs) will produce many false positives — most of the 84+ checks are platform-level (CHK-FIREWALL, CHK-SIP) documented in HARDENING.md, not the new docs. | **Fixed:** REQ-B5 changed to informational only — print count of unreferenced checks, don't FAIL. The primary value is forward direction (doc→code). |
| M-001 | MEDIUM | REQ-C1 `aliveStatusCodes: [200, 201, 301, 302, 403]` — accepting 403 means we can't distinguish "site blocks bots" from "URL truly requires auth." | **Accepted:** For government/standards sites, 403 almost always means bot-blocking. We'd rather have false negatives (miss a dead link) than false positives (fail CI on every NIST URL). |
| M-002 | MEDIUM | Vale's VersionPinning rule could false-positive on narrative mentions of standards without version context (e.g., "as recommended by NIST"). | **Fixed:** Rule should only flag references in structured sections (tables, lists) where version pinning is expected. Use Vale's scope/block-level targeting. |
| M-003 | MEDIUM | Makefile is NOT uchg-locked but could become locked after `make integrity-lock`. If someone runs these targets after locking, Makefile is fine (read-only targets) but the spec-check script itself may fail if it tries to write temp files in a locked directory. | **Accepted:** spec-check uses pipes and subshells, no temp files. Vale and link-check read-only. No issue. |
| L-001 | LOW | `.vale.ini` and `.markdown-link-check.json` are dot-files that might be ignored by some tools. | **Accepted:** Both tools explicitly look for these config files. Standard practice. |

### Gate Statement

**0 CRITICAL, 0 HIGH remaining.** Spec cleared for planning.

## Clarifications

**Q1: Should Vale rules be errors or warnings?**
Answer: Warnings. These are new tools — start permissive, tighten after evaluating false positive rates. Constitution III (Free-First) principle: don't block developers with unproven tooling.

**Q2: Should spec-check run in CI?**
Answer: Not yet. Run manually via `make spec-check`. Add to CI after confirming zero false positives across 3+ audit cycles.

**Q3: Where do Vale styles live — dotfiles or project?**
Answer: Project (`styles/OpenClaw/`). Styles are project-specific (NIST, NemoClaw rules don't apply to other repos). Only the Vale binary goes in dotfiles Brewfile.

All 3 self-answered. 0 deferred.
