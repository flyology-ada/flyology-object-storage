#!/usr/bin/env python3
"""Verify the pinned GetObjectLegalHold model inventory and corpus graph."""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "tests" / "corpora" / "get-object-legal-hold"
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
    ("request", 278, 1, "Bucket", 60, "uri-label", "true", "projected"),
    ("request", 278, 2, "Key", 471, "uri-label", "true", "projected"),
    ("request", 278, 3, "VersionId", 492, "query", "false", "projected"),
    ("request", 278, 4, "RequestPayer", 599, "header", "false", "projected"),
    ("request", 278, 5, "ExpectedBucketOwner", 15, "header", "false", "projected"),
    ("output", 277, 1, "LegalHold", 476, "body", "false", "decoded"),
    ("nested", 476, 1, "Status", 477, "body", "false", "decoded"),
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
    "URI_Location": "uri-label",
    "Query_Location": "query",
    "Header_Location": "header",
    "Body_Location": "body",
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
        r"when Get_Object_Legal_Hold_Operation =>\s+return\s+([^;]+);",
        function_body(model, function),
    )
    if match is None:
        fail(f"generated model lacks GetObjectLegalHold {function}")
    return match.group(1).strip().strip('"')


def case_values(model: str, function: str, shape: int) -> list[str]:
    match = re.search(
        rf"when {shape} =>\s+case Member is(?P<body>.*?)\s+end case;",
        function_body(model, function),
        re.DOTALL,
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


def scalar_for_shape(model: str, function: str, shape: int) -> int:
    match = re.search(
        rf"when\s+{shape}\s+=>\s+return\s+(\d+);",
        function_body(model, function),
    )
    if match is None:
        fail(f"generated model lacks {function} for shape {shape}")
    return int(match.group(1))


def enum_values(model: str, shape: int) -> list[str]:
    match = re.search(
        rf"when {shape} =>\s+case Index is(?P<body>.*?)\s+end case;",
        function_body(model, "Enumeration_Value"), re.DOTALL,
    )
    if match is None:
        fail(f"generated model lacks enum values for shape {shape}")
    values = [value for _, value in re.findall(
        r'when\s+(\d+)\s+=>\s+return\s+"([^"]*)";',
        match.group("body"),
    )]
    if len(values) != scalar_for_shape(model, "Enumeration_Count", shape):
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
        "Request_URI": "/{Bucket}/{Key+}?legal-hold",
        "Response_Code": "200",
        "Input_Shape": "278",
        "Output_Shape": "277",
        "Request_Checksum_Required": "False",
    }
    for function, expected in expected_scalars.items():
        if operation_scalar(model, function) != expected:
            fail(f"generated {function} changed")
    if re.search(
            r'when 277 =>\s+return "LegalHold";',
            function_body(model, "Payload_Member"),
    ) is None:
        fail("generated payload member changed")
    if scalar_for_shape(model, "Member_Count", 278) != 5 or \
            scalar_for_shape(model, "Member_Count", 277) != 1 or \
            scalar_for_shape(model, "Member_Count", 476) != 1:
        fail("generated member counts changed")
    if enum_values(model, 599) != ["requester"] or \
            enum_values(model, 477) != ["ON", "OFF"]:
        fail("generated payer or legal-hold enum changed")

    generated = []
    for direction, shape, boundary in (
        ("request", 278, "projected"),
        ("output", 277, "decoded"),
        ("nested", 476, "decoded"),
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
        if not re.fullmatch(r"GOH-(?:RQ|RS|TR)-\d{3}", vector_id):
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
        if any(ref != "operation:GetObjectLegalHold" and ref not in member_keys
               for ref in refs):
            fail(f"{vector_id}: unknown member reference")
        if vector_id not in referenced and \
                "operation:GetObjectLegalHold" not in refs:
            fail(f"{vector_id}: unreachable vector")

    sources = "\n".join(path.read_text(encoding="utf-8") for path in (
        LOW_SPEC, LOW_BODY, LOCK_SPEC, LOCK_BODY,
    ))
    for token in (
        "Prepare_Get_Object_Legal_Hold",
        "Decode_Get_Object_Legal_Hold_Response",
        "Execute_Get_Object_Legal_Hold",
        "Parse_Legal_Hold",
        "Legal_Hold_Status_Absent, Legal_Hold_On, Legal_Hold_Off",
    ):
        if token not in sources:
            fail(f"typed implementation lacks {token}")

    print(
        "GetObjectLegalHold preparation: 5 request, 1 output, 1 nested "
        f"member, 2 exact enum domains, {len(vectors)} reciprocal vectors"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, UnicodeError, ValueError) as exc:
        print(
            f"GetObjectLegalHold verification failed: {exc}",
            file=sys.stderr,
        )
        raise SystemExit(1)
