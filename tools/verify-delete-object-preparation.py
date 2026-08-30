#!/usr/bin/env python3
"""Fail-closed evidence for reviewed DeleteObject qualification."""

from __future__ import annotations

import json
import os
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODEL_SHA256 = (
    "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
)
REGISTRY = ROOT / "coverage" / "s3-operations.toml"
LOW_SPEC = ROOT / "src" / "flyology-object_storage-client-low_level.ads"
LOW_BODY = ROOT / "src" / "flyology-object_storage-client-low_level.adb"
OBJECTS_SPEC = ROOT / "src" / "flyology-object_storage-client-objects.ads"
OBJECTS_BODY = ROOT / "src" / "flyology-object_storage-client-objects.adb"
TESTING = (
    ROOT
    / "tests"
    / "src"
    / "flyology-object_storage-client-objects-testing.adb"
)
CERTAINTY = (
    ROOT
    / "tests"
    / "corpora"
    / "composable-client"
    / "delete-certainty.tsv"
)
FIXTURE_VERIFY = ROOT / "tools" / "verify-composable-client-fixtures.sh"
FIXTURE_NEGATIVE = (
    ROOT / "tools" / "test-composable-client-fixtures-verifier.sh"
)
SOCKET = ROOT / "tests" / "src" / "s3_http_socket_corpus.adb"
SERVER = (
    ROOT
    / "src"
    / "flyology-object_storage-server-s3_applications.adb"
)
SERVER_TEST = ROOT / "tests" / "src" / "s3_server_application_corpus.adb"
BACKEND = ROOT / "tests" / "src" / "object_storage_test_cases.adb"
SQLITE = (
    ROOT
    / "sqlite"
    / "tests"
    / "src"
    / "flyology_object_storage_sqlite_tests.adb"
)
IMPLEMENTATION = ROOT / "tests" / "src" / "s3_implementation_corpus.adb"
QUALIFICATION = ROOT / "docs" / "qualification" / "delete-object.md"


def require_once(text: str, marker: str, label: str) -> int:
    count = text.count(marker)
    assert count == 1, f"{label}: expected once, found {count}: {marker}"
    return text.index(marker)


def require_ordered(text: str, markers: list[str], label: str) -> None:
    positions = [require_once(text, marker, label) for marker in markers]
    assert positions == sorted(positions), f"{label}: evidence order changed"


def assert_order_rejects(markers: list[str], label: str) -> None:
    fixture = "\n".join(reversed(markers))
    positions = [fixture.index(marker) for marker in markers]
    assert positions != sorted(positions), f"{label}: reordered fixture passed"


def region(text: str, first: str, last: str, label: str) -> str:
    start = require_once(text, first, label)
    finish = require_once(text, last, label)
    assert start < finish, f"{label}: invalid boundary order"
    return text[start:finish]


def assert_regular(path: Path) -> None:
    assert path.exists(), f"missing evidence path: {path}"
    assert path.is_file(), f"non-file evidence path: {path}"
    assert not path.is_symlink(), f"symlink evidence path: {path}"


def load_model() -> dict[str, object]:
    model_path = os.environ.get("FLYOLOGY_S3_SERVICE_MODEL", "")
    assert model_path, "FLYOLOGY_S3_SERVICE_MODEL is required"
    path = Path(model_path)
    assert_regular(path)
    import hashlib

    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    assert digest == MODEL_SHA256, "pinned model hash changed"
    return json.loads(path.read_text(encoding="utf-8"))


