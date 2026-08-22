#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPEATS=${FLYOLOGY_S3_MATRIX_REPEATS:-3}

case "$REPEATS" in
  ''|*[!0-9]*) echo "FLYOLOGY_S3_MATRIX_REPEATS must be a positive integer" >&2; exit 2 ;;
esac
if [ "$REPEATS" -lt 1 ]; then
  echo "FLYOLOGY_S3_MATRIX_REPEATS must be at least 1" >&2
  exit 2
fi

for SERVER in rustfs seaweedfs minio flyology-memory flyology-files flyology-sqlite
do
  RUN=1
  while [ "$RUN" -le "$REPEATS" ]
  do
    echo "S3 oracle matrix: $SERVER run $RUN/$REPEATS"
    case "$SERVER" in
      flyology-*) "$SCRIPT_DIR/test-flyology-server.sh" "${SERVER#flyology-}" ;;
      *) "$SCRIPT_DIR/test-$SERVER.sh" ;;
    esac
    RUN=$((RUN + 1))
  done
done

echo "S3 oracle matrix: all implementations and repetitions OK"
