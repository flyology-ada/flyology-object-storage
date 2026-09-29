#!/usr/bin/env python3
"""Fail-closed evidence for reviewed CreateBucket qualification."""

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
QUALIFICATION = ROOT / "docs" / "qualification" / "create-bucket.md"


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
    model_path = os.environ.get("FLYOLOGY_S3_SERVICE_MODEL", "")
    assert model_path, "FLYOLOGY_S3_SERVICE_MODEL is required"
    path = Path(model_path)
    regular(path)
    assert hashlib.sha256(path.read_bytes()).hexdigest() == MODEL_SHA256
    return json.loads(path.read_text(encoding="utf-8"))


def verify_model(model: dict[str, object]) -> None:
    operation = model["operations"]["CreateBucket"]
    assert operation["http"] == {
        "method": "PUT",
        "requestUri": "/{Bucket}",
    }
    assert operation["input"] == {"shape": "CreateBucketRequest"}
    assert operation["output"] == {"shape": "CreateBucketOutput"}
    assert operation["errors"] == [
        {"shape": "BucketAlreadyExists"},
        {"shape": "BucketAlreadyOwnedByYou"},
    ]
    request = model["shapes"]["CreateBucketRequest"]
    assert request["required"] == ["Bucket"]
    expected_input = [
        ("ACL", "header", "x-amz-acl"),
        ("Bucket", "uri", "Bucket"),
        ("CreateBucketConfiguration", None, None),
        ("GrantFullControl", "header", "x-amz-grant-full-control"),
        ("GrantRead", "header", "x-amz-grant-read"),
        ("GrantReadACP", "header", "x-amz-grant-read-acp"),
        ("GrantWrite", "header", "x-amz-grant-write"),
        ("GrantWriteACP", "header", "x-amz-grant-write-acp"),
        (
            "ObjectLockEnabledForBucket",
            "header",
            "x-amz-bucket-object-lock-enabled",
        ),
        ("ObjectOwnership", "header", "x-amz-object-ownership"),
        ("BucketNamespace", "header", "x-amz-bucket-namespace"),
    ]
    members = request["members"]
    assert list(members) == [item[0] for item in expected_input]
    for name, location, wire_name in expected_input:
        if location is None:
            assert "location" not in members[name]
            continue
        assert members[name]["location"] == location
        assert members[name]["locationName"] == wire_name
    assert request["payload"] == "CreateBucketConfiguration"
    output = model["shapes"]["CreateBucketOutput"]["members"]
    assert list(output) == ["Location", "BucketArn"]
    assert output["Location"]["locationName"] == "Location"
    assert output["BucketArn"]["locationName"] == "x-amz-bucket-arn"


