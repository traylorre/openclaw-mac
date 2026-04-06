# Implementation Plan: GETTING-STARTED.md Update

**Branch**: `027-setup-docs-update` | **Date**: 2026-04-06 | **Spec**: [spec.md](spec.md)

## Summary

Update `GETTING-STARTED.md` to cover workspace integrity setup (M4), `make doctor` validation, sudoers secure_path, dangerous env var warnings, package manager explanation, and cross-references to the new documentation suite (028, 029, 030).

## Technical Context

**Language/Version**: Markdown (CommonMark)
**Dependencies**: Features 028, 029, 030 (all cross-referenced, must exist first)
**Testing**: markdownlint-cli2 CI
**Key constraint**: Modifying an existing file — must preserve current structure (REQ-07)

## Constitution Check

All applicable principles pass. Key notes:
- **VIII. Explicit Over Clever**: Copy-pasteable commands, `EDITOR=nano` for visudo
- **IX. Markdown Quality Gate**: Must pass markdownlint after edits
- **V. Every Recommendation Is Verifiable**: Each new step has a verification command

**Gate result: PASS**

## Current Document Structure

```text
GETTING-STARTED.md (current)
├── TL;DR (4 commands) ← ADD make doctor (REQ-01)
├── What each command does
├── Step 1: Install Homebrew
├── Step 2: Clone and bootstrap ← ADD make doctor checkpoint (REQ-01)
├── Step 3: Audit and fix
├── Step 4: Verify
├── What was changed
├── Undoing changes
├── Next steps ← ADD cross-references (REQ-06)
├── Troubleshooting ← ADD "Operation not permitted" (REQ-08)
└── Reference

After modification:
├── ... (Steps 1-4 preserved)
├── Step 5: Workspace Integrity ← NEW (REQ-02)
├── Step 6: sudoers secure_path ← NEW (REQ-03)
├── Dangerous Environment Variables ← NEW callout (REQ-04)
├── Package Managers ← NEW section (REQ-05)
├── ... (remaining sections preserved with additions)
```

## Clarifications

**Q1**: Where exactly should "Package Managers" go? After Step 6 but before "What was changed" — it's context the reader needs before the reference sections.

**Q2**: Should Step 5 warn about file locking consequences? Yes — add a callout: "After this step, workspace files will be locked. See BEHAVIORS.md for how to edit protected files."

All self-answered. 0 deferred.

## Adversarial Review #2

No drift. Clarifications are additive. Gate: PASS.
