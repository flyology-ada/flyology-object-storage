#!/usr/bin/env python3
"""Verify the isolated DeleteBucketCors model inventory and corpus graph."""

from __future__ import annotations

import copy
import csv
import re
import sys
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "tests" / "corpora" / "delete-bucket-cors"
MODEL = ROOT / "src" / "flyology-object_storage-s3-model.adb"
MODEL_SPEC = ROOT / "src" / "flyology-object_storage-s3-model.ads"
LOCK = ROOT / "coverage" / "corpora.lock.toml"
REGISTRY = ROOT / "coverage" / "s3-operations.toml"
LOW_SPEC = ROOT / "src" / "flyology-object_storage-client-low_level.ads"
LOW_BODY = ROOT / "src" / "flyology-object_storage-client-low_level.adb"
BUCKETS_SPEC = ROOT / "src" / "flyology-object_storage-client-buckets.ads"
BUCKETS_BODY = ROOT / "src" / "flyology-object_storage-client-buckets.adb"
DIRECT = ROOT / "tests" / "src" / "object_storage_test_cases.adb"
TESTING = (
    ROOT / "tests" / "src" /
    "flyology-object_storage-client-buckets-testing.adb"
)
SOCKET = ROOT / "tests" / "src" / "s3_http_socket_corpus.adb"
SERVER = (
    ROOT / "src" / "flyology-object_storage-server-s3_applications.adb"
)
SERVER_TEST = ROOT / "tests" / "src" / "s3_server_application_corpus.adb"
SQLITE_TEST = (
    ROOT / "sqlite" / "tests" / "src" /
    "flyology_object_storage_sqlite_tests.adb"
)
QUALIFICATION = ROOT / "docs" / "qualification" / "delete-bucket-cors.md"
EXPECTED_REVISION = "36c34f15391da01cd717c73c0fffa747c9889768"
EXPECTED_SHA256 = "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
EXPECTED_MEMBERS = ["Bucket", "ExpectedBucketOwner"]
MEMBER_HEADER = [
    "direction", "shape", "ordinal", "member", "wire_location",
    "current_boundary", "required_contract", "vector_ids",
]
VECTOR_HEADER = [
    "id", "direction", "layer", "category", "member_refs", "stimulus",
    "expected_contract",
]
CERTAINTY = (
    "only a complete validated 204 response with an exactly empty body "
    "reports Bucket_CORS_Mutation_Completed; an exact recognized "
    "non-mutating rejection or definite non-admission reports "
    "Bucket_CORS_Mutation_Definitely_Not_Applied; pre-admission "
    "cancellation reports Bucket_CORS_Mutation_Cancelled_Before_Admission; "
    "possible or incomplete admission, retryable responses, and malformed "
    "or oversized responses report Bucket_CORS_Mutation_Outcome_Unknown; "
    "no automatic replay"
)
RECONCILIATION = (
    "caller-selected Get_CORS may observe the current "
    "NoSuchCORSConfiguration state before a retry but does not prove that "
    "the lost deletion caused the observed absence or upgrade mutation "
    "certainty; no automatic replay"
)
EXPECTED_LANE = [
    [
        "uv", "run", "--python", "3.13", "--",
        "tools/verify-delete-bucket-cors-preparation.py",
    ],
    ["@tests", "alr", "-n", "build"],
    ["@tests", "./bin/s3_delete_bucket_cors_corpus"],
    ["@tests", "./bin/s3_server_application_corpus"],
    ["@tests", "./bin/s3_http_socket_corpus"],
    ["./tools/verify-coverage.sh"],
    [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-bucket-cors-gnatdoc",
    ],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]


def fail(message: str) -> None:
    raise ValueError(message)


def regular(path: Path) -> None:
    if not path.is_file() or path.is_symlink():
        fail(f"missing or non-regular evidence path: {path}")


def once(text: str, marker: str, label: str) -> int:
    count = text.count(marker)
    if count != 1:
        fail(f"{label}: expected one marker, found {count}: {marker}")
    return text.index(marker)


def region(text: str, start: str, end: str, label: str) -> str:
    start_at = once(text, start, label)
    end_at = text.find(end, start_at + len(start))
    if end_at < 0:
        fail(f"{label}: missing end marker: {end}")
    return text[start_at:end_at]


def ordered(text: str, markers: list[str], label: str) -> None:
    cursor = 0
    for marker in markers:
        position = text.find(marker, cursor)
        if position < 0:
            fail(f"{label}: missing ordered marker: {marker}")
        cursor = position + len(marker)


def collapsed(text: str) -> str:
    return " ".join(text.split())


