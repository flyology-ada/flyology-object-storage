#!/usr/bin/env python3
"""Fail-closed static evidence for reviewed ListObjectsV2 qualification."""

from __future__ import annotations

import re
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "coverage" / "s3-operations.toml"
LOW_SPEC = ROOT / "src" / "flyology-object_storage-client-low_level.ads"
LOW_BODY = ROOT / "src" / "flyology-object_storage-client-low_level.adb"
OBJECTS_SPEC = ROOT / "src" / "flyology-object_storage-client-objects.ads"
OBJECTS_BODY = ROOT / "src" / "flyology-object_storage-client-objects.adb"
SOCKET = ROOT / "tests" / "src" / "s3_http_socket_corpus.adb"
BACKEND = ROOT / "tests" / "src" / "object_storage_test_cases.adb"
SERVER = ROOT / "tests" / "src" / "s3_server_application_corpus.adb"

EXPECTED_ERRORS = [
    "authentication",
    "authorization",
    "not_found",
    "invalid_request",
    "unavailable_or_retryable",
    "corrupt_or_invalid_response",
]
EXPECTED_SYMBOLS = [
    "Prepare_List_Objects_V2",
    "Decode_List_Objects_V2_Complete_Response",
    "Execute_List_Objects_V2",
    "List_Objects_V2_Operation",
    "List_Page",
    "Finish",
]


def fail(message: str) -> None:
    raise SystemExit(f"ListObjectsV2 preparation failed: {message}")


def region(source: str, start: str, end: str, label: str) -> str:
    first = source.find(start)
    if first < 0:
        fail(f"{label}: missing start marker")
    if source.find(start, first + 1) >= 0:
        fail(f"{label}: duplicate start marker")
    last = source.find(end, first)
    if last < 0:
        fail(f"{label}: missing end marker")
    return source[first:last + len(end)]


def ordered(source: str, fragments: list[str], label: str) -> None:
    normalized = re.sub(r"\s+", " ", source)
    position = -1
    for fragment in fragments:
        expected = re.sub(r"\s+", " ", fragment)
        if normalized.count(expected) != 1:
            fail(f"{label}: fragment count changed: {fragment!r}")
        next_position = normalized.find(expected)
        if next_position <= position:
            fail(f"{label}: fragment order changed: {fragment!r}")
        position = next_position


def operation_entry() -> dict[str, object]:
    raw = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    matches = [
        entry for entry in raw["operation"]
        if entry.get("name") == "ListObjectsV2"
    ]
    if len(matches) != 1:
        fail("registry entry count changed")
    lane = raw["qualification"].get("list_objects_v2")
    if lane != [
        ["uv", "run", "--python", "3.13", "--",
         "tools/verify-list-objects-v2-preparation.py"],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
        ["./tools/build-api-docs.sh",
         "/private/tmp/fos-list-objects-v2-gnatdoc"],
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]:
        fail("qualification lane changed")
    return matches[0]


