---
name: Rule of Three for Refactoring
description: Do not extract shared code until at least 3 concrete use-cases exist; duplication is preferred over premature abstraction
type: feedback
---

Only refactor common code when at least 3 concrete use-cases already exist. Prefer inline duplication over shared files/abstractions until the threshold is met.

**Why:** User initially rejected a shared `browser-registry.sh` when they thought there were only 2 browsers (Chromium + Edge). When they realized there are 3 (Chromium, Chrome, Edge), they immediately applied the rule correctly: 3 use-cases = extract. The principle is about counting *concrete use-cases*, not consumers. User wants this added as a constitution principle.

**How to apply:** When designing any shared utility, library file, or abstraction that deduplicates code across files, count the number of *concrete use-cases* (not just consumers/callers). If fewer than 3, keep the code duplicated inline. At 3+, extract to shared code.
