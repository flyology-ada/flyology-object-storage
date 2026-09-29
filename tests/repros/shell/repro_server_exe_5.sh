#!/usr/bin/env bash
# SERVER-EXE-5: the executable enforces the documented exclusive-root
# precondition for the SQLite backend but not for the files backend.
#
#   docs/architecture/files-layout.md:3 -- "The files backend requires
#   exclusive ownership of its configured root by one process."
#   README.md:36 -- "one process owning an exclusive storage root".
#
# sqlite.adb:105-125 takes flock(LOCK_EX|LOCK_NB) on
# <root>/.flyology-object-storage.lock, so a second server on the same SQLite
# root fails to start with a named error.  files.adb:3514-3567 takes no lock,
# so a second server on the same files root starts -- and its Open first
# Delete_Tree's <root>/tmp (files.adb:3548-3564), the staging directory the
# first, live process is using (Temp_Path, files.adb:364-365, is the staging
# target of bucket creation, PUT, tag and multipart-completion publication).
#
# Correct behaviour asserted: a second server pointed at a files root that a
# live server already owns either refuses to start (as the SQLite backend
# does) or leaves the live root's tmp/ contents in place.
#
# The sentinel this program places in <root>/tmp/ stands in for the first
# process's transient staging artefacts; it does NOT demonstrate destruction
# of a real in-flight staging file, which needs a timing race.  What it does
# demonstrate deterministically is that the second process empties a directory
# owned by the live first process.
#
# Control: the same two-process attempt on a SQLite root is refused with a
# named diagnostic, so the executable can and does enforce this elsewhere.
#
# Exit 0 = PASS (not reproduced), 1 = BUG REPRODUCED, 2 = harness problem.
set -u

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$here/../../.." && pwd)
server="$root/server/bin/flyology_object_storage_server"
assets="$root/server/assets"
scratch=${TMPDIR_REPRO:-/private/tmp/claude-501}

if [ ! -x "$server" ]; then
  echo "harness problem: $server is not built (cd $root/server && alr -n build)" >&2
  exit 2
fi

work=$(mktemp -d "$scratch/repro-server-exe-5-XXXXXX") || exit 2
pids=""
cleanup() {
  for p in $pids; do kill -TERM "$p" 2>/dev/null; wait "$p" 2>/dev/null; done
  rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

failures=0
check() {
  if [ "$1" -eq 0 ]; then echo "  ok: $2"; else echo "  FAILED: $2"; failures=$((failures + 1)); fi
}

launch() {  # backend store credentials log -> echoes the pid
  env -i PATH="$PATH" \
    FLYOLOGY_ADMIN_ASSET_ROOT="$assets" \
    FLYOLOGY_OBJECT_STORAGE_BACKEND="$1" \
    FLYOLOGY_OBJECT_STORAGE_ROOT="$2" \
    FLYOLOGY_ADMIN_CREDENTIALS_FILE="$3" \
    FLYOLOGY_S3_PORT=0 FLYOLOGY_ADMIN_PORT=0 \
    AWS_ACCESS_KEY_ID=REPROKEY AWS_SECRET_ACCESS_KEY=reprosecret \
    "$server" >"$4" 2>&1 &
  echo $!
}

settle() {  # log pid -> 0 when READY, 1 when it exited first
  for _ in $(seq 1 400); do
    grep -q '^READY admin ' "$1" && return 0
    kill -0 "$2" 2>/dev/null || return 1
    sleep 0.05
  done
  return 1
}

# ---- files backend --------------------------------------------------------
fstore="$work/files-root"; mkdir -p "$fstore"
p1=$(launch files "$fstore" "$work/f1.cred" "$work/f1.log"); pids="$pids $p1"
if ! settle "$work/f1.log" "$p1"; then
  echo "harness problem: the first files server did not start" >&2
  cat "$work/f1.log" >&2; exit 2
fi
echo "  -- server 1 owns $fstore:"
grep '^READY' "$work/f1.log" | sed 's/^/       /'
echo "sentinel: transient staging artefact of the live owning process" \
  >"$fstore/tmp/owner-staging.tmp"
echo "  -- placed $fstore/tmp/owner-staging.tmp while server 1 is live"

p2=$(launch files "$fstore" "$work/f2.cred" "$work/f2.log"); pids="$pids $p2"
if settle "$work/f2.log" "$p2"; then f2_started=0; else f2_started=1; fi
echo "  -- server 2 on the same root:"
grep -E '^(READY|object-storage server|raised)' "$work/f2.log" | sed 's/^/       /'
echo "  -- server 2 reached READY: $([ $f2_started -eq 0 ] && echo yes || echo no)"
if [ -f "$fstore/tmp/owner-staging.tmp" ]; then survived=0; else survived=1; fi
echo "  -- server 1's tmp/owner-staging.tmp survived: $([ $survived -eq 0 ] && echo yes || echo no)"
echo "  -- server 1 still alive: $(kill -0 "$p1" 2>/dev/null && echo yes || echo no)"

check "$([ $f2_started -ne 0 ] && echo 0 || echo 1)" \
  "files: a second server is refused a root a live server already owns"
check "$survived" \
  "files: ... or at least leaves the live root's tmp/ contents in place"

kill -TERM $p1 $p2 2>/dev/null; wait $p1 $p2 2>/dev/null; pids=""

# ---- sqlite control -------------------------------------------------------
sstore="$work/sqlite-root"; mkdir -p "$sstore"
q1=$(launch sqlite "$sstore" "$work/s1.cred" "$work/s1.log"); pids="$pids $q1"
if ! settle "$work/s1.log" "$q1"; then
  echo "harness problem: the first sqlite server did not start" >&2
  cat "$work/s1.log" >&2; exit 2
fi
q2=$(launch sqlite "$sstore" "$work/s2.cred" "$work/s2.log"); pids="$pids $q2"
if settle "$work/s2.log" "$q2"; then q2_started=0; else q2_started=1; fi
echo "  -- control, sqlite: second server on the same root:"
grep -E '^(READY|object-storage server startup failed|raised)' "$work/s2.log" \
  | cut -c1-140 | sed 's/^/       /'
check "$([ $q2_started -ne 0 ] && echo 0 || echo 1)" \
  "control: sqlite refuses a second server on a root a live server owns"
check "$(grep -q 'could not acquire exclusive SQLite backend root lock' "$work/s2.log" && echo 0 || echo 1)" \
  "control: the sqlite refusal names the reason"

if [ "$failures" -eq 0 ]; then echo PASS; exit 0; fi
echo "BUG REPRODUCED: $failures failed expectation(s)"
exit 1
