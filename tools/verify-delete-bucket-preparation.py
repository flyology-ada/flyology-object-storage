#!/usr/bin/env python3
"""Fail-closed evidence for reviewed DeleteBucket qualification."""

from __future__ import annotations

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
    ROOT
    / "tests"
    / "src"
    / "flyology-object_storage-client-buckets-testing.adb"
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
QUALIFICATION = ROOT / "docs" / "qualification" / "delete-bucket.md"


def regular(path: Path) -> None:
    assert path.is_file(), f"missing evidence path: {path}"
    assert not path.is_symlink(), f"symlink evidence path: {path}"


def once(text: str, marker: str, label: str) -> int:
    count = text.count(marker)
    assert count == 1, f"{label}: expected once, found {count}: {marker}"
    return text.index(marker)


def ordered(text: str, markers: list[str], label: str) -> None:
    positions = [once(text, marker, label) for marker in markers]
    assert positions == sorted(positions), f"{label}: evidence order changed"


def ordered_fragments(text: str, markers: list[str], label: str) -> None:
    cursor = 0
    for marker in markers:
        position = text.find(marker, cursor)
        assert position >= 0, f"{label}: missing ordered marker: {marker}"
        cursor = position + len(marker)


def between(text: str, start: str, end: str, label: str) -> str:
    first = once(text, start, label)
    last = once(text, end, label)
    assert first < last, f"{label}: invalid region boundary"
    return text[first:last]


def load_model() -> dict[str, object]:
    model_name = os.environ.get("FLYOLOGY_S3_SERVICE_MODEL", "")
    assert model_name, "FLYOLOGY_S3_SERVICE_MODEL is required"
    model_path = Path(model_name)
    regular(model_path)
    assert hashlib.sha256(model_path.read_bytes()).hexdigest() == MODEL_SHA256
    return json.loads(model_path.read_text(encoding="utf-8"))


def verify_model(model: dict[str, object]) -> None:
    operation = model["operations"]["DeleteBucket"]
    assert operation["http"] == {
        "method": "DELETE",
        "requestUri": "/{Bucket}",
        "responseCode": 204,
    }
    assert operation["input"] == {"shape": "DeleteBucketRequest"}
    assert "output" not in operation
    assert "errors" not in operation
    request = model["shapes"]["DeleteBucketRequest"]
    assert request["required"] == ["Bucket"]
    assert list(request["members"]) == ["Bucket", "ExpectedBucketOwner"]
    assert request["members"]["Bucket"]["location"] == "uri"
    assert request["members"]["Bucket"]["locationName"] == "Bucket"
    owner = request["members"]["ExpectedBucketOwner"]
    assert owner["location"] == "header"
    assert owner["locationName"] == "x-amz-expected-bucket-owner"


