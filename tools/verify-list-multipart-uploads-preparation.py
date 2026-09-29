#!/usr/bin/env python3
"""Verify the isolated ListMultipartUploads disposition and design corpus."""

from __future__ import annotations

import csv
import copy
import hashlib
import json
import os
import re
import sys
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "tests" / "corpora" / "list-multipart-uploads"
MEMBERS_PATH = CORPUS / "members.tsv"
VECTORS_PATH = CORPUS / "vectors.tsv"
MODEL_PATH = ROOT / "src" / "flyology-object_storage-s3-model.adb"
LOCK_PATH = ROOT / "coverage" / "corpora.lock.toml"
REGISTRY_PATH = ROOT / "coverage" / "s3-operations.toml"
OBJECT_STORAGE_BODY = ROOT / "src" / "flyology-object_storage.adb"
S3_MULTIPART_SPEC = (
    ROOT / "src" / "flyology-object_storage-s3-multipart_uploads.ads"
)
S3_MULTIPART_BODY = (
    ROOT / "src" / "flyology-object_storage-s3-multipart_uploads.adb"
)
LOW_SPEC = ROOT / "src" / "flyology-object_storage-client-low_level.ads"
LOW_BODY = ROOT / "src" / "flyology-object_storage-client-low_level.adb"
TRANSFERS_SPEC = ROOT / "src" / "flyology-object_storage-client-transfers.ads"
TRANSFERS_BODY = ROOT / "src" / "flyology-object_storage-client-transfers.adb"
TRANSFERS_TESTING = (
    ROOT / "tests/src/flyology-object_storage-client-transfers-testing.adb"
)
SOCKET = ROOT / "tests/src/s3_http_socket_corpus.adb"
QUALIFICATION = (
    ROOT / "docs/qualification/list-multipart-uploads-preparation.md"
)

EXPECTED_EVIDENCE = {
    "backend": [
        "tests/src/object_storage_test_cases.adb",
        "sqlite/tests/src/flyology_object_storage_sqlite_tests.adb",
    ],
    "client": [
        "src/flyology-object_storage.adb",
        "src/flyology-object_storage-s3-multipart_uploads.ads",
        "src/flyology-object_storage-s3-multipart_uploads.adb",
        "src/flyology-object_storage-client-low_level.ads",
        "src/flyology-object_storage-client-low_level.adb",
        "src/flyology-object_storage-client-transfers.ads",
        "src/flyology-object_storage-client-transfers.adb",
        "tests/src/flyology-object_storage-client-transfers-testing.adb",
        "tests/src/s3_http_socket_corpus.adb",
    ],
    "server": [
        "src/flyology-object_storage-s3-multipart_uploads.ads",
        "src/flyology-object_storage-s3-multipart_uploads.adb",
        "src/flyology-object_storage-server-s3_applications.adb",
        "tests/src/s3_server_application_corpus.adb",
        "tests/src/s3_http_socket_corpus.adb",
    ],
    "corpus": [
        "tests/corpora/list-multipart-uploads/members.tsv",
        "tests/corpora/list-multipart-uploads/vectors.tsv",
        "tools/verify-list-multipart-uploads-preparation.py",
        "docs/qualification/list-multipart-uploads-preparation.md",
        "tests/src/flyology-object_storage-client-transfers-testing.adb",
        "tests/src/s3_http_socket_corpus.adb",
        "tests/src/s3_implementation_corpus.adb",
        "tests/src/s3_server_application_corpus.adb",
        "tests/scripts/test-minio.sh",
        "tests/scripts/test-rustfs.sh",
        "tests/scripts/test-seaweedfs.sh",
    ],
}

EXPECTED_REVISION = "36c34f15391da01cd717c73c0fffa747c9889768"
EXPECTED_SHA256 = (
    "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
)
EXPECTED_MEMBERS_SHA256 = (
    "188668f0810494602dba0809b17f054828b955fba4c22c23a23d56a29dca647d"
)
EXPECTED_VECTORS_SHA256 = (
    "b9a51bd7c495a030e608dccc3ab988b6baef0cb82bffb4ddf11c4acde450535f"
)
EXPECTED = {
    ("request", "391"): [
        "Bucket", "Delimiter", "EncodingType", "KeyMarker", "MaxUploads",
        "Prefix", "UploadIdMarker", "ExpectedBucketOwner", "RequestPayer",
    ],
    ("response", "390"): [
        "Bucket", "KeyMarker", "UploadIdMarker", "NextKeyMarker", "Prefix",
        "Delimiter", "NextUploadIdMarker", "MaxUploads", "IsTruncated",
        "Uploads", "CommonPrefixes", "EncodingType", "RequestCharged",
    ],
}

