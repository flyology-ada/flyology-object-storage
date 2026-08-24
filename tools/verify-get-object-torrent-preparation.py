#!/usr/bin/env python3
"""Verify the pinned GetObjectTorrent model inventory and corpus graph."""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "tests" / "corpora" / "get-object-torrent"
MODEL = ROOT / "src" / "flyology-object_storage-s3-model.adb"
LOW_SPEC = ROOT / "src" / "flyology-object_storage-client-low_level.ads"
LOW_BODY = ROOT / "src" / "flyology-object_storage-client-low_level.adb"
LOCK = ROOT / "coverage" / "corpora.lock.toml"

# These values identify the reviewed upstream model. A change is a model
# upgrade and requires regenerating and reviewing the complete inventory.
EXPECTED_REVISION = "36c34f15391da01cd717c73c0fffa747c9889768"
EXPECTED_SHA256 = "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
EXPECTED_MEMBERS = [
    ("request", 289, 1, "Bucket", 60, "uri-label", "true", "projected"),
    ("request", 289, 2, "Key", 471, "uri-label", "true", "projected"),
    ("request", 289, 3, "RequestPayer", 599, "header", "false", "projected"),
    ("request", 289, 4, "ExpectedBucketOwner", 15, "header", "false", "projected"),
    ("output", 288, 1, "Body", 46, "body", "false", "streamed"),
    ("output", 288, 2, "RequestCharged", 598, "header", "false", "projected"),
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
        r"when Get_Object_Torrent_Operation =>\s+return\s+([^;]+);",
        function_body(model, function),
    )
    if match is None:
        fail(f"generated model lacks GetObjectTorrent {function}")
    return match.group(1).strip().strip('"')


def shape_block(model: str, function: str, shape: int) -> str:
    match = re.search(
        rf"when {shape} =>\s+case Member is(?P<body>.*?)\s+end case;",
        function_body(model, function),
        re.DOTALL,
    )
    if match is None:
        fail(f"generated model lacks {function} block for shape {shape}")
    return match.group("body")


def member_values(model: str, function: str, shape: int) -> list[str]:
    if function == "Member_Name":
        value = r'"([^"]*)"'
    else:
        value = r"([A-Za-z_][A-Za-z0-9_]*|\d+)"
    pairs = re.findall(
        rf"when\s+(\d+)\s+=>\s+return\s+{value};",
        shape_block(model, function, shape),
    )
    ordinals = [int(number) for number, _ in pairs]
    if ordinals != list(range(1, len(pairs) + 1)):
        fail(f"shape {shape} {function} order is not contiguous")
    return [item for _, item in pairs]


def member_count(model: str, shape: int) -> int:
    match = re.search(
        rf"when\s+{shape}\s+=>\s+return\s+(\d+);",
        function_body(model, "Member_Count"),
    )
    if match is None:
        fail(f"generated model lacks member count for shape {shape}")
    return int(match.group(1))


