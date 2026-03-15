# NetworkChuck Style: macOS Sonoma (14) Hardening Addendum

> **DEPRECATED**: This document has been superseded by the comprehensive
> [macOS Hardening Guide](HARDENING.md). See §2 for OS foundation controls
> covering both Sonoma and Tahoe.

<!-- "You're on Sonoma? Fine. But don't let your guard down just because it's not Tahoe yet!" -->

This guide focuses on the specific security gaps in **macOS Sonoma** compared
to the newer Tahoe/Sequoia architectures. Use these steps to close the
"legacy" holes.

## 1. The Gatekeeper Habit

In Sonoma, you still have the "Easy Button" (Right-Click > Open) to bypass security for unsigned apps.

* **The Rule:** Stop using it.
* **The Secure Way:** If an app is blocked, go to **System Settings > Privacy & Security** and manually click "Open Anyway." This extra friction prevents "fat-fingering" a piece of malware.

## 2. Network Visibility (The Sonoma Gap)

Sonoma isn't as aggressive as Tahoe in sandboxing local network requests.

* **Action:** Manually audit **System Settings > Privacy & Security > Local Network**.
* **Pro Tip:** If an app doesn't *need* to find a printer or a smart bulb, turn it **OFF**. Most apps use this just for telemetry and tracking.

## 3. Password Management

You don't have the fancy standalone **Passwords App** yet.

* **Location:** Access your vault via **System Settings > Passwords**.
* **Hardening:** Ensure "AutoFill Passwords and Passkeys" is restricted ONLY to browsers you trust (e.g., Safari, Chromium with managed policies per §2.11 of the main hardening guide). If you use Bitwarden or 1Password, disable iCloud Keychain AutoFill to reduce your attack surface.

## 4. Firewall "Stealth Mode" (Crucial for Sonoma)

Because Sonoma is more permissive with network discovery, Stealth Mode is your best friend.

* **The Command:** Run this in Terminal to ensure your Mac doesn't talk back to strangers scanning your network:

    ```bash
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
    ```

## 5. Security Maintenance

* **Rapid Security Response (RSR):** Sonoma was the first to use "mini" security patches.
* **Action:** Ensure **System Settings > General > Software Update > (i)** has "Install Security Responses and system files" toggled **ON**.

---

## Sonoma-Specific Audit Commands

Paste these into Terminal to check Sonoma-specific settings:

```bash
#!/bin/bash
echo "--- Sonoma Security Check ---"

# Check for Rapid Security Response status
echo "[*] Checking for Security Responses..."
defaults read /Library/Preferences/com.apple.SoftwareUpdate.plist \
  | grep "CriticalUpdate"

# Check for Gatekeeper Policy
echo "[*] Checking Gatekeeper Level..."
spctl --status

# Check if Find My Mac is active (Physical Security)
echo "[*] Checking Find My Mac Status..."
nvram -p | grep fmm-mobileme-token-proxy > /dev/null \
  && echo "Find My Mac: ENABLED" \
  || echo "Find My Mac: DISABLED (Warning!)"

echo "--- Check Complete ---"
```
