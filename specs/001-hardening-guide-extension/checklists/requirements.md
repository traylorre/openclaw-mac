# Specification Quality Checklist: Hardening Guide Extension

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-03-07
**Updated**: 2026-03-07 (Rev 11 -- 3 injection-focused rounds: data flow, LLM depth, audit)
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Notes

- All items pass. Spec is ready for `/speckit.clarify` or `/speckit.plan`.
- **Rev 9 changes (injection: data flow and detection):**
  - Added US-7 (Operator Secures Workflows Against Injection) with
    4 acceptance scenarios: vulnerable Code node pattern, prompt
    injection resistance, logging of attempts, and bare-metal
    consequence awareness.
  - FR-021 expanded with data flow mapping (5-step pipeline showing
    where untrusted data enters and where it reaches code execution).
  - FR-021 expanded with n8n built-in security env vars
    (`N8N_BLOCK_ENV_ACCESS_IN_NODE`, `N8N_RESTRICT_FILE_ACCESS_TO`,
    community/node type restrictions).
  - FR-021 expanded with Detect layer: execution logging, anomaly
    monitoring, suspicious pattern detection, Docker log capture.
  - FR-021 sections now labeled by defensive layer (Prevent/Detect/
    Respond) per FR-008.
  - Fixed stale "25 control areas" reference in FR-020.
- **Rev 10 changes (injection: prompt injection depth):**
  - FR-021 prompt injection: added "never allow LLM output to modify
    workflows" (n8n API persistence attack). Added "system prompt
    hardening is a speed bump, not a wall" caveat.
  - FR-021: named specific vulnerable n8n AI/LLM nodes (OpenAI,
    AI Agent, LangChain, Anthropic, community AI nodes).
  - FR-021 bare-metal warning: expanded to list 5 concrete
    consequences (home directory, Keychain, persistence, lateral
    movement, data exfiltration). Added minimum bare-metal controls
    if operator declines containerization.
  - Edge cases added: subtle data exfiltration via HTTP Request
    nodes following attacker URLs; LLM tool-calling/function-calling
    exploitation.
- **Rev 11 changes (injection: audit and monitoring):**
  - FR-007: expanded injection audit checks beyond Execute Command
    to include `N8N_BLOCK_ENV_ACCESS_IN_NODE`, file access
    restrictions, execution logging enabled.
  - FR-009: added injection log review and workflow re-audit to
    ongoing maintenance tier.
  - SC-012 added: operator can audit any workflow for injection
    vulnerabilities in one pass using the guide's checklist.
  - Assumption added: AI/LLM nodes may or may not be in use;
    injection defense section must be useful regardless.
- Cumulative counts (Rev 11):
  - FR count: 21
  - User story count: 7
  - Success criteria count: 12
  - Edge case count: 14
  - Control areas: 26
