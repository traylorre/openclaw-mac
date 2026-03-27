# Research Brief: Security Hardening Phase 2

**Date**: 2026-03-24
**Input**: 4 parallel research agents (ecosystem, frameworks, file inventory, Context7)
**Purpose**: Inform /speckit.specify for comprehensive security hardening

## Key Findings

### 1. CVE Landscape (31 CVEs tracked)

- CVE-2026-25253 (CVSS 8.8): Auth token theft → RCE via Control UI
- CVE-2026-32056 (CVSS 7.5): Shell env injection bypasses command allowlist
- CVE-2026-32048: Sandbox inheritance bypass (child processes escape sandbox)
- GHSA-F7WW-2725-QVW2: TOCTOU approval bypass via symlink rebinding
- GHSA-M8V2-6WWH-R4GC: Sandbox escape via symlink manipulation
- 40,000+ exposed OpenClaw instances, 63% vulnerable to CVE-2026-25253

### 2. ClawHavoc (Updated Numbers)

- 1,184 malicious skills across 12 author IDs (hightower6eu: 677 alone)
- 5 of top 7 most-downloaded skills were malware at peak
- Attack vectors: reverse shells, AMOS stealer, ClickFix social engineering
- ClawHub comments weaponized: fake "update service" on 99/100 top skills

### 3. NemoClaw Gaps

- Landlock + seccomp + network deny-by-default: strong process isolation
- BUT: skill files copied INTO writable /sandbox directory
- No prompt injection detection
- No distinction between "agent writes normal file" and "agent rewrites instructions"
- No input validation for instruction modification attempts

### 4. Sensitive Files NOT Currently Protected

Critical gaps from file inventory:

| File | Impact | Currently Protected? |
|------|--------|:---:|
| `.claude/settings.local.json` | Controls Claude Code permissions (287 patterns) | NO |
| `~/.openclaw/openclaw.json.bak[1-4]` | Old configs with weaker security posture | NO |
| `~/.openclaw/agents/*/models.json` | LLM routing (redirect to attacker LLM) | NO |
| `~/.openclaw/agents/*/.openclaw/workspace-state.json` | Session state poisoning | NO |
| `~/.openclaw/restore-scripts/` | 10 scripts at 755 (world-readable!) | NO |
| `~/.openclaw/logs/config-audit.jsonl` | Audit trail tampering | NO |
| `~/.openclaw/sandboxes/*/data/` | Writable dir (monitored for symlinks but not content) | PARTIAL |
| Docker n8n_data volume | Credentials, workflow state, execution history | NO |
| Browser profile (storageState) | LinkedIn session cookies | NO |
| `~/.openclaw/agents/*/.git/hooks/` | Git hooks execute arbitrary code | NO |

### 5. Framework Gaps (NIST/OWASP/ToIP)

- **NIST CAISI**: Agent needs its own identity, not borrowed user session
- **OWASP LLM02**: Insecure output handling — agent output to n8n not sanitized
- **OWASP Agentic Top 10**: Cascading failures through orchestration chains
- **MITRE ATLAS**: AML.T0051 (LLM prompt injection), AML.T0054 (supply chain compromise)
- **Zero-trust**: Every tool invocation should be verified, not just startup
- **SLSA**: No build provenance for skills or workflows

### 6. Missing Defense Layers

1. **Output sanitization**: Agent output → n8n webhook should be validated
2. **Runtime re-verification**: Sandbox config checked at startup only, not continuously
3. **Credential isolation**: Agent and operator share user account
4. **Docker volume integrity**: n8n credentials/workflows not integrity-checked
5. **Browser session protection**: LinkedIn storageState not encrypted at rest
6. **Git hook protection**: .git/hooks/ in agent directories can execute code
7. **Backup config protection**: openclaw.json.bak* files restorable to weaker state
8. **LLM routing protection**: models.json not in protected file list
9. **Permission allowlist protection**: .claude/settings.local.json not integrity-checked
10. **Append-only audit enforcement**: chflags uappnd not applied to audit log
