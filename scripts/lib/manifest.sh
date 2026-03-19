#!/usr/bin/env bash
# OpenClaw Manifest Library — Shared manifest read/write functions
# Sourced by bootstrap.sh, gateway-setup.sh, hardening-fix.sh, openclaw.sh
#
# All manifest JSON writes use atomic pattern (tmp + mv) per FR-021.
# Signal traps (INT, HUP, TERM) prevent corruption per FR-022.
# Version tracking per artifact per FR-023.
# Background sudo keepalive per FR-024.

# shellcheck disable=SC2059  # Color variables in printf format strings are intentional
set -euo pipefail

# --- Constants ---
# Overridable for test sandboxing (tests pre-set MANIFEST_DIR before sourcing)
MANIFEST_DIR="${MANIFEST_DIR:-${HOME}/.openclaw}"
MANIFEST_FILE="${MANIFEST_FILE:-${MANIFEST_DIR}/manifest.json}"
# Lock is mkdir-based at ${MANIFEST_DIR}/.lock (see manifest_lock)
readonly MANIFEST_SCHEMA_VERSION="1.0.0"

# --- Color Setup (inherited from consumer or set here) ---
if [[ -z "${RED:-}" ]]; then
    RED='\033[0;31m'
    # shellcheck disable=SC2034  # Colors used by sourcing scripts
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    # shellcheck disable=SC2034
    BOLD='\033[1m'
    NC='\033[0m'
    if [[ ! -t 1 ]]; then
        # shellcheck disable=SC2034
        RED='' GREEN='' YELLOW='' CYAN='' BOLD='' NC=''
    fi
fi

# --- Internal State ---
_MANIFEST_SUDO_PID=""
_MANIFEST_LOCK_DIR=""

# ============================================================
# Signal Handling (FR-022)
# ============================================================

manifest_setup_traps() {
    trap '_manifest_cleanup; echo "Interrupted. Re-run to resume." >&2; exit 130' INT HUP TERM
    trap '_manifest_cleanup' EXIT
}

_manifest_cleanup() {
    manifest_sudo_keepalive_stop
    # Clean up tmp file from interrupted atomic write
    rm -f "${MANIFEST_FILE}.tmp" 2>/dev/null || true
    # Release lock directory if we hold it
    if [[ -n "${_MANIFEST_LOCK_DIR:-}" ]]; then
        rm -rf "${_MANIFEST_LOCK_DIR}" 2>/dev/null || true
        _MANIFEST_LOCK_DIR=""
    fi
}

# ============================================================
# File Locking
# ============================================================

manifest_lock() {
    # Acquire exclusive lock using mkdir (atomic, works on macOS — flock is Linux-only).
    # Stale lock recovery: checks PID liveness, then directory age (>1 hour).
    mkdir -p "${MANIFEST_DIR}" 2>/dev/null || true
    chmod 700 "${MANIFEST_DIR}" 2>/dev/null || true
    local lock_dir="${MANIFEST_DIR}/.lock"
    if ! mkdir "$lock_dir" 2>/dev/null; then
        local lock_pid_file="${lock_dir}/pid"
        local stale=false

        if [[ -f "$lock_pid_file" ]]; then
            local lock_pid
            lock_pid="$(cat "$lock_pid_file" 2>/dev/null)" || lock_pid=""
            if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
                stale=true  # PID is dead
            fi
        else
            # No PID file — process crashed between mkdir and PID write.
            # Check directory age: if older than 1 hour, assume stale.
            local lock_age
            lock_age="$(( $(date +%s) - $(stat -f %m "$lock_dir" 2>/dev/null || echo 0) ))"
            if [[ "$lock_age" -gt 3600 ]]; then
                stale=true
            fi
        fi

        if [[ "$stale" == true ]]; then
            rm -rf "$lock_dir" 2>/dev/null
            if ! mkdir "$lock_dir" 2>/dev/null; then
                printf "  ${RED}✗${NC}  Another openclaw process is running.\n" >&2
                exit 1
            fi
        else
            local msg="Another openclaw process is running"
            if [[ -f "$lock_pid_file" ]]; then
                msg+=" (PID: $(cat "$lock_pid_file" 2>/dev/null))"
            fi
            printf "  ${RED}✗${NC}  %s.\n" "$msg" >&2
            printf "  ${RED}✗${NC}  If this is stale, run: rm -rf %s\n" "$lock_dir" >&2
            exit 1
        fi
    fi
    # Write PID immediately for stale detection
    echo $$ > "${lock_dir}/pid"
    _MANIFEST_LOCK_DIR="$lock_dir"
}

