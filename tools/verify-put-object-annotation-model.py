#!/usr/bin/env python3
"""Verify the reviewed model-only PutObjectAnnotation boundary."""

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
CHECKSUMS = (
    "CRC32", "CRC32C", "CRC64NVME", "SHA1", "SHA256", "SHA512",
    "MD5", "XXHASH64", "XXHASH3", "XXHASH128",
)


def fail(message: str) -> None:
    raise ValueError(message)


def members(shape: dict) -> list[tuple[str, str, str, str, bool]]:
    return [
        (name, item["shape"], item.get("location", "body"),
         item.get("locationName", name), item.get("streaming", False))
        for name, item in shape["members"].items()
    ]


def checksum_members() -> list[tuple[str, str, str, str, bool]]:
    return [
        (f"Checksum{name}", f"Checksum{name}", "header",
         f"x-amz-checksum-{name.lower()}", False)
        for name in CHECKSUMS
    ]


def main() -> int:
    model_path = os.environ.get("FLYOLOGY_S3_SERVICE_MODEL")
    if not model_path:
        fail("FLYOLOGY_S3_SERVICE_MODEL is required")
    raw = Path(model_path).read_bytes()
    if hashlib.sha256(raw).hexdigest() != MODEL_SHA256:
        fail("pinned model identity changed")
    model = json.loads(raw)
    operation = model["operations"]["PutObjectAnnotation"]
    if operation["http"] != {
        "method": "PUT", "requestUri": "/{Bucket}/{Key+}?annotation",
    }:
        fail("method or request URI changed")
    if operation["input"] != {"shape": "PutObjectAnnotationRequest"} or (
        operation["output"] != {"shape": "PutObjectAnnotationOutput"}
    ):
        fail("input or output shape changed")
    if [item["shape"] for item in operation["errors"]] != [
        "NoSuchBucket", "NoSuchKey", "InvalidRequest",
        "AnnotationNameTooLong", "AnnotationLimitExceeded",
        "InvalidAnnotationName", "UnsupportedMediaType",
    ]:
        fail("modeled error order changed")
    if operation["httpChecksum"] != {
        "requestAlgorithmMember": "ChecksumAlgorithm",
        "requestChecksumRequired": False,
    }:
        fail("checksum request trait changed")

    request = model["shapes"]["PutObjectAnnotationRequest"]
    if request.get("payload") != "AnnotationPayload" or request["required"] != [
        "Bucket", "Key", "AnnotationName", "AnnotationPayload",
    ]:
        fail("required request members or payload changed")
    expected_request = [
        ("Bucket", "BucketName", "uri", "Bucket", False),
        ("Key", "ObjectKey", "uri", "Key", False),
        ("VersionId", "ObjectVersionId", "querystring", "versionId", False),
        ("AnnotationName", "AnnotationName", "querystring",
         "annotationName", False),
        ("AnnotationPayload", "AnnotationPayload", "body",
         "AnnotationPayload", True),
        ("ObjectIfMatch", "ObjectIfMatch", "header",
         "x-amz-object-if-match", False),
        ("ChecksumAlgorithm", "ChecksumAlgorithm", "header",
         "x-amz-sdk-checksum-algorithm", False),
    ]
    expected_request.extend(checksum_members())
    expected_request.extend([
        ("ContentMD5", "ContentMD5", "header", "Content-MD5", False),
        ("RequestPayer", "RequestPayer", "header",
         "x-amz-request-payer", False),
        ("ExpectedBucketOwner", "AccountId", "header",
         "x-amz-expected-bucket-owner", False),
    ])
    if members(request) != expected_request:
        fail("request member inventory changed")

    response = model["shapes"]["PutObjectAnnotationOutput"]
    expected_response = [
        ("Key", "ObjectKey", "body", "Key", False),
        ("AnnotationName", "AnnotationName", "body",
         "AnnotationName", False),
        ("ObjectVersionId", "ObjectVersionId", "header",
         "x-amz-object-version-id", False),
        ("ETag", "ETag", "header", "ETag", False),
    ]
    expected_response.extend(checksum_members())
    expected_response.extend([
        ("ChecksumType", "ChecksumType", "header", "x-amz-checksum-type",
         False),
        ("ServerSideEncryption", "ServerSideEncryption", "header",
         "x-amz-server-side-encryption", False),
        ("RequestCharged", "RequestCharged", "header",
         "x-amz-request-charged", False),
    ])
    if members(response) != expected_response:
        fail("response member inventory changed")
    if model["shapes"]["AnnotationName"] != {"type": "string"} or (
        model["shapes"]["AnnotationPayload"] != {"type": "blob"}
    ):
        fail("annotation name or payload gained a generated bound")
    if model["shapes"]["ChecksumAlgorithm"]["enum"] != [
        "CRC32", "CRC32C", "SHA1", "SHA256", "CRC64NVME", "SHA512",
        "MD5", "XXHASH64", "XXHASH3", "XXHASH128",
    ]:
        fail("checksum algorithm domain changed")

    generated = (
        ROOT / "src/flyology-object_storage-s3-model.adb"
    ).read_text(encoding="utf-8")
    for fragment in (
        'return "PutObjectAnnotation";',
        'return "/{Bucket}/{Key+}?annotation";',
        'return "PutObjectAnnotationOutput";',
        'return "PutObjectAnnotationRequest";',
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
        "Prepare_Put_Object_Annotation", "Execute_Put_Object_Annotation",
        "Put_Object_Annotation_Operation", "Put_Annotation",
    ):
        if symbol in client:
            fail(f"model-only review unexpectedly exposes {symbol}")
    print("PutObjectAnnotation model review: 20 request and 17 response members")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, TypeError, UnicodeError, ValueError) as exc:
        print(f"PutObjectAnnotation model verification failed: {exc}",
              file=sys.stderr)
        raise SystemExit(1)
