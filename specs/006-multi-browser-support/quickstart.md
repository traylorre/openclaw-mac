# Quickstart: Multi-Browser Support

**Feature**: 006-multi-browser-support | **Date**: 2026-03-16

## Implementation Order

```text
1. browser-registry.sh   ← NEW shared file, foundation for everything
2. hardening-audit.sh    ← source registry, refactor 8 checks, rename IDs
3. hardening-fix.sh      ← source registry, refactor 5 fix functions
4. browser-cleanup.sh    ← source registry, --all flag
5. CHK-REGISTRY.md       ← rename 8 check IDs
6. HARDENING.md          ← update section 2.11, badges, references
7. GETTING-STARTED*.md   ← add Edge mention (2 files)
```

## Step 1: Create browser-registry.sh

3 browsers = 3 concrete use-cases = shared file per Rule-of-Three.
All three scripts source this file:

```bash
#!/usr/bin/env bash
# scripts/browser-registry.sh — Shared browser registry.
# Source this file from audit, fix, and cleanup scripts.
# To add a new browser: add one block below. No other changes needed.
declare -A BROWSER_NAME BROWSER_APP_PATH BROWSER_BINARY_PATH
declare -A BROWSER_PLIST_DOMAIN BROWSER_PROFILE_DIR BROWSER_TCC_BUNDLE
declare -A BROWSER_CASK BROWSER_PROCESS_NAME

BROWSER_PREFERENCE_ORDER=(chromium chrome edge)

BROWSER_NAME[chromium]="Chromium"
BROWSER_APP_PATH[chromium]="/Applications/Chromium.app"
BROWSER_BINARY_PATH[chromium]="/Applications/Chromium.app/Contents/MacOS/Chromium"
BROWSER_PLIST_DOMAIN[chromium]="org.chromium.Chromium"
BROWSER_PROFILE_DIR[chromium]="$HOME/Library/Application Support/Chromium/Default"
BROWSER_TCC_BUNDLE[chromium]="org.chromium.Chromium"
BROWSER_CASK[chromium]="chromium"
BROWSER_PROCESS_NAME[chromium]="Chromium"

BROWSER_NAME[chrome]="Google Chrome"
BROWSER_APP_PATH[chrome]="/Applications/Google Chrome.app"
BROWSER_BINARY_PATH[chrome]="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
BROWSER_PLIST_DOMAIN[chrome]="com.google.Chrome"
BROWSER_PROFILE_DIR[chrome]="$HOME/Library/Application Support/Google/Chrome/Default"
BROWSER_TCC_BUNDLE[chrome]="com.google.Chrome"
BROWSER_CASK[chrome]="google-chrome"
BROWSER_PROCESS_NAME[chrome]="Google Chrome"

BROWSER_NAME[edge]="Microsoft Edge"
BROWSER_APP_PATH[edge]="/Applications/Microsoft Edge.app"
BROWSER_BINARY_PATH[edge]="/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"
BROWSER_PLIST_DOMAIN[edge]="com.microsoft.Edge"
BROWSER_PROFILE_DIR[edge]="$HOME/Library/Application Support/Microsoft Edge/Default"
BROWSER_TCC_BUNDLE[edge]="com.microsoft.edgemac"
BROWSER_CASK[edge]="microsoft-edge"
BROWSER_PROCESS_NAME[edge]="Microsoft Edge"

# Helper: list installed browsers (short names)
get_installed_browsers() {
  local -a installed=()
  for browser in "${BROWSER_PREFERENCE_ORDER[@]}"; do
    if [[ -d "${BROWSER_APP_PATH[$browser]}" ]]; then
      installed+=("$browser")
    fi
  done
  echo "${installed[@]}"
}

# Helper: get preferred browser (first installed in preference order)
get_preferred_browser() {
  for browser in "${BROWSER_PREFERENCE_ORDER[@]}"; do
    if [[ -d "${BROWSER_APP_PATH[$browser]}" ]]; then
      echo "$browser"
      return 0
    fi
  done
  return 1
}
```

## Step 2: Refactor audit checks

Pattern for converting a check function:

**Before** (hardcoded):

```bash
check_chromium_policy() {
  local plist_path
  plist_path="$(_chromium_policy_plist)"
  # ... check logic using plist_path
  emit_result "CHK-CHROMIUM-POLICY" "$status" "$message"
}
```

**After** (parameterized):

```bash
check_browser_policy() {
  local browser="$1"
  local domain="${BROWSER_PLIST_DOMAIN[$browser]}"
  local name="${BROWSER_NAME[$browser]}"
  # ... same check logic using $domain
  emit_result "CHK-BROWSER-POLICY" "$status" "$message" "$name"
}

# Wrapper that iterates installed browsers
run_browser_checks() {
  local -a installed
  read -ra installed <<< "$(get_installed_browsers)"
  if [[ ${#installed[@]} -eq 0 ]]; then
    emit_result "CHK-BROWSER-POLICY" "SKIP" "No supported browser installed"
    return
  fi
  for browser in "${installed[@]}"; do
    check_browser_policy "$browser"
    check_browser_autofill "$browser"
    # ... all 8 checks
  done
}
```

## Step 3: Refactor fix functions

Same parameterization pattern. Key difference: the policy XML is
shared across all browsers — only the output plist path changes.

```bash
fix_browser_policy() {
  local browser="$1"
  local domain="${BROWSER_PLIST_DOMAIN[$browser]}"
  local plist_path="/Library/Managed Preferences/${domain}.plist"
  # Write the same policy XML to the browser-specific plist path
}
```

## Step 4: Add --all to browser-cleanup.sh

```bash
# Parse new flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)     cleanup_all=true; shift ;;
    --browser) cleanup_target="$2"; shift 2 ;;
    --profile) profile_override="$2"; shift 2 ;;
    *)         shift ;;
  esac
done

# Determine which browsers to clean
if [[ "$cleanup_all" == true ]]; then
  read -ra targets <<< "$(get_installed_browsers)"
elif [[ -n "${cleanup_target:-}" ]]; then
  targets=("$cleanup_target")
else
  targets=("$(get_preferred_browser)")
fi
```

## Key Gotchas

1. **Paths with spaces**: Edge's profile dir has spaces. Always quote
   `"${BROWSER_PROFILE_DIR[$browser]}"`.
2. **TCC bundle ≠ plist domain for Edge**: Edge's TCC bundle is
   `com.microsoft.edgemac` but its policy domain is `com.microsoft.Edge`.
3. **Process name has spaces**: `pgrep -x "Microsoft Edge"` needs quotes.
4. **Associative array iteration order**: Bash doesn't guarantee order.
   Use `BROWSER_PREFERENCE_ORDER` array for deterministic iteration.
5. **shellcheck**: Add `# shellcheck source=browser-registry.sh`
   directive before the `source` line in consuming scripts to suppress
   SC1091 warnings.
