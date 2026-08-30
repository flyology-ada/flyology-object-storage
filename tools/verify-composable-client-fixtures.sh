#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
PUT_FIXTURE=${1:-"$PROJECT_DIR/tests/corpora/composable-client/put-certainty.tsv"}
PARENT_FIXTURE=${2:-"$PROJECT_DIR/tests/corpora/composable-client/parent-faults.tsv"}
RANGE_FIXTURE=${3:-"$PROJECT_DIR/tests/corpora/composable-client/range-get.tsv"}
HEAD_FIXTURE=${4:-"$PROJECT_DIR/tests/corpora/composable-client/head-object.tsv"}
DELETE_FIXTURE=${5:-"$PROJECT_DIR/tests/corpora/composable-client/delete-certainty.tsv"}
CREATE_FIXTURE=${6:-"$PROJECT_DIR/tests/corpora/composable-client/create-multipart-certainty.tsv"}
UPLOAD_FIXTURE=${7:-"$PROJECT_DIR/tests/corpora/composable-client/upload-part-certainty.tsv"}
COMPLETE_FIXTURE=${8:-"$PROJECT_DIR/tests/corpora/composable-client/complete-multipart-certainty.tsv"}
ABORT_FIXTURE=${9:-"$PROJECT_DIR/tests/corpora/composable-client/abort-multipart-certainty.tsv"}
COPY_FIXTURE=${10:-"$PROJECT_DIR/tests/corpora/composable-client/copy-certainty.tsv"}
TAGGING_FIXTURE=${11:-"$PROJECT_DIR/tests/corpora/composable-client/object-tagging-certainty.tsv"}
DELETE_OBJECTS_FIXTURE=${12:-"$PROJECT_DIR/tests/corpora/"\
"composable-client/delete-objects-certainty.tsv"}

if [ ! -f "$PUT_FIXTURE" ]; then
  printf '%s\n' "missing Put fixture: $PUT_FIXTURE" >&2
  exit 1
fi
if [ ! -f "$PARENT_FIXTURE" ]; then
  printf '%s\n' "missing parent-fault fixture: $PARENT_FIXTURE" >&2
  exit 1
fi
if [ ! -f "$RANGE_FIXTURE" ]; then
  printf '%s\n' "missing range-Get fixture: $RANGE_FIXTURE" >&2
  exit 1
fi
if [ ! -f "$HEAD_FIXTURE" ]; then
  printf '%s\n' "missing HeadObject fixture: $HEAD_FIXTURE" >&2
  exit 1
fi
if [ ! -f "$DELETE_FIXTURE" ]; then
  printf '%s\n' "missing DeleteObject fixture: $DELETE_FIXTURE" >&2
  exit 1
fi
if [ ! -f "$CREATE_FIXTURE" ]; then
  printf '%s\n' "missing CreateMultipartUpload fixture: $CREATE_FIXTURE" >&2
  exit 1
fi
if [ ! -f "$UPLOAD_FIXTURE" ]; then
  printf '%s\n' "missing UploadPart fixture: $UPLOAD_FIXTURE" >&2
  exit 1
fi
if [ ! -f "$COMPLETE_FIXTURE" ]; then
  printf '%s\n' "missing CompleteMultipartUpload fixture: $COMPLETE_FIXTURE" >&2
  exit 1
fi
if [ ! -f "$ABORT_FIXTURE" ]; then
  printf '%s\n' "missing AbortMultipartUpload fixture: $ABORT_FIXTURE" >&2
  exit 1
fi
if [ ! -f "$COPY_FIXTURE" ]; then
  printf '%s\n' "missing CopyObject fixture: $COPY_FIXTURE" >&2
  exit 1
fi
if [ ! -f "$TAGGING_FIXTURE" ]; then
  printf '%s\n' "missing object-tagging fixture: $TAGGING_FIXTURE" >&2
  exit 1
fi
if [ ! -f "$DELETE_OBJECTS_FIXTURE" ]; then
  printf '%s\n' "missing DeleteObjects fixture: $DELETE_OBJECTS_FIXTURE" >&2
  exit 1
fi

awk -F '\t' '
function fail(message) {
  print FILENAME ":" NR ": " message > "/dev/stderr"
  failed = 1
}

function exact_complete(status, code, publication, reason) {
  return $1 == "Response_Complete" && $2 == "Response_Observed" &&
    $3 == status && $4 == code && $5 == publication &&
    $6 == reason
}

function modeled_invalid_request(code) {
  return code == "InvalidRequest" || code == "InvalidWriteOffset" ||
    code == "TooManyParts" || code == "EncryptionTypeMismatch"
}

BEGIN {
  split("Response_Complete Pre_Admission_Rejected Cancelled Timed_Out Client_Unavailable Connection_Failed Transport_Failed Request_Source_Failed Response_Invalid Response_Body_Too_Large Response_Sink_Failed", values, " ")
  for (i in values) allowed_http[values[i]] = 1
  split("Not_Admitted Possibly_Admitted Response_Observed", values, " ")
  for (i in values) allowed_admission[values[i]] = 1
  split("200 400 401 403 404 409 412 429 500 502 503 504 none incomplete invalid oversized overflow-or-fault", values, " ")
  for (i in values) allowed_status[values[i]] = 1
  split("none InvalidRequest InvalidWriteOffset TooManyParts EncryptionTypeMismatch InvalidAccessKeyId AccessDenied NoSuchBucket ConditionalRequestConflict PreconditionFailed SlowDown InternalError BadGateway RequestTimeout missing malformed not-applicable", values, " ")
  for (i in values) allowed_code[values[i]] = 1
  split("Published Precondition_Failed Definitely_Not_Published Outcome_Unknown Cancelled_Before_Publication", values, " ")
  for (i in values) allowed_publication[values[i]] = 1
  split("None Authentication_Failed Authorization_Failed Invalid_Request Not_Found Unavailable_Or_Retryable Cancelled Timed_Out Client_Unavailable Connection_Failed Transport_Failed Request_Source_Failed Corrupt_Or_Invalid_Response", values, " ")
  for (i in values) allowed_reason[values[i]] = 1
  expected_reason["Pre_Admission_Rejected"] = "Invalid_Request"
  expected_reason["Cancelled"] = "Cancelled"
  expected_reason["Timed_Out"] = "Timed_Out"
  expected_reason["Client_Unavailable"] = "Client_Unavailable"
  expected_reason["Connection_Failed"] = "Connection_Failed"
  expected_reason["Transport_Failed"] = "Transport_Failed"
  expected_reason["Request_Source_Failed"] = "Request_Source_Failed"
  expected_reason["Response_Invalid"] = "Corrupt_Or_Invalid_Response"
  expected_reason["Response_Body_Too_Large"] = "Corrupt_Or_Invalid_Response"
  expected_reason["Response_Sink_Failed"] = "Corrupt_Or_Invalid_Response"
}

NR == 1 {
  if (NF != 8 || $1 != "http_result" || $2 != "admission" ||
      $3 != "status" || $4 != "s3_code" ||
      $5 != "publication" || $6 != "failure_reason" ||
      $7 != "reconcile" || $8 != "note")
    fail("unexpected Put fixture header")
  next
}

