# Implementation Plan: Hardening Guide Extension

**Branch**: `001-hardening-guide-extension` | **Date**: 2026-03-11 | **Spec**: [spec.md](spec.md) (Rev 29)
**Input**: Feature specification from `/specs/001-hardening-guide-extension/spec.md`

## Summary

Rewrite `docs/HARDENING.md` from a 68-line thin guide into a comprehensive,
threat-modeled security guide (90 FRs, 39 control areas) for a Mac Mini
running n8n + Apify for LinkedIn lead generation. Deliver a standalone
`hardening-audit.sh` script with 55+ automated checks. Two independent
deployment paths: containerized (Colima/Docker, recommended) and bare-metal
(dedicated service account, alternative). All content must be sourced from
canonical references, verifiable via CLI, and organized by defensive layer
(Prevent/Detect/Respond).

## Technical Context

**Language/Version**: Bash 5.x (audit script, launchd plists, helper scripts); Markdown (guide prose)
**Primary Dependencies**: shellcheck (static analysis), jq (JSON audit output), macOS CLI tools (`defaults`, `csrutil`, `fdesetup`, `socketfilterfw`, `security`, `tmutil`, `launchctl`, `pfctl`), Docker CLI, Colima
**Storage**: N/A (documentation + scripts, no application database)
**Testing**: shellcheck --severity=warning (zero warnings); markdownlint-cli2 (CI); manual verification on macOS Tahoe/Sonoma
**Target Platform**: macOS Tahoe (26) and Sonoma (14) on Mac Mini (Apple Silicon and Intel)
**Minimum n8n Version**: v2.0+ (v1.x deprecated; `EXECUTIONS_PROCESS` removed, security defaults changed)
**Project Type**: Documentation + scripting (not a library, CLI tool, or web service)
**Performance Goals**: N/A (documentation project; audit script should complete in <60 seconds)
**Constraints**: Guide must be followable by a technically capable non-specialist; all infrastructure via CLI (Constitution Article X); free-first (Constitution Article III)
**Scale/Scope**: Single Mac Mini; 90 FRs across 4 domain modules; ~39 control areas; 55+ audit checks
**External Dependencies**: SMTP relay access required for email notifications (§10.2); Gmail app passwords, SendGrid, or similar — has its own security implications (app-specific passwords, API key management)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Article | Requirement | Status | Notes |
|---------|-------------|--------|-------|
| I. Documentation-Is-the-Product | Output is actionable hardening guidance | PASS | This IS the product |
| II. Threat-Model Driven (NON-NEGOTIABLE) | Every control traced to threat | PASS | All 90 FRs cite adversaries from the threat model |
| III. Free-First | Default to free tools, mark paid with `[PAID]` | PASS | Colima, ClamAV, Santa, LuLu, Quad9, Caddy primary; Docker Desktop, Little Snitch, SentinelOne noted as paid |
| IV. Cite Canonical Sources (NON-NEGOTIABLE) | Every recommendation sourced | PASS | All FRs cite CIS, NIST, Apple, OWASP, MITRE ATT&CK |
| V. Every Recommendation Verifiable | CLI check or Settings path | PASS | FRs include verification method; FR-007 defines 55+ audit checks |
| VI. Bash Scripts Are Infrastructure | set -euo pipefail, shellcheck, idempotent | PASS | FR-007 mandates shellcheck-clean, colored output, deployment-aware |
| VII. Defense in Depth | Organized by Prevent/Detect/Respond | PASS | FR-003 mandates layer headers; guide structure mirrors kill chain |
| VIII. Explicit Over Clever | Full paths, copy-pasteable commands | PASS | FR-008 mandates copy-pasteable commands, WHY before HOW |
| IX. Markdown Quality Gate | Must pass markdownlint CI | PASS | FR-009 mandates markdownlint compliance |
| X. CLI-First Infrastructure | All setup via CLI | PASS | FR-010/FR-019 mandate CLI-only infrastructure setup |

**Gate result**: PASS — no violations, no justifications needed.

## Project Structure

### Documentation (this feature)

```text
specs/001-hardening-guide-extension/
├── spec.md                        # Main spec hub (12 meta-FRs, FR index, user stories, SCs)
├── spec-macos-platform.md         # macOS OS, containers, network FRs
├── spec-n8n-platform.md           # n8n config, API, webhooks, nodes FRs
├── spec-data-security.md          # Injection, PII, credentials, SSRF FRs
├── spec-audit-ops.md              # Audit script, monitoring, IR, backup FRs
├── plan.md                        # This file
├── research.md                    # Phase 0 output
├── data-model.md                  # Phase 1 output
├── quickstart.md                  # Phase 1 output
├── contracts/                     # Phase 1 output
│   ├── audit-script-cli.md        # Audit script CLI interface contract
│   └── guide-structure.md         # Guide section structure contract
├── checklists/
│   └── requirements.md            # Spec quality gate checklist
├── CONTEXT-CARRYOVER-01.md        # Session 1 context (Rev 1-3)
├── CONTEXT-CARRYOVER-02.md        # Session 2 context (Rev 12-17)
└── CONTEXT-CARRYOVER-03.md        # Session 3 context (Rev 23, modular split)
```

