# Implementation Plan: Pipeline Security Hardening

**Branch**: `014-pipeline-security-hardening` | **Date**: 2026-03-26 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/014-pipeline-security-hardening/spec.md`

## Summary

Harden the LinkedIn automation pipeline (010) against the current CVE landscape across all three components (n8n, OpenClaw, LinkedIn API). Implement OWASP ASI Top 10 control mapping, five-layer defense-in-depth verification (Prevent, Contain, Detect, Respond, Recover), sensitive file inventory with HMAC-signing remediation for ADV-002/ADV-004, expanded environment variable validation, and dependency update procedures. Extends the existing integrity framework (lib/integrity.sh) with CVE verification, behavioral baseline monitoring, and trust boundary documentation referencing ToIP TEA/TSP.

## Technical Context

**Language/Version**: Bash 5.x (POSIX-compatible subset per Constitution VI) + jq (JSON), openssl (HMAC-SHA256), shasum (SHA-256), curl (API calls)
**Primary Dependencies**: Existing integrity framework (lib/integrity.sh, ~1500 lines), hardening-audit.sh (~3100 lines), Docker CLI (container inspection), macOS Keychain (HMAC key storage), n8n REST API (version/execution queries)
**Storage**: Filesystem — `~/.openclaw/` (manifest.json, lock-state.json, openclaw.json, skill-allowlist.json), JSONL audit log, version-controlled CVE registry (JSON)
**Testing**: shellcheck (bash scripts), integration tests (test-phase4-integration.sh pattern), manual end-to-end verification
**Target Platform**: macOS (Apple Silicon Mac Mini, Tahoe/Sonoma), hardened per M2 baseline
**Project Type**: Security tooling extension — audit checks, verification scripts, documentation artifacts
**Performance Goals**: Security verification < 60 seconds, audit checks < 1 second each
**Constraints**: All tools must be free/open-source (Constitution III). All checks verifiable via terminal command (Constitution V). All scripts shellcheck-clean (Constitution VI).
**Scale/Scope**: Single Mac Mini, single agent (linkedin-persona), single n8n container, ~27 FRs, ~12 SCs

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Documentation-Is-the-Product | **PASS** | Primary outputs are documentation artifacts: ASI mapping, sensitive file inventory, trust boundary model, dependency update procedures. Audit script extensions are verifiable tooling. |
| II. Threat-Model Driven (NON-NEGOTIABLE) | **PASS** | Every control traces to named threats: n8n CVEs (CVE-2026-21858 et al.), OpenClaw CVEs (CVE-2026-25253 et al.), ClawHavoc supply chain (1,184 malicious skills), OWASP ASI Top 10. Adversary list extended: LLM provider compromise (ASI01), trojanized agent binary (ASI04). |
| III. Free-First with Cost Transparency | **PASS** | All tools free: openssl, jq, shasum, Docker CLI, macOS Keychain, shellcheck. No paid dependencies. |
| IV. Cite Canonical Sources (NON-NEGOTIABLE) | **PASS** | Sources: OWASP Top 10 for Agentic Applications (Dec 2025), NIST AI RMF 1.0, MITRE ATLAS (Oct 2025 update, 14 agent techniques), ToIP TSP Rev 2 (Nov 2025), CIS Docker Benchmark, LinkedIn API documentation (learn.microsoft.com). CVEs cite NVD entries. |
| V. Every Recommendation Is Verifiable | **PASS** | Each FR maps to an audit check or documented verification procedure. All checks report PASS/FAIL/WARN/SKIP with colored output. |
| VI. Bash Scripts Are Infrastructure | **PASS** | All new scripts follow existing patterns: set -euo pipefail, shellcheck clean, idempotent, colored output, no interactive input, Apple Silicon + Intel compatible. |
| VII. Defense in Depth | **PASS** | Five layers explicitly verified: Prevent (credential isolation, HMAC, immutability, sandbox), Contain (Docker isolation, OpenClaw sandbox, node exclusion), Detect (pre-launch attestation, continuous monitoring, behavioral baseline), Respond (alert delivery, audit logging, remediation procedures), Recover (credential rotation, manifest re-baseline, dependency rollback). |
| VIII. Explicit Over Clever | **PASS** | CVE verification reports specific CVE numbers, CVSS scores, and upgrade commands. No hidden logic. |
| IX. Markdown Quality Gate | **PASS** | All markdown passes markdownlint (MD013 disabled). |
| X. CLI-First Infrastructure, UI for Business Logic | **PASS** | All security tooling is CLI. ASI mapping and trust boundary model are documentation (Constitution I). |

**Constitution gate: PASSED.** No violations requiring justification.

## Project Structure

### Documentation (this feature)

```text
specs/014-pipeline-security-hardening/
├── spec.md
├── plan.md              # This file
├── research.md          # Phase 0: CVE registry, version verification research
├── data-model.md        # Phase 1: CVE records, sensitive file entries, ASI mappings
├── quickstart.md        # Phase 1: Quick verification guide
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
scripts/
├── hardening-audit.sh               # EXTEND: add CVE verification, defense layer,
│                                     #   behavioral baseline, env var checks
├── lib/
│   ├── integrity.sh                 # EXTEND: HMAC-sign lock-state.json, heartbeat
│   └── cve-registry.sh              # NEW: CVE lookup functions
├── integrity-verify.sh              # EXTEND: behavioral baseline comparison
├── integrity-deploy.sh              # EXTEND: Ollama digest capture
├── integrity-rotate-key.sh          # EXTEND: update lock-state + heartbeat signing
└── test-phase5-integration.sh       # NEW: integration tests for 014

