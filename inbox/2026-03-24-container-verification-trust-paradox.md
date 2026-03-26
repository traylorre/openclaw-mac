---
type: content-note
date: 2026-03-24
topic: container-security
hook: "The verification trust paradox — when asking the suspect to testify about their own crimes"
---

# Content Note


# Content Note
## The Finding

# Content Note


# Content Note
When verifying container integrity, you face a fundamental trust paradox: the most valuable checks (credential enumeration, workflow comparison, community node inventory) run inside the container via `docker exec`. But if the container is compromised, these checks run against a lying witness.

# Content Note


# Content Note
## The Two Tiers

# Content Note


# Content Note
**Host-side checks (high trust):**

# Content Note


# Content Note
- Image digest comparison — runs `docker inspect` from the host

# Content Note
- Runtime configuration — extracted from the same atomic `docker inspect`

# Content Note
- Filesystem drift — `docker diff` runs from the host

# Content Note


# Content Note
These can't be spoofed without replacing the Docker daemon itself.

# Content Note


# Content Note
**Container-side checks (partial trust):**

# Content Note


# Content Note
- `n8n list:credentials` — runs the n8n binary inside the container

# Content Note
- `n8n export:workflow --all` — same

# Content Note
- Reading `package.json` files — via `docker exec cat`

# Content Note


# Content Note
A fully compromised container can return fabricated results to all three.

# Content Note


# Content Note
## Why You Still Run Both

# Content Note


# Content Note
The partial-trust checks detect the 80% case: an attacker who gains code execution via n8n sandbox escape (CVE-2026-27495) and adds exfiltration credentials, but doesn't modify the n8n binary itself. The attacker has `process.exec` access but typically installs persistence, not a complete n8n replacement.

# Content Note


# Content Note
Image digest verification catches the 20% case: complete container replacement (tag poisoning, config.patch escape). Together, the two tiers cover the spectrum.

# Content Note


# Content Note
## The Design Pattern

# Content Note


# Content Note
1. Start with the highest-trust check (image digest)

# Content Note
2. If it fails, don't run lower-trust checks (they'd execute inside a compromised container)

# Content Note
3. If it passes, run lower-trust checks knowing the container image is authentic

# Content Note
4. Document the trust boundary explicitly — never let "all checks pass" imply "container is definitely clean"

# Content Note


# Content Note
## Tags

# Content Note


# Content Note
