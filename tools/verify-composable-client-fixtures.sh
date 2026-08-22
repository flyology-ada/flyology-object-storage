#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
PUT_FIXTURE=${1:-"$PROJECT_DIR/tests/corpora/composable-client/put-certainty.tsv"}
PARENT_FIXTURE=${2:-"$PROJECT_DIR/tests/corpora/composable-client/parent-faults.tsv"}

if [ ! -f "$PUT_FIXTURE" ]; then
  printf '%s\n' "missing Put fixture: $PUT_FIXTURE" >&2
  exit 1
fi
if [ ! -f "$PARENT_FIXTURE" ]; then
  printf '%s\n' "missing parent-fault fixture: $PARENT_FIXTURE" >&2
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

BEGIN {
  split("Response_Complete Pre_Admission_Rejected Cancelled Timed_Out Client_Unavailable Connection_Failed Transport_Failed Request_Source_Failed Response_Invalid Response_Body_Too_Large Response_Sink_Failed", values, " ")
  for (i in values) allowed_http[values[i]] = 1
  split("Not_Admitted Possibly_Admitted Response_Observed", values, " ")
  for (i in values) allowed_admission[values[i]] = 1
  split("200 400 401 403 404 409 412 429 500 502 503 504 none incomplete invalid oversized overflow-or-fault", values, " ")
  for (i in values) allowed_status[values[i]] = 1
  split("none InvalidRequest InvalidAccessKeyId AccessDenied NoSuchBucket ConditionalRequestConflict PreconditionFailed SlowDown InternalError BadGateway RequestTimeout missing malformed not-applicable", values, " ")
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
      !exact_complete("400", "InvalidRequest",
                      "Definitely_Not_Published", "Invalid_Request"))
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
  split("200:none 400:InvalidRequest 401:InvalidAccessKeyId 403:AccessDenied 404:NoSuchBucket 409:ConditionalRequestConflict 412:PreconditionFailed 429:SlowDown 500:InternalError 502:BadGateway 503:SlowDown 504:RequestTimeout 400:missing 403:missing 404:missing 412:missing 500:malformed", required, " ")
  for (i in required) {
    split(required[i], pair, ":")
    if (!(pair[1] SUBSEP pair[2] in semantic_seen))
      fail("missing exact status/code coverage for " required[i])
  }
  if (NR - 1 < 41) fail("Put fixture is unexpectedly small")
  exit failed
}
' "$PUT_FIXTURE"

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

printf '%s\n' "composable client fixtures: OK"
