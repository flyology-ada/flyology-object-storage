#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
"$PROJECT_DIR/tools/verify-coverage.sh"
"$PROJECT_DIR/tools/test-coverage-verifier.sh"
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

CONDITIONAL_LINK_ROOT=$(mktemp -d /tmp/flyology-files-conditional-link.XXXXXX)
trap 'case "$CONDITIONAL_LINK_ROOT" in /tmp/flyology-files-conditional-link.*) rm -rf "$CONDITIONAL_LINK_ROOT" ;; esac' EXIT INT TERM
./bin/files_conditional_symlink_probe "$CONDITIONAL_LINK_ROOT/live" live
./bin/files_conditional_symlink_probe "$CONDITIONAL_LINK_ROOT/dangling" dangling
rm -rf "$CONDITIONAL_LINK_ROOT"
trap - EXIT INT TERM
echo "files conditional object-path symlink rejection: live/dangling OK"

CRASH_ROOT=$(mktemp -d /tmp/flyology-files-crash.XXXXXX)
trap 'case "$CRASH_ROOT" in /tmp/flyology-files-crash.*) rm -rf "$CRASH_ROOT" ;; esac' EXIT INT TERM
run_crash_cases() {
  scenario=$1
  barriers=$2
  for phase in before after; do
    point=0
    while [ "$point" -lt "$barriers" ]; do
      root="$CRASH_ROOT/$scenario-$phase-$point"
      ./bin/files_crash_probe prepare "$scenario" "$root"
      status=$(
        (
          set +e
          ./bin/files_crash_probe crash \
            "$scenario" "$root" "$point" "$phase" >/dev/null 2>&1
          printf '%s\n' "$?"
        ) 2>/dev/null
      )
      if [ "$status" -ne 137 ]; then
        echo "$scenario $phase barrier $point did not terminate abruptly (status $status)" >&2
        exit 1
      fi
      ./bin/files_crash_probe verify "$scenario" "$root"
      point=$((point + 1))
    done
  done
}
run_crash_cases bucket 10
run_crash_cases put 3
run_crash_cases conditional-put 3
run_crash_cases object-tags 3
run_crash_cases bucket-tags 3
run_crash_cases delete 1
run_crash_cases delete-objects 2
run_crash_cases initiate 6
run_crash_cases part 3
run_crash_cases abort 1
run_crash_cases delete-bucket 1
run_crash_cases complete 4
run_crash_cases versioning 3
rm -rf "$CRASH_ROOT"
trap - EXIT INT TERM
echo "files abrupt-crash matrix: 86 pre/post-barrier cases OK"

./bin/flyology_object_storage_tests
./bin/s3_checksum_corpus
./bin/s3_server_application_corpus
for run in 1 2 3
do
  ./bin/s3_http_socket_corpus
  ./bin/s3_transfer_many_corpus
done
