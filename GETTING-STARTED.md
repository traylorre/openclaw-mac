# Hardening Your Mac Mini (Apple Silicon)

This guide walks you through securing a Mac Mini with Apple Silicon
(M1, M2, M3, M4) using the OpenClaw hardening toolkit. Every command
is copy-pasteable. The process takes about 15 minutes.

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

- A Mac Mini with Apple Silicon (M1 or later)
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

When it finishes, it will print **"Next steps"** with commands to add
Homebrew to your PATH. Copy and paste those commands exactly as shown.
They will look similar to this:

```bash
echo >> ~/.zprofile
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Verify it worked:

```bash
brew --version
```

You should see output like:

```
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
sudo bash scripts/bootstrap.sh
```

Your Mac will ask for your password. This is your Mac login password,
not an Apple ID password. You will not see the characters as you type.

You should see output similar to this:

```
OpenClaw Bootstrap v0.1.0
Mode: install (will install dependencies and create directories)

[1/8] Platform Check
  ✓  macOS 15.2 detected
  ℹ  Architecture: arm64

[2/8] Homebrew
  ✓  Homebrew installed: Homebrew 4.x.x

[3/8] Required Tools
  ✓  bash 5.x: ...
  ✓  jq: jq-1.x
  —  shellcheck not installed (optional)
  —  msmtp not installed (optional)
  ✓  sqlite3: available

[4/8] Directory Structure
  +  Created /opt/n8n/
  +  Created /opt/n8n/scripts/
  ...

[5/8] Deploy Scripts
  +  Deployed hardening-audit.sh → /opt/n8n/scripts/hardening-audit.sh
  ...

[6/8] Configuration
  +  Created default notify.conf

[7/8] Sample Audit JSON
  +  Generated sample audit JSON

[8/8] Command Validation
  ✓  csrutil available
  ✓  fdesetup available
  ...
  —  docker not installed (container checks will SKIP)

════════════════════════════════════════
  16 OK  |  11 FIXED  |  0 ERRORS
════════════════════════════════════════
```

Your output will have more lines than shown above (the `...` lines
are abbreviated). Here is what the symbols mean:

- `✓` or **OK** — already in place, no action taken
- `+` or **FIXED** — the bootstrap installed or created this for you
- `—` — optional, can be ignored
- `✗` or **ERRORS** — something needs attention before continuing

---

## Step 5: Run the Security Audit

The audit reads your Mac's current security settings and reports what
is configured correctly and what is not. It does not change anything.

```bash
sudo bash scripts/hardening-audit.sh
```

You should see output similar to this (your results will vary based
on your Mac's current configuration):

```
================================================================
  OpenClaw Mac Hardening Audit
  Version: 0.1.0 | Date: 2026-03-16
  Deployment: unknown | macOS: 15.2
================================================================

[Section: System Integrity Protection]
  PASS  SIP is enabled                               → §2.3

[Section: Disk Encryption]
  PASS  FileVault is enabled                         → §2.1

[Section: Firewall]
  FAIL  Application firewall is disabled             → §2.2
  WARN  Stealth mode is not enabled                  → §2.2

[Section: Gatekeeper]
  PASS  Gatekeeper is enabled                        → §2.4
  ...

[Section: Guest Account]
  FAIL  Guest account is enabled                     → §2.7
  ...

[Section: n8n Platform]
  SKIP  n8n not detected                             → §5.1
  ...

================================================================
  Results: 17 PASS | 5 FAIL | 22 WARN | 19 SKIP
================================================================
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

---

## Step 6: Apply Fixes (Dry Run)

Before making any changes, preview what the fix script would do.
First, save the audit results to a file:

```bash
sudo bash scripts/hardening-audit.sh --json | tee openclaw-audit.json > /dev/null
```

Then run the fix script in dry-run mode:

```bash
sudo bash scripts/hardening-fix.sh --dry-run --auto --audit-file openclaw-audit.json
```

This shows every command that would run without actually executing it.
Review the output. Each line marked `[DRY-RUN]` shows the exact
command. Nothing is changed on your Mac during this step.

---

## Step 7: Apply Fixes

When you are ready, apply the fixes. This uses the same audit file
you generated in Step 6:

```bash
sudo bash scripts/hardening-fix.sh --auto --audit-file openclaw-audit.json
```

Your Mac may ask for your password again if more than a few minutes
have passed since Step 6. You should see output similar to this:

```
================================================================
  OpenClaw Mac Hardening Fix
  Version: 0.1.0 | Date: 2026-03-16
  Mode: auto | Dry-run: false
  Audit file: /tmp/openclaw-audit.json
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
  Usage: bash /opt/n8n/logs/audit/pre-fix-restore-20260316-123456.sh --list | --all | CHK-ID
```

**SKIPPED** items are either checks with no automatic fix (you would
handle them manually) or settings that require interactive
confirmation. **FAILED** items indicate a fix that could not be
applied.

> Every change the script makes is recorded in a restore script. If
> you need to undo a specific change later, see
> [Undo a Specific Change](#undo-a-specific-change) at the bottom of
> this guide.

---

## Step 8: Verify

Run the audit again to confirm the fixes took effect:

```bash
sudo bash scripts/hardening-audit.sh
```

You should see your PASS count increase and your FAIL count decrease
compared to Step 5. A typical result after applying fixes:

```
================================================================
  Results: 26 PASS | 1 FAIL | 21 WARN | 19 SKIP
================================================================
```

The remaining FAIL is expected if n8n is not yet deployed
(`/opt/n8n/data` is owned by root until the n8n service account is
created). The WARN items are optional hardening steps you can address
over time.

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

- **Install n8n** and re-run the audit to validate its security
  configuration
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

  Then verify the browser security checks pass:

  ```bash
  sudo bash scripts/hardening-audit.sh --section "Browser Security"
  ```

  See [docs/HARDENING.md §2.11](docs/HARDENING.md#211-browser-security-chromium-auto-fix)
  for full browser hardening details including CDP port binding,
  managed security policies, and browser data cleanup.

- **Clean browser session data** after automation runs to remove
  cookies, cache, and history:

  ```bash
  bash scripts/browser-cleanup.sh
  ```

- **Configure encrypted DNS** to address the DNS WARN
- **Set up Time Machine** or another backup solution

---

## Troubleshooting

### "command not found: brew"

Close Terminal and reopen it. If that does not work, run:

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

### Bootstrap shows errors for /opt/n8n directories

Run bootstrap with sudo:

```bash
sudo bash scripts/bootstrap.sh
```

### Audit shows FAIL but fix says SKIPPED

Some checks are classified as CONFIRMATION and require interactive
approval. Run the fix script in interactive mode:

```bash
sudo bash scripts/hardening-fix.sh --interactive --audit-file openclaw-audit.json
```

### Audit results differ when run with and without sudo

Some checks read system-level settings that require elevated
privileges. Always run the audit with `sudo` to get complete results.

### A fix did not take effect after reboot

A small number of macOS settings (such as FileVault) require a reboot
to activate. Re-run the audit after restarting.

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

---

## Reference

- Full hardening guide: [docs/HARDENING.md](docs/HARDENING.md)
- Audit script options: `bash scripts/hardening-audit.sh --help`
- Fix script options: `bash scripts/hardening-fix.sh --help`
- Bootstrap options: `bash scripts/bootstrap.sh --help`
