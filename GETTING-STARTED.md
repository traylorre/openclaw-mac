# Hardening Your Mac

This guide walks you through securing a Mac using the OpenClaw
hardening toolkit. Works on both Apple Silicon and Intel Macs. Every
command is copy-pasteable. The process takes about 15 minutes.

**What the scripts do:**

- **Audit** your Mac's security settings and report what is and isn't
  configured (read-only, changes nothing)
- **Fix** common security gaps like enabling the firewall, disabling
  guest accounts, and turning off unnecessary sharing services
- **Snapshot** your settings before making changes, so any individual
  fix can be reversed

n8n is not required. The audit will skip n8n-related checks if it is
not installed. You can deploy n8n later and re-run the audit at any
time.

> If your Mac is not a fresh install, skip to
> [Step 3: Clone This Repository](#step-3-clone-this-repository).
> The bootstrap script detects what you already have and only installs
> what is missing.

---

## Before You Begin

- A Mac (Apple Silicon M1+ or Intel 2009+)
- The admin account you created during Mac setup
- An internet connection
- Optional: a Time Machine backup (recommended before any system changes)

---

## Step 1: Open Terminal

Open **Terminal** from one of these locations:

- Spotlight: press **Cmd + Space**, type `Terminal`, press Enter
- Finder: Applications > Utilities > Terminal

You will use Terminal for all remaining steps.

---

## Step 2: Install Homebrew

Homebrew is a package manager that installs developer tools.
macOS does not include it by default.

Paste this command and press Enter:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

This may take a few minutes. Follow the on-screen prompts when they
appear.

**Apple Silicon (M1+):** When Homebrew finishes, it will print
**"Next steps"** with commands to add Homebrew to your PATH. Copy and
paste those commands exactly as shown. They will look similar to this:

```bash
echo >> ~/.zprofile
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

**Intel:** Homebrew installs to `/usr/local` and is usually available
immediately — no PATH setup needed. If you see `command not found`,
add it manually:

```bash
echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/usr/local/bin/brew shellenv)"
```

Verify it worked:

```bash
brew --version
```

You should see output like:

```text
Homebrew 4.x.x
```

If you see `command not found`, close Terminal completely (Cmd + Q),
reopen it, and try `brew --version` again.

> **Already have Homebrew?** If `brew --version` already works, skip
> to Step 3.

---

## Step 3: Clone This Repository

This downloads the hardening scripts to your Mac:

```bash
git clone https://github.com/traylorre/openclaw-mac.git
cd openclaw-mac
```

> **First time using git?** macOS may show a popup window asking to
> install Command Line Tools. Click **Install**, wait for it to finish
> (this can take several minutes), then run the two commands above
> again.

---

## Step 4: Run Bootstrap

The bootstrap script installs two required tools (`bash 5` and `jq`),
creates the directory structure the scripts expect, and validates
that everything is ready.

```bash
make install
```

Your Mac will ask for your password when the script needs elevated
access. This is your Mac login password, not an Apple ID password.
You will not see the characters as you type.

> **Note:** Do not run this with `sudo`. The bootstrap script handles
> elevated privileges internally where needed. Running the entire script
> as root can cause problems with Homebrew.

You should see output similar to this:

```text
OpenClaw Bootstrap v0.1.0
Mode: install (will install dependencies and create directories)

[1/8] Platform Check
  ✓  macOS detected
  ℹ  Architecture: arm64 (or x86_64 on Intel)

[2/8] Homebrew
  ✓  Homebrew installed: Homebrew 4.x.x

[3/8] Required Tools
  ✓  bash 5.x: ...
  ✓  jq: jq-1.x
  —  shellcheck not installed (optional)
  —  msmtp not installed (optional)
  ✓  sqlite3: available
...

════════════════════════════════════════
  16 OK  |  11 FIXED  |  0 ERRORS
