#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
VERIFIER="$SCRIPT_DIR/verify-composable-client-fixtures.sh"
SOURCE_DIR="$PROJECT_DIR/tests/corpora/composable-client"
WORK_DIR=$(mktemp -d /tmp/flyology-composable-verifier.XXXXXX)

cleanup() {
  case "$WORK_DIR" in
    /tmp/flyology-composable-verifier.*) rm -rf "$WORK_DIR" ;;
    *) printf '%s\n' "refusing unsafe cleanup: $WORK_DIR" >&2 ;;
  esac
}
trap cleanup EXIT INT TERM

reset_fixtures() {
  cp "$SOURCE_DIR/put-certainty.tsv" "$WORK_DIR/put.tsv"
  cp "$SOURCE_DIR/parent-faults.tsv" "$WORK_DIR/parent.tsv"
}

expect_rejection() {
  label=$1
  if "$VERIFIER" "$WORK_DIR/put.tsv" "$WORK_DIR/parent.tsv" \
      >"$WORK_DIR/stdout" 2>"$WORK_DIR/stderr"; then
    printf '%s\n' "verifier accepted invalid fixture: $label" >&2
    exit 1
  fi
  if [ ! -s "$WORK_DIR/stderr" ]; then
    printf '%s\n' "verifier rejected $label without a diagnostic" >&2
    exit 1
  fi
}

reset_fixtures
"$VERIFIER" "$WORK_DIR/put.tsv" "$WORK_DIR/parent.tsv" >/dev/null

reset_fixtures
awk 'NR == 2 { duplicate = $0 } { print } END { print duplicate }' \
  "$WORK_DIR/put.tsv" >"$WORK_DIR/mutated.tsv"
mv "$WORK_DIR/mutated.tsv" "$WORK_DIR/put.tsv"
expect_rejection "duplicate Put input tuple"

reset_fixtures
awk -F '\t' 'BEGIN { OFS = "\t" } NR == 2 { $3 = "201" } { print }' \
  "$WORK_DIR/put.tsv" >"$WORK_DIR/mutated.tsv"
mv "$WORK_DIR/mutated.tsv" "$WORK_DIR/put.tsv"
expect_rejection "Published without valid 200"

reset_fixtures
awk -F '\t' 'BEGIN { OFS = "\t" } $5 == "Outcome_Unknown" && !done { $7 = "no"; done = 1 } { print }' \
  "$WORK_DIR/put.tsv" >"$WORK_DIR/mutated.tsv"
mv "$WORK_DIR/mutated.tsv" "$WORK_DIR/put.tsv"
expect_rejection "unknown outcome without reconciliation"

reset_fixtures
awk -F '\t' 'BEGIN { OFS = "\t" } $4 == "ConditionalRequestConflict" { $5 = "Unavailable_Or_Retryable" } { print }' \
  "$WORK_DIR/put.tsv" >"$WORK_DIR/mutated.tsv"
mv "$WORK_DIR/mutated.tsv" "$WORK_DIR/put.tsv"
expect_rejection "failure reason collapsed into publication disposition"

reset_fixtures
awk -F '\t' 'BEGIN { OFS = "\t" } $4 == "PreconditionFailed" { $4 = "missing" } { print }' \
  "$WORK_DIR/put.tsv" >"$WORK_DIR/mutated.tsv"
mv "$WORK_DIR/mutated.tsv" "$WORK_DIR/put.tsv"
expect_rejection "status-only precondition conclusion"

reset_fixtures
awk -F '\t' '$1 != "Response_Sink_Failed"' "$WORK_DIR/put.tsv" \
  >"$WORK_DIR/mutated.tsv"
mv "$WORK_DIR/mutated.tsv" "$WORK_DIR/put.tsv"
expect_rejection "missing required HTTP result"

reset_fixtures
awk 'NR == 2 { duplicate = $0 } { print } END { print duplicate }' \
  "$WORK_DIR/parent.tsv" >"$WORK_DIR/mutated.tsv"
mv "$WORK_DIR/mutated.tsv" "$WORK_DIR/parent.tsv"
expect_rejection "duplicate parent-fault case"

reset_fixtures
awk -F '\t' '$1 != "abandon-parent"' "$WORK_DIR/parent.tsv" \
  >"$WORK_DIR/mutated.tsv"
mv "$WORK_DIR/mutated.tsv" "$WORK_DIR/parent.tsv"
expect_rejection "missing parent drain case"

reset_fixtures
awk -F '\t' 'BEGIN { OFS = "\t" } $1 == "readiness-fan-in-bound" { $4 = "arm-first-four" } { print }' \
  "$WORK_DIR/parent.tsv" >"$WORK_DIR/mutated.tsv"
mv "$WORK_DIR/mutated.tsv" "$WORK_DIR/parent.tsv"
expect_rejection "truncated source and transport fan-in"

printf '%s\n' "composable client fixture verifier self-tests: OK"
