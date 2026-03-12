# Quickstart: Hardening Guide Extension

**Plan**: [plan.md](plan.md) | **Spec**: [spec.md](spec.md) (Rev 29)

## What This Feature Produces

1. **`docs/HARDENING.md`** — A comprehensive macOS hardening guide
   (~3,000-5,000 lines) replacing the current 68-line stub
2. **`scripts/hardening-audit.sh`** — A standalone Bash audit script
   with 55+ automated security checks
3. **`scripts/templates/docker-compose.yml`** — Reference secure
   Docker Compose configuration for n8n
4. **`scripts/launchd/*.plist`** — launchd plist templates for
   scheduled auditing and notifications

## Development Prerequisites

- macOS Tahoe (26) or Sonoma (14) — for testing audit script
- Homebrew — `brew install shellcheck markdownlint-cli2`
- Node.js — `npm install` (sets up linter + git hooks)
- Docker CLI + Colima — for testing container-path audit checks
- A running n8n instance (container or bare-metal) — for testing
  n8n-specific checks

## Build and Verify

```bash
# Lint the guide
npx markdownlint-cli2 docs/HARDENING.md

# Lint the audit script
shellcheck --severity=warning scripts/hardening-audit.sh

# Run the audit script
bash scripts/hardening-audit.sh

# Run with JSON output
bash scripts/hardening-audit.sh --json | jq .

# CI pipeline (runs automatically on push)
# .github/workflows/lint.yml handles markdownlint + link checking
```

## Implementation Order

The guide is implemented section-by-section, one PR per section.
Each section is validated on a fresh Sonoma MacBook before the next
section begins (see plan.md "Testing Strategy" for full details).

1. **Threat Model** (§1) — foundation for everything else
2. **OS Foundation** (§2) — FileVault, firewall, SIP, etc.
3. **Network Security** (§3) — SSH, DNS, outbound filtering
4. **Container Isolation** (§4) — Colima, Docker Compose, hardening
5. **n8n Platform Security** (§5) — binding, auth, env vars, webhooks
6. **Bare-Metal Path** (§6) — service account, Keychain, launchd
7. **Data Security** (§7) — credentials, injection, PII, SSRF
8. **Detection and Monitoring** (§8) — IDS, logging, integrity
9. **Response and Recovery** (§9) — IR runbook, backups, rotation
10. **Operational Maintenance** (§10) — scheduling, notifications
11. **Audit Script Reference** (§11) + appendices — build incrementally alongside each section

**Delivery**: One PR per section. Audit script checks for each section
are included in the same PR as the guide section they verify.

## Key Conventions

- Every control section uses the CIS Benchmark pattern:
  Threat → Why → How → Verify → Edge Cases
- Two deployment paths must be independently complete
- Free tools are primary; paid tools marked with `[PAID]`
- All sources cited per Constitution Article IV
- Cross-references use `§X.Y` notation
- Audit checks use `CHK-*` identifiers
