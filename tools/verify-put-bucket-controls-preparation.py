#!/usr/bin/env python3
"""Verify the pinned five-operation scalar bucket-control PUT family."""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "tests" / "corpora" / "put-bucket-controls"
MODEL = ROOT / "src" / "flyology-object_storage-s3-model.adb"
LOCK = ROOT / "coverage" / "corpora.lock.toml"
EXPECTED_REVISION = "36c34f15391da01cd717c73c0fffa747c9889768"
EXPECTED_SHA256 = "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"

# Persisted shape numbers and public bindings come from the reviewed pinned
# model. They are compatibility evidence, not product capacity policy.
EXPECTED = [
    ("PutBucketAbac", "Put_Bucket_Abac", 523, "/{Bucket}?abac",
     "Prepare_Put_Bucket_Abac", "Execute_Put_Bucket_Abac", "Set_ABAC"),
    ("PutBucketAccelerateConfiguration", "Put_Bucket_Accelerate_Configuration",
     524, "/{Bucket}?accelerate", "Prepare_Put_Bucket_Accelerate_Configuration",
     "Execute_Put_Bucket_Accelerate_Configuration",
     "Set_Accelerate_Configuration"),
    ("PutBucketPolicy", "Put_Bucket_Policy", 539, "/{Bucket}?policy",
     "Prepare_Put_Bucket_Policy", "Execute_Put_Bucket_Policy", "Set_Policy"),
    ("PutBucketRequestPayment", "Put_Bucket_Request_Payment", 541,
     "/{Bucket}?requestPayment", "Prepare_Put_Bucket_Request_Payment",
     "Execute_Put_Bucket_Request_Payment", "Set_Request_Payment"),
    ("PutPublicAccessBlock", "Put_Public_Access_Block", 559,
     "/{Bucket}?publicAccessBlock", "Prepare_Put_Public_Access_Block",
     "Execute_Put_Public_Access_Block", "Set_Public_Access_Block"),
]

EXPECTED_MEMBERS = [
    ("PutBucketAbac", "request", 523, 1, "Bucket", 60, "uri-label", "true"),
    ("PutBucketAbac", "request", 523, 2, "ContentMD5", 111, "header", "false"),
    ("PutBucketAbac", "request", 523, 3, "ChecksumAlgorithm", 77, "header", "false"),
    ("PutBucketAbac", "request", 523, 4, "ExpectedBucketOwner", 15, "header", "false"),
    ("PutBucketAbac", "request", 523, 5, "AbacStatus", 1, "body", "true"),
    ("PutBucketAbac", "nested", 1, 1, "Status", 48, "body", "false"),
    ("PutBucketAccelerateConfiguration", "request", 524, 1, "Bucket", 60, "uri-label", "true"),
    ("PutBucketAccelerateConfiguration", "request", 524, 2, "AccelerateConfiguration", 7, "body", "true"),
    ("PutBucketAccelerateConfiguration", "request", 524, 3, "ExpectedBucketOwner", 15, "header", "false"),
    ("PutBucketAccelerateConfiguration", "request", 524, 4, "ChecksumAlgorithm", 77, "header", "false"),
    ("PutBucketAccelerateConfiguration", "nested", 7, 1, "Status", 49, "body", "false"),
    ("PutBucketPolicy", "request", 539, 1, "Bucket", 60, "uri-label", "true"),
    ("PutBucketPolicy", "request", 539, 2, "ContentMD5", 111, "header", "false"),
    ("PutBucketPolicy", "request", 539, 3, "ChecksumAlgorithm", 77, "header", "false"),
    ("PutBucketPolicy", "request", 539, 4, "ConfirmRemoveSelfBucketAccess", 106, "header", "false"),
    ("PutBucketPolicy", "request", 539, 5, "Policy", 515, "body", "true"),
    ("PutBucketPolicy", "request", 539, 6, "ExpectedBucketOwner", 15, "header", "false"),
    ("PutBucketRequestPayment", "request", 541, 1, "Bucket", 60, "uri-label", "true"),
    ("PutBucketRequestPayment", "request", 541, 2, "ContentMD5", 111, "header", "false"),
    ("PutBucketRequestPayment", "request", 541, 3, "ChecksumAlgorithm", 77, "header", "false"),
    ("PutBucketRequestPayment", "request", 541, 4, "RequestPaymentConfiguration", 600, "body", "true"),
    ("PutBucketRequestPayment", "request", 541, 5, "ExpectedBucketOwner", 15, "header", "false"),
    ("PutBucketRequestPayment", "nested", 600, 1, "Payer", 513, "body", "true"),
    ("PutPublicAccessBlock", "request", 559, 1, "Bucket", 60, "uri-label", "true"),
    ("PutPublicAccessBlock", "request", 559, 2, "ContentMD5", 111, "header", "false"),
    ("PutPublicAccessBlock", "request", 559, 3, "ChecksumAlgorithm", 77, "header", "false"),
    ("PutPublicAccessBlock", "request", 559, 4, "PublicAccessBlockConfiguration", 522, "body", "true"),
    ("PutPublicAccessBlock", "request", 559, 5, "ExpectedBucketOwner", 15, "header", "false"),
    ("PutPublicAccessBlock", "nested", 522, 1, "BlockPublicAcls", 655, "body", "false"),
    ("PutPublicAccessBlock", "nested", 522, 2, "IgnorePublicAcls", 655, "body", "false"),
    ("PutPublicAccessBlock", "nested", 522, 3, "BlockPublicPolicy", 655, "body", "false"),
    ("PutPublicAccessBlock", "nested", 522, 4, "RestrictPublicBuckets", 655, "body", "false"),
]

