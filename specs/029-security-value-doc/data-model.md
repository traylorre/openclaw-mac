# Data Model: Feature 029 — SECURITY-VALUE.md

**Date**: 2026-04-06 | **Phase**: 1 (Design)

## Document Structure

`docs/SECURITY-VALUE.md` is a markdown document, not a data store. The "data model" describes the document's information architecture.

### Section Layout

```text
docs/SECURITY-VALUE.md
├── Title + scope statement
├── Relationship to ASI-MAPPING.md (cross-reference)
├── Control Matrix (table — primary artifact)
│   ├── Row per control (7 core + summary of additional)
│   └── Columns: Control | Threat | NIST Family | TSC Category | Layer | Implementation | Value
├── Why This Matters (narrative — interview material)
│   ├── Defense-in-depth chain explanation
│   ├── "What happens if you skip this?" for each control
│   └── Real-world incident parallels
├── OWASP LLM Mapping (table — secondary)
│   └── LLM Risk | Controls | Gap
├── Standards Referenced (table — citations)
│   └── Standard | Version | Date | URL
├── Limitations and Exclusions
│   └── What this project does NOT cover
└── Footer with generation date and document version
```

### Control Matrix Schema

Each row in the Control Matrix contains:

| Field | Type | Source | Example |
|-------|------|--------|---------|
| Control | String | REQ-03 control list | "Filesystem Immutability (uchg)" |
| Threat | String | Constitution II threat model | "Workspace file tampering by compromised agent or supply chain attack" |
| NIST Family | String[] | research.md mapping | "SC-28, CM-5, SI-7" |
| TSC Category | String | research.md mapping | "Security (CC6.1)" |
| Layer | Enum | Constitution VII | "Prevent" / "Detect" / "Respond" |
| Implementation | String | Audit check IDs + make targets | "`CHK-OPENCLAW-INTEGRITY-LOCK` · `make integrity-lock`" |
| Value | String | research.md value statements | One-sentence plain-English justification |

### Cross-Reference Model

```text
SECURITY-VALUE.md (control-centric)
    ├── references → ASI-MAPPING.md (threat-centric, OWASP Agentic)
    ├── references → HARDENING.md (full audit check details)
    ├── referenced-by ← FEATURE-COMPARISON.md (030, uses terminology)
    ├── referenced-by ← BEHAVIORS.md (028, links for "why")
    └── referenced-by ← GETTING-STARTED.md (027, next-steps link)
```

### Entities

No persistent data entities. The document is a static reference artifact that is regenerated when controls change.

### State Transitions

N/A — document is immutable between commits.

### Validation Rules

1. Every row in Control Matrix must have non-empty values in all columns
2. Every NIST family cited must be a valid 800-53r5 family identifier
3. Every TSC category must be one of: Security, Availability, Processing Integrity, Confidentiality, Privacy
4. Every Layer must be one of: Prevent, Detect, Respond (per Constitution VII)
5. Every Implementation field must reference at least one `CHK-*` identifier or `make` target
6. Standards Referenced URLs must resolve (verified during implementation)