def operation_entry(data: dict[str, object]) -> dict[str, object]:
    matches = [
        item for item in data["operation"]
        if item["name"] == "DeleteBucketCors"
    ]
    if len(matches) != 1:
        fail("DeleteBucketCors registry entry is not unique")
    return matches[0]


def verify_registry(data: dict[str, object]) -> None:
    entry = operation_entry(data)
    expected = {
        "tier": "extended",
        "provider": "buckets",
        "family": "bodyless_mutation",
        "public_provider": "Flyology.Object_Storage.Client.Buckets",
        "codec": "empty_response",
        "public_name": "Delete_CORS",
        "errors": [
            "authentication",
            "authorization",
            "not_found",
            "invalid_request",
            "unavailable_or_retryable",
            "corrupt_or_invalid_response",
        ],
        "certainty": CERTAINTY,
        "reconciliation": RECONCILIATION,
        "coverage": {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        },
        "provenance": {
            "backend": "handwritten",
            "client": "handwritten",
            "server": "handwritten",
            "tests": "handwritten",
        },
        "implementation_mode": "handwritten",
        "generator_eligible": False,
        "human_decisions_resolved": True,
        "decision_status": "reviewed",
        "qualification": "delete_bucket_cors",
        "ada_symbols": [
            "Prepare_Delete_Bucket_CORS",
            "Decode_Delete_Bucket_CORS_Response",
            "Execute_Delete_Bucket_CORS",
            "Delete_Bucket_Cors_Operation",
            "Delete_CORS",
            "Finish",
        ],
    }
    for key, value in expected.items():
        if entry.get(key) != value:
            fail(f"DeleteBucketCors registry changed: {key}")
    if "does not assert prior CORS-configuration presence" not in (
        entry["absence"]
    ):
        fail("DeleteBucketCors absence semantics changed")
    if "exact NoSuchBucket" not in entry["absence"]:
        fail("DeleteBucketCors missing-bucket semantics changed")
    if "exact HTTP 204" not in entry["exclusions"][2]:
        fail("DeleteBucketCors success status changed")
    if "exactly empty response body" not in entry["exclusions"][2]:
        fail("DeleteBucketCors success body changed")
    if "previously present" not in entry["exclusions"][3]:
        fail("DeleteBucketCors prior-presence boundary changed")
    if "does not establish causation" not in entry["exclusions"][4]:
        fail("DeleteBucketCors reconciliation boundary changed")
    if data["qualification"].get("delete_bucket_cors") != EXPECTED_LANE:
        fail("DeleteBucketCors qualification lane changed")


def verify_registry_negatives(data: dict[str, object]) -> None:
    mutations = (
        ("missing public name", "public_name", None),
        ("wrong public name", "public_name", "Delete_Configuration"),
        (
            "broadened success",
            "certainty",
            CERTAINTY.replace("validated 204", "validated 200 or 204"),
        ),
        (
            "causal reconciliation",
            "reconciliation",
            "Get_CORS proves the deletion completed",
        ),
        ("cross-operation lane", "qualification", "delete_bucket_tagging"),
    )
    for label, key, value in mutations:
        candidate = copy.deepcopy(data)
        entry = operation_entry(candidate)
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        if candidate == data:
            fail(f"{label}: candidate did not change")
        try:
            verify_registry(candidate)
        except (KeyError, TypeError, ValueError):
            continue
        fail(f"{label}: candidate was accepted")

    duplicate = copy.deepcopy(data)
    duplicate["operation"].append(copy.deepcopy(operation_entry(duplicate)))
    if duplicate == data:
        fail("duplicate entry: candidate did not change")
    try:
        verify_registry(duplicate)
    except (KeyError, TypeError, ValueError):
        pass
    else:
        fail("duplicate DeleteBucketCors entry was accepted")

    malformed_lane = copy.deepcopy(data)
    malformed_lane["qualification"]["delete_bucket_cors"][0][-1] = (
        "tools/verify-delete-bucket-tagging-preparation.py"
    )
    if malformed_lane == data:
        fail("malformed lane: candidate did not change")
    try:
        verify_registry(malformed_lane)
    except (KeyError, TypeError, ValueError):
        pass
    else:
        fail("malformed DeleteBucketCors lane was accepted")


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
        fail(f"generated model has no {function} body")
    tail = model[match.end():]
    marker = f"end {function};"
    if marker not in tail:
        fail(f"generated model has no end for {function}")
    return tail.split(marker, 1)[0]


def operation_shape(model: str, function: str) -> int:
    match = re.search(
        r"when Delete_Bucket_Cors_Operation =>\s+return\s+(\d+);",
        function_body(model, function),
    )
    if match is None:
        fail(f"generated model has no DeleteBucketCors {function}")
    return int(match.group(1))


