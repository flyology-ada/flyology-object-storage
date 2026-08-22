#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SERVER_IMAGE="ghcr.io/rustfs/rustfs@sha256:800cf3f352a0a27e3275ca854a51f0027975d7acc7a0d52089a35bcc9fcbf0b5"
ACCESS_KEY="FLYOLOGYS3ORACLE"
SECRET_KEY="flyology-s3-oracle-secret-key-tests"
CONTAINER="flyology-object-storage-rustfs-$$"
BUCKET="flyology-rustfs-corpus-$$"

cleanup() {
  if docker inspect "$CONTAINER" >/dev/null 2>&1; then
    docker stop --timeout 5 "$CONTAINER" >/dev/null
  fi
}
trap cleanup EXIT INT TERM

command -v docker >/dev/null
docker pull "$SERVER_IMAGE"
SERVER_VERSION=$(docker run --rm \
  --env "RUSTFS_ACCESS_KEY=$ACCESS_KEY" \
  --env "RUSTFS_SECRET_KEY=$SECRET_KEY" \
  "$SERVER_IMAGE" --version)
case "$SERVER_VERSION" in
  *1.0.0-rc.3*1aae6803739a5bac67e0d702ac46d43f09fb06dd*) ;;
  *) echo "unexpected RustFS image provenance" >&2; exit 1 ;;
esac
docker run --detach --rm --name "$CONTAINER" \
  --publish "127.0.0.1::9000" \
  --env "RUSTFS_ACCESS_KEY=$ACCESS_KEY" \
  --env "RUSTFS_SECRET_KEY=$SECRET_KEY" \
  "$SERVER_IMAGE" >/dev/null

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
    echo "RustFS did not become healthy" >&2
    exit 1
  fi
  sleep 0.25
done

if [ -n "${FLYOLOGY_S3_SERVER_RUNNER:-}" ]; then
  FLYOLOGY_S3_IMPLEMENTATION=rustfs \
  FLYOLOGY_S3_SERVER_REVISION="$SERVER_IMAGE" "$FLYOLOGY_S3_SERVER_RUNNER" \
    "http://host.docker.internal:$PORT" \
    "$BUCKET" "$ACCESS_KEY" "$SECRET_KEY"
  echo "RustFS endpoint runner: OK"
  exit 0
fi

"$SCRIPT_DIR/run-s3-server-slice.sh" \
  "http://host.docker.internal:$PORT" \
  "$BUCKET-slice" "$ACCESS_KEY" "$SECRET_KEY"

FLYOLOGY_GET_OBJECT_ATTRIBUTES_ORACLE_MODE=\
rustfs-rc3-missing-error-message \
"$SCRIPT_DIR/run-s3-implementation.sh" \
  "http://127.0.0.1:$PORT" \
  "http://host.docker.internal:$PORT" \
  "$BUCKET" "$ACCESS_KEY" "$SECRET_KEY" yes
echo "RustFS GetObjectAttributes missing-key oracle: skipped, pinned" \
  "response omits the required Error Message member"

if [ -n "${FLYOLOGY_S3T_BIN:-}" ]; then
  FLYOLOGY_S3_IMPLEMENTATION=rustfs \
    "$SCRIPT_DIR/run-s3t-corpus.sh" "http://127.0.0.1:$PORT" \
    "$ACCESS_KEY" "$SECRET_KEY"
fi

echo "RustFS primary permissive target: OK"
