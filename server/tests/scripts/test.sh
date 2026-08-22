#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SERVER_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SERVER_DIR/.." && pwd)
SERVER="$SERVER_DIR/bin/flyology_object_storage_server"
CREDENTIAL_CORPUS="$SERVER_DIR/bin/flyology_object_storage_server_credentials_corpus"
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

credential_mode() {
  if stat -c '%a' "$1" >/dev/null 2>&1; then
    stat -c '%a' "$1"
  else
    stat -f '%Lp' "$1"
  fi
}

admin_request() {
  local method=$1
  local url=$2
  local body_file=$3
  local header_file=$4
  shift 4
  curl --silent --show-error --request "$method" \
    --output "$body_file" --dump-header "$header_file" \
    --write-out '%{http_code}' "$@" "$url"
}

exercise_admin_api() {
  local backend=$1
  local admin_port=$2
  local s3_port=$3
  local password=$4
  local prefix=$5
  local base="http://127.0.0.1:$admin_port"
  local body="$RUN_ROOT/$prefix.body"
  local headers="$RUN_ROOT/$prefix.headers"
  local cookies="$RUN_ROOT/$prefix.cookies"
  local code token

  code=$(admin_request GET "$base/" "$body" "$headers")
  test "$code" = 200
  grep -q '<title>Object Storage · Flyology</title>' "$body"
  grep -qi '^Cache-Control: no-store' "$headers"
  grep -qi "^Content-Security-Policy: default-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'" \
    "$headers"
  grep -qi '^Referrer-Policy: no-referrer' "$headers"

  code=$(admin_request GET "$base/assets/app.css" "$body" "$headers")
  test "$code" = 200
  grep -qi '^Content-Type: text/css; charset=utf-8' "$headers"
  cmp "$body" "$SERVER_DIR/assets/app.css"
  code=$(admin_request GET "$base/assets/app.js" "$body" "$headers")
  test "$code" = 200
  grep -qi '^Content-Type: text/javascript; charset=utf-8' "$headers"
  cmp "$body" "$SERVER_DIR/assets/app.js"

  code=$(admin_request GET "$base/" "$body" "$headers" \
    -H 'Host: attacker.invalid')
  test "$code" = 421

  code=$(admin_request GET "$base/api/status" "$body" "$headers")
  test "$code" = 401
  test "$(tr -d '\r\n' <"$body")" = '{"authenticated":false}'

  code=$(admin_request POST "$base/api/login" "$body" "$headers" \
    -H "Origin: $base" \
    --data-binary 'username=admin&password=000000000000000000000000000000000000000000000000')
  test "$code" = 401
  sleep 1

  code=$(admin_request POST "$base/api/login" "$body" "$headers" \
    -H 'Origin: https://attacker.invalid' \
    --data-binary "username=admin&password=$password")
  test "$code" = 401
  sleep 1

  code=$(admin_request POST "$base/api/login" "$body" "$headers" \
    -H "Origin: $base" -c "$cookies" \
    --data-binary "username=admin&password=$password")
  test "$code" = 200
  test "$(tr -d '\r\n' <"$body")" = '{"authenticated":true}'
  grep -qi '^Set-Cookie: flyology_admin=[0-9a-f]\{64\}; Path=/; Max-Age=43200; HttpOnly; SameSite=Strict' \
    "$headers"
  token=$(awk '$6 == "flyology_admin" { print $7 }' "$cookies")
  case "$token" in
    *[!0-9a-f]*|'') echo "invalid administrator session token" >&2; exit 1 ;;
  esac
  test "${#token}" = 64

  code=$(admin_request GET "$base/api/status" "$body" "$headers" \
    -b "$cookies")
  test "$code" = 200
  test "$(tr -d '\r\n' <"$body")" = \
    "{\"authenticated\":true,\"backend\":\"$backend\",\"region\":\"us-east-1\",\"s3_address\":\"127.0.0.1\",\"s3_port\":$s3_port}"

  code=$(admin_request GET "$base/api/status" "$body" "$headers" \
    -H "Cookie: notflyology_admin=$token")
  test "$code" = 401
  code=$(admin_request GET "$base/api/status" "$body" "$headers" \
    -H "Cookie: flyology_admin=$token; flyology_admin=$token")
  test "$code" = 401
  code=$(admin_request GET "$base/api/status" "$body" "$headers" \
    -H "Cookie: flyology_admin=$token" \
    -H "Cookie: flyology_admin=$token")
  test "$code" = 401

  code=$(admin_request POST "$base/api/logout" "$body" "$headers" \
    -H "Origin: $base" -b "$cookies")
  test "$code" = 200
  grep -qi '^Set-Cookie: flyology_admin=; Path=/; Max-Age=0; HttpOnly; SameSite=Strict' \
    "$headers"
  code=$(admin_request GET "$base/api/status" "$body" "$headers" \
    -b "$cookies")
  test "$code" = 401
}

