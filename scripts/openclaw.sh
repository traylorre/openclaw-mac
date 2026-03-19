#!/usr/bin/env bash
# OpenClaw CLI — Dispatcher for manifest, uninstall, and install commands
# Usage: openclaw <command> [options]
#
# Commands:
#   manifest              Show installed artifacts
#   manifest --verify     Check artifacts against disk
#   manifest --rebuild    Reconstruct manifest from disk
#   manifest --json       Output raw JSON
#   uninstall             Remove all openclaw artifacts
#   install               Run install with manifest tracking

# shellcheck disable=SC2059  # Color variables in printf format strings are intentional
set -euo pipefail

readonly VERSION="0.1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

if [[ ! -t 1 ]]; then
    RED='' GREEN='' YELLOW='' CYAN='' BOLD='' NC=''
fi

# --- Source manifest library ---
# shellcheck source=lib/manifest.sh disable=SC1091
source "${SCRIPT_DIR}/lib/manifest.sh"

# --- Usage ---
usage() {
    cat <<EOF
Usage: openclaw <command> [options]

Commands:
  manifest [--verify] [--rebuild] [--json]   Inspect installation manifest
  uninstall [--dry-run] [--force] [--keep-data] [--keep-hardening] [--confirm]
                                              Remove openclaw artifacts
  install [--hardening-only]                  Install with manifest tracking

Options:
  --help      Show this help
  --version   Show version

EOF
}

# ============================================================
# Command: manifest
# ============================================================

cmd_manifest() {
    local verify=false rebuild=false json_output=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verify)  verify=true; shift ;;
            --rebuild) rebuild=true; shift ;;
            --json)    json_output=true; shift ;;
            *)         echo "Unknown manifest option: $1" >&2; exit 2 ;;
        esac
    done

    if [[ "${rebuild}" == true ]]; then
        cmd_manifest_rebuild
        return
    fi

    if [[ ! -f "${MANIFEST_FILE}" ]]; then
        printf "${YELLOW}No manifest found.${NC} Run bootstrap.sh first, or: openclaw manifest --rebuild\n"
        exit 2
    fi

    if [[ "${verify}" == true ]]; then
        cmd_manifest_verify "${json_output}"
        return
    fi

    if [[ "${json_output}" == true ]]; then
        cat "${MANIFEST_FILE}"
        return
    fi

    # Default: human-readable table
    cmd_manifest_table
}

cmd_manifest_table() {
    local count
    count="$(jq '.artifacts | length' "${MANIFEST_FILE}")"
    local repo_root
    repo_root="$(jq -r '.repo_root' "${MANIFEST_FILE}")"

    printf "${BOLD}OpenClaw Manifest${NC} — %d artifacts tracked\n" "${count}"
    printf "Repo: %s\n\n" "${repo_root}"

    if [[ "${count}" -eq 0 ]]; then
        printf "  (no artifacts tracked)\n"
        return
    fi

    printf "  %-20s %-48s %-12s %s\n" "TYPE" "PATH" "CATEGORY" "STATUS"
    printf "  %-20s %-48s %-12s %s\n" "────────────────────" "────────────────────────────────────────────────" "────────────" "──────────"

    jq -r '.artifacts[] | "\(.type)\t\(.path)\t\(.category)\t\(.status)"' "${MANIFEST_FILE}" | \
    while IFS=$'\t' read -r type path category status; do
        printf "  %-20s %-48s %-12s %s\n" "${type}" "${path}" "${category}" "${status}"
    done
}

