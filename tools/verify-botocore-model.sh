#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 /path/to/service-2.json" >&2
  exit 2
fi

MODEL=$1
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LEDGER="$PROJECT_DIR/coverage/aws-s3-operations.tsv"
EXPECTED_SHA256=429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9

test -f "$MODEL"
test "$(shasum -a 256 "$MODEL" | cut -d ' ' -f 1)" = "$EXPECTED_SHA256"
test "$(jq -r '.operations | length' "$MODEL")" = 116

MODEL_OPERATIONS=$(mktemp)
LEDGER_OPERATIONS=$(mktemp)
trap 'rm -f "$MODEL_OPERATIONS" "$LEDGER_OPERATIONS"' EXIT

jq -r '.operations | keys[]' "$MODEL" > "$MODEL_OPERATIONS"
tail -n +2 "$LEDGER" | cut -f 1 > "$LEDGER_OPERATIONS"
diff -u "$MODEL_OPERATIONS" "$LEDGER_OPERATIONS"
"$PROJECT_DIR/tools/generate-s3-model.py" \
  "$MODEL" --output-dir "$PROJECT_DIR/src" --check

echo "botocore model: pinned hash, 116 operations, and generated schema match"
