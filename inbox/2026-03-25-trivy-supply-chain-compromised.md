---
type: content-note
date: 2026-03-25
topic: supply-chain-security
hook: "Your security scanner got hacked — when the watchers need watching"
---

# Content Note


# Content Note
## The Finding

# Content Note


# Content Note
In March 2026, Trivy — the most popular open-source container security scanner (50M+ Docker Hub pulls) — was itself supply-chain compromised. Attackers hijacked 76 of 77 GitHub Actions release tags, published fake releases, and pushed malicious Docker Hub images containing the TeamPCP infostealer.

# Content Note


# Content Note
The security scanner that tells you whether your images are safe... was delivering malware.

# Content Note


# Content Note
## Why This Matters

# Content Note


# Content Note
If your entire container security strategy is "run Trivy in CI/CD," you had a window where your security check was the attack vector. Your defense-in-depth collapsed to defense-in-one-tool.

# Content Note


# Content Note
## The Lesson

# Content Note


# Content Note
Defense in depth isn't just multiple checks — it's multiple INDEPENDENT verification mechanisms:

# Content Note


# Content Note
1. **Pre-deployment scanning** (Trivy/Grype) catches known CVEs

# Content Note
2. **CIS benchmark auditing** (docker-bench-security) catches misconfigurations

# Content Note
3. **Runtime verification** (custom) catches post-deployment tampering

# Content Note
4. **Application integrity** (credential baselines, workflow hashes) catches compromise artifacts

# Content Note


# Content Note
If any one of these tools is compromised, the other three still function. The scanner that got hacked can't fake the runtime digest comparison. The credential baseline doesn't depend on the vulnerability database.

# Content Note


# Content Note
## The Pattern

# Content Note


# Content Note
The 80/20 rule for security tooling: 80% should come from maintained open-source tools (they track CVE databases you can't maintain yourself). 20% should be custom verification that addresses your specific deployment topology. When the 80% tool fails, the 20% custom code is your safety net.

# Content Note


# Content Note
## Tags

# Content Note


# Content Note
