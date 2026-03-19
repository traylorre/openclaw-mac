# Feature Specification: NoMOOP (No Matter Out Of Place)

**Feature Branch**: `009-nomoop`
**Created**: 2026-03-18
**Status**: Draft
**Input**: Installation manifest with clean install/uninstall, self-healing state tracking, and leave-no-trace methodology. Every artifact placed on the system is tracked, reversible, and verifiable.

## Clarifications

### Session 2026-03-18

- Q: Should manifest tracking cover only install scripts (bootstrap.sh + gateway-setup.sh) or also hardening-fix.sh which creates system accounts, SSH configs, Chromium policies, and firewall rules? → A: Track all artifacts from all scripts — leave no stone unturned. All three scripts (bootstrap.sh, gateway-setup.sh, hardening-fix.sh) must record to the manifest.
- Q: Should the manifest format remain JSON+jq, or switch to YAML or another format? → A: JSON+jq is the right choice (jq already a dependency). Format flexibility noted — any format is acceptable if it makes scripting easier, but JSON+jq is optimal for this use case.
- Q: Sudo strategy during uninstall — single upfront prompt, per-step prompts, or run entire script as root? → A: Hybrid — default is `sudo -v` upfront (single prompt, cached credentials). Power users can pass `--confirm` flag to see each sudo command and approve individually. Script always runs as user (never `sudo openclaw uninstall`) to avoid $HOME/$USER resolution issues.
- Q: Manifest file permissions? → A: `600` on manifest.json, `700` on `~/.openclaw/` directory. Self-evident — no use case for wider access, single-operator machine, secrets live in Keychain not manifest.
- Q: Should security-hardening artifacts be auto-removed during uninstall? → A: Option C + mirror. Uninstall auto-removes all by default with per-item warnings, but supports `--keep-hardening` to preserve security posture. Mirror operation: install supports `--hardening-only` to apply only hardening artifacts without the full stack. Artifacts gain a `category` field ("hardening" vs "tooling") to enable this filtering.
- Q: Should the manifest track which script created each artifact? → A: Yes. Each entry includes an `installed_by` field with the script filename. Enables filtering (e.g., `openclaw manifest --source hardening-fix.sh`) and debugging provenance.
- Q: How should manifest writes survive interrupts (Ctrl+C, SIGHUP, terminal close)? → A: All jq writes MUST use atomic write pattern (write to .tmp, then mv). Scripts MUST set trap handlers for INT, HUP, TERM signals. This prevents manifest corruption on any interrupt type.
- Q: Should the manifest track artifact versions? → A: Yes. Each entry includes a `version` field (package version for brew, image tag for Docker, "N/A" for files/dirs). Enables `--verify` to detect VERSION_DRIFT and future `openclaw update` command.
- Q: Should install scripts handle sudo credential expiry? → A: Yes. Both install and uninstall scripts MUST run a background `sudo -v` refresh loop to prevent credential timeout during long operations (brew downloads, Docker image pulls).

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Fresh Install With Manifest Tracking (Priority: P1)

An operator clones the repo on a fresh Mac and runs the install
script. Every file placed outside the repo, every Homebrew package
installed, every shell config line appended, and every system
directory created is recorded in a manifest file. After installation
completes, the operator can view the manifest to see exactly what
was placed where.

**Why this priority**: Without tracking what was installed, there
is no path to clean uninstall. The manifest is the foundation for
everything else.

**Independent Test**: Run the install on a fresh system, inspect
the manifest, verify every entry corresponds to a real file on disk.

**Acceptance Scenarios**:

1. **Given** a fresh Mac with no openclaw artifacts, **When** the
   operator runs the install, **Then** a manifest file is created
   at `~/.openclaw/manifest.json` listing every artifact with path,
   type, timestamp, and checksum where applicable.
2. **Given** the install completes, **When** the operator runs
   `openclaw manifest --verify`, **Then** each entry is checked
   against disk and reported as PRESENT or MISSING.
