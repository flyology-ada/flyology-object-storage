#!/usr/bin/env python3
"""Fail-closed CopyObject review and qualification preparation oracle."""

from __future__ import annotations

import csv
import hashlib
import json
import os
from pathlib import Path
import sys
import tomllib


ROOT = Path(__file__).resolve().parent.parent
MODEL_SHA256 = (
    "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
)


def fail(message: str) -> None:
    raise SystemExit(f"CopyObject preparation audit failed: {message}")


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def require_order(text: str, fragments: list[str], label: str) -> None:
    cursor = -1
    for fragment in fragments:
        if text.count(fragment) != 1:
            fail(f"{label}: expected one {fragment!r}")
        position = text.index(fragment)
        if position <= cursor:
            fail(f"{label}: out-of-order {fragment!r}")
        cursor = position


def require_sequence(text: str, fragments: list[str], label: str) -> None:
    cursor = 0
    for fragment in fragments:
        position = text.find(fragment, cursor)
        if position < 0:
            fail(f"{label}: missing ordered {fragment!r}")
        cursor = position + len(fragment)


model_path = Path(os.environ.get("FLYOLOGY_S3_SERVICE_MODEL", ""))
if not model_path.is_file():
    fail("FLYOLOGY_S3_SERVICE_MODEL must name the pinned model")
model_bytes = model_path.read_bytes()
if hashlib.sha256(model_bytes).hexdigest() != MODEL_SHA256:
    fail("pinned service model hash changed")
model = json.loads(model_bytes)
operation = model["operations"].get("CopyObject")
if operation is None:
    fail("pinned model has no CopyObject operation")
if operation.get("http") != {
    "method": "PUT",
    "requestUri": "/{Bucket}/{Key+}",
}:
    fail("CopyObject HTTP method or greedy target changed")
if operation.get("input") != {"shape": "CopyObjectRequest"}:
    fail("CopyObject input shape changed")
if operation.get("output") != {"shape": "CopyObjectOutput"}:
    fail("CopyObject output shape changed")
if operation.get("errors") != [{"shape": "ObjectNotInActiveTierError"}]:
    fail("CopyObject modeled error inventory changed")
if model["shapes"]["ObjectNotInActiveTierError"].get("error") != {
    "httpStatusCode": 403
}:
    fail("ObjectNotInActiveTierError status changed")
request = model["shapes"]["CopyObjectRequest"]
if request.get("required") != ["Bucket", "CopySource", "Key"]:
    fail("CopyObject required request members changed")
if len(request.get("members", {})) != 44:
    fail("CopyObject request member inventory is not 44")
output = model["shapes"]["CopyObjectOutput"]
result = model["shapes"]["CopyObjectResult"]
if (
    len(output.get("members", {})) != 11
    or len(result.get("members", {})) != 13
):
    fail(
        "CopyObject output geometry is not 11 top-level plus 13 result "
        "members"
    )

registry = tomllib.loads(read("coverage/s3-operations.toml"))
entries = [
    item for item in registry["operation"] if item["name"] == "CopyObject"
]
if len(entries) != 1:
    fail("registry must contain exactly one CopyObject entry")
entry = entries[0]
expected_fields = {
    "tier": "core",
    "provider": "transfers",
    "family": "rest_xml_mutation",
    "public_provider": "Flyology.Object_Storage.Client.Transfers",
    "codec": "strict_bodyless_rest_xml_and_singleton_headers",
    "public_name": "Copy_Object",
    "errors": [
        "authentication",
        "authorization",
        "not_found",
        "invalid_request",
        "unavailable_or_retryable",
        "corrupt_or_invalid_response",
    ],
    "coverage": {
        "backend": "covered",
        "client": "covered",
        "server": "covered",
        "corpus": "covered",
    },
    "provenance": {
        "backend": "handwritten",
        "client": "handwritten",
        "server": "handwritten",
        "tests": "handwritten",
    },
    "implementation_mode": "handwritten",
    "generator_eligible": False,
    "human_decisions_resolved": True,
    "decision_status": "reviewed",
    "qualification": "copy_object",
    "ada_symbols": [
        "Prepare_Copy_Object",
        "Decode_Copy_Object_Complete_Response",
        "Execute_Copy_Object",
        "Copy_Operation",
        "Copy_Object",
        "Finish",
    ],
}
for key, expected in expected_fields.items():
    if entry.get(key) != expected:
        fail(f"registry field {key} changed")
for phrase in (
    "no automatic replay",
    "Outcome_Unknown",
    "generation-bound HeadObject or whole Get",
    "exact source selector and source conditions",
):
    contract = entry.get("certainty", "") + entry.get("reconciliation", "")
    if phrase not in contract:
        fail(f"registry certainty contract lacks {phrase!r}")

