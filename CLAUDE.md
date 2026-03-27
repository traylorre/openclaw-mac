# openclaw-mac Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-03-08

## Active Technologies

- Bash 5.x (POSIX-compatible subset per Constitution VI) + jq (JSON manipulation), openssl (AES-256-GCM encryption, HMAC signing), shasum (SHA-256 checksums), macOS chflags (filesystem flags), Docker CLI (container inspection), fswatch (filesystem monitoring) (012-security-hardening-phase2)
- Filesystem — JSON state files (~/.openclaw/), JSONL audit log, encrypted session files (012-security-hardening-phase2)

- Bash 5.x (POSIX-compatible subset for scripts), JSON (manifest and config files), jq (JSON manipulation) + macOS chflags (filesystem immutability), OpenClaw v2026.3.13 (sandbox mode), fswatch (filesystem monitoring via Homebrew), launchd (process supervision), macOS Keychain (HMAC key storage) (011-workspace-integrity)
- Filesystem — `~/.openclaw/manifest.json` (signed integrity manifest), `~/.openclaw/skill-allowlist.json`, `~/.openclaw/lock-state.json`, `~/.openclaw/integrity-monitor-heartbeat.json` (011-workspace-integrity)

- JavaScript/TypeScript (Bun runtime for OpenClaw), Bash 5.x (POSIX-compatible subset for scripts and audit checks), JSON (n8n workflow definitions) + OpenClaw (self-hosted AI agent), n8n v2.13.0 (Docker), Playwright (via n8n-nodes-playwright community node), LinkedIn Share API (OAuth 2.0), LLM providers (Gemini, Anthropic, Ollama) (010-linkedin-automation)
- OpenClaw SQLite + sqlite-vec (conversation history), n8n Docker volume (execution history, credentials, workflow state), filesystem (workspace files, pending drafts JSON, manifest checksums) (010-linkedin-automation)

- Bash 5.x (POSIX-compatible subset per constitution) + jq (JSON manifest manipulation), shasum (checksums), macOS CLI tools (security, launchctl, defaults) (009-nomoop)
- Filesystem — `~/.openclaw/manifest.json` (JSON, managed with jq) (009-nomoop)
- Bash 5.x (POSIX-compatible subset per constitution) + Homebrew (`brew install colima docker`), (008-colima-lifecycle)
- N/A (no persistent state beyond Colima VM itself) (008-colima-lifecycle)

- n8n workflow JSON (declarative), Bash 5.x (setup scripts) + n8n v2.13.0 (Docker), Colima, Docker CLI (007-n8n-gateway)
- Docker volume `n8n_data` (workflows, credentials, execution logs) (007-n8n-gateway)
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

- 012-security-hardening-phase2: Added Bash 5.x (POSIX-compatible subset per Constitution VI) + jq (JSON manipulation), openssl (AES-256-GCM encryption, HMAC signing), shasum (SHA-256 checksums), macOS chflags (filesystem flags), Docker CLI (container inspection), fswatch (filesystem monitoring)

- 011-workspace-integrity: Added Bash 5.x (POSIX-compatible subset for scripts), JSON (manifest and config files), jq (JSON manipulation) + macOS chflags (filesystem immutability), OpenClaw v2026.3.13 (sandbox mode), fswatch (filesystem monitoring via Homebrew), launchd (process supervision), macOS Keychain (HMAC key storage)

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
