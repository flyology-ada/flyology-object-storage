#!/usr/bin/env bash
# SERVER-EXE-1: an administrator login runs 600,000 PBKDF2-HMAC-SHA256
# iterations inside a cooperative handler
# (flyology_object_storage_server_runtime.adb:853-858 instantiates the
# management Structured_Servers with Handler_Model => Flyology.Lightweight_Task,
# :187-190 does the same for the S3 listener), and
# flyology_object_storage_server_credentials.adb:133-145 never suspends, delays
# or polls cancellation inside the derivation loop.  With the default automatic
# loop pool of one shared group (flyology-execution_groups.ads:154-158) both
# listeners' handlers share one event-loop thread, so the derivation blocks
# every in-flight S3 request until it finishes.
#
# This program asserts the CORRECT behaviour: the two bounded listeners are
# documented (server/README.md:8-12) as coupled only through supervision
# order, so a management login must not change S3 request latency.
#
# Threshold: a concurrent S3 request fails the assertion when it exceeds both
#   * 10 x the slowest of the three baseline S3 requests, and
#   * an absolute floor of 0.050 s
# (the floor keeps host scheduling noise on a sub-millisecond baseline from
# tripping the ratio).  Measured on this host the ratio is ~300x, far above
# either bound.
#
# Exit 0 = PASS (not reproduced), 1 = BUG REPRODUCED, 2 = harness problem.
set -u

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$here/../../.." && pwd)
server="$root/server/bin/flyology_object_storage_server"
assets="$root/server/assets"
scratch=${TMPDIR_REPRO:-/private/tmp/claude-501}

if [ ! -x "$server" ]; then
  echo "harness problem: $server is not built (cd $root/server && alr -n build)" >&2
  exit 2
fi

work=$(mktemp -d "$scratch/repro-server-exe-1-XXXXXX") || exit 2
probe="$work/probe.py"
cat >"$probe" <<'PYEOF'
import datetime, hashlib, hmac, http.client, socket, sys, time

def sign(key, msg):
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()

def sigv4(method, path, host, access, secret, region, payload=b""):
    now = datetime.datetime.now(datetime.timezone.utc)
    amzdate = now.strftime("%Y%m%dT%H%M%SZ")
    datestamp = now.strftime("%Y%m%d")
    digest = hashlib.sha256(payload).hexdigest()
    canonical_headers = (f"host:{host}\nx-amz-content-sha256:{digest}\n"
                         f"x-amz-date:{amzdate}\n")
    signed = "host;x-amz-content-sha256;x-amz-date"
    creq = f"{method}\n{path}\n\n{canonical_headers}\n{signed}\n{digest}"
    scope = f"{datestamp}/{region}/s3/aws4_request"
    sts = ("AWS4-HMAC-SHA256\n" + amzdate + "\n" + scope + "\n"
           + hashlib.sha256(creq.encode("utf-8")).hexdigest())
    k = sign(("AWS4" + secret).encode("utf-8"), datestamp)
    for part in (region, "s3", "aws4_request"):
        k = sign(k, part)
    sig = hmac.new(k, sts.encode("utf-8"), hashlib.sha256).hexdigest()
    return {"Host": host, "x-amz-content-sha256": digest, "x-amz-date": amzdate,
            "Authorization": (f"AWS4-HMAC-SHA256 Credential={access}/{scope}, "
                              f"SignedHeaders={signed}, Signature={sig}")}

kind, port = sys.argv[1], int(sys.argv[2])
host = f"127.0.0.1:{port}"
if kind == "s3":
    access, secret, region = sys.argv[3], sys.argv[4], sys.argv[5]
    headers = sigv4("GET", "/", host, access, secret, region)
    t0 = time.monotonic()
    c = http.client.HTTPConnection("127.0.0.1", port, timeout=300)
    c.request("GET", "/", headers=headers)
    r = c.getresponse(); body = r.read(); dt = time.monotonic() - t0
    c.close()
    print(f"{dt:.3f} {r.status} {len(body)}")
elif kind == "connect":
    t0 = time.monotonic()
    socket.create_connection(("127.0.0.1", port), timeout=300).close()
    print(f"{time.monotonic() - t0:.3f} connected")
elif kind == "login":
    body = f"username=admin&password={sys.argv[3]}".encode("ascii")
    t0 = time.monotonic()
    c = http.client.HTTPConnection("127.0.0.1", port, timeout=300)
    c.request("POST", "/api/login", body=body,
              headers={"Host": host, "Origin": f"http://{host}",
                       "Content-Type": "application/x-www-form-urlencoded",
                       "Content-Length": str(len(body))})
    r = c.getresponse(); payload = r.read(); dt = time.monotonic() - t0
    c.close()
    print(f"{dt:.3f} {r.status} {payload.decode('ascii', 'replace')}")
