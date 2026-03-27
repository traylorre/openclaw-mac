---
type: content-note
date: 2026-03-24
topic: container-integrity
hook: "`docker diff` — the zero-dependency drift detector nobody uses"
---

## The Tool

```bash
docker diff <container>
```

Output:

- `A /path` — file Added since container start
- `D /path` — file Deleted since container start
- `C /path` — file Changed since container start

That's it. Built into Docker. No Falco, no Sysdig, no agents, no subscriptions.

## Why Nobody Uses It

Enterprise security loves complexity. Falco monitors syscalls via eBPF. Sysdig Drift Control uses kernel-level instrumentation. Both are excellent. Both require deployment, configuration, and ongoing management.

`docker diff` runs from the host, returns in milliseconds, and tells you exactly what changed in the container's overlay filesystem since it started.

## The Catch

Changes in Docker volumes are NOT shown. Volumes are stored outside the container's overlay filesystem. So if an attacker writes to a mounted volume (like the n8n data directory), `docker diff` won't catch it.

This is why it's a layer, not the answer. Use it alongside credential enumeration, workflow comparison, and application-level integrity checks.

## Practical Implementation

```bash
# In a heartbeat monitoring cycle:
changes=$(docker diff n8n 2>/dev/null | grep -E '^[AD]' | grep -v '^C /tmp')
if [[ -n "$changes" ]]; then
    echo "ALERT: Container filesystem drift detected"
    echo "$changes"
fi
```

Add it to your pre-launch verification. Add it to your continuous monitoring heartbeat. It costs nothing and catches the things that more sophisticated tools also catch — just without the overhead.

## The Deeper Point

The best security control is the one you actually deploy. A simple check that runs every 30 seconds beats a sophisticated check that's still in your backlog.

## Tags

