#!/usr/bin/env python3
"""Verify the reviewed model-only PutObjectAcl boundary."""

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


def members(shape: dict) -> list[tuple[str, str, str, str, bool, bool]]:
    return [
        (
            name,
            item["shape"],
            item.get("location", "body"),
            item.get("locationName", name),
            item.get("streaming", False),
            item.get("xmlAttribute", False),
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
    operation = model["operations"]["PutObjectAcl"]
    if operation["http"] != {
        "method": "PUT", "requestUri": "/{Bucket}/{Key+}?acl",
    }:
        fail("method or request URI changed")
    if operation["input"] != {"shape": "PutObjectAclRequest"} or (
        operation["output"] != {"shape": "PutObjectAclOutput"}
    ):
        fail("input or output shape changed")
    if [item["shape"] for item in operation["errors"]] != ["NoSuchKey"]:
        fail("modeled error inventory changed")
    if operation["httpChecksum"] != {
        "requestAlgorithmMember": "ChecksumAlgorithm",
        "requestChecksumRequired": True,
    }:
        fail("required checksum request trait changed")

    request = model["shapes"]["PutObjectAclRequest"]
    if request.get("payload") != "AccessControlPolicy" or (
        request["required"] != ["Bucket", "Key"]
    ):
        fail("required request members or payload changed")
    expected_request = [
        ("ACL", "ObjectCannedACL", "header", "x-amz-acl", False, False),
        ("AccessControlPolicy", "AccessControlPolicy", "body",
         "AccessControlPolicy", False, False),
        ("Bucket", "BucketName", "uri", "Bucket", False, False),
        ("ContentMD5", "ContentMD5", "header", "Content-MD5", False,
         False),
        ("ChecksumAlgorithm", "ChecksumAlgorithm", "header",
         "x-amz-sdk-checksum-algorithm", False, False),
        ("GrantFullControl", "GrantFullControl", "header",
         "x-amz-grant-full-control", False, False),
        ("GrantRead", "GrantRead", "header", "x-amz-grant-read", False,
         False),
        ("GrantReadACP", "GrantReadACP", "header",
         "x-amz-grant-read-acp", False, False),
        ("GrantWrite", "GrantWrite", "header", "x-amz-grant-write", False,
         False),
        ("GrantWriteACP", "GrantWriteACP", "header",
         "x-amz-grant-write-acp", False, False),
        ("Key", "ObjectKey", "uri", "Key", False, False),
        ("RequestPayer", "RequestPayer", "header", "x-amz-request-payer",
         False, False),
        ("VersionId", "ObjectVersionId", "querystring", "versionId", False,
         False),
        ("ExpectedBucketOwner", "AccountId", "header",
         "x-amz-expected-bucket-owner", False, False),
    ]
    if members(request) != expected_request:
        fail("top-level request member inventory changed")
    policy_member = request["members"]["AccessControlPolicy"]
    if policy_member.get("xmlNamespace") != {
        "uri": "http://s3.amazonaws.com/doc/2006-03-01/"
    }:
        fail("access-control policy request namespace changed")

    response = model["shapes"]["PutObjectAclOutput"]
    if members(response) != [
        ("RequestCharged", "RequestCharged", "header",
         "x-amz-request-charged", False, False),
    ]:
        fail("response member inventory changed")

    policy = model["shapes"]["AccessControlPolicy"]
    if policy.get("type") != "structure" or policy.get("required", []) != []:
        fail("access-control policy shape changed")
    if members(policy) != [
        ("Grants", "Grants", "body", "AccessControlList", False, False),
        ("Owner", "Owner", "body", "Owner", False, False),
    ]:
        fail("access-control policy member inventory changed")
    grants = model["shapes"]["Grants"]
    if grants.get("type") != "list" or grants.get("member") != {
        "shape": "Grant", "locationName": "Grant",
    }:
        fail("grant-list shape changed")
    grant = model["shapes"]["Grant"]
    if grant.get("type") != "structure" or grant.get("required", []) != []:
        fail("grant shape changed")
    if members(grant) != [
        ("Grantee", "Grantee", "body", "Grantee", False, False),
        ("Permission", "Permission", "body", "Permission", False, False),
    ]:
        fail("grant member inventory changed")
    grantee = model["shapes"]["Grantee"]
    if grantee.get("type") != "structure" or (
        grantee.get("required") != ["Type"]
    ):
        fail("grantee shape changed")
    if members(grantee) != [
        ("DisplayName", "DisplayName", "body", "DisplayName", False, False),
        ("EmailAddress", "EmailAddress", "body", "EmailAddress", False,
         False),
        ("ID", "ID", "body", "ID", False, False),
        ("Type", "Type", "body", "xsi:type", False, True),
        ("URI", "URI", "body", "URI", False, False),
    ]:
        fail("grantee member inventory changed")
    if grantee.get("xmlNamespace") != {
        "prefix": "xsi",
        "uri": "http://www.w3.org/2001/XMLSchema-instance",
    }:
        fail("grantee XML namespace changed")
    owner = model["shapes"]["Owner"]
    if owner.get("type") != "structure" or owner.get("required", []) != []:
        fail("owner shape changed")
    if members(owner) != [
        ("DisplayName", "DisplayName", "body", "DisplayName", False, False),
        ("ID", "ID", "body", "ID", False, False),
    ]:
        fail("owner member inventory changed")
    if model["shapes"]["Permission"] != {
        "type": "string",
        "enum": ["FULL_CONTROL", "WRITE", "WRITE_ACP", "READ", "READ_ACP"],
    }:
        fail("permission domain changed")
    if model["shapes"]["Type"] != {
        "type": "string",
        "enum": ["CanonicalUser", "AmazonCustomerByEmail", "Group"],
    }:
        fail("grantee type domain changed")
    if model["shapes"]["ObjectCannedACL"] != {
        "type": "string",
        "enum": [
            "private", "public-read", "public-read-write",
            "authenticated-read", "aws-exec-read", "bucket-owner-read",
            "bucket-owner-full-control",
        ],
    }:
        fail("object canned-ACL domain changed")
    for shape_name in (
        "ContentMD5", "GrantFullControl", "GrantRead", "GrantReadACP",
        "GrantWrite", "GrantWriteACP",
    ):
        if model["shapes"][shape_name] != {"type": "string"}:
            fail(f"{shape_name} shape changed")
    if model["shapes"]["ChecksumAlgorithm"] != {
        "type": "string",
        "enum": [
            "CRC32", "CRC32C", "SHA1", "SHA256", "CRC64NVME", "SHA512",
            "MD5", "XXHASH64", "XXHASH3", "XXHASH128",
        ],
    }:
        fail("checksum algorithm domain changed")

    generated = (
        ROOT / "src/flyology-object_storage-s3-model.adb"
    ).read_text(encoding="utf-8")
    for fragment in (
        'return "PutObjectAcl";',
        'return "/{Bucket}/{Key+}?acl";',
        'return "PutObjectAclOutput";',
        'return "PutObjectAclRequest";',
        'return "AccessControlPolicy";',
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
        "Prepare_Put_Object_ACL", "Execute_Put_Object_ACL",
        "Put_Object_ACL_Operation", "Put_Object_ACL", "Put_ACL",
        "Set_Object_ACL",
    ):
        if symbol in client:
            fail(f"model-only review unexpectedly exposes {symbol}")
    print("PutObjectAcl model review: 14 request and 1 response members")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, TypeError, UnicodeError, ValueError) as exc:
        print(f"PutObjectAcl model verification failed: {exc}",
              file=sys.stderr)
        raise SystemExit(1)
