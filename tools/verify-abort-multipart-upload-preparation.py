#!/usr/bin/env python3
"""Fail-closed evidence for reviewed AbortMultipartUpload qualification."""

from __future__ import annotations

import json
import os
import tomllib
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODEL_SHA256 = (
    "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
)
REGISTRY = ROOT / "coverage" / "s3-operations.toml"
LOW_SPEC = ROOT / "src" / "flyology-object_storage-client-low_level.ads"
LOW_BODY = ROOT / "src" / "flyology-object_storage-client-low_level.adb"
TRANSFERS_SPEC = ROOT / "src" / "flyology-object_storage-client-transfers.ads"
TRANSFERS_BODY = ROOT / "src" / "flyology-object_storage-client-transfers.adb"
TESTING = (
    ROOT
    / "tests"
    / "src"
    / "flyology-object_storage-client-transfers-testing.adb"
)
CERTAINTY = (
    ROOT
    / "tests"
    / "corpora"
    / "composable-client"
    / "abort-multipart-certainty.tsv"
)
FIXTURE_VERIFY = ROOT / "tools" / "verify-composable-client-fixtures.sh"
FIXTURE_NEGATIVE = (
    ROOT / "tools" / "test-composable-client-fixtures-verifier.sh"
)
SOCKET = ROOT / "tests" / "src" / "s3_http_socket_corpus.adb"
BACKEND = ROOT / "tests" / "src" / "object_storage_test_cases.adb"
SQLITE = (
    ROOT
    / "sqlite"
    / "tests"
    / "src"
    / "flyology_object_storage_sqlite_tests.adb"
)
SERVER = (
    ROOT
    / "src"
    / "flyology-object_storage-server-s3_applications.adb"
)
SERVER_TEST = ROOT / "tests" / "src" / "s3_server_application_corpus.adb"
IMPLEMENTATION = ROOT / "tests" / "src" / "s3_implementation_corpus.adb"
QUALIFICATION = ROOT / "docs" / "qualification" / "abort-multipart-upload.md"

