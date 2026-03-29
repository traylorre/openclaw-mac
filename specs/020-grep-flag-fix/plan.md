# Implementation Plan: Grep Flag Fix

**Branch**: `020-grep-flag-fix` | **Date**: 2026-03-28 | **Spec**: [spec.md](spec.md)

## Summary

One-line fix in `scripts/hardening-audit.sh` line 2085: replace `-e` with `--` to prevent BSD grep from interpreting `--disable-web-security` patterns as option flags.

## Scope

- **File**: `scripts/hardening-audit.sh`
- **Change**: `grep -oE -e "$dangerous_flags"` -> `grep -oE -- "$dangerous_flags"`
- **Risk**: Minimal — `--` is universally supported by POSIX grep implementations.
