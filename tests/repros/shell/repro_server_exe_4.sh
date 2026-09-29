#!/usr/bin/env bash
# SERVER-EXE-4: when a listener cannot bind, the supervisor's termination
# diagnostics are discarded.  flyology_object_storage_server_runtime.adb:922-925
# binds the management listener with no handler, so Socket_Error escapes the
# generation; flyology-supervision-static.adb:750-752 copies the child's
# Termination_Summary (exception name plus up to 512 characters of message,
# flyology-supervision.ads:167-177,405-411) into Supervisor_Result; and
# runtime.adb:1075-1080 prints only Result.Outcome'Image.
#
# This program asserts the CORRECT behaviour: the operator diagnostic for a
# failed start must name at least one of the failing child, the endpoint it
# tried to bind, or the exception, so the operator can tell a port conflict
# from an asset, credential or backend failure.
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

work=$(mktemp -d "$scratch/repro-server-exe-4-XXXXXX") || exit 2
holder_pid=""
cleanup() {
  if [ -n "$holder_pid" ]; then kill "$holder_pid" 2>/dev/null; wait "$holder_pid" 2>/dev/null; fi
  rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

# Hold a loopback port so the management listener's bind fails.
python3 -c '
import socket, sys, time
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 0)); s.listen(16)
print(s.getsockname()[1], flush=True)
time.sleep(120)
' >"$work/port" 2>&1 &
holder_pid=$!
for _ in $(seq 1 100); do
  [ -s "$work/port" ] && break
  sleep 0.05
done
busy=$(head -1 "$work/port")
case "$busy" in
  ''|*[!0-9]*) echo "harness problem: could not hold a loopback port" >&2; cat "$work/port" >&2; exit 2 ;;
esac
echo "  -- another process holds 127.0.0.1:$busy (a port already in use is the common operator mistake)"

env -i PATH="$PATH" \
  FLYOLOGY_ADMIN_ASSET_ROOT="$assets" \
  FLYOLOGY_ADMIN_CREDENTIALS_FILE="$work/admin.credentials" \
  FLYOLOGY_S3_PORT=0 FLYOLOGY_ADMIN_PORT="$busy" \
  AWS_ACCESS_KEY_ID=REPROKEY AWS_SECRET_ACCESS_KEY=reprosecret \
  "$server" >"$work/out" 2>"$work/err"
status=$?

echo "  -- server exit status: $status"
echo "  -- stdout:"
sed 's/^/       /' "$work/out"
echo "  -- stderr:"
sed 's/^/       /' "$work/err"

failures=0
check() {
  if [ "$1" -eq 0 ]; then echo "  ok: $2"; else echo "  FAILED: $2"; failures=$((failures + 1)); fi
}

# The diagnostic under test is the failure report itself: the
# "object-storage server stopped:" line and anything the executable adds after
# it.  The BOOTSTRAP banner and the credentials path printed at startup are
# excluded deliberately -- they are emitted on every run and say nothing about
# the failure.
diagnostics=$(sed -n '/object-storage server stopped:/,$p' "$work/err")
echo "  -- failure diagnostic under test:"
printf '%s\n' "$diagnostics" | sed 's/^/       /'

# Control: the failure is detected at all.
check "$([ "$status" -ne 0 ] && echo 0 || echo 1)" \
  "control: a management bind failure gives a non-zero exit status"
check "$(grep -q 'object-storage server stopped:' "$work/err" && echo 0 || echo 1)" \
  "control: the executable reports that the server stopped"

if printf '%s' "$diagnostics" | grep -qi 'admin\|management\|workbench\|child'; then
  named_child=0
else
  named_child=1
fi
if printf '%s' "$diagnostics" | grep -q ":$busy"; then
  named_endpoint=0
else
  named_endpoint=1
fi
if printf '%s' "$diagnostics" | grep -qi 'socket_error\|address already in use\|EADDRINUSE\|exception'; then
  named_exception=0
else
  named_exception=1
fi
echo "  -- diagnostic names the failing child: $([ $named_child -eq 0 ] && echo yes || echo no)"
echo "  -- diagnostic names the endpoint 127.0.0.1:$busy: $([ $named_endpoint -eq 0 ] && echo yes || echo no)"
echo "  -- diagnostic names the exception: $([ $named_exception -eq 0 ] && echo yes || echo no)"

if [ $named_child -eq 0 ] || [ $named_endpoint -eq 0 ] || [ $named_exception -eq 0 ]; then
  informative=0
else
  informative=1
fi
check "$informative" \
  "the startup-failure diagnostic names the failing child, the endpoint, or the exception"

# Control: the same executable does report the cause for a failure raised
# before the supervisor starts (server.adb:91-99 prints Exception_Information),
# so the executable can produce a useful diagnostic and the gap is specific to
# supervisor outcomes.
env -i PATH="$PATH" \
  FLYOLOGY_ADMIN_ASSET_ROOT="$assets" \
  FLYOLOGY_ADMIN_CREDENTIALS_FILE="$work/admin2.credentials" \
  FLYOLOGY_OBJECT_STORAGE_BACKEND=not-a-backend \
  FLYOLOGY_S3_PORT=0 FLYOLOGY_ADMIN_PORT=0 \
  "$server" >"$work/out2" 2>"$work/err2"
echo "  -- control (pre-supervisor failure, bad backend name), stderr:"
grep -m1 -i 'must be memory' "$work/err2" | sed 's/^/       /'
check "$(grep -qi 'must be memory, files, or sqlite' "$work/err2" && echo 0 || echo 1)" \
  "control: a configuration failure before the supervisor names its cause"

if [ "$failures" -eq 0 ]; then echo PASS; exit 0; fi
echo "BUG REPRODUCED: $failures failed expectation(s)"
exit 1
