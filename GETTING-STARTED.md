# Hardening Your Mac

15 minutes to harden your Mac. Works on Apple Silicon and Intel.

> Recommended: back up with Time Machine before starting.

---

## TL;DR

If you already have Homebrew and git:

```bash
cd ~/
git clone https://github.com/traylorre/openclaw-mac.git
cd openclaw-mac
make install
make doctor
make audit
make fix
make verify
```

If anything looks wrong, read the detailed steps below.

---

## What each command does — and how to undo it

| Do | Undo | What changes |
|----|------|-------------|
| `make install` | `make uninstall` | Creates `/opt/n8n/`, deploys scripts, installs Homebrew packages (bash, jq, shellcheck). Brew packages are kept on uninstall — remove with `brew bundle cleanup --file=Brewfile --force` |
| `make fix` or `make fix-interactive` | `make fix-undo` | Modifies macOS security settings (firewall, Siri, AirDrop, etc.). Creates a restore script so changes can be undone individually or all at once. `fix-interactive` prompts before each change |
| `make setup-gateway` | `make teardown-gateway` | Starts Colima VM, creates Docker containers/volumes, stores bearer token in Keychain |
| `make shellrc` | `make shellrc-undo` | Creates shell aliases in `~/.openclaw/shellrc`, adds source line to shell profile. Re-run if you move the repo |

Read-only commands (no undo needed): `make audit`, `make fix-dry-run`,
`make verify`, `make help`

For a full list of all audit checks: see
[scripts/CHK-REGISTRY.md](scripts/CHK-REGISTRY.md).

---

## Step 1: Install Homebrew

Skip this step if `brew --version` already works.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

When it finishes, Homebrew prints **"Next steps"** with commands to add
it to your PATH. **Copy and paste those commands exactly as shown** —
they differ between Apple Silicon and Intel Macs.

Verify: `brew --version` should print `Homebrew 4.x.x` or later.

---

## Step 2: Clone and bootstrap

```bash
cd ~/
git clone https://github.com/traylorre/openclaw-mac.git
cd openclaw-mac
make install
make doctor
```

`make doctor` checks that all prerequisites are in place (Bash 5.x, jq,
shellcheck, correct PATH). If it reports issues, fix them before
continuing — the remaining steps depend on these tools.

> **Do not run `make install` with `sudo`.** The bootstrap handles
> elevated privileges internally. Running as root breaks Homebrew.
>
> **First time using git?** macOS may prompt to install Command Line
> Tools. Click Install, wait, then re-run the commands above.

---

## Step 3: Audit and fix

```bash
make audit
make fix
```

`make audit` displays your Mac's security posture and saves the results.
`make fix` applies safe fixes automatically (firewall, guest account,
AirDrop, Siri, screen lock, etc.). Every change is recorded in a
restore script.

> **Want to preview first?** Run `make fix-dry-run` to see what would
> change without modifying anything.
>
> **Want to approve each change?** Run `make fix-interactive` instead
> of `make fix`.

---

## Step 4: Verify

```bash
make verify
```

Checks that all expected files, directories, and services are in place.
`DOWN` for Colima/n8n is normal if you haven't deployed the gateway yet.

---

## Step 5: Workspace integrity

> **Prerequisite**: Steps 1-4 must be complete before this step.

```bash
make integrity-deploy
make integrity-lock
make monitor-setup
```

`make integrity-deploy` creates the HMAC-signed integrity manifest.
`make integrity-lock` sets `uchg` flags on protected workspace files.
`make monitor-setup` starts the background file monitor (fswatch).

> **After this step, workspace files will be locked.** Edits to
> protected files (SOUL.md, AGENTS.md, TOOLS.md, skill files) will
> silently fail unless you unlock first. See
> [docs/BEHAVIORS.md](docs/BEHAVIORS.md) for how to edit protected
> files and what the "new normal" looks like.

Check your environment before continuing:

> **Dangerous environment variables**: If you have `NODE_OPTIONS`,
> `DYLD_INSERT_LIBRARIES`, `DYLD_LIBRARY_PATH`, `PYTHONPATH`, or
> similar variables set in your shell profile, the audit will FAIL and
> agent startup may be blocked. Unset them before proceeding:
> `unset NODE_OPTIONS` (repeat for each variable). See
> [docs/BEHAVIORS.md](docs/BEHAVIORS.md) for the full list of 15
> blocked variables.

---

## Step 6: sudoers secure_path

By default, `sudo` on macOS inherits your user PATH, which may include
18+ directories in your home folder (`~/.bun/bin`, `~/.cargo/bin`,
etc.). An attacker who can write to any of those directories could place
a trojan binary that `sudo` would execute as root.

Fix this by adding a `secure_path` to sudoers:

```bash
EDITOR=nano sudo visudo
```

Add this line at the end of the file:

```text
Defaults    secure_path="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
```

Save and exit (`Ctrl+O`, `Enter`, `Ctrl+X` in nano).

> **Warning**: Do not make other changes to the sudoers file. A syntax
> error in sudoers can lock you out of `sudo` entirely. If that happens,
> reboot into Recovery Mode and fix the file from there.

---

## Package managers

This repo uses three package managers, each for a different purpose:

