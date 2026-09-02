#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/flyology-coverage-verifier.XXXXXX")
trap 'case "$TEMP_ROOT" in */flyology-coverage-verifier.*) rm -rf "$TEMP_ROOT" ;; esac' EXIT INT TERM

LEDGER="$TEMP_ROOT/aws-s3-operations.tsv"
OUTPUT="$TEMP_ROOT/output.txt"
awk -F '\t' '
  BEGIN { OFS="\t" }
  $1 == "SelectObjectContent" { $5="covered"; changed=1 }
  { print }
  END { if (!changed) exit 2 }
' "$PROJECT_DIR/coverage/aws-s3-operations.tsv" >"$LEDGER"

if COVERAGE_LEDGER="$LEDGER" \
  "$PROJECT_DIR/tools/verify-coverage.sh" >"$OUTPUT" 2>&1
then
  echo "coverage verifier accepted a ledger-only promotion" >&2
  exit 1
fi
if ! grep -Fq \
  "coverage ledger differs from reviewed evidence registry" "$OUTPUT"
then
  echo "coverage verifier rejected the fixture for the wrong reason" >&2
  cat "$OUTPUT" >&2
  exit 1
fi

echo "coverage verifier negative oracle: OK"
