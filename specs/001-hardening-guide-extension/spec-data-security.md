# Spec Module: Data Security

**Parent spec**: [spec.md](spec.md) (Rev 29)
**Module scope**: Injection defense, PII/lead data protection, credential management, SSRF, data exfiltration, supply chain integrity, and cloud service exposure.

## Functional Requirements

- **FR-012**: The guide MUST include a credential and secret management
  section covering: macOS Keychain usage (bare-metal path), Docker
  secrets (container path), Bitwarden CLI as a free alternative, and
  LinkedIn-specific credential hygiene.
  *Source: NIST SP 800-63B (Digital Identity Guidelines); OWASP Secrets Management Cheat Sheet.*

- **FR-013**: The guide MUST include a PII/lead data protection section
  addressing GDPR, CCPA, and LinkedIn ToS implications with specific
  technical controls. This deployment scrapes, stores, and processes
  personal data — making it a high-value target and a potential
  liability. The section MUST cover:
  - **Data classification**: identify exactly what PII this deployment
    handles — full names, job titles, company names, LinkedIn profile
    URLs, email addresses (if scraped or enriched), phone numbers (if
    enriched), profile photos, employment history, education history,
    location data, skills/endorsements, connection count. The guide
    MUST classify each field by sensitivity level: public (visible on
    LinkedIn without login), semi-private (visible only to connections
    or logged-in users), and derived (enriched data not directly from
    LinkedIn)
  - **Data minimization**: the guide MUST recommend collecting only the
    fields required for the lead generation workflow — not scraping
    entire profiles "just in case." Fewer fields stored = smaller
    breach impact = lower notification burden. The guide MUST show how
    to configure Apify actors to limit field extraction
  - **Data flow mapping**: the guide MUST document where PII lives at
    rest and in transit in this deployment:
    - At rest: n8n database (SQLite or Postgres), Docker volumes,
      backup archives, Time Machine snapshots, n8n execution logs
      (which can contain full input/output data)
    - In transit: Apify API → n8n (HTTPS), n8n → email/CRM/database
      (varies), n8n execution logs (contain PII in workflow data)
    - Derived: any LLM enrichment creates additional PII-containing
      outputs stored in n8n
  - **Retention limits**: the guide MUST recommend a data retention
    policy — PII lead data should be retained only as long as needed
    for the business purpose. The guide MUST document how to configure
    n8n execution log retention (which contains PII in
    input/output data) and how to purge old lead data from n8n's
    database
  - **Secure deletion**: when PII is deleted, it must be actually
    deleted — not just removed from the n8n UI. The guide MUST cover
    deleting PII from n8n's database, execution logs, backup archives
    (or accepting that old backups contain PII and scheduling their
    destruction), and Time Machine snapshots
  - **Access control**: PII data access MUST be restricted — on bare-
    metal, only the n8n service account should have read access to the
    n8n database. On containerized, the database is inside the
    container. The guide MUST recommend not exporting PII data to
    shared directories, email attachments without encryption, or
    unencrypted cloud storage
  - **Encryption**: PII at rest MUST be encrypted via FileVault (disk-
    level) and n8n's credential encryption (for stored credentials
    that contain PII). The guide MUST note that FileVault protects
    against physical theft but not against a running attacker with
    shell access
  - **Breach notification obligations**: the guide MUST summarize the
    operator's notification obligations if PII is breached:
    - GDPR: 72-hour notification to supervisory authority if EU
      residents' data is involved (Article 33)
    - CCPA: notification to affected California residents (Section
      1798.150) with potential statutory damages
    - LinkedIn ToS: scraping may violate ToS; a breach involving
      scraped data may trigger LinkedIn enforcement action
    - The guide MUST recommend consulting legal counsel before
      scraping LinkedIn data at scale
  *Source: GDPR Article 32; CCPA Section 1798.150; hiQ Labs v.
  LinkedIn (9th Cir. 2022); NIST SP 800-122 (Guide to Protecting the
  Confidentiality of PII).*