INPUT_MEMBERS = [
    "Bucket",
    "Key",
    "UploadId",
    "RequestPayer",
    "ExpectedBucketOwner",
    "IfMatchInitiatedTime",
]
INPUT_LOCATIONS = {
    "Bucket": ("uri", "Bucket"),
    "Key": ("uri", "Key"),
    "UploadId": ("querystring", "uploadId"),
    "RequestPayer": ("header", "x-amz-request-payer"),
    "ExpectedBucketOwner": ("header", "x-amz-expected-bucket-owner"),
    "IfMatchInitiatedTime": (
        "header",
        "x-amz-if-match-initiated-time",
    ),
}
OUTPUT_MEMBERS = ["RequestCharged"]
ERRORS = [
    "authentication",
    "authorization",
    "not_found",
    "invalid_request",
    "unavailable_or_retryable",
    "corrupt_or_invalid_response",
]
SYMBOLS = [
    "Prepare_Abort_Multipart_Upload",
    "Decode_Abort_Multipart_Complete_Response",
    "Execute_Abort_Multipart_Upload",
    "Abort_Multipart_Operation",
    "Abort_Multipart_Upload",
    "Finish",
]
EXCLUSIONS = [
    "server compatibility is limited to authenticated path-style "
    "general-purpose bucket requests; directory-bucket, access-point, "
    "Outposts, and Requester Pays server capabilities are not claimed",
    "the Flyology server applies IfMatchInitiatedTime atomically to "
    "general-purpose uploads as an explicit extension; no directory-bucket "
    "compatibility claim is inferred",
    "abort is cleanup and cannot roll back an object already published by "
    "completion",
]
EVIDENCE = {
    "backend": [
        "tests/src/object_storage_test_cases.adb",
        "sqlite/tests/src/flyology_object_storage_sqlite_tests.adb",
    ],
    "client": [
        "src/flyology-object_storage-client-low_level.ads",
        "src/flyology-object_storage-client-low_level.adb",
        "src/flyology-object_storage-client-transfers.ads",
        "src/flyology-object_storage-client-transfers.adb",
        "tests/src/flyology-object_storage-client-transfers-testing.adb",
        "tests/corpora/composable-client/abort-multipart-certainty.tsv",
        "tools/verify-composable-client-fixtures.sh",
        "tools/test-composable-client-fixtures-verifier.sh",
        "tests/src/s3_http_socket_corpus.adb",
    ],
    "server": [
        "src/flyology-object_storage-server-s3_applications.adb",
        "tests/src/s3_server_application_corpus.adb",
        "tests/src/s3_http_socket_corpus.adb",
    ],
    "corpus": [
        "tests/src/flyology-object_storage-client-transfers-testing.adb",
        "tests/corpora/composable-client/abort-multipart-certainty.tsv",
        "tools/verify-composable-client-fixtures.sh",
        "tools/test-composable-client-fixtures-verifier.sh",
        "tests/src/s3_http_socket_corpus.adb",
        "tests/src/s3_implementation_corpus.adb",
        "tests/src/s3_server_application_corpus.adb",
        "tests/scripts/test-minio.sh",
        "tests/scripts/test-rustfs.sh",
        "tests/scripts/test-seaweedfs.sh",
    ],
}
EXPECTED_ENTRY = {
    "name": "AbortMultipartUpload",
    "tier": "core",
    "provider": "transfers",
    "family": "bodyless_mutation",
    "public_provider": "Flyology.Object_Storage.Client.Transfers",
    "codec": "bodyless_rest_xml_and_singleton_headers",
    "public_name": "Abort_Multipart_Upload",
    "absence": (
        "no dedicated absence variant; NoSuchBucket, NoSuchKey, and "
        "NoSuchUpload remain structured typed rejections with unknown "
        "abort outcome"
    ),
    "errors": ERRORS,
    "certainty": (
        "only a complete validated 204 reports Multipart_Aborted; definite "
        "non-admission reports Definitely_Not_Aborted, pre-admission "
        "cancellation reports Abort_Cancelled_Before_Admission, and every "
        "rejection or possible admission reports Abort_Outcome_Unknown; no "
        "automatic replay"
    ),
    "reconciliation": (
        "read-only ListParts for the exact bucket, key, and upload "
        "identifier before any retry or completion decision"
    ),
    "exclusions": EXCLUSIONS,
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
    "evidence": EVIDENCE,
    "decision_status": "reviewed",
    "qualification": "abort_multipart_upload",
    "ada_symbols": SYMBOLS,
}
EXPECTED_LANE = [
    [
        "uv",
        "run",
        "--python",
        "3.13",
        "--",
        "tools/verify-abort-multipart-upload-preparation.py",
    ],
    ["./tools/verify-composable-client-fixtures.sh"],
    ["./tools/test-composable-client-fixtures-verifier.sh"],
    ["@tests", "alr", "-n", "build"],
    ["@tests", "./bin/s3_http_socket_corpus"],
    ["./tools/verify-coverage.sh"],
    [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-abort-multipart-upload-gnatdoc",
    ],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]


def require_once(text: str, marker: str, label: str) -> int:
    count = text.count(marker)
    assert count == 1, f"{label}: expected once, found {count}: {marker}"
    return text.index(marker)


def require_ordered(text: str, markers: list[str], label: str) -> None:
    positions = [require_once(text, marker, label) for marker in markers]
    assert positions == sorted(positions), f"{label}: evidence order changed"


def region(text: str, start: str, end: str, label: str) -> str:
    first = require_once(text, start, label)
    last = require_once(text, end, label)
    assert first < last, f"{label}: region order changed"
    return text[first:last]


def assert_order_rejects(markers: list[str], label: str) -> None:
    rendered = "\n".join(markers)
    require_ordered(rendered, markers, label)
    for index, marker in enumerate(markers):
        damaged = rendered.replace(marker, "", 1)
        try:
            require_ordered(damaged, markers, label)
        except AssertionError:
            pass
        else:
            raise AssertionError(f"{label}: missing marker {index} accepted")
    damaged = rendered + "\n" + markers[0]
    try:
        require_ordered(damaged, markers, label)
    except AssertionError:
        pass
    else:
        raise AssertionError(f"{label}: duplicate marker accepted")


