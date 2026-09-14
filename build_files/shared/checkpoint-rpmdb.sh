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
# docs/skills/ci/references/failure-modes.md).
#
# #1153 checkpointed the WAL and switched to rollback-journal mode, but the
# corruption recurred at the base-common -> extension-builder boundary
# (issue #1167): the writer stage exits cleanly yet the child stage's first
# rpmdb read still returns SQLITE_CORRUPT. The evidence points at how Buildah
# commits the overlay layer — an in-place rewrite of the existing rpmdb inode
# is not carried across the stage boundary under rootful Buildah 1.42.1/overlay.
#
# This helper therefore does three things:
#   1. Validate the checkpoint instead of trusting a clean exit. It fails
#      unless wal_checkpoint(TRUNCATE) reports busy=0, journal_mode is delete,
#      and PRAGMA quick_check is ok, so a busy checkpoint or a corrupt database
#      fails here rather than at the next stage's first rpmdb read.
#   2. Materialize a brand-new inode and atomically swap it in, so the committed
#      layer carries a freshly written file instead of an in-place mutation.
#   3. Reopen the swapped-in file read-only and require quick_check=ok, then run
#      `rpm --verifydb` when the rpm toolchain is present.
#
# Run this as the last step of any RUN whose rpmdb a later stage or the final
# image will read.

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
import os
import sqlite3
import stat
import sys

dbpath = sys.argv[1]


def fail(msg):
    sys.stderr.write(f"checkpoint-rpmdb: {msg}\n")
    sys.exit(1)


# Phase 1 — checkpoint, convert to rollback-journal mode, and verify integrity
# on the same write connection. Every pragma result is checked so a busy
# checkpoint or a corrupt database fails loudly here. A malformed database
# raises instead of returning a value, so wrap the whole phase.
conn = None
try:
    conn = sqlite3.connect(dbpath)
    cur = conn.cursor()
    busy, _logged, _checkpointed = cur.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchone()
    if busy != 0:
        fail(f"wal_checkpoint(TRUNCATE) returned busy={busy}; database was locked and not fully checkpointed")
    mode = cur.execute("PRAGMA journal_mode=DELETE").fetchone()[0]
    if mode != "delete":
        fail(f"journal_mode is {mode!r}, expected 'delete'")
    integrity = cur.execute("PRAGMA quick_check").fetchone()[0]
    if integrity != "ok":
        fail(f"quick_check reported {integrity!r}; refusing to commit a corrupt layer")
    conn.commit()
except sqlite3.Error as exc:
    fail(str(exc))
finally:
    conn.close()

# The WAL sidecars must be gone before we copy, so the sibling is a true
# single-file snapshot of the checkpointed database.
for sidecar in (f"{dbpath}-wal", f"{dbpath}-shm"):
    try:
        os.unlink(sidecar)
    except FileNotFoundError:
        pass

# Phase 2 — materialize a brand-new inode and atomically swap it in.
# Buildah commits overlay layers as changes against the previous inode, and an
# in-place rewrite of that inode is what the CI rootful-buildah+overlay stack
# fails to carry across the stage boundary (issue #1167). Writing a fresh file
# and os.replace()ing it over the original forces the committed layer to carry
# a newly written inode instead of an in-place mutation.
tmp = f"{dbpath}.fresh"
try:
    os.unlink(tmp)
except FileNotFoundError:
    pass
st = os.stat(dbpath)
# Plain byte copy: never a reflink/copy-on-write of the source inode, so the
# destination is self-contained even on a reflinking filesystem.
with open(dbpath, "rb") as src, open(tmp, "wb") as dst:
    while True:
        chunk = src.read(1 << 20)
        if not chunk:
            break
        dst.write(chunk)
    dst.flush()
    os.fsync(dst)
os.chmod(tmp, stat.S_IMODE(st.st_mode))
try:
    os.chown(tmp, st.st_uid, st.st_gid)
except PermissionError:
    pass
os.replace(tmp, dbpath)
dirfd = os.open(os.path.dirname(dbpath) or ".", os.O_DIRECTORY)
try:
    os.fsync(dirfd)
finally:
    os.close(dirfd)

# Phase 3 — reopen the swapped-in file read-only and require integrity, so a
# corrupt result surfaces here (exit non-zero) instead of at the next stage's
# first rpmdb read.
ro = None
try:
    ro = sqlite3.connect(f"file:{dbpath}?mode=ro", uri=True)
    integrity = ro.execute("PRAGMA quick_check").fetchone()[0]
    if integrity != "ok":
        fail(f"post-swap quick_check reported {integrity!r}")
except sqlite3.Error as exc:
    fail(str(exc))
finally:
    ro.close()
PYEOF

# `rpm --verifydb` only exists on the Fedora/bluefin build toolchain, never on
# the plain Ubuntu unit-test runner, so guard it: it is a no-op in unit tests
# and a real integrity gate in the image build.
if command -v rpm >/dev/null 2>&1; then
    rpm --verifydb "${RPMDB_PATH}"
fi

echo "::endgroup::"