expected_lane = [
    [
        "uv",
        "run",
        "--python",
        "3.13",
        "--",
        "tools/verify-copy-object-preparation.py",
    ],
    ["./tools/verify-composable-client-fixtures.sh"],
    ["./tools/test-composable-client-fixtures-verifier.sh"],
    ["@tests", "alr", "-n", "build"],
    ["@tests", "./bin/s3_http_socket_corpus"],
    ["./tools/verify-coverage.sh"],
    ["./tools/build-api-docs.sh", "/private/tmp/fos-copy-object-gnatdoc"],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]
if registry["qualification"].get("copy_object") != expected_lane:
    fail("CopyObject qualification lane changed")

def response(
    status: str,
    code: str,
    publication: str,
    failure: str,
    reconcile: str,
) -> tuple[str, ...]:
    return (
        "Response_Complete",
        "Response_Observed",
        status,
        code,
        publication,
        failure,
        reconcile,
    )


def inconsistent_success(admission: str) -> tuple[str, ...]:
    return (
        "Response_Complete",
        admission,
        "200",
        "none",
        "Outcome_Unknown",
        "Corrupt_Or_Invalid_Response",
        "yes",
    )


response_rows = [
    response("200", "none", "Published", "No_Failure", "no"),
    response(
        "412", "PreconditionFailed", "Precondition_Failed", "No_Failure", "no"
    ),
    response(
        "400", "InvalidArgument", "Definitely_Not_Published",
        "Invalid_Request", "no"
    ),
    response(
        "400", "InvalidRequest", "Definitely_Not_Published",
        "Invalid_Request", "no"
    ),
    response(
        "401", "InvalidAccessKeyId", "Definitely_Not_Published",
        "Authentication_Failed", "no"
    ),
    response(
        "403", "AccessDenied", "Definitely_Not_Published",
        "Authorization_Failed", "no"
    ),
    response(
        "403", "ObjectNotInActiveTierError", "Definitely_Not_Published",
        "Invalid_Request", "no"
    ),
    response(
        "404", "NoSuchBucket", "Definitely_Not_Published", "Not_Found", "no"
    ),
    response(
        "404", "NoSuchKey", "Definitely_Not_Published", "Not_Found", "no"
    ),
    response(
        "501", "NotImplemented", "Definitely_Not_Published",
        "Invalid_Request", "no"
    ),
    response(
        "409", "OperationAborted", "Outcome_Unknown",
        "Unavailable_Or_Retryable", "yes"
    ),
    response(
        "429", "SlowDown", "Outcome_Unknown",
        "Unavailable_Or_Retryable", "yes"
    ),
    response(
        "500", "InternalError", "Outcome_Unknown",
        "Unavailable_Or_Retryable", "yes"
    ),
    response(
        "200", "InternalError", "Outcome_Unknown",
        "Unavailable_Or_Retryable", "yes"
    ),
    response(
        "502", "BadGateway", "Outcome_Unknown",
        "Unavailable_Or_Retryable", "yes"
    ),
    response(
        "503", "SlowDown", "Outcome_Unknown",
        "Unavailable_Or_Retryable", "yes"
    ),
    response(
        "504", "RequestTimeout", "Outcome_Unknown",
        "Unavailable_Or_Retryable", "yes"
    ),
    response(
        "412", "AccessDenied", "Outcome_Unknown",
        "Corrupt_Or_Invalid_Response", "yes"
    ),
    inconsistent_success("Not_Admitted"),
    inconsistent_success("Possibly_Admitted"),
]
failure_reasons = [
    ("Pre_Admission_Rejected", "Invalid_Request"),
    ("Cancelled", "Cancelled"),
    ("Timed_Out", "Timed_Out"),
    ("Client_Unavailable", "Client_Unavailable"),
    ("Connection_Failed", "Connection_Failed"),
    ("Transport_Failed", "Transport_Failed"),
    ("Request_Source_Failed", "Request_Source_Failed"),
    ("Response_Invalid", "Corrupt_Or_Invalid_Response"),
    ("Response_Body_Too_Large", "Corrupt_Or_Invalid_Response"),
    ("Response_Sink_Failed", "Corrupt_Or_Invalid_Response"),
]
admissions = ["Not_Admitted", "Possibly_Admitted", "Response_Observed"]
expected_rows = list(response_rows)
for kind, reason in failure_reasons:
    for admission in admissions:
        if kind == "Response_Invalid":
            status = "invalid"
        elif kind == "Response_Body_Too_Large":
            status = "oversized"
        elif kind == "Response_Sink_Failed":
            status = "overflow-or-fault"
        elif (
            admission == "Response_Observed"
            and kind != "Pre_Admission_Rejected"
        ):
            status = "incomplete"
        else:
            status = "none"
        if admission == "Not_Admitted":
            publication = (
                "Cancelled_Before_Publication"
                if kind == "Cancelled"
                else "Definitely_Not_Published"
            )
            reconcile = "no"
        else:
            publication = "Outcome_Unknown"
            reconcile = "yes"
        expected_rows.append(
            (
                kind,
                admission,
                status,
                "not-applicable",
                publication,
                reason,
                reconcile,
            )
        )

