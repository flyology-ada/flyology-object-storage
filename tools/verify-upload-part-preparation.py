#!/usr/bin/env python3
"""Verify the qualified UploadPart model disposition and design corpus."""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "tests" / "corpora" / "upload-part"
MEMBERS_PATH = CORPUS / "members.tsv"
VECTORS_PATH = CORPUS / "vectors.tsv"
MODEL_PATH = ROOT / "src" / "flyology-object_storage-s3-model.adb"
LOCK_PATH = ROOT / "coverage" / "corpora.lock.toml"

EXPECTED_REVISION = "36c34f15391da01cd717c73c0fffa747c9889768"
EXPECTED_SHA256 = "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
EXPECTED = {
    ("request", "708"): [
        "Body", "Bucket", "ContentLength", "ContentMD5",
        "ChecksumAlgorithm", "ChecksumCRC32", "ChecksumCRC32C",
        "ChecksumCRC64NVME", "ChecksumSHA1", "ChecksumSHA256",
        "ChecksumSHA512", "ChecksumMD5", "ChecksumXXHASH64",
        "ChecksumXXHASH3", "ChecksumXXHASH128", "Key", "PartNumber",
        "UploadId", "SSECustomerAlgorithm", "SSECustomerKey",
        "SSECustomerKeyMD5", "RequestPayer", "ExpectedBucketOwner",
    ],
    ("response", "707"): [
        "ServerSideEncryption", "ETag", "ChecksumCRC32",
        "ChecksumCRC32C", "ChecksumCRC64NVME", "ChecksumSHA1",
        "ChecksumSHA256", "ChecksumSHA512", "ChecksumMD5",
        "ChecksumXXHASH64", "ChecksumXXHASH3", "ChecksumXXHASH128",
        "SSECustomerAlgorithm", "SSECustomerKeyMD5", "SSEKMSKeyId",
        "BucketKeyEnabled", "RequestCharged",
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
ALLOWED_BOUNDARIES = {
    "qualified", "transport_owned", "validated_rejected",
}
ALLOWED_VECTOR_DIRECTIONS = {"request", "response", "both"}
MANIFEST_TO_MODEL_LOCATION = {
    "payload": "Body_Location",
    "uri-label": "URI_Location",
    "header": "Header_Location",
    # The modeled position is a header. AWS SDK checksum selection can move
    # the corresponding concrete checksum into a declared physical trailer.
    "header-or-trailer": "Header_Location",
    "query": "Query_Location",
}


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


def generated_members(model: str, shape: str) -> list[str]:
    try:
        member_body = model.split("function Member_Name", 1)[1].split(
            "end Member_Name;", 1
        )[0]
    except IndexError as exc:
        raise ValueError("generated model has no Member_Name body") from exc
    match = re.search(
        rf"when {re.escape(shape)} =>\s+case Member is(?P<body>.*?)\s+end case;",
        member_body,
        flags=re.DOTALL,
    )
    if match is None:
        fail(f"generated model has no member block for shape {shape}")
    pairs = re.findall(
        r'when\s+(\d+)\s+=>\s+return\s+"([^"]+)";', match.group("body")
    )
    ordinals = [int(ordinal) for ordinal, _ in pairs]
    if ordinals != list(range(1, len(pairs) + 1)):
        fail(f"generated model shape {shape} member order is not contiguous")
    return [name for _, name in pairs]


def generated_count(model: str, shape: str) -> int:
    try:
        count_body = model.split("function Member_Count", 1)[1].split(
            "end Member_Count;", 1
        )[0]
    except IndexError as exc:
        raise ValueError("generated model has no Member_Count body") from exc
    match = re.search(
        rf"when\s+{re.escape(shape)}\s+=>\s+return\s+(\d+);", count_body
    )
    if match is None:
        fail(f"generated model has no count for shape {shape}")
    return int(match.group(1))


def generated_locations(model: str, shape: str) -> list[str]:
    try:
        location_body = model.split("   function Location\n", 1)[1].split(
            "end Location;", 1
        )[0]
    except IndexError as exc:
        raise ValueError("generated model has no Location body") from exc
    match = re.search(
        rf"when {re.escape(shape)} =>\s+case Member is(?P<body>.*?)\s+end case;",
        location_body,
        flags=re.DOTALL,
    )
    if match is None:
        fail(f"generated model has no location block for shape {shape}")
    pairs = re.findall(
        r"when\s+(\d+)\s+=>\s+return\s+([A-Za-z_]+);",
        match.group("body"),
    )
    ordinals = [int(ordinal) for ordinal, _ in pairs]
    if ordinals != list(range(1, len(pairs) + 1)):
        fail(f"generated model shape {shape} location order is not contiguous")
    return [location for _, location in pairs]


def split_csv(value: str) -> list[str]:
    values = value.split(",")
    if any(item == "" or item != item.strip() for item in values):
        fail(f"noncanonical comma list: {value!r}")
    return values


def main() -> int:
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
        if not re.fullmatch(r"UP-(?:RQ|RS|LC|OR)-\d{3}", vector_id):
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
        generated = generated_members(model, key[1])
        if generated != expected_names:
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
                if ref != "operation:UploadPart":
                    fail(f"{vector_id}: unexpected operation reference {ref}")
            elif ref not in member_keys:
                fail(f"{vector_id}: unknown member reference {ref}")
        if vector_id not in referenced_vectors and not any(
            ref == "operation:UploadPart" for ref in refs
        ):
            fail(f"{vector_id}: vector is not reachable from the manifest")

    request_count = len(grouped[("request", "708")])
    response_count = len(grouped[("response", "707")])
    print(
        "UploadPart qualification: "
        f"{request_count} request members, {response_count} response members, "
        f"{len(vectors)} contract vectors; pinned model and references match"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"UploadPart qualification verification failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
