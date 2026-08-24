#!/usr/bin/env python3
"""Verify the pinned GetBucketCors inventory and reciprocal corpus graph."""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "src/flyology-object_storage-s3-model.adb"
CORPUS = ROOT / "tests/corpora/get-bucket-cors"
LOCK = ROOT / "coverage/corpora.lock.toml"
SOURCES = (
    ROOT / "src/flyology-object_storage-client-low_level.ads",
    ROOT / "src/flyology-object_storage-client-low_level.adb",
    ROOT / "src/flyology-object_storage-s3-bucket_controls.ads",
    ROOT / "src/flyology-object_storage-s3-bucket_controls.adb",
)
REVISION = "36c34f15391da01cd717c73c0fffa747c9889768"
SHA256 = "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
EXPECTED = [
    ("request", 230, 1, "Bucket", 60, "uri-label", "true", "projected"),
    ("request", 230, 2, "ExpectedBucketOwner", 15, "header", "false", "projected"),
    ("output", 229, 1, "CORSRules", 72, "body", "false", "decoded"),
    ("nested", 71, 1, "ID", 308, "body", "false", "decoded"),
    ("nested", 71, 2, "AllowedHeaders", 18, "body", "false", "decoded"),
    ("nested", 71, 3, "AllowedMethods", 20, "body", "true", "decoded"),
    ("nested", 71, 4, "AllowedOrigins", 22, "body", "true", "decoded"),
    ("nested", 71, 5, "ExposeHeaders", 211, "body", "false", "decoded"),
    ("nested", 71, 6, "MaxAgeSeconds", 412, "body", "false", "decoded"),
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


def body(model: str, function: str) -> str:
    match = re.search(rf"   function {re.escape(function)}(?=\s*\()", model)
    if match is None:
        fail(f"generated model lacks {function}")
    tail = model[match.end():]
    return tail.split(f"end {function};", 1)[0]


def op(model: str, function: str) -> str:
    match = re.search(r"when Get_Bucket_Cors_Operation =>\s+return\s+([^;]+);",
                      body(model, function))
    if match is None:
        fail(f"GetBucketCors lacks {function}")
    return match.group(1).strip().strip('"')


def scalar(model: str, function: str, shape: int) -> str:
    match = re.search(rf"when\s+{shape}\s+=>\s+return\s+([^;]+);",
                      body(model, function))
    if match is None:
        fail(f"shape {shape} lacks {function}")
    return match.group(1).strip().strip('"')


def members(model: str, function: str, shape: int) -> list[str]:
    match = re.search(rf"when {shape} =>\s+case Member is(.*?)\s+end case;",
                      body(model, function), re.DOTALL)
    if match is None:
        fail(f"shape {shape} lacks {function} members")
    pattern = r'"([^"]*)"' if function in ("Member_Name", "Member_Location_Name") \
        else r"([A-Za-z_][A-Za-z0-9_]*|\d+)"
    pairs = re.findall(rf"when\s+(\d+)\s+=>\s+return\s+{pattern};",
                       match.group(1))
    return [value for _, value in pairs]


def read_tsv(path: Path, header: list[str]) -> list[dict[str, str]]:
    if b"\r" in path.read_bytes():
        fail(f"{path}: noncanonical CR")
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
    scalars = {"Method": "Get_Method", "Request_URI": "/{Bucket}?cors",
               "Response_Code": "200", "Input_Shape": "230",
               "Output_Shape": "229", "Request_Checksum_Required": "False"}
    for function, expected in scalars.items():
        if op(model, function) != expected:
            fail(f"generated {function} changed")
    if scalar(model, "Kind", 72) != "List_Shape" or \
            scalar(model, "List_Member_Shape", 72) != "71" or \
            scalar(model, "Is_Flattened", 72) != "True" or \
            scalar(model, "Shape_Name", 70) != "CORSConfiguration":
        fail("generated flattened CORSRule contract changed")
    for list_shape, item_shape in ((18, 17), (20, 19), (22, 21), (211, 210)):
        if scalar(model, "Kind", list_shape) != "List_Shape" or \
                scalar(model, "List_Member_Shape", list_shape) != str(item_shape) or \
                scalar(model, "Is_Flattened", list_shape) != "True":
            fail(f"generated flattened list {list_shape} changed")
    if scalar(model, "Kind", 412) != "Integer_Shape" or \
            scalar(model, "Minimum", 412) != "" or \
            scalar(model, "Maximum", 412) != "":
        fail("generated unbounded MaxAgeSeconds contract changed")

    generated = []
    for direction, shape, boundary in (("request", 230, "projected"),
                                       ("output", 229, "decoded"),
                                       ("nested", 71, "decoded")):
        names = members(model, "Member_Name", shape)
        shapes = members(model, "Member_Shape", shape)
        locations = members(model, "Location", shape)
        required = members(model, "Member_Required", shape)
        for index, name in enumerate(names):
            generated.append((direction, shape, index + 1, name,
                              int(shapes[index]), LOCATION[locations[index]],
                              required[index].lower(), boundary))
    if generated != EXPECTED:
        fail(f"generated inventory changed: {generated!r}")

    manifest_rows = read_tsv(CORPUS / "members.tsv", MEMBER_HEADER)
    manifest = [(row["direction"], int(row["shape"]), int(row["ordinal"]),
                 row["member"], int(row["member_shape"]), row["wire_location"],
                 row["required"], row["current_boundary"])
                for row in manifest_rows]
    if manifest != EXPECTED:
        fail("manifest differs from generated inventory")
    vectors = read_tsv(CORPUS / "vectors.tsv", VECTOR_HEADER)
    vector_ids = {row["id"] for row in vectors}
    member_keys = {f'{row["direction"]}:{row["member"]}' for row in manifest_rows}
    reached = set()
    for row in manifest_rows:
        key = f'{row["direction"]}:{row["member"]}'
        for vector_id in row["vector_ids"].split(","):
            if vector_id not in vector_ids:
                fail(f"{key}: unknown vector {vector_id}")
            reached.add(vector_id)
    for vector in vectors:
        refs = vector["member_refs"].split(",")
        if any(ref != "operation:GetBucketCors" and ref not in member_keys
               for ref in refs):
            fail(f'{vector["id"]}: unknown member reference')
        if vector["id"] not in reached and "operation:GetBucketCors" not in refs:
            fail(f'{vector["id"]}: unreachable vector')
    source = "\n".join(path.read_text(encoding="utf-8") for path in SOURCES)
    for token in ("Prepare_Get_Bucket_CORS", "Decode_Get_Bucket_CORS_Response",
                  "Execute_Get_Bucket_CORS", "Parse_CORS",
                  "Optional_CORS_Integer_Text", "CORS_String_Vectors"):
        if token not in source:
            fail(f"typed implementation lacks {token}")
    print(f"GetBucketCors preparation: 9 modeled members, four flattened "
          f"string lists, unbounded integer text, {len(vectors)} vectors")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, UnicodeError, ValueError) as exc:
        print(f"GetBucketCors verification failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
