#!/usr/bin/env python3
"""Verify the pinned lifecycle-read inventory and reciprocal corpus graph."""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "tests/corpora/get-bucket-lifecycle-configuration"
MODEL = ROOT / "src/flyology-object_storage-s3-model.adb"
LOCK = ROOT / "coverage/corpora.lock.toml"
SOURCES = (
    ROOT / "src/flyology-object_storage-client-low_level.ads",
    ROOT / "src/flyology-object_storage-client-low_level.adb",
    ROOT / "src/flyology-object_storage-client-buckets.ads",
    ROOT / "src/flyology-object_storage-client-buckets.adb",
    ROOT / "src/flyology-object_storage-s3-lifecycle.ads",
    ROOT / "src/flyology-object_storage-s3-lifecycle.adb",
)
REVISION = "36c34f15391da01cd717c73c0fffa747c9889768"
SHA256 = "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
EXPECTED = [
    ("request", 238, 1, "Bucket", 60, "uri-label", "true", "projected"),
    ("request", 238, 2, "ExpectedBucketOwner", 15, "header", "false", "projected"),
    ("output", 237, 1, "Rules", 377, "body", "false", "decoded"),
    ("output", 237, 2, "TransitionDefaultMinimumObjectSize", 693,
     "header", "false", "decoded"),
    ("nested", 3, 1, "DaysAfterInitiation", 142, "body", "false", "decoded"),
    ("nested", 373, 1, "Date", 140, "body", "false", "decoded"),
    ("nested", 373, 2, "Days", 141, "body", "false", "decoded"),
    ("nested", 373, 3, "ExpiredObjectDeleteMarker", 208, "body", "false", "decoded"),
    ("nested", 374, 1, "Expiration", 373, "body", "false", "decoded"),
    ("nested", 374, 2, "ID", 308, "body", "false", "decoded"),
    ("nested", 374, 3, "Prefix", 517, "body", "false", "decoded"),
    ("nested", 374, 4, "Filter", 376, "body", "false", "decoded"),
    ("nested", 374, 5, "Status", 207, "body", "true", "decoded"),
    ("nested", 374, 6, "Transitions", 694, "body", "false", "decoded"),
    ("nested", 374, 7, "NoncurrentVersionTransitions", 457,
     "body", "false", "decoded"),
    ("nested", 374, 8, "NoncurrentVersionExpiration", 455,
     "body", "false", "decoded"),
    ("nested", 374, 9, "AbortIncompleteMultipartUpload", 3,
     "body", "false", "decoded"),
    ("nested", 375, 1, "Prefix", 517, "body", "false", "decoded"),
    ("nested", 375, 2, "Tags", 674, "body", "false", "decoded"),
    ("nested", 375, 3, "ObjectSizeGreaterThan", 488,
     "body", "false", "decoded"),
    ("nested", 375, 4, "ObjectSizeLessThan", 489,
     "body", "false", "decoded"),
    ("nested", 376, 1, "Prefix", 517, "body", "false", "decoded"),
    ("nested", 376, 2, "Tag", 672, "body", "false", "decoded"),
    ("nested", 376, 3, "ObjectSizeGreaterThan", 488,
     "body", "false", "decoded"),
    ("nested", 376, 4, "ObjectSizeLessThan", 489,
     "body", "false", "decoded"),
    ("nested", 376, 5, "And", 375, "body", "false", "decoded"),
    ("nested", 455, 1, "NoncurrentDays", 141, "body", "false", "decoded"),
    ("nested", 455, 2, "NewerNoncurrentVersions", 711,
     "body", "false", "decoded"),
    ("nested", 456, 1, "NoncurrentDays", 141, "body", "false", "decoded"),
    ("nested", 456, 2, "StorageClass", 695, "body", "false", "decoded"),
    ("nested", 456, 3, "NewerNoncurrentVersions", 711,
     "body", "false", "decoded"),
    ("nested", 672, 1, "Key", 471, "body", "true", "decoded"),
    ("nested", 672, 2, "Value", 710, "body", "true", "decoded"),
    ("nested", 692, 1, "Date", 140, "body", "false", "decoded"),
    ("nested", 692, 2, "Days", 141, "body", "false", "decoded"),
    ("nested", 692, 3, "StorageClass", 695, "body", "false", "decoded"),
]
INVENTORY_SHAPES = (238, 237, 3, 373, 374, 375, 376, 455, 456, 672, 692)
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


def operation_scalar(
    model: str,
    function: str,
    operation: str = "Get_Bucket_Lifecycle_Configuration_Operation",
) -> str:
    match = re.search(
        rf"when {re.escape(operation)} =>\s+"
        r"return\s+([^;]+);", function_body(model, function))
    if match is None:
        fail(f"{operation} lacks {function}")
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


