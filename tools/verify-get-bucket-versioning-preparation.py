#!/usr/bin/env python3
"""Fail-closed evidence for reviewed GetBucketVersioning qualification."""

from __future__ import annotations

import copy
import hashlib
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
BUCKETS_SPEC = ROOT / "src" / "flyology-object_storage-client-buckets.ads"
BUCKETS_BODY = ROOT / "src" / "flyology-object_storage-client-buckets.adb"
TESTING = (
    ROOT / "tests" / "src" /
    "flyology-object_storage-client-buckets-testing.adb"
)
SOCKET = ROOT / "tests" / "src" / "s3_http_socket_corpus.adb"
SERVER = ROOT / "src" / "flyology-object_storage-server-s3_applications.adb"
SERVER_TEST = ROOT / "tests" / "src" / "s3_server_application_corpus.adb"
BACKEND = ROOT / "tests" / "src" / "object_storage_test_cases.adb"
SQLITE = (
    ROOT / "sqlite" / "tests" / "src" /
    "flyology_object_storage_sqlite_tests.adb"
)
IMPLEMENTATION = ROOT / "tests" / "src" / "s3_implementation_corpus.adb"
QUALIFICATION = (
    ROOT / "docs" / "qualification" / "get-bucket-versioning.md"
)


def regular(path: Path) -> None:
    assert path.is_file(), f"missing evidence path: {path}"
    assert not path.is_symlink(), f"symlink evidence path: {path}"


def once(text: str, marker: str, label: str) -> int:
    count = text.count(marker)
    assert count == 1, f"{label}: expected once, found {count}: {marker}"
    return text.index(marker)


def ordered(text: str, markers: list[str], label: str) -> None:
    cursor = 0
    for marker in markers:
        position = text.find(marker, cursor)
        assert position >= 0, f"{label}: missing ordered marker: {marker}"
        cursor = position + len(marker)


def unique_region(text: str, start: str, end: str, label: str) -> str:
    start_at = once(text, start, label)
    end_at = text.find(end, start_at + len(start))
    assert end_at >= 0, f"{label}: missing region end: {end}"
    return text[start_at:end_at]


def load_model() -> dict[str, object]:
    name = os.environ.get("FLYOLOGY_S3_SERVICE_MODEL", "")
    assert name, "FLYOLOGY_S3_SERVICE_MODEL is required"
    path = Path(name)
    regular(path)
    assert hashlib.sha256(path.read_bytes()).hexdigest() == MODEL_SHA256
    return json.loads(path.read_text(encoding="utf-8"))


def verify_model(model: dict[str, object]) -> None:
    operation = model["operations"]["GetBucketVersioning"]
    assert operation["http"] == {
        "method": "GET",
        "requestUri": "/{Bucket}?versioning",
    }
    assert operation["input"] == {
        "shape": "GetBucketVersioningRequest"
    }
    assert operation["output"] == {
        "shape": "GetBucketVersioningOutput"
    }
    request = model["shapes"]["GetBucketVersioningRequest"]
    assert request["required"] == ["Bucket"]
    assert list(request["members"]) == ["Bucket", "ExpectedBucketOwner"]
    assert request["members"]["Bucket"]["location"] == "uri"
    owner = request["members"]["ExpectedBucketOwner"]
    assert owner["location"] == "header"
    assert owner["locationName"] == "x-amz-expected-bucket-owner"
    output = model["shapes"]["GetBucketVersioningOutput"]
    assert list(output["members"]) == ["Status", "MFADelete"]
    assert model["shapes"]["BucketVersioningStatus"]["enum"] == [
        "Enabled",
        "Suspended",
    ]
    assert model["shapes"]["MFADeleteStatus"]["enum"] == [
        "Enabled",
        "Disabled",
    ]


def operation_entry(data: dict[str, object]) -> dict[str, object]:
    matches = [
        item
        for item in data["operation"]
        if item["name"] == "GetBucketVersioning"
    ]
    assert len(matches) == 1, "GetBucketVersioning entry is not unique"
    return matches[0]


