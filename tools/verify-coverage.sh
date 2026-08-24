#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LEDGER=${COVERAGE_LEDGER:-"$PROJECT_DIR/coverage/aws-s3-operations.tsv"}

test -s "$PROJECT_DIR/coverage/corpora.lock.toml"
"$PROJECT_DIR/tools/verify-corpora-lock.sh"
"$PROJECT_DIR/tools/verify-benchmark-plan.sh"
test "$(head -n 1 "$LEDGER")" = $'operation\ttier\tbackend\tclient\tserver\tcorpus'
tail -n +2 "$LEDGER" | cut -f1 | LC_ALL=C sort -c
test "$(tail -n +2 "$LEDGER" | cut -f1 | uniq -d | wc -l | tr -d ' ')" = 0
test "$(tail -n +2 "$LEDGER" | wc -l | tr -d ' ')" = 116

if awk -F '\t' 'NR > 1 && ($2 !~ /^(core|extended)$/ || $3 !~ /^(missing|partial|covered)$/ || $4 !~ /^(missing|partial|covered)$/ || $5 !~ /^(missing|partial|covered)$/ || $6 !~ /^(missing|partial|covered)$/) { exit 1 }' "$LEDGER"; then
  :
else
  echo "invalid coverage state" >&2
  exit 1
fi

# A covered cell must remain tied to operation-specific executable evidence.
# This does not attempt to replace semantic review; it prevents a ledger-only
# promotion from passing CI when the corresponding qualification corpus has no
# trace of that operation. Combined feature suites use the explicit aliases
# below because their Ada test names describe the shared domain rather than one
# REST operation.
evidence_pattern() {
  operation_name=$1
  case "$operation_name" in
    DeleteObjectTagging)
      printf '%s\n' 'Delete_Object_Tags|object.tagging'
      ;;
    DeleteBucketTagging|GetBucketTagging|PutBucketTagging)
      printf '%s\n' 'Bucket_Tags|Bucket_Tagging|bucket tagging'
      ;;
    GetBucketVersioning|PutBucketVersioning)
      printf '%s\n' 'Bucket_Versioning|bucket versioning'
      ;;
    *)
      ada_name=$(printf '%s' "$operation_name" |
        sed -E 's/([a-z0-9])([A-Z])/(\1_\2)/g' |
        tr '[:lower:]' '[:upper:]' | tr -d '()')
      printf '%s|%s\n' "$operation_name" "$ada_name"
      ;;
  esac
}

require_evidence() {
  operation_name=$1
  layer_name=$2
  pattern=$3
  shift 3
  if ! grep -Eirq -- "$pattern" "$@"; then
    echo "covered $layer_name cell lacks test evidence: $operation_name" >&2
    exit 1
  fi
}

tail -n +2 "$LEDGER" |
while IFS=$'\t' read -r operation_name tier_name backend_state \
  client_state server_state corpus_state
do
  pattern=$(evidence_pattern "$operation_name")
  if [ "$backend_state" = covered ]; then
    require_evidence "$operation_name" backend "$pattern" \
      "$PROJECT_DIR/tests/src/object_storage_test_cases.adb" \
      "$PROJECT_DIR/sqlite/tests/src/flyology_object_storage_sqlite_tests.adb"
  fi
  if [ "$client_state" = covered ]; then
    require_evidence "$operation_name" client "$pattern" \
      "$PROJECT_DIR/tests/src/object_storage_test_cases.adb" \
      "$PROJECT_DIR/tests/src/s3_http_socket_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_bucket_controls_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_put_bucket_controls_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_object_legal_hold_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_object_retention_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_object_lock_configuration_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_object_torrent_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_object_torrent_socket_corpus.adb"
  fi
  if [ "$server_state" = covered ]; then
    require_evidence "$operation_name" server "$pattern" \
      "$PROJECT_DIR/tests/src/s3_server_application_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_http_socket_corpus.adb"
  fi
  if [ "$corpus_state" = covered ]; then
    require_evidence "$operation_name" corpus "$pattern" \
      "$PROJECT_DIR/tests/src/s3_implementation_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_delete_bucket_configurations_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_bucket_controls_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_put_bucket_controls_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_object_lock_configuration_corpus.adb" \
      "$PROJECT_DIR/tests/scripts"
  fi
done

echo "coverage ledger: 116 pinned S3 operations"