def member_block(model: str, function: str, shape: int) -> str:
    match = re.search(
        rf"when {shape} =>\s+case Member is(?P<body>.*?)\s+end case;",
        function_body(model, function),
        re.DOTALL,
    )
    if match is None:
        fail(f"generated model has no {function} block for shape {shape}")
    return match.group("body")


def member_values(model: str, function: str, shape: int) -> list[str]:
    pattern = (
        r'when\s+(\d+)\s+=>\s+return\s+"([^"]+)";'
        if function == "Member_Name"
        else r"when\s+(\d+)\s+=>\s+return\s+([A-Za-z_]+);"
    )
    pairs = re.findall(pattern, member_block(model, function, shape))
    if [int(number) for number, _ in pairs] != list(range(1, len(pairs) + 1)):
        fail(f"shape {shape} {function} order is not contiguous")
    return [value for _, value in pairs]


def member_count(model: str, shape: int) -> int:
    match = re.search(
        rf"when\s+{shape}\s+=>\s+return\s+(\d+);",
        function_body(model, "Member_Count"),
    )
    if match is None:
        fail(f"generated model has no member count for shape {shape}")
    return int(match.group(1))


def comma_values(value: str) -> list[str]:
    values = value.split(",")
    if any(item == "" or item != item.strip() for item in values):
        fail(f"noncanonical comma list: {value!r}")
    if len(values) != len(set(values)):
        fail(f"duplicate comma-list value: {value!r}")
    return values


