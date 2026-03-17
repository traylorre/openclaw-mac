# Contract: Audit Output Schema

**Feature**: 006-multi-browser-support | **Date**: 2026-03-16

## CLI Interface

### hardening-audit.sh

**Invocation** (unchanged):

```bash
bash scripts/hardening-audit.sh [--json] [--section "Browser Security"]
```

### Output Format Change: Check IDs

**Before** (single browser):

```text
CHK-CHROMIUM-POLICY  : PASS  Managed policy plist deployed
CHK-CHROMIUM-CDP     : PASS  No CDP listeners on 9222 or 18800
```

**After** (per-browser results):

```text
CHK-BROWSER-POLICY [Chromium] : PASS  Managed policy plist deployed
CHK-BROWSER-POLICY [Edge]     : PASS  Managed policy plist deployed
CHK-BROWSER-CDP               : PASS  No CDP listeners on 9222 or 18800
```

**Rules**:
- Check IDs rename from `CHK-CHROMIUM-*` to `CHK-BROWSER-*`
- Browser-specific checks append `[BrowserName]` suffix
- Checks that are port-based (CDP) or process-based (DANGERFLAGS)
  may emit a single line if they scan system-wide, or per-browser
  lines if they can attribute findings to a specific browser
- If no registered browser is installed, all browser checks emit
  `SKIP` with message "No supported browser installed"

### JSON Output Change

**Before**:

```json
{
  "id": "CHK-CHROMIUM-POLICY",
  "status": "PASS",
  "message": "Managed policy plist deployed"
}
```

**After**:

```json
{
  "id": "CHK-BROWSER-POLICY",
  "browser": "Chromium",
  "status": "PASS",
  "message": "Managed policy plist deployed"
}
```

**New field**: `"browser"` (string) — the display name of the browser
this result applies to. Present on all `CHK-BROWSER-*` results.
Absent on non-browser checks.

### hardening-fix.sh

**Invocation** (unchanged):

```bash
bash scripts/hardening-fix.sh [--check CHK-BROWSER-POLICY] [--auto-approve]
```

**FIX_REGISTRY key change**:

| Old Key | New Key |
|---------|---------|
| `CHK-CHROMIUM-POLICY` | `CHK-BROWSER-POLICY` |
| `CHK-CHROMIUM-AUTOFILL` | `CHK-BROWSER-AUTOFILL` |
| `CHK-CHROMIUM-EXTENSIONS` | `CHK-BROWSER-EXTENSIONS` |
| `CHK-CHROMIUM-URLBLOCK` | `CHK-BROWSER-URLBLOCK` |
| `CHK-CHROMIUM-TCC` | `CHK-BROWSER-TCC` |
| `CHK-CHROMIUM-CDP` | `CHK-BROWSER-CDP` |
| `CHK-CHROMIUM-DANGERFLAGS` | `CHK-BROWSER-DANGERFLAGS` |
| `CHK-CHROMIUM-VERSION` | `CHK-BROWSER-VERSION` |

Fix functions apply to all installed browsers automatically.

### browser-cleanup.sh

**Before**:

```bash
bash scripts/browser-cleanup.sh [--profile PATH]
```

**After**:

```bash
bash scripts/browser-cleanup.sh [--profile PATH] [--all] [--browser NAME]
```

**New flags**:
- `--all`: Clean session data for all installed browsers
- `--browser NAME`: Clean only the named browser (chromium, chrome, edge)
- Default (no flags): Clean the preferred browser (Chromium > Chrome > Edge)

**Output change**: Cleanup messages name the specific browser being
cleaned instead of always saying "Chromium".