{
  if (NF != 8) fail("expected 8 tab-separated fields, got " NF)
  if (!($1 in allowed_http)) fail("unknown HTTP result " $1)
  if (!($2 in allowed_admission)) fail("unknown admission certainty " $2)
  if (!($3 in allowed_status)) fail("unknown response status " $3)
  if (!($4 in allowed_code)) fail("unknown S3 error code " $4)
  if (!($5 in allowed_publication))
    fail("unknown publication disposition " $5)
  if (!($6 in allowed_reason)) fail("unknown bounded failure reason " $6)
  if ($7 != "yes" && $7 != "no") fail("reconcile must be yes or no")
  if ($8 == "") fail("qualification note must not be empty")

  key = $1 SUBSEP $2 SUBSEP $3 SUBSEP $4
  if (key in seen) fail("duplicate input tuple")
  seen[key] = 1
  result_seen[$1] = 1
  semantic_seen[$3 SUBSEP $4] = 1

  if ($2 == "Not_Admitted" && $5 == "Outcome_Unknown")
    fail("Not_Admitted cannot map to Outcome_Unknown")
  if ($5 == "Outcome_Unknown" && $7 != "yes")
    fail("Outcome_Unknown requires reconciliation")
  if ($5 != "Outcome_Unknown" && $7 != "no")
    fail("conclusive publication disposition must not require reconciliation")
  if ($6 == "None" &&
      $5 != "Published" && $5 != "Precondition_Failed")
    fail("None is only valid for successful or precondition dispositions")

  if ($5 == "Published" &&
      !exact_complete("200", "none", "Published", "None"))
    fail("Published requires a complete valid 200 response")
  if ($5 == "Precondition_Failed" &&
      !exact_complete("412", "PreconditionFailed",
                      "Precondition_Failed", "None"))
    fail("Precondition_Failed requires exact parsed S3 semantics")
  if ($5 == "Cancelled_Before_Publication" &&
      !($1 == "Cancelled" && $2 == "Not_Admitted" &&
        $6 == "Cancelled"))
    fail("cancelled-before-publication requires pre-admission cancellation")

  if ($6 == "Authentication_Failed" &&
      !exact_complete("401", "InvalidAccessKeyId",
                      "Definitely_Not_Published", "Authentication_Failed"))
    fail("authentication rejection requires exact modeled S3 semantics")
  if ($6 == "Authorization_Failed" &&
      !exact_complete("403", "AccessDenied",
                      "Definitely_Not_Published", "Authorization_Failed"))
    fail("authorization rejection requires exact modeled S3 semantics")
  if ($6 == "Invalid_Request" && $1 == "Response_Complete" &&
      !($2 == "Response_Observed" && $3 == "400" &&
        modeled_invalid_request($4) &&
        $5 == "Definitely_Not_Published" && $6 == "Invalid_Request"))
    fail("service invalid request requires exact modeled S3 semantics")
  if ($6 == "Not_Found" &&
      !exact_complete("404", "NoSuchBucket",
                      "Definitely_Not_Published", "Not_Found"))
    fail("missing destination requires exact modeled S3 semantics")
  if ($6 == "Unavailable_Or_Retryable" &&
      !($1 == "Response_Complete" && $2 == "Response_Observed" &&
        $5 == "Outcome_Unknown" && $7 == "yes" &&
        (($3 == "409" && $4 == "ConditionalRequestConflict") ||
         ($3 == "429" && $4 == "SlowDown") ||
         ($3 == "500" && $4 == "InternalError") ||
         ($3 == "502" && $4 == "BadGateway") ||
         ($3 == "503" && $4 == "SlowDown") ||
         ($3 == "504" && $4 == "RequestTimeout"))) )
    fail("retryable reason must preserve unknown publication disposition")
  if ($6 == "Corrupt_Or_Invalid_Response" &&
      (($2 == "Not_Admitted" && $5 != "Definitely_Not_Published") ||
       ($2 != "Not_Admitted" && $5 != "Outcome_Unknown")))
    fail("corrupt response reason must preserve admission-based disposition")

  if ($1 in expected_reason && $6 != expected_reason[$1])
    fail("HTTP result does not retain its bounded failure reason")
  if ($1 == "Response_Complete" && $2 != "Response_Observed")
    fail("Response_Complete requires Response_Observed certainty")
  if ($2 == "Response_Observed" && $1 == "Pre_Admission_Rejected")
    fail("pre-admission rejection cannot observe a response")
}

END {
  split("Response_Complete Pre_Admission_Rejected Cancelled Timed_Out Client_Unavailable Connection_Failed Transport_Failed Request_Source_Failed Response_Invalid Response_Body_Too_Large Response_Sink_Failed", required, " ")
  for (i in required)
    if (!(required[i] in result_seen))
      fail("missing HTTP result coverage for " required[i])
  split("200:none 400:InvalidRequest 400:InvalidWriteOffset 400:TooManyParts 400:EncryptionTypeMismatch 401:InvalidAccessKeyId 403:AccessDenied 404:NoSuchBucket 409:ConditionalRequestConflict 412:PreconditionFailed 429:SlowDown 500:InternalError 502:BadGateway 503:SlowDown 504:RequestTimeout 400:missing 403:missing 404:missing 412:missing 500:malformed", required, " ")
  for (i in required) {
    split(required[i], pair, ":")
    if (!(pair[1] SUBSEP pair[2] in semantic_seen))
      fail("missing exact status/code coverage for " required[i])
  }
  if (NR - 1 < 44) fail("Put fixture is unexpectedly small")
  exit failed
}
' "$PUT_FIXTURE"

awk -F '\t' '
function fail(message) {
  print FILENAME ":" NR ": " message > "/dev/stderr"
  failed = 1
}

function exact_complete(status, code, deletion, reason) {
  return $1 == "Response_Complete" && $2 == "Response_Observed" &&
    $3 == status && $4 == code && $5 == deletion && $6 == reason
}

BEGIN {
  split("Response_Complete Pre_Admission_Rejected Cancelled Timed_Out Client_Unavailable Connection_Failed Transport_Failed Request_Source_Failed Response_Invalid Response_Body_Too_Large Response_Sink_Failed", values, " ")
  for (i in values) allowed_http[values[i]] = 1
  split("Not_Admitted Possibly_Admitted Response_Observed", values, " ")
  for (i in values) allowed_admission[values[i]] = 1
  split("204 400 401 403 404 409 412 429 500 502 503 504 none incomplete invalid oversized overflow-or-fault", values, " ")
  for (i in values) allowed_status[values[i]] = 1
  split("none InvalidRequest InvalidAccessKeyId AccessDenied NoSuchBucket NoSuchKey NoSuchVersion OperationAborted PreconditionFailed SlowDown InternalError BadGateway RequestTimeout missing malformed not-applicable", values, " ")
  for (i in values) allowed_code[values[i]] = 1
  split("Deletion_Completed Definitely_Not_Deleted Deletion_Outcome_Unknown Deletion_Cancelled_Before_Admission", values, " ")
  for (i in values) allowed_deletion[values[i]] = 1
  split("No_Failure Authentication_Failed Authorization_Failed Invalid_Request Not_Found Unavailable_Or_Retryable Cancelled Timed_Out Client_Unavailable Connection_Failed Transport_Failed Request_Source_Failed Corrupt_Or_Invalid_Response", values, " ")
  for (i in values) allowed_reason[values[i]] = 1
  expected_reason["Pre_Admission_Rejected"] = "Invalid_Request"
  expected_reason["Cancelled"] = "Cancelled"
  expected_reason["Timed_Out"] = "Timed_Out"
  expected_reason["Client_Unavailable"] = "Client_Unavailable"
  expected_reason["Connection_Failed"] = "Connection_Failed"
  expected_reason["Transport_Failed"] = "Transport_Failed"
  expected_reason["Request_Source_Failed"] = "Request_Source_Failed"
  expected_reason["Response_Invalid"] = "Corrupt_Or_Invalid_Response"
  expected_reason["Response_Body_Too_Large"] = "Corrupt_Or_Invalid_Response"
  expected_reason["Response_Sink_Failed"] = "Corrupt_Or_Invalid_Response"
}

NR == 1 {
  if (NF != 8 || $1 != "http_result" || $2 != "admission" ||
      $3 != "status" || $4 != "s3_code" || $5 != "deletion" ||
      $6 != "failure_reason" || $7 != "reconcile" || $8 != "note")
    fail("unexpected DeleteObject fixture header")
  next
}

