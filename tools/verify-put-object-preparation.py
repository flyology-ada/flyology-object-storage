#!/usr/bin/env python3
"""Fail-closed static evidence for reviewed PutObject qualification."""

from __future__ import annotations

import hashlib
import json
import os
import re
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "coverage" / "s3-operations.toml"
LOW_SPEC = ROOT / "src" / "flyology-object_storage-client-low_level.ads"
LOW_BODY = ROOT / "src" / "flyology-object_storage-client-low_level.adb"
OBJECTS_SPEC = ROOT / "src" / "flyology-object_storage-client-objects.ads"
OBJECTS_BODY = ROOT / "src" / "flyology-object_storage-client-objects.adb"
TESTING = (
    ROOT
    / "tests"
    / "src"
    / "flyology-object_storage-client-objects-testing.adb"
)
CERTAINTY = (
    ROOT / "tests" / "corpora" / "composable-client" / "put-certainty.tsv"
)
SOCKET = ROOT / "tests" / "src" / "s3_http_socket_corpus.adb"
BACKEND = ROOT / "tests" / "src" / "object_storage_test_cases.adb"
SERVER = ROOT / "tests" / "src" / "s3_server_application_corpus.adb"
IMPLEMENTATION = ROOT / "tests" / "src" / "s3_implementation_corpus.adb"
QUALIFICATION = ROOT / "docs" / "qualification" / "put-object.md"

