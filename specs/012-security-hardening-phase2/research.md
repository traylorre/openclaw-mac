# Research: Security Hardening Phase 2 (012)

**Date**: 2026-03-24
**Status**: Complete
**Spec**: [spec.md](spec.md)

## R-001: Append-Only Flag Behavior on macOS

**Decision**: Use `chflags uappnd` (user append-only) for the audit log. Accept that root can clear it with `chflags nouappnd`. Document this limitation.

**Rationale**: macOS provides two append-only flags: `uappnd` (user-level, clearable by root) and `sappnd` (system-level, requires Recovery Mode to clear). `sappnd` would be stronger but operationally hostile — log rotation, troubleshooting, and development all become impossible without rebooting into Recovery Mode. `uappnd` provides meaningful protection: the file owner and non-root processes cannot truncate or delete the log. Root can clear it, but this is consistent with the threat model (root compromise is an accepted residual risk per ADV-001).

**Alternatives considered**:
- `sappnd` (system append-only): Strongest but requires Recovery Mode to clear. Unacceptable for operations.
- No flag, rely on file permissions only: Insufficient — same-user processes can delete 600-permission files.
- External logging (syslog/rsyslog): Would require a separate logging daemon. Over-engineering for single-operator deployment.

## R-002: Hash-Chained Audit Log Design

**Decision**: Each audit log entry includes a `prev_hash` field containing the SHA-256 hash of the previous entry. The first entry uses a well-known constant (`GENESIS`). Verification walks the chain to detect insertion, reordering, or deletion.

**Rationale**: A hash chain provides ordering integrity without requiring a separate signing key per entry. Combined with the append-only flag, it creates two independent protections: the flag prevents deletion, the chain detects insertion/reordering. An attacker who appends forged entries cannot make them chain-consistent with the existing entries unless they can also compute SHA-256 (trivial) AND know the last entry's hash (they can read it since the log is readable). Therefore, the hash chain primarily detects offline tampering (log copied, modified, replaced) rather than online appending.

**Alternatives considered**:
- Per-entry HMAC signing: Stronger but the same ADV-001 key-in-same-domain problem applies — same-user attacker has the key.
- Merkle tree: Over-engineering for a linear append-only log.
- External timestamping service: Deferred to M5 (requires network dependency).

## R-003: Browser Session Encryption

**Decision**: Use AES-256-GCM via `openssl enc` with the encryption key stored in macOS Keychain under a separate service name. Decryption produces a temporary file that is deleted after use.

**Rationale**: AES-256-GCM provides authenticated encryption (confidentiality + integrity). The `openssl` CLI is built into macOS, requiring no additional dependencies. Storing the key in the Keychain (separate from the HMAC signing key) follows the established credential storage pattern. The encryption protects against offline/physical attacks (disk theft, backup exfiltration) but not same-user extraction (ADV-001 applies — any same-user process can read the Keychain).

**Alternatives considered**:
- macOS Disk Encryption (FileVault): Already enabled (M2 baseline). Protects the whole disk but not individual files at rest when the system is booted and logged in.
- GPG encryption: Requires gpg installation and key management. Heavier than needed.
- Age encryption: Clean modern tool but adds a dependency. openssl is already available.

## R-004: Container Image Verification

**Decision**: Record the n8n Docker image ID (SHA-256 digest from `docker inspect`) in the integrity manifest during deployment. Before any `docker exec` command, verify the running container's image ID matches the manifest.

**Rationale**: Docker image IDs are content-addressed (SHA-256 of the image configuration). An attacker who replaces the container with a different image will produce a different ID. This check is cheap (one `docker inspect` call) and definitive (image IDs cannot be forged without producing an identical image). The image ID is stored in the manifest alongside file checksums, signed with the same HMAC key.

**Alternatives considered**:
- Docker Content Trust (DCT/Notary): Enterprise feature, requires a notary server. Over-engineering for a local deployment.
- Image hash comparison via `docker images --digests`: Only works for pulled images, not locally built ones. Our n8n image is custom-built.
- Container runtime verification via `docker inspect --format`: This is what we use — most direct and reliable.

## R-005: Webhook Payload Sanitization Layer

