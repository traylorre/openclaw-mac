# openclaw-mac Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-03-08

## Active Technologies

- Markdown (documentation), Bash 5.x (one identifier rename) + None (manual markdown edits) (004-hardening-coverage-map)
- N/A (filesystem, git-tracked markdown files) (004-hardening-coverage-map)
- Bash 5.x + macOS CLI tools (lsof, ps, brew), existing hardening-audit.sh and hardening-fix.sh (005-chromium-cdp-hardening)
- N/A (filesystem) (005-chromium-cdp-hardening)
- Bash 5.x (POSIX-compatible subset per constitution) + `defaults`, `lsof`, `pgrep`, `sqlite3` (006-multi-browser-support)
- Filesystem (managed preference plists, TCC.db reads, profile directories) (006-multi-browser-support)
- Bash 5.x (audit script, launchd plists, helper scripts); Markdown (guide prose) + shellcheck (static analysis), jq (JSON audit output), macOS CLI tools (`defaults`, `csrutil`, `fdesetup`, `socketfilterfw`, `security`, `tmutil`, `launchctl`, `pfctl`), Docker CLI, Colima (001-hardening-guide-extension)
- N/A (documentation + scripts, no application database) (001-hardening-guide-extension)
- Bash 5.x (POSIX-compatible subset for portability) + jq (JSON parsing), git (branch detection), tmux (optional automation) (002-context-auto-rotation)
- Filesystem — signal files in `.claude/`, CARRYOVER files in `specs/<branch>/`, logs in `.claude/recovery-logs/` (002-context-auto-rotation)
- Filesystem — JSON markers, markdown logs, temp files in `.claude/` (003-compaction-recovery)
- Bash 5.x (POSIX-compatible subset for portability) + jq (JSON parsing), git (file reverts), tmux (optional automation) (003-compaction-recovery)

## Project Structure

```text
src/
tests/
```

## Commands

<!-- TODO: Add commands for Bash 5.x (POSIX-compatible subset for portability) -->

## Code Style

Bash 5.x (POSIX-compatible subset for portability): Follow standard conventions

## Recent Changes

- 006-multi-browser-support: Added Bash 5.x (POSIX-compatible subset per constitution) + `defaults`, `lsof`, `pgrep`, `sqlite3`
- 005-chromium-cdp-hardening: Added Bash 5.x + macOS CLI tools (lsof, ps, brew), existing hardening-audit.sh and hardening-fix.sh
- 004-hardening-coverage-map: Added Markdown (documentation), Bash 5.x (one identifier rename) + None (manual markdown edits)

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