# ============================================================
# Sudo Keepalive (FR-024)
# ============================================================

manifest_sudo_keepalive() {
    # Start background loop to refresh sudo credentials every 4 minutes.
    # Self-terminates when parent process exits (prevents zombie on SIGKILL).
    local parent_pid=$$
    if sudo -v 2>/dev/null; then
        (while kill -0 "$parent_pid" 2>/dev/null; do sudo -n -v 2>/dev/null; sleep 180; done) &
        _MANIFEST_SUDO_PID=$!
    fi
}

manifest_sudo_keepalive_stop() {
    if [[ -n "${_MANIFEST_SUDO_PID:-}" ]]; then
        kill "${_MANIFEST_SUDO_PID}" 2>/dev/null || true
        wait "${_MANIFEST_SUDO_PID}" 2>/dev/null || true
        _MANIFEST_SUDO_PID=""
    fi
}

# ============================================================
# Atomic Write Helper (FR-021)
# ============================================================

_manifest_atomic_write() {
    # Usage: echo "$json" | _manifest_atomic_write
    # Reads JSON from stdin, validates, then atomically overwrites MANIFEST_FILE.
    # Refuses to overwrite good manifest with invalid JSON (disk full, pipe broken).
    local tmp="${MANIFEST_FILE}.tmp"
    cat > "${tmp}"
    if ! jq empty "${tmp}" 2>/dev/null; then
        printf "  ${RED}✗${NC}  Manifest write produced invalid JSON — aborting to protect existing data.\n" >&2
        rm -f "${tmp}"
        return 1
    fi
    mv "${tmp}" "${MANIFEST_FILE}"
}

# ============================================================
# Manifest Init (T003)
# ============================================================

manifest_init() {
    # Create ~/.openclaw/ (mode 700) and manifest.json (mode 600)
    # No-op if manifest already exists and is valid JSON
    if [[ -f "${MANIFEST_FILE}" ]] && jq empty "${MANIFEST_FILE}" 2>/dev/null; then
        return 0
    fi

    mkdir -p "${MANIFEST_DIR}"
    chmod 700 "${MANIFEST_DIR}"

    local repo_root
    # Detect repo root: walk up from this library file (lib/manifest.sh -> scripts/ -> repo)
    repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

    local ts
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    jq -n \
        --arg ver "${MANIFEST_SCHEMA_VERSION}" \
        --arg root "${repo_root}" \
        --arg ts "${ts}" \
        '{version: $ver, repo_root: $root, created_at: $ts, updated_at: $ts, artifacts: []}' \
        | _manifest_atomic_write

    chmod 600 "${MANIFEST_FILE}"
}

# ============================================================
# Manifest CRUD (T004)
# ============================================================

manifest_add() {
    # Usage: manifest_add <id> <type> <category> <path> <version> <checksum> <installed_by> <pre_existing> <removable> [notes]
    # Adds entry with status="installed" (or "skipped" if pre_existing=true)
    # Skips silently if entry with same id already exists
    local id="$1" type="$2" category="$3" path="$4" version="$5"
    local checksum="$6" installed_by="$7" pre_existing="$8" removable="$9"
    local notes="${10:-}"

    # Skip if entry already exists
    if manifest_has "${id}"; then
        return 0
    fi

    local status="installed"
    if [[ "${pre_existing}" == "true" ]]; then
        status="skipped"
    fi

    local ts
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    # Use --arg for safe string escaping; handle null via jq filter
    jq \
        --arg id "${id}" \
        --arg type "${type}" \
        --arg cat "${category}" \
        --arg path "${path}" \
        --arg ver "${version}" \
        --arg cksum "${checksum}" \
        --arg ts "${ts}" \
        --arg by "${installed_by}" \
        --argjson pre "${pre_existing}" \
        --argjson rem "${removable}" \
        --arg stat "${status}" \
        --arg notes "${notes}" \
        '.updated_at = $ts | .artifacts += [{
            id: $id, type: $type, category: $cat, path: $path,
            version: $ver,
            checksum: (if $cksum == "" or $cksum == "null" then null else $cksum end),
            installed_at: $ts, installed_by: $by, pre_existing: $pre,
            removable: $rem, status: $stat,
            notes: (if $notes == "" then null else $notes end)
        }]' "${MANIFEST_FILE}" | _manifest_atomic_write
}

