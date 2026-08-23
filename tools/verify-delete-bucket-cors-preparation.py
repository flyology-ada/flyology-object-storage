#!/usr/bin/env python3
"""Verify the isolated DeleteBucketCors model inventory and corpus graph."""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "tests" / "corpora" / "delete-bucket-cors"
MODEL = ROOT / "src" / "flyology-object_storage-s3-model.adb"
LOCK = ROOT / "coverage" / "corpora.lock.toml"
EXPECTED_REVISION = "36c34f15391da01cd717c73c0fffa747c9889768"
EXPECTED_SHA256 = "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
EXPECTED_MEMBERS = ["Bucket", "ExpectedBucketOwner"]
MEMBER_HEADER = [
    "direction", "shape", "ordinal", "member", "wire_location",
    "current_boundary", "required_contract", "vector_ids",
]
VECTOR_HEADER = [
    "id", "direction", "layer", "category", "member_refs", "stimulus",
    "expected_contract",
]


def fail(message: str) -> None:
    raise ValueError(message)


def read_tsv(path: Path, header: list[str]) -> list[dict[str, str]]:
    if b"\r" in path.read_bytes():
        fail(f"{path}: CR characters are not canonical")
    with path.open("r", encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        if reader.fieldnames != header:
            fail(f"{path}: header mismatch")
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
    marker = f"end {function};"
    if marker not in tail:
        fail(f"generated model has no end for {function}")
    return tail.split(marker, 1)[0]


def operation_shape(model: str, function: str) -> int:
    match = re.search(
        r"when Delete_Bucket_Cors_Operation =>\s+return\s+(\d+);",
        function_body(model, function),
    )
    if match is None:
        fail(f"generated model has no DeleteBucketCors {function}")
    return int(match.group(1))


def member_block(model: str, function: str, shape: int) -> str:
    match = re.search(
        rf"when {shape} =>\s+case Member is(?P<body>.*?)\s+end case;",
        function_body(model, function),
        re.DOTALL,
    )
    if match is None:
        fail(f"generated model has no {function} block for shape {shape}")
    return match.group("body")


def member_values(model: str, function: str, shape: int) -> list[str]:
    pattern = (
        r'when\s+(\d+)\s+=>\s+return\s+"([^"]+)";'
        if function == "Member_Name"
        else r"when\s+(\d+)\s+=>\s+return\s+([A-Za-z_]+);"
    )
    pairs = re.findall(pattern, member_block(model, function, shape))
    if [int(number) for number, _ in pairs] != list(range(1, len(pairs) + 1)):
        fail(f"shape {shape} {function} order is not contiguous")
    return [value for _, value in pairs]


def member_count(model: str, shape: int) -> int:
    match = re.search(
        rf"when\s+{shape}\s+=>\s+return\s+(\d+);",
        function_body(model, "Member_Count"),
    )
    if match is None:
        fail(f"generated model has no member count for shape {shape}")
    return int(match.group(1))


def comma_values(value: str) -> list[str]:
    values = value.split(",")
    if any(item == "" or item != item.strip() for item in values):
        fail(f"noncanonical comma list: {value!r}")
    if len(values) != len(set(values)):
        fail(f"duplicate comma-list value: {value!r}")
    return values


def main() -> int:
    lock = LOCK.read_text(encoding="utf-8")
    if f'revision = "{EXPECTED_REVISION}"' not in lock:
        fail("pinned botocore revision changed")
    if f'service_model_sha256 = "{EXPECTED_SHA256}"' not in lock:
        fail("pinned botocore service hash changed")

    model = MODEL.read_text(encoding="utf-8")
    input_shape = operation_shape(model, "Input_Shape")
    output_shape = operation_shape(model, "Output_Shape")
    if input_shape != 146 or output_shape != 0:
        fail(f"unexpected operation shapes: input={input_shape}, output={output_shape}")
    if member_count(model, input_shape) != len(EXPECTED_MEMBERS):
        fail("generated request member count changed")
    if member_values(model, "Member_Name", input_shape) != EXPECTED_MEMBERS:
        fail("generated request member names changed")
    if member_values(model, "Location", input_shape) != [
        "URI_Location", "Header_Location",
    ]:
        fail("generated request member locations changed")

    members = read_tsv(CORPUS / "members.tsv", MEMBER_HEADER)
    vectors = read_tsv(CORPUS / "vectors.tsv", VECTOR_HEADER)
    if [row["member"] for row in members] != EXPECTED_MEMBERS:
        fail("manifest member names changed")
    if [int(row["ordinal"]) for row in members] != [1, 2]:
        fail("manifest ordinals are not contiguous")
    if any(row["direction"] != "request" or row["shape"] != "146"
           or row["current_boundary"] != "projected" for row in members):
        fail("manifest shape or boundary changed")

    vector_by_id: dict[str, dict[str, str]] = {}
    for vector in vectors:
        vector_id = vector["id"]
        if not re.fullmatch(r"DBC-(?:RQ|RS|TR)-\d{3}", vector_id):
            fail(f"noncanonical vector id: {vector_id}")
        if vector_id in vector_by_id:
            fail(f"duplicate vector id: {vector_id}")
        vector_by_id[vector_id] = vector

    member_keys = {f'request:{row["member"]}' for row in members}
    referenced_vectors: set[str] = set()
    for member in members:
        member_key = f'request:{member["member"]}'
        for vector_id in comma_values(member["vector_ids"]):
            vector = vector_by_id.get(vector_id)
            if vector is None:
                fail(f"{member_key}: unknown vector {vector_id}")
            if member_key not in comma_values(vector["member_refs"]):
                fail(f"{member_key}: {vector_id} lacks reciprocal reference")
            referenced_vectors.add(vector_id)

    for vector_id, vector in vector_by_id.items():
        for reference in comma_values(vector["member_refs"]):
            if reference == "operation:DeleteBucketCors":
                continue
            if reference not in member_keys:
                fail(f"{vector_id}: unknown member reference {reference}")
        if vector_id not in referenced_vectors and \
                "operation:DeleteBucketCors" not in comma_values(
                    vector["member_refs"]
                ):
            fail(f"{vector_id}: unreachable vector")

    print(
        "DeleteBucketCors preparation: 2 request members, no modeled success "
        f"output, {len(vectors)} reciprocal contract vectors; pinned model matches"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, UnicodeError, ValueError) as exc:
        print(
            f"DeleteBucketCors preparation verification failed: {exc}",
            file=sys.stderr,
        )
        raise SystemExit(1)
