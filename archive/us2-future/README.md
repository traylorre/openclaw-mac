# US2 Future Scope — Archived Artifacts

These files are deferred US2 (feed discovery + engagement) artifacts that
affect the build/deploy pipeline and cannot remain in their original
locations while inactive.

Preserved here for future activation.

## Contents

- `docker/n8n-playwright.Dockerfile` — Custom n8n Docker image with
  Playwright system dependencies and n8n-nodes-playwright community node.
  Originally at `docker/n8n-playwright.Dockerfile`.

- `openclaw-extractor/` — Extraction agent workspace files (SOUL.md,
  AGENTS.md, IDENTITY.md). Quarantined zero-tool agent for processing
  untrusted feed content (Rule of Two, R-012).
  Originally at `openclaw-extractor/`.

## When to restore

When US2 (community engagement) implementation begins:

1. Copy `docker/n8n-playwright.Dockerfile` to repo root `docker/`
2. Copy `openclaw-extractor/` to repo root
3. Re-enable `docker-image-setup` target in Makefile
4. Re-enable `check_openclaw_extraction_agent` in audit run list
5. Run full adversarial review
