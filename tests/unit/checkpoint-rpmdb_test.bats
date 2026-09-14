#!/usr/bin/env bats
# Unit tests for build_files/shared/checkpoint-rpmdb.sh.
# Run with: bats tests/unit/checkpoint-rpmdb_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
CHECKPOINT_RPMDB="${SCRIPT_DIR}/../../build_files/shared/checkpoint-rpmdb.sh"

setup() {
    TEST_ROOT="${SCRIPT_DIR}/.bats-sandbox/checkpoint-rpmdb.${BATS_TEST_NUMBER:-0}.$$"
    mkdir -p "${TEST_ROOT}"
    RPMDB_PATH="${TEST_ROOT}/rpmdb.sqlite"
    export RPMDB_PATH

    # A real WAL-mode database with live sidecars, like the one a dnf
    # transaction leaves behind at the end of a build stage.
    python3 - "${RPMDB_PATH}" <<'PYEOF'
import sqlite3
import sys

db = sqlite3.connect(sys.argv[1])
db.execute("PRAGMA journal_mode=WAL")
db.execute("CREATE TABLE Packages (hnum INTEGER PRIMARY KEY, blob BLOB)")
db.execute("INSERT INTO Packages (hnum, blob) VALUES (1, x'c0ffee')")
db.commit()
# Leave the connection open state behind us without checkpointing so the
# -wal file still holds the committed frames, then close.
db.close()
PYEOF
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

journal_mode() {
    python3 -c '
import sqlite3
import sys

db = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
print(db.execute("PRAGMA journal_mode").fetchone()[0])
' "${RPMDB_PATH}"
}

@test "checkpoint-rpmdb: converts the database to rollback-journal mode" {
    run "${CHECKPOINT_RPMDB}"
    [ "$status" -eq 0 ]

    run journal_mode
    [ "$status" -eq 0 ]
    [ "$output" = "delete" ]
}

@test "checkpoint-rpmdb: removes the -shm and -wal sidecar files" {
    # Recreate the stale-sidecar state the base images ship with.
    touch "${RPMDB_PATH}-shm" "${RPMDB_PATH}-wal"

    run "${CHECKPOINT_RPMDB}"
    [ "$status" -eq 0 ]

    [ ! -e "${RPMDB_PATH}-shm" ]
    [ ! -e "${RPMDB_PATH}-wal" ]
}

@test "checkpoint-rpmdb: preserves the database contents" {
    run "${CHECKPOINT_RPMDB}"
    [ "$status" -eq 0 ]

    run python3 -c '
import sqlite3
import sys

db = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
print(db.execute("SELECT hnum, hex(blob) FROM Packages").fetchone())
' "${RPMDB_PATH}"
    [ "$status" -eq 0 ]
    [ "$output" = "(1, 'C0FFEE')" ]
}

@test "checkpoint-rpmdb: fails loudly when the database is missing" {
    rm -f "${RPMDB_PATH}"

    run "${CHECKPOINT_RPMDB}"
    [ "$status" -ne 0 ]
    [[ "$output" == *"no rpmdb at"* ]]
    # The failed run must not have created a stray empty database.
    [ ! -e "${RPMDB_PATH}" ]
}

@test "checkpoint-rpmdb: materializes a fresh inode instead of rewriting in place" {
    local inode_before inode_after
    # First run lands on inode A; a second run must land on a different inode
    # B, proving the helper always writes a sibling file and atomically swaps
    # it in rather than rewriting the original inode in place.
    run "${CHECKPOINT_RPMDB}"
    [ "$status" -eq 0 ]
    inode_before=$(stat -c '%i' "${RPMDB_PATH}")

    run "${CHECKPOINT_RPMDB}"
    [ "$status" -eq 0 ]
    inode_after=$(stat -c '%i' "${RPMDB_PATH}")

    [ "${inode_before}" != "${inode_after}" ]
}

@test "checkpoint-rpmdb: fails loudly when the database is corrupt" {
    # SQLite stores no per-page content checksums by default, so quick_check
    # only catches structural damage. Truncating the file leaves the header
    # claiming more pages than exist on disk; the integrity check must reject
    # it rather than ship a truncated layer to the next stage.
    python3 - "${RPMDB_PATH}" <<'PYEOF'
import os

path = sys.argv[1]
pages = os.path.getsize(path) // 4096
# Keep (pages - 1) full pages plus a sliver of the next, so the header still
# references a final page that no longer fully exists on disk.
os.truncate(path, (pages - 1) * 4096 + 2000)
PYEOF

    run "${CHECKPOINT_RPMDB}"
    [ "$status" -ne 0 ]
    [[ "$output" == *"checkpoint-rpmdb:"* ]]
}