def verify_sources() -> None:
    paths = (
        MODEL_SPEC, LOW_SPEC, LOW_BODY, BUCKETS_SPEC, BUCKETS_BODY,
        DIRECT, TESTING, SOCKET, SERVER, SERVER_TEST, SQLITE_TEST,
        QUALIFICATION,
    )
    for path in paths:
        regular(path)
    model_spec = MODEL_SPEC.read_text(encoding="utf-8")
    low_spec = LOW_SPEC.read_text(encoding="utf-8")
    low_body = LOW_BODY.read_text(encoding="utf-8")
    buckets_spec = BUCKETS_SPEC.read_text(encoding="utf-8")
    buckets_body = BUCKETS_BODY.read_text(encoding="utf-8")
    direct = DIRECT.read_text(encoding="utf-8")
    testing = TESTING.read_text(encoding="utf-8")
    socket = SOCKET.read_text(encoding="utf-8")
    server = SERVER.read_text(encoding="utf-8")
    server_test = SERVER_TEST.read_text(encoding="utf-8")
    sqlite_test = SQLITE_TEST.read_text(encoding="utf-8")
    qualification = collapsed(QUALIFICATION.read_text(encoding="utf-8"))

    if model_spec.count(
        "@enum Delete_Bucket_Cors_Operation Delete bucket CORS operation"
    ) != 1:
        fail("DeleteBucketCors generated model documentation changed")

    low_contract = region(
        low_spec,
        "   --  Every member in the pinned DeleteBucketCors request shape.",
        "   --  Parameters for a named bodyless bucket-configuration delete.",
        "low-level contract",
    )
    ordered(
        low_contract,
        [
            "@field Expected_Bucket_Owner",
            "type Delete_Bucket_CORS_Parameters",
            "Build and sign one bodyless DeleteBucketCors request",
            "function Prepare_Delete_Bucket_CORS",
            "@enum Bucket_CORS_Deleted Exact empty 204 response",
            "@enum Delete_Bucket_CORS_Rejected",
            "type Delete_Bucket_CORS_Outcome_Kind",
            "@field Kind",
            "@field Status",
            "@field Error",
            "type Delete_Bucket_CORS_Outcome",
            "function Decode_Delete_Bucket_CORS_Response",
            "function Execute_Delete_Bucket_CORS",
        ],
        "low-level contract",
    )

    decoder = region(
        low_body,
        "   function Decode_Delete_Bucket_Configuration_Response",
        "   function Execute_Bucket_Configuration_Deletion",
        "response decoder",
    )
    ordered(
        decoder,
        [
            "elsif Status = 204 then",
            "if Payload'Length /= 0 then",
            "Kind => Configuration_Deleted, Status => Status",
            "Kind   => Delete_Configuration_Rejected",
        ],
        "response decoder",
    )
    if "Status in 200 | 204" in decoder:
        fail("DeleteBucketCors success status was broadened")

    public_contract = region(
        buckets_spec,
        "   --  Shape of a terminal DeleteBucketCors mutation.",
        "   --  Remove one named analytics configuration.",
        "public contract",
    )
    ordered(
        public_contract,
        [
            "type Delete_Bucket_CORS_Result_Kind",
            "@field Disposition",
            "@field Admission",
            "type Delete_Bucket_CORS_Result",
            "type Delete_Bucket_CORS_Operation",
            "procedure Delete_CORS",
            "function Delete_CORS",
            "procedure Finish",
            "function Delete_CORS",
            "function Delete_CORS",
        ],
        "public contract",
    )

    provider = region(
        buckets_body,
        "   function Normalize_Delete_Bucket_CORS_Response",
        "   function Normalize_Put_Bucket_CORS_Response",
        "composable provider",
    )
    ordered(
        provider,
        [
            "Bucket_CORS_Mutation_Outcome_Unknown",
            "Low_Level.Bucket_CORS_Deleted",
            "Bucket_CORS_Mutation_Completed",
            "Bucket_CORS_Mutation_Definitely_Not_Applied",
            "function Normalize_Delete_Bucket_CORS_Failure",
            "Complete_Delete_Bucket_CORS_Child",
            "Low.Clear_Prepared_Request",
            "procedure Start_Delete_Bucket_CORS",
            "DeleteBucketCors restart changed a retained owner",
            "function Delete_CORS",
            "procedure Finish",
        ],
        "composable provider",
    )
    if buckets_body.count("Put_Request => False") != 2:
        fail("DeleteBucketCors operation-specific classification changed")
    if buckets_body.count("Put_Request => True") != 2:
        fail("PutBucketCors operation-specific classification changed")

    certainty = region(
        testing,
        "   procedure Check_Bucket_CORS_Result_Corpus is",
        "   end Check_Bucket_CORS_Result_Corpus;",
        "certainty corpus",
    )
    ordered(
        certainty,
        [
            '(400, "InvalidRequest",',
            '(400, "BadDigest", Bucket_CORS_Mutation_Outcome_Unknown,',
            '(400, "InvalidDigest", Bucket_CORS_Mutation_Outcome_Unknown,',
            '(400, "MalformedXML", Bucket_CORS_Mutation_Outcome_Unknown,',
            '(400, "XAmzContentSHA256Mismatch",',
            "Bucket_CORS_Mutation_Outcome_Unknown",
            "Corrupt_Or_Invalid_Response",
        ],
        "certainty corpus",
    )

    direct_corpus = (
        ROOT / "tests" / "src" / "s3_delete_bucket_cors_corpus.adb"
    ).read_text(encoding="utf-8")
    ordered(
        direct_corpus,
        [
            "Prepare_Delete_Bucket_CORS",
            'Low_Level.Target (Path) = "/example-bucket?cors"',
            'Decode_Delete_Bucket_CORS_Response (204, "")',
            "Outcome.Status = 204",
            'Expect_Invalid_Response (204, " ")',
            'Expect_Invalid_Response (200, "")',
            "Maximum_Document_Bytes => Error_XML'Length - 1",
        ],
        "deterministic corpus",
    )

    socket_region = region(
        socket,
        "            Result : constant Buckets.Delete_Outcome :=",
        "         Require_Configuration_Deletion",
        "socket evidence",
    )
    ordered(
        socket_region,
        [
            "DeleteBucketCors convenience success mismatch",
            "typed DeleteBucketCors response mismatch",
            "DeleteBucketCors accepted an encryption request",
            "composed DeleteBucketCors mismatch",
            "Bucket_CORS_Mutation_Definitely_Not_Applied",
            "restarted DeleteBucketCors mismatch",
            "Bucket_CORS_Mutation_Outcome_Unknown",
            "bounded DeleteBucketCors response mismatch",
        ],
        "socket evidence",
    )

    server_region = region(
        server,
        "            when Delete_Bucket_CORS =>",
        "            when Put_Bucket_Policy =>",
        "server route",
    )
    ordered(
        server_region,
        [
            "Check_Expected_Bucket_Owner",
            "Store.Delete_Bucket_CORS",
            'Apps.Respond (X, 204, "", "");',
        ],
        "server route",
    )
    ordered(
        server_test,
        [
            'SigV4.Pair ("x-id", "DeleteBucketCors")',
            "Signed_Query_Request",
            '("DELETE", "/test-bucket", Delete_Query)',
            '"DeleteBucketCors failed"',
            '"DeleteBucketCors left visible state"',
            '"DeleteBucketCors was not idempotent"',
        ],
        "server corpus",
    )

    backend_region = region(
        direct,
        "   procedure Exercise_Bucket_CORS",
        "   end Exercise_Bucket_CORS;",
        "backend evidence",
    )
    ordered(
        backend_region,
        [
            "Store.Delete_Bucket_CORS",
            "bucket CORS delete left visible state",
            "bucket CORS delete was not idempotent",
            "bucket CORS delete did not distinguish an absent bucket",
        ],
        "backend evidence",
    )
    ordered(
        sqlite_test,
        [
            "SQLite bucket CORS replacement lost exact bytes",
            "Store.Delete_Bucket_CORS",
            "SQLite bucket CORS deletion retained state",
            'Store.Delete_Bucket_CORS\n           ("missing-bucket"',
        ],
        "SQLite evidence",
    )
    ordered(
        qualification,
        [
            "Put-only checksum and request-body errors never classify a "
            "DeleteBucketCors rejection",
            "covered / covered / covered / covered",
            "removed exactly the one candidate-owned",
            "added none",
            "Repository-wide and selected-operation GNATdoc qualification "
            "remain blocked",
            "`delete_bucket_cors` lane must still succeed",
        ],
        "qualification prose",
    )