3. **Given** an operator has already installed, **When** they run
   the install again, **Then** the manifest is updated (not
   duplicated) and new artifacts are appended while existing ones
   are verified.

---

### User Story 2 — Clean Uninstall (Priority: P1)

The operator runs an uninstall command that reads the manifest and
removes every tracked artifact, restoring the system to its
pre-install state. After uninstall, the only remaining file is a
post-uninstall checklist documenting what was removed and flagging
anything that could not be removed automatically.

**Why this priority**: An install that can't be cleanly reversed is
a liability. Operators who evaluate the toolkit need confidence that
it won't leave permanent residue on their production systems.

**Independent Test**: Install, then uninstall, then verify no
openclaw artifacts remain except the post-uninstall checklist.

**Acceptance Scenarios**:

1. **Given** a fully installed system, **When** the operator runs
   `openclaw uninstall`, **Then** every manifest-tracked artifact
   is removed and the manifest is updated to reflect removal.
2. **Given** the uninstall completes, **When** the operator
   inspects the system, **Then** the only remaining artifact is
   `~/.openclaw/uninstall-report.txt` listing what was removed and
   any items requiring manual cleanup.
3. **Given** a Homebrew package was installed by openclaw but is
   also used by other software, **When** the uninstall runs,
   **Then** it marks the package as "SHARED: not removed" in the
   report and does NOT uninstall it.
4. **Given** the operator has modified a file that openclaw
   installed, **When** the uninstall runs, **Then** it warns
   about the modification and backs up the file before removing.

---

### User Story 3 — Interrupted Install/Uninstall Recovery (Priority: P2)

The install or uninstall is interrupted (Ctrl+C, power loss, SSH
disconnect). When the operator re-runs the same command, it detects
the incomplete state and resumes from where it left off rather than
starting over or leaving the system in a broken half-state.

**Why this priority**: Real-world installs get interrupted. A
self-healing system that can resume is the difference between
"professional tool" and "scary script."

**Independent Test**: Start an install, interrupt it midway, re-run,
verify it completes without errors or duplicated work.

**Acceptance Scenarios**:

1. **Given** an install was interrupted, **When** the operator
   re-runs the install, **Then** already-completed steps are
   verified (not re-executed) and remaining steps proceed normally.
2. **Given** an uninstall was interrupted, **When** the operator
   re-runs the uninstall, **Then** already-removed items are
   skipped and remaining items are removed.
3. **Given** the manifest is corrupted or missing, **When** the
   operator runs `openclaw manifest --rebuild`, **Then** the system
   is scanned for known openclaw artifacts and the manifest is
   reconstructed.

---

### User Story 4 — Shell Config Isolation (Priority: P2)

Instead of appending lines to `~/.bash_profile` or `~/.bashrc`
directly, the install creates a single `~/.openclaw/shellrc` file
containing all openclaw shell configurations. A single `source`
line is added to the operator's shell config. Uninstall removes
that one line. This prevents openclaw modifications from
interleaving with the operator's own shell customizations.

**Why this priority**: Editing shell configs is the most common
source of "dirty uninstall" problems. Isolating openclaw's shell
additions to a single sourceable file makes install/uninstall
deterministic.

**Independent Test**: Install, verify only one line was added to
shell config. Uninstall, verify that line was removed and
`~/.openclaw/shellrc` was deleted.

**Acceptance Scenarios**:

1. **Given** the operator's `~/.bash_profile` exists, **When**
   openclaw installs, **Then** exactly one line is appended:
   `[ -f ~/.openclaw/shellrc ] && source ~/.openclaw/shellrc`
2. **Given** the source line already exists, **When** the install
   runs again, **Then** it is not duplicated.
3. **Given** openclaw is uninstalled, **When** the operator opens
   a new shell, **Then** no openclaw aliases, functions, or
   environment variables are set.

---

### User Story 5 — Manifest Inspection and Drift Detection (Priority: P3)

The operator can inspect the manifest to see what's installed, check
for drift (files modified or deleted since install), and generate a
report suitable for audit or compliance review.

