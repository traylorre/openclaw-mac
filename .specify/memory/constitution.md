# OpenClaw-Mac Constitution

## Core Principles

### I. Documentation-Is-the-Product

This repository's primary output is actionable macOS hardening guidance
and audit tooling, not application software. Every change must be
evaluated by whether it makes the guides more complete, more accurate,
or easier to follow. Prose quality matters as much as code quality.

Reference: [drduh/macOS-Security-and-Privacy-Guide](https://github.com/drduh/macOS-Security-and-Privacy-Guide)
is the benchmark for community hardening docs. Our guides should
match or exceed that standard for the specific threat model we serve.

### II. Threat-Model Driven (NON-NEGOTIABLE)

Every hardening recommendation must be justified against a specific,
named threat to this deployment:

* **Platform:** Apple Silicon Mac Mini running headless or semi-headless
* **Workload:** n8n orchestrating Apify actors for LinkedIn lead
  generation and enrichment
* **Assets to protect:** LinkedIn credentials and session tokens,
  Apify API keys, PII lead data, n8n workflow IP, system integrity
* **Adversaries:** opportunistic network scanners, credential-stuffing
  bots, malicious npm/community-node supply chain, physical theft,
  LAN-adjacent attackers

Do not add controls that cannot be traced back to a plausible attack
path against this deployment. Defense in depth is required — no
single control is sufficient — but controls without a threat
justification are bloat.

Reference: NIST SP 800-154 (Guide to Data-Centric System Threat
Modeling); MITRE ATT&CK for macOS technique matrix.

### III. Free-First with Cost Transparency

Default to free and open-source tools for every recommendation.

* **Free options** are presented as the primary recommendation with
  full setup instructions.
* **Paid options** must be clearly marked with `[PAID]`, approximate
  cost, and what capability gap they fill over the free alternative.
* **Where no free alternative exists**, document the explicit tradeoff:
  what risk you are accepting by not spending, and what the liability
  exposure looks like (data breach notification costs, credential
  compromise blast radius, account bans, etc.).

Never recommend a paid tool without first exhausting free options.
Never dismiss a risk just because the mitigation costs money.

### IV. Cite Canonical Sources (NON-NEGOTIABLE)

Every security recommendation must reference at least one of:

* **Standards bodies:** CIS Apple macOS Benchmarks, NIST SP 800-179
  (Guide to Securing Apple macOS Systems), NIST SP 800-123 (Guide
  to General Server Security)
* **Vendor documentation:** Apple Platform Security Guide
  (support.apple.com/guide/security), Apple's Manage Login Items
  documentation
* **Established security tooling repos:** Objective-See
  (objective-see.org), Google Santa
  (github.com/google/santa), ClamAV (github.com/Cisco-Talos/clamav)
* **Community references:** drduh/macOS-Security-and-Privacy-Guide
  (github.com), OWASP Top 10, relevant CVE entries
* **Credible practitioners:** Patrick Wardle (Objective-See founder),
  The Mac Security Blog (Intego), Krebs on Security for breach
  context

Unsourced recommendations are not allowed. "I heard this is a good
practice" is not a source. If a recommendation cannot be sourced, it
must be flagged as experiential guidance with a clear disclaimer.

### V. Every Recommendation Is Verifiable

For every hardening step, provide one of:

* A terminal command that checks the current state
* A System Settings navigation path that shows the current state
* A check in the comprehensive audit script

If a recommendation cannot be verified, it cannot be audited, and an
unauditable control is the same as no control. The audit script
(`docs/HARDENING.md` verification section) is a first-class artifact
that must stay in sync with the guide content.

Reference: CIS Benchmarks structure every control as
Description / Rationale / Audit / Remediation. Follow that pattern.

### VI. Bash Scripts Are Infrastructure

All shell scripts in this repository must:

* Start with `set -euo pipefail`
* Pass `shellcheck` with zero warnings
* Be idempotent and safe to re-run (no destructive side effects)
* Use colored PASS/FAIL/WARN output for audit scripts
* Quote all variables, use `[[ ]]` over `[ ]`
* Never require interactive input (no `read -p` in audit scripts)
* Work on both Apple Silicon and Intel Mac Minis where applicable

Reference: Google Shell Style Guide
(google.github.io/styleguide/shellguide.html); ShellCheck
(github.com/koalaman/shellcheck).

### VII. Defense in Depth, Organized by Layer

Structure hardening content in layers that mirror the kill chain:

1. **Prevent:** Controls that stop attacks before they succeed
   (firewall, disable services, Gatekeeper, SIP)
2. **Detect:** Controls that reveal attacks in progress or after the
   fact (IDS, outbound firewall alerts, log monitoring, file
   integrity)
3. **Respond:** Controls that limit blast radius and enable recovery
   (backup, Find My Mac, credential rotation, incident procedures)

Every section of the hardening guide should make clear which layer it
addresses. A section that only prevents but doesn't detect is
incomplete.

Reference: NIST Cybersecurity Framework (Identify, Protect, Detect,
Respond, Recover).

### VIII. Explicit Over Clever

Write for an operator who is technically capable (comfortable with
Terminal) but is NOT a macOS security specialist. That means:

* Spell out the full `System Settings` navigation path, not just the
  pane name
* Provide copy-pasteable terminal commands, not pseudocode
* Explain WHY a control matters before HOW to enable it — name the
  attack it prevents
* Never assume the reader knows what SIP, TCC, OpenBSM, or XProtect
  are without a one-line explanation

### IX. Markdown Quality Gate

All documentation must pass the project's markdownlint CI pipeline
(`.github/workflows/lint.yml`) before merge. The
`.markdownlint-cli2.jsonc` config disables MD013 (line length) —
all other rules are enforced.

Write clean markdown on the first pass. Do not rely on CI to catch
formatting issues.

## Deployment Context

### Target System

| Attribute | Value |
|-----------|-------|
| Hardware | Mac Mini (Apple Silicon or Intel) |
| Role | Always-on automation server |
| OS | macOS Tahoe (26) or Sonoma (14) |
| Workload | n8n, Node.js, Apify CLI/SDK |
| Data sensitivity | PII (lead data), API credentials, session tokens |
| Network posture | LAN-connected, possible webhook ingress |
| Physical posture | Office/home, not a data center |

### Out of Scope

* iOS/iPadOS hardening
* MDM/enterprise fleet management (this is a single machine)
* macOS Sequoia (15) — covered only if controls differ materially
  from Tahoe or Sonoma
* Application development guidance (this repo does not ship software
  to end users)

## Development Workflow

### Adding or Modifying Hardening Content

1. **Spec first:** Use `/speckit.specify` to produce a spec that
   names the threats addressed, sources consulted, and controls
   proposed
2. **Plan second:** Use `/speckit.plan` to break the spec into tasks
   with clear acceptance criteria (including audit script updates)
3. **Implement:** Write the guide content, terminal commands, and
   audit script checks together — never one without the others
4. **Verify:** Run the audit script on an actual macOS system before
   merging (or document that verification is pending)
5. **CI must pass:** Markdownlint and link checker must be green

### Pull Request Standards

* PR title under 70 characters
* Body must state which threats are addressed
* Every new recommendation must include its source citation
* Audit script must be updated in the same PR as guide content
* No PRs that only add guide prose without a verification path

## Governance

This constitution supersedes default Spec-Kit principles (library-
first, CLI mandate, TDD imperative) which do not apply to a
documentation and scripting repository. Amendments require:

1. A rationale tied to a change in the deployment's threat model
2. Review by the repository maintainer
3. Update to this document in the same PR as the change it enables

**Version**: 1.0.0 | **Ratified**: 2026-03-07 | **Last Amended**: 2026-03-07