def verify_registry() -> None:
    data = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    matches = [
        item for item in data["operation"] if item["name"] == "DeleteBucket"
    ]
    assert len(matches) == 1, "DeleteBucket registry entry is not unique"
    entry = matches[0]
    expected = {
        "tier": "core",
        "provider": "buckets",
        "family": "bodyless_mutation",
        "public_provider": "Flyology.Object_Storage.Client.Buckets",
        "codec": "bodyless_rest_xml_and_singleton_headers",
        "public_name": "Delete",
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
        "qualification": "delete_bucket",
        "ada_symbols": [
            "Prepare_Delete_Bucket",
            "Decode_Delete_Bucket_Response",
            "Execute_Delete_Bucket",
            "Delete_Bucket_Operation",
            "Delete",
            "Finish",
        ],
    }
    for key, value in expected.items():
        assert entry[key] == value, (
            f"DeleteBucket registry field changed: {key}"
        )
    assert entry["errors"] == [
        "authentication",
        "authorization",
        "not_found",
        "invalid_request",
        "unavailable_or_retryable",
        "corrupt_or_invalid_response",
    ]
    assert entry["absence"] == (
        "no dedicated absence variant; exact NoSuchBucket is a structured "
        "typed rejection confirming current bucket absence and proving this "
        "request did not delete it"
    )
    assert entry["certainty"] == (
        "only a complete validated 204 reports Bucket_Deletion_Completed; "
        "exact recognized non-applying rejections or definite non-admission "
        "report Bucket_Definitely_Not_Deleted; pre-admission cancellation "
        "reports Bucket_Deletion_Cancelled_Before_Admission; possible or "
        "incomplete admission, retryable responses, and malformed or "
        "oversized responses report Bucket_Deletion_Outcome_Unknown; no "
        "automatic replay"
    )
    assert entry["reconciliation"] == (
        "caller-selected HeadBucket for the exact bucket name and "
        "expected-owner context before any retry; current absence ends "
        "deletion work, while a present or ownership-ambiguous result "
        "requires caller policy"
    )
    assert entry["exclusions"] == [
        (
            "server qualification is limited to authenticated path-style "
            "general-purpose bucket requests; directory-bucket/S3 Express "
            "control endpoints, access-point, and Outposts routing are not "
            "claimed"
        ),
        (
            "DeleteBucket performs no recursive cleanup; objects, retained "
            "versions, delete markers, and blocking multipart state must be "
            "removed through their own operations"
        ),
        (
            "deletion cannot roll back an already-deleted bucket or prevent "
            "concurrent recreation"
        ),
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
            "tools/verify-delete-bucket-preparation.py",
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
            "tests/scripts/run-s3-implementation.sh",
            "tests/scripts/run-s3-server-slice.sh",
            "tests/scripts/test-minio.sh",
            "tests/scripts/test-rustfs.sh",
            "tests/scripts/test-seaweedfs.sh",
        ],
    }
    assert data["qualification"]["delete_bucket"] == [
        [
            "uv",
            "run",
            "--python",
            "3.13",
            "--",
            "tools/verify-delete-bucket-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
        [
            "./tools/build-api-docs.sh",
            "/private/tmp/fos-delete-bucket-gnatdoc",
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
        TESTING,
        SOCKET,
        SERVER,
        SERVER_TEST,
        BACKEND,
        SQLITE,
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
    docs = QUALIFICATION.read_text(encoding="utf-8")

    serve = between(
        socket,
        "      procedure Serve\n",
        "         declare\n            Request : constant String :=",
        "shared socket Serve request-head boundary",
    )
    fresh_peer_admission = [
        "Deadline : constant Ada.Real_Time.Time :=",
        "function Remaining_Time return Duration is",
        "if not Reuse_Peer then",
        "Timeout => Remaining_Time",
        "Sockets.Receive",
        "if Last < Buffer'First then",
        "if not Reuse_Peer and then US.Length (Head) = 0 then",
        "Sockets.Close_Socket (Peer);",
        "exit;",
        'raise Program_Error with\n                    '
        '"client closed before request head";',
        "exit when US.Length (Head) > 0;",
    ]
    ordered_fragments(
        serve,
        fresh_peer_admission,
        "fresh TCP peer versus HTTP admission boundary",
    )
    assert serve.count("Deadline : constant Ada.Real_Time.Time :=") == 1, (
        "Serve must use one overall request deadline"
    )
    assert serve.count("Timeout => Remaining_Time") == 2, (
        "accept and receive must share the overall request deadline"
    )
    assert "Timeout => 5.0" not in serve, (
        "Serve resets its timeout instead of retaining one deadline"
    )

    low_declarations = between(
        low_spec,
        "type Delete_Bucket_Parameters is record",
        "type Delete_Bucket_CORS_Parameters is record",
        "DeleteBucket Low_Level declaration region",
    )
    ordered(
        low_declarations,
        [
            "type Delete_Bucket_Parameters is record",
            "function Prepare_Delete_Bucket\n     (",
            "type Delete_Bucket_Outcome_Kind is",
            "function Decode_Delete_Bucket_Response\n     (",
            "function Execute_Delete_Bucket\n     (",
        ],
        "DeleteBucket Low_Level declaration inventory",
    )
    once(
        low_spec,
        "procedure Delete_Bucket\n     (",
        "DeleteBucket private exchange declaration",
    )
    prepare = between(
        low_body,
        "function Prepare_Delete_Bucket\n     (",
        "function Decode_Delete_Bucket_Response\n     (",
        "DeleteBucket preparation",
    )
    for marker in [
        'SigV4.Pair ("x-amz-expected-bucket-owner", Owner)',
        '(Delete_Bucket_Operation, "DELETE", Origin, Style, Bucket, "",',
        "Object_Resource => False",
    ]:
        assert marker in prepare, f"DeleteBucket preparation missing: {marker}"

    public_contract = between(
        buckets_spec,
        "type Bucket_Deletion_Disposition is",
        "type Head_Bucket_Result_Kind is",
        "DeleteBucket public contract region",
    )
    ordered(
        public_contract,
        [
            "type Bucket_Deletion_Disposition is",
            "type Delete_Bucket_Result\n     (",
            "type Delete_Bucket_Operation",
            "procedure Delete\n     (",
            "function Delete\n     (",
            "procedure Finish\n     (",
        ],
        "DeleteBucket public contract",
    )
    driver = between(
        buckets_body,
        "function Normalize_Delete_Bucket_Response",
        "function Normalize_Head_Bucket_Response",
        "DeleteBucket provider implementation",
    )
    for marker in [
        "Bucket_Deletion_Completed",
        "Bucket_Definitely_Not_Deleted",
        "Bucket_Deletion_Outcome_Unknown",
        "Bucket_Deletion_Cancelled_Before_Admission",
        "Operations.Cancel (Item.Child);",
        '"DeleteBucket restart changed a retained owner"',
    ]:
        assert marker in driver, f"DeleteBucket provider missing: {marker}"

    corpus = between(
        testing,
        "procedure Check_Delete_Bucket_Response",
        "procedure Check_Head_Bucket_Response",
        "DeleteBucket certainty corpus",
    )
    for code in [
        "InvalidBucketName",
        "InvalidAccessKeyId",
        "AccessDenied",
        "NoSuchBucket",
        "BucketNotEmpty",
        "NotImplemented",
        "OperationAborted",
        "SlowDown",
        "InternalError",
    ]:
        assert f'"{code}"' in corpus, f"DeleteBucket corpus missing {code}"
    for kind in [
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
    ]:
        assert f"HTTP_Client.{kind}" in corpus

    for token in [
        "Delete_Bucket_Admission_Native",
        "Delete_Bucket_Admission_Lightweight",
        "Delete_Bucket_Drain_Native",
        "Delete_Bucket_Drain_Lightweight",
    ]:
        assert socket.count(token) == 3, (
            f"DeleteBucket token inventory changed: {token}"
        )
    dispatcher_fragments = [
        (
            "when Delete_Bucket_Cancellation =>\n"
            "                        if Cancellation_Round = 1 then\n"
            "                           Delete_Bucket_Drain_Native.Request;\n"
            "                        else\n"
            "                           Delete_Bucket_Drain_Lightweight."
            "Request;\n"
            "                        end if;"
        ),
        (
            "when Delete_Bucket_Cancellation =>\n"
            "                     if Cancellation_Round = 1 then\n"
            "                        Delete_Bucket_Admission_Native.Request;\n"
            "                     else\n"
            "                        Delete_Bucket_Admission_Lightweight."
            "Request;\n"
            "                     end if;"
        ),
        (
            "when Delete_Bucket_Cancellation =>\n"
            "                           raise Program_Error with\n"
            '                             "DeleteBucket cancel peer sent '
            'data before " &\n'
            '                             "drain";'
        ),
    ]
    for fragment in dispatcher_fragments:
        assert socket.count(fragment) == 1, (
            "DeleteBucket cancellation dispatcher changed"
        )
    server_cancel = between(
        socket,
        'Serve\n           ("", "DELETE", "/delete-bucket-cancel",',
        "--  Accept exactly one DeleteBucket and drop its response.",
        "DeleteBucket server cancellation sequence",
    )
    ordered_fragments(
        server_cancel,
        [
            '"DELETE", "/delete-bucket-cancel"',
            'Expected_Bucket_Owner => "123456789012"',
            "Await_Cancellation => True",
            "Cancellation_Kind => Delete_Bucket_Cancellation",
            "Cancellation_Round => Round",
            '"DELETE", "/delete-bucket-cancel-restart"',
        ],
        "DeleteBucket server cancellation sequence",
    )
    server_lost = between(
        socket,
        "--  Accept exactly one DeleteBucket and drop its response.",
        '"GET",\n            "/typed-location?location"',
        "DeleteBucket server lost-response sequence",
    )
    ordered_fragments(
        server_lost,
        [
            '"HTTP/1.1 200 OK" & CRLF &',
            '"Content-Length: 0" & CRLF &',
            '"x-amz-bucket-region: us-west-2" & CRLF &',
            '"Connection: keep-alive" & CRLF & CRLF',
            '"HEAD", "/delete-bucket-lost"',
            'Expected_Bucket_Owner => "123456789012"',
            "Keep_Open => True",
            '"", "DELETE", "/delete-bucket-lost"',
            'Expected_Bucket_Owner => "123456789012"',
            "Reuse_Peer => True",
            '"HEAD", "/delete-bucket-lost"',
            'Expected_Bucket_Owner => "123456789012"',
        ],
        "DeleteBucket server lost-response sequence",
    )
    assert "automatic replay desynchronizes this sequence" in server_lost
    client_cancel = between(
        socket,
        "Delete_Bucket_Admission_Native.Wait_Source",
        "Delete_Parameters : constant",
        "DeleteBucket client cancellation sequence",
    )
    ordered_fragments(
        client_cancel,
        [
            "Delete_Bucket_Admission_Native.Wait_Source",
            "Delete_Bucket_Drain_Native.Wait_Source",
            "Delete_Bucket_Admission_Lightweight.Wait_Source",
            "Delete_Bucket_Drain_Lightweight.Wait_Source",
            "Cancel_Set : aliased Operations.Completion_Set (5);",
            "Operations.Wait_Some (Cancel_Set, Completed_Batch);",
            "Flyology.IO.Finish (Admission_Ready);",
            "Operations.Cancel (Cancel_Operation);",
            "Operations.Wait_All (Cancel_Set);",
            "Finish (Cancel_Operation, Cancel_Result);",
            "Bucket_Deletion_Outcome_Unknown",
            "Flyology.IO.Finish (Drain_Ready);",
            '"delete-bucket-cancel-restart"',
            "Operations.Wait_All (Cancel_Set);",
            "Finish (Cancel_Operation, Cancel_Result);",
            "Bucket_Deletion_Completed",
            "same-operation DeleteBucket restart mismatch",
        ],
        "DeleteBucket client cancellation sequence",
    )
    client_lost = between(
        socket,
        "Delete_Parameters : constant",
        "typed GetBucketLocation response mismatch",
        "DeleteBucket client lost-response sequence",
    )
    ordered_fragments(
        client_lost,
        [
            "Before : constant Head_Bucket_Result := Buckets.Head",
            "Low_Level.Bucket_Found",
            "Lost : constant Delete_Bucket_Result := Buckets.Delete",
            "Bucket_Deletion_Outcome_Unknown",
            "After : constant Head_Bucket_Result := Buckets.Head",
            "Low_Level.Head_Bucket_Rejected",
            "After.Response.Status /= 404",
            "lost-response DeleteBucket reconciliation mismatch",
        ],
        "DeleteBucket client lost-response sequence",
    )
    assert "HeadBucket establishes current state" in docs
    assert "repository-owned GNATdoc warning prevents" in docs


def verify_negative_oracle() -> None:
    markers = [
        "Bucket_Deletion_Completed",
        "Bucket_Definitely_Not_Deleted",
        "Bucket_Deletion_Outcome_Unknown",
        "Bucket_Deletion_Cancelled_Before_Admission",
    ]
    fixture = "\n".join(markers)
    ordered(fixture, markers, "DeleteBucket independent certainty order")
    for marker in markers:
        damaged = fixture.replace(marker, "", 1)
        try:
            ordered(damaged, markers, "DeleteBucket damaged certainty order")
        except AssertionError:
            pass
        else:
            raise AssertionError(
                f"missing certainty marker accepted: {marker}"
            )
    lifecycle = [
        "admission",
        "cancel",
        "wait-all",
        "typed-finish",
        "drain-finish",
        "same-operation-restart",
        "head-before",
        "dropped-delete-response",
        "head-after",
    ]
    fixture = "\n".join(lifecycle)
    ordered_fragments(
        fixture, lifecycle, "DeleteBucket independent lifecycle order"
    )
    for marker in lifecycle:
        damaged = fixture.replace(marker, "", 1)
        try:
            ordered_fragments(
                damaged,
                lifecycle,
                "DeleteBucket damaged lifecycle order",
            )
        except AssertionError:
            pass
        else:
            raise AssertionError(
                f"missing lifecycle marker accepted: {marker}"
            )
    fresh_peer_admission = [
        "deadline-before-accept-loop",
        "fresh-peer-only-empty-head-skip",
        "close-skipped-peer",
        "retained-or-partial-eof-fails",
        "same-request-slot",
    ]
    fixture = "\n".join(fresh_peer_admission)
    ordered_fragments(
        fixture,
        fresh_peer_admission,
        "independent fresh-peer admission boundary",
    )
    for marker in fresh_peer_admission:
        damaged = fixture.replace(marker, "", 1)
        try:
            ordered_fragments(
                damaged,
                fresh_peer_admission,
                "damaged fresh-peer admission boundary",
            )
        except AssertionError:
            pass
        else:
            raise AssertionError(
                f"missing fresh-peer admission marker accepted: {marker}"
            )
    socket = SOCKET.read_text(encoding="utf-8")
    server_lost = between(
        socket,
        "--  Accept exactly one DeleteBucket and drop its response.",
        '"GET",\n            "/typed-location?location"',
        "negative DeleteBucket lost-response sequence",
    )
    framing = [
        '"Content-Length: 0" & CRLF &',
        '"x-amz-bucket-region: us-west-2" & CRLF &',
        '"Connection: keep-alive" & CRLF & CRLF',
        '"HEAD", "/delete-bucket-lost"',
        "Keep_Open => True",
        '"", "DELETE", "/delete-bucket-lost"',
        "Reuse_Peer => True",
        '"HEAD", "/delete-bucket-lost"',
    ]
    ordered_fragments(
        server_lost,
        framing,
        "independent DeleteBucket lost-response framing",
    )
    for marker in framing:
        damaged = server_lost.replace(marker, "", 1)
        try:
            ordered_fragments(
                damaged,
                framing,
                "damaged DeleteBucket lost-response framing",
            )
        except AssertionError:
            pass
        else:
            raise AssertionError(
                f"damaged DeleteBucket lost-response marker accepted: "
                f"{marker}"
            )


def main() -> None:
    verify_model(load_model())
    verify_registry()
    verify_sources()
    verify_negative_oracle()
    print("DeleteBucket preparation evidence: OK")


if __name__ == "__main__":
    main()
