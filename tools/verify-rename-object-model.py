#!/usr/bin/env python3
"""Verify the reviewed model-only RenameObject boundary."""

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


def main() -> int:
    model_path = os.environ.get("FLYOLOGY_S3_SERVICE_MODEL")
    if not model_path:
        fail("FLYOLOGY_S3_SERVICE_MODEL is required")
    raw = Path(model_path).read_bytes()
    if hashlib.sha256(raw).hexdigest() != MODEL_SHA256:
        fail("pinned model identity changed")
    model = json.loads(raw)
    operation = model["operations"]["RenameObject"]
    if operation["http"] != {
        "method": "PUT", "requestUri": "/{Bucket}/{Key+}?renameObject",
    }:
        fail("method or request URI changed")
    if operation["input"] != {"shape": "RenameObjectRequest"} or (
        operation["output"] != {"shape": "RenameObjectOutput"}
    ):
        fail("input or output shape changed")
    if [item["shape"] for item in operation["errors"]] != [
        "IdempotencyParameterMismatch"
    ]:
        fail("modeled error inventory changed")
    if "httpChecksum" in operation:
        fail("rename operation unexpectedly gained checksum traits")
    if "staticContextParams" in operation:
        fail("rename operation unexpectedly gained static context")

    request = model["shapes"]["RenameObjectRequest"]
    if request.get("type") != "structure" or (
        request.get("payload") is not None
    ) or request["required"] != [
        "Bucket", "Key", "RenameSource",
    ]:
        fail("required request members or payload changed")
    expected_request = [
        ("Bucket", "BucketName", "uri", "Bucket"),
        ("Key", "ObjectKey", "uri", "Key"),
        ("RenameSource", "RenameSource", "header",
         "x-amz-rename-source"),
        ("DestinationIfMatch", "IfMatch", "header", "If-Match"),
        ("DestinationIfNoneMatch", "IfNoneMatch", "header",
         "If-None-Match"),
        ("DestinationIfModifiedSince", "IfModifiedSince", "header",
         "If-Modified-Since"),
        ("DestinationIfUnmodifiedSince", "IfUnmodifiedSince", "header",
         "If-Unmodified-Since"),
        ("SourceIfMatch", "RenameSourceIfMatch", "header",
         "x-amz-rename-source-if-match"),
        ("SourceIfNoneMatch", "RenameSourceIfNoneMatch", "header",
         "x-amz-rename-source-if-none-match"),
        ("SourceIfModifiedSince", "RenameSourceIfModifiedSince", "header",
         "x-amz-rename-source-if-modified-since"),
        ("SourceIfUnmodifiedSince", "RenameSourceIfUnmodifiedSince",
         "header", "x-amz-rename-source-if-unmodified-since"),
        ("ClientToken", "ClientToken", "header", "x-amz-client-token"),
    ]
    if members(request) != expected_request:
        fail("request member inventory changed")
    if request["members"]["Bucket"].get("contextParam") != {
        "name": "Bucket"
    } or request["members"]["Key"].get("contextParam") != {
        "name": "Key"
    }:
        fail("request context parameters changed")
    if request["members"]["ClientToken"].get("idempotencyToken") is not True:
        fail("client-token idempotency trait changed")

    if model["shapes"]["RenameObjectOutput"] != {
        "type": "structure", "members": {},
    }:
        fail("empty response shape changed")
    mismatch = model["shapes"]["IdempotencyParameterMismatch"]
    if mismatch.get("type") != "structure" or mismatch.get("members") != {}:
        fail("idempotency mismatch error structure changed")
    if mismatch.get("error") != {
        "httpStatusCode": 400
    } or mismatch.get("exception") is not True:
        fail("idempotency mismatch error trait changed")
    if model["shapes"]["RenameSource"] != {
        "type": "string", "pattern": "\\/?.+\\/.+",
    }:
        fail("rename-source shape changed")
    if model["shapes"]["ObjectKey"] != {"type": "string", "min": 1}:
        fail("object-key shape changed")
    if model["shapes"]["BucketName"] != {"type": "string"}:
        fail("bucket-name shape changed")
    for shape_name in (
        "IfMatch", "IfNoneMatch", "RenameSourceIfMatch",
        "RenameSourceIfNoneMatch", "ClientToken",
    ):
        if model["shapes"][shape_name] != {"type": "string"}:
            fail(f"{shape_name} shape changed")
    for shape_name in ("IfModifiedSince", "IfUnmodifiedSince"):
        if model["shapes"][shape_name] != {"type": "timestamp"}:
            fail(f"{shape_name} timestamp shape changed")
    for shape_name in (
        "RenameSourceIfModifiedSince", "RenameSourceIfUnmodifiedSince",
    ):
        if model["shapes"][shape_name] != {
            "type": "timestamp", "timestampFormat": "rfc822",
        }:
            fail(f"{shape_name} timestamp shape changed")

    generated = (
        ROOT / "src/flyology-object_storage-s3-model.adb"
    ).read_text(encoding="utf-8")
    for fragment in (
        'return "RenameObject";',
        'return "/{Bucket}/{Key+}?renameObject";',
        'return "RenameObjectOutput";',
        'return "RenameObjectRequest";',
        'return "x-amz-rename-source";',
        'return "x-amz-client-token";',
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
        "Prepare_Rename_Object", "Execute_Rename_Object",
        "Rename_Object_Operation", "Rename_Object", "Rename",
    ):
        if symbol in client:
            fail(f"model-only review unexpectedly exposes {symbol}")
    print("RenameObject model review: 12 request and 0 response members")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, TypeError, UnicodeError, ValueError) as exc:
        print(f"RenameObject model verification failed: {exc}",
              file=sys.stderr)
        raise SystemExit(1)
