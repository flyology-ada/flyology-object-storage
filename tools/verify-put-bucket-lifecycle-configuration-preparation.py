#!/usr/bin/env python3
"""Verify the pinned lifecycle-write inventory and implemented boundary."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "src/flyology-object_storage-s3-model.adb"
LOCK = ROOT / "coverage/corpora.lock.toml"
SOURCES = (
    ROOT / "src/flyology-object_storage-client-low_level.ads",
    ROOT / "src/flyology-object_storage-client-low_level.adb",
    ROOT / "src/flyology-object_storage-client-buckets.ads",
    ROOT / "src/flyology-object_storage-client-buckets.adb",
    ROOT / "src/flyology-object_storage-s3-lifecycle.ads",
    ROOT / "src/flyology-object_storage-s3-lifecycle.adb",
    ROOT / "tests/src/s3_put_bucket_lifecycle_configuration_corpus.adb",
)
REVISION = "36c34f15391da01cd717c73c0fffa747c9889768"
SHA256 = "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"


def fail(message: str) -> None:
    raise ValueError(message)


def function_body(model: str, function: str) -> str:
    match = re.search(rf"   function {re.escape(function)}(?=\s*\()", model)
    if match is None:
        fail(f"generated model lacks {function}")
    tail = model[match.end():]
    marker = f"end {function};"
    if marker not in tail:
        fail(f"generated model lacks end {function}")
    return tail.split(marker, 1)[0]


def operation_scalar(model: str, function: str) -> str:
    match = re.search(
        r"when Put_Bucket_Lifecycle_Configuration_Operation =>\s+"
        r"return\s+([^;]+);", function_body(model, function))
    if match is None:
        fail(f"PutBucketLifecycleConfiguration lacks {function}")
    return match.group(1).strip().strip('"')


def shape_scalar(model: str, function: str, shape: int) -> str:
    match = re.search(rf"when\s+{shape}\s+=>\s+return\s+([^;]+);",
                      function_body(model, function))
    if match is None:
        fail(f"shape {shape} lacks {function}")
    return match.group(1).strip().strip('"')


def case_values(model: str, function: str, shape: int) -> list[str]:
    match = re.search(rf"when {shape} =>\s+case Member is(.*?)\s+end case;",
                      function_body(model, function), re.DOTALL)
    if match is None:
        fail(f"shape {shape} lacks {function} members")
    value = r'"([^\"]*)"' if function in (
        "Member_Name", "Member_Location_Name") else \
        r"([A-Za-z_][A-Za-z0-9_]*|\d+)"
    pairs = re.findall(rf"when\s+(\d+)\s+=>\s+return\s+{value};",
                       match.group(1))
    if [int(index) for index, _ in pairs] != list(range(1, len(pairs) + 1)):
        fail(f"shape {shape} {function} is not contiguous")
    return [item for _, item in pairs]


def enum_values(model: str, shape: int) -> list[str]:
    match = re.search(rf"when {shape} =>\s+case Index is(.*?)\s+end case;",
                      function_body(model, "Enumeration_Value"), re.DOTALL)
    if match is None:
        fail(f"shape {shape} lacks enum values")
    return [value for _, value in re.findall(
        r'when\s+(\d+)\s+=>\s+return\s+"([^"]*)";', match.group(1))]


def main() -> int:
    lock = LOCK.read_text(encoding="utf-8")
    if f'revision = "{REVISION}"' not in lock or \
            f'service_model_sha256 = "{SHA256}"' not in lock:
        fail("pinned botocore identity changed")
    model = MODEL.read_text(encoding="utf-8")
    scalars = {
        "Method": "Put_Method",
        "Request_URI": "/{Bucket}?lifecycle",
        "Response_Code": "200",
        "Input_Shape": "532",
        "Output_Shape": "531",
        "Request_Checksum_Required": "True",
        "Request_Checksum_Algorithm_Member": "ChecksumAlgorithm",
    }
    for function, expected in scalars.items():
        if operation_scalar(model, function) != expected:
            fail(f"generated {function} changed")

    if case_values(model, "Member_Name", 532) != [
            "Bucket", "ChecksumAlgorithm", "LifecycleConfiguration",
            "ExpectedBucketOwner", "TransitionDefaultMinimumObjectSize"] or \
            case_values(model, "Member_Shape", 532) != [
                "60", "77", "55", "15", "693"] or \
            case_values(model, "Member_Required", 532) != [
                "True", "False", "False", "False", "False"] or \
            case_values(model, "Member_Location_Name", 532) != [
                "Bucket", "x-amz-sdk-checksum-algorithm",
                "LifecycleConfiguration", "x-amz-expected-bucket-owner",
                "x-amz-transition-default-minimum-object-size"]:
        fail("generated lifecycle-write request inventory changed")
    if case_values(model, "Member_Name", 531) != [
            "TransitionDefaultMinimumObjectSize"] or \
            case_values(model, "Member_Shape", 531) != ["693"] or \
            case_values(model, "Member_Location_Name", 531) != [
                "x-amz-transition-default-minimum-object-size"]:
        fail("generated lifecycle-write response inventory changed")
    if case_values(model, "Member_Name", 55) != ["Rules"] or \
            case_values(model, "Member_Shape", 55) != ["377"] or \
            case_values(model, "Member_Required", 55) != ["True"] or \
            case_values(model, "Member_Location_Name", 55) != ["Rule"]:
        fail("generated lifecycle configuration root changed")
    if shape_scalar(model, "Kind", 377) != "List_Shape" or \
            shape_scalar(model, "List_Member_Shape", 377) != "374" or \
            shape_scalar(model, "Is_Flattened", 377) != "True":
        fail("generated lifecycle rule projection changed")
    if enum_values(model, 77) != [
            "CRC32", "CRC32C", "SHA1", "SHA256", "CRC64NVME", "SHA512",
            "MD5", "XXHASH64", "XXHASH3", "XXHASH128"] or \
            enum_values(model, 693) != [
                "varies_by_storage_class", "all_storage_classes_128K"]:
        fail("generated lifecycle-write enum domain changed")

    source = "\n".join(path.read_text(encoding="utf-8") for path in SOURCES)
    for token in (
            "Serialize", "Prepare_Put_Bucket_Lifecycle_Configuration",
            "Decode_Put_Bucket_Lifecycle_Configuration_Response",
            "Execute_Put_Bucket_Lifecycle_Configuration",
            "Put_Bucket_Lifecycle_Operation", "Set_Lifecycle_Configuration",
            "Put_Bucket_Lifecycle_Configuration_Parameters",
            "x-amz-transition-default-minimum-object-size",
            "x-amz-sdk-checksum-algorithm"):
        if token not in source:
            fail(f"typed implementation lacks {token}")
    print("PutBucketLifecycleConfiguration preparation: five request members, "
          "one response member, required flattened Rules, 12 exact checksum/"
          "transition values, and the shared 32-member lifecycle graph")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, UnicodeError, ValueError) as exc:
        print("PutBucketLifecycleConfiguration verification failed: "
              f"{exc}", file=sys.stderr)
        raise SystemExit(1)