else:
    raise SystemExit(2)
PYEOF

log="$work/server.log"
server_pid=""
cleanup() {
  if [ -n "$server_pid" ]; then
    kill -TERM "$server_pid" 2>/dev/null
    wait "$server_pid" 2>/dev/null
  fi
  rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

env -i PATH="$PATH" \
  FLYOLOGY_ADMIN_ASSET_ROOT="$assets" \
  FLYOLOGY_ADMIN_CREDENTIALS_FILE="$work/admin.credentials" \
  FLYOLOGY_S3_PORT=0 FLYOLOGY_ADMIN_PORT=0 \
  AWS_ACCESS_KEY_ID=REPROKEY AWS_SECRET_ACCESS_KEY=reprosecret \
  AWS_REGION=us-east-1 \
  "$server" >"$log" 2>&1 &
server_pid=$!

for _ in $(seq 1 400); do
  grep -q '^READY admin ' "$log" && break
  kill -0 "$server_pid" 2>/dev/null || break
  sleep 0.05
done
if ! grep -q '^READY admin ' "$log"; then
  echo "harness problem: server did not become ready" >&2; cat "$log" >&2; exit 2
fi

s3_port=$(sed -n 's|^READY s3 http://[^:]*:\([0-9][0-9]*\) .*$|\1|p' "$log" | tail -1)
admin_port=$(sed -n 's|^READY admin http://127.0.0.1:\([0-9][0-9]*\)/$|\1|p' "$log" | tail -1)
password=$(sed -n 's/^BOOTSTRAP ADMIN username=admin password=\([0-9a-f]*\)$/\1/p' "$log")
if [ -z "$s3_port" ] || [ -z "$admin_port" ] || [ ${#password} -ne 48 ]; then
  echo "harness problem: could not read ports or bootstrap password" >&2
  cat "$log" >&2; exit 2
fi
echo "  -- s3 port $s3_port, management port $admin_port, loop pool = default (FLYOLOGY_LOOP_POOL_SIZE unset)"

failures=0
check() {
  if [ "$1" -eq 0 ]; then echo "  ok: $2"; else echo "  FAILED: $2"; failures=$((failures + 1)); fi
}

echo "  -- baseline: signed S3 ListBuckets with no other traffic (3 runs)"
base_max=0
for run in 1 2 3; do
  out=$(python3 "$probe" s3 "$s3_port" REPROKEY reprosecret us-east-1) || exit 2
  echo "     run $run: $out  (seconds status bytes)"
  t=${out%% *}
  base_max=$(python3 -c "print(max($base_max, $t))")
done
echo "  -- worst baseline S3 latency: ${base_max}s"

echo "  -- one management login on its own (3 runs)"
for run in 1 2 3; do
  echo "     run $run: $(python3 "$probe" login "$admin_port" "$password")"
done

threshold=$(python3 -c "print(max(10 * $base_max, 0.050))")
echo "  -- threshold for a concurrent S3 request: ${threshold}s (max of 10x baseline and 0.050 s)"

echo "  -- S3 request issued 0.15 s into a valid login (3 runs)"
worst=0
for run in 1 2 3; do
  python3 "$probe" login "$admin_port" "$password" >"$work/login-$run" 2>&1 &
  login_pid=$!
  sleep 0.15
  s3out=$(python3 "$probe" s3 "$s3_port" REPROKEY reprosecret us-east-1) || exit 2
  conn=$(python3 "$probe" connect "$s3_port") || exit 2
  wait "$login_pid"
  echo "     run $run: s3=${s3out}  tcp-connect=${conn}  login=$(cat "$work/login-$run")"
  t=${s3out%% *}
  worst=$(python3 -c "print(max($worst, $t))")
done
echo "  -- worst S3 latency during a login: ${worst}s"

check "$(python3 -c "print(0 if $worst <= $threshold else 1)")" \
  "an S3 request issued during an administrator login stays within ${threshold}s"

# Control: with the login finished, the same request is fast again, so the
# probe and the signature are correct and the listener is healthy.
after=$(python3 "$probe" s3 "$s3_port" REPROKEY reprosecret us-east-1) || exit 2
echo "  -- control: S3 request after the logins: $after  (seconds status bytes)"
check "$(python3 -c "print(0 if ${after%% *} <= $threshold else 1)")" \
  "control: with no login in flight the same signed S3 request is fast"

if [ "$failures" -eq 0 ]; then echo PASS; exit 0; fi
echo "BUG REPRODUCED: $failures failed expectation(s)"
exit 1
