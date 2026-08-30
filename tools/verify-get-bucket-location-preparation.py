#!/usr/bin/env python3
"""Fail-closed evidence for reviewed GetBucketLocation qualification."""

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
    ROOT
    / "tests"
    / "src"
    / "flyology-object_storage-client-buckets-testing.adb"
)
SOCKET = ROOT / "tests" / "src" / "s3_http_socket_corpus.adb"
SERVER = ROOT / "src" / "flyology-object_storage-server-s3_applications.adb"
SERVER_TEST = ROOT / "tests" / "src" / "s3_server_application_corpus.adb"
BACKEND = ROOT / "tests" / "src" / "object_storage_test_cases.adb"
IMPLEMENTATION = ROOT / "tests" / "src" / "s3_implementation_corpus.adb"
QUALIFICATION = (
    ROOT / "docs" / "qualification" / "get-bucket-location.md"
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


def ordered_once(text: str, markers: list[str], label: str) -> None:
    positions = [once(text, marker, label) for marker in markers]
    assert positions == sorted(positions), f"{label}: evidence order changed"


def between(text: str, start: str, end: str, label: str) -> str:
    first = once(text, start, label)
    last = once(text, end, label)
    assert first < last, f"{label}: invalid region boundary"
    return text[first:last]


def load_model() -> dict[str, object]:
    model_name = os.environ.get("FLYOLOGY_S3_SERVICE_MODEL", "")
    assert model_name, "FLYOLOGY_S3_SERVICE_MODEL is required"
    path = Path(model_name)
    regular(path)
    assert hashlib.sha256(path.read_bytes()).hexdigest() == MODEL_SHA256
    return json.loads(path.read_text(encoding="utf-8"))


def verify_model(model: dict[str, object]) -> None:
    operation = model["operations"]["GetBucketLocation"]
    assert operation["http"] == {
        "method": "GET",
        "requestUri": "/{Bucket}?location",
    }
    assert operation["input"] == {"shape": "GetBucketLocationRequest"}
    assert operation["output"] == {"shape": "GetBucketLocationOutput"}
    request = model["shapes"]["GetBucketLocationRequest"]
    assert request["required"] == ["Bucket"]
    assert list(request["members"]) == ["Bucket", "ExpectedBucketOwner"]
    assert request["members"]["Bucket"]["location"] == "uri"
    owner = request["members"]["ExpectedBucketOwner"]
    assert owner["location"] == "header"
    assert owner["locationName"] == "x-amz-expected-bucket-owner"
    output = model["shapes"]["GetBucketLocationOutput"]
    assert list(output["members"]) == ["LocationConstraint"]
    assert output["members"]["LocationConstraint"]["shape"] == (
        "BucketLocationConstraint"
    )


def verify_registry(data: dict[str, object] | None = None) -> None:
    if data is None:
        data = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    matches = [
        item
        for item in data["operation"]
        if item["name"] == "GetBucketLocation"
    ]
    assert len(matches) == 1, "GetBucketLocation registry entry is not unique"
    entry = matches[0]
    expected = {
        "tier": "core",
        "provider": "buckets",
        "family": "bounded_rest_xml_read",
        "public_provider": "Flyology.Object_Storage.Client.Buckets",
        "codec": "rest_xml_and_headers",
        "public_name": "Get_Location",
        "absence": (
            "no dedicated absence variant; exact NoSuchBucket remains a "
            "bounded structured typed rejection"
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
        "qualification": "get_bucket_location",
        "ada_symbols": [
            "Prepare_Get_Bucket_Location",
            "Decode_Get_Bucket_Location_Response",
            "Execute_Get_Bucket_Location",
            "Get_Bucket_Location_Operation",
            "Get_Location",
            "Finish",
        ],
    }
    for key, value in expected.items():
        assert entry[key] == value, f"GetBucketLocation field changed: {key}"
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
        "tools/verify-get-bucket-location-preparation.py",
        "tests/src/s3_http_socket_corpus.adb",
    ]
    assert entry["evidence"]["backend"] == [
        "tests/src/object_storage_test_cases.adb",
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
    assert data["qualification"]["get_bucket_location"] == [
        [
            "uv",
            "run",
            "--python",
            "3.13",
            "--",
            "tools/verify-get-bucket-location-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
        [
            "./tools/build-api-docs.sh",
            "/private/tmp/fos-get-bucket-location-gnatdoc",
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
    server_source = SERVER.read_text(encoding="utf-8")
    server_test = SERVER_TEST.read_text(encoding="utf-8")
    backend = BACKEND.read_text(encoding="utf-8")
    implementation = IMPLEMENTATION.read_text(encoding="utf-8")
    docs = QUALIFICATION.read_text(encoding="utf-8")

    declarations = between(
        low_spec,
        "type Get_Bucket_Location_Parameters is record",
        "type Put_Bucket_Tagging_Parameters is record",
        "GetBucketLocation Low_Level declarations",
    )
    ordered(
        declarations,
        [
            "type Get_Bucket_Location_Parameters is record",
            "function Prepare_Get_Bucket_Location",
            "type Get_Bucket_Location_Result is record",
            "type Get_Bucket_Location_Outcome_Kind is",
            "type Get_Bucket_Location_Outcome",
            "function Decode_Get_Bucket_Location_Response",
            "function Execute_Get_Bucket_Location",
        ],
        "GetBucketLocation declaration inventory",
    )
    prepare = between(
        low_body,
        "function Prepare_Get_Bucket_Location",
        "function Decode_Get_Bucket_Location_Response",
        "GetBucketLocation request preparation",
    )
    for marker in [
        'SigV4.Pair ("location", "")',
        'SigV4.Pair ("x-amz-expected-bucket-owner", Owner)',
        '(Get_Bucket_Location_Operation, "GET", Origin, Style, Bucket, "",',
        "Object_Resource => False",
    ]:
        assert marker in prepare, (
            f"GetBucketLocation preparation lacks {marker}"
        )
    decoder = between(
        low_body,
        "function Decode_Get_Bucket_Location_Response",
        "function Execute_Get_Bucket_Location",
        "GetBucketLocation decoder",
    )
    for marker in [
        "if Status = 200 then",
        "S3.Buckets.Parse_Location_Constraint (Payload, Limits)",
        "Kind   => Get_Bucket_Location_Rejected",
        "S3.Buckets.Malformed_Bucket_Location",
        '"malformed GetBucketLocation response"',
    ]:
        assert marker in decoder, f"GetBucketLocation decoder lacks {marker}"
    public_contract = between(
        buckets_spec,
        "type Get_Bucket_Location_Result_Kind is",
        "type Bucket_Tag_Mutation_Disposition is",
        "GetBucketLocation public contract",
    )
    ordered(
        public_contract,
        [
            "type Get_Bucket_Location_Result_Kind is",
            "type Get_Bucket_Location_Result",
            "type Get_Bucket_Location_Operation",
            "procedure Get_Location",
            "function Get_Location",
            "procedure Finish",
        ],
        "GetBucketLocation public contract",
    )
    provider = between(
        buckets_body,
        "function Normalize_Get_Bucket_Location_Response",
        "function Normalize_Get_Bucket_Versioning_Response",
        "GetBucketLocation provider",
    )
    for marker in [
        "Authentication_Failed",
        "Authorization_Failed",
        "Not_Found",
        "Invalid_Request",
        "Unavailable_Or_Retryable",
        "Corrupt_Or_Invalid_Response",
        "Operations.Cancel (Item.Child);",
        '"GetBucketLocation restart changed a retained owner"',
    ]:
        assert marker in provider, f"GetBucketLocation provider lacks {marker}"

    query_classifier = between(
        server_source,
        "Is_Get_Bucket_Location_Query : constant Boolean :=",
        "Looks_Like_ACL_Query : constant Boolean :=",
        "GetBucketLocation server query classifier",
    )
    ordered_once(
        query_classifier,
        [
            'Query_Text = "location"',
            'Query_Text = "location="',
            'Query_Text = "location=&x-id=GetBucketLocation"',
            'Query_Text = "x-id=GetBucketLocation&location="',
        ],
        "GetBucketLocation server query classifier",
    )
    assert (
        'elsif Method = "GET" and then Is_Get_Bucket_Location_Query\n'
        "            then Get_Bucket_Location"
    ) in server_source
    server_handler = between(
        server_source,
        "            when Get_Bucket_Location =>",
        "            when Put_Bucket_Tagging =>",
        "GetBucketLocation server handler",
    )
    ordered(
        server_handler,
        [
            "Check_Expected_Bucket_Owner",
            "Store.Head_Bucket",
            "if Result = Success then",
            'then "us-east-1" else Configured',
            "Buckets.Valid_Location_Constraint (Region)",
            (
                'Send_Error\n                                '
                '(X, 500, "InternalError"'
            ),
            "Buckets.Serialize_Location_Constraint",
            "Send_Backend_Error (X, Result, True, Target_Text)",
        ],
        "GetBucketLocation server handler",
    )
    for marker in [
        "GetBucketLocation did not return null us-east-1 constraint",
        "GetBucketLocation rejected the authenticated owner",
        "GetBucketLocation ignored the expected owner precondition",
        "GetBucketLocation did not check bucket existence",
        "GetBucketLocation accepted a request body",
        "GetBucketLocation accepted a duplicate subresource",
    ]:
        assert server_test.count(marker) == 1, (
            f"GetBucketLocation server corpus lacks {marker}"
        )
    for marker in [
        'Buckets.Serialize_Location_Constraint ("us-east-1")',
        'Buckets.Serialize_Location_Constraint ("us-west-2")',
        "GetBucketLocation us-east-1 was not encoded as null",
        "GetBucketLocation legacy constraint round trip",
        "malformed GetBucketLocation XML was accepted",
    ]:
        assert backend.count(marker) == 1, (
            f"GetBucketLocation backend evidence lacks {marker}"
        )
    for marker in [
        "procedure Require_Bucket_Location",
        "Low_Level.Prepare_Get_Bucket_Location",
        "Low_Level.Execute_Get_Bucket_Location",
        "Client_Buckets.Get_Location",
        "high-level bucket-location normalization mismatch",
    ]:
        assert implementation.count(marker) == 1, (
            f"GetBucketLocation implementation corpus lacks {marker}"
        )

    corpus = between(
        testing,
        "procedure Check_Get_Bucket_Location_Response",
        "procedure Check_Get_Bucket_Policy_Response",
        "GetBucketLocation normalization corpus",
    )
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
    ordered_once(corpus, response_cases, "GetBucketLocation response matrix")
    assert "for Kind of Failure_Kinds loop" in corpus
    assert "for Admission in HTTP_Client.Admission_Certainty loop" in corpus
    assert socket.count(
        "Buckets_Testing.Check_Get_Bucket_Location_Result_Corpus;"
    ) == 1

    cancellation_inventory = (
        "      Create_Multipart_Cancellation,\n"
        "      Get_Bucket_Location_Cancellation,\n"
        "      Get_Bucket_Versioning_Cancellation,\n"
        "      Put_Bucket_Versioning_Cancellation);"
    )
    assert socket.count(cancellation_inventory) == 1
    serve = between(
        socket,
        "      procedure Serve\n",
        "         declare\n            Request : constant String :=",
        "shared socket Serve request-head boundary",
    )
    serve_contract = [
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
    ordered(serve, serve_contract, "fresh peer versus HTTP admission")
    assert serve.count("Deadline : constant Ada.Real_Time.Time :=") == 1
    assert serve.count("Timeout => Remaining_Time") == 2
    assert "Timeout => 5.0" not in serve
    delete_lost = between(
        socket,
        "--  Accept exactly one DeleteBucket and drop its response.",
        '"GET",\n            "/typed-location?location"',
        "DeleteBucket prerequisite lost-response sequence",
    )
    ordered(
        delete_lost,
        [
            '"HTTP/1.1 200 OK" & CRLF &',
            '"Content-Length: 0" & CRLF &',
            '"x-amz-bucket-region: us-west-2" & CRLF &',
            '"Connection: keep-alive" & CRLF & CRLF',
            '"HEAD", "/delete-bucket-lost"',
            "Keep_Open => True",
            '"", "DELETE", "/delete-bucket-lost"',
            "Reuse_Peer => True",
            '"HEAD", "/delete-bucket-lost"',
        ],
        "DeleteBucket prerequisite lost-response sequence",
    )
    server_start = once(
        socket,
        '"", "GET", "/get-location-cancel?location"',
        "GetBucketLocation cancellation server region",
    )
    server_end = socket.find('"HEAD", "/example-bucket"', server_start)
    assert server_end > server_start, (
        "GetBucketLocation cancellation server terminator is missing"
    )
    server = socket[server_start:server_end]
    ordered(
        server,
        [
            '"/get-location-cancel?location"',
            'Expected_Bucket_Owner => "123456789012"',
            "Await_Cancellation => True",
            "Cancellation_Kind => Get_Bucket_Location_Cancellation",
            "Cancellation_Round => Round",
            '"2006-03-01/"">EU</LocationConstraint>"',
            '"/get-location-cancel-restart?location"',
        ],
        "GetBucketLocation cancellation server region",
    )
    client = between(
        socket,
        '"typed GetBucketLocation response mismatch"',
        '"composable HeadBucket response mismatch"',
        "GetBucketLocation client region",
    )
    ordered(
        client,
        [
            '"composed GetBucketLocation first result mismatch"',
            '"composed GetBucketLocation restart mismatch"',
            '"get-location-cancelled"',
            "HTTP_Client.Not_Admitted",
            "Get_Location_Admission_Native.Wait_Source",
            "Get_Location_Drain_Native.Wait_Source",
            "Get_Location_Admission_Lightweight.Wait_Source",
            "Get_Location_Drain_Lightweight.Wait_Source",
            "Cancel_Set : aliased Operations.Completion_Set (5);",
            "Operations.Wait_Some (Cancel_Set, Completed_Batch);",
            "Flyology.IO.Finish (Admission_Ready);",
            "Operations.Cancel (Cancel_Operation);",
            "Operations.Wait_All (Cancel_Set);",
            "Finish (Cancel_Operation, Cancel_Result);",
            "HTTP_Client.Possibly_Admitted",
            "Flyology.IO.Finish (Drain_Ready);",
            "Token => Changed_Token'Access",
            '"GetBucketLocation accepted changed retained owner"',
            "Token => Cancel_Token'Access",
            '"same-operation GetBucketLocation restart mismatch"',
        ],
        "GetBucketLocation client lifecycle",
    )
    assert socket.count("Run_And_Report (1);") == 1
    assert socket.count("Run_And_Report (2);") == 1
    assert "read-only operation" in docs
    assert "repository-owned GNATdoc warning gate" in docs


def verify_negative_oracle() -> None:
    model = load_model()
    for mutate, label in [
        (
            lambda value: value["operations"]["GetBucketLocation"][
                "http"
            ].update(method="POST"),
            "method",
        ),
        (
            lambda value: value["shapes"]["GetBucketLocationRequest"][
                "members"
            ].pop("ExpectedBucketOwner"),
            "expected owner",
        ),
        (
            lambda value: value["operations"]["GetBucketLocation"].update(
                output={"shape": "WrongOutput"}
            ),
            "output shape",
        ),
    ]:
        damaged = copy.deepcopy(model)
        mutate(damaged)
        try:
            verify_model(damaged)
        except (AssertionError, KeyError):
            pass
        else:
            raise AssertionError(
                f"damaged GetBucketLocation model accepted: {label}"
            )

    registry = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    registry_mutations = [
        ("public name", lambda entry: entry.update(public_name="GetLocation")),
        ("server evidence", lambda entry: entry["evidence"]["server"].pop()),
        ("exclusion", lambda entry: entry["exclusions"].pop()),
    ]
    for label, mutate in registry_mutations:
        damaged = copy.deepcopy(registry)
        entry = next(
            item
            for item in damaged["operation"]
            if item["name"] == "GetBucketLocation"
        )
        mutate(entry)
        try:
            verify_registry(damaged)
        except (AssertionError, KeyError):
            pass
        else:
            raise AssertionError(
                f"damaged GetBucketLocation registry accepted: {label}"
            )
    damaged = copy.deepcopy(registry)
    damaged["qualification"]["get_bucket_location"][-3] = [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-get-bucket-location-gnatdoc",
        "--operation",
        "GetBucketLocation",
    ]
    try:
        verify_registry(damaged)
    except AssertionError:
        pass
    else:
        raise AssertionError("preselected GetBucketLocation docs lane accepted")

    testing = TESTING.read_text(encoding="utf-8")
    corpus = between(
        testing,
        "procedure Check_Get_Bucket_Location_Response",
        "procedure Check_Get_Bucket_Policy_Response",
        "GetBucketLocation negative normalization corpus",
    )
    response_cases = [
        '(200, "", No_Failure)',
        '(400, "InvalidBucketName", Invalid_Request)',
        '(403, "AccessDenied", Authorization_Failed)',
        '(404, "NoSuchBucket", Not_Found)',
        '(503, "SlowDown", Unavailable_Or_Retryable)',
        '(409, "", Corrupt_Or_Invalid_Response)',
    ]
    ordered_once(
        corpus,
        response_cases,
        "independent GetBucketLocation normalization matrix",
    )
    for marker in response_cases:
        for damaged in [
            corpus.replace(marker, "", 1),
            corpus.replace(marker, marker + "\n" + marker, 1),
        ]:
            try:
                ordered_once(
                    damaged,
                    response_cases,
                    "damaged GetBucketLocation normalization matrix",
                )
            except AssertionError:
                pass
            else:
                raise AssertionError(
                    f"damaged normalization marker accepted: {marker}"
                )
    reordered = corpus.replace(response_cases[0], "__FIRST__", 1)
    reordered = reordered.replace(response_cases[1], response_cases[0], 1)
    reordered = reordered.replace("__FIRST__", response_cases[1], 1)
    try:
        ordered_once(
            reordered,
            response_cases,
            "reordered GetBucketLocation normalization matrix",
        )
    except AssertionError:
        pass
    else:
        raise AssertionError("reordered GetBucketLocation matrix accepted")

    socket = SOCKET.read_text(encoding="utf-8")
    client = between(
        socket,
        '"typed GetBucketLocation response mismatch"',
        '"composable HeadBucket response mismatch"',
        "GetBucketLocation negative client region",
    )
    lifecycle = [
        '"get-location-cancelled"',
        "Get_Location_Admission_Native.Wait_Source",
        "Get_Location_Drain_Native.Wait_Source",
        "Get_Location_Admission_Lightweight.Wait_Source",
        "Get_Location_Drain_Lightweight.Wait_Source",
        "Cancel_Set : aliased Operations.Completion_Set (5);",
        "Operations.Wait_Some (Cancel_Set, Completed_Batch);",
        "Operations.Cancel (Cancel_Operation);",
        "Flyology.IO.Finish (Drain_Ready);",
        "Token => Changed_Token'Access",
        '"GetBucketLocation accepted changed retained owner"',
        (
            "Token => Cancel_Token'Access,\n"
            "                     Operation => Cancel_Operation);"
        ),
        '"same-operation GetBucketLocation restart mismatch"',
    ]
    ordered(client, lifecycle, "independent GetBucketLocation lifecycle")
    for marker in lifecycle:
        damaged = client.replace(marker, "", 1)
        try:
            ordered(damaged, lifecycle, "damaged GetBucketLocation lifecycle")
        except AssertionError:
            pass
        else:
            raise AssertionError(
                f"damaged GetBucketLocation lifecycle accepted: {marker}"
            )

    serve = between(
        socket,
        "      procedure Serve\n",
        "         declare\n            Request : constant String :=",
        "negative shared socket Serve boundary",
    )
    serve_contract = [
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

    def validate_serve(value: str) -> None:
        ordered(value, serve_contract, "independent Serve boundary")
        assert value.count("Deadline : constant Ada.Real_Time.Time :=") == 1
        assert value.count("Timeout => Remaining_Time") == 2
        assert "Timeout => 5.0" not in value

    validate_serve(serve)
    for marker in serve_contract:
        damaged = serve.replace(marker, "", 1)
        try:
            validate_serve(damaged)
        except AssertionError:
            pass
        else:
            raise AssertionError(f"damaged Serve boundary accepted: {marker}")
    delete_lost = between(
        socket,
        "--  Accept exactly one DeleteBucket and drop its response.",
        '"GET",\n            "/typed-location?location"',
        "negative DeleteBucket prerequisite sequence",
    )
    delete_lost_contract = [
        '"Content-Length: 0" & CRLF &',
        '"x-amz-bucket-region: us-west-2" & CRLF &',
        '"Connection: keep-alive" & CRLF & CRLF',
        '"HEAD", "/delete-bucket-lost"',
        "Keep_Open => True",
        '"", "DELETE", "/delete-bucket-lost"',
        "Reuse_Peer => True",
        '"HEAD", "/delete-bucket-lost"',
    ]
    ordered(
        delete_lost,
        delete_lost_contract,
        "independent DeleteBucket prerequisite sequence",
    )
    for marker in delete_lost_contract:
        damaged = delete_lost.replace(marker, "", 1)
        try:
            ordered(
                damaged,
                delete_lost_contract,
                "damaged DeleteBucket prerequisite sequence",
            )
        except AssertionError:
            pass
        else:
            raise AssertionError(
                f"damaged DeleteBucket prerequisite accepted: {marker}"
            )


def main() -> None:
    verify_model(load_model())
    verify_registry()
    verify_sources()
    verify_negative_oracle()
    print("GetBucketLocation preparation evidence: OK")


if __name__ == "__main__":
    main()
