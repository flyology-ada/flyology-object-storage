#!/usr/bin/env python3
"""Verify PutObjectRetention inventory and reciprocal corpus coverage."""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "tests/corpora/put-object-retention"
MODEL = ROOT / "src/flyology-object_storage-s3-model.adb"
LOCK = ROOT / "coverage/corpora.lock.toml"
SOURCES = (
    ROOT / "src/flyology-object_storage-client-low_level.ads",
    ROOT / "src/flyology-object_storage-client-low_level.adb",
    ROOT / "src/flyology-object_storage-s3-object_lock.ads",
    ROOT / "src/flyology-object_storage-s3-object_lock.adb",
)
REVISION = "36c34f15391da01cd717c73c0fffa747c9889768"
SHA256 = "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
EXPECTED = [
    ("request", 556, 1, "Bucket", 60, "uri-label", "true", "projected"),
    ("request", 556, 2, "Key", 471, "uri-label", "true", "projected"),
    ("request", 556, 3, "Retention", 480, "body", "false", "encoded"),
    ("request", 556, 4, "RequestPayer", 599, "header", "false", "projected"),
    ("request", 556, 5, "VersionId", 492, "query", "false", "projected"),
    ("request", 556, 6, "BypassGovernanceRetention", 66, "header", "false", "projected"),
    ("request", 556, 7, "ContentMD5", 111, "header", "false", "projected"),
    ("request", 556, 8, "ChecksumAlgorithm", 77, "header", "false", "projected"),
    ("request", 556, 9, "ExpectedBucketOwner", 15, "header", "false", "projected"),
    ("nested", 480, 1, "Mode", 481, "body", "false", "encoded"),
    ("nested", 480, 2, "RetainUntilDate", 140, "body", "false", "encoded"),
    ("response", 555, 1, "RequestCharged", 598, "header", "false", "decoded"),
]
MEMBER_HEADER = ["direction", "shape", "ordinal", "member", "member_shape",
                 "wire_location", "required", "current_boundary",
                 "required_contract", "vector_ids"]
VECTOR_HEADER = ["id", "direction", "layer", "category", "member_refs",
                 "stimulus", "expected_contract"]
LOCATION = {"URI_Location": "uri-label", "Header_Location": "header",
            "Query_Location": "query", "Body_Location": "body"}


def fail(message: str) -> None:
    raise ValueError(message)


def function_body(model: str, function: str) -> str:
    match = re.search(rf"   function {re.escape(function)}(?=\s*\()", model)
    if match is None:
        fail(f"generated model lacks {function}")
    tail = model[match.end():]
    marker = f"end {function};"
    if marker not in tail:
        fail(f"generated model lacks end {function}")
    return tail.split(marker, 1)[0]


def operation_scalar(model: str, function: str) -> str:
    match = re.search(
        r"when Put_Object_Retention_Operation =>\s+return\s+([^;]+);",
        function_body(model, function))
    if match is None:
        fail(f"PutObjectRetention lacks {function}")
    return match.group(1).strip().strip('"')


def shape_scalar(model: str, function: str, shape: int) -> str:
    match = re.search(rf"when\s+{shape}\s+=>\s+return\s+([^;]+);",
                      function_body(model, function))
    if match is None:
        fail(f"shape {shape} lacks {function}")
    return match.group(1).strip().strip('"')


def case_values(model: str, function: str, shape: int) -> list[str]:
    match = re.search(rf"when {shape} =>\s+case Member is(.*?)\s+end case;",
                      function_body(model, function), re.DOTALL)
    if match is None:
        fail(f"shape {shape} lacks {function} members")
    value = r'"([^"]*)"' if function in (
        "Member_Name", "Member_Location_Name") else \
        r"([A-Za-z_][A-Za-z0-9_]*|\d+)"
    pairs = re.findall(rf"when\s+(\d+)\s+=>\s+return\s+{value};",
                       match.group(1))
    if [int(index) for index, _ in pairs] != list(range(1, len(pairs) + 1)):
        fail(f"shape {shape} {function} is not contiguous")
    return [item for _, item in pairs]


def enum_values(model: str, shape: int) -> list[str]:
    match = re.search(rf"when {shape} =>\s+case Index is(.*?)\s+end case;",
                      function_body(model, "Enumeration_Value"), re.DOTALL)
    if match is None:
        fail(f"shape {shape} lacks enum values")
    return [value for _, value in re.findall(
        r'when\s+(\d+)\s+=>\s+return\s+"([^"]*)";', match.group(1))]