### Source (repository root)

```text
docs/
├── HARDENING.md                   # PRIMARY DELIVERABLE — comprehensive guide (replaces current 68-line stub)
└── SONOMA-HARDENING.md            # DEPRECATED — new guide covers Sonoma; add redirect header pointing to HARDENING.md §2

scripts/
├── hardening-audit.sh             # PRIMARY DELIVERABLE — standalone audit script (55+ checks)
├── launchd/
│   ├── com.openclaw.audit.plist   # launchd plist template for scheduled audits (FR-022)
│   └── com.openclaw.notify.plist  # launchd plist for notification delivery (FR-024)
└── templates/
    ├── docker-compose.yml         # Reference secure docker-compose for n8n (FR-058)
    └── n8n-entrypoint.sh          # Entrypoint wrapper for Docker secrets (R-001: N8N_ENCRYPTION_KEY_FILE bug)
```

**Structure Decision**: Flat `docs/` + `scripts/` layout. No `src/` directory —
this is a documentation project. The guide is a single Markdown file;
the audit script is a single Bash file. Supporting files (plists, compose
template) live under `scripts/` to keep `docs/` clean.

## Constitution Check — Post-Design Re-Evaluation

*Re-checked after Phase 1 design artifacts completed.*

| Article | Pre-Design | Post-Design | Delta |
|---------|------------|-------------|-------|
| I. Documentation-Is-the-Product | PASS | PASS | No change |
| II. Threat-Model Driven | PASS | PASS | No change — research confirmed all tools are threat-justified |
| III. Free-First | PASS | PASS | No change — research confirmed all primary tools are free |
| IV. Cite Canonical Sources | PASS | PASS | Research added sources: n8n v2.0 docs, northpolesec/santa |
| V. Every Recommendation Verifiable | PASS | PASS | Audit script CLI contract defines verification for all checks |
| VI. Bash Scripts Are Infrastructure | PASS | PASS | Audit script contract mandates shellcheck, set -euo pipefail |
| VII. Defense in Depth | PASS | PASS | Guide structure contract organizes by Prevent/Detect/Respond |
| VIII. Explicit Over Clever | PASS | PASS | Guide structure contract mandates copy-pasteable commands |
| IX. Markdown Quality Gate | PASS | PASS | No change |
| X. CLI-First Infrastructure | PASS | PASS | No change |

**Post-design gate result**: PASS — no new violations introduced.

**Known Article V exceptions**: FR-083 (firmware password awareness),
FR-087 (USB/Thunderbolt policy), and FR-044 (PII classification) are
marked "Verification: not automated — educational" in the spec. Per
Article V ("Every Recommendation Verifiable"), these are educational
guidance items rather than enforceable controls. They are documented in
the guide for completeness but excluded from automated audit checks.
The guide marks them with an `[EDUCATIONAL]` tag instead of a `CHK-*` ID.

### Research-Driven Corrections

Research (Phase 0) identified 8 factual corrections that must be applied
during implementation. These do not violate the constitution but affect
accuracy:

1. `N8N_PUBLIC_API_DISABLED=true` (not `N8N_PUBLIC_API_ENABLED=false`)
2. `EXECUTIONS_PROCESS` removed (deprecated in n8n v2.0)
3. `N8N_BLOCK_ENV_ACCESS_IN_NODE` defaults to `true` in v2.0
4. Docker secrets: `_FILE` suffix partially supported; `N8N_ENCRYPTION_KEY_FILE` has bugs — use entrypoint wrapper
5. Apify webhooks use URL tokens, not HMAC signatures
6. Containerized outbound filtering: iptables in Colima VM, not macOS pf
7. Santa moved to `northpolesec/santa` (google/santa archived)
8. n8n supports native TOTP 2FA (no conditional needed in FR-067)

See [research.md](research.md) for full details on each correction.

## Testing Strategy: Section-by-Section MacBook Validation

Dev environment is WSL2 (Linux). The audit script and guide target macOS,
so macOS-only commands (`defaults`, `csrutil`, `fdesetup`, etc.) cannot be
tested on the dev machine. A freshly wiped Sonoma MacBook serves as the
integration test target.

**Approach**:

1. Implement the guide one section at a time (§1 → §2 → ... → §11)
2. Each section is delivered as its own PR (solves the 5,000-line
   single-file context problem)
3. After each PR merges, the guide is followed on the fresh MacBook
4. The MacBook gets Homebrew, git, Colima, etc. ONLY after reading the
   hardening guidance for each tool — the fresh state IS the test
5. The audit script grows incrementally alongside each guide section
6. Clone the repo on the MacBook only when needed for audit script testing

**Benefits**:

- Each PR is a manageable, reviewable diff
- Each section is validated on real hardware before merging
- Context window is never overwhelmed (one section at a time)
- The MacBook operator literally IS user story US-1

**PR sequence** (one per guide section):