def verify_registry(data: dict[str, object] | None = None) -> None:
    if data is None:
        data = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    entry = operation_entry(data)
    expected = {
        "tier": "core",
        "provider": "buckets",
        "family": "bounded_rest_xml_read",
        "public_provider": "Flyology.Object_Storage.Client.Buckets",
        "codec": "rest_xml_and_headers",
        "public_name": "Get_Versioning",
        "errors": [
            "authentication",
            "authorization",
            "not_found",
            "invalid_request",
            "unavailable_or_retryable",
            "corrupt_or_invalid_response",
        ],
        "certainty": "read_only",
        "reconciliation": "not_applicable",
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
        "qualification": "get_bucket_versioning",
        "ada_symbols": [
            "Prepare_Get_Bucket_Versioning",
            "Decode_Get_Bucket_Versioning_Response",
            "Execute_Get_Bucket_Versioning",
            "Get_Bucket_Versioning_Operation",
            "Get_Versioning",
            "Finish",
        ],
    }
    for key, value in expected.items():
        assert entry[key] == value, f"GetBucketVersioning changed: {key}"
    assert entry["absence"] == (
        "a 200 response with omitted Status and MFADelete is a successful "
        "Versioning_Unconfigured snapshot; no dedicated absence variant "
        "exists and exact NoSuchBucket remains a bounded structured typed "
        "rejection"
    )
    assert entry["exclusions"] == [
        (
            "qualification covers caller-supplied origins for "
            "general-purpose buckets; directory-bucket and S3 Express "
            "endpoint selection is not claimed"
        ),
        (
            "access-point, Object Lambda, and Outposts endpoint discovery "
            "or rewriting is not claimed"
        ),
        "cross-region redirect following is not qualified",
        (
            "the read reports configured versioning and MFA Delete state "
            "but does not authorize or perform either mutation"
        ),
    ]
    assert entry["evidence"]["client"] == [
        "src/flyology-object_storage-client-low_level.ads",
        "src/flyology-object_storage-client-low_level.adb",
        "src/flyology-object_storage-client-buckets.ads",
        "src/flyology-object_storage-client-buckets.adb",
        "tests/src/flyology-object_storage-client-buckets-testing.adb",
        "tests/src/s3_http_socket_corpus.adb",
    ]
    assert entry["evidence"]["backend"] == [
        "tests/src/object_storage_test_cases.adb",
        "sqlite/tests/src/flyology_object_storage_sqlite_tests.adb",
    ]
    assert entry["evidence"]["server"] == [
        "src/flyology-object_storage-server-s3_applications.adb",
        "tests/src/s3_server_application_corpus.adb",
        "tests/src/s3_http_socket_corpus.adb",
    ]
    assert entry["evidence"]["corpus"] == [
        "tests/src/flyology-object_storage-client-buckets-testing.adb",
        "tests/src/s3_http_socket_corpus.adb",
        "tests/src/s3_implementation_corpus.adb",
        "tests/src/s3_server_application_corpus.adb",
    ]
    assert data["qualification"]["get_bucket_versioning"] == [
        [
            "uv",
            "run",
            "--python",
            "3.13",
            "--",
            "tools/verify-get-bucket-versioning-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
        [
            "./tools/build-api-docs.sh",
            "/private/tmp/fos-get-bucket-versioning-gnatdoc",
        ],
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]


def verify_normalization(testing: str, buckets_body: str) -> None:
    failure_region = testing[
        once(
            testing,
            "procedure Check_Get_Bucket_Versioning_Result_Corpus is",
            "normalization",
        ) : once(
            testing,
            "procedure Check_Put_Bucket_Versioning_Response",
            "normalization",
        )
    ]
    response_cases = [
        '(200, "", No_Failure)',
        '(400, "InvalidBucketName", Invalid_Request)',
        '(400, "InvalidRequest", Invalid_Request)',
        '(401, "InvalidAccessKeyId", Authentication_Failed)',
        '(403, "AccessDenied", Authorization_Failed)',
        '(404, "NoSuchBucket", Not_Found)',
        '(409, "OperationAborted", Unavailable_Or_Retryable)',
        '(429, "SlowDown", Unavailable_Or_Retryable)',
        '(500, "InternalError", Unavailable_Or_Retryable)',
        '(502, "BadGateway", Unavailable_Or_Retryable)',
        '(503, "SlowDown", Unavailable_Or_Retryable)',
        '(504, "RequestTimeout", Unavailable_Or_Retryable)',
        '(501, "NotImplemented", Invalid_Request)',
        '(409, "", Corrupt_Or_Invalid_Response)',
    ]
    for case in response_cases:
        assert failure_region.count(case) == 1, (
            f"normalization case changed: {case}"
        )
    failure_kinds = [
        "Pre_Admission_Rejected",
        "Cancelled",
        "Timed_Out",
        "Client_Unavailable",
        "Connection_Failed",
        "Transport_Failed",
        "Request_Source_Failed",
        "Response_Invalid",
        "Response_Body_Too_Large",
        "Response_Sink_Failed",
    ]
    for kind in failure_kinds:
        assert failure_region.count("HTTP_Client." + kind) == 1
    assert "for Admission in HTTP_Client.Admission_Certainty loop" in (
        failure_region
    )
    assert "Check_Get_Bucket_Versioning_Failure (Kind, Admission);" in (
        failure_region
    )
    ordered(
        buckets_body,
        [
            "function Normalize_Get_Bucket_Versioning_Response",
            "function Normalize_Get_Bucket_Versioning_Failure",
            "overriding procedure Write",
            "procedure Complete_Get_Bucket_Versioning_Child",
            "overriding procedure Drive",
            "overriding procedure Request_Cancellation",
            "procedure Start_Get_Bucket_Versioning",
            '"GetBucketVersioning restart changed a retained owner"',
            "function Get_Versioning",
            "procedure Finish",
        ],
        "provider lifecycle",
    )


def exact_ordered(region: str, markers: list[str], label: str) -> None:
    ordered(region, markers, label)
    for marker in markers:
        assert region.count(marker) == 1, (
            f"{label}: marker count differs: {marker}"
        )


def verify_socket_lifecycle(socket: str) -> None:
    server = unique_region(
        socket,
        '"", "GET", "/get-versioning-cancel?versioning",',
        '"PUT", "/typed-put-versioning?versioning",',
        "GetBucketVersioning server lifecycle",
    )
    exact_ordered(
        server,
        [
            '"", "GET", "/get-versioning-cancel?versioning",',
            'Expected_Bucket_Owner => "123456789012",',
            "Await_Cancellation => True,",
            "Cancellation_Kind => Get_Bucket_Versioning_Cancellation,",
            "Cancellation_Round => Round);",
            '"200 OK", "<VersioningConfiguration/>"',
            '"GET", "/get-versioning-cancel-restart?versioning",',
        ],
        "GetBucketVersioning server lifecycle",
    )
    lifecycle = unique_region(
        socket,
        '"get-versioning-cancelled",',
        "Low_Level.Put_Bucket_Versioning_Parameters :=",
        "GetBucketVersioning client lifecycle",
    )
    ordered(
        lifecycle,
        [
            '"get-versioning-cancelled",',
            "Result.Failure /= Client_API.Cancelled",
            "Result.Admission /= HTTP_Client.Not_Admitted",
            '"pre-admission GetBucketVersioning cancellation " &',
            "Get_Versioning_Admission_Native.Wait_Source",
            "Get_Versioning_Drain_Native.Wait_Source",
            "Get_Versioning_Admission_Lightweight.Wait_Source",
            "Get_Versioning_Drain_Lightweight.Wait_Source",
            "Operations.Completion_Set (5)",
            '"get-versioning-cancel",',
            "Operations.Wait_Some (Cancel_Set, Completed_Batch);",
            "Operations.Is_Terminal (Admission_Ready)",
            "Operations.Is_Active (Drain_Ready)",
            "Operations.Is_Active (Cancel_Operation)",
            "Flyology.IO.Finish (Admission_Ready);",
            "Operations.Cancel (Cancel_Operation);",
            "Operations.Wait_All (Cancel_Set);",
            "Finish (Cancel_Operation, Cancel_Result);",
            "Cancel_Result.Failure /= Client_API.Cancelled",
            "Cancel_Result.HTTP_Result /= HTTP_Client.Cancelled",
            "HTTP_Client.Possibly_Admitted",
            "Operations.Is_Terminal (Drain_Ready)",
            "Flyology.IO.Finish (Drain_Ready);",
            '"get-versioning-cancel-restart",',
            "Token => Changed_Token'Access,",
            "Operation => Cancel_Operation);",
            "when Program_Error =>",
            "Changed_Owner_Rejected := True;",
            '"GetBucketVersioning accepted changed retained owner"',
            '"get-versioning-cancel-restart",',
            "Token => Cancel_Token'Access,",
            "Operation => Cancel_Operation);",
            "Operations.Wait_All (Cancel_Set);",
            "Finish (Cancel_Operation, Cancel_Result);",
            "HTTP_Client.Response_Observed",
            "Low_Level.Bucket_Versioning_Found",
            "Flyology.Object_Storage.Versioning_Unconfigured",
            '"same-operation GetBucketVersioning restart mismatch"',
        ],
        "GetBucketVersioning client lifecycle",
    )
    for marker, count in (
        ("Operations.Wait_All (Cancel_Set);", 2),
        ("Finish (Cancel_Operation, Cancel_Result);", 2),
        ("Operation => Cancel_Operation);", 2),
        ("Token => Changed_Token'Access,", 1),
        ("Token => Cancel_Token'Access,", 1),
        ("HTTP_Client.Possibly_Admitted", 1),
        ("HTTP_Client.Response_Observed", 1),
        ("Flyology.IO.Finish (Drain_Ready);", 1),
        ('"get-versioning-cancel-restart",', 2),
    ):
        assert lifecycle.count(marker) == count, (
            "GetBucketVersioning client lifecycle count differs: "
            f"{marker}"
        )


def reject_socket_lifecycle(
    original: str, candidate: str, diagnostic: str
) -> None:
    assert candidate != original
    try:
        verify_socket_lifecycle(candidate)
    except AssertionError:
        return
    raise AssertionError(diagnostic)


def mutate_socket_lifecycle(
    original: str, old: str, new: str, count: int = 1
) -> str:
    start_marker = '"get-versioning-cancelled",'
    end_marker = "Low_Level.Put_Bucket_Versioning_Parameters :="
    start_at = once(original, start_marker, "lifecycle negative")
    end_at = original.find(end_marker, start_at + len(start_marker))
    assert end_at >= 0
    region = original[start_at:end_at]
    assert region.count(old) == count, (
        f"lifecycle negative source count differs: {old}"
    )
    return (
        original[:start_at]
        + region.replace(old, new, 1)
        + original[end_at:]
    )


def verify_coverage_evidence(
    backend: str,
    sqlite: str,
    implementation: str,
    server: str,
    server_test: str,
) -> None:
    backend_region = unique_region(
        backend,
        "procedure Check_Bucket_Versioning (Unused : in out Fixture) is",
        "end Check_Bucket_Versioning;",
        "backend versioning corpus",
    )
    exact_ordered(
        backend_region,
        [
            '"new bucket did not report unconfigured versioning"',
            '"atomic independent versioning fields did not merge"',
            '"missing bucket versioning classification"',
            '"files versioning configuration did not persist"',
            '"typed GetBucketVersioning request projection"',
            '"typed GetBucketVersioning success decode"',
            '"typed GetBucketVersioning error decode"',
        ],
        "backend versioning corpus",
    )
    for marker in (
        '"SQLite backend invented initial versioning configuration"',
        '"SQLite backend versioning fields did not merge atomically"',
        '"SQLite denied MFA update changed stored configuration"',
        '"SQLite versioning did not distinguish a missing bucket"',
    ):
        once(sqlite, marker, "SQLite versioning corpus")
    implementation_region = unique_region(
        implementation,
        "procedure Require_Bucket_Versioning",
        "end Require_Bucket_Versioning;",
        "implementation versioning corpus",
    )
    ordered(
        implementation_region,
        [
            "Initial.Configuration.Status /=",
            "Flyology.Object_Storage.Versioning_Unconfigured",
            "Enabled_Value.Configuration.Status /=",
            "Flyology.Object_Storage.Versioning_Enabled",
            "Suspended_Value.Configuration.Status /=",
            "Flyology.Object_Storage.Versioning_Suspended",
            '"bucket versioning configuration oracle mismatch"',
        ],
        "implementation versioning corpus",
    )
    for marker in (
        "Initial.Configuration.Status /=",
        "Enabled_Value.Configuration.Status /=",
        "Suspended_Value.Configuration.Status /=",
        '"bucket versioning configuration oracle mismatch"',
    ):
        assert implementation_region.count(marker) == 1, (
            "implementation versioning corpus count differs: " + marker
        )
    server_region = unique_region(
        server,
        "when Get_Bucket_Versioning =>",
        "when Delete_Bucket =>",
        "server GetBucketVersioning handler",
    )
    exact_ordered(
        server_region,
        [
            "Check_Expected_Bucket_Owner",
            "Store.Get_Bucket_Versioning",
            "Versioning.Serialize_Response (Configuration)",
            "Send_Backend_Error",
        ],
        "server GetBucketVersioning handler",
    )
    server_test_region = unique_region(
        server_test,
        '"versioning corpus bucket creation failed"',
        '"versioning corpus bucket cleanup failed"',
        "server GetBucketVersioning corpus",
    )
    exact_ordered(
        server_test_region,
        [
            '"GetBucketVersioning did not preserve initial absence"',
            '"GetBucketVersioning did not return enabled status"',
            '"GetBucketVersioning lost verified MFA Delete state"',
            '"GetBucketVersioning accepted duplicate subresources"',
            '"GetBucketVersioning accepted a mismatched operation ID"',
            '"GetBucketVersioning accepted a nonempty subresource value"',
            '"GetBucketVersioning accepted a request body"',
            '"GetBucketVersioning did not classify a missing bucket"',
        ],
        "server GetBucketVersioning corpus",
    )


def verify_sources() -> None:
    paths = [
        LOW_SPEC,
        LOW_BODY,
        BUCKETS_SPEC,
        BUCKETS_BODY,
        TESTING,
        SOCKET,
        SERVER,
        SERVER_TEST,
        BACKEND,
        SQLITE,
        IMPLEMENTATION,
        QUALIFICATION,
    ]
    for path in paths:
        regular(path)
    low_spec = LOW_SPEC.read_text(encoding="utf-8")
    low_body = LOW_BODY.read_text(encoding="utf-8")
    buckets_spec = BUCKETS_SPEC.read_text(encoding="utf-8")
    buckets_body = BUCKETS_BODY.read_text(encoding="utf-8")
    testing = TESTING.read_text(encoding="utf-8")
    socket = SOCKET.read_text(encoding="utf-8")
    server = SERVER.read_text(encoding="utf-8")
    server_test = SERVER_TEST.read_text(encoding="utf-8")
    backend = BACKEND.read_text(encoding="utf-8")
    sqlite = SQLITE.read_text(encoding="utf-8")
    implementation = IMPLEMENTATION.read_text(encoding="utf-8")
    qualification = QUALIFICATION.read_text(encoding="utf-8")
    ordered(
        low_spec,
        [
            "type Get_Bucket_Versioning_Parameters is record",
            "function Prepare_Get_Bucket_Versioning",
            "type Get_Bucket_Versioning_Outcome_Kind is",
            "function Decode_Get_Bucket_Versioning_Response",
            "function Execute_Get_Bucket_Versioning",
            "procedure Get_Bucket_Versioning",
        ],
        "Low_Level contract",
    )
    ordered(
        low_body,
        [
            "function Prepare_Get_Bucket_Versioning",
            '"invalid GetBucketVersioning owner header"',
            "function Decode_Get_Bucket_Versioning_Response",
            "function Execute_Get_Bucket_Versioning",
            '"GetBucketVersioning response exceeds XML limit"',
        ],
        "Low_Level implementation",
    )
    ordered(
        buckets_spec,
        [
            "type Get_Bucket_Versioning_Result_Kind is",
            "type Get_Bucket_Versioning_Result",
            "type Get_Bucket_Versioning_Operation",
            "procedure Get_Versioning",
            "function Get_Versioning",
            "procedure Finish",
        ],
        "public contract",
    )
    verify_normalization(testing, buckets_body)
    verify_socket_lifecycle(socket)
    for lane in (
        "Get_Versioning_Admission_Native",
        "Get_Versioning_Admission_Lightweight",
        "Get_Versioning_Drain_Native",
        "Get_Versioning_Drain_Lightweight",
    ):
        assert socket.count(lane) >= 3, f"lifecycle lane changed: {lane}"
    assert socket.count("Get_Bucket_Versioning_Cancellation") >= 4
    assert "<VersioningConfiguration/>" in socket
    assert "Versioning_Unconfigured" in socket
    verify_coverage_evidence(
        backend, sqlite, implementation, server, server_test
    )
    for marker in (
        "read-only",
        "pre-admission cancellation",
        "admitted cancellation",
        "same-operation",
        "documentation warning",
    ):
        assert marker in qualification


def verify_negative_oracles() -> None:
    data = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    for field, replacement in (
        ("public_name", "Get_Bucket_Versioning"),
        ("certainty", "unknown"),
        ("decision_status", "inventory_only"),
        ("qualification", "get_bucket_location"),
    ):
        changed = copy.deepcopy(data)
        operation_entry(changed)[field] = replacement
        try:
            verify_registry(changed)
        except AssertionError:
            pass
        else:
            raise AssertionError(f"changed registry field accepted: {field}")
    changed = copy.deepcopy(data)
    operation_entry(changed)["errors"].pop()
    try:
        verify_registry(changed)
    except AssertionError:
        pass
    else:
        raise AssertionError("incomplete error inventory was accepted")
    socket = SOCKET.read_text(encoding="utf-8")
    for candidate, diagnostic in (
        (
            mutate_socket_lifecycle(
                socket,
                "HTTP_Client.Possibly_Admitted",
                "HTTP_Client.Not_Admitted",
            ),
            "wrong admitted-cancellation certainty was accepted",
        ),
        (
            mutate_socket_lifecycle(
                socket,
                "Token => Changed_Token'Access,",
                "Token => Cancel_Token'Access,",
            ),
            "missing retained-owner substitution was accepted",
        ),
        (
            mutate_socket_lifecycle(
                socket, "Flyology.IO.Finish (Drain_Ready);", "null;"
            ),
            "missing drain acknowledgement Finish was accepted",
        ),
        (
            mutate_socket_lifecycle(
                socket,
                '"get-versioning-cancel-restart",',
                '"get-versioning-wrong-restart",',
                2,
            ),
            "wrong GetBucketVersioning restart route was accepted",
        ),
    ):
        reject_socket_lifecycle(socket, candidate, diagnostic)


def main() -> None:
    verify_model(load_model())
    verify_registry()
    verify_sources()
    verify_negative_oracles()
    print("GetBucketVersioning preparation evidence: OK")


if __name__ == "__main__":
    main()
