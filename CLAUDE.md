# openclaw-mac Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-03-08

## Active Technologies

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

- 002-context-auto-rotation: Added Bash 5.x (POSIX-compatible subset for portability) + jq (JSON parsing), git (branch detection), tmux (optional automation)

- 003-compaction-recovery: Added Bash 5.x (POSIX-compatible subset for portability) + jq (JSON parsing), git (file reverts), tmux (optional automation)

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
