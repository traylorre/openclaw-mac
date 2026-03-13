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

# Start n8n (replaces this shell process)
exec n8n start