MEMBER_HEADER = [
    "direction", "shape", "ordinal", "member", "wire_location",
    "current_boundary", "required_closure", "vector_ids",
]
VECTOR_HEADER = [
    "id", "direction", "layer", "category", "member_refs", "stimulus",
    "expected_contract",
]
ALLOWED_BOUNDARIES = {"projected", "partial"}
ALLOWED_VECTOR_DIRECTIONS = {"request", "response", "both"}
MANIFEST_TO_MODEL_LOCATION = {
    "uri-label": "URI_Location",
    "query": "Query_Location",
    "header": "Header_Location",
    "body": "Body_Location",
}


def fail(message: str) -> None:
    raise ValueError(message)


def regular(path: Path) -> None:
    if not path.is_file() or path.is_symlink():
        fail(f"missing or unsafe ListMultipartUploads evidence: {path}")


def once(text: str, marker: str, label: str) -> int:
    count = text.count(marker)
    if count != 1:
        fail(f"{label}: expected once, found {count}: {marker}")
    return text.index(marker)


def ordered_once(text: str, markers: list[str], label: str) -> None:
    positions = [once(text, marker, label) for marker in markers]
    if positions != sorted(positions):
        fail(f"{label}: evidence order changed")


def between(text: str, start: str, end: str, label: str) -> str:
    first = once(text, start, label)
    last = once(text, end, label)
    if first >= last:
        fail(f"{label}: invalid region boundary")
    return text[first:last + len(end)]


