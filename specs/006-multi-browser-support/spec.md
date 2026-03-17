# Feature Specification: Multi-Browser Support

**Feature Branch**: `006-multi-browser-support`
**Created**: 2026-03-16
**Status**: Draft
**Input**: Refactor Chromium-specific hardening to a browser registry pattern supporting Chromium, Chrome, and Edge with shared policy keys and per-browser paths, bundle IDs, and process names.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Edge User Gets Same Protections as Chromium (Priority: P1)

An operator installs Microsoft Edge instead of Chromium. When they
run the audit, all 8 browser security checks detect Edge and report
its security status. When they run the fix script, all remediation
applies to Edge — managed policies are deployed to Edge's plist
domain, TCC permissions target Edge's bundle ID, and the version
check uses Edge's Homebrew cask.

**Why this priority**: This is the core deliverable — Edge users
get the same security coverage as Chromium users without needing
a separate set of scripts or checks.

**Independent Test**: Install Edge via `brew install --cask
microsoft-edge`, run the audit, verify all 8 browser checks detect
Edge and report correctly. Run the fix script and verify Edge-specific
policies are deployed.

**Acceptance Scenarios**:

1. **Given** only Microsoft Edge is installed, **When** the audit
   runs, **Then** all 8 `CHK-BROWSER-*` checks detect Edge and
   report PASS/FAIL/WARN (not SKIP).
2. **Given** only Microsoft Edge is installed, **When** the fix
   script deploys managed policies, **Then** the plist is written
   to `com.microsoft.Edge.plist` (not `org.chromium.Chromium.plist`).
3. **Given** only Microsoft Edge is installed, **When** the TCC fix
   runs, **Then** camera and microphone are reset for bundle ID
   `com.microsoft.edgemac`.

---

### User Story 2 - Multiple Browsers Detected and Checked (Priority: P1)

An operator has both Chromium and Edge installed. The audit checks
both browsers and reports findings for each. The fix script applies
policies to all detected browsers, not just the first one found.

**Why this priority**: Real deployments may have multiple Chromium-
based browsers installed. Checking only one leaves the other
unprotected.

**Independent Test**: Install both Chromium and Edge, run the audit,
verify both are checked and both receive managed policies.

**Acceptance Scenarios**:

1. **Given** both Chromium and Edge are installed, **When** the audit
   runs, **Then** browser security checks report findings for both
   browsers.
2. **Given** both Chromium and Edge are installed, **When** the fix
   script deploys managed policies, **Then** both
   `org.chromium.Chromium.plist` and `com.microsoft.Edge.plist` are
   created.
3. **Given** both browsers are installed, **When** the TCC fix runs,
   **Then** camera and microphone are reset for both bundle IDs.

---

### User Story 3 - Browser Cleanup Works for Any Installed Browser (Priority: P2)

An operator runs `browser-cleanup.sh` and it detects which browser
is installed (Chromium, Chrome, or Edge), finds the correct profile
directory, and cleans session data. If multiple browsers are
installed, it cleans all of them.

**Why this priority**: Session data cleanup is critical for limiting
the exposure window after automation runs. It must work regardless
of which browser is in use.

**Independent Test**: Create session data in an Edge profile, run
cleanup, verify Edge profile data is removed.

**Acceptance Scenarios**:

1. **Given** Edge is the only installed browser, **When** cleanup
   runs, **Then** Edge's profile data is cleaned from
   `~/Library/Application Support/Microsoft Edge/Default/`.
2. **Given** both Chromium and Edge are installed, **When** cleanup
   runs with `--all`, **Then** both profiles are cleaned.
3. **Given** Edge is running, **When** cleanup is attempted, **Then**
   it refuses with a warning naming "Microsoft Edge" (not "Chromium").

---

### User Story 4 - GETTING-STARTED Guides Mention Edge (Priority: P3)

Both getting-started guides mention Edge as a supported alternative
to Chromium, with the correct install command and a note that all
browser security checks apply equally.

**Why this priority**: New operators should know Edge is supported
without reading the full HARDENING.md.

**Independent Test**: Read the Next Steps section and verify Edge
is mentioned with its install command.

**Acceptance Scenarios**:

1. **Given** GETTING-STARTED.md or GETTING-STARTED-INTEL.md is open,
   **When** the reader reaches the Chromium section, **Then** they
   see a note that Edge is also supported with
   `brew install --cask microsoft-edge`.

---

### Edge Cases

- Only one of three browsers is installed. Checks and fixes apply
  to that browser only, no errors for missing browsers.
- A browser is installed via `.dmg` download, not Homebrew. Detection
  works by checking app paths, not Homebrew. Version auto-update is
  skipped with a manual instruction.
- Brave or Vivaldi (other Chromium-based browsers) are installed.
  These are out of scope for this feature but the registry pattern
  should make adding them trivial in the future.
- CDP is running on a port opened by Edge, not Chromium. The CDP
  check detects the correct process name and reports accordingly.
