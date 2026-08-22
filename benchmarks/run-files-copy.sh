#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
MIB=${1:-64}
COPIES=${2:-4}
TEMP_ROOT=$(mktemp -d /tmp/flyology-files-copy.XXXXXX)
cleanup() {
  case "$TEMP_ROOT" in
    /tmp/flyology-files-copy.*) rm -rf "$TEMP_ROOT" ;;
    *) echo "refusing unexpected benchmark cleanup path" >&2 ;;
  esac
}
trap cleanup EXIT HUP INT TERM

cd "$PROJECT_DIR/tests"
alr -n build
./bin/files_copy_benchmark "$TEMP_ROOT/store" "$MIB" "$COPIES"