MODEL_SHA256 = (
    "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
)
EXPECTED_INPUT_MEMBERS = [
    "ACL",
    "Body",
    "Bucket",
    "CacheControl",
    "ContentDisposition",
    "ContentEncoding",
    "ContentLanguage",
    "ContentLength",
    "ContentMD5",
    "ContentType",
    "ChecksumAlgorithm",
    "ChecksumCRC32",
    "ChecksumCRC32C",
    "ChecksumCRC64NVME",
    "ChecksumSHA1",
    "ChecksumSHA256",
    "ChecksumSHA512",
    "ChecksumMD5",
    "ChecksumXXHASH64",
    "ChecksumXXHASH3",
    "ChecksumXXHASH128",
    "Expires",
    "IfMatch",
    "IfNoneMatch",
    "GrantFullControl",
    "GrantRead",
    "GrantReadACP",
    "GrantWriteACP",
    "Key",
    "WriteOffsetBytes",
    "Metadata",
    "ServerSideEncryption",
    "StorageClass",
    "WebsiteRedirectLocation",
    "SSECustomerAlgorithm",
    "SSECustomerKey",
    "SSECustomerKeyMD5",
    "SSEKMSKeyId",
    "SSEKMSEncryptionContext",
    "BucketKeyEnabled",
    "RequestPayer",
    "Tagging",
    "ObjectLockMode",
    "ObjectLockRetainUntilDate",
    "ObjectLockLegalHoldStatus",
    "ExpectedBucketOwner",
]
EXPECTED_OUTPUT_MEMBERS = [
    "Expiration",
    "ETag",
    "ChecksumCRC32",
    "ChecksumCRC32C",
    "ChecksumCRC64NVME",
    "ChecksumSHA1",
    "ChecksumSHA256",
    "ChecksumSHA512",
    "ChecksumMD5",
    "ChecksumXXHASH64",
    "ChecksumXXHASH3",
    "ChecksumXXHASH128",
    "ChecksumType",
    "ServerSideEncryption",
    "VersionId",
    "SSECustomerAlgorithm",
    "SSECustomerKeyMD5",
    "SSEKMSKeyId",
    "SSEKMSEncryptionContext",
    "BucketKeyEnabled",
    "Size",
    "RequestCharged",
]
EXPECTED_INPUT_LOCATION_NAMES = [
    "x-amz-acl",
    "",
    "Bucket",
    "Cache-Control",
    "Content-Disposition",
    "Content-Encoding",
    "Content-Language",
    "Content-Length",
    "Content-MD5",
    "Content-Type",
    "x-amz-sdk-checksum-algorithm",
    "x-amz-checksum-crc32",
    "x-amz-checksum-crc32c",
    "x-amz-checksum-crc64nvme",
    "x-amz-checksum-sha1",
    "x-amz-checksum-sha256",
    "x-amz-checksum-sha512",
    "x-amz-checksum-md5",
    "x-amz-checksum-xxhash64",
    "x-amz-checksum-xxhash3",
    "x-amz-checksum-xxhash128",
    "Expires",
    "If-Match",
    "If-None-Match",
    "x-amz-grant-full-control",
    "x-amz-grant-read",
    "x-amz-grant-read-acp",
    "x-amz-grant-write-acp",
    "Key",
    "x-amz-write-offset-bytes",
    "x-amz-meta-",
    "x-amz-server-side-encryption",
    "x-amz-storage-class",
    "x-amz-website-redirect-location",
    "x-amz-server-side-encryption-customer-algorithm",
    "x-amz-server-side-encryption-customer-key",
    "x-amz-server-side-encryption-customer-key-MD5",
    "x-amz-server-side-encryption-aws-kms-key-id",
    "x-amz-server-side-encryption-context",
    "x-amz-server-side-encryption-bucket-key-enabled",
    "x-amz-request-payer",
    "x-amz-tagging",
    "x-amz-object-lock-mode",
    "x-amz-object-lock-retain-until-date",
    "x-amz-object-lock-legal-hold",
    "x-amz-expected-bucket-owner",
]
EXPECTED_OUTPUT_LOCATION_NAMES = [
    "x-amz-expiration",
    "ETag",
    "x-amz-checksum-crc32",
    "x-amz-checksum-crc32c",
    "x-amz-checksum-crc64nvme",
    "x-amz-checksum-sha1",
    "x-amz-checksum-sha256",
    "x-amz-checksum-sha512",
    "x-amz-checksum-md5",
    "x-amz-checksum-xxhash64",
    "x-amz-checksum-xxhash3",
    "x-amz-checksum-xxhash128",
    "x-amz-checksum-type",
    "x-amz-server-side-encryption",
    "x-amz-version-id",
    "x-amz-server-side-encryption-customer-algorithm",
    "x-amz-server-side-encryption-customer-key-MD5",
    "x-amz-server-side-encryption-aws-kms-key-id",
    "x-amz-server-side-encryption-context",
    "x-amz-server-side-encryption-bucket-key-enabled",
    "x-amz-object-size",
    "x-amz-request-charged",
]
EXPECTED_MODELED_ERRORS = [
    "InvalidRequest",
    "InvalidWriteOffset",
    "TooManyParts",
    "EncryptionTypeMismatch",
]
EXPECTED_CERTAINTY_HEADER = [
    "http_result",
    "admission",
    "status",
    "s3_code",
    "publication",
    "failure_reason",
    "reconcile",
    "note",
]
EXPECTED_MODELED_REJECTION_ROWS = {
    (
        "Response_Complete",
        "Response_Observed",
        "400",
        code,
        "Definitely_Not_Published",
        "Invalid_Request",
        "no",
        "exact modeled request rejection",
    )
    for code in EXPECTED_MODELED_ERRORS
}
EXPECTED_ERRORS = [
    "authentication",
    "authorization",
    "not_found",
    "invalid_request",
    "unavailable_or_retryable",
    "corrupt_or_invalid_response",
]
EXPECTED_SYMBOLS = [
    "Prepare_Put_Object",
    "Decode_Put_Object_Complete_Response",
    "Execute_Put_Object",
    "Conditional_Put_Operation",
    "Put_Object",
    "Finish",
]
EXPECTED_EXCLUSIONS = [
    "directory-bucket and S3 Express endpoint and session semantics are "
    "outside the qualified server profile",
    "only STANDARD storage class is accepted as a validated no-op; other "
    "modeled storage classes are rejected",
    "the server explicitly rejects ACL and grant controls, write offsets, "
    "server-side encryption, SSE-C, KMS and bucket-key controls, "
    "requester-pays, Object Lock, and inner aws-chunked signature-chain "
    "controls",
    "the composable surface owns a bounded complete-object buffer; the "
    "established one-shot borrowed-source overload remains synchronous",
]
EXPECTED_EVIDENCE = {
    "backend": [
        "tests/src/object_storage_test_cases.adb",
        "sqlite/tests/src/flyology_object_storage_sqlite_tests.adb",
    ],
    "client": [
        "src/flyology-object_storage-client-low_level.adb",
        "src/flyology-object_storage-client-objects.adb",
        "tests/src/flyology-object_storage-client-objects-testing.adb",
        "tests/corpora/composable-client/put-certainty.tsv",
        "tools/verify-composable-client-fixtures.sh",
        "tests/src/s3_http_socket_corpus.adb",
    ],
    "server": [
        "tests/src/s3_server_application_corpus.adb",
        "tests/src/s3_http_socket_corpus.adb",
    ],
    "corpus": [
        "tests/src/flyology-object_storage-client-objects-testing.adb",
        "tests/corpora/composable-client/put-certainty.tsv",
        "tools/verify-composable-client-fixtures.sh",
        "tests/src/s3_http_socket_corpus.adb",
        "tests/src/s3_implementation_corpus.adb",
        "tests/src/s3_server_application_corpus.adb",
        "tests/scripts/test-minio.sh",
        "tests/scripts/test-rustfs.sh",
        "tests/scripts/test-seaweedfs.sh",
    ],
}
EXPECTED_ENTRY = {
    "name": "PutObject",
    "tier": "core",
    "provider": "objects",
    "family": "streaming_mutation",
    "public_provider": "Flyology.Object_Storage.Client.Objects",
    "codec": "streaming_request_and_headers",
    "public_name": "Put_Object",
    "absence": "not_applicable",
    "errors": EXPECTED_ERRORS,
    "certainty": (
        "complete observed success or conclusive rejection; otherwise "
        "Outcome_Unknown; no automatic replay"
    ),
    "reconciliation": (
        "caller-selected generation-bound Get_Whole before any retry"
    ),
    "exclusions": EXPECTED_EXCLUSIONS,
    "coverage": {
        "backend": "covered",
        "client": "covered",
        "server": "covered",
        "corpus": "covered",
    },
    "provenance": {
        "backend": "handwritten",
        "client": "handwritten",
        "server": "handwritten",
        "tests": "handwritten",
    },
    "implementation_mode": "handwritten",
    "generator_eligible": False,
    "human_decisions_resolved": True,
    "evidence": EXPECTED_EVIDENCE,
    "decision_status": "reviewed",
    "qualification": "put_object",
    "ada_symbols": EXPECTED_SYMBOLS,
}
EXPECTED_LANE = [
    [
        "uv",
        "run",
        "--python",
        "3.13",
        "--",
        "tools/verify-put-object-preparation.py",
    ],
    ["./tools/verify-composable-client-fixtures.sh"],
    ["@tests", "alr", "-n", "build"],
    ["@tests", "./bin/s3_http_socket_corpus"],
    ["./tools/verify-coverage.sh"],
    [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-put-object-gnatdoc",
    ],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]


