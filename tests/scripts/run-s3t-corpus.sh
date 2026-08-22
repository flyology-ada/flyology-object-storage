#!/usr/bin/env bash
set -euo pipefail
umask 077

if [ "$#" -ne 3 ]; then
  echo "usage: $0 http://LOOPBACK:PORT ACCESS_KEY SECRET_KEY" >&2
  exit 2
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
S3T=${FLYOLOGY_S3T_BIN:?FLYOLOGY_S3T_BIN must name the pinned s3t binary}
ENDPOINT=$1
ACCESS_KEY=$2
SECRET_KEY=$3
EXPECTED_REVISION=51506ac904f6e35424b3ec9d38716985023beba6
WORK_ROOT=$(mktemp -d "/tmp/flyology-s3t-corpus.XXXXXX")
CONFIG="$WORK_ROOT/s3tests.conf"
REPORT_ROOT=${FLYOLOGY_S3T_REPORT_DIR:-"$PROJECT_DIR/obj/s3t"}
IMPLEMENTATION=${FLYOLOGY_S3_IMPLEMENTATION:-flyology}
REPORT_ID=${FLYOLOGY_S3T_REPORT_ID:-"$(date -u +%Y%m%dT%H%M%SZ)-$$"}
REPORT="$REPORT_ROOT/$IMPLEMENTATION-$REPORT_ID.jsonl"
KNOWN_FAILURES="$PROJECT_DIR/coverage/s3t-known-failures-$IMPLEMENTATION.txt"

cleanup() {
  case "$WORK_ROOT" in
    /tmp/flyology-s3t-corpus.*) rm -rf "$WORK_ROOT" ;;
    *) echo "refusing unexpected s3t cleanup path" >&2 ;;
  esac
}
trap cleanup EXIT INT TERM

test -x "$S3T"
VERSION=$($S3T version)
REVISION=$(printf '%s\n' "$VERSION" | sed -n 's/^revision \([0-9a-f]\{40\}\)$/\1/p')
if [ "$REVISION" != "$EXPECTED_REVISION" ]; then
  echo "unexpected or dirty s3t binary provenance: $VERSION" >&2
  exit 1
fi

case "$ENDPOINT" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *) echo "s3t corpus requires a cleartext loopback endpoint" >&2; exit 2 ;;
esac
HOST_PORT=${ENDPOINT#http://}
HOST=${HOST_PORT%:*}
PORT=${HOST_PORT##*:}
case "$PORT" in
  ''|*[!0-9]*) echo "invalid s3t endpoint port" >&2; exit 2 ;;
esac

mkdir -p "$REPORT_ROOT"
{
  echo '[DEFAULT]'
  echo "host = $HOST"
  echo "port = $PORT"
  echo 'is_secure = False'
  echo 'ssl_verify = False'
  echo '[fixtures]'
  echo 'bucket prefix = flyology-s3t-{random}-'
  echo '[s3 main]'
  echo 'display_name = Flyology Tester'
  echo 'user_id = flyology'
  echo 'email = flyology@example.invalid'
  echo 'api_name = default'
  echo "access_key = $ACCESS_KEY"
  echo "secret_key = $SECRET_KEY"
  echo '[s3 alt]'
  echo 'display_name = Alternate Tester'
  echo 'user_id = alternate'
  echo 'email = alternate@example.invalid'
  echo 'access_key = FLYOLOGYALTERNATE'
  echo 'secret_key = flyology-alternate-secret-key-tests'
  echo '[s3 tenant]'
  echo 'display_name = Tenant Tester'
  echo 'user_id = tenant'
  echo 'email = tenant@example.invalid'
  echo 'access_key = FLYOLOGYTENANT'
  echo 'secret_key = flyology-tenant-secret-key-tests'
  echo 'tenant = flyology'
} >"$CONFIG"

if [ -n "${FLYOLOGY_S3T_PATTERN:-}" ]; then
  ARGS=(run -c "$CONFIG" -k "$FLYOLOGY_S3T_PATTERN"
    --parallel 4 --color never --json "$REPORT" --timeout 2m)
else
  ARGS=(run -c "$CONFIG"
    --allow-list "$PROJECT_DIR/coverage/s3t-allow.txt"
    --parallel 4 --color never --json "$REPORT" --timeout 2m)
fi
if [ -z "${FLYOLOGY_S3T_PATTERN:-}" ] && [ -s "$KNOWN_FAILURES" ]; then
  ARGS+=(--known-failures "$KNOWN_FAILURES")
fi
"$S3T" "${ARGS[@]}"
echo "pinned s3t corpus: $IMPLEMENTATION OK"
