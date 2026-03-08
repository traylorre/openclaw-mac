# Spec Module: n8n Platform Security

**Parent spec**: [spec.md](spec.md) (Rev 29)
**Module scope**: n8n application configuration, API security, webhook hardening, node restrictions, updates, and troubleshooting.

## Functional Requirements

- **FR-011**: The guide MUST include an n8n-specific hardening section
  covering: localhost binding, authentication, credential encryption
  at rest, community node supply chain risk, webhook authentication
  (cross-reference FR-039 for full webhook security), workload
  isolation, REST API access control (cross-reference FR-038 for full
  API security), and a cross-reference to the scraped data input
  security section (FR-021) for injection defense. The section MUST
  present two deployment paths: (a) containerized via Docker
  (recommended) and (b) bare-metal with dedicated service account
  (alternative). Both paths must be complete and independently
  followable.
  *Source: n8n security documentation; OWASP Top 10 (A01 Broken Access Control, A02 Cryptographic Failures, A03 Injection); OWASP LLM Top 10 (LLM01 Prompt Injection); CIS Docker Benchmark v1.6.*

- **FR-038**: The guide MUST include an n8n REST API security section
  addressing the API as a critical attack surface. n8n exposes a REST
  API (default: same port as the web UI) that can create, modify,
  delete, and execute workflows, as well as read and write stored
  credentials. An attacker who can reach the API can achieve
  persistent arbitrary code execution by creating a workflow with a
  Code or Execute Command node. The section MUST cover:
  - **API access control**: disable the API entirely if not needed
    (`N8N_PUBLIC_API_ENABLED=false`); if needed, require API key
    authentication and document how to generate and rotate API keys
  - **API network binding**: the API MUST NOT be reachable from the
    network — it shares the web UI binding, so localhost binding
    (FR-011) protects it, but the guide MUST explicitly call out that
    the API is a separate attack surface from the UI
  - **API key storage**: API keys MUST be treated as credentials with
    the same storage requirements as other secrets (Keychain, Docker
    secrets, or Bitwarden — never in plaintext config files)
  - **Workflow modification detection**: the guide MUST recommend
    monitoring for unexpected workflow changes via n8n's execution
    log or API audit trail — an attacker who gains API access will
    create or modify workflows to establish persistence (MITRE
    ATT&CK T1053.005 Scheduled Task, T1059 Command and Scripting
    Interpreter)
  - **API rate limiting**: if the API is enabled, recommend rate
    limiting (reverse proxy or n8n's built-in settings if available)
    to slow credential brute force attempts
  - For containerized deployments: the API is only reachable via the
    mapped port, which is bound to localhost. For bare-metal: the API
    runs in the same process as n8n and is accessible to any user who
    can reach the n8n port
  - Verification: audit script checks `N8N_PUBLIC_API_ENABLED` setting
    and warns if the API is enabled without authentication
  *Source: OWASP Top 10 (A01 Broken Access Control); n8n API
  documentation; MITRE ATT&CK T1106 (Native API), T1059.007
  (JavaScript).*

- **FR-039**: The guide MUST include a webhook security section
  addressing webhooks as inbound attack vectors. Every n8n Webhook
  node creates an HTTP endpoint that accepts external requests. If
  webhooks are accessible from the internet (e.g., for receiving
  Apify completion callbacks), they are a direct entry point for
  attackers. The section MUST cover:
  - **Webhook authentication**: document all n8n webhook
    authentication methods — Header Auth (shared secret in a custom
    header), Basic Auth (username/password), and webhook-specific
    tokens. The guide MUST recommend Header Auth with a
    cryptographically random secret as the minimum, and explain why
    unauthenticated webhooks are equivalent to an open API endpoint
  - **Webhook path unpredictability**: n8n generates webhook paths
    using the workflow ID and node name by default, which are
    predictable. The guide MUST recommend using the "webhook path"
    setting with a random UUID or the production webhook URL (which
    uses a random path) instead of test webhooks in production
  - **Webhook IP allowlisting**: if webhooks only need to receive
    requests from known sources (e.g., Apify's IP ranges), the guide
    MUST show how to restrict access via pf rules or a reverse proxy
    that validates source IP
  - **Webhook rate limiting**: document how to rate-limit webhook
    endpoints to prevent abuse (denial of service, credential
    stuffing via webhook-triggered workflows)
  - **Webhook payload validation**: webhook-triggered workflows MUST
    validate incoming payloads against an expected schema before
    processing — never trust the structure or content of webhook
    data. Cross-reference FR-021 (injection defense) for data that
    reaches code execution nodes
  - **Reverse proxy for webhook ingress**: if webhooks must be
    internet-facing, the guide MUST recommend placing them behind a
    reverse proxy (e.g., Caddy or nginx, both free) that handles TLS
    termination, rate limiting, IP filtering, and request logging.
    The n8n instance MUST NOT be directly exposed to the internet
  - Verification: audit script checks whether any webhook nodes lack
    authentication configuration (WARN) and whether n8n is directly
    internet-exposed without a reverse proxy (FAIL if port 5678 is
    bound to 0.0.0.0)
  *Source: OWASP Top 10 (A01 Broken Access Control, A07 Server-Side
  Request Forgery); MITRE ATT&CK T1190 (Exploit Public-Facing
  Application); n8n webhook documentation.*

- **FR-044**: The guide MUST include a section on n8n's execution
  model and process-level credential isolation, documenting the
  security implications of how n8n executes Code and Function nodes:
  - **No sandbox**: n8n Code nodes execute JavaScript in the same
    Node.js process as n8n itself. There is NO sandbox — a Code node
    can access `process.env` (all environment variables including
    `N8N_ENCRYPTION_KEY`), `require()` any Node.js module, make
    network requests, read/write the filesystem (subject to OS
    permissions), and access n8n's internal APIs. The guide MUST make
    this fact explicit because operators often assume Code nodes are
    sandboxed
  - **Credential cross-access**: in n8n's default configuration, a
    Code node in any workflow can potentially access credentials
    stored for other workflows via n8n's internal database or API.
    The guide MUST document this risk and recommend:
    - `N8N_BLOCK_ENV_ACCESS_IN_NODE=true` to prevent Code nodes from
      reading environment variables (this blocks access to
      `N8N_ENCRYPTION_KEY` and other secrets passed via env vars)
    - `N8N_RESTRICT_FILE_ACCESS_TO` to limit filesystem access
    - For bare-metal: the Code node runs as whatever user n8n runs
      as — if that is the admin user, Code nodes have admin access
      to the entire system (reinforces FR-036 service account)
    - For containerized: the Code node runs inside the container, so
      filesystem and network access are limited by container
      isolation — but the Code node can still access all n8n
      credentials within the container
  - **Execute Command node process model**: Execute Command nodes
    spawn a child process (shell) that inherits n8n's environment
    and user context. On bare-metal, this is a full shell as the n8n
    user. In a container, this is a shell inside the container. The
    guide MUST document that Execute Command + scraped data = remote
    code execution, regardless of deployment path
  - **Workflow-level isolation**: n8n does not provide workflow-level
    isolation — all workflows share the same process, same
    credentials database, and same environment. The guide MUST
    recommend separating high-risk workflows (those processing
    scraped data) from low-risk workflows (those managing
    credentials or system configuration) by running them in separate
    n8n instances if the operator's threat model warrants it
  - Verification: audit script checks `N8N_BLOCK_ENV_ACCESS_IN_NODE`
    (WARN if not set) and `N8N_RESTRICT_FILE_ACCESS_TO` (WARN if not
    set)
  *Source: n8n security documentation; OWASP Top 10 (A03 Injection);
  MITRE ATT&CK T1059.007 (JavaScript), T1059.004 (Unix Shell); NIST
  SP 800-123 Section 4.1 (Least Privilege).*

- **FR-054**: The guide MUST include a community node vetting
  checklist that operators follow before installing any n8n community
  node. Community nodes are npm packages that execute arbitrary code
  within the n8n process — they have full access to n8n's environment,
  credentials, and filesystem. The checklist MUST include:
  - **Source verification**: check the npm page for a link to a public
    source repository (GitHub, GitLab). No source repo = do not
    install
  - **Maintainer reputation**: check the npm publisher's profile for
    other packages, publication history, and whether the account
    appears legitimate. A brand-new account with one package is high
    risk
  - **Download volume**: check weekly download count. Community nodes
    with <100 weekly downloads have minimal community vetting. This
    is not a guarantee of safety but low-download packages are more
    likely to be typosquatting or abandoned
  - **Version history**: check for recent updates and version
    churn. A package that has been stable for months and suddenly
    publishes a new version could indicate maintainer account
    compromise
  - **Dependency audit**: run `npm audit` on the package before
    installation. Check the dependency tree for known vulnerabilities
    and suspicious nested dependencies
  - **Code review**: for high-risk nodes (those that handle credentials
    or make network requests), review the source code for:
    - Obfuscated code or minified bundles without source maps
    - `eval()`, `Function()`, or dynamic `require()` calls
    - Outbound network requests to hardcoded URLs
    - Postinstall scripts that download or execute external code
    - File system access outside expected paths
  - **Installation procedure**: always install with `--ignore-scripts`
    first, review the postinstall scripts, then re-install if they
    are safe. Never install community nodes on the same n8n instance
    that handles sensitive credentials if they haven't been code-
    reviewed
  - The guide MUST note that even a legitimate community node can be
    compromised later via maintainer account takeover — the vetting
    checklist reduces but does not eliminate supply chain risk
  *Source: npm security documentation; OWASP Top 10 (A08 Software and
  Data Integrity Failures); MITRE ATT&CK T1195.001 (Compromise
  Software Dependencies and Development Tools); n8n community node
  documentation.*

- **FR-055**: The guide MUST include a reverse proxy section for
  operators who need remote access to the n8n web UI or who expose
  webhooks to the internet. n8n MUST NOT be directly exposed to the
  network — a reverse proxy provides TLS termination, authentication,
  rate limiting, and request logging that n8n alone does not offer.
  The section MUST cover:
  - **Why a reverse proxy**: n8n's built-in web server does not
    support TLS (HTTPS) natively and has limited authentication
    options. Exposing n8n directly to the internet means credentials
    are transmitted in cleartext (on non-TLS connections) and the
    full attack surface (API, webhooks, UI) is reachable
  - **Recommended proxies**: Caddy (free, automatic TLS via Let's
    Encrypt, simple config) as primary recommendation; nginx (free,
    widely documented) as alternative. Both are installable via
    Homebrew
  - **Remote UI access**: if the operator needs to access the n8n web
    UI from outside the LAN, the guide MUST recommend:
    - Option A (preferred): SSH tunnel (`ssh -L 5678:localhost:5678`)
      for occasional access — no additional software, encrypted,
      requires SSH key
    - Option B: reverse proxy with TLS + client certificate
      authentication or HTTP basic auth (for persistent remote
      access). The proxy should only expose the n8n UI path, not the
      API (unless specifically needed)
  - **Webhook exposure**: if webhooks must receive external requests,
    the reverse proxy should expose only the webhook paths
    (`/webhook/*`) and block all other n8n paths (`/api/*`, `/rest/*`,
    `/`) from external access. Cross-reference FR-039 (webhook
    security)
  - **Logging**: the reverse proxy MUST log all requests (source IP,
    path, response code, timestamp) to enable forensic analysis of
    webhook abuse and unauthorized access attempts
  - **For containerized deployments**: the reverse proxy can run as a
    second container in the same Docker Compose stack, receiving
    traffic on port 443 and proxying to the n8n container on port
    5678 (internal Docker network only — n8n is not port-mapped to
    the host)
  - Verification: audit script checks whether n8n's port (5678) is
    directly exposed to non-localhost interfaces (FAIL if bound to
    0.0.0.0 without a reverse proxy)
  *Source: OWASP Top 10 (A02 Cryptographic Failures, A01 Broken
  Access Control); CIS Docker Benchmark v1.6; NIST SP 800-123
  Section 4 (Securing the OS).*

- **FR-059**: The guide MUST include a comprehensive n8n security
  environment variable reference listing all security-relevant
  configuration options. Operators often miss critical settings
  because n8n's documentation scatters them across multiple pages.
  The guide MUST document these as a single reference table:
  - **Authentication and access**:
    - `N8N_BASIC_AUTH_ACTIVE` / `N8N_BASIC_AUTH_USER` /
      `N8N_BASIC_AUTH_PASSWORD`: enable/configure basic auth for the
      web UI
    - `N8N_PUBLIC_API_ENABLED`: enable/disable the REST API (FR-038)
    - `N8N_EDITOR_BASE_URL`: base URL for the editor (relevant for
      reverse proxy configuration per FR-055)
  - **Execution security**:
    - `N8N_BLOCK_ENV_ACCESS_IN_NODE`: prevent Code nodes from reading
      environment variables (critical — blocks N8N_ENCRYPTION_KEY
      leakage)
    - `N8N_RESTRICT_FILE_ACCESS_TO`: restrict filesystem access from
      Code nodes
    - `EXECUTIONS_PROCESS`: `main` (default, all in one process) vs
      `own` (separate process per execution — slightly better
      isolation but higher resource use)
    - `N8N_PERSONALIZATION_ENABLED`: disable to reduce data collection
  - **Telemetry and information leakage**:
    - `N8N_DIAGNOSTICS_ENABLED`: controls telemetry data sent to n8n.
      The guide MUST recommend disabling (`false`) for security-
      sensitive deployments — telemetry can reveal deployment details
      to n8n's servers
    - `N8N_HIRING_BANNER_ENABLED`: disable to remove the hiring
      banner (reduces UI noise, minor information leakage)
    - `N8N_TEMPLATES_ENABLED`: disable to prevent loading workflow
      templates from n8n's servers (reduces outbound connections and
      prevents template-based social engineering)
    - `N8N_VERSION_NOTIFICATIONS_ENABLED`: disable to prevent version
      check requests to n8n's servers (reduces outbound connections;
      manual version tracking via FR-026 instead)
  - **Credential security**:
    - `N8N_ENCRYPTION_KEY`: master key for credential encryption
      (FR-043 rotation, FR-045 backup, FR-057 access pattern)
    - `N8N_USER_MANAGEMENT_JWT_SECRET`: secret for JWT token signing
      (must be unique and strong)
  - **Logging**:
    - `N8N_LOG_LEVEL`: set to `warn` or `info` for production (not
      `debug` — debug logging may include sensitive data in logs)
    - `N8N_LOG_OUTPUT`: configure log destination
    - `EXECUTIONS_DATA_SAVE_ON_ERROR` /
      `EXECUTIONS_DATA_SAVE_ON_SUCCESS`: control what execution data
      is retained (PII implications per FR-013)
  - For each variable, the guide MUST state: recommended value,
    security rationale, and what risk is introduced by the default
  - Verification: audit script checks critical env vars
    (N8N_BLOCK_ENV_ACCESS_IN_NODE, N8N_DIAGNOSTICS_ENABLED,
    N8N_PUBLIC_API_ENABLED) and reports WARN if not configured
  *Source: n8n environment variable documentation; OWASP Top 10
  (A05 Security Misconfiguration); CIS Docker Benchmark v1.6.*