════════════════════════════════════════
```

Here is what the symbols mean:

- `✓` or **OK** — already in place, no action taken
- `+` or **FIXED** — the bootstrap installed or created this for you
- `—` — optional, can be ignored
- `✗` or **ERRORS** — something needs attention before continuing

---

## Step 5: Run the Security Audit

The audit reads your Mac's current security settings, displays the
results, and saves them for the fix script.

```bash
make audit
```

You should see output similar to this (your results will vary based
on your Mac's current configuration):

```text
================================================================
  OpenClaw Mac Hardening Audit
================================================================

[Section: System Integrity Protection]
  PASS  SIP is enabled                               → §2.3

[Section: Firewall]
  FAIL  Application firewall is disabled             → §2.2
  WARN  Stealth mode is not enabled                  → §2.2
  ...

================================================================
  Results: 17 PASS | 5 FAIL | 22 WARN | 19 SKIP
================================================================

Audit results saved. Run 'make fix' to apply fixes.
```

**What the statuses mean:**

| Status | Meaning |
|--------|---------|
| **PASS** | This setting is configured correctly. No action needed. |
| **FAIL** | This setting needs to be fixed. The fix script can handle most of these. |
| **WARN** | This setting could be improved. Review and decide if it applies to your setup. |
| **SKIP** | This check was skipped because it does not apply (e.g., n8n is not installed). |

SKIP results for n8n, Docker, and Chromium are expected if those tools
are not installed. They will be checked automatically when you install
them later.

> **Intel Macs:** You may see a WARN for "No firmware password set
> (Intel)." This is normal. See [Next Steps](#next-steps) for how to
> set one.

---

## Step 6: Preview Fixes (Optional)

Before making any changes, preview what the fix script would do:

```bash
make fix-dry-run
```

This shows every command that would run without actually executing it.
Review the output. Each line marked `[DRY-RUN]` shows the exact
command. Nothing is changed on your Mac during this step.

---

## Step 7: Apply Fixes

When you are ready, apply the fixes:

```bash
make fix
```

Your Mac may ask for your password again. You should see output similar
to this:

```text
================================================================
  OpenClaw Mac Hardening Fix
  Mode: auto | Dry-run: false
  Checks to process: 27
================================================================

  FIXED       CHK-FIREWALL    Enabled application firewall
  FIXED       CHK-STEALTH     Enabled firewall stealth mode
  FIXED       CHK-GUEST       Disabled guest account
  FIXED       CHK-AIRDROP     Disabled AirDrop
  FIXED       CHK-SCREEN-LOCK Configured screen lock to require password immediately
  ...

================================================================
  Results: 10 FIXED | 12 SKIPPED | 0 FAILED
================================================================

  Restore script: /opt/n8n/logs/audit/pre-fix-restore-20260316-123456.sh
```

**SKIPPED** items are either checks with no automatic fix (you would
handle them manually) or settings that require interactive
confirmation. **FAILED** items indicate a fix that could not be
applied.

> Every change the script makes is recorded in a restore script. If
> you need to undo a specific change later, see
> [Undo a Specific Change](#undo-a-specific-change) at the bottom of
> this guide.
>
> **Want interactive mode?** Run `make fix-interactive` instead of
> `make fix` to approve each change individually before it is applied.

---

## Step 8: Verify

Run the audit again to confirm the fixes took effect, then verify all
artifacts are in place:

```bash
make audit
make verify
```

Your PASS count should increase and your FAIL count should decrease
compared to Step 5. A typical result after applying fixes:

```text
================================================================
  Results: 26 PASS | 1 FAIL | 21 WARN | 19 SKIP