class EvidenceError(RuntimeError):
    """One fail-closed mismatch in the reviewed static evidence."""


def fail(message: str) -> None:
    raise EvidenceError(message)


def read_source(path: Path, label: str) -> str:
    data = path.read_bytes()
    if b"\r" in data:
        fail(f"{label}: carriage-return byte present")
    return data.decode("utf-8")


def region(source: str, start: str, end: str, label: str) -> str:
    if source.count(start) != 1:
        fail(f"{label}: start marker count changed")
    if source.count(end) != 1:
        fail(f"{label}: end marker count changed")
    first = source.index(start)
    last = source.index(end)
    if last <= first:
        fail(f"{label}: markers reversed")
    return source[first:last + len(end)]


def normalized(source: str) -> str:
    return re.sub(r"\s+", " ", source)


def normalized_comment(source: str) -> str:
    lines = [
        re.sub(r"^\s*--\s?", "", line)
        for line in source.splitlines()
        if line.lstrip().startswith("--")
    ]
    return normalized("\n".join(lines))


def in_order(source: str, fragments: list[str], label: str) -> None:
    text = normalized(source)
    position = 0
    for fragment in fragments:
        expected = normalized(fragment)
        next_position = text.find(expected, position)
        if next_position < 0:
            fail(f"{label}: missing or reordered fragment: {fragment!r}")
        position = next_position + len(expected)


