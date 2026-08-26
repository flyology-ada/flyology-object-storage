#!/usr/bin/env python3
"""Verify the pinned bodyless bucket-configuration DELETE family."""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "tests" / "corpora" / "delete-bucket-configurations"
MODEL = ROOT / "src" / "flyology-object_storage-s3-model.adb"
LOW_SPEC = ROOT / "src" / "flyology-object_storage-client-low_level.ads"
LOW_BODY = ROOT / "src" / "flyology-object_storage-client-low_level.adb"
HIGH_SPEC = ROOT / "src" / "flyology-object_storage-client-buckets.ads"
HIGH_BODY = ROOT / "src" / "flyology-object_storage-client-buckets.adb"
LOCK = ROOT / "coverage" / "corpora.lock.toml"
EXPECTED_REVISION = "36c34f15391da01cd717c73c0fffa747c9889768"
EXPECTED_SHA256 = "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"

# Operation, generated enum stem, shape, URI, whether Id is required,
# low-level preparer, low-level executor, and convenience call.
EXPECTED = [
    ("DeleteBucketAnalyticsConfiguration", "Delete_Bucket_Analytics_Configuration", 145,
     "/{Bucket}?analytics", True, "Prepare_Delete_Bucket_Analytics_Configuration",
     "Execute_Delete_Bucket_Analytics_Configuration", "Delete_Analytics_Configuration"),
    ("DeleteBucketEncryption", "Delete_Bucket_Encryption", 147,
     "/{Bucket}?encryption", False, "Prepare_Delete_Bucket_Encryption",
     "Execute_Delete_Bucket_Encryption", "Delete_Encryption"),
    ("DeleteBucketIntelligentTieringConfiguration",
     "Delete_Bucket_Intelligent_Tiering_Configuration", 148,
     "/{Bucket}?intelligent-tiering", True,
     "Prepare_Delete_Bucket_Intelligent_Tiering_Configuration",
     "Execute_Delete_Bucket_Intelligent_Tiering_Configuration",
     "Delete_Intelligent_Tiering_Configuration"),
    ("DeleteBucketInventoryConfiguration", "Delete_Bucket_Inventory_Configuration", 149,
     "/{Bucket}?inventory", True, "Prepare_Delete_Bucket_Inventory_Configuration",
     "Execute_Delete_Bucket_Inventory_Configuration", "Delete_Inventory_Configuration"),
    ("DeleteBucketLifecycle", "Delete_Bucket_Lifecycle", 150,
     "/{Bucket}?lifecycle", False, "Prepare_Delete_Bucket_Lifecycle",
     "Execute_Delete_Bucket_Lifecycle", "Delete_Lifecycle"),
    ("DeleteBucketMetadataConfiguration", "Delete_Bucket_Metadata_Configuration", 151,
     "/{Bucket}?metadataConfiguration", False,
     "Prepare_Delete_Bucket_Metadata_Configuration",
     "Execute_Delete_Bucket_Metadata_Configuration", "Delete_Metadata_Configuration"),
    ("DeleteBucketMetadataTableConfiguration",
     "Delete_Bucket_Metadata_Table_Configuration", 152,
     "/{Bucket}?metadataTable", False,
     "Prepare_Delete_Bucket_Metadata_Table_Configuration",
     "Execute_Delete_Bucket_Metadata_Table_Configuration",
     "Delete_Metadata_Table_Configuration"),
    ("DeleteBucketMetricsConfiguration", "Delete_Bucket_Metrics_Configuration", 153,
     "/{Bucket}?metrics", True, "Prepare_Delete_Bucket_Metrics_Configuration",
     "Execute_Delete_Bucket_Metrics_Configuration", "Delete_Metrics_Configuration"),
    ("DeleteBucketOwnershipControls", "Delete_Bucket_Ownership_Controls", 154,
     "/{Bucket}?ownershipControls", False,
     "Prepare_Delete_Bucket_Ownership_Controls",
     "Execute_Delete_Bucket_Ownership_Controls", "Delete_Ownership_Controls"),
    ("DeleteBucketPolicy", "Delete_Bucket_Policy", 155,
     "/{Bucket}?policy", False, "Prepare_Delete_Bucket_Policy",
     "Execute_Delete_Bucket_Policy", "Delete_Policy"),
    ("DeleteBucketReplication", "Delete_Bucket_Replication", 156,
     "/{Bucket}?replication", False, "Prepare_Delete_Bucket_Replication",
     "Execute_Delete_Bucket_Replication", "Delete_Replication"),
    ("DeleteBucketWebsite", "Delete_Bucket_Website", 159,
     "/{Bucket}?website", False, "Prepare_Delete_Bucket_Website",
     "Execute_Delete_Bucket_Website", "Delete_Website"),
    ("DeletePublicAccessBlock", "Delete_Public_Access_Block", 174,
     "/{Bucket}?publicAccessBlock", False, "Prepare_Delete_Public_Access_Block",
     "Execute_Delete_Public_Access_Block", "Delete_Public_Access_Block"),
]

