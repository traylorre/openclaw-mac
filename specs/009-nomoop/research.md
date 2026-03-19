# Research: 009-nomoop

**Date**: 2026-03-18 | **Spec**: `specs/009-nomoop/spec.md`

## R-001: Manifest Storage Format

**Decision**: JSON file at `~/.openclaw/manifest.json`, manipulated with `jq`.

**Rationale**: jq is already a bootstrap dependency (installed by
`scripts/bootstrap.sh`). JSON is machine-readable for verify/rebuild
commands and human-readable enough for inspection. A single file
(vs. a directory of entries) simplifies atomic writes and backups.

**Alternatives considered**:
- SQLite: More powerful queries, but overkill for <100 entries. Adds
  a dependency we don't need.
- Plain text (one line per artifact): Easy to append but hard to
  update individual entries. No structured types.
- YAML: Requires a parser (yq) not in bootstrap. No advantage over
  JSON given jq is already available.

## R-002: Checksum Algorithm

**Decision**: SHA-256 via `shasum -a 256` (ships with macOS).

**Rationale**: shasum is a macOS built-in (no dependency). SHA-256
is fast enough for our artifact count (<100 files) and collision-
resistant. Using it for drift detection, not cryptographic
verification, so SHA-256 is more than sufficient.

**Alternatives considered**:
- MD5: Weaker, no practical advantage over SHA-256.
- CRC32: Too weak even for drift detection.
- `openssl dgst`: Also built-in, but shasum has simpler output format.

## R-003: Pre-existing Package Detection

**Decision**: Before each `brew install`, check `command -v <tool>`
or `brew list <package>` and record the result. If the tool exists
before we install, mark `"pre_existing": true`.

**Rationale**: bootstrap.sh already checks `command -v` before
installing. We just need to record the result in the manifest before
the install step runs.

**Alternatives considered**:
- Snapshot all installed packages before/after: Overly broad, catches
  unrelated concurrent installs.
- Homebrew receipt timestamps: Fragile and version-dependent.

## R-004: Shell Config File Detection

**Decision**: Detect operator's login shell from `$SHELL` (or
`dscl . -read /Users/$USER UserShell`), then target the appropriate
rc file:
- bash → `~/.bash_profile` (macOS sources this for login shells)
- zsh → `~/.zshrc` (macOS default since Catalina)

**Rationale**: macOS supports two shells (bash, zsh). The spec
requires handling both. `$SHELL` is the canonical way to detect
the login shell. We target the file that the login shell actually
sources on macOS (bash_profile for bash, zshrc for zsh).

**Alternatives considered**:
- Always use `.bashrc`: Wrong for macOS — bash login shells source
  `.bash_profile`, not `.bashrc`.
- Modify all rc files: Overkill and creates more cleanup.
- Use `/etc/profile.d/`: Requires sudo, affects all users.

## R-005: Idempotent Install/Uninstall Strategy

**Decision**: Each install step checks current state before acting.
The manifest records per-step status: `"status": "installed"`,
`"status": "pending"`, `"status": "removed"`. On re-run, steps
with `"installed"` status are verified (not re-executed), steps
with `"pending"` are retried.

**Rationale**: bootstrap.sh and gateway-setup.sh already follow
this pattern (check → skip or install). NoMOOP formalizes it by
recording the state. This also enables interrupt recovery — a
Ctrl+C leaves some steps as "pending", and re-run picks up where
it left off.

**Alternatives considered**:
- Transaction log (write-ahead log): Overkill for sequential scripts.
- Lock file with step counter: Fragile if steps change between versions.

## R-006: Reverse-Order Uninstall

**Decision**: Uninstall processes manifest entries in reverse order.
Docker containers stop before volumes are removed. Colima stops
before its VM is deleted. Shell config lines are removed before
shellrc is deleted.

**Rationale**: The manifest array is ordered by installation time.
Reversing it naturally handles dependencies — things installed
later (containers, workflows) depend on things installed earlier
(Docker, Colima). This mirrors how package managers handle
removal order.

**Alternatives considered**:
- Dependency graph: More correct in theory, but for 16 artifact
  types with a linear install order, reverse chronological is
  equivalent and far simpler.
- Parallel removal: Risky — container removal depends on Colima
  running.

## R-007: Backup Strategy for Modified Files

**Decision**: Before removing a file flagged as DRIFTED during
uninstall, copy it to `~/.openclaw/backups/<timestamp>/<path>`.
The uninstall report lists each backup with its original path.

**Rationale**: The operator may have customized config files
(notify.conf, shellrc). Removing without backup could lose
their work. The backup directory is excluded from manifest
tracking (it's a safety net, not an artifact).

**Alternatives considered**:
- `.bak` files alongside originals: Litters the filesystem.
- Git stash: Only works inside the repo, not for system files.

## R-008: `openclaw` CLI Entry Point

**Decision**: A single `scripts/openclaw.sh` script that dispatches
subcommands: `openclaw manifest`, `openclaw manifest --verify`,
`openclaw manifest --rebuild`, `openclaw uninstall`. The shellrc
adds an alias: `alias openclaw='bash /path/to/scripts/openclaw.sh'`.

**Rationale**: The spec references `openclaw manifest` and
`openclaw uninstall` as operator-facing commands. A dispatcher
script is simpler than multiple standalone scripts and matches
the UX described in the spec.

**Alternatives considered**:
- Separate scripts (`manifest.sh`, `uninstall.sh`): More files,
  less unified UX.
- Makefile targets: Not discoverable for operators. Requires make.
- Bash completion: Nice-to-have, defer.

## R-009: Shared Homebrew Package Detection

**Decision**: Before removing a brew package during uninstall, run
`brew uses --installed <package>`. If output is non-empty, mark
as "SHARED: not removed" in the uninstall report.

**Rationale**: FR-007 requires this check. `brew uses --installed`
is the canonical Homebrew command for checking reverse dependencies.
It's fast and reliable.

**Alternatives considered**:
- Check if the binary is in any other script's PATH: Unreliable.
- Ask the operator: Interrupts automated uninstall.
