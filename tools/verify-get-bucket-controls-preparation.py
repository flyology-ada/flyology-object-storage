#!/usr/bin/env python3
"""Verify the pinned six-operation bucket-control GET family."""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "tests" / "corpora" / "get-bucket-controls"
MODEL = ROOT / "src" / "flyology-object_storage-s3-model.adb"
LOW_SPEC = ROOT / "src" / "flyology-object_storage-client-low_level.ads"
LOW_BODY = ROOT / "src" / "flyology-object_storage-client-low_level.adb"
HIGH_SPEC = ROOT / "src" / "flyology-object_storage-client-buckets.ads"
HIGH_BODY = ROOT / "src" / "flyology-object_storage-client-buckets.adb"
SERVER_BODY = (
    ROOT / "src" / "flyology-object_storage-server-s3_applications.adb"
)
SERVER_CORPUS = ROOT / "tests" / "src" / "s3_server_application_corpus.adb"
IMPLEMENTATION = ROOT / "tests" / "src" / "s3_implementation_corpus.adb"
LOCK = ROOT / "coverage" / "corpora.lock.toml"

# These are the stable source revision and content digest recorded by the
# repository corpus lock. Changing either is a model upgrade and requires
# regenerating and reviewing this complete operation/member inventory.
EXPECTED_REVISION = "36c34f15391da01cd717c73c0fffa747c9889768"
EXPECTED_SHA256 = "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"

# Each tuple records the reviewed pinned-model projection and exact public API
# binding. Shape numbers are persisted corpus identifiers, not product limits.
EXPECTED = [
    ("GetBucketAbac", "Get_Bucket_Abac", 222, 221, "/{Bucket}?abac",
     "Prepare_Get_Bucket_Abac", "Execute_Get_Bucket_Abac", "Get_ABAC"),
    ("GetBucketAccelerateConfiguration", "Get_Bucket_Accelerate_Configuration",
     224, 223, "/{Bucket}?accelerate",
     "Prepare_Get_Bucket_Accelerate_Configuration",
     "Execute_Get_Bucket_Accelerate_Configuration",
     "Get_Accelerate_Configuration"),
    ("GetBucketPolicy", "Get_Bucket_Policy", 257, 256,
     "/{Bucket}?policy", "Prepare_Get_Bucket_Policy",
     "Execute_Get_Bucket_Policy", "Get_Policy"),
    ("GetBucketPolicyStatus", "Get_Bucket_Policy_Status", 259, 258,
     "/{Bucket}?policyStatus", "Prepare_Get_Bucket_Policy_Status",
     "Execute_Get_Bucket_Policy_Status", "Get_Policy_Status"),
    ("GetBucketRequestPayment", "Get_Bucket_Request_Payment", 263, 262,
     "/{Bucket}?requestPayment", "Prepare_Get_Bucket_Request_Payment",
     "Execute_Get_Bucket_Request_Payment", "Get_Request_Payment"),
    ("GetPublicAccessBlock", "Get_Public_Access_Block", 291, 290,
     "/{Bucket}?publicAccessBlock", "Prepare_Get_Public_Access_Block",
     "Execute_Get_Public_Access_Block", "Get_Public_Access_Block"),
]

