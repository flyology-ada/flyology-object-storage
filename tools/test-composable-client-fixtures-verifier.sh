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
  cp "$SOURCE_DIR/range-get.tsv" "$WORK_DIR/range.tsv"
  cp "$SOURCE_DIR/head-object.tsv" "$WORK_DIR/head.tsv"
  cp "$SOURCE_DIR/delete-certainty.tsv" "$WORK_DIR/delete.tsv"
  cp "$SOURCE_DIR/create-multipart-certainty.tsv" "$WORK_DIR/create.tsv"
  cp "$SOURCE_DIR/upload-part-certainty.tsv" "$WORK_DIR/upload.tsv"
  cp "$SOURCE_DIR/complete-multipart-certainty.tsv" "$WORK_DIR/complete.tsv"
  cp "$SOURCE_DIR/abort-multipart-certainty.tsv" "$WORK_DIR/abort.tsv"
  cp "$SOURCE_DIR/copy-certainty.tsv" "$WORK_DIR/copy.tsv"
  cp "$SOURCE_DIR/object-tagging-certainty.tsv" "$WORK_DIR/tagging.tsv"
}

expect_rejection() {
  label=$1
  if "$VERIFIER" "$WORK_DIR/put.tsv" "$WORK_DIR/parent.tsv" \
      "$WORK_DIR/range.tsv" "$WORK_DIR/head.tsv" "$WORK_DIR/delete.tsv" \
      "$WORK_DIR/create.tsv" "$WORK_DIR/upload.tsv" \
      "$WORK_DIR/complete.tsv" "$WORK_DIR/abort.tsv" \
      "$WORK_DIR/copy.tsv" "$WORK_DIR/tagging.tsv" \
      >"$WORK_DIR/stdout" 2>"$WORK_DIR/stderr"; then
    printf '%s\n' "verifier accepted invalid fixture: $label" >&2
    exit 1
  fi
  if [ ! -s "$WORK_DIR/stderr" ]; then
    printf '%s\n' "verifier rejected $label without a diagnostic" >&2
    exit 1
  fi
}

install_tagging_mutation() {
  original=$1
  candidate=$2
  label=$3
  if cmp -s "$original" "$candidate"; then
    printf '%s\n' "object-tagging mutation changed no row: $label" >&2
    exit 1
  fi
  mv "$candidate" "$original"
}

reset_fixtures
"$VERIFIER" "$WORK_DIR/put.tsv" "$WORK_DIR/parent.tsv" \
  "$WORK_DIR/range.tsv" "$WORK_DIR/head.tsv" \
  "$WORK_DIR/delete.tsv" "$WORK_DIR/create.tsv" \
  "$WORK_DIR/upload.tsv" "$WORK_DIR/complete.tsv" \
  "$WORK_DIR/abort.tsv" "$WORK_DIR/copy.tsv" \
  "$WORK_DIR/tagging.tsv" >/dev/null

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

reset_fixtures
awk 'NR == 2 { duplicate = $0 } { print } END { print duplicate }' \
  "$WORK_DIR/range.tsv" >"$WORK_DIR/mutated.tsv"
mv "$WORK_DIR/mutated.tsv" "$WORK_DIR/range.tsv"
expect_rejection "duplicate range-Get case"

reset_fixtures
awk -F '\t' '$1 != "HD-RS-002"' "$WORK_DIR/head.tsv" \
  >"$WORK_DIR/mutated.tsv"
mv "$WORK_DIR/mutated.tsv" "$WORK_DIR/head.tsv"
expect_rejection "missing HeadObject body handling case"

reset_fixtures
awk 'NR == 2 { duplicate = $0 } { print } END { print duplicate }' \
  "$WORK_DIR/delete.tsv" >"$WORK_DIR/mutated.tsv"
mv "$WORK_DIR/mutated.tsv" "$WORK_DIR/delete.tsv"
expect_rejection "duplicate DeleteObject input tuple"

reset_fixtures
awk -F '\t' 'BEGIN { OFS = "\t" } $4 == "PreconditionFailed" { $4 = "missing" } { print }' \
  "$WORK_DIR/delete.tsv" >"$WORK_DIR/mutated.tsv"
mv "$WORK_DIR/mutated.tsv" "$WORK_DIR/delete.tsv"
expect_rejection "status-only DeleteObject precondition conclusion"

reset_fixtures
awk -F '\t' 'BEGIN { OFS = "\t" } $5 == "Deletion_Outcome_Unknown" && !done { $7 = "no"; done = 1 } { print }' \
  "$WORK_DIR/delete.tsv" >"$WORK_DIR/mutated.tsv"
mv "$WORK_DIR/mutated.tsv" "$WORK_DIR/delete.tsv"
expect_rejection "unknown deletion without reconciliation"

reset_fixtures
awk 'NR == 2 { duplicate = $0 } { print } END { print duplicate }' \
  "$WORK_DIR/create.tsv" >"$WORK_DIR/mutated.tsv"
mv "$WORK_DIR/mutated.tsv" "$WORK_DIR/create.tsv"
expect_rejection "duplicate CreateMultipartUpload input tuple"