# Exact external domains from the pinned model.
EXPECTED_ENUMS = {
    48: ["Enabled", "Disabled"],
    49: ["Enabled", "Suspended"],
    77: ["CRC32", "CRC32C", "SHA1", "SHA256", "CRC64NVME", "SHA512",
         "MD5", "XXHASH64", "XXHASH3", "XXHASH128"],
    513: ["Requester", "BucketOwner"],
}
OP_HEADER = ["operation", "input_shape", "request_uri", "member_count",
             "prepare", "execute", "high_level", "vector_ids"]
MEMBER_HEADER = ["operation", "direction", "shape", "ordinal", "member",
                 "member_shape", "wire_location", "required", "vector_ids"]
VECTOR_HEADER = ["id", "direction", "layer", "category", "operation_refs",
                 "stimulus", "expected_contract"]
LOCATION = {"URI_Location": "uri-label", "Header_Location": "header",
            "Body_Location": "body"}


def fail(message: str) -> None:
    raise ValueError(message)


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
        fail(f"{path}: empty, surplus, or missing field")
    return rows


def comma_values(value: str) -> list[str]:
    values = value.split(",")
    if any(item != item.strip() or item == "" for item in values) or \
            len(values) != len(set(values)):
        fail(f"noncanonical comma list: {value!r}")
    return values


def function_body(model: str, function: str) -> str:
    match = re.search(rf"   function {re.escape(function)}(?=\s*\()", model)
    if match is None:
        fail(f"generated model has no {function}")
    tail = model[match.end():]
    return tail.split(f"end {function};", 1)[0]


def scalar(model: str, function: str, key: str, operation: bool = False) -> str:
    label = f"{key}_Operation" if operation else key
    match = re.search(rf"when\s+{re.escape(label)}\s*=>\s*return\s+([^;]+);",
                      function_body(model, function))
    if match is None:
        fail(f"generated model lacks {function} for {label}")
    return match.group(1).strip().strip('"')


def member_values(model: str, function: str, shape: int) -> list[str]:
    block = re.search(rf"when {shape} =>\s+case Member is(?P<body>.*?)\s+end case;",
                      function_body(model, function), re.DOTALL)
    if block is None:
        fail(f"generated model lacks {function} shape {shape}")
    pattern = (r'when\s+(\d+)\s+=>\s+return\s+"([^"]+)";' if function == "Member_Name"
               else r"when\s+(\d+)\s+=>\s+return\s+([A-Za-z0-9_]+);")
    pairs = re.findall(pattern, block.group("body"))
    if [int(number) for number, _ in pairs] != list(range(1, len(pairs) + 1)):
        fail(f"shape {shape} {function} ordinals changed")
    return [value for _, value in pairs]


def enum_values(model: str, shape: int) -> list[str]:
    count = int(scalar(model, "Enumeration_Count", str(shape)))
    block = re.search(rf"when {shape} =>\s+case Index is(?P<body>.*?)\s+end case;",
                      function_body(model, "Enumeration_Value"), re.DOTALL)
    pairs = re.findall(r'when\s+(\d+)\s+=>\s+return\s+"([^"]+)";',
                       block.group("body") if block else "")
    if [int(number) for number, _ in pairs] != list(range(1, count + 1)):
        fail(f"shape {shape} enum ordinals changed")
    return [value for _, value in pairs]