def main() -> int:
    entry = operation_entry()
    expected = {
        "provider": "objects",
        "family": "paginated_rest_xml_read",
        "public_provider": "Flyology.Object_Storage.Client.Objects",
        "codec": "strict_paginated_rest_xml_and_singleton_headers",
        "public_name": "List_Page",
        "certainty": "read_only",
        "reconciliation": "not_applicable",
        "human_decisions_resolved": True,
        "decision_status": "reviewed",
        "qualification": "list_objects_v2",
    }
    for key, value in expected.items():
        if entry.get(key) != value:
            fail(f"registry {key} changed")
    if entry.get("errors") != EXPECTED_ERRORS:
        fail("reviewed error categories changed")
    if entry.get("ada_symbols") != EXPECTED_SYMBOLS:
        fail("public symbol inventory changed")
    if "404 NoSuchBucket" not in str(entry.get("absence")):
        fail("reviewed absence contract changed")

    low_spec = LOW_SPEC.read_text(encoding="utf-8")
    low_body = LOW_BODY.read_text(encoding="utf-8")
    objects_spec = OBJECTS_SPEC.read_text(encoding="utf-8")
    objects_body = OBJECTS_BODY.read_text(encoding="utf-8")

    low_region = region(
        low_body,
        "function Decode_List_Objects_V2_Complete_Response",
        "end Decode_List_Objects_V2_Complete_Response;",
        "complete decoder",
    )
    ordered(
        low_region,
        [
            "Prepared.Operation /= List_Objects_V2_Operation",
            'Singleton_Header ("x-amz-request-charged")',
            'Singleton_Header ("x-amz-request-id")',
            'Singleton_Header ("x-amz-id-2")',
            "Prepared.Requested_URL_Encoding",
            "Outcome.Listing.Name /= Prepared.Requested_Bucket",
            "Outcome.Listing.Prefix",
            "Prepared.Requested_Prefix",
            "Outcome.Listing.Delimiter",
            "Prepared.Requested_Delimiter",
            "Outcome.Listing.Continuation_Token",
            "Prepared.Requested_Continuation_Token",
            "Outcome.Listing.Start_After",
            "Prepared.Requested_Start_After",
            "Outcome.Listing.Max_Keys",
            "Prepared.Requested_Max_Keys",
            "Outcome.Listing.Encoding_Type",
            "Expected_Encoding",
            '"ListObjectsV2 response does not match prepared request"',
        ],
        "complete decoder",
    )
    for symbol in EXPECTED_SYMBOLS[:3]:
        if symbol not in low_spec or symbol not in low_body:
            fail(f"low-level symbol missing: {symbol}")

    type_region = region(
        objects_spec,
        "type List_Objects_V2_Operation\n"
        "     (Set : not null access "
        "Flyology.Operations.Completion_Set'Class;\n"
        "      HTTP : not null access Flyology.HTTP.Client.Client;",
        "Flyology.HTTP.Client.Response_Body_Sink with private;",
        "public operation type",
    )
    ordered(
        type_region,
        [
            "Cancellation : access Flyology.Cancellation.Token) is",
            "new Flyology.Operations.Operation and",
            "Flyology.HTTP.Client.Response_Body_Sink with private;",
        ],
        "public operation type",
    )
    start_region = region(
        objects_body,
        "procedure Start_List_Objects_V2",
        "end Start_List_Objects_V2;",
        "provider restart",
    )
    ordered(
        start_region,
        [
            "Operation.HTTP /= Client or else "
            "Operation.Cancellation /= Token",
            '"ListObjectsV2 restart changed a retained owner"',
            "Low_Level.Prepare_List_Objects_V2",
            "Flyology.Bytes.Clear (Operation.Response_Data);",
            "S3.XML.Default_Limits.Maximum_Document_Bytes",
            "Operation_Drivers.Start (Operation);",
            "Operations.Drive",
            "Operation_Drivers.Rollback_Start (Operation);",
            "Low.Clear_Prepared_Request (Operation.Prepared);",
        ],
        "provider restart",
    )
    drive_region = region(
        objects_body,
        "overriding procedure Drive\n"
        "     (Item : in out List_Objects_V2_Operation;",
        "end Drive;",
        "provider drive",
    )
    ordered(
        drive_region,
        [
            "Low.List_Objects_V2 (Item.HTTP, Item.Prepared'Access, "
            "Item'Access, Item.Deadline, Item.Cancellation, Item.Child);",
            "Operations.Continue_After (Item, Item.Child);",
            "Complete_List_Objects_V2_Child (Item);",
            "Operation_Drivers.Complete (Item, Operations.Failed);",
        ],
        "provider drive",
    )
    for token in (
        "function List_Page",
        "procedure List_Page",
        "List_Objects_V2_Operation",
        "List_Objects_V2_Result",
    ):
        if token not in objects_spec or token not in objects_body:
            fail(f"provider surface missing: {token}")

    socket = SOCKET.read_text(encoding="utf-8")
    socket_region = region(
        socket,
        '"high-level ListObjects v1 accepted malformed URL marker";',
        '"composed ListObjectsV2 continuation mismatch";',
        "socket evidence",
    )
    ordered(
        socket_region,
        [
            "Low_Level.Execute_List_Objects_V2",
            '"typed ListObjectsV2 socket success mismatch"',
            "Require_Invalid_List_Objects_V2",
            '"ListObjectsV2 accepted a wrong echoed bucket"',
            '"ListObjectsV2 accepted a duplicate singleton header"',
            '"pre-admission ListObjectsV2 cancellation mismatch"',
            '"high-level ListObjectsV2 continuation mismatch"',
            "Operation : List_Objects_V2_Operation :=",
            '"composed ListObjectsV2 first page mismatch"',
            '"composed ListObjectsV2 continuation mismatch"',
        ],
        "socket evidence",
    )
    if "List_Objects_V2" not in BACKEND.read_text(encoding="utf-8"):
        fail("backend evidence missing")
    if "ListObjectsV2" not in SERVER.read_text(encoding="utf-8"):
        fail("server evidence missing")

    print(
        "ListObjectsV2 preparation: reviewed composable contract and "
        "cross-layer evidence OK"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
