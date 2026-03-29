# Feature Specification: Doctor Version Guard

**Feature Branch**: `021-doctor-version-guard`
**Created**: 2026-03-28
**Status**: Draft

## Problem
In `scripts/doctor.sh`, the `check_bash_version()` function at line 75 performs `[[ "$major" -ge 5 ]]`. If the version string extraction fails and `$major` is empty, this comparison crashes with a "integer expression expected" error because empty string is not a valid integer for `-ge`.

## Fix
Add an `-n` guard before the integer comparison:
```bash
if [[ -n "$major" ]] && [[ "$major" -ge 5 ]]; then
```

## Verification
Run `bash scripts/doctor.sh` — the script should complete without errors even if bash version detection fails on an unusual system.