manifest_begin_step() {
    # Usage: manifest_begin_step <id> <type> <category> <path> <version> <installed_by> <pre_existing> <removable> [notes]
    # Adds entry with status="pending" BEFORE the action executes
    # On re-run: if status="installed", verifies and skips; if status="pending", allows retry
    local id="$1" type="$2" category="$3" path="$4" version="$5"
    local installed_by="$6" pre_existing="$7" removable="$8"
    local notes="${9:-}"

    if manifest_has "${id}"; then
        local current_status
        current_status="$(manifest_get "${id}" "status")"
        if [[ "${current_status}" == "installed" || "${current_status}" == "skipped" ]]; then
            # Already completed — skip
            return 1
        fi
        # Status is "pending" — remove stale entry so we can retry
        jq --arg id "${id}" '.artifacts |= map(select(.id != $id))' \
            "${MANIFEST_FILE}" | _manifest_atomic_write
    fi

    local ts
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    jq \
        --arg id "${id}" \
        --arg type "${type}" \
        --arg cat "${category}" \
        --arg path "${path}" \
        --arg ver "${version}" \
        --arg ts "${ts}" \
        --arg by "${installed_by}" \
        --argjson pre "${pre_existing}" \
        --argjson rem "${removable}" \
        --arg notes "${notes}" \
        '.updated_at = $ts | .artifacts += [{
            id: $id, type: $type, category: $cat, path: $path,
            version: $ver, checksum: null, installed_at: $ts,
            installed_by: $by, pre_existing: $pre, removable: $rem,
            status: "pending",
            notes: (if $notes == "" then null else $notes end)
        }]' "${MANIFEST_FILE}" | _manifest_atomic_write

    return 0
}

manifest_complete_step() {
    # Usage: manifest_complete_step <id> [checksum]
    # Updates status from "pending" to "installed", sets checksum if provided
    local id="$1"
    local checksum="${2:-}"

    local ts
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    jq \
        --arg id "${id}" \
        --arg cksum "${checksum}" \
        --arg ts "${ts}" \
        '(.artifacts[] | select(.id == $id)) |= (.status = "installed" | .checksum = (if $cksum == "" or $cksum == "null" then null else $cksum end) | .installed_at = $ts) | .updated_at = $ts' \
        "${MANIFEST_FILE}" | _manifest_atomic_write
}

# ============================================================
# Manifest Query (T005)
# ============================================================

manifest_has() {
    # Usage: manifest_has <id>
    # Returns 0 if entry exists, 1 otherwise
    local id="$1"
    [[ -f "${MANIFEST_FILE}" ]] || return 1
    jq -e --arg id "${id}" '.artifacts[] | select(.id == $id)' "${MANIFEST_FILE}" >/dev/null 2>&1
}

manifest_get() {
    # Usage: manifest_get <id> [field]
    # Returns entry JSON or specific field value
    local id="$1"
    local field="${2:-}"

    if [[ -z "${field}" ]]; then
        jq --arg id "${id}" '.artifacts[] | select(.id == $id)' "${MANIFEST_FILE}"
    else
        jq -r --arg id "${id}" --arg f "${field}" '.artifacts[] | select(.id == $id) | .[$f]' "${MANIFEST_FILE}"
    fi
}

# ============================================================
# Manifest Update (T006)
# ============================================================