def main() -> int:
    for path in (LOCK, MODEL, REGISTRY):
        regular(path)
    lock = LOCK.read_text(encoding="utf-8")
    if f'revision = "{EXPECTED_REVISION}"' not in lock:
        fail("pinned botocore revision changed")
    if f'service_model_sha256 = "{EXPECTED_SHA256}"' not in lock:
        fail("pinned botocore service hash changed")

    model = MODEL.read_text(encoding="utf-8")
    input_shape = operation_shape(model, "Input_Shape")
    output_shape = operation_shape(model, "Output_Shape")
    if input_shape != 146 or output_shape != 0:
        fail(f"unexpected operation shapes: input={input_shape}, output={output_shape}")
    if member_count(model, input_shape) != len(EXPECTED_MEMBERS):
        fail("generated request member count changed")
    if member_values(model, "Member_Name", input_shape) != EXPECTED_MEMBERS:
        fail("generated request member names changed")
    if member_values(model, "Location", input_shape) != [
        "URI_Location", "Header_Location",
    ]:
        fail("generated request member locations changed")

    members = read_tsv(CORPUS / "members.tsv", MEMBER_HEADER)
    vectors = read_tsv(CORPUS / "vectors.tsv", VECTOR_HEADER)
    if [row["member"] for row in members] != EXPECTED_MEMBERS:
        fail("manifest member names changed")
    if [int(row["ordinal"]) for row in members] != [1, 2]:
        fail("manifest ordinals are not contiguous")
    if any(row["direction"] != "request" or row["shape"] != "146"
           or row["current_boundary"] != "projected" for row in members):
        fail("manifest shape or boundary changed")

    vector_by_id: dict[str, dict[str, str]] = {}
    for vector in vectors:
        vector_id = vector["id"]
        if not re.fullmatch(r"DBC-(?:RQ|RS|TR)-\d{3}", vector_id):
            fail(f"noncanonical vector id: {vector_id}")
        if vector_id in vector_by_id:
            fail(f"duplicate vector id: {vector_id}")
        vector_by_id[vector_id] = vector

    member_keys = {f'request:{row["member"]}' for row in members}
    referenced_vectors: set[str] = set()
    for member in members:
        member_key = f'request:{member["member"]}'
        for vector_id in comma_values(member["vector_ids"]):
            vector = vector_by_id.get(vector_id)
            if vector is None:
                fail(f"{member_key}: unknown vector {vector_id}")
            if member_key not in comma_values(vector["member_refs"]):
                fail(f"{member_key}: {vector_id} lacks reciprocal reference")
            referenced_vectors.add(vector_id)

    for vector_id, vector in vector_by_id.items():
        for reference in comma_values(vector["member_refs"]):
            if reference == "operation:DeleteBucketCors":
                continue
            if reference not in member_keys:
                fail(f"{vector_id}: unknown member reference {reference}")
        if vector_id not in referenced_vectors and \
                "operation:DeleteBucketCors" not in comma_values(
                    vector["member_refs"]
                ):
            fail(f"{vector_id}: unreachable vector")

    data = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    verify_registry(data)
    verify_registry_negatives(data)
    verify_sources()

    print(
        "DeleteBucketCors preparation: exact 204 empty response, 2 request "
        f"members, {len(vectors)} reciprocal vectors, certainty, lifecycle, "
        "server, backend, registry, and docs match"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, UnicodeError, ValueError) as exc:
        print(
            f"DeleteBucketCors preparation verification failed: {exc}",
            file=sys.stderr,
        )
        raise SystemExit(1)
