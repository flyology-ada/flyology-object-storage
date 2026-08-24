#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 memory|files|sqlite" >&2
  exit 2
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
BACKEND=$1
ACCESS_KEY="FLYOLOGYS3ORACLE"
SECRET_KEY="flyology-s3-oracle-secret-key-tests"
RUN_ROOT=$(mktemp -d "/tmp/flyology-s3-$BACKEND.XXXXXX")
SERVER_LOG="$RUN_ROOT/server.log"
SERVER_PID=""

cleanup() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    kill -TERM "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" >/dev/null 2>&1 || true
  fi
  case "$RUN_ROOT" in
    "/tmp/flyology-s3-$BACKEND."*) rm -rf "$RUN_ROOT" ;;
    *) echo "refusing unexpected server cleanup path" >&2 ;;
  esac
}
trap cleanup EXIT INT TERM

case "$BACKEND" in
  memory)
    (cd "$PROJECT_DIR/tests" && alr -n build)
    SERVER="$PROJECT_DIR/tests/bin/s3_memory_server"
    ;;
  files)
    (cd "$PROJECT_DIR/tests" && alr -n build)
    SERVER="$PROJECT_DIR/tests/bin/s3_files_server"
    ;;
  sqlite)
    (cd "$PROJECT_DIR/sqlite/tests" && alr -n build)
    SERVER="$PROJECT_DIR/sqlite/tests/bin/s3_sqlite_server"
    ;;
  *) echo "unknown Flyology backend: $BACKEND" >&2; exit 2 ;;
esac

start_server() {
  : >"$SERVER_LOG"
  AWS_ACCESS_KEY_ID=$ACCESS_KEY \
  AWS_SECRET_ACCESS_KEY=$SECRET_KEY \
  AWS_REGION=us-east-1 \
  FLYOLOGY_STORAGE_ROOT="$RUN_ROOT/store" \
    "$SERVER" 0 16 >"$SERVER_LOG" 2>&1 &
  SERVER_PID=$!

  PORT=""
  for attempt in $(seq 1 200)
  do
    PORT=$(sed -n 's/^PORT //p' "$SERVER_LOG" | tail -1)
    if [ -n "$PORT" ]; then
      return
    fi
    if ! kill -0 "$SERVER_PID" >/dev/null 2>&1; then
      cat "$SERVER_LOG" >&2
      echo "Flyology $BACKEND server exited before readiness" >&2
      exit 1
    fi
    if [ "$attempt" -eq 200 ]; then
      cat "$SERVER_LOG" >&2
      echo "Flyology $BACKEND server did not become ready" >&2
      exit 1
    fi
    sleep 0.05
  done
}

stop_server() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    kill -TERM "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" >/dev/null 2>&1 || true
  fi
  SERVER_PID=""
}

start_server

RUNNER=${FLYOLOGY_S3_SERVER_RUNNER:-"$SCRIPT_DIR/run-s3-server-slice.sh"}
SERVER_REVISION=$(git -C "$PROJECT_DIR" rev-parse --verify HEAD 2>/dev/null \
  || true)
if [ -z "$SERVER_REVISION" ]; then
  SERVER_REVISION=working-tree
fi
if ! env \
  FLYOLOGY_S3_IMPLEMENTATION="flyology-$BACKEND" \
  FLYOLOGY_S3_SERVER_REVISION="$SERVER_REVISION" \
  "$RUNNER" "http://host.docker.internal:$PORT" \
  "flyology-$BACKEND-slice-$$" "$ACCESS_KEY" "$SECRET_KEY"
then
  cat "$SERVER_LOG" >&2
  echo "Flyology $BACKEND endpoint runner failed" >&2
  exit 1
fi

if [ -n "${FLYOLOGY_S3_SERVER_RUNNER:-}" ]; then
  echo "Flyology $BACKEND endpoint runner: OK"
else
  FLYOLOGY_S3_IMPLEMENTATION="flyology-$BACKEND" \
    "$SCRIPT_DIR/run-s3-implementation.sh" \
    "http://127.0.0.1:$PORT" \
    "http://host.docker.internal:$PORT" \
    "flyology-$BACKEND-corpus-$$" "$ACCESS_KEY" "$SECRET_KEY" yes
  if [ "$BACKEND" = sqlite ]; then
    RESTART_BUCKET="flyology-sqlite-restart-$$"
    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    FLYOLOGY_S3_IMPLEMENTATION=flyology-sqlite \
      "$PROJECT_DIR/tests/bin/s3_implementation_corpus" \
      "http://127.0.0.1:$PORT" "$RESTART_BUCKET" "$TIMESTAMP" \
      restart-prepare
    stop_server
    start_server
    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    FLYOLOGY_S3_IMPLEMENTATION=flyology-sqlite \
      "$PROJECT_DIR/tests/bin/s3_implementation_corpus" \
      "http://127.0.0.1:$PORT" "$RESTART_BUCKET" "$TIMESTAMP" \
      restart-verify
    echo "Flyology sqlite authenticated restart routing: OK"
  fi
  if [ -n "${FLYOLOGY_S3T_BIN:-}" ]; then
    FLYOLOGY_S3_IMPLEMENTATION="flyology-$BACKEND" \
      "$SCRIPT_DIR/run-s3t-corpus.sh" "http://127.0.0.1:$PORT" \
      "$ACCESS_KEY" "$SECRET_KEY"
  fi
  echo "Flyology $BACKEND black-box server slice: OK"
fi