cmd_manifest_verify() {
    local json_output="${1:-false}"

    local present=0 missing=0 drifted=0 version_drift=0
    local total
    total="$(jq '.artifacts | length' "${MANIFEST_FILE}")"

    if [[ "$json_output" != true ]]; then
        printf "${BOLD}OpenClaw Manifest Verify${NC} — %d artifacts\n\n" "$total"
        printf "  %-20s %-48s %s\n" "TYPE" "PATH" "STATUS"
        printf "  %-20s %-48s %s\n" "────────────────────" "────────────────────────────────────────────────" "──────────────"
    fi

    local json_results="[]"

    while IFS= read -r entry; do
        local id type path checksum version
        id="$(echo "$entry" | jq -r '.id')"
        type="$(echo "$entry" | jq -r '.type')"
        path="$(echo "$entry" | jq -r '.path')"
        checksum="$(echo "$entry" | jq -r '.checksum // ""')"
        version="$(echo "$entry" | jq -r '.version // ""')"
        local status
        status="$(echo "$entry" | jq -r '.status')"

        # Skip already-removed entries
        if [[ "$status" == "removed" ]]; then
            continue
        fi

        local verify_status="PRESENT"
        local current_cksum="" current_ver=""

        case "$type" in
            brew-package)
                if ! brew list "$path" &>/dev/null; then
                    verify_status="MISSING"
                elif [[ -n "$version" && "$version" != "N/A" && "$version" != "unknown" ]]; then
                    current_ver="$(manifest_brew_version "$path")"
                    if [[ "$current_ver" != "$version" ]]; then
                        verify_status="VERSION_DRIFT"
                    fi
                fi
                ;;
            file|system-config-file|managed-preference|launchd-plist|shell-rc-file)
                if [[ ! -f "$path" ]]; then
                    verify_status="MISSING"
                elif [[ -n "$checksum" && "$checksum" != "null" ]]; then
                    current_cksum="$(manifest_checksum "$path")"
                    if [[ "$current_cksum" != "$checksum" ]]; then
                        verify_status="DRIFTED"
                    fi
                fi
                ;;
            directory)
                [[ ! -d "$path" ]] && verify_status="MISSING"
                ;;
            docker-container)
                if ! docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${path}$"; then
                    verify_status="MISSING"
                fi
                ;;
            docker-volume)
                if ! docker volume ls --format '{{.Name}}' 2>/dev/null | grep -q "^${path}$"; then
                    verify_status="MISSING"
                fi
                ;;
            docker-image)
                if ! docker image inspect "$path" &>/dev/null; then
                    verify_status="MISSING"
                fi
                ;;
            colima-vm)
                if ! colima list 2>/dev/null | grep -q "$path"; then
                    verify_status="MISSING"
                fi
                ;;
            keychain-entry)
                if ! security find-generic-password -s "$path" &>/dev/null; then
                    verify_status="MISSING"
                fi
                ;;
            shell-config-line|system-config-line)
                if [[ ! -f "$path" ]]; then
                    verify_status="MISSING"
                else
                    # Check that the actual line is present in the file, not just the file
                    local expected_line
                    expected_line="$(_get_removal_pattern "$id" "$type")"
                    if [[ -n "$expected_line" ]]; then
                        if ! grep -qF "$expected_line" "$path" 2>/dev/null; then
                            verify_status="MISSING"
                        fi
                    fi
                fi
                ;;
            system-account)
                if ! id "$path" &>/dev/null; then
                    verify_status="MISSING"
                fi
                ;;
            spotlight-exclusion)
                [[ ! -d "$path" ]] && verify_status="MISSING"
                ;;
        esac

        # Count
        case "$verify_status" in
            PRESENT)       present=$((present + 1)) ;;
            MISSING)       missing=$((missing + 1)) ;;
            DRIFTED)       drifted=$((drifted + 1)) ;;
            VERSION_DRIFT) version_drift=$((version_drift + 1)) ;;
        esac

        # T026: JSON output
        if [[ "$json_output" == true ]]; then
            local json_entry
            json_entry="$(jq -n \
                --arg id "$id" --arg path "$path" --arg type "$type" \
                --arg vs "$verify_status" \
                --arg ec "${checksum:-}" --arg cc "${current_cksum:-}" \
                --arg ev "${version:-}" --arg cv "${current_ver:-}" \
                '{id:$id, path:$path, type:$type, verify_status:$vs,
                  expected_checksum:$ec, current_checksum:$cc,
                  expected_version:$ev, current_version:$cv}')"
            if [[ "$json_results" == "[]" ]]; then
                json_results="[${json_entry}]"
            else
                json_results="${json_results%]},$json_entry]"
            fi
        else
            # Terminal output
            local color=""
            case "$verify_status" in
                PRESENT)       color="$GREEN" ;;
                MISSING)       color="$RED" ;;
                DRIFTED)       color="$YELLOW" ;;
                VERSION_DRIFT) color="$YELLOW" ;;
            esac
            printf "  %-20s %-48s ${color}%s${NC}\n" "$type" "$path" "$verify_status"
            if [[ "$verify_status" == "DRIFTED" ]]; then
                printf "  %20s   Expected: %s  Current: %s\n" "" "${checksum:0:12}..." "${current_cksum:0:12}..."
            elif [[ "$verify_status" == "VERSION_DRIFT" ]]; then
                printf "  %20s   Expected: %s  Current: %s\n" "" "$version" "$current_ver"
            fi
        fi
    done < <(jq -c '.artifacts[]' "${MANIFEST_FILE}")

    if [[ "$json_output" == true ]]; then
        echo "$json_results" | jq .
    else
        printf "\n${BOLD}Summary${NC}: ${GREEN}%d PRESENT${NC}, ${YELLOW}%d DRIFTED${NC}, ${YELLOW}%d VERSION_DRIFT${NC}, ${RED}%d MISSING${NC}\n" \
            "$present" "$drifted" "$version_drift" "$missing"
    fi

    if [[ $missing -gt 0 || $drifted -gt 0 || $version_drift -gt 0 ]]; then
        return 1
    fi
    return 0
}

