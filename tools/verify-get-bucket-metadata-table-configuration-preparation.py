#!/usr/bin/env python3
"""Verify GetBucketMetadataTableConfiguration inventory and corpus graph."""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "tests/corpora/get-bucket-metadata-table-configuration"
MODEL = ROOT / "src/flyology-object_storage-s3-model.adb"
LOCK = ROOT / "coverage/corpora.lock.toml"
SOURCES = (
    ROOT / "src/flyology-object_storage-client-low_level.ads",
    ROOT / "src/flyology-object_storage-client-low_level.adb",
    ROOT / "src/flyology-object_storage-s3-metadata_tables.ads",
    ROOT / "src/flyology-object_storage-s3-metadata_tables.adb",
)
REVISION = "36c34f15391da01cd717c73c0fffa747c9889768"
SHA256 = "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
EXPECTED = [
    ("request", 249, 1, "Bucket", 60, "uri-label", "true", "projected"),
    ("request", 249, 2, "ExpectedBucketOwner", 15, "header", "false", "projected"),
    ("output", 248, 1, "GetBucketMetadataTableConfigurationResult", 250, "body", "false", "decoded"),
    ("nested", 250, 1, "MetadataTableConfigurationResult", 427, "body", "true", "decoded"),
    ("nested", 250, 2, "Status", 429, "body", "true", "decoded"),
    ("nested", 250, 3, "Error", 196, "body", "false", "decoded"),
    ("nested", 427, 1, "S3TablesDestinationResult", 630, "body", "true", "decoded"),
    ("nested", 630, 1, "TableBucketArn", 627, "body", "true", "decoded"),
    ("nested", 630, 2, "TableName", 631, "body", "true", "decoded"),
    ("nested", 630, 3, "TableArn", 626, "body", "true", "decoded"),
    ("nested", 630, 4, "TableNamespace", 632, "body", "true", "decoded"),
    ("nested", 196, 1, "ErrorCode", 195, "body", "false", "decoded"),
    ("nested", 196, 2, "ErrorMessage", 198, "body", "false", "decoded"),
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
        r"when Get_Bucket_Metadata_Table_Configuration_Operation =>\s+return\s+([^;]+);",
        function_body(model, function))
    if match is None:
        fail(f"operation lacks {function}")
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
    scalars = {"Method": "Get_Method", "Request_URI": "/{Bucket}?metadataTable",
               "Response_Code": "200", "Input_Shape": "249",
               "Output_Shape": "248", "Request_Checksum_Required": "False"}
    for function, expected in scalars.items():
        if operation_scalar(model, function) != expected:
            fail(f"generated {function} changed")
    structures = (248, 249, 250, 427, 630, 196)
    if any(shape_scalar(model, "Kind", shape) != "Structure_Shape"
           for shape in structures):
        fail("generated metadata-table structures changed kind")
    if any(shape_scalar(model, "Enumeration_Count", shape) != "0"
           for shape in (195, 198, 429, 626, 627, 631, 632)):
        fail("generated metadata-table strings gained an enum domain")
    if any(shape_scalar(model, "Minimum", shape) != "" or
           shape_scalar(model, "Maximum", shape) != ""
           for shape in (195, 198, 429, 626, 627, 631, 632)):
        fail("generated metadata-table string bounds changed")

    generated = []
    for direction, shape, boundary in (
            ("request", 249, "projected"), ("output", 248, "decoded"),
            ("nested", 250, "decoded"), ("nested", 427, "decoded"),
            ("nested", 630, "decoded"), ("nested", 196, "decoded")):
        names = case_values(model, "Member_Name", shape)
        shapes = case_values(model, "Member_Shape", shape)
        locations = case_values(model, "Location", shape)
        required = case_values(model, "Member_Required", shape)
        flattened = case_values(model, "Member_Flattened", shape)
        if any(value != "False" for value in flattened):
            fail(f"shape {shape} unexpectedly gained a flattened member")
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
    member_keys = {f'{row["direction"]}:{row["member"]}'
                   for row in member_rows}
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
        if any(ref != "operation:GetBucketMetadataTableConfiguration" and
               ref not in member_keys for ref in refs):
            fail(f'{vector["id"]}: unknown member reference')
        if vector["id"] not in reached and \
                "operation:GetBucketMetadataTableConfiguration" not in refs:
            fail(f'{vector["id"]}: unreachable vector')
    source = "\n".join(path.read_text(encoding="utf-8") for path in SOURCES)
    for token in ("Prepare_Get_Bucket_Metadata_Table_Configuration",
                  "Decode_Get_Bucket_Metadata_Table_Configuration_Response",
                  "Execute_Get_Bucket_Metadata_Table_Configuration",
                  "S3_Tables_Destination_Result",
                  "Status remains an opaque required provider string"):
        if token not in source:
            fail(f"typed implementation lacks {token}")
    print("GetBucketMetadataTableConfiguration preparation: 13 modeled "
          f"members, no lists or enums, {len(vectors)} vectors")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, UnicodeError, ValueError) as exc:
        print(f"GetBucketMetadataTableConfiguration verification failed: {exc}",
              file=sys.stderr)
        raise SystemExit(1)
