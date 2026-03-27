#!/usr/bin/env bash
# skill-allowlist.sh — Manage the operator-controlled skill allowlist
# Constitution VI: set -euo pipefail, shellcheck clean, idempotent, colored output
# FR-026: Content-hash-based skill identification
# FR-027: Verify installed skills against allowlist
# FR-029: Reject unapproved skills at startup
#
# Usage:
#   scripts/skill-allowlist.sh add <skill-name>     # add/update skill hash
#   scripts/skill-allowlist.sh remove <skill-name>   # remove from allowlist
#   scripts/skill-allowlist.sh check                 # verify all installed skills
#   scripts/skill-allowlist.sh list                  # show current allowlist
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/integrity.sh disable=SC1091
source "${SCRIPT_DIR}/lib/integrity.sh"

REPO_ROOT="$(resolve_repo_root "$SCRIPT_DIR")"
readonly REPO_ROOT
readonly OPENCLAW_DIR="${HOME}/.openclaw"
readonly SKILLS_DIR="${REPO_ROOT}/openclaw/skills"

usage() {
    cat <<'USAGE'
Usage: scripts/skill-allowlist.sh <command> [args]

Commands:
  add <name>    Compute SHA-256 of skill's SKILL.md and add to allowlist
  remove <name> Remove a skill from the allowlist
  check         Verify all installed skills match the allowlist
  list          Show current allowlist with hashes

Skills are identified by content hash (SHA-256 of SKILL.md), not by name.
USAGE
}

ensure_allowlist() {
    if [[ ! -f "$INTEGRITY_ALLOWLIST" ]]; then
        local initial='{"skills":[]}'
        integrity_sign_state_file "$initial" "$INTEGRITY_ALLOWLIST"
    fi
}

# FR-008: Read allowlist data, verifying HMAC signature first
read_allowlist() {
    ensure_allowlist
    if ! integrity_verify_state_file "$INTEGRITY_ALLOWLIST"; then
        log_error "Skill allowlist signature invalid — possible tampering"
        log_error "  Re-approve skills with: make skillallow-add NAME=<skill>"
        return 1
    fi
    jq -c '.' "$INTEGRITY_ALLOWLIST" 2>/dev/null
}

# FR-007: Write allowlist data with HMAC signature
write_allowlist() {
    local data="$1"
    integrity_sign_state_file "$data" "$INTEGRITY_ALLOWLIST"
    integrity_audit_log "skill_allowlist_update" "allowlist updated"
}

find_skill_file() {
    local name="$1"
    local skill_file="${SKILLS_DIR}/${name}/SKILL.md"

    # Check repo skills first
    if [[ -f "$skill_file" ]]; then
        echo "$skill_file"
        return
    fi

    # Check deployed agent skills
    local deployed
    deployed=$(find "${OPENCLAW_DIR}/agents" -path "*/skills/${name}/SKILL.md" -type f 2>/dev/null | head -1)
    if [[ -n "$deployed" ]]; then
        echo "$deployed"
        return
    fi

    return 1
}

do_add() {
    local name="$1"

    local skill_file
    if ! skill_file=$(find_skill_file "$name"); then
        log_error "Skill not found: ${name}"
        log_error "  Checked: ${SKILLS_DIR}/${name}/SKILL.md"
        log_error "  Checked: ${OPENCLAW_DIR}/agents/*/skills/${name}/SKILL.md"
        exit 1
    fi

    local content_hash
    content_hash=$(integrity_compute_sha256 "$skill_file")

    local allowlist
    if ! allowlist=$(read_allowlist); then
        exit 1
    fi

    # Check if already exists — update hash if so
    local exists
    exists=$(echo "$allowlist" | jq --arg n "$name" '[.skills[] | select(.name == $n)] | length')

    if [[ "$exists" -gt 0 ]]; then
        allowlist=$(echo "$allowlist" | jq \
            --arg n "$name" \
            --arg h "$content_hash" \
            --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            'del(.signature) | .skills = [.skills[] | if .name == $n then .content_hash = $h | .approved_at = $ts else . end]')
        log_info "Updated: ${name} → ${content_hash:0:16}..."
    else
        allowlist=$(echo "$allowlist" | jq \
            --arg n "$name" \
            --arg h "$content_hash" \
            --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            'del(.signature) | .skills += [{"name": $n, "content_hash": $h, "approved_at": $ts}]')
        log_info "Added: ${name} → ${content_hash:0:16}..."
    fi

    write_allowlist "$allowlist"
    integrity_audit_log "skill_add" "${name} (${content_hash:0:16}...)"
}