def verify_model(model: dict[str, object]) -> None:
    operations = model["operations"]
    shapes = model["shapes"]
    operation = operations["DeleteObject"]
    assert operation["http"] == {
        "method": "DELETE",
        "requestUri": "/{Bucket}/{Key+}",
        "responseCode": 204,
    }
    assert operation["input"] == {"shape": "DeleteObjectRequest"}
    assert operation["output"] == {"shape": "DeleteObjectOutput"}
    request = shapes["DeleteObjectRequest"]
    assert request["required"] == ["Bucket", "Key"]
    members = request["members"]
    expected_input = [
        ("Bucket", "uri", "Bucket"),
        ("Key", "uri", "Key"),
        ("MFA", "header", "x-amz-mfa"),
        ("VersionId", "querystring", "versionId"),
        ("RequestPayer", "header", "x-amz-request-payer"),
        (
            "BypassGovernanceRetention",
            "header",
            "x-amz-bypass-governance-retention",
        ),
        (
            "ExpectedBucketOwner",
            "header",
            "x-amz-expected-bucket-owner",
        ),
        ("IfMatch", "header", "If-Match"),
        (
            "IfMatchLastModifiedTime",
            "header",
            "x-amz-if-match-last-modified-time",
        ),
        ("IfMatchSize", "header", "x-amz-if-match-size"),
    ]
    assert list(members) == [item[0] for item in expected_input]
    for name, location, wire_name in expected_input:
        assert members[name]["location"] == location
        assert members[name]["locationName"] == wire_name
    output = shapes["DeleteObjectOutput"]["members"]
    expected_output = [
        ("DeleteMarker", "x-amz-delete-marker"),
        ("VersionId", "x-amz-version-id"),
        ("RequestCharged", "x-amz-request-charged"),
    ]
    assert list(output) == [item[0] for item in expected_output]
    for name, wire_name in expected_output:
        assert output[name]["location"] == "header"
        assert output[name]["locationName"] == wire_name
    assert "errors" not in operation, "DeleteObject gained modeled errors"


def operation_entry(data: dict[str, object]) -> dict[str, object]:
    matches = [
        entry
        for entry in data["operation"]
        if entry["name"] == "DeleteObject"
    ]
    assert len(matches) == 1, "DeleteObject registry entry is not unique"
    return matches[0]


