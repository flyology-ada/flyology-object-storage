#!/usr/bin/env python3
"""Verify the reviewed UploadPartCopy source and registry boundary."""

from __future__ import annotations

import copy
import hashlib
import json
import os
import sys
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "coverage/s3-operations.toml"
LOW_SPEC = ROOT / "src/flyology-object_storage-client-low_level.ads"
LOW_BODY = ROOT / "src/flyology-object_storage-client-low_level.adb"
TRANSFER_SPEC = ROOT / "src/flyology-object_storage-client-transfers.ads"
TRANSFER_BODY = ROOT / "src/flyology-object_storage-client-transfers.adb"
TRANSFER_TEST = ROOT / "tests/src/flyology-object_storage-client-transfers-testing.adb"
DIRECT_TEST = ROOT / "tests/src/object_storage_test_cases.adb"
SOCKET = ROOT / "tests/src/s3_http_socket_corpus.adb"
SERVER_TEST = ROOT / "tests/src/s3_server_application_corpus.adb"
QUALIFICATION = ROOT / "docs/qualification/upload-part-copy.md"
MODEL_SHA256 = (
    "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
)
SYMBOLS = [
    "Prepare_Upload_Part_Copy",
    "Decode_Upload_Part_Copy_Complete_Response",
    "Execute_Upload_Part_Copy",
    "Upload_Part_Copy_Operation",
    "Upload_Part_Copy",
    "Finish",
]
CERTAINTY = (
    "only a complete validated 200 Part_Copied response observed reports "
    "Published; exact 412 PreconditionFailed reports Precondition_Failed; "
    "recognized complete authentication, authorization, not-found, "
    "invalid-request, and NotImplemented rejections or definite "
    "non-admission report Definitely_Not_Published; pre-admission "
    "cancellation reports Cancelled_Before_Publication; possible or "
    "incomplete admission and embedded or retryable errors report "
    "Outcome_Unknown; no automatic replay"
)
RECONCILIATION = (
    "read-only ListParts for the exact destination bucket, key, upload "
    "identifier, and part number before any caller-selected retry or "
    "completion decision"
)
LANE = [
    [
        "uv", "run", "--python", "3.13", "--",
        "tools/verify-upload-part-copy-preparation.py",
    ],
    ["@tests", "alr", "-n", "build"],
    ["@tests", "./bin/s3_http_socket_corpus"],
    ["./tools/verify-coverage.sh"],
    [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-upload-part-copy-gnatdoc",
    ],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]


def fail(message: str) -> None:
    raise ValueError(message)


def require_in_order(text: str, fragments: list[str], label: str) -> None:
    cursor = 0
    for fragment in fragments:
        position = text.find(fragment, cursor)
        if position < 0:
            fail(f"{label}: missing {fragment}")
        cursor = position + len(fragment)


def entry(data: dict[str, object]) -> dict[str, object]:
    matches = [
        value for value in data["operation"]
        if value["name"] == "UploadPartCopy"
    ]
    if len(matches) != 1:
        fail("UploadPartCopy registry entry is not unique")
    return matches[0]


def verify_registry(data: dict[str, object]) -> None:
    value = entry(data)
    expected = {
        "codec": "strict_rest_xml_request_and_bounded_response",
        "public_name": "Upload_Part_Copy",
        "certainty": CERTAINTY,
        "reconciliation": RECONCILIATION,
        "human_decisions_resolved": True,
        "decision_status": "reviewed",
        "qualification": "upload_part_copy",
        "ada_symbols": SYMBOLS,
    }
    for key, expected_value in expected.items():
        if value.get(key) != expected_value:
            fail(f"UploadPartCopy registry field changed: {key}")
    if "NoSuchBucket, NoSuchKey, and NoSuchUpload" not in value["absence"]:
        fail("UploadPartCopy absence contract changed")
    if "caller-selected source version" not in value["exclusions"][1]:
        fail("UploadPartCopy source binding changed")
    if "concurrent writer" not in value["exclusions"][3]:
        fail("UploadPartCopy reconciliation exclusion changed")
    if data["qualification"].get("upload_part_copy") != LANE:
        fail("UploadPartCopy qualification lane changed")


def verify_negatives(data: dict[str, object]) -> None:
    mutations = (
        ("missing name", "public_name", None),
        ("legacy certainty", "certainty", "legacy_preserved"),
        ("automatic replay", "reconciliation", "retry automatically"),
        ("unresolved", "human_decisions_resolved", False),
        ("cross symbol", "ada_symbols", ["Upload_Part"]),
        ("missing lane", "qualification", ""),
    )
    for label, key, replacement in mutations:
        candidate = copy.deepcopy(data)
        candidate_entry = entry(candidate)
        if replacement is None:
            del candidate_entry[key]
        else:
            candidate_entry[key] = replacement
        if candidate == data:
            fail(f"{label}: candidate did not change")
        try:
            verify_registry(candidate)
        except (IndexError, KeyError, TypeError, ValueError):
            continue
        fail(f"{label}: candidate was accepted")


