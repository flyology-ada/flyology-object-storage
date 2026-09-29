#!/usr/bin/env python3
"""Fail-closed evidence for reviewed PutBucketVersioning qualification."""

from __future__ import annotations

import copy
import hashlib
import json
import os
import re
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
    ROOT / "docs" / "qualification" / "put-bucket-versioning.md"
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


def exact_ordered(text: str, markers: list[str], label: str) -> None:
    ordered(text, markers, label)
    for marker in markers:
        assert text.count(marker) == 1, (
            f"{label}: marker count differs: {marker}"
        )


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
    operation = model["operations"]["PutBucketVersioning"]
    assert operation["http"] == {
        "method": "PUT",
        "requestUri": "/{Bucket}?versioning",
    }
    assert operation["input"] == {"shape": "PutBucketVersioningRequest"}
    assert operation["httpChecksum"] == {
        "requestAlgorithmMember": "ChecksumAlgorithm",
        "requestChecksumRequired": True,
    }
    assert operation["staticContextParams"] == {
        "UseS3ExpressControlEndpoint": {"value": True}
    }
    request = model["shapes"]["PutBucketVersioningRequest"]
    assert request["required"] == ["Bucket", "VersioningConfiguration"]
    assert list(request["members"]) == [
        "Bucket",
        "ContentMD5",
        "ChecksumAlgorithm",
        "MFA",
        "VersioningConfiguration",
        "ExpectedBucketOwner",
    ]
    assert request["payload"] == "VersioningConfiguration"
    assert request["members"]["Bucket"]["location"] == "uri"
    assert request["members"]["ContentMD5"]["locationName"] == (
        "Content-MD5"
    )
    assert request["members"]["ChecksumAlgorithm"]["locationName"] == (
        "x-amz-sdk-checksum-algorithm"
    )
    assert request["members"]["MFA"]["locationName"] == "x-amz-mfa"
    assert request["members"]["ExpectedBucketOwner"]["locationName"] == (
        "x-amz-expected-bucket-owner"
    )
    configuration = model["shapes"]["VersioningConfiguration"]
    assert list(configuration["members"]) == ["MFADelete", "Status"]
    assert model["shapes"]["BucketVersioningStatus"]["enum"] == [
        "Enabled",
        "Suspended",
    ]


def operation_entry(data: dict[str, object]) -> dict[str, object]:
    entries = [
        item for item in data["operation"]
        if item["name"] == "PutBucketVersioning"
    ]
    assert len(entries) == 1, "PutBucketVersioning entry is not unique"
    return entries[0]


