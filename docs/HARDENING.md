# macOS Hardening Guide for n8n + Apify Deployment

<!-- markdownlint-disable MD013 -->

## Table of Contents

- [Preamble](#preamble)
- [1. Threat Model](#1-threat-model)
- [2. OS Foundation](#2-os-foundation)
- [3. Network Security](#3-network-security)
- [4. Container Isolation — Containerized Path](#4-container-isolation--containerized-path)
- [5. n8n Platform Security](#5-n8n-platform-security)
- [6. Bare-Metal Path — Bare-Metal Only](#6-bare-metal-path--bare-metal-only)
- [7. Data Security](#7-data-security)
- [8. Detection and Monitoring](#8-detection-and-monitoring)
- [9. Response and Recovery](#9-response-and-recovery)
- [10. Operational Maintenance](#10-operational-maintenance)
- [11. Audit Script Reference](#11-audit-script-reference)
- [Appendix A: Security Environment Variable Reference](#appendix-a-security-environment-variable-reference)
- [Appendix B: Credential Inventory Template](#appendix-b-credential-inventory-template)
- [Appendix C: Incident Response Checklist](#appendix-c-incident-response-checklist)
- [Appendix D: Tool Comparison Matrix](#appendix-d-tool-comparison-matrix)
- [Appendix E: PII Data Classification Table](#appendix-e-pii-data-classification-table)

---

## Preamble

<!-- Content: T006 -->

---

## 1. Threat Model

<!-- Content: T007 -->

---

## 2. OS Foundation

### 2.1 Disk Encryption (FileVault)

<!-- Content: T009 -->

### 2.2 Firewall

<!-- Content: T009 -->

### 2.3 System Integrity Protection (SIP)

<!-- Content: T009 -->

### 2.4 Gatekeeper and XProtect

<!-- Content: T009 -->

### 2.5 Software Updates

<!-- Content: T009 -->

### 2.6 Screen Lock and Login Security

<!-- Content: T009 -->

### 2.7 Guest Account and Sharing Services

<!-- Content: T009 -->

### 2.8 Lockdown Mode

<!-- Content: T009 -->

### 2.9 Recovery Mode Password

<!-- Content: T009 -->

### 2.10 System Privacy and TCC

<!-- Content: T009 -->

---

## 3. Network Security

### 3.1 SSH Hardening

<!-- Content: T014 -->

### 3.2 DNS Security

<!-- Content: T014 -->

### 3.3 Outbound Filtering

<!-- Content: T014 -->

### 3.4 Bluetooth

<!-- Content: T014 -->

### 3.5 IPv6

<!-- Content: T014 -->

### 3.6 Service Binding and Port Exposure

<!-- Content: T014 -->

---

## 4. Container Isolation — Containerized Path

### 4.1 Colima Setup

<!-- Content: T019 -->

### 4.2 Docker Security Principles

<!-- Content: T019 -->

### 4.3 Reference docker-compose.yml

<!-- Content: T019 -->

### 4.4 Advanced Container Hardening

<!-- Content: T019 -->

### 4.5 Container Networking

<!-- Content: T019 -->

---

## 5. n8n Platform Security

### 5.1 Binding and Authentication

<!-- Content: T024 -->

### 5.2 User Management

<!-- Content: T024 -->

### 5.3 Security Environment Variables

<!-- Content: T024 -->

### 5.4 REST API Security

<!-- Content: T024 -->

### 5.5 Webhook Security

<!-- Content: T024 -->

### 5.6 Execution Model and Node Isolation

<!-- Content: T024 -->

### 5.7 Community Node Vetting

<!-- Content: T024 -->

### 5.8 Reverse Proxy

<!-- Content: T024 -->

### 5.9 Update and Migration Security

<!-- Content: T024 -->

---

## 6. Bare-Metal Path — Bare-Metal Only

### 6.1 Dedicated Service Account

<!-- Content: T029 -->

### 6.2 Keychain Integration

<!-- Content: T029 -->

### 6.3 launchd Execution

<!-- Content: T029 -->

### 6.4 Filesystem Permissions

<!-- Content: T029 -->

---

## 7. Data Security

### 7.1 Credential Management

<!-- Content: T034 -->

### 7.2 Credential Lifecycle

<!-- Content: T034 -->

### 7.3 Scraped Data Input Security

<!-- Content: T034 -->

### 7.4 PII Protection

<!-- Content: T034 -->

### 7.5 SSRF Defense

<!-- Content: T034 -->

### 7.6 Data Exfiltration Prevention

<!-- Content: T034 -->

### 7.7 Supply Chain Integrity

<!-- Content: T034 -->

### 7.8 Apify Actor Security

<!-- Content: T034 -->

### 7.9 Secure Deletion

<!-- Content: T034 -->

### 7.10 Clipboard Security

<!-- Content: T034 -->

---

## 8. Detection and Monitoring

### 8.1 IDS Tools

<!-- Content: T039 -->

### 8.2 Launch Daemon and Persistence Auditing

<!-- Content: T039 -->

### 8.3 Workflow Integrity Monitoring

<!-- Content: T039 -->

### 8.4 macOS Logging

<!-- Content: T039 -->

### 8.5 Credential Exposure Monitoring

<!-- Content: T039 -->

### 8.6 iCloud and Cloud Service Exposure

<!-- Content: T039 -->

### 8.7 Certificate Trust Monitoring

<!-- Content: T039 -->

---

## 9. Response and Recovery

### 9.1 Incident Response Runbook

<!-- Content: T044 -->

### 9.2 Credential Rotation Procedures

<!-- Content: T044 -->

### 9.3 Backup and Recovery

<!-- Content: T044 -->

### 9.4 Restore Testing

<!-- Content: T044 -->

### 9.5 Physical Security

<!-- Content: T044 -->

---

## 10. Operational Maintenance

### 10.1 Automated Audit Scheduling

<!-- Content: T049 -->

### 10.2 Notification Setup

<!-- Content: T049 -->

### 10.3 Tool Maintenance

<!-- Content: T049 -->

### 10.4 Log Retention and Rotation

<!-- Content: T049 -->

### 10.5 Troubleshooting Common Failures

<!-- Content: T049 -->

### 10.6 Hardening Validation Tests

<!-- Content: T049 -->

---

## 11. Audit Script Reference

### 11.1 Running the Audit Script

<!-- Content: T054 -->

### 11.2 Check Reference Table

<!-- Content: T054 -->

### 11.3 JSON Output Schema

<!-- Content: T054 -->

### 11.4 Interpreting Results

<!-- Content: T054 -->

---

## Appendix A: Security Environment Variable Reference

<!-- Content: T059 -->

## Appendix B: Credential Inventory Template

<!-- Content: T060 -->

## Appendix C: Incident Response Checklist

<!-- Content: T061 -->

## Appendix D: Tool Comparison Matrix

<!-- Content: T062 -->

## Appendix E: PII Data Classification Table

<!-- Content: T063 -->
