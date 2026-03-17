# Context Carryover: 006-multi-browser-support

**Session**: 2026-03-16 | **Context**: ~20% | **Constitution**: 1.3.0

## Resume Instructions
1. Read this file
2. Read specs/006-multi-browser-support/spec.md
3. Run /speckit.plan

## Key Decision
CHK-CHROMIUM-* renamed to CHK-BROWSER-* for multi-browser support (Chromium, Chrome, Edge).

## Session Summary (13 PRs)
PRs #32-43: Script bugs, guides, coverage map, CDP hardening, drift detection, Intel guide, test fixes.

## Browser Registry
| Browser | Policy Domain | TCC Bundle | Cask | Profile Dir |
|---------|--------------|------------|------|-------------|
| Chromium | org.chromium.Chromium | org.chromium.Chromium | chromium | ~/Library/Application Support/Chromium/Default/ |
| Chrome | com.google.Chrome | com.google.Chrome | google-chrome | ~/Library/Application Support/Google/Chrome/Default/ |
| Edge | com.microsoft.Edge | com.microsoft.edgemac | microsoft-edge | ~/Library/Application Support/Microsoft Edge/Default/ |
