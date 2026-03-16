# Feature Specification: Chromium CDP Hardening

**Feature Branch**: `005-chromium-cdp-hardening`
**Created**: 2026-03-16
**Status**: Draft
**Input**: Close the 3 remaining Chromium audit-only gaps (CDP port binding, version freshness, dangerous launch flags) with auto-fixes or actionable remediation, add browser data cleanup automation, and integrate Chromium setup into the GETTING-STARTED.md guide.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - CDP Port Binding Verified and Fixable (Priority: P1)

An operator runs the audit and the system detects whether the Chrome
DevTools Protocol port (9222 or 18800) is bound to localhost only or
exposed to the network. If exposed, the fix script can warn the
operator with specific remediation steps rather than silently
reporting WARN.

**Why this priority**: An unauthenticated CDP port bound to `0.0.0.0`
is remote code execution for any process on the network. This is the
highest-risk gap in the entire Chromium section. CDP has zero
authentication — anyone who can reach the port has full browser
control including cookie extraction, JavaScript execution, and
screenshot capture.

**Independent Test**: Start Chromium with `--remote-debugging-port=9222`
(without `--remote-debugging-address=127.0.0.1`), run the audit, and
verify the check reports FAIL with actionable remediation. Then restart
with the correct flags and verify PASS.

**Acceptance Scenarios**:

1. **Given** Chromium is running with CDP on port 9222 bound to
   `0.0.0.0`, **When** the audit runs, **Then** `CHK-CHROMIUM-CDP`
   reports FAIL with remediation showing the correct launch flags.
2. **Given** Chromium is running with CDP on port 9222 bound to
   `127.0.0.1`, **When** the audit runs, **Then** `CHK-CHROMIUM-CDP`
   reports PASS.
3. **Given** Chromium is not running, **When** the audit runs,
   **Then** `CHK-CHROMIUM-CDP` reports SKIP (not FAIL).
4. **Given** the fix script runs for `CHK-CHROMIUM-CDP`, **When**
   the check is in FAIL state, **Then** the fix script prints
   specific instructions showing the correct launch flags to use.

---

### User Story 2 - Dangerous Launch Flags Detected and Fixable (Priority: P1)

An operator runs the audit and the system detects whether Chromium
was launched with flags that weaken security (e.g.,
`--disable-web-security`, `--no-sandbox`, `--disable-extensions`).
If found, the fix script provides specific remediation.

**Why this priority**: Dangerous flags disable browser security
controls that protect against malicious web content. An AI agent
processing untrusted LinkedIn pages with `--disable-web-security`
is running without any cross-origin protection.

**Independent Test**: Launch Chromium with `--no-sandbox`, run the
audit, verify WARN with the specific dangerous flag named.

**Acceptance Scenarios**:

1. **Given** Chromium is running with `--no-sandbox`, **When** the
   audit runs, **Then** `CHK-CHROMIUM-DANGERFLAGS` reports WARN
   naming the specific flag.
2. **Given** Chromium is running with no dangerous flags, **When**
   the audit runs, **Then** `CHK-CHROMIUM-DANGERFLAGS` reports PASS.
3. **Given** the fix script runs for `CHK-CHROMIUM-DANGERFLAGS`,
   **When** the check is in WARN state, **Then** the fix script
   prints instructions listing which flags to remove and why.

---

### User Story 3 - Chromium Version Freshness Checked (Priority: P2)

The audit checks whether the installed Chromium version is current
and warns if it is more than 14 days behind the latest stable
release. The fix script can trigger an update.

**Why this priority**: Stale browser versions have known CVEs that
are actively exploited. A browser processing untrusted web content
must be current.

**Independent Test**: Check the installed Chromium version against
the expected freshness threshold.

**Acceptance Scenarios**:

1. **Given** Chromium was updated within 14 days, **When** the audit
   runs, **Then** `CHK-CHROMIUM-VERSION` reports PASS.
2. **Given** Chromium was last updated more than 14 days ago, **When**
   the audit runs, **Then** `CHK-CHROMIUM-VERSION` reports WARN with
   remediation to update.
