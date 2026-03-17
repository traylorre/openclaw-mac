# Data Model: Multi-Browser Support

**Feature**: 006-multi-browser-support | **Date**: 2026-03-16

## Entities

### Browser Registry Entry

The core data structure. Defined as parallel Bash associative arrays
in `scripts/browser-registry.sh` (shared file sourced by audit, fix,
and cleanup scripts).

| Field | Array Name | Type | Example (Edge) |
|-------|-----------|------|----------------|
| Short name | (array key) | string | `edge` |
| Display name | `BROWSER_NAME` | string | `Microsoft Edge` |
| App path | `BROWSER_APP_PATH` | string | `/Applications/Microsoft Edge.app` |
| Binary path | `BROWSER_BINARY_PATH` | string | `/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge` |
| Plist domain | `BROWSER_PLIST_DOMAIN` | string | `com.microsoft.Edge` |
| Profile dir | `BROWSER_PROFILE_DIR` | string | `~/Library/Application Support/Microsoft Edge/Default` |
| TCC bundle ID | `BROWSER_TCC_BUNDLE` | string | `com.microsoft.edgemac` |
| Homebrew cask | `BROWSER_CASK` | string | `microsoft-edge` |
| Process name | `BROWSER_PROCESS_NAME` | string | `Microsoft Edge` |

### Registry Data (3 entries)

```bash
# Chromium
BROWSER_NAME[chromium]="Chromium"
BROWSER_APP_PATH[chromium]="/Applications/Chromium.app"
BROWSER_BINARY_PATH[chromium]="/Applications/Chromium.app/Contents/MacOS/Chromium"
BROWSER_PLIST_DOMAIN[chromium]="org.chromium.Chromium"
BROWSER_PROFILE_DIR[chromium]="$HOME/Library/Application Support/Chromium/Default"
BROWSER_TCC_BUNDLE[chromium]="org.chromium.Chromium"
BROWSER_CASK[chromium]="chromium"
BROWSER_PROCESS_NAME[chromium]="Chromium"

# Google Chrome
BROWSER_NAME[chrome]="Google Chrome"
BROWSER_APP_PATH[chrome]="/Applications/Google Chrome.app"
BROWSER_BINARY_PATH[chrome]="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
BROWSER_PLIST_DOMAIN[chrome]="com.google.Chrome"
BROWSER_PROFILE_DIR[chrome]="$HOME/Library/Application Support/Google/Chrome/Default"
BROWSER_TCC_BUNDLE[chrome]="com.google.Chrome"
BROWSER_CASK[chrome]="google-chrome"
BROWSER_PROCESS_NAME[chrome]="Google Chrome"

# Microsoft Edge
BROWSER_NAME[edge]="Microsoft Edge"
BROWSER_APP_PATH[edge]="/Applications/Microsoft Edge.app"
BROWSER_BINARY_PATH[edge]="/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"
BROWSER_PLIST_DOMAIN[edge]="com.microsoft.Edge"
BROWSER_PROFILE_DIR[edge]="$HOME/Library/Application Support/Microsoft Edge/Default"
BROWSER_TCC_BUNDLE[edge]="com.microsoft.edgemac"
BROWSER_CASK[edge]="microsoft-edge"
BROWSER_PROCESS_NAME[edge]="Microsoft Edge"
```

### Derived Entities

**Installed Browser**: A registry entry where `[[ -d "${BROWSER_APP_PATH[$key]}" ]]`
returns true. Computed at runtime by iterating the registry.

```bash
# Helper function
get_installed_browsers() {
  local -a installed=()
  for browser in "${!BROWSER_APP_PATH[@]}"; do
    if [[ -d "${BROWSER_APP_PATH[$browser]}" ]]; then
      installed+=("$browser")
    fi
  done
  echo "${installed[@]}"
}
```

**Active Browser**: An installed browser with a running process,
detected via `pgrep -x "${BROWSER_PROCESS_NAME[$browser]}"`.

**Preferred Browser**: The first installed browser in preference order
`chromium > chrome > edge`. Used by `browser-cleanup.sh` when `--all`
is not specified.

```bash
BROWSER_PREFERENCE_ORDER=(chromium chrome edge)
```

## Relationships

```text
Browser Registry (3 entries)
    │
    ├── Installed Browsers (0-3, detected at runtime)
    │       │
    │       ├── Audit checks iterate installed browsers
    │       │   └── emit one result per check per browser
    │       │
    │       ├── Fix functions iterate installed browsers
    │       │   └── apply remediation per browser
    │       │
    │       └── Cleanup targets installed browsers
    │           └── --all: all installed; default: preferred only
    │
    └── Active Browsers (subset of installed, 0-3)
            └── Cleanup refuses to clean active browsers
```

## State Transitions

Browser registry entries are static (hardcoded in source). The only
runtime state is:

| State | Transition | Effect |
|-------|-----------|--------|
| Not installed | `brew install --cask $BROWSER_CASK` | Becomes installed |
| Installed, not running | Launch browser | Becomes active |
| Active (running) | Quit browser | Returns to installed |
| Installed | `brew uninstall --cask $BROWSER_CASK` | Returns to not installed |

The audit/fix scripts do not modify browser state — they only read it
to decide which checks to run and which policies to deploy.

## Validation Rules

- **App path must be a directory**: `[[ -d "${BROWSER_APP_PATH[$b]}" ]]`
- **Binary must be executable**: `[[ -x "${BROWSER_BINARY_PATH[$b]}" ]]`
  (used only for version checks)
- **Profile dir may not exist**: New installs may not have a Default
  profile yet. Cleanup skips with a warning; audit reports as WARN.
- **At least one browser must be installed**: If no registered browsers
  are found, all browser checks emit SKIP (not FAIL) — matching
  existing behavior for non-Chromium systems.