cmd_manifest_rebuild() {
    printf "${BOLD}OpenClaw Manifest Rebuild${NC}\n"
    printf "Scanning known artifact locations...\n\n"

    manifest_setup_traps
    manifest_lock
    manifest_init

    local found=0 not_found=0

    # Helper: try to add an artifact if found on disk
    _rebuild_check() {
        local id="$1" type="$2" category="$3" path="$4" check_type="$5"
        local exists=false

        case "$check_type" in
            file)      [[ -f "$path" ]] && exists=true ;;
            dir)       [[ -d "$path" ]] && exists=true ;;
            brew)      brew list "$path" &>/dev/null && exists=true ;;
            command)   command -v "$path" &>/dev/null && exists=true ;;
            colima)    colima list 2>/dev/null | grep -q "$path" && exists=true ;;
            container) docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${path}$" && exists=true ;;
            volume)    docker volume ls --format '{{.Name}}' 2>/dev/null | grep -q "^${path}$" && exists=true ;;
            image)     docker image inspect "$path" &>/dev/null && exists=true ;;
            keychain)  security find-generic-password -s "$path" &>/dev/null && exists=true ;;
            account)   id "$path" &>/dev/null && exists=true ;;
        esac

        if [[ "$exists" == true ]]; then
            local cksum="null" version="N/A"
            if [[ "$check_type" == "file" ]]; then
                cksum="$(manifest_checksum "$path")"
            fi
            if [[ "$check_type" == "brew" ]]; then
                version="$(manifest_brew_version "$path")"
            fi
            manifest_add "$id" "$type" "$category" "$path" "$version" \
                "${cksum}" "rebuild" false true ""
            printf "  ${GREEN}Found${NC}:     %-20s %s\n" "($type)" "$path"
            found=$((found + 1))
        else
            printf "  ${YELLOW}Not found${NC}: %-20s %s\n" "($type)" "$path"
            not_found=$((not_found + 1))
        fi
    }

    # --- Brew packages (bootstrap.sh) ---
    _rebuild_check "brew-jq"             "brew-package" "tooling" "jq" "brew"
    _rebuild_check "brew-bash"           "brew-package" "tooling" "bash" "brew"
    _rebuild_check "brew-colima"         "brew-package" "tooling" "colima" "brew"
    _rebuild_check "brew-docker"         "brew-package" "tooling" "docker" "brew"
    _rebuild_check "brew-docker-compose" "brew-package" "tooling" "docker-compose" "brew"

    # --- Directories (bootstrap.sh) ---
    local dirs=("/opt/n8n" "/opt/n8n/scripts" "/opt/n8n/etc" "/opt/n8n/logs"
                "/opt/n8n/logs/audit" "/opt/n8n/data")
    for dir in "${dirs[@]}"; do
        _rebuild_check "dir-${dir//\//-}" "directory" "tooling" "$dir" "dir"
    done

    # --- Deployed scripts (bootstrap.sh) ---
    local scripts=("hardening-audit.sh" "audit-notify.sh" "hardening-fix.sh" "audit-cron.sh")
    for s in "${scripts[@]}"; do
        _rebuild_check "file-${s}" "file" "tooling" "/opt/n8n/scripts/${s}" "file"
    done

    # --- Config files (bootstrap.sh) ---
    _rebuild_check "file-notify-conf" "file" "tooling" "/opt/n8n/etc/notify.conf" "file"

    # --- LaunchD plist (bootstrap.sh) ---
    _rebuild_check "launchd-com-openclaw-audit-cron" "launchd-plist" "tooling" \
        "/Library/LaunchDaemons/com.openclaw.audit-cron.plist" "file"

    # --- /etc/shells line (bootstrap.sh) ---
    local bash_path
    if [[ "$(uname -m)" == "arm64" ]]; then bash_path="/opt/homebrew/bin/bash"; else bash_path="/usr/local/bin/bash"; fi
    if grep -q "$bash_path" /etc/shells 2>/dev/null; then
        manifest_add "system-config-line-etc-shells" "system-config-line" "hardening" \
            "/etc/shells" "N/A" "null" "rebuild" false true "Homebrew bash"
        printf "  ${GREEN}Found${NC}:     %-20s %s\n" "(system-config-line)" "/etc/shells ($bash_path)"
        found=$((found + 1))
    fi

    # --- Shell config (bootstrap.sh / shellrc_setup) ---
    _rebuild_check "shell-rc-file" "shell-rc-file" "tooling" "${HOME}/.openclaw/shellrc" "file"
    local rc_file
    rc_file="$(manifest_detect_shell)"
    local source_line='[ -f ~/.openclaw/shellrc ] && source ~/.openclaw/shellrc'
    if grep -qF "$source_line" "$rc_file" 2>/dev/null; then
        manifest_add "shell-config-line-${rc_file##*/}" "shell-config-line" "tooling" \
            "$rc_file" "N/A" "null" "rebuild" false true "source line for ~/.openclaw/shellrc"
        printf "  ${GREEN}Found${NC}:     %-20s %s\n" "(shell-config-line)" "$rc_file"
        found=$((found + 1))
    fi

    # --- Gateway artifacts (gateway-setup.sh) ---
    _rebuild_check "colima-vm-default"   "colima-vm"        "tooling" "default" "colima"
    _rebuild_check "docker-container-n8n" "docker-container" "tooling" "templates-n8n-1" "container"
    _rebuild_check "docker-volume-n8n"   "docker-volume"    "tooling" "templates_n8n_data" "volume"
    _rebuild_check "docker-image-n8n"    "docker-image"     "tooling" "docker.n8n.io/n8nio/n8n" "image"
    _rebuild_check "file-encryption-key" "file"             "tooling" "${HOME}/.openclaw/n8n-encryption-key" "file"
    _rebuild_check "keychain-n8n-bearer" "keychain-entry"   "tooling" "n8n-gateway-bearer" "keychain"

    # --- Hardening artifacts (hardening-fix.sh) ---
    _rebuild_check "hardening-ssh-config" "system-config-file" "hardening" \
        "/etc/ssh/sshd_config.d/hardening.conf" "file"
    _rebuild_check "hardening-service-account-n8n" "system-account" "hardening" "_n8n" "account"

    # Browser policies (check all known browser domains)
    local browser_plists=(
        "hardening-browser-policy-chromium:/Library/Managed Preferences/org.chromium.Chromium.plist"
        "hardening-browser-policy-chrome:/Library/Managed Preferences/com.google.Chrome.plist"
        "hardening-browser-policy-brave:/Library/Managed Preferences/com.brave.Browser.plist"
        "hardening-browser-policy-edge:/Library/Managed Preferences/com.microsoft.Edge.plist"
    )
    for entry in "${browser_plists[@]}"; do
        local bid="${entry%%:*}" bpath="${entry#*:}"
        _rebuild_check "$bid" "managed-preference" "hardening" "$bpath" "file"
    done

    # Spotlight exclusions
    for spath in "$HOME/.n8n" "$HOME/.colima" "/opt/n8n"; do
        local sid="hardening-spotlight-${spath##*/}"
        if [[ -d "$spath" ]]; then
            # Can't reliably detect if indexing is off; add if dir exists
            manifest_add "$sid" "spotlight-exclusion" "hardening" "$spath" "N/A" \
                "null" "rebuild" false true "Spotlight exclusion (best-effort)"
            printf "  ${GREEN}Found${NC}:     %-20s %s\n" "(spotlight-exclusion)" "$spath"
            found=$((found + 1))
        fi
    done

    printf "\n${BOLD}Rebuilt manifest with %d artifacts (%d not found on disk).${NC}\n" "$found" "$not_found"
    printf "Written to: %s\n" "${MANIFEST_FILE}"
}