{
  if (NF != 8) fail("expected 8 tab-separated fields, got " NF)
  if (!($1 in allowed_http)) fail("unknown HTTP result " $1)
  if (!($2 in allowed_admission)) fail("unknown admission certainty " $2)
  if (!($3 in allowed_status)) fail("unknown response status " $3)
  if (!($4 in allowed_code)) fail("unknown S3 error code " $4)
  if (!($5 in allowed_deletion)) fail("unknown deletion disposition " $5)
  if (!($6 in allowed_reason)) fail("unknown bounded failure reason " $6)
  if ($7 != "yes" && $7 != "no") fail("reconcile must be yes or no")
  if ($8 == "") fail("qualification note must not be empty")

  key = $1 SUBSEP $2 SUBSEP $3 SUBSEP $4
  if (key in seen) fail("duplicate DeleteObject input tuple")
  seen[key] = 1
  result_seen[$1] = 1
  semantic_seen[$3 SUBSEP $4] = 1

  if ($2 == "Not_Admitted" && $5 == "Deletion_Outcome_Unknown")
    fail("Not_Admitted cannot map to unknown deletion")
  if ($5 == "Deletion_Outcome_Unknown" && $7 != "yes")
    fail("unknown deletion requires reconciliation")
  if ($5 != "Deletion_Outcome_Unknown" && $7 != "no")
    fail("conclusive deletion disposition must not require reconciliation")
  if ($6 == "No_Failure" &&
      $5 != "Deletion_Completed" &&
      !exact_complete("412", "PreconditionFailed",
                      "Definitely_Not_Deleted", "No_Failure"))
    fail("No_Failure is only valid for success or exact precondition failure")

  if ($5 == "Deletion_Completed" &&
      !exact_complete("204", "none", "Deletion_Completed", "No_Failure"))
    fail("Deletion_Completed requires a complete valid 204 response")
  if ($5 == "Deletion_Cancelled_Before_Admission" &&
      !($1 == "Cancelled" && $2 == "Not_Admitted" && $6 == "Cancelled"))
    fail("cancelled-before-admission requires pre-admission cancellation")
  if ($5 == "Definitely_Not_Deleted" && $2 != "Not_Admitted" &&
      !(exact_complete("400", "InvalidRequest", $5, "Invalid_Request") ||
        exact_complete("401", "InvalidAccessKeyId", $5,
                       "Authentication_Failed") ||
        exact_complete("403", "AccessDenied", $5,
                       "Authorization_Failed") ||
        exact_complete("404", "NoSuchBucket", $5, "Not_Found") ||
        exact_complete("404", "NoSuchKey", $5, "Not_Found") ||
        exact_complete("404", "NoSuchVersion", $5, "Not_Found") ||
        exact_complete("412", "PreconditionFailed", $5, "No_Failure")))
    fail("definite rejection lacks exact modeled semantics")

  if ($6 == "Unavailable_Or_Retryable" &&
      !($1 == "Response_Complete" && $2 == "Response_Observed" &&
        $5 == "Deletion_Outcome_Unknown" && $7 == "yes" &&
        (($3 == "409" && $4 == "OperationAborted") ||
         ($3 == "429" && $4 == "SlowDown") ||
         ($3 == "500" && $4 == "InternalError") ||
         ($3 == "502" && $4 == "BadGateway") ||
         ($3 == "503" && $4 == "SlowDown") ||
         ($3 == "504" && $4 == "RequestTimeout"))))
    fail("retryable reason must preserve unknown deletion disposition")
  if ($1 in expected_reason && $6 != expected_reason[$1])
    fail("HTTP result does not retain its bounded failure reason")
  if ($1 == "Response_Complete" && $2 != "Response_Observed")
    fail("Response_Complete requires Response_Observed certainty")
}

END {
  split("Response_Complete Pre_Admission_Rejected Cancelled Timed_Out Client_Unavailable Connection_Failed Transport_Failed Request_Source_Failed Response_Invalid Response_Body_Too_Large Response_Sink_Failed", required, " ")
  for (i in required)
    if (!(required[i] in result_seen))
      fail("missing HTTP result coverage for " required[i])
  split("204:none 400:InvalidRequest 401:InvalidAccessKeyId 403:AccessDenied 404:NoSuchBucket 404:NoSuchKey 404:NoSuchVersion 409:OperationAborted 412:PreconditionFailed 429:SlowDown 500:InternalError 502:BadGateway 503:SlowDown 504:RequestTimeout 400:missing 403:missing 404:missing 412:missing 500:malformed", required, " ")
  for (i in required) {
    split(required[i], pair, ":")
    if (!(pair[1] SUBSEP pair[2] in semantic_seen))
      fail("missing exact status/code coverage for " required[i])
  }
  if (NR - 1 < 42) fail("DeleteObject fixture is unexpectedly small")
  exit failed
}
' "$DELETE_FIXTURE"

awk -F '\t' '
function fail(message) {
  print FILENAME ":" NR ": " message > "/dev/stderr"
  failed = 1
}

function exact_complete(status, code, creation, reason) {
  return $1 == "Response_Complete" && $2 == "Response_Observed" &&
    $3 == status && $4 == code && $5 == creation && $6 == reason
}

BEGIN {
  split("Response_Complete Pre_Admission_Rejected Cancelled Timed_Out Client_Unavailable Connection_Failed Transport_Failed Request_Source_Failed Response_Invalid Response_Body_Too_Large Response_Sink_Failed", values, " ")
  for (i in values) allowed_http[values[i]] = 1
  split("Not_Admitted Possibly_Admitted Response_Observed", values, " ")
  for (i in values) allowed_admission[values[i]] = 1
  split("200 400 401 403 404 409 429 500 502 503 504 none incomplete invalid oversized overflow-or-fault", values, " ")
  for (i in values) allowed_status[values[i]] = 1
  split("none InvalidRequest InvalidAccessKeyId AccessDenied NoSuchBucket OperationAborted SlowDown InternalError BadGateway RequestTimeout missing not-applicable", values, " ")
  for (i in values) allowed_code[values[i]] = 1
  split("Multipart_Upload_Created Definitely_Not_Created Creation_Outcome_Unknown Creation_Cancelled_Before_Admission", values, " ")
  for (i in values) allowed_creation[values[i]] = 1
  split("No_Failure Authentication_Failed Authorization_Failed Invalid_Request Not_Found Unavailable_Or_Retryable Cancelled Timed_Out Client_Unavailable Connection_Failed Transport_Failed Request_Source_Failed Corrupt_Or_Invalid_Response", values, " ")
  for (i in values) allowed_reason[values[i]] = 1
  expected_reason["Pre_Admission_Rejected"] = "Invalid_Request"
  expected_reason["Cancelled"] = "Cancelled"
  expected_reason["Timed_Out"] = "Timed_Out"
  expected_reason["Client_Unavailable"] = "Client_Unavailable"
  expected_reason["Connection_Failed"] = "Connection_Failed"
  expected_reason["Transport_Failed"] = "Transport_Failed"
  expected_reason["Request_Source_Failed"] = "Request_Source_Failed"
  expected_reason["Response_Invalid"] = "Corrupt_Or_Invalid_Response"
  expected_reason["Response_Body_Too_Large"] = "Corrupt_Or_Invalid_Response"
  expected_reason["Response_Sink_Failed"] = "Corrupt_Or_Invalid_Response"
}

NR == 1 {
  if (NF != 8 || $1 != "http_result" || $2 != "admission" ||
      $3 != "status" || $4 != "s3_code" || $5 != "creation" ||
      $6 != "failure_reason" || $7 != "reconcile" || $8 != "note")
    fail("unexpected CreateMultipartUpload fixture header")
  next
}

{
  if (NF != 8) fail("expected 8 tab-separated fields, got " NF)
  if (!($1 in allowed_http)) fail("unknown HTTP result " $1)
  if (!($2 in allowed_admission)) fail("unknown admission certainty " $2)
  if (!($3 in allowed_status)) fail("unknown response status " $3)
  if (!($4 in allowed_code)) fail("unknown S3 error code " $4)
  if (!($5 in allowed_creation)) fail("unknown creation disposition " $5)
  if (!($6 in allowed_reason)) fail("unknown bounded failure reason " $6)
  if ($7 != "yes" && $7 != "no") fail("reconcile must be yes or no")
  if ($8 == "") fail("qualification note must not be empty")

  key = $1 SUBSEP $2 SUBSEP $3 SUBSEP $4
  if (key in seen) fail("duplicate CreateMultipartUpload input tuple")
  seen[key] = 1
  result_seen[$1] = 1
  semantic_seen[$3 SUBSEP $4] = 1

  if ($2 == "Not_Admitted" && $5 == "Creation_Outcome_Unknown")
    fail("Not_Admitted cannot map to unknown creation")
  if ($5 == "Creation_Outcome_Unknown" && $7 != "yes")
    fail("unknown creation requires reconciliation")
  if ($5 != "Creation_Outcome_Unknown" && $7 != "no")
    fail("conclusive creation disposition must not require reconciliation")
  if ($5 == "Multipart_Upload_Created" &&
      !exact_complete("200", "none", $5, "No_Failure"))
    fail("creation success requires a complete valid 200 response")
  if ($5 == "Creation_Cancelled_Before_Admission" &&
      !($1 == "Cancelled" && $2 == "Not_Admitted" && $6 == "Cancelled"))
    fail("cancelled-before-admission requires pre-admission cancellation")
  if ($5 == "Definitely_Not_Created" && $2 != "Not_Admitted" &&
      !(exact_complete("400", "InvalidRequest", $5, "Invalid_Request") ||
        exact_complete("401", "InvalidAccessKeyId", $5,
                       "Authentication_Failed") ||
        exact_complete("403", "AccessDenied", $5,
                       "Authorization_Failed") ||
        exact_complete("404", "NoSuchBucket", $5, "Not_Found")))
    fail("definite rejection lacks exact modeled semantics")
  if ($6 == "Unavailable_Or_Retryable" &&
      !($1 == "Response_Complete" && $2 == "Response_Observed" &&
        $5 == "Creation_Outcome_Unknown" && $7 == "yes" &&
        (($3 == "409" && $4 == "OperationAborted") ||
         ($3 == "429" && $4 == "SlowDown") ||
         ($3 == "500" && $4 == "InternalError") ||
         ($3 == "502" && $4 == "BadGateway") ||
         ($3 == "503" && $4 == "SlowDown") ||
         ($3 == "504" && $4 == "RequestTimeout"))))
    fail("retryable reason must preserve unknown creation disposition")
  if ($1 in expected_reason && $6 != expected_reason[$1])
    fail("HTTP result does not retain its bounded failure reason")
  if ($1 == "Response_Complete" && $2 != "Response_Observed")
    fail("Response_Complete requires Response_Observed certainty")
}

