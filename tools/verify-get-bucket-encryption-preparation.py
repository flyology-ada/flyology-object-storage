#!/usr/bin/env python3
"""Verify GetBucketEncryption model inventory and reciprocal corpus graph."""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "tests/corpora/get-bucket-encryption"
MODEL = ROOT / "src/flyology-object_storage-s3-model.adb"
LOCK = ROOT / "coverage/corpora.lock.toml"
SOURCES = (
    ROOT / "src/flyology-object_storage-client-low_level.ads",
    ROOT / "src/flyology-object_storage-client-low_level.adb",
    ROOT / "src/flyology-object_storage-s3-encryption.ads",
    ROOT / "src/flyology-object_storage-s3-encryption.adb",
)
REVISION = "36c34f15391da01cd717c73c0fffa747c9889768"
SHA256 = "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
EXPECTED = [
    ("request", 232, 1, "Bucket", 60, "uri-label", "true", "projected"),
    ("request", 232, 2, "ExpectedBucketOwner", 15, "header", "false", "projected"),
    ("output", 231, 1, "ServerSideEncryptionConfiguration", 648, "body", "false", "decoded"),
    ("nested", 648, 1, "Rules", 650, "body", "true", "decoded"),
    ("nested", 649, 1, "ApplyServerSideEncryptionByDefault", 647, "body", "false", "decoded"),
    ("nested", 649, 2, "BucketKeyEnabled", 54, "body", "false", "decoded"),
    ("nested", 649, 3, "BlockedEncryptionTypes", 45, "body", "false", "decoded"),
    ("nested", 647, 1, "SSEAlgorithm", 646, "body", "true", "decoded"),
    ("nested", 647, 2, "KMSMasterKeyID", 639, "body", "false", "decoded"),
    ("nested", 45, 1, "EncryptionType", 190, "body", "false", "decoded"),
]
MEMBER_HEADER = ["direction", "shape", "ordinal", "member", "member_shape",
                 "wire_location", "required", "current_boundary",
                 "required_contract", "vector_ids"]
VECTOR_HEADER = ["id", "direction", "layer", "category", "member_refs",
                 "stimulus", "expected_contract"]
LOCATION = {"URI_Location": "uri-label", "Header_Location": "header",
            "Body_Location": "body", "Query_Location": "query"}


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
        r"when Get_Bucket_Encryption_Operation =>\s+return\s+([^;]+);",
        function_body(model, function))
    if match is None:
        fail(f"GetBucketEncryption lacks {function}")
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
    scalars = {"Method": "Get_Method", "Request_URI": "/{Bucket}?encryption",
               "Response_Code": "200", "Input_Shape": "232",
               "Output_Shape": "231", "Request_Checksum_Required": "False"}
    for function, expected in scalars.items():
        if operation_scalar(model, function) != expected:
            fail(f"generated {function} changed")
    if shape_scalar(model, "Kind", 650) != "List_Shape" or \
            shape_scalar(model, "List_Member_Shape", 650) != "649" or \
            shape_scalar(model, "Is_Flattened", 650) != "True" or \
            shape_scalar(model, "Kind", 190) != "List_Shape" or \
            shape_scalar(model, "List_Member_Shape", 190) != "189" or \
            shape_scalar(model, "Is_Flattened", 190) != "True":
        fail("generated flattened encryption lists changed")
    if enum_values(model, 646) != [
            "AES256", "aws:fsx", "aws:backup", "aws:kms", "aws:kms:dsse"]:
        fail("generated encryption algorithm enum changed")
    if enum_values(model, 189) != ["NONE", "SSE-C"]:
        fail("generated blocked encryption enum changed")

    generated = []
    for direction, shape, boundary in (
            ("request", 232, "projected"), ("output", 231, "decoded"),
            ("nested", 648, "decoded"), ("nested", 649, "decoded"),
            ("nested", 647, "decoded"), ("nested", 45, "decoded")):
        names = case_values(model, "Member_Name", shape)
        shapes = case_values(model, "Member_Shape", shape)
        locations = case_values(model, "Location", shape)
        required = case_values(model, "Member_Required", shape)
        for index, name in enumerate(names):
            generated.append((direction, shape, index + 1, name,
                              int(shapes[index]), LOCATION[locations[index]],
                              required[index].lower(), boundary))
    if generated != EXPECTED:
        fail(f"generated inventory changed: {generated!r}")

    member_rows = read_tsv(CORPUS / "members.tsv", MEMBER_HEADER)
    manifest = [(row["direction"], int(row["shape"]), int(row["ordinal"]),
                 row["member"], int(row["member_shape"]), row["wire_location"],
                 row["required"], row["current_boundary"])
                for row in member_rows]
    if manifest != EXPECTED:
        fail("manifest differs from generated inventory")
    vectors = read_tsv(CORPUS / "vectors.tsv", VECTOR_HEADER)
    vector_by_id = {row["id"]: row for row in vectors}
    if len(vector_by_id) != len(vectors):
        fail("duplicate vector identifier")
    member_keys = {f'{row["direction"]}:{row["member"]}' for row in member_rows}
    reached = set()
    for row in member_rows:
        key = f'{row["direction"]}:{row["member"]}'
        for vector_id in row["vector_ids"].split(","):
            if vector_id not in vector_by_id or key not in \
                    vector_by_id[vector_id]["member_refs"].split(","):
                fail(f"{key}: invalid reciprocal vector {vector_id}")
            reached.add(vector_id)
    for vector in vectors:
        refs = vector["member_refs"].split(",")
        if any(ref != "operation:GetBucketEncryption" and ref not in member_keys
               for ref in refs):
            fail(f'{vector["id"]}: unknown member reference')
        if vector["id"] not in reached and \
                "operation:GetBucketEncryption" not in refs:
            fail(f'{vector["id"]}: unreachable vector')
    source = "\n".join(path.read_text(encoding="utf-8") for path in SOURCES)
    for token in ("Prepare_Get_Bucket_Encryption",
                  "Decode_Get_Bucket_Encryption_Response",
                  "Execute_Get_Bucket_Encryption", "Encryption_Rule_Vectors",
                  "AES256_Encryption, FSx_Encryption, Backup_Encryption"):
        if token not in source:
            fail(f"typed implementation lacks {token}")
    print("GetBucketEncryption preparation: 10 modeled members, two "
          f"flattened lists, 7 exact enum values, {len(vectors)} vectors")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, UnicodeError, ValueError) as exc:
        print(f"GetBucketEncryption verification failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
