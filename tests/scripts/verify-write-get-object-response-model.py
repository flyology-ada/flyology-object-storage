#!/usr/bin/env python3
"""Verify the reviewed model-only WriteGetObjectResponse boundary."""

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
    "AcceptRanges", "Body", "BucketKeyEnabled", "CacheControl",
    "ChecksumCRC32", "ChecksumCRC32C", "ChecksumCRC64NVME",
    "ChecksumMD5", "ChecksumSHA1", "ChecksumSHA256", "ChecksumSHA512",
    "ChecksumXXHASH128", "ChecksumXXHASH3", "ChecksumXXHASH64",
    "ContentDisposition", "ContentEncoding", "ContentLanguage",
    "ContentLength", "ContentRange", "ContentType", "DeleteMarker",
    "ETag", "ErrorCode", "ErrorMessage", "Expiration", "Expires",
    "GetObjectResponseStatusCode", "LastModified", "Metadata",
    "MetadataKey", "MetadataValue", "MissingMeta",
    "ObjectLockLegalHoldStatus", "ObjectLockMode",
    "ObjectLockRetainUntilDate", "ObjectVersionId", "PartsCount",
    "ReplicationStatus", "RequestCharged", "RequestRoute", "RequestToken",
    "Restore", "SSECustomerAlgorithm", "SSECustomerKeyMD5", "SSEKMSKeyId",
    "ServerSideEncryption", "StorageClass", "TagCount",
    "WriteGetObjectResponseRequest",
]
EXPECTED_MEMBERS = [
    ("RequestRoute", "RequestRoute", "header", "x-amz-request-route"),
    ("RequestToken", "RequestToken", "header", "x-amz-request-token"),
    ("Body", "Body", "body", "Body"),
    ("StatusCode", "GetObjectResponseStatusCode", "header",
     "x-amz-fwd-status"),
    ("ErrorCode", "ErrorCode", "header", "x-amz-fwd-error-code"),
    ("ErrorMessage", "ErrorMessage", "header", "x-amz-fwd-error-message"),
    ("AcceptRanges", "AcceptRanges", "header",
     "x-amz-fwd-header-accept-ranges"),
    ("CacheControl", "CacheControl", "header",
     "x-amz-fwd-header-Cache-Control"),
    ("ContentDisposition", "ContentDisposition", "header",
     "x-amz-fwd-header-Content-Disposition"),
    ("ContentEncoding", "ContentEncoding", "header",
     "x-amz-fwd-header-Content-Encoding"),
    ("ContentLanguage", "ContentLanguage", "header",
     "x-amz-fwd-header-Content-Language"),
    ("ContentLength", "ContentLength", "header", "Content-Length"),
    ("ContentRange", "ContentRange", "header",
     "x-amz-fwd-header-Content-Range"),
    ("ContentType", "ContentType", "header",
     "x-amz-fwd-header-Content-Type"),
    ("ChecksumCRC32", "ChecksumCRC32", "header",
     "x-amz-fwd-header-x-amz-checksum-crc32"),
    ("ChecksumCRC32C", "ChecksumCRC32C", "header",
     "x-amz-fwd-header-x-amz-checksum-crc32c"),
    ("ChecksumCRC64NVME", "ChecksumCRC64NVME", "header",
     "x-amz-fwd-header-x-amz-checksum-crc64nvme"),
    ("ChecksumSHA1", "ChecksumSHA1", "header",
     "x-amz-fwd-header-x-amz-checksum-sha1"),
    ("ChecksumSHA256", "ChecksumSHA256", "header",
     "x-amz-fwd-header-x-amz-checksum-sha256"),
    ("ChecksumSHA512", "ChecksumSHA512", "header",
     "x-amz-fwd-header-x-amz-checksum-sha512"),
    ("ChecksumMD5", "ChecksumMD5", "header",
     "x-amz-fwd-header-x-amz-checksum-md5"),
    ("ChecksumXXHASH64", "ChecksumXXHASH64", "header",
     "x-amz-fwd-header-x-amz-checksum-xxhash64"),
    ("ChecksumXXHASH3", "ChecksumXXHASH3", "header",
     "x-amz-fwd-header-x-amz-checksum-xxhash3"),
    ("ChecksumXXHASH128", "ChecksumXXHASH128", "header",
     "x-amz-fwd-header-x-amz-checksum-xxhash128"),
    ("DeleteMarker", "DeleteMarker", "header",
     "x-amz-fwd-header-x-amz-delete-marker"),
    ("ETag", "ETag", "header", "x-amz-fwd-header-ETag"),
    ("Expires", "Expires", "header", "x-amz-fwd-header-Expires"),
    ("Expiration", "Expiration", "header",
     "x-amz-fwd-header-x-amz-expiration"),
    ("LastModified", "LastModified", "header",
     "x-amz-fwd-header-Last-Modified"),
    ("MissingMeta", "MissingMeta", "header",
     "x-amz-fwd-header-x-amz-missing-meta"),
    ("Metadata", "Metadata", "headers", "x-amz-meta-"),
    ("ObjectLockMode", "ObjectLockMode", "header",
     "x-amz-fwd-header-x-amz-object-lock-mode"),
    ("ObjectLockLegalHoldStatus", "ObjectLockLegalHoldStatus", "header",
     "x-amz-fwd-header-x-amz-object-lock-legal-hold"),
    ("ObjectLockRetainUntilDate", "ObjectLockRetainUntilDate", "header",
     "x-amz-fwd-header-x-amz-object-lock-retain-until-date"),
    ("PartsCount", "PartsCount", "header",
     "x-amz-fwd-header-x-amz-mp-parts-count"),
    ("ReplicationStatus", "ReplicationStatus", "header",
     "x-amz-fwd-header-x-amz-replication-status"),
    ("RequestCharged", "RequestCharged", "header",
     "x-amz-fwd-header-x-amz-request-charged"),
    ("Restore", "Restore", "header", "x-amz-fwd-header-x-amz-restore"),
    ("ServerSideEncryption", "ServerSideEncryption", "header",
     "x-amz-fwd-header-x-amz-server-side-encryption"),
    ("SSECustomerAlgorithm", "SSECustomerAlgorithm", "header",
     "x-amz-fwd-header-x-amz-server-side-encryption-customer-algorithm"),
    ("SSEKMSKeyId", "SSEKMSKeyId", "header",
     "x-amz-fwd-header-x-amz-server-side-encryption-aws-kms-key-id"),
    ("SSECustomerKeyMD5", "SSECustomerKeyMD5", "header",
     "x-amz-fwd-header-x-amz-server-side-encryption-customer-key-MD5"),
    ("StorageClass", "StorageClass", "header",
     "x-amz-fwd-header-x-amz-storage-class"),
    ("TagCount", "TagCount", "header",
     "x-amz-fwd-header-x-amz-tagging-count"),
    ("VersionId", "ObjectVersionId", "header",
     "x-amz-fwd-header-x-amz-version-id"),
    ("BucketKeyEnabled", "BucketKeyEnabled", "header",
     "x-amz-fwd-header-x-amz-server-side-encryption-bucket-key-enabled"),
]


