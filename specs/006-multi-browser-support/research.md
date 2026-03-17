# Research: Multi-Browser Support

**Feature**: 006-multi-browser-support | **Date**: 2026-03-16

## R1: Edge managed policy compatibility

**Decision**: Microsoft Edge uses the same Chromium enterprise policy
schema as Chromium and Google Chrome. The plist domain is
`com.microsoft.Edge`.

**Rationale**: Edge is built on Chromium and documents support for the
same policy keys (PasswordManagerEnabled, AutofillAddressEnabled,
ExtensionInstallBlocklist, URLBlocklist, etc.) in Microsoft's
[Edge enterprise policy reference](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies).
The existing policy XML can be deployed verbatim to Edge's plist domain.

**Alternatives considered**: None — this is a factual finding, not a
design choice.

## R2: Edge TCC bundle ID

**Decision**: Edge's TCC bundle ID is `com.microsoft.edgemac`.

**Rationale**: Verified from macOS TCC database schema. The bundle ID
differs from the managed policy plist domain (`com.microsoft.Edge`),
which is a common pattern for Microsoft macOS apps. The audit's
`tccutil reset` commands and sqlite3 TCC.db queries must use
`com.microsoft.edgemac`, not `com.microsoft.Edge`.

**Alternatives considered**: `com.microsoft.Edge` (incorrect for TCC).

## R3: Edge Homebrew cask name

**Decision**: `microsoft-edge`

**Rationale**: Verified via `brew info --cask microsoft-edge`. This is
the official cask maintained in homebrew-cask.

**Alternatives considered**: None.

## R4: Edge profile directory

**Decision**: `~/Library/Application Support/Microsoft Edge/Default/`

**Rationale**: Matches Chromium's pattern but uses "Microsoft Edge"
as the application directory name. Verified by inspecting Edge's
data directory on macOS.

**Alternatives considered**: None.

## R5: Edge process name for pgrep/ps

**Decision**: `Microsoft Edge` (with space, as shown by `ps aux`).

**Rationale**: Edge's main process appears as `Microsoft Edge` in
process listings, similar to how `Google Chrome` appears with a space.
The `pgrep` pattern needs to account for this.

**Alternatives considered**: `msedge` (the Linux binary name — not
used on macOS).

## R6: Bash associative array vs. alternatives for registry

**Decision**: Use multiple `declare -A` associative arrays, one per
metadata field, keyed by browser short name.

**Rationale**: Considered four approaches:

| Approach | Pros | Cons |
|----------|------|------|
| Associative arrays (chosen) | Native Bash 4+, no escaping needed, handles spaces in paths | Requires Bash 4+ (we mandate 5.x) |
| Colon-delimited strings | Works in any shell | Breaks on paths with spaces (Edge profile dir) |
| JSON + jq | Structured, easy to extend | Adds jq as hard dependency to audit/fix scripts |
| External config file | Separation of concerns | Another file to sync, parse complexity |

Associative arrays are the cleanest fit for our constraints (Bash 5.x
floor, paths with spaces, 3 browsers).

## R7: Check output format for multi-browser results

**Decision**: Each check emits one result line per installed browser,
with the browser name in brackets:
`CHK-BROWSER-POLICY [Chromium]: PASS`
`CHK-BROWSER-POLICY [Edge]: FAIL`

**Rationale**: A single aggregated PASS/FAIL per check would hide
which browser failed. Per-browser output lets the operator see exactly
which browser needs attention. The existing `emit_result` function
can be extended to accept a suffix parameter.

**Alternatives considered**:
- Aggregated result (FAIL if any browser fails): less actionable
- Separate check IDs per browser (CHK-BROWSER-POLICY-CHROMIUM): breaks
  the "one registry entry, zero new functions" requirement (FR-002)

## R8: CDP port check across browsers

**Decision**: CDP port checks (9222 default, 18800 OpenClaw) apply to
all browsers equally. The check identifies which browser process owns
the port via `lsof` output.

**Rationale**: Any Chromium-based browser uses the same
`--remote-debugging-port` flag. The port owner is identified from the
process name in `lsof` output, which maps back to the registry's
process name field.

**Alternatives considered**: None — the existing approach works, just
needs the process name parameterized.

## R9: Backward compatibility for Chromium-only deployments

**Decision**: No changes to operator workflow. The audit/fix scripts
auto-detect installed browsers. If only Chromium is installed, behavior
is identical to pre-refactor except check IDs say `CHK-BROWSER-*`
instead of `CHK-CHROMIUM-*`.

**Rationale**: FR-010 requires backward compatibility. The only
visible change is the check ID rename, which is explicitly required
by FR-006. No new flags or configuration needed for existing operators.

**Alternatives considered**: An opt-in `--multi-browser` flag was
considered and rejected — the whole point is that multi-browser
detection is automatic.