def exact_count(source: str, fragment: str, count: int, label: str) -> None:
    actual = normalized(source).count(normalized(fragment))
    if actual != count:
        fail(f"{label}: expected {count}, found {actual}: {fragment!r}")


def exact_inventory(
    actual: list[str], expected: list[str], label: str
) -> None:
    if actual != expected:
        fail(f"{label}: inventory or order changed")


def expect_error(action, label: str) -> None:
    try:
        action()
    except EvidenceError:
        return
    fail(f"negative oracle accepted {label}")


def verify_helpers() -> None:
    if region("BEGIN body END", "BEGIN", "END", "fixture") != (
        "BEGIN body END"
    ):
        fail("region helper changed positive extraction")
    expect_error(
        lambda: region("body END", "BEGIN", "END", "fixture"),
        "missing start marker",
    )
    expect_error(
        lambda: region("END body BEGIN", "BEGIN", "END", "fixture"),
        "reversed markers",
    )
    expect_error(
        lambda: in_order("beta alpha", ["alpha", "beta"], "fixture"),
        "reordered evidence",
    )
    expect_error(
        lambda: exact_count("alpha", "alpha", 2, "fixture"),
        "wrong evidence count",
    )
    expect_error(
        lambda: exact_inventory(["beta", "alpha"], ["alpha", "beta"],
                                "fixture"),
        "reordered exact inventory",
    )
    expect_error(
        lambda: exact_inventory(["alpha", "gamma"], ["alpha", "beta"],
                                "fixture"),
        "replaced exact inventory member",
    )


def verify_model() -> None:
    model_name = os.environ.get("FLYOLOGY_S3_SERVICE_MODEL")
    if not model_name:
        fail("FLYOLOGY_S3_SERVICE_MODEL is not set")
    model_path = Path(model_name)
    if not model_path.is_file() or model_path.is_symlink():
        fail("pinned service model is not a regular file")
    digest = hashlib.sha256(model_path.read_bytes()).hexdigest()
    if digest != MODEL_SHA256:
        fail(f"pinned service model hash changed: {digest}")
    model = json.loads(model_path.read_text(encoding="utf-8"))
    operation = model["operations"]["PutObject"]
    if operation["http"] != {
        "method": "PUT",
        "requestUri": "/{Bucket}/{Key+}",
    }:
        fail("PutObject HTTP binding changed")
    input_shape = model["shapes"][operation["input"]["shape"]]
    output_shape = model["shapes"][operation["output"]["shape"]]
    exact_inventory(
        list(input_shape["members"]),
        EXPECTED_INPUT_MEMBERS,
        "PutObject input members",
    )
    if input_shape.get("required") != ["Bucket", "Key"]:
        fail("PutObject required member inventory changed")
    input_locations = {
        name: member.get("location", "body")
        for name, member in input_shape["members"].items()
    }
    if input_locations["Body"] != "body":
        fail("PutObject Body location changed")
    if input_locations["Bucket"] != "uri":
        fail("PutObject Bucket location changed")
    if input_locations["Key"] != "uri":
        fail("PutObject Key location changed")
    if input_locations["Metadata"] != "headers":
        fail("PutObject Metadata location changed")
    if any(
        location != "header"
        for name, location in input_locations.items()
        if name not in {"Body", "Bucket", "Key", "Metadata"}
    ):
        fail("PutObject singleton input header geometry changed")
    exact_inventory(
        [
            member.get("locationName", "")
            for member in input_shape["members"].values()
        ],
        EXPECTED_INPUT_LOCATION_NAMES,
        "PutObject input location names",
    )
    exact_inventory(
        list(output_shape["members"]),
        EXPECTED_OUTPUT_MEMBERS,
        "PutObject output members",
    )
    if any(
        member.get("location") != "header"
        for member in output_shape["members"].values()
    ):
        fail("PutObject output header geometry changed")
    exact_inventory(
        [
            member.get("locationName", "")
            for member in output_shape["members"].values()
        ],
        EXPECTED_OUTPUT_LOCATION_NAMES,
        "PutObject output location names",
    )
    modeled_errors = [
        error["shape"] for error in operation.get("errors", [])
    ]
    exact_inventory(
        modeled_errors,
        EXPECTED_MODELED_ERRORS,
        "PutObject modeled errors",
    )
    if any(
        model["shapes"][name].get("error", {}).get("httpStatusCode") != 400
        for name in EXPECTED_MODELED_ERRORS
    ):
        fail("PutObject modeled error status geometry changed")