def read_tsv(path: Path, expected_header: list[str]) -> list[dict[str, str]]:
    raw = path.read_bytes()
    if b"\r" in raw:
        fail(f"{path}: CR characters are not canonical")
    with path.open("r", encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        if reader.fieldnames != expected_header:
            fail(f"{path}: header mismatch: {reader.fieldnames!r}")
        rows = list(reader)
    if not rows:
        fail(f"{path}: no rows")
    for number, row in enumerate(rows, start=2):
        if None in row or any(value == "" for value in row.values()):
            fail(f"{path}:{number}: empty or surplus field")
    return rows


def verify_corpus_hashes(
    members_raw: bytes | None = None,
    vectors_raw: bytes | None = None,
) -> None:
    if members_raw is None:
        members_raw = MEMBERS_PATH.read_bytes()
    if vectors_raw is None:
        vectors_raw = VECTORS_PATH.read_bytes()
    if hashlib.sha256(members_raw).hexdigest() != EXPECTED_MEMBERS_SHA256:
        fail("ListMultipartUploads member semantics changed")
    if hashlib.sha256(vectors_raw).hexdigest() != EXPECTED_VECTORS_SHA256:
        fail("ListMultipartUploads vector semantics changed")


def generated_block(model: str, function: str, shape: str) -> str:
    marker = f"   function {function}\n"
    try:
        function_body = model.split(marker, 1)[1].split(
            f"end {function};", 1
        )[0]
    except IndexError as exc:
        raise ValueError(f"generated model has no {function} body") from exc
    match = re.search(
        rf"when {re.escape(shape)} =>\s+case Member is"
        rf"(?P<body>.*?)\s+end case;",
        function_body,
        flags=re.DOTALL,
    )
    if match is None:
        fail(f"generated model has no {function} block for shape {shape}")
    return match.group("body")


def generated_members(model: str, shape: str) -> list[str]:
    pairs = re.findall(
        r'when\s+(\d+)\s+=>\s+return\s+"([^"]+)";',
        generated_block(model, "Member_Name", shape),
    )
    ordinals = [int(ordinal) for ordinal, _ in pairs]
    if ordinals != list(range(1, len(pairs) + 1)):
        fail(f"generated model shape {shape} member order is not contiguous")
    return [name for _, name in pairs]


def generated_locations(model: str, shape: str) -> list[str]:
    pairs = re.findall(
        r"when\s+(\d+)\s+=>\s+return\s+([A-Za-z_]+);",
        generated_block(model, "Location", shape),
    )
    ordinals = [int(ordinal) for ordinal, _ in pairs]
    if ordinals != list(range(1, len(pairs) + 1)):
        fail(f"generated model shape {shape} location order is not contiguous")
    return [location for _, location in pairs]


def generated_count(model: str, shape: str) -> int:
    try:
        body = model.split("function Member_Count", 1)[1].split(
            "end Member_Count;", 1
        )[0]
    except IndexError as exc:
        raise ValueError("generated model has no Member_Count body") from exc
    match = re.search(
        rf"when\s+{re.escape(shape)}\s+=>\s+return\s+(\d+);", body
    )
    if match is None:
        fail(f"generated model has no count for shape {shape}")
    return int(match.group(1))


def split_csv(value: str) -> list[str]:
    values = value.split(",")
    if any(item == "" or item != item.strip() for item in values):
        fail(f"noncanonical comma list: {value!r}")
    if len(values) != len(set(values)):
        fail(f"duplicate item in comma list: {value!r}")
    return values


def verify_registry(data: dict[str, object] | None = None) -> None:
    if data is None:
        data = tomllib.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
    matches = [
        entry for entry in data["operation"]
        if entry["name"] == "ListMultipartUploads"
    ]
    if len(matches) != 1:
        fail("ListMultipartUploads registry entry is not unique")
    entry = matches[0]
    expected = {
        "tier": "core",
        "provider": "transfers",
        "family": "paginated_rest_xml_read",
        "public_provider": "Flyology.Object_Storage.Client.Transfers",
        "codec": "strict_paginated_rest_xml_and_singleton_headers",
        "public_name": "List_Multipart_Uploads_Page",
        "absence": (
            "no dedicated absence variant; a well-formed bounded 404 "
            "NoSuchBucket response is a structured typed rejection"
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
        "qualification": "list_multipart_uploads",
        "ada_symbols": [
            "Prepare_List_Multipart_Uploads",
            "Decode_List_Multipart_Uploads_Complete_Response",
            "Execute_List_Multipart_Uploads",
            "List_Multipart_Uploads_Operation",
            "List_Multipart_Uploads_Page",
            "Finish",
        ],
    }
    for key, value in expected.items():
        if entry[key] != value:
            fail(f"ListMultipartUploads registry field changed: {key}")
    expected_exclusions = [
        (
            "directory-bucket endpoint, session, and marker-order semantics "
            "are outside the qualified general-purpose path claim"
        ),
        (
            "server-side configured Requester Pays accounting is not "
            "claimed; exact client RequestPayer and RequestCharged handling "
            "remains covered"
        ),
        (
            "SeaweedFS 4.43 is excluded from the positive external lane "
            "because its exact-limit response omits required NextKeyMarker "
            "and initiation metadata"
        ),
    ]
    if entry["exclusions"] != expected_exclusions:
        fail("ListMultipartUploads exclusions changed")
    if entry["evidence"] != EXPECTED_EVIDENCE:
        fail("ListMultipartUploads evidence inventory changed")
    if data["qualification"]["list_multipart_uploads"] != [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-list-multipart-uploads-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
        [
            "./tools/build-api-docs.sh",
            "/private/tmp/fos-list-multipart-uploads-gnatdoc",
        ],
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]:
        fail("ListMultipartUploads qualification lane changed")


def verify_authoritative_model() -> None:
    model_name = os.environ.get("FLYOLOGY_S3_SERVICE_MODEL", "")
    if not model_name:
        fail("FLYOLOGY_S3_SERVICE_MODEL is required")
    path = Path(model_name)
    regular(path)
    if hashlib.sha256(path.read_bytes()).hexdigest() != EXPECTED_SHA256:
        fail("pinned botocore service hash changed")
    model = json.loads(path.read_text(encoding="utf-8"))
    operation = model["operations"]["ListMultipartUploads"]
    if operation["http"] != {
        "method": "GET",
        "requestUri": "/{Bucket}?uploads",
    }:
        fail("ListMultipartUploads method or URI changed")
    if operation["input"] != {"shape": "ListMultipartUploadsRequest"}:
        fail("ListMultipartUploads request shape changed")
    if operation["output"] != {"shape": "ListMultipartUploadsOutput"}:
        fail("ListMultipartUploads response shape changed")


def verify_sources() -> None:
    paths = {
        OBJECT_STORAGE_BODY,
        S3_MULTIPART_SPEC,
        S3_MULTIPART_BODY,
        LOW_SPEC,
        LOW_BODY,
        TRANSFERS_SPEC,
        TRANSFERS_BODY,
        TRANSFERS_TESTING,
        SOCKET,
        QUALIFICATION,
    }
    paths.update(
        ROOT / name
        for names in EXPECTED_EVIDENCE.values()
        for name in names
    )
    for path in sorted(paths):
        regular(path)
    object_storage = OBJECT_STORAGE_BODY.read_text(encoding="utf-8")
    s3_spec = S3_MULTIPART_SPEC.read_text(encoding="utf-8")
    s3_body = S3_MULTIPART_BODY.read_text(encoding="utf-8")
    low_spec = LOW_SPEC.read_text(encoding="utf-8")
    low_body = LOW_BODY.read_text(encoding="utf-8")
    transfers_spec = TRANSFERS_SPEC.read_text(encoding="utf-8")
    transfers_body = TRANSFERS_BODY.read_text(encoding="utf-8")
    testing = TRANSFERS_TESTING.read_text(encoding="utf-8")
    socket = SOCKET.read_text(encoding="utf-8")
    docs = QUALIFICATION.read_text(encoding="utf-8")
    object_tests = (
        ROOT / "tests/src/object_storage_test_cases.adb"
    ).read_text(encoding="utf-8")
    sqlite_tests = (
        ROOT / "sqlite/tests/src/flyology_object_storage_sqlite_tests.adb"
    ).read_text(encoding="utf-8")
    server_app = (
        ROOT / "src/flyology-object_storage-server-s3_applications.adb"
    ).read_text(encoding="utf-8")
    server_corpus = (
        ROOT / "tests/src/s3_server_application_corpus.adb"
    ).read_text(encoding="utf-8")
    implementation_corpus = (
        ROOT / "tests/src/s3_implementation_corpus.adb"
    ).read_text(encoding="utf-8")

    bucket_validator = between(
        object_storage,
        "function Valid_Bucket_Name",
        "end Valid_Bucket_Name;",
        "general-purpose bucket validator",
    )
    bucket_rejection = bucket_validator.split(
        "for Character_Value of Value loop", 1
    )[0]
    ordered_once(
        bucket_rejection,
        [
            "Value'Length not in 3 .. 63",
            'Ends_With (Value, "--x-s3")',
            'Ends_With (Value, "--table-s3")',
            "then\n         return False;",
        ],
        "general-purpose bucket validator",
    )
    preparer = between(
        low_body,
        "function Prepare_List_Multipart_Uploads",
        "end Prepare_List_Multipart_Uploads;",
        "ListMultipartUploads preparer",
    )
    validation = between(
        preparer,
        "if not Valid_Bucket_Name (Bucket)",
        'Add ("Bucket", Bucket);',
        "ListMultipartUploads parameter validation",
    )
    ordered_once(
        validation,
        [
            "if not Valid_Bucket_Name (Bucket)",
            "Parameters.Max_Uploads = 0",
            'Request_Payer /= "requester"',
            '"invalid ListMultipartUploads parameters"',
            'Add ("Bucket", Bucket);',
        ],
        "ListMultipartUploads parameter validation",
    )
    ordered_once(
        preparer,
        [
            'Add ("Bucket", Bucket);',
            '"MaxUploads"',
            'Add_Optional ("Delimiter", Parameters.Delimiter);',
            'Add ("EncodingType", "url");',
            'Add_Optional ("KeyMarker", Parameters.Key_Marker);',
            'Add_Optional ("Prefix", Parameters.Prefix);',
            'Add_Optional ("UploadIdMarker", Parameters.Upload_ID_Marker);',
            '"ExpectedBucketOwner"',
            'Add_Optional ("RequestPayer", Parameters.Request_Payer);',
            "Prepare_Model_Request",
            "Result.Operation := List_Multipart_Uploads_Operation;",
            "Result.Requested_Bucket :=",
            "Result.Requested_Key_Marker :=",
            "Result.Requested_Upload_ID_Marker :=",
            "Result.Requested_Prefix :=",
            "Result.Requested_Delimiter :=",
            "Result.Requested_List_Request_Payer :=",
            "Result.Requested_Max_Uploads :=",
            "Result.Requested_URL_Encoding :=",
        ],
        "ListMultipartUploads preparer",
    )
    owner_guard = between(
        transfers_body,
        "procedure Start_List_Multipart_Uploads",
        "Operation.Prepared := Low_Level.Prepare_List_Multipart_Uploads",
        "ListMultipartUploads retained owners",
    )
    ordered_once(
        owner_guard,
        [
            "Operation.HTTP /= Client",
            "Operation.Cancellation /= Token",
            '"ListMultipartUploads restart changed a retained owner"',
            "Operation.Prepared := Low_Level.Prepare_List_Multipart_Uploads",
        ],
        "ListMultipartUploads retained owners",
    )
    normalized_docs = " ".join(docs.split())
    for marker in (
        "type List_Multipart_Uploads_Parameters is record",
        "function Prepare_List_Multipart_Uploads",
        "type List_Multipart_Uploads_Result is record",
        "type List_Multipart_Uploads_Outcome_Kind is",
        "type List_Multipart_Uploads_Outcome\n     (Kind",
        "function Decode_List_Multipart_Uploads_Response",
        "function Decode_List_Multipart_Uploads_Complete_Response",
        "function Execute_List_Multipart_Uploads",
    ):
        once(low_spec, marker, "ListMultipartUploads Low_Level contract")
    complete_decoder = between(
        low_body,
        "function Decode_List_Multipart_Uploads_Complete_Response",
        "end Decode_List_Multipart_Uploads_Complete_Response;",
        "ListMultipartUploads complete decoder",
    )
    ordered_once(
        complete_decoder,
        [
            "Flyology.HTTP.Client.Header_Count (Response, Name);",
            '"invalid ListMultipartUploads response header multiplicity"',
            "Prepared.Operation /= List_Multipart_Uploads_Operation",
            'Singleton_Header ("x-amz-request-charged")',
            "Expected_Encoding : constant String :=",
            "function Expected_Echo",
            "Prepared.Requested_List_Request_Payer",
            "Outcome.Result.Listing.Bucket /= Prepared.Requested_Bucket",
            "Prepared.Requested_Key_Marker",
            "Prepared.Requested_Upload_ID_Marker",
            "Prepared.Requested_Prefix",
            "Prepared.Requested_Delimiter",
            "Prepared.Requested_Max_Uploads",
            '"ListMultipartUploads response does not match prepared request"',
        ],
        "ListMultipartUploads complete decoder",
    )
    for marker in (
        "type List_Multipart_Uploads_Result_Kind is",
        "type List_Multipart_Uploads_Result\n     (Kind",
    ):
        once(transfers_spec, marker, "ListMultipartUploads public contract")
    operation_region = between(
        transfers_spec,
        "type List_Multipart_Uploads_Result_Kind is",
        """procedure Finish
     (Operation : in out List_Multipart_Uploads_Operation;
      Result    : out List_Multipart_Uploads_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);""",
        "ListMultipartUploads public operation",
    )
    ordered_once(
        operation_region,
        [
            "type List_Multipart_Uploads_Result_Kind is",
            "type List_Multipart_Uploads_Result\n     (Kind",
            "type List_Multipart_Uploads_Operation\n     (Set",
            "procedure List_Multipart_Uploads_Page\n     (Client",
            "function List_Multipart_Uploads_Page\n     (Set",
            "procedure Finish",
        ],
        "ListMultipartUploads public operation",
    )
    normalizer = between(
        transfers_body,
        "function Normalize_List_Multipart_Uploads_Response",
        "end Normalize_List_Multipart_Uploads_Failure;",
        "ListMultipartUploads normalization",
    )
    ordered_once(
        normalizer,
        [
            "Admission /= HTTP_Client.Response_Observed",
            "Low_Level.Multipart_Uploads_Listed",
            'Code in "InvalidArgument" | "InvalidRequest"',
            'Value.Status = 501 and then Code = "NotImplemented"',
            'Value.Status = 401 and then Code = "InvalidAccessKeyId"',
            'Value.Status = 403 and then Code = "AccessDenied"',
            'Value.Status = 404 and then Code = "NoSuchBucket"',
            'Value.Status = 409 and then Code = "OperationAborted"',
            'Value.Status = 429 and then Code = "SlowDown"',
            'Value.Status = 500 and then Code = "InternalError"',
            'Value.Status = 502 and then Code = "BadGateway"',
            'Value.Status = 503 and then Code = "SlowDown"',
            'Value.Status = 504 and then Code = "RequestTimeout"',
            "else Corrupt_Or_Invalid_Response",
            "function Normalize_List_Multipart_Uploads_Failure",
            "Failure     => Failed_Reason (Kind)",
        ],
        "ListMultipartUploads normalization",
    )
    corpus = between(
        testing,
        "procedure Check_List_Multipart_Uploads_Result_Corpus is",
        "end Check_List_Multipart_Uploads_Result_Corpus;",
        "ListMultipartUploads normalization corpus",
    )
    ordered_once(
        corpus,
        [
            "Check_List_Multipart_Uploads_Response (200, \"\", No_Failure);",
            '(400, "InvalidArgument", Invalid_Request);',
            '(400, "InvalidRequest", Invalid_Request);',
            '(401, "InvalidAccessKeyId", Authentication_Failed);',
            '(403, "AccessDenied", Authorization_Failed);',
            '(404, "NoSuchBucket", Not_Found);',
            '(409, "OperationAborted", Unavailable_Or_Retryable);',
            '(429, "SlowDown", Unavailable_Or_Retryable);',
            '(500, "InternalError", Unavailable_Or_Retryable);',
            '(502, "BadGateway", Unavailable_Or_Retryable);',
            '(503, "SlowDown", Unavailable_Or_Retryable);',
            '(504, "RequestTimeout", Unavailable_Or_Retryable);',
            '(501, "NotImplemented", Invalid_Request);',
            '(400, "", Corrupt_Or_Invalid_Response);',
            "for Kind of Failure_Kinds loop",
            "for Admission in HTTP_Client.Admission_Certainty loop",
        ],
        "ListMultipartUploads normalization corpus",
    )
    for marker, expected_count in (
        ("List_Multipart_Uploads_Admission_Native", 3),
        ("List_Multipart_Uploads_Admission_Lightweight", 3),
        ("List_Multipart_Uploads_Drain_Native", 3),
        ("List_Multipart_Uploads_Drain_Lightweight", 3),
    ):
        if socket.count(marker) != expected_count:
            fail(f"ListMultipartUploads readiness count changed: {marker}")
    if socket.count("List_Multipart_Uploads_Cancellation") != 5:
        fail("ListMultipartUploads cancellation mapping count changed")
    lifecycle = between(
        socket,
        "List_Multipart_Uploads_Admission_Native.Wait_Source",
        '"same-operation ListMultipartUploads restart mismatch"',
        "ListMultipartUploads client lifecycle",
    )
    cancellation = between(
        lifecycle,
        "Operations.Wait_Some (Cancel_Set, Completed_Batch);",
        "Flyology.IO.Finish (Drain_Ready);",
        "ListMultipartUploads cancellation",
    )
    ordered_once(
        cancellation,
        [
            "Operations.Wait_Some (Cancel_Set, Completed_Batch);",
            "Flyology.IO.Finish (Admission_Ready);",
            "Operations.Cancel (Cancel_Operation);",
            "Operations.Wait_All (Cancel_Set);",
            "Finish (Cancel_Operation, Cancel_Result);",
            "HTTP_Client.Possibly_Admitted",
            '"ListMultipartUploads drain was not acknowledged"',
            "Flyology.IO.Finish (Drain_Ready);",
        ],
        "ListMultipartUploads cancellation",
    )
    restart = between(
        lifecycle,
        "Token => Changed_Token'Access",
        '"same-operation ListMultipartUploads restart mismatch"',
        "ListMultipartUploads restart",
    )
    ordered_once(
        restart,
        [
            "Token => Changed_Token'Access",
            '"ListMultipartUploads restart changed a retained "',
            "Token => Cancel_Token'Access",
            "Operations.Wait_All (Cancel_Set);",
            "Finish (Cancel_Operation, Cancel_Result);",
            '"same-operation ListMultipartUploads restart mismatch"',
        ],
        "ListMultipartUploads restart",
    )
    for marker in (
        "type List_Multipart_Uploads_Request is record",
        "function Parse_List_Multipart_Uploads_Query",
        "type List_Multipart_Uploads_Result is record",
        "function Parse_List_Multipart_Uploads\n",
        "function Serialize_List_Multipart_Uploads",
    ):
        once(s3_spec, marker, "ListMultipartUploads XML contract")
    for marker in (
        "XML.Parse",
        "Validate",
        "ListMultipartUploadsResult",
        "NextKeyMarker",
        "NextUploadIdMarker",
    ):
        if marker not in s3_body:
            fail(f"ListMultipartUploads XML evidence missing: {marker}")
    for marker in (
        "Directory buckets",
        "one HTTP child",
        "no publication disposition",
        "transport drain acknowledgement",
        "repository-owned warning",
    ):
        if marker not in normalized_docs:
            fail(f"ListMultipartUploads qualification prose missing: {marker}")

    backend_region = between(
        object_tests,
        "procedure Exercise_Multipart_Upload_Listing",
        "end Exercise_Multipart_Upload_Listing;",
        "ListMultipartUploads backend corpus",
    )
    ordered_once(
        backend_region,
        [
            '"multipart listing absent bucket"',
            '"multipart listing invalid bucket"',
            '"multipart listing bounded first page"',
            '"multipart listing continuation"',
            '"multipart upload-ID marker filtering"',
            '"key-only multipart marker did not skip equal keys"',
            '"multipart delimiter prefix and page budget"',
            '"multipart delimiter continuation"',
            '"multipart listing prefix filter"',
            '"aborted multipart upload remained visible"',
            '"zero-sized multipart listing is empty and final"',
            '"multipart listing ignored cancellation"',
            '"multipart listing ignored expired deadline"',
        ],
        "ListMultipartUploads backend corpus",
    )
    sqlite_region = between(
        sqlite_tests,
        '"SQLite second multipart create failed"',
        '"SQLite multipart upload listing metadata failed"',
        "ListMultipartUploads SQLite corpus",
    )
    ordered_once(
        sqlite_region,
        [
            '"SQLite second multipart create failed"',
            '"SQLite multipart upload listing first page failed"',
            '"SQLite multipart upload listing continuation failed"',
            '"SQLite multipart upload listing metadata failed"',
        ],
        "ListMultipartUploads SQLite corpus",
    )
    server_region = between(
        server_app,
        "when List_Multipart_Uploads =>",
        "when Create_Multipart =>",
        "ListMultipartUploads server handler",
    )
    ordered_once(
        server_region,
        [
            'Apps.Request_Header_Count (X, "x-amz-request-payer")',
            "Apps.Request_Header_Count\n"
            '                       (X, "x-amz-expected-bucket-owner")',
            "Check_Expected_Bucket_Owner",
            '"Requester Pays is not implemented"',
            "Parse_List_Multipart_Uploads_Query",
            "Store.List_Multipart_Uploads",
            "Serialize_List_Multipart_Uploads",
            "when Multipart_Uploads.Malformed_List_Request",
        ],
        "ListMultipartUploads server handler",
    )
    ordered_once(
        server_corpus,
        [
            '"ListMultipartUploads server first page mismatch: "',
            '"ListMultipartUploads server continuation mismatch: "',
            '"ListMultipartUploads URL encoding mismatch: "',
            '"ListMultipartUploads delimiter grouping mismatch"',
            '"ListMultipartUploads zero page was accepted"',
            '"ListMultipartUploads missing bucket was misreported"',
            '"ListMultipartUploads silently accepted Requester Pays"',
            '"ListMultipartUploads accepted duplicate payer"',
        ],
        "ListMultipartUploads server corpus",
    )
    for marker in (
        '"S3 implementation rejected composable " &',
        '"ListMultipartUploads";',
        '"durable multipart upload listing mismatch"',
    ):
        if marker not in implementation_corpus:
            fail(f"ListMultipartUploads provider corpus missing: {marker}")


def verify_negative_registry() -> None:
    original = tomllib.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
    index = next(
        position for position, entry in enumerate(original["operation"])
        if entry["name"] == "ListMultipartUploads"
    )
    for label, key, value in (
        ("legacy absence", "absence", "legacy_preserved"),
        ("legacy errors", "errors", ["legacy_preserved"]),
        ("wrong public name", "public_name", "List_Uploads"),
        ("wrong certainty", "certainty", "possibly_applied"),
        ("unresolved decisions", "human_decisions_resolved", False),
        ("missing qualification", "qualification", ""),
    ):
        candidate = copy.deepcopy(original)
        candidate["operation"][index][key] = value
        try:
            verify_registry(candidate)
        except ValueError:
            pass
        else:
            fail(f"ListMultipartUploads {label} was accepted")


def verify_negative_corpus() -> None:
    members_raw = MEMBERS_PATH.read_bytes()
    vectors_raw = VECTORS_PATH.read_bytes()
    for label, candidate_members, candidate_vectors in (
        ("member semantics", members_raw + b"\n", vectors_raw),
        ("vector semantics", members_raw, vectors_raw + b"\n"),
    ):
        try:
            verify_corpus_hashes(candidate_members, candidate_vectors)
        except ValueError:
            pass
        else:
            fail(f"ListMultipartUploads changed {label} was accepted")


def main() -> int:
    verify_authoritative_model()
    verify_registry()
    verify_sources()
    verify_negative_registry()
    verify_corpus_hashes()
    verify_negative_corpus()
    lock = LOCK_PATH.read_text(encoding="utf-8")
    if f'revision = "{EXPECTED_REVISION}"' not in lock:
        fail("pinned botocore revision changed")
    if f'service_model_sha256 = "{EXPECTED_SHA256}"' not in lock:
        fail("pinned botocore service hash changed")

    model = MODEL_PATH.read_text(encoding="utf-8")
    members = read_tsv(MEMBERS_PATH, MEMBER_HEADER)
    vectors = read_tsv(VECTORS_PATH, VECTOR_HEADER)

    vector_by_id: dict[str, dict[str, str]] = {}
    for row in vectors:
        vector_id = row["id"]
        if vector_id in vector_by_id:
            fail(f"duplicate vector id: {vector_id}")
        if not re.fullmatch(r"LM-(?:RQ|RS|LC|OR)-\d{3}", vector_id):
            fail(f"noncanonical vector id: {vector_id}")
        if row["direction"] not in ALLOWED_VECTOR_DIRECTIONS:
            fail(f"invalid vector direction: {vector_id}")
        vector_by_id[vector_id] = row

    member_keys: set[str] = set()
    grouped: dict[tuple[str, str], list[dict[str, str]]] = {}
    for row in members:
        key = (row["direction"], row["shape"])
        grouped.setdefault(key, []).append(row)
        member_key = f'{row["direction"]}:{row["member"]}'
        if member_key in member_keys:
            fail(f"duplicate manifest member: {member_key}")
        member_keys.add(member_key)
        if row["current_boundary"] not in ALLOWED_BOUNDARIES:
            fail(f"invalid current boundary for {member_key}")

    if set(grouped) != set(EXPECTED):
        fail(f"unexpected direction/shape groups: {sorted(grouped)}")

    for key, expected_names in EXPECTED.items():
        rows = grouped[key]
        ordinals = [int(row["ordinal"]) for row in rows]
        names = [row["member"] for row in rows]
        if ordinals != list(range(1, len(expected_names) + 1)):
            fail(f"{key}: manifest ordinals are not contiguous")
        if names != expected_names:
            fail(f"{key}: manifest names do not match the pinned inventory")
        if generated_members(model, key[1]) != expected_names:
            fail(f"{key}: generated Ada model differs from expected inventory")
        if generated_count(model, key[1]) != len(expected_names):
            fail(f"{key}: generated Ada member count differs")
        expected_locations = generated_locations(model, key[1])
        manifest_locations = []
        for row in rows:
            try:
                manifest_locations.append(
                    MANIFEST_TO_MODEL_LOCATION[row["wire_location"]]
                )
            except KeyError as exc:
                raise ValueError(
                    f'{key}: unknown wire location {row["wire_location"]!r}'
                ) from exc
        if manifest_locations != expected_locations:
            fail(f"{key}: manifest locations differ from generated Ada model")

    referenced_vectors: set[str] = set()
    for row in members:
        member_key = f'{row["direction"]}:{row["member"]}'
        for vector_id in split_csv(row["vector_ids"]):
            vector = vector_by_id.get(vector_id)
            if vector is None:
                fail(f"{member_key}: unknown vector {vector_id}")
            refs = set(split_csv(vector["member_refs"]))
            if member_key not in refs:
                fail(
                    f"{member_key}: vector {vector_id} lacks reciprocal "
                    "reference"
                )
            referenced_vectors.add(vector_id)

    for vector_id, vector in vector_by_id.items():
        refs = split_csv(vector["member_refs"])
        for ref in refs:
            if ref.startswith("operation:"):
                if ref != "operation:ListMultipartUploads":
                    fail(f"{vector_id}: unexpected operation reference {ref}")
            elif ref not in member_keys:
                fail(f"{vector_id}: unknown member reference {ref}")
        if vector_id not in referenced_vectors and not any(
            ref == "operation:ListMultipartUploads" for ref in refs
        ):
            fail(f"{vector_id}: vector is not reachable from the manifest")

    request_count = len(grouped[("request", "391")])
    response_count = len(grouped[("response", "390")])
    print(
        "ListMultipartUploads preparation: "
        f"{request_count} request members, {response_count} response members, "
        f"{len(vectors)} contract vectors; pinned model and references match"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, UnicodeError, ValueError) as exc:
        print(
            f"ListMultipartUploads preparation verification failed: {exc}",
            file=sys.stderr,
        )
        raise SystemExit(1)
