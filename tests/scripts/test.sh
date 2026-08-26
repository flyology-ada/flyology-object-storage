#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
"$PROJECT_DIR/tools/verify-coverage.sh"
"$PROJECT_DIR/tools/test-coverage-verifier.sh"
"$PROJECT_DIR/tools/verify-composable-client-fixtures.sh"
"$PROJECT_DIR/tools/test-composable-client-fixtures-verifier.sh"
python3 "$PROJECT_DIR/tools/verify-create-session-preparation.py"
python3 "$PROJECT_DIR/tools/verify-list-object-versions-preparation.py"
python3 "$PROJECT_DIR/tools/verify-delete-bucket-cors-preparation.py"
python3 "$PROJECT_DIR/tools/verify-delete-bucket-configurations-preparation.py"
python3 "$PROJECT_DIR/tools/verify-get-bucket-controls-preparation.py"
python3 "$PROJECT_DIR/tools/verify-put-bucket-controls-preparation.py"
python3 "$PROJECT_DIR/tools/verify-put-bucket-ownership-controls-preparation.py"
python3 "$PROJECT_DIR/tools/verify-put-bucket-encryption-preparation.py"
python3 "$PROJECT_DIR/tools/verify-create-bucket-metadata-table-configuration-preparation.py"
python3 "$PROJECT_DIR/tools/verify-delete-object-annotation-preparation.py"
python3 "$PROJECT_DIR/tools/verify-put-object-legal-hold-preparation.py"
python3 "$PROJECT_DIR/tools/verify-put-object-retention-preparation.py"
python3 "$PROJECT_DIR/tools/verify-put-object-lock-configuration-preparation.py"
python3 "$PROJECT_DIR/tools/verify-get-object-torrent-preparation.py"
python3 "$PROJECT_DIR/tools/verify-get-object-legal-hold-preparation.py"
python3 "$PROJECT_DIR/tools/verify-get-object-retention-preparation.py"
python3 "$PROJECT_DIR/tools/verify-get-object-lock-configuration-preparation.py"
python3 "$PROJECT_DIR/tools/verify-get-bucket-ownership-controls-preparation.py"
python3 "$PROJECT_DIR/tools/verify-get-bucket-cors-preparation.py"
python3 "$PROJECT_DIR/tools/verify-get-bucket-encryption-preparation.py"
python3 "$PROJECT_DIR/tools/verify-get-bucket-metadata-table-configuration-preparation.py"
python3 "$PROJECT_DIR/tools/verify-get-bucket-acl-preparation.py"
python3 "$PROJECT_DIR/tools/verify-get-object-acl-preparation.py"
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

check_tag_delete_symlink() {
  path_kind=$1
  target_state=$2
  case_root="$SYMLINK_ROOT/$path_kind-$target_state/root"
  outside="$SYMLINK_ROOT/$path_kind-$target_state/outside"
  ./bin/files_open_probe prepare-bucket-tags "$case_root"
  bucket_path="$case_root/buckets/probe-bucket"
  configuration_path="$bucket_path/configuration"
  tags_path="$configuration_path/tags.fos"
  external_target="$outside/target"
  mkdir -p "$outside"
  case "$path_kind" in
    bucket)
      internal_path=$bucket_path
      rm -rf "$internal_path"
      if [ "$target_state" = live ]; then
        mkdir -p "$external_target"
        printf 'outside-sentinel\n' >"$external_target/sentinel"
      fi
      ;;
    configuration)
      internal_path=$configuration_path
      rm -rf "$internal_path"
      if [ "$target_state" = live ]; then
        mkdir -p "$external_target"
        printf 'outside-sentinel\n' >"$external_target/sentinel"
      fi
      ;;
    tags)
      internal_path=$tags_path
      rm -f "$internal_path"
      if [ "$target_state" = live ]; then
        printf 'outside-sentinel\n' >"$external_target"
      fi
      ;;
    *) echo "unknown tag deletion symlink kind" >&2; exit 2 ;;
  esac
  ln -s "$external_target" "$internal_path"
  ./bin/files_open_probe delete-must-fail "$case_root"
  test -L "$internal_path"
  if [ "$target_state" = live ]; then
    if [ "$path_kind" = tags ]; then
      test "$(cat "$external_target")" = outside-sentinel
    else
      test "$(cat "$external_target/sentinel")" = outside-sentinel
    fi
  else
    test ! -e "$external_target"
  fi
}

for path_kind in bucket configuration tags
do
  check_tag_delete_symlink "$path_kind" live
  check_tag_delete_symlink "$path_kind" dangling
done
rm -rf "$SYMLINK_ROOT"
trap - EXIT INT TERM
echo "files staging and bucket-tag deletion symlink rejection: OK"

CONDITIONAL_LINK_ROOT=$(mktemp -d /tmp/flyology-files-conditional-link.XXXXXX)
trap 'case "$CONDITIONAL_LINK_ROOT" in /tmp/flyology-files-conditional-link.*) rm -rf "$CONDITIONAL_LINK_ROOT" ;; esac' EXIT INT TERM
./bin/files_conditional_symlink_probe "$CONDITIONAL_LINK_ROOT/live" live
./bin/files_conditional_symlink_probe "$CONDITIONAL_LINK_ROOT/dangling" dangling
rm -rf "$CONDITIONAL_LINK_ROOT"
trap - EXIT INT TERM
echo "files conditional put/delete object-path symlink rejection: live/dangling OK"

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
run_crash_cases versioned-put 3
run_crash_cases versioned-delete-marker 3
run_crash_cases suspended-put 4
run_crash_cases suspended-delete-marker 4
run_crash_cases suspended-exact-delete 5
run_crash_cases object-tags 3
run_crash_cases bucket-tags 3
run_crash_cases bucket-tag-delete 1
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
echo "files abrupt-crash matrix: 126 pre/post-barrier cases including retained generations OK"

./bin/flyology_object_storage_tests
./bin/s3_bucket_tagging_benchmark --self-test
./bin/s3_checksum_corpus
./bin/s3_server_application_corpus
for run in 1 2 3
do
  ./bin/s3_list_object_versions_corpus
  ./bin/s3_delete_bucket_cors_corpus
  ./bin/s3_delete_bucket_configurations_corpus
  ./bin/s3_get_bucket_controls_corpus
  ./bin/s3_put_bucket_controls_corpus
  ./bin/s3_put_bucket_ownership_controls_corpus
  ./bin/s3_create_bucket_metadata_table_configuration_corpus
  ./bin/s3_delete_object_annotation_corpus
  ./bin/s3_put_object_legal_hold_corpus
  ./bin/s3_put_object_retention_corpus
  ./bin/s3_put_object_lock_configuration_corpus
  ./bin/s3_get_object_torrent_corpus
  ./bin/s3_get_object_torrent_socket_corpus
  ./bin/s3_get_object_legal_hold_corpus
  ./bin/s3_get_object_retention_corpus
  ./bin/s3_get_object_lock_configuration_corpus
  ./bin/s3_get_bucket_ownership_controls_corpus
  ./bin/s3_get_bucket_cors_corpus
  ./bin/s3_get_bucket_encryption_corpus
  ./bin/s3_get_bucket_metadata_table_configuration_corpus
  ./bin/s3_get_bucket_acl_corpus
  ./bin/s3_get_object_acl_corpus
  ./bin/s3_http_socket_corpus
  ./bin/s3_create_session_tls_corpus
  ./bin/s3_transfer_many_corpus
done
