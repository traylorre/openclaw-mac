# Implementation Plan: Workspace Integrity

**Branch**: `011-workspace-integrity` | **Date**: 2026-03-23 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/011-workspace-integrity/spec.md`

## Summary

Harden the self-hosted AI agent deployment against workspace file tampering, supply chain attacks, and prompt injection persistence. Four independent defense layers: Prevent (filesystem immutability via macOS `chflags uchg`), Contain (agent sandbox with read-only workspace and tool restrictions), Detect (startup integrity verification + continuous filesystem monitoring), Verify (audit script extensions). Every control traces to a named threat from the platform's MITRE ATLAS threat model or OWASP AI Agent Security guidance.

Key research findings: use `uchg` (user immutable) not `schg` (system immutable) — `uchg` prevents agent self-modification while keeping lock/unlock manageable via root. OpenClaw sandbox mode is confirmed functional in v2026.3.13. `fswatch` on macOS uses FSEvents with ~1 second latency. No built-in skill allowlist exists — must be implemented as custom manifest layer.

## Technical Context

**Language/Version**: Bash 5.x (POSIX-compatible subset for scripts), JSON (manifest and config files), jq (JSON manipulation)
**Primary Dependencies**: macOS chflags (filesystem immutability), OpenClaw v2026.3.13 (sandbox mode), fswatch (filesystem monitoring via Homebrew), launchd (process supervision), macOS Keychain (HMAC key storage)
**Storage**: Filesystem — `~/.openclaw/manifest.json` (signed integrity manifest), `~/.openclaw/skill-allowlist.json`, `~/.openclaw/lock-state.json`, `~/.openclaw/integrity-monitor-heartbeat.json`
**Testing**: shellcheck (bash scripts), manual verification on macOS, hardening-audit.sh (audit framework)
**Target Platform**: macOS (Intel Mac Mini, Sonoma/Tahoe)
**Project Type**: Security hardening — scripts, configuration, audit checks
**Performance Goals**: Integrity check adds <500ms to agent startup, monitoring detection within 60 seconds
**Constraints**: Must not break M3 operator workflow (chat → draft → approve → publish), must work with existing OpenClaw native process
**Scale/Scope**: Single host, ~40 protected files, 2 agents, 5 skills

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Documentation-Is-the-Product | **PASS** | Outputs are scripts, audit checks, and configuration — core infrastructure artifacts. |
| II. Threat-Model Driven (NON-NEGOTIABLE) | **PASS** | Every FR traces to T-PERSIST-002 (skill update poisoning), T-PERSIST-003 (config tampering), OWASP AI Agent Security (compromised skills), or gap analysis (detection window). See spec Threat Traceability table. |
| III. Free-First with Cost Transparency | **PASS** | All tools free: chflags (built-in), fswatch (Homebrew, open-source), OpenClaw sandbox (open-source), jq (open-source), launchd (built-in). |
| IV. Cite Canonical Sources (NON-NEGOTIABLE) | **PASS** | Sources: OpenClaw THREAT-MODEL-ATLAS.md (MITRE ATLAS), OWASP AI Agent Security Cheat Sheet, NVIDIA NemoClaw architecture, CIS macOS Benchmark (filesystem protections). |
| V. Every Recommendation Is Verifiable | **PASS** | Every FR has a corresponding CHK-OPENCLAW-* audit check. 8 new checks: INTEGRITY-LOCK, INTEGRITY-MANIFEST, SANDBOX-MODE, SANDBOX-TOOLS, MONITOR-STATUS, SKILL-ALLOWLIST, SYMLINK-CHECK, PLATFORM-VERSION. |
| VI. Bash Scripts Are Infrastructure | **PASS** | All scripts follow: set -euo pipefail, shellcheck clean, idempotent, colored output. |
| VII. Defense in Depth | **PASS** | Four independent layers: Prevent (immutability), Contain (sandbox), Detect (monitoring + startup check), Verify (audit). |
| VIII. Explicit Over Clever | **PASS** | Quickstart provides copy-pasteable commands. Lock/unlock workflow documented. |
| IX. Markdown Quality Gate | **PASS** | All output passes markdownlint (MD013 disabled per config). |
| X. CLI-First Infrastructure, UI for Business Logic | **PASS** | All controls are CLI-managed (make targets, scripts). No UI dependencies. |

**Constitution gate: PASSED.** No violations requiring justification.

## Project Structure

### Documentation (this feature)

```text
specs/011-workspace-integrity/
├── spec.md              # Feature specification (29 adversarial findings addressed)
├── plan.md              # This file
├── research.md          # Phase 0: 8 research decisions
├── data-model.md        # Phase 1: entity definitions
├── quickstart.md        # Phase 1: operator guide
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
scripts/
├── integrity-lock.sh        # Lock protected files (chflags uchg + manifest sign)
├── integrity-unlock.sh      # Unlock specific file for editing
├── integrity-deploy.sh      # Deploy workspace files from repo (git-clean + checksums + sign)
├── integrity-verify.sh      # Startup integrity check (checksums + env vars + symlinks)
├── integrity-monitor.sh     # Background file monitoring service
├── skill-allowlist.sh       # Manage skill allowlist (add/remove/check)
├── sandbox-setup.sh         # Configure OpenClaw sandbox mode in openclaw.json
├── hardening-audit.sh       # Extended with 8 new CHK-OPENCLAW-* checks
└── lib/
    ├── common.sh            # Shared library (already exists)
    └── integrity.sh         # Integrity manifest helpers (checksums, HMAC, file list)