manifest_update() {
    # Usage: manifest_update <id> <field> <value>
    # Updates a single field of an existing entry.
    # Detects boolean/numeric/null values and uses --argjson to preserve type.
    local id="$1" field="$2" value="$3"

    local ts
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    # Use --argjson for JSON literals (true, false, null, numbers)
    local value_flag="--arg"
    if [[ "$value" =~ ^(true|false|null|[0-9]+\.?[0-9]*)$ ]]; then
        value_flag="--argjson"
    fi

    jq \
        --arg id "${id}" \
        --arg f "${field}" \
        "$value_flag" v "${value}" \
        --arg ts "${ts}" \
        '(.artifacts[] | select(.id == $id))[$f] = $v | .updated_at = $ts' \
        "${MANIFEST_FILE}" | _manifest_atomic_write
}

# ============================================================
# Checksum (T007)
# ============================================================

manifest_checksum() {
    # Usage: manifest_checksum <file_path>
    # Returns SHA-256 hex string, or empty string if file doesn't exist.
    # Uses sudo fallback for root-owned files (e.g., /etc/ssh/sshd_config.d/).
    local file_path="$1"
    if [[ -f "${file_path}" ]]; then
        if [[ -r "${file_path}" ]]; then
            shasum -a 256 "${file_path}" | awk '{print $1}'
        else
            sudo shasum -a 256 "${file_path}" 2>/dev/null | awk '{print $1}'
        fi
    else
        echo ""
    fi
}

# ============================================================
# Pre-existing Detection (T008)
# ============================================================

manifest_detect_preexisting() {
    # Usage: manifest_detect_preexisting <type> <identifier>
    # Returns 0 if pre-existing, 1 if new
    local type="$1" identifier="$2"

    case "${type}" in
        brew-package)
            brew list "${identifier}" &>/dev/null && return 0
            ;;
        file|system-config-file|managed-preference|launchd-plist|shell-rc-file)
            [[ -f "${identifier}" ]] && return 0
            ;;
        directory)
            [[ -d "${identifier}" ]] && return 0
            ;;
        command)
            command -v "${identifier}" &>/dev/null && return 0
            ;;
        colima-vm)
            colima status &>/dev/null && return 0
            ;;
        docker-container)
            docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${identifier}$" && return 0
            ;;
        docker-volume)
            docker volume ls --format '{{.Name}}' 2>/dev/null | grep -q "^${identifier}$" && return 0
            ;;
        docker-image)
            docker image inspect "${identifier}" &>/dev/null && return 0
            ;;
        keychain-entry)
            security find-generic-password -s "${identifier}" &>/dev/null && return 0
            ;;
        system-config-line)
            # Caller must check specific file content
            return 1
            ;;
        spotlight-exclusion|system-account)
            # No reliable pre-existing check; assume new
            return 1
            ;;
    esac
    return 1
}

# ============================================================
# Shell Detection (T009)
# ============================================================

manifest_detect_shell() {
    # Returns the correct rc file path for the operator's login shell
    # bash → ~/.bash_profile, zsh → ~/.zshrc
    # Warns and defaults to zsh for unsupported shells (ksh, fish, etc.)
    local shell_name
    shell_name="$(basename "${SHELL:-/bin/zsh}")"

    local rc_file
    case "${shell_name}" in
        bash)
            rc_file="${HOME}/.bash_profile"
            ;;
        zsh)
            rc_file="${HOME}/.zshrc"
            ;;
        *)
            printf "  ${YELLOW}!${NC}  Unsupported shell: %s. Defaulting to ~/.zshrc (macOS default)\n" "${shell_name}" >&2
            rc_file="${HOME}/.zshrc"
            ;;
    esac

    # Create if it doesn't exist
    if [[ ! -f "${rc_file}" ]]; then
        touch "${rc_file}"
    fi

    echo "${rc_file}"
}

# ============================================================
# Shell RC Setup (T010)
# ============================================================

