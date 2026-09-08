#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# Leave the rpmdb as a single self-contained file in the committed layer.
#
# The Fedora bootc base images ship /usr/lib/sysimage/rpm/rpmdb.sqlite in
# SQLite WAL journal mode together with stale rpmdb.sqlite-{shm,wal}
# sidecars, and every dnf transaction in a build stage switches the database
# back to WAL and leaves fresh sidecars behind. A layer committed in that
# state is not self-contained: the next stage's first rpmdb read must
# reconstruct WAL state through overlayfs, which is where CI's
# "database disk image is malformed" failures come from (issue #995;
# docs/skills/ci/references/failure-modes.md). Checkpointing the WAL and
# switching to the default rollback-journal mode makes the database an
# ordinary single file that any later stage — and the shipped image — can
# read without WAL machinery. Run this as the last step of any RUN whose
# rpmdb a later stage or the final image will read.

# RPMDB_PATH: absolute path of the rpmdb SQLite database.
# Defaults to the bootc sysimage location; overridden in unit tests.
RPMDB_PATH="${RPMDB_PATH:-/usr/lib/sysimage/rpm/rpmdb.sqlite}"

# sqlite3.connect() would silently create an empty database at a wrong path;
# a build without an rpmdb here is broken and must fail now, not later.
if [[ ! -f "${RPMDB_PATH}" ]]; then
    echo "checkpoint-rpmdb: no rpmdb at ${RPMDB_PATH}" >&2
    exit 1
fi

python3 - "${RPMDB_PATH}" <<'PYEOF'
import sqlite3
import sys

db = sqlite3.connect(sys.argv[1])
db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
db.execute("PRAGMA journal_mode=DELETE")
db.close()
PYEOF

rm -f "${RPMDB_PATH}-shm" "${RPMDB_PATH}-wal"

echo "::endgroup::"