| PR | Content | MacBook validates |
|----|---------|-------------------|
| 1 | §1 Threat Model + guide skeleton | N/A (narrative) |
| 2 | §2 OS Foundation | FileVault, firewall, SIP, Gatekeeper |
| 3 | §3 Network Security | SSH, DNS, pf |
| 4 | §4 Container Isolation | Colima install, Docker hardening |
| 5 | §5 n8n Platform Security | n8n deploy, env vars, webhooks |
| 6 | §6 Bare-Metal Path | Service account, Keychain |
| 7 | §7 Data Security | Credentials, PII |
| 8 | §8 Detection and Monitoring | Santa, BlockBlock, LuLu, logging |
| 9 | §9 Response and Recovery | IR runbook, backups |
| 10 | §10 Operational Maintenance | launchd scheduling, notifications |
| 11 | §11 Audit Script Reference + appendices | Full audit run |

## FR → Guide Section Mapping

Allocation of 90 FRs across guide sections. FRs from all 4 spec modules
mapped to their primary guide section.

| Guide Section | Primary FRs | Count |
|---------------|-------------|-------|
| §1 Threat Model | FR-001 | 1 |
| §2.1 FileVault | FR-011 | 1 |
| §2.2 Firewall | FR-013 | 1 |
| §2.3 SIP | FR-014 | 1 |
| §2.4 Gatekeeper/XProtect | FR-015, FR-034 | 2 |
| §2.5 Software Updates | FR-016 | 1 |
| §2.6 Screen Lock/Login | FR-025, FR-026, FR-090 | 3 |
| §2.7 Guest/Sharing | FR-027, FR-028 | 2 |
| §2.8 Lockdown Mode | FR-033 | 1 |
| §2.9 Recovery Mode | FR-083 | 1 |
| §3.1 SSH Hardening | FR-029 | 1 |
| §3.2 DNS Security | FR-031 | 1 |
| §3.3 Outbound Filtering | FR-030, FR-032 | 2 |
| §3.4 Bluetooth | FR-035 | 1 |
| §3.5 IPv6 | FR-036 | 1 |
| §3.6 Service Binding | FR-037 | 1 |
| §4.1 Colima Setup | FR-017 | 1 |
| §4.2 Docker Security | FR-018 | 1 |
| §4.3 docker-compose.yml | FR-058 | 1 |
| §4.4 Advanced Hardening | FR-041, FR-042 | 2 |
| §4.5 Container Networking | FR-040 | 1 |
| §5.1 Binding/Auth | FR-019, FR-020, FR-067 | 3 |
| §5.2 User Management | FR-066 | 1 |
| §5.3 Security Env Vars | FR-059 | 1 |
| §5.4 REST API | FR-061 | 1 |
| §5.5 Webhook Security | FR-039, FR-060 | 2 |
| §5.6 Execution/Nodes | FR-021, FR-062, FR-063 | 3 |
| §5.7 Community Nodes | FR-064 | 1 |
| §5.8 Reverse Proxy | FR-065 | 1 |
| §5.9 Update Security | FR-068 | 1 |
| §6.1 Service Account | FR-046 | 1 |
| §6.2 Keychain | FR-047 | 1 |
| §6.3 launchd | FR-048 | 1 |
| §6.4 File Permissions | FR-049 | 1 |
| §7.1 Credential Mgmt | FR-012, FR-043, FR-057 | 3 |
| §7.2 Credential Lifecycle | FR-050, FR-051 | 2 |
| §7.3 Injection Defense | FR-052, FR-053 | 2 |
| §7.4 PII Protection | FR-044, FR-054 | 2 |
| §7.5 SSRF | FR-055 | 1 |
| §7.6 Data Exfiltration | FR-069 | 1 |
| §7.7 Supply Chain | FR-070, FR-071 | 2 |
| §7.8 Apify Security | FR-060, FR-072 | 2 |
| §7.9 Secure Deletion | FR-073 | 1 |
| §7.10 Clipboard | FR-074 | 1 |
| §8.1 IDS Tools | FR-032, FR-075 | 2 |
| §8.2 Launch Daemon Audit | FR-076 | 1 |
| §8.3 Workflow Integrity | FR-077 | 1 |
| §8.4 macOS Logging | FR-078, FR-079 | 2 |
| §8.5 Credential Exposure | FR-080 | 1 |
| §8.6 iCloud Exposure | FR-081 | 1 |
| §8.7 Certificate Trust | FR-082 | 1 |
| §9.1 IR Runbook | FR-084 | 1 |
| §9.2 Credential Rotation | FR-085 | 1 |
| §9.3 Backup/Recovery | FR-038, FR-086 | 2 |
| §9.4 Restore Testing | FR-088 | 1 |
| §9.5 Physical Security | FR-087, FR-089 | 2 |
| §10.1 Audit Scheduling | FR-022 | 1 |
| §10.2 Notifications | FR-024 | 1 |
| §10.3 Tool Maintenance | FR-016, FR-068 | 2 |
| §10.4 Log Retention | FR-079 | 1 |
| §10.5 Troubleshooting | (derived) | 0 |
| §11 Audit Script Ref | FR-007, FR-023, FR-056 | 3 |
| Meta (guide-wide) | FR-002–FR-010 | 9 |
