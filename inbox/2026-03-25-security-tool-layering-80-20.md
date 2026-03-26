---
type: content-note
date: 2026-03-25
topic: security-architecture
hook: "Three tools, three layers, zero overlap in what matters"
---

# Content Note


# Content Note
## The Finding

# Content Note


# Content Note
The average SOC manages 83 security tools from ~30 vendors. Organizations with consolidated platforms generate 4x greater ROI (101% vs 28%) — IBM/Palo Alto 2026 study.

# Content Note


# Content Note
For single-container deployments, the equivalent anti-pattern is accumulating 6-8 CLI scanners that each need updating, each produce different output formats, and each require separate mental models.

# Content Note


# Content Note
## The Three-Layer Model

# Content Note


# Content Note
For a single container on macOS:

# Content Note


# Content Note
| Layer | Tool | Question it answers |

# Content Note
|-------|------|---------------------|

# Content Note
| Host posture | docker-bench-security | Is the Docker host configured securely? |

# Content Note
| Image safety | Grype (not Trivy — compromised) | Does this image have known CVEs? |

# Content Note
| Runtime integrity | Custom verification | Is THIS container running as expected RIGHT NOW? |

# Content Note


# Content Note
That's it. Three tools. Each answers a fundamentally different question. No tool answers another tool's question.

# Content Note


# Content Note
## The Custom Code Decision Framework

# Content Note


# Content Note
Keep custom code when:

# Content Note


# Content Note
- It verifies YOUR deployment topology (n8n credential baseline)

# Content Note
- It verifies application-level integrity no standard tool covers (workflow hash comparison)

# Content Note
- It integrates with YOUR trust chain (HMAC-signed manifests, hash-chained audit log)

# Content Note


# Content Note
Replace with standard tools when:

# Content Note


# Content Note
- The check is "table stakes" a maintained project does better (CVE scanning)

# Content Note
- You're maintaining vulnerability databases yourself

# Content Note
- The custom implementation has worse coverage than the standard tool

# Content Note


# Content Note
## The Key Insight

# Content Note


# Content Note
Custom code is not NIH syndrome when standard tools don't cover your use case. It's NIH syndrome when you rewrite `trivy image scan` in bash. It's engineering when you build credential baseline comparison that no standard tool provides.

# Content Note


# Content Note
## Tags

# Content Note


# Content Note
