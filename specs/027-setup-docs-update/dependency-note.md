# Dependency Note

## Revised Execution Order (2026-04-06)

Original plan had 027-029 as parallelizable. User correctly identified that 027 and 028 would need revision after 029+030 establish terminology and gap analysis.

**Revised order (strictly sequential):**
1. **029** — SECURITY-VALUE.md (establishes TSP/NIST terminology + control framework)
2. **030** — FEATURE-COMPARISON.md (uses 029 terminology, adds NemoClaw gap analysis)
3. **028** — BEHAVIORS.md (references both, uses consistent terms)
4. **027** — GETTING-STARTED.md update (cross-references 028+029, uses same language)

## Battleplan Status

- Phase 0: Complete (research + dependency mapping)
- Phase 1: Stage 1 (Specify) complete for all 4 features
- Phase 1: Stages 2-9 pending — start with Feature 029
- Context7 MCP research needed for: TSP glossary, NIST SP 800-53r5, CIS macOS Benchmark, OWASP Top 10 for LLM, MITRE ATLAS, NemoClaw docs

## Resume Command

```
/battleplan Resume 029→030→028→027 pipeline. Stage 1 (Specify) is complete for all 4. Start with Feature 029 Stage 2 (Adversarial Review #1). Specs are in specs/029-security-value-doc/spec.md. Context7 research needed for TSP glossary, NIST 800-53r5, NemoClaw docs.
```
