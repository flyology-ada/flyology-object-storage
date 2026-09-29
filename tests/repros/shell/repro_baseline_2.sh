#!/usr/bin/env bash
# BASELINE-2: the two s5cmd-driven CI jobs cannot fail.
#
# .github/workflows/ci.yml runs, under the default GitHub shell (`bash -e {0}`,
# no pipefail), the steps
#     ./tests/scripts/test-<reference>.sh 2>&1 | tee obj/ci/reference-<reference>.log
#     ./tests/scripts/test-flyology-server.sh memory 2>&1 | tee obj/ci/s3-smoke.log
# so the step's status is `tee`'s, and a failing script never fails the job.
# The scheduled run 34031107803 (2026-09-06) shows both jobs "success" with
# `ERROR "mb s3://...": dial tcp 172.17.0.1:<port>: connect: connection
# refused` in their logs, because the servers are published on the host
# loopback (`--publish 127.0.0.1::<port>`), which a container reaching
# host.docker.internal cannot connect to on Linux.
#
# This program asserts the CORRECT behaviour: a step written the way the
# workflow writes it must fail when the script fails.  Exit 1 = BUG REPRODUCED.
set -u
failures=0
check() { if [ "$1" -eq 0 ]; then echo "  ok: $2"; else echo "  FAILED: $2"; failures=$((failures + 1)); fi; }

script=$(mktemp)
printf '#!/bin/sh\necho "Flyology memory endpoint runner failed" >&2\nexit 1\n' >"$script"
chmod +x "$script"

# 1. The workflow step, verbatim shape, under GitHub's default shell.
bash -e -c "$script 2>&1 | tee /dev/null" >/dev/null 2>&1
status=$?
echo "  -- default shell 'bash -e', script exits 1 through '| tee': step status $status"
check $(( status != 0 ? 0 : 1 )) "a failing conformance script fails the CI step as written (bash -e, pipe to tee)"

# 2. Control: the same step with pipefail (what 'shell: bash' would give).
bash -eo pipefail -c "$script 2>&1 | tee /dev/null" >/dev/null 2>&1
status=$?
echo "  -- control 'bash -eo pipefail': step status $status"
check $(( status != 0 ? 0 : 1 )) "control: with pipefail the same step fails"

# 3. The loopback publish is unreachable from a sibling container on Linux;
#    on this macOS host Docker Desktop/OrbStack forwards it, which is why the
#    corpus ran locally.  Show the binding the scripts request.
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  cid=$(docker run --detach --rm --publish 127.0.0.1::9000 alpine:3 sleep 30 2>/dev/null || true)
  if [ -n "$cid" ]; then
    mapping=$(docker port "$cid" 9000/tcp 2>/dev/null || true)
    echo "  -- docker port for '--publish 127.0.0.1::9000': ${mapping:-<none>}"
    docker stop --timeout 1 "$cid" >/dev/null 2>&1 || true
    case "$mapping" in
      127.0.0.1:*) echo "  -- the published port is bound to the host loopback only";;
    esac
  else
    echo "  -- (alpine image not available; skipped the publish demonstration)"
  fi
fi
if grep -q 'shell:\|pipefail' "$(dirname "$0")/../../../.github/workflows/ci.yml" 2>/dev/null; then found=0; else found=1; fi
check "$found" "ci.yml sets 'shell: bash' or pipefail for the piped steps"
rm -f "$script"
if [ "$failures" -eq 0 ]; then echo PASS; exit 0; else echo "BUG REPRODUCED: $failures failed expectation(s)"; exit 1; fi