def enumeration_values(model: str, shape: int) -> list[str]:
    count_match = re.search(
        rf"when\s+{shape}\s+=>\s+return\s+(\d+);",
        function_body(model, "Enumeration_Count"),
    )
    if count_match is None:
        fail(f"generated model lacks enumeration count for shape {shape}")
    block_match = re.search(
        rf"when {shape} =>\s+case Index is(?P<body>.*?)\s+end case;",
        function_body(model, "Enumeration_Value"),
        re.DOTALL,
    )
    if block_match is None:
        fail(f"generated model lacks enumeration values for shape {shape}")
    pairs = re.findall(
        r'when\s+(\d+)\s+=>\s+return\s+"([^"]*)";',
        block_match.group("body"),
    )
    values = [value for _, value in pairs]
    if len(values) != int(count_match.group(1)):
        fail(f"generated enumeration cardinality changed for shape {shape}")
    return values


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
    if operation_scalar(model, "Request_URI") != "/{Bucket}/{Key+}?torrent":
        fail("generated request URI changed")
    if operation_scalar(model, "Response_Code") != "200":
        fail("generated success status changed")
    if operation_scalar(model, "Input_Shape") != "289" or \
            operation_scalar(model, "Output_Shape") != "288":
        fail("generated operation shapes changed")
    if operation_scalar(model, "Method") != "Get_Method":
        fail("generated HTTP method changed")
    if member_count(model, 289) != 4 or member_count(model, 288) != 2:
        fail("generated member counts changed")

    generated: list[tuple[str, int, int, str, int, str, str, str]] = []
    for direction, shape in (("request", 289), ("output", 288)):
        names = member_values(model, "Member_Name", shape)
        shapes = member_values(model, "Member_Shape", shape)
        locations = member_values(model, "Location", shape)
        required = member_values(model, "Member_Required", shape)
        streaming = member_values(model, "Member_Streaming", shape)
        for index, name in enumerate(names):
            boundary = "streamed" if streaming[index] == "True" else "projected"
            generated.append(
                (direction, shape, index + 1, name, int(shapes[index]),
                 LOCATION[locations[index]], required[index].lower(), boundary)
            )
    if generated != EXPECTED_MEMBERS:
        fail(f"generated operation inventory changed: {generated!r}")
    if operation_scalar(model, "Request_Checksum_Required") != "False":
        fail("generated request checksum requirement changed")
    if enumeration_values(model, 598) != ["requester"] or \
            enumeration_values(model, 599) != ["requester"]:
        fail("generated payer or charged enumeration changed")
    if re.search(r"when 288 =>\s+return \"Body\";",
                 function_body(model, "Payload_Member")) is None:
        fail("generated streaming payload member changed")

    members = read_tsv(CORPUS / "members.tsv", MEMBER_HEADER)
    manifest = [
        (row["direction"], int(row["shape"]), int(row["ordinal"]),
         row["member"], int(row["member_shape"]), row["wire_location"],
         row["required"], row["current_boundary"])
        for row in members
    ]
    if manifest != EXPECTED_MEMBERS:
        fail("manifest does not match the generated inventory")

    vectors = read_tsv(CORPUS / "vectors.tsv", VECTOR_HEADER)
    vector_by_id: dict[str, dict[str, str]] = {}
    for vector in vectors:
        vector_id = vector["id"]
        if not re.fullmatch(r"GOT-(?:RQ|RS|TR)-\d{3}", vector_id):
            fail(f"noncanonical vector id: {vector_id}")
        if vector_id in vector_by_id:
            fail(f"duplicate vector id: {vector_id}")
        vector_by_id[vector_id] = vector

    member_keys = {f'{row["direction"]}:{row["member"]}' for row in members}
    referenced: set[str] = set()
    for member in members:
        key = f'{member["direction"]}:{member["member"]}'
        for vector_id in comma_values(member["vector_ids"]):
            vector = vector_by_id.get(vector_id)
            if vector is None:
                fail(f"{key}: unknown vector {vector_id}")
            if key not in comma_values(vector["member_refs"]):
                fail(f"{key}: {vector_id} lacks reciprocal reference")
            referenced.add(vector_id)
    for vector_id, vector in vector_by_id.items():
        refs = comma_values(vector["member_refs"])
        for reference in refs:
            if reference != "operation:GetObjectTorrent" and \
                    reference not in member_keys:
                fail(f"{vector_id}: unknown member reference {reference}")
        if vector_id not in referenced and \
                "operation:GetObjectTorrent" not in refs:
            fail(f"{vector_id}: unreachable vector")

    spec = LOW_SPEC.read_text(encoding="utf-8")
    body = LOW_BODY.read_text(encoding="utf-8")
    for token in (
        "type Get_Object_Torrent_Parameters is record",
        "type Get_Object_Torrent_Outcome",
    ):
        if token not in spec:
            fail(f"typed client surface lacks {token}")
    for token in (
        "function Prepare_Get_Object_Torrent",
        "function Execute_Get_Object_Torrent",
        "function Decode_Get_Object_Torrent_Response_Head",
    ):
        if token not in spec or token not in body:
            fail(f"typed client surface lacks {token}")

    print(
        "GetObjectTorrent preparation: 4 request members, 2 output members, "
        f"{len(vectors)} reciprocal contract vectors; pinned model matches"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, UnicodeError, ValueError) as exc:
        print(
            f"GetObjectTorrent preparation verification failed: {exc}",
            file=sys.stderr,
        )
        raise SystemExit(1)