END {
  split("Response_Complete Pre_Admission_Rejected Cancelled Timed_Out Client_Unavailable Connection_Failed Transport_Failed Request_Source_Failed Response_Invalid Response_Body_Too_Large Response_Sink_Failed", required, " ")
  for (i in required)
    if (!(required[i] in result_seen))
      fail("missing HTTP result coverage for " required[i])
  split("200:none 400:InvalidRequest 401:InvalidAccessKeyId 403:AccessDenied 404:NoSuchBucket 409:OperationAborted 429:SlowDown 500:InternalError 502:BadGateway 503:SlowDown 504:RequestTimeout 400:missing 403:missing 404:missing 500:SlowDown", required, " ")
  for (i in required) {
    split(required[i], pair, ":")
    if (!(pair[1] SUBSEP pair[2] in semantic_seen))
      fail("missing exact status/code coverage for " required[i])
  }
  if (NR - 1 < 45)
    fail("CreateMultipartUpload fixture is unexpectedly small")
  exit failed
}
' "$CREATE_FIXTURE"

awk -F '\t' '
function fail(message) {
  print FILENAME ":" NR ": " message > "/dev/stderr"
  failed = 1
}

NR == 1 {
  if (NF != 5 || $1 != "case" || $2 != "child_state" ||
      $3 != "event" || $4 != "parent_action" ||
      $5 != "required_observation")
    fail("unexpected parent-fault fixture header")
  next
}

{
  if (NF != 5) fail("expected 5 tab-separated fields, got " NF)
  for (field = 1; field <= 5; field++)
    if ($field == "") fail("parent-fault fields must not be empty")
  if ($1 in seen) fail("duplicate parent-fault case " $1)
  seen[$1] = 1
  if ($1 == "source-query-arm-race" &&
      !($2 == "source-needs-read" &&
        $3 == "readiness-between-query-and-arm" &&
        $4 == "arm-complete-readiness-set"))
    fail("source query-to-arm race must retain and arm latched readiness")
  if ($1 == "source-ready-now" &&
      !($3 == "query-returns-ready-now" &&
        $4 == "reschedule-without-arm"))
    fail("Ready_Now must reschedule without arming a descriptor")
  if ($1 == "source-disarm-before-read" &&
      $4 != "disarm-complete-set-then-Read_Now")
    fail("source readiness must be disarmed before Read_Now")
  if ($1 == "source-release-drain" &&
      $4 != "disarm-drain-Release_Source")
    fail("source readiness must be disarmed and drained before release")
  if ($1 == "readiness-fan-in-bound" &&
      !($3 == "arm-source-transport-close-outbound-shutdown-cancel" &&
        $4 == "arm-complete-readiness-set"))
    fail("readiness fan-in must retain every required source")
}

END {
  split("immediate-terminal pending-success pending-failure cancel-before-admission cancel-after-admission deadline-with-child finish-wrong-buffer abandon-parent restart-child gate-race client-shutdown source-fault source-query-arm-race source-ready-now source-disarm-before-read source-release-drain readiness-fan-in-bound", required, " ")
  for (i in required)
    if (!(required[i] in seen))
      fail("missing parent-fault case " required[i])
  if (NR - 1 < 17) fail("parent-fault fixture is unexpectedly small")
  exit failed
}
' "$PARENT_FIXTURE"

verify_read_fixture() {
  fixture=$1
  fixture_kind=$2
  prefix=$3
  minimum=$4
  required=$5
  awk -F '\t' -v kind="$fixture_kind" -v prefix="$prefix" \
    -v minimum="$minimum" -v required_text="$required" '
function fail(message) {
  print FILENAME ":" NR ": " message > "/dev/stderr"
  failed = 1
}

BEGIN {
  allowed_scope["request"] = 1
  allowed_scope["response"] = 1
  allowed_scope["transport"] = 1
  split(required_text, required, " ")
}

NR == 1 {
  if (NF != 6 || $1 != "case" || $2 != "scope" ||
      $3 != "concern" || $4 != "request" || $5 != "response" ||
      $6 != "required_observation")
    fail("unexpected " kind " fixture header")
  next
}

{
  if (NF != 6) fail("expected 6 tab-separated fields, got " NF)
  for (field = 1; field <= 6; field++)
    if ($field == "") fail(kind " fixture fields must not be empty")
  if (index($1, prefix "-") != 1)
    fail("unexpected " kind " case identifier " $1)
  if ($1 in seen) fail("duplicate " kind " case " $1)
  seen[$1] = 1
  if (!($2 in allowed_scope)) fail("unknown " kind " scope " $2)
  scope_seen[$2] = 1
  concern_seen[$3] = 1
}

END {
  for (i in required)
    if (!(required[i] in seen))
      fail("missing required " kind " case " required[i])
  for (scope in allowed_scope)
    if (!(scope in scope_seen))
      fail("missing " kind " scope " scope)
  if (length(concern_seen) < 12)
    fail(kind " fixture has too few independent concerns")
  if (NR - 1 < minimum)
    fail(kind " fixture is unexpectedly small")
  exit failed
}
' "$fixture"
}

verify_read_fixture "$RANGE_FIXTURE" "range-Get" "RG" 34 \
  "RG-RQ-001 RG-RQ-005 RG-RQ-010 RG-RS-001 RG-RS-002 RG-RS-005 RG-RS-006 RG-RS-010 RG-RS-012 RG-RS-013 RG-RS-015 RG-TR-001 RG-TR-002 RG-TR-004"
verify_read_fixture "$HEAD_FIXTURE" "HeadObject" "HD" 32 \
  "HD-RQ-001 HD-RQ-006 HD-RQ-010 HD-RS-001 HD-RS-002 HD-RS-003 HD-RS-004 HD-RS-006 HD-RS-008 HD-RS-015 HD-TR-001 HD-TR-002 HD-TR-005"

awk -F '\t' '
function fail(message) {
  print FILENAME ":" NR ": " message > "/dev/stderr"
  failed = 1
}

