#!/usr/bin/env python3
"""Verify the reviewed model-only GetObjectAnnotation boundary."""

from __future__ import annotations

import hashlib
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODEL_SHA256 = (
    "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
)


def fail(message: str) -> None:
    raise ValueError(message)


def members(shape: dict) -> list[tuple[str, str, str, str, bool]]:
    return [
        (name, item["shape"], item.get("location", "body"),
         item.get("locationName", name), item.get("streaming", False))
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
    operation = model["operations"]["GetObjectAnnotation"]
    if operation["http"] != {
        "method": "GET",
        "requestUri": "/{Bucket}/{Key+}?annotation",
    }:
        fail("method or request URI changed")
    if operation["input"] != {"shape": "GetObjectAnnotationRequest"} or (
        operation["output"] != {"shape": "GetObjectAnnotationOutput"}
    ):
        fail("input or output shape changed")
    if [item["shape"] for item in operation["errors"]] != [
        "NoSuchBucket", "NoSuchKey", "NoSuchAnnotation",
    ]:
        fail("modeled error order changed")
    if operation["httpChecksum"] != {
        "requestValidationModeMember": "ChecksumMode",
        "responseAlgorithms": [
            "CRC64NVME", "CRC32", "CRC32C", "SHA256", "SHA1", "SHA512",
            "MD5", "XXHASH64", "XXHASH3", "XXHASH128",
        ],
    }:
        fail("checksum model changed")

    request = model["shapes"]["GetObjectAnnotationRequest"]
    if request["required"] != ["Bucket", "Key", "AnnotationName"]:
        fail("required request members changed")
    if members(request) != [
        ("Bucket", "BucketName", "uri", "Bucket", False),
        ("Key", "ObjectKey", "uri", "Key", False),
        ("AnnotationName", "AnnotationName", "querystring",
         "annotationName", False),
        ("VersionId", "ObjectVersionId", "querystring", "versionId", False),
        ("RequestPayer", "RequestPayer", "header",
         "x-amz-request-payer", False),
        ("ExpectedBucketOwner", "AccountId", "header",
         "x-amz-expected-bucket-owner", False),
        ("ChecksumMode", "ChecksumMode", "header",
         "x-amz-checksum-mode", False),
    ]:
        fail("request member inventory changed")

    response = model["shapes"]["GetObjectAnnotationOutput"]
    expected = [
        ("AnnotationPayload", "AnnotationPayload", "body",
         "AnnotationPayload", True),
        ("ObjectVersionId", "ObjectVersionId", "header",
         "x-amz-object-version-id", False),
        ("LastModified", "LastModified", "header", "Last-Modified", False),
        ("ContentLength", "ContentLength", "header", "Content-Length", False),
        ("ETag", "ETag", "header", "ETag", False),
    ]
    for name in (
        "CRC32", "CRC32C", "CRC64NVME", "SHA1", "SHA256", "SHA512",
        "MD5", "XXHASH64", "XXHASH3", "XXHASH128",
    ):
        expected.append(
            (f"Checksum{name}", f"Checksum{name}", "header",
             f"x-amz-checksum-{name.lower()}", False)
        )
    expected.extend([
        ("ChecksumType", "ChecksumType", "header", "x-amz-checksum-type",
         False),
        ("ServerSideEncryption", "ServerSideEncryption", "header",
         "x-amz-server-side-encryption", False),
        ("RequestCharged", "RequestCharged", "header",
         "x-amz-request-charged", False),
        ("ReplicationStatus", "ReplicationStatus", "header",
         "x-amz-replication-status", False),
    ])
    if response.get("payload") != "AnnotationPayload" or (
        members(response) != expected
    ):
        fail("response payload or member inventory changed")
    annotation_name = model["shapes"]["AnnotationName"]
    if annotation_name != {"type": "string"}:
        fail("AnnotationName gained a generated constraint")
    if model["shapes"]["AnnotationPayload"] != {"type": "blob"}:
        fail("annotation payload is no longer an unconstrained blob")

    generated = (
        ROOT / "src/flyology-object_storage-s3-model.adb"
    ).read_text(encoding="utf-8")
    for fragment in (
        'return "GetObjectAnnotation";',
        'return "/{Bucket}/{Key+}?annotation";',
        'return "GetObjectAnnotationOutput";',
        'return "GetObjectAnnotationRequest";',
        'return "AnnotationPayload";',
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
        "Prepare_Get_Object_Annotation", "Execute_Get_Object_Annotation",
        "Get_Object_Annotation_Operation", "Get_Annotation",
    ):
        if symbol in client:
            fail(f"model-only review unexpectedly exposes {symbol}")

    print("GetObjectAnnotation model review: 7 request and 19 response members")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, TypeError, UnicodeError, ValueError) as exc:
        print(f"GetObjectAnnotation model verification failed: {exc}",
              file=sys.stderr)
        raise SystemExit(1)