verify_persisted_admin() {
  local backend=$1
  local admin_port=$2
  local s3_port=$3
  local password=$4
  local base="http://127.0.0.1:$admin_port"
  local body="$RUN_ROOT/$backend-reload.body"
  local headers="$RUN_ROOT/$backend-reload.headers"
  local cookies="$RUN_ROOT/$backend-reload.cookies"
  local code

  code=$(admin_request POST "$base/api/login" "$body" "$headers" \
    -H "Origin: $base" -c "$cookies" \
    --data-binary "username=admin&password=$password")
  test "$code" = 200
  code=$(admin_request GET "$base/api/status" "$body" "$headers" \
    -b "$cookies")
  test "$code" = 200
  test "$(tr -d '\r\n' <"$body")" = \
    "{\"authenticated\":true,\"backend\":\"$backend\",\"region\":\"us-east-1\",\"s3_address\":\"127.0.0.1\",\"s3_port\":$s3_port}"
}

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
expect_startup_failure invalid-region \
  FLYOLOGY_OBJECT_STORAGE_BACKEND=memory AWS_REGION=US-EAST-1 \
  AWS_ACCESS_KEY_ID="$ACCESS_KEY" AWS_SECRET_ACCESS_KEY="$SECRET_KEY"
cp -R "$SERVER_DIR/assets" "$RUN_ROOT/tampered-assets"
printf '\n/* tampered */\n' >>"$RUN_ROOT/tampered-assets/app.css"
expect_startup_failure tampered-admin-assets \
  FLYOLOGY_OBJECT_STORAGE_BACKEND=memory \
  FLYOLOGY_ADMIN_ASSET_ROOT="$RUN_ROOT/tampered-assets" \
  FLYOLOGY_ADMIN_CREDENTIALS_FILE="$RUN_ROOT/tampered-admin.credentials" \
  AWS_ACCESS_KEY_ID="$ACCESS_KEY" AWS_SECRET_ACCESS_KEY="$SECRET_KEY"
grep -q 'management asset failed integrity check: app.css' \
  "$RUN_ROOT/tampered-admin-assets.log"
echo "server configuration rejection corpus: OK"

credential_path="$RUN_ROOT/credential-corpus/admin.credentials"
"$CREDENTIAL_CORPUS" "$credential_path"
test "$(credential_mode "$credential_path")" = 600
chmod 0644 "$credential_path"
if "$CREDENTIAL_CORPUS" "$credential_path" >/dev/null 2>&1; then
  echo "credential corpus accepted group/world-readable state" >&2
  exit 1
fi
echo "server credential permissions: OK"