def read_tsv(path: Path, header: list[str]) -> list[dict[str, str]]:
    if b"\r" in path.read_bytes():
        fail(f"{path}: CR characters are not canonical")
    with path.open(encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        if reader.fieldnames != header:
            fail(f"{path}: header mismatch")
        rows = list(reader)
    if not rows or any(None in row or any(value == "" for value in row.values())
                       for row in rows):
        fail(f"{path}: empty or surplus field")
    return rows


def main() -> int:
    lock = LOCK.read_text(encoding="utf-8")
    if f'revision = "{REVISION}"' not in lock or \
            f'service_model_sha256 = "{SHA256}"' not in lock:
        fail("pinned botocore identity changed")
    model = MODEL.read_text(encoding="utf-8")
    scalars = {
        "Method": "Put_Method",
        "Request_URI": "/{Bucket}/{Key+}?retention",
        "Response_Code": "200",
        "Input_Shape": "556",
        "Output_Shape": "555",
        "Request_Checksum_Required": "True",
        "Request_Checksum_Algorithm_Member": "ChecksumAlgorithm",
    }
    for function, expected in scalars.items():
        if operation_scalar(model, function) != expected:
            fail(f"generated {function} changed")
    for shape in (555, 556, 480):
        if shape_scalar(model, "Kind", shape) != "Structure_Shape":
            fail(f"generated structure shape {shape} changed kind")
    if shape_scalar(model, "Kind", 66) != "Boolean_Shape":
        fail("generated governance bypass shape changed")
    if shape_scalar(model, "Timestamp_Format", 140) != "iso8601":
        fail("generated retention timestamp format changed")
    if enum_values(model, 481) != ["GOVERNANCE", "COMPLIANCE"]:
        fail("generated retention mode enum changed")
    if enum_values(model, 598) != ["requester"] or \
            enum_values(model, 599) != ["requester"]:
        fail("generated requester-pays enum changed")
    checksums = ["CRC32", "CRC32C", "SHA1", "SHA256", "CRC64NVME",
                 "SHA512", "MD5", "XXHASH64", "XXHASH3", "XXHASH128"]
    if enum_values(model, 77) != checksums:
        fail("generated checksum algorithm enum changed")

    generated = []
    for direction, shape, boundary in (("request", 556, "projected"),
                                       ("nested", 480, "encoded"),
                                       ("response", 555, "decoded")):
        names = case_values(model, "Member_Name", shape)
        shapes = case_values(model, "Member_Shape", shape)
        locations = case_values(model, "Location", shape)
        required = case_values(model, "Member_Required", shape)
        for index, name in enumerate(names):
            member_boundary = (
                "encoded" if shape == 556 and name == "Retention"
                else boundary)
            generated.append((direction, shape, index + 1, name,
                              int(shapes[index]), LOCATION[locations[index]],
                              required[index].lower(), member_boundary))
    if generated != EXPECTED:
        fail(f"generated inventory changed: {generated!r}")

    members = read_tsv(CORPUS / "members.tsv", MEMBER_HEADER)
    manifest = [(row["direction"], int(row["shape"]), int(row["ordinal"]),
                 row["member"], int(row["member_shape"]),
                 row["wire_location"], row["required"],
                 row["current_boundary"]) for row in members]
    if manifest != EXPECTED:
        fail("manifest differs from generated inventory")
    vectors = read_tsv(CORPUS / "vectors.tsv", VECTOR_HEADER)
    vector_by_id = {row["id"]: row for row in vectors}
    if len(vector_by_id) != len(vectors):
        fail("duplicate vector identifier")
    member_keys = {f'{row["direction"]}:{row["shape"]}:{row["member"]}'
                   for row in members}
    reached = set()
    for row in members:
        key = f'{row["direction"]}:{row["shape"]}:{row["member"]}'
        for vector_id in row["vector_ids"].split(","):
            if vector_id not in vector_by_id or key not in \
                    vector_by_id[vector_id]["member_refs"].split(","):
                fail(f"{key}: invalid reciprocal vector {vector_id}")
            reached.add(vector_id)
    for vector in vectors:
        refs = vector["member_refs"].split(",")
        if any(ref != "operation:PutObjectRetention" and
               ref not in member_keys for ref in refs):
            fail(f'{vector["id"]}: unknown member reference')
        if vector["id"] not in reached and \
                "operation:PutObjectRetention" not in refs:
            fail(f'{vector["id"]}: unreachable vector')

    source = "\n".join(path.read_text(encoding="utf-8") for path in SOURCES)
    for token in ("Serialize_Retention", "Prepare_Put_Object_Retention",
                  "Execute_Put_Object_Retention",
                  "Decode_Put_Object_Retention_Response",
                  "Put_Object_Retention_Operation",
                  "Non_Replayable_Buffer_Source", "Owned_Request_Payload",
                  "x-amz-bypass-governance-retention",
                  "x-amz-sdk-checksum-algorithm"):
        if token not in source:
            fail(f"typed implementation lacks {token}")
    print("PutObjectRetention preparation: 12 modeled members, 10 exact "
          f"checksum values, {len(vectors)} vectors")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, UnicodeError, ValueError) as exc:
        print(f"PutObjectRetention verification failed: {exc}",
              file=sys.stderr)
        raise SystemExit(1)
