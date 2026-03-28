# Dependency Update Procedure

INTERNAL -- Operator Reference Only

Step-by-step procedures for updating each pipeline dependency (n8n, OpenClaw,
Ollama) with pre-update verification, update commands, post-update verification,
rollback, and post-rollback CVE re-check.

Requirement traceability: FR-005, SC-006, US4.

---

## n8n Docker Image Update

Current pinned version: `docker.n8n.io/n8nio/n8n:2.13.0`
(see `scripts/templates/docker-compose.yml` line 20).

### 1. Pre-Update

Record the current version and image digest, then tag the running image so it
is preserved locally for rollback even after `docker compose pull` replaces it.

```bash
# Record current version
docker exec openclaw-n8n n8n --version

# Record current image digest
docker inspect --format='{{index .RepoDigests 0}}' openclaw-n8n

# Tag current image for rollback
docker tag docker.n8n.io/n8nio/n8n:2.13.0 openclaw-n8n-rollback:prev
```

Check the CVE registry (`data/cve-registry.json`) for any CVEs that affect the
current version but are patched in the target version.

### 2. Update

Edit the image tag in `scripts/templates/docker-compose.yml`:

```yaml
# Before
image: docker.n8n.io/n8nio/n8n:2.13.0

# After (example)
image: docker.n8n.io/n8nio/n8n:2.15.0
```

Pull and restart. The `--no-deps` flag avoids restarting unrelated services.

```bash
cd scripts/templates
docker compose pull n8n
docker compose up -d --no-deps n8n
```

### 3. Post-Update Verification

Re-baseline the integrity manifest and run the full audit. The `--force` flag
skips the first-run interactive confirmation prompt (Make does not forward
arguments, so call the script directly).

```bash
bash scripts/integrity-deploy.sh --force
make audit
```

Confirm the audit output shows:

- CVE checks: PASS for the new n8n version
- Container hardening: PASS (read-only rootfs, non-root, caps dropped)
- Image digest recorded in manifest

### 4. Rollback

If the new version introduces regressions, restore the tagged rollback image.

```bash
# Restore docker-compose.yml to the previous tag
# (git checkout or manual edit)

# Retag rollback image
docker tag openclaw-n8n-rollback:prev docker.n8n.io/n8nio/n8n:2.13.0

# Restart with previous version
cd scripts/templates
docker compose up -d --no-deps n8n

# Re-baseline and verify
bash scripts/integrity-deploy.sh --force
make audit
```

After rollback, the CVE checks will flag any vulnerabilities present in the
rolled-back version. The operator can make an informed decision to accept the
risk temporarily.

### 5. Digest Pinning (Recommended)

For stronger supply chain integrity, pin the image by digest in addition to tag.
This prevents tag mutation attacks where a registry tag is overwritten with a
different image.

```yaml
image: docker.n8n.io/n8nio/n8n:2.13.0@sha256:<digest>
```

To obtain the digest after a pull:

```bash
docker inspect --format='{{index .RepoDigests 0}}' docker.n8n.io/n8nio/n8n:2.13.0
```

---

## OpenClaw Update

Current pinned version: `>= 2026.3.13`.

### 1. Pre-Update

Record the current installed version and binary location.

```bash
openclaw --version
which openclaw
```

The OpenClaw binary location is not pinned in the codebase. Document the path
returned by `which openclaw` before updating so rollback can target the correct
file.

### 2. Update

Download the new version from the official source and install it.

**Residual risk (FR-027)**: OpenClaw does not provide binary signature
verification or provenance attestation. There is no way to cryptographically
verify that a downloaded binary is authentic. This is a documented residual
risk under ASI04 (Supply Chain). Mitigation: download only from the official
release page, verify the release SHA-256 checksum if published, and monitor
release notes for security advisories.

```bash
# Back up current binary
cp "$(which openclaw)" /tmp/openclaw-backup

# Install new version per OpenClaw release instructions
# (Exact command depends on installation method)
```

### 3. Post-Update Verification

Re-baseline and audit.

```bash
bash scripts/integrity-deploy.sh --force
make audit
```

Confirm the audit output shows:

- CVE checks: PASS for the new OpenClaw version against all 8 known CVEs
- Sandbox mode: PASS
- Workspace integrity: PASS

### 4. Rollback

Restore the backed-up binary.

```bash
# Restore previous binary
cp /tmp/openclaw-backup "$(which openclaw)"
chmod +x "$(which openclaw)"

# Re-baseline and verify
bash scripts/integrity-deploy.sh --force
make audit
```

After rollback, the CVE checks will flag any reintroduced vulnerabilities.

### 5. Version Tracking

The manifest does not currently pin the OpenClaw binary path or hash. Version
currency is verified at audit time via `openclaw --version` against the CVE
registry. This is a known limitation -- the binary is the most privileged
component, yet its integrity cannot be verified by the tools it provides.

---

## Ollama Model Update

Default model: `gemma3:4b` (configurable via `OLLAMA_MODEL` environment
variable; see `scripts/integrity-deploy.sh` line 344).

### 1. Pre-Update