- **FR-064**: The guide MUST include an n8n update and migration
  security section covering the security implications of upgrading
  n8n versions. Version upgrades can silently change security-relevant
  defaults, introduce new node types, or run database migrations that
  alter how credentials are stored. The section MUST cover:
  - **Pre-update checklist**: before updating n8n, the operator MUST:
    - Back up the n8n database and credentials (FR-018)
    - Record the current workflow baseline hash (FR-046)
    - Review the n8n release notes for security-relevant changes
      (new node types, changed defaults, deprecated env vars)
    - For containerized: record the current image digest before
      pulling the new image
  - **Post-update verification**: after updating, the operator MUST:
    - Run the full audit script to verify all hardening controls are
      intact — n8n updates may reset environment variable defaults
    - Verify that security-relevant env vars (FR-059) are still
      applied (a new n8n version might rename or deprecate a setting)
    - Verify that disabled node types remain disabled (a new version
      might add new code-execution-capable nodes)
    - Check that the workflow baseline has not changed unexpectedly
      (migration scripts may modify workflow structure)
    - Verify that n8n credentials still decrypt correctly (migration
      may change encryption format)
  - **Containerized update procedure**: for Docker deployments, the
    guide MUST document: pull new image by digest (FR-040), stop
    current container, start with new image using same compose file
    (FR-058), run verification. Emphasize that the compose file
    security options MUST NOT be modified during the update
  - **Bare-metal update procedure**: for npm-based deployments, the
    guide MUST document: `npm update -g n8n`, run post-update
    verification, check for new postinstall scripts (FR-040 supply
    chain risk)
  - **Rollback procedure**: if the update breaks functionality or
    security controls, the guide MUST document how to roll back to
    the previous version (restore Docker image by digest, or
    `npm install -g n8n@<previous-version>`) and restore the database
    from pre-update backup
  *Source: NIST SP 800-40 Rev 4 (Guide to Enterprise Patch
  Management Planning); CIS Controls v8 (Control 7: Continuous
  Vulnerability Management); n8n migration documentation.*

