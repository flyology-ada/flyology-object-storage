#!/usr/bin/env python3
"""Verify the reviewed model-only SelectObjectContent boundary."""

from __future__ import annotations

import hashlib
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODEL_SHA256 = (
    "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
)
REACHABLE_SHAPES = [
    "AccountId", "AllowQuotedRecordDelimiter", "Body", "BucketName",
    "BytesProcessed", "BytesReturned", "BytesScanned", "CSVInput",
    "CSVOutput", "Comments", "CompressionType", "ContinuationEvent",
    "EnableRequestProgress", "End", "EndEvent", "Expression",
    "ExpressionType", "FieldDelimiter", "FileHeaderInfo",
    "InputSerialization", "JSONInput", "JSONOutput", "JSONType",
    "ObjectKey", "OutputSerialization", "ParquetInput", "Progress",
    "ProgressEvent", "QuoteCharacter", "QuoteEscapeCharacter",
    "QuoteFields", "RecordDelimiter", "RecordsEvent", "RequestProgress",
    "SSECustomerAlgorithm", "SSECustomerKey", "SSECustomerKeyMD5",
    "ScanRange", "SelectObjectContentEventStream",
    "SelectObjectContentOutput", "SelectObjectContentRequest", "Start",
    "Stats", "StatsEvent",
]


def fail(message: str) -> None:
    raise ValueError(message)


def members(shape: dict) -> list[tuple[str, str, str, str]]:
    return [
        (
            name,
            item["shape"],
            item.get("location", "body"),
            item.get("locationName", name),
        )
        for name, item in shape["members"].items()
    ]


def reachable_shapes(model: dict, roots: list[str]) -> list[str]:
    pending = list(roots)
    seen: set[str] = set()
    while pending:
        name = pending.pop()
        if name in seen:
            continue
        seen.add(name)
        shape = model["shapes"][name]
        for item in shape.get("members", {}).values():
            pending.append(item["shape"])
        member = shape.get("member")
        if member is not None:
            pending.append(member["shape"])
    return sorted(seen)


def structure(
    model: dict,
    name: str,
    required: list[str],
    member_names: list[str],
) -> None:
    shape = model["shapes"][name]
    if shape.get("type") != "structure" or (
        shape.get("required", []) != required
    ) or list(shape.get("members", {})) != member_names:
        fail(f"{name} structure changed")