def fail(message: str) -> None:
    raise ValueError(message)


def member_rows(shape: dict) -> list[tuple[str, str, str, str]]:
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
        pending.extend(
            item["shape"] for item in shape.get("members", {}).values()
        )
        for relation in ("key", "value", "member"):
            if relation in shape:
                pending.append(shape[relation]["shape"])
    return sorted(seen)


def require_shape(model: dict, name: str, expected: dict) -> None:
    shape = {
        key: value for key, value in model["shapes"][name].items()
        if key != "documentation"
    }
    if shape != expected:
        fail(f"{name} shape changed")


def main() -> int:
    model_path = os.environ.get("FLYOLOGY_S3_SERVICE_MODEL")
    if not model_path:
        fail("FLYOLOGY_S3_SERVICE_MODEL is required")
    raw = Path(model_path).read_bytes()
    if hashlib.sha256(raw).hexdigest() != MODEL_SHA256:
        fail("pinned model identity changed")
    model = json.loads(raw)
    operation = model["operations"]["WriteGetObjectResponse"]
    if operation["http"] != {
        "method": "POST", "requestUri": "/WriteGetObjectResponse",
    }:
        fail("method or request URI changed")
    if operation["input"] != {"shape": "WriteGetObjectResponseRequest"}:
        fail("input shape changed")
    if "output" in operation or operation.get("errors", []) != []:
        fail("one-way output or error inventory changed")
    if operation.get("httpChecksum") is not None:
        fail("request checksum trait unexpectedly appeared")
    if operation.get("authtype") != "v4-unsigned-body" or (
        operation.get("unsignedPayload") is not True
    ):
        fail("unsigned authentication traits changed")
    if operation.get("endpoint") != {"hostPrefix": "{RequestRoute}."}:
        fail("Object Lambda host prefix changed")
    if operation.get("staticContextParams") != {
        "UseObjectLambdaEndpoint": {"value": True}
    }:
        fail("Object Lambda static context changed")
    if reachable_shapes(
        model, [operation["input"]["shape"]]
    ) != REACHABLE_SHAPES:
        fail("reachable callback shape inventory changed")

    request = model["shapes"]["WriteGetObjectResponseRequest"]
    if request.get("type") != "structure" or (
        request.get("required") != ["RequestRoute", "RequestToken"]
    ) or request.get("payload") != "Body":
        fail("request structure, required members, or payload changed")
    if member_rows(request) != EXPECTED_MEMBERS:
        fail("ordered request member inventory changed")
    if request["members"]["RequestRoute"].get("hostLabel") is not True:
        fail("RequestRoute host-label trait changed")
    if request["members"]["Body"].get("streaming") is not True:
        fail("Body streaming trait changed")
    for name, item in request["members"].items():
        if name != "RequestRoute" and "hostLabel" in item:
            fail(f"{name} unexpectedly became a host label")
        if name != "Body" and "streaming" in item:
            fail(f"{name} unexpectedly became streaming")

    require_shape(model, "Body", {"type": "blob"})
    require_shape(
        model, "GetObjectResponseStatusCode",
        {"type": "integer", "box": True},
    )
    require_shape(model, "BucketKeyEnabled", {
        "type": "boolean", "box": True,
    })
    require_shape(model, "SSEKMSKeyId", {
        "type": "string", "sensitive": True,
    })
    require_shape(model, "Metadata", {
        "type": "map",
        "key": {"shape": "MetadataKey"},
        "value": {"shape": "MetadataValue"},
    })
    require_shape(model, "ObjectLockRetainUntilDate", {
        "type": "timestamp", "timestampFormat": "iso8601",
    })
    enum_shapes = {
        "ObjectLockLegalHoldStatus": ["ON", "OFF"],
        "ObjectLockMode": ["GOVERNANCE", "COMPLIANCE"],
        "ReplicationStatus": [
            "COMPLETE", "PENDING", "FAILED", "REPLICA", "COMPLETED",
        ],
        "RequestCharged": ["requester"],
        "ServerSideEncryption": [
            "AES256", "aws:fsx", "aws:backup", "aws:kms",
            "aws:kms:dsse",
        ],
        "StorageClass": [
            "STANDARD", "REDUCED_REDUNDANCY", "STANDARD_IA",
            "ONEZONE_IA", "INTELLIGENT_TIERING", "GLACIER",
            "DEEP_ARCHIVE", "OUTPOSTS", "GLACIER_IR", "SNOW",
            "EXPRESS_ONEZONE", "FSX_OPENZFS", "FSX_ONTAP",
            "AWS_BACKUP_WARM", "AWS_BACKUP_LOW_COST_WARM",
        ],
    }
    for name, values in enum_shapes.items():
        require_shape(model, name, {"type": "string", "enum": values})
    for name in ("Expires", "LastModified"):
        require_shape(model, name, {"type": "timestamp"})
    require_shape(model, "ContentLength", {"type": "long"})
    for name in ("MissingMeta",):
        require_shape(model, name, {"type": "integer"})
    for name in ("PartsCount", "TagCount"):
        require_shape(model, name, {"type": "integer", "box": True})

    generated = (
        ROOT / "src/flyology-object_storage-s3-model.adb"
    ).read_text(encoding="utf-8")
    for fragment in (
        'return "WriteGetObjectResponse";',
        'return "/WriteGetObjectResponse";',
        'return "v4-unsigned-body";',
        'return "WriteGetObjectResponseRequest";',
    ):
        if fragment not in generated:
            fail(f"generated model lacks {fragment}")
    tests = (
        ROOT / "tests/src/object_storage_test_cases.adb"
    ).read_text(encoding="utf-8")
    for fragment in (
        "Model.Write_Get_Object_Response_Operation",
        '"special unsigned S3 operation traits changed"',
    ):
        if fragment not in tests:
            fail(f"generated-model test lacks {fragment}")
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
        "Prepare_Write_Get_Object_Response",
        "Execute_Write_Get_Object_Response",
        "Write_Get_Object_Response_Operation",
        "Write_Get_Object_Response",
    ):
        if symbol in client:
            fail(f"model-only review unexpectedly exposes {symbol}")
    print(
        "WriteGetObjectResponse model review: "
        "46 request, 0 response, 49 shapes"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, TypeError, UnicodeError, ValueError) as exc:
        print(
            f"WriteGetObjectResponse model verification failed: {exc}",
            file=sys.stderr,
        )
        raise SystemExit(1)
