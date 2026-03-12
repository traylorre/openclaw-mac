# Contract: Audit Script CLI Interface

**Artifact**: `scripts/hardening-audit.sh`
**FRs**: FR-007, FR-022, FR-023, FR-056

## Interface

```text
Usage: hardening-audit.sh [OPTIONS]

Options:
  --json             Output results in JSON format (FR-023)
  --section SECTION  Run checks for a specific section only
  --quiet            Suppress PASS output, show only FAIL/WARN
  --no-color         Disable colored output (for piping/logging)
  --help             Show usage information
  --version          Show script version

Exit codes:
  0    All checks passed (zero FAIL results)
  1    One or more FAIL results
  2    Script error (missing dependency, permission denied)

Statuses:
  PASS  Control is correctly configured
  FAIL  Critical control is missing or misconfigured
  WARN  Recommended control is missing or misconfigured
  SKIP  Check cannot run (lacking admin privileges, wrong deployment path, missing tool)
```

## Output Format: Human-Readable (default)

```text
================================================================
  OpenClaw Mac Hardening Audit
  Version: 1.0.0 | Date: 2026-03-11
  Deployment: containerized | macOS: Tahoe 26.0
================================================================

[Section: Disk Encryption]
  PASS  FileVault is enabled                        → §2.1
  PASS  FileVault recovery key is escrowed          → §2.1

[Section: Firewall]
  PASS  Application firewall is enabled             → §2.2
  WARN  Stealth mode is not enabled                 → §2.2

[Section: n8n Hardening]
  FAIL  n8n is bound to 0.0.0.0 (should be 127.0.0.1)  → §5.1
  WARN  N8N_BLOCK_ENV_ACCESS_IN_NODE is not set     → §5.3

================================================================
  Results: 48 PASS | 2 FAIL | 5 WARN
  Action required: Fix 2 FAIL items (see referenced sections)
================================================================
```

### Output Rules

- Every line prefixed with colored status: `PASS` (green), `FAIL` (red), `WARN` (yellow)
- Every line includes a guide section reference (`→ §X.Y`) for remediation
- FAIL items are always printed; PASS/WARN can be suppressed with `--quiet`
- Summary line at the end with total counts
- Colors disabled automatically when stdout is not a terminal (or via `--no-color`)

## Output Format: JSON (`--json` flag)

```json
{
  "version": "1.0.0",
  "timestamp": "2026-03-11T14:30:00Z",
  "system": {
    "macos_version": "26.0",
    "hardware": "Apple Silicon",
    "deployment": "containerized"
  },
  "results": [
    {
      "id": "CHK-FILEVAULT",
      "section": "Disk Encryption",
      "description": "FileVault is enabled",
      "status": "PASS|FAIL|WARN|SKIP",
      "guide_ref": "§2.1"
    },
    {
      "id": "CHK-N8N-BIND",
      "section": "n8n Hardening",
      "description": "n8n is bound to 0.0.0.0 (should be 127.0.0.1)",
      "status": "FAIL",
      "guide_ref": "§5.1",
      "remediation": "Set N8N_HOST=127.0.0.1 in your environment"
    }
  ],
  "summary": {
    "total": 55,
    "pass": 48,
    "fail": 2,
    "warn": 5,
    "skip": 0
  }
}
```

## Design Decision: `set -euo pipefail` with Failing Check Commands

The script uses `set -euo pipefail` (Constitution Article VI). However,
check commands intentionally return non-zero to indicate FAIL/WARN.

**Pattern**: Each check function runs the verification command in a
subshell with an explicit trap, preventing `set -e` from aborting the
script on an expected non-zero exit:

```bash
run_check() {
  local result
  result=$(eval "$1" 2>&1) || true  # capture exit code without triggering set -e
  # ... classify as PASS/FAIL/WARN/SKIP based on exit code and output
}
```

This preserves `set -euo pipefail` for the script's own logic while
allowing check commands to fail gracefully.

## Deployment Detection

The script auto-detects the deployment path at startup:

```text
1. Check if Docker/Colima is running AND an n8n container exists
   → Yes: deployment = "containerized"
   → No:  Check if an n8n process is running natively
          → Yes: deployment = "bare-metal"
          → No:  deployment = "unknown" (run OS-only checks)
```

When `deployment = "containerized"`:

- Run container-specific checks (non-root user, read-only fs, no privileged, secrets)
- Skip bare-metal-only checks (service account, Keychain access)

When `deployment = "bare-metal"`:

- Run bare-metal-specific checks (service account, file permissions)
- Skip container-specific checks

When `deployment = "unknown"`:

- Run OS-level checks only
- WARN that n8n was not detected

## Dependencies

Required (script exits with error if missing):

- bash 5.x
- macOS (script checks `uname` at startup)

Optional (graceful degradation):

- `jq` — required only for `--json` output; script warns if missing when `--json` is used
- `docker` — required for container checks; skipped if not available
- `colima` — checked for container runtime detection

## Check Categories

| Category | Severity | Count (approx) | Deployment |
|----------|----------|-----------------|------------|
| Disk encryption (FileVault) | critical | 2 | both |
| Firewall | critical | 3 | both |
| SIP | critical | 1 | both |
| Gatekeeper | critical | 1 | both |
| Authentication (guest, auto-login) | critical | 2 | both |
| Screen lock | critical | 1 | both |
| Sharing services | critical | 4 | both |
| n8n binding/auth | critical | 3 | both |
| SSH hardening | recommended | 4 | both |
| DNS security | recommended | 2 | both |
| Outbound filtering | recommended | 2 | both |
| IDS tools | recommended | 3 | both |
| Bluetooth | recommended | 1 | both |
| USB/Thunderbolt | recommended | 1 | both |
| Software updates | recommended | 2 | both |
| Logging | recommended | 2 | both |
| Backup | recommended | 2 | both |
| Container isolation | critical | 6 | containerized |
| Service account | critical | 3 | bare-metal |
| n8n env vars | recommended | 4 | both |
| Supply chain | recommended | 2 | containerized |
| Credential exposure | recommended | 3 | both |
| iCloud services | recommended | 2 | both |