scripts/templates/
└── com.openclaw.integrity-monitor.plist  # launchd LaunchAgent for monitoring service

Makefile                     # New targets: integrity-lock, integrity-unlock,
                             # integrity-verify, monitor-setup, monitor-teardown,
                             # monitor-status, sandbox-setup, sandbox-teardown,
                             # skillallow-add, skillallow-remove
```

**Structure Decision**: Extends existing `scripts/` directory with new hardening scripts. No new top-level directories. All scripts source `scripts/lib/common.sh`. LaunchAgent plist for monitoring service follows existing pattern from `com.openclaw.audit-cron.plist`.

## Research Decisions

| ID | Decision | Rationale |
|----|----------|-----------|
| R-001 | Use `uchg` (user immutable), not `schg` | `schg` can't be cleared without single-user mode on Apple Silicon. `uchg` prevents non-root modification and is manageable via `sudo chflags nouchg`. |
| R-002 | OpenClaw sandbox: `mode: "all"`, `workspaceAccess: "ro"`, `tools.fs.workspaceOnly: true` | Confirmed functional in v2026.3.13. Extraction agent gets `workspaceAccess: "none"` + zero tools. |
| R-003 | `fswatch` via Homebrew for monitoring | Uses native macOS FSEvents backend. 1-second latency. LaunchAgent (not LaunchDaemon) for Keychain access. |
| R-004 | Custom skill allowlist in manifest | OpenClaw has no built-in content-hash-based allowlist. Implemented as JSON + startup check. |
| R-005 | Keychain HMAC key via `security` CLI | LaunchAgents can access login Keychain. Sign manifest as user, then elevate to root for chflags. |
| R-006 | NemoClaw model: writable /data + read-only workspace | Writable data dir for drafts/state, read-only for instructions. Same pattern. |
| R-007 | Custom env var validation at startup | OpenClaw has no built-in LD_PRELOAD/DYLD protection. Check in startup script. |
| R-008 | JSON schema validation for pending-drafts.json | BOOT.md loads without validation. Host-side startup script validates before agent launch using jq. |

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Root-level file tampering bypasses uchg flags | Low | High | Integrity verification (detect layer). macOS hardening baseline (M2) limits root access paths. |
| OpenClaw sandbox API changes in future versions | Medium | Medium | Pin platform version in manifest (FR-020). Audit checks detect version changes. |
| fswatch misses events during high disk I/O | Low | Low | Startup integrity check runs independently. Monitoring is supplementary. |
| Operator fatigue from lock/unlock friction | Medium | Medium | Short grace periods (5 min). Clear make targets. Batch unlock/lock in single deploy operation. |
| macOS update clears uchg flags | Low | Medium | Startup check detects. `make integrity-lock` is idempotent — safe to re-run. |
| Sandbox mode breaks M3 webhook workflow | Medium | High | Test full draft→approve→publish flow in sandbox before locking down. Ensure web_fetch/HTTP tools are on the allow list. Phase 3 explicitly gates on this test. |
| Conversation history poisoning (out of scope) | Medium | Medium | Accepted residual risk. Platform-managed state. Documented in spec. |

## Implementation Phases

### Phase 1: Filesystem Immutability (US1)
**Priority**: P1 — Foundation for all other controls
**Scripts**: integrity-lock.sh, integrity-unlock.sh, integrity-deploy.sh
**Makefile**: integrity-lock, integrity-unlock, integrity-deploy
**Audit**: CHK-OPENCLAW-INTEGRITY-LOCK, CHK-OPENCLAW-SYMLINK
**FRs**: FR-001 to FR-006

Implement `uchg` flag management, signed manifest (HMAC via Keychain), symlink detection. Separate deploy script (integrity-deploy.sh) handles git-clean verification (FR-006), file copy from repo to workspace, fresh checksums, manifest signing, and flag setting. Lock/unlock scripts handle the edit workflow without requiring a clean git tree.

### Phase 2: Startup Integrity Verification (US3, partial)
**Priority**: P1 — Blocks agent startup on tampering
**Scripts**: integrity-verify.sh
**Makefile**: integrity-verify
**FRs**: FR-014 to FR-020

Implement pre-startup checksum verification, env var validation (DYLD_INSERT_LIBRARIES, NODE_OPTIONS — NOT BUN_INSTALL which is legitimately set), manifest signature verification, data file structural validation for pending-drafts.json (FR-012 via jq: check required fields, reject unknown fields, enforce content length limits), n8n workflow structural comparison (FR-018 via `docker exec` export + jq diff ignoring metadata keys), platform version check (FR-020). This script launches the agent directly after all checks pass (eliminates TOCTOU window).

**Note on FR-013 (sandbox active before external operations)**: Verified at startup by this script. If sandbox is not configured, the startup check warns but does not block (sandbox is a separate layer — US2).

### Phase 3: Agent Sandbox Configuration (US2)
**Priority**: P2 — Contains blast radius
**Scripts**: sandbox-setup.sh
**Makefile**: sandbox-setup, sandbox-teardown
**FRs**: FR-007 to FR-013

Configure OpenClaw sandbox mode, tool restrictions, read-only workspace, extraction agent isolation. The extraction agent name is `feed-extractor` (matching M3 Makefile, not "extraction").

**Critical: writable data directory resolution.** The sandbox sets `workspaceAccess: "ro"` which blocks writes to the workspace. Agent state (pending-drafts.json) must be stored in a sandboxed writable directory (`~/.openclaw/sandboxes/<agent>/data/`) that is OUTSIDE the read-only workspace but INSIDE the sandbox. OpenClaw's sandbox provides this via the sandbox workspace at `~/.openclaw/sandboxes/<agentId>/`. The agent process writes drafts there; the startup integrity-verify.sh validates the file before the agent reads it.

**Webhook workflow compatibility**: The agent calls n8n webhooks via HTTP, not filesystem tools. The `web_fetch` tool (or equivalent) must be on the allowed tools list. Test the full M3 draft→approve→publish flow in sandbox mode before locking down.

### Phase 4: Continuous Monitoring (US3, complete)
**Priority**: P3 — Defense in depth detection
**Scripts**: integrity-monitor.sh
**Templates**: com.openclaw.integrity-monitor.plist (LaunchAgent, not LaunchDaemon — starts after login for Keychain access)
**Makefile**: monitor-setup, monitor-teardown, monitor-status
**FRs**: FR-021 to FR-025

Implement fswatch-based monitoring, heartbeat (every 30s), per-file alert suppression with 5-minute timeout (FR-023), launchd KeepAlive management. On file change event, re-verify checksum against manifest (FR-025) to catch transient modify-and-restore attacks.

### Phase 5: Supply Chain Controls (US4)
**Priority**: P4 — Skill allowlisting
**Scripts**: skill-allowlist.sh
**Makefile**: skillallow-add, skillallow-remove (noun-verb convention)
**FRs**: FR-026 to FR-029

Implement content-hash-based skill allowlist. Skills identified by SHA-256 hash, not name. Skill allowlist must be configured BEFORE integrity-lock (hashes included in manifest).

### Phase 6: Audit Extensions (US5)
**Priority**: P5 — Verification layer
**Scripts**: hardening-audit.sh (extend)
**FRs**: FR-030 to FR-037

Add 8 new CHK-OPENCLAW-* checks:

| Check | FR | What it verifies |
|-------|-----|-----------------|
| CHK-OPENCLAW-INTEGRITY-LOCK | FR-030 | Immutable flags set on all protected files |
| CHK-OPENCLAW-INTEGRITY-MANIFEST | FR-035 | Manifest signature is valid, checksums match |
| CHK-OPENCLAW-SANDBOX-MODE | FR-031 | Sandbox mode enabled in openclaw.json |
| CHK-OPENCLAW-SANDBOX-TOOLS | FR-032 | Tool restrictions enforced per agent |
| CHK-OPENCLAW-MONITOR-STATUS | FR-033 | Monitoring service running, heartbeat recent |
| CHK-OPENCLAW-SKILLALLOW | FR-034 | All installed skills on allowlist (by hash) |
| CHK-OPENCLAW-SYMLINK | FR-036 | No symlinks in protected directories |
| CHK-OPENCLAW-PLATFORM-VERSION | FR-037 | Platform runtime version matches manifest |

### Phase 7: Testing and Polish
**Priority**: P5

**Testing strategy** (adversarial review finding #4):
1. Shellcheck on all new scripts (zero warnings)
2. Tamper test: modify SOUL.md → verify startup check blocks agent
3. Sandbox test: attempt to read ~/.openclaw/.env from agent → verify denied
4. Sandbox test: run full M3 draft→approve→publish flow → verify no disruption
5. Monitor test: modify file with sudo → verify alert within 60s
6. Allowlist test: add unapproved skill → verify agent rejects it
7. Audit test: run `make audit` → verify all 8 new checks pass
8. Weakening test: disable one control → verify corresponding audit check fails

Update quickstart (correct ordering: skillallow-add before integrity-lock), final end-to-end validation.
