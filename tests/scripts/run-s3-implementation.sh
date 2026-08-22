#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 6 ]; then
  echo "usage: $0 HOST_ENDPOINT ORACLE_ENDPOINT BUCKET ACCESS_KEY SECRET_KEY CREATE_BUCKET" >&2
  exit 2
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
S5CMD_IMAGE="docker.io/peakcom/s5cmd@sha256:2ff939e2ee3c76adcadd78dbfc3e2569b18a3743ed9dcfccb1ec589af7fb9903"
EXPECTED_SHA256="4fb7be0b60c43f987190544222ed17a4c4e9ffb635199477f9a449ec64c11141"
HOST_ENDPOINT=$1
ORACLE_ENDPOINT=$2
BUCKET=$3
ACCESS_KEY=$4
SECRET_KEY=$5
CREATE_BUCKET=$6

command -v docker >/dev/null
docker pull "$S5CMD_IMAGE"
S5CMD_VERSION=$(docker run --rm "$S5CMD_IMAGE" version)
case "$S5CMD_VERSION" in
  v2.3.0-991c9fb*) ;;
  *) echo "unexpected s5cmd image provenance" >&2; exit 1 ;;
esac

s5cmd() {
  docker run --rm --add-host host.docker.internal:host-gateway \
    --env "AWS_ACCESS_KEY_ID=$ACCESS_KEY" \
    --env "AWS_SECRET_ACCESS_KEY=$SECRET_KEY" \
    --env AWS_REGION=us-east-1 \
    "$S5CMD_IMAGE" --endpoint-url "$ORACLE_ENDPOINT" "$@"
}

cd "$PROJECT_DIR/tests"
alr -n build
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
case "$CREATE_BUCKET" in
  yes)
    ./bin/s3_implementation_corpus \
      "$HOST_ENDPOINT" "$BUCKET" "$TIMESTAMP" setup
    s5cmd ls "s3://$BUCKET/" >/dev/null
    ;;
  no) s5cmd ls "s3://$BUCKET/" >/dev/null ;;
  *) echo "CREATE_BUCKET must be yes or no" >&2; exit 2 ;;
esac

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
./bin/s3_implementation_corpus "$HOST_ENDPOINT" "$BUCKET" "$TIMESTAMP"

for KEY in \
  native-object \
  lightweight-object \
  "native-object-high level+%25" \
  "lightweight-object-high level+%25"
do
  OBSERVED_SHA256=$(s5cmd cat "s3://$BUCKET/$KEY" | \
    shasum -a 256 | cut -d ' ' -f 1)
  test "$OBSERVED_SHA256" = "$EXPECTED_SHA256"
done

echo "independent s5cmd byte oracle: OK"
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
./bin/s3_implementation_corpus \
  "$HOST_ENDPOINT" "$BUCKET" "$TIMESTAMP" cleanup
if s5cmd ls "s3://$BUCKET/" >/dev/null 2>&1; then
  echo "S3 implementation cleanup left the bucket visible" >&2
  exit 1
fi
echo "independent s5cmd deletion oracle: OK"