BEGIN {
  split("Response_Complete Pre_Admission_Rejected Cancelled Timed_Out Client_Unavailable Connection_Failed Transport_Failed Request_Source_Failed Response_Invalid Response_Body_Too_Large Response_Sink_Failed", values, " ")
  for (i in values) allowed_http[values[i]] = 1
  split("Not_Admitted Possibly_Admitted Response_Observed", values, " ")
  for (i in values) allowed_admission[values[i]] = 1
  split("Part_Published Definitely_Not_Staged Part_Outcome_Unknown Part_Cancelled_Before_Admission", values, " ")
  for (i in values) allowed_publication[values[i]] = 1
  split("No_Failure Authentication_Failed Authorization_Failed Invalid_Request Not_Found Unavailable_Or_Retryable Cancelled Timed_Out Client_Unavailable Connection_Failed Transport_Failed Request_Source_Failed Corrupt_Or_Invalid_Response", values, " ")
  for (i in values) allowed_reason[values[i]] = 1
  expected_reason["Pre_Admission_Rejected"] = "Invalid_Request"
  expected_reason["Cancelled"] = "Cancelled"
  expected_reason["Timed_Out"] = "Timed_Out"
  expected_reason["Client_Unavailable"] = "Client_Unavailable"
  expected_reason["Connection_Failed"] = "Connection_Failed"
  expected_reason["Transport_Failed"] = "Transport_Failed"
  expected_reason["Request_Source_Failed"] = "Request_Source_Failed"
  expected_reason["Response_Invalid"] = "Corrupt_Or_Invalid_Response"
  expected_reason["Response_Body_Too_Large"] = "Corrupt_Or_Invalid_Response"
  expected_reason["Response_Sink_Failed"] = "Corrupt_Or_Invalid_Response"
}

NR == 1 {
  if (NF != 8 || $1 != "http_result" || $2 != "admission" ||
      $3 != "status" || $4 != "s3_code" ||
      $5 != "part_publication" || $6 != "failure_reason" ||
      $7 != "reconcile" || $8 != "note")
    fail("unexpected UploadPart fixture header")
  next
}

{
  if (NF != 8) fail("expected 8 tab-separated fields, got " NF)
  if (!($1 in allowed_http)) fail("unknown HTTP result " $1)
  if (!($2 in allowed_admission)) fail("unknown admission certainty " $2)
  if (!($5 in allowed_publication))
    fail("unknown part-publication disposition " $5)
  if (!($6 in allowed_reason)) fail("unknown bounded failure reason " $6)
  if ($7 != "yes" && $7 != "no") fail("reconcile must be yes or no")
  if ($8 == "") fail("qualification note must not be empty")

  key = $1 SUBSEP $2 SUBSEP $3 SUBSEP $4
  if (key in seen) fail("duplicate UploadPart input tuple")
  seen[key] = 1
  result_seen[$1] = 1
  semantic_seen[$3 SUBSEP $4] = 1

  if ($5 == "Part_Outcome_Unknown" && $7 != "yes")
    fail("unknown part publication requires reconciliation")
  if ($5 != "Part_Outcome_Unknown" && $7 != "no")
    fail("conclusive part publication must not require reconciliation")
  if ($2 == "Not_Admitted" && $5 == "Part_Outcome_Unknown")
    fail("Not_Admitted cannot map to unknown part publication")
  if ($5 == "Part_Published" &&
      !($1 == "Response_Complete" && $2 == "Response_Observed" &&
        $3 == "200" && $4 == "none" && $6 == "No_Failure"))
    fail("Part_Published requires one complete valid 200 response")
  if ($5 == "Part_Cancelled_Before_Admission" &&
      !($1 == "Cancelled" && $2 == "Not_Admitted" && $6 == "Cancelled"))
    fail("cancelled part disposition requires pre-admission cancellation")
  if ($1 == "Response_Complete" && $3 != "200" &&
      $5 != "Part_Outcome_Unknown")
    fail("modeled UploadPart rejection must remain conservative")
  if ($1 in expected_reason && $6 != expected_reason[$1])
    fail("HTTP result does not retain its bounded failure reason")
}

END {
  split("Response_Complete Pre_Admission_Rejected Cancelled Timed_Out Client_Unavailable Connection_Failed Transport_Failed Request_Source_Failed Response_Invalid Response_Body_Too_Large Response_Sink_Failed", required, " ")
  for (i in required)
    if (!(required[i] in result_seen))
      fail("missing UploadPart HTTP result coverage for " required[i])
  split("200:none 400:BadDigest 400:InvalidPart 400:InvalidRequest 400:EntityTooLarge 401:InvalidAccessKeyId 403:AccessDenied 404:NoSuchBucket 404:NoSuchUpload 409:OperationAborted 429:SlowDown 500:InternalError 502:BadGateway 503:SlowDown 504:RequestTimeout 400:missing", required, " ")
  for (i in required) {
    split(required[i], pair, ":")
    if (!(pair[1] SUBSEP pair[2] in semantic_seen))
      fail("missing UploadPart status/code coverage for " required[i])
  }
  if (NR - 1 < 46) fail("UploadPart fixture is unexpectedly small")
  exit failed
}
' "$UPLOAD_FIXTURE"

awk -F '\t' '
function fail(message) {
  print FILENAME ":" NR ": " message > "/dev/stderr"
  failed = 1
}

BEGIN {
  split("Response_Complete Pre_Admission_Rejected Cancelled Timed_Out Client_Unavailable Connection_Failed Transport_Failed Request_Source_Failed Response_Invalid Response_Body_Too_Large Response_Sink_Failed", values, " ")
  for (i in values) allowed_http[values[i]] = 1
  split("Not_Admitted Possibly_Admitted Response_Observed", values, " ")
  for (i in values) allowed_admission[values[i]] = 1
  split("Multipart_Completed Definitely_Not_Completed Completion_Outcome_Unknown Completion_Cancelled_Before_Admission", values, " ")
  for (i in values) allowed_publication[values[i]] = 1
  split("No_Failure Authentication_Failed Authorization_Failed Invalid_Request Not_Found Unavailable_Or_Retryable Cancelled Timed_Out Client_Unavailable Connection_Failed Transport_Failed Request_Source_Failed Corrupt_Or_Invalid_Response", values, " ")
  for (i in values) allowed_reason[values[i]] = 1
  expected_reason["Pre_Admission_Rejected"] = "Invalid_Request"
  expected_reason["Cancelled"] = "Cancelled"
  expected_reason["Timed_Out"] = "Timed_Out"
  expected_reason["Client_Unavailable"] = "Client_Unavailable"
  expected_reason["Connection_Failed"] = "Connection_Failed"
  expected_reason["Transport_Failed"] = "Transport_Failed"
  expected_reason["Request_Source_Failed"] = "Request_Source_Failed"
  expected_reason["Response_Invalid"] = "Corrupt_Or_Invalid_Response"
  expected_reason["Response_Body_Too_Large"] = "Corrupt_Or_Invalid_Response"
  expected_reason["Response_Sink_Failed"] = "Corrupt_Or_Invalid_Response"
}

NR == 1 {
  if (NF != 8 || $1 != "http_result" || $2 != "admission" ||
      $3 != "status" || $4 != "s3_code" || $5 != "publication" ||
      $6 != "failure_reason" || $7 != "reconcile" || $8 != "note")
    fail("unexpected CompleteMultipartUpload fixture header")
  next
}

{
  if (NF != 8) fail("expected 8 tab-separated fields, got " NF)
  if (!($1 in allowed_http)) fail("unknown HTTP result " $1)
  if (!($2 in allowed_admission)) fail("unknown admission certainty " $2)
  if (!($5 in allowed_publication)) fail("unknown publication " $5)
  if (!($6 in allowed_reason)) fail("unknown bounded failure reason " $6)
  if ($7 != "yes" && $7 != "no") fail("reconcile must be yes or no")
  if ($8 == "") fail("qualification note must not be empty")

  key = $1 SUBSEP $2 SUBSEP $3 SUBSEP $4
  if (key in seen) fail("duplicate CompleteMultipartUpload input tuple")
  seen[key] = 1
  result_seen[$1] = 1
  semantic_seen[$3 SUBSEP $4] = 1

  if ($5 == "Completion_Outcome_Unknown" && $7 != "yes")
    fail("unknown completion publication requires reconciliation")
  if ($5 != "Completion_Outcome_Unknown" && $7 != "no")
    fail("conclusive completion publication must not require reconciliation")
  if ($2 == "Not_Admitted" && $5 == "Completion_Outcome_Unknown")
    fail("Not_Admitted cannot map to unknown completion publication")
  if ($5 == "Multipart_Completed" &&
      !($1 == "Response_Complete" && $2 == "Response_Observed" &&
        $3 == "200" && $4 == "none" && $6 == "No_Failure"))
    fail("Multipart_Completed requires one complete valid 200 response")
  if ($5 == "Completion_Cancelled_Before_Admission" &&
      !($1 == "Cancelled" && $2 == "Not_Admitted" && $6 == "Cancelled"))
    fail("cancelled completion requires pre-admission cancellation")
  if ($1 == "Response_Complete" && $4 != "none" &&
      $5 != "Completion_Outcome_Unknown")
    fail("modeled completion rejection must remain conservative")
  if ($1 in expected_reason && $6 != expected_reason[$1])
    fail("HTTP result does not retain its bounded failure reason")
}