do_remove() {
    local name="$1"

    local allowlist
    if ! allowlist=$(read_allowlist); then
        exit 1
    fi

    local exists
    exists=$(echo "$allowlist" | jq --arg n "$name" '[.skills[] | select(.name == $n)] | length')

    if [[ "$exists" -eq 0 ]]; then
        log_warn "Skill not in allowlist: ${name}"
        return
    fi

    allowlist=$(echo "$allowlist" | jq --arg n "$name" 'del(.signature) | .skills = [.skills[] | select(.name != $n)]')
    write_allowlist "$allowlist"
    integrity_audit_log "skill_remove" "${name}"
    log_info "Removed: ${name}"
}

do_check() {
    log_step "Checking installed skills against allowlist"

    # FR-008: Verify allowlist signature before trusting
    if ! read_allowlist >/dev/null 2>&1; then
        log_error "Skill allowlist signature verification failed"
        return 1
    fi

    local total=0
    local passed=0
    local failed=0
    local unapproved=0

    # Find all installed SKILL.md files
    local skill_files=()
    while IFS= read -r f; do
        skill_files+=("$f")
    done < <(find "${OPENCLAW_DIR}/agents" -path "*/skills/*/SKILL.md" -type f 2>/dev/null)

    # Also check repo skills
    while IFS= read -r f; do
        skill_files+=("$f")
    done < <(find "${SKILLS_DIR}" -name "SKILL.md" -type f 2>/dev/null)

    # Deduplicate by skill name
    declare -A seen_skills
    for f in "${skill_files[@]}"; do
        local name
        name=$(basename "$(dirname "$f")")

        if [[ -n "${seen_skills[$name]:-}" ]]; then
            continue
        fi
        seen_skills[$name]=1
        total=$((total + 1))

        local content_hash
        content_hash=$(integrity_compute_sha256 "$f")

        # Look up in allowlist
        local approved_hash
        approved_hash=$(jq -r --arg n "$name" \
            '.skills[] | select(.name == $n) | .content_hash // empty' \
            "$INTEGRITY_ALLOWLIST" 2>/dev/null)

        if [[ -z "$approved_hash" ]]; then
            log_error "UNAPPROVED: ${name} (not in allowlist)"
            unapproved=$((unapproved + 1))
        elif [[ "$content_hash" == "$approved_hash" ]]; then
            log_info "OK: ${name} (hash matches)"
            passed=$((passed + 1))
        else
            log_error "HASH MISMATCH: ${name}"
            log_error "  allowlist: ${approved_hash:0:16}..."
            log_error "  installed: ${content_hash:0:16}..."
            failed=$((failed + 1))
        fi
    done

    echo ""
    log_info "Skills: ${passed}/${total} passed, ${failed} mismatched, ${unapproved} unapproved"

    if [[ $((failed + unapproved)) -gt 0 ]]; then
        return 1
    fi
    return 0
}

do_list() {
    ensure_allowlist

    local count
    count=$(jq '.skills | length' "$INTEGRITY_ALLOWLIST")

    log_step "Skill Allowlist (${count} entries)"
    echo ""

    jq -r '.skills[] | "  \(.name)\t\(.content_hash[0:16])...\t\(.approved_at)"' \
        "$INTEGRITY_ALLOWLIST" 2>/dev/null | column -t -s $'\t'
}

main() {
    local cmd="${1:-}"
    shift || true

    case "$cmd" in
        add)
            if [[ -z "${1:-}" ]]; then
                log_error "Usage: skill-allowlist.sh add <skill-name>"
                exit 1
            fi
            do_add "$1"
            ;;
        remove)
            if [[ -z "${1:-}" ]]; then
                log_error "Usage: skill-allowlist.sh remove <skill-name>"
                exit 1
            fi
            do_remove "$1"
            ;;
        check)  do_check ;;
        list)   do_list ;;
        *)      usage; exit 1 ;;
    esac
}

main "$@"