# ============================================================
# Command: uninstall (T017-T020)
# ============================================================

# T019: Hardening artifact security warnings
_hardening_warning() {
    local type="$1" id="$2"
    case "$type" in
        system-config-file)   echo "This re-enables SSH password authentication" ;;
        system-config-line)   echo "This weakens the firewall" ;;
        managed-preference)   echo "This loosens Chromium browser policy" ;;
        system-account)       echo "This may orphan files owned by _n8n" ;;
        spotlight-exclusion)  echo "Spotlight will re-index this path" ;;
        *)                    echo "" ;;
    esac
}

# Get the line pattern for shell/system config-line removal
_get_removal_pattern() {
    local id="$1" type="$2"
    case "$type" in
        shell-config-line)
            echo '[ -f ~/.openclaw/shellrc ] && source ~/.openclaw/shellrc'
            ;;
        system-config-line)
            case "$id" in
                *etc-shells*)
                    if [[ "$(uname -m)" == "arm64" ]]; then
                        echo "/opt/homebrew/bin/bash"
                    else
                        echo "/usr/local/bin/bash"
                    fi
                    ;;
                *) echo "" ;;
            esac
            ;;
        *) echo "" ;;
    esac
}

# Dispatch artifact type to the correct remove_* function
_uninstall_dispatch() {
    local type="$1" path="$2" checksum="$3" backup_dir="$4" id="$5"
    case "$type" in
        brew-package)         remove_brew_package "$path" ;;
        file)                 remove_file "$path" "$checksum" "$backup_dir" ;;
        directory)            remove_directory "$path" ;;
        shell-config-line)
            local pattern
            pattern="$(_get_removal_pattern "$id" "$type")"
            if [[ -n "$pattern" ]]; then
                remove_shell_config_line "$path" "$pattern"
            else
                return 1
            fi
            ;;
        shell-rc-file)        remove_shell_rc_file "$path" ;;
        keychain-entry)       remove_keychain_entry "$path" ;;
        launchd-plist)        remove_launchd_plist "$path" ;;
        docker-container)     remove_docker_container "$path" ;;
        docker-volume)        remove_docker_volume "$path" ;;
        docker-image)         remove_docker_image "$path" ;;
        colima-vm)            remove_colima_vm "$path" ;;
        system-account)       remove_system_account "$path" ;;
        system-config-file)   remove_system_config_file "$path" "$checksum" "$backup_dir" ;;
        system-config-line)
            local pattern
            pattern="$(_get_removal_pattern "$id" "$type")"
            if [[ -n "$pattern" ]]; then
                remove_system_config_line "$path" "$pattern"
            else
                return 1
            fi
            ;;
        managed-preference)   remove_managed_preference "$path" ;;
        spotlight-exclusion)  remove_spotlight_exclusion "$path" ;;
        *)                    return 1 ;;
    esac
}