**Why this priority**: Visibility into installed state supports both
operator confidence and the trust audit milestone (M2).

**Independent Test**: Install, modify one tracked file, run
manifest verify, see the drift reported.

**Acceptance Scenarios**:

1. **Given** a fully installed system, **When** the operator runs
   `openclaw manifest`, **Then** a human-readable table is printed
   showing each artifact, its type, location, and status.
2. **Given** a tracked file has been modified since install, **When**
   the operator runs `openclaw manifest --verify`, **Then** the
   modified file is flagged as DRIFTED with the original and
   current checksums.
3. **Given** a tracked file has been deleted, **When** the operator
   runs `openclaw manifest --verify`, **Then** it is flagged as
   MISSING.

---

### Edge Cases

- Operator installs on a system that already has Colima, Docker,
  jq, bash 5.x from a prior manual install. The manifest records
  these as "PRE-EXISTING" and does not mark them for removal during
  uninstall.
- Operator has a non-standard shell config path (e.g., `~/.zshenv`
  instead of `~/.zshrc`). The installer detects the active shell
  and appends to the correct file.
- `/opt/n8n/` was created by bootstrap with sudo. Uninstall uses
  `sudo -v` upfront (single password prompt with explanation of
  which steps need elevation). Power users can pass `--confirm`
  to approve each sudo command individually. The script must
  never be run as `sudo openclaw uninstall` — it always runs as
  the operator's user to ensure correct $HOME and $USER resolution.
- Operator runs uninstall but Docker containers are still running.
  Uninstall should stop containers and Colima before removing
  artifacts.
- Multiple versions of openclaw are installed in different
  directories. The manifest is per-install-directory, not global.
- The `~/.openclaw/` directory itself is deleted by the operator
  manually. The install script should be able to reconstruct the
  manifest from known artifact locations (best-effort rebuild).
- Operator's `$SHELL` is ksh, fish, or another non-bash/zsh shell.
  The installer MUST validate that `$SHELL` is bash or zsh. If not,
  warn the operator and prompt for which rc file to modify (or
  default to `~/.zshrc` since zsh is macOS default since Catalina).
- Network operations hang indefinitely (`brew install`, `colima
  start`, `docker compose up`). Scripts SHOULD use `timeout`
  wrappers for network-dependent operations and report a clear
  error if a timeout is exceeded rather than hanging silently.
- Disk is nearly full (<5GB free). Bootstrap SHOULD check available
  disk space before starting and warn if below 8GB (Colima VM +
  Docker images + packages can consume 5-10GB).
- Two terminals run bootstrap.sh simultaneously. Manifest writes
  SHOULD use `flock` to prevent concurrent corruption:
  `flock -n /tmp/openclaw-manifest.lock` at script start, exit
  with clear error if lock is held by another process.
- Operator runs `brew upgrade` which upgrades openclaw dependencies
  to untested versions. `openclaw manifest --verify` SHOULD detect
  VERSION_DRIFT for brew packages and report the old vs new version.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: An installation manifest MUST be maintained at
  `~/.openclaw/manifest.json` recording every artifact placed on
  the system outside the repo directory by any openclaw script
  (bootstrap.sh, gateway-setup.sh, hardening-fix.sh).
- **FR-002**: Each manifest entry MUST include: artifact path, type
  (see Artifact Type Taxonomy for complete list of 16 types),
  category (`tooling` or `hardening`), version (package version,
  image tag, or "N/A"), installed timestamp, checksum (for files),
  and a removable flag (true/false).
- **FR-003**: Artifacts that pre-existed before install MUST be
  marked as `"pre_existing": true` and MUST NOT be removed during
  uninstall.
- **FR-004**: The install process MUST be idempotent. Running it
  twice MUST produce the same system state and manifest.
- **FR-005**: An uninstall command MUST read the manifest and
  remove all artifacts where `removable` is true, in reverse
  installation order.
- **FR-006**: Uninstall MUST stop running Docker containers and
  Colima before removing Docker volumes and Colima data.
