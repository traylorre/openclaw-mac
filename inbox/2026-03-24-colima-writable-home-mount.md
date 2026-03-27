---
type: content-note
date: 2026-03-24
topic: container-security
hook: "Your container boundary is only as strong as your VM mount policy"
---

## The Finding

Colima (the macOS Docker runtime) mounts `$HOME` writable into the Linux VM by default. Empty `mounts: []` in colima.yaml = the entire home directory is read-write accessible from inside the VM.

## Why It Matters

Container escape doesn't land you on macOS. It lands you in the Colima Linux VM. But if the VM has writable access to `$HOME`, you have:

- `~/.ssh/` — lateral movement to every SSH-accessible server
- `~/.gnupg/` — sign commits as the operator
- `~/.zshrc` — persistence via shell initialization (survives container restarts, reboots, everything)
- Every credential, config, and integrity artifact the operator has

The container isolation (read-only rootfs, capabilities dropped, no-new-privileges) is doing its job. But the VM mount policy is the moat that was never built.

## The Fix

```yaml
# colima.yaml
mounts:
  - location: /Users/username
    writable: false
  - location: /Users/username/projects/project-dir
    writable: true
```

Explicit mounts. Read-only default. Writable only where needed.

## The Deeper Lesson

Defense in depth means every layer independently limits blast radius. When one layer's default configuration silently bypasses the protections of all inner layers, you don't have defense in depth — you have defense in decoration.

## Framework Alignment

- NIST SP 800-190: "Minimize host directories shared into containers"
- MITRE ATT&CK T1611: Escape to Host — "Monitor anomalous volume mounts"
- CIS Docker Benchmark 5.12: "Mount volumes read-only where possible"

## Tags

