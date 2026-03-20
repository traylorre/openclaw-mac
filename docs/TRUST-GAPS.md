# Trust Gaps: What Self-Attestation Can and Cannot Verify

This document identifies the boundary between what our hardening audit
can verify today and what requires a trust architecture (such as
[TEA — TSP-Enabled AI Agents](https://github.com/trustoverip/aimwg-tsp-enabled-ai-agent-protocols))
to verify credibly.

## What the audit verifies (Examine method)

`hardening-audit.sh` checks 84 controls across macOS, Docker, n8n,
browser, and operational categories. Every check uses the NIST SP
800-53A **Examine** method: read a configuration value, compare to
expected state, report PASS/FAIL.

This answers: **"Does the control exist?"**

For OS-level checks (~30), the
[mSCP](https://github.com/usnistgov/macos_security) project provides
validated CIS Benchmark and NIST SP 800-53 Rev 5 mappings. For
container and platform checks (~54), mappings follow CIS Docker
Benchmark v1.6 and NIST SP 800-190.

## What the audit cannot verify

| Gap | Why it matters | What would fix it |
|-----|---------------|-------------------|
| **Control effectiveness** | A firewall rule exists, but does it actually block a real probe? Examine ≠ Test (800-53A). | Test-method assessment: attempt the attack, observe the block. |
| **Report provenance** | The audit JSON is unsigned. Anyone with file access can forge a passing report. | DID-signed reports with verifiable credentials (TEA). |
| **Assessor independence** | The system audits itself. Subject and assessor are the same entity. | External witness or third-party attestation (TEA). |
| **Agent identity** | The n8n workflow authenticates via bearer token. There is no durable, portable agent identity. | Cryptographic agent ID independent of infrastructure (TEA/TSP). |
| **Delegation chain** | When the audit script calls n8n which calls Claude, there is no verifiable chain of authority. | Delegation credentials linking each hop (TEA/TSP). |
| **Temporal integrity** | A report says "PASS at 06:00" but the config could change at 06:01. No continuous assurance. | Continuous monitoring with signed state transitions. |

## The self-assessment trust problem (OWASP ASI09)

This deployment is an instance of
[ASI09 — Human-Agent Trust Exploitation](https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/):
the system that generates the trust report depends on the same
infrastructure the report assesses. A compromised system could report
itself as healthy.

This is not a flaw to fix in M2 — it is the **design constraint** that
future milestones (and TEA integration) aim to address. The value of
running self-attested audits now is generating baseline data and
building the measurement instrument, not making compliance claims.

## References

- NIST SP 800-53A Rev 5 — Assessment methods (Examine, Interview, Test)
- NIST SP 800-219 Rev 1 + [mSCP](https://github.com/usnistgov/macos_security) — macOS security baselines
- [TEA specification](https://github.com/trustoverip/aimwg-tsp-enabled-ai-agent-protocols) — TSP-Enabled AI Agent protocols
- [TSP specification](https://trustoverip.github.io/tswg-tsp-specification/) — Trust Spanning Protocol
- [OWASP Top 10 for Agentic Applications for 2026](https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/)