OP_HEADER = [
    "operation", "input_shape", "request_uri", "identifier_required",
    "member_count", "prepare", "execute", "high_level", "vector_ids",
]
MEMBER_HEADER = [
    "operation", "shape", "ordinal", "member", "wire_location", "required",
    "vector_ids",
]
VECTOR_HEADER = [
    "id", "direction", "layer", "category", "operation_refs", "stimulus",
    "expected_contract",
]
LOCATION = {
    "Bucket": "URI_Location",
    "Id": "Query_Location",
    "ExpectedBucketOwner": "Header_Location",
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


def comma_values(value: str) -> list[str]:
    values = value.split(",")
    if any(item == "" or item != item.strip() for item in values):
        fail(f"noncanonical comma list: {value!r}")
    if len(values) != len(set(values)):
        fail(f"duplicate comma-list value: {value!r}")
    return values


def function_body(model: str, function: str) -> str:
    match = re.search(rf"   function {re.escape(function)}(?=\s*\()", model)
    if match is None:
        fail(f"generated model has no {function}")
    tail = model[match.end():]
    marker = f"end {function};"
    if marker not in tail:
        fail(f"generated model has no end for {function}")
    return tail.split(marker, 1)[0]


def operation_scalar(model: str, function: str, enum_stem: str) -> str:
    match = re.search(
        rf"when {re.escape(enum_stem)}_Operation =>\s+return\s+([^;]+);",
        function_body(model, function),
    )
    if match is None:
        fail(f"generated model lacks {function} for {enum_stem}")
    return match.group(1).strip().strip('"')


def member_values(model: str, function: str, shape: int) -> list[str]:
    block = re.search(
        rf"when {shape} =>\s+case Member is(?P<body>.*?)\s+end case;",
        function_body(model, function), re.DOTALL,
    )
    if block is None:
        fail(f"generated model lacks {function} shape {shape}")
    if function == "Member_Name":
        pattern = r'when\s+(\d+)\s+=>\s+return\s+"([^"]+)";'
    elif function == "Member_Required":
        pattern = r"when\s+(\d+)\s+=>\s+return\s+(True|False);"
    else:
        pattern = r"when\s+(\d+)\s+=>\s+return\s+([A-Za-z_]+);"
    pairs = re.findall(pattern, block.group("body"))
    if [int(number) for number, _ in pairs] != list(range(1, len(pairs) + 1)):
        fail(f"shape {shape} {function} ordinals are not contiguous")
    return [value for _, value in pairs]


def member_count(model: str, shape: int) -> int:
    match = re.search(
        rf"when\s+{shape}\s+=>\s+return\s+(\d+);",
        function_body(model, "Member_Count"),
    )
    if match is None:
        fail(f"generated model lacks member count for shape {shape}")
    return int(match.group(1))


def main() -> int:
    lock = LOCK.read_text(encoding="utf-8")
    if f'revision = "{EXPECTED_REVISION}"' not in lock:
        fail("pinned botocore revision changed")
    if f'service_model_sha256 = "{EXPECTED_SHA256}"' not in lock:
        fail("pinned botocore service hash changed")

    model = MODEL.read_text(encoding="utf-8")
    operations = read_tsv(CORPUS / "operations.tsv", OP_HEADER)
    members = read_tsv(CORPUS / "members.tsv", MEMBER_HEADER)
    vectors = read_tsv(CORPUS / "vectors.tsv", VECTOR_HEADER)
    if [row["operation"] for row in operations] != [item[0] for item in EXPECTED]:
        fail("operation inventory or order changed")

    texts = {
        "low-level specification": LOW_SPEC.read_text(encoding="utf-8"),
        "low-level body": LOW_BODY.read_text(encoding="utf-8"),
        "high-level specification": HIGH_SPEC.read_text(encoding="utf-8"),
        "high-level body": HIGH_BODY.read_text(encoding="utf-8"),
    }
    expected_member_rows: list[tuple[str, str, str, str, str, str]] = []
    for row, expected in zip(operations, EXPECTED, strict=True):
        operation, enum_stem, shape, uri, has_id, prepare, execute, high = expected
        wanted_members = ["Bucket"] + (["Id"] if has_id else []) + ["ExpectedBucketOwner"]
        wanted_locations = [LOCATION[name] for name in wanted_members]
        wanted_required = ["True"] + (["True"] if has_id else []) + ["False"]
        if operation_scalar(model, "Operation_Name", enum_stem) != operation:
            fail(f"{operation}: generated name changed")
        if operation_scalar(model, "Method", enum_stem) != "Delete_Method":
            fail(f"{operation}: generated method is not DELETE")
        if int(operation_scalar(model, "Input_Shape", enum_stem)) != shape:
            fail(f"{operation}: generated input shape changed")
        if operation_scalar(model, "Output_Shape", enum_stem) != "0":
            fail(f"{operation}: generated output shape changed")
        if operation_scalar(model, "Request_URI", enum_stem) != uri:
            fail(f"{operation}: generated request URI changed")
        if operation_scalar(model, "Response_Code", enum_stem) != "204":
            fail(f"{operation}: generated success code changed")
        if member_count(model, shape) != len(wanted_members):
            fail(f"{operation}: generated member count changed")
        if member_values(model, "Member_Name", shape) != wanted_members:
            fail(f"{operation}: generated member names changed")
        if member_values(model, "Location", shape) != wanted_locations:
            fail(f"{operation}: generated member locations changed")
        if member_values(model, "Member_Required", shape) != wanted_required:
            fail(f"{operation}: generated required flags changed")
        expected_row = [
            operation, str(shape), uri, str(has_id).lower(),
            str(len(wanted_members)), prepare, execute, high,
        ]
        if [row[name] for name in OP_HEADER[:-1]] != expected_row:
            fail(f"{operation}: operation manifest drift")
        for ordinal, (name, location, required) in enumerate(
                zip(wanted_members, wanted_locations, wanted_required, strict=True), 1):
            expected_member_rows.append((
                operation, str(shape), str(ordinal), name,
                {"URI_Location": "uri-label", "Query_Location": "query",
                 "Header_Location": "header"}[location], required.lower(),
            ))
        for label, text in texts.items():
            names = [prepare, execute] if label.startswith("low-level") else [high]
            for name in names:
                if not re.search(rf"\bfunction\s+{re.escape(name)}\b", text):
                    fail(f"{operation}: {name} absent from {label}")

    lifecycle_tokens = {
        "low-level specification": [
            r"\bprocedure\s+Delete_Bucket_Lifecycle\b",
            r"Operation\s*:\s*in\s+out\s+"
            r"Flyology\.HTTP\.Client\.Exchange_Operation",
        ],
        "low-level body": [
            r"\bprocedure\s+Delete_Bucket_Lifecycle\b",
            r"Model\.Delete_Bucket_Lifecycle_Operation",
        ],
        "high-level specification": [
            r"\btype\s+Delete_Bucket_Lifecycle_Operation\b",
            r"\btype\s+Delete_Bucket_Lifecycle_Result\b",
            r"\bprocedure\s+Finish\s*\(\s*Operation\s*:\s*in\s+out\s+"
            r"Delete_Bucket_Lifecycle_Operation",
        ],
        "high-level body": [
            r"\bprocedure\s+Start_Delete_Bucket_Lifecycle\b",
            r"\bfunction\s+Normalize_Delete_Bucket_Lifecycle_Response\b",
            r"Low\.Delete_Bucket_Lifecycle",
        ],
    }
    replication_tokens = {
        "low-level specification": [
            r"\bprocedure\s+Delete_Bucket_Replication\b",
            r"Operation\s*:\s*in\s+out\s+"
            r"Flyology\.HTTP\.Client\.Exchange_Operation",
        ],
        "low-level body": [
            r"\bprocedure\s+Delete_Bucket_Replication\b",
            r"Model\.Delete_Bucket_Replication_Operation",
        ],
        "high-level specification": [
            r"\btype\s+Delete_Bucket_Replication_Operation\b",
            r"\btype\s+Delete_Bucket_Replication_Result\b",
            r"\bprocedure\s+Finish\s*\(\s*Operation\s*:\s*in\s+out\s+"
            r"Delete_Bucket_Replication_Operation",
        ],
        "high-level body": [
            r"\bprocedure\s+Start_Delete_Bucket_Replication\b",
            r"\bfunction\s+Normalize_Delete_Bucket_Replication_Response\b",
            r"Low\.Delete_Bucket_Replication",
        ],
    }
    website_tokens = {
        "low-level specification": [
            r"\bprocedure\s+Delete_Bucket_Website\b",
            r"Operation\s*:\s*in\s+out\s+"
            r"Flyology\.HTTP\.Client\.Exchange_Operation",
        ],
        "low-level body": [
            r"\bprocedure\s+Delete_Bucket_Website\b",
            r"Model\.Delete_Bucket_Website_Operation",
        ],
        "high-level specification": [
            r"\btype\s+Delete_Bucket_Website_Operation\b",
            r"\btype\s+Delete_Bucket_Website_Result\b",
            r"\bprocedure\s+Finish\s*\(\s*Operation\s*:\s*in\s+out\s+"
            r"Delete_Bucket_Website_Operation",
        ],
        "high-level body": [
            r"\bprocedure\s+Start_Delete_Bucket_Website\b",
            r"\bfunction\s+Normalize_Delete_Bucket_Website_Response\b",
            r"Low\.Delete_Bucket_Website",
        ],
    }
    analytics_tokens = {
        "low-level specification": [
            r"\bprocedure\s+Delete_Bucket_Analytics_Configuration\b",
            r"Operation\s*:\s*in\s+out\s+"
            r"Flyology\.HTTP\.Client\.Exchange_Operation",
        ],
        "low-level body": [
            r"\bprocedure\s+Delete_Bucket_Analytics_Configuration\b",
            r"Model\.Delete_Bucket_Analytics_Configuration_Operation",
        ],
        "high-level specification": [
            r"\btype\s+Delete_Bucket_Analytics_Operation\b",
            r"\btype\s+Delete_Bucket_Analytics_Result\b",
            r"\bprocedure\s+Finish\s*\(\s*Operation\s*:\s*in\s+out\s+"
            r"Delete_Bucket_Analytics_Operation",
        ],
        "high-level body": [
            r"\bprocedure\s+Start_Delete_Bucket_Analytics\b",
            r"\bfunction\s+Normalize_Delete_Bucket_Analytics_Response\b",
            r"Low\.Delete_Bucket_Analytics_Configuration",
        ],
    }
    intelligent_tiering_tokens = {
        "low-level specification": [
            r"\bprocedure\s+Delete_Bucket_Intelligent_Tiering_Configuration\b",
            r"Operation\s*:\s*in\s+out\s+"
            r"Flyology\.HTTP\.Client\.Exchange_Operation",
        ],
        "low-level body": [
            r"\bprocedure\s+Delete_Bucket_Intelligent_Tiering_Configuration\b",
            r"Model\.Delete_Bucket_Intelligent_Tiering_Configuration_Operation",
        ],
        "high-level specification": [
            r"\btype\s+Delete_Bucket_Tiering_Operation\b",
            r"\btype\s+Delete_Bucket_Tiering_Result\b",
            r"\bprocedure\s+Finish\s*\(\s*Operation\s*:\s*in\s+out\s+"
            r"Delete_Bucket_Tiering_Operation",
        ],
        "high-level body": [
            r"\bprocedure\s+Start_Delete_Bucket_Tiering\b",
            r"\bfunction\s+Normalize_Delete_Bucket_Tiering_Response\b",
            r"Low\.Delete_Bucket_Intelligent_Tiering_Configuration",
        ],
    }
    inventory_tokens = {
        "low-level specification": [
            r"\bprocedure\s+Delete_Bucket_Inventory_Configuration\b",
            r"Operation\s*:\s*in\s+out\s+"
            r"Flyology\.HTTP\.Client\.Exchange_Operation",
        ],
        "low-level body": [
            r"\bprocedure\s+Delete_Bucket_Inventory_Configuration\b",
            r"Model\.Delete_Bucket_Inventory_Configuration_Operation",
        ],
        "high-level specification": [
            r"\btype\s+Delete_Bucket_Inventory_Configuration_Operation\b",
            r"\btype\s+Delete_Bucket_Inventory_Configuration_Result\b",
            r"\bprocedure\s+Finish\s*\(\s*Operation\s*:\s*in\s+out\s+"
            r"Delete_Bucket_Inventory_Configuration_Operation",
        ],
        "high-level body": [
            r"\bprocedure\s+Start_Delete_Bucket_Inventory_Configuration\b",
            r"\bfunction\s+Normalize_Delete_Bucket_Inventory_Configuration_Response\b",
            r"Low\.Delete_Bucket_Inventory_Configuration",
        ],
    }
    for operation, tokens in (
        ("DeleteBucketLifecycle", lifecycle_tokens),
        ("DeleteBucketReplication", replication_tokens),
        ("DeleteBucketWebsite", website_tokens),
        ("DeleteBucketAnalyticsConfiguration", analytics_tokens),
        ("DeleteBucketIntelligentTieringConfiguration",
         intelligent_tiering_tokens),
        ("DeleteBucketInventoryConfiguration", inventory_tokens),
    ):
        for label, patterns in tokens.items():
            for pattern in patterns:
                if re.search(pattern, texts[label]) is None:
                    fail(f"{operation} composable API absent from {label}")
    for operation, name in (
        ("DeleteBucketLifecycle", "Delete_Lifecycle"),
        ("DeleteBucketReplication", "Delete_Replication"),
        ("DeleteBucketWebsite", "Delete_Website"),
        ("DeleteBucketAnalyticsConfiguration", "Delete_Analytics_Configuration"),
        ("DeleteBucketIntelligentTieringConfiguration",
         "Delete_Intelligent_Tiering_Configuration"),
        ("DeleteBucketInventoryConfiguration", "Delete_Inventory_Configuration"),
    ):
        for label in ("high-level specification", "high-level body"):
            if texts[label].count(f"function {name}") != 3:
                fail(f"{operation} function overload count changed in {label}")
            if texts[label].count(f"procedure {name}") != 1:
                fail(f"{operation} reusable overload count changed in {label}")

    if [tuple(row[name] for name in MEMBER_HEADER[:-1]) for row in members] != expected_member_rows:
        fail("member manifest does not exactly match generated input shapes")

    operation_by_name = {row["operation"]: row for row in operations}
    vector_by_id: dict[str, dict[str, str]] = {}
    for vector in vectors:
        vector_id = vector["id"]
        if not re.fullmatch(r"BCF-(?:RQ|RS|TR)-\d{3}", vector_id):
            fail(f"noncanonical vector id: {vector_id}")
        if vector_id in vector_by_id:
            fail(f"duplicate vector id: {vector_id}")
        vector_by_id[vector_id] = vector
        for operation in comma_values(vector["operation_refs"]):
            if operation not in operation_by_name:
                fail(f"{vector_id}: unknown operation {operation}")

    for operation, row in operation_by_name.items():
        for vector_id in comma_values(row["vector_ids"]):
            vector = vector_by_id.get(vector_id)
            if vector is None:
                fail(f"{operation}: unknown vector {vector_id}")
            if operation not in comma_values(vector["operation_refs"]):
                fail(f"{operation}: {vector_id} lacks reciprocal reference")
    for vector_id, vector in vector_by_id.items():
        for operation in comma_values(vector["operation_refs"]):
            if vector_id not in comma_values(operation_by_name[operation]["vector_ids"]):
                fail(f"{vector_id}: {operation} lacks reciprocal reference")
    for member in members:
        for vector_id in comma_values(member["vector_ids"]):
            vector = vector_by_id.get(vector_id)
            if vector is None or member["operation"] not in comma_values(vector["operation_refs"]):
                fail(f"{member['operation']}:{member['member']}: bad vector {vector_id}")

    print(
        "bucket-configuration DELETE preparation: 13 operations, 30 request "
        f"members, no modeled success outputs, {len(vectors)} reciprocal vectors; "
        "pinned model and exact public APIs match, including analytics, "
        "lifecycle, replication, website, intelligent-tiering, and inventory "
        "composable forms"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, UnicodeError, ValueError) as exc:
        print(f"bucket-configuration DELETE verification failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