- **FR-021**: The guide MUST include a scraped data input security
  section addressing injection attacks via untrusted web content.
  Since Apify actors scrape LinkedIn profiles and web pages that
  anyone can edit, ALL data entering n8n from external sources MUST
  be treated as adversarial. The section MUST cover:

  **Data flow mapping (Prevent):** The section MUST open with a
  concrete description of the data flow through this deployment so
  the operator understands where untrusted data enters and where it
  can reach code execution:
  1. Apify actor scrapes LinkedIn → returns structured data via API
  2. n8n trigger/webhook receives Apify response
  3. n8n transformation nodes process the data (Set, IF, Switch,
     Merge, etc. — these are safe as they don't execute arbitrary
     code)
  4. **Danger zone:** data reaches a node that CAN execute code
     (Code, Execute Command, SSH, Function, AI/LLM nodes) — this is
     where injection becomes code execution
  5. Output: data is stored, sent via email/webhook, or written to a
     database
  The guide MUST make clear that the attack surface is step 4: the
  boundary where data crosses from "being processed" to "influencing
  code execution."

  **Prompt injection (Prevent):** If any LLM or AI node processes
  scraped content (e.g., for lead enrichment or summarization),
  adversarial prompts embedded in profile fields (job title, summary,
  company name) can hijack the model into executing unintended
  actions. The guide MUST explain the attack, show concrete examples
  using LinkedIn profile fields, and recommend layered controls:
  - Structural separation: pass scraped data as clearly delimited
    data fields, never concatenated directly into the prompt text
  - Output schema validation: validate LLM output against an
    expected structure before acting on it
  - Never chain LLM output to code execution: LLM output MUST NOT
    flow into Execute Command, Code, or SSH nodes without human
    review
  - Never allow LLM output to modify workflows: if n8n's API is
    accessible, a hijacked LLM could create or modify workflows to
    establish persistence. The guide MUST recommend restricting n8n
    API access and never granting AI nodes permission to call the
    n8n API
  - System prompt hardening: include instructions to ignore embedded
    directives, but treat this as a weak control (it can be bypassed
    by sufficiently adversarial input — it is a speed bump, not a
    wall)
  The guide MUST name the specific n8n nodes that process LLM/AI
  content and are vulnerable to prompt injection: OpenAI node,
  AI Agent node, LangChain nodes (LLM Chain, Retrieval QA, etc.),
  Anthropic node, and any community AI nodes. Each MUST be flagged
  as high-risk when processing scraped data.

  **Command injection (Prevent):** The n8n Execute Command node runs
  shell commands on the host (bare-metal) or inside the container. If
  scraped data reaches this node unsanitized, it is arbitrary code
  execution. The guide MUST recommend disabling Execute Command
  unless strictly needed, and if needed, showing how to sanitize
  inputs and restrict what commands can run.

  **Code injection (Prevent):** The n8n Code node executes JavaScript
  or Python. If scraped data is interpolated into code strings, it is
  code injection. The guide MUST recommend treating all scraped
  fields as data (never code), using parameterized operations, and
  auditing workflows for string interpolation of external data.

  **n8n built-in security controls (Prevent):** The guide MUST
  document n8n's own security environment variables that restrict
  what nodes can do:
  - `N8N_BLOCK_ENV_ACCESS_IN_NODE`: prevents Code/Function nodes
    from reading environment variables (blocks credential leakage)
  - `N8N_RESTRICT_FILE_ACCESS_TO`: restricts filesystem access from
    Code nodes to a specific directory
  - Community node restrictions: disable untrusted community nodes
    that may introduce additional code execution paths
  - Node type restrictions: if n8n supports disabling specific node
    types, document how to remove Execute Command and SSH nodes from
    the available palette entirely

  **Node restriction policy (Prevent):** The guide MUST list which
  n8n nodes can execute arbitrary code (Execute Command, Code,
  Function, SSH, HTTP Request with scripting, AI Agent, LangChain
  nodes) and recommend a policy for when each is acceptable in a
  workflow that processes untrusted data.

  **Detection and logging (Detect):** The guide MUST cover how to
  detect injection attempts after they happen:
  - Enable n8n execution logging so every workflow run records input
    data and node outputs
  - Monitor for anomalous patterns: unexpected outbound connections
    from the container/host, unusual process execution, file system
    changes outside expected paths
  - Log scraped data that contains shell metacharacters, prompt
    injection keywords, or other suspicious patterns before it
    reaches processing nodes
  - For containerized deployments, use Docker logging to capture
    container stdout/stderr for forensic review

  **Defense in depth with containerization (Respond):** Even with
  input sanitization, injection defenses can be bypassed. Container
  isolation (FR-016) limits blast radius if injection succeeds —
  the attacker gets a container shell, not a host shell. The guide
  MUST cross-reference the container isolation section as the
  fallback when input validation fails. For bare-metal deployments,
  the guide MUST include a prominent warning box explaining the
  concrete consequences of successful injection without
  containerization:
  - Full access to the operator's home directory (SSH keys, browser
    profiles, credentials files)
  - macOS Keychain access (if the n8n process runs as the user)
  - Ability to install persistence mechanisms (launch agents/daemons)
  - Lateral movement to other devices on the LAN
  - Exfiltration of all PII lead data, LinkedIn credentials, and
    Apify API keys
  The guide MUST recommend containerization as the single most
  important control for any deployment that processes scraped web
  data. If the operator chooses bare-metal despite this warning,
  the guide MUST recommend at minimum: running n8n under a dedicated
  service account with no login shell, restricted filesystem
  permissions, and no Keychain access.

  *Source: OWASP Top 10 (A03 Injection); OWASP LLM Top 10
  (LLM01 Prompt Injection); MITRE ATT&CK T1059 (Command and
  Scripting Interpreter); n8n security documentation.*

