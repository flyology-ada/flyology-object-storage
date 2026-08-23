#!/usr/bin/env python3
"""Verify the isolated CreateSession member inventory and design corpus."""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "tests" / "corpora" / "create-session"
MODEL = ROOT / "src" / "flyology-object_storage-s3-model.adb"
LOCK = ROOT / "coverage" / "corpora.lock.toml"
EXPECTED_REVISION = "36c34f15391da01cd717c73c0fffa747c9889768"
EXPECTED_SHA256 = "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
EXPECTED = {
    ("request", "137"): [
        "SessionMode", "Bucket", "ServerSideEncryption", "SSEKMSKeyId",
        "SSEKMSEncryptionContext", "BucketKeyEnabled",
    ],
    ("response", "136"): [
        "ServerSideEncryption", "SSEKMSKeyId", "SSEKMSEncryptionContext",
        "BucketKeyEnabled", "Credentials",
    ],
    ("credential", "652"): [
        "AccessKeyId", "SecretAccessKey", "SessionToken", "Expiration",
    ],
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
    "header": "Header_Location",
    "body": "Body_Location",
}


def fail(message: str) -> None:
    raise ValueError(message)


def read_tsv(path: Path, header: list[str]) -> list[dict[str, str]]:
    raw = path.read_bytes()
    if b"\r" in raw:
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


def function_body(model: str, name: str) -> str:
    match = re.search(rf"   function {re.escape(name)}(?=\s*\()", model)
    if match is None:
        fail(f"generated model has no {name}")
    tail = model[match.end():]
    try:
        return tail.split(f"end {name};", 1)[0]
    except IndexError as exc:
        raise ValueError(f"generated model has no end for {name}") from exc


def shape_block(model: str, function: str, shape: str) -> str:
    body = function_body(model, function)
    match = re.search(
        rf"when {re.escape(shape)} =>\s+case Member is(?P<body>.*?)"
        r"\s+end case;",
        body,
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
    pairs = re.findall(pattern, shape_block(model, function, shape))
    if [int(number) for number, _ in pairs] != list(range(1, len(pairs) + 1)):
        fail(f"shape {shape} {function} order is not contiguous")
    return [value for _, value in pairs]


def generated_count(model: str, shape: str) -> int:
    body = function_body(model, "Member_Count")
    match = re.search(rf"when\s+{shape}\s+=>\s+return\s+(\d+);", body)
    if match is None:
        fail(f"generated model has no count for shape {shape}")
    return int(match.group(1))


def csv_values(value: str) -> list[str]:
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
    for row in vectors:
        vector_id = row["id"]
        if not re.fullmatch(r"CS-(?:RQ|RS|TR|OR)-\d{3}", vector_id):
            fail(f"noncanonical vector id: {vector_id}")
        if vector_id in vector_by_id:
            fail(f"duplicate vector id: {vector_id}")
        vector_by_id[vector_id] = row

    grouped: dict[tuple[str, str], list[dict[str, str]]] = {}
    member_keys: set[str] = set()
    referenced: set[str] = set()
    for row in members:
        key = (row["direction"], row["shape"])
        grouped.setdefault(key, []).append(row)
        member_key = f'{row["direction"]}:{row["member"]}'
        if member_key in member_keys:
            fail(f"duplicate member: {member_key}")
        member_keys.add(member_key)
        for vector_id in csv_values(row["vector_ids"]):
            vector = vector_by_id.get(vector_id)
            if vector is None:
                fail(f"{member_key}: unknown vector {vector_id}")
            if member_key not in csv_values(vector["member_refs"]):
                fail(f"{member_key}: {vector_id} lacks reciprocal reference")
            referenced.add(vector_id)

    if set(grouped) != set(EXPECTED):
        fail(f"unexpected direction/shape groups: {sorted(grouped)}")
    for key, expected_names in EXPECTED.items():
        rows = grouped[key]
        if [int(row["ordinal"]) for row in rows] != list(
            range(1, len(expected_names) + 1)
        ):
            fail(f"{key}: manifest ordinals are not contiguous")
        if [row["member"] for row in rows] != expected_names:
            fail(f"{key}: manifest names differ from pinned inventory")
        if generated_count(model, key[1]) != len(expected_names):
            fail(f"{key}: generated member count differs")
        if generated_values(model, "Member_Name", key[1]) != expected_names:
            fail(f"{key}: generated names differ")
        expected_locations = generated_values(model, "Location", key[1])
        actual_locations = [LOCATION[row["wire_location"]] for row in rows]
        if actual_locations != expected_locations:
            fail(f"{key}: generated wire locations differ")

    for vector_id, vector in vector_by_id.items():
        for reference in csv_values(vector["member_refs"]):
            if reference.startswith("operation:"):
                if reference != "operation:CreateSession":
                    fail(f"{vector_id}: unexpected operation reference")
            elif reference not in member_keys:
                fail(f"{vector_id}: unknown member reference {reference}")
        if vector_id not in referenced and "operation:CreateSession" not in \
                csv_values(vector["member_refs"]):
            fail(f"{vector_id}: unreachable vector")

    print(
        "CreateSession preparation: 6 request members, 5 top-level response "
        f"members, 4 credential members, {len(vectors)} contract vectors; "
        "pinned model and references match"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, UnicodeError, ValueError) as exc:
        print(f"CreateSession preparation verification failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
