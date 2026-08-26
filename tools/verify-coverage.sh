#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LEDGER=${COVERAGE_LEDGER:-"$PROJECT_DIR/coverage/aws-s3-operations.tsv"}

uv run --python 3.13 -- "$PROJECT_DIR/tools/s3-operation.py" generate --check
uv run --python 3.13 -- "$PROJECT_DIR/tools/test-s3-operation-registry.py"
if [ "$LEDGER" != "$PROJECT_DIR/coverage/aws-s3-operations.tsv" ] &&
  ! cmp -s "$LEDGER" "$PROJECT_DIR/coverage/aws-s3-operations.tsv"
then
  echo "coverage ledger differs from reviewed evidence registry" >&2
  exit 1
fi
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

# Retained independent oracle while the generated registry evidence gate is
# qualified against the complete repository suite.
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
    DeletePublicAccessBlock|GetPublicAccessBlock|PutPublicAccessBlock)
      printf '%s\n' 'PublicAccessBlock|Public_Access_Block|public access block'
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
      "$PROJECT_DIR/tests/src/s3_list_object_versions_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_delete_bucket_cors_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_delete_bucket_configurations_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_bucket_controls_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_put_bucket_controls_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_object_legal_hold_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_object_retention_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_object_lock_configuration_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_bucket_ownership_controls_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_bucket_encryption_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_bucket_cors_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_bucket_lifecycle_configuration_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_put_bucket_lifecycle_configuration_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_bucket_notification_configuration_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_create_bucket_metadata_table_configuration_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_delete_object_annotation_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_put_object_legal_hold_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_put_object_retention_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_put_object_lock_configuration_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_object_legal_hold_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_object_retention_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_object_torrent_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_object_torrent_socket_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_bucket_replication_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_put_bucket_replication_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_bucket_metadata_table_configuration_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_bucket_acl_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_object_acl_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_create_session_tls_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_transfer_many_corpus.adb"
  fi
  if [ "$server_state" = covered ]; then
    require_evidence "$operation_name" server "$pattern" \
      "$PROJECT_DIR/tests/src/s3_server_application_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_http_socket_corpus.adb"
  fi
  if [ "$corpus_state" = covered ]; then
    require_evidence "$operation_name" corpus "$pattern" \
      "$PROJECT_DIR/tests/src/s3_implementation_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_list_object_versions_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_delete_bucket_cors_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_delete_bucket_configurations_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_bucket_controls_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_put_bucket_controls_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_put_bucket_ownership_controls_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_object_lock_configuration_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_bucket_ownership_controls_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_bucket_encryption_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_bucket_cors_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_bucket_lifecycle_configuration_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_put_bucket_lifecycle_configuration_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_bucket_notification_configuration_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_create_bucket_metadata_table_configuration_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_delete_object_annotation_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_put_object_legal_hold_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_put_object_retention_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_put_object_lock_configuration_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_object_legal_hold_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_object_retention_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_object_torrent_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_object_torrent_socket_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_bucket_replication_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_put_bucket_replication_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_bucket_metadata_table_configuration_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_bucket_acl_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_get_object_acl_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_create_session_tls_corpus.adb" \
      "$PROJECT_DIR/tests/src/s3_transfer_many_corpus.adb" \
      "$PROJECT_DIR/tests/scripts"
  fi
done

echo "coverage ledger: 116 pinned S3 operations"
