#!/usr/bin/env python3
"""Fail-closed evidence for reviewed HeadBucket qualification."""

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
LOW_SPEC = ROOT / "src/flyology-object_storage-client-low_level.ads"
LOW_BODY = ROOT / "src/flyology-object_storage-client-low_level.adb"
BUCKETS_SPEC = ROOT / "src/flyology-object_storage-client-buckets.ads"
BUCKETS_BODY = ROOT / "src/flyology-object_storage-client-buckets.adb"
BUCKETS_TESTING = (
    ROOT
    / "tests/src/flyology-object_storage-client-buckets-testing.adb"
)
SOCKET = ROOT / "tests/src/s3_http_socket_corpus.adb"
SERVER = ROOT / "src/flyology-object_storage-server-s3_applications.adb"
SERVER_TEST = ROOT / "tests/src/s3_server_application_corpus.adb"
BACKEND = ROOT / "tests/src/object_storage_test_cases.adb"
SQLITE_BACKEND = (
    ROOT / "sqlite/tests/src/flyology_object_storage_sqlite_tests.adb"
)
IMPLEMENTATION = ROOT / "tests/src/s3_implementation_corpus.adb"
QUALIFICATION = ROOT / "docs/qualification/head-bucket-composable.md"


def regular(path: Path) -> None:
    assert path.is_file(), f"missing HeadBucket evidence: {path}"
    assert not path.is_symlink(), f"symlink HeadBucket evidence: {path}"


def once(text: str, marker: str, label: str) -> int:
    count = text.count(marker)
    assert count == 1, f"{label}: expected once, found {count}: {marker}"
    return text.index(marker)


def ordered_once(text: str, markers: list[str], label: str) -> None:
    positions = [once(text, marker, label) for marker in markers]
    assert positions == sorted(positions), f"{label}: evidence order changed"


def between(text: str, start: str, end: str, label: str) -> str:
    first = once(text, start, label)
    last = once(text, end, label)
    assert first < last, f"{label}: invalid region boundary"
    return text[first:last + len(end)]


def load_model() -> dict[str, object]:
    model_name = os.environ.get("FLYOLOGY_S3_SERVICE_MODEL", "")
    assert model_name, "FLYOLOGY_S3_SERVICE_MODEL is required"
    path = Path(model_name)
    regular(path)
    assert hashlib.sha256(path.read_bytes()).hexdigest() == MODEL_SHA256
    return json.loads(path.read_text(encoding="utf-8"))


def verify_model(model: dict[str, object]) -> None:
    operation = model["operations"]["HeadBucket"]
    assert operation["http"] == {
        "method": "HEAD",
        "requestUri": "/{Bucket}",
    }
    assert operation["input"] == {"shape": "HeadBucketRequest"}
    assert operation["output"] == {"shape": "HeadBucketOutput"}
    assert operation["errors"] == [{"shape": "NoSuchBucket"}]
    request = model["shapes"]["HeadBucketRequest"]
    assert request["type"] == "structure"
    assert request["required"] == ["Bucket"]
    assert list(request["members"]) == [
        "Bucket",
        "ExpectedBucketOwner",
    ]
    assert request["members"]["Bucket"]["location"] == "uri"
    assert request["members"]["Bucket"]["shape"] == "BucketName"
    owner = request["members"]["ExpectedBucketOwner"]
    assert owner["shape"] == "AccountId"
    assert owner["location"] == "header"
    assert owner["locationName"] == "x-amz-expected-bucket-owner"
    output = model["shapes"]["HeadBucketOutput"]
    assert output["type"] == "structure"
    assert list(output["members"]) == [
        "BucketArn",
        "BucketLocationType",
        "BucketLocationName",
        "BucketRegion",
        "AccessPointAlias",
    ]
    assert [
        output["members"][name]["locationName"]
        for name in output["members"]
    ] == [
        "x-amz-bucket-arn",
        "x-amz-bucket-location-type",
        "x-amz-bucket-location-name",
        "x-amz-bucket-region",
        "x-amz-access-point-alias",
    ]
    assert [
        output["members"][name]["shape"]
        for name in output["members"]
    ] == [
        "S3RegionalOrS3ExpressBucketArnString",
        "LocationType",
        "BucketLocationName",
        "Region",
        "AccessPointAlias",
    ]
    assert all(
        output["members"][name]["location"] == "header"
        for name in output["members"]
    )
    shapes = model["shapes"]
    assert shapes["BucketName"] == {"type": "string"}
    assert shapes["AccountId"] == {"type": "string"}
    assert shapes["S3RegionalOrS3ExpressBucketArnString"] == {
        "type": "string",
        "max": 128,
        "min": 1,
        "pattern": "arn:[^:]+:(s3|s3express):.*",
    }
    assert shapes["LocationType"] == {
        "type": "string",
        "enum": ["AvailabilityZone", "LocalZone"],
    }
    assert shapes["BucketLocationName"] == {"type": "string"}
    assert shapes["Region"] == {"type": "string", "max": 20, "min": 0}
    assert shapes["AccessPointAlias"] == {"type": "boolean", "box": True}


