#!/usr/bin/env python3
"""Verify the isolated ListObjectVersions model inventory and corpus graph."""

from __future__ import annotations

import csv
import re
import sys
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "tests" / "corpora" / "list-object-versions"
MODEL = ROOT / "src" / "flyology-object_storage-s3-model.adb"
LOCK = ROOT / "coverage" / "corpora.lock.toml"
REGISTRY = ROOT / "coverage" / "s3-operations.toml"
LOW_SPEC = ROOT / "src" / "flyology-object_storage-client-low_level.ads"
LOW_BODY = ROOT / "src" / "flyology-object_storage-client-low_level.adb"
OBJECTS_SPEC = ROOT / "src" / "flyology-object_storage-client-objects.ads"
OBJECTS_BODY = ROOT / "src" / "flyology-object_storage-client-objects.adb"
SOCKET = ROOT / "tests" / "src" / "s3_http_socket_corpus.adb"
EXPECTED_REVISION = "36c34f15391da01cd717c73c0fffa747c9889768"
EXPECTED_SHA256 = "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
EXPECTED = {
    ("request", "395"): [
        "Bucket", "Delimiter", "EncodingType", "KeyMarker", "MaxKeys",
        "Prefix", "VersionIdMarker", "ExpectedBucketOwner", "RequestPayer",
        "OptionalObjectAttributes",
    ],
    ("response", "394"): [
        "IsTruncated", "KeyMarker", "VersionIdMarker", "NextKeyMarker",
        "NextVersionIdMarker", "Versions", "DeleteMarkers", "Name",
        "Prefix", "Delimiter", "MaxKeys", "CommonPrefixes", "EncodingType",
        "RequestCharged",
    ],
    ("version", "491"): [
        "ETag", "ChecksumAlgorithm", "ChecksumType", "Size", "StorageClass",
        "Key", "VersionId", "IsLatest", "LastModified", "Owner",
        "RestoreStatus",
    ],
    ("delete-marker", "161"): [
        "Owner", "Key", "VersionId", "IsLatest", "LastModified",
    ],
    ("owner", "499"): ["DisplayName", "ID"],
    ("restore", "617"): ["IsRestoreInProgress", "RestoreExpiryDate"],
    ("common-prefix", "97"): ["Prefix"],
}
MEMBER_HEADER = [
    "direction", "shape", "ordinal", "member", "wire_location",
    "current_boundary", "required_contract", "vector_ids",
]
VECTOR_HEADER = [
    "id", "direction", "layer", "category", "member_refs", "stimulus",
    "expected_contract",
]
LOCATION = {
    "uri-label": "URI_Location",
    "query": "Query_Location",
    "header": "Header_Location",
    "body": "Body_Location",
}
EXPECTED_ERRORS = [
    "authentication",
    "authorization",
    "not_found",
    "invalid_request",
    "unavailable_or_retryable",
    "corrupt_or_invalid_response",
]
EXPECTED_EXCLUSIONS = [
    "directory-bucket endpoint and session semantics are outside the "
    "qualified general-purpose bucket claim",
    "access-point, Object Lambda, and S3 on Outposts ARN and hostname "
    "routing are not claimed",
    "server-side configured Requester Pays accounting is not claimed; exact "
    "client RequestPayer and RequestCharged handling remains covered",
    "the local server accepts RestoreStatus request syntax but supports no "
    "archival restore state and emits no RestoreStatus result",
    "no automatic pagination, automatic retry, or cross-page "
    "snapshot-consistency claim",
    "external-server interoperability is not claimed",
]
EXPECTED_SYMBOLS = [
    "Prepare_List_Object_Versions",
    "Decode_List_Object_Versions_Complete_Response",
    "Execute_List_Object_Versions",
    "List_Object_Versions_Operation",
    "List_Versions_Page",
    "Finish",
]
EXPECTED_LANE = [
    ["uv", "run", "--python", "3.13", "--",
     "tools/verify-list-object-versions-preparation.py"],
    ["@tests", "alr", "-n", "build"],
    ["@tests", "./bin/s3_list_object_versions_corpus"],
    ["@tests", "./bin/s3_http_socket_corpus"],
    ["./tools/verify-coverage.sh"],
    ["./tools/build-api-docs.sh",
     "/private/tmp/fos-list-object-versions-gnatdoc"],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]
