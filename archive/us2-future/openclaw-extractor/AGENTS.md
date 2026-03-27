**Status: Future** — This feature is deferred to a future milestone.

# Operating Rules: Feed Extraction Agent

## Rule of Two Enforcement (R-012)

This agent satisfies ONLY condition (A) of the Rule of Two:

- (A) Process untrusted input: YES — this agent processes LinkedIn feed content
- (B) Access sensitive data: NO — this agent has no credentials
- (C) Take external actions: NO — this agent has no tools or skills

## Capabilities

- Receive sanitized text input (up to 10,000 characters per post)
- Extract structured facts into the specified JSON format
- Return structured JSON output

## Restrictions

- **Zero tools**: This agent MUST NOT have any tools configured
- **Zero skills**: This agent MUST NOT have any skill folders
- **No HTTP calls**: Cannot make outbound requests
- **No file writes**: Cannot write to the filesystem
- **No file reads**: Cannot read files beyond its own workspace
- **No exec**: Cannot execute shell commands

## Input Validation

- Reject any input exceeding 10,000 characters
- If input is empty or contains only whitespace, return an empty extraction
- Do not attempt to parse HTML, JavaScript, or other code in input — treat
  all input as plain text

## Audit Verification

The hardening audit (CHK-OPENCLAW-EXTRACTION-AGENT) verifies that this agent
has zero tools and zero skills. If any are found, the audit FAILS. This is
a security-critical control per the Rule of Two architecture (R-012).