def load_model() -> dict:
    model_path = os.environ.get("FLYOLOGY_S3_SERVICE_MODEL", "")
    assert model_path, "FLYOLOGY_S3_SERVICE_MODEL is required"
    path = Path(model_path)
    assert path.is_file() and not path.is_symlink(), "invalid model path"
    import hashlib

    assert hashlib.sha256(path.read_bytes()).hexdigest() == MODEL_SHA256
    return json.loads(path.read_text(encoding="utf-8"))


def verify_model(model: dict) -> None:
    operation = model["operations"]["AbortMultipartUpload"]
    assert operation["http"] == {
        "method": "DELETE",
        "requestUri": "/{Bucket}/{Key+}",
        "responseCode": 204,
    }
    assert operation["input"] == {"shape": "AbortMultipartUploadRequest"}
    assert operation["output"] == {"shape": "AbortMultipartUploadOutput"}
    assert operation["errors"] == [{"shape": "NoSuchUpload"}]
    request = model["shapes"]["AbortMultipartUploadRequest"]
    assert request["required"] == ["Bucket", "Key", "UploadId"]
    assert list(request["members"]) == INPUT_MEMBERS
    assert {
        name: (member["location"], member["locationName"])
        for name, member in request["members"].items()
    } == INPUT_LOCATIONS
    output = model["shapes"]["AbortMultipartUploadOutput"]
    assert list(output["members"]) == OUTPUT_MEMBERS
    assert output["members"]["RequestCharged"] == {
        "shape": "RequestCharged",
        "location": "header",
        "locationName": "x-amz-request-charged",
    }


def verify_registry() -> None:
    data = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    entries = [
        entry
        for entry in data["operation"]
        if entry["name"] == "AbortMultipartUpload"
    ]
    assert entries == [EXPECTED_ENTRY], "AbortMultipartUpload registry drift"
    assert data["qualification"]["abort_multipart_upload"] == EXPECTED_LANE
    for section in EVIDENCE.values():
        for relative in section:
            path = ROOT / relative
            assert path.is_file() and not path.is_symlink(), relative


def verify_certainty() -> None:
    lines = CERTAINTY.read_text(encoding="utf-8").splitlines()
    assert lines[0].split("\t") == [
        "http_result",
        "admission",
        "status",
        "s3_code",
        "abort",
        "failure_reason",
        "reconcile",
        "note",
    ]
    rows = [tuple(line.split("\t")) for line in lines[1:]]
    assert len(rows) == 45 and len(set(rows)) == 45
    keys = [(row[0], row[1], row[2], row[3]) for row in rows]
    assert len(set(keys)) == 45
    assert rows[0][:7] == (
        "Response_Complete",
        "Response_Observed",
        "204",
        "none",
        "Multipart_Aborted",
        "No_Failure",
        "no",
    )
    response_codes = Counter((row[2], row[3]) for row in rows[:15])
    assert response_codes == Counter(
        {
            ("204", "none"): 1,
            ("400", "InvalidRequest"): 1,
            ("401", "InvalidAccessKeyId"): 1,
            ("403", "AccessDenied"): 1,
            ("404", "NoSuchBucket"): 1,
            ("404", "NoSuchKey"): 1,
            ("404", "NoSuchUpload"): 1,
            ("409", "OperationAborted"): 1,
            ("412", "PreconditionFailed"): 1,
            ("429", "SlowDown"): 1,
            ("500", "InternalError"): 1,
            ("502", "BadGateway"): 1,
            ("503", "SlowDown"): 1,
            ("504", "RequestTimeout"): 1,
            ("400", "missing"): 1,
        }
    )
    for row in rows:
        assert row[7], "empty certainty note"
        assert (row[4] == "Abort_Outcome_Unknown") == (row[6] == "yes")
    no_such_upload = [row for row in rows if row[3] == "NoSuchUpload"]
    assert len(no_such_upload) == 1
    assert no_such_upload[0][4:7] == (
        "Abort_Outcome_Unknown",
        "Not_Found",
        "yes",
    )