END {
  split("Response_Complete Pre_Admission_Rejected Cancelled Timed_Out Client_Unavailable Connection_Failed Transport_Failed Request_Source_Failed Response_Invalid Response_Body_Too_Large Response_Sink_Failed", required, " ")
  for (i in required)
    if (!(required[i] in result_seen))
      fail("missing CompleteMultipartUpload HTTP result " required[i])
  split("200:none 200:InternalError 400:BadDigest 400:EntityTooSmall 400:InvalidPart 400:InvalidPartOrder 400:InvalidRequest 401:InvalidAccessKeyId 403:AccessDenied 404:NoSuchBucket 404:NoSuchKey 404:NoSuchUpload 409:OperationAborted 412:PreconditionFailed 503:SlowDown 400:missing", required, " ")
  for (i in required) {
    split(required[i], pair, ":")
    if (!(pair[1] SUBSEP pair[2] in semantic_seen))
      fail("missing CompleteMultipartUpload status/code " required[i])
  }
  if (NR - 1 < 46) fail("CompleteMultipartUpload fixture is unexpectedly small")
  exit failed
}
' "$COMPLETE_FIXTURE"

awk -F '\t' '
function fail(message) {
  print FILENAME ":" NR ": " message > "/dev/stderr"
  failed = 1
}

BEGIN {
  split("Response_Complete Pre_Admission_Rejected Cancelled Timed_Out Client_Unavailable Connection_Failed Transport_Failed Request_Source_Failed Response_Invalid Response_Body_Too_Large Response_Sink_Failed", values, " ")
  for (i in values) allowed_http[values[i]] = 1
  split("Not_Admitted Possibly_Admitted Response_Observed", values, " ")
  for (i in values) allowed_admission[values[i]] = 1
  split("Multipart_Aborted Definitely_Not_Aborted Abort_Outcome_Unknown Abort_Cancelled_Before_Admission", values, " ")
  for (i in values) allowed_abort[values[i]] = 1
  split("No_Failure Authentication_Failed Authorization_Failed Invalid_Request Not_Found Unavailable_Or_Retryable Cancelled Timed_Out Client_Unavailable Connection_Failed Transport_Failed Request_Source_Failed Corrupt_Or_Invalid_Response", values, " ")
  for (i in values) allowed_reason[values[i]] = 1
  expected_reason["Pre_Admission_Rejected"] = "Invalid_Request"
  expected_reason["Cancelled"] = "Cancelled"
  expected_reason["Timed_Out"] = "Timed_Out"
  expected_reason["Client_Unavailable"] = "Client_Unavailable"
  expected_reason["Connection_Failed"] = "Connection_Failed"
  expected_reason["Transport_Failed"] = "Transport_Failed"
  expected_reason["Request_Source_Failed"] = "Request_Source_Failed"
  expected_reason["Response_Invalid"] = "Corrupt_Or_Invalid_Response"
  expected_reason["Response_Body_Too_Large"] = "Corrupt_Or_Invalid_Response"
  expected_reason["Response_Sink_Failed"] = "Corrupt_Or_Invalid_Response"
}

NR == 1 {
  if (NF != 8 || $1 != "http_result" || $2 != "admission" ||
      $3 != "status" || $4 != "s3_code" || $5 != "abort" ||
      $6 != "failure_reason" || $7 != "reconcile" || $8 != "note")
    fail("unexpected AbortMultipartUpload fixture header")
  next
}

{
  if (NF != 8) fail("expected 8 tab-separated fields, got " NF)
  if (!($1 in allowed_http)) fail("unknown HTTP result " $1)
  if (!($2 in allowed_admission)) fail("unknown admission certainty " $2)
  if (!($5 in allowed_abort)) fail("unknown abort disposition " $5)
  if (!($6 in allowed_reason)) fail("unknown bounded failure reason " $6)
  if ($7 != "yes" && $7 != "no") fail("reconcile must be yes or no")
  if ($8 == "") fail("qualification note must not be empty")

  key = $1 SUBSEP $2 SUBSEP $3 SUBSEP $4
  if (key in seen) fail("duplicate AbortMultipartUpload input tuple")
  seen[key] = 1
  result_seen[$1] = 1
  semantic_seen[$3 SUBSEP $4] = 1

  if ($5 == "Abort_Outcome_Unknown" && $7 != "yes")
    fail("unknown abort outcome requires reconciliation")
  if ($5 != "Abort_Outcome_Unknown" && $7 != "no")
    fail("conclusive abort disposition must not require reconciliation")
  if ($2 == "Not_Admitted" && $5 == "Abort_Outcome_Unknown")
    fail("Not_Admitted cannot map to unknown abort outcome")
  if ($5 == "Multipart_Aborted" &&
      !($1 == "Response_Complete" && $2 == "Response_Observed" &&
        $3 == "204" && $4 == "none" && $6 == "No_Failure"))
    fail("Multipart_Aborted requires one complete valid 204 response")
  if ($5 == "Abort_Cancelled_Before_Admission" &&
      !($1 == "Cancelled" && $2 == "Not_Admitted" && $6 == "Cancelled"))
    fail("cancelled abort requires pre-admission cancellation")
  if ($1 == "Response_Complete" && $4 != "none" &&
      $5 != "Abort_Outcome_Unknown")
    fail("modeled abort rejection must remain conservative")
  if ($1 in expected_reason && $6 != expected_reason[$1])
    fail("HTTP result does not retain its bounded failure reason")
}

END {
  split("Response_Complete Pre_Admission_Rejected Cancelled Timed_Out Client_Unavailable Connection_Failed Transport_Failed Request_Source_Failed Response_Invalid Response_Body_Too_Large Response_Sink_Failed", required, " ")
  for (i in required)
    if (!(required[i] in result_seen))
      fail("missing AbortMultipartUpload HTTP result " required[i])
  split("204:none 400:InvalidRequest 401:InvalidAccessKeyId 403:AccessDenied 404:NoSuchBucket 404:NoSuchKey 404:NoSuchUpload 409:OperationAborted 412:PreconditionFailed 429:SlowDown 500:InternalError 502:BadGateway 503:SlowDown 504:RequestTimeout 400:missing", required, " ")
  for (i in required) {
    split(required[i], pair, ":")
    if (!(pair[1] SUBSEP pair[2] in semantic_seen))
      fail("missing AbortMultipartUpload status/code " required[i])
  }
  if (NR - 1 < 45) fail("AbortMultipartUpload fixture is unexpectedly small")
  exit failed
}
' "$ABORT_FIXTURE"

awk -F '\t' '
function fail(message) {
  print FILENAME ":" NR ": " message > "/dev/stderr"
  failed = 1
}

NR == 1 {
  if (NF != 8 || $1 != "http_result" || $2 != "admission" ||
      $3 != "status" || $4 != "s3_code" || $5 != "publication" ||
      $6 != "failure_reason" || $7 != "reconcile" || $8 != "note")
    fail("unexpected CopyObject fixture header")
  next
}

{
  if (NF != 8) fail("expected 8 tab-separated fields, got " NF)
  if ($8 == "") fail("CopyObject qualification note must not be empty")
  key = $1 SUBSEP $2 SUBSEP $3 SUBSEP $4
  if (key in seen) fail("duplicate CopyObject input tuple")
  seen[key] = 1
  if (($5 == "Outcome_Unknown") != ($7 == "yes"))
    fail("CopyObject reconciliation does not match publication certainty")
  if ($5 == "Published" &&
      !($1 == "Response_Complete" && $2 == "Response_Observed" &&
        $3 == "200" && $4 == "none" && $6 == "No_Failure"))
    fail("CopyObject Published requires exact complete success")
  if ($5 == "Precondition_Failed" &&
      !($1 == "Response_Complete" && $2 == "Response_Observed" &&
        $3 == "412" && $4 == "PreconditionFailed" &&
        $6 == "No_Failure"))
    fail("CopyObject precondition disposition requires exact semantics")
  if ($4 == "ObjectNotInActiveTierError" &&
      !($1 == "Response_Complete" && $2 == "Response_Observed" &&
        $3 == "403" && $5 == "Definitely_Not_Published" &&
        $6 == "Invalid_Request" && $7 == "no"))
    fail("CopyObject inactive-tier error is not classified exactly")
}