def main() -> int:
    lock = LOCK.read_text(encoding="utf-8")
    if f'revision = "{EXPECTED_REVISION}"' not in lock or \
            f'service_model_sha256 = "{EXPECTED_SHA256}"' not in lock:
        fail("pinned botocore authority changed")
    model = MODEL.read_text(encoding="utf-8")
    operations = read_tsv(CORPUS / "operations.tsv", OP_HEADER)
    members = read_tsv(CORPUS / "members.tsv", MEMBER_HEADER)
    vectors = read_tsv(CORPUS / "vectors.tsv", VECTOR_HEADER)
    if [row["operation"] for row in operations] != [item[0] for item in EXPECTED]:
        fail("operation inventory or order changed")
    expected_rows = [tuple(str(value) for value in row) for row in EXPECTED_MEMBERS]
    if [tuple(row[name] for name in MEMBER_HEADER[:-1]) for row in members] != expected_rows:
        fail("member inventory does not match the reviewed 32-member graph")
    texts = [path.read_text(encoding="utf-8") for path in
             [ROOT / "src/flyology-object_storage-client-low_level.ads",
              ROOT / "src/flyology-object_storage-client-low_level.adb",
              ROOT / "src/flyology-object_storage-client-buckets.ads",
              ROOT / "src/flyology-object_storage-client-buckets.adb"]]
    by_operation = {name: [row for row in expected_rows if row[0] == name]
                    for name, *_ in EXPECTED}
    for row, expected in zip(operations, EXPECTED, strict=True):
        name, stem, shape, uri, prepare, execute, high = expected
        if scalar(model, "Operation_Name", stem, True) != name or \
                scalar(model, "Method", stem, True) != "Put_Method" or \
                scalar(model, "Request_URI", stem, True) != uri or \
                scalar(model, "Response_Code", stem, True) != "200" or \
                int(scalar(model, "Input_Shape", stem, True)) != shape or \
                scalar(model, "Output_Shape", stem, True) != "0":
            fail(f"{name}: generated operation metadata changed")
        if [row[field] for field in OP_HEADER[:-1]] != [name, str(shape), uri,
                str(len(by_operation[name])), prepare, execute, high]:
            fail(f"{name}: operation manifest drift")
        for symbol in [prepare, execute, high]:
            if sum(bool(re.search(rf"\bfunction\s+{re.escape(symbol)}\b", text))
                   for text in texts) != 2:
                fail(f"{name}: {symbol} is not declared and implemented exactly once")
    for shape in sorted({int(row[2]) for row in expected_rows}):
        rows = [row for row in expected_rows if int(row[2]) == shape]
        if int(scalar(model, "Member_Count", str(shape))) != len(rows) or \
                member_values(model, "Member_Name", shape) != [row[4] for row in rows] or \
                member_values(model, "Member_Shape", shape) != [row[5] for row in rows] or \
                [LOCATION[value] for value in member_values(model, "Location", shape)] != [row[6] for row in rows] or \
                [value.lower() for value in member_values(model, "Member_Required", shape)] != [row[7] for row in rows]:
            fail(f"shape {shape}: generated member metadata changed")
    for shape, values in EXPECTED_ENUMS.items():
        if enum_values(model, shape) != values:
            fail(f"shape {shape}: enum domain changed")
    operation_by_name = {row["operation"]: row for row in operations}
    vector_by_id = {row["id"]: row for row in vectors}
    if len(vector_by_id) != len(vectors):
        fail("duplicate vector id")
    for vector_id, vector in vector_by_id.items():
        if not re.fullmatch(r"PBC-(?:MD|RQ|RS|TR)-\d{3}", vector_id):
            fail(f"noncanonical vector id: {vector_id}")
        for operation in comma_values(vector["operation_refs"]):
            if operation not in operation_by_name or vector_id not in \
                    comma_values(operation_by_name[operation]["vector_ids"]):
                fail(f"{vector_id}: bad reciprocal operation {operation}")
    for operation, row in operation_by_name.items():
        for vector_id in comma_values(row["vector_ids"]):
            if vector_id not in vector_by_id or operation not in \
                    comma_values(vector_by_id[vector_id]["operation_refs"]):
                fail(f"{operation}: bad reciprocal vector {vector_id}")
    for member in members:
        for vector_id in comma_values(member["vector_ids"]):
            if vector_id not in vector_by_id or member["operation"] not in \
                    comma_values(vector_by_id[vector_id]["operation_refs"]):
                fail(f"{member['operation']}:{member['member']}: bad vector")
    print("scalar bucket-control PUT preparation: 5 operations, 32 request/nested "
          f"members, 4 exact enum domains, {len(vectors)} reciprocal vectors; "
          "pinned model and exact public APIs match")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AttributeError, KeyError, OSError, UnicodeError, ValueError) as exc:
        print(f"scalar bucket-control PUT verification failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
