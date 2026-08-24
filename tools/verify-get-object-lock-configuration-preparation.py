#!/usr/bin/env python3
"""Verify the pinned GetObjectLockConfiguration inventory and corpus graph."""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "tests" / "corpora" / "get-object-lock-configuration"
MODEL = ROOT / "src" / "flyology-object_storage-s3-model.adb"
LOW_SPEC = ROOT / "src" / "flyology-object_storage-client-low_level.ads"
LOW_BODY = ROOT / "src" / "flyology-object_storage-client-low_level.adb"
LOCK_SPEC = ROOT / "src" / "flyology-object_storage-s3-object_lock.ads"
LOCK_BODY = ROOT / "src" / "flyology-object_storage-s3-object_lock.adb"
CORPORA_LOCK = ROOT / "coverage" / "corpora.lock.toml"

# Reviewed upstream identity and persisted generated-shape identifiers.
EXPECTED_REVISION = "36c34f15391da01cd717c73c0fffa747c9889768"
EXPECTED_SHA256 = "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
EXPECTED = [
    ("request", 280, 1, "Bucket", 60, "uri-label", "true", "projected"),
    ("request", 280, 2, "ExpectedBucketOwner", 15, "header", "false", "projected"),
    ("output", 279, 1, "ObjectLockConfiguration", 473, "body", "false", "decoded"),
    ("nested", 473, 1, "ObjectLockEnabled", 474, "body", "false", "decoded"),
    ("nested", 473, 2, "Rule", 482, "body", "false", "decoded"),
    ("nested", 482, 1, "DefaultRetention", 143, "body", "false", "decoded"),
    ("nested", 143, 1, "Mode", 481, "body", "false", "decoded"),
    ("nested", 143, 2, "Days", 141, "body", "false", "decoded"),
    ("nested", 143, 3, "Years", 718, "body", "false", "decoded"),
]
MEMBER_HEADER = [
    "direction", "shape", "ordinal", "member", "member_shape",
    "wire_location", "required", "current_boundary", "required_contract",
    "vector_ids",
]
VECTOR_HEADER = [
    "id", "direction", "layer", "category", "member_refs", "stimulus",
    "expected_contract",
]
LOCATION = {
    "URI_Location": "uri-label", "Query_Location": "query",
    "Header_Location": "header", "Body_Location": "body",
}


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
        fail(f"generated model has no {function}")
    tail = model[match.end():]
    marker = f"end {function};"
    if marker not in tail:
        fail(f"generated model has no end for {function}")
    return tail.split(marker, 1)[0]


def operation_scalar(model: str, function: str) -> str:
    match = re.search(
        r"when Get_Object_Lock_Configuration_Operation =>\s+return\s+([^;]+);",
        function_body(model, function),
    )
    if match is None:
        fail(f"generated model lacks GetObjectLockConfiguration {function}")
    return match.group(1).strip().strip('"')


def shape_scalar(model: str, function: str, shape: int) -> str:
    match = re.search(
        rf"when\s+{shape}\s+=>\s+return\s+([^;]+);",
        function_body(model, function),
    )
    if match is None:
        fail(f"generated model lacks {function} for shape {shape}")
    return match.group(1).strip().strip('"')


def case_values(model: str, function: str, shape: int) -> list[str]:
    match = re.search(
        rf"when {shape} =>\s+case Member is(?P<body>.*?)\s+end case;",
        function_body(model, function), re.DOTALL,
    )
    if match is None:
        fail(f"generated model lacks {function} block for shape {shape}")
    value = r'"([^"]*)"' if function == "Member_Name" else \
        r"([A-Za-z_][A-Za-z0-9_]*|\d+)"
    pairs = re.findall(
        rf"when\s+(\d+)\s+=>\s+return\s+{value};", match.group("body")
    )
    if [int(number) for number, _ in pairs] != \
            list(range(1, len(pairs) + 1)):
        fail(f"shape {shape} {function} order is not contiguous")
    return [item for _, item in pairs]


def integer_for_shape(model: str, function: str, shape: int) -> int:
    return int(shape_scalar(model, function, shape))


def enum_values(model: str, shape: int) -> list[str]:
    match = re.search(
        rf"when {shape} =>\s+case Index is(?P<body>.*?)\s+end case;",
        function_body(model, "Enumeration_Value"), re.DOTALL,
    )
    if match is None:
        fail(f"generated model lacks enum values for shape {shape}")
    values = [value for _, value in re.findall(
        r'when\s+(\d+)\s+=>\s+return\s+"([^"]*)";', match.group("body")
    )]
    if len(values) != integer_for_shape(model, "Enumeration_Count", shape):
        fail(f"generated enum cardinality changed for shape {shape}")
    return values


def comma_values(value: str) -> list[str]:
    values = value.split(",")
    if any(item == "" or item != item.strip() for item in values):
        fail(f"noncanonical comma list: {value!r}")
    if len(values) != len(set(values)):
        fail(f"duplicate comma-list value: {value!r}")
    return values