fixture_path = ROOT / "tests/corpora/composable-client/copy-certainty.tsv"
if b"\r" in fixture_path.read_bytes():
    fail("CopyObject certainty fixture contains CR bytes")
with fixture_path.open(newline="", encoding="utf-8") as stream:
    rows = list(csv.reader(stream, delimiter="\t"))
if not rows or rows[0] != [
    "http_result",
    "admission",
    "status",
    "s3_code",
    "publication",
    "failure_reason",
    "reconcile",
    "note",
]:
    fail("CopyObject certainty header changed")
if any(len(row) != 8 or not row[7] for row in rows[1:]):
    fail("CopyObject certainty rows require eight nonempty fields")
actual_rows = [tuple(row[:7]) for row in rows[1:]]
if actual_rows != expected_rows:
    mismatch = next(
        (index for index, pair in enumerate(zip(actual_rows, expected_rows), 1)
         if pair[0] != pair[1]),
        min(len(actual_rows), len(expected_rows)) + 1,
    )
    fail(f"CopyObject certainty tuple inventory changed at row {mismatch}")

transfers = read("src/flyology-object_storage-client-transfers.adb")
copy_normalizer = transfers.split("function Normalize_Copy_Response", 1)[1]
copy_normalizer = copy_normalizer.split(
    "function Normalize_Copy_Failure", 1
)[0]
for fragment in (
    'Code in "AccessDenied" | "ObjectNotInActiveTierError"',
    'Code = "ObjectNotInActiveTierError"',
    "then Invalid_Request",
):
    if fragment not in copy_normalizer:
        fail(f"CopyObject normalizer lacks {fragment!r}")

socket = read("tests/src/s3_http_socket_corpus.adb")
for fragment in (
    "Copy_Admission_Native         : aliased Flyology.Cancellation.Token;",
    "Copy_Drain_Native             : aliased Flyology.Cancellation.Token;",
    (
        "Abort_Multipart_Cancellation,\n"
        "      Copy_Object_Cancellation,\n"
        "      Create_Bucket_Cancellation,\n"
        "      Delete_Bucket_Cancellation,\n"
        "      Create_Multipart_Cancellation,\n"
        "      Get_Bucket_Location_Cancellation,\n"
        "      Get_Bucket_Versioning_Cancellation,\n"
        "      Put_Bucket_Versioning_Cancellation);"
    ),
):
    if socket.count(fragment) != 1:
        fail(f"CopyObject socket inventory lacks exact {fragment!r}")
cancel_start = socket.index("pre-admission CopyObject cancellation mismatch")
cancel_end = socket.index("direct CopyObject first completion mismatch")
cancel_region = socket[cancel_start:cancel_end]
require_sequence(
    cancel_region,
    [
        "Copy_Admission_Native.Wait_Source",
        "Copy_Drain_Native.Wait_Source",
        '"copy-cancel"',
        "Operations.Cancel (Cancel_Operation);",
        "Operations.Wait_All (Cancel_Set);",
        "Finish (Cancel_Operation, Cancel_Result);",
        '"copy-cancel-restart"',
        "same-operation CopyObject restart mismatch",
    ],
    "CopyObject admitted-cancellation client region",
)
lost_start = socket.index("lost-response CopyObject priming HEAD mismatch")
lost_end = socket.index("high-level CopyObject rejection mismatch")
lost_region = socket[lost_start:lost_end]
require_sequence(
    lost_region,
    [
        "Transfers.Copy_Object",
        '"copy-lost"',
        "lost CopyObject response was classified conclusively",
        "Objects.Get_Whole",
        '"copy-lost-generation"',
        "lost-response CopyObject reconciliation mismatch",
    ],
    "CopyObject lost-response reconciliation client region",
)
for fragment in (
    "admitted CopyObject cancellation mismatch",
    "CopyObject drain was not acknowledged",
    "same-operation CopyObject restart mismatch",
    "lost CopyObject response was classified conclusively",
    "lost-response CopyObject reconciliation mismatch",
):
    if fragment not in socket:
        fail(f"CopyObject socket evidence lacks {fragment!r}")

print("CopyObject preparation evidence: OK")
