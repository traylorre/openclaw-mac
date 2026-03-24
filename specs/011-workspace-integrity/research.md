# Research: Workspace Integrity (011)

**Date**: 2026-03-23
**Spec**: [spec.md](spec.md)

---

## R-001: macOS chflags behavior — schg vs uchg

### Decision

Use `uchg` (user immutable), not `schg` (system immutable), for workspace file protection.

### Rationale

**uchg (user immutable flag)**:
- Set by file owner or root: `chflags uchg <file>`
- Cleared by file owner or root in normal multi-user mode: `chflags nouchg <file>`
- Prevents deletion, modification, and renaming by any process (including root) while set
- Root can clear the flag without rebooting — practical for operator workflows

**schg (system immutable flag)**:
- Set by root only: `sudo chflags schg <file>`
- Cleared by root **only in single-user mode** — the `kern.securelevel` sysctl enforces this. On a running macOS system, `kern.securelevel` can be raised but never lowered. `sudo chflags noschg <file>` returns "Operation not permitted" in normal multi-user mode.
- On Apple Silicon Macs, single-user mode no longer exists in the traditional sense. Accessing it requires booting into Recovery Mode, downgrading to Permissive Security, and using Terminal from Recovery. This makes routine unlock/lock cycles (FR-002) impractical for daily operations.
- On Intel Macs with T2 chips, single-user mode is similarly restricted by firmware password and Secure Boot settings.

**Why uchg is the correct choice**: The spec's operator workflow (unlock specific file, edit, re-lock) must complete in under 30 seconds (SC-009). With `schg`, every unlock requires a full reboot into Recovery Mode — completely incompatible with the workflow. `uchg` provides the same immutability guarantee during normal operation (no non-root process can modify the file) while allowing root to manage flags in-place. The threat model already accepts root-level compromise as a residual risk (spec Accepted Residual Risks table), so `schg`'s additional protection against root is not load-bearing.

**Persistence**: Both `uchg` and `schg` flags are stored in APFS filesystem metadata and persist across reboots. They are properties of the inode, not ephemeral state. APFS snapshots capture the filesystem state including flags at the snapshot time, but snapshots are read-only copies — restoring from a snapshot would restore whatever flag state existed at snapshot time.

**macOS updates**: Major macOS updates can clear file flags on system volumes. User files in home directories are generally preserved, but this is not guaranteed. The spec's startup integrity check (FR-014) and continuous monitoring (FR-021) detect cleared flags regardless of cause, so a macOS update that clears flags is caught before the agent loads.

**SIP interaction**: System Integrity Protection (SIP) protects Apple system files, not user files. `chflags uchg` on files in `~/.openclaw/` is unaffected by SIP. SIP does not interfere with setting or clearing user immutable flags on user-owned files.

**sandbox-exec interaction**: `sandbox-exec` is a deprecated macOS command-line sandboxing tool using SBPL (Scheme-based) profiles. It restricts application access to system resources but operates at the syscall/Mach-level, not at the filesystem metadata level. A sandboxed process that is denied write access by `sandbox-exec` cannot write regardless of `chflags` state. Conversely, `sandbox-exec` does not grant bypass of `chflags` — the immutable flag is enforced by the VFS layer before sandbox policies are evaluated. A process inside `sandbox-exec` cannot clear `uchg` flags unless the sandbox profile permits the `chflags` syscall AND the process has appropriate ownership/privilege. Note: `sandbox-exec` is deprecated by Apple in favor of App Sandbox; it is not part of this feature's design.

### Alternatives Considered

| Alternative | Rejected Because |
|---|---|
| `schg` (system immutable) | Requires Recovery Mode reboot to clear on Apple Silicon. Incompatible with SC-009 (30s unlock/lock cycle). |
| POSIX `chmod 444` | Any process running as file owner or root can `chmod` back. No immutability guarantee. |
| macOS ACLs (`chmod +a`) | More granular but complex. Can be cleared by root. Does not provide true immutability — only permission restrictions. |
| `sandbox-exec` for agent process | Deprecated, undocumented SBPL profile format, may break across macOS updates. OpenClaw's native sandbox mode is the correct containment layer (R-002). |