def verify_certainty_fixture() -> None:
    source = read_source(CERTAINTY, "PutObject certainty fixture")
    lines = source.splitlines()
    if not lines:
        fail("PutObject certainty fixture is empty")
    exact_inventory(
        lines[0].split("\t"),
        EXPECTED_CERTAINTY_HEADER,
        "PutObject certainty header",
    )
    rows = [tuple(line.split("\t")) for line in lines[1:]]
    if any(len(row) != len(EXPECTED_CERTAINTY_HEADER) for row in rows):
        fail("PutObject certainty fixture row width changed")
    if len(rows) != 44 or len(set(rows)) != 44:
        fail("PutObject certainty fixture count or uniqueness changed")
    actual_modeled = {
        row
        for row in rows
        if row[2] == "400" and row[3] in EXPECTED_MODELED_ERRORS
    }
    if actual_modeled != EXPECTED_MODELED_REJECTION_ROWS:
        fail("PutObject modeled rejection rows changed")
    for row in rows:
        if row[0] == "Response_Complete" and row[1] != "Response_Observed":
            fail("PutObject complete response lacks observed admission")
        if row[4] == "Outcome_Unknown" and row[6] != "yes":
            fail("PutObject unknown outcome lacks reconciliation")
        if row[4] in {
            "Published",
            "Precondition_Failed",
            "Definitely_Not_Published",
            "Cancelled_Before_Publication",
        } and row[6] != "no":
            fail("PutObject conclusive outcome requests reconciliation")


def verify_registry() -> None:
    parsed = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    entries = [
        item
        for item in parsed["operation"]
        if item["name"] == "PutObject"
    ]
    if len(entries) != 1:
        fail("registry PutObject entry count changed")
    entry = entries[0]
    if entry.keys() != EXPECTED_ENTRY.keys():
        fail("registry PutObject field inventory changed")
    for key, value in EXPECTED_ENTRY.items():
        if entry[key] != value:
            fail(f"registry PutObject {key} changed")
    if parsed["qualification"].get("put_object") != EXPECTED_LANE:
        fail("registry PutObject qualification lane changed")
    for paths in EXPECTED_EVIDENCE.values():
        for relative in paths:
            path = ROOT / relative
            if not path.is_file() or path.is_symlink():
                fail(
                    "registry PutObject evidence path is invalid: "
                    f"{relative}"
                )


