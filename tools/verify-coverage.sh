#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LEDGER="$PROJECT_DIR/coverage/aws-s3-operations.tsv"

test -s "$PROJECT_DIR/coverage/corpora.lock.toml"
"$PROJECT_DIR/tools/verify-corpora-lock.sh"
"$PROJECT_DIR/tools/verify-benchmark-plan.sh"
test "$(head -n 1 "$LEDGER")" = $'operation\ttier\tbackend\tclient\tserver\tcorpus'
tail -n +2 "$LEDGER" | cut -f1 | LC_ALL=C sort -c
test "$(tail -n +2 "$LEDGER" | cut -f1 | uniq -d | wc -l | tr -d ' ')" = 0
test "$(tail -n +2 "$LEDGER" | wc -l | tr -d ' ')" = 116

if awk -F '\t' 'NR > 1 && ($2 !~ /^(core|extended)$/ || $3 !~ /^(missing|partial|covered)$/ || $4 !~ /^(missing|partial|covered)$/ || $5 !~ /^(missing|partial|covered)$/ || $6 !~ /^(missing|partial|covered)$/) { exit 1 }' "$LEDGER"; then
  :
else
  echo "invalid coverage state" >&2
  exit 1
fi

echo "coverage ledger: 116 pinned S3 operations"