- **FR-040**: The guide MUST include a software supply chain integrity
  section addressing the risk that software installation and update
  channels themselves are attack vectors (MITRE ATT&CK T1195 Supply
  Chain Compromise). This deployment depends on multiple package
  ecosystems, each with distinct trust models:
  - **Docker image integrity**: Docker Hub images can be compromised
    via maintainer account takeover or tag mutation (an attacker
    pushes a malicious image to an existing tag). The guide MUST
    recommend:
    - Pinning Docker images by digest (`image: n8nio/n8n@sha256:...`)
      rather than by mutable tag (`:latest`, `:1.x`)
    - Recording known-good digests in the `docker-compose.yml` and
      verifying them after every pull
    - Using Docker Content Trust (`DOCKER_CONTENT_TRUST=1`) to
      enforce image signature verification where available
    - Checking n8n's official release channels for digest
      announcements before updating
  - **Homebrew package integrity**: Homebrew verifies SHA256
    checksums for bottles (prebuilt binaries). The guide MUST explain
    this verification mechanism and recommend:
    - Avoiding third-party Homebrew taps for security-critical tools
      unless the tap is well-known and audited
    - Reviewing `brew info <package>` output to verify the package
      source before installation
    - Checking for Homebrew security advisories after updates
  - **npm supply chain (bare-metal path)**: n8n installed via npm
    inherits the full npm supply chain risk. The guide MUST cover:
    - Typosquatting attacks: attacker publishes `n8n-community-node`
      with a slightly different name that contains malicious code
    - Dependency confusion: attacker publishes a public package with
      the same name as an internal dependency
    - Malicious postinstall scripts: npm packages can execute
      arbitrary code during installation via postinstall hooks. The
      guide MUST recommend `--ignore-scripts` for untrusted packages
      and auditing with `npm audit`
    - Community node vetting: before installing any community node,
      check the npm page for download count, maintenance status,
      source repository, and recent version history. A community
      node with <100 weekly downloads and no source repo is high risk
  - **Colima and Docker engine updates**: verify release signatures
    or checksums when updating container runtime components
  - Verification: audit script checks that Docker images are pinned
    by digest (WARN if using mutable tags), and that
    `DOCKER_CONTENT_TRUST` is set (WARN if not)
  *Source: NIST SP 800-218 (SSDF); MITRE ATT&CK T1195.001 (Compromise
  Software Dependencies and Development Tools), T1195.002 (Compromise
  Software Supply Chain); Docker Content Trust documentation; npm
  security documentation.*

