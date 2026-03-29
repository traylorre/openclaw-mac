# Feature Specification: Grep Flag Fix

**Feature Branch**: `020-grep-flag-fix`
**Created**: 2026-03-28
**Status**: Draft

## Problem
Line 2085 of `scripts/hardening-audit.sh` passes a pattern containing `--disable-web-security` to grep. Despite using `-e`, BSD grep on macOS interprets the `--` prefix as an option flag, causing: `grep: unrecognized option`.

## Fix
Replace `grep -oE -e "$dangerous_flags"` with `grep -oE -- "$dangerous_flags"`. The `--` end-of-options marker prevents pattern interpretation as flags.

## Verification
Run `make audit` — the grep error should no longer appear in output.
