#!/usr/bin/env python3
"""Verify PutBucketCors inventory and reciprocal corpus graph."""

from __future__ import annotations

import copy
import csv
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "tests/corpora/put-bucket-cors"
MODEL = ROOT / "src/flyology-object_storage-s3-model.adb"
LOCK = ROOT / "coverage/corpora.lock.toml"
REGISTRY = ROOT / "coverage/s3-operations.toml"
TESTING = ROOT / "tests/src/flyology-object_storage-client-buckets-testing.adb"
SOCKET = ROOT / "tests/src/s3_http_socket_corpus.adb"
SERVER = ROOT / "src/flyology-object_storage-server-s3_applications.adb"
SERVER_TEST = ROOT / "tests/src/s3_server_application_corpus.adb"
QUALIFICATION = ROOT / "docs/qualification/put-bucket-cors.md"
SOURCES = (
    ROOT / "src/flyology-object_storage-client-low_level.ads",
    ROOT / "src/flyology-object_storage-client-low_level.adb",
    ROOT / "src/flyology-object_storage-client-buckets.ads",
    ROOT / "src/flyology-object_storage-client-buckets.adb",
    ROOT / "src/flyology-object_storage-s3-bucket_controls.ads",
    ROOT / "src/flyology-object_storage-s3-bucket_controls.adb",
)
REVISION = "36c34f15391da01cd717c73c0fffa747c9889768"
SHA256 = "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
EXPECTED = [
    ("request", 527, 1, "Bucket", 60, "uri-label", "true", "projected"),
    ("request", 527, 2, "CORSConfiguration", 70, "body", "true", "encoded"),
    ("request", 527, 3, "ContentMD5", 111, "header", "false", "projected"),
    ("request", 527, 4, "ChecksumAlgorithm", 77, "header", "false", "projected"),
    ("request", 527, 5, "ExpectedBucketOwner", 15, "header", "false", "projected"),
    ("nested", 70, 1, "CORSRules", 72, "body", "true", "encoded"),
    ("nested", 71, 1, "ID", 308, "body", "false", "encoded"),
    ("nested", 71, 2, "AllowedHeaders", 18, "body", "false", "encoded"),
    ("nested", 71, 3, "AllowedMethods", 20, "body", "true", "encoded"),
    ("nested", 71, 4, "AllowedOrigins", 22, "body", "true", "encoded"),
    ("nested", 71, 5, "ExposeHeaders", 211, "body", "false", "encoded"),
    ("nested", 71, 6, "MaxAgeSeconds", 412, "body", "false", "encoded"),
]
MEMBER_HEADER = ["direction", "shape", "ordinal", "member", "member_shape",
                 "wire_location", "required", "current_boundary",
                 "required_contract", "vector_ids"]
VECTOR_HEADER = ["id", "direction", "layer", "category", "member_refs",
                 "stimulus", "expected_contract"]
LOCATION = {"URI_Location": "uri-label", "Header_Location": "header",
            "Body_Location": "body", "Query_Location": "query"}
PUT_CORS_CERTAINTY = (
    "only a complete validated 200 response with an empty or XML-whitespace "
    "body reports Bucket_CORS_Mutation_Completed; an exact recognized "
    "non-mutating rejection or definite non-admission reports "
    "Bucket_CORS_Mutation_Definitely_Not_Applied; pre-admission cancellation "
    "reports Bucket_CORS_Mutation_Cancelled_Before_Admission; possible or "
    "incomplete admission, retryable responses, and malformed or oversized "
    "responses report Bucket_CORS_Mutation_Outcome_Unknown; no automatic "
    "replay"
)
PUT_CORS_RECONCILIATION = (
    "caller-selected Get_CORS may observe the current exact CORS "
    "configuration or NoSuchCORSConfiguration before a retry, but does not "
    "prove that the lost replacement caused the observed state or upgrade "
    "mutation certainty; no automatic replay"
)
PUT_CORS_LANE = [
    ["uv", "run", "--python", "3.13", "--",
     "tools/verify-put-bucket-cors-preparation.py"],
    ["@tests", "alr", "-n", "build"],
    ["@tests", "./bin/s3_get_bucket_cors_corpus"],
    ["@tests", "./bin/s3_server_application_corpus"],
    ["@tests", "./bin/s3_http_socket_corpus"],
    ["./tools/verify-coverage.sh"],
    ["./tools/build-api-docs.sh",
     "/private/tmp/fos-put-bucket-cors-gnatdoc"],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]
