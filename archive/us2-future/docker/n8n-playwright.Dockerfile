# n8n-playwright.Dockerfile — Custom n8n image with Playwright support for LinkedIn feed discovery
# Extends official n8n image with Chromium browser and system dependencies
#
# The official n8n:latest uses Docker Hardened Images (Alpine 3.22) which strips
# the apk package manager. We restore it from a standard Alpine image to install
# Chromium system libraries, then remove apk to preserve the hardened posture.
#
# The n8n-nodes-playwright community node has a setup-browsers.js script that:
#   1. Tries apt-get install (fails on Alpine)
#   2. Downloads ALL browsers (Chromium + Firefox + WebKit, ~500MB)
#   3. Exits with error if any browser is missing
# We replace it with a no-op since we pre-install Chromium at build time.
#
# Build: docker build -t openclaw-n8n:latest -f docker/n8n-playwright.Dockerfile .
# Usage: Referenced in docker-compose.yml as image: openclaw-n8n:latest

# Stage 1: Source for apk package manager (stripped from hardened n8n image)
FROM alpine:3.22 AS apk-source

# Stage 2: n8n hardened image + Chromium
FROM docker.n8n.io/n8nio/n8n:latest

USER root

# Restore apk from standard Alpine (hardened image removes it)
COPY --from=apk-source /sbin/apk /sbin/apk
COPY --from=apk-source /etc/apk/ /etc/apk/
COPY --from=apk-source /lib/apk/ /lib/apk/

# Install system dependencies required by Playwright/Chromium
# chromium: pulls in nss, freetype, harfbuzz, cairo, pango, etc. as deps
# ttf-freefont, font-noto-cjk: fonts for page rendering
# dbus, xvfb: display server for headed mode (if needed)
RUN apk add --no-cache \
    chromium \
    nss \
    freetype \
    harfbuzz \
    ca-certificates \
    ttf-freefont \
    font-noto-cjk \
    dbus \
    xvfb \
    && rm -f /sbin/apk \
    && rm -rf /etc/apk /lib/apk

# Install n8n-nodes-playwright community node
USER node

RUN cd /home/node && \
    npm install n8n-nodes-playwright

# Pre-install Playwright Chromium browser into the node's browsers dir.
# This is where the package looks for browsers at runtime.
RUN PLAYWRIGHT_BROWSERS_PATH=/home/node/node_modules/n8n-nodes-playwright/dist/nodes/browsers \
    npx --yes playwright install chromium

# Replace the setup-browsers.js startup script with a no-op.
# The original script assumes Ubuntu (apt-get), downloads ALL browsers
# (~500MB including Firefox/WebKit we don't need), and exits(1) if any
# browser is missing. Since we pre-installed Chromium above, skip it all.
RUN echo '"use strict"; console.log("Browser setup: skipped (pre-installed in Docker image)");' \
    > /home/node/node_modules/n8n-nodes-playwright/dist/nodes/scripts/setup-browsers.js

# Set runtime env vars
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

# Runtime user
USER node

# Expose n8n default port
EXPOSE 5678

# n8n entrypoint is inherited from base image