- **FR-043**: The guide MUST expand the credential management section
  (FR-012) with credential lifecycle management covering rotation,
  expiry detection, and revocation procedures:
  - **Rotation schedule**: the guide MUST recommend rotation intervals
    for each credential type in this deployment:
    - n8n encryption key: rotate annually (requires re-encryption of
      all stored credentials — document the procedure)
    - LinkedIn session tokens/cookies: rotate when LinkedIn forces
      re-authentication or every 90 days, whichever is sooner
    - Apify API keys: rotate every 90 days or immediately if
      compromise is suspected
    - SSH keys: rotate annually; prefer short-lived certificates if
      infrastructure supports it
    - SMTP relay credentials: rotate per the relay provider's policy
    - n8n API keys (if enabled per FR-038): rotate every 90 days
    - Docker registry credentials (if using private registries):
      rotate per registry policy
  - **Expiry detection**: the guide MUST document how to detect
    credential expiry for each credential type — some expire silently
    (LinkedIn sessions), some provide warnings (API keys), some never
    expire (SSH keys). The audit script MUST check for credential age
    where feasible (e.g., SSH key creation date, n8n credential last-
    modified timestamp)
  - **Revocation procedures**: for each credential type, document how
    to revoke and replace it — including the downstream impact (which
    workflows break, which services lose access, what order to update
    in). An operator in a breach response scenario needs to rotate
    all credentials quickly without trial-and-error
  - **Credential inventory**: the guide MUST recommend maintaining a
    credential inventory — a list of every credential stored on the
    Mac Mini, where it is stored, what it accesses, and when it was
    last rotated. This inventory is essential for incident response
    (FR-031 credential blast radius assessment)
  - Verification: audit script reports credential age for SSH keys
    and n8n encryption key creation date (WARN if older than rotation
    policy)
  *Source: NIST SP 800-63B Section 5.1 (Authenticator Lifecycle);
  CIS Controls v8 (Control 5: Account Management); MITRE ATT&CK
  T1078 (Valid Accounts), T1528 (Steal Application Access Token).*

- **FR-047**: The guide MUST address Server-Side Request Forgery
  (SSRF) as a data exfiltration and internal network reconnaissance
  vector within n8n workflows. n8n's HTTP Request node follows URLs
  provided in workflow data — if an attacker controls the URL (via
  scraped data, webhook payloads, or workflow modification), they can
  direct the n8n process to make requests to internal services. The
  section MUST cover:
  - **SSRF attack surface in n8n**: the HTTP Request node, Webhook
    Response node, and any node that fetches external URLs (RSS,
    HTML Extract, etc.) can be directed to internal targets. In a
    containerized deployment, the container can reach the Docker
    bridge network, host services via gateway IP, and cloud metadata
    endpoints (169.254.169.254). On bare-metal, the n8n process can
    reach all services on localhost and the LAN
  - **Internal target risks**: document what an SSRF attack can reach:
    - Docker API on the host (if exposed on a TCP port)
    - Other Docker containers on the bridge network
    - macOS services bound to localhost (SSH, screen sharing, etc.)
    - Cloud metadata endpoints (if the Mac Mini runs cloud-adjacent
      services or has cloud credentials configured)
    - LAN devices and their management interfaces
  - **Mitigations**: the guide MUST recommend:
    - Never interpolating untrusted data into URL fields of HTTP
      Request nodes — use allowlisted base URLs with only path or
      query parameters from scraped data
    - Configuring pf rules on the host to block the container's
      outbound access to localhost, the Docker gateway, and RFC 1918
      ranges (except explicitly required LAN services)
    - For bare-metal: pf rules blocking outbound connections from the
      n8n service account to localhost services and LAN ranges
    - Docker network configuration: use `--internal` flag for
      networks that don't need external access; restrict container
      DNS resolution to prevent internal name resolution
  - **Cross-reference**: FR-030 (outbound filtering) and FR-021
    (injection defense) — SSRF is the intersection of network access
    and untrusted data
  - Verification: audit script checks whether n8n container has
    unrestricted access to Docker bridge network (WARN)
  *Source: OWASP Top 10 (A10 Server-Side Request Forgery); MITRE
  ATT&CK T1090 (Proxy), T1571 (Non-Standard Port); CIS Docker
  Benchmark v1.6 (Section 5: Container Runtime).*

