#!/bin/sh
# OpenClaw Mac — n8n Docker Secrets Entrypoint Wrapper
# See docs/HARDENING.md §4.3 for context
#
# n8n's _FILE suffix for N8N_ENCRYPTION_KEY has known bugs in queue mode.
# This entrypoint reads Docker secrets from /run/secrets/ and exports them
# as environment variables before starting n8n.
#
# References:
#   - R-001: N8N_ENCRYPTION_KEY _FILE bug
#   - https://github.com/n8n-io/n8n/issues/14596

set -e

# Read Docker secrets that don't support _FILE suffix reliably
if [ -f /run/secrets/n8n_encryption_key ]; then
  N8N_ENCRYPTION_KEY="$(cat /run/secrets/n8n_encryption_key)"
  export N8N_ENCRYPTION_KEY
fi

# M3: Install n8n-nodes-playwright into ~/.n8n/nodes/ on first boot.
# Community nodes must be in ~/.n8n/nodes/ for n8n 2.x to detect them.
# ~/.n8n is a Docker volume (persists across restarts), so this runs once.
# We use npm install --ignore-scripts (package enforces pnpm via preinstall).
NODES_DIR="/home/node/.n8n/nodes"
PW_PKG="${NODES_DIR}/node_modules/n8n-nodes-playwright"
if [ ! -d "${PW_PKG}" ]; then
  mkdir -p "${NODES_DIR}"
  cd "${NODES_DIR}"
  npm install --cache /tmp/npm-cache --ignore-scripts n8n-nodes-playwright 2>&1
  echo "Installed n8n-nodes-playwright into ~/.n8n/nodes/"
fi

# Ensure setup-browsers.js is replaced with no-op (prevents 500MB download loop).
# The n8n-nodes-playwright package setup script assumes Ubuntu (apt-get),
# downloads ALL browsers, and exit(1)s if any is missing.
# Browsers are pre-installed in the Docker image at build time.
SETUP_SCRIPT="${PW_PKG}/dist/nodes/scripts/setup-browsers.js"
if [ -f "${SETUP_SCRIPT}" ] && ! grep -q "skipped" "${SETUP_SCRIPT}" 2>/dev/null; then
  echo '"use strict"; console.log("Browser setup: skipped (pre-installed in Docker image)");' \
    > "${SETUP_SCRIPT}"
  echo "Replaced setup-browsers.js with no-op"
fi

# Copy pre-installed Chromium from image into volume if missing.
# Browsers are baked into the image at /home/node/node_modules/n8n-nodes-playwright/
BROWSERS_SRC="/home/node/node_modules/n8n-nodes-playwright/dist/nodes/browsers"
BROWSERS_DST="${PW_PKG}/dist/nodes/browsers"
if [ -d "${BROWSERS_SRC}" ] && [ ! -d "${BROWSERS_DST}/chromium-1148" ]; then
  mkdir -p "${BROWSERS_DST}"
  cp -r "${BROWSERS_SRC}"/* "${BROWSERS_DST}/"
  echo "Copied pre-installed browsers into volume"
fi

# Start n8n (replaces this shell process)
exec n8n start
