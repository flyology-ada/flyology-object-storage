#!/usr/bin/env bash
# SERVER-EXE-2: the management routes declare per-route admission policy
#   flyology_object_storage_server_runtime.adb:882-887
#     ("/api/login", ... Concurrency => 1, Rate_Per_Second => 2)
# and the same pattern on /api/buckets, /api/objects, /api/buckets/delete and
# /api/logout (:888-918), but nothing installs the toolkit layers that consume
# it: Handle serves the router directly (:846-850) and
# `rg -n -i 'middleware|bulkhead|rate_limits' server/src/` matches nothing.
# flyology_http 0.1.3 routing.ads:81-89 says the policy is "consumed
# incrementally by optional toolkit layers"; the only readers of
# Rate_Per_Second / Concurrency_Limit are middleware_rate_limits.adb and
# middleware_bulkheads.adb, which reject with 429 (Retry-After) and 503.
#
# This program asserts the CORRECT behaviour implied by the written policy:
# of 50 simultaneous POST /api/login attempts with a wrong password, a
# per-client token bucket of 2/s (or a bulkhead of 1) must reject most of them
# with 429 or 503 instead of running 50 full 600,000-iteration PBKDF2
# derivations.
#
# Exit 0 = PASS (not reproduced), 1 = BUG REPRODUCED, 2 = harness problem.
set -u

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$here/../../.." && pwd)
server="$root/server/bin/flyology_object_storage_server"
assets="$root/server/assets"
scratch=${TMPDIR_REPRO:-/private/tmp/claude-501}
attempts=${ATTEMPTS:-50}

if [ ! -x "$server" ]; then
  echo "harness problem: $server is not built (cd $root/server && alr -n build)" >&2
  exit 2
fi

work=$(mktemp -d "$scratch/repro-server-exe-2-XXXXXX") || exit 2
flood="$work/flood.py"
cat >"$flood" <<'PYEOF'
import collections, http.client, sys, threading, time

port, password, count = int(sys.argv[1]), sys.argv[2], int(sys.argv[3])
host = f"127.0.0.1:{port}"
body = f"username=admin&password={password}".encode("ascii")
results, lock, gate = [], threading.Lock(), threading.Barrier(count)

def one():
    gate.wait()
    t0 = time.monotonic()
    try:
        c = http.client.HTTPConnection("127.0.0.1", port, timeout=600)
        c.request("POST", "/api/login", body=body,
                  headers={"Host": host, "Origin": f"http://{host}",
                           "Content-Type": "application/x-www-form-urlencoded",
                           "Content-Length": str(len(body))})
        r = c.getresponse(); r.read()
        retry = r.getheader("Retry-After")
        outcome = str(r.status) + (f" Retry-After={retry}" if retry else "")
        c.close()
    except Exception as exc:
        outcome = f"transport-error {type(exc).__name__}"
    with lock:
        results.append((outcome, time.monotonic() - t0))

start = time.monotonic()
threads = [threading.Thread(target=one) for _ in range(count)]
for t in threads: t.start()
for t in threads: t.join()
wall = time.monotonic() - start
tally = collections.Counter(o for o, _ in results)
for outcome, n in sorted(tally.items()):
    print(f"     {n:3d} x {outcome}")
lat = sorted(d for _, d in results)
served = sum(n for o, n in tally.items() if o.startswith(("200", "401")))
limited = sum(n for o, n in tally.items() if o.startswith(("429", "503")))
print(f"     wall={wall:.2f}s min={lat[0]:.2f}s median={lat[len(lat)//2]:.2f}s "
      f"max={lat[-1]:.2f}s")
print(f"SUMMARY served={served} limited={limited} wall={wall:.2f}")
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
admin_port=$(sed -n 's|^READY admin http://127.0.0.1:\([0-9][0-9]*\)/$|\1|p' "$log" | tail -1)
[ -n "$admin_port" ] || { echo "harness problem: no management port" >&2; exit 2; }

failures=0
check() {
  if [ "$1" -eq 0 ]; then echo "  ok: $2"; else echo "  FAILED: $2"; failures=$((failures + 1)); fi
}

echo "  -- management port $admin_port; declared policy on /api/login is Concurrency => 1, Rate_Per_Second => 2"
echo "  -- $attempts simultaneous POST /api/login with a wrong 48-hex password:"
wrong=$(printf '0%.0s' $(seq 1 48))
out=$(python3 "$flood" "$admin_port" "$wrong" "$attempts") || exit 2
echo "$out" | grep -v '^SUMMARY'
summary=$(echo "$out" | sed -n 's/^SUMMARY //p')
served=$(echo "$summary" | sed -n 's/.*served=\([0-9]*\).*/\1/p')
limited=$(echo "$summary" | sed -n 's/.*limited=\([0-9]*\).*/\1/p')
wall=$(echo "$summary" | sed -n 's/.*wall=\([0-9.]*\).*/\1/p')
echo "  -- fully processed by a handler (200/401): $served; rejected by a limiter (429/503): $limited"

check "$(python3 -c "print(0 if $limited > 0 else 1)")" \
  "a per-client rate limit or bulkhead rejects some of $attempts simultaneous logins with 429/503"

# middleware_rate_limits.ads:24-25 gives the token bucket a burst capacity
# equal to the configured rate, so a simultaneous burst from one peer must
# admit at most 2 and reject the remaining ~48 immediately.
echo "  -- burst capacity of the declared policy is 2; observed admissions: $served (wall ${wall}s)"
check "$(python3 -c "print(0 if $served <= 2 else 1)")" \
  "a simultaneous burst from one peer admits at most the declared burst of 2"

# Control: the endpoint itself works and answers 401 for a wrong password, so
# the flood above measured real handler work and not a broken request shape.
single=$(python3 - "$admin_port" "$wrong" <<'PYEOF'
import http.client, sys
port, password = int(sys.argv[1]), sys.argv[2]
host = f"127.0.0.1:{port}"
body = f"username=admin&password={password}".encode("ascii")
c = http.client.HTTPConnection("127.0.0.1", port, timeout=300)
c.request("POST", "/api/login", body=body,
          headers={"Host": host, "Origin": f"http://{host}",
                   "Content-Type": "application/x-www-form-urlencoded",
                   "Content-Length": str(len(body))})
r = c.getresponse(); print(r.status, r.read().decode("ascii", "replace"))
PYEOF
) || exit 2
echo "  -- control: one wrong-password login on its own: $single"
case "$single" in
  401*) check 0 "control: a single wrong-password login is answered 401" ;;
  *)    check 1 "control: a single wrong-password login is answered 401" ;;
esac

if [ "$failures" -eq 0 ]; then echo PASS; exit 0; fi
echo "BUG REPRODUCED: $failures failed expectation(s)"
exit 1