def verify_registry() -> None:
    data = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    matches = [
        item for item in data["operation"] if item["name"] == "CreateBucket"
    ]
    assert len(matches) == 1, "CreateBucket registry entry is not unique"
    entry = matches[0]
    expected = {
        "tier": "core",
        "provider": "buckets",
        "family": "rest_xml_mutation",
        "public_provider": "Flyology.Object_Storage.Client.Buckets",
        "codec": "strict_rest_xml_request_and_singleton_headers",
        "public_name": "Create",
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
        "qualification": "create_bucket",
        "ada_symbols": [
            "Prepare_Create_Bucket",
            "Decode_Create_Bucket_Complete_Response",
            "Execute_Create_Bucket",
            "Create_Bucket_Operation",
            "Create",
            "Finish",
        ],
    }
    for key, value in expected.items():
        assert entry[key] == value, (
            f"CreateBucket registry field changed: {key}"
        )
    assert entry["absence"] == (
        "not applicable; the request creates a new named bucket and exact "
        "conflict responses remain structured typed rejections"
    )
    assert entry["certainty"] == (
        "only a complete validated 200 reports Bucket_Creation_Completed; "
        "exact recognized non-mutating rejections or definite non-admission "
        "report Bucket_Definitely_Not_Created; pre-admission cancellation "
        "reports Bucket_Creation_Cancelled_Before_Admission; possible or "
        "incomplete admission, retryable responses, and malformed responses "
        "report Bucket_Creation_Outcome_Unknown; no automatic replay"
    )
    assert entry["reconciliation"] == (
        "caller-selected HeadBucket for the exact bucket name, ownership "
        "context, and intended location before retry"
    )
    assert entry["errors"] == [
        "authentication",
        "authorization",
        "invalid_request",
        "unavailable_or_retryable",
        "corrupt_or_invalid_response",
    ]
    assert entry["exclusions"] == [
        (
            "the server qualification covers authenticated path-style "
            "general-purpose bucket creation only; directory-bucket, "
            "access-point, and Outposts routing are not claimed"
        ),
        (
            "initial tags, public or grant ACLs, Object Lock, non-enforced "
            "ownership, and explicit bucket namespace selection remain typed "
            "server capability exclusions"
        ),
        (
            "cross-region redirect handling and virtual-hosted creation are "
            "not qualified"
        ),
        "creation cannot roll back an already-created bucket",
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
            "tools/verify-create-bucket-preparation.py",
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
    expected_lane = [
        [
            "uv",
            "run",
            "--python",
            "3.13",
            "--",
            "tools/verify-create-bucket-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
        [
            "./tools/build-api-docs.sh",
            "/private/tmp/fos-create-bucket-gnatdoc",
        ],
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    assert data["qualification"]["create_bucket"] == expected_lane


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

    low_declarations = between(
        low_spec,
        "type Create_Bucket_Parameters is record",
        "type Delete_Bucket_Parameters is record",
        "CreateBucket Low_Level declaration region",
    )
    ordered(
        low_declarations,
        [
            "type Create_Bucket_Parameters is record",
            "function Prepare_Create_Bucket\n     (",
            "type Create_Bucket_Result is record",
            "type Create_Bucket_Outcome_Kind is",
            "function Decode_Create_Bucket_Complete_Response\n     (",
            "function Execute_Create_Bucket\n     (",
        ],
        "CreateBucket Low_Level declaration inventory",
    )
    once(
        low_spec,
        "procedure Create_Bucket\n     (",
        "CreateBucket private exchange declaration",
    )
    prepare = between(
        low_body,
        "function Prepare_Create_Bucket\n     (",
        "function Decode_Create_Bucket_Response\n     (",
        "CreateBucket preparation",
    )
    for marker in [
        'Add_Header ("x-amz-acl", ACL);',
        '"x-amz-bucket-object-lock-enabled"',
        'Add_Header ("x-amz-object-ownership", Ownership);',
        'Add_Header ("x-amz-bucket-namespace", Namespace);',
        "Serialize_Create_Configuration",
        "Result.Owned_Request_Payload",
    ]:
        assert marker in prepare, f"CreateBucket preparation missing: {marker}"

    public_contract = between(
        buckets_spec,
        "type Bucket_Creation_Disposition is",
        "type Bucket_Deletion_Disposition is",
        "CreateBucket public contract region",
    )
    ordered(
        public_contract,
        [
            "type Bucket_Creation_Disposition is",
            "type Create_Bucket_Result\n     (",
            "type Create_Bucket_Operation",
            "procedure Create\n     (",
            "function Create\n     (",
            "procedure Finish\n     (",
        ],
        "CreateBucket public contract",
    )
    driver = between(
        buckets_body,
        "function Normalize_Create_Bucket_Response",
        "function Normalize_Delete_Bucket_Response",
        "CreateBucket provider implementation",
    )
    for marker in [
        "Bucket_Creation_Completed",
        "Bucket_Definitely_Not_Created",
        "Bucket_Creation_Outcome_Unknown",
        "Bucket_Creation_Cancelled_Before_Admission",
        "Operations.Cancel (Item.Child);",
        '"CreateBucket restart changed a retained owner"',
    ]:
        assert marker in driver, f"CreateBucket provider missing: {marker}"

    corpus = between(
        testing,
        "procedure Check_Create_Bucket_Response",
        "procedure Check_Delete_Bucket_Response",
        "CreateBucket certainty corpus",
    )
    for code in [
        "InvalidBucketName",
        "IllegalLocationConstraintException",
        "InvalidAccessKeyId",
        "AccessDenied",
        "BucketAlreadyExists",
        "BucketAlreadyOwnedByYou",
        "TooManyBuckets",
        "NotImplemented",
        "OperationAborted",
        "SlowDown",
        "InternalError",
        "BadGateway",
        "RequestTimeout",
    ]:
        assert f'"{code}"' in corpus, f"CreateBucket corpus missing {code}"
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
        "Create_Admission_Native",
        "Create_Admission_Lightweight",
        "Create_Drain_Native",
        "Create_Drain_Lightweight",
    ]:
        assert socket.count(token) == 3, (
            f"CreateBucket token inventory changed: {token}"
        )
    dispatcher_fragments = [
        (
            "when Create_Bucket_Cancellation =>\n"
            "                        if Cancellation_Round = 1 then\n"
            "                           Create_Drain_Native.Request;\n"
            "                        else\n"
            "                           Create_Drain_Lightweight.Request;\n"
            "                        end if;"
        ),
        (
            "when Create_Bucket_Cancellation =>\n"
            "                     if Cancellation_Round = 1 then\n"
            "                        Create_Admission_Native.Request;\n"
            "                     else\n"
            "                        Create_Admission_Lightweight.Request;\n"
            "                     end if;"
        ),
        (
            "when Create_Bucket_Cancellation =>\n"
            "                           raise Program_Error with\n"
            '                             "CreateBucket cancel peer sent '
            'data before " &\n'
            '                             "drain";'
        ),
    ]
    for fragment in dispatcher_fragments:
        assert socket.count(fragment) == 1, (
            "CreateBucket cancellation dispatcher changed"
        )

    server_cancel = between(
        socket,
        'Serve\n           ("", "PUT", "/create-cancel",',
        "--  Accept exactly one CreateBucket and drop its response.",
        "CreateBucket server cancellation sequence",
    )
    ordered_fragments(
        server_cancel,
        [
            '"PUT", "/create-cancel"',
            "Await_Cancellation => True",
            "Cancellation_Kind => Create_Bucket_Cancellation",
            "Cancellation_Round => Round",
            '"PUT", "/create-cancel-restart"',
        ],
        "CreateBucket server cancellation sequence",
    )
    server_lost = between(
        socket,
        "--  Accept exactly one CreateBucket and drop its response.",
        '"DELETE",\n            "/typed-deleted"',
        "CreateBucket server lost-response sequence",
    )
    ordered_fragments(
        server_lost,
        [
            '"HEAD", "/create-lost", Keep_Open => True',
            '"", "PUT", "/create-lost"',
            "Reuse_Peer => True",
            '"HEAD", "/create-lost"',
        ],
        "CreateBucket server lost-response sequence",
    )
    assert "automatic replay desynchronizes this sequence" in server_lost

    client_cancel = between(
        socket,
        "Create_Admission_Native.Wait_Source",
        "Create_Parameters : Low_Level.Create_Bucket_Parameters :=",
        "CreateBucket client cancellation sequence",
    )
    ordered_fragments(
        client_cancel,
        [
            "Create_Admission_Native.Wait_Source",
            "Create_Drain_Native.Wait_Source",
            "Create_Admission_Lightweight.Wait_Source",
            "Create_Drain_Lightweight.Wait_Source",
            "Cancel_Set : aliased Operations.Completion_Set (5);",
            "Operations.Wait_Some (Cancel_Set, Completed_Batch);",
            "Flyology.IO.Finish (Admission_Ready);",
            "Operations.Cancel (Cancel_Operation);",
            "Operations.Wait_All (Cancel_Set);",
            "Finish (Cancel_Operation, Cancel_Result);",
            "Bucket_Creation_Outcome_Unknown",
            "Flyology.IO.Finish (Drain_Ready);",
            '"create-cancel-restart"',
            "Operations.Wait_All (Cancel_Set);",
            "Finish (Cancel_Operation, Cancel_Result);",
            "Bucket_Creation_Completed",
            "same-operation CreateBucket restart mismatch",
        ],
        "CreateBucket client cancellation sequence",
    )
    client_lost = between(
        socket,
        "Create_Parameters : Low_Level.Create_Bucket_Parameters :=",
        "high-level CreateBucket ignored cancellation/deadline",
        "CreateBucket client lost-response sequence",
    )
    ordered_fragments(
        client_lost,
        [
            "Before : constant Head_Bucket_Result := Buckets.Head",
            "Low_Level.Head_Bucket_Rejected",
            "Before.Response.Status /= 404",
            "Lost : constant Create_Bucket_Result := Buckets.Create",
            "Bucket_Creation_Outcome_Unknown",
            "After : constant Head_Bucket_Result := Buckets.Head",
            "Low_Level.Bucket_Found",
            "lost-response CreateBucket reconciliation mismatch",
        ],
        "CreateBucket client lost-response sequence",
    )
    assert "HeadBucket reconciliation" in docs
    assert "repository-owned GNATdoc warning prevents" in docs


def verify_negative_oracle() -> None:
    markers = [
        "Bucket_Creation_Completed",
        "Bucket_Definitely_Not_Created",
        "Bucket_Creation_Outcome_Unknown",
        "Bucket_Creation_Cancelled_Before_Admission",
    ]
    fixture = "\n".join(markers)
    ordered(fixture, markers, "CreateBucket independent certainty order")
    for marker in markers:
        damaged = fixture.replace(marker, "", 1)
        try:
            ordered(damaged, markers, "CreateBucket damaged certainty order")
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
        "dropped-create-response",
        "head-after",
    ]
    fixture = "\n".join(lifecycle)
    ordered_fragments(
        fixture, lifecycle, "CreateBucket independent lifecycle order"
    )
    for marker in lifecycle:
        damaged = fixture.replace(marker, "", 1)
        try:
            ordered_fragments(
                damaged,
                lifecycle,
                "CreateBucket damaged lifecycle order",
            )
        except AssertionError:
            pass
        else:
            raise AssertionError(
                f"missing lifecycle marker accepted: {marker}"
            )


def main() -> None:
    assert hashlib.sha256(REGISTRY.read_bytes()).hexdigest()
    verify_model(load_model())
    verify_registry()
    verify_sources()
    verify_negative_oracle()
    print("CreateBucket preparation evidence: OK")


if __name__ == "__main__":
    main()