def verify_registry() -> None:
    data = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    assert data["model_sha256"] == MODEL_SHA256
    entry = operation_entry(data)
    expected = {
        "name": "DeleteObject",
        "tier": "core",
        "provider": "objects",
        "family": "bodyless_mutation",
        "public_provider": "Flyology.Object_Storage.Client.Objects",
        "codec": "bodyless_rest_xml_and_singleton_headers",
        "public_name": "Delete",
        "absence": (
            "an unconditioned missing current object is idempotent success; "
            "recognized exact NoSuchBucket, NoSuchKey, and NoSuchVersion S3 "
            "rejections are structured conclusive non-deletion results"
        ),
        "errors": [
            "authentication",
            "authorization",
            "not_found",
            "invalid_request",
            "unavailable_or_retryable",
            "corrupt_or_invalid_response",
        ],
        "certainty": (
            "only a complete validated 204 reports Deletion_Completed; "
            "a recognized exact S3 rejection or definite non-admission "
            "reports Definitely_Not_Deleted, pre-admission cancellation "
            "reports Deletion_Cancelled_Before_Admission, and every other "
            "possibly admitted or incomplete outcome reports "
            "Deletion_Outcome_Unknown; no automatic replay"
        ),
        "reconciliation": (
            "generation-bound HeadObject for the exact bucket, key, and "
            "selected version or generation predicate before retry"
        ),
        "exclusions": [
            (
                "directory-bucket endpoint and session behavior and "
                "directory-only time and size predicates are outside the "
                "qualified server profile"
            ),
            (
                "access-point, Object Lambda, and Outposts routing are not "
                "claimed"
            ),
            (
                "Requester Pays and true governance-retention bypass remain "
                "explicit server capability exclusions"
            ),
            (
                "durable retained-generation deletion outside the supported "
                "memory, pure-files, and SQLite profiles is not claimed"
            ),
            "deletion cannot roll back an already-published mutation",
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
        "evidence": {
            "backend": [
                "tests/src/object_storage_test_cases.adb",
                (
                    "sqlite/tests/src/"
                    "flyology_object_storage_sqlite_tests.adb"
                ),
            ],
            "client": [
                "src/flyology-object_storage-client-low_level.ads",
                "src/flyology-object_storage-client-low_level.adb",
                "src/flyology-object_storage-client-objects.ads",
                "src/flyology-object_storage-client-objects.adb",
                (
                    "tests/src/"
                    "flyology-object_storage-client-objects-testing.adb"
                ),
                "tests/corpora/composable-client/delete-certainty.tsv",
                "tools/verify-composable-client-fixtures.sh",
                "tools/test-composable-client-fixtures-verifier.sh",
                "tests/src/s3_http_socket_corpus.adb",
            ],
            "server": [
                (
                    "src/"
                    "flyology-object_storage-server-s3_applications.adb"
                ),
                "tests/src/s3_server_application_corpus.adb",
                "tests/src/s3_http_socket_corpus.adb",
            ],
            "corpus": [
                (
                    "tests/src/"
                    "flyology-object_storage-client-objects-testing.adb"
                ),
                "tests/corpora/composable-client/delete-certainty.tsv",
                "tools/verify-composable-client-fixtures.sh",
                "tools/test-composable-client-fixtures-verifier.sh",
                "tests/src/s3_http_socket_corpus.adb",
                "tests/src/s3_implementation_corpus.adb",
                "tests/src/s3_server_application_corpus.adb",
                "tests/scripts/run-s3-implementation.sh",
                "tests/scripts/run-s3-server-slice.sh",
                "tests/scripts/test-minio.sh",
                "tests/scripts/test-rustfs.sh",
                "tests/scripts/test-seaweedfs.sh",
            ],
        },
        "decision_status": "reviewed",
        "qualification": "delete_object",
        "ada_symbols": [
            "Prepare_Delete_Object",
            "Decode_Delete_Object_Complete_Response",
            "Execute_Delete_Object",
            "Delete_Operation",
            "Delete",
            "Finish",
        ],
    }
    assert entry == expected, "DeleteObject registry entry changed"
    expected_lane = [
        [
            "uv",
            "run",
            "--python",
            "3.13",
            "--",
            "tools/verify-delete-object-preparation.py",
        ],
        ["./tools/verify-composable-client-fixtures.sh"],
        ["./tools/test-composable-client-fixtures-verifier.sh"],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
        [
            "./tools/build-api-docs.sh",
            "/private/tmp/fos-delete-object-gnatdoc",
        ],
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    assert data["qualification"]["delete_object"] == expected_lane
    for paths in entry["evidence"].values():
        for item in paths:
            assert_regular(ROOT / item)


def verify_certainty() -> None:
    lines = CERTAINTY.read_text(encoding="utf-8").splitlines()
    assert lines[0].split("\t") == [
        "http_result",
        "admission",
        "status",
        "s3_code",
        "deletion",
        "failure_reason",
        "reconcile",
        "note",
    ]
    rows = [tuple(line.split("\t")) for line in lines[1:]]
    expected_rows = [
        (
            "Response_Complete", "Response_Observed", "204", "none",
            "Deletion_Completed", "No_Failure", "no",
            "complete modeled deletion success",
        ),
        (
            "Response_Complete", "Response_Observed", "412",
            "PreconditionFailed", "Definitely_Not_Deleted", "No_Failure",
            "no", "condition conclusively rejected",
        ),
        (
            "Response_Complete", "Response_Observed", "401",
            "InvalidAccessKeyId", "Definitely_Not_Deleted",
            "Authentication_Failed", "no",
            "authentication conclusively rejected",
        ),
        (
            "Response_Complete", "Response_Observed", "403", "AccessDenied",
            "Definitely_Not_Deleted", "Authorization_Failed", "no",
            "authorization conclusively rejected",
        ),
        (
            "Response_Complete", "Response_Observed", "400",
            "InvalidRequest", "Definitely_Not_Deleted", "Invalid_Request",
            "no", "exact recognized request rejection",
        ),
        (
            "Response_Complete", "Response_Observed", "404", "NoSuchBucket",
            "Definitely_Not_Deleted", "Not_Found", "no",
            "missing bucket conclusively rejected",
        ),
        (
            "Response_Complete", "Response_Observed", "404", "NoSuchKey",
            "Definitely_Not_Deleted", "Not_Found", "no",
            "missing exact key conclusively rejected",
        ),
        (
            "Response_Complete", "Response_Observed", "404", "NoSuchVersion",
            "Definitely_Not_Deleted", "Not_Found", "no",
            "missing exact version conclusively rejected",
        ),
        (
            "Response_Complete", "Response_Observed", "409",
            "OperationAborted", "Deletion_Outcome_Unknown",
            "Unavailable_Or_Retryable", "yes",
            "conflict response does not prove deletion disposition",
        ),
        (
            "Response_Complete", "Response_Observed", "429", "SlowDown",
            "Deletion_Outcome_Unknown", "Unavailable_Or_Retryable", "yes",
            "caller reconciles before retry",
        ),
        (
            "Response_Complete", "Response_Observed", "500", "InternalError",
            "Deletion_Outcome_Unknown", "Unavailable_Or_Retryable", "yes",
            "caller reconciles before retry",
        ),
        (
            "Response_Complete", "Response_Observed", "502", "BadGateway",
            "Deletion_Outcome_Unknown", "Unavailable_Or_Retryable", "yes",
            "caller reconciles before retry",
        ),
        (
            "Response_Complete", "Response_Observed", "503", "SlowDown",
            "Deletion_Outcome_Unknown", "Unavailable_Or_Retryable", "yes",
            "caller reconciles before retry",
        ),
        (
            "Response_Complete", "Response_Observed", "504",
            "RequestTimeout", "Deletion_Outcome_Unknown",
            "Unavailable_Or_Retryable", "yes",
            "caller reconciles before retry",
        ),
        (
            "Response_Complete", "Response_Observed", "400", "missing",
            "Deletion_Outcome_Unknown", "Corrupt_Or_Invalid_Response", "yes",
            "status alone does not prove semantic rejection",
        ),
        (
            "Response_Complete", "Response_Observed", "403", "missing",
            "Deletion_Outcome_Unknown", "Corrupt_Or_Invalid_Response", "yes",
            "unmodeled authorization body is not conclusive",
        ),
        (
            "Response_Complete", "Response_Observed", "404", "missing",
            "Deletion_Outcome_Unknown", "Corrupt_Or_Invalid_Response", "yes",
            "unmodeled not-found body is not conclusive",
        ),
        (
            "Response_Complete", "Response_Observed", "412", "missing",
            "Deletion_Outcome_Unknown", "Corrupt_Or_Invalid_Response", "yes",
            "unmodeled precondition body is not conclusive",
        ),
        (
            "Response_Complete", "Response_Observed", "500", "malformed",
            "Deletion_Outcome_Unknown", "Corrupt_Or_Invalid_Response", "yes",
            "malformed service response is not retry evidence",
        ),
        (
            "Pre_Admission_Rejected", "Not_Admitted", "none",
            "not-applicable", "Definitely_Not_Deleted", "Invalid_Request",
            "no", "HTTP validation rejected before handoff",
        ),
        (
            "Cancelled", "Not_Admitted", "none", "not-applicable",
            "Deletion_Cancelled_Before_Admission", "Cancelled", "no",
            "cancelled before possible admission",
        ),
        (
            "Cancelled", "Possibly_Admitted", "none", "not-applicable",
            "Deletion_Outcome_Unknown", "Cancelled", "yes",
            "local cancellation cannot retract admission",
        ),
        (
            "Cancelled", "Response_Observed", "incomplete",
            "not-applicable", "Deletion_Outcome_Unknown", "Cancelled", "yes",
            "partial response is not conclusive",
        ),
        (
            "Timed_Out", "Not_Admitted", "none", "not-applicable",
            "Definitely_Not_Deleted", "Timed_Out", "no",
            "deadline expired before handoff",
        ),
        (
            "Timed_Out", "Possibly_Admitted", "none", "not-applicable",
            "Deletion_Outcome_Unknown", "Timed_Out", "yes",
            "deadline after possible admission",
        ),
        (
            "Timed_Out", "Response_Observed", "incomplete", "not-applicable",
            "Deletion_Outcome_Unknown", "Timed_Out", "yes",
            "deadline with incomplete response",
        ),
        (
            "Client_Unavailable", "Not_Admitted", "none", "not-applicable",
            "Definitely_Not_Deleted", "Client_Unavailable", "no",
            "client rejected admission",
        ),
        (
            "Client_Unavailable", "Possibly_Admitted", "none",
            "not-applicable", "Deletion_Outcome_Unknown",
            "Client_Unavailable", "yes", "conservative monotonic certainty",
        ),
        (
            "Client_Unavailable", "Response_Observed", "incomplete",
            "not-applicable", "Deletion_Outcome_Unknown",
            "Client_Unavailable", "yes", "partial response is not conclusive",
        ),
        (
            "Connection_Failed", "Not_Admitted", "none", "not-applicable",
            "Definitely_Not_Deleted", "Connection_Failed", "no",
            "connect or secure failure before handoff",
        ),
        (
            "Connection_Failed", "Possibly_Admitted", "none",
            "not-applicable", "Deletion_Outcome_Unknown", "Connection_Failed",
            "yes", "conservative monotonic certainty",
        ),
        (
            "Connection_Failed", "Response_Observed", "incomplete",
            "not-applicable", "Deletion_Outcome_Unknown", "Connection_Failed",
            "yes", "partial response is not conclusive",
        ),
        (
            "Transport_Failed", "Not_Admitted", "none", "not-applicable",
            "Definitely_Not_Deleted", "Transport_Failed", "no",
            "no request handoff occurred",
        ),
        (
            "Transport_Failed", "Possibly_Admitted", "none",
            "not-applicable", "Deletion_Outcome_Unknown", "Transport_Failed",
            "yes", "lost accepted-request response",
        ),
        (
            "Transport_Failed", "Response_Observed", "incomplete",
            "not-applicable", "Deletion_Outcome_Unknown", "Transport_Failed",
            "yes", "partial response is not conclusive",
        ),
        (
            "Request_Source_Failed", "Not_Admitted", "none",
            "not-applicable", "Definitely_Not_Deleted",
            "Request_Source_Failed", "no",
            "source failure before request handoff",
        ),
        (
            "Request_Source_Failed", "Possibly_Admitted", "none",
            "not-applicable", "Deletion_Outcome_Unknown",
            "Request_Source_Failed", "yes",
            "partial admitted request is conservative unknown",
        ),
        (
            "Request_Source_Failed", "Response_Observed", "incomplete",
            "not-applicable", "Deletion_Outcome_Unknown",
            "Request_Source_Failed", "yes",
            "partial response is not conclusive",
        ),
        (
            "Response_Invalid", "Not_Admitted", "invalid", "not-applicable",
            "Definitely_Not_Deleted", "Corrupt_Or_Invalid_Response", "no",
            "invalid local response state precedes admission",
        ),
        (
            "Response_Invalid", "Possibly_Admitted", "invalid",
            "not-applicable", "Deletion_Outcome_Unknown",
            "Corrupt_Or_Invalid_Response", "yes",
            "invalid response state cannot disprove deletion",
        ),
        (
            "Response_Invalid", "Response_Observed", "invalid",
            "not-applicable", "Deletion_Outcome_Unknown",
            "Corrupt_Or_Invalid_Response", "yes",
            "deletion requires reconciliation",
        ),
        (
            "Response_Body_Too_Large", "Response_Observed", "oversized",
            "not-applicable", "Deletion_Outcome_Unknown",
            "Corrupt_Or_Invalid_Response", "yes",
            "oversized response cannot prove deletion disposition",
        ),
        (
            "Response_Sink_Failed", "Response_Observed", "overflow-or-fault",
            "not-applicable", "Deletion_Outcome_Unknown",
            "Corrupt_Or_Invalid_Response", "yes",
            "bounded error sink did not complete",
        ),
    ]
    assert rows == expected_rows, "DeleteObject certainty rows changed"


def verify_sources() -> None:
    low_spec = LOW_SPEC.read_text(encoding="utf-8")
    low_body = LOW_BODY.read_text(encoding="utf-8")
    objects_spec = OBJECTS_SPEC.read_text(encoding="utf-8")
    objects_body = OBJECTS_BODY.read_text(encoding="utf-8")
    testing = TESTING.read_text(encoding="utf-8")
    fixture = FIXTURE_VERIFY.read_text(encoding="utf-8")
    negative = FIXTURE_NEGATIVE.read_text(encoding="utf-8")
    socket = SOCKET.read_text(encoding="utf-8")
    server = SERVER.read_text(encoding="utf-8")

    low_spec_region = region(
        low_spec,
        "type Delete_Object_Parameters is record",
        "type Delete_Object_Annotation_Parameters is record",
        "DeleteObject Low_Level spec",
    )
    low_spec_markers = [
        "type Delete_Object_Parameters is record",
        "function Prepare_Delete_Object",
        "type Delete_Object_Result is record",
        "type Delete_Object_Outcome_Kind is",
        "type Delete_Object_Outcome\n     (Kind",
        "function Decode_Delete_Object_Response",
        "function Decode_Delete_Object_Complete_Response",
        "function Execute_Delete_Object",
        "DeleteObject is never transparently replayed",
    ]
    require_ordered(low_spec_region, low_spec_markers, "DeleteObject spec")
    assert_order_rejects(low_spec_markers, "DeleteObject spec negative")

    low_body_region = region(
        low_body,
        "function Prepare_Delete_Object\n     (Origin",
        "function Prepare_Delete_Object_Annotation\n     (Origin",
        "DeleteObject Low_Level body",
    )
    low_body_markers = [
        "function Prepare_Delete_Object\n     (Origin",
        'Prepare_Object_Request\n        (Delete_Object_Operation, "DELETE"',
        "function Decode_Delete_Object_Complete_Response",
        'Singleton_Header ("x-amz-delete-marker")',
        'Singleton_Header ("x-amz-version-id")',
        'Singleton_Header ("x-amz-request-charged")',
        "function Execute_Delete_Object",
        "Source : Non_Replayable_Empty_Source;",
    ]
    require_ordered(low_body_region, low_body_markers, "DeleteObject body")
    assert_order_rejects(low_body_markers, "DeleteObject body negative")

    public_region = region(
        objects_spec,
        "--  What is known about one DeleteObject mutation",
        "--  What is known about one DeleteObjects batch",
        "DeleteObject public composable region",
    )
    public_markers = [
        "type Deletion_Disposition is",
        "type Delete_Result_Kind is",
        "type Delete_Result\n     (Kind",
        "type Delete_Operation\n     (Set",
        "procedure Delete\n",
        "function Delete\n",
        "procedure Finish\n",
    ]
    require_ordered(public_region, public_markers, "DeleteObject public API")
    assert_order_rejects(public_markers, "DeleteObject API negative")
    sync_region = region(
        objects_spec,
        "--  Execute one DeleteObject by waiting on the composable operation",
        "--  Read the selected generation's legal hold",
        "DeleteObject synchronous overloads",
    )
    assert sync_region.count("function Delete\n") == 2
    assert sync_region.count("return Delete_Result;") == 1
    assert sync_region.count("return Delete_Outcome;") == 1

    lifecycle_region = region(
        objects_body,
        "function Normalize_Delete_Response",
        "function Normalize_Delete_Objects_Response",
        "DeleteObject lifecycle region",
    )
    lifecycle_markers = [
        "function Normalize_Delete_Response",
        "function Normalize_Delete_Failure",
        "return HTTP_Client.Known_Length (0);",
        "procedure Complete_Delete_Child",
        "procedure Start_Delete_Object",
        '"DeleteObject restart changed a retained owner"',
        "function Delete\n",
        "procedure Finish\n",
        "Operations.Consume (Operation);",
    ]
    require_ordered(
        lifecycle_region, lifecycle_markers, "DeleteObject lifecycle"
    )
    assert_order_rejects(lifecycle_markers, "DeleteObject lifecycle negative")
    for marker in [
        "Check_Delete_Certainty_Corpus",
        "Check_Delete_Response",
        "Check_Delete_Failure",
    ]:
        assert marker in testing, marker
    for marker in [
        'fail("duplicate DeleteObject input tuple")',
        'fail("missing HTTP result coverage for " required[i])',
        'fail("missing exact status/code coverage for " required[i])',
    ]:
        assert marker in fixture, marker
    for marker in [
        'expect_rejection "duplicate DeleteObject input tuple"',
        'expect_rejection "status-only DeleteObject precondition conclusion"',
        'expect_rejection "unknown deletion without reconciliation"',
    ]:
        assert marker in negative, marker

    assert (
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
        "      Put_Bucket_Versioning_Cancellation);" in socket
    )
    cancellation_region = region(
        socket,
        "if Await_Cancellation then",
        "elsif Response'Length = 0 then",
        "socket cancellation handshake",
    )
    cancellation_markers = [
        "Delete_Drain_Native.Request",
        "Delete_Drain_Lightweight.Request",
        "if Cancellation_Round not in 1 .. 2 then",
        "Delete_Admission_Native.Request",
        "Delete_Admission_Lightweight.Request",
        "Sockets.Receive (Peer, Buffer, Last, Timeout => 5.0);",
        "Sockets.Close_Socket (Peer);\n               exception",
        "Request_Drain;\n               return;",
    ]
    require_ordered(
        cancellation_region,
        cancellation_markers,
        "DeleteObject cancellation handshake",
    )
    assert_order_rejects(
        cancellation_markers,
        "DeleteObject cancellation handshake negative",
    )
    socket_server_region = region(
        socket,
        'Serve\n           ("", "DELETE", "/example-bucket/delete-cancel"',
        (
            "Serve\n"
            "           (HTTP_Response\n"
            '              ("204 No Content", "", '
            "Omit_Content_Length => True),\n"
            '            "DELETE", "/example-bucket/delete-restart");'
        ),
        "DeleteObject socket server region",
    )
    server_markers = [
        "Await_Cancellation => True",
        "Cancellation_Kind => Delete_Object_Cancellation",
        "Cancellation_Round => Round",
    ]
    require_ordered(socket_server_region, server_markers, "Delete server")
    assert_order_rejects(server_markers, "Delete server negative")
    assert socket.count(
        '"DELETE", "/example-bucket/delete-restart");'
    ) == 1
    socket_client_region = region(
        socket,
        "--  Five slots are the derived composed stack: deletion",
        '"pre-admission DeleteObject cancellation mismatch"',
        "DeleteObject socket client region",
    )
    client_markers = [
        "Delete_Admission_Native.Wait_Source",
        "Delete_Drain_Native.Wait_Source",
        "Delete_Admission_Lightweight.Wait_Source",
        "Delete_Drain_Lightweight.Wait_Source",
        "Operations.Wait_Some (Cancel_Set, Completed_Batch);",
        (
            "Operations.Cancel (Cancel_Operation);\n"
            "                  Operations.Wait_All (Cancel_Set);\n"
            "                  Finish (Cancel_Operation, Cancel_Result);"
        ),
        '"admitted DeleteObject cancellation mismatch"',
        '"DeleteObject transport drain was not acknowledged"',
        (
            '"delete-restart", Cancel_Parameters, Identity,\n'
            "                     HTTP_Client.Deadline_After (5.0),\n"
            "                     Operation => Cancel_Operation);\n"
            "                  Operations.Wait_All (Cancel_Set);\n"
            "                  Finish (Cancel_Operation, Cancel_Result);"
        ),
        '"same-object DeleteObject restart after "',
    ]
    require_ordered(socket_client_region, client_markers, "Delete client")
    assert_order_rejects(client_markers, "Delete client negative")
    for marker in [
        "Run_And_Report (1);",
        "Run_And_Report (2);",
        "when Count = 2",
    ]:
        assert socket.count(marker) == 1, marker
    lost_region = region(
        socket,
        '"lost-response DeleteObject priming HEAD mismatch"',
        "Request : Deletions.Delete_Objects_Request;",
        "DeleteObject lost-response region",
    )
    lost_markers = [
        '"lost DeleteObject response was classified conclusively"',
        "Low_Level.Execute_Head_Object",
        '"lost-response DeleteObject reconciliation mismatch"',
    ]
    require_ordered(lost_region, lost_markers, "Delete reconciliation")
    assert_order_rejects(lost_markers, "Delete reconciliation negative")

    server_region = region(
        server,
        "when Delete_Object =>",
        "when Delete_Objects =>",
        "DeleteObject server region",
    )
    server_product_markers = [
        "when Delete_Object =>",
        "Check_Expected_Bucket_Owner",
        "Store.Delete_Object",
        'Apps.Respond (X, 204, "", "");',
    ]
    require_ordered(server_region, server_product_markers, "Delete server")
    assert_order_rejects(server_product_markers, "Delete server negative")
    for path, marker in [
        (SERVER_TEST, "DeleteObject"),
        (BACKEND, "Delete_Object"),
        (SQLITE, "Delete_Object"),
        (IMPLEMENTATION, "Delete_Object"),
    ]:
        assert marker in path.read_text(encoding="utf-8"), marker
    qualification = QUALIFICATION.read_text(encoding="utf-8")
    for marker in [
        "non-rewindable HTTP source",
        "must reconcile the exact key/generation",
        "wait through transport drain",
        "restart the same consumed operation object",
        "no status or exception after publication",
    ]:
        assert marker in qualification, marker


def main() -> None:
    verify_model(load_model())
    verify_registry()
    verify_certainty()
    verify_sources()
    print("DeleteObject preparation evidence: OK")


if __name__ == "__main__":
    main()