def verify_registry(data: dict[str, object] | None = None) -> None:
    if data is None:
        data = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    entry = operation_entry(data)
    expected = {
        "tier": "core",
        "provider": "buckets",
        "family": "rest_xml_mutation",
        "public_provider": "Flyology.Object_Storage.Client.Buckets",
        "codec": "empty_response",
        "public_name": "Set_Versioning_Configuration",
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
        "qualification": "put_bucket_versioning",
        "ada_symbols": [
            "Prepare_Put_Bucket_Versioning",
            "Decode_Put_Bucket_Versioning_Response",
            "Execute_Put_Bucket_Versioning",
            "Put_Bucket_Versioning_Operation",
            "Set_Versioning_Configuration",
            "Finish",
        ],
    }
    for key, value in expected.items():
        assert entry[key] == value, f"PutBucketVersioning changed: {key}"
    assert entry["absence"] == (
        "not applicable; the operation updates an existing bucket and exact "
        "NoSuchBucket remains a bounded structured rejection proving the "
        "requested configuration was not applied"
    )
    assert entry["certainty"] == (
        "only a complete validated 200 reports "
        "Bucket_Versioning_Mutation_Completed; exact recognized non-mutating "
        "rejections report "
        "Bucket_Versioning_Mutation_Definitely_Not_Applied; pre-admission "
        "cancellation reports "
        "Bucket_Versioning_Mutation_Cancelled_Before_Admission; possible or "
        "incomplete admission, retryable responses, and malformed or "
        "oversized responses report "
        "Bucket_Versioning_Mutation_Outcome_Unknown; no automatic replay"
    )
    assert entry["reconciliation"] == (
        "caller-selected Get_Versioning for the exact bucket and expected "
        "owner, comparing each field explicitly present in the serialized "
        "mutation; Versioning_Unconfigured and MFA_Delete_Unconfigured "
        "preserve that field and are not comparison targets before retry"
    )
    assert entry["exclusions"] == [
        "directory buckets are unsupported by the pinned model",
        (
            "qualification covers caller-supplied origins for "
            "general-purpose buckets; automatic S3 Express "
            "control-endpoint, access-point, and Outposts routing is not "
            "claimed"
        ),
        (
            "the model-documented propagation interval and downstream "
            "object-version publication or listing behavior are not "
            "qualified"
        ),
        (
            "external-provider compatibility is not claimed by the "
            "maintained in-process server and socket evidence"
        ),
        "a completed update cannot be rolled back by client cancellation",
    ]
    assert entry["evidence"] == {
        "backend": [
            "tests/src/object_storage_test_cases.adb",
            "sqlite/tests/src/flyology_object_storage_sqlite_tests.adb",
        ],
        "client": [
            "src/flyology-object_storage-client-low_level.ads",
            "src/flyology-object_storage-client-low_level.adb",
            "src/flyology-object_storage-client-buckets.ads",
            "src/flyology-object_storage-client-buckets.adb",
            "tests/src/flyology-object_storage-client-buckets-testing.adb",
            "tests/src/s3_http_socket_corpus.adb",
        ],
        "server": [
            "src/flyology-object_storage-server-s3_applications.adb",
            "tests/src/s3_server_application_corpus.adb",
            "tests/src/s3_http_socket_corpus.adb",
        ],
        "corpus": [
            "tests/src/flyology-object_storage-client-buckets-testing.adb",
            "tests/src/s3_http_socket_corpus.adb",
            "tests/src/s3_implementation_corpus.adb",
            "tests/src/s3_server_application_corpus.adb",
        ],
    }
    assert data["qualification"]["put_bucket_versioning"] == [
        [
            "uv",
            "run",
            "--python",
            "3.13",
            "--",
            "tools/verify-put-bucket-versioning-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
        [
            "./tools/build-api-docs.sh",
            "/private/tmp/fos-put-bucket-versioning-gnatdoc",
        ],
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]


def verify_normalization(testing: str, buckets_body: str) -> None:
    corpus = unique_region(
        testing,
        "procedure Check_Put_Bucket_Versioning_Certainty_Corpus is",
        "end Check_Put_Bucket_Versioning_Certainty_Corpus;",
        "PutBucketVersioning certainty corpus",
    )
    conclusive = [
        (400, "BadDigest"),
        (400, "InvalidArgument"),
        (400, "InvalidDigest"),
        (400, "InvalidRequest"),
        (400, "MalformedXML"),
        (400, "XAmzContentSHA256Mismatch"),
        (501, "NotImplemented"),
    ]
    retryable = [
        (409, "OperationAborted"),
        (429, "SlowDown"),
        (500, "InternalError"),
        (502, "BadGateway"),
        (503, "SlowDown"),
        (504, "RequestTimeout"),
    ]
    for _, code in conclusive + retryable:
        assert corpus.count(f'"{code}"') >= 1, (
            f"certainty corpus lost response code: {code}"
        )
    for code in [
        "InvalidAccessKeyId",
        "AccessDenied",
        "NoSuchBucket",
    ]:
        assert corpus.count(f'"{code}"') >= 1, (
            f"certainty corpus lost response code: {code}"
        )
    assert corpus.count('US.To_Unbounded_String ("SlowDown")') == 2
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
    failure_block = unique_region(
        corpus,
        "Failure_Kinds : constant Failure_Kind_Array :=",
        "Conclusive_Pairs : constant Response_Pair_Array :=",
        "failure-kind inventory",
    )
    assert re.findall(r"HTTP_Client\.([A-Za-z_]+)", failure_block) == (
        failure_kinds
    )
    pair_pattern = re.compile(
        r"\d+\s*=>\s*\((\d+),\s*US\.To_Unbounded_String\s*"
        r"\(\"([^\"]+)\"\)\)"
    )
    conclusive_block = unique_region(
        corpus,
        "Conclusive_Pairs : constant Response_Pair_Array :=",
        "Retryable_Pairs : constant Response_Pair_Array :=",
        "conclusive response inventory",
    )
    retryable_block = unique_region(
        corpus,
        "Retryable_Pairs : constant Response_Pair_Array :=",
        "begin\n      Check_Put_Bucket_Versioning_Response",
        "retryable response inventory",
    )
    assert [
        (int(status), code)
        for status, code in pair_pattern.findall(conclusive_block)
    ] == conclusive
    assert [
        (int(status), code)
        for status, code in pair_pattern.findall(retryable_block)
    ] == retryable
    assert len(conclusive) == 7
    assert len(retryable) == 6
    observed_rows = 1 + len(conclusive) + 3 + len(retryable) + 1
    inconsistent_rows = 2 * 2
    exchange_rows = len(failure_kinds) * 3
    assert (observed_rows, inconsistent_rows, exchange_rows) == (18, 4, 30)
    assert observed_rows + inconsistent_rows + exchange_rows == 52
    ordered(
        corpus,
        [
            "Conclusive_Pairs : constant Response_Pair_Array :=",
            "Retryable_Pairs : constant Response_Pair_Array :=",
            "Check_Put_Bucket_Versioning_Response\n        (200,",
            "for Pair of Conclusive_Pairs loop",
            '"InvalidAccessKeyId"',
            '"AccessDenied"',
            '"NoSuchBucket"',
            "for Pair of Retryable_Pairs loop",
            (
                "Check_Put_Bucket_Versioning_Response\n"
                '        (409,\n         "",'
            ),
            "HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted",
            "for Kind of Failure_Kinds loop",
            "for Admission in HTTP_Client.Admission_Certainty loop",
        ],
        "52-row certainty geometry",
    )
    for marker in (
        "Conclusive_Pairs : constant Response_Pair_Array :=",
        "Retryable_Pairs : constant Response_Pair_Array :=",
        "for Pair of Conclusive_Pairs loop",
        "for Pair of Retryable_Pairs loop",
        "for Kind of Failure_Kinds loop",
        "for Admission in HTTP_Client.Admission_Certainty loop",
    ):
        assert corpus.count(marker) == 1, (
            f"52-row certainty geometry count differs: {marker}"
        )
    assert "Kind = HTTP_Client.Cancelled" in corpus
    assert "Admission = HTTP_Client.Not_Admitted" in corpus
    assert "Bucket_Versioning_Mutation_Cancelled_Before_Admission" in corpus
    assert "Bucket_Versioning_Mutation_Definitely_Not_Applied" in corpus
    assert "Bucket_Versioning_Mutation_Outcome_Unknown" in corpus
    ordered(
        buckets_body,
        [
            "function Normalize_Put_Bucket_Versioning_Response",
            "function Normalize_Put_Bucket_Versioning_Failure",
            "overriding function Declared_Length",
            "overriding procedure Read_Now",
            "overriding procedure Write",
            "procedure Complete_Put_Bucket_Versioning_Child",
            "overriding procedure Drive",
            "overriding procedure Request_Cancellation",
            "procedure Start_Put_Bucket_Versioning",
            '"PutBucketVersioning restart changed a retained owner"',
            "function Set_Versioning_Configuration",
            "procedure Finish",
        ],
        "provider certainty lifecycle",
    )


def verify_socket_lifecycle(socket: str) -> None:
    server = unique_region(
        socket,
        '"PUT", "/typed-put-versioning?versioning",',
        '"HEAD", "/example-bucket");',
        "PutBucketVersioning server lifecycle",
    )
    ordered(
        server,
        [
            '"PUT", "/typed-put-versioning?versioning",',
            '"PUT", "/composed-put-versioning?versioning",',
            '"PUT", "/restart-put-versioning?versioning",',
            '"", "PUT", "/put-versioning-cancel?versioning",',
            'Expected_Body_Root => "<Status>Enabled</Status>",',
            'Expected_Bucket_Owner => "123456789012",',
            'Expected_Content_MD5 => "*",',
            "Await_Cancellation => True,",
            "Cancellation_Kind => Put_Bucket_Versioning_Cancellation,",
            "Cancellation_Round => Round);",
            '"PUT", "/put-versioning-cancel-restart?versioning",',
        ],
        "PutBucketVersioning server lifecycle",
    )
    for marker, count in (
        ('"PUT", "/typed-put-versioning?versioning",', 1),
        ('"PUT", "/composed-put-versioning?versioning",', 1),
        ('"PUT", "/restart-put-versioning?versioning",', 1),
        ('"", "PUT", "/put-versioning-cancel?versioning",', 1),
        ('"PUT", "/put-versioning-cancel-restart?versioning",', 1),
        ('Expected_Body_Root => "<Status>Enabled</Status>",', 4),
        ('Expected_Body_Root => "<Status>Suspended</Status>",', 1),
        ('Expected_Bucket_Owner => "123456789012",', 5),
        ('Expected_Content_MD5 => "*"', 5),
        ("Await_Cancellation => True,", 1),
        ("Cancellation_Kind => Put_Bucket_Versioning_Cancellation,", 1),
        ("Cancellation_Round => Round);", 1),
    ):
        assert server.count(marker) == count, (
            f"PutBucketVersioning server count differs: {marker}"
        )
    for path in (
        '"PUT", "/typed-put-versioning?versioning",',
        '"PUT", "/composed-put-versioning?versioning",',
        '"PUT", "/restart-put-versioning?versioning",',
        '"", "PUT", "/put-versioning-cancel?versioning",',
        '"PUT", "/put-versioning-cancel-restart?versioning",',
    ):
        assert socket.count(path) == 1, (
            f"PutBucketVersioning global server path differs: {path}"
        )
    assert server.index('"PUT", "/restart-put-versioning?versioning",') < (
        server.index('"", "PUT", "/put-versioning-cancel?versioning",')
    ), "PutBucketVersioning cancellation slots precede ordinary requests"
    reordered_server = "\n".join(
        [
            '"PUT", "/typed-put-versioning?versioning",',
            '"", "PUT", "/put-versioning-cancel?versioning",',
            '"PUT", "/composed-put-versioning?versioning",',
            '"PUT", "/restart-put-versioning?versioning",',
            '"PUT", "/put-versioning-cancel-restart?versioning",',
        ]
    )
    try:
        ordered(
            reordered_server,
            [
                '"PUT", "/typed-put-versioning?versioning",',
                '"PUT", "/composed-put-versioning?versioning",',
                '"PUT", "/restart-put-versioning?versioning",',
                '"", "PUT", "/put-versioning-cancel?versioning",',
                '"PUT", "/put-versioning-cancel-restart?versioning",',
            ],
            "reordered PutBucketVersioning server negative",
        )
    except AssertionError:
        pass
    else:
        raise AssertionError(
            "reordered PutBucketVersioning server was accepted"
        )
    client = unique_region(
        socket,
        '"typed-put-versioning",',
        "Low_Level.Model_Value_Array :=",
        "PutBucketVersioning client lifecycle",
    )
    ordered(
        client,
        [
            '"typed-put-versioning",',
            '"composed-put-versioning",',
            '"restart-put-versioning",',
            '"put-versioning-cancelled", Parameters,',
            "Bucket_Versioning_Mutation_Cancelled_Before_Admission",
            "Client_API.Cancelled",
            "HTTP_Client.Not_Admitted",
            "Put_Versioning_Admission_Native.Wait_Source",
            "Put_Versioning_Drain_Native.Wait_Source",
            "Put_Versioning_Admission_Lightweight.Wait_Source",
            "Put_Versioning_Drain_Lightweight.Wait_Source",
            "Operations.Completion_Set (5)",
            '"put-versioning-cancel", Parameters, Identity,',
            "Operations.Wait_Some (Cancel_Set, Completed_Batch);",
            "Operations.Is_Terminal (Admission_Ready)",
            "Operations.Is_Active (Drain_Ready)",
            "Operations.Is_Active (Cancel_Operation)",
            "Flyology.IO.Finish (Admission_Ready);",
            "Operations.Cancel (Cancel_Operation);",
            "Operations.Wait_All (Cancel_Set);",
            "Finish (Cancel_Operation, Cancel_Result);",
            "Bucket_Versioning_Mutation_Outcome_Unknown",
            "HTTP_Client.Possibly_Admitted",
            "Operations.Is_Terminal (Drain_Ready)",
            "Flyology.IO.Finish (Drain_Ready);",
            '"put-versioning-cancel-restart", Parameters, Identity,',
            "Token => Changed_Token'Access,",
            "Operation => Cancel_Operation);",
            "when Error : Program_Error =>",
            "Ada.Exceptions.Exception_Message (Error) =",
            '"PutBucketVersioning restart changed a retained owner"',
            "Changed_Owner_Rejected := True;",
            '"PutBucketVersioning accepted changed retained owner"',
            '"put-versioning-cancel-restart",',
            "Token => Cancel_Token'Access,",
            "Operations.Wait_All (Cancel_Set);",
            "Finish (Cancel_Operation, Cancel_Result);",
            "Bucket_Versioning_Mutation_Completed",
            "HTTP_Client.Response_Observed",
            "Low_Level.Bucket_Versioning_Updated",
            '"same-operation PutBucketVersioning restart mismatch"',
        ],
        "PutBucketVersioning client lifecycle",
    )
    for marker, count in (
        ("Operations.Wait_All (Cancel_Set);", 2),
        ("Finish (Cancel_Operation, Cancel_Result);", 2),
        ("Operation => Cancel_Operation);", 2),
        ("Token => Changed_Token'Access,", 1),
        ("Token => Cancel_Token'Access,", 1),
        ("Flyology.IO.Finish (Drain_Ready);", 1),
        (
            '"PutBucketVersioning restart changed a retained owner"',
            1,
        ),
    ):
        assert client.count(marker) == count, (
            f"PutBucketVersioning lifecycle count differs: {marker}"
        )


def verify_contract(
    low_spec: str,
    low_body: str,
    buckets_spec: str,
    buckets_body: str,
) -> None:
    ordered(
        low_spec,
        [
            "type Put_Bucket_Versioning_Parameters is record",
            "function Prepare_Put_Bucket_Versioning",
            "type Put_Bucket_Versioning_Outcome_Kind is",
            "type Put_Bucket_Versioning_Outcome",
            "function Decode_Put_Bucket_Versioning_Response",
            "function Execute_Put_Bucket_Versioning",
        ],
        "Low_Level contract",
    )
    ordered(
        low_body,
        [
            "function Prepare_Put_Bucket_Versioning",
            "S3.Versioning.Serialize (Parameters.Configuration)",
            "then Content_MD5 (Payload) else Supplied_MD5",
            '"invalid PutBucketVersioning header"',
            'SigV4.Pair ("content-md5", MD5)',
            'SigV4.Pair ("x-amz-mfa", MFA)',
            'SigV4.Pair ("x-amz-expected-bucket-owner", Owner)',
            "Checksums.Encode_Base64 (Digest)",
            "Object_Resource => False, Store_Payload => False",
            "Result.Owned_Request_Payload := US.To_Unbounded_String",
            "function Decode_Put_Bucket_Versioning_Response",
            '"PutBucketVersioning success contains a response body"',
            "function Execute_Put_Bucket_Versioning",
            "Prepared.Operation /= Put_Bucket_Versioning_Operation",
            "Non_Replayable_Buffer_Source",
            '"PutBucketVersioning response exceeds XML limit"',
        ],
        "Low_Level implementation",
    )
    ordered(
        buckets_spec,
        [
            "type Bucket_Versioning_Mutation_Disposition is",
            "type Put_Bucket_Versioning_Result_Kind is",
            "type Put_Bucket_Versioning_Result",
            "type Put_Bucket_Versioning_Operation",
            "procedure Set_Versioning_Configuration",
            "function Set_Versioning_Configuration",
            "procedure Finish",
        ],
        "public contract",
    )
    for marker in (
        "The operation never rewinds or replays its body.",
        "caller-selected Get_Versioning",
        "before any retry",
        "@param Set Caller-owned completion set",
    ):
        assert marker in buckets_spec, f"public contract lost: {marker}"
    start_region = unique_region(
        buckets_body,
        "procedure Start_Put_Bucket_Versioning",
        "end Start_Put_Bucket_Versioning;",
        "PutBucketVersioning start",
    )
    assert start_region.count("Operation.Source_Position := 0;") == 1


def verify_coverage(
    backend: str,
    sqlite: str,
    implementation: str,
    server: str,
    server_test: str,
) -> None:
    for marker in (
        '"atomic independent versioning fields did not merge"',
        '"files versioning configuration did not persist"',
        '"typed PutBucketVersioning request projection"',
        '"typed PutBucketVersioning success decode"',
        '"complete PutBucketVersioning projection omitted controls"',
    ):
        once(backend, marker, "backend versioning evidence")
    for marker in (
        '"SQLite backend versioning fields did not merge atomically"',
        '"SQLite denied MFA update changed stored configuration"',
        '"SQLite versioning did not distinguish a missing bucket"',
    ):
        once(sqlite, marker, "SQLite versioning evidence")
    implementation_region = unique_region(
        implementation,
        "procedure Require_Bucket_Versioning",
        "end Require_Bucket_Versioning;",
        "implementation versioning evidence",
    )
    for marker in (
        "Versioning_Unconfigured",
        "Versioning_Enabled",
        "Versioning_Suspended",
    ):
        assert marker in implementation_region
    provider_region = unique_region(
        server,
        "when Put_Bucket_Versioning =>",
        "when Get_Bucket_Versioning =>",
        "server PutBucketVersioning handler",
    )
    ordered(
        provider_region,
        [
            "Check_Expected_Bucket_Owner",
            "Versioning.Parse (Document)",
            "Store.Put_Bucket_Versioning",
            "Send_Backend_Error",
        ],
        "server PutBucketVersioning handler",
    )
    for marker in (
        '"PutBucketVersioning rejected enabled status"',
        '"PutBucketVersioning accepted a missing Content-MD5"',
        '"PutBucketVersioning accepted a mismatched Content-MD5"',
        '"PutBucketVersioning accepted an invalid status"',
        '"PutBucketVersioning accepted an oversized document"',
    ):
        once(server_test, marker, "server PutBucketVersioning corpus")


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
    verify_contract(low_spec, low_body, buckets_spec, buckets_body)
    verify_normalization(testing, buckets_body)
    verify_socket_lifecycle(socket)
    verify_coverage(backend, sqlite, implementation, server, server_test)
    for lane in (
        "Put_Versioning_Admission_Native",
        "Put_Versioning_Admission_Lightweight",
        "Put_Versioning_Drain_Native",
        "Put_Versioning_Drain_Lightweight",
    ):
        assert socket.count(lane) >= 3, f"lifecycle lane changed: {lane}"
    assert socket.count("Put_Bucket_Versioning_Cancellation") >= 4
    qualification_words = " ".join(qualification.split())
    for marker in (
        "one serialized XML request body",
        "does not rewind or automatically replay",
        "Get_Versioning",
        "each field explicitly present in the serialized mutation",
        "Versioning_Unconfigured",
        "MFA_Delete_Unconfigured",
        "pre-admission",
        "native and lightweight",
        "drain acknowledgement",
        "documentation warning",
    ):
        assert marker in qualification_words, (
            f"qualification boundary lost: {marker}"
        )


def reject_registry(
    original: dict[str, object], field: str, value: object
) -> None:
    candidate = copy.deepcopy(original)
    operation_entry(candidate)[field] = value
    try:
        verify_registry(candidate)
    except AssertionError:
        return
    raise AssertionError(f"registry negative accepted: {field}")


def reject_socket(original: str, old: str, new: str) -> None:
    start_marker = '"put-versioning-cancelled", Parameters,'
    end_marker = "Low_Level.Model_Value_Array :="
    start_at = once(original, start_marker, "socket negative")
    end_at = original.find(end_marker, start_at + len(start_marker))
    assert end_at >= 0, "socket negative region end missing"
    region = original[start_at:end_at]
    assert region.count(old) >= 1, f"socket negative source missing: {old}"
    candidate = (
        original[:start_at]
        + region.replace(old, new, 1)
        + original[end_at:]
    )
    try:
        verify_socket_lifecycle(candidate)
    except AssertionError:
        return
    raise AssertionError(f"socket negative accepted: {old}")


def verify_negative_oracles() -> None:
    data = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    for field, value in (
        ("public_name", "Put_Bucket_Versioning"),
        ("certainty", "legacy_preserved_no_automatic_replay"),
        ("reconciliation", "not_applicable"),
        ("decision_status", "inventory_only"),
        ("qualification", "get_bucket_versioning"),
        ("ada_symbols", ["Set_Versioning_Configuration"]),
    ):
        reject_registry(data, field, value)
    model = load_model()
    candidate = copy.deepcopy(model)
    candidate["shapes"]["PutBucketVersioningRequest"]["required"] = [
        "Bucket"
    ]
    try:
        verify_model(candidate)
    except AssertionError:
        pass
    else:
        raise AssertionError("model negative accepted missing payload")
    socket = SOCKET.read_text(encoding="utf-8")
    for old, new in (
        ("Operations.Cancel (Cancel_Operation);", "null;"),
        ("Operations.Wait_All (Cancel_Set);", "null;"),
        ("Flyology.IO.Finish (Drain_Ready);", "null;"),
        ("Token => Changed_Token'Access,", "Token => Cancel_Token'Access,"),
        ("Token => Cancel_Token'Access,", "Token => Changed_Token'Access,"),
        (
            "Bucket_Versioning_Mutation_Cancelled_Before_Admission",
            "Bucket_Versioning_Mutation_Outcome_Unknown",
        ),
    ):
        reject_socket(socket, old, new)


def main() -> None:
    verify_model(load_model())
    verify_registry()
    verify_sources()
    verify_negative_oracles()
    print("PutBucketVersioning preparation evidence: OK")


if __name__ == "__main__":
    main()