def comma_values(value: str) -> list[str]:
    values = value.split(",")
    if any(not item or item != item.strip() for item in values):
        fail(f"noncanonical comma list: {value!r}")
    return values


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
        "Method": "Get_Method",
        "Request_URI": "/{Bucket}?lifecycle",
        "Response_Code": "200",
        "Input_Shape": "238",
        "Output_Shape": "237",
        "Request_Checksum_Required": "False",
    }
    for function, expected in scalars.items():
        if operation_scalar(model, function) != expected:
            fail(f"generated {function} changed")

    legacy_scalars = {
        "Method": "Get_Method",
        "Request_URI": "/{Bucket}?lifecycle",
        "Response_Code": "200",
        "Input_Shape": "240",
        "Output_Shape": "239",
        "Request_Checksum_Required": "False",
    }
    for function, expected in legacy_scalars.items():
        if operation_scalar(
            model, function, "Get_Bucket_Lifecycle_Operation"
        ) != expected:
            fail(f"generated legacy {function} changed")

    for function in (
        "Member_Name",
        "Member_Shape",
        "Location",
        "Member_Location_Name",
        "Member_Required",
    ):
        if case_values(model, function, 240) != case_values(
            model, function, 238
        ):
            fail(f"legacy lifecycle request {function} diverged")
    if case_values(model, "Member_Name", 239) != ["Rules"] or \
            case_values(model, "Member_Shape", 239) != ["622"] or \
            case_values(model, "Member_Location_Name", 239) != ["Rule"] or \
            case_values(model, "Member_Required", 239) != ["False"]:
        fail("legacy lifecycle output projection changed")
    if shape_scalar(model, "Kind", 622) != "List_Shape" or \
            shape_scalar(model, "List_Member_Shape", 622) != "621" or \
            shape_scalar(model, "Is_Flattened", 622) != "True":
        fail("legacy lifecycle Rules list changed")
    legacy_rule_wire = case_values(model, "Member_Location_Name", 621)
    modern_rule_wire = case_values(model, "Member_Location_Name", 374)
    if legacy_rule_wire != [
        name for name in modern_rule_wire if name != "Filter"
    ]:
        fail("legacy lifecycle Rule is not the maintained wire subset")

    for list_shape, item_shape, flattened in (
            (377, 374, "True"), (694, 692, "True"),
            (457, 456, "True"), (674, 672, "False")):
        if shape_scalar(model, "Kind", list_shape) != "List_Shape" or \
                shape_scalar(model, "List_Member_Shape", list_shape) != \
                str(item_shape) or \
                shape_scalar(model, "Is_Flattened", list_shape) != flattened:
            fail(f"generated lifecycle list {list_shape} changed")
    if case_values(model, "Member_Location_Name", 237) != [
            "Rule", "x-amz-transition-default-minimum-object-size"] or \
            case_values(model, "Member_Location_Name", 374)[5:7] != [
                "Transition", "NoncurrentVersionTransition"] or \
            case_values(model, "Member_Location_Name", 375)[1] != "Tag":
        fail("generated direct lifecycle list projection changed")
    if enum_values(model, 207) != ["Enabled", "Disabled"] or \
            enum_values(model, 693) != [
                "varies_by_storage_class", "all_storage_classes_128K"] or \
            enum_values(model, 695) != [
                "GLACIER", "STANDARD_IA", "ONEZONE_IA",
                "INTELLIGENT_TIERING", "DEEP_ARCHIVE", "GLACIER_IR"]:
        fail("generated lifecycle enum domain changed")
    if shape_scalar(model, "Kind", 140) != "Timestamp_Shape":
        fail("generated lifecycle Date is no longer a timestamp")
    for shape, kind in ((141, "Integer_Shape"), (142, "Integer_Shape"),
                        (488, "Long_Shape"), (489, "Long_Shape"),
                        (711, "Integer_Shape")):
        if shape_scalar(model, "Kind", shape) != kind or \
                shape_scalar(model, "Minimum", shape) != "" or \
                shape_scalar(model, "Maximum", shape) != "":
            fail(f"generated unbounded numeric shape {shape} changed")

    generated = []
    for direction, shape, boundary in (
            ("request", 238, "projected"), ("output", 237, "decoded"),
            *(("nested", shape, "decoded") for shape in INVENTORY_SHAPES[2:])):
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
    member_keys = {
        f'{row["direction"]}:{row["shape"]}:{row["member"]}'
        for row in member_rows
    }
    reached = set()
    for row in member_rows:
        key = f'{row["direction"]}:{row["shape"]}:{row["member"]}'
        for vector_id in comma_values(row["vector_ids"]):
            if vector_id not in vector_by_id or key not in comma_values(
                    vector_by_id[vector_id]["member_refs"]):
                fail(f"{key}: invalid reciprocal vector {vector_id}")
            reached.add(vector_id)
    for vector in vectors:
        refs = comma_values(vector["member_refs"])
        if any(ref != "operation:GetBucketLifecycleConfiguration" and
               ref not in member_keys for ref in refs):
            fail(f'{vector["id"]}: unknown member reference')
        if vector["id"] not in reached and \
                "operation:GetBucketLifecycleConfiguration" not in refs:
            fail(f'{vector["id"]}: unreachable vector')

    source = "\n".join(path.read_text(encoding="utf-8") for path in SOURCES)
    for token in (
            "Prepare_Get_Bucket_Lifecycle_Configuration",
            "Decode_Get_Bucket_Lifecycle_Configuration_Response",
            "Execute_Get_Bucket_Lifecycle_Configuration",
            "Get_Bucket_Lifecycle_Operation",
            "Get_Lifecycle_Configuration",
            "Lifecycle_Rule_Vectors",
            "Parse_Transition_Default_Minimum_Size"):
        if token not in source:
            fail(f"typed implementation lacks {token}")
    print("GetBucketLifecycleConfiguration preparation: legacy exact wire "
          "subset; 36 modeled members, four exact list projections, 10 enum "
          f"values, five unbounded numeric shapes, {len(vectors)} vectors")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, UnicodeError, ValueError) as exc:
        print("GetBucketLifecycleConfiguration verification failed: "
              f"{exc}", file=sys.stderr)
        raise SystemExit(1)