EXPECTED_EVIDENCE = {
    "backend": [
        "tests/src/object_storage_test_cases.adb",
        "sqlite/tests/src/flyology_object_storage_sqlite_tests.adb",
    ],
    "client": [
        "src/flyology-object_storage-s3-versions.ads",
        "src/flyology-object_storage-s3-versions.adb",
        "src/flyology-object_storage-client-low_level.ads",
        "src/flyology-object_storage-client-low_level.adb",
        "src/flyology-object_storage-client-objects.ads",
        "src/flyology-object_storage-client-objects.adb",
        "tests/src/s3_list_object_versions_corpus.adb",
        "tests/src/s3_http_socket_corpus.adb",
    ],
    "server": [
        "src/flyology-object_storage-s3-versions.ads",
        "src/flyology-object_storage-s3-versions.adb",
        "src/flyology-object_storage-server-s3_applications.adb",
        "tests/src/s3_server_application_corpus.adb",
        "tests/src/s3_http_socket_corpus.adb",
    ],
    "corpus": [
        "tests/corpora/list-object-versions/members.tsv",
        "tests/corpora/list-object-versions/vectors.tsv",
        "tools/verify-list-object-versions-preparation.py",
        "docs/qualification/list-object-versions.md",
        "tests/src/s3_list_object_versions_corpus.adb",
        "tests/src/s3_http_socket_corpus.adb",
        "tests/src/s3_implementation_corpus.adb",
        "tests/src/s3_server_application_corpus.adb",
    ],
}


def fail(message: str) -> None:
    raise ValueError(message)


