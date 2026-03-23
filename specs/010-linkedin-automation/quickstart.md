# Quickstart: LinkedIn Automation (010)

**Date**: 2026-03-21
**Spec**: [spec.md](spec.md)
**Plan**: [plan.md](plan.md)

## Prerequisites

- M1 (Gateway Live) complete — n8n running in Docker via Colima
- M2 (Security Baseline) complete — hardening audit passes
- Benefactor has provided: LinkedIn account (profile complete), LinkedIn developer app (Share on LinkedIn enabled), chat platform preference, content direction

## Developer Setup

### 1. Install OpenClaw

```bash
# Install Bun (if not already installed)
curl -fsSL https://bun.sh/install | bash

# Install OpenClaw globally
bun install -g openclaw

# Verify installation
openclaw --version
```

### 2. Configure OpenClaw Agent

```bash
# Initialize agent workspace
openclaw agent create linkedin-persona

# Configure LLM providers
export GEMINI_API_KEY="<key>"
export ANTHROPIC_API_KEY="<key>"

# Set model config (Gemini primary, Anthropic fallback, Ollama local)
openclaw models set google/gemini-3.1-pro-preview
```

Edit `~/.openclaw/openclaw.json` to add fallback providers and chat channel config.

### 3. Configure Chat Channel

```bash
# Telegram (recommended)
openclaw channels add telegram
# Provide BotFather token when prompted

# OR WhatsApp (if benefactor prefers)
openclaw channels add whatsapp
# Scan QR code when prompted
```

### 4. Build Custom n8n Docker Image

```bash
# Build n8n image with Playwright support
cd /path/to/openclaw-mac
docker build -t openclaw-n8n:latest -f docker/n8n-playwright.Dockerfile .

# Restart n8n with new image
docker compose down && docker compose up -d
```

### 5. Set Up HMAC Webhook Secret

```bash
# Generate shared secret
WEBHOOK_SECRET=$(openssl rand -hex 32)

# Set in OpenClaw environment
echo "N8N_WEBHOOK_SECRET=$WEBHOOK_SECRET" >> ~/.openclaw/.env

# Set in n8n environment
# Add OPENCLAW_WEBHOOK_SECRET to docker-compose.yml environment section
```

### 6. Import n8n Workflows

```bash
# Import all workflows from repo
docker exec -u node openclaw-n8n n8n import:workflow --separate --input=/workflows/

# Set up n8n Custom Variables via API for operating configuration
# (discovery schedule, volume limits, quiet hours, warmup mode)
```

### 7. Configure LinkedIn OAuth

```bash
# In n8n UI: Settings > Credentials > Create New > OAuth2
# - Client ID: from LinkedIn developer app
# - Client Secret: from LinkedIn developer app
# - Authorization URL: https://www.linkedin.com/oauth/v2/authorization
# - Token URL: https://www.linkedin.com/oauth/v2/accessToken
# - Scope: w_member_social
# Complete the browser authorization flow
```

### 8. Set Up Workspace Files

Copy workspace templates from repo to OpenClaw agent workspace:

```bash
cp openclaw/SOUL.md ~/.openclaw/agents/linkedin-persona/agent/SOUL.md
cp openclaw/AGENTS.md ~/.openclaw/agents/linkedin-persona/agent/AGENTS.md
cp openclaw/BOOT.md ~/.openclaw/agents/linkedin-persona/agent/BOOT.md
# Edit files with benefactor-specific content direction
```

### 9. Initialize Manifest Checksums

```bash
# Compute and store initial checksums for workspace files
make manifest-update
```

### 10. Verify

```bash
# Run hardening audit (should include new CHK-OPENCLAW-* checks)
make audit

# Send a test message via chat
# "Draft a test post about autonomous racing"
# Verify draft appears, approve it, confirm it posts to LinkedIn
```

## Key Files

| File | Purpose |
|------|---------|
| `workflows/*.json` | n8n workflow definitions (version-controlled) |
| `openclaw/SOUL.md` | Persona voice template |
| `openclaw/AGENTS.md` | Operating rules template |
| `openclaw/BOOT.md` | Restart recovery sequence |
| `docker/n8n-playwright.Dockerfile` | Custom n8n image with Playwright |
| `scripts/hardening-audit.sh` | Extended with CHK-OPENCLAW-* checks |

## Smoke Test

1. Send chat message: "Draft a post about autonomous racing technology"
2. Review draft in chat
3. Approve: "approve"
4. Verify post appears on LinkedIn
5. Run `make audit` — all checks should pass
