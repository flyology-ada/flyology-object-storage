#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LOCK="$PROJECT_DIR/coverage/corpora.lock.toml"
EXPECTED=$(mktemp)
ACTUAL=$(mktemp)
trap 'rm -f "$EXPECTED" "$ACTUAL"' EXIT

printf '%s\n' \
  botocore-s3-model \
  ceph-s3-tests \
  minio-mint-archive \
  minio-s3-server \
  rustfs-s3-server \
  s3t \
  s5cmd-byte-oracle \
  seaweedfs-s3-server | LC_ALL=C sort >"$EXPECTED"
sed -n 's/^name = "\([^"]*\)"$/\1/p' "$LOCK" | \
  LC_ALL=C sort >"$ACTUAL"
diff -u "$EXPECTED" "$ACTUAL"

awk '
function value(line, result) {
  result = line
  sub(/^[^=]*=[[:space:]]*"/, "", result)
  sub(/"[[:space:]]*$/, "", result)
  return result
}
function fail(message) {
  print "corpora lock: " message > "/dev/stderr"
  failed = 1
}
function finish( digest) {
  if (!active) return
  if (name == "") fail("entry without name")
  if (seen[name]++) fail("duplicate entry " name)
  if (repository !~ /^https:\/\/github.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+(\.git)?$/)
    fail(name " has non-GitHub source")
  if (length(revision) != 40 || revision !~ /^[0-9a-f]+$/)
    fail(name " revision is not a full lowercase Git commit")
  if (license != "Apache-2.0" && license != "MIT" &&
      license != "AGPL-3.0-only")
    fail(name " has an unreviewed license")
  if (purpose == "") fail(name " has no purpose")
  if (image != "") {
    if (image !~ /@sha256:/) fail(name " image is not digest-pinned")
    digest = image
    sub(/^.*@sha256:/, "", digest)
    if (length(digest) != 64 || digest !~ /^[0-9a-f]+$/)
      fail(name " image digest is malformed")
  }
  if (name == "minio-s3-server" && license != "AGPL-3.0-only")
    fail("MinIO license pin changed")
  if ((name == "rustfs-s3-server" || name == "seaweedfs-s3-server") &&
      license != "Apache-2.0")
    fail(name " is no longer permissively licensed")
  if (name == "s5cmd-byte-oracle" && license != "MIT")
    fail("s5cmd is no longer MIT-licensed")
}
/^\[\[corpus\]\]$/ {
  finish()
  active = 1
  name = repository = revision = license = purpose = image = ""
  next
}
/^name = /       { name = value($0); next }
/^repository = / { repository = value($0); next }
/^revision = /   { revision = value($0); next }
/^license = /    { license = value($0); next }
/^purpose = /    { purpose = value($0); next }
/^image = /      { image = value($0); next }
END {
  finish()
  if (failed) exit 1
}
' "$LOCK"

echo "corpora lock: 8 exact revisions, reviewed licenses, immutable images"

S3T_ALLOW="$PROJECT_DIR/coverage/s3t-allow.txt"
test -s "$S3T_ALLOW"
test "$(grep -c '^s3tests/functional/test_s3.py::test_' "$S3T_ALLOW")" = 113
test "$(grep -v '^#' "$S3T_ALLOW" | sed '/^$/d' | sort -u | wc -l | tr -d ' ')" = 113
echo "s3t allowlist: 113 exact ceph-compatible node IDs"

S3T_SEAWEED_FAILURES="$PROJECT_DIR/coverage/s3t-known-failures-seaweedfs.txt"
test "$(grep -c '^s3tests/functional/test_s3.py::test_bucket_delete_nonempty$' "$S3T_SEAWEED_FAILURES")" = 1
test "$(grep -c '^s3tests/functional/test_s3.py::test_object_write_to_nonexist_bucket$' "$S3T_SEAWEED_FAILURES")" = 1
test "$(grep -c '^s3tests/functional/test_s3.py::test_bucket_list_encoding_basic$' "$S3T_SEAWEED_FAILURES")" = 1
test "$(grep -c '^s3tests/functional/test_s3.py::test_bucket_listv2_encoding_basic$' "$S3T_SEAWEED_FAILURES")" = 1
test "$(grep -c '^s3tests/functional/test_s3.py::test_multipart_copy_invalid_range$' "$S3T_SEAWEED_FAILURES")" = 1
test "$(grep -c '^s3tests/functional/test_s3.py::test_multipart_copy_improper_range$' "$S3T_SEAWEED_FAILURES")" = 1
test "$(grep -v '^#' "$S3T_SEAWEED_FAILURES" | sed '/^$/d' | wc -l | tr -d ' ')" = 6

S3T_RUSTFS_FAILURES="$PROJECT_DIR/coverage/s3t-known-failures-rustfs.txt"
test "$(grep -c '^s3tests/functional/test_s3.py::test_multipart_upload_complete_without_create$' "$S3T_RUSTFS_FAILURES")" = 1
test "$(grep -v '^#' "$S3T_RUSTFS_FAILURES" | sed '/^$/d' | wc -l | tr -d ' ')" = 1

S3T_MINIO_FAILURES="$PROJECT_DIR/coverage/s3t-known-failures-minio.txt"
for node in \
  test_multipart_upload_empty \
  test_bucket_list_delimiter_prefix \
  test_bucket_list_delimiter_prefix_underscore \
  test_bucket_list_encoding_basic \
  test_bucket_listv2_continuationtoken_empty \
  test_bucket_listv2_encoding_basic \
  test_multipart_copy_invalid_range
do
  test "$(grep -c "^s3tests/functional/test_s3.py::$node\$" \
    "$S3T_MINIO_FAILURES")" = 1
done
test "$(grep -v '^#' "$S3T_MINIO_FAILURES" | sed '/^$/d' | wc -l | tr -d ' ')" = 7
