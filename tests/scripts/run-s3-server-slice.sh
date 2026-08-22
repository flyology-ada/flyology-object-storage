#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "usage: $0 ORACLE_ENDPOINT BUCKET ACCESS_KEY SECRET_KEY" >&2
  exit 2
fi

S5CMD_IMAGE="docker.io/peakcom/s5cmd@sha256:2ff939e2ee3c76adcadd78dbfc3e2569b18a3743ed9dcfccb1ec589af7fb9903"
ORACLE_ENDPOINT=$1
BUCKET=$2
ACCESS_KEY=$3
SECRET_KEY=$4
PAYLOAD_ROOT=$(mktemp -d /tmp/flyology-s3-slice.XXXXXX)

cleanup() {
  case "$PAYLOAD_ROOT" in
    /tmp/flyology-s3-slice.*) rm -rf "$PAYLOAD_ROOT" ;;
    *) echo "refusing unexpected payload cleanup path" >&2 ;;
  esac
}
trap cleanup EXIT INT TERM

command -v docker >/dev/null
docker pull "$S5CMD_IMAGE" >/dev/null
S5CMD_VERSION=$(docker run --rm "$S5CMD_IMAGE" version)
case "$S5CMD_VERSION" in
  v2.3.0-991c9fb*) ;;
  *) echo "unexpected s5cmd image provenance" >&2; exit 1 ;;
esac

if command -v sha256sum >/dev/null 2>&1; then
  hash_file() { sha256sum "$1" | awk '{print $1}'; }
  hash_stream() { sha256sum | awk '{print $1}'; }
elif command -v shasum >/dev/null 2>&1; then
  hash_file() { shasum -a 256 "$1" | awk '{print $1}'; }
  hash_stream() { shasum -a 256 | awk '{print $1}'; }
else
  echo "neither sha256sum nor shasum is available" >&2
  exit 1
fi

: >"$PAYLOAD_ROOT/empty.bin"
perl -e 'for ($i = 0; $i < 4096; $i++) { print chr(($i * 131 + 17) % 251) }' \
  >"$PAYLOAD_ROOT/small.bin"
perl -e 'for ($i = 0; $i < 2097152; $i++) { print chr(($i * 131 + 17) % 251) }' \
  >"$PAYLOAD_ROOT/large.bin"
perl -e 'for ($i = 0; $i < 6291456; $i++) { print chr(($i * 193 + 29) % 251) }' \
  >"$PAYLOAD_ROOT/multipart.bin"
test "$(wc -c <"$PAYLOAD_ROOT/empty.bin" | tr -d ' ')" = 0
test "$(wc -c <"$PAYLOAD_ROOT/small.bin" | tr -d ' ')" = 4096
test "$(wc -c <"$PAYLOAD_ROOT/large.bin" | tr -d ' ')" = 2097152
test "$(wc -c <"$PAYLOAD_ROOT/multipart.bin" | tr -d ' ')" = 6291456
SMALL_HASH=$(hash_file "$PAYLOAD_ROOT/small.bin")
LARGE_HASH=$(hash_file "$PAYLOAD_ROOT/large.bin")
EMPTY_HASH=$(hash_file "$PAYLOAD_ROOT/empty.bin")
MULTIPART_HASH=$(hash_file "$PAYLOAD_ROOT/multipart.bin")

s5cmd() {
  docker run --rm --add-host host.docker.internal:host-gateway \
    --volume "$PAYLOAD_ROOT:/data:ro" \
    --env "AWS_ACCESS_KEY_ID=$ACCESS_KEY" \
    --env "AWS_SECRET_ACCESS_KEY=$SECRET_KEY" \
    --env AWS_REGION=us-east-1 \
    "$S5CMD_IMAGE" --retry-count 0 --endpoint-url "$ORACLE_ENDPOINT" "$@"
}

s5cmd mb "s3://$BUCKET"
BUCKET_LIST=$(s5cmd ls)
case "$BUCKET_LIST" in
  *"$BUCKET"*) ;;
  *) echo "ListBuckets did not return the created bucket" >&2; exit 1 ;;