- **FR-007**: Uninstall MUST NOT remove Homebrew packages that
  are dependencies of other installed software. It MUST check
  `brew uses --installed <package>` before removing.
- **FR-008**: Shell config modifications MUST be isolated to a
  single `~/.openclaw/shellrc` file sourced by one line in the
  operator's shell config.
- **FR-009**: The source line added to shell config MUST be
  guarded: `[ -f ~/.openclaw/shellrc ] && source ~/.openclaw/shellrc`
  so that removing the file silently disables all openclaw shell
  additions.
- **FR-010**: Uninstall MUST remove the source line from shell
  config files and delete `~/.openclaw/shellrc`.
- **FR-011**: A manifest verify command MUST check each tracked
  artifact against disk and report PRESENT, MISSING, or DRIFTED.
- **FR-012**: A manifest rebuild command MUST scan known artifact
  locations and reconstruct the manifest when it is missing or
  corrupted.
- **FR-013**: Interrupted install/uninstall MUST be resumable.
  Each step MUST check current state before acting (idempotent
  per-step).
- **FR-014**: After uninstall, a human-readable report MUST be
  left at `~/.openclaw/uninstall-report.txt` documenting what
  was removed and what requires manual cleanup.
- **FR-015**: Modified files MUST be backed up before removal
  during uninstall. Backups stored in `~/.openclaw/backups/`.
- **FR-016**: Uninstall MUST use `sudo -v` at the start to cache
  credentials, with a clear explanation of which steps require
  elevation. The script MUST NOT be designed to run as root.
- **FR-017**: Uninstall MUST support a `--confirm` flag that
  displays each sudo command and waits for operator approval
  before executing, enabling per-step inspection for power users.
- **FR-018**: Uninstall MUST support a `--keep-hardening` flag
  that skips removal of artifacts with `category: "hardening"`.
  Skipped artifacts MUST be listed in the uninstall report as
  "KEPT: hardening artifact preserved."