docs/
├── ASI-MAPPING.md                   # NEW: OWASP ASI Top 10 control mapping
├── TRUST-BOUNDARY-MODEL.md          # NEW: 5 trust zones with gaps
├── DEPENDENCY-UPDATE-PROCEDURE.md   # NEW: update/rollback procedures
└── SENSITIVE-FILE-INVENTORY.md      # NEW: complete file inventory with protections

data/
└── cve-registry.json                # NEW: maintained CVE database (version-controlled)
```

**Structure Decision**: This feature extends existing scripts (hardening-audit.sh, lib/integrity.sh) and adds documentation artifacts (docs/*.md) plus a CVE registry data file. No new directories beyond `data/`. Test follows existing `test-phase*-integration.sh` pattern.

## Phase 1: Security Verification (US1)

**Goal**: CVE verification, container hardening checks, HMAC consistency validation

1. Create `data/cve-registry.json` with known CVEs for n8n, OpenClaw, Ollama
2. Create `scripts/lib/cve-registry.sh` with lookup functions
3. Add `check_cve_n8n()` to hardening-audit.sh
4. Add `check_cve_openclaw()` to hardening-audit.sh
5. Add `check_cve_ollama()` to hardening-audit.sh
6. Add `check_hmac_secret_consistency()` to hardening-audit.sh
7. Verify existing container hardening checks cover FR-021 requirements

**Exit criteria**: `make audit` includes CVE checks, reports PASS for current versions

## Phase 2: Sensitive File Hardening (US2)

**Goal**: Sensitive file inventory, HMAC-sign lock-state.json and heartbeat, env file protection

8. Create `docs/SENSITIVE-FILE-INVENTORY.md` with all files and protections
9. Extend `integrity.sh`: HMAC-sign lock-state.json on write (ADV-002 fix)
10. Extend `integrity.sh`: HMAC-sign heartbeat on write (ADV-004 fix)
11. Add `check_sensitive_file_protections()` to hardening-audit.sh
12. Add `check_env_gitignore()` to hardening-audit.sh
13. Update `integrity-verify.sh`: verify lock-state and heartbeat signatures

**Exit criteria**: Audit verifies all 14+ sensitive files, ADV-002 and ADV-004 closed

## Phase 3: OWASP ASI Mapping + Defense-in-Depth (US3 + US5)

**Goal**: ASI mapping document, defense layer verification, behavioral baseline

14. Create `docs/ASI-MAPPING.md` with all 10 ASI risks mapped to controls
15. Add `check_defense_layer_prevent()` to hardening-audit.sh
16. Add `check_defense_layer_contain()` to hardening-audit.sh
17. Add `check_defense_layer_detect()` to hardening-audit.sh
18. Add `check_defense_layer_respond()` to hardening-audit.sh
19. Add `check_defense_layer_recover()` to hardening-audit.sh
20. Add `check_env_vars_dangerous()` to hardening-audit.sh (FR-023, ADV-007)
21. Implement behavioral baseline: webhook call frequency tracking in integrity-verify.sh

**Exit criteria**: All 10 ASI risks mapped, all 5 defense layers verifiable, env vars validated

## Phase 4: Dependency Management + Trust Boundary (US4 + US6)

**Goal**: Update procedures, LinkedIn token lifecycle, trust boundary model

22. Create `docs/DEPENDENCY-UPDATE-PROCEDURE.md` for n8n, OpenClaw, Ollama
23. Create `docs/TRUST-BOUNDARY-MODEL.md` with 5 trust zones and gaps
24. Extend `integrity-deploy.sh`: capture Ollama model digest
25. Update 010 spec R-006: correct LinkedIn refresh token information
26. Add token refresh logic to `workflows/token-check.json`

**Exit criteria**: Update procedures documented, trust model documented, token refresh implemented

## Phase 5: Integration Tests + Polish

**Goal**: End-to-end verification, shellcheck, documentation quality

27. Create `scripts/test-phase5-integration.sh` with tests for all new checks
28. Run `shellcheck` on all modified scripts — zero warnings
29. Run `make audit` full suite — verify all checks pass
30. Update `ROADMAP.md` with 014 completion status
31. Validate quickstart.md end-to-end

**Exit criteria**: All tests pass, shellcheck clean, full audit passes

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| CVE registry becomes stale | Medium | High — false PASS for vulnerable versions | Manual review on each dependency update; date-stamp entries |
| HMAC-signing lock-state.json breaks existing unlock flow | Medium | Medium — operator locked out of editing | Test unlock/re-lock cycle thoroughly; preserve backward compat |
| Behavioral baseline creates false positives | Medium | Low — alert fatigue | Start with high thresholds; tune based on operational data |
| n8n version upgrade introduces breaking changes | Low | High — pipeline down | Rollback procedure documented; manifest preserves previous digest |
| OpenClaw binary compromise undetected | Low | Critical — full pipeline takeover | Documented residual risk (FR-027); version pinning is partial mitigation |
| LLM provider output manipulation | Low | High — reputational damage | Human approval gate; documented residual risk (FR-026) |