esac
s5cmd cp /data/empty.bin "s3://$BUCKET/empty.bin"
s5cmd cp /data/small.bin "s3://$BUCKET/small.bin"
s5cmd cp /data/large.bin "s3://$BUCKET/large.bin"
s5cmd cp --part-size 5 /data/multipart.bin "s3://$BUCKET/multipart.bin"
s5cmd cp /data/small.bin "s3://$BUCKET/nested/space + plus-%25.bin"
s5cmd cp /data/small.bin "s3://$BUCKET/overwrite.bin"
s5cmd cp /data/large.bin "s3://$BUCKET/overwrite.bin"
s5cmd cp /data/small.bin "s3://$BUCKET/delete-objects-probe.bin"
s5cmd head "s3://$BUCKET/empty.bin" >/dev/null
s5cmd head "s3://$BUCKET/small.bin" >/dev/null
s5cmd head "s3://$BUCKET/large.bin" >/dev/null
s5cmd head "s3://$BUCKET/multipart.bin" >/dev/null
s5cmd head "s3://$BUCKET/nested/space + plus-%25.bin" >/dev/null
s5cmd head "s3://$BUCKET/overwrite.bin" >/dev/null
s5cmd head "s3://$BUCKET/delete-objects-probe.bin" >/dev/null

OBSERVED_EMPTY=$(s5cmd cat "s3://$BUCKET/empty.bin" | hash_stream)
OBSERVED_SMALL=$(s5cmd cat "s3://$BUCKET/small.bin" | hash_stream)
OBSERVED_LARGE=$(s5cmd cat "s3://$BUCKET/large.bin" | hash_stream)
OBSERVED_MULTIPART=$(s5cmd cat "s3://$BUCKET/multipart.bin" | hash_stream)
OBSERVED_TRICKY=$(s5cmd cat \
  "s3://$BUCKET/nested/space + plus-%25.bin" | hash_stream)
OBSERVED_OVERWRITE=$(s5cmd cat "s3://$BUCKET/overwrite.bin" | hash_stream)
test "$OBSERVED_EMPTY" = "$EMPTY_HASH"
test "$OBSERVED_SMALL" = "$SMALL_HASH"
test "$OBSERVED_LARGE" = "$LARGE_HASH"
test "$OBSERVED_MULTIPART" = "$MULTIPART_HASH"
test "$OBSERVED_TRICKY" = "$SMALL_HASH"
test "$OBSERVED_OVERWRITE" = "$LARGE_HASH"

#  s5cmd's rm operation uses POST ?delete= even for one explicit key. This
#  keeps DeleteObjects in the independent cross-server wire slice without
#  disturbing the objects consumed by the Ada client corpus that follows.
s5cmd rm "s3://$BUCKET/delete-objects-probe.bin"
if s5cmd head "s3://$BUCKET/delete-objects-probe.bin" >/dev/null 2>&1
then
  echo "DeleteObjects left its probe object visible" >&2
  exit 1
fi

if docker run --rm --add-host host.docker.internal:host-gateway \
  --env "AWS_ACCESS_KEY_ID=$ACCESS_KEY" \
  --env AWS_SECRET_ACCESS_KEY=deliberately-wrong-secret \
  --env AWS_REGION=us-east-1 \
  "$S5CMD_IMAGE" --retry-count 0 --endpoint-url "$ORACLE_ENDPOINT" \
  head "s3://$BUCKET/small.bin" >/dev/null 2>&1
then
  echo "server accepted an invalid S3 signature" >&2
  exit 1
fi

if docker run --rm --add-host host.docker.internal:host-gateway \
  --env AWS_ACCESS_KEY_ID=DELIBERATELYWRONG \
  --env "AWS_SECRET_ACCESS_KEY=$SECRET_KEY" \
  --env AWS_REGION=us-east-1 \
  "$S5CMD_IMAGE" --retry-count 0 --endpoint-url "$ORACLE_ENDPOINT" \
  head "s3://$BUCKET/small.bin" >/dev/null 2>&1
then
  echo "server accepted an unknown S3 access key" >&2
  exit 1
fi

if docker run --rm --add-host host.docker.internal:host-gateway \
  --env "AWS_ACCESS_KEY_ID=$ACCESS_KEY" \
  --env "AWS_SECRET_ACCESS_KEY=$SECRET_KEY" \
  --env AWS_SESSION_TOKEN=unexpected-session-token \
  --env AWS_REGION=us-east-1 \
  "$S5CMD_IMAGE" --retry-count 0 --endpoint-url "$ORACLE_ENDPOINT" \
  head "s3://$BUCKET/small.bin" >/dev/null 2>&1
then
  echo "server accepted an unexpected S3 session token" >&2
  exit 1
fi

echo "independent s5cmd server slice: OK"