| Manager | Purpose | Install method |
|---------|---------|---------------|
| Homebrew | System tools: bash 5.x, jq, shellcheck, docker, colima, fswatch, grype | `make install` (via Brewfile) |
| npm | Dev dependency: markdownlint-cli2 for pre-push markdown linting | `npm install` (via package.json) |
| Bun | OpenClaw runtime (the AI agent itself) | `curl -fsSL https://bun.sh/install \| bash` |

All three are needed. Homebrew provides macOS system tools that Apple
does not ship (or ships outdated versions of). npm provides the linting
tool that CI uses. Bun is the runtime that OpenClaw requires.

---

## What was changed

All fixes are standard macOS security recommendations:

| Setting | What it does |
|---------|-------------|
| Application Firewall | Blocks unsolicited incoming connections |
| Stealth Mode | Mac does not respond to network probes |
| Automatic Updates | Ensures security patches install automatically |
| Network Time (NTP) | Keeps system clock accurate (important for logging) |
| Screen Lock | Requires password immediately when screen locks |
| Guest Account | Disables the guest login |
| Remote Apple Events | Disables remote scripting access |
| AirDrop | Disables file sharing over local network |
| Core Dumps | Prevents memory dumps that could contain sensitive data |
| Siri | Disables Siri (which sends voice data to Apple servers) |
| Bluetooth Discovery | Prevents the Mac from advertising itself over Bluetooth |

None of these affect normal Mac usage. To re-enable any setting, see
[Undoing changes](#undoing-changes).

> **FileVault** (disk encryption) is the only setting that requires a
> reboot. All other changes take effect immediately. `make fix` does
> not enable FileVault automatically — it requires interactive approval
> via `make fix-interactive`.

---

## Undoing changes

Run `make fix-undo` to undo the most recent fix run. It shows what
will be undone and asks for confirmation.

To undo a single change instead of all:

```bash
sudo bash /opt/n8n/logs/audit/pre-fix-restore-TIMESTAMP.sh CHK-AIRDROP
```

Each check is independent — undoing one does not affect others. For
example, re-enabling AirDrop does not change the firewall setting.

> **After uninstall:** restore scripts are preserved in
> `~/.openclaw/restore-scripts/`.

---

## Next steps

- **Deploy the n8n gateway:**

  ```bash
  make setup-gateway
  ```

  Opens `http://localhost:5678` for n8n setup. Use Chrome, not Safari.
  To stop: `make teardown-gateway`. To restart: `make setup-gateway`.

- **Set up shell aliases:** `make shellrc` (undo: `make shellrc-undo`)

- **Enable scheduled audits:**

  ```bash
  sudo launchctl bootstrap system /Library/LaunchDaemons/com.openclaw.audit-cron.plist
  ```

  This loads a launchd job installed by bootstrap that runs the audit
  on a schedule and saves results to `/opt/n8n/logs/audit/`.

- **Set up a browser** for automation (CDP):

  ```bash
  brew install --cask chromium
  ```

  Google Chrome and Microsoft Edge also work. Run `make audit` after
  installing to verify browser security checks.

- **Clean browser session data** after automation runs:
  `bash scripts/browser-cleanup.sh`

- **Set a firmware password** (Intel only): requires Recovery Mode
  (restart, hold Cmd + R). See
  [docs/HARDENING.md §2.9](docs/HARDENING.md).

- **Understand the new normal**: After hardening, your repo behaves
  differently. See [docs/BEHAVIORS.md](docs/BEHAVIORS.md) for what
  changed and how to work within the restrictions.

- **Why each restriction exists**:
  [docs/SECURITY-VALUE.md](docs/SECURITY-VALUE.md) maps each control
  to NIST 800-53r5 standards and explains the security value.

- **How this compares to NemoClaw**:
  [docs/FEATURE-COMPARISON.md](docs/FEATURE-COMPARISON.md) shows what
  this repo provides that NVIDIA's cloud sandbox doesn't (and vice
  versa).

---

## Troubleshooting

### "command not found: brew"

Run the PATH setup commands that Homebrew printed during installation.
Apple Silicon: `eval "$(/opt/homebrew/bin/brew shellenv)"`.
Intel: `eval "$(/usr/local/bin/brew shellenv)"`.
If unsure, close Terminal and reopen it.

### "No audit JSON files found"

Run `make audit` first — it saves the JSON that `make fix` needs.

### Audit shows FAIL but fix says SKIPPED

Some checks need interactive approval: run `make fix-interactive`.

### "Operation not permitted"

A file has the `uchg` (user immutable) flag set by the integrity
framework. Run `make integrity-unlock` to temporarily remove the lock,
make your edit, then `make integrity-lock` and `make manifest-update`.
See [docs/BEHAVIORS.md](docs/BEHAVIORS.md) for detailed workflows.

### "No firmware password set (Intel)" WARN

Expected on Intel Macs. Optional — see Next Steps above.

---

## Reference

- Full hardening guide: [docs/HARDENING.md](docs/HARDENING.md)
- All audit checks: [scripts/CHK-REGISTRY.md](scripts/CHK-REGISTRY.md)
- `bash scripts/hardening-audit.sh --help`
- `bash scripts/hardening-fix.sh --help`
- `bash scripts/bootstrap.sh --help`