for backend in memory files sqlite
do
  log="$RUN_ROOT/$backend.log"
  root="$RUN_ROOT/$backend-store"
  env -i PATH="$PATH" \
    FLYOLOGY_OBJECT_STORAGE_BACKEND="$backend" \
    FLYOLOGY_OBJECT_STORAGE_ROOT="$root" \
    FLYOLOGY_ADMIN_CREDENTIALS_FILE="$RUN_ROOT/$backend-admin.credentials" \
    FLYOLOGY_S3_PORT=0 \
    FLYOLOGY_ADMIN_PORT=0 \
    AWS_ACCESS_KEY_ID="$ACCESS_KEY" \
    AWS_SECRET_ACCESS_KEY="$SECRET_KEY" \
    AWS_REGION=us-east-1 \
      "$SERVER" >"$log" 2>&1 &
  SERVER_PID=$!

  port=""
  admin_port=""
  for attempt in $(seq 1 200)
  do
    port=$(sed -n 's/^READY s3 http:\/\/[^:]*:\([0-9][0-9]*\) backend=.*$/\1/p' \
      "$log" | tail -1)
    admin_port=$(sed -n \
      's|^READY admin http://127.0.0.1:\([0-9][0-9]*\)/$|\1|p' \
      "$log" | tail -1)
    if [ -n "$port" ] && [ -n "$admin_port" ]; then
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
  test "$(grep -c '^BOOTSTRAP ADMIN username=admin password=' "$log")" = 1
  admin_password=$(sed -n \
    's/^BOOTSTRAP ADMIN username=admin password=\([0-9a-f]*\)$/\1/p' \
    "$log")
  case "$admin_password" in
    *[!0-9a-f]*|'') echo "invalid bootstrap administrator password" >&2; exit 1 ;;
  esac
  test "${#admin_password}" = 48
  test "$(credential_mode "$RUN_ROOT/$backend-admin.credentials")" = 600

  exercise_admin_api "$backend" "$admin_port" "$port" "$admin_password" \
    "$backend-admin"

  "$PROJECT_DIR/tests/scripts/run-s3-server-slice.sh" \
    "http://host.docker.internal:$port" \
    "flyology-production-$backend-$$" "$ACCESS_KEY" "$SECRET_KEY"

  kill -TERM "$SERVER_PID"
  wait "$SERVER_PID"
  SERVER_PID=""

  reload_log="$RUN_ROOT/$backend-reload.log"
  env -i PATH="$PATH" \
    FLYOLOGY_OBJECT_STORAGE_BACKEND="$backend" \
    FLYOLOGY_OBJECT_STORAGE_ROOT="$root" \
    FLYOLOGY_ADMIN_CREDENTIALS_FILE="$RUN_ROOT/$backend-admin.credentials" \
    FLYOLOGY_S3_PORT=0 \
    FLYOLOGY_ADMIN_PORT=0 \
    AWS_ACCESS_KEY_ID="$ACCESS_KEY" \
    AWS_SECRET_ACCESS_KEY="$SECRET_KEY" \
    AWS_REGION=us-east-1 \
      "$SERVER" >"$reload_log" 2>&1 &
  SERVER_PID=$!
  reload_port=""
  reload_admin_port=""
  for attempt in $(seq 1 200)
  do
    reload_port=$(sed -n \
      's/^READY s3 http:\/\/[^:]*:\([0-9][0-9]*\) backend=.*$/\1/p' \
      "$reload_log" | tail -1)
    reload_admin_port=$(sed -n \
      's|^READY admin http://127.0.0.1:\([0-9][0-9]*\)/$|\1|p' \
      "$reload_log" | tail -1)
    if [ -n "$reload_port" ] && [ -n "$reload_admin_port" ]; then
      break
    fi
    if ! kill -0 "$SERVER_PID" >/dev/null 2>&1; then
      cat "$reload_log" >&2
      echo "$backend reload exited before readiness" >&2
      exit 1
    fi
    if [ "$attempt" -eq 200 ]; then
      cat "$reload_log" >&2
      echo "$backend reload did not become ready" >&2
      exit 1
    fi
    sleep 0.05
  done
  test "$(grep -c '^BOOTSTRAP ADMIN ' "$reload_log" || true)" = 0
  verify_persisted_admin "$backend" "$reload_admin_port" "$reload_port" \
    "$admin_password"
  kill -TERM "$SERVER_PID"
  wait "$SERVER_PID"
  SERVER_PID=""
  echo "supervised production server $backend: OK"
done
