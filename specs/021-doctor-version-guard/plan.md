# Implementation Plan: Doctor Version Guard

**Branch**: `021-doctor-version-guard` | **Date**: 2026-03-28 | **Spec**: [spec.md](spec.md)

## Summary

One-line fix in `scripts/doctor.sh` line 75: add `-n "$major"` guard before the `-ge 5` integer comparison to prevent crash when version extraction yields an empty string.

## Scope

- **File**: `scripts/doctor.sh`
- **Change**: `if [[ "$major" -ge 5 ]]; then` -> `if [[ -n "$major" ]] && [[ "$major" -ge 5 ]]; then`
- **Risk**: Minimal — adds a defensive guard that short-circuits to the FAIL branch when version is undetectable.
