# Context Carryover 02: Hardening Guide Extension

**Feature Branch:** `001-hardening-guide-extension`
**Date:** 2026-03-07
**Spec Revision:** Rev 14 → Rev 17 (this session)
**Constitution Version:** 1.3.0 (unchanged this session)

## Project: openclaw-mac

**Repo:** `https://github.com/traylorre/openclaw-mac`
**Branch:** `001-hardening-guide-extension`
**Purpose:** macOS hardening guides + audit tooling for a Mac Mini running n8n + Apify for LinkedIn lead gen

## Key Files

| File | What |
|------|------|
| `.specify/memory/constitution.md` | v1.3.0 -- 10 articles (I-X), injection adversary in Article II |
| `specs/001-hardening-guide-extension/spec.md` | Rev 17 -- 37 FRs, 9 user stories, 16 SCs, 29 edge cases, 7 key entities |
| `specs/001-hardening-guide-extension/checklists/requirements.md` | All items pass |
| `specs/001-hardening-guide-extension/CONTEXT-CARRYOVER-01.md` | Prior session context (Rev 3) |
| `docs/HARDENING.md` | Current thin guide -- to be replaced |
| `docs/SONOMA-HARDENING.md` | Separate addendum, out of scope |
| `.github/workflows/lint.yml` | CI: markdownlint-cli2 + lychee link checker |

## Session Summary

This session ran 6 `/speckit.specify` rounds across two invocations,
advancing the spec from Rev 11 (starting state) to Rev 17.

### Invocation 1: Maintainability & Low-Touch Operation (Rev 12-14)

Focus: automated monitoring, notification, and maintainability.

- **Rev 12 (low-touch automated audit scheduling):**
  - US-8: Operator Configures Automated Security Monitoring (P2)
  - FR-022: scheduled audit via launchd (plist template, weekly default)
  - FR-023: machine-readable audit output (`--json` flag)
  - SC-013: routine maintenance < 15 min/month
  - FR-009 ongoing tier + FR-020 post-update checklist updated

- **Rev 13 (automated failure notification):**
  - FR-024: email (msmtp/mailx + SMTP relay) + macOS Notification Center + optional webhook
  - FR-025: alert design — FAIL-only active alerts, WARN logged silently
  - SC-014: fully unattended monitoring after initial config

- **Rev 14 (maintainability and self-monitoring):**
  - FR-026: automated tool maintenance (ClamAV freshclam, brew outdated, n8n updates)
  - FR-027: log retention (90 days), rotation, self-monitoring meta-audit
  - Key Entity: Scheduled Job

### Invocation 2: Top-10 Weakness Analysis (Rev 15-17)

Systematically identified and strengthened the 10 weakest areas:

| # | Weakness | Resolution |
|---|----------|------------|
| 1 | SSH hardening -- no specifics | FR-028: key-only, root disabled, AllowUsers, timeout, ed25519 |
| 2 | Outbound filtering -- no FR | FR-030: pf allowlisting, LuLu (free), Little Snitch [PAID] |
| 3 | DNS security -- no FR | FR-029: encrypted DNS (DoH/DoT), Quad9 vs Cloudflare |
| 4 | IDS -- no FR | FR-032: Santa, BlockBlock, LuLu, KnockKnock |
| 5 | Launch daemon auditing -- no FR | FR-033: baseline creation, drift detection |
| 6 | USB/Thunderbolt -- no FR | FR-034: accessory security, BadUSB/DMA |
| 7 | Incident response -- no Respond layer | FR-031 + US-9: triage → containment → recovery |
| 8 | macOS logging -- thin | FR-035: unified log predicates, security events |
| 9 | Bare-metal service account -- vague | FR-036: dedicated `_n8n` user, filesystem isolation |
| 10 | Restore testing -- no details | FR-037: non-destructive restore test, key escrow |

- **Rev 15**: FR-028 (SSH), FR-029 (DNS), FR-030 (outbound), FR-031 (incident response), US-9
- **Rev 16**: FR-032 (IDS), FR-033 (launch daemons), FR-034 (USB), FR-035 (logging)
- **Rev 17**: FR-036 (service account), FR-037 (restore testing), SC-015, SC-016
- Fixed FR-002 bug: "25 control areas" → "26 control areas"

## Spec Rev 17 -- Cumulative State

