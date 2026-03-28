# Contract: Workflow Sync Operations

## make workflow-import

**Input**: `workflows/*.json` files in repository root
**Output**: Workflows imported into running n8n instance and activated
**Side effects**: Deactivates then reactivates each workflow (webhook re-registration)

### Pre-conditions
- n8n container `openclaw-n8n` is running
- `workflows/` directory contains valid JSON files with `id` fields
- (Optional) n8n API key stored in macOS Keychain under `openclaw/n8n-api-key`

### Post-conditions
- Each workflow JSON is loaded into n8n, replacing any existing workflow with the same `id`
- Workflows are activated in dependency order (hmac-verify first)
- If no API key: workflows are imported but remain inactive (warning logged)

### Error conditions
- Container not running: exits with error, no changes made
- No JSON files found: exits cleanly with warning
- Import failure: logs warning, continues with remaining files
- Activation failure: logs warning per workflow, does not roll back import

## make workflow-export

**Input**: Running n8n instance workflows
**Output**: `workflows/*.json` files written to repository root
**Side effects**: Overwrites existing JSON files (includes current Static Data state)

### Warning
Exported files include runtime Static Data. This is operational state that should NOT be committed to git without review. Use `git diff workflows/` to inspect before committing.

## Post-Import Verification (new)

**Input**: n8n REST API
**Output**: Pass/fail report for each imported workflow

### Checks
1. Workflow exists with expected ID
2. Node count matches expected value
3. Workflow is active (triggers armed)
4. Webhook endpoint responds (if applicable)