PUT_CORS_SYMBOLS = [
    "Prepare_Put_Bucket_CORS",
    "Execute_Put_Bucket_CORS",
    "Put_Bucket_CORS_Operation",
    "Set_CORS",
    "Finish",
]


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
    match = re.search(r"when Put_Bucket_Cors_Operation =>\s+return\s+([^;]+);",
                      function_body(model, function))
    if match is None:
        fail(f"PutBucketCors lacks {function}")
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
    value = r'"([^\"]*)"' if function in (
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


def registry_entry(data: dict[str, object]) -> dict[str, object]:
    matches = [
        entry for entry in data["operation"]
        if entry["name"] == "PutBucketCors"
    ]
    if len(matches) != 1:
        fail("PutBucketCors is not unique")
    return matches[0]


def verify_registry(data: dict[str, object]) -> None:
    entry = registry_entry(data)
    expected = {
        "public_name": "Set_CORS",
        "decision_status": "reviewed",
        "human_decisions_resolved": True,
        "qualification": "put_bucket_cors",
        "certainty": PUT_CORS_CERTAINTY,
        "reconciliation": PUT_CORS_RECONCILIATION,
        "coverage": {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        },
        "ada_symbols": PUT_CORS_SYMBOLS,
    }
    for key, value in expected.items():
        if entry.get(key) != value:
            fail(f"PutBucketCors changed: {key}")
    if "atomically replaces" not in entry["absence"]:
        fail("PutBucketCors replacement semantics changed")
    if "exact HTTP 200" not in entry["exclusions"][0]:
        fail("PutBucketCors success changed")
    if "Content-MD5" not in entry["exclusions"][1]:
        fail("PutBucketCors checksum binding changed")
    if "does not establish causation" not in entry["exclusions"][3]:
        fail("PutBucketCors reconciliation changed")
    if data["qualification"].get("put_bucket_cors") != PUT_CORS_LANE:
        fail("PutBucketCors lane changed")


def verify_registry_negatives(data: dict[str, object]) -> None:
    mutations = (
        ("missing public name", "public_name", None),
        ("wrong public name", "public_name", "Get_CORS"),
        ("broadened success", "exclusions", []),
        ("causal reconciliation", "reconciliation", "Get_CORS proves put"),
        ("cross-operation lane", "qualification", "get_bucket_cors"),
        ("cross-operation symbols", "ada_symbols", ["Get_CORS"]),
    )
    for label, key, value in mutations:
        candidate = copy.deepcopy(data)
        entry = registry_entry(candidate)
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        if candidate == data:
            fail(f"{label}: candidate did not change")
        try:
            verify_registry(candidate)
        except (IndexError, KeyError, TypeError, ValueError):
            continue
        fail(f"{label}: candidate was accepted")


def require_in_order(text: str, fragments: list[str], label: str) -> None:
    cursor = 0
    for fragment in fragments:
        position = text.find(fragment, cursor)
        if position < 0:
            fail(f"{label}: missing {fragment}")
        cursor = position + len(fragment)


def main() -> int:
    lock = LOCK.read_text(encoding="utf-8")
    if f'revision = "{REVISION}"' not in lock or \
            f'service_model_sha256 = "{SHA256}"' not in lock:
        fail("pinned botocore identity changed")
    model = MODEL.read_text(encoding="utf-8")
    scalars = {
        "Method": "Put_Method", "Request_URI": "/{Bucket}?cors",
        "Response_Code": "200", "Input_Shape": "527", "Output_Shape": "0",
        "Request_Checksum_Required": "True",
        "Request_Checksum_Algorithm_Member": "ChecksumAlgorithm",
    }
    for function, expected in scalars.items():
        if operation_scalar(model, function) != expected:
            fail(f"generated {function} changed")
    for shape, member in ((72, 71), (18, 17), (20, 19),
                          (22, 21), (211, 210)):
        if shape_scalar(model, "Kind", shape) != "List_Shape" or \
                shape_scalar(model, "List_Member_Shape", shape) != str(member) or \
                shape_scalar(model, "Is_Flattened", shape) != "True":
            fail(f"generated flattened CORS list {shape} changed")
    if shape_scalar(model, "Kind", 412) != "Integer_Shape" or \
            shape_scalar(model, "Minimum", 412) != "" or \
            shape_scalar(model, "Maximum", 412) != "":
        fail("generated unbounded MaxAgeSeconds contract changed")
    if enum_values(model, 77) != [
            "CRC32", "CRC32C", "SHA1", "SHA256", "CRC64NVME", "SHA512",
            "MD5", "XXHASH64", "XXHASH3", "XXHASH128"]:
        fail("generated checksum algorithm enum changed")

    generated = []
    for direction, shape, boundary in (
            ("request", 527, "projected"), ("nested", 70, "encoded"),
            ("nested", 71, "encoded")):
        names = case_values(model, "Member_Name", shape)
        shapes = case_values(model, "Member_Shape", shape)
        locations = case_values(model, "Location", shape)
        required = case_values(model, "Member_Required", shape)
        for index, name in enumerate(names):
            member_boundary = (
                "encoded" if shape == 527 and name == "CORSConfiguration"
                else boundary)
            generated.append((direction, shape, index + 1, name,
                              int(shapes[index]), LOCATION[locations[index]],
                              required[index].lower(), member_boundary))
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
        if any(ref != "operation:PutBucketCors" and ref not in member_keys
               for ref in refs):
            fail(f'{vector["id"]}: unknown member reference')
        if vector["id"] not in reached and "operation:PutBucketCors" not in refs:
            fail(f'{vector["id"]}: unreachable vector')
    source = "\n".join(path.read_text(encoding="utf-8") for path in SOURCES)
    for token in ("Serialize_CORS", "Prepare_Put_Bucket_CORS",
                  "Execute_Put_Bucket_CORS", "Put_Bucket_CORS_Operation",
                  "Set_CORS", "content-md5",
                  "x-amz-sdk-checksum-algorithm"):
        if token not in source:
            fail(f"typed implementation lacks {token}")
    registry = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    verify_registry(registry)
    verify_registry_negatives(registry)
    require_in_order(
        source,
        [
            "function Normalize_Put_Bucket_CORS_Response",
            "Bucket_CORS_Mutation_Completed",
            "function Normalize_Put_Bucket_CORS_Failure",
            "PutBucketCors restart changed a retained owner",
        ],
        "PutBucketCors provider",
    )
    require_in_order(
        TESTING.read_text(encoding="utf-8"),
        [
            "Bucket_CORS_Mutation_Definitely_Not_Applied",
            "Bucket_CORS_Mutation_Outcome_Unknown",
            "(200, \"\", Bucket_CORS_Mutation_Completed, No_Failure)",
        ],
        "PutBucketCors normalization",
    )
    require_in_order(
        SERVER.read_text(encoding="utf-8"),
        [
            "when Put_Bucket_CORS =>",
            "Store.Put_Bucket_CORS",
            "Apps.Respond (X, 200",
        ],
        "PutBucketCors server",
    )
    require_in_order(
        SERVER_TEST.read_text(encoding="utf-8"),
        [
            '"PutBucketCors rejected a valid configuration',
            '"PutBucketCors rejected a valid SDK checksum',
            '"PutBucketCors accepted a mismatched Content-MD5"',
        ],
        "PutBucketCors server corpus",
    )
    require_in_order(
        SOCKET.read_text(encoding="utf-8"),
        [
            '"typed PutBucketCors response mismatch"',
            '"composed PutBucketCors result mismatch"',
            '"restarted PutBucketCors result mismatch"',
        ],
        "PutBucketCors socket corpus",
    )
    qualification = " ".join(
        QUALIFICATION.read_text(encoding="utf-8").split()
    )
    require_in_order(
        qualification,
        [
            "`PutBucketCors` registry lane",
            "exact HTTP-200 completion",
            "unknown outcome after possible admission",
            "region-scoped warning measurement only",
        ],
        "PutBucketCors qualification",
    )
    print("PutBucketCors preparation: 12 modeled members, five flattened "
          f"lists, unbounded integer text, 10 checksum values, "
          f"{len(vectors)} vectors; registry, persistence, routing, and "
          "docs match")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, UnicodeError, ValueError) as exc:
        print(f"PutBucketCors verification failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