Record the current model digest.

```bash
ollama show "${OLLAMA_MODEL:-gemma3:4b}" --modelfile | grep -oE 'sha256:[a-f0-9]+'
```

### 2. Update

Pull the new model version.

```bash
ollama pull "${OLLAMA_MODEL:-gemma3:4b}"
```

To switch to a different model entirely:

```bash
export OLLAMA_MODEL=<new-model-name>
ollama pull "$OLLAMA_MODEL"
```

### 3. Post-Update Verification

Re-baseline to record the new model digest in the manifest, then verify.

```bash
bash scripts/integrity-deploy.sh --force
make audit
```

Confirm:

- Ollama CVE check: PASS
- Model digest in manifest matches the newly pulled version

### 4. Rollback

Ollama supports pulling a specific digest to restore a previous model version.

```bash
ollama pull "${OLLAMA_MODEL:-gemma3:4b}@<old-digest>"

# Re-baseline
bash scripts/integrity-deploy.sh --force
make audit
```

If the old digest is unknown, check the manifest backup or git history for
the `ollama_model_digest` field.

---

## Credential Rotation

### HMAC Key Rotation

The HMAC-SHA256 shared secret is used for webhook authentication between
OpenClaw and n8n. It is stored in the macOS Keychain and distributed to
`.env` files.

```bash
# Generate new key and distribute
make hmac-setup

# Re-baseline the manifest (HMAC key change invalidates all signatures)
bash scripts/integrity-deploy.sh --force

# Re-lock workspace files
sudo make integrity-lock

# Verify everything passes
make audit
```

Both the agent environment (`~/.openclaw/.env`) and orchestrator environment
(repo root `.env`) are updated by `make hmac-setup`. The n8n container reads
the secret via `env_file` and must be restarted to pick up the new value.

```bash
cd scripts/templates
docker compose restart n8n
```

### n8n Encryption Key Rotation

The n8n encryption key protects stored credentials (LinkedIn OAuth tokens,
API keys) at rest within the n8n Docker volume. It is stored as a Docker
secret in `scripts/templates/secrets/n8n_encryption_key.txt`.

**Warning**: Rotating this key makes all existing n8n stored credentials
unreadable. You must re-enter all credentials in the n8n UI after rotation.

```bash
# Generate new key
openssl rand -hex 32 > scripts/templates/secrets/n8n_encryption_key.txt
chmod 600 scripts/templates/secrets/n8n_encryption_key.txt

# Restart n8n to load new key
cd scripts/templates
docker compose down n8n
docker compose up -d n8n

# Re-enter all credentials in n8n UI (http://localhost:5678)
# Re-baseline
bash scripts/integrity-deploy.sh --force
make audit
```

---

## Partial Update Recovery

A dependency update can fail partway through, leaving the pipeline in an
inconsistent state. The table below documents each half-complete state and
how `make audit` detects it.

| Partial State | Symptom | Audit Detection |
|---------------|---------|-----------------|
| docker-compose.yml edited but image not pulled | Container runs old image; compose file says new tag | CVE check may PASS (old patched image) but image digest mismatch vs manifest |
| Image pulled but container not restarted | `docker inspect` shows old image on running container | Container image digest does not match `docker images` output for the tag |
| Container restarted but manifest not re-baselined | New image digest does not match manifest | CHK-PIPELINE-IMAGE-DIGEST reports FAIL |
| Manifest re-baselined but immutable flags not re-set | Workspace files writable | CHK-OPENCLAW-INTEGRITY-LOCK reports FAIL |
| HMAC key rotated in Keychain but .env not updated | Agent and orchestrator secrets diverge | CHK-HMAC-CONSISTENCY reports FAIL |
| HMAC key rotated but manifest not re-signed | Manifest signature invalid | CHK-OPENCLAW-MANIFEST-SIG reports FAIL |
| Ollama model pulled but manifest not re-baselined | Model digest in manifest is stale | CHK-CVE-OLLAMA model digest mismatch |
| OpenClaw updated but manifest not re-baselined | Version check passes but binary hash differs | No automated detection (FR-027 residual risk) |
| n8n encryption key rotated but credentials not re-entered | n8n cannot decrypt stored credentials | Workflow executions fail; not detected by audit directly |

### Recovery Procedure

For any partial state detected by `make audit`:

1. Identify the FAIL check(s) in the audit report
2. Complete the remaining steps of the relevant update procedure above
3. Re-baseline: `bash scripts/integrity-deploy.sh --force`
4. Re-lock: `sudo make integrity-lock`
5. Re-verify: `make audit`

If the partial state cannot be resolved forward, follow the rollback procedure
for the relevant component to return to the last known-good state.

---

## References

- `data/cve-registry.json` -- maintained CVE registry for all components
- `scripts/templates/docker-compose.yml` -- n8n container configuration
- `scripts/integrity-deploy.sh` -- manifest baseline creation
- `docs/SENSITIVE-FILE-INVENTORY.md` -- sensitive file protections
- `docs/ASI-MAPPING.md` -- OWASP ASI control mappings (ASI04 supply chain)