# Operation ownership is repeated for shared nested shapes so the reciprocal
# corpus graph proves which public result exposes each generated member.
EXPECTED_MEMBERS = [
    ("GetBucketAbac", "request", 222, 1, "Bucket", 60, "uri-label", "true"),
    ("GetBucketAbac", "request", 222, 2, "ExpectedBucketOwner", 15,
     "header", "false"),
    ("GetBucketAbac", "output", 221, 1, "AbacStatus", 1, "body", "false"),
    ("GetBucketAbac", "nested", 1, 1, "Status", 48, "body", "false"),
    ("GetBucketAccelerateConfiguration", "request", 224, 1, "Bucket", 60,
     "uri-label", "true"),
    ("GetBucketAccelerateConfiguration", "request", 224, 2,
     "ExpectedBucketOwner", 15, "header", "false"),
    ("GetBucketAccelerateConfiguration", "request", 224, 3, "RequestPayer",
     599, "header", "false"),
    ("GetBucketAccelerateConfiguration", "output", 223, 1, "Status", 49,
     "body", "false"),
    ("GetBucketAccelerateConfiguration", "output", 223, 2,
     "RequestCharged", 598, "header", "false"),
    ("GetBucketPolicy", "request", 257, 1, "Bucket", 60, "uri-label", "true"),
    ("GetBucketPolicy", "request", 257, 2, "ExpectedBucketOwner", 15,
     "header", "false"),
    ("GetBucketPolicy", "output", 256, 1, "Policy", 515, "body", "false"),
    ("GetBucketPolicyStatus", "request", 259, 1, "Bucket", 60, "uri-label",
     "true"),
    ("GetBucketPolicyStatus", "request", 259, 2, "ExpectedBucketOwner", 15,
     "header", "false"),
    ("GetBucketPolicyStatus", "output", 258, 1, "PolicyStatus", 516, "body",
     "false"),
    ("GetBucketPolicyStatus", "nested", 516, 1, "IsPublic", 353, "body",
     "false"),
    ("GetBucketRequestPayment", "request", 263, 1, "Bucket", 60,
     "uri-label", "true"),
    ("GetBucketRequestPayment", "request", 263, 2, "ExpectedBucketOwner", 15,
     "header", "false"),
    ("GetBucketRequestPayment", "output", 262, 1, "Payer", 513, "body",
     "false"),
    ("GetPublicAccessBlock", "request", 291, 1, "Bucket", 60, "uri-label",
     "true"),
    ("GetPublicAccessBlock", "request", 291, 2, "ExpectedBucketOwner", 15,
     "header", "false"),
    ("GetPublicAccessBlock", "output", 290, 1,
     "PublicAccessBlockConfiguration", 522, "body", "false"),
    ("GetPublicAccessBlock", "nested", 522, 1, "BlockPublicAcls", 655, "body",
     "false"),
    ("GetPublicAccessBlock", "nested", 522, 2, "IgnorePublicAcls", 655, "body",
     "false"),
    ("GetPublicAccessBlock", "nested", 522, 3, "BlockPublicPolicy", 655, "body",
     "false"),
    ("GetPublicAccessBlock", "nested", 522, 4, "RestrictPublicBuckets", 655,
     "body", "false"),
]

# Exact external enum domains are compatibility input from the pinned model.
EXPECTED_ENUMS = {
    48: ["Enabled", "Disabled"],
    49: ["Enabled", "Suspended"],
    513: ["Requester", "BucketOwner"],
    598: ["requester"],
    599: ["requester"],
}

OP_HEADER = [
    "operation", "input_shape", "output_shape", "request_uri", "member_count",
    "prepare", "execute", "high_level", "vector_ids",
]
MEMBER_HEADER = [
    "operation", "direction", "shape", "ordinal", "member", "member_shape",
    "wire_location", "required", "vector_ids",
]
VECTOR_HEADER = [
    "id", "direction", "layer", "category", "operation_refs", "stimulus",
    "expected_contract",
]
LOCATION = {
    "URI_Location": "uri-label",
    "Header_Location": "header",
    "Body_Location": "body",
}


def fail(message: str) -> None:
    raise ValueError(message)


def source_region(text: str, start: str, end: str, label: str) -> str:
    if text.count(start) != 1:
        fail(f"{label}: start boundary is not unique")
    first = text.index(start)
    last = text.find(end, first + len(start))
    if last < 0:
        fail(f"{label}: end boundary is absent")
    return text[first:last + len(end)]


def require_in_order(
    text: str, fragments: tuple[str, ...], label: str
) -> None:
    position = 0
    for fragment in fragments:
        found = text.find(fragment, position)
        if found < 0:
            fail(f"{label}: missing ordered fragment {fragment!r}")
        position = found + len(fragment)


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
    pattern = (
        r'when\s+(\d+)\s+=>\s+return\s+"([^"]+)";'
        if function == "Member_Name"
        else r"when\s+(\d+)\s+=>\s+return\s+([A-Za-z0-9_]+);"
    )
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