3. **Given** the fix script runs for `CHK-CHROMIUM-VERSION`, **When**
   the check is in WARN state, **Then** the fix script executes the
   update command.

---

### User Story 4 - Browser Data Cleanup Available (Priority: P2)

An operator can run a cleanup command that removes browser session
data (cookies, local storage, cache, history) from the Chromium
profile directory. This prevents stale session tokens from persisting
between automation runs.

**Why this priority**: After an automation session, the browser
profile contains LinkedIn session cookies, browsing history, cached
page content, and local storage data. If the machine is compromised,
this data is immediately extractable. Regular cleanup limits the
window of exposure.

**Independent Test**: Run the cleanup, verify the profile directory
no longer contains cookies, history, or cache data.

**Acceptance Scenarios**:

1. **Given** a Chromium profile directory exists with session data,
   **When** the cleanup runs, **Then** cookies, local storage,
   history, and cache files are removed.
2. **Given** Chromium is currently running, **When** the cleanup
   is attempted, **Then** it refuses to run and warns the operator
   to close the browser first.
3. **Given** no Chromium profile directory exists, **When** the
   cleanup is attempted, **Then** it reports that no data was found.

---

### User Story 5 - GETTING-STARTED Guide Covers Chromium (Priority: P3)

A new operator following the GETTING-STARTED.md guide sees a section
explaining how to install Chromium and verify its security settings.
The guide covers installation, the audit, and the fix script in the
context of Chromium/CDP usage.

**Why this priority**: Without guide coverage, new operators must
discover Chromium hardening on their own or read the full HARDENING.md.
The getting-started guide should mention it as an optional step.

**Independent Test**: Read GETTING-STARTED.md and verify there is a
section that covers Chromium installation and audit verification.

**Acceptance Scenarios**:

1. **Given** GETTING-STARTED.md is open, **When** the reader reaches
   the "Next Steps" section, **Then** they see Chromium setup
   instructions with copy-pasteable commands.

---

### Edge Cases

- Chromium is installed via `.dmg` download instead of Homebrew. The
  audit and fix scripts should work regardless of installation method
  by detecting the browser binary rather than the Homebrew package.
- Both Google Chrome and Chromium are installed. The scripts should
  check whichever is present, preferring Chromium if both exist.
- CDP is running on a non-standard port (not 9222 or 18800). The
  audit should detect CDP on any port by checking the process
  arguments for `--remote-debugging-port`.
- The operator uses a custom profile directory (not the default).
  Cleanup should accept a path argument or detect the active profile.
- Chromium is running but CDP is not enabled (no `--remote-debugging-port`
  flag). The CDP check should report PASS (CDP not exposed).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The fix script MUST register `CHK-CHROMIUM-CDP` with
  an INSTRUCTED fix that shows the correct launch flags
  (`--remote-debugging-address=127.0.0.1`).
- **FR-002**: The fix script MUST register `CHK-CHROMIUM-DANGERFLAGS`
  with an INSTRUCTED fix that names each dangerous flag found and
  explains why it should be removed.
- **FR-003**: The fix script MUST register `CHK-CHROMIUM-VERSION`
  with a SAFE fix that runs the update command for the detected
  installation method.
- **FR-004**: A browser data cleanup function MUST be added that
  removes cookies, local storage, history, and cache from the
  Chromium profile directory.
- **FR-005**: The cleanup function MUST refuse to run if Chromium
  is currently running and report a clear warning.
- **FR-006**: The audit check `CHK-CHROMIUM-CDP` MUST detect CDP
  port binding by inspecting the running process arguments, not by
  assuming a fixed port number.
- **FR-007**: GETTING-STARTED.md MUST include Chromium installation
  and verification steps in the "Next Steps" section.
- **FR-008**: The pre-fix snapshot mechanism MUST record restore
  commands for any new auto-fixes added in this feature.
- **FR-009**: All new fix functions MUST use `run_as_user` for
  user-scoped operations to prevent the sudo privilege pollution
  bug fixed in PR #35.