# T020: Generate uninstall report file
_generate_uninstall_report() {
    local backup_dir="$1"
    local r_removed="$2" r_skipped_pre="$3" r_skipped_shared="$4"
    local r_kept="$5" r_backed="$6" r_failed="$7" r_manual="$8"

    local report_file="${MANIFEST_DIR}/uninstall-report.txt"
    local repo_root
    repo_root="$(jq -r '.repo_root // "unknown"' "${MANIFEST_FILE}" 2>/dev/null)" || repo_root="unknown"

    {
        echo "OpenClaw Uninstall Report"
        echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "Repo: ${repo_root}"
        echo ""

        if [[ -n "$r_removed" ]]; then
            echo "REMOVED:"
            printf '%s' "$r_removed"
            echo ""
        fi

        if [[ -n "$r_skipped_pre" ]]; then
            echo "SKIPPED — PRE-EXISTING:"
            printf '%s' "$r_skipped_pre"
            echo ""
        fi

        if [[ -n "$r_skipped_shared" ]]; then
            echo "SKIPPED — SHARED:"
            printf '%s' "$r_skipped_shared"
            echo ""
        fi

        if [[ -n "$r_kept" ]]; then
            echo "KEPT:"
            printf '%s' "$r_kept"
            echo ""
        fi

        if [[ -n "$r_backed" ]]; then
            echo "BACKED UP — MODIFIED:"
            printf '%s' "$r_backed"
            echo ""
        fi

        if [[ -n "$r_failed" ]]; then
            echo "FAILED:"
            printf '%s' "$r_failed"
            echo ""
        fi

        if [[ -n "$r_manual" ]]; then
            echo "MANUAL CLEANUP:"
            printf '%s' "$r_manual"
            echo ""
        fi

        echo "This report is the only remaining openclaw artifact."
        echo "Delete it with: rm -rf ~/.openclaw"
    } > "$report_file"

    printf "\n  Report: %s\n" "$report_file"
    printf "  To fully clean up: rm -rf ~/.openclaw\n"
}