- **FR-066**: The guide MUST include troubleshooting guidance for
  common failures that occur when applying hardening controls. Each
  deployment path has specific failure modes:
  - **Containerized path failures**:
    - Container fails to start with `read_only: true` — identify
      which directories need tmpfs mounts (n8n cache, temp files)
    - Container fails with `cap_drop: [ALL]` — identify if any
      specific capability is required and document it
    - Container cannot reach external services after pf outbound
      rules — verify the allowlist includes all required destinations
    - n8n credentials fail to decrypt after container rebuild —
      verify N8N_ENCRYPTION_KEY is correctly injected via secrets
  - **Bare-metal path failures**:
    - n8n fails to start under the dedicated service account — verify
      filesystem permissions on the data directory, check that the
      account has no login shell but can still run processes via
      launchd
    - Keychain access fails on headless server — verify Keychain
      unlock procedure in launchd pre-start script
    - Service account cannot install npm packages — this is expected;
      npm operations should be run as admin, not the service account
  - **Common failures (both paths)**:
    - SSH lockout after hardening — recovery procedure: physical
      access, Screen Sharing (if enabled), or single-user mode boot
    - Firewall blocks legitimate traffic — how to temporarily disable
      and re-configure without removing security controls
    - Audit script reports false FAILs after macOS update — how to
      determine if the check logic needs updating vs the control
      actually regressed
  - Each troubleshooting entry MUST include: symptom, likely cause,
    resolution steps, and how to fix it without disabling the
    security control
  *Source: CIS Apple macOS Benchmarks (remediation sections); Docker
  troubleshooting documentation.*

