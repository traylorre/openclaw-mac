# Pending Work: HARDENING.md Extension

## Context
The user wants to extend `docs/HARDENING.md` using the audit from `docs/HARDENING-AUDIT.md`.

## Requirements
- Merge the comprehensive audit findings INTO `docs/HARDENING.md` (not a separate file)
- Focus on **free options** throughout
- Call out wherever options incur cost
- Where no free alternative exists, explain the tradeoff of not spending vs the liability
- Think like a principal engineer
- Cite canonical sources (CIS Benchmarks, NIST SP 800-179, Apple Platform Security Guide, drduh/macOS-Security-and-Privacy-Guide GitHub repo, Objective-See, Google Santa repo, OWASP, MITRE ATT&CK for macOS, etc.)
- Use prominent repos or social media content to justify improvements

## Threat Model
Mac Mini running:
- OpenClaw project
- n8n orchestrating lead generation and enrichment workflows
- Apify.com integration targeting LinkedIn and other websites

## Key Sections to Cover
- Threat model (specific to this setup)
- Core system security (FileVault, SIP, firmware, updates)
- Network hardening (firewall inbound+outbound, sharing services, Bluetooth, IPv6, DNS)
- n8n-specific hardening (bind localhost, auth, encryption key, community nodes, webhooks, dedicated user)
- Credential/secret management (macOS Keychain, Bitwarden CLI)
- Antivirus/EDR (ClamAV, Objective-See suite, cost tradeoffs for SentinelOne/CrowdStrike)
- IDS (OpenBSM, Google Santa, LuLu, Wazuh)
- Bluetooth lockdown
- USB/Thunderbolt lockdown
- Access control and privacy
- PII/lead data protection (GDPR, CCPA, LinkedIn ToS)
- Logging, monitoring, alerting
- Backup and recovery
- Physical security
- Comprehensive audit script
- Quick-start checklist

## Use the Spec-Kit /speckit.specify command once initialized
The user originally tried to use `/speckit.specify` to drive this work but the project hasn't been initialized with GitHub Spec-Kit yet.