END {
  if (NR != 51) fail("CopyObject fixture must contain exactly 50 rows")
  modeled = "Response_Complete" SUBSEP "Response_Observed" SUBSEP "403" \
    SUBSEP "ObjectNotInActiveTierError"
  if (!(modeled in seen))
    fail("missing modeled CopyObject inactive-tier error")
  exit failed
}
' "$COPY_FIXTURE"

awk -F '\t' '
function fail(message) {
  print FILENAME ":" NR ": " message > "/dev/stderr"
  failed = 1
}
function add_expected(row) { expected[row] = 1 }
function disposition(op, result, admission) {
  if (op == "GetObjectTagging") return "not-applicable"
  if (admission != "Not_Admitted")
    return "Object_Tag_Mutation_Outcome_Unknown"
  if (result == "Cancelled")
    return "Object_Tag_Mutation_Cancelled_Before_Admission"
  return "Object_Tag_Mutation_Definitely_Not_Applied"
}
function note(op, admission) {
  if (op == "GetObjectTagging")
    return "read failure upgrades no mutation certainty"
  if (admission == "Not_Admitted")
    return "failure occurred before possible admission"
  return "possibly admitted mutation is never replayed"
}
function add_failure(op, encoded, item, value, reconcile) {
  split(encoded, item, ":")
  value = disposition(op, item[2], item[3])
  reconcile = (value == "Object_Tag_Mutation_Outcome_Unknown" ? "yes" : "no")
  add_expected(op "\t" item[2] "\t" item[3] "\t" item[4] "\t" item[5] \
    "\t" value "\t" item[6] "\t" reconcile \
    "\texplicit-or-omitted\t" note(op, item[3]))
}
BEGIN {
  split("PutObjectTagging GetObjectTagging DeleteObjectTagging", ops, " ")
  failure_text = "x:Pre_Admission_Rejected:Not_Admitted:none:none:"
  failure_text = failure_text "Invalid_Request "
  failure_text = failure_text "x:Cancelled:Not_Admitted:none:none:Cancelled "
  failure_text = failure_text "x:Cancelled:Possibly_Admitted:none:none:"
  failure_text = failure_text "Cancelled "
  failure_text = failure_text "x:Timed_Out:Not_Admitted:none:none:Timed_Out "
  failure_text = failure_text "x:Timed_Out:Possibly_Admitted:none:none:"
  failure_text = failure_text "Timed_Out "
  failure_text = failure_text "x:Client_Unavailable:Not_Admitted:none:none:"
  failure_text = failure_text "Client_Unavailable "
  failure_text = failure_text "x:Connection_Failed:Not_Admitted:none:none:"
  failure_text = failure_text "Connection_Failed "
  failure_text = failure_text "x:Transport_Failed:Not_Admitted:none:none:"
  failure_text = failure_text "Transport_Failed "
  failure_text = failure_text "x:Transport_Failed:Possibly_Admitted:none:none:"
  failure_text = failure_text "Transport_Failed "
  failure_text = failure_text "x:Request_Source_Failed:Not_Admitted:none:none:"
  failure_text = failure_text "Request_Source_Failed "
  failure_text = failure_text "x:Request_Source_Failed:Possibly_Admitted:"
  failure_text = failure_text "none:none:Request_Source_Failed "
  failure_text = failure_text "x:Response_Invalid:Response_Observed:invalid:"
  failure_text = failure_text "malformed:Corrupt_Or_Invalid_Response "
  failure_text = failure_text "x:Response_Body_Too_Large:Response_Observed:"
  failure_text = failure_text "oversized:none:Corrupt_Or_Invalid_Response "
  failure_text = failure_text "x:Response_Sink_Failed:Response_Observed:"
  failure_text = failure_text "overflow-or-fault:none:"
  failure_text = failure_text "Corrupt_Or_Invalid_Response"
  split(failure_text, failures, " ")
  for (o in ops)
    for (i in failures)
      if (!(ops[o] == "GetObjectTagging" && i == 11))
        add_failure(ops[o], failures[i])
  add_expected("PutObjectTagging\tResponse_Complete\tResponse_Observed\t200" \
    "\tnone\tObject_Tag_Mutation_Completed\tNo_Failure\tno" \
    "\texplicit-version\texact same-version response proves completion," \
    " not causal tag-state proof")
  add_expected("PutObjectTagging\tResponse_Complete\tResponse_Observed\t200" \
    "\tnone\tObject_Tag_Mutation_Completed\tNo_Failure\tno" \
    "\tomitted-version\tcurrent-version response proves completion," \
    " not target-version identity")
  add_expected("GetObjectTagging\tResponse_Complete\tResponse_Observed\t200" \
    "\tnone\tnot-applicable\tNo_Failure\tno\texplicit-version" \
    "\texact same-version current-state observation, not causal proof")
  add_expected("GetObjectTagging\tResponse_Complete\tResponse_Observed\t200" \
    "\tnone\tnot-applicable\tNo_Failure\tno\tomitted-version" \
    "\tcurrent-version observation only, with no mutation certainty")
  add_expected("DeleteObjectTagging\tResponse_Complete\tResponse_Observed" \
    "\t204\tnone\tObject_Tag_Mutation_Completed\tNo_Failure\tno" \
    "\texplicit-version\texact same-version response proves completion," \
    " not causal tag-state proof")
  add_expected("DeleteObjectTagging\tResponse_Complete\tResponse_Observed" \
    "\t204\tnone\tObject_Tag_Mutation_Completed\tNo_Failure\tno" \
    "\tomitted-version\tcurrent-version response proves completion," \
    " not target-version identity")
  add_expected("PutObjectTagging\tResponse_Complete\tResponse_Observed\t400" \
    "\tInvalidDigest\tObject_Tag_Mutation_Definitely_Not_Applied" \
    "\tInvalid_Request\tno\texplicit-or-omitted" \
    "\tput checksum rejection is conclusive")
  add_expected("GetObjectTagging\tResponse_Complete\tResponse_Observed\t400" \
    "\tInvalidDigest\tnot-applicable\tCorrupt_Or_Invalid_Response\tno" \
    "\texplicit-or-omitted" \
    "\tput-only checksum error is not a read contract")
  add_expected("DeleteObjectTagging\tResponse_Complete\tResponse_Observed" \
    "\t400\tInvalidDigest\tObject_Tag_Mutation_Outcome_Unknown" \
    "\tCorrupt_Or_Invalid_Response\tyes\texplicit-or-omitted" \
    "\tput-only checksum error is not delete evidence")
}
NR == 1 {
  if (NF != 10 || $1 != "operation" || $2 != "http_result" ||
      $3 != "admission" || $4 != "status" || $5 != "s3_code" ||
      $6 != "disposition" || $7 != "failure_reason" ||
      $8 != "reconcile" || $9 != "selection" || $10 != "note")
    fail("unexpected object-tagging fixture header")
  next
}
{
  if (NF != 10 || $9 == "" || $10 == "")
    fail("invalid object-tagging fixture row")
  if ($1 != "PutObjectTagging" && $1 != "GetObjectTagging" &&
      $1 != "DeleteObjectTagging") fail("unknown object-tagging operation")
  key = $0
  if (key in seen) fail("duplicate object-tagging input tuple")
  seen[key] = 1
  if (!(key in expected)) fail("unexpected object-tagging tuple")
  operation[$1] = 1
  if ($1 == "GetObjectTagging" && $6 != "not-applicable")
    fail("GetObjectTagging acquired mutation certainty")
  if (($6 == "Object_Tag_Mutation_Outcome_Unknown") != ($8 == "yes"))
    fail("object-tagging reconciliation does not match certainty")
  if ($5 == "InvalidDigest" && $1 != "PutObjectTagging" &&
      $7 == "Invalid_Request")
    fail("put-only checksum rejection leaked to another operation")
}
END {
  if (!("PutObjectTagging" in operation) ||
      !("GetObjectTagging" in operation) ||
      !("DeleteObjectTagging" in operation))
    fail("missing object-tagging operation")
  for (key in expected)
    if (!(key in seen)) fail("missing exact object-tagging tuple")
  if (NR != 51) fail("object-tagging fixture must contain exactly 50 rows")
  exit failed
}
' "$TAGGING_FIXTURE"

