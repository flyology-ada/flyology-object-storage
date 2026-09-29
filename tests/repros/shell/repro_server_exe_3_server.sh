#!/usr/bin/env bash
# SERVER-EXE-3, through the executable's documented configuration surface.
#
# tests/repros/src/repro_server_exe_3.adb shows the mechanism at the files
# backend.  This program shows that the mechanism is reachable from the one
# documented variable FLYOLOGY_OBJECT_STORAGE_ROOT (server/README.md:64), for
# both backends that use a root:
#   * flyology_object_storage_server_configuration.adb:41-45 checks only that
#     the value is non-empty;
#   * flyology_object_storage_server.adb:63-68 / :75-82 pass it straight to
#     Files.Open / SQLite.Open;
#   * files.adb:3548-3564 Delete_Tree's a pre-existing <root>/tmp, and
#     sqlite.adb:303-305 Clean_Directory's <root>/staging and every
#     unreferenced ordinary file under <root>/objects.
#
# Correct behaviour asserted: starting the server against a directory that is
# plainly not a store either refuses to start or leaves that directory's
# existing content in place.
# Control: a sibling directory the store never uses (<root>/notes/) survives,
# so the harness is observing the filesystem correctly.
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

work=$(mktemp -d "$scratch/repro-server-exe-3-XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT HUP INT TERM

failures=0
check() {
  if [ "$1" -eq 0 ]; then echo "  ok: $2"; else echo "  FAILED: $2"; failures=$((failures + 1)); fi
}

start_and_stop() {
  backend=$1; store=$2; log="$work/$backend.log"
  env -i PATH="$PATH" \
    FLYOLOGY_ADMIN_ASSET_ROOT="$assets" \
    FLYOLOGY_OBJECT_STORAGE_BACKEND="$backend" \
    FLYOLOGY_OBJECT_STORAGE_ROOT="$store" \
    FLYOLOGY_ADMIN_CREDENTIALS_FILE="$work/$backend-admin.credentials" \
    FLYOLOGY_S3_PORT=0 FLYOLOGY_ADMIN_PORT=0 \
    AWS_ACCESS_KEY_ID=REPROKEY AWS_SECRET_ACCESS_KEY=reprosecret \
    "$server" >"$log" 2>&1 &
  pid=$!
  started=1
  for _ in $(seq 1 400); do
    if grep -q '^READY admin ' "$log"; then started=0; break; fi
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.05
  done
  if [ $started -eq 0 ]; then
    kill -TERM "$pid" 2>/dev/null
  fi
  wait "$pid" 2>/dev/null
  return $started
}

# ---- files backend --------------------------------------------------------
files_root="$work/files-root"
mkdir -p "$files_root/tmp/nested" "$files_root/notes"
echo "keep-me: unrelated operator data" >"$files_root/tmp/keep.txt"
echo "keep-me: one level down" >"$files_root/tmp/nested/deep.txt"
echo "unrelated notes" >"$files_root/notes/readme.txt"
echo "  -- files root $files_root before:"
(cd "$files_root" && find . -type f | sort | sed 's/^/       /')
if start_and_stop files "$files_root"; then
  files_started=0
  echo "  -- files server reached READY:"
else
  files_started=1
  echo "  -- files server did NOT reach READY:"
fi
grep -E '^(READY|object-storage server)' "$work/files.log" | sed 's/^/       /'
echo "  -- files root after:"
(cd "$files_root" && find . -type f | sort | sed 's/^/       /')

check "$([ $files_started -ne 0 ] || [ -f "$files_root/tmp/keep.txt" ] && echo 0 || echo 1)" \
  "files: the server refuses a root that is not a store, or leaves tmp/keep.txt in place"
check "$([ $files_started -ne 0 ] || [ -f "$files_root/tmp/nested/deep.txt" ] && echo 0 || echo 1)" \
  "files: ... and leaves tmp/nested/deep.txt in place"
check "$([ -f "$files_root/notes/readme.txt" ] && echo 0 || echo 1)" \
  "control: files: a sibling directory the store does not use survives"

# ---- sqlite backend -------------------------------------------------------
sqlite_root="$work/sqlite-root"
mkdir -p "$sqlite_root/objects" "$sqlite_root/staging" "$sqlite_root/notes"
echo "keep-me: unrelated operator data" >"$sqlite_root/objects/keep.txt"
echo "keep-me: unrelated operator data" >"$sqlite_root/staging/keep.txt"
echo "unrelated notes" >"$sqlite_root/notes/readme.txt"
echo "  -- sqlite root $sqlite_root before:"
(cd "$sqlite_root" && find . -type f | sort | sed 's/^/       /')
if start_and_stop sqlite "$sqlite_root"; then
  sqlite_started=0
  echo "  -- sqlite server reached READY:"
else
  sqlite_started=1
  echo "  -- sqlite server did NOT reach READY:"
fi
grep -E '^(READY|object-storage server)' "$work/sqlite.log" | sed 's/^/       /'
echo "  -- sqlite root after:"
(cd "$sqlite_root" && find . -type f | sort | sed 's/^/       /')

check "$([ $sqlite_started -ne 0 ] || [ -f "$sqlite_root/objects/keep.txt" ] && echo 0 || echo 1)" \
  "sqlite: the server refuses a root that is not a store, or leaves objects/keep.txt in place"
check "$([ $sqlite_started -ne 0 ] || [ -f "$sqlite_root/staging/keep.txt" ] && echo 0 || echo 1)" \
  "sqlite: ... and leaves staging/keep.txt in place"
check "$([ -f "$sqlite_root/notes/readme.txt" ] && echo 0 || echo 1)" \
  "control: sqlite: a sibling directory the store does not use survives"

if [ "$failures" -eq 0 ]; then echo PASS; exit 0; fi
echo "BUG REPRODUCED: $failures failed expectation(s)"
exit 1
