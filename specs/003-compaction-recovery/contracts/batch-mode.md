# Contract: compaction-audit Batch Mode Extension

**Command**: `.claude/commands/compaction-audit.md`
**Extension**: `--batch` flag for recovery-triggered invocation
**Existing behavior**: Interactive (asks for confirmation before each revert)

## Trigger

The recovery workflow injects context instructing the model to run:

```text
/compaction-audit --batch
```

The `--batch` flag is passed as part of the user's slash command invocation
and is visible in the command's `$ARGUMENTS` variable.

## Behavior Changes in Batch Mode

| Aspect | Interactive (default) | Batch (`--batch`) |
|--------|----------------------|-------------------|
| Confirmation prompts | Per-revert confirmation | No confirmation — auto-approve all |
| Uncommitted changes | Warn and ask | Auto-stash before reverts (FR-037) |
| Git hooks on revert | Normal | Bypass via `--no-verify` (FR-049) |
| Output verbosity | Full per-edit details | Summarized (file paths + types only) |
| Recovery log | Not written | Written to `.claude/recovery-logs/` (FR-043) |
| Sentinel file | Not created | Creates `.claude/recovery-audit-complete` |
| Stash restore | N/A | Auto-restore stash after reverts (FR-037) |

## Batch Mode Workflow

1. Identify tainted edits (same as interactive)
2. Check git working tree state:
   - If dirty: `git stash push --keep-index -m "recovery-auto-stash"` (FR-037, FR-096)
   - If stash fails: warn and skip files that would conflict (FR-114)
3. Check for infrastructure files in tainted list (FR-047):
   - Flag and prioritize their revert
4. Execute all reverts without confirmation:
   - `git checkout <pre-compaction-commit> -- <file>` for modified files
   - `rm <file>` for files created by tainted Write (FR-041)
   - Skip out-of-repo files (FR-086)
   - Skip files with external modifications (FR-040)
   - Use `--no-verify` to bypass git hooks (FR-049)
5. If >50 tainted edits: summarized output only (FR-068)
6. Restore stash: `git stash pop` (if stashed in step 2)
7. Write recovery log (FR-043)
8. Present summary report to developer
9. Create sentinel file: `.claude/recovery-audit-complete` (empty file)
10. Update recovery marker stage to `"reverts_complete"`

## Output Format (Batch)

The model's conversation output in batch mode should be concise (FR-053):

```text
🔍 Compaction audit (batch mode) — scanning for tainted edits...
Found 5 tainted edits across 4 files.

Reverting:
  ✓ src/hook.sh (modified → reverted)
  ✓ src/new-file.sh (created → deleted)
  ✓ docs/README.md (modified → reverted)
  ⚠ /tmp/output.txt (out-of-repo → skipped)
  ✓ .claude/settings.json (CRITICAL infrastructure → reverted)

Recovery complete. 4 files reverted, 1 skipped.
Full details in .claude/recovery-logs/recovery-2026-03-08T143000Z.md
```

## Sentinel File

**Path**: `.claude/recovery-audit-complete`
**Content**: Empty file
**Purpose**: Signals `recovery-watcher.sh` that audit + reverts are done
**Cleanup**: Deleted by watcher after sending /clear

The model creates this file as the last step of batch mode:

```bash
touch .claude/recovery-audit-complete
```

## Compatibility

- The `--batch` flag is **additive** — it does not change the command's
  core detection logic
- Interactive mode (no flag) remains the default for manual invocation
- The command file itself documents both modes with clear conditional logic
- FR-003 compliance: this is a controlled extension, not a reimplementation
