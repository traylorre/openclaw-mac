#!/usr/bin/env bash
# OpenClaw Bootstrap — Prepare a fresh macOS for hardening
# Run this FIRST on the target Mac before any other scripts.
# Idempotent — safe to run multiple times.
set -euo pipefail

readonly VERSION="0.1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Color Setup ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

if [[ ! -t 1 ]]; then
    RED='' GREEN='' YELLOW='' CYAN='' BOLD='' NC=''
fi

# --- Counters ---
OK=0
FIXED=0
ERRORS=0

report() {
    local status="$1" msg="$2"
    case "$status" in
        OK)    printf "  ${GREEN}✓${NC}  %s\n" "$msg"; OK=$((OK + 1)) ;;
        FIXED) printf "  ${CYAN}+${NC}  %s\n" "$msg"; FIXED=$((FIXED + 1)) ;;
        FAIL)  printf "  ${RED}✗${NC}  %s\n" "$msg"; ERRORS=$((ERRORS + 1)) ;;
        SKIP)  printf "  ${YELLOW}—${NC}  %s\n" "$msg" ;;
        INFO)  printf "  ${BOLD}ℹ${NC}  %s\n" "$msg" ;;
    esac
}

# --- Usage ---
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Prepare a fresh macOS for OpenClaw hardening.

What it does:
  1. Validates macOS platform
  2. Installs/verifies Homebrew
  3. Installs/verifies bash 5.x, jq, shellcheck
  4. Creates /opt/n8n directory structure
  5. Deploys scripts to /opt/n8n/scripts/
  6. Creates default notify.conf
  7. Generates sample audit JSON for testing
  8. Validates all script dependencies

Options:
  --check     Validate only, do not install or create anything
  --help      Show this help message
  --version   Show version

Run as your normal admin user (not root). Sudo is used where needed.
EOF
}

# --- Platform ---
check_macos() {
    printf "\n${BOLD}[1/8] Platform Check${NC}\n"
    if [[ "$(uname -s)" != "Darwin" ]]; then
        report FAIL "Not macOS — this script requires macOS"
        exit 2
    fi
    local ver
    ver=$(sw_vers -productVersion 2>/dev/null) || ver="unknown"
    report OK "macOS ${ver} detected"

    local arch
    arch=$(uname -m)
    report INFO "Architecture: ${arch}"

    if [[ "$arch" == "arm64" ]]; then
        HOMEBREW_PREFIX="/opt/homebrew"
    else
        HOMEBREW_PREFIX="/usr/local"
    fi
}

# --- Homebrew ---
check_homebrew() {
    printf "\n${BOLD}[2/8] Homebrew${NC}\n"
    if command -v brew &>/dev/null; then
        local brew_ver
        brew_ver=$(brew --version 2>/dev/null) || true
        brew_ver="${brew_ver%%$'\n'*}"
        report OK "Homebrew installed: ${brew_ver}"
    elif [[ "$CHECK_ONLY" == true ]]; then
        report FAIL "Homebrew not installed"
    else
        report INFO "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        # Add to PATH for this session
        if [[ -f "${HOMEBREW_PREFIX}/bin/brew" ]]; then
            eval "$("${HOMEBREW_PREFIX}/bin/brew" shellenv)"
            report FIXED "Homebrew installed"
        else
            report FAIL "Homebrew installation failed"
        fi
    fi
}

