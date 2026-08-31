#!/usr/bin/env python3
"""Verify the reviewed model-only RestoreObject boundary."""

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
    "AccountId", "AllowQuotedRecordDelimiter", "BucketName", "CSVInput",
    "CSVOutput", "ChecksumAlgorithm", "Comments", "CompressionType",
    "Days", "Description", "DisplayName", "EmailAddress", "Encryption",
    "Expression", "ExpressionType", "FieldDelimiter", "FileHeaderInfo",
    "GlacierJobParameters", "Grant", "Grantee", "Grants", "ID",
    "InputSerialization", "JSONInput", "JSONOutput", "JSONType",
    "KMSContext", "LocationPrefix", "MetadataEntry", "MetadataKey",
    "MetadataValue", "ObjectAlreadyInActiveTierError", "ObjectCannedACL",
    "ObjectKey", "ObjectVersionId", "OutputLocation",
    "OutputSerialization", "ParquetInput", "Permission", "QuoteCharacter",
    "QuoteEscapeCharacter", "QuoteFields", "RecordDelimiter",
    "RequestCharged", "RequestPayer", "RestoreObjectOutput",
    "RestoreObjectRequest", "RestoreOutputPath", "RestoreRequest",
    "RestoreRequestType", "S3Location", "SSEKMSKeyId", "SelectParameters",
    "ServerSideEncryption", "StorageClass", "Tag", "TagSet", "Tagging",
    "Tier", "Type", "URI", "UserMetadata", "Value",
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
    operation = model["operations"]["RestoreObject"]
    if operation["http"] != {
        "method": "POST", "requestUri": "/{Bucket}/{Key+}?restore",
    }:
        fail("method or request URI changed")
    if operation["input"] != {"shape": "RestoreObjectRequest"} or (
        operation["output"] != {"shape": "RestoreObjectOutput"}
    ):
        fail("input or output shape changed")
    if [item["shape"] for item in operation["errors"]] != [
        "ObjectAlreadyInActiveTierError"
    ]:
        fail("modeled error inventory changed")
    if operation.get("httpChecksum") != {
        "requestAlgorithmMember": "ChecksumAlgorithm",
        "requestChecksumRequired": False,
    }:
        fail("checksum request trait changed")
    if "staticContextParams" in operation:
        fail("restore operation unexpectedly gained static context")
    roots = [
        operation["input"]["shape"], operation["output"]["shape"],
        *[item["shape"] for item in operation["errors"]],
    ]
    if reachable_shapes(model, roots) != REACHABLE_SHAPES:
        fail("reachable restore shape inventory changed")

    request = model["shapes"]["RestoreObjectRequest"]
    if request.get("type") != "structure" or (
        request.get("payload") != "RestoreRequest"
    ) or request.get("required") != ["Bucket", "Key"]:
        fail("required request members or payload changed")
    if members(request) != [
        ("Bucket", "BucketName", "uri", "Bucket"),
        ("Key", "ObjectKey", "uri", "Key"),
        ("VersionId", "ObjectVersionId", "querystring", "versionId"),
        ("RestoreRequest", "RestoreRequest", "body", "RestoreRequest"),
        ("RequestPayer", "RequestPayer", "header", "x-amz-request-payer"),
        ("ChecksumAlgorithm", "ChecksumAlgorithm", "header",
         "x-amz-sdk-checksum-algorithm"),
        ("ExpectedBucketOwner", "AccountId", "header",
         "x-amz-expected-bucket-owner"),
    ]:
        fail("top-level request member inventory changed")
    if request["members"]["Bucket"].get("contextParam") != {
        "name": "Bucket"
    }:
        fail("bucket context parameter changed")
    if request["members"]["RestoreRequest"].get("xmlNamespace") != {
        "uri": "http://s3.amazonaws.com/doc/2006-03-01/"
    }:
        fail("restore request namespace changed")

    response = model["shapes"]["RestoreObjectOutput"]
    if response.get("type") != "structure" or members(response) != [
        ("RequestCharged", "RequestCharged", "header",
         "x-amz-request-charged"),
        ("RestoreOutputPath", "RestoreOutputPath", "header",
         "x-amz-restore-output-path"),
    ]:
        fail("response header inventory changed")
    active_tier = model["shapes"]["ObjectAlreadyInActiveTierError"]
    if active_tier.get("type") != "structure" or (
        active_tier.get("members") != {}
    ) or active_tier.get("error") != {"httpStatusCode": 403} or (
        active_tier.get("exception") is not True
    ):
        fail("active-tier error shape changed")

    expected_structures = {
        "RestoreRequest": ([], [
            "Days", "GlacierJobParameters", "Type", "Tier", "Description",
            "SelectParameters", "OutputLocation",
        ]),
        "GlacierJobParameters": (["Tier"], ["Tier"]),
        "SelectParameters": ([
            "InputSerialization", "ExpressionType", "Expression",
            "OutputSerialization",
        ], [
            "InputSerialization", "ExpressionType", "Expression",
            "OutputSerialization",
        ]),
        "OutputLocation": ([], ["S3"]),
        "S3Location": (["BucketName", "Prefix"], [
            "BucketName", "Prefix", "Encryption", "CannedACL",
            "AccessControlList", "Tagging", "UserMetadata", "StorageClass",
        ]),
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
        "Encryption": (["EncryptionType"], [
            "EncryptionType", "KMSKeyId", "KMSContext",
        ]),
        "Grant": ([], ["Grantee", "Permission"]),
        "Grantee": (["Type"], [
            "DisplayName", "EmailAddress", "ID", "Type", "URI",
        ]),
        "Tag": (["Key", "Value"], ["Key", "Value"]),
        "Tagging": (["TagSet"], ["TagSet"]),
        "MetadataEntry": ([], ["Name", "Value"]),
    }
    for name, (required, names) in expected_structures.items():
        structure(model, name, required, names)
    if model["shapes"]["Days"] != {"type": "integer", "box": True}:
        fail("unbounded boxed Days shape changed")
    if model["shapes"]["Tier"] != {
        "type": "string", "enum": ["Standard", "Bulk", "Expedited"],
    }:
        fail("restore tier domain changed")
    if model["shapes"]["RestoreRequestType"] != {
        "type": "string", "enum": ["SELECT"],
    }:
        fail("restore request type domain changed")
    if model["shapes"]["ExpressionType"] != {
        "type": "string", "enum": ["SQL"],
    }:
        fail("select expression type domain changed")
    if model["shapes"]["ChecksumAlgorithm"]["enum"] != [
        "CRC32", "CRC32C", "SHA1", "SHA256", "CRC64NVME", "SHA512",
        "MD5", "XXHASH64", "XXHASH3", "XXHASH128",
    ]:
        fail("checksum algorithm domain changed")
    for shape_name, member_shape in (
        ("Grants", "Grant"), ("TagSet", "Tag"),
        ("UserMetadata", "MetadataEntry"),
    ):
        shape = model["shapes"][shape_name]
        if shape.get("type") != "list" or shape.get("member") != {
            "shape": member_shape, "locationName": member_shape,
        }:
            fail(f"{shape_name} list shape changed")

    generated = (
        ROOT / "src/flyology-object_storage-s3-model.adb"
    ).read_text(encoding="utf-8")
    for fragment in (
        'return "RestoreObject";',
        'return "/{Bucket}/{Key+}?restore";',
        'return "RestoreObjectOutput";',
        'return "RestoreObjectRequest";',
        'return "RestoreRequest";',
        'return "x-amz-restore-output-path";',
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
        "Prepare_Restore_Object", "Execute_Restore_Object",
        "Restore_Object_Operation", "Restore_Object",
    ):
        if symbol in client:
            fail(f"model-only review unexpectedly exposes {symbol}")
    print("RestoreObject model review: 7 request, 2 response, 63 shapes")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, TypeError, UnicodeError, ValueError) as exc:
        print(f"RestoreObject model verification failed: {exc}",
              file=sys.stderr)
        raise SystemExit(1)