def verify_model() -> None:
    name = os.environ.get("FLYOLOGY_S3_SERVICE_MODEL", "")
    if not name:
        fail("FLYOLOGY_S3_SERVICE_MODEL is required")
    path = Path(name)
    if not path.is_file() or path.is_symlink():
        fail("pinned model is not a regular file")
    if hashlib.sha256(path.read_bytes()).hexdigest() != MODEL_SHA256:
        fail("pinned model hash changed")
    operation = json.loads(path.read_text(encoding="utf-8"))["operations"][
        "UploadPartCopy"
    ]
    if operation["http"] != {
        "method": "PUT",
        "requestUri": "/{Bucket}/{Key+}",
    }:
        fail("UploadPartCopy HTTP contract changed")
    if operation["input"] != {"shape": "UploadPartCopyRequest"}:
        fail("UploadPartCopy request shape changed")
    if operation["output"] != {"shape": "UploadPartCopyOutput"}:
        fail("UploadPartCopy response shape changed")


def verify_sources() -> None:
    require_in_order(
        LOW_SPEC.read_text(encoding="utf-8"),
        [
            "type Upload_Part_Copy_Parameters is record",
            "Copy_Source",
            "Source_Range",
            "function Prepare_Upload_Part_Copy",
            "function Decode_Upload_Part_Copy_Complete_Response",
            "function Execute_Upload_Part_Copy",
        ],
        "UploadPartCopy low-level API",
    )
    require_in_order(
        LOW_BODY.read_text(encoding="utf-8"),
        [
            "function Prepare_Upload_Part_Copy",
            '"invalid UploadPartCopy parameters"',
            "function Decode_Upload_Part_Copy_Complete_Response",
            '"UploadPartCopy charged response was not requested"',
        ],
        "UploadPartCopy prepared binding",
    )
    require_in_order(
        TRANSFER_SPEC.read_text(encoding="utf-8"),
        [
            "type Upload_Part_Copy_Result_Kind is",
            "type Upload_Part_Copy_Operation",
            "procedure Upload_Part_Copy",
            "function Upload_Part_Copy",
            "procedure Finish",
        ],
        "UploadPartCopy composable API",
    )
    require_in_order(
        TRANSFER_BODY.read_text(encoding="utf-8"),
        [
            "function Normalize_Upload_Part_Copy_Response",
            "Precondition_Rejection",
            "Conclusive_Rejection",
            "function Normalize_Upload_Part_Copy_Failure",
            '"UploadPartCopy restart changed a retained owner"',
        ],
        "UploadPartCopy normalization",
    )
    require_in_order(
        TRANSFER_TEST.read_text(encoding="utf-8"),
        [
            "Normalize_Upload_Part_Copy_Response",
            "Normalize_Upload_Part_Copy_Failure",
            "procedure Check_Upload_Part_Copy_Certainty_Corpus",
        ],
        "UploadPartCopy certainty corpus",
    )
    require_in_order(
        DIRECT_TEST.read_text(encoding="utf-8"),
        [
            "Low_Level.Prepare_Upload_Part_Copy",
            "Low_Level.Decode_Upload_Part_Copy_Response",
        ],
        "UploadPartCopy direct tests",
    )
    require_in_order(
        SOCKET.read_text(encoding="utf-8"),
        [
            '"lost UploadPartCopy response certainty mismatch"',
            '"pre-admission UploadPartCopy cancellation mismatch"',
            '"direct UploadPartCopy restart mismatch"',
            '"typed UploadPartCopy rejection mismatch"',
        ],
        "UploadPartCopy socket evidence",
    )
    require_in_order(
        SERVER_TEST.read_text(encoding="utf-8"),
        [
            '"UploadPartCopy server response mismatch: "',
            '"configured composite UploadPartCopy checksum mismatch: "',
        ],
        "UploadPartCopy server evidence",
    )
    qualification = " ".join(
        QUALIFICATION.read_text(encoding="utf-8").split()
    )
    require_in_order(
        qualification,
        [
            "exact precondition rejection",
            "`UploadPartCopy` registry lane",
            "region-scoped warning measurement",
        ],
        "UploadPartCopy qualification",
    )


def main() -> int:
    verify_model()
    data = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    verify_registry(data)
    verify_negatives(data)
    verify_sources()
    print("UploadPartCopy preparation: model, registry, source, lifecycle, "
          "server, and qualification evidence match")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"UploadPartCopy preparation verification failed: {exc}",
              file=sys.stderr)
        raise SystemExit(1)