def main() -> int:
    lock = CORPORA_LOCK.read_text(encoding="utf-8")
    if f'revision = "{EXPECTED_REVISION}"' not in lock or \
            f'service_model_sha256 = "{EXPECTED_SHA256}"' not in lock:
        fail("pinned botocore model identity changed")

    model = MODEL.read_text(encoding="utf-8")
    expected_scalars = {
        "Method": "Get_Method",
        "Request_URI": "/{Bucket}?object-lock",
        "Response_Code": "200",
        "Input_Shape": "280",
        "Output_Shape": "279",
        "Request_Checksum_Required": "False",
    }
    for function, expected in expected_scalars.items():
        if operation_scalar(model, function) != expected:
            fail(f"generated {function} changed")
    if re.search(
            r'when 279 =>\s+return "ObjectLockConfiguration";',
            function_body(model, "Payload_Member"),
    ) is None:
        fail("generated payload member changed")
    expected_counts = {280: 2, 279: 1, 473: 2, 482: 1, 143: 3}
    if any(integer_for_shape(model, "Member_Count", shape) != count
           for shape, count in expected_counts.items()):
        fail("generated member counts changed")
    if enum_values(model, 474) != ["Enabled"] or \
            enum_values(model, 481) != ["GOVERNANCE", "COMPLIANCE"]:
        fail("generated object-lock enum changed")
    for shape in (141, 718):
        if shape_scalar(model, "Kind", shape) != "Integer_Shape" or any(
                shape_scalar(model, function, shape) != ""
                for function in ("Minimum", "Maximum", "Pattern")):
            fail(f"generated unbounded integer contract changed for {shape}")

    generated = []
    for direction, shape, boundary in (
        ("request", 280, "projected"),
        ("output", 279, "decoded"),
        ("nested", 473, "decoded"),
        ("nested", 482, "decoded"),
        ("nested", 143, "decoded"),
    ):
        names = case_values(model, "Member_Name", shape)
        shapes = case_values(model, "Member_Shape", shape)
        locations = case_values(model, "Location", shape)
        required = case_values(model, "Member_Required", shape)
        for index, name in enumerate(names):
            generated.append(
                (direction, shape, index + 1, name, int(shapes[index]),
                 LOCATION[locations[index]], required[index].lower(), boundary)
            )
    if generated != EXPECTED:
        fail(f"generated operation inventory changed: {generated!r}")

    members = read_tsv(CORPUS / "members.tsv", MEMBER_HEADER)
    manifest = [
        (row["direction"], int(row["shape"]), int(row["ordinal"]),
         row["member"], int(row["member_shape"]), row["wire_location"],
         row["required"], row["current_boundary"])
        for row in members
    ]
    if manifest != EXPECTED:
        fail("manifest does not match the generated inventory")

    vectors = read_tsv(CORPUS / "vectors.tsv", VECTOR_HEADER)
    vector_by_id = {}
    for vector in vectors:
        vector_id = vector["id"]
        if not re.fullmatch(r"GOL-(?:RQ|RS|TR)-\d{3}", vector_id):
            fail(f"noncanonical vector id: {vector_id}")
        if vector_id in vector_by_id:
            fail(f"duplicate vector id: {vector_id}")
        vector_by_id[vector_id] = vector
    member_keys = {f'{row["direction"]}:{row["member"]}' for row in members}
    referenced = set()
    for member in members:
        key = f'{member["direction"]}:{member["member"]}'
        for vector_id in comma_values(member["vector_ids"]):
            if vector_id not in vector_by_id or key not in comma_values(
                    vector_by_id[vector_id]["member_refs"]):
                fail(f"{key}: invalid reciprocal vector {vector_id}")
            referenced.add(vector_id)
    for vector_id, vector in vector_by_id.items():
        refs = comma_values(vector["member_refs"])
        if any(ref != "operation:GetObjectLockConfiguration" and
               ref not in member_keys for ref in refs):
            fail(f"{vector_id}: unknown member reference")
        if vector_id not in referenced and \
                "operation:GetObjectLockConfiguration" not in refs:
            fail(f"{vector_id}: unreachable vector")

    sources = "\n".join(path.read_text(encoding="utf-8") for path in (
        LOW_SPEC, LOW_BODY, LOCK_SPEC, LOCK_BODY,
    ))
    for token in (
        "Prepare_Get_Object_Lock_Configuration",
        "Decode_Get_Object_Lock_Configuration_Response",
        "Execute_Get_Object_Lock_Configuration",
        "Parse_Configuration",
        "Object_Lock_Enabled_Absent, Object_Lock_Enabled",
        "Retention_Mode_Absent, Governance_Retention, Compliance_Retention",
        "Valid_Integer_Text",
    ):
        if token not in sources:
            fail(f"typed implementation lacks {token}")

    print(
        "GetObjectLockConfiguration preparation: 2 request, 1 output, "
        f"6 nested members, exact enums, unbounded integer shapes, "
        f"{len(vectors)} reciprocal vectors"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, UnicodeError, ValueError) as exc:
        print(
            f"GetObjectLockConfiguration verification failed: {exc}",
            file=sys.stderr,
        )
        raise SystemExit(1)
