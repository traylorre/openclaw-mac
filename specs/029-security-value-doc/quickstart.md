# Quickstart: Feature 029 — SECURITY-VALUE.md

## What This Feature Does

Creates `docs/SECURITY-VALUE.md` — a control-centric reference that answers "why does each security restriction exist?" by mapping controls to NIST 800-53r5 families, AICPA TSC categories, and plain-English value propositions.

## Implementation Steps

1. Create `docs/SECURITY-VALUE.md` with the Control Matrix table (7 core controls)
2. Write the "Why This Matters" narrative section
3. Add the OWASP LLM 2025 mapping table
4. Add the Standards Referenced table with version-pinned citations
5. Add the Limitations and Exclusions section
6. Add scope statement and cross-reference to ASI-MAPPING.md
7. Verify all external links resolve
8. Run markdownlint to ensure CI will pass

## Files Changed

- `docs/SECURITY-VALUE.md` — **NEW** (primary deliverable)

## Files Referenced (not modified)

- `docs/ASI-MAPPING.md` — cross-referenced for threat-centric view
- `docs/HARDENING.md` — referenced for audit check details

## Testing

```bash
# Verify markdownlint passes
npx markdownlint-cli2 docs/SECURITY-VALUE.md

# Verify no broken internal cross-references
grep -o '\[.*\](docs/[^)]*\.md)' docs/SECURITY-VALUE.md
```

## Dependencies

- None (first in the 029→030→028→027 pipeline)
- Downstream: Feature 030 uses terminology from this document