- **FR-049**: The guide MUST address data exfiltration via
  "non-dangerous" n8n nodes — nodes that do not execute arbitrary
  code but can still leak data to external endpoints. The current
  injection defense section (FR-021) focuses on code execution nodes
  (Code, Execute Command, SSH). However, data exfiltration does not
  require code execution. The section MUST cover:
  - **Exfiltration-capable nodes**: the guide MUST list n8n nodes that
    can send data to external destinations without executing code:
    - HTTP Request: can POST data to any URL
    - Email/SMTP: can email data to any address
    - Webhook Response: can include data in webhook responses
    - Slack/Discord/Telegram: can send data to messaging platforms
    - Database nodes: can write data to external databases
    - File upload nodes: can send files to external services
    - Any node with a configurable URL or destination
  - **Exfiltration via scraped data**: an attacker who controls a
    LinkedIn profile field could embed a URL in a field value. If a
    workflow passes this URL to an HTTP Request node (e.g., to fetch
    a profile photo or validate a link), the request leaks the IP
    address and potentially other data to the attacker's server. The
    guide MUST recommend never using scraped URLs in HTTP Request
    nodes without allowlisting the destination domain
  - **Exfiltration via workflow modification**: if an attacker gains
    workflow modification access (API, UI), they can add a node that
    silently copies all processed data to an external endpoint. The
    workflow integrity monitoring (FR-046) is the primary defense
  - **Outbound filtering as defense**: pf outbound allowlisting
    (FR-030) is the primary technical control — even if a workflow
    tries to exfiltrate data, the connection will be blocked if the
    destination is not in the allowlist. The guide MUST cross-
    reference FR-030 and emphasize that outbound filtering is
    critical not just for post-compromise containment but for
    preventing data exfiltration via manipulated workflows
  - Verification: audit script checks for outbound filtering (WARN
    if no pf rules or application-level firewall is configured)
  *Source: OWASP Top 10 (A01 Broken Access Control); MITRE ATT&CK
  T1041 (Exfiltration Over C2 Channel), T1567 (Exfiltration Over Web
  Service), T1048 (Exfiltration Over Alternative Protocol).*

- **FR-057**: The guide MUST expand FR-012 (credential management) to
  document how credentials are actually accessed at runtime in each
  deployment path, so the operator understands the access pattern and
  its security implications:
  - **Bare-metal Keychain access**: n8n does not natively integrate
    with macOS Keychain. If credentials are stored in Keychain, they
    must be retrieved via `security find-generic-password` in a
    wrapper script and passed to n8n as environment variables at
    startup. The guide MUST document this pattern and its limitation:
    the credentials are in environment variables (visible via `ps`)
    while n8n is running. Cross-reference FR-044 (execution model)
    and FR-051 (Keychain security)
  - **Docker secrets access**: Docker secrets are mounted as files
    inside the container at `/run/secrets/<secret_name>`. n8n reads
    credentials from environment variables, not files. The guide MUST
    document how to bridge this gap — either using n8n's `_FILE`
    environment variable suffix (e.g., `N8N_ENCRYPTION_KEY_FILE`) if
    supported, or using an entrypoint script that reads the secret
    file into an environment variable before starting n8n
  - **Keychain lock behavior on headless servers**: on a headless Mac
    Mini without a GUI session, the login Keychain may not auto-
    unlock. The guide MUST document what happens when the Keychain is
    locked: `security find-generic-password` will fail, n8n will
    start without credentials, and workflows will fail silently. The
    guide MUST provide a launchd pre-start script pattern that
    unlocks the Keychain (storing the Keychain password securely is
    a bootstrapping problem the guide MUST acknowledge)
  - **n8n's internal credential storage**: n8n stores credentials in
    its database, encrypted with `N8N_ENCRYPTION_KEY`. The guide MUST
    document that this key is the single master secret — anyone with
    this key and the database can decrypt all stored credentials.
    This reinforces why the encryption key must be protected per
    FR-045 and rotated per FR-043
  *Source: Apple Developer Documentation (Keychain Services); Docker
  documentation (Docker secrets); n8n environment variable
  documentation.*

