#!/usr/bin/env python3
"""Verify the isolated CreateSession member inventory and design corpus."""

from __future__ import annotations

import csv
import copy
import re
import sys
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "tests" / "corpora" / "create-session"
MODEL = ROOT / "src" / "flyology-object_storage-s3-model.adb"
LOW_SPEC = ROOT / "src" / "flyology-object_storage-client-low_level.ads"
LOW_BODY = ROOT / "src" / "flyology-object_storage-client-low_level.adb"
HIGH_SPEC = ROOT / "src" / "flyology-object_storage-client-buckets.ads"
HIGH_BODY = ROOT / "src" / "flyology-object_storage-client-buckets.adb"
LOCK = ROOT / "coverage" / "corpora.lock.toml"
REGISTRY = ROOT / "coverage" / "s3-operations.toml"
QUALIFICATION = ROOT / "docs" / "qualification" / "create-session.md"
EXPECTED_REVISION = "36c34f15391da01cd717c73c0fffa747c9889768"
EXPECTED_SHA256 = "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
EXPECTED = {
    ("request", "137"): [
        "SessionMode", "Bucket", "ServerSideEncryption", "SSEKMSKeyId",
        "SSEKMSEncryptionContext", "BucketKeyEnabled",
    ],
    ("response", "136"): [
        "ServerSideEncryption", "SSEKMSKeyId", "SSEKMSEncryptionContext",
        "BucketKeyEnabled", "Credentials",
    ],
    ("credential", "652"): [
        "AccessKeyId", "SecretAccessKey", "SessionToken", "Expiration",
    ],
}
MEMBER_HEADER = [
    "direction", "shape", "ordinal", "member", "wire_location",
    "current_boundary", "required_contract", "vector_ids",
]
VECTOR_HEADER = [
    "id", "direction", "layer", "category", "member_refs", "stimulus",
    "expected_contract",
]
LOCATION = {
    "uri-label": "URI_Location",
    "header": "Header_Location",
    "body": "Body_Location",
}
LANE = [
    ["uv", "run", "--python", "3.13", "--",
     "tools/verify-create-session-preparation.py"],
    ["@tests", "alr", "-n", "build"],
    ["@tests", "./bin/s3_create_session_tls_corpus"],
    ["./tools/verify-coverage.sh"],
    ["./tools/build-api-docs.sh", "/private/tmp/fos-create-session-gnatdoc"],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]


def fail(message: str) -> None:
    raise ValueError(message)


def registry_entry(data: dict[str, object]) -> dict[str, object]:
    matches = [
        entry for entry in data["operation"]
        if entry["name"] == "CreateSession"
    ]
    if len(matches) != 1:
        fail("CreateSession registry entry is not unique")
    return matches[0]


def verify_registry(data: dict[str, object]) -> None:
    entry = registry_entry(data)
    expected = {
        "public_name": "Create_Session",
        "decision_status": "reviewed",
        "human_decisions_resolved": True,
        "qualification": "create_session",
        "codec": "rest_xml_and_headers",
        "certainty": "read_only",
        "reconciliation": "not_applicable",
        "coverage": {
            "backend": "missing",
            "client": "covered",
            "server": "missing",
            "corpus": "covered",
        },
        "ada_symbols": [
            "Prepare_Create_Session",
            "Decode_Create_Session_Complete_Response",
            "Execute_Create_Session",
            "Create_Session_Operation",
            "Create_Session",
            "Finish",
        ],
    }
    for key, value in expected.items():
        if entry.get(key) != value:
            fail(f"CreateSession registry changed: {key}")
    if "exact HTTP 200" not in entry["exclusions"][1]:
        fail("CreateSession success boundary changed")
    if "zeroizing Credentials" not in entry["exclusions"][2]:
        fail("CreateSession credential ownership changed")
    if "no refresh task" not in entry["exclusions"][3]:
        fail("CreateSession lifecycle boundary changed")
    if data["qualification"].get("create_session") != LANE:
        fail("CreateSession qualification lane changed")