reset_fixtures
awk -F '\t' 'BEGIN { OFS = "\t" } $5 == "Creation_Outcome_Unknown" && !done { $7 = "no"; done = 1 } { print }' \
  "$WORK_DIR/create.tsv" >"$WORK_DIR/mutated.tsv"
mv "$WORK_DIR/mutated.tsv" "$WORK_DIR/create.tsv"
expect_rejection "unknown creation without reconciliation"

reset_fixtures
awk -F '\t' 'BEGIN { OFS = "\t" } $4 == "InvalidRequest" { $4 = "missing" } { print }' \
  "$WORK_DIR/create.tsv" >"$WORK_DIR/mutated.tsv"
mv "$WORK_DIR/mutated.tsv" "$WORK_DIR/create.tsv"
expect_rejection "status-only CreateMultipartUpload rejection"

reset_fixtures
awk 'NR == 2 { duplicate = $0 } { print } END { print duplicate }' \
  "$WORK_DIR/upload.tsv" >"$WORK_DIR/mutated.tsv"
mv "$WORK_DIR/mutated.tsv" "$WORK_DIR/upload.tsv"
expect_rejection "duplicate UploadPart input tuple"

reset_fixtures
awk -F '\t' 'BEGIN { OFS = "\t" } $5 == "Part_Outcome_Unknown" && !done { $7 = "no"; done = 1 } { print }' \
  "$WORK_DIR/upload.tsv" >"$WORK_DIR/mutated.tsv"
mv "$WORK_DIR/mutated.tsv" "$WORK_DIR/upload.tsv"
expect_rejection "unknown UploadPart publication without reconciliation"

reset_fixtures
awk -F '\t' 'BEGIN { OFS = "\t" } $4 == "BadDigest" { $5 = "Definitely_Not_Staged" } { print }' \
  "$WORK_DIR/upload.tsv" >"$WORK_DIR/mutated.tsv"
mv "$WORK_DIR/mutated.tsv" "$WORK_DIR/upload.tsv"
expect_rejection "modeled UploadPart rejection treated as conclusive"

reset_fixtures
awk 'NR == 2 { duplicate = $0 } { print } END { print duplicate }' \
  "$WORK_DIR/complete.tsv" >"$WORK_DIR/mutated.tsv"
mv "$WORK_DIR/mutated.tsv" "$WORK_DIR/complete.tsv"
expect_rejection "duplicate CompleteMultipartUpload input tuple"

reset_fixtures
awk -F '\t' 'BEGIN { OFS = "\t" } $5 == "Completion_Outcome_Unknown" && !done { $7 = "no"; done = 1 } { print }' \
  "$WORK_DIR/complete.tsv" >"$WORK_DIR/mutated.tsv"
mv "$WORK_DIR/mutated.tsv" "$WORK_DIR/complete.tsv"
expect_rejection "unknown completion publication without reconciliation"

reset_fixtures
awk -F '\t' 'BEGIN { OFS = "\t" } $4 == "InternalError" { $5 = "Definitely_Not_Completed" } { print }' \
  "$WORK_DIR/complete.tsv" >"$WORK_DIR/mutated.tsv"
mv "$WORK_DIR/mutated.tsv" "$WORK_DIR/complete.tsv"
expect_rejection "embedded completion error treated as conclusive"

reset_fixtures
awk 'NR == 2 { duplicate = $0 } { print } END { print duplicate }' \
  "$WORK_DIR/abort.tsv" >"$WORK_DIR/mutated.tsv"
mv "$WORK_DIR/mutated.tsv" "$WORK_DIR/abort.tsv"
expect_rejection "duplicate AbortMultipartUpload input tuple"

reset_fixtures
awk -F '\t' 'BEGIN { OFS = "\t" } $5 == "Abort_Outcome_Unknown" && !done { $7 = "no"; done = 1 } { print }' \
  "$WORK_DIR/abort.tsv" >"$WORK_DIR/mutated.tsv"
mv "$WORK_DIR/mutated.tsv" "$WORK_DIR/abort.tsv"
expect_rejection "unknown abort outcome without reconciliation"

reset_fixtures
awk -F '\t' 'BEGIN { OFS = "\t" } $4 == "NoSuchUpload" { $5 = "Definitely_Not_Aborted" } { print }' \
  "$WORK_DIR/abort.tsv" >"$WORK_DIR/mutated.tsv"
mv "$WORK_DIR/mutated.tsv" "$WORK_DIR/abort.tsv"
expect_rejection "modeled abort rejection treated as conclusive"

reset_fixtures
awk 'NR == 2 { duplicate = $0 } { print } END { print duplicate }' \
  "$WORK_DIR/copy.tsv" >"$WORK_DIR/mutated.tsv"
mv "$WORK_DIR/mutated.tsv" "$WORK_DIR/copy.tsv"
expect_rejection "duplicate CopyObject input tuple"

