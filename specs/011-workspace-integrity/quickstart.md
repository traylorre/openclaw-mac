# Quickstart: Workspace Integrity

**Prerequisites**: M3 LinkedIn Automation infrastructure deployed (make agents-setup completed)

## 1. Enable Sandbox Mode

Add sandbox configuration to openclaw.json for both agents:

```bash
make sandbox-setup
```

## 2. Configure Skill Allowlist

Add approved skills before locking (hashes are included in manifest):

```bash
make skillallow-add NAME=linkedin-post
make skillallow-add NAME=linkedin-engage
make skillallow-add NAME=linkedin-activity
make skillallow-add NAME=config-update
make skillallow-add NAME=token-status
```

## 3. Lock Workspace Files

Deploy workspace files and set immutable flags:

```bash
# Deploys files, computes checksums, signs manifest, sets immutable flags
# Requires elevated privileges for chflags
sudo make integrity-lock
```

## 4. Start Monitoring Service

Install and start the file monitoring service:

```bash
make monitor-setup
# Verify: check heartbeat is recent
make monitor-status
```

## 5. Verify Everything

Run the full security audit:

```bash
make audit
# All CHK-OPENCLAW-INTEGRITY-* and CHK-OPENCLAW-SANDBOX-* checks should PASS
```

## Editing Workspace Files

```bash
# Unlock specific file for editing
sudo make integrity-unlock FILE=~/.openclaw/agents/linkedin-persona/SOUL.md

# Make your edits...

# Re-lock (updates checksums and manifest)
sudo make integrity-lock
```

## Operator Commands

| Command | Purpose |
| --- | --- |
| `sudo make integrity-lock` | Lock all workspace files, update manifest |
| `sudo make integrity-unlock FILE=<path>` | Unlock a specific file for editing |
| `make integrity-verify` | Run integrity check without starting the agent |
| `make monitor-setup` | Install and start the monitoring service |
| `make monitor-teardown` | Stop and remove the monitoring service |
| `make monitor-status` | Check monitoring service status and heartbeat |
| `make sandbox-setup` | Configure sandbox mode in openclaw.json |
| `make sandbox-teardown` | Disable sandbox mode |
| `make skillallow-add NAME=<name>` | Add a skill to the allowlist |
| `make skillallow-remove NAME=<name>` | Remove a skill from the allowlist |
| `make audit` | Full security audit including all new checks |
