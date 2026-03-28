# openclaw-mac

Security hardening toolkit and audit tooling for headless AI agent
servers on macOS. Built for a Mac Mini running n8n orchestration with
OpenClaw, focusing on trust boundaries, credential isolation, and
integrity verification for autonomous agent deployments.

## What's Here

| Category | Description |
|----------|-------------|
| **[Hardening Guide](docs/HARDENING.md)** | Comprehensive macOS hardening guide (7,300+ lines) with NIST 800-53r5 mapping |
| **[Trust Gaps Analysis](docs/TRUST-GAPS.md)** | Where current agent security controls break down — and what protocol-level solutions (TEA/TSP) would fix |
| **[Deployment Observations](docs/HARDENING-OBSERVATIONS.md)** | Practitioner notes on what works, what needs workarounds, and what isn't possible |
| **[Getting Started](GETTING-STARTED.md)** | 15-minute step-by-step hardening walkthrough |
| **[Roadmap](ROADMAP.md)** | 5-milestone architecture with trust boundary diagrams |

## Project Scale

- **14,800+ lines** of bash across 39 scripts (8,200+ lines security-specific)
- **84-check** hardening audit covering macOS, n8n, Docker, OpenClaw, and CVE tracking
- **50 PASS / 0 FAIL** on macOS NIST 800-53r5 moderate baseline
- **14 feature specs** with full specification artifacts
- **146 commits** across 5 milestones

## Security Architecture

- **Credential isolation**: Agent holds LLM keys, orchestrator holds OAuth
  tokens — HMAC-SHA256 signed webhooks enforce the boundary
- **Workspace integrity**: 77 protected files with kernel-enforced
  immutability (`chflags uchg`), HMAC-signed manifests, continuous
  filesystem monitoring
- **Supply chain protection**: Content-hash skill allowlisting (not
  name-based) — responds to 1,184 malicious skills found on ClawHub
- **Container hardening**: Read-only rootfs, non-root user, all caps
  dropped, localhost-only networking
- **Adversarial testing**: 18-finding adversarial review with documented
  residual risks and honest bypass documentation

## Getting Started

Follow the step-by-step guide (works on both Apple Silicon and Intel):

- **[Getting Started](GETTING-STARTED.md)**

## Development Setup

```bash
git clone https://github.com/traylorre/openclaw-mac.git
cd openclaw-mac
npm install
```

`npm install` installs the markdown linter and configures a pre-push
git hook that runs it automatically before every push.

## Disclaimer

**Use at your own risk.** Hardening involves modifying system-level settings.
Always ensure you have a **Time Machine backup** before running scripts or
changing security policies. I am not responsible for locked accounts or
"bricked" OS installs.