cmd_uninstall() {
    local dry_run=false force=false keep_data=false keep_hardening=false confirm_mode=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)         dry_run=true; shift ;;
            --force)           force=true; shift ;;
            --keep-data)       keep_data=true; shift ;;
            --keep-hardening)  keep_hardening=true; shift ;;
            --confirm)         confirm_mode=true; shift ;;
            *)                 echo "Unknown uninstall option: $1" >&2; exit 2 ;;
        esac
    done

    # Check manifest exists
    if [[ ! -f "${MANIFEST_FILE}" ]]; then
        printf "${YELLOW}No manifest found.${NC} Nothing to uninstall.\n"
        printf "  Hint: openclaw manifest --rebuild\n"
        exit 2
    fi

    manifest_lock
    manifest_setup_traps

    printf "${BOLD}OpenClaw Uninstall${NC}\n"
    if [[ "$dry_run" == true ]]; then
        printf "Mode: ${CYAN}dry-run${NC} (no changes will be made)\n"
    elif [[ "$force" == true ]]; then
        printf "Mode: ${YELLOW}force${NC} (all confirmations skipped)\n"
    fi

    # Read artifacts in reverse installation order (R-006)
    local artifacts_json
    artifacts_json="$(jq '[.artifacts[] | select(.status == "installed" or .status == "pending" or .status == "skipped")] | reverse' "${MANIFEST_FILE}")"
    local total
    total="$(echo "$artifacts_json" | jq 'length')"

    if [[ "$total" -eq 0 ]]; then
        printf "\n  No removable artifacts found.\n"
        return
    fi

    local pre_count
    pre_count="$(echo "$artifacts_json" | jq '[.[] | select(.pre_existing == true)] | length')"

    printf "\nThis will process ${BOLD}%d${NC} tracked artifacts." "$total"
    if [[ "$pre_count" -gt 0 ]]; then
        printf "\n%d pre-existing items will be skipped." "$pre_count"
    fi
    printf "\n"

    # Interactive confirmation (skip if --force or --dry-run)
    if [[ "$force" != true && "$dry_run" != true ]]; then
        printf "\nContinue? [y/N] "
        local reply
        read -r reply </dev/tty 2>/dev/null || reply="n"
        case "$reply" in
            [yY]|[yY][eE][sS]) ;;
            *) printf "Aborted.\n"; exit 0 ;;
        esac
    fi

    # T017: Sudo handling
    local needs_sudo=false
    local sudo_types=("system-config-file" "system-config-line" "system-account" "managed-preference" "spotlight-exclusion" "launchd-plist")
    for stype in "${sudo_types[@]}"; do
        if echo "$artifacts_json" | jq -e --arg t "$stype" '.[] | select(.type == $t and .pre_existing == false)' >/dev/null 2>&1; then
            needs_sudo=true
            break
        fi
    done
    # Also check for files/dirs in system paths
    if echo "$artifacts_json" | jq -e '.[] | select((.type == "file" or .type == "directory") and .pre_existing == false and (.path | test("^/(opt|Library|etc)")))' >/dev/null 2>&1; then
        needs_sudo=true
    fi

    if [[ "$needs_sudo" == true && "$dry_run" != true ]]; then
        printf "\n  ${BOLD}ℹ${NC}  Some artifacts require elevated privileges.\n"
        sudo -v 2>/dev/null || { printf "  ${RED}✗${NC}  sudo authentication failed\n"; exit 1; }
        manifest_sudo_keepalive
    fi

    # T020: Setup backup directory
    local backup_dir
    backup_dir="${MANIFEST_DIR}/backups/$(date -u +%Y-%m-%dT%H%M%SZ)"

    printf "\n"

    # --- Core loop (T018) ---
    local removed=0 skipped=0 failed=0 idx=0
    local r_removed="" r_skipped_pre="" r_skipped_shared=""
    local r_kept="" r_backed="" r_failed="" r_manual=""

    while IFS= read -r entry; do
        idx=$((idx + 1))
        local id type category path checksum pre_existing
        id="$(echo "$entry" | jq -r '.id')"
        type="$(echo "$entry" | jq -r '.type')"
        category="$(echo "$entry" | jq -r '.category')"
        path="$(echo "$entry" | jq -r '.path')"
        checksum="$(echo "$entry" | jq -r '.checksum // ""')"
        pre_existing="$(echo "$entry" | jq -r '.pre_existing')"

        # Skip pre-existing
        if [[ "$pre_existing" == "true" ]]; then
            printf "  [%d/%d] ${YELLOW}SKIP${NC}    [%-20s] %s (pre-existing)\n" "$idx" "$total" "$type" "$path"
            r_skipped_pre+="  — [$type] $path (installed before openclaw)"$'\n'
            skipped=$((skipped + 1))
            continue
        fi

        # Skip hardening if --keep-hardening
        if [[ "$keep_hardening" == true && "$category" == "hardening" ]]; then
            printf "  [%d/%d] ${YELLOW}KEPT${NC}    [%-20s] %s (--keep-hardening)\n" "$idx" "$total" "$type" "$path"
            r_kept+="  — [$type] $path"$'\n'
            skipped=$((skipped + 1))
            continue
        fi

        # Skip docker volumes if --keep-data
        if [[ "$keep_data" == true && "$type" == "docker-volume" ]]; then
            printf "  [%d/%d] ${YELLOW}KEPT${NC}    [%-20s] %s (--keep-data)\n" "$idx" "$total" "$type" "$path"
            r_kept+="  — [$type] $path (data preserved)"$'\n'
            skipped=$((skipped + 1))
            continue
        fi

        # T019: Hardening artifact warnings
        if [[ "$category" == "hardening" && "$force" != true && "$dry_run" != true ]]; then
            local warning
            warning="$(_hardening_warning "$type" "$id")"
            if [[ -n "$warning" ]]; then
                printf "         ${YELLOW}⚠  %s${NC}\n" "$warning"
            fi
        fi

        # --confirm mode: prompt before each removal
        if [[ "$confirm_mode" == true && "$force" != true && "$dry_run" != true ]]; then
            printf "  Remove [%s] %s? [y/N] " "$type" "$path"
            local reply
            read -r reply </dev/tty 2>/dev/null || reply="n"
            case "$reply" in
                [yY]|[yY][eE][sS]) ;;
                *)
                    printf "  [%d/%d] ${YELLOW}SKIP${NC}    [%-20s] %s (user declined)\n" "$idx" "$total" "$type" "$path"
                    skipped=$((skipped + 1))
                    continue
                    ;;
            esac
        fi

        # --dry-run: display only
        if [[ "$dry_run" == true ]]; then
            printf "  [%d/%d] ${CYAN}DRY-RUN${NC} [%-20s] %s\n" "$idx" "$total" "$type" "$path"
            continue
        fi

        # T020: Check for drift before removal (for backup tracking in report)
        local drifted=false
        if [[ -n "$checksum" && "$checksum" != "null" && -f "$path" ]]; then
            local current_cksum
            current_cksum="$(manifest_checksum "$path")"
            if [[ -n "$current_cksum" && "$current_cksum" != "$checksum" ]]; then
                drifted=true
            fi
        fi

        # Dispatch to appropriate removal function
        local rc=0
        _uninstall_dispatch "$type" "$path" "$checksum" "$backup_dir" "$id" || rc=$?

        case $rc in
            0)
                printf "  [%d/%d] ${GREEN}✓${NC}       [%-20s] %s\n" "$idx" "$total" "$type" "$path"
                manifest_update "$id" "status" "removed"
                if [[ "$category" == "hardening" ]]; then
                    r_removed+="  ⚠ [$type] $path"$'\n'
                else
                    r_removed+="  ✓ [$type] $path"$'\n'
                fi
                if [[ "$drifted" == true ]]; then
                    r_backed+="  ⚠ [$type] $path"$'\n'
                    r_backed+="    Backup: ${backup_dir}${path}"$'\n'
                fi
                removed=$((removed + 1))
                ;;
            1)
                printf "  [%d/%d] ${YELLOW}—${NC}       [%-20s] %s\n" "$idx" "$total" "$type" "$path"
                # Check if shared brew package
                if [[ "$type" == "brew-package" ]]; then
                    local deps
                    deps="$(brew uses --installed "$path" 2>/dev/null | tr '\n' ', ' | sed 's/,$//')" || true
                    if [[ -n "$deps" ]]; then
                        r_skipped_shared+="  — [$type] $path (used by: $deps)"$'\n'
                    fi
                fi
                skipped=$((skipped + 1))
                ;;
            2)
                printf "  [%d/%d] ${RED}✗${NC}       [%-20s] %s\n" "$idx" "$total" "$type" "$path"
                r_failed+="  ✗ [$type] $path"$'\n'
                failed=$((failed + 1))
                ;;
        esac
    done < <(echo "$artifacts_json" | jq -c '.[]')

    # Summary
    printf "\n${BOLD}════════════════════════════════════════${NC}\n"
    printf "  ${GREEN}%d REMOVED${NC}  |  ${YELLOW}%d SKIPPED${NC}  |  ${RED}%d FAILED${NC}\n" "$removed" "$skipped" "$failed"
    printf "${BOLD}════════════════════════════════════════${NC}\n"

    # T020: Generate report
    if [[ "$dry_run" != true ]]; then
        _generate_uninstall_report "$backup_dir" \
            "$r_removed" "$r_skipped_pre" "$r_skipped_shared" \
            "$r_kept" "$r_backed" "$r_failed" "$r_manual"
    fi

    manifest_sudo_keepalive_stop

    if [[ "$failed" -gt 0 ]]; then
        exit 1
    fi
}

