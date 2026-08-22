#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
"$PROJECT_DIR/tools/verify-coverage.sh"
cd "$PROJECT_DIR/tests"
alr -n build

SYMLINK_ROOT=$(mktemp -d /tmp/flyology-files-symlink.XXXXXX)
trap 'case "$SYMLINK_ROOT" in /tmp/flyology-files-symlink.*) rm -rf "$SYMLINK_ROOT" ;; esac' EXIT INT TERM
mkdir -p "$SYMLINK_ROOT/root" "$SYMLINK_ROOT/outside"
printf 'outside-sentinel\n' >"$SYMLINK_ROOT/outside/sentinel"
ln -s "$SYMLINK_ROOT/outside" "$SYMLINK_ROOT/root/tmp"
if ./bin/files_open_probe "$SYMLINK_ROOT/root" >/dev/null 2>&1; then
  echo "files backend accepted a symlinked staging directory" >&2
  exit 1
fi
test "$(cat "$SYMLINK_ROOT/outside/sentinel")" = outside-sentinel
rm -rf "$SYMLINK_ROOT"
trap - EXIT INT TERM
echo "files staging symlink rejection: OK"

./bin/flyology_object_storage_tests
./bin/s3_server_application_corpus
for run in 1 2 3
do
  ./bin/s3_http_socket_corpus
  ./bin/s3_transfer_many_corpus
done
