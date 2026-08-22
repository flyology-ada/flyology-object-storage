#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SERVER_IMAGE="quay.io/minio/minio@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e"
ACCESS_KEY="FLYOLOGYS3ORACLE"
SECRET_KEY="flyology-s3-oracle-secret-key-tests"
CONTAINER="flyology-object-storage-minio-$$"
BUCKET="flyology-corpus-$$"

cleanup() {
  if docker inspect "$CONTAINER" >/dev/null 2>&1; then
    docker stop --timeout 5 "$CONTAINER" >/dev/null
  fi
}
trap cleanup EXIT INT TERM

command -v docker >/dev/null
docker pull "$SERVER_IMAGE"
SERVER_VERSION=$(docker run --rm "$SERVER_IMAGE" --version)
case "$SERVER_VERSION" in
  *RELEASE.2025-09-07T16-13-09Z*07c3a429bfed433e49018cb0f78a52145d4bedeb*) ;;
  *) echo "unexpected MinIO server image provenance" >&2; exit 1 ;;
esac
docker run --detach --rm --name "$CONTAINER" \
  --publish "127.0.0.1::9000" \
  --env "MINIO_ROOT_USER=$ACCESS_KEY" \
  --env "MINIO_ROOT_PASSWORD=$SECRET_KEY" \
  "$SERVER_IMAGE" server /data --address :9000 >/dev/null

PORT=""
for attempt in $(seq 1 120)
do
  MAPPING=$(docker port "$CONTAINER" 9000/tcp 2>/dev/null || true)
  if [ -n "$MAPPING" ]; then
    PORT=${MAPPING##*:}
  fi
  if [ -n "$PORT" ] && curl -fsS \
    "http://127.0.0.1:$PORT/minio/health/live" >/dev/null 2>&1
  then
    break
  fi
  if [ "$attempt" -eq 120 ]; then
    docker logs "$CONTAINER" >&2
    echo "MinIO did not become healthy" >&2
    exit 1
  fi
  sleep 0.25
done

if [ -n "${FLYOLOGY_S3_SERVER_RUNNER:-}" ]; then
  FLYOLOGY_S3_IMPLEMENTATION=minio \
  FLYOLOGY_S3_SERVER_REVISION="$SERVER_IMAGE" "$FLYOLOGY_S3_SERVER_RUNNER" \
    "http://host.docker.internal:$PORT" \
    "$BUCKET" "$ACCESS_KEY" "$SECRET_KEY"
  echo "MinIO endpoint runner: OK"
  exit 0
fi

"$SCRIPT_DIR/run-s3-server-slice.sh" \
  "http://host.docker.internal:$PORT" \
  "$BUCKET-slice" "$ACCESS_KEY" "$SECRET_KEY"

FLYOLOGY_GET_OBJECT_ATTRIBUTES_ORACLE_MODE=minio-2025-lowercase-root \
FLYOLOGY_HEAD_OBJECT_ORACLE_MODE=minio-2025-uses-206-for-part-and-range \
FLYOLOGY_LIST_OBJECTS_V1_ORACLE_MODE=\
minio-2025-next-marker-without-delimiter \
FLYOLOGY_DELETE_OBJECT_ORACLE_MODE=minio-2025-ignores-if-match \
"$SCRIPT_DIR/run-s3-implementation.sh" \
  "http://127.0.0.1:$PORT" \
  "http://host.docker.internal:$PORT" \
  "$BUCKET" "$ACCESS_KEY" "$SECRET_KEY" yes
echo "MinIO GetObjectAttributes oracle: skipped, pinned response uses" \
  "a non-AWS lowercase root element"
echo "MinIO HeadObject range/part oracle: pinned release returns HTTP 206" \
  "and Content-Range instead of the AWS HTTP 200 response"
echo "MinIO ListObjects v1 pagination oracle: pinned release emits an" \
  "internal NextMarker without delimiter, contrary to AWS v1 semantics"
echo "MinIO DeleteObject oracle: pinned release ignores If-Match and returns" \
  "204 while deleting the mismatched object"

if [ -n "${FLYOLOGY_S3T_BIN:-}" ]; then
  FLYOLOGY_S3_IMPLEMENTATION=minio \
    "$SCRIPT_DIR/run-s3t-corpus.sh" "http://127.0.0.1:$PORT" \
    "$ACCESS_KEY" "$SECRET_KEY"
fi

echo "MinIO compatibility target: OK"