# ============================================================
# Command: install
# ============================================================

cmd_install() {
    local hardening_only=false
    local -a passthrough_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --hardening-only) hardening_only=true; shift ;;
            *)                passthrough_args+=("$1"); shift ;;
        esac
    done

    if [[ "${hardening_only}" == true ]]; then
        printf "${BOLD}OpenClaw Install (hardening only)${NC}\n"
        printf "Dispatching to hardening-fix.sh with manifest tracking...\n\n"
        # Initialize manifest if needed
        manifest_setup_traps
        manifest_lock
        manifest_init
        # Run hardening-fix.sh from the repo scripts directory
        if [[ -x "${SCRIPT_DIR}/hardening-fix.sh" ]]; then
            bash "${SCRIPT_DIR}/hardening-fix.sh" "${passthrough_args[@]+"${passthrough_args[@]}"}"
        else
            printf "  ${RED}✗${NC}  hardening-fix.sh not found at %s\n" "${SCRIPT_DIR}/hardening-fix.sh"
            exit 2
        fi
        return
    else
        printf "${BOLD}OpenClaw Install${NC}\n"
        printf "  Run: bash scripts/bootstrap.sh && bash scripts/gateway-setup.sh\n"
    fi
}

# ============================================================
# Main Dispatcher
# ============================================================

main() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 0
    fi

    local command="$1"
    shift

    case "${command}" in
        manifest)   cmd_manifest "$@" ;;
        uninstall)  cmd_uninstall "$@" ;;
        install)    cmd_install "$@" ;;
        --help)     usage ;;
        --version)  echo "openclaw v${VERSION}" ;;
        *)          echo "Unknown command: ${command}" >&2; usage >&2; exit 2 ;;
    esac
}

main "$@"