- **FR-060**: The guide MUST include an Apify actor security section
  addressing the first point of contact with untrusted data. Apify
  actors scrape LinkedIn and web pages — they are the entry point for
  adversarial content before n8n sees it. The section MUST cover:
  - **Actor trust**: only use official Apify actors or actors from
    verified publishers with high usage counts. Third-party actors
    with low usage or no source code are high risk — they could
    modify scraped data to include injection payloads or exfiltrate
    the operator's Apify API key
  - **API key security**: Apify API keys have full account access
    (create/delete actors, access stored data, manage webhooks). The
    guide MUST recommend:
    - Using scoped API tokens if Apify supports them (limited to
      specific actors and datasets)
    - Rotating API keys per FR-043 schedule
    - Never embedding API keys in n8n workflows — use n8n credentials
      storage instead
  - **Actor output validation**: Apify actor output should be treated
    as untrusted even if the actor is legitimate — the data comes from
    LinkedIn profiles that anyone can edit. The guide MUST recommend
    validating actor output schema in the n8n workflow before
    processing (expected fields, data types, length limits)
  - **Apify webhook security**: if Apify sends completion webhooks to
    n8n, the webhook must be authenticated (cross-reference FR-039).
    Apify supports webhook signing — the guide MUST document how to
    verify Apify webhook signatures in n8n
  - **Data residency**: Apify stores scraped data on their platform.
    The guide MUST note this for PII compliance (FR-013) — scraped
    LinkedIn PII exists on Apify's servers as well as the Mac Mini.
    The guide MUST recommend configuring Apify data retention to the
    minimum period and deleting datasets after n8n retrieval
  - Verification: audit script checks that Apify API key is stored in
    n8n credentials (not hardcoded in workflows) — WARN if found in
    workflow export
  *Source: Apify platform security documentation; OWASP Top 10 (A08
  Software and Data Integrity Failures); MITRE ATT&CK T1195.002
  (Compromise Software Supply Chain).*

- **FR-071**: The guide MUST include an iCloud and Apple cloud
  services exposure control section. If the Mac Mini has an Apple ID
  signed in (required for Find My Mac per FR-053), other iCloud
  services may sync data from the Mac Mini to Apple's servers and
  to the operator's other Apple devices, creating data leakage paths
  and expanding the attack surface. The section MUST cover:
  - **iCloud Keychain**: if enabled, passwords and credentials stored
    in the macOS Keychain may sync to the operator's iPhone, iPad,
    and other Macs. A compromise of any synced device exposes the
    Mac Mini's credentials. The guide MUST recommend disabling iCloud
    Keychain on the Mac Mini — credentials for n8n should be stored
    in a separate, non-syncing Keychain (cross-reference FR-051)
  - **iCloud Drive**: if enabled, files in Desktop, Documents, or
    other configured directories are uploaded to Apple's servers.
    If the n8n data directory or backup files are in a synced
    location, PII and credentials could be uploaded to iCloud. The
    guide MUST recommend disabling iCloud Drive entirely on the Mac
    Mini
  - **Desktop & Documents sync**: a subset of iCloud Drive that
    specifically syncs the Desktop and Documents folders. The guide
    MUST verify this is disabled — any sensitive files placed on the
    Desktop (common during debugging or maintenance) would be
    uploaded
  - **Universal Clipboard**: syncs clipboard content between Apple
    devices on the same Apple ID. If the operator copies a password
    or API key on the Mac Mini, it appears on their iPhone. The guide
    MUST recommend disabling Handoff (which includes Universal
    Clipboard) on the Mac Mini (cross-reference FR-042 which already
    recommends disabling Handoff for lateral movement defense)
  - **Photos, Mail, Contacts, Calendar**: all MUST be disabled on a
    headless server. None have legitimate use for an automation server
    and each adds iCloud data sync surface
  - **iCloud Backup**: does not apply to macOS (only iOS/iPadOS), but
    the guide MUST note this to prevent confusion with Time Machine
    backup (FR-018)
  - **Find My Mac**: the ONLY iCloud service that should remain
    enabled (per FR-053). The guide MUST explain that Find My Mac
    requires iCloud sign-in but does not require any other iCloud
    service to be enabled
  - **Apple ID compromise impact**: if the operator's Apple ID is
    compromised (phishing, credential stuffing), an attacker could:
    - Use Find My Mac to remotely lock or erase the Mac Mini
    - Access any iCloud-synced data (if services were left enabled)
    - The guide MUST recommend enabling two-factor authentication on
      the Apple ID and using a strong, unique password
  - Verification: audit script checks iCloud service status (WARN
    if any service besides Find My Mac is enabled), Handoff status
    (WARN if enabled — cross-ref FR-042)
  *Source: Apple Platform Security Guide (iCloud security); CIS Apple
  macOS Benchmarks (iCloud configuration); MITRE ATT&CK T1537 (Transfer
  Data to Cloud Account), T1530 (Data from Cloud Storage).*