- **FR-010**: The dangerous flags check MUST detect at minimum:
  `--disable-web-security`, `--no-sandbox`,
  `--disable-site-isolation-trials`, `--disable-features=IsolateOrigins`,
  and `--allow-running-insecure-content`.
- **FR-011**: The cleanup MUST be a standalone script
  (`scripts/browser-cleanup.sh`) that can be called independently
  after each automation session. The fix script MUST source it
  when needed, so there is a single implementation with two
  entry points.

### Key Entities

- **CDP Port**: A TCP port opened by Chromium for remote debugging,
  identified by the `--remote-debugging-port` process argument.
- **Dangerous Flag**: A Chromium launch flag that weakens security
  controls, detectable by inspecting process arguments.
- **Browser Profile**: A directory containing Chromium session data
  including cookies, history, cache, and local storage.
- **Installation Method**: How Chromium was installed (Homebrew cask,
  .dmg download, or Google Chrome), which determines the update
  command.

### Rabbit Holes (Identified, Deferred)

- **RH-001: Automated CDP session monitoring** — Continuous
  monitoring of CDP connections (who connected, what commands were
  sent) would provide detection for CDP-based attacks. This requires
  intercepting or logging CDP websocket traffic, which is complex.
  *Defer to a detection-focused feature.*
- **RH-002: Chromium sandboxing beyond macOS defaults** — Running
  Chromium in a container or macOS sandbox profile would provide
  stronger isolation. This requires custom sandbox profiles and
  testing with CDP. *Defer unless required.*
- **RH-003: Automated session rotation** — Automatically cleaning
  browser data between automation runs on a schedule. This requires
  coordination with the automation framework (OpenClaw) to know when
  a session ends. *Defer until OpenClaw integration is defined.*

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All 8 Chromium CHK-* checks have either an auto-fix
  or an instructed fix registered in the fix script (currently 5/8,
  target 8/8).
- **SC-002**: Running the fix script with `--auto` on a system with
  Chromium installed resolves or instructs on all Chromium WARN/FAIL
  findings.
- **SC-003**: The GETTING-STARTED.md guide includes Chromium setup
  as a documented optional step.
- **SC-004**: Browser data cleanup removes all session artifacts
  (cookies, history, cache, local storage) from the profile directory
  in a single command.
- **SC-005**: An operator can verify CDP port binding safety in
  under 10 seconds by running the audit.

## Assumptions

- Chromium is installed via Homebrew cask (`brew install --cask
  chromium`) as recommended in §2.11.1 of HARDENING.md. The fix
  script uses `brew upgrade --cask chromium` for version updates.
  Other installation methods are detected but may not support
  automated updates.
- The default Chromium profile directory is
  `~/Library/Application Support/Chromium/Default/`. Google Chrome
  uses `~/Library/Application Support/Google/Chrome/Default/`.
- CDP port binding is detectable by inspecting `/proc`-equivalent
  output on macOS (`lsof` or `ps` with process arguments).
- The fix for `CHK-CHROMIUM-CDP` is INSTRUCTED (not automated)
  because the CDP launch configuration is controlled by the calling
  process (OpenClaw), not by the fix script. The fix script cannot
  modify how another tool launches Chromium.
- The fix for `CHK-CHROMIUM-DANGERFLAGS` is INSTRUCTED (not
  automated) for the same reason — flags are set by the launching
  process.

## Clarifications

### Session 2026-03-16

- Q: Should browser data cleanup be a standalone script or a function within hardening-fix.sh? → A: Both — standalone script `scripts/browser-cleanup.sh` that the fix script sources when needed (single implementation, two entry points).

## Out of Scope

- Modifying how OpenClaw or other automation frameworks launch
  Chromium (we detect and report, not enforce).
- Firefox or Safari support (CDP is Chromium-only).
- CDP authentication mechanisms (none exist in the protocol).
- Browser extension management beyond the existing managed policy
  blocklist (already implemented in `CHK-CHROMIUM-EXTENSIONS`).