### Source

- [chflags man page — SS64](https://ss64.com/mac/chflags.html)
- [Pro Terminal Commands: chflags — Apple Gazette](https://www.applegazette.com/mac/pro-terminal-commands-chflags-macos/)
- [Cannot unset schg on M1 Mac — Apple Developer Forums](https://developer.apple.com/forums/thread/675860)
- [Single-user mode on Apple Silicon — MacRumors Forums](https://forums.macrumors.com/threads/single-user-mode-on-apple-silicon.2269986/)
- [sandbox-exec overview — Igor's Techno Club](https://igorstechnoclub.com/sandbox-exec/)
- [macOS Sandbox Escapes — jhftss research](https://jhftss.github.io/A-New-Era-of-macOS-Sandbox-Escapes/)

---

## R-002: OpenClaw sandbox configuration

### Decision

Use OpenClaw's native JSON5 agent configuration with `sandbox.mode: "all"`, `workspaceAccess: "ro"`, `tools.fs.workspaceOnly: true`, and per-agent tool deny lists. The exact syntax is confirmed in OpenClaw's official documentation.

### Rationale

OpenClaw (confirmed in `/openclaw/openclaw` Context7 library, source reputation: High) provides a comprehensive per-agent sandbox configuration. The configuration lives in the agent's JSON5 config file (typically `openclaw.json` or the gateway configuration).

**Primary agent configuration**:

```json5
{
  agents: {
    list: [
      {
        id: "linkedin-persona",
        workspace: "~/.openclaw/agents/linkedin-persona/agent",
        sandbox: {
          mode: "all",       // Always sandboxed — every turn runs in sandbox
          scope: "agent",    // One sandbox container per agent
          workspaceAccess: "ro",  // Read-only workspace — agent cannot write to instruction files
        },
        tools: {
          fs: {
            workspaceOnly: true,  // All FS operations confined to workspace directory
          },
          allow: [
            "read",
            "sessions_list",
            "sessions_history",
            "sessions_send",
            "sessions_spawn",
            "session_status",
          ],
          deny: [
            "write",
            "edit",
            "apply_patch",
            "exec",
            "process",
            "browser",
          ],
        },
      },
    ],
  },
}
```

**Extraction agent configuration** (zero tools, zero skills):

```json5
{
  agents: {
    list: [
      {
        id: "extraction",
        workspace: "~/.openclaw/agents/extraction/agent",
        sandbox: {
          mode: "all",
          scope: "agent",
          workspaceAccess: "none",  // No workspace access at all
        },
        tools: {
          allow: [],  // Zero tools
          deny: [
            "read", "write", "edit", "apply_patch",
            "exec", "process", "browser", "canvas",
            "nodes", "cron", "gateway", "image",
          ],
        },
      },
    ],
  },
}
```

**Key findings from documentation**:
- `sandbox.mode` accepts `"all"` (always sandboxed), `"off"` (no sandbox), or per-session control
- `sandbox.scope: "agent"` means one Docker container per agent — agents cannot interfere with each other
- `workspaceAccess` accepts `"ro"` (read-only), `"rw"` (read-write), or `"none"` (no access)
- `tools.fs.workspaceOnly: true` confines ALL filesystem operations (read, write, edit, apply_patch) and native prompt image auto-loading strictly to the agent's workspace directory
- Tool deny lists use exact tool names: `write`, `edit`, `apply_patch`, `exec`, `process`, `browser`, `canvas`, `nodes`, `cron`, `gateway`, `image`
- The Docker backend on macOS (via Colima) is the container runtime for sandbox mode — this aligns with our existing Colima lifecycle management (feature 008)
- `sandbox.docker.setupCommand` allows one-time container setup after creation

**Exec approvals** (additional layer): OpenClaw also has a separate `exec-approvals.json` system for granular command execution control, with per-agent allowlists, safe bins, and security policies. This is complementary to the sandbox tool deny list — even if `exec` were allowed, individual commands would still require approval.

### Alternatives Considered

| Alternative | Rejected Because |
|---|---|
| macOS `sandbox-exec` with SBPL profiles | Deprecated by Apple. Undocumented profile format. Fragile across macOS updates. OpenClaw's native sandbox is purpose-built for this. |
| Docker-only isolation (no OpenClaw sandbox) | OpenClaw already runs in Docker when sandbox mode is enabled. Using Docker directly would bypass OpenClaw's tool restriction layer. |
| File permissions only (no sandbox) | Does not restrict tool access. Agent could still use `exec` to run arbitrary commands even if file writes are blocked. |

### Source

- OpenClaw documentation: `docs/gateway/security/index.md` (Context7 /openclaw/openclaw)
- OpenClaw documentation: `docs/gateway/configuration-reference.md` (Context7 /openclaw/openclaw)
- OpenClaw documentation: `docs/concepts/multi-agent.md` (Context7 /openclaw/openclaw)
- OpenClaw documentation: `docs/tools/exec.md` and `docs/tools/exec-approvals.md` (Context7 /openclaw/openclaw)

---

## R-003: macOS fswatch / FSEvents for file monitoring

### Decision

Use `fswatch` (installed via Homebrew) backed by macOS FSEvents API, managed by a launchd LaunchAgent (not LaunchDaemon) for continuous file monitoring.

### Rationale

**fswatch**:
- Cross-platform file change monitor. On macOS, it exclusively uses the FSEvents monitor backend (Apple's native filesystem events API).
- Install: `brew install fswatch`
- Current Homebrew version: 1.16.0+
- No known limitations on macOS. Scales to 500GB+ filesystems with no performance degradation over long periods.
- FSEvents monitors directory children recursively by default — the `--recursive` and `--directories` flags have no practical effect on macOS (FSEvents API already does this).
- Latency is configurable via `-l, --latency=DOUBLE` (seconds). Default latency is 1.0 second. This means fswatch batches events within a 1-second window before delivering them.
- The `darwin.eventStream.noDefer` property controls event delivery timing relative to the latency threshold — when set, events are delivered at the beginning of the latency window rather than deferred to the end.
- For our use case (monitoring ~20-50 files), latency of 1.0s is acceptable. The spec requires detection within 60 seconds (FR-022); sub-second latency is not needed.

**launchd integration**:
- The monitoring service MUST be a LaunchAgent (runs in user context), NOT a LaunchDaemon (runs as root in system context). This is critical for Keychain access (R-005).
- LaunchAgent plist goes in `~/Library/LaunchAgents/`.
- `KeepAlive: true` ensures launchd restarts the service if it crashes or is killed (FR-021).
- `RunAtLoad: true` starts the service when the user logs in.
- LaunchAgents start after login and FileVault unlock — this is correct for our use case (monitoring is meaningful only when the user is logged in and the filesystem is decrypted).

**Heartbeat pattern**: The monitoring script writes a timestamp to `~/.openclaw/monitor-heartbeat` at regular intervals (every 30 seconds). The startup integrity check and audit verify the heartbeat is recent (within 2x the interval = 60 seconds). A stale heartbeat indicates the monitor was killed or crashed and not restarted.

**Event handling**: On receiving a filesystem event, the monitor:
1. Re-computes the SHA-256 checksum of the changed file
2. Compares against the manifest
3. If mismatch: sends alert to operator via OpenClaw chat webhook
4. If match (benign touch or transient modify-restore): no alert

### Alternatives Considered

| Alternative | Rejected Because |
|---|---|
| `kqueue` directly | Requires one file descriptor per watched file. Does not scale. fswatch abstracts this away on macOS by using FSEvents instead. |
| Polling with `sha256sum` in a loop | Wastes CPU. Latency depends on poll interval. FSEvents is event-driven and efficient. |
| `launchd WatchPaths` | launchd can trigger a job when a path changes, but it only fires once per change batch and does not provide the continuous monitoring + heartbeat pattern we need. Better for one-shot triggers than continuous monitoring. |
| LaunchDaemon (root context) | Cannot access user's login Keychain without `security unlock-keychain`. LaunchAgent runs in user context and has natural Keychain access. |

### Source

- [fswatch GitHub repository](https://github.com/emcrisostomo/fswatch)
- [fswatch Monitors documentation](https://emcrisostomo.github.io/fswatch/doc/1.16.0/fswatch.html/Monitors.html)
- [fswatch on Homebrew](https://libraries.io/homebrew/fswatch)
- [FSEvents — Wikipedia](https://en.wikipedia.org/wiki/FSEvents)
- [Monitoring directory changes with fswatch](https://support.moonpoint.com/os/os-x/homebrew/fswatch.php)

---

## R-004: OpenClaw skill allowlist

### Decision

OpenClaw does not have a built-in "skill allowlist" in the sense of a curated list of approved skills identified by content hash. However, it does have an **exec approvals allowlist** and **tool deny lists** that can be combined to achieve equivalent supply chain control. The skill allowlist for content-hash-based approval (FR-026 through FR-029) must be implemented as a custom layer in the integrity manifest.

### Rationale

**What OpenClaw provides natively**:

1. **Exec approvals allowlist** (`exec-approvals.json`): Controls which binaries/commands the agent can execute. Per-agent policies with `security: "allowlist"` mode. Matches resolved binary paths, not basenames. Supports `autoAllowSkills: false` to prevent skills from automatically gaining exec permissions.

2. **Tool deny lists** (per-agent `tools.deny`): Prevents the agent from using specific tool categories (`exec`, `write`, `browser`, etc.). This is the primary containment — a malicious skill cannot invoke a denied tool.

3. **Safe bins configuration** (`tools.exec.safeBins`): Restricts which small stdin-only utilities are auto-approved. Explicitly warns against adding interpreter runtimes (`python3`, `node`, `bash`) to safe bins.

4. **`openclaw security audit`**: Warns about missing explicit profiles for interpreter/runtime safe bins entries.

**What OpenClaw does NOT provide**:

- No content-hash-based skill identity verification
- No skill version pinning mechanism
- No operator-controlled approval gate before skill installation
- No skill integrity monitoring after installation
- No built-in mechanism to reject a skill at load time based on a hash mismatch

**Custom implementation needed**: The integrity manifest (FR-026-029) must:
1. Record SHA-256 hashes of all installed skill files (SKILL.md and any associated code)
2. At agent startup, verify installed skill hashes against the manifest
3. Refuse to load any skill whose hash is not in the manifest or does not match
4. The lock/deploy workflow updates skill hashes when skills are intentionally installed or updated

This is implemented as part of the startup integrity check script (FR-014), not as an OpenClaw configuration option.

### Alternatives Considered

| Alternative | Rejected Because |
|---|---|
| Rely solely on OpenClaw's exec approvals | Controls command execution but not skill loading. A malicious skill that only reads files and sends data via allowed tools (sessions_send) would bypass exec restrictions. |
| Disable all skills | Eliminates the skill attack surface entirely but also eliminates all agent capabilities (posting, engagement, config updates). Not viable. |
| Use OpenClaw's `autoAllowSkills: false` only | Prevents skills from auto-approving exec commands but does not verify skill file integrity or prevent malicious skill installation. Necessary but not sufficient. |

### Source

- OpenClaw documentation: `docs/tools/exec.md` (Context7 /openclaw/openclaw)
- OpenClaw documentation: `docs/tools/exec-approvals.md` (Context7 /openclaw/openclaw)
- OpenClaw documentation: `docs/cli/approvals.md` (Context7 /openclaw/openclaw)
- OpenClaw documentation: `docs/platforms/macos.md` (Context7 /openclaw/openclaw)

---

## R-005: macOS Keychain CLI for HMAC signing keys

### Decision

Store the manifest HMAC signing key in the macOS login Keychain as a generic password item using the `security` CLI. Access from a launchd LaunchAgent (user context) works without additional unlock steps. Access from launchd LaunchDaemons or sudo-executed scripts requires special handling.

### Rationale

**Storing the key**:

```bash
# Generate a 32-byte hex-encoded HMAC key
HMAC_KEY=$(openssl rand -hex 32)

# Store in login Keychain
security add-generic-password \
  -a "$(whoami)" \
  -s "com.openclaw.manifest-hmac" \
  -j "HMAC signing key for workspace integrity manifest" \
  -w "$HMAC_KEY"
```

- `-a`: Account name (current user)
- `-s`: Service name (unique identifier for this credential)
- `-j`: Comment/description
- `-w`: Password value (the hex-encoded HMAC key)

**Retrieving the key**:

```bash
HMAC_KEY=$(security find-generic-password \
  -a "$(whoami)" \
  -s "com.openclaw.manifest-hmac" \
  -w)
```

The `-w` flag returns only the password value, suitable for piping into signing operations.

**Key format**: The HMAC key is stored as a 64-character hex string (32 bytes). Hex encoding avoids binary data issues with the Keychain CLI, which expects string values. The signing operation decodes hex to binary for HMAC computation:

```bash
echo -n "$manifest_content" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:${HMAC_KEY}"
```

**Access from launchd LaunchAgents**: LaunchAgents run in the user's login session context. The login Keychain is automatically unlocked when the user logs in (it uses the login password). A LaunchAgent can call `security find-generic-password` without additional unlock steps, provided:
1. The Keychain item's access control list (ACL) permits the calling binary
2. The first access may trigger a macOS prompt asking the user to allow access — this can be pre-approved by adding the binary to the ACL with `security set-generic-password-partition-list`

**Access from sudo-executed scripts**: When a script runs via `sudo`, it runs as root. Root does NOT automatically have access to the user's login Keychain. Two approaches:
1. Run the signing operation as the original user (not sudo), then pass the result to the privileged operation
2. Use `security unlock-keychain -p <password> ~/Library/Keychains/login.keychain-db` — but this requires the user's login password, which is impractical for automation

**Chosen approach**: The manifest signing operation (which needs the HMAC key) runs as the current user, BEFORE the privileged `chflags` operations. The workflow is:
1. Compute checksums (user context)
2. Sign the manifest with HMAC key from Keychain (user context)
3. `sudo chflags uchg` on protected files (elevated context — does not need Keychain)

This avoids the Keychain-from-sudo problem entirely.

**Access from launchd LaunchDaemons**: LaunchDaemons run as root outside any user session. They CANNOT access the user's login Keychain. The Data Protection keychain (modern macOS) is only available to processes in a user context. For daemons, the recommendation is to use the System Keychain or IPC (XPC) to a user-context agent. Since our monitoring service is a LaunchAgent (R-003), this is not an issue.

### Alternatives Considered

| Alternative | Rejected Because |
|---|---|
| Store key in a file (`~/.openclaw/hmac.key`) | File-based keys are accessible to any process running as the user. Defeats the purpose — an attacker who can modify files could also read the key and re-sign a tampered manifest. |
| Store key in environment variable | Environment variables are visible to all child processes and in `/proc`. Worse than file storage. |
| Use macOS System Keychain | Requires root to access. Would work for LaunchDaemons but not for user-context operations. Unnecessarily complex. |
| Use 1Password CLI or other password manager | Adds external dependency. macOS Keychain is built-in and sufficient. |
| Store key in Secure Enclave via CryptoKit | Requires Swift/Objective-C code. Keys in Secure Enclave cannot be exported — would need to implement signing in native code. Over-engineered for this threat model. |

### Source

- [security command — SS64](https://ss64.com/mac/security.html)
- [security password commands — SS64](https://ss64.com/mac/security-password.html)
- [Storing generic passwords in macOS Keychain — jpmens.net](https://jpmens.net/2021/04/18/storing-passwords-in-macos-keychain/)
- [Using the OS X Keychain — netmeister.org](https://www.netmeister.org/blog/keychain-passwords.html)
- [launchctl LaunchDaemons and keychain access — Apple Developer Forums](https://developer.apple.com/forums/thread/685967)
- [Claude Code CLI over SSH — Keychain access fix](https://phoenixtrap.com/2025/10/26/claude-code-cli-over-ssh-on-macos-fixing-keychain-access/)

---

## R-006: NemoClaw filesystem policies

### Decision

Adopt NemoClaw's filesystem policy model as the reference architecture: writable paths explicitly listed, all other paths read-only. The exact enforcement mechanism differs (NemoClaw uses Landlock LSM in a Linux container; our implementation uses OpenClaw's native sandbox mode on macOS).

### Rationale

**NemoClaw architecture** (from NVIDIA documentation):

- Sandbox runs the `ghcr.io/nvidia/openshell-community/sandboxes/openclaw` container image
- The sandbox process runs as a dedicated `sandbox` user and group (not root)
- Filesystem policy from `openclaw-sandbox.yaml`:

  | Path | Access |
  |---|---|
  | `/sandbox` | Read-write |
  | `/tmp` | Read-write |
  | `/dev/null` | Read-write |
  | `/usr` | Read-only |
  | `/lib` | Read-only |
  | `/proc` | Read-only |
  | `/dev/urandom` | Read-only |
  | `/app` | Read-only |
  | `/etc` | Read-only |
  | `/var/log` | Read-only |
  | Everything else | Denied |

- Network egress is controlled by a separate whitelist in the same policy file — only endpoints listed in the policy are reachable. Unlisted hosts are blocked and surfaced in the TUI for operator approval.
- Enforcement: Landlock LSM (Linux Security Module) on a "best-effort basis" — meaning it applies where the kernel supports it but does not hard-fail if Landlock is unavailable.

**Policy file structure** (`nemoclaw-blueprint/policies/openclaw-sandbox.yaml`):
- The exact YAML schema is not publicly documented in full. The documentation references the [OpenShell Policy Schema](https://docs.nvidia.com/openshell/latest/reference/policy-schema.html) for the complete specification.
- The file contains `network` and `filesystem` sections
- Network section defines endpoint groups with: `endpoints` (host:port pairs), `binaries` (executables allowed to use the endpoint), `rules` (HTTP methods and paths permitted)
- Filesystem section defines path access levels
- Preset files in `nemoclaw-blueprint/policies/presets/` serve as templates

**Mapping to our implementation**:

| NemoClaw Concept | Our Implementation |
|---|---|
| `/sandbox` (writable) | `~/.openclaw/agents/<id>/data/` (writable data directory for pending-drafts.json, session state) |
| `/tmp` (writable) | Agent's temp directory within sandbox container |
| `/app` (read-only) | `~/.openclaw/agents/<id>/agent/` (workspace — SOUL.md, AGENTS.md, etc.) |
| Landlock LSM | OpenClaw `sandbox.mode: "all"` + `workspaceAccess: "ro"` + `tools.fs.workspaceOnly: true` |
| Dedicated `sandbox` user | Not implemented (deferred — spec finding #21). Agent runs as operator user, contained by OpenClaw sandbox. |
| Network egress whitelist | Not directly applicable — our agent's network access goes through n8n webhooks, not direct egress. |

### Alternatives Considered

| Alternative | Rejected Because |
|---|---|
| Replicate NemoClaw's exact Landlock enforcement | Landlock is Linux-only. Our host is macOS. OpenClaw's sandbox mode provides equivalent containment on macOS via Docker. |
| Run NemoClaw directly | NemoClaw is designed for NVIDIA cloud inference. Our setup uses local LLM providers (Gemini, Anthropic, Ollama) with n8n orchestration. Different architecture. |
| Ignore NemoClaw's model | NemoClaw is the only production-validated sandbox for OpenClaw. Its path separation (writable data vs. read-only instructions) is a proven pattern. |

### Source

- [NemoClaw — How it Works](https://docs.nvidia.com/nemoclaw/latest/about/how-it-works.html)
- [NemoClaw — Architecture Reference](https://docs.nvidia.com/nemoclaw/latest/reference/architecture.html)
- [NemoClaw — Network Policies Reference](https://docs.nvidia.com/nemoclaw/latest/reference/network-policies.html)
- [NemoClaw — Customize Network Policy](https://docs.nvidia.com/nemoclaw/latest/network-policy/customize-network-policy.html)
- Context7 library: /websites/nvidia_nemoclaw (source reputation: High, benchmark: 76.3)

---

## R-007: OpenClaw SECURITY.md environment variable hardening

### Decision

OpenClaw does not document specific protections against `LD_PRELOAD`, `DYLD_INSERT_LIBRARIES`, or `NODE_OPTIONS` injection. The startup integrity check must implement environment variable validation independently.

### Rationale

**What was found in OpenClaw documentation** (Context7 search across /openclaw/openclaw):

- `OPENCLAW_NO_RESPAWN=1`: Controls whether OpenClaw respawns child processes. Used in systemd service configurations for stability.
- `NODE_COMPILE_CACHE`: Performance optimization for Node.js module compilation caching.
- `OPENCLAW_IMAGE`, `OPENCLAW_GATEWAY_TOKEN`, `OPENCLAW_GATEWAY_BIND`, `OPENCLAW_GATEWAY_PORT`: Standard configuration environment variables.
- `OPENCLAW_CONFIG_DIR`, `OPENCLAW_WORKSPACE_DIR`: Directory configuration.
- `${VAR_NAME}` substitution syntax in JSON5 configuration files.
- `GOG_KEYRING_PASSWORD`, `XDG_CONFIG_HOME`: Infrastructure variables.

**What was NOT found**:
- No `SECURITY.md` file documenting environment variable hardening
- No documentation about `LD_PRELOAD` protection
- No documentation about `DYLD_INSERT_LIBRARIES` protection
- No documentation about `NODE_OPTIONS` sanitization
- No startup security checks for dangerous environment variables
- No environment variable validation framework

**Why this matters**: On macOS, `DYLD_INSERT_LIBRARIES` is the equivalent of Linux's `LD_PRELOAD` — it forces the dynamic linker to load arbitrary shared libraries into every spawned process. An attacker who sets this variable can intercept any library call. `NODE_OPTIONS` can inject arbitrary flags into the Node.js runtime (OpenClaw runs on Bun, but skills or subprocesses may use Node). These are classic privilege escalation vectors.

**Implementation for FR-019**: The startup integrity check script must verify:

```bash
# Dangerous environment variables that should be unset
DANGEROUS_VARS=(
  "LD_PRELOAD"
  "DYLD_INSERT_LIBRARIES"
  "DYLD_LIBRARY_PATH"
  "DYLD_FRAMEWORK_PATH"
  "NODE_OPTIONS"
  "NODE_EXTRA_CA_CERTS"
  "ELECTRON_RUN_AS_NODE"
  "BUN_INSTALL"
)

for var in "${DANGEROUS_VARS[@]}"; do
  if [[ -n "${!var:-}" ]]; then
    log_error "FAIL: Dangerous environment variable ${var} is set"
    exit 1
  fi
done
```

**macOS-specific note**: macOS System Integrity Protection (SIP) already strips `DYLD_INSERT_LIBRARIES` from processes with special entitlements, but this only applies to Apple-signed system binaries. User-installed software (including OpenClaw/Bun) is NOT protected by SIP's dyld variable stripping. The startup check is necessary.

### Alternatives Considered

| Alternative | Rejected Because |
|---|---|
| Rely on SIP to strip DYLD variables | SIP only strips DYLD variables for Apple-signed system binaries. OpenClaw is user-installed software. |
| Set environment variables in launchd plist only | Ensures the agent starts clean but does not detect if the operator's shell environment is compromised. Belt-and-suspenders: check at startup regardless of launch method. |
| Patch OpenClaw to add env var validation | Upstream modification. Out of scope. Our startup wrapper script handles this before OpenClaw launches. |

### Source

- OpenClaw documentation: `docs/platforms/raspberry-pi.md`, `docs/vps.md`, `docs/install/gcp.md`, `docs/help/environment.md` (Context7 /openclaw/openclaw)
- [macOS Security and Privacy Guide — drduh](https://github.com/drduh/macOS-Security-and-Privacy-Guide)
- macOS `dyld` man page (documents DYLD_INSERT_LIBRARIES behavior and SIP stripping)

---

## R-008: Pending-drafts.json validation

### Decision

Implement JSON schema validation for `pending-drafts.json` at agent startup, enforcing the Content Draft entity schema from the 010-linkedin-automation data model. Validation rejects any file that contains unexpected keys, non-string content fields, or structural anomalies that could be used for prompt injection.

### Rationale

**Current BOOT.md behavior** (from `/Users/scotthazlett/projects/openclaw-mac/openclaw/BOOT.md`):

The BOOT.md startup sequence:
1. Reads `~/.openclaw/agents/linkedin-persona/pending-drafts.json`
2. For each entry with `status: "presented"`: presents the draft content to the operator and waits for response (approve, edit, discard)
3. After handling pending drafts: checks n8n reachability, reports status
4. If no pending drafts and system is healthy: greets the operator

**The injection risk**: BOOT.md instructs the agent to read pending-drafts.json and present its `content` field to the operator. If an attacker modifies pending-drafts.json to include prompt injection payloads in the `content` field (or adds unexpected fields that get interpolated into the agent's context), the agent would execute them on the next startup. This is the "writable data directory injection" attack (spec adversarial finding #7, FR-012).

**Expected schema** (derived from 010-linkedin-automation data model, Entity: Content Draft):

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "array",
  "items": {
    "type": "object",
    "required": ["id", "type", "content", "status", "created_at"],
    "properties": {
      "id": { "type": "string", "pattern": "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$" },
      "type": { "type": "string", "enum": ["post", "comment", "like", "image_post", "article_share"] },
      "content": { "type": "string", "maxLength": 3000 },
      "image_path": { "type": ["string", "null"] },
      "target_urn": { "type": ["string", "null"], "pattern": "^urn:li:" },
      "status": { "type": "string", "enum": ["drafted", "presented", "approved", "rejected", "published", "failed"] },
      "created_at": { "type": "string", "format": "date-time" },
      "presented_at": { "type": ["string", "null"], "format": "date-time" },
      "resolved_at": { "type": ["string", "null"], "format": "date-time" },
      "revision_count": { "type": "integer", "minimum": 0 },
      "scheduled_at": { "type": ["string", "null"], "format": "date-time" }
    },
    "additionalProperties": false
  },
  "maxItems": 50
}
```

**Validation rules**:
1. File must be valid JSON (reject malformed files)
2. Top-level structure must be an array
3. Each item must conform to the Content Draft schema
4. `additionalProperties: false` — reject any unexpected keys (prevents smuggling of instruction-like fields such as `system_prompt`, `instructions`, `role`)
5. `content` field max length of 3000 characters (LinkedIn post limit is 3000; longer values are suspicious)
6. `maxItems: 50` — reject files with implausible numbers of pending drafts
7. `id` must be a valid UUID format
8. `target_urn` must match LinkedIn URN format if present
9. No nested objects or arrays within the content field (prevents structured injection)

**Implementation approach**: Use `jq` for validation in the startup script (already a project dependency). `jq` can validate JSON structure, check types, verify enum values, and enforce constraints. For the full JSON Schema validation, a lightweight tool like `ajv-cli` (Node.js) or `check-jsonschema` (Python) could be used, but `jq` is sufficient for the critical structural checks without adding dependencies.

**BOOT.md does NOT validate**: The current BOOT.md simply reads the file and presents entries. There is no validation step. The startup integrity check script (FR-014) must validate BEFORE BOOT.md executes — which is guaranteed by the design where the integrity check script launches the agent directly after passing (FR-014, addressing the TOCTOU race from adversarial finding #3).

### Alternatives Considered

| Alternative | Rejected Because |
|---|---|
| Trust pending-drafts.json without validation | The file is in the writable data directory. Any process running as the user can modify it. Without validation, it is a prompt injection vector. |
| Move pending-drafts.json to the protected workspace | Would require making it immutable, but the agent legitimately needs to write to it (updating draft status). Would break the core workflow. |
| Validate inside BOOT.md (agent-side) | The agent is the entity we are protecting FROM. If the agent is compromised (which is the threat model), agent-side validation is bypassed. Validation must happen in the host-side startup script before the agent launches. |
| Use a database instead of JSON file | Over-engineered. The file contains at most a handful of pending drafts. JSON with validation is appropriate. |

### Source

- `/Users/scotthazlett/projects/openclaw-mac/openclaw/BOOT.md` (local file)
- `/Users/scotthazlett/projects/openclaw-mac/specs/010-linkedin-automation/data-model.md` (local file, Entity: Content Draft)
- Spec adversarial review finding #7 (writable data dir injection)
- [JSON Schema specification — json-schema.org](https://json-schema.org/draft/2020-12/json-schema-core)
