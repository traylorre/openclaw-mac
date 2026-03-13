# Audit Check Registry

Central registry of all `CHK-*` identifiers used in `scripts/hardening-audit.sh`.

| ID | Severity | Deployment | Guide Section | Owning Task |
|----|----------|------------|---------------|-------------|
| CHK-SIP | FAIL | both | §2.3 | T003 |
| CHK-FILEVAULT | FAIL | both | §2.1 | T003 |
| CHK-FIREWALL | FAIL | both | §2.2 | T003 |
| CHK-STEALTH | WARN | both | §2.2 | T003 |
| CHK-GATEKEEPER | FAIL | both | §2.4 | T014 |
| CHK-XPROTECT-FRESH | WARN | both | §2.4 | T014 |
| CHK-AUTO-UPDATES | WARN | both | §2.5 | T014 |
| CHK-NTP | WARN | both | §2.5 | T014 |
| CHK-AUTO-LOGIN | FAIL | both | §2.6 | T014 |
| CHK-SCREEN-LOCK | WARN | both | §2.6 | T014 |
| CHK-GUEST | FAIL | both | §2.7 | T014 |
| CHK-SHARING-FILE | FAIL | both | §2.7 | T014 |
| CHK-SHARING-REMOTE-EVENTS | FAIL | both | §2.7 | T014 |
| CHK-SHARING-INTERNET | FAIL | both | §2.7 | T014 |
| CHK-SHARING-SCREEN | WARN | both | §2.7 | T014 |
| CHK-AIRDROP | WARN | both | §2.7 | T014 |
| CHK-STARTUP-SECURITY | WARN | both | §2.9 | T014 |
| CHK-TCC | WARN | both | §2.10 | T014 |
| CHK-CORE-DUMPS | WARN | both | §2.10 | T014 |
| CHK-PRIVACY | WARN | both | §2.10 | T014 |
| CHK-PROFILES | WARN | both | §2.10 | T014 |
| CHK-SPOTLIGHT | WARN | both | §2.10 | T014 |
| CHK-SSH-KEY-ONLY | FAIL | both | §3.1 | T019 |
| CHK-SSH-ROOT | FAIL | both | §3.1 | T019 |
| CHK-DNS-ENCRYPTED | WARN | both | §3.2 | T019 |
| CHK-OUTBOUND-FILTER | WARN | both | §3.3 | T019 |
| CHK-BLUETOOTH | WARN | both | §3.4 | T019 |
| CHK-IPV6 | WARN | both | §3.5 | T019 |
| CHK-LISTENERS-BASELINE | WARN | both | §3.6 | T019 |
| CHK-CONTAINER-ROOT | FAIL | containerized | §4.3 | T024 |
| CHK-CONTAINER-READONLY | WARN | containerized | §4.3 | T024 |
| CHK-CONTAINER-CAPS | WARN | containerized | §4.3 | T024 |
| CHK-CONTAINER-PRIVILEGED | FAIL | containerized | §4.3 | T024 |
| CHK-DOCKER-SOCKET | FAIL | containerized | §4.3 | T024 |
| CHK-SECRETS-ENV | WARN | containerized | §4.3 | T024 |
| CHK-COLIMA-MOUNTS | WARN | containerized | §4.3 | T024 |
| CHK-N8N-BIND | FAIL | both | §5.1 | T029 |
| CHK-N8N-AUTH | FAIL | both | §5.1 | T029 |
| CHK-N8N-API | WARN | both | §5.4 | T029 |
| CHK-N8N-ENV-BLOCK | WARN | both | §5.3 | T029 |
| CHK-N8N-ENV-DIAGNOSTICS | WARN | both | §5.3 | T029 |
| CHK-N8N-ENV-API | WARN | both | §5.3 | T029 |
| CHK-N8N-NODES | WARN | both | §5.6 | T029 |
| CHK-N8N-WEBHOOK | WARN | both | §5.5 | T029 |
| CHK-SERVICE-ACCOUNT | FAIL | bare-metal | §6.1 | T032 |
| CHK-SERVICE-HOME-PERMS | FAIL | bare-metal | §6.4 | T032 |
| CHK-SERVICE-DATA-PERMS | FAIL | bare-metal | §6.4 | T032 |
<!-- New checks added by T038, T045, T050, T058 -->
