#!/usr/bin/env bats
# Tests for mkdir-based locking (replaced flock which is Linux-only)

load '../helpers/setup'

@test "manifest_lock creates lock directory" {
    manifest_lock
    [ -d "${MANIFEST_DIR}/.lock" ]
}

@test "manifest_lock writes PID file" {
    manifest_lock
    [ -f "${MANIFEST_DIR}/.lock/pid" ]
    local pid
    pid=$(cat "${MANIFEST_DIR}/.lock/pid")
    [ "$pid" = "$$" ]
}

@test "manifest_lock recovers stale lock from dead PID" {
    mkdir -p "${MANIFEST_DIR}/.lock"
    echo "99999" > "${MANIFEST_DIR}/.lock/pid"
    # PID 99999 is almost certainly not running
    manifest_lock
    local pid
    pid=$(cat "${MANIFEST_DIR}/.lock/pid")
    [ "$pid" = "$$" ]
}

@test "manifest_lock fails when lock held by live process" {
    mkdir -p "${MANIFEST_DIR}/.lock"
    echo "$$" > "${MANIFEST_DIR}/.lock/pid"
    # Our own PID is alive — lock should be refused
    run bash -c "
        export MANIFEST_DIR='${MANIFEST_DIR}'
        export MANIFEST_FILE='${MANIFEST_FILE}'
        source '${SCRIPT_DIR}/lib/manifest.sh'
        manifest_lock
    "
    [ "$status" -ne 0 ]
}

@test "_manifest_cleanup removes lock directory" {
    manifest_lock
    [ -d "${MANIFEST_DIR}/.lock" ]
    _manifest_cleanup
    [ ! -d "${MANIFEST_DIR}/.lock" ]
}

@test "_manifest_cleanup removes orphaned .tmp file" {
    manifest_init
    touch "${MANIFEST_FILE}.tmp"
    _MANIFEST_LOCK_DIR="${MANIFEST_DIR}/.lock"
    mkdir -p "$_MANIFEST_LOCK_DIR"
    _manifest_cleanup
    [ ! -f "${MANIFEST_FILE}.tmp" ]
}
