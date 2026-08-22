#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SERVER_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SERVER_DIR/.." && pwd)
SERVER="$SERVER_DIR/bin/flyology_object_storage_server"
ACCESS_KEY=FLYOLOGYS3ORACLE
SECRET_KEY=flyology-s3-oracle-secret-key-tests
RUN_ROOT=$(mktemp -d /tmp/flyology-object-storage-server.XXXXXX)
SERVER_PID=""

cleanup() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    kill -TERM "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" >/dev/null 2>&1 || true
  fi
  case "$RUN_ROOT" in
    /tmp/flyology-object-storage-server.*) rm -rf "$RUN_ROOT" ;;
    *) echo "refusing unexpected server-test cleanup path" >&2 ;;
  esac
}
trap cleanup EXIT INT TERM

expect_startup_failure() {
  local name=$1
  shift
  if env -i PATH="$PATH" "$@" "$SERVER" >"$RUN_ROOT/$name.log" 2>&1; then
    echo "server unexpectedly accepted invalid configuration: $name" >&2
    exit 1
  fi
}

expect_startup_failure missing-root \
  FLYOLOGY_OBJECT_STORAGE_BACKEND=files \
  AWS_ACCESS_KEY_ID="$ACCESS_KEY" AWS_SECRET_ACCESS_KEY="$SECRET_KEY"
expect_startup_failure unknown-backend \
  FLYOLOGY_OBJECT_STORAGE_BACKEND=unknown \
  AWS_ACCESS_KEY_ID="$ACCESS_KEY" AWS_SECRET_ACCESS_KEY="$SECRET_KEY"
expect_startup_failure missing-s3-credentials \
  FLYOLOGY_OBJECT_STORAGE_BACKEND=memory
expect_startup_failure hostname-bind \
  FLYOLOGY_OBJECT_STORAGE_BACKEND=memory FLYOLOGY_S3_BIND=localhost \
  AWS_ACCESS_KEY_ID="$ACCESS_KEY" AWS_SECRET_ACCESS_KEY="$SECRET_KEY"
expect_startup_failure excessive-capacity \
  FLYOLOGY_OBJECT_STORAGE_BACKEND=memory FLYOLOGY_S3_CAPACITY=4097 \
  AWS_ACCESS_KEY_ID="$ACCESS_KEY" AWS_SECRET_ACCESS_KEY="$SECRET_KEY"
echo "server configuration rejection corpus: OK"

for backend in memory files sqlite
do
  log="$RUN_ROOT/$backend.log"
  root="$RUN_ROOT/$backend-store"
  env -i PATH="$PATH" \
    FLYOLOGY_OBJECT_STORAGE_BACKEND="$backend" \
    FLYOLOGY_OBJECT_STORAGE_ROOT="$root" \
    FLYOLOGY_S3_PORT=0 \
    AWS_ACCESS_KEY_ID="$ACCESS_KEY" \
    AWS_SECRET_ACCESS_KEY="$SECRET_KEY" \
    AWS_REGION=us-east-1 \
      "$SERVER" >"$log" 2>&1 &
  SERVER_PID=$!

  port=""
  for attempt in $(seq 1 200)
  do
    port=$(sed -n 's/^READY s3 http:\/\/[^:]*:\([0-9][0-9]*\) backend=.*$/\1/p' \
      "$log" | tail -1)
    if [ -n "$port" ]; then
      break
    fi
    if ! kill -0 "$SERVER_PID" >/dev/null 2>&1; then
      cat "$log" >&2
      echo "$backend server exited before readiness" >&2
      exit 1
    fi
    if [ "$attempt" -eq 200 ]; then
      cat "$log" >&2
      echo "$backend server did not become ready" >&2
      exit 1
    fi
    sleep 0.05
  done

  "$PROJECT_DIR/tests/scripts/run-s3-server-slice.sh" \
    "http://host.docker.internal:$port" \
    "flyology-production-$backend-$$" "$ACCESS_KEY" "$SECRET_KEY"

  kill -TERM "$SERVER_PID"
  wait "$SERVER_PID"
  SERVER_PID=""
  echo "supervised production server $backend: OK"
done