| Metric | Count |
|--------|-------|
| Functional requirements | 37 (FR-001 to FR-037) |
| User stories | 9 (US-1 to US-9) |
| Success criteria | 16 (SC-001 to SC-016) |
| Edge cases | 29 |
| Key Entities | 7 |
| Control areas | 26 |
| Assumptions | 11 |

### Key Decisions (cumulative)

- **Colima** = primary container runtime (free, CLI-only, no licensing)
- **Docker Desktop** = noted alternative (same `docker` CLI, adds GUI + licensing)
- **Two deployment paths:** containerized (recommended) + bare-metal (alternative), independently complete
- **launchd** = scheduling mechanism (preferred over cron for macOS sleep/wake handling)
- **Email** = primary notification channel (msmtp/mailx + SMTP relay)
- **macOS Notification Center** = local fallback notification channel
- **FAIL-only active alerts** to prevent alert fatigue; WARN logged silently
- **Google Santa + Objective-See tools** = IDS stack (all free)
- **pf + LuLu** = free outbound filtering; Little Snitch as paid option
- **Quad9** = primary DNS provider (free, malware-blocking)
- **Dedicated service account** (`_n8n`) for bare-metal isolation
- **90-day log retention** with rotation via newsyslog or launchd
- **Quarterly restore testing** with non-destructive procedure

### FR Index by Control Area

| Control Area | Primary FRs |
|--------------|-------------|
| 1. FileVault | FR-007 (critical check) |
| 2. Firewall | FR-007 (critical check) |
| 3. SIP | FR-007 (critical check) |
| 4. Gatekeeper | FR-007 (critical check) |
| 5. Software updates | FR-009 (immediate tier) |
| 6. DNS security | FR-029 |
| 7. Screen lock | FR-007 (critical check) |
| 8. n8n hardening | FR-011 |
| 9. Credential management | FR-012 |
| 10. Antivirus/EDR | FR-005, FR-006 |
| 11. IDS | FR-032 |
| 12. Bluetooth | FR-009 (follow-up tier) |
| 13. SSH | FR-028 |
| 14. USB/Thunderbolt | FR-034 |
| 15. Sharing services | FR-007 (critical check) |
| 16. Outbound filtering | FR-030 |
| 17. Logging and alerting | FR-035, FR-022-027 |
| 18. Backup and recovery | FR-018, FR-037 |
| 19. PII protection | FR-013 |
| 20. Launch daemon auditing | FR-033 |
| 21. Physical security | FR-009 (immediate tier) |
| 22. Guest account | FR-007 (critical check) |
| 23. Automatic login | FR-007 (critical check) |
| 24. IPv6 | FR-009 (follow-up tier) |
| 25. Container isolation | FR-016, FR-017 |
| 26. Injection defense | FR-021 |

### User Story Index

| US | Title | Priority |
|----|-------|----------|
| 1 | Operator Hardens a Fresh Mac Mini | P1 |
| 2 | Operator Audits an Existing Mac Mini | P2 |
| 3 | Operator Evaluates Free vs Paid Security Tools | P2 |
| 4 | Operator Secures n8n Specifically | P1 |
| 5 | Operator Isolates n8n via Container | P1 |
| 6 | Operator Maintains Hardened State Over Time | P2 |
| 7 | Operator Secures Workflows Against Injection | P1 |
| 8 | Operator Configures Automated Security Monitoring | P2 |
| 9 | Operator Responds to a Suspected Breach | P2 |

## Threat Model

- **Platform:** Mac Mini (Apple Silicon or Intel), headless, macOS Tahoe/Sonoma
- **Workload:** n8n orchestrating Apify actors for LinkedIn scraping
- **Assets:** LinkedIn creds, Apify API keys, PII lead data, n8n workflow IP, SSH keys, SMTP creds
- **Adversaries:** network scanners, credential stuffing, npm supply chain, physical theft, LAN-adjacent, adversarial scraped content (prompt/command/code injection)

## What's Next

- `/speckit.clarify` -- optional, to resolve any remaining ambiguity
- `/speckit.plan` -- break spec into implementation tasks
- Implementation: rewrite `docs/HARDENING.md` with full content + audit script

## How to Resume

1. Read this file for context (covers Rev 12-17)
2. Read `CONTEXT-CARRYOVER-01.md` for earlier session context (Rev 1-3)
3. Read `specs/001-hardening-guide-extension/spec.md` for current spec (Rev 17)
4. Read `.specify/memory/constitution.md` for governance rules (v1.3.0)
5. Continue with `/speckit.clarify`, `/speckit.plan`, or more `/speckit.specify` rounds
