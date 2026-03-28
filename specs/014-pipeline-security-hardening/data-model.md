# Data Model: Pipeline Security Hardening

**Feature**: 014-pipeline-security-hardening
**Date**: 2026-03-26

## Entity: CVE Record

A known vulnerability tracked in the version-controlled CVE registry.

**Attributes**:
- `cve_id`: CVE identifier (e.g., `CVE-2026-21858`)
- `cvss_score`: Numeric CVSS score (e.g., `10.0`)
- `severity`: `critical` | `high` | `medium` | `low`
- `component`: `n8n` | `openclaw` | `ollama`
- `affected_versions`: Version range (e.g., `<1.121.0`)
- `fixed_version`: First patched version (e.g., `1.121.0`)
- `description`: Brief description of the vulnerability
- `source_url`: NVD or advisory URL
- `date_added`: When this entry was added to the registry

**Persistence**: `data/cve-registry.json` (version-controlled, manually maintained)

**Relationships**:
- Queried by CVE verification audit checks (check_cve_n8n, check_cve_openclaw, check_cve_ollama)
- Referenced in ASI mapping (ASI04 Supply Chain controls)

---

## Entity: Sensitive File Entry

A file in the pipeline with documented protections and verification status.

**Attributes**:
- `path`: Absolute or tilde-prefixed path
- `risk_level`: `critical` | `high` | `medium`
- `protection_type`: Array of `permissions` | `immutability` | `hmac_signature` | `gitignore`
- `expected_permissions`: Mode string (e.g., `600`)
- `expected_flags`: `uchg` | `none`
- `expected_signature`: `hmac_signed` | `unsigned` | `not_applicable`
- `status`: `enforced` | `needs_remediation` | `future`
- `adv_reference`: ADV finding ID if applicable (e.g., `ADV-002`)

**Persistence**: `docs/SENSITIVE-FILE-INVENTORY.md` (version-controlled documentation)

**Relationships**:
- Verified by `check_sensitive_file_protections()` in hardening-audit.sh
- Remediation tracked by ADV finding IDs

---

## Entity: ASI Control Mapping

An OWASP ASI risk mapped to pipeline-specific controls.

**Attributes**:
- `asi_id`: Local identifier (e.g., `ASI01`)
- `risk_name`: OWASP risk name (e.g., `Agent Goal Hijack`)
- `controls`: Array of pipeline controls with descriptions
- `verification_method`: Audit check name or manual procedure
- `residual_risk`: Description of remaining exposure after controls
- `residual_severity`: `critical` | `high` | `medium` | `low` | `accepted`
- `remediation_milestone`: Target milestone for residual risk remediation (if applicable)

**Persistence**: `docs/ASI-MAPPING.md` (version-controlled documentation)

**Relationships**:
- Controls reference audit checks in hardening-audit.sh
- Residual risks reference ADV findings

---

## Entity: Defense Layer

One of five defense-in-depth layers with independently verifiable controls.

**Attributes**:
- `layer_name`: `prevent` | `contain` | `detect` | `respond` | `recover`
- `nist_csf_function`: Corresponding NIST Cybersecurity Framework function
- `controls`: Array of controls with names and audit check IDs
- `mitre_atlas_techniques`: Array of ATLAS technique IDs defended by this layer
- `status`: `healthy` | `degraded` | `failed`

**Persistence**: In-memory during audit run; reported in audit JSON output

**Relationships**:
- Each control maps to one or more hardening-audit.sh check functions
- Layer status aggregated from individual control statuses

---

## Entity: Token Lifecycle State

LinkedIn API credential status with dual-token support.

**Attributes**:
- `access_token_granted_at`: Timestamp of last access token grant
- `access_token_expires_at`: Computed (granted_at + 60 days)
- `access_token_days_remaining`: Computed daily
- `refresh_token_granted_at`: Timestamp of original refresh token grant
- `refresh_token_expires_at`: Computed (granted_at + 365 days)
- `refresh_token_days_remaining`: Computed daily
- `last_refresh_attempt`: Timestamp of last automated refresh
- `last_refresh_result`: `success` | `failed` | `not_attempted`
- `status`: `healthy` | `expiring_soon` | `expired` | `refresh_failed`

**Persistence**: n8n Workflow Static Data (token-check workflow)

**Relationships**:
- Managed by token-check n8n workflow (daily schedule)
- Alerts sent to OpenClaw inbound hook on status changes

---

## Entity: Behavioral Baseline

Operational baseline for agent behavior used to detect anomalies.

**Attributes**:
- `baseline_date`: When the baseline was established
- `webhook_call_frequency`: Expected calls per day by webhook path
- `skill_invocation_frequency`: Expected invocations per day by skill name (initially null; populated when OpenClaw agent produces skill invocation logs)
- `last_comparison_date`: When the baseline was last compared against actual behavior
- `deviation_threshold`: Percentage deviation that triggers an alert

**Persistence**: `~/.openclaw/behavioral-baseline.json` (created by integrity-deploy.sh at deployment-time, compared by integrity-verify.sh at launch-time)

**Relationships**:
- Compared against actual n8n execution history during integrity-verify.sh
- Deviations reported as WARN in audit output
