#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SERVER_IMAGE="docker.io/chrislusf/seaweedfs@sha256:7bea581f48155c069d3c725e60c386c88210c67cde8bce412344ff6ebea264da"
ACCESS_KEY="FLYOLOGYS3ORACLE"
SECRET_KEY="flyology-s3-oracle-secret-key-tests"
CONTAINER="flyology-object-storage-seaweedfs-$$"
BUCKET="flyology-seaweedfs-corpus-$$"
EXPECTED_REVISION="6c7f184381e3c4f7908934f4c1d8cb7dcca41894"

cleanup() {
  if docker inspect "$CONTAINER" >/dev/null 2>&1; then
    docker stop --timeout 5 "$CONTAINER" >/dev/null
  fi
}
trap cleanup EXIT INT TERM

command -v docker >/dev/null
docker pull "$SERVER_IMAGE"
SERVER_REVISION=$(docker image inspect "$SERVER_IMAGE" \
  --format '{{index .Config.Labels "org.opencontainers.image.revision"}}')
SERVER_LICENSE=$(docker image inspect "$SERVER_IMAGE" \
  --format '{{index .Config.Labels "org.opencontainers.image.licenses"}}')
test "$SERVER_REVISION" = "$EXPECTED_REVISION"
test "$SERVER_LICENSE" = "Apache-2.0"
SERVER_VERSION=$(docker run --rm --entrypoint /usr/bin/weed \
  "$SERVER_IMAGE" version)
case "$SERVER_VERSION" in
  *4.43*6c7f18438*) ;;
  *) echo "unexpected SeaweedFS image provenance" >&2; exit 1 ;;
esac
docker run --detach --rm --name "$CONTAINER" \
  --publish "127.0.0.1::8333" \
  --env "AWS_ACCESS_KEY_ID=$ACCESS_KEY" \
  --env "AWS_SECRET_ACCESS_KEY=$SECRET_KEY" \
  "$SERVER_IMAGE" >/dev/null

PORT=""
for attempt in $(seq 1 240)
do
  MAPPING=$(docker port "$CONTAINER" 8333/tcp 2>/dev/null || true)
  if [ -n "$MAPPING" ]; then
    PORT=${MAPPING##*:}
  fi
  if [ -n "$PORT" ] && curl -sS \
    "http://127.0.0.1:$PORT/" >/dev/null 2>&1
  then
    break
  fi
  if [ "$attempt" -eq 240 ]; then
    docker logs "$CONTAINER" >&2
    echo "SeaweedFS did not become healthy" >&2
    exit 1
  fi
  sleep 0.25
done

if [ -n "${FLYOLOGY_S3_SERVER_RUNNER:-}" ]; then
  FLYOLOGY_S3_IMPLEMENTATION=seaweedfs \
  FLYOLOGY_S3_SERVER_REVISION="$SERVER_IMAGE" "$FLYOLOGY_S3_SERVER_RUNNER" \
    "http://host.docker.internal:$PORT" \
    "$BUCKET" "$ACCESS_KEY" "$SECRET_KEY"
  echo "SeaweedFS endpoint runner: OK"
  exit 0
fi

"$SCRIPT_DIR/run-s3-server-slice.sh" \
  "http://host.docker.internal:$PORT" \
  "$BUCKET-slice" "$ACCESS_KEY" "$SECRET_KEY"

FLYOLOGY_LIST_MULTIPART_UPLOADS_ORACLE_MODE=\
seaweedfs-4.43-invalid-pagination \
"$SCRIPT_DIR/run-s3-implementation.sh" \
  "http://127.0.0.1:$PORT" \
  "http://host.docker.internal:$PORT" \
  "$BUCKET" "$ACCESS_KEY" "$SECRET_KEY" yes
echo "SeaweedFS ListMultipartUploads oracle: skipped, pinned response has" \
  "invalid truncation markers and omits initiation metadata"

if [ -n "${FLYOLOGY_S3T_BIN:-}" ]; then
  FLYOLOGY_S3_IMPLEMENTATION=seaweedfs \
    "$SCRIPT_DIR/run-s3t-corpus.sh" "http://127.0.0.1:$PORT" \
    "$ACCESS_KEY" "$SECRET_KEY"
fi

echo "SeaweedFS second permissive target: OK"
