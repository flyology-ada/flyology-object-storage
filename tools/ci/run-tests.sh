#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
LOG_DIR=${FLYOLOGY_CI_LOG_DIR:-"$PROJECT_DIR/obj/ci"}
mkdir -p "$LOG_DIR"
STATUS=0

run_gate() {
  local name=$1
  shift
  set +e
  "$@" 2>&1 | tee "$LOG_DIR/$name.log"
  local gate_status=${PIPESTATUS[0]}
  set -e
  if [ "$gate_status" -ne 0 ]; then
    echo "$name failed with status $gate_status" >&2
    STATUS=1
  fi
}

cd "$PROJECT_DIR"
run_gate root-build alr -n build
run_gate root-tests "$PROJECT_DIR/tests/scripts/test.sh"
run_gate sqlite-tests "$PROJECT_DIR/sqlite/tests/scripts/test.sh"

if [ "$STATUS" -ne 0 ]; then
  echo "CI test gates: FAILED" >&2
  exit "$STATUS"
fi
echo "CI test gates: root build, root tests, and SQLite tests OK"