shellrc_setup() {
    # Creates ~/.openclaw/shellrc and adds guarded source line to shell rc
    # Tracks both artifacts in manifest
    local installed_by="${1:-bootstrap.sh}"

    local repo_root
    repo_root="$(jq -r '.repo_root' "${MANIFEST_FILE}")"

    local shellrc="${MANIFEST_DIR}/shellrc"
    local rc_file
    rc_file="$(manifest_detect_shell)"
    local source_line='[ -f ~/.openclaw/shellrc ] && source ~/.openclaw/shellrc'

    # Create shellrc if it doesn't exist or is empty
    if [[ ! -s "${shellrc}" ]]; then
        cat > "${shellrc}" <<SHELLRC
# OpenClaw Shell Configuration
# Sourced from your shell config via:
#   [ -f ~/.openclaw/shellrc ] && source ~/.openclaw/shellrc
# Do not edit this file directly — it is managed by openclaw.

# --- Aliases ---
alias openclaw='bash ${repo_root}/scripts/openclaw.sh'
alias n8n-token='security find-generic-password -a "openclaw" -s "n8n-gateway-bearer" -w'

# --- Environment ---
# (reserved for future use)

# --- Functions ---
# (reserved for future use)
SHELLRC
    fi

    # Track shellrc in manifest
    local cksum
    cksum="$(manifest_checksum "${shellrc}")"
    manifest_add "shell-rc-file" "shell-rc-file" "tooling" "${shellrc}" "N/A" \
        "${cksum}" "${installed_by}" false true ""

    # Add guarded source line if not already present
    if ! grep -qF "${source_line}" "${rc_file}" 2>/dev/null; then
        printf '\n%s\n' "${source_line}" >> "${rc_file}"
    fi

    # Track source line in manifest
    manifest_add "shell-config-line-${rc_file##*/}" "shell-config-line" "tooling" "${rc_file}" "N/A" \
        "null" "${installed_by}" false true "source line for ~/.openclaw/shellrc"
}

# ============================================================
# Shell Config Migration (T024)
# ============================================================

shellrc_migrate() {
    # Scans operator's shell rc file for pre-NoMOOP openclaw lines,
    # moves them to ~/.openclaw/shellrc, and removes originals.
    # Called during bootstrap.sh for operators upgrading from older installs.
    #
    # SAFETY: processes line-by-line to avoid grep -vF removing comments
    # or zeroing the file when all lines match.
    local rc_file
    rc_file="$(manifest_detect_shell)"
    local shellrc="${MANIFEST_DIR}/shellrc"
    local migrated=0

    [[ -f "$rc_file" ]] || return 0

    local -a patterns=(
        "alias openclaw="
        "alias n8n-token="
        "n8n-gateway-bearer"
    )

    local tmp="${rc_file}.migrate.tmp"
    local changed=false
    rm -f "$tmp" 2>/dev/null

    # Process line by line: migrate matching executable lines, keep everything else
    while IFS= read -r line || [[ -n "$line" ]]; do
        local should_migrate=false

        # Never migrate empty lines, comments, or the source line
        if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]] || [[ "$line" == *"openclaw/shellrc"* ]]; then
            printf '%s\n' "$line" >> "$tmp"
            continue
        fi

        # Check if this executable line matches any migration pattern
        for pattern in "${patterns[@]}"; do
            if [[ "$line" == *"$pattern"* ]]; then
                should_migrate=true
                break
            fi
        done

        if [[ "$should_migrate" == true ]]; then
            # Move to shellrc if not already there
            if ! grep -qF "$line" "$shellrc" 2>/dev/null; then
                printf '%s\n' "$line" >> "$shellrc"
                migrated=$((migrated + 1))
            fi
            changed=true
            # Don't write to tmp — this line is removed from rc file
        else
            printf '%s\n' "$line" >> "$tmp"
        fi
    done < "$rc_file"

    if [[ "$changed" == true ]]; then
        mv "$tmp" "$rc_file"
    else
        rm -f "$tmp"
    fi

    if [[ "$migrated" -gt 0 ]]; then
        printf "  ${CYAN}+${NC}  Migrated %d line(s) from %s to ~/.openclaw/shellrc\n" "$migrated" "$rc_file"
    fi
}

# ============================================================
# Brew Version Helper
# ============================================================

manifest_brew_version() {
    # Usage: manifest_brew_version <package>
    # Returns installed version string, or "unknown"
    local pkg="$1"
    local ver
    ver="$(brew info --json=v2 "${pkg}" 2>/dev/null | jq -r '.formulae[0].installed[0].version // .casks[0].installed // "unknown"' 2>/dev/null)" || ver="unknown"
    echo "${ver}"
}