def verify_sources() -> None:
    low_spec = LOW_SPEC.read_text(encoding="utf-8")
    low_body = LOW_BODY.read_text(encoding="utf-8")
    transfers_spec = TRANSFERS_SPEC.read_text(encoding="utf-8")
    transfers_body = TRANSFERS_BODY.read_text(encoding="utf-8")
    testing = TESTING.read_text(encoding="utf-8")
    fixture = FIXTURE_VERIFY.read_text(encoding="utf-8")
    fixture_negative = FIXTURE_NEGATIVE.read_text(encoding="utf-8")
    socket = SOCKET.read_text(encoding="utf-8")
    server = SERVER.read_text(encoding="utf-8")

    low_region = region(
        low_spec,
        (
            "--  Every non-resource member in the pinned "
            "AbortMultipartUpload input"
        ),
        "--  Every non-resource member in the pinned ListParts input shape.",
        "Low_Level spec region",
    )
    low_markers = [
        "type Abort_Multipart_Parameters is record",
        "type Abort_Multipart_Result is record",
        "type Abort_Multipart_Outcome_Kind is (Aborted, Abort_Rejected);",
        "function Decode_Abort_Multipart_Complete_Response",
        "function Execute_Abort_Multipart_Upload",
    ]
    require_ordered(low_region, low_markers, "Low_Level spec")
    assert_order_rejects(low_markers, "Low_Level spec negative")
    for marker in [
        'SigV4.Pair ("uploadId", Upload_ID)',
        'Add ("x-amz-request-payer", Request_Payer);',
        '"x-amz-expected-bucket-owner"',
        'Add ("x-amz-if-match-initiated-time", Initiated);',
        '"invalid AbortMultipartUpload header multiplicity"',
        '"invalid AbortMultipartUpload request-charged header"',
    ]:
        assert marker in low_body, marker

    public_region = region(
        transfers_spec,
        "--  What is known about one AbortMultipartUpload mutation after",
        "--  Shape of a terminal ListParts read.",
        "Transfers spec region",
    )
    public_markers = [
        "type Multipart_Abort_Disposition is",
        (
            "type Multipart_Abort_Result\n"
            "     (Kind : Multipart_Abort_Result_Kind"
        ),
        "type Abort_Multipart_Operation",
        "procedure Abort_Multipart_Upload",
        "function Abort_Multipart_Upload",
        (
            "procedure Finish\n"
            "     (Operation : in out Abort_Multipart_Operation;"
        ),
    ]
    require_ordered(public_region, public_markers, "Transfers spec")
    assert_order_rejects(public_markers, "Transfers spec negative")
    lifecycle_region = region(
        transfers_body,
        (
            "--  Exact status/code pairs are S3 wire authority for bounded "
            "diagnostics.\n"
            "   --  Only a validated 204 proves this abort request"
        ),
        "function Normalize_List_Parts_Response",
        "Transfers lifecycle region",
    )
    lifecycle_markers = [
        "function Normalize_Abort_Multipart_Response",
        "function Normalize_Abort_Multipart_Failure",
        "procedure Complete_Abort_Multipart_Child",
        (
            "Operation_Drivers.Complete (Item, Operations.Succeeded);\n"
            "            return;"
        ),
        (
            "end;\n"
            "      Operations.Release (Item.Child);\n"
            "      if HTTP_Client.Kind (HTTP_Result)"
        ),
        (
            "Operation_Drivers.Complete (Item, Operations.Succeeded);\n"
            "   end Complete_Abort_Multipart_Child;"
        ),
        "procedure Start_Abort_Multipart_Upload",
        '"AbortMultipartUpload restart changed a retained owner"',
        (
            "procedure Finish\n"
            "     (Operation : in out Abort_Multipart_Operation;"
        ),
        "Operations.Consume (Operation);",
    ]
    require_ordered(
        lifecycle_region, lifecycle_markers, "Transfers lifecycle"
    )
    for marker in [
        "Check_Abort_Multipart_Response (204, \"\", No_Failure);",
        '(404, "NoSuchUpload", Not_Found);',
        "for Kind of Failure_Kinds loop",
        "for Admission in HTTP_Client.Admission_Certainty loop",
    ]:
        assert marker in testing, marker
    for marker in [
        'fail("duplicate AbortMultipartUpload input tuple")',
        'fail("missing AbortMultipartUpload HTTP result "',
        'fail("missing AbortMultipartUpload status/code "',
        'if (NR - 1 < 45)',
    ]:
        assert marker in fixture, marker
    for marker in [
        'expect_rejection "duplicate AbortMultipartUpload input tuple"',
        'expect_rejection "unknown abort outcome without reconciliation"',
        'expect_rejection "modeled abort rejection treated as conclusive"',
    ]:
        assert marker in fixture_negative, marker

    socket_server_region = region(
        socket,
        'Serve\n           ("", "DELETE",\n'
        '            "/example-bucket/abort-cancel?uploadId=abort-cancel-id"',
        "Serve\n           (HTTP_Response\n"
        '              ("200 OK", Versions_Complete_XML,',
        "socket abort server region",
    )
    socket_server_markers = [
        "Await_Cancellation => True",
        "Cancellation_Kind => Abort_Multipart_Cancellation",
        "Cancellation_Round => Round",
        '"/example-bucket/abort-restart?uploadId=abort-restart-id"',
    ]
    require_ordered(
        socket_server_region,
        socket_server_markers,
        "socket abort server",
    )
    assert_order_rejects(
        socket_server_markers, "socket abort server negative"
    )
    cancellation_kinds = (
        "type Cancellation_Exchange is\n"
        "     (List_Objects_V2_Cancellation,\n"
        "      Put_Object_Cancellation,\n"
        "      Delete_Object_Cancellation,\n"
        "      Complete_Multipart_Cancellation,\n"
        "      Abort_Multipart_Cancellation,\n"
        "      Copy_Object_Cancellation,\n"
        "      Create_Bucket_Cancellation,\n"
        "      Delete_Bucket_Cancellation,\n"
        "      Create_Multipart_Cancellation,\n"
        "      Get_Bucket_Location_Cancellation,\n"
        "      Get_Bucket_Versioning_Cancellation,\n"
        "      Put_Bucket_Versioning_Cancellation);"
    )
    require_once(socket, cancellation_kinds, "cancellation kind inventory")
    cancellation_region = region(
        socket,
        "if Await_Cancellation then",
        "elsif Response'Length = 0 then",
        "socket cancellation handshake",
    )
    cancellation_markers = [
        (
            "when Abort_Multipart_Cancellation =>\n"
            "                        if Cancellation_Round = 1 then\n"
            "                           Abort_Drain_Native.Request;"
        ),
        "Abort_Drain_Lightweight.Request",
        "if Cancellation_Round not in 1 .. 2 then",
        (
            "when Abort_Multipart_Cancellation =>\n"
            "                     if Cancellation_Round = 1 then\n"
            "                        Abort_Admission_Native.Request;"
        ),
        "Abort_Admission_Lightweight.Request",
        "Sockets.Receive (Peer, Buffer, Last, Timeout => 5.0);",
        "Sockets.Close_Socket (Peer);\n               exception",
        "Request_Drain;\n                        "
        "Ada.Exceptions.Reraise_Occurrence (Saved);",
        "Request_Drain;\n               return;",
    ]
    require_ordered(
        cancellation_region,
        cancellation_markers,
        "socket cancellation handshake",
    )
    assert_order_rejects(
        cancellation_markers,
        "socket cancellation handshake negative",
    )
    socket_client_region = region(
        socket,
        "--  Five slots are the derived composed stack: abort",
        (
            "declare\n"
            "            Parameters : "
            "Low_Level.List_Object_Versions_Parameters;\n"
            "         begin\n"
            "            Parameters.Delimiter := "
            "US.To_Unbounded_String (\"/\");"
        ),
        "socket abort client region",
    )
    socket_client_markers = [
        "Abort_Admission_Native.Wait_Source",
        "Abort_Drain_Native.Wait_Source",
        "Abort_Admission_Lightweight.Wait_Source",
        "Abort_Drain_Lightweight.Wait_Source",
        (
            "Operations.Wait_Some\n"
            "                          (Cancel_Set, Completed_Batch);"
        ),
        (
            "Operations.Cancel (Cancel_Operation);\n"
            "                        Operations.Wait_All (Cancel_Set);\n"
            "                        Finish (Cancel_Operation, Abort_Result);"
        ),
        '"admitted AbortMultipartUpload cancellation "',
        '"AbortMultipartUpload transport drain was not "',
        (
            '"abort-restart-id",\n'
            "                           Abort_Parameters,\n"
            "                           Identity,\n"
            "                           HTTP_Client.Deadline_After (5.0),\n"
            "                           Operation => Cancel_Operation);\n"
            "                        Operations.Wait_All (Cancel_Set);\n"
            "                        Finish (Cancel_Operation, Abort_Result);"
        ),
        '"same-object AbortMultipartUpload restart "',
    ]
    require_ordered(
        socket_client_region,
        socket_client_markers,
        "socket abort client lifecycle",
    )
    assert_order_rejects(
        socket_client_markers, "socket abort client lifecycle negative"
    )
    for marker in [
        "Run_And_Report (1);",
        "Run_And_Report (2);",
        "when Count = 2",
    ]:
        assert socket.count(marker) == 1, marker
    lost_region = region(
        socket,
        '"AbortMultipartUpload lost-response setup failed"',
        '"UploadPartCopy lost-response connection prime failed"',
        "lost abort response region",
    )
    lost_markers = [
        '"lost AbortMultipartUpload response certainty mismatch"',
        '"lost AbortMultipartUpload reconciliation failed"',
    ]
    require_ordered(lost_region, lost_markers, "lost abort reconciliation")
    assert_order_rejects(lost_markers, "lost abort reconciliation negative")
    for text, marker in [
        (BACKEND.read_text(encoding="utf-8"), "Abort_Multipart_Upload"),
        (SQLITE.read_text(encoding="utf-8"), "Abort_Multipart_Upload"),
        (SERVER_TEST.read_text(encoding="utf-8"),
         "x-amz-if-match-initiated-time"),
        (IMPLEMENTATION.read_text(encoding="utf-8"),
         "Abort_Multipart_Upload"),
    ]:
        assert marker in text, marker
    server_region = region(
        server,
        "when Abort_Multipart =>",
        "when Copy_Object =>",
        "server abort region",
    )
    server_markers = [
        "when Abort_Multipart =>",
        (
            "Apps.Request_Header_Count\n"
            "                      (X, "
            '"x-amz-if-match-initiated-time")'
        ),
        "Check_Expected_Bucket_Owner",
        (
            "Apps.Request_Header\n"
            "                                 (X, "
            '"x-amz-if-match-initiated-time")'
        ),
        "Store.Abort_Multipart_Upload",
        "Apps.Respond (X, 204, \"\", \"\");",
    ]
    require_ordered(server_region, server_markers, "server abort boundary")
    assert_order_rejects(server_markers, "server abort negative")
    qualification = QUALIFICATION.read_text(encoding="utf-8")
    for marker in [
        "non-rewindable known-empty request source",
        "Every complete S3 rejection",
        "exact-upload ListParts\nreconciliation",
        "cannot roll back a destination object already",
    ]:
        assert marker in qualification, marker


def main() -> None:
    verify_model(load_model())
    verify_registry()
    verify_certainty()
    verify_sources()
    print("AbortMultipartUpload preparation evidence: OK")


if __name__ == "__main__":
    main()
