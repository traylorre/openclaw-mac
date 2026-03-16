# openclaw-mac

macOS hardening guides and audit tooling for a Mac Mini running n8n
orchestration with Apify integrations.

## Getting Started

Follow the step-by-step guide for your hardware:

- **[Apple Silicon Mac Mini](GETTING-STARTED.md)** (M1, M2, M3, M4)
- Intel Mac Mini (coming soon)

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
