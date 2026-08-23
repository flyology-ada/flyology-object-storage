#!/usr/bin/env python3
"""Verify the isolated ListObjectVersions model inventory and corpus graph."""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "tests" / "corpora" / "list-object-versions"
MODEL = ROOT / "src" / "flyology-object_storage-s3-model.adb"
LOCK = ROOT / "coverage" / "corpora.lock.toml"
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


def main() -> int:
    lock = LOCK.read_text(encoding="utf-8")
    if f'revision = "{EXPECTED_REVISION}"' not in lock:
        fail("pinned botocore revision changed")
    if f'service_model_sha256 = "{EXPECTED_SHA256}"' not in lock:
        fail("pinned botocore service hash changed")

    model = MODEL.read_text(encoding="utf-8")
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
