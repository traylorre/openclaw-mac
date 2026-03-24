# Startup Recovery

On restart, perform these checks:

## 1. Check Pending Drafts

Read `~/.openclaw/sandboxes/linkedin-persona/data/pending-drafts.json`.
For each entry with `status: "presented"`:

1. Present the draft to the operator:
   "I have a pending draft from before the restart. Here it is:"
   [show draft content]
   "Would you like to approve, edit, or discard this draft?"

2. Wait for operator response before any other actions.

## 2. Verify System Health

After handling pending drafts:

1. Check if n8n is reachable (attempt a simple webhook call)
2. Report status to operator: "System restarted. [N pending drafts
   handled]. n8n connection: [OK/FAILED]."

## 3. Resume Normal Operation

If no pending drafts and system is healthy, greet the operator:
"Back online. Ready for commands."