**Decision**: Add a Code node to the n8n webhook workflow (immediately after HMAC verification) that validates payload schema, content length, and character safety. The sanitization workflow JSON file is added to the protected file list so its modification is detected.

**Rationale**: Placing sanitization inside n8n (rather than a host-side proxy) keeps the architecture simple — one less process to manage. The circular dependency (sanitization inside the container that US3 protects) is mitigated by: (1) the sanitization workflow file is in the protected file set, so modification is detected at next verification, (2) the HMAC signature already proves the payload came from the agent, so the sanitization is a second layer checking content quality, not authentication.

**Alternatives considered**:
- Host-side webhook proxy: Stronger isolation but adds a new process, port, and failure mode. Deferred unless circular dependency proves exploitable.
- n8n built-in validation: n8n has no built-in payload schema validation. Must be a Code node.
- Agent-side validation before sending: Defense-in-depth says validate at both ends, but the agent itself may be compromised (that's the threat we're defending against).

## R-006: Manifest Sequence Counter Storage

**Decision**: Store the last verified sequence number in `~/.openclaw/manifest-sequence.json`, signed with the same state-file signing pattern. The sequence is incremented during `integrity-deploy` and verified during `integrity-verify`.

**Rationale**: Storing the sequence outside the manifest prevents an attacker from rolling back both the manifest and its sequence in one operation. The sequence file is signed, so modification without the HMAC key is detected. The known limitation (ADV-001: same-user attacker has the key) means rollback detection only works against external attackers, not same-user compromise. This is documented in the spec's Known Limitations section.

**Alternatives considered**:
- Store sequence in a git-signed commit: Strongest (git object hashes are content-addressed), but requires the operator to commit after every deploy. Operationally heavy.
- Store sequence in the Keychain itself: macOS Keychain can store arbitrary data, but it would be unusual and hard to inspect.
- Monotonic clock (hardware counter): Not available on consumer macOS hardware.

## R-007: Protected File List Expansion

**Decision**: Add these files to the protected file list in `scripts/lib/integrity.sh`:

| File | Category | Rationale |
|------|----------|-----------|
| `~/.openclaw/agents/*/models.json` | configuration | LLM routing — redirect to attacker-controlled model |
| `~/.openclaw/agents/*/.openclaw/workspace-state.json` | state | Session poisoning |
| `~/.openclaw/openclaw.json.bak*` | configuration | Rollback to weaker config |
| `~/.openclaw/restore-scripts/*` | script | Restore scripts at 755 could be attack vectors |
| `~/.openclaw/skill-allowlist.json` | governance | Already tracked but now HMAC-signed |
| `.claude/settings.local.json` | configuration | Claude Code permission allowlist (287 patterns) |
| `~/.openclaw/manifest-sequence.json` | state | Rollback detection counter |
| `~/.openclaw/agents/*/.git/hooks/*` | script | Git hooks execute arbitrary code |

**Rationale**: Each file was identified in the exhaustive file inventory (4 parallel research agents, 2026-03-24). Each can influence agent behavior, leak credentials, or weaken security posture if modified.

**Alternatives considered**:
- Protect entire ~/.openclaw/ directory recursively: Too broad — would lock writable data directories (sandboxes, session state) that the agent legitimately writes to.
- Protect via file permissions only (no uchg): Insufficient for same-user processes. uchg provides kernel-level enforcement.

## R-008: Enforcement Configuration Design

**Decision**: Store the enforcement configuration (which audit checks are enforced vs advisory) in `~/.openclaw/enforcement.json`, signed with HMAC, included in the protected file list. A minimum hardcoded set (sandbox enabled, manifest signature valid) cannot be disabled.

**Rationale**: Making enforcement configurable allows the system to mature — new checks can start as advisory (warn) and be promoted to enforced as confidence grows. The hardcoded minimum prevents the configuration from being used to completely disable security. Signing the file and including it in the protected set means an attacker cannot modify enforcement without detection.

**Alternatives considered**:
- All checks hardcoded as enforced: Too rigid — breaks development and debugging workflows.
- Environment variable overrides: Harder to audit than a configuration file.
- No enforcement (advisory only): Defeated the purpose of US7 (ADV-012).