# --- Shell & Tools ---
check_tools() {
    printf "\n${BOLD}[3/8] Required Tools${NC}\n"

    # jq FIRST — required for manifest operations (FR-023, C2 fix)
    local jq_was_preexisting=false
    if command -v jq &>/dev/null; then
        jq_was_preexisting=true
        report OK "jq: $(jq --version 2>/dev/null)"
    elif [[ "$CHECK_ONLY" == true ]]; then
        report FAIL "jq not installed"
    else
        local brew_err
        if brew_err=$(brew install jq 2>&1); then
            report FIXED "jq installed"
        else
            report FAIL "jq install failed: ${brew_err##*$'\n'}"
        fi
    fi

    # Bash 5.x
    local bash_ver
    bash_ver=$(bash --version 2>/dev/null | head -1) || true
    if echo "$bash_ver" | grep -q 'version [5-9]'; then
        report OK "bash 5.x: ${bash_ver##*version }"
    elif [[ "$CHECK_ONLY" == true ]]; then
        report FAIL "bash 5.x not found (macOS ships with bash 3.x)"
    else
        report INFO "Installing bash via Homebrew..."
        local brew_err
        if brew_err=$(brew install bash 2>&1); then
            report FIXED "bash 5.x installed"
        else
            report FAIL "bash install failed: ${brew_err##*$'\n'}"
        fi
        # Add to /etc/shells if not present
        if ! grep -q "${HOMEBREW_PREFIX}/bin/bash" /etc/shells 2>/dev/null; then
            echo "${HOMEBREW_PREFIX}/bin/bash" | sudo tee -a /etc/shells >/dev/null
            report FIXED "Added ${HOMEBREW_PREFIX}/bin/bash to /etc/shells"
        fi
    fi

    # SC linter (optional, for development)
    if command -v shellcheck &>/dev/null; then
        local sc_ver
        sc_ver=$(shellcheck --version 2>/dev/null | grep version) || true
        report OK "shellcheck: ${sc_ver:-unknown}"
    else
        report SKIP "shellcheck not installed (optional — brew install shellcheck)"
    fi

    # msmtp (optional, for email notifications)
    if command -v msmtp &>/dev/null; then
        report OK "msmtp: installed (email notifications available)"
    else
        report SKIP "msmtp not installed (optional — brew install msmtp for email alerts)"
    fi

    # sqlite3 (for TCC checks)
    if command -v sqlite3 &>/dev/null; then
        report OK "sqlite3: available"
    else
        report FAIL "sqlite3 not found (needed for TCC checks)"
    fi
}

# --- Directory Structure ---
check_directories() {
    printf "\n${BOLD}[4/8] Directory Structure${NC}\n"

    local dirs=(
        "/opt/n8n"
        "/opt/n8n/scripts"
        "/opt/n8n/etc"
        "/opt/n8n/logs"
        "/opt/n8n/logs/audit"
        "/opt/n8n/data"
    )

    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            report OK "${dir}/ exists"
        elif [[ "$CHECK_ONLY" == true ]]; then
            report FAIL "${dir}/ missing"
        else
            sudo mkdir -p "$dir"
            report FIXED "Created ${dir}/"
        fi
    done

    # Set permissions
    if [[ "$CHECK_ONLY" != true ]]; then
        sudo chmod 755 /opt/n8n /opt/n8n/scripts /opt/n8n/logs /opt/n8n/logs/audit
        sudo chmod 700 /opt/n8n/etc /opt/n8n/data
    fi

}

# --- Deploy Scripts ---
deploy_scripts() {
    printf "\n${BOLD}[5/8] Deploy Scripts${NC}\n"

    # Determine source directory (where this script lives)
    local src_dir
    src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    local scripts=(
        "hardening-audit.sh"
        "audit-notify.sh"
        "hardening-fix.sh"
        "audit-cron.sh"
    )

    for script in "${scripts[@]}"; do
        local src="${src_dir}/${script}"
        local dst="/opt/n8n/scripts/${script}"
        if [[ ! -f "$src" ]]; then
            report FAIL "Source not found: ${src}"
            continue
        fi
        if [[ "$CHECK_ONLY" == true ]]; then
            if [[ -f "$dst" ]]; then
                report OK "${script} deployed"
            else
                report FAIL "${script} not deployed to ${dst}"
            fi
        else
            sudo cp "$src" "$dst"
            sudo chmod 755 "$dst"
            report FIXED "Deployed ${script} → ${dst}"
        fi
    done

    # Deploy launchd plists
    local plists=(
        "launchd/com.openclaw.audit-cron.plist"
    )
    for plist in "${plists[@]}"; do
        local src="${src_dir}/${plist}"
        local dst
        dst="/Library/LaunchDaemons/$(basename "$plist")"
        if [[ ! -f "$src" ]]; then
            report FAIL "Source not found: ${src}"
            continue
        fi
        if [[ "$CHECK_ONLY" == true ]]; then
            if [[ -f "$dst" ]]; then
                report OK "$(basename "$plist") installed"
            else
                report FAIL "$(basename "$plist") not installed at ${dst}"
            fi
        else
            sudo cp "$src" "$dst"
            sudo chown root:wheel "$dst"
            sudo chmod 644 "$dst"
            report FIXED "Installed $(basename "$plist") → ${dst}"
        fi
    done
}

