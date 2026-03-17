# Implementation Plan: Multi-Browser Support

**Branch**: `006-multi-browser-support` | **Date**: 2026-03-16 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/006-multi-browser-support/spec.md`

## Summary

Refactor all Chromium-specific hardening logic (8 audit checks, 5 fix
functions, browser cleanup) into a browser registry pattern that supports
Chromium, Google Chrome, and Microsoft Edge. The registry encodes
per-browser metadata (app path, plist domain, TCC bundle ID, cask name,
profile directory, process name) so that adding a new Chromium-based
browser requires one registry entry and zero new functions. Check IDs
rename from `CHK-CHROMIUM-*` to `CHK-BROWSER-*`.

## Technical Context

**Language/Version**: Bash 5.x (POSIX-compatible subset per constitution)
**Primary Dependencies**: `defaults`, `lsof`, `pgrep`, `sqlite3`,
`tccutil`, `brew`, `shellcheck`
**Storage**: Filesystem (managed preference plists, TCC.db reads, profile
directories)
**Testing**: Manual test-operator walkthrough + shellcheck static analysis
**Target Platform**: macOS Sonoma/Tahoe on Apple Silicon and Intel Mac Mini
**Project Type**: CLI audit/fix scripts + documentation
**Performance Goals**: N/A (single-run audit/fix scripts)
**Constraints**: Must pass shellcheck with zero warnings; idempotent and
safe to re-run; no interactive input
**Scale/Scope**: 3 browsers × 8 checks = 24 check iterations max; ~1,200
lines of Chromium-specific code to refactor

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Documentation-Is-the-Product | PASS | HARDENING.md, GETTING-STARTED guides updated alongside scripts |
| II. Threat-Model Driven | PASS | Browser hardening targets credential theft, CDP exploitation, TCC abuse — all named threats |
| III. Free-First | PASS | All three browsers are free; no paid tools introduced |
| IV. Cite Canonical Sources | PASS | Existing citations (CIS, Apple Platform Security) apply to all Chromium-based browsers |
| V. Every Recommendation Is Verifiable | PASS | Audit checks remain the verification mechanism, now parameterized per browser |
| VI. Bash Scripts Are Infrastructure | PASS | `set -euo pipefail`, shellcheck, idempotent, no interactive input |
| VII. Defense in Depth | PASS | All three layers (prevent/detect/respond) maintained per browser |
| VIII. Explicit Over Clever | PASS | Registry is a simple array, not a framework; output names the browser explicitly |
| IX. Markdown Quality Gate | PASS | No new markdown patterns; existing lint config applies |
| X. CLI-First | PASS | All changes are CLI scripts and markdown |

**Gate result**: PASS — no violations.

## Project Structure

### Documentation (this feature)

```text
specs/006-multi-browser-support/
├── plan.md              # This file
├── research.md          # Phase 0: registry design decisions
├── data-model.md        # Phase 1: browser registry entity model
├── quickstart.md        # Phase 1: implementation quickstart
├── contracts/           # Phase 1: CLI interface contracts
│   └── audit-output.md  # JSON output schema with new check IDs
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
scripts/
├── browser-registry.sh  # NEW: shared browser registry sourced by all scripts
├── hardening-audit.sh   # MODIFY: source registry, refactor 8 checks, rename IDs
├── hardening-fix.sh     # MODIFY: source registry, refactor 5 fix functions
├── browser-cleanup.sh   # MODIFY: source registry, --all flag, multi-browser detection
└── CHK-REGISTRY.md      # MODIFY: rename 8 check IDs

docs/
└── HARDENING.md         # MODIFY: section 2.11 title, coverage badges, check references

GETTING-STARTED.md       # MODIFY: add Edge as supported alternative
GETTING-STARTED-INTEL.md # MODIFY: add Edge as supported alternative
```

**Structure Decision**: One new file: `scripts/browser-registry.sh`.
The registry is defined once and sourced by all three scripts. Per the
Rule-of-Three principle — 3 browsers (Chromium, Chrome, Edge) = 3
concrete use-cases — extraction to a shared file is warranted. Adding
a new browser means editing one file instead of three.

## Complexity Tracking

> No constitution violations — this section is empty.

## Design Decisions

### D1: Registry encoding — Bash associative arrays

**Decision**: Use `declare -A` associative arrays keyed by browser
short name (`chromium`, `chrome`, `edge`) with one array per metadata
field.

**Rationale**: Colon-delimited strings break on paths with spaces
(Edge's profile dir: `Microsoft Edge/Default/`). Associative arrays
are native to Bash 4+ (Bash 5.x is our floor), readable, and don't
require delimiter escaping. One array per field (`BROWSER_APP_PATH`,
`BROWSER_PLIST_DOMAIN`, etc.) is cleaner than one mega-array with
index arithmetic.

**Alternatives rejected**:
- Single colon-delimited array: breaks on spaces in paths
- JSON + jq: adds jq dependency to scripts that currently don't need it
- External config file: adds a file to keep in sync, no benefit for 3 entries
- Single associative array with compound keys: harder to iterate browsers

### D2: Registry placement — shared file sourced by all scripts

**Decision**: Define the registry in `scripts/browser-registry.sh`,
sourced by audit, fix, and cleanup scripts.

**Rationale**: 3 browsers (Chromium, Chrome, Edge) = 3 concrete
use-cases, meeting the Rule-of-Three threshold for extraction. A
single source file keeps metadata in one place — adding a browser
means editing one file instead of three. The file is ~40 lines, not
a framework.

**Alternatives rejected**:
- Inline duplication in each script: considered initially when we
  thought there were only 2 browsers. With 3 browsers meeting the
  Rule-of-Three, shared file is the right call

### D3: Check ID migration — rename in place, no aliases

**Decision**: Rename all 8 check IDs from `CHK-CHROMIUM-*` to
`CHK-BROWSER-*` in audit, fix, registry, and documentation. No
backward-compatibility aliases.

**Rationale**: The spec explicitly requires renaming (FR-006). The
carryover confirms this decision was made in the previous session.
Aliases add complexity for an internal tool with no external consumers
of the check IDs.

### D4: Multi-browser iteration — loop in each check function

**Decision**: Each check function receives a browser short name as
argument and checks that single browser. A wrapper loop calls each
check for every installed browser.

**Rationale**: This keeps check functions single-responsibility (check
one browser) and the loop logic centralized. It also produces
per-browser output lines (`CHK-BROWSER-POLICY [Chromium]: PASS`,
`CHK-BROWSER-POLICY [Edge]: FAIL`) which is more useful than a single
aggregated result.

### D5: browser-cleanup.sh --all flag

**Decision**: Without `--all`, cleanup targets the preferred browser
(Chromium > Chrome > Edge). With `--all`, it iterates all installed
browsers.

**Rationale**: Matches FR-007 exactly. The preference order preserves
backward compatibility (Chromium was always the only option before).