- **FR-083**: The guide MUST address the practical limitations of secure
  data deletion on modern macOS systems with APFS-formatted SSDs.
  FR-013 requires secure deletion of PII, but traditional secure
  deletion methods do not work as expected on current Mac hardware. The
  section MUST cover:
  - **APFS + SSD + TRIM**: Apple's APFS filesystem on SSDs uses
    copy-on-write semantics, and the SSD controller performs TRIM (block
    reclamation) independently of the operating system. The `srm`
    (secure remove) command was removed in macOS Catalina because it
    cannot guarantee data overwrite on SSDs — the SSD controller may
    remap blocks, leaving original data on the physical medium. The
    guide MUST explain that traditional "overwrite the file with zeros"
    secure deletion is not reliable on any modern Mac
  - **FileVault as the primary data-at-rest protection**: since secure
    deletion is unreliable, the guide MUST position FileVault (full-disk
    encryption) as the primary mechanism for protecting deleted data.
    When FileVault is enabled, deleted data remains on the SSD in
    encrypted form — an attacker who obtains the physical disk cannot
    read deleted data without the FileVault decryption key. This makes
    FileVault not just a theft defense but a deletion defense
  - **Crypto-shredding**: the most reliable way to permanently destroy
    data on an encrypted volume is crypto-shredding — destroying the
    encryption key. Apple's Erase All Content and Settings (or
    `diskutil secureErase`) performs crypto-shredding for the entire
    volume. For individual files, there is no crypto-shredding mechanism
    — the data remains on disk until TRIM reclaims the blocks, but is
    protected by FileVault encryption while it persists
  - **Time Machine snapshot implications**: when PII is deleted from
    n8n's database, it may persist in Time Machine local snapshots and
    backup volumes. The guide MUST cross-reference FR-013 (PII retention
    limits) and note that old Time Machine backups containing PII should
    be scheduled for destruction per the data retention policy.
    `tmutil deletelocalsnapshots` removes local snapshots but cannot
    selectively delete individual files from backups
  - **Practical deletion procedures**: for this deployment, the guide
    MUST document:
    - How to purge PII from n8n's database (workflow execution logs,
      stored lead data) using n8n CLI or database operations
    - How to delete n8n execution logs that contain PII (cross-ref
      FR-013)
    - How to remove Docker volumes containing PII (`docker volume rm`)
    - The fact that after deletion, the data remains encrypted on disk
      (via FileVault) until the SSD controller reclaims the blocks,
      which is the best achievable outcome on current hardware
  - Verification: not automated — this is educational content that
    informs the operator's data handling practices. The audit script's
    FileVault check (existing) is the technical verification
  *Source: Apple Platform Security Guide (Data Protection, APFS); NIST
  SP 800-88 Rev 1 (Guidelines for Media Sanitization — Section 2.5 SSD
  considerations); Apple Support (About encrypted storage on your Mac);
  APFS reference documentation.*

- **FR-087**: The guide MUST address clipboard (pasteboard) security as
  a credential exposure vector on the bare-metal deployment path. On
  macOS, the system pasteboard is accessible to all processes running
  as the same user. If the operator copies a password, API key, or
  N8N_ENCRYPTION_KEY to the clipboard, any process — including a
  compromised n8n Code node running as the same user — can read it via
  `pbpaste` or the NSPasteboard API. The section MUST cover:
  - **Clipboard exposure on bare-metal**: on the bare-metal path, n8n
    runs as a user account and Code nodes execute JavaScript in the
    same process. A malicious or injected Code node can read the
    clipboard via `require('child_process').execSync('pbpaste')
    .toString()`. The guide MUST warn operators to never copy sensitive
    credentials to the clipboard while n8n is running on bare-metal
  - **Containerized path advantage**: in the containerized deployment
    path, the n8n process runs inside the Colima VM and has no access
    to the macOS pasteboard. The guide MUST note this as another
    advantage of containerization for security-sensitive deployments
  - **Universal Clipboard cross-reference**: FR-071 addresses Universal
    Clipboard (syncing clipboard between Apple devices via iCloud/
    Handoff). This FR addresses the local clipboard accessible to
    processes on the same Mac Mini
  - **Operational security practices**: the guide MUST recommend:
    - Use a password manager (Bitwarden CLI, free) to inject
      credentials directly into configuration files or environment
      variables, avoiding the clipboard entirely
    - If clipboard use is unavoidable, clear the clipboard immediately
      after pasting: `pbcopy < /dev/null`
    - On bare-metal: run credential management tasks only when n8n is
      stopped, or with n8n running under the dedicated service account
      (FR-036) which cannot access the admin user's clipboard
  - **Clipboard monitoring detection**: for bare-metal, the guide MUST
    note that there is no reliable macOS mechanism to detect clipboard
    monitoring by a process running as the same user. This is a
    fundamental limitation of the same-user execution model,
    reinforcing the recommendation for containerization or service
    account isolation (FR-036)
  - Verification: not automated — this is operational security
    guidance. The audit script cannot monitor clipboard activity
  *Source: Apple Developer Documentation (NSPasteboard); MITRE ATT&CK
  T1115 (Clipboard Data); CIS Apple macOS Benchmarks (privacy
  controls).*