# --- Configuration ---
create_config() {
    printf "\n${BOLD}[6/8] Configuration${NC}\n"

    local conf="/opt/n8n/etc/notify.conf"
    if [[ -f "$conf" ]]; then
        report OK "notify.conf exists"
    elif [[ "$CHECK_ONLY" == true ]]; then
        report FAIL "notify.conf missing"
    else
        sudo tee "$conf" > /dev/null <<'CONF'
# OpenClaw Audit Notification Configuration
# See docs/HARDENING.md §10.2 for setup guide

# --- Email (requires msmtp: brew install msmtp) ---
NOTIFY_EMAIL_ENABLED=false
NOTIFY_EMAIL_TO="operator@example.com"
NOTIFY_EMAIL_FROM="openclaw-audit@localhost"

# --- macOS Notification Center (local, enabled by default) ---
NOTIFY_OSASCRIPT_ENABLED=true

# --- Webhook (Slack, Discord, n8n, etc.) ---
NOTIFY_WEBHOOK_ENABLED=false
NOTIFY_WEBHOOK_URL=""

# --- Log directory ---
LOG_DIR="/opt/n8n/logs/audit"
CONF
        sudo chmod 600 "$conf"
        report FIXED "Created default notify.conf"
    fi
}

# --- Generate Sample Audit JSON ---
generate_sample_json() {
    printf "\n${BOLD}[7/8] Sample Audit JSON${NC}\n"

    local sample="/opt/n8n/logs/audit/audit-sample.json"
    if [[ -f "$sample" ]]; then
        report OK "Sample audit JSON exists"
    elif [[ "$CHECK_ONLY" == true ]]; then
        report SKIP "Sample audit JSON not generated (use without --check)"
    else
        local ts
        ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        cat > /tmp/openclaw-sample-audit.json <<SAMPLE
{
  "version": "0.1.0",
  "timestamp": "${ts}",
  "system": {
    "macos_version": "14.6.1",
    "hardware": "arm64",
    "deployment": "unknown"
  },
  "results": [
    {"id":"CHK-SIP","section":"System Integrity Protection","description":"SIP is enabled","status":"PASS","guide_ref":"§2.3"},
    {"id":"CHK-FILEVAULT","section":"Disk Encryption","description":"FileVault is disabled","status":"FAIL","guide_ref":"§2.1","remediation":"Enable FileVault: sudo fdesetup enable"},
    {"id":"CHK-FIREWALL","section":"Firewall","description":"Application firewall is disabled","status":"FAIL","guide_ref":"§2.2","remediation":"Enable firewall: sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on"},
    {"id":"CHK-STEALTH","section":"Firewall","description":"Stealth mode is not enabled","status":"WARN","guide_ref":"§2.2","remediation":"Enable stealth mode: sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on"},
    {"id":"CHK-GATEKEEPER","section":"Gatekeeper","description":"Gatekeeper is enabled","status":"PASS","guide_ref":"§2.4"},
    {"id":"CHK-GUEST","section":"Guest Account","description":"Guest account is enabled","status":"FAIL","guide_ref":"§2.7","remediation":"Disable: sudo defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false"},
    {"id":"CHK-AUTO-LOGIN","section":"Login Security","description":"Auto-login is disabled","status":"PASS","guide_ref":"§2.6"},
    {"id":"CHK-SHARING-FILE","section":"Sharing Services","description":"File Sharing (SMB) is disabled","status":"PASS","guide_ref":"§2.7"},
    {"id":"CHK-SSH-KEY-ONLY","section":"SSH Security","description":"SSH password auth enabled","status":"FAIL","guide_ref":"§3.1","remediation":"Add PasswordAuthentication no to /etc/ssh/sshd_config.d/hardening.conf"},
    {"id":"CHK-SANTA","section":"Detection Tools","description":"Santa not installed","status":"WARN","guide_ref":"§8.1","remediation":"Install: brew install santa"},
    {"id":"CHK-BACKUP-CONFIGURED","section":"Recovery","description":"No backup configured","status":"WARN","guide_ref":"§9.3","remediation":"Configure Time Machine backup"},
    {"id":"CHK-LOG-DIR","section":"Operational","description":"Audit log directory exists","status":"PASS","guide_ref":"§10.1"}
  ],
  "summary": {
    "total": 12,
    "pass": 5,
    "fail": 4,
    "warn": 3,
    "skip": 0
  }
}
SAMPLE
        sudo cp /tmp/openclaw-sample-audit.json "$sample"
        rm -f /tmp/openclaw-sample-audit.json
        report FIXED "Generated sample audit JSON (4 FAILs, 3 WARNs)"
        report INFO "Test with: audit-notify.sh --log-dir /opt/n8n/logs/audit"
        report INFO "Test with: hardening-fix.sh --dry-run --auto --audit-file ${sample}"
    fi
}

