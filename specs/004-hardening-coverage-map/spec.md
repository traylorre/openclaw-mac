# Feature Specification: Hardening Guide Coverage Map

**Feature Branch**: `004-hardening-coverage-map`
**Created**: 2026-03-16
**Status**: Draft
**Input**: Add inline automation annotations to HARDENING.md, sync CHK-REGISTRY.md with implemented checks, surface coverage metrics, and identify gaps — enabling technical reviewers, operators, and stakeholders to see at-a-glance what is automated, what is manual, and where coverage can be improved.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Stakeholder Reviews Coverage at a Glance (Priority: P1)

A technical stakeholder opens `docs/HARDENING.md` and immediately sees
a coverage summary near the top showing what percentage of the guide
is backed by automated checks and auto-fixes. They can scan section
headings to see inline badges indicating which items are automated,
which are audit-only, and which are manual procedures.

**Why this priority**: This is the primary deliverable — making the
guide self-documenting about its own automation coverage. Without this,
a reviewer must cross-reference three files (guide, registry, scripts)
to understand what is and isn't automated.

**Independent Test**: Open HARDENING.md and verify that (a) a coverage
summary block exists near the top, (b) every subsection heading from
§2 through §10 has an inline annotation, and (c) the counts in the
summary match the actual annotations.

**Acceptance Scenarios**:

1. **Given** HARDENING.md is opened, **When** the reader scrolls past
   the Table of Contents, **Then** they see a coverage summary block
   immediately — before the preamble — showing total sections,
   automated count, auto-fix count, manual count, and a percentage.
2. **Given** any subsection from §2.1 through §10.6, **When** the
   reader views the heading, **Then** it includes one of these inline
   badges: `[AUTO-FIX]`, `[AUDIT-ONLY]`, or `[MANUAL]`.
3. **Given** the coverage summary, **When** a new check is added to
   the audit script, **Then** updating the summary requires changing
   only the counts and the affected section badge (no structural
   changes).

---

### User Story 2 - Maintainer Syncs CHK-REGISTRY (Priority: P1)

A maintainer opens `scripts/CHK-REGISTRY.md` and finds every `CHK-*`
identifier that exists in the audit script listed in the registry with
correct metadata. No implemented checks are missing from the registry.

**Why this priority**: Equal priority with US-1 because an incomplete
registry undermines trust with technical reviewers. Ten checks exist
in the audit script today but are absent from the registry.

**Independent Test**: Extract all `CHK-*` identifiers from
`hardening-audit.sh` and compare against `CHK-REGISTRY.md`. The sets
must match exactly.

**Acceptance Scenarios**:

1. **Given** the audit script defines a check function with a
   `CHK-*` identifier, **When** the registry is checked, **Then**
   that identifier appears in the registry table with severity,
   deployment scope, guide section reference, and auto-fix status.
2. **Given** the registry is updated, **When** a reviewer counts
   rows, **Then** the count matches the number of distinct `CHK-*`
   identifiers in `hardening-audit.sh`.

---

### User Story 3 - Operator Understands Badge Meaning (Priority: P2)

An operator sees a badge on a section heading and understands
immediately whether the item is handled by the scripts or requires
manual action. A legend in the notation conventions table explains
all badge types.

**Why this priority**: Without clear badge definitions, annotations
create more confusion than clarity.

**Independent Test**: Read the notation conventions table and verify
it includes all badge types with one-line definitions.

**Acceptance Scenarios**:

1. **Given** the notation conventions table in HARDENING.md, **When**
   a reader encounters a badge they do not understand, **Then** the
   table includes all badge types with clear definitions.
2. **Given** a `[MANUAL]` section, **When** the reader searches for
   a `CHK-*` identifier in that section, **Then** none is found
   (confirming it is truly manual).

---

### User Story 4 - Security Reviewer Finds Weakest Layers (Priority: P2)