- **FR-019**: When auto-removing hardening artifacts, uninstall
  MUST display a per-item warning describing the security
  implication (e.g., "Removing SSH hardening — this re-enables
  password authentication").
- **FR-020**: Install MUST support a `--hardening-only` flag
  (via `openclaw install --hardening-only` or
  `hardening-fix.sh --manifest`) that applies only hardening
  artifacts and records them to the manifest, without requiring
  the full bootstrap/gateway stack.
- **FR-021**: All manifest JSON writes MUST use atomic write
  pattern: write to a temporary file, then `mv` to the final
  path. This prevents manifest corruption if the script is
  interrupted during a write (Ctrl+C, SIGHUP, terminal close,
  power loss). `mv` on the same filesystem is atomic on APFS.
- **FR-022**: All scripts that modify the manifest MUST set
  signal trap handlers for INT, HUP, and TERM that print a
  resume message and exit cleanly: `trap 'echo "Interrupted.
  Re-run to resume." >&2; exit 130' INT HUP TERM`.
- **FR-023**: Each manifest entry MUST include a `version` field
  recording the installed version: brew packages use `brew info
  --json <pkg> | jq -r '.[0].installed[0].version'`, Docker
  images use the image tag, files/directories use "N/A". The
  `--verify` command MUST report VERSION_DRIFT when the current
  version differs from the recorded version.
- **FR-024**: Both install and uninstall scripts MUST maintain
  a background `sudo -v` refresh loop (every 4 minutes) to
  prevent credential timeout during long operations. The loop
  MUST be killed on script exit via trap handler.

### Key Entities

- **Manifest**: JSON file at `~/.openclaw/manifest.json`. The
  single source of truth for installed state. Contains an ordered
  array of artifact entries.
- **Artifact Entry**: A single installed item with path, type,
  category (tooling/hardening), version, installed_by (source
  script), checksum, timestamp, pre_existing flag, and removable
  flag.
- **Shell RC**: The `~/.openclaw/shellrc` file containing all
  openclaw shell additions (aliases, exports, functions).
- **Uninstall Report**: Plain-text file left after uninstall
  listing every action taken and any items requiring manual cleanup.

### Artifact Type Taxonomy

Every artifact placed on the system falls into one of these types:

| Type | Example | Category | Removable? | Notes |
|------|---------|----------|-----------|-------|
| `brew-package` | colima, docker, jq | tooling | Conditional | Only if no other dependents |
| `directory` | /opt/n8n, ~/.openclaw | tooling | Yes | Recursive removal |
| `file` | /opt/n8n/scripts/hardening-audit.sh | tooling | Yes | Checksum tracked |
| `shell-config-line` | source line in ~/.bash_profile | tooling | Yes | Single line, grep-removable |
| `shell-rc-file` | ~/.openclaw/shellrc | tooling | Yes | Contains aliases, exports |
| `keychain-entry` | n8n-gateway-bearer | tooling | Yes | `security delete-generic-password` |
| `launchd-plist` | com.openclaw.audit-cron.plist | tooling | Yes | Must unload before removing |
| `docker-volume` | templates_n8n_data | tooling | Yes | Must stop containers first |
| `docker-container` | templates-n8n-1 | tooling | Yes | Must stop before removing |
| `docker-image` | n8nio/n8n:2.13.0 | tooling | Conditional | May be shared |
| `colima-vm` | default profile | tooling | Conditional | `colima delete` |
| `system-account` | _n8n service account | hardening | Yes | `sysadminctl -deleteUser`; warn: orphans data |
| `system-config-file` | /etc/ssh/sshd_config.d/hardening.conf | hardening | Yes | Warn: re-enables password auth |
| `system-config-line` | /etc/shells bash line, /etc/pf.conf anchor | hardening | Yes | Warn: weakens firewall |
| `managed-preference` | /Library/Managed Preferences/org.chromium.Chromium.plist | hardening | Yes | Warn: loosens browser policy |
| `spotlight-exclusion` | mdutil -i off /opt/n8n | hardening | Yes | Reverse: `mdutil -i on` |

### Rabbit Holes (Identified, Deferred)

- **RH-001: Homebrew Tap distribution** — Packaging openclaw as a
  Homebrew formula enables `brew install/uninstall` natively. This
  requires 75+ stars for Homebrew Core, but a personal tap can be
  created immediately. *Defer until post-M2.*
- **RH-002: macOS .pkg installer** — Building a .pkg with Apple's
  receipt system provides native install tracking. *Overkill for
  current stage. Defer.*
- **RH-003: Nix/nix-darwin integration** — Declarative system
  management with atomic rollback. *Massively overkill. Defer.*

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An operator can install, uninstall, and verify zero
  residue in under 10 minutes.
- **SC-002**: The manifest correctly tracks 100% of artifacts
  placed outside the repo directory.
- **SC-003**: Interrupted install/uninstall resumes correctly
  without duplicate work or orphaned artifacts.
- **SC-004**: Uninstall on a system with pre-existing Homebrew
  packages does not remove those packages.
- **SC-005**: After uninstall, the only remaining artifact is the
  uninstall report and (optionally) the backup directory.

## Assumptions

- The operator has admin access (some removals require sudo).
- Homebrew is the package manager (per constitution).
- The operator's login shell is bash or zsh (the two shells
  supported by macOS). Other shells (ksh, fish) are not supported
  but detected and warned about.
- `jq` is available for manifest JSON manipulation (installed
  by bootstrap).
- At least 8GB of free disk space is available for the full
  install (Colima VM, Docker images, Homebrew packages).
- The repo clone directory is not tracked by the manifest (the
  operator manages their own git clones).

## Out of Scope

- Homebrew Tap / formula packaging (RH-001, future milestone).
- macOS .pkg installer (RH-002).
- Nix/nix-darwin (RH-003).
- Managing the repo clone itself (that's the operator's concern).
- Windows or Linux support.
- GUI uninstaller.
- Tracking artifacts created by n8n at runtime (execution logs,
  workflow state). Only artifacts placed by openclaw scripts are
  tracked.
