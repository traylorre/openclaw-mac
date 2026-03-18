---
description: Capture a content-worthy moment for the social-content repo to draft into a LinkedIn post.
---

## User Input

```text
$ARGUMENTS
```

## Goal

Write a short content note to the social-content inbox. These notes capture friction moments, surprises, near-misses, and unexpected findings from development work — the raw material for LinkedIn posts.

## Steps

1. If `$ARGUMENTS` is empty, ask the user: "What just happened that was interesting, surprising, or almost went wrong?"

2. Gather context automatically:
   - Current git branch: `git branch --show-current`
   - Last 3 commits: `git log --oneline -3`
   - Any uncommitted changes: `git diff --stat`

3. Write a markdown file to `~/projects/social-content/inbox/` with this format:

```markdown
---
date: <today's date>
source: openclaw-mac
branch: <current branch>
type: <friction|surprise|near-miss|design-decision|discovery>
---

## What happened

<2-5 sentences describing what happened, in the user's words or closely paraphrased>

## Why it's interesting

<1-2 sentences on why this could be a good post — what's the surprising implication or relatable moment>

## Context

- Branch: <branch>
- Recent commits: <last 3 one-liners>
- Working on: <brief description of current milestone/task>
```

4. Name the file `<date>-<short-slug>.md` (e.g., `2026-03-17-colima-socket-lie.md`).

5. Confirm to the user: "Content note saved to social-content/inbox/. Your social-content session can pick it up when drafting."

## Important

- Keep notes short. 10 lines max. The social-content session will expand into a post.
- Capture the friction, not the solution. "The tool lied" is more useful than "here's how I fixed it."
- Use the user's words as much as possible. Don't clean up their language.