A security-minded reviewer uses the coverage summary to identify
which defensive layers have the weakest automation coverage. They
can see per-section coverage (e.g., "§7 Data Security: 3/11
automated") and prioritize which gaps to close.

**Why this priority**: The coverage map is an operational tool for
prioritizing future hardening work, not just documentation.

**Independent Test**: Verify the coverage summary includes per-section
breakdowns that highlight low-coverage areas.

**Acceptance Scenarios**:

1. **Given** the coverage summary, **When** a reviewer looks at a
   specific guide section (e.g., §7), **Then** they see the count
   of automated vs. total subsections for that section.
2. **Given** the per-section breakdown, **When** a section has low
   coverage, **Then** it is identifiable without reading the full
   guide.

---

### User Story 5 - Guide Links Back to Scripts (Priority: P3)

Sections with `[AUTO-FIX]` or `[AUDIT-ONLY]` badges reference the
specific `CHK-*` identifier(s), so a technical reader can navigate
directly to the implementation.

**Why this priority**: Useful for maintainers and power users but
not required for the primary coverage-visibility goal.

**Independent Test**: For any `[AUTO-FIX]` section, verify the
`CHK-*` identifier referenced exists in both `hardening-audit.sh`
and `hardening-fix.sh`.

**Acceptance Scenarios**:

1. **Given** a section tagged `[AUTO-FIX]`, **When** the reader looks
   for the check ID, **Then** they find a `CHK-*` identifier that
   matches a function in both the audit and fix scripts.

---

### Edge Cases

- A guide section has multiple `CHK-*` checks with mixed coverage
  (e.g., one has auto-fix, another is audit-only). The badge
  reflects the lowest coverage level, and all check IDs are listed.
- A new section is added to the guide without a corresponding audit
  check. It defaults to `[MANUAL]`.
- The audit script adds a check for a section currently tagged
  `[MANUAL]`. The maintainer must update the badge manually.
  Documenting this in a maintenance note is sufficient.
- A section is educational-only (e.g., §1 Threat Model). It does
  not receive a badge because it contains no actionable hardening
  steps.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: HARDENING.md MUST include a coverage summary block
  immediately after the Table of Contents (before the Preamble)
  showing: total actionable sections, sections with automated
  checks, sections with auto-fix, manual-only sections, and an
  overall automation percentage.
- **FR-002**: The coverage summary MUST include per-section
  breakdowns for each major guide section (§2 through §10).
- **FR-003**: Every actionable subsection heading from §2.1 through
  §10.6 MUST have exactly one inline badge: `[AUTO-FIX]`,
  `[AUDIT-ONLY]`, or `[MANUAL]`.
- **FR-004**: Badge definitions MUST be added to the Notation
  Conventions table in HARDENING.md.
- **FR-005**: `scripts/CHK-REGISTRY.md` MUST include every `CHK-*`
  identifier that exists in `scripts/hardening-audit.sh`, with zero
  omissions.
- **FR-006**: Each registry entry MUST include: ID, severity,
  deployment scope, guide section reference, and auto-fix status
  (yes/no).
- **FR-007**: Sections tagged `[AUTO-FIX]` or `[AUDIT-ONLY]` MUST
  reference their `CHK-*` identifier(s) within the section body.
- **FR-008**: The coverage summary MUST be maintainable by editing
  counts directly — no build step or script is required to
  regenerate it.
- **FR-009**: The inline annotations MUST NOT alter the existing
  content, structure, or section numbering of HARDENING.md.
- **FR-010**: The coverage summary MUST include links to the scripts
  directory and to GETTING-STARTED.md for readers who want to run
  the tools.
- **FR-011**: §1 (Threat Model), §11 (Audit Script Reference), and
  Appendices MUST NOT receive badges — they are reference material,
  not actionable hardening steps.

### Key Entities

- **Guide Section**: A subsection of HARDENING.md (e.g., §2.1)
  containing a specific hardening topic.
- **CHK Identifier**: A unique string (e.g., `CHK-FIREWALL`) mapping
  an audit check to a guide section.
- **Fix Function**: A function in `hardening-fix.sh` that remediates
  a specific `CHK-*` finding.
- **Coverage Badge**: An inline annotation on a section heading
  indicating its automation level.

### Rabbit Holes (Identified, Deferred)

These areas surfaced during analysis but are out of scope for this
feature. Each warrants its own feature branch if pursued.

- **RH-001: Chrome DevTools Protocol (CDP) hardening** — §2.11 has
  8 Chromium checks, 4 without auto-fix. The CDP port binding check
  (`CHK-CHROMIUM-CDP`) is critical for deployments using Chrome
  automation (ports 9222/18800). Adding auto-fix for CDP port
  validation, Chromium profile isolation, and browser data cleanup
  is a separate workstream. *Candidate for `005-chromium-cdp-hardening`.*
- **RH-002: §7 Data Security automation** — 11 subsections, only 3
  have checks. Credential rotation, SSRF defense, supply chain
  integrity, and secure deletion are all manual. *Candidate for
  `006-data-security-checks`.*
- **RH-003: Incident response readiness checks (§9)** — IR
  procedures are inherently manual, but automated checks could
  verify that IR documentation exists, credentials are rotatable,
  and backup restore has been tested. *Candidate for
  `007-ir-readiness-checks`.*
- **RH-004: Lockdown Mode detection (§2.8)** — Apple does not
  expose Lockdown Mode status via CLI. A heuristic check is fragile
  across macOS versions. *Park unless specifically needed.*

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A reviewer can determine the automation coverage of
  any guide section in under 5 seconds by reading its heading badge.
- **SC-002**: The coverage summary at the top of HARDENING.md shows
  per-section breakdowns that sum correctly to the aggregate totals.
- **SC-003**: 100% of `CHK-*` identifiers in `hardening-audit.sh`
  appear in `CHK-REGISTRY.md` with zero omissions.
- **SC-004**: Zero existing content in HARDENING.md is altered —
  only badges, the coverage block, and notation table entries are
  added.
- **SC-005**: A non-technical stakeholder can understand the coverage
  summary without reading the full guide.
- **SC-006**: The three weakest sections (lowest automation
  percentage) are identifiable from the coverage summary alone.

## Assumptions

- The guide structure (section numbering, heading format) is stable
  and will not be reorganized during this feature.
- Badge placement is at the end of the subsection heading line
  (e.g., `### 2.1 Disk Encryption (FileVault) [AUTO-FIX]`).
- The coverage summary is manually maintained. This is acceptable
  because section changes are infrequent.
- The 10 missing CHK-* entries in the registry are:
  CHK-CHROMIUM-POLICY, CHK-CHROMIUM-AUTOFILL,
  CHK-CHROMIUM-EXTENSIONS, CHK-CHROMIUM-CDP, CHK-CHROMIUM-TCC,
  CHK-CHROMIUM-VERSION, CHK-CHROMIUM-DANGERFLAGS,
  CHK-CHROMIUM-URLBLOCK, CHK-PASSWORD-POLICY, CHK-SCRIPT-INTEGRITY.

## Clarifications

### Session 2026-03-16

- Q: Where should the coverage summary be placed in HARDENING.md? → A: Immediately after the Table of Contents, before the Preamble (maximum visibility for stakeholders reviewing coverage).

## Out of Scope

- Writing new audit checks or fix functions (this feature annotates
  existing coverage, not extend it).
- Changing the structure or content of HARDENING.md beyond adding
  badges and the coverage block.
- Automating coverage summary generation.
- Chrome/CDP-specific hardening improvements (see RH-001).