# ============================================================
# Backup Helper (T016)
# ============================================================

_manifest_backup_file() {
    # Usage: _manifest_backup_file <src_path> <backup_dir>
    # Copies file to backup_dir preserving directory structure.
    # backup_dir is typically ~/.openclaw/backups/<ISO-timestamp>
    local src="$1" backup_dir="$2"
    [[ -f "$src" ]] || return 0
    local dest="${backup_dir}${src}"
    mkdir -p "$(dirname "$dest")"
    if [[ -r "$src" ]]; then
        cp -p "$src" "$dest"
    else
        sudo cp -p "$src" "$dest"
        # Fix ownership so user can manage their own backups
        sudo chown "$(id -u):$(id -g)" "$dest"
    fi
}

# ============================================================
# Artifact Removal Functions (T016)
# ============================================================
# Each function returns: 0=removed, 1=skipped, 2=failed
# Caller is responsible for updating manifest status after call.

remove_brew_package() {
    # Usage: remove_brew_package <name>
    # FR-007: Skip if other installed packages depend on this one
    local name="$1"
    if ! brew list "$name" &>/dev/null; then
        return 1  # not installed
    fi
    # Check if any installed formula depends on this package
    local dependents
    dependents="$(brew uses --installed "$name" 2>/dev/null | tr -d '[:space:]')" || true
    if [[ -n "$dependents" ]]; then
        return 1  # shared with other packages
    fi
    if brew uninstall "$name" 2>/dev/null; then
        return 0
    else
        return 2
    fi
}

remove_file() {
    # Usage: remove_file <path> [expected_checksum] [backup_dir]
    # Backs up file if checksum has drifted before removing
    local path="$1"
    local expected_checksum="${2:-}"
    local backup_dir="${3:-}"
    [[ -f "$path" ]] || return 1
    # Backup if file has drifted from expected checksum
    if [[ -n "$expected_checksum" && "$expected_checksum" != "null" && -n "$backup_dir" ]]; then
        local current_cksum
        current_cksum="$(manifest_checksum "$path")"
        if [[ -n "$current_cksum" && "$current_cksum" != "$expected_checksum" ]]; then
            _manifest_backup_file "$path" "$backup_dir"
        fi
    fi
    if [[ -w "$(dirname "$path")" ]]; then
        if rm -f "$path"; then return 0; else return 2; fi
    else
        if sudo rm -f "$path"; then return 0; else return 2; fi
    fi
}

remove_directory() {
    # Usage: remove_directory <path>
    local path="$1"
    [[ -d "$path" ]] || return 1
    if [[ -w "$(dirname "$path")" ]]; then
        if rm -rf "$path"; then return 0; else return 2; fi
    else
        if sudo rm -rf "$path"; then return 0; else return 2; fi
    fi
}

remove_shell_config_line() {
    # Usage: remove_shell_config_line <rc_file> <line_pattern>
    # Uses grep -vF (fixed-string inverse) to avoid regex escaping issues.
    # Handles edge case where ALL lines match (grep -vF returns 1 with empty output).
    local rc_file="$1"
    local pattern="$2"
    [[ -f "$rc_file" ]] || return 1
    if ! grep -qF "$pattern" "$rc_file" 2>/dev/null; then
        return 1  # line not found
    fi
    local tmp="${rc_file}.tmp"
    # grep -vF exits 1 when no lines survive — that's success (all matching lines removed)
    grep -vF "$pattern" "$rc_file" > "$tmp" 2>/dev/null || true
    mv "$tmp" "$rc_file" && return 0
    rm -f "$tmp" 2>/dev/null
    return 2
}

remove_shell_rc_file() {
    # Usage: remove_shell_rc_file <path>
    local path="$1"
    [[ -f "$path" ]] || return 1
    if rm -f "$path"; then return 0; else return 2; fi
}

remove_keychain_entry() {
    # Usage: remove_keychain_entry <service_name>
    local service="$1"
    if ! security find-generic-password -s "$service" &>/dev/null; then
        return 1  # not found
    fi
    if security delete-generic-password -s "$service" &>/dev/null; then
        return 0
    else
        return 2
    fi
}