def main() -> int:
    model_path = os.environ.get("FLYOLOGY_S3_SERVICE_MODEL")
    if not model_path:
        fail("FLYOLOGY_S3_SERVICE_MODEL is required")
    raw = Path(model_path).read_bytes()
    if hashlib.sha256(raw).hexdigest() != MODEL_SHA256:
        fail("pinned model identity changed")
    model = json.loads(raw)
    operation = model["operations"]["SelectObjectContent"]
    if operation["http"] != {
        "method": "POST",
        "requestUri": "/{Bucket}/{Key+}?select&select-type=2",
    }:
        fail("method or request URI changed")
    if operation["input"] != {
        "shape": "SelectObjectContentRequest",
        "locationName": "SelectObjectContentRequest",
        "xmlNamespace": {"uri": "http://s3.amazonaws.com/doc/2006-03-01/"},
    } or operation["output"] != {"shape": "SelectObjectContentOutput"}:
        fail("input or output shape changed")
    for trait in ("errors", "httpChecksum", "staticContextParams"):
        if trait in operation:
            fail(f"operation unexpectedly gained {trait}")
    roots = [operation["input"]["shape"], operation["output"]["shape"]]
    if reachable_shapes(model, roots) != REACHABLE_SHAPES:
        fail("reachable Select shape inventory changed")

    request = model["shapes"]["SelectObjectContentRequest"]
    if request.get("type") != "structure" or request.get("required") != [
        "Bucket", "Key", "Expression", "ExpressionType",
        "InputSerialization", "OutputSerialization",
    ]:
        fail("required request members changed")
    if members(request) != [
        ("Bucket", "BucketName", "uri", "Bucket"),
        ("Key", "ObjectKey", "uri", "Key"),
        ("SSECustomerAlgorithm", "SSECustomerAlgorithm", "header",
         "x-amz-server-side-encryption-customer-algorithm"),
        ("SSECustomerKey", "SSECustomerKey", "header",
         "x-amz-server-side-encryption-customer-key"),
        ("SSECustomerKeyMD5", "SSECustomerKeyMD5", "header",
         "x-amz-server-side-encryption-customer-key-MD5"),
        ("Expression", "Expression", "body", "Expression"),
        ("ExpressionType", "ExpressionType", "body", "ExpressionType"),
        ("RequestProgress", "RequestProgress", "body", "RequestProgress"),
        ("InputSerialization", "InputSerialization", "body",
         "InputSerialization"),
        ("OutputSerialization", "OutputSerialization", "body",
         "OutputSerialization"),
        ("ScanRange", "ScanRange", "body", "ScanRange"),
        ("ExpectedBucketOwner", "AccountId", "header",
         "x-amz-expected-bucket-owner"),
    ]:
        fail("request member inventory changed")
    if request["members"]["Bucket"].get("contextParam") != {
        "name": "Bucket"
    }:
        fail("bucket context parameter changed")
    if model["shapes"]["SSECustomerKey"] != {
        "type": "string", "sensitive": True,
    }:
        fail("SSE-C key sensitivity changed")

    output = model["shapes"]["SelectObjectContentOutput"]
    if output.get("type") != "structure" or (
        output.get("payload") != "Payload"
    ) or members(output) != [
        ("Payload", "SelectObjectContentEventStream", "body", "Payload"),
    ]:
        fail("event-stream response payload changed")
    stream = model["shapes"]["SelectObjectContentEventStream"]
    if stream.get("type") != "structure" or (
        stream.get("eventstream") is not True
    ) or members(stream) != [
        ("Records", "RecordsEvent", "body", "Records"),
        ("Stats", "StatsEvent", "body", "Stats"),
        ("Progress", "ProgressEvent", "body", "Progress"),
        ("Cont", "ContinuationEvent", "body", "Cont"),
        ("End", "EndEvent", "body", "End"),
    ]:
        fail("event-stream variant inventory changed")
    events = {
        "RecordsEvent": ("Payload", "Body"),
        "StatsEvent": ("Details", "Stats"),
        "ProgressEvent": ("Details", "Progress"),
    }
    for name, (member_name, member_shape) in events.items():
        event = model["shapes"][name]
        if event.get("type") != "structure" or (
            event.get("event") is not True
        ) or list(event.get("members", {})) != [member_name]:
            fail(f"{name} event geometry changed")
        member = event["members"][member_name]
        if member.get("shape") != member_shape or (
            member.get("eventpayload") is not True
        ):
            fail(f"{name} event payload changed")
    for name in ("ContinuationEvent", "EndEvent"):
        event = model["shapes"][name]
        if event.get("type") != "structure" or (
            event.get("members") != {}
        ) or event.get("event") is not True:
            fail(f"{name} terminal event changed")

    expected_structures = {
        "RequestProgress": ([], ["Enabled"]),
        "ScanRange": ([], ["Start", "End"]),
        "InputSerialization": ([], [
            "CSV", "CompressionType", "JSON", "Parquet",
        ]),
        "OutputSerialization": ([], ["CSV", "JSON"]),
        "CSVInput": ([], [
            "FileHeaderInfo", "Comments", "QuoteEscapeCharacter",
            "RecordDelimiter", "FieldDelimiter", "QuoteCharacter",
            "AllowQuotedRecordDelimiter",
        ]),
        "CSVOutput": ([], [
            "QuoteFields", "QuoteEscapeCharacter", "RecordDelimiter",
            "FieldDelimiter", "QuoteCharacter",
        ]),
        "JSONInput": ([], ["Type"]),
        "JSONOutput": ([], ["RecordDelimiter"]),
        "ParquetInput": ([], []),
        "Stats": ([], [
            "BytesScanned", "BytesProcessed", "BytesReturned",
        ]),
        "Progress": ([], [
            "BytesScanned", "BytesProcessed", "BytesReturned",
        ]),
    }
    for name, (required, names) in expected_structures.items():
        structure(model, name, required, names)
    expected_enums = {
        "ExpressionType": ["SQL"],
        "CompressionType": ["NONE", "GZIP", "BZIP2"],
        "FileHeaderInfo": ["USE", "IGNORE", "NONE"],
        "JSONType": ["DOCUMENT", "LINES"],
        "QuoteFields": ["ALWAYS", "ASNEEDED"],
    }
    for name, values in expected_enums.items():
        if model["shapes"][name] != {"type": "string", "enum": values}:
            fail(f"{name} domain changed")
    for name in (
        "Start", "End", "BytesScanned", "BytesProcessed", "BytesReturned",
    ):
        if model["shapes"][name] != {"type": "long", "box": True}:
            fail(f"{name} boxed-long shape changed")
    if model["shapes"]["Body"] != {"type": "blob"}:
        fail("record payload body shape changed")

    generated = (
        ROOT / "src/flyology-object_storage-s3-model.adb"
    ).read_text(encoding="utf-8")
    for fragment in (
        'return "SelectObjectContent";',
        'return "/{Bucket}/{Key+}?select&select-type=2";',
        'return "SelectObjectContentEventStream";',
        'return "SelectObjectContentOutput";',
        'return "SelectObjectContentRequest";',
    ):
        if fragment not in generated:
            fail(f"generated model lacks {fragment}")
    client = "\n".join(
        (ROOT / path).read_text(encoding="utf-8")
        for path in (
            "src/flyology-object_storage-client-low_level.ads",
            "src/flyology-object_storage-client-low_level.adb",
            "src/flyology-object_storage-client-objects.ads",
            "src/flyology-object_storage-client-objects.adb",
        )
    )
    for symbol in (
        "Prepare_Select_Object_Content", "Execute_Select_Object_Content",
        "Select_Object_Content_Operation", "Select_Object_Content",
    ):
        if symbol in client:
            fail(f"model-only review unexpectedly exposes {symbol}")
    print("SelectObjectContent model review: 12 request, 5 events, 44 shapes")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, TypeError, UnicodeError, ValueError) as exc:
        print(f"SelectObjectContent model verification failed: {exc}",
              file=sys.stderr)
        raise SystemExit(1)
