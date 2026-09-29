#!/bin/sh
# Build and run one reproduction program.
#   ./run.sh repro_name [timeout_seconds]
# Exit status: 0 = expected (correct) behavior observed; 1 = bug reproduced;
# 124 = timed out (treated as a hang); other = build failure or crash.
set -u
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
name=${1:?repro program name}
limit=${2:-60}
lock="$script_dir/../../../tests/repros/.build.lock"
cd "$script_dir" || exit 2
# Serialize concurrent builds sharing one object directory and the Alire cache.
tries=0
until mkdir "$lock" 2>/dev/null; do
  tries=$((tries + 1))
  if [ "$tries" -gt 1800 ]; then echo "lock timeout" >&2; exit 2; fi
  sleep 1
done
trap 'rmdir "$lock" 2>/dev/null' EXIT HUP INT TERM
mkdir -p obj
if [ ! -f config/repros_sqlite_config.gpr ]; then
  # First use: let Alire materialize the pinned root crate and the config.
  alr -n build >"obj/build-alire-setup.log" 2>&1 || true
fi
if ! alr -n exec -- gprbuild -q -p -P repros_sqlite.gpr -XMAIN="$name" >"obj/build-$name.log" 2>&1; then
  cat "obj/build-$name.log" >&2
  echo "BUILD FAILED: $name" >&2
  exit 2
fi
rmdir "$lock" 2>/dev/null
trap - EXIT HUP INT TERM
if command -v timeout >/dev/null 2>&1; then
  timeout "$limit" "./bin/$name"
else
  perl -e 'alarm shift; exec @ARGV' "$limit" "./bin/$name"
fi
status=$?
if [ "$status" -eq 124 ] || [ "$status" -eq 142 ]; then
  echo "TIMEOUT after ${limit}s: $name (hang)"; status=124
fi
exit "$status"