def verify_contract() -> None:
    low_spec = read_source(LOW_SPEC, "low-level specification")
    low_region = region(
        low_spec,
        "--  Every non-body, non-ContentLength member in the pinned "
        "PutObject input",
        "return Put_Object_Outcome;\n\n"
        "   --  Modeled DeleteBucket request headers.",
        "low-level PutObject contract",
    )
    in_order(
        low_region,
        [
            "Every non-body, non-ContentLength member in the pinned "
            "PutObject input",
            "type Put_Object_Parameters is record",
            "function Prepare_Put_Object",
            "type Put_Object_Result is record",
            "type Put_Object_Outcome_Kind is",
            "type Put_Object_Outcome",
            "function Decode_Put_Object_Response",
            "function Decode_Put_Object_Complete_Response",
            "function Decode_Put_Object_Complete_Response",
            "function Execute_Put_Object",
        ],
        "low-level PutObject contract",
    )
    exact_count(
        low_region,
        "function Decode_Put_Object_Complete_Response",
        2,
        "low-level request-bound decoder",
    )
    for fragment in [
        "Every non-body, non-ContentLength member",
        "Prepare all 46 modeled PutObject inputs",
        "Every member in the pinned PutObject output shape",
        "present-nonempty semantics for all 22 modeled response headers",
    ]:
        if normalized(fragment) not in normalized_comment(low_region):
            fail(f"low-level PutObject contract lost: {fragment}")

    objects_spec = read_source(OBJECTS_SPEC, "Objects specification")
    public_region = region(
        objects_spec,
        "--  Shape of a terminal complete-object PUT result.",
        "--  Shape of a terminal bounded whole-Get result.",
        "public composable PutObject contract",
    )
    in_order(
        public_region,
        [
            "Shape of a terminal complete-object PUT result",
            "type Conditional_Put_Result_Kind is",
            "type Conditional_Put_Result",
            "type Conditional_Put_Operation",
            "procedure Put_Object",
            "function Put_Object",
            "procedure Finish",
        ],
        "public composable PutObject contract",
    )
    for fragment in [
        "input buffer token moves into this object until Finish",
        "No request is retried",
        "retained through terminal drain",
        "restore its input token",
    ]:
        if normalized(fragment) not in normalized_comment(public_region):
            fail(f"public composable PutObject contract lost: {fragment}")

    low_body = read_source(LOW_BODY, "low-level implementation")
    for fragment in [
        "function Prepare_Put_Object",
        "function Decode_Put_Object_Complete_Response",
        "function Execute_Put_Object",
        "Model.Put_Object_Operation",
    ]:
        if normalized(fragment) not in normalized(low_body):
            fail(f"low-level PutObject implementation lost: {fragment}")

    objects_body = read_source(OBJECTS_BODY, "Objects implementation")
    lifecycle = region(
        objects_body,
        "function Normalize_Put_Response",
        "function Read_Exchange_Failure\n"
        "     (Value : HTTP_Client.Exchange_Result) "
        "return Whole_Get_Result is",
        "provider PutObject lifecycle",
    )
    in_order(
        lifecycle,
        [
            "function Normalize_Put_Response",
            "function Normalize_Put_Failure",
            "procedure Complete_Child",
            "HTTP_Client.Finish",
            "overriding procedure Request_Cancellation",
            "Operations.Cancel (Item.Child)",
            "overriding procedure Finalize",
            "procedure Start_Put_Object",
            "function Put_Object",
            "procedure Finish",
            "Operations.Consume (Operation)",
        ],
        "provider PutObject lifecycle",
    )
    for fragment in [
        "PutObject restart changed a retained owner",
        "PutObject Finish requires the original buffer pool",
        "PutObject has no terminal result",
    ]:
        if fragment not in lifecycle:
            fail(f"provider PutObject invariant lost: {fragment}")