================================================================
```

The remaining FAIL is expected if n8n is not yet deployed
(`/opt/n8n/data` is owned by root until the n8n service account is
created). The WARN items are optional hardening steps you can address
over time.

`make verify` checks that all expected files, directories, and services
are in place:

```text
OpenClaw Verify
===============
  OK  Brew packages
  OK  /opt/n8n/scripts/hardening-audit.sh
  OK  /opt/n8n/scripts/hardening-fix.sh
  ...
  OK  /opt/n8n/ exists
  DOWN  Colima not running
  DOWN  n8n container not running
  MISSING  Shell aliases (run: make shellrc)
```

---

## What Was Changed

Here is what the `--auto` fix applies. All of these are standard macOS
security recommendations:

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

None of these changes affect your ability to use the Mac normally.
If you find you need a specific feature back (e.g., AirDrop for file
transfer), see [Undo a Specific Change](#undo-a-specific-change).

---

## Next Steps

After hardening, consider these optional improvements:

- **Set up shell aliases** for quick access to audit and fix commands:

  ```bash
  make shellrc
  ```

  This creates aliases (`openclaw-audit`, `openclaw-fix`, `n8n-token`)
  in `~/.openclaw/shellrc` and sources them from your shell profile.
  To remove them later: `make shellrc-remove`.

  > If you move the repo to a different directory, re-run `make shellrc`
  > to update the alias paths.

- **Set up the n8n gateway** (Fledge Milestone 1). One command
  handles everything: starts Colima, launches n8n in Docker, and
  imports the gateway workflows:

  ```bash
  make setup-gateway
  ```

  The script prints manual steps at the end for creating your n8n
  account and setting up Bearer auth. Open `http://localhost:5678`
  in Chrome (not Safari) to complete them. Do not use Safari (it
  forces HTTPS which n8n doesn't serve on localhost).

  After completing all manual steps (including Keychain storage and
  the `n8n-token` alias), verify the gateway works:

  ```bash
  curl -s -X POST http://localhost:5678/webhook/gateway \
    -H "Authorization: Bearer $(n8n-token)" \
    -H "Content-Type: application/json" \
    -d '{"intent": "hello"}'
  ```

  To stop the gateway: `make teardown-gateway`
  To restart everything: `make setup-gateway`

- **Install detection tools** like LuLu (outbound firewall) or
  BlockBlock (persistence monitor) to address WARN items
- **Set up scheduled audits** by loading the launchd job that was
  installed during bootstrap:

  ```bash
  sudo launchctl bootstrap system /Library/LaunchDaemons/com.openclaw.audit-cron.plist
  ```

- **Set up a browser** if you will use browser automation (e.g.,
  OpenClaw with Chrome DevTools Protocol). Chromium is recommended,
  but Google Chrome and Microsoft Edge are also fully supported —
  all browser security checks apply equally:

  ```bash
  brew install --cask chromium
  # Or: brew install --cask google-chrome
  # Or: brew install --cask microsoft-edge
  ```

  Then re-run the audit to verify browser security checks:

  ```bash
  make audit
  ```

  See [docs/HARDENING.md §2.11](docs/HARDENING.md#211-browser-security-chromium-auto-fix)
  for full browser hardening details including CDP port binding,
  managed security policies, and browser data cleanup.

- **Clean browser session data** after automation runs to remove
  cookies, cache, and history:

  ```bash
  bash scripts/browser-cleanup.sh
  ```

- **Set a firmware password** (Intel only) — requires booting into
  Recovery Mode (restart, hold Cmd + R). See
  [docs/HARDENING.md §2.9](docs/HARDENING.md) for instructions.
  This prevents unauthorized booting from external media.

- **Configure encrypted DNS** to address the DNS WARN
- **Set up Time Machine** or another backup solution

---

## Troubleshooting

### "command not found: brew"

**Apple Silicon:** Close Terminal and reopen it, or run:

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

**Intel:** Homebrew installs to `/usr/local/bin/`. Try:

```bash
eval "$(/usr/local/bin/brew shellenv)"
```

### Bootstrap shows errors for /opt/n8n directories

Make sure you are running from the repository root:

```bash
cd openclaw-mac
make install
```

If the problem persists, check that your user has admin privileges.

### "No audit JSON files found"

The fix script needs audit results in JSON format. Run the audit first:

```bash
make audit
```

This both displays results and saves the JSON. Then retry the fix
command.

### Audit shows FAIL but fix says SKIPPED

Some checks are classified as CONFIRMATION and require interactive
approval. Run the fix script in interactive mode:

```bash
make fix-interactive
```

### Audit results differ when run with and without sudo

Some checks read system-level settings that require elevated
privileges. `make audit` runs with sudo automatically.

### A fix did not take effect after reboot

A small number of macOS settings (such as FileVault) require a reboot
to activate. Re-run `make audit` after restarting.

---

## Undo a Specific Change

Every time the fix script runs, it creates a restore script that
records the previous state of each setting. You can undo individual
changes at any time.

First, find your restore file:

```bash
ls /opt/n8n/logs/audit/pre-fix-restore-*.sh
```

You will see one file per fix run, named with a timestamp (e.g.,
`pre-fix-restore-20260316-143022.sh`). Use the most recent one, or
the one matching the run you want to undo.

**List what can be undone:**

```bash
sudo bash /opt/n8n/logs/audit/pre-fix-restore-20260316-143022.sh --list
```

**Undo a single change** (example: re-enable AirDrop):

```bash
sudo bash /opt/n8n/logs/audit/pre-fix-restore-20260316-143022.sh CHK-AIRDROP
```

**Undo all changes from a run:**

```bash
sudo bash /opt/n8n/logs/audit/pre-fix-restore-20260316-143022.sh --all
```

Replace the filename with the one shown by the `ls` command above.

> **Quick undo:** Run `make fix-undo` to undo the most recent fix run
> interactively.
>
> **After uninstall:** If you ran `make uninstall`, restore scripts are
> preserved in `~/.openclaw/restore-scripts/`. Use those instead.

---

## Uninstall

To remove all OpenClaw artifacts (containers, Colima VM, scripts,
shell aliases):

```bash
make uninstall
```

This does **not** reverse hardening changes. To undo hardening first,
run `make fix-undo`. Restore scripts are automatically preserved in
`~/.openclaw/restore-scripts/` before deletion.

---

## Quick Reference

All available commands: `make help`

### Operations and their inverses

Every command that modifies your system has a corresponding undo:

| Do | Undo | What changes |
|----|------|-------------|
| `make install` | `make uninstall` | Creates `/opt/n8n/` tree, deploys scripts, installs Homebrew packages (bash, jq, shellcheck). Homebrew packages are left in place on uninstall — remove manually with `brew bundle cleanup --file=Brewfile --force` |
| `make setup-gateway` | `make teardown-gateway` | Starts Colima VM, creates Docker containers/volumes, stores bearer token in Keychain |
| `make fix` | `make fix-undo` | Modifies macOS security settings (firewall, Siri, AirDrop, etc.). Each run creates a restore script so changes can be undone individually or all at once |
| `make shellrc` | `make shellrc-remove` | Creates `~/.openclaw/shellrc` with aliases, adds source line to your shell profile |

### Other commands

| Command | What it does | Modifies system? |
|---------|-------------|-----------------|
| `make audit` | Run security audit, display results, and save JSON | Saves log files only |
| `make fix-interactive` | Apply fixes one at a time with approval prompts | Yes (same as `make fix`, but asks before each change) |
| `make fix-dry-run` | Preview fixes without applying them | No |
| `make verify` | Check that all expected artifacts are present | No |
| `make help` | Show all available targets | No |

---

## Reference

- Full hardening guide: [docs/HARDENING.md](docs/HARDENING.md)
- Audit script options: `bash scripts/hardening-audit.sh --help`
- Fix script options: `bash scripts/hardening-fix.sh --help`
- Bootstrap options: `bash scripts/bootstrap.sh --help`
