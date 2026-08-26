#!/usr/bin/env python3
"""Verify GetObjectAcl model inventory and reciprocal corpus graph."""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "tests/corpora/get-object-acl"
MODEL = ROOT / "src/flyology-object_storage-s3-model.adb"
LOCK = ROOT / "coverage/corpora.lock.toml"
SOURCES = (
    ROOT / "src/flyology-object_storage-client-low_level.ads",
    ROOT / "src/flyology-object_storage-client-low_level.adb",
    ROOT / "src/flyology-object_storage-client-objects.ads",
    ROOT / "src/flyology-object_storage-client-objects.adb",
    ROOT / "src/flyology-object_storage-s3-acl.ads",
    ROOT / "src/flyology-object_storage-s3-acl.adb",
)
REVISION = "36c34f15391da01cd717c73c0fffa747c9889768"
SHA256 = "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
EXPECTED = [
    ("request", 271, 1, "Bucket", 60, "uri-label", "true", "projected"),
    ("request", 271, 2, "Key", 471, "uri-label", "true", "projected"),
    ("request", 271, 3, "VersionId", 492, "query", "false", "projected"),
    ("request", 271, 4, "RequestPayer", 599, "header", "false", "projected"),
    ("request", 271, 5, "ExpectedBucketOwner", 15, "header", "false", "projected"),
    ("output", 270, 1, "Owner", 499, "body", "false", "decoded"),
    ("output", 270, 2, "Grants", 300, "body", "false", "decoded"),
    ("output", 270, 3, "RequestCharged", 598, "header", "false", "decoded"),
    ("nested", 499, 1, "DisplayName", 182, "body", "false", "decoded"),
    ("nested", 499, 2, "ID", 308, "body", "false", "decoded"),
    ("nested", 293, 1, "Grantee", 299, "body", "false", "decoded"),
    ("nested", 293, 2, "Permission", 514, "body", "false", "decoded"),
    ("nested", 299, 1, "DisplayName", 182, "body", "false", "decoded"),
    ("nested", 299, 2, "EmailAddress", 184, "body", "false", "decoded"),
    ("nested", 299, 3, "ID", 308, "body", "false", "decoded"),
    ("nested", 299, 4, "Type", 696, "body", "true", "decoded"),
    ("nested", 299, 5, "URI", 697, "body", "false", "decoded"),
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
    match = re.search(r"when Get_Object_Acl_Operation =>\s+return\s+([^;]+);",
                      function_body(model, function))
    if match is None:
        fail(f"GetObjectAcl lacks {function}")
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
    scalars = {"Method": "Get_Method", "Request_URI": "/{Bucket}/{Key+}?acl",
               "Response_Code": "200", "Input_Shape": "271",
               "Output_Shape": "270", "Request_Checksum_Required": "False"}
    for function, expected in scalars.items():
        if operation_scalar(model, function) != expected:
            fail(f"generated {function} changed")
    if shape_scalar(model, "Kind", 300) != "List_Shape" or \
            shape_scalar(model, "List_Member_Shape", 300) != "293" or \
            shape_scalar(model, "Is_Flattened", 300) != "False":
        fail("generated nonflattened Grant list changed")
    enums = {514: ["FULL_CONTROL", "WRITE", "WRITE_ACP", "READ", "READ_ACP"],
             696: ["CanonicalUser", "AmazonCustomerByEmail", "Group"],
             598: ["requester"], 599: ["requester"]}
    for shape, expected in enums.items():
        if enum_values(model, shape) != expected:
            fail(f"generated enum shape {shape} changed")

    generated = []
    for direction, shape, boundary in (
            ("request", 271, "projected"), ("output", 270, "decoded"),
            ("nested", 499, "decoded"), ("nested", 293, "decoded"),
            ("nested", 299, "decoded")):
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
    if case_values(model, "Member_XML_Attribute", 299) != \
            ["False", "False", "False", "True", "False"]:
        fail("generated grantee attribute placement changed")

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
    member_keys = {f'{row["direction"]}:{row["shape"]}:{row["member"]}'
                   for row in member_rows}
    reached = set()
    for row in member_rows:
        key = f'{row["direction"]}:{row["shape"]}:{row["member"]}'
        for vector_id in row["vector_ids"].split(","):
            if vector_id not in vector_by_id or key not in \
                    vector_by_id[vector_id]["member_refs"].split(","):
                fail(f"{key}: invalid reciprocal vector {vector_id}")
            reached.add(vector_id)
    for vector in vectors:
        refs = vector["member_refs"].split(",")
        if any(ref != "operation:GetObjectAcl" and ref not in member_keys
               for ref in refs):
            fail(f'{vector["id"]}: unknown member reference')
        if vector["id"] not in reached and "operation:GetObjectAcl" not in refs:
            fail(f'{vector["id"]}: unreachable vector')
    source = "\n".join(path.read_text(encoding="utf-8") for path in SOURCES)
    for token in ("Prepare_Get_Object_ACL", "Decode_Get_Object_ACL_Response",
                  "Execute_Get_Object_ACL", "Get_Object_Acl_Operation",
                  "Get_Object_ACL_Operation",
                  "Get_Object_ACL_Response_Available",
                  "procedure Get_Object_ACL", "procedure Get_ACL",
                  "function Get_ACL",
                  "Request_Charged", "ACL.Parse", "Grant_Vectors"):
        if token not in source:
            fail(f"typed implementation lacks {token}")
    print("GetObjectAcl preparation: 17 modeled members, one nonflattened "
          f"list, 10 exact enum values, {len(vectors)} vectors")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, UnicodeError, ValueError) as exc:
        print(f"GetObjectAcl verification failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
