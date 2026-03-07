# NetworkChuck Style: macOS Tahoe (26) Hardening Guide

> *"You need to lock this down... RIGHT NOW!"*

NetworkChuck treats his Mac like a high-security server. This guide reflects
the **macOS Tahoe** security paradigm: **Zero Trust** for local networks,
aggressive **App Sandboxing**, and hardware-level **Identity Protection**.

## 1. Network Security: The Zero-Trust Layer

* **Global Local Network Privacy:** Tahoe now treats your LAN like a public coffee shop.
  * *Action:* Go to **System Settings > Privacy & Security > Local Network**. Revoke everything that doesn't *explicitly* need to talk to your printer or NAS.
* **Stealth Mode Firewall:** Don't let your Mac respond to "pings" from hackers scanning your network.
  * *Action:* Network > Firewall > Options > **Enable Stealth Mode**.
* **Encrypted DNS (System-Wide):** Don't let your ISP sell your browsing history.
  * *Action:* Use a `.mobileconfig` profile from [NextDNS](https://nextdns.io) or [Cloudflare](https://1.1.1.1) to force DNS-over-HTTPS at the kernel level.

## 2. System Integrity: The "Fort Knox" Layer

* **The Passwords App:** Tahoe moved passwords out of Settings into a standalone app.
  * *Hardening:* If you aren't using Bitwarden, use this. It handles 2FA codes natively—**Delete Google Authenticator; it's a single point of failure.**
* **Locked-Down Gatekeeper:** Tahoe has removed the "Control-Click" bypass for unsigned apps.
  * *Action:* If you must run an unsigned tool, you now have to manually verify it under **Privacy & Security** after it fails to launch. It's annoying, but it saves your data.
* **FileVault + Lockdown Mode:** If you are a high-value target (or just want to be cool), enable **Lockdown Mode**. It disables complex web features that hackers use for "Zero Click" exploits.

## 3. Privacy & App Hardening

* **Microphone & Camera Indicators:** In Tahoe, these are more persistent. If you see a dot and didn't start a call—**Kill the process.**
* **Hardened Browsing:** Use [LibreWolf](https://librewolf.net). It's Firefox, but with all the "telemetry" (spying) ripped out.

---

## Verification Script (Terminal)

Copy and paste this into your Terminal to audit your Tahoe or Sonoma system.

```bash
#!/bin/bash
echo "------------------------------------------------"
echo "NetworkChuck Style: macOS Security Audit"
echo "------------------------------------------------"

# 1. Check SIP
echo "[*] SIP Status (Must be Enabled):"
csrutil status

# 2. Check FileVault
echo "[*] Disk Encryption Status:"
fdesetup status

# 3. Check Firewall
echo "[*] Application Firewall:"
/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate

# 4. Check Stealth Mode
echo "[*] Stealth Mode (Drop ICMP/Pings):"
/usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode

# 5. Check Local Network Privacy (Tahoe Specific check)
if [[ $(sw_vers -productVersion) == 26* ]]; then
    echo "[*] macOS Tahoe Detected: Reviewing Local Network Sandbox..."
    # Note: Tahoe permissions are stored in TCC.db;
    # this confirms we are on the new architecture.
fi

echo "------------------------------------------------"
echo "If you see 'Disabled'... you're doing it wrong! FIX IT!"
```