- Browser-cleanup is called with `--profile` pointing to an Edge
  profile. It should work regardless of the `--profile` path.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A browser registry MUST define per-browser metadata:
  app path, binary path, managed policy plist domain, profile
  directory, TCC bundle ID, Homebrew cask name, and process name
  for each supported browser.
- **FR-002**: The registry MUST support Chromium, Google Chrome, and
  Microsoft Edge at launch. Adding a new Chromium-based browser
  MUST require only adding one registry entry (no new functions).
- **FR-003**: All 8 existing `CHK-CHROMIUM-*` audit checks MUST be
  refactored to use the browser registry instead of hardcoded
  paths and names.
- **FR-004**: Audit checks MUST iterate over all installed browsers
  and report findings for each. A check that finds Edge and Chromium
  both installed MUST check both.
- **FR-005**: Fix functions MUST apply remediation to all detected
  browsers (e.g., deploy managed policies for both Chromium and
  Edge if both are installed).
- **FR-006**: The `CHK-CHROMIUM-*` check IDs MUST be renamed to
  browser-neutral names: `CHK-BROWSER-POLICY`, `CHK-BROWSER-CDP`,
  `CHK-BROWSER-TCC`, `CHK-BROWSER-VERSION`, `CHK-BROWSER-DANGERFLAGS`,
  `CHK-BROWSER-AUTOFILL`, `CHK-BROWSER-EXTENSIONS`,
  `CHK-BROWSER-URLBLOCK`.
- **FR-007**: `browser-cleanup.sh` MUST detect all installed
  browsers and clean session data for each. A new `--all` flag
  MUST clean all detected profiles. Without `--all`, it MUST clean
  the preferred browser (Chromium > Chrome > Edge).
- **FR-008**: The `CHK-REGISTRY.md` MUST be updated to reflect
  renamed or expanded check IDs.
- **FR-009**: The HARDENING.md coverage summary and badges MUST be
  updated if check IDs change.
- **FR-010**: All existing Chromium-only **functional behavior** MUST
  continue to work for operators who only have Chromium installed
  (backward compatibility). Note: check IDs change from
  `CHK-CHROMIUM-*` to `CHK-BROWSER-*` per FR-006 — this is an
  intentional output format change, not a functional regression.
- **FR-011**: The GETTING-STARTED guides MUST mention Edge as a
  supported alternative with the correct Homebrew install command.

### Key Entities

- **Browser Registry Entry**: A record defining one supported
  browser with: name, app path, binary path, policy plist domain,
  profile directory, TCC bundle ID, Homebrew cask name, and process
  name.
- **Installed Browser**: A browser detected on the system by
  checking if its app path exists. Multiple browsers can be
  installed simultaneously.
- **Active Browser**: An installed browser with a running process,
  detectable via pgrep with the registered process name.

### Rabbit Holes (Identified, Deferred)

- **RH-001: Brave/Vivaldi/Arc support** — Other Chromium-based
  browsers exist. The registry pattern makes adding them trivial
  (one entry each) but testing and documenting each is effort.
  *Defer unless requested.*
- **RH-002: Per-browser CHK IDs** — Resolved: rename to
  `CHK-BROWSER-*`. Requires updating CHK-REGISTRY.md, coverage
  map badges, hardening-audit.sh, hardening-fix.sh, and any
  audit JSON consumers that reference the old IDs.
- **RH-003: Multi-profile support** — Each browser can have
  multiple profiles (Default, Profile 1, etc.). Currently only
  Default is checked and cleaned. *Defer unless required.*

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An operator with only Edge installed gets the same
  8 audit checks and fix coverage as an operator with only Chromium.
- **SC-002**: Adding a new Chromium-based browser requires adding
  one registry entry and zero new functions.
- **SC-003**: All existing Chromium-only deployments continue to
  work with zero changes to their workflow.
- **SC-004**: Browser cleanup works for any combination of installed
  browsers without the operator specifying which one.
- **SC-005**: The total lines of browser-specific code decreases
  compared to duplicating functions for each browser.

## Assumptions

- Microsoft Edge for macOS uses the same managed policy keys as
  Chromium (confirmed: Edge is built on Chromium and supports the
  same enterprise policy schema).
- Edge's TCC bundle ID is `com.microsoft.edgemac` (verified from
  Apple's TCC database schema).
- Edge's Homebrew cask is `microsoft-edge`.
- Edge's default profile directory is
  `~/Library/Application Support/Microsoft Edge/Default/`.
- CDP on Edge uses the same `--remote-debugging-port` and
  `--remote-debugging-address` flags as Chromium.

## Clarifications

### Session 2026-03-16

- Q: Should check IDs be renamed from CHK-CHROMIUM-* to CHK-BROWSER-*? → A: Yes, rename to CHK-BROWSER-* for accuracy when checking Edge or other Chromium-based browsers.

## Out of Scope

- Non-Chromium browsers (Firefox, Safari).
- Brave, Vivaldi, Arc, or other Chromium forks beyond the initial
  three (Chromium, Chrome, Edge). The registry makes adding them
  easy but testing and documentation is deferred.
- Per-profile security (only the Default profile is checked).
- Modifying how OpenClaw or other frameworks select which browser
  to use.