# --- Dependency Validation ---
validate_commands() {
    printf "\n${BOLD}[8/8] Command Validation${NC}\n"

    # Test each macOS command the audit script depends on
    local cmds=(
        "csrutil:csrutil status"
        "fdesetup:fdesetup status"
        "socketfilterfw:/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate"
        "spctl:spctl --status"
        "systemsetup:sudo systemsetup -getusingnetworktime"
        "defaults:defaults domains"
        "mdutil:mdutil -s /"
        "launchctl:launchctl print system"
        "profiles:profiles list"
        "sw_vers:sw_vers -productVersion"
        "system_profiler:system_profiler SPSoftwareDataType"
    )

    for entry in "${cmds[@]}"; do
        local name="${entry%%:*}"
        # cmd portion reserved for future --test-commands mode
        if command -v "$name" &>/dev/null || [[ "$name" == "socketfilterfw" && -x "/usr/libexec/ApplicationFirewall/socketfilterfw" ]]; then
            report OK "${name} available"
        else
            report FAIL "${name} not found"
        fi
    done

    # Docker/Colima (required for container workloads)
    local hw_arch
    hw_arch=$(uname -m)
    if [[ "$hw_arch" == "arm64" ]]; then
        report INFO "Hardware: Apple Silicon (${hw_arch})"
    else
        report INFO "Hardware: Intel (${hw_arch})"
    fi

    if command -v colima &>/dev/null; then
        local colima_ver
        colima_ver=$(colima version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || colima_ver="unknown"
        report OK "colima: ${colima_ver}"
    elif [[ "$CHECK_ONLY" == true ]]; then
        report FAIL "colima not installed"
    else
        report INFO "Installing colima via Homebrew..."
        local brew_err
        if brew_err=$(brew install colima 2>&1); then
            report FIXED "colima installed"
        else
            report FAIL "colima install failed: ${brew_err##*$'\n'}"
        fi
    fi
    if command -v docker &>/dev/null; then
        report OK "docker: $(docker --version 2>/dev/null)"
    elif [[ "$CHECK_ONLY" == true ]]; then
        report FAIL "docker not installed"
    else
        report INFO "Installing docker via Homebrew..."
        local brew_err
        if brew_err=$(brew install docker 2>&1); then
            report FIXED "docker installed"
        else
            report FAIL "docker install failed: ${brew_err##*$'\n'}"
        fi
    fi
    if docker compose version &>/dev/null; then
        report OK "docker-compose: $(docker compose version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    elif [[ "$CHECK_ONLY" == true ]]; then
        report FAIL "docker-compose not installed"
    else
        report INFO "Installing docker-compose via Homebrew..."
        local brew_err
        if brew_err=$(brew install docker-compose 2>&1); then
            report FIXED "docker-compose installed"
        else
            report FAIL "docker-compose install failed: ${brew_err##*$'\n'}"
        fi
    fi
    # Chromium (optional, for OpenClaw browser control)
    if [[ -d "/Applications/Chromium.app" ]] || command -v chromium &>/dev/null; then
        report OK "Chromium available (browser control enabled)"
    elif [[ -d "/Applications/Google Chrome.app" ]] || command -v google-chrome &>/dev/null; then
        report OK "Google Chrome available (browser control enabled)"
    else
        report SKIP "Chromium not installed (optional — brew install --cask chromium for OpenClaw §2.11)"
    fi
}

# --- Main ---
main() {
    CHECK_ONLY=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check)   CHECK_ONLY=true; shift ;;
            --version) echo "bootstrap.sh v${VERSION}"; exit 0 ;;
            --help)    usage; exit 0 ;;
            *)         echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
        esac
    done

    printf "${BOLD}OpenClaw Bootstrap v${VERSION}${NC}\n"
    if [[ "$CHECK_ONLY" == true ]]; then
        printf "Mode: ${YELLOW}check only${NC} (no changes will be made)\n"
    else
        printf "Mode: ${GREEN}install${NC} (will install dependencies and create directories)\n"
    fi

    # Pre-flight: disk space check
    if [[ "$CHECK_ONLY" != true ]]; then
        local avail_gb
        avail_gb=$(df -g / | awk 'NR==2 {print $4}') || avail_gb=999
        if [[ "$avail_gb" -lt 8 ]]; then
            printf "  ${YELLOW}!${NC}  Low disk space: %dGB available (8GB recommended)\n" "$avail_gb"
        fi
    fi

    check_macos
    check_homebrew
    check_tools
    check_directories
    deploy_scripts
    create_config
    generate_sample_json
    validate_commands

    # Summary
    printf "\n${BOLD}════════════════════════════════════════${NC}\n"
    printf "  ${GREEN}%d OK${NC}  |  ${CYAN}%d FIXED${NC}  |  ${RED}%d ERRORS${NC}\n" "$OK" "$FIXED" "$ERRORS"
    printf "${BOLD}════════════════════════════════════════${NC}\n"

    if [[ $ERRORS -gt 0 ]]; then
        printf "\n${YELLOW}Next: Fix the errors above, then re-run bootstrap.sh${NC}\n"
        exit 1
    fi

    if [[ "$CHECK_ONLY" != true ]]; then
        printf "\n${GREEN}Bootstrap complete. Next steps:${NC}\n"
        echo "  1. Test notify:  /opt/n8n/scripts/audit-notify.sh --log-dir /opt/n8n/logs/audit"
        echo "  2. Test fix:     /opt/n8n/scripts/hardening-fix.sh --dry-run --auto --audit-file /opt/n8n/logs/audit/audit-sample.json"
        echo "  3. Run audit:    sudo /opt/n8n/scripts/hardening-audit.sh"
        echo "  4. Run fix:      sudo /opt/n8n/scripts/hardening-fix.sh --auto"
        echo "  5. Enable cron:  sudo launchctl bootstrap system /Library/LaunchDaemons/com.openclaw.audit-cron.plist"
        echo ""
        echo "  Note: sudo auto-detects Homebrew bash 5.x — no manual PATH needed."
        echo "  Add --debug to any script for bash trace output."
    fi
}

main "$@"