reset_fixtures
awk -F '\t' 'BEGIN { OFS = "\t" }
  $4 == "ObjectNotInActiveTierError" { $6 = "Authorization_Failed" }
  { print }' "$WORK_DIR/copy.tsv" >"$WORK_DIR/mutated.tsv"
mv "$WORK_DIR/mutated.tsv" "$WORK_DIR/copy.tsv"
expect_rejection "misclassified CopyObject modeled error"

reset_fixtures
awk -F '\t' 'BEGIN { OFS = "\t" }
  $5 == "Outcome_Unknown" && !done { $7 = "no"; done = 1 }
  { print }' "$WORK_DIR/copy.tsv" >"$WORK_DIR/mutated.tsv"
mv "$WORK_DIR/mutated.tsv" "$WORK_DIR/copy.tsv"
expect_rejection "unknown CopyObject outcome without reconciliation"

reset_fixtures
awk 'NR == 2 { duplicate = $0 } { print } END { print duplicate }' \
  "$WORK_DIR/tagging.tsv" >"$WORK_DIR/mutated.tsv"
install_tagging_mutation "$WORK_DIR/tagging.tsv" \
  "$WORK_DIR/mutated.tsv" "duplicate exact tuple"
expect_rejection "duplicate object-tagging input tuple"

reset_fixtures
awk -F '\t' 'BEGIN { OFS = "\t" }
  $1 == "GetObjectTagging" && !done {
    $6 = "Object_Tag_Mutation_Completed"; done = 1
  }
  { print }' "$WORK_DIR/tagging.tsv" >"$WORK_DIR/mutated.tsv"
install_tagging_mutation "$WORK_DIR/tagging.tsv" \
  "$WORK_DIR/mutated.tsv" "Get mutation certainty"
expect_rejection "GetObjectTagging mutation certainty"

reset_fixtures
awk -F '\t' 'NR != 2' "$WORK_DIR/tagging.tsv" \
  >"$WORK_DIR/mutated.tsv"
install_tagging_mutation "$WORK_DIR/tagging.tsv" \
  "$WORK_DIR/mutated.tsv" "missing exact tuple"
expect_rejection "missing exact object-tagging tuple"

reset_fixtures
awk '1; END { print "UnknownTagging\tCancelled\tNot_Admitted\tnone\tnone\t" \
  "not-applicable\tCancelled\tno\texplicit-or-omitted\tunknown" }' \
  "$WORK_DIR/tagging.tsv" >"$WORK_DIR/mutated.tsv"
install_tagging_mutation "$WORK_DIR/tagging.tsv" \
  "$WORK_DIR/mutated.tsv" "extra unknown tuple"
expect_rejection "extra unknown object-tagging tuple"

reset_fixtures
awk -F '\t' 'BEGIN { OFS = "\t" }
  $2 == "Connection_Failed" && !done { $3 = "Possibly_Admitted"; done = 1 }
  { print } END { if (!done) exit 2 }' "$WORK_DIR/tagging.tsv" \
  >"$WORK_DIR/mutated.tsv"
install_tagging_mutation "$WORK_DIR/tagging.tsv" \
  "$WORK_DIR/mutated.tsv" "invalid admission pairing"
expect_rejection "invalid object-tagging admission pairing"

reset_fixtures
awk -F '\t' 'BEGIN { OFS = "\t" }
  $2 == "Timed_Out" && !done { $7 = "Cancelled"; done = 1 }
  { print } END { if (!done) exit 2 }' "$WORK_DIR/tagging.tsv" \
  >"$WORK_DIR/mutated.tsv"
install_tagging_mutation "$WORK_DIR/tagging.tsv" \
  "$WORK_DIR/mutated.tsv" "wrong failure reason"
expect_rejection "wrong object-tagging failure reason"

reset_fixtures
awk -F '\t' 'BEGIN { OFS = "\t" }
  $6 == "Object_Tag_Mutation_Outcome_Unknown" && !done {
    $6 = "Object_Tag_Mutation_Definitely_Not_Applied"; $8 = "no"; done = 1
  } { print } END { if (!done) exit 2 }' "$WORK_DIR/tagging.tsv" \
  >"$WORK_DIR/mutated.tsv"
install_tagging_mutation "$WORK_DIR/tagging.tsv" \
  "$WORK_DIR/mutated.tsv" "wrong disposition relation"
expect_rejection "wrong object-tagging disposition relation"

reset_fixtures
awk -F '\t' 'BEGIN { OFS = "\t" }
  $1 == "DeleteObjectTagging" && $5 == "InvalidDigest" && !done {
    $6 = "Object_Tag_Mutation_Definitely_Not_Applied";
    $7 = "Invalid_Request"; $8 = "no"; done = 1
  } { print } END { if (!done) exit 2 }' "$WORK_DIR/tagging.tsv" \
  >"$WORK_DIR/mutated.tsv"
install_tagging_mutation "$WORK_DIR/tagging.tsv" \
  "$WORK_DIR/mutated.tsv" "Put-only code leakage"
expect_rejection "Put-only object-tagging code leakage"

printf '%s\n' "composable client fixture verifier self-tests: OK"
