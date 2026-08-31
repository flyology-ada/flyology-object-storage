#!/usr/bin/env python3
"""Verify the reviewed model-only UpdateObjectEncryption boundary."""

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
REACHABLE_SHAPES = [
    "AccessDenied", "AccountId", "BucketKeyEnabled", "BucketName",
    "ChecksumAlgorithm", "ContentMD5", "InvalidRequest", "NoSuchKey",
    "NonEmptyKmsKeyArnString", "ObjectEncryption", "ObjectKey",
    "ObjectVersionId", "RequestCharged", "RequestPayer", "SSEKMSEncryption",
    "UpdateObjectEncryptionRequest", "UpdateObjectEncryptionResponse",
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
    return sorted(seen)


def main() -> int:
    model_path = os.environ.get("FLYOLOGY_S3_SERVICE_MODEL")
    if not model_path:
        fail("FLYOLOGY_S3_SERVICE_MODEL is required")
    raw = Path(model_path).read_bytes()
    if hashlib.sha256(raw).hexdigest() != MODEL_SHA256:
        fail("pinned model identity changed")
    model = json.loads(raw)
    operation = model["operations"]["UpdateObjectEncryption"]
    if operation["http"] != {
        "method": "PUT", "requestUri": "/{Bucket}/{Key+}?encryption",
    }:
        fail("method or request URI changed")
    if operation["input"] != {
        "shape": "UpdateObjectEncryptionRequest"
    } or operation["output"] != {
        "shape": "UpdateObjectEncryptionResponse"
    }:
        fail("input or output shape changed")
    if [item["shape"] for item in operation["errors"]] != [
        "NoSuchKey", "InvalidRequest", "AccessDenied",
    ]:
        fail("modeled error inventory changed")
    if operation.get("httpChecksum") != {
        "requestAlgorithmMember": "ChecksumAlgorithm",
        "requestChecksumRequired": True,
    }:
        fail("required checksum request trait changed")
    if "staticContextParams" in operation:
        fail("encryption update unexpectedly gained static context")
    roots = [
        operation["input"]["shape"], operation["output"]["shape"],
        *[item["shape"] for item in operation["errors"]],
    ]
    if reachable_shapes(model, roots) != REACHABLE_SHAPES:
        fail("reachable encryption-update shape inventory changed")

    request = model["shapes"]["UpdateObjectEncryptionRequest"]
    if request.get("type") != "structure" or (
        request.get("payload") != "ObjectEncryption"
    ) or request.get("required") != ["Bucket", "Key", "ObjectEncryption"]:
        fail("required request members or payload changed")
    if members(request) != [
        ("Bucket", "BucketName", "uri", "Bucket"),
        ("Key", "ObjectKey", "uri", "Key"),
        ("VersionId", "ObjectVersionId", "querystring", "versionId"),
        ("ObjectEncryption", "ObjectEncryption", "body",
         "ObjectEncryption"),
        ("RequestPayer", "RequestPayer", "header", "x-amz-request-payer"),
        ("ExpectedBucketOwner", "AccountId", "header",
         "x-amz-expected-bucket-owner"),
        ("ContentMD5", "ContentMD5", "header", "Content-MD5"),
        ("ChecksumAlgorithm", "ChecksumAlgorithm", "header",
         "x-amz-sdk-checksum-algorithm"),
    ]:
        fail("request member inventory changed")
    if request["members"]["Bucket"].get("contextParam") != {
        "name": "Bucket"
    }:
        fail("bucket context parameter changed")
    if request["members"]["ObjectEncryption"].get("xmlNamespace") != {
        "uri": "http://s3.amazonaws.com/doc/2006-03-01/"
    }:
        fail("object-encryption namespace changed")

    response = model["shapes"]["UpdateObjectEncryptionResponse"]
    if response.get("type") != "structure" or members(response) != [
        ("RequestCharged", "RequestCharged", "header",
         "x-amz-request-charged"),
    ]:
        fail("response member inventory changed")
    expected_errors = {
        "NoSuchKey": (404, False),
        "InvalidRequest": (400, False),
        "AccessDenied": (403, True),
    }
    for name, (status, synthetic) in expected_errors.items():
        shape = model["shapes"][name]
        if shape.get("type") != "structure" or shape.get("members") != {}:
            fail(f"{name} error structure changed")
        if shape.get("error") != {"httpStatusCode": status} or (
            shape.get("exception") is not True
        ) or shape.get("synthetic", False) is not synthetic:
            fail(f"{name} error traits changed")

    encryption = model["shapes"]["ObjectEncryption"]
    if encryption.get("type") != "structure" or (
        encryption.get("union") is not True
    ) or members(encryption) != [
        ("SSEKMS", "SSEKMSEncryption", "body", "SSE-KMS"),
    ]:
        fail("object-encryption union changed")
    sse_kms = model["shapes"]["SSEKMSEncryption"]
    if sse_kms.get("type") != "structure" or (
        sse_kms.get("required") != ["KMSKeyArn"]
    ) or members(sse_kms) != [
        ("KMSKeyArn", "NonEmptyKmsKeyArnString", "body", "KMSKeyArn"),
        ("BucketKeyEnabled", "BucketKeyEnabled", "body",
         "BucketKeyEnabled"),
    ]:
        fail("SSE-KMS payload changed")
    if model["shapes"]["NonEmptyKmsKeyArnString"] != {
        "type": "string", "max": 2048, "min": 20,
        "pattern": (
            "arn:aws[a-zA-Z0-9-]*:kms:[a-z0-9-]+:[0-9]{12}:"
            "key/[a-zA-Z0-9-]+"
        ),
        "sensitive": True,
    }:
        fail("KMS ARN shape changed")
    if model["shapes"]["BucketKeyEnabled"] != {
        "type": "boolean", "box": True,
    }:
        fail("bucket-key shape changed")
    if model["shapes"]["ChecksumAlgorithm"]["enum"] != [
        "CRC32", "CRC32C", "SHA1", "SHA256", "CRC64NVME", "SHA512",
        "MD5", "XXHASH64", "XXHASH3", "XXHASH128",
    ]:
        fail("checksum algorithm domain changed")
    for name in ("RequestPayer", "RequestCharged"):
        shape = model["shapes"][name]
        if shape.get("type") != "string" or (
            shape.get("enum") != ["requester"]
        ):
            fail(f"{name} domain changed")

    generated = (
        ROOT / "src/flyology-object_storage-s3-model.adb"
    ).read_text(encoding="utf-8")
    for fragment in (
        'return "UpdateObjectEncryption";',
        'return "/{Bucket}/{Key+}?encryption";',
        'return "UpdateObjectEncryptionRequest";',
        'return "UpdateObjectEncryptionResponse";',
        'return "ObjectEncryption";',
        'return "SSE-KMS";',
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
        "Prepare_Update_Object_Encryption",
        "Execute_Update_Object_Encryption",
        "Update_Object_Encryption_Operation",
        "Update_Object_Encryption",
    ):
        if symbol in client:
            fail(f"model-only review unexpectedly exposes {symbol}")
    print(
        "UpdateObjectEncryption model review: "
        "8 request, 1 response, 17 shapes"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, TypeError, UnicodeError, ValueError) as exc:
        print(f"UpdateObjectEncryption model verification failed: {exc}",
              file=sys.stderr)
        raise SystemExit(1)