remove_launchd_plist() {
    # Usage: remove_launchd_plist <path>
    # Boots out the service before removing the plist file
    local path="$1"
    [[ -f "$path" ]] || return 1
    local label
    label="$(basename "$path" .plist)"
    # Bootout gracefully — ignore errors if not loaded
    sudo launchctl bootout "system/${label}" 2>/dev/null || true
    if sudo rm -f "$path"; then
        return 0
    else
        return 2
    fi
}

remove_docker_container() {
    # Usage: remove_docker_container <name>
    local name="$1"
    if ! docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${name}$"; then
        return 1  # not found
    fi
    if docker rm -f "$name" &>/dev/null; then
        return 0
    else
        return 2
    fi
}

remove_docker_volume() {
    # Usage: remove_docker_volume <name>
    local name="$1"
    if ! docker volume ls --format '{{.Name}}' 2>/dev/null | grep -q "^${name}$"; then
        return 1  # not found
    fi
    if docker volume rm "$name" &>/dev/null; then
        return 0
    else
        return 2
    fi
}

remove_docker_image() {
    # Usage: remove_docker_image <image_ref>
    local image="$1"
    if ! docker image inspect "$image" &>/dev/null; then
        return 1  # not found
    fi
    if docker rmi "$image" &>/dev/null; then
        return 0
    else
        return 2
    fi
}

remove_colima_vm() {
    # Usage: remove_colima_vm [profile]
    local profile="${1:-default}"
    # Check if VM exists (running or stopped)
    if ! colima list 2>/dev/null | grep -q "$profile"; then
        return 1  # not found
    fi
    # Stop first (ignore error if already stopped), then force delete
    colima stop "$profile" 2>/dev/null || true
    if colima delete "$profile" --force 2>/dev/null; then
        return 0
    else
        return 2
    fi
}

remove_system_account() {
    # Usage: remove_system_account <username>
    local username="$1"
    if ! id "$username" &>/dev/null; then
        return 1  # not found
    fi
    if sudo sysadminctl -deleteUser "$username" 2>/dev/null; then
        return 0
    else
        return 2
    fi
}

remove_system_config_file() {
    # Usage: remove_system_config_file <path> [expected_checksum] [backup_dir]
    # Always backs up system config files before removal
    local path="$1"
    local expected_checksum="${2:-}"
    local backup_dir="${3:-}"
    [[ -f "$path" ]] || return 1
    if [[ -n "$backup_dir" ]]; then
        _manifest_backup_file "$path" "$backup_dir"
    fi
    if sudo rm -f "$path"; then
        return 0
    else
        return 2
    fi
}

remove_system_config_line() {
    # Usage: remove_system_config_line <config_file> <line_pattern>
    # Uses grep -vF via sudo for system files
    local config_file="$1"
    local pattern="$2"
    [[ -f "$config_file" ]] || return 1
    if ! sudo grep -qF "$pattern" "$config_file" 2>/dev/null; then
        return 1  # line not found
    fi
    local tmp
    tmp="$(mktemp)"
    # Read as root (file may be root-owned), filter, write to user-writable tmp
    # grep -vF exits 1 when no lines survive — that's success (line removed)
    sudo cat "$config_file" | grep -vF "$pattern" > "$tmp" 2>/dev/null || true
    # cp preserves original ownership/permissions, then clean up tmp
    if sudo cp "$tmp" "$config_file" 2>/dev/null; then
        rm -f "$tmp"
        return 0
    fi
    rm -f "$tmp" 2>/dev/null
    return 2
}

remove_managed_preference() {
    # Usage: remove_managed_preference <path>
    local path="$1"
    [[ -f "$path" ]] || return 1
    if sudo rm -f "$path"; then
        return 0
    else
        return 2
    fi
}

remove_spotlight_exclusion() {
    # Usage: remove_spotlight_exclusion <path>
    # Re-enables Spotlight indexing for the path
    local path="$1"
    [[ -d "$path" ]] || return 1
    if sudo mdutil -i on "$path" &>/dev/null; then
        return 0
    else
        return 2
    fi
}