- **FR-090**: The guide MUST address environment variable and container
  metadata exposure as credential leakage vectors. Multiple tools and
  interfaces can reveal secrets that are passed via environment
  variables or stored in container configuration. The section MUST
  cover:
  - **`docker inspect` credential exposure**: `docker inspect
    <container>` displays the full container configuration including
    all environment variables in plaintext. If n8n's
    N8N_ENCRYPTION_KEY, database passwords, or API keys are set via
    environment variables in docker-compose.yml, any user with Docker
    access can read them via `docker inspect`. The guide MUST
    recommend:
    - Using Docker secrets instead of environment variables for
      sensitive values (cross-ref FR-016, FR-058)
    - Restricting Docker socket access to root only (the default on
      Colima, but may be changed if the operator adds their user to
      the docker group)
    - Being aware that `docker inspect` is a credential disclosure
      vector during container forensics and debugging
  - **Process listing exposure**: on bare-metal, `ps aux` shows
    command-line arguments passed to processes. If secrets are passed
    as command-line arguments (e.g., `n8n start --encryption-key=...`),
    they are visible to any user on the system. Additionally,
    `/proc/<pid>/environ` (on Linux inside the Colima VM) exposes
    all environment variables of a running process. The guide MUST
    recommend:
    - Never passing secrets via command-line arguments — use files,
      launchd plist EnvironmentVariables (not visible in `ps`), or
      Docker secrets
    - For containerized: secrets should be mounted via Docker secrets
      (`/run/secrets/`), not passed as environment variables
    - Cross-reference FR-044 (execution model) and FR-057 (credential
      access patterns)
  - **Docker log credential leakage**: n8n's stdout/stderr may include
    environment variable references in error messages or debug output.
    If Docker logging is set to `json-file` (default), these logs are
    stored in plaintext on the host at
    `/var/lib/docker/containers/<id>/<id>-json.log` (inside the Colima
    VM). The guide MUST recommend:
    - Setting n8n log level to `warn` or `info` (not `debug`) in
      production (cross-ref FR-059)
    - Configuring Docker log rotation via the `max-size` and
      `max-file` logging options in docker-compose.yml to limit the
      window of credential exposure
    - Reviewing Docker logs before sharing them for debugging — redact
      any secrets that appear in error messages
  - **Compose file credential exposure**: the docker-compose.yml may
    contain secrets in plaintext if the operator uses `environment:`
    directives instead of `secrets:`. The guide MUST verify this is
    addressed in FR-058 and cross-reference the reference compose file
    which uses Docker secrets for all sensitive values
  - Verification: audit script checks whether `docker inspect` on the
    running n8n container reveals environment variables matching secret
    patterns (N8N_ENCRYPTION_KEY, PASSWORD, TOKEN, SECRET, API_KEY) —
    WARN if secrets are found in environment variables, recommending
    Docker secrets instead
  *Source: CIS Docker Benchmark v1.6 (Section 5: Container Runtime —
  environment variable exposure); Docker documentation (Docker
  Secrets); NIST SP 800-190 (Application Container Security Guide);
  OWASP (Secrets in Environment Variables).*