def verify_certainty_and_runtime() -> None:
    verify_certainty_fixture()
    testing = read_source(TESTING, "PutObject certainty corpus")
    certainty = region(
        testing,
        "procedure Check_Put_Certainty_Corpus is",
        "end Check_Put_Certainty_Corpus;",
        "PutObject certainty matrix",
    )
    in_order(
        certainty,
        [
            "Check_Response (200, \"\", Published, No_Failure)",
            "401, \"InvalidAccessKeyId\", Definitely_Not_Published",
            "403, \"AccessDenied\", Definitely_Not_Published",
            "400, \"InvalidRequest\", Definitely_Not_Published",
            "400, \"InvalidWriteOffset\", Definitely_Not_Published",
            "400, \"TooManyParts\", Definitely_Not_Published",
            "400, \"EncryptionTypeMismatch\", Definitely_Not_Published",
            "404, \"NoSuchBucket\", Definitely_Not_Published",
            "409, \"ConditionalRequestConflict\", Outcome_Unknown",
            "429, \"SlowDown\", Outcome_Unknown",
            "500, \"InternalError\", Outcome_Unknown",
            "400, \"\", Outcome_Unknown, Corrupt_Or_Invalid_Response",
            "403, \"\", Outcome_Unknown, Corrupt_Or_Invalid_Response",
            "404, \"\", Outcome_Unknown, Corrupt_Or_Invalid_Response",
            "412, \"\", Outcome_Unknown, Corrupt_Or_Invalid_Response",
            "for Admission in HTTP_Client.Admission_Certainty loop",
            "Check_Failure (Kind, Admission)",
        ],
        "PutObject certainty matrix",
    )

    socket = read_source(SOCKET, "HTTP socket corpus")
    in_order(
        socket,
        [
            "raw PutObject response did not reject",
            "procedure Run_Lost_Put_Reconciliation is",
            "lost PutObject response was classified conclusively",
            "lost PutObject response reconciliation mismatch",
            "scoped PutObject did not move its input token",
            "scoped PutObject success/ownership mismatch",
            "composable complete PutObject retained caller token",
            "composable complete PutObject constructor mismatch",
            "composable complete PutObject restart mismatch",
            "composable PutObject checksum binding mismatch",
        ],
        "HTTP socket PutObject evidence",
    )
    if socket.count("Objects_Testing.Check_Put_Certainty_Corpus;") != 1:
        fail("PutObject certainty corpus registration changed")
    for token in [
        "Put_Admission_Native",
        "Put_Admission_Lightweight",
        "Put_Drain_Native",
        "Put_Drain_Lightweight",
    ]:
        exact_count(socket, f"{token} : aliased", 1, token)
    cancel_region = region(
        socket,
        "Buffers.Copy_From\n"
        '              (Payload_Buffer, Bytes ("scoped-put-cancel-body"));',
        "Buffers.Copy_From\n"
        '              (Payload_Buffer, Bytes ("scoped-cas-body"));',
        "PutObject admitted cancellation and restart",
    )
    in_order(
        cancel_region,
        [
            "Put_Admission_Native.Wait_Source",
            "Put_Drain_Native.Wait_Source",
            "Put_Admission_Lightweight.Wait_Source",
            "Put_Drain_Lightweight.Wait_Source",
            "stale PutObject cancellation readiness",
            "Put_Object",
            "scoped-put-cancel",
            "Flyology.IO.Wait",
            "Flyology.IO.Wait",
            "Operations.Wait_Some",
            "PutObject did not remain active through admission",
            "Flyology.IO.Finish (Admission_Ready)",
            "Operations.Cancel (Operation)",
            "Operations.Wait_All (Set)",
            "Finish (Operation, Result, Payload_Buffer)",
            "admitted PutObject cancellation mismatch",
            "PutObject transport drain was not acknowledged",
            "Flyology.IO.Finish (Drain_Ready)",
            "Put_Object",
            'Key => "scoped-put-restart"',
            "Operation => Operation",
            "Operations.Wait_All (Set)",
            "Finish (Operation, Result, Payload_Buffer)",
            "same-object PutObject restart after cancellation",
        ],
        "PutObject admitted cancellation and restart",
    )
    for fragment, count in [
        ("Operations.Cancel (Operation)", 1),
        ("Finish (Operation, Result, Payload_Buffer)", 2),
        ('"scoped-put-cancel-body"', 5),
    ]:
        exact_count(cancel_region, fragment, count, "PutObject cancellation")
    exact_count(
        socket,
        "Cancellation_Kind => Put_Object_Cancellation",
        1,
        "PutObject cancellation server exchange",
    )
    typed_regions = [
        (
            region(
                cancel_region,
                "if Result.Kind /= Put_Exchange_Failed",
                "admitted PutObject cancellation mismatch",
                "PutObject cancellation result",
            ),
            [
                "Result.Kind /= Put_Exchange_Failed",
                "Result.Failure /= Client_API.Cancelled",
                "Result.HTTP_Result /= HTTP_Client.Cancelled",
                "Result.Admission /= HTTP_Client.Possibly_Admitted",
                "not Buffers.Has_Buffer (Payload_Buffer)",
                'Buffer_String (Payload_Buffer) /= "scoped-put-cancel-body"',
            ],
            "PutObject cancellation result",
        ),
        (
            region(
                cancel_region,
                "if Result.Kind /= Put_Response_Available",
                "same-object PutObject restart after cancellation ",
                "PutObject restart result",
            ),
            [
                "Result.Kind /= Put_Response_Available",
                "Result.Disposition /= Published",
                "Result.Failure /= No_Failure",
                "Result.Admission /= HTTP_Client.Response_Observed",
                "Result.Response.Kind /= Low_Level.Object_Put",
                '"""scoped-put-restart"""',
                "not Buffers.Has_Buffer (Payload_Buffer)",
                'Buffer_String (Payload_Buffer) /= "scoped-put-cancel-body"',
            ],
            "PutObject restart result",
        ),
    ]
    for typed_region, predicates, label in typed_regions:
        for fragment in predicates:
            exact_count(typed_region, fragment, 1, label)
            weakened = normalized(typed_region).replace(
                normalized(fragment), "", 1
            )
            expect_error(
                lambda weakened=weakened, fragment=fragment, label=label:
                    exact_count(weakened, fragment, 1, label),
                f"removed typed predicate {fragment}",
            )
    exact_count(
        cancel_region,
        "not Operations.Is_Terminal (Drain_Ready)",
        1,
        "PutObject drain acknowledgement",
    )

    server_cancel = region(
        socket,
        "if Await_Cancellation then",
        "Request_Drain;\n               return;",
        "PutObject cancellation server routing",
    )
    server_tokens = [
        "List_V2_Drain_Native.Request",
        "List_V2_Drain_Lightweight.Request",
        "Put_Drain_Native.Request",
        "Put_Drain_Lightweight.Request",
        "List_V2_Admission_Native.Request",
        "List_V2_Admission_Lightweight.Request",
        "Put_Admission_Native.Request",
        "Put_Admission_Lightweight.Request",
    ]
    in_order(
        server_cancel,
        server_tokens,
        "PutObject cancellation server routing",
    )
    for fragment in server_tokens:
        exact_count(
            server_cancel,
            fragment,
            1,
            "PutObject cancellation server routing",
        )
        weakened = server_cancel.replace(fragment, "", 1)
        expect_error(
            lambda weakened=weakened, fragment=fragment: exact_count(
                weakened,
                fragment,
                1,
                "PutObject cancellation server routing",
            ),
            f"removed cancellation routing token {fragment}",
        )

    backend = read_source(BACKEND, "backend corpus")
    for fragment in [
        "PutObject exact target and streaming payload hash",
        "PutObject modeled header families are signed",
        "Check_Put_Object_Response_Decoder",
        "Check_Put_Object_Required_Disposition",
    ]:
        if fragment not in backend:
            fail(f"backend PutObject evidence lost: {fragment}")

    server = read_source(SERVER, "server corpus")
    for fragment in [
        "PutObject on an absent bucket did not return NoSuchBucket",
        "complete PutObject tuple persistence",
        "PutObject integrity failure mutated the prior object",
        "PutObject ignored expected owner mismatch",
        "PutObject 5 GiB exact/+1 scalar boundary failed",
        "PutObject accepted undecoded inner aws-chunked frames",
    ]:
        if fragment not in server:
            fail(f"server PutObject evidence lost: {fragment}")

    implementation = read_source(IMPLEMENTATION, "implementation corpus")
    for fragment in [
        "S3 implementation rejected complete PutObject tuple",
        "S3 implementation changed complete PutObject bytes",
        "S3 implementation changed complete PutObject tags",
        "durable version-routing PutObject generations mismatch",
    ]:
        if fragment not in implementation:
            fail(f"implementation PutObject evidence lost: {fragment}")


def verify_qualification_text() -> None:
    text = read_source(QUALIFICATION, "PutObject qualification prose")
    in_order(
        text,
        [
            "# PutObject qualification and boundaries",
            "## Request members (46)",
            "## Output positions (22)",
            "## Atomic publication and direct checksums",
            "## Client publication certainty",
            "generation-bound GET",
            "there is no transparent replay",
            "## Server compatibility boundaries",
            "## Reproducible functional evidence",
        ],
        "PutObject qualification prose",
    )


def main() -> int:
    verify_helpers()
    verify_model()
    verify_registry()
    verify_contract()
    verify_certainty_and_runtime()
    verify_qualification_text()
    print(
        "PutObject preparation: reviewed streaming publication contract "
        "and cross-layer evidence OK"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except EvidenceError as error:
        raise SystemExit(f"PutObject preparation failed: {error}")
    except (
        json.JSONDecodeError,
        KeyError,
        OSError,
        UnicodeError,
        tomllib.TOMLDecodeError,
    ) as error:
        raise SystemExit(
            "PutObject preparation failed: unreadable evidence: "
            f"{error}"
        )
