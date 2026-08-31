#!/usr/bin/env python3
"""Verify the isolated ListParts model disposition and design corpus."""

from __future__ import annotations

import copy
import csv
import re
import sys
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "tests" / "corpora" / "list-parts"
MEMBERS_PATH = CORPUS / "members.tsv"
VECTORS_PATH = CORPUS / "vectors.tsv"
MODEL_PATH = ROOT / "src" / "flyology-object_storage-s3-model.adb"
LOCK_PATH = ROOT / "coverage" / "corpora.lock.toml"
REGISTRY_PATH = ROOT / "coverage" / "s3-operations.toml"
LOW_SPEC = ROOT / "src" / "flyology-object_storage-client-low_level.ads"
LOW_BODY = ROOT / "src" / "flyology-object_storage-client-low_level.adb"
TRANSFERS_SPEC = ROOT / "src" / "flyology-object_storage-client-transfers.ads"
TRANSFERS_BODY = ROOT / "src" / "flyology-object_storage-client-transfers.adb"
SOCKET = ROOT / "tests" / "src" / "s3_http_socket_corpus.adb"
QUALIFICATION = ROOT / "docs" / "qualification" / "list-parts-preparation.md"

EXPECTED_REVISION = "36c34f15391da01cd717c73c0fffa747c9889768"
EXPECTED_SHA256 = "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
EXPECTED = {
    ("request", "401"): [
        "Bucket", "Key", "MaxParts", "PartNumberMarker", "UploadId",
        "RequestPayer", "ExpectedBucketOwner", "SSECustomerAlgorithm",
        "SSECustomerKey", "SSECustomerKeyMD5",
    ],
    ("response", "400"): [
        "AbortDate", "AbortRuleId", "Bucket", "Key", "UploadId",
        "PartNumberMarker", "NextPartNumberMarker", "MaxParts",
        "IsTruncated", "Parts", "Initiator", "Owner", "StorageClass",
        "RequestCharged", "ChecksumAlgorithm", "ChecksumType",
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
ALLOWED_BOUNDARIES = {"projected", "partial", "client_only"}
ALLOWED_VECTOR_DIRECTIONS = {"request", "response", "both"}
MANIFEST_TO_MODEL_LOCATION = {
    "uri-label": "URI_Location",
    "query": "Query_Location",
    "header": "Header_Location",
    "body": "Body_Location",
}
LIST_PARTS_SYMBOLS = [
    "Prepare_List_Parts",
    "Decode_List_Parts_Complete_Response",
    "Execute_List_Parts",
    "List_Parts_Operation",
    "List_Parts_Page",
    "Finish",
]
LIST_PARTS_EXCLUSIONS = [
    (
        "directory-bucket endpoint and session semantics are outside the "
        "qualified general-purpose path claim"
    ),
    (
        "server-side configured Requester Pays accounting is not claimed; "
        "exact client RequestPayer and RequestCharged handling remains covered"
    ),
    (
        "server-side SSE-C multipart state is unavailable; exact client SSE-C "
        "header construction and response validation plus authenticated "
        "NotImplemented coverage remain covered"
    ),
    (
        "SeaweedFS 4.43 is excluded from the positive external lane because "
        "it repeats a part at or below the supplied PartNumberMarker on the "
        "second page"
    ),
]
LIST_PARTS_LANE = [
    [
        "uv", "run", "--python", "3.13", "--",
        "tools/verify-list-parts-preparation.py",
    ],
    ["@tests", "alr", "-n", "build"],
    ["@tests", "./bin/s3_http_socket_corpus"],
    ["./tools/verify-coverage.sh"],
    ["./tools/build-api-docs.sh", "/private/tmp/fos-list-parts-gnatdoc"],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]


def fail(message: str) -> None:
    raise ValueError(message)


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


def generated_block(model: str, function: str, shape: str) -> str:
    marker = f"   function {function}\n"
    try:
        function_body = model.split(marker, 1)[1].split(
            f"end {function};", 1
        )[0]
    except IndexError as exc:
        raise ValueError(f"generated model has no {function} body") from exc
    match = re.search(
        rf"when {re.escape(shape)} =>\s+case Member is(?P<body>.*?)\s+end case;",
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


def registry_entry(data: dict[str, object]) -> dict[str, object]:
    matches = [
        entry for entry in data["operation"]
        if entry["name"] == "ListParts"
    ]
    if len(matches) != 1:
        fail("ListParts registry entry is not unique")
    return matches[0]


def verify_registry(data: dict[str, object]) -> None:
    entry = registry_entry(data)
    expected = {
        "codec": "strict_paginated_rest_xml_and_singleton_headers",
        "public_name": "List_Parts_Page",
        "absence": (
            "no dedicated absence variant; a well-formed bounded 404 "
            "NoSuchUpload or NoSuchBucket response is a structured typed "
            "rejection"
        ),
        "errors": [
            "authentication", "authorization", "not_found",
            "invalid_request", "unavailable_or_retryable",
            "corrupt_or_invalid_response",
        ],
        "certainty": "read_only",
        "reconciliation": "not_applicable",
        "human_decisions_resolved": True,
        "decision_status": "reviewed",
        "qualification": "list_parts",
        "ada_symbols": LIST_PARTS_SYMBOLS,
    }
    for key, value in expected.items():
        if entry.get(key) != value:
            fail(f"ListParts registry field changed: {key}")
    if entry.get("exclusions") != LIST_PARTS_EXCLUSIONS:
        fail("ListParts exclusions changed")
    if data["qualification"].get("list_parts") != LIST_PARTS_LANE:
        fail("ListParts qualification lane changed")


def verify_registry_negatives(data: dict[str, object]) -> None:
    mutations = (
        ("missing public name", "public_name", None),
        ("legacy absence", "absence", "legacy_preserved"),
        ("legacy errors", "errors", ["legacy_preserved"]),
        ("wrong certainty", "certainty", "possibly_applied"),
        ("unresolved decision", "human_decisions_resolved", False),
        ("cross-operation symbol", "ada_symbols", ["List_Objects"]),
        ("missing qualification", "qualification", ""),
    )
    for label, key, value in mutations:
        candidate = copy.deepcopy(data)
        entry = registry_entry(candidate)
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        if candidate == data:
            fail(f"{label}: candidate did not change")
        try:
            verify_registry(candidate)
        except (IndexError, KeyError, TypeError, ValueError):
            continue
        fail(f"{label}: candidate was accepted")


def require_in_order(text: str, fragments: list[str], label: str) -> None:
    cursor = 0
    for fragment in fragments:
        position = text.find(fragment, cursor)
        if position < 0:
            fail(f"{label}: missing {fragment}")
        cursor = position + len(fragment)


def verify_sources() -> None:
    require_in_order(
        LOW_SPEC.read_text(encoding="utf-8"),
        [
            "type List_Parts_Parameters is record",
            "function Prepare_List_Parts",
            "function Decode_List_Parts_Complete_Response",
            "function Execute_List_Parts",
            "procedure List_Parts",
        ],
        "ListParts low-level API",
    )
    require_in_order(
        LOW_BODY.read_text(encoding="utf-8"),
        [
            "function Prepare_List_Parts",
            "function Decode_List_Parts_Complete_Response",
            '"ListParts response does not match prepared request"',
            "function Execute_List_Parts",
        ],
        "ListParts prepared response binding",
    )
    require_in_order(
        TRANSFERS_SPEC.read_text(encoding="utf-8"),
        [
            "type List_Parts_Result_Kind is",
            "type List_Parts_Operation",
            "procedure List_Parts_Page",
            "function List_Parts_Page",
            "procedure Finish",
        ],
        "ListParts composable API",
    )
    require_in_order(
        TRANSFERS_BODY.read_text(encoding="utf-8"),
        [
            "function Normalize_List_Parts_Response",
            "function Normalize_List_Parts_Failure",
            "procedure Complete_List_Parts_Child",
            '"ListParts restart changed a retained owner"',
        ],
        "ListParts normalization and restart",
    )
    require_in_order(
        SOCKET.read_text(encoding="utf-8"),
        [
            '"pre-admission ListParts cancellation mismatch"',
            '"composed ListParts first page mismatch"',
            '"composed ListParts continuation mismatch"',
            '"wrong ListParts upload ID accepted"',
            '"wrong ListParts marker accepted"',
        ],
        "ListParts socket evidence",
    )
    qualification = " ".join(
        QUALIFICATION.read_text(encoding="utf-8").split()
    )
    require_in_order(
        qualification,
        [
            "`ListParts` registry lane",
            "exact-upload response binding",
            "region-scoped warning measurement only",
        ],
        "ListParts qualification",
    )


def main() -> int:
    registry = tomllib.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
    verify_registry(registry)
    verify_registry_negatives(registry)
    verify_sources()
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
        if not re.fullmatch(r"LP-(?:RQ|RS|LC|OR)-\d{3}", vector_id):
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
                fail(f"{member_key}: vector {vector_id} lacks reciprocal reference")
            referenced_vectors.add(vector_id)

    for vector_id, vector in vector_by_id.items():
        refs = split_csv(vector["member_refs"])
        for ref in refs:
            if ref.startswith("operation:"):
                if ref != "operation:ListParts":
                    fail(f"{vector_id}: unexpected operation reference {ref}")
            elif ref not in member_keys:
                fail(f"{vector_id}: unknown member reference {ref}")
        if vector_id not in referenced_vectors and not any(
            ref == "operation:ListParts" for ref in refs
        ):
            fail(f"{vector_id}: vector is not reachable from the manifest")

    request_count = len(grouped[("request", "401")])
    response_count = len(grouped[("response", "400")])
    print(
        "ListParts preparation: "
        f"{request_count} request members, {response_count} response members, "
        f"{len(vectors)} contract vectors; pinned model, registry, source, "
        "and references match"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"ListParts preparation verification failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