def enumeration_values(model: str, shape: int) -> list[str]:
    count_match = re.search(
        rf"when\s+{shape}\s+=>\s+return\s+(\d+);",
        function_body(model, "Enumeration_Count"),
    )
    block = re.search(
        rf"when {shape} =>\s+case Index is(?P<body>.*?)\s+end case;",
        function_body(model, "Enumeration_Value"), re.DOTALL,
    )
    if count_match is None or block is None:
        fail(f"generated model lacks enumeration shape {shape}")
    pairs = re.findall(
        r'when\s+(\d+)\s+=>\s+return\s+"([^"]+)";', block.group("body")
    )
    count = int(count_match.group(1))
    if [int(number) for number, _ in pairs] != list(range(1, count + 1)):
        fail(f"shape {shape} enumeration order is not contiguous")
    return [value for _, value in pairs]


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
    server_body = SERVER_BODY.read_text(encoding="utf-8")
    server_corpus = SERVER_CORPUS.read_text(encoding="utf-8")
    implementation_corpus = IMPLEMENTATION.read_text(encoding="utf-8")
    expected_rows = [tuple(str(value) for value in row) for row in EXPECTED_MEMBERS]
    actual_rows = [tuple(row[name] for name in MEMBER_HEADER[:-1]) for row in members]
    if actual_rows != expected_rows:
        fail("member manifest does not exactly match the reviewed 26-member graph")

    rows_by_operation: dict[str, list[tuple[str, ...]]] = {}
    for row in expected_rows:
        rows_by_operation.setdefault(row[0], []).append(row)

    for row, expected in zip(operations, EXPECTED, strict=True):
        operation, enum_stem, input_shape, output_shape, uri, prepare, execute, high = expected
        if operation_scalar(model, "Operation_Name", enum_stem) != operation:
            fail(f"{operation}: generated name changed")
        if operation_scalar(model, "Method", enum_stem) != "Get_Method":
            fail(f"{operation}: generated method is not GET")
        if operation_scalar(model, "Request_URI", enum_stem) != uri:
            fail(f"{operation}: generated request URI changed")
        if operation_scalar(model, "Response_Code", enum_stem) != "200":
            fail(f"{operation}: generated success code changed")
        if int(operation_scalar(model, "Input_Shape", enum_stem)) != input_shape:
            fail(f"{operation}: generated input shape changed")
        if int(operation_scalar(model, "Output_Shape", enum_stem)) != output_shape:
            fail(f"{operation}: generated output shape changed")
        expected_op = [
            operation, str(input_shape), str(output_shape), uri,
            str(len(rows_by_operation[operation])), prepare, execute, high,
        ]
        if [row[name] for name in OP_HEADER[:-1]] != expected_op:
            fail(f"{operation}: operation manifest drift")
        for label, text in texts.items():
            names = [prepare, execute] if label.startswith("low-level") else [high]
            for name in names:
                if not re.search(rf"\bfunction\s+{re.escape(name)}\b", text):
                    fail(f"{operation}: {name} absent from {label}")

    composable_reads = (
        (
            "GetBucketAccelerateConfiguration",
            "Get_Bucket_Accelerate_Configuration",
        ),
        ("GetBucketAbac", "Get_Bucket_ABAC"),
        ("GetBucketPolicyStatus", "Get_Bucket_Policy_Status"),
        ("GetBucketRequestPayment", "Get_Bucket_Request_Payment"),
    )
    for operation, stem in composable_reads:
        for label in ("low-level specification", "low-level body"):
            if not re.search(rf"\bprocedure\s+{stem}\b", texts[label]):
                fail(
                    f"{operation}: composable initiator absent from {label}"
                )
        for declaration in (
                f"{stem}_Result",
                f"{stem}_Operation",
                f"Normalize_{stem}_Response",
                f"Normalize_{stem}_Failure",
        ):
            if declaration not in texts["high-level specification"]:
                fail(
                    f"{operation}: {declaration} absent from provider spec"
                )
            if declaration.startswith("Normalize_") and declaration not in (
                    texts["high-level body"]):
                fail(
                    f"{operation}: {declaration} absent from provider body"
                )

    checked_shapes: set[int] = set()
    for _, _, shape_text, _, _, _, _, _ in expected_rows:
        shape = int(shape_text)
        if shape in checked_shapes:
            continue
        checked_shapes.add(shape)
        shape_rows = [row for row in expected_rows if int(row[2]) == shape]
        if member_count(model, shape) != len(shape_rows):
            fail(f"shape {shape}: generated member count changed")
        if member_values(model, "Member_Name", shape) != [row[4] for row in shape_rows]:
            fail(f"shape {shape}: generated member names changed")
        if member_values(model, "Member_Shape", shape) != [row[5] for row in shape_rows]:
            fail(f"shape {shape}: generated member shapes changed")
        if [LOCATION[value] for value in member_values(model, "Location", shape)] != [
                row[6] for row in shape_rows]:
            fail(f"shape {shape}: generated member locations changed")
        if [value.lower() for value in member_values(
                model, "Member_Required", shape)] != [row[7] for row in shape_rows]:
            fail(f"shape {shape}: generated required flags changed")

    for shape, expected_values in EXPECTED_ENUMS.items():
        if enumeration_values(model, shape) != expected_values:
            fail(f"shape {shape}: generated enum domain changed")

    operation_by_name = {row["operation"]: row for row in operations}
    vector_by_id: dict[str, dict[str, str]] = {}
    for vector in vectors:
        vector_id = vector["id"]
        if not re.fullmatch(r"GBC-(?:MD|RQ|RS|TR)-\d{3}", vector_id):
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
            if vector is None or operation not in comma_values(vector["operation_refs"]):
                fail(f"{operation}: bad reciprocal vector {vector_id}")
    for vector_id, vector in vector_by_id.items():
        for operation in comma_values(vector["operation_refs"]):
            if vector_id not in comma_values(operation_by_name[operation]["vector_ids"]):
                fail(f"{vector_id}: {operation} lacks reciprocal reference")
    for member in members:
        for vector_id in comma_values(member["vector_ids"]):
            vector = vector_by_id.get(vector_id)
            if vector is None or member["operation"] not in comma_values(
                    vector["operation_refs"]):
                fail(f"{member['operation']}:{member['member']}: bad vector {vector_id}")

    assessment = source_region(
        server_body,
        "   function Assess_Bucket_Policy\n",
        "   end Assess_Bucket_Policy;",
        "bucket policy assessment",
    )
    require_in_order(
        assessment,
        (
            "GNAT.Sockets.Inet_Addr",
            "return Prefix in 32 .. 128;",
            "return Prefix in 8 .. 32;",
            "return not Contains_Open_Value (Value);",
            "function Fixed_Data_Access_Point_ARN",
            "Operators.Contains (Operator)",
            "Keys.Contains (Key)",
            "Has_Public_Grant := True;",
            "when Malformed | Constraint_Error =>",
        ),
        "bucket policy assessment",
    )
    route = source_region(
        server_body,
        "            when Get_Bucket_Policy_Status =>",
        "            when Delete_Bucket_Policy =>",
        "bucket policy status route",
    )
    require_in_order(
        route,
        (
            "Store.Get_Bucket_Policy",
            '"NoSuchBucketPolicy"',
            "Assess_Bucket_Policy",
            "when Malformed_Bucket_Policy =>",
            '"InternalError"',
            '"<PolicyStatus xmlns=""http://s3."',
            '"<IsPublic>"',
        ),
        "bucket policy status route",
    )
    implementation = source_region(
        implementation_corpus,
        "      procedure Check_Bucket_Policy_Status is",
        "      end Check_Bucket_Policy_Status;",
        "bucket policy implementation corpus",
    )
    require_in_order(
        implementation,
        (
            '"NoSuchBucketPolicy"',
            "Set_And_Require (Public_Policy, True);",
            "Set_And_Require (Fixed_Policy, False);",
            '"InternalError"',
            "Delete_Stored_Policy;",
            "when others =>",
            "Delete_Stored_Policy;",
        ),
        "bucket policy implementation corpus",
    )
    server_cases = source_region(
        server_corpus,
        "      Status_Query : constant SigV4.Name_Value_Array :=",
        "      for Algorithm in Checksum_Policy.Algorithm loop",
        "bucket policy status server corpus",
    )
    require_in_order(
        server_cases,
        (
            "Require_Status (Public_Policy, True);",
            "Require_Status (Fixed_Policy, False);",
            "Require_Status (Conditioned_Policy, False);",
            "Require_Status (Role_Session_Policy, True);",
            "Require_Status (Open_User_ID_Policy, True);",
            "Require_Status (Invalid_IP_Policy, True);",
            "Require_Status (Narrow_IP_Policy, False);",
            "Require_Status (Broad_IP_Policy, True);",
            "Require_Status (Fixed_Access_Point_Policy, False);",
            "Require_Status (Open_Access_Point_Account_Policy, True);",
            "Require_Status (Mixed_Policy, True);",
            "Require_Status (Wildcard_Deny_Policy, False);",
            "Require_Malformed_Status (Duplicate_Condition_Policy);",
            "Require_Malformed_Status (Duplicate_Condition_Key_Policy);",
            '"GetBucketPolicyStatus ignored expected owner"',
            '"GetBucketPolicyStatus accepted an extra query member"',
            '"GetBucketPolicyStatus accepted a request body"',
            '"GetBucketPolicyStatus accepted non-modeled RequestPayer"',
        ),
        "bucket policy status server corpus",
    )

    print(
        "bucket-control GET preparation: 6 operations, 26 request/output/nested "
        f"members, 5 exact enum domains, {len(vectors)} reciprocal vectors; "
        "pinned model and exact public APIs match"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, UnicodeError, ValueError) as exc:
        print(f"bucket-control GET verification failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