def read_tsv(path: Path, header: list[str]) -> list[dict[str, str]]:
    if b"\r" in path.read_bytes():
        fail(f"{path}: CR characters are not canonical")
    with path.open("r", encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        if reader.fieldnames != header:
            fail(f"{path}: header mismatch: {reader.fieldnames!r}")
        rows = list(reader)
    if not rows:
        fail(f"{path}: no rows")
    for number, row in enumerate(rows, 2):
        if None in row or any(value == "" for value in row.values()):
            fail(f"{path}:{number}: empty or surplus field")
    return rows


def function_body(model: str, function: str) -> str:
    match = re.search(rf"   function {re.escape(function)}(?=\s*\()", model)
    if match is None:
        fail(f"generated model has no {function} body")
    tail = model[match.end():]
    try:
        return tail.split(f"end {function};", 1)[0]
    except IndexError as exc:
        raise ValueError(f"generated model has no end for {function}") from exc


def member_block(model: str, function: str, shape: str) -> str:
    match = re.search(
        rf"when {re.escape(shape)} =>\s+case Member is(?P<body>.*?)\s+end case;",
        function_body(model, function),
        re.DOTALL,
    )
    if match is None:
        fail(f"generated model has no {function} block for shape {shape}")
    return match.group("body")


def generated_values(model: str, function: str, shape: str) -> list[str]:
    pattern = (
        r'when\s+(\d+)\s+=>\s+return\s+"([^"]+)";'
        if function == "Member_Name"
        else r"when\s+(\d+)\s+=>\s+return\s+([A-Za-z_]+);"
    )
    pairs = re.findall(pattern, member_block(model, function, shape))
    if [int(number) for number, _ in pairs] != list(range(1, len(pairs) + 1)):
        fail(f"shape {shape} {function} order is not contiguous")
    return [value for _, value in pairs]


def generated_count(model: str, shape: str) -> int:
    match = re.search(
        rf"when\s+{re.escape(shape)}\s+=>\s+return\s+(\d+);",
        function_body(model, "Member_Count"),
    )
    if match is None:
        fail(f"generated model has no count for shape {shape}")
    return int(match.group(1))


def comma_values(value: str) -> list[str]:
    result = value.split(",")
    if any(item == "" or item != item.strip() for item in result):
        fail(f"noncanonical comma list: {value!r}")
    if len(result) != len(set(result)):
        fail(f"duplicate comma-list value: {value!r}")
    return result


def source(path: Path) -> str:
    if not path.is_file() or path.is_symlink():
        fail(f"missing or unsafe evidence path: {path}")
    raw = path.read_bytes()
    if b"\r" in raw:
        fail(f"{path}: CR characters are not canonical")
    return raw.decode("utf-8")


def require_once(text: str, fragment: str, label: str) -> int:
    count = text.count(fragment)
    if count != 1:
        fail(f"{label}: expected once, found {count}: {fragment!r}")
    return text.index(fragment)


def require_ordered(text: str, fragments: list[str], label: str) -> None:
    positions = [require_once(text, item, label) for item in fragments]
    if positions != sorted(positions):
        fail(f"{label}: reviewed evidence order changed")


def require_in_order(text: str, fragments: list[str], label: str) -> None:
    position = 0
    for fragment in fragments:
        position = text.find(fragment, position)
        if position < 0:
            fail(f"{label}: missing or reordered {fragment!r}")
        position += len(fragment)


def evidence_region(text: str, start: str, end: str, label: str) -> str:
    first = require_once(text, start, label)
    last = text.find(end, first + len(start))
    if last < 0:
        fail(f"{label}: end marker is missing")
    return text[first:last + len(end)]


def verify_registry() -> None:
    registry = tomllib.loads(source(REGISTRY))
    entries = [
        item for item in registry["operation"]
        if item["name"] == "ListObjectVersions"
    ]
    if len(entries) != 1:
        fail("registry must contain exactly one ListObjectVersions entry")
    entry = entries[0]
    expected = {
        "codec": "strict_paginated_rest_xml_and_singleton_headers",
        "public_name": "List_Versions_Page",
        "absence": (
            "no dedicated absence variant; a well-formed bounded 404 "
            "NoSuchBucket response is a structured typed rejection"
        ),
        "errors": EXPECTED_ERRORS,
        "certainty": "read_only",
        "reconciliation": "not_applicable",
        "exclusions": EXPECTED_EXCLUSIONS,
        "human_decisions_resolved": True,
        "decision_status": "reviewed",
        "qualification": "list_object_versions",
        "ada_symbols": EXPECTED_SYMBOLS,
        "evidence": EXPECTED_EVIDENCE,
    }
    for key, value in expected.items():
        if entry.get(key) != value:
            fail(f"registry {key} differs from the reviewed decision")
    if entry.get("coverage") != {
        "backend": "covered",
        "client": "covered",
        "server": "covered",
        "corpus": "covered",
    }:
        fail("registry four-cell coverage changed")
    if registry["qualification"].get("list_object_versions") != EXPECTED_LANE:
        fail("ListObjectVersions qualification lane changed")
    for values in EXPECTED_EVIDENCE.values():
        for relative in values:
            source(ROOT / relative)


def verify_client_and_socket() -> None:
    low_spec = source(LOW_SPEC)
    low_body = source(LOW_BODY)
    objects_spec = source(OBJECTS_SPEC)
    objects_body = source(OBJECTS_BODY)
    socket = source(SOCKET)
    for symbol in EXPECTED_SYMBOLS[:3]:
        if symbol not in low_spec or symbol not in low_body:
            fail(f"low-level declaration/body missing {symbol}")
    contract = evidence_region(
        objects_spec,
        "type List_Object_Versions_Result_Kind is",
        "type Get_Object_Attributes_Result_Kind is",
        "public composable contract",
    )
    require_ordered(
        contract,
        [
            "type List_Object_Versions_Result_Kind is",
            "type List_Object_Versions_Operation",
            "procedure List_Versions_Page",
            "function List_Versions_Page",
            "procedure Finish",
        ],
        "public composable contract",
    )
    implementation = evidence_region(
        objects_body,
        "function Normalize_List_Object_Versions_Response",
        "end List_Versions_Page;",
        "typed normalization and retained ownership",
    )
    require_ordered(
        implementation,
        [
            "function Normalize_List_Object_Versions_Response",
            'Code in "InvalidArgument" | "InvalidRequest"',
            'Value.Status = 401 and then Code = "InvalidAccessKeyId"',
            'Value.Status = 403 and then Code = "AccessDenied"',
            'Value.Status = 404 and then Code = "NoSuchBucket"',
            'Value.Status = 503 and then Code = "SlowDown"',
            "else Corrupt_Or_Invalid_Response",
            "procedure Start_List_Object_Versions",
            "Operation.HTTP /= Client or else Operation.Cancellation /= Token",
            '"ListObjectVersions restart changed a retained owner"',
        ],
        "typed normalization and retained ownership",
    )
    for fragment in [
        "List_Object_Versions_Cancellation",
        "List_Versions_Admission_Native.Wait_Source",
        "List_Versions_Admission_Lightweight.Wait_Source",
        "List_Versions_Drain_Native.Wait_Source",
        "List_Versions_Drain_Lightweight.Wait_Source",
        "Require_Normalized_List_Versions_Failure",
        '"admitted ListObjectVersions cancellation mismatch"',
        '"ListObjectVersions drain was not acknowledged"',
        '"ListObjectVersions accepted changed retained HTTP "',
        '"ListObjectVersions accepted changed retained "',
        '"same-object ListObjectVersions restart mismatch"',
    ]:
        if fragment not in socket:
            fail(f"socket evidence missing {fragment!r}")
    lifecycle = evidence_region(
        socket,
        "procedure Require_Normalized_List_Versions_Failure",
        '"same-object ListObjectVersions restart mismatch";',
        "ListObjectVersions normalization and lifecycle",
    )
    require_in_order(
        lifecycle,
        [
            "(Authentication_Failed, 401, \"InvalidAccessKeyId\"",
            "(Authorization_Failed, 403, \"AccessDenied\"",
            "(Not_Found, 404, \"NoSuchBucket\"",
            "(Invalid_Request, 400, \"InvalidArgument\"",
            "(Unavailable_Or_Retryable, 503, \"SlowDown\"",
            "(Corrupt_Or_Invalid_Response, 400,",
            "Operations.Wait_Some (Cancel_Set, Completed_Batch);",
            "Operations.Cancel (Operation);",
            "Operations.Wait_All (Cancel_Set);",
            "Finish (Operation, Result);",
            "List_Versions_Page\n                    (Changed_HTTP'Access,",
            "Token => Changed_Token'Access,",
            "Token => Cancel_Token'Access,\n"
            "                  Operation => Operation);",
        ],
        "ListObjectVersions normalization and lifecycle",
    )
    if lifecycle.count("Operations.Wait_All (Cancel_Set);") != 2:
        fail("ListObjectVersions cancel/restart wait inventory changed")
    if lifecycle.count("Finish (Operation, Result);") != 2:
        fail("ListObjectVersions typed Finish inventory changed")
    for failure in EXPECTED_ERRORS:
        mapping = {
            "authentication": "Authentication_Failed",
            "authorization": "Authorization_Failed",
            "not_found": "Not_Found",
            "invalid_request": "Invalid_Request",
            "unavailable_or_retryable": "Unavailable_Or_Retryable",
            "corrupt_or_invalid_response": "Corrupt_Or_Invalid_Response",
        }[failure]
        if socket.count(f"({mapping},") < 1:
            fail(f"socket evidence missing {failure} normalization")
    if socket.count("List_Object_Versions_Cancellation") != 5:
        fail("ListObjectVersions cancellation server wiring changed")
    if socket.count(
        '"ListObjectVersions restart changed a retained owner"'
    ) != 2:
        fail("ListObjectVersions owner-substitution assertions changed")


def main() -> int:
    verify_registry()
    verify_client_and_socket()
    lock = LOCK.read_text(encoding="utf-8")
    if f'revision = "{EXPECTED_REVISION}"' not in lock:
        fail("pinned botocore revision changed")
    if f'service_model_sha256 = "{EXPECTED_SHA256}"' not in lock:
        fail("pinned botocore service hash changed")

    model = MODEL.read_text(encoding="utf-8")
    for binding in [
        (
            "when List_Object_Versions_Operation =>\n"
            '            return "ListObjectVersions";'
        ),
        (
            "when List_Object_Versions_Operation =>\n"
            "            return Get_Method;"
        ),
        (
            "when List_Object_Versions_Operation =>\n"
            '            return "/{Bucket}?versions";'
        ),
        (
            "when List_Object_Versions_Operation =>\n"
            "            return 200;"
        ),
        (
            "when List_Object_Versions_Operation =>\n"
            "            return 395;"
        ),
        (
            "when List_Object_Versions_Operation =>\n"
            "            return 394;"
        ),
    ]:
        require_once(model, binding, "pinned operation binding")
    members = read_tsv(CORPUS / "members.tsv", MEMBER_HEADER)
    vectors = read_tsv(CORPUS / "vectors.tsv", VECTOR_HEADER)

    vector_by_id: dict[str, dict[str, str]] = {}
    for vector in vectors:
        vector_id = vector["id"]
        if not re.fullmatch(r"LOV-(?:RQ|RS|TR)-\d{3}", vector_id):
            fail(f"noncanonical vector id: {vector_id}")
        if vector_id in vector_by_id:
            fail(f"duplicate vector id: {vector_id}")
        if vector["direction"] not in {"request", "response", "both"}:
            fail(f"invalid vector direction: {vector_id}")
        vector_by_id[vector_id] = vector

    grouped: dict[tuple[str, str], list[dict[str, str]]] = {}
    member_keys: set[str] = set()
    referenced_vectors: set[str] = set()
    for member in members:
        group = (member["direction"], member["shape"])
        grouped.setdefault(group, []).append(member)
        member_key = f'{member["direction"]}:{member["member"]}'
        if member_key in member_keys:
            fail(f"duplicate member key: {member_key}")
        member_keys.add(member_key)
        if member["current_boundary"] not in {"projected", "decoded"}:
            fail(f"invalid boundary for {member_key}")
        for vector_id in comma_values(member["vector_ids"]):
            vector = vector_by_id.get(vector_id)
            if vector is None:
                fail(f"{member_key}: unknown vector {vector_id}")
            if member_key not in comma_values(vector["member_refs"]):
                fail(f"{member_key}: {vector_id} lacks reciprocal reference")
            referenced_vectors.add(vector_id)

    if set(grouped) != set(EXPECTED):
        fail(f"unexpected direction/shape groups: {sorted(grouped)}")
    for group, expected_names in EXPECTED.items():
        rows = grouped[group]
        if [int(row["ordinal"]) for row in rows] != list(
            range(1, len(expected_names) + 1)
        ):
            fail(f"{group}: manifest ordinals are not contiguous")
        if [row["member"] for row in rows] != expected_names:
            fail(f"{group}: names differ from pinned inventory")
        shape = group[1]
        if generated_count(model, shape) != len(expected_names):
            fail(f"{group}: generated count differs")
        if generated_values(model, "Member_Name", shape) != expected_names:
            fail(f"{group}: generated names differ")
        try:
            locations = [LOCATION[row["wire_location"]] for row in rows]
        except KeyError as exc:
            raise ValueError(f"{group}: unknown manifest wire location") from exc
        if generated_values(model, "Location", shape) != locations:
            fail(f"{group}: generated wire locations differ")

    for vector_id, vector in vector_by_id.items():
        refs = comma_values(vector["member_refs"])
        for reference in refs:
            if reference.startswith("operation:"):
                if reference != "operation:ListObjectVersions":
                    fail(f"{vector_id}: unexpected operation reference")
            elif reference not in member_keys:
                fail(f"{vector_id}: unknown member reference {reference}")
        if vector_id not in referenced_vectors and \
                "operation:ListObjectVersions" not in refs:
            fail(f"{vector_id}: unreachable vector")

    print(
        "ListObjectVersions preparation: "
        f"{len(members)} modeled members across {len(grouped)} shapes, "
        f"{len(vectors)} reciprocal contract vectors; pinned model matches"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, UnicodeError, ValueError) as exc:
        print(
            f"ListObjectVersions preparation verification failed: {exc}",
            file=sys.stderr,
        )
        raise SystemExit(1)