- **FR-067**: The guide MUST address n8n's built-in user management
  system and its interaction with the hardening guide's authentication
  recommendations. Newer versions of n8n include multi-user support
  with roles (owner, member, admin). The section MUST cover:
  - **Relationship to basic auth**: n8n's built-in user management
    replaces basic auth. If user management is enabled, the guide
    MUST recommend using it instead of basic auth (stronger session
    management, role separation, audit trail)
  - **Owner account security**: the n8n owner account has full system
    access (workflow creation, credential management, user management,
    API access). The guide MUST recommend:
    - Strong, unique password for the owner account
    - Limit owner accounts to one (the primary operator)
    - Create member accounts for any additional users with minimal
      permissions
  - **Security implications**: n8n user management does NOT add
    workflow-level isolation — all users can see all workflows (by
    default). The guide MUST note that user management provides
    authentication and audit trail but does not provide the
    credential isolation described in FR-044
  - **MFA/2FA**: if n8n supports multi-factor authentication, the
    guide MUST recommend enabling it. If not supported, the guide
    MUST note this gap and recommend compensating controls (reverse
    proxy with MFA per FR-055, strong password + IP restriction)
  - Verification: audit script checks whether n8n authentication is
    enabled (FAIL if no auth — either basic auth or user management
    must be active)
  *Source: n8n user management documentation; OWASP Top 10 (A01
  Broken Access Control, A07 Identification and Authentication
  Failures).*