awk -F '\t' '
function fail(message) {
  print FILENAME ":" NR ": " message > "/dev/stderr"
  failed = 1
}
function add_expected(row) { expected[row] = 1 }
function add_response(status, code, disposition, reason, note) {
  add_expected("Response_Complete\tResponse_Observed\t" status "\t" code \
    "\t" disposition "\t" reason "\t" \
    (disposition == "Batch_Outcome_Unknown" ? "yes" : "no") "\t" note)
}
function failure_disposition(result, admission) {
  if (admission != "Not_Admitted") return "Batch_Outcome_Unknown"
  if (result == "Cancelled") return "Batch_Cancelled_Before_Admission"
  return "Batch_Definitely_Not_Processed"
}
function failure_note(result, admission) {
  if (result == "Pre_Admission_Rejected")
    return "HTTP validation rejected before handoff"
  if (result == "Cancelled" && admission == "Not_Admitted")
    return "cancelled before possible admission"
  if (result == "Cancelled" && admission == "Possibly_Admitted")
    return "cancellation cannot retract possible admission"
  if (result == "Timed_Out" && admission == "Not_Admitted")
    return "deadline expired before handoff"
  if (result == "Timed_Out" && admission == "Possibly_Admitted")
    return "deadline expired after possible admission"
  if (result == "Client_Unavailable" && admission == "Not_Admitted")
    return "client rejected admission"
  if (result == "Connection_Failed" && admission == "Not_Admitted")
    return "connection failed before handoff"
  if (result == "Transport_Failed" && admission == "Not_Admitted")
    return "transport failed before handoff"
  if (result == "Transport_Failed" && admission == "Possibly_Admitted")
    return "lost accepted-request response is unknown"
  if (result == "Request_Source_Failed" && admission == "Not_Admitted")
    return "source failed before handoff"
  if (result == "Request_Source_Failed" && admission == "Possibly_Admitted")
    return "partial admitted request remains conservative"
  if (result == "Response_Invalid" && admission == "Not_Admitted")
    return "invalid local state preceded admission"
  if (result == "Response_Invalid" && admission == "Possibly_Admitted")
    return "invalid response cannot disprove processing"
  if (result == "Response_Invalid")
    return "invalid observed response requires reconciliation"
  if (result == "Response_Body_Too_Large")
    return "oversized response cannot prove processing"
  if (result == "Response_Sink_Failed")
    return "failed response sink cannot prove processing"
  if (admission == "Response_Observed")
    return "observed partial response is not conclusive"
  return "possible admission remains conservative"
}
function add_failure(encoded, item, disposition, reconcile) {
  split(encoded, item, ":")
  disposition = failure_disposition(item[1], item[2])
  reconcile = (disposition == "Batch_Outcome_Unknown" ? "yes" : "no")
  add_expected(item[1] "\t" item[2] "\t" item[3] "\t" item[4] \
    "\t" disposition "\t" item[5] "\t" reconcile "\t" \
    failure_note(item[1], item[2]))
}
BEGIN {
  add_response("200", "none", "Batch_Processed", "No_Failure",
    "complete bound DeleteObjects response")
  add_response("400", "BadDigest", "Batch_Definitely_Not_Processed",
    "Invalid_Request", "checksum rejection is conclusive")
  add_response("400", "EntityTooLarge", "Batch_Definitely_Not_Processed",
    "Invalid_Request", "request size rejection is conclusive")
  add_response("400", "InvalidArgument", "Batch_Definitely_Not_Processed",
    "Invalid_Request", "argument rejection is conclusive")
  add_response("400", "InvalidDigest", "Batch_Definitely_Not_Processed",
    "Invalid_Request", "digest rejection is conclusive")
  add_response("400", "InvalidRequest", "Batch_Definitely_Not_Processed",
    "Invalid_Request", "request rejection is conclusive")
  add_response("400", "MalformedXML", "Batch_Definitely_Not_Processed",
    "Invalid_Request", "request document rejection is conclusive")
  add_response("400", "XAmzContentSHA256Mismatch",
    "Batch_Definitely_Not_Processed", "Invalid_Request",
    "payload checksum rejection is conclusive")
  add_response("401", "InvalidAccessKeyId",
    "Batch_Definitely_Not_Processed", "Authentication_Failed",
    "authentication rejection is conclusive")
  add_response("403", "AccessDenied", "Batch_Definitely_Not_Processed",
    "Authorization_Failed", "authorization rejection is conclusive")
  add_response("404", "NoSuchBucket", "Batch_Definitely_Not_Processed",
    "Not_Found", "missing bucket rejection is conclusive")
  add_response("501", "NotImplemented", "Batch_Definitely_Not_Processed",
    "Invalid_Request", "unsupported request rejection is conclusive")
  retry_note = "caller reconciles the selected object set before retry"
  add_response("409", "OperationAborted", "Batch_Outcome_Unknown",
    "Unavailable_Or_Retryable", retry_note)
  add_response("429", "SlowDown", "Batch_Outcome_Unknown",
    "Unavailable_Or_Retryable", retry_note)
  add_response("500", "InternalError", "Batch_Outcome_Unknown",
    "Unavailable_Or_Retryable", retry_note)
  add_response("502", "BadGateway", "Batch_Outcome_Unknown",
    "Unavailable_Or_Retryable", retry_note)
  add_response("503", "SlowDown", "Batch_Outcome_Unknown",
    "Unavailable_Or_Retryable", retry_note)
  add_response("504", "RequestTimeout", "Batch_Outcome_Unknown",
    "Unavailable_Or_Retryable", retry_note)
  failures = "Pre_Admission_Rejected:Not_Admitted:none:not-applicable:"
  failures = failures "Invalid_Request "
  results = "Cancelled Timed_Out Client_Unavailable Connection_Failed "
  results = results "Transport_Failed Request_Source_Failed Response_Invalid"
  split(results, values, " ")
  for (i in values) {
    result = values[i]
    reason = result
    status = "none"
    if (result == "Response_Invalid") {
      reason = "Corrupt_Or_Invalid_Response"
      status = "invalid"
    }
    failures = failures result ":Not_Admitted:" status ":not-applicable:"
    failures = failures reason " " result ":Possibly_Admitted:" status
    failures = failures ":not-applicable:" reason " " result
    failures = failures ":Response_Observed:"
    if (result == "Response_Invalid")
      response_status = "invalid"
    else
      response_status = "incomplete"
    failures = failures response_status
    failures = failures ":not-applicable:" reason " "
  }
  failures = failures "Response_Body_Too_Large:Response_Observed:"
  failures = failures "oversized:not-applicable:Corrupt_Or_Invalid_Response "
  failures = failures "Response_Sink_Failed:Response_Observed:"
  failures = failures "overflow-or-fault:not-applicable:"
  failures = failures "Corrupt_Or_Invalid_Response"
  split(failures, failure, " ")
  for (i in failure) add_failure(failure[i])
}
NR == 1 {
  if (NF != 8 || $1 != "http_result" || $2 != "admission" ||
      $3 != "status" || $4 != "s3_code" || $5 != "disposition" ||
      $6 != "failure_reason" || $7 != "reconcile" || $8 != "note")
    fail("unexpected DeleteObjects fixture header")
  next
}
{
  if (NF != 8 || $8 == "") fail("invalid DeleteObjects fixture row")
  key = $0
  if (key in seen) fail("duplicate DeleteObjects input tuple")
  seen[key] = 1
  if (!(key in expected)) fail("unexpected DeleteObjects tuple")
  if (($5 == "Batch_Outcome_Unknown") != ($7 == "yes"))
    fail("DeleteObjects reconciliation does not match certainty")
  if ($4 == "InvalidDigest" || $4 == "XAmzContentSHA256Mismatch")
    if ($5 != "Batch_Definitely_Not_Processed" ||
        $6 != "Invalid_Request")
      fail("DeleteObjects checksum rejection is not conclusive")
}
END {
  for (key in expected)
    if (!(key in seen)) fail("missing exact DeleteObjects tuple")
  if (NR != 43) fail("DeleteObjects fixture must contain exactly 42 rows")
  exit failed
}
' "$DELETE_OBJECTS_FIXTURE"

printf '%s\n' "composable client fixtures: OK"