def verify_registry(data: dict[str, object] | None = None) -> None:
    if data is None:
        data = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    matches = [
        entry for entry in data["operation"]
        if entry["name"] == "HeadBucket"
    ]
    assert len(matches) == 1, "HeadBucket registry entry is not unique"
    entry = matches[0]
    expected = {
        "tier": "core",
        "provider": "buckets",
        "family": "response_head_read",
        "public_provider": "Flyology.Object_Storage.Client.Buckets",
        "codec": "headers",
        "public_name": "Head",
        "absence": (
            "no dedicated absence variant; a complete bodyless 404 is "
            "normalized to Not_Found without claiming that status "
            "conclusively proves bucket absence"
        ),
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
        "qualification": "head_bucket",
        "ada_symbols": [
            "Prepare_Head_Bucket",
            "Decode_Head_Bucket_Complete_Response",
            "Execute_Head_Bucket",
            "Head_Bucket_Operation",
            "Head",
            "Finish",
        ],
    }
    for key, value in expected.items():
        assert entry[key] == value, f"HeadBucket field changed: {key}"
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
    ]
    assert entry["evidence"]["client"] == [
        "src/flyology-object_storage-client-low_level.ads",
        "src/flyology-object_storage-client-low_level.adb",
        "src/flyology-object_storage-client-buckets.ads",
        "src/flyology-object_storage-client-buckets.adb",
        "tests/src/flyology-object_storage-client-buckets-testing.adb",
        "tools/verify-head-bucket-preparation.py",
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
    assert data["qualification"]["head_bucket"] == [
        [
            "uv",
            "run",
            "--python",
            "3.13",
            "--",
            "tools/verify-head-bucket-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
        [
            "./tools/build-api-docs.sh",
            "/private/tmp/fos-head-bucket-gnatdoc",
        ],
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]


def verify_sources() -> None:
    paths = [
        LOW_SPEC,
        LOW_BODY,
        BUCKETS_SPEC,
        BUCKETS_BODY,
        BUCKETS_TESTING,
        SOCKET,
        SERVER,
        SERVER_TEST,
        BACKEND,
        SQLITE_BACKEND,
        IMPLEMENTATION,
        QUALIFICATION,
    ]
    for path in paths:
        regular(path)
    low_spec = LOW_SPEC.read_text(encoding="utf-8")
    low_body = LOW_BODY.read_text(encoding="utf-8")
    buckets_spec = BUCKETS_SPEC.read_text(encoding="utf-8")
    buckets_body = BUCKETS_BODY.read_text(encoding="utf-8")
    testing = BUCKETS_TESTING.read_text(encoding="utf-8")
    socket = SOCKET.read_text(encoding="utf-8")
    server = SERVER.read_text(encoding="utf-8")
    server_test = SERVER_TEST.read_text(encoding="utf-8")
    backend = BACKEND.read_text(encoding="utf-8")
    sqlite_backend = SQLITE_BACKEND.read_text(encoding="utf-8")
    implementation = IMPLEMENTATION.read_text(encoding="utf-8")
    docs = QUALIFICATION.read_text(encoding="utf-8")

    for marker in (
        "type Head_Bucket_Parameters is record",
        "function Prepare_Head_Bucket",
        "type Head_Bucket_Result is record",
        "type Head_Bucket_Outcome_Kind is",
        "function Decode_Head_Bucket_Complete_Response",
        "function Execute_Head_Bucket",
        "procedure Head_Bucket",
    ):
        assert marker in low_spec, (
            f"missing HeadBucket Low_Level API: {marker}"
        )
    assert """\
   type Head_Bucket_Result is record
      Bucket_ARN           : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Location_Type : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Location_Name : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Region        : Ada.Strings.Unbounded.Unbounded_String;
      Access_Point_Alias   : Optional_Boolean;
   end record;
""" in low_spec, "HeadBucket Low_Level result inventory differs"
    for marker in (
        '(Head_Bucket_Operation, "HEAD", Origin, Style, Bucket, "",',
        '"HeadBucket contains a response body"',
        '"HeadBucket response uses transfer coding"',
        '"HeadBucket response duplicates a singleton header"',
    ):
        assert marker in low_body, f"missing HeadBucket decoder rule: {marker}"
    assert """\
         Headers : constant Head_Bucket_Result :=
           (Bucket_ARN           => H ("x-amz-bucket-arn"),
            Bucket_Location_Type => H ("x-amz-bucket-location-type"),
            Bucket_Location_Name => H ("x-amz-bucket-location-name"),
            Bucket_Region        => H ("x-amz-bucket-region"),
            Access_Point_Alias   => Optional_Boolean_Header
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-access-point-alias")));
""" in low_body, "HeadBucket response-header decoder mapping differs"
    for marker in (
        "type Head_Bucket_Result_Kind is",
        "type Head_Bucket_Result",
        "type Head_Bucket_Operation",
        "return Head_Bucket_Operation;",
        "procedure Finish",
    ):
        assert marker in buckets_spec, (
            f"missing HeadBucket public API: {marker}"
        )
    normalization = between(
        buckets_body,
        "function Normalize_Head_Bucket_Response",
        "end Normalize_Head_Bucket_Failure;",
        "HeadBucket normalization region",
    )
    ordered_once(
        normalization,
        [
            "function Normalize_Head_Bucket_Response",
            "Admission /= HTTP_Client.Response_Observed",
            "then Corrupt_Or_Invalid_Response",
            "Value.Kind = Low_Level.Bucket_Found",
            "then No_Failure",
            "elsif Value.Status in 301 | 307 | 400 | 501",
            "then Invalid_Request",
            "elsif Value.Status = 401",
            "then Authentication_Failed",
            "elsif Value.Status = 403",
            "then Authorization_Failed",
            "elsif Value.Status = 404",
            "then Not_Found",
            "elsif Value.Status in 409 | 429 | 500 | 502 | 503 | 504",
            "then Unavailable_Or_Retryable",
            "else Corrupt_Or_Invalid_Response",
            "function Normalize_Head_Bucket_Failure",
            "Failure     => Failed_Reason (Kind)",
            "HTTP_Result => Kind",
        ],
        "HeadBucket normalization",
    )
    failure_helper = between(
        testing,
        "procedure Check_Head_Bucket_Failure",
        "end Check_Head_Bucket_Failure;",
        "HeadBucket failure normalization helper",
    )
    assert """\
      Expected_Failure : constant Failure_Reason :=
        (case Kind is
            when HTTP_Client.Pre_Admission_Rejected => Invalid_Request,
            when HTTP_Client.Cancelled => Cancelled,
            when HTTP_Client.Timed_Out => Timed_Out,
            when HTTP_Client.Client_Unavailable => Client_Unavailable,
            when HTTP_Client.Connection_Failed => Connection_Failed,
            when HTTP_Client.Transport_Failed => Transport_Failed,
            when HTTP_Client.Request_Source_Failed => Request_Source_Failed,
            when HTTP_Client.Response_Body_Too_Large => Response_Too_Large,
            when HTTP_Client.Response_Invalid |
                 HTTP_Client.Response_Sink_Failed =>
              Corrupt_Or_Invalid_Response,
            when HTTP_Client.Response_Complete =>
              raise Program_Error with "complete response is not a failure");
""" in failure_helper, "HeadBucket failure-reason mapping differs"
    ordered_once(
        failure_helper,
        [
            "Normalize_Head_Bucket_Failure",
            "Result.Kind /= Head_Bucket_Exchange_Failed",
            "Result.Failure /= Expected_Failure",
            "Result.Admission /= Admission",
            "Result.HTTP_Result /= Kind",
        ],
        "HeadBucket failure normalization helper",
    )
    corpus = between(
        testing,
        "procedure Check_Head_Bucket_Result_Corpus is",
        "end Check_Head_Bucket_Result_Corpus;",
        "HeadBucket normalization corpus",
    )
    ordered_once(
        corpus,
        [
            "HTTP_Client.Pre_Admission_Rejected",
            "HTTP_Client.Cancelled",
            "HTTP_Client.Timed_Out",
            "HTTP_Client.Client_Unavailable",
            "HTTP_Client.Connection_Failed",
            "HTTP_Client.Transport_Failed",
            "HTTP_Client.Request_Source_Failed",
            "HTTP_Client.Response_Invalid",
            "HTTP_Client.Response_Body_Too_Large",
            "HTTP_Client.Response_Sink_Failed",
            "Check_Head_Bucket_Response (200, No_Failure);",
            "Check_Head_Bucket_Response (301, Invalid_Request);",
            "Check_Head_Bucket_Response (307, Invalid_Request);",
            "Check_Head_Bucket_Response (400, Invalid_Request);",
            "Check_Head_Bucket_Response (501, Invalid_Request);",
            "Check_Head_Bucket_Response (401, Authentication_Failed);",
            "Check_Head_Bucket_Response (403, Authorization_Failed);",
            "Check_Head_Bucket_Response (404, Not_Found);",
            "Check_Head_Bucket_Response (409, Unavailable_Or_Retryable);",
            "Check_Head_Bucket_Response (429, Unavailable_Or_Retryable);",
            "Check_Head_Bucket_Response (500, Unavailable_Or_Retryable);",
            "Check_Head_Bucket_Response (502, Unavailable_Or_Retryable);",
            "Check_Head_Bucket_Response (503, Unavailable_Or_Retryable);",
            "Check_Head_Bucket_Response (504, Unavailable_Or_Retryable);",
            "Check_Head_Bucket_Response (418, Corrupt_Or_Invalid_Response);",
            "HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted",
            "Normalize_Head_Bucket_Response (Value, Admission);",
            "Result.Failure /= Corrupt_Or_Invalid_Response",
            "for Kind of Failure_Kinds loop",
            "for Admission in HTTP_Client.Admission_Certainty loop",
            "Check_Head_Bucket_Failure (Kind, Admission);",
        ],
        "HeadBucket normalization corpus",
    )

    server_cancellation = between(
        socket,
        "if Await_Cancellation then",
        "elsif Response'Length = 0 then",
        "shared cancellation server",
    )
    for block in (
        """\
                  when Head_Bucket_Cancellation =>
                     if Cancellation_Round = 1 then
                        Head_Bucket_Admission_Native.Request;
                     else
                        Head_Bucket_Admission_Lightweight.Request;
                     end if;
""",
        """\
                     when Head_Bucket_Cancellation =>
                        if Cancellation_Round = 1 then
                           Head_Bucket_Drain_Native.Request;
                        else
                           Head_Bucket_Drain_Lightweight.Request;
                        end if;
""",
    ):
        assert server_cancellation.count(block) == 1, (
            "HeadBucket server readiness mapping differs"
        )
    admission = once(
        server_cancellation,
        "Head_Bucket_Admission_Native.Request;",
        "HeadBucket server admission",
    )
    receive = once(
        server_cancellation,
        "Sockets.Receive (Peer, Buffer, Last, Timeout => 5.0);",
        "HeadBucket server cancellation receive",
    )
    eof_check = once(
        server_cancellation,
        '"HeadBucket cancel peer sent data before drain"',
        "HeadBucket server EOF/reset check",
    )
    drain_calls = [
        once(
            server_cancellation,
            "\n                        Request_Drain;\n",
            "HeadBucket exceptional server drain call",
        ),
        once(
            server_cancellation,
            "\n               Request_Drain;\n",
            "HeadBucket terminal server drain call",
        ),
    ]
    assert admission < receive < eof_check < drain_calls[-1], (
        "HeadBucket server admission/drain order changed"
    )
    server_exchanges = between(
        socket,
        '"HEAD", "/head-bucket-cancel"',
        '"HEAD", "/head-bucket-cancel-restart"',
        "HeadBucket server exchanges",
    )
    ordered_once(
        server_exchanges,
        [
            '"HEAD", "/head-bucket-cancel"',
            "Await_Cancellation => True",
            "Cancellation_Kind => Head_Bucket_Cancellation",
            '"HEAD", "/head-bucket-cancel-restart"',
        ],
        "HeadBucket server exchanges",
    )
    lifecycle = between(
        socket,
        "Head_Bucket_Admission_Native.Wait_Source",
        '"same-operation HeadBucket restart mismatch"',
        "HeadBucket client lifecycle",
    )
    ordered_once(
        lifecycle,
        [
            "Head_Bucket_Admission_Native.Wait_Source",
            "Head_Bucket_Drain_Native.Wait_Source",
            "Head_Bucket_Admission_Lightweight.Wait_Source",
            "Head_Bucket_Drain_Lightweight.Wait_Source",
            '"invalid HeadBucket cancellation round"',
        ],
        "HeadBucket readiness selection",
    )
    cancellation_phase = between(
        lifecycle,
        "Operations.Wait_Some (Cancel_Set, Completed_Batch);",
        "Flyology.IO.Finish (Drain_Ready);",
        "HeadBucket cancellation phase",
    )
    ordered_once(
        cancellation_phase,
        [
            "Operations.Wait_Some (Cancel_Set, Completed_Batch);",
            "Operations.Cancel (Cancel_Operation);",
            "Operations.Wait_All (Cancel_Set);",
            "Finish (Cancel_Operation, Cancel_Result);",
            "HTTP_Client.Possibly_Admitted",
            '"HeadBucket drain was not acknowledged"',
            "Flyology.IO.Finish (Drain_Ready);",
        ],
        "HeadBucket cancellation phase",
    )
    restart_phase = between(
        lifecycle,
        "Token => Changed_Token'Access",
        '"same-operation HeadBucket restart mismatch"',
        "HeadBucket restart phase",
    )
    ordered_once(
        restart_phase,
        [
            "Token => Changed_Token'Access",
            '"HeadBucket restart changed a retained owner"',
            '"HeadBucket accepted changed retained owner"',
            "Token => Cancel_Token'Access",
            "Operations.Wait_All (Cancel_Set);",
            "Finish (Cancel_Operation, Cancel_Result);",
            "HTTP_Client.Response_Observed",
            '"same-operation HeadBucket restart mismatch"',
        ],
        "HeadBucket restart phase",
    )
    for marker, expected_count in (
        ("Head_Bucket_Admission_Native", 3),
        ("Head_Bucket_Admission_Lightweight", 3),
        ("Head_Bucket_Drain_Native", 3),
        ("Head_Bucket_Drain_Lightweight", 3),
    ):
        assert socket.count(marker) == expected_count, (
            f"HeadBucket readiness count changed: {marker}"
        )
    assert socket.count("Head_Bucket_Cancellation") == 5
    assert "Five slots cover the HeadBucket parent" in lifecycle

    for marker in (
        'Method = "HEAD" and then Query_Text = "x-id=HeadBucket"',
        "then Head_Bucket",
        "when Head_Bucket =>",
        "Store.Head_Bucket",
        'Apps.Set_Header (X, "x-amz-bucket-region", Region)',
    ):
        assert marker in server, (
            f"missing HeadBucket server evidence: {marker}"
        )
    for marker in (
        'Signed_Bucket_Request ("HEAD", "/test-bucket")',
        '"signed HeadBucket metadata mismatch"',
        '"HeadBucket ignored the expected owner precondition"',
        '"HeadBucket absent-bucket metadata mismatch"',
        '"HeadBucket accepted a duplicate expected owner header: "',
    ):
        assert marker in server_test, (
            f"missing HeadBucket server corpus evidence: {marker}"
        )
    for marker in (
        "Store.Head_Bucket",
        '"head existing memory bucket"',
        '"head deleted memory bucket"',
        '"head existing files bucket"',
        '"head deleted files bucket"',
        "Low_Level.Prepare_Head_Bucket",
        "Low_Level.Decode_Head_Bucket_Response",
    ):
        assert marker in backend, (
            f"missing HeadBucket backend/client evidence: {marker}"
        )
    for marker in (
        "Store.Head_Bucket",
        '"SQLite backend bucket head failed"',
    ):
        assert marker in sqlite_backend, (
            f"missing HeadBucket SQLite evidence: {marker}"
        )
    for marker in (
        "procedure Require_Head_Bucket",
        "Low_Level.Execute_Head_Bucket",
        "Client_Buckets.Head",
        '"S3 implementation returned invalid HeadBucket metadata"',
    ):
        assert marker in implementation, (
            f"missing HeadBucket implementation corpus evidence: {marker}"
        )

    assert all(len(line) <= 79 for line in docs.splitlines())
    normalized_docs = " ".join(docs.split())
    for marker in (
        "bodyless 404 is normalized to `Not_Found`",
        "does not prove bucket absence",
        "admission, cancellation, drain acknowledgement, typed `Finish`",
        "same operation object",
        "caller-supplied origins for general-purpose buckets",
    ):
        assert marker in normalized_docs, (
            f"missing HeadBucket qualification prose: {marker}"
        )


def verify_negative_registry() -> None:
    original = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    index = next(
        position for position, entry in enumerate(original["operation"])
        if entry["name"] == "HeadBucket"
    )
    for label, key, value in (
        ("legacy absence", "absence", "legacy_preserved"),
        ("legacy errors", "errors", ["legacy_preserved"]),
        ("unresolved decision", "human_decisions_resolved", False),
        ("wrong public name", "public_name", "Head_Bucket"),
        ("wrong certainty", "certainty", "possibly_applied"),
        ("missing qualification", "qualification", ""),
    ):
        candidate = copy.deepcopy(original)
        candidate["operation"][index][key] = value
        try:
            verify_registry(candidate)
        except AssertionError:
            pass
        else:
            raise AssertionError(f"HeadBucket {label} was accepted")


def main() -> None:
    verify_model(load_model())
    verify_registry()
    verify_sources()
    verify_negative_registry()
    print("HeadBucket preparation evidence: OK")


if __name__ == "__main__":
    main()
