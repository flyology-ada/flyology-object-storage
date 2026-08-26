#!/usr/bin/env python3
"""Verify the pinned PutBucketReplication request and typed implementation."""

from __future__ import annotations

import re
import runpy
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "src/flyology-object_storage-s3-model.adb"
GET_VERIFIER = ROOT / "tools/verify-get-bucket-replication-preparation.py"
SOURCES = (
    ROOT / "src/flyology-object_storage-client-low_level.ads",
    ROOT / "src/flyology-object_storage-client-low_level.adb",
    ROOT / "src/flyology-object_storage-client-buckets.ads",
    ROOT / "src/flyology-object_storage-client-buckets.adb",
    ROOT / "src/flyology-object_storage-s3-replication.ads",
    ROOT / "src/flyology-object_storage-s3-replication.adb",
    ROOT / "tests/src/s3_put_bucket_replication_corpus.adb",
)


def fail(message: str) -> None:
    raise ValueError(message)


def main() -> int:
    shared = runpy.run_path(str(GET_VERIFIER))
    if shared["main"]() != 0:
        fail("shared replication graph verification failed")
    model = MODEL.read_text(encoding="utf-8")

    def operation_scalar(function: str) -> str:
        match = re.search(
            r"when Put_Bucket_Replication_Operation =>\s+return\s+([^;]+);",
            shared["function_body"](model, function),
        )
        if match is None:
            fail(f"PutBucketReplication lacks {function}")
        return match.group(1).strip().strip('"')

    expected = {
        "Method": "Put_Method",
        "Request_URI": "/{Bucket}?replication",
        "Response_Code": "200",
        "Input_Shape": "540",
        "Output_Shape": "0",
        "Request_Checksum_Required": "True",
        "Request_Checksum_Algorithm_Member": "ChecksumAlgorithm",
    }
    for function, value in expected.items():
        if operation_scalar(function) != value:
            fail(f"generated PutBucketReplication {function} changed")

    shared["require_shape"](
        model,
        540,
        ["Bucket", "ContentMD5", "ChecksumAlgorithm",
         "ReplicationConfiguration", "Token", "ExpectedBucketOwner"],
        ["60", "111", "77", "588", "483", "15"],
        ["True", "False", "False", "True", "False", "False"],
        ["Bucket", "Content-MD5", "x-amz-sdk-checksum-algorithm",
         "ReplicationConfiguration", "x-amz-bucket-object-lock-token",
         "x-amz-expected-bucket-owner"],
    )
    if shared["enum_values"](model, 77) != [
        "CRC32", "CRC32C", "SHA1", "SHA256", "CRC64NVME", "SHA512",
        "MD5", "XXHASH64", "XXHASH3", "XXHASH128",
    ]:
        fail("PutBucketReplication checksum domain changed")

    source = "\n".join(path.read_text(encoding="utf-8") for path in SOURCES)
    for token in (
        "Serialize", "Prepare_Put_Bucket_Replication",
        "Execute_Put_Bucket_Replication", "Put_Bucket_Replication",
        "Put_Bucket_Replication_Operation", "Set_Replication_Configuration",
        "Put_Bucket_Replication_Parameters",
        "x-amz-bucket-object-lock-token", "Content-MD5",
    ):
        if token not in source:
            fail(f"typed implementation lacks {token}")
    print(
        "PutBucketReplication preparation: six request members, required "
        "replication payload, required request checksum, exact token/owner/MD5 "
        "headers, and shared complete replication graph"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"PutBucketReplication verification failed: {exc}",
              file=sys.stderr)
        raise SystemExit(1)