def verify_registry_negatives(data: dict[str, object]) -> None:
    mutations = (
        ("missing public name", "public_name", None),
        ("wrong public name", "public_name", "Create_Directory_Session"),
        ("mutation certainty", "certainty", "outcome_unknown"),
        ("cross-operation lane", "qualification", "create_multipart_upload"),
        (
            "cross-operation symbols",
            "ada_symbols",
            ["Prepare_Create_Multipart_Upload"],
        ),
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
        except (KeyError, TypeError, ValueError):
            continue
        fail(f"{label}: candidate was accepted")


def read_tsv(path: Path, header: list[str]) -> list[dict[str, str]]:
    raw = path.read_bytes()
    if b"\r" in raw:
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


def function_body(model: str, name: str) -> str:
    match = re.search(rf"   function {re.escape(name)}(?=\s*\()", model)
    if match is None:
        fail(f"generated model has no {name}")
    tail = model[match.end():]
    try:
        return tail.split(f"end {name};", 1)[0]
    except IndexError as exc:
        raise ValueError(f"generated model has no end for {name}") from exc


def shape_block(model: str, function: str, shape: str) -> str:
    body = function_body(model, function)
    match = re.search(
        rf"when {re.escape(shape)} =>\s+case Member is(?P<body>.*?)"
        r"\s+end case;",
        body,
        re.DOTALL,
    )
    if match is None:
        fail(f"generated model has no {function} block for shape {shape}")
    return match.group("body")


def generated_values(model: str, function: str, shape: str) -> list[str]:
    pattern = (
        r'when\s+(\d+)\s+=>\s+return\s+"([^"]+)";'
        if function == "Member_Name"
        else r"when\s+(\d+)\s+=>\s+return\s+([A-Za-z_]+);"
    )
    pairs = re.findall(pattern, shape_block(model, function, shape))
    if [int(number) for number, _ in pairs] != list(range(1, len(pairs) + 1)):
        fail(f"shape {shape} {function} order is not contiguous")
    return [value for _, value in pairs]


def generated_count(model: str, shape: str) -> int:
    body = function_body(model, "Member_Count")
    match = re.search(rf"when\s+{shape}\s+=>\s+return\s+(\d+);", body)
    if match is None:
        fail(f"generated model has no count for shape {shape}")
    return int(match.group(1))


def csv_values(value: str) -> list[str]:
    result = value.split(",")
    if any(item == "" or item != item.strip() for item in result):
        fail(f"noncanonical comma list: {value!r}")
    if len(result) != len(set(result)):
        fail(f"duplicate comma-list value: {value!r}")
    return result


def main() -> int:
    lock = LOCK.read_text(encoding="utf-8")
    if f'revision = "{EXPECTED_REVISION}"' not in lock:
        fail("pinned botocore revision changed")
    if f'service_model_sha256 = "{EXPECTED_SHA256}"' not in lock:
        fail("pinned botocore service hash changed")

    model = MODEL.read_text(encoding="utf-8")
    sources = {
        "low-level specification": LOW_SPEC.read_text(encoding="utf-8"),
        "low-level body": LOW_BODY.read_text(encoding="utf-8"),
        "provider specification": HIGH_SPEC.read_text(encoding="utf-8"),
        "provider body": HIGH_BODY.read_text(encoding="utf-8"),
    }
    members = read_tsv(CORPUS / "members.tsv", MEMBER_HEADER)
    vectors = read_tsv(CORPUS / "vectors.tsv", VECTOR_HEADER)
    vector_by_id: dict[str, dict[str, str]] = {}
    for row in vectors:
        vector_id = row["id"]
        if not re.fullmatch(r"CS-(?:RQ|RS|TR|OR)-\d{3}", vector_id):
            fail(f"noncanonical vector id: {vector_id}")
        if vector_id in vector_by_id:
            fail(f"duplicate vector id: {vector_id}")
        vector_by_id[vector_id] = row

    grouped: dict[tuple[str, str], list[dict[str, str]]] = {}
    member_keys: set[str] = set()
    referenced: set[str] = set()
    for row in members:
        key = (row["direction"], row["shape"])
        grouped.setdefault(key, []).append(row)
        member_key = f'{row["direction"]}:{row["member"]}'
        if member_key in member_keys:
            fail(f"duplicate member: {member_key}")
        member_keys.add(member_key)
        for vector_id in csv_values(row["vector_ids"]):
            vector = vector_by_id.get(vector_id)
            if vector is None:
                fail(f"{member_key}: unknown vector {vector_id}")
            if member_key not in csv_values(vector["member_refs"]):
                fail(f"{member_key}: {vector_id} lacks reciprocal reference")
            referenced.add(vector_id)

    if set(grouped) != set(EXPECTED):
        fail(f"unexpected direction/shape groups: {sorted(grouped)}")
    for key, expected_names in EXPECTED.items():
        rows = grouped[key]
        if [int(row["ordinal"]) for row in rows] != list(
            range(1, len(expected_names) + 1)
        ):
            fail(f"{key}: manifest ordinals are not contiguous")
        if [row["member"] for row in rows] != expected_names:
            fail(f"{key}: manifest names differ from pinned inventory")
        if generated_count(model, key[1]) != len(expected_names):
            fail(f"{key}: generated member count differs")
        if generated_values(model, "Member_Name", key[1]) != expected_names:
            fail(f"{key}: generated names differ")
        expected_locations = generated_values(model, "Location", key[1])
        actual_locations = [LOCATION[row["wire_location"]] for row in rows]
        if actual_locations != expected_locations:
            fail(f"{key}: generated wire locations differ")

    for vector_id, vector in vector_by_id.items():
        for reference in csv_values(vector["member_refs"]):
            if reference.startswith("operation:"):
                if reference != "operation:CreateSession":
                    fail(f"{vector_id}: unexpected operation reference")
            elif reference not in member_keys:
                fail(f"{vector_id}: unknown member reference {reference}")
        if vector_id not in referenced and "operation:CreateSession" not in \
                csv_values(vector["member_refs"]):
            fail(f"{vector_id}: unreachable vector")

    composable_patterns = {
        "low-level specification": [
            r"\bprocedure\s+Create_Session\b",
            r"\btype\s+Create_Session_Response_Metadata\b",
            r"\bfunction\s+Decode_Create_Session_Complete_Response\b",
            r"Operation\s*:\s*in\s+out\s+"
            r"Flyology\.HTTP\.Client\.Exchange_Operation",
        ],
        "low-level body": [
            r"\bprocedure\s+Create_Session\b",
            r"Start_Sink\s*\(\s*Create_Session_Operation",
            r"\bfunction\s+Read_Create_Session_Response_Metadata\b",
            r"\bfunction\s+Decode_Create_Session_Complete_Response\b",
        ],
        "provider specification": [
            r"\btype\s+Create_Session_Operation\b",
            r"\btype\s+Create_Session_Result\b",
            r"\bfunction\s+Finish\s*\(\s*Operation\s*:\s*in\s+out\s+"
            r"Create_Session_Operation",
        ],
        "provider body": [
            r"\bprocedure\s+Start_Create_Session\b",
            r"\bfunction\s+Finish_Create_Session_Response\b",
            r"Low\.Create_Session",
            r"Low_Level\.Decode_Create_Session_Complete_Response",
        ],
    }
    for label, patterns in composable_patterns.items():
        for pattern in patterns:
            if re.search(pattern, sources[label]) is None:
                fail(f"CreateSession composable API absent from {label}")
    for label in ("provider specification", "provider body"):
        if sources[label].count("function Create_Session") != 3:
            fail(f"CreateSession function overload count changed in {label}")
        if sources[label].count("procedure Create_Session") != 1:
            fail(f"CreateSession reusable overload count changed in {label}")

    decoder = function_body(
        sources["low-level body"], "Decode_Create_Session_Complete_Response"
    )
    operation_check = decoder.find(
        "if Prepared.Operation /= Create_Session_Operation then"
    )
    metadata_check = decoder.find("elsif not Metadata.Validated then")
    session_field_accesses = [
        decoder.find("Prepared.Requested_Session_Server_Side_Encryption"),
        decoder.find("Prepared.Requested_Session_SSE_KMS_Key_ID"),
        decoder.find("Prepared.Requested_Session_SSE_KMS_Encryption_Context"),
        decoder.find("Prepared.Requested_Session_Bucket_Key_Enabled"),
    ]
    if (
        operation_check < 0
        or metadata_check < 0
        or any(position < 0 for position in session_field_accesses)
    ):
        fail("CreateSession complete decoder binding structure changed")
    if not operation_check < metadata_check < min(session_field_accesses):
        fail("CreateSession decoder reads response/request fields before validation")

    registry = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    verify_registry(registry)
    verify_registry_negatives(registry)
    qualification = " ".join(
        QUALIFICATION.read_text(encoding="utf-8").split()
    )
    for fact in (
        "reviewed operation as `missing / covered / missing / covered`",
        "No overload creates a refresh task",
        "Repository-wide qualification remains blocked",
    ):
        if fact not in qualification:
            fail(f"CreateSession qualification record lacks {fact}")

    print(
        "CreateSession preparation: 6 request members, 5 top-level response "
        f"members, 4 credential members, {len(vectors)} contract vectors; "
        "pinned model, references, and composable API match"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, UnicodeError, ValueError) as exc:
        print(f"CreateSession preparation verification failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
