#!/usr/bin/env python3
"""Fail-closed evidence for reviewed CompleteMultipartUpload qualification."""

from __future__ import annotations

import hashlib
import json
import os
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODEL_SHA256 = (
    "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
)
CERTAINTY_SHA256 = (
    "79b179ff7d0e0cdce2f1cc863639c69775d3933080ed8366b0bb4d4df1c54736"
)
EXPECTED_CERTAINTY_ROWS = [
    (
        "Response_Complete",
        "Response_Observed",
        "200",
        "none",
        "Multipart_Completed",
        "No_Failure",
        "no",
        "complete modeled success proves destination "
        "publication",
    ),
    (
        "Response_Complete",
        "Response_Observed",
        "200",
        "InternalError",
        "Completion_Outcome_Unknown",
        "Unavailable_Or_Retryable",
        "yes",
        "embedded success-status error requires read-only "
        "reconciliation",
    ),
    (
        "Response_Complete",
        "Response_Observed",
        "400",
        "BadDigest",
        "Completion_Outcome_Unknown",
        "Invalid_Request",
        "yes",
        "complete rejection remains conservative after "
        "admission",
    ),
    (
        "Response_Complete",
        "Response_Observed",
        "400",
        "EntityTooSmall",
        "Completion_Outcome_Unknown",
        "Invalid_Request",
        "yes",
        "part-size rejection remains conservative after "
        "admission",
    ),
    (
        "Response_Complete",
        "Response_Observed",
        "400",
        "InvalidPart",
        "Completion_Outcome_Unknown",
        "Invalid_Request",
        "yes",
        "part rejection remains conservative after admission",
    ),
    (
        "Response_Complete",
        "Response_Observed",
        "400",
        "InvalidPartOrder",
        "Completion_Outcome_Unknown",
        "Invalid_Request",
        "yes",
        "part-order rejection remains conservative after "
        "admission",
    ),
    (
        "Response_Complete",
        "Response_Observed",
        "400",
        "InvalidRequest",
        "Completion_Outcome_Unknown",
        "Invalid_Request",
        "yes",
        "request rejection remains conservative after admission",
    ),
    (
        "Response_Complete",
        "Response_Observed",
        "401",
        "InvalidAccessKeyId",
        "Completion_Outcome_Unknown",
        "Authentication_Failed",
        "yes",
        "authentication response cannot disprove an earlier "
        "publication",
    ),
    (
        "Response_Complete",
        "Response_Observed",
        "403",
        "AccessDenied",
        "Completion_Outcome_Unknown",
        "Authorization_Failed",
        "yes",
        "authorization response cannot disprove an earlier "
        "publication",
    ),
    (
        "Response_Complete",
        "Response_Observed",
        "404",
        "NoSuchBucket",
        "Completion_Outcome_Unknown",
        "Not_Found",
        "yes",
        "missing destination remains conservative after "
        "admission",
    ),
    (
        "Response_Complete",
        "Response_Observed",
        "404",
        "NoSuchKey",
        "Completion_Outcome_Unknown",
        "Not_Found",
        "yes",
        "missing key remains conservative after admission",
    ),
    (
        "Response_Complete",
        "Response_Observed",
        "404",
        "NoSuchUpload",
        "Completion_Outcome_Unknown",
        "Not_Found",
        "yes",
        "missing upload may follow a successful completion",
    ),
    (
        "Response_Complete",
        "Response_Observed",
        "409",
        "OperationAborted",
        "Completion_Outcome_Unknown",
        "Unavailable_Or_Retryable",
        "yes",
        "conflict requires destination and upload "
        "reconciliation",
    ),
    (
        "Response_Complete",
        "Response_Observed",
        "412",
        "PreconditionFailed",
        "Completion_Outcome_Unknown",
        "Invalid_Request",
        "yes",
        "precondition response remains conservative after "
        "admission",
    ),
    (
        "Response_Complete",
        "Response_Observed",
        "503",
        "SlowDown",
        "Completion_Outcome_Unknown",
        "Unavailable_Or_Retryable",
        "yes",
        "service failure cannot disprove publication",
    ),
    (
        "Response_Complete",
        "Response_Observed",
        "400",
        "missing",
        "Completion_Outcome_Unknown",
        "Corrupt_Or_Invalid_Response",
        "yes",
        "status without exact modeled code is not conclusive",
    ),
    (
        "Pre_Admission_Rejected",
        "Not_Admitted",
        "none",
        "not-applicable",
        "Definitely_Not_Completed",
        "Invalid_Request",
        "no",
        "local validation rejected before admission",
    ),
    (
        "Pre_Admission_Rejected",
        "Possibly_Admitted",
        "none",
        "not-applicable",
        "Completion_Outcome_Unknown",
        "Invalid_Request",
        "yes",
        "inconsistent admission remains conservative",
    ),
    (
        "Pre_Admission_Rejected",
        "Response_Observed",
        "none",
        "not-applicable",
        "Completion_Outcome_Unknown",
        "Invalid_Request",
        "yes",
        "inconsistent admission remains conservative",
    ),
    (
        "Cancelled",
        "Not_Admitted",
        "incomplete",
        "not-applicable",
        "Completion_Cancelled_Before_Admission",
        "Cancelled",
        "no",
        "cancellation completed before admission",
    ),
    (
        "Cancelled",
        "Possibly_Admitted",
        "incomplete",
        "not-applicable",
        "Completion_Outcome_Unknown",
        "Cancelled",
        "yes",
        "cancellation may follow request admission",
    ),
    (
        "Cancelled",
        "Response_Observed",
        "incomplete",
        "not-applicable",
        "Completion_Outcome_Unknown",
        "Cancelled",
        "yes",
        "cancellation after response observation requires "
        "reconciliation",
    ),
    (
        "Timed_Out",
        "Not_Admitted",
        "incomplete",
        "not-applicable",
        "Definitely_Not_Completed",
        "Timed_Out",
        "no",
        "deadline expired before admission",
    ),
    (
        "Timed_Out",
        "Possibly_Admitted",
        "incomplete",
        "not-applicable",
        "Completion_Outcome_Unknown",
        "Timed_Out",
        "yes",
        "deadline may expire after publication",
    ),
    (
        "Timed_Out",
        "Response_Observed",
        "incomplete",
        "not-applicable",
        "Completion_Outcome_Unknown",
        "Timed_Out",
        "yes",
        "observed incomplete response requires reconciliation",
    ),
    (
        "Client_Unavailable",
        "Not_Admitted",
        "none",
        "not-applicable",
        "Definitely_Not_Completed",
        "Client_Unavailable",
        "no",
        "client rejected before admission",
    ),
    (
        "Client_Unavailable",
        "Possibly_Admitted",
        "incomplete",
        "not-applicable",
        "Completion_Outcome_Unknown",
        "Client_Unavailable",
        "yes",
        "client failure cannot disprove admission",
    ),
    (
        "Client_Unavailable",
        "Response_Observed",
        "incomplete",
        "not-applicable",
        "Completion_Outcome_Unknown",
        "Client_Unavailable",
        "yes",
        "observed incomplete result requires reconciliation",
    ),
    (
        "Connection_Failed",
        "Not_Admitted",
        "none",
        "not-applicable",
        "Definitely_Not_Completed",
        "Connection_Failed",
        "no",
        "connection failed before admission",
    ),
    (
        "Connection_Failed",
        "Possibly_Admitted",
        "incomplete",
        "not-applicable",
        "Completion_Outcome_Unknown",
        "Connection_Failed",
        "yes",
        "connection failure cannot disprove admission",
    ),
    (
        "Connection_Failed",
        "Response_Observed",
        "incomplete",
        "not-applicable",
        "Completion_Outcome_Unknown",
        "Connection_Failed",
        "yes",
        "observed incomplete result requires reconciliation",
    ),
    (
        "Transport_Failed",
        "Not_Admitted",
        "none",
        "not-applicable",
        "Definitely_Not_Completed",
        "Transport_Failed",
        "no",
        "transport failed before admission",
    ),
    (
        "Transport_Failed",
        "Possibly_Admitted",
        "incomplete",
        "not-applicable",
        "Completion_Outcome_Unknown",
        "Transport_Failed",
        "yes",
        "lost transport result requires reconciliation",
    ),
    (
        "Transport_Failed",
        "Response_Observed",
        "incomplete",
        "not-applicable",
        "Completion_Outcome_Unknown",
        "Transport_Failed",
        "yes",
        "observed incomplete result requires reconciliation",
    ),
    (
        "Request_Source_Failed",
        "Not_Admitted",
        "none",
        "not-applicable",
        "Definitely_Not_Completed",
        "Request_Source_Failed",
        "no",
        "source failed before admission",
    ),
    (
        "Request_Source_Failed",
        "Possibly_Admitted",
        "incomplete",
        "not-applicable",
        "Completion_Outcome_Unknown",
        "Request_Source_Failed",
        "yes",
        "source failure may follow partial admitted "
        "transmission",
    ),
    (
        "Request_Source_Failed",
        "Response_Observed",
        "incomplete",
        "not-applicable",
        "Completion_Outcome_Unknown",
        "Request_Source_Failed",
        "yes",
        "observed incomplete result requires reconciliation",
    ),
    (
        "Response_Invalid",
        "Not_Admitted",
        "invalid",
        "not-applicable",
        "Definitely_Not_Completed",
        "Corrupt_Or_Invalid_Response",
        "no",
        "invalid local result preceded admission",
    ),
    (
        "Response_Invalid",
        "Possibly_Admitted",
        "invalid",
        "not-applicable",
        "Completion_Outcome_Unknown",
        "Corrupt_Or_Invalid_Response",
        "yes",
        "invalid response cannot disprove publication",
    ),
    (
        "Response_Invalid",
        "Response_Observed",
        "invalid",
        "not-applicable",
        "Completion_Outcome_Unknown",
        "Corrupt_Or_Invalid_Response",
        "yes",
        "invalid observed response requires reconciliation",
    ),
    (
        "Response_Body_Too_Large",
        "Not_Admitted",
        "oversized",
        "not-applicable",
        "Definitely_Not_Completed",
        "Corrupt_Or_Invalid_Response",
        "no",
        "oversized local result preceded admission",
    ),
    (
        "Response_Body_Too_Large",
        "Possibly_Admitted",
        "oversized",
        "not-applicable",
        "Completion_Outcome_Unknown",
        "Corrupt_Or_Invalid_Response",
        "yes",
        "oversized response cannot disprove publication",
    ),
    (
        "Response_Body_Too_Large",
        "Response_Observed",
        "oversized",
        "not-applicable",
        "Completion_Outcome_Unknown",
        "Corrupt_Or_Invalid_Response",
        "yes",
        "bounded response did not complete",
    ),
    (
        "Response_Sink_Failed",
        "Not_Admitted",
        "overflow-or-fault",
        "not-applicable",
        "Definitely_Not_Completed",
        "Corrupt_Or_Invalid_Response",
        "no",
        "local sink failure preceded admission",
    ),
    (
        "Response_Sink_Failed",
        "Possibly_Admitted",
        "overflow-or-fault",
        "not-applicable",
        "Completion_Outcome_Unknown",
        "Corrupt_Or_Invalid_Response",
        "yes",
        "bounded sink failure cannot disprove publication",
    ),
    (
        "Response_Sink_Failed",
        "Response_Observed",
        "overflow-or-fault",
        "not-applicable",
        "Completion_Outcome_Unknown",
        "Corrupt_Or_Invalid_Response",
        "yes",
        "bounded sink did not complete",
    ),
]
REGISTRY = ROOT / "coverage" / "s3-operations.toml"
CERTAINTY = (
    ROOT
    / "tests"
    / "corpora"
    / "composable-client"
    / "complete-multipart-certainty.tsv"
)
LOW_SPEC = ROOT / "src" / "flyology-object_storage-client-low_level.ads"
LOW_BODY = ROOT / "src" / "flyology-object_storage-client-low_level.adb"
TRANSFERS_SPEC = ROOT / "src" / "flyology-object_storage-client-transfers.ads"
TRANSFERS_BODY = ROOT / "src" / "flyology-object_storage-client-transfers.adb"
TESTING = (
    ROOT
    / "tests"
    / "src"
    / "flyology-object_storage-client-transfers-testing.adb"
)
SOCKET = ROOT / "tests" / "src" / "s3_http_socket_corpus.adb"
SERVER = (
    ROOT / "src" / "flyology-object_storage-server-s3_applications.adb"
)
SERVER_TEST = ROOT / "tests" / "src" / "s3_server_application_corpus.adb"
BACKEND = ROOT / "tests" / "src" / "object_storage_test_cases.adb"
SQLITE = (
    ROOT
    / "sqlite"
    / "tests"
    / "src"
    / "flyology_object_storage_sqlite_tests.adb"
)
QUALIFICATION = (
    ROOT / "docs" / "qualification" / "complete-multipart-upload.md"
)


def assert_regular(path: Path) -> None:
    assert path.exists(), f"missing evidence path: {path}"
    assert path.is_file(), f"non-file evidence path: {path}"
    assert not path.is_symlink(), f"symlink evidence path: {path}"


def require_once(text: str, marker: str, label: str) -> int:
    count = text.count(marker)
    assert count == 1, f"{label}: expected once, found {count}: {marker}"
    return text.index(marker)


def require_ordered(text: str, markers: list[str], label: str) -> None:
    positions = [require_once(text, marker, label) for marker in markers]
    assert positions == sorted(positions), f"{label}: evidence order changed"


def region(text: str, first: str, last: str, label: str) -> str:
    start = require_once(text, first, label)
    finish = require_once(text, last, label)
    assert start < finish, f"{label}: invalid boundary order"
    return text[start:finish]


def load_model() -> dict[str, object]:
    model_path = os.environ.get("FLYOLOGY_S3_SERVICE_MODEL", "")
    assert model_path, "FLYOLOGY_S3_SERVICE_MODEL is required"
    path = Path(model_path)
    assert_regular(path)
    assert hashlib.sha256(path.read_bytes()).hexdigest() == MODEL_SHA256
    return json.loads(path.read_text(encoding="utf-8"))


def member_inventory(shape: dict[str, object]) -> list[tuple[str, ...]]:
    return [
        (
            name,
            value.get("location", "body"),
            value.get("locationName", name),
            value["shape"],
        )
        for name, value in shape["members"].items()
    ]


def verify_model(model: dict[str, object]) -> None:
    operation = model["operations"]["CompleteMultipartUpload"]
    shapes = model["shapes"]
    assert operation["http"] == {
        "method": "POST",
        "requestUri": "/{Bucket}/{Key+}",
    }
    assert operation["input"] == {"shape": "CompleteMultipartUploadRequest"}
    assert operation["output"] == {"shape": "CompleteMultipartUploadOutput"}
    assert "errors" not in operation
    request = shapes["CompleteMultipartUploadRequest"]
    assert request["required"] == ["Bucket", "Key", "UploadId"]
    assert member_inventory(request) == [
        ("Bucket", "uri", "Bucket", "BucketName"),
        ("Key", "uri", "Key", "ObjectKey"),
        (
            "MultipartUpload",
            "body",
            "CompleteMultipartUpload",
            "CompletedMultipartUpload",
        ),
        ("UploadId", "querystring", "uploadId", "MultipartUploadId"),
        ("ChecksumCRC32", "header", "x-amz-checksum-crc32", "ChecksumCRC32"),
        (
            "ChecksumCRC32C",
            "header",
            "x-amz-checksum-crc32c",
            "ChecksumCRC32C",
        ),
        (
            "ChecksumCRC64NVME",
            "header",
            "x-amz-checksum-crc64nvme",
            "ChecksumCRC64NVME",
        ),
        ("ChecksumSHA1", "header", "x-amz-checksum-sha1", "ChecksumSHA1"),
        (
            "ChecksumSHA256",
            "header",
            "x-amz-checksum-sha256",
            "ChecksumSHA256",
        ),
        (
            "ChecksumSHA512",
            "header",
            "x-amz-checksum-sha512",
            "ChecksumSHA512",
        ),
        ("ChecksumMD5", "header", "x-amz-checksum-md5", "ChecksumMD5"),
        (
            "ChecksumXXHASH64",
            "header",
            "x-amz-checksum-xxhash64",
            "ChecksumXXHASH64",
        ),
        (
            "ChecksumXXHASH3",
            "header",
            "x-amz-checksum-xxhash3",
            "ChecksumXXHASH3",
        ),
        (
            "ChecksumXXHASH128",
            "header",
            "x-amz-checksum-xxhash128",
            "ChecksumXXHASH128",
        ),
        ("ChecksumType", "header", "x-amz-checksum-type", "ChecksumType"),
        ("MpuObjectSize", "header", "x-amz-mp-object-size", "MpuObjectSize"),
        ("RequestPayer", "header", "x-amz-request-payer", "RequestPayer"),
        (
            "ExpectedBucketOwner",
            "header",
            "x-amz-expected-bucket-owner",
            "AccountId",
        ),
        ("IfMatch", "header", "If-Match", "IfMatch"),
        ("IfNoneMatch", "header", "If-None-Match", "IfNoneMatch"),
        (
            "SSECustomerAlgorithm",
            "header",
            "x-amz-server-side-encryption-customer-algorithm",
            "SSECustomerAlgorithm",
        ),
        (
            "SSECustomerKey",
            "header",
            "x-amz-server-side-encryption-customer-key",
            "SSECustomerKey",
        ),
        (
            "SSECustomerKeyMD5",
            "header",
            "x-amz-server-side-encryption-customer-key-MD5",
            "SSECustomerKeyMD5",
        ),
    ]
    output = shapes["CompleteMultipartUploadOutput"]
    assert member_inventory(output) == [
        ("Location", "body", "Location", "Location"),
        ("Bucket", "body", "Bucket", "BucketName"),
        ("Key", "body", "Key", "ObjectKey"),
        ("Expiration", "header", "x-amz-expiration", "Expiration"),
        ("ETag", "body", "ETag", "ETag"),
        ("ChecksumCRC32", "body", "ChecksumCRC32", "ChecksumCRC32"),
        ("ChecksumCRC32C", "body", "ChecksumCRC32C", "ChecksumCRC32C"),
        (
            "ChecksumCRC64NVME",
            "body",
            "ChecksumCRC64NVME",
            "ChecksumCRC64NVME",
        ),
        ("ChecksumSHA1", "body", "ChecksumSHA1", "ChecksumSHA1"),
        ("ChecksumSHA256", "body", "ChecksumSHA256", "ChecksumSHA256"),
        ("ChecksumSHA512", "body", "ChecksumSHA512", "ChecksumSHA512"),
        ("ChecksumMD5", "body", "ChecksumMD5", "ChecksumMD5"),
        ("ChecksumXXHASH64", "body", "ChecksumXXHASH64", "ChecksumXXHASH64"),
        ("ChecksumXXHASH3", "body", "ChecksumXXHASH3", "ChecksumXXHASH3"),
        (
            "ChecksumXXHASH128",
            "body",
            "ChecksumXXHASH128",
            "ChecksumXXHASH128",
        ),
        ("ChecksumType", "body", "ChecksumType", "ChecksumType"),
        (
            "ServerSideEncryption",
            "header",
            "x-amz-server-side-encryption",
            "ServerSideEncryption",
        ),
        ("VersionId", "header", "x-amz-version-id", "ObjectVersionId"),
        (
            "SSEKMSKeyId",
            "header",
            "x-amz-server-side-encryption-aws-kms-key-id",
            "SSEKMSKeyId",
        ),
        (
            "BucketKeyEnabled",
            "header",
            "x-amz-server-side-encryption-bucket-key-enabled",
            "BucketKeyEnabled",
        ),
        (
            "RequestCharged",
            "header",
            "x-amz-request-charged",
            "RequestCharged",
        ),
    ]


def operation_entry(data: dict[str, object]) -> dict[str, object]:
    matches = [
        item
        for item in data["operation"]
        if item["name"] == "CompleteMultipartUpload"
    ]
    assert len(matches) == 1, "CompleteMultipartUpload registry is not unique"
    return matches[0]


def verify_registry() -> None:
    data = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    assert data["model_sha256"] == MODEL_SHA256
    entry = operation_entry(data)
    expected_fields = {
        "name": "CompleteMultipartUpload",
        "tier": "core",
        "provider": "transfers",
        "family": "rest_xml_mutation",
        "public_provider": "Flyology.Object_Storage.Client.Transfers",
        "codec": "strict_rest_xml_request_and_bounded_response",
        "public_name": "Complete_Multipart_Upload",
        "absence": (
            "no dedicated absence variant; NoSuchBucket, NoSuchKey, and "
            "NoSuchUpload are structured typed rejections but remain "
            "publication-unknown after admission"
        ),
        "errors": [
            "authentication",
            "authorization",
            "not_found",
            "invalid_request",
            "unavailable_or_retryable",
            "corrupt_or_invalid_response",
        ],
        "certainty": (
            "only a complete validated 200 success document reports "
            "Multipart_Completed; definite non-admission reports "
            "Definitely_Not_Completed, pre-admission cancellation reports "
            "Completion_Cancelled_Before_Admission, and every complete "
            "rejection, embedded HTTP-200 S3 error, or possible or incomplete "
            "admission reports Completion_Outcome_Unknown; no automatic replay"
        ),
        "reconciliation": (
            "generation-bound HeadObject or whole Get for the exact bucket "
            "and key plus read-only ListParts for the exact upload identifier "
            "before caller-selected retry, re-initiation, or abort"
        ),
        "decision_status": "reviewed",
        "qualification": "complete_multipart_upload",
        "human_decisions_resolved": True,
        "implementation_mode": "handwritten",
        "generator_eligible": False,
        "ada_symbols": [
            "Prepare_Complete_Multipart_Upload",
            "Decode_Complete_Multipart_Complete_Response",
            "Execute_Complete_Multipart_Upload",
            "Complete_Multipart_Operation",
            "Complete_Multipart_Upload",
            "Finish",
        ],
    }
    for key, value in expected_fields.items():
        assert entry[key] == value, f"CompleteMultipartUpload {key} changed"
    assert entry["coverage"] == {
        "backend": "covered",
        "client": "covered",
        "server": "covered",
        "corpus": "covered",
    }
    assert entry["provenance"] == {
        "backend": "handwritten",
        "client": "handwritten",
        "server": "handwritten",
        "tests": "handwritten",
    }
    assert entry["exclusions"] == [
        (
            "server compatibility is limited to authenticated path-style "
            "general-purpose bucket requests; directory-bucket, access-point, "
            "and Outposts routing are not claimed"
        ),
        (
            "Requester Pays and server-side encryption including SSE-C remain "
            "explicit typed server capability exclusions"
        ),
        (
            "trailer manifests, inner aws-chunked framing, and HTTP/2 or "
            "HTTP/3 server qualification are outside the profile"
        ),
        "completion or abort cannot roll back an already-published object",
    ]
    expected_lane = [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-complete-multipart-upload-preparation.py",
        ],
        ["./tools/verify-composable-client-fixtures.sh"],
        ["./tools/test-composable-client-fixtures-verifier.sh"],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
        [
            "./tools/build-api-docs.sh",
            "/private/tmp/fos-complete-multipart-upload-gnatdoc",
        ],
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    assert data["qualification"]["complete_multipart_upload"] == expected_lane
    expected_evidence = {
        "backend": [
            "tests/src/object_storage_test_cases.adb",
            "sqlite/tests/src/flyology_object_storage_sqlite_tests.adb",
        ],
        "client": [
            "src/flyology-object_storage-client-low_level.ads",
            "src/flyology-object_storage-client-low_level.adb",
            "src/flyology-object_storage-client-transfers.ads",
            "src/flyology-object_storage-client-transfers.adb",
            "tests/src/flyology-object_storage-client-transfers-testing.adb",
            "tests/corpora/composable-client/complete-multipart-certainty.tsv",
            "tools/verify-composable-client-fixtures.sh",
            "tools/test-composable-client-fixtures-verifier.sh",
            "tests/src/s3_http_socket_corpus.adb",
        ],
        "server": [
            "src/flyology-object_storage-server-s3_applications.adb",
            "tests/src/s3_server_application_corpus.adb",
            "tests/src/s3_http_socket_corpus.adb",
        ],
        "corpus": [
            "tests/src/flyology-object_storage-client-transfers-testing.adb",
            "tests/corpora/composable-client/complete-multipart-certainty.tsv",
            "tools/verify-composable-client-fixtures.sh",
            "tools/test-composable-client-fixtures-verifier.sh",
            "tests/src/s3_http_socket_corpus.adb",
            "tests/src/s3_implementation_corpus.adb",
            "tests/src/s3_server_application_corpus.adb",
            "tests/scripts/test-minio.sh",
            "tests/scripts/test-rustfs.sh",
            "tests/scripts/test-seaweedfs.sh",
        ],
    }
    assert entry["evidence"] == expected_evidence
    expected_entry = {
        **expected_fields,
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
        "exclusions": [
            (
                "server compatibility is limited to authenticated path-style "
                "general-purpose bucket requests; directory-bucket, "
                "access-point, and Outposts routing are not claimed"
            ),
            (
                "Requester Pays and server-side encryption including SSE-C "
                "remain explicit typed server capability exclusions"
            ),
            (
                "trailer manifests, inner aws-chunked framing, and HTTP/2 or "
                "HTTP/3 server qualification are outside the profile"
            ),
            (
                "completion or abort cannot roll back an already-published "
                "object"
            ),
        ],
        "evidence": expected_evidence,
    }
    assert entry == expected_entry, (
        "CompleteMultipartUpload registry row changed"
    )
    for paths in expected_evidence.values():
        for path in paths:
            assert_regular(ROOT / path)


def verify_certainty() -> None:
    payload = CERTAINTY.read_bytes()
    assert hashlib.sha256(payload).hexdigest() == CERTAINTY_SHA256
    lines = payload.decode("utf-8").splitlines()
    assert lines[0].split("\t") == [
        "http_result", "admission", "status", "s3_code", "publication",
        "failure_reason", "reconcile", "note",
    ]
    assert len(lines) == 47, "CompleteMultipartUpload certainty rows changed"
    assert all(len(line.split("\t")) == 8 for line in lines[1:])
    rows = [tuple(line.split("\t")) for line in lines[1:]]
    assert rows == EXPECTED_CERTAINTY_ROWS, (
        "CompleteMultipartUpload ordered certainty semantics changed"
    )


def verify_sources() -> None:
    low_spec = LOW_SPEC.read_text(encoding="utf-8")
    low_body = LOW_BODY.read_text(encoding="utf-8")
    transfers_spec = TRANSFERS_SPEC.read_text(encoding="utf-8")
    transfers_body = TRANSFERS_BODY.read_text(encoding="utf-8")
    testing = TESTING.read_text(encoding="utf-8")
    socket = SOCKET.read_text(encoding="utf-8")
    server = SERVER.read_text(encoding="utf-8")
    server_test = SERVER_TEST.read_text(encoding="utf-8")
    backend = BACKEND.read_text(encoding="utf-8")
    sqlite = SQLITE.read_text(encoding="utf-8")
    qualification = QUALIFICATION.read_text(encoding="utf-8")

    low_region = region(
        low_spec,
        "type Complete_Multipart_Parameters is record",
        "type Abort_Multipart_Parameters is record",
        "CompleteMultipartUpload Low_Level spec",
    )
    require_ordered(
        low_region,
        [
            "type Complete_Multipart_Parameters is record",
            "type Complete_Multipart_Result is record",
            "type Complete_Multipart_Outcome_Kind is",
            "function Decode_Complete_Multipart_Complete_Response",
            "function Execute_Complete_Multipart_Upload",
        ],
        "CompleteMultipartUpload Low_Level spec",
    )
    assert low_region.count("function Prepare_Complete_Multipart_Upload") == 2
    low_body_region = region(
        low_body,
        "function Prepare_Complete_Multipart_Upload\n     (Origin     :",
        "procedure Validate_Complete_Multipart_Result",
        "CompleteMultipartUpload Low_Level body",
    )
    require_ordered(
        low_body_region,
        [
            "S3.Multipart.Serialize_Complete_Request",
            "return Result : Prepared_Request",
            "Result.Operation := Complete_Multipart_Operation",
            "Result.Owned_Request_Payload := US.To_Unbounded_String (Payload)",
            'Flyology.HTTP.Client.Set_Body (Result.Message, "")',
        ],
        "CompleteMultipartUpload owned request",
    )
    public_region = region(
        transfers_spec,
        "type Multipart_Completion_Disposition is",
        "type Multipart_Abort_Disposition is",
        "CompleteMultipartUpload public API",
    )
    require_ordered(
        public_region,
        [
            "type Multipart_Completion_Disposition is",
            "type Multipart_Completion_Result\n     (Kind",
            "type Complete_Multipart_Operation",
            "procedure Complete_Multipart_Upload",
            "function Complete_Multipart_Upload",
            "procedure Finish",
        ],
        "CompleteMultipartUpload public API",
    )
    body_region = region(
        transfers_body,
        "function Normalize_Complete_Multipart_Response",
        "function Normalize_Abort_Multipart_Response",
        "CompleteMultipartUpload composable body",
    )
    require_ordered(
        body_region,
        [
            "function Normalize_Complete_Multipart_Response",
            "procedure Complete_Multipart_Child",
            "overriding procedure Request_Cancellation",
            "overriding procedure Finalize",
            "procedure Start_Complete_Multipart_Upload",
            '"CompleteMultipartUpload restart changed a retained owner"',
            (
                "Operation.Prepared := "
                "Low_Level.Prepare_Complete_Multipart_Upload"
            ),
            "function Complete_Multipart_Upload",
            (
                "Operations.Consume (Operation);\n"
                "      Low.Clear_Prepared_Request (Operation.Prepared);"
            ),
        ],
        "CompleteMultipartUpload ownership lifecycle",
    )
    assert "Check_Complete_Multipart_Certainty_Corpus" in testing

    cancellation_inventory = (
        "type Cancellation_Exchange is\n"
        "     (List_Objects_V2_Cancellation,\n"
        "      Put_Object_Cancellation,\n"
        "      Delete_Object_Cancellation,\n"
        "      Complete_Multipart_Cancellation,\n"
        "      Abort_Multipart_Cancellation,\n"
        "      Copy_Object_Cancellation,\n"
        "      Create_Bucket_Cancellation,\n"
        "      Delete_Bucket_Cancellation,\n"
        "      Create_Multipart_Cancellation,\n"
        "      Get_Bucket_Location_Cancellation,\n"
        "      Get_Bucket_Versioning_Cancellation,\n"
        "      Put_Bucket_Versioning_Cancellation);"
    )
    require_once(socket, cancellation_inventory, "cancellation inventory")
    cancel_server_call = (
        'Serve\n'
        '           ("", "POST",\n'
        '            "/example-bucket/complete-cancel?" &\n'
        '              "uploadId=complete-cancel-id",\n'
        '            "<CompleteMultipartUpload",\n'
        '            Await_Cancellation => True,\n'
        '            Cancellation_Kind => Complete_Multipart_Cancellation,\n'
        '            Cancellation_Round => Round);'
    )
    restart_server_call = (
        'Serve\n'
        '           (HTTP_Response ("200 OK", Complete_Restart_XML), '
        '"POST",\n'
        '            "/example-bucket/complete-restart?" &\n'
        '              "uploadId=complete-restart-id",\n'
        '            "<CompleteMultipartUpload");'
    )
    cancel_server_position = require_once(
        socket,
        cancel_server_call,
        "CompleteMultipartUpload cancellation server call",
    )
    restart_server_position = require_once(
        socket,
        restart_server_call,
        "CompleteMultipartUpload restart server call",
    )
    assert cancel_server_position < restart_server_position, (
        "CompleteMultipartUpload server exchange order changed"
    )
    server_region = region(
        socket,
        '"/example-bucket/complete-cancel?" &\n'
        '              "uploadId=complete-cancel-id"',
        '"/example-bucket/complete-restart?" &\n'
        '              "uploadId=complete-restart-id"',
        "CompleteMultipartUpload cancellation server",
    )
    require_ordered(
        server_region,
        [
            '"<CompleteMultipartUpload"',
            "Await_Cancellation => True",
            "Cancellation_Kind => Complete_Multipart_Cancellation",
            "Cancellation_Round => Round",
        ],
        "CompleteMultipartUpload cancellation server",
    )
    client_region = region(
        socket,
        "--  Five slots are the completion parent, HTTP exchange,",
        '"same-operation CompleteMultipartUpload restart " &',
        "CompleteMultipartUpload cancellation client",
    )
    cancel_result_check = (
        "if Cancel_Result.Kind /=\n"
        "                       Complete_Multipart_Exchange_Failed\n"
        "                       or else Cancel_Result.Disposition /=\n"
        "                         Completion_Outcome_Unknown\n"
        "                       or else Cancel_Result.Failure /= "
        "Client_API.Cancelled\n"
        "                       or else Cancel_Result.HTTP_Result /=\n"
        "                         HTTP_Client.Cancelled\n"
        "                       or else Cancel_Result.Admission /=\n"
        "                         HTTP_Client.Possibly_Admitted"
    )
    drain_finish = (
        "if not Operations.Is_Terminal (Drain_Ready) then\n"
        "                        raise Program_Error with\n"
        "                          \"CompleteMultipartUpload drain was not "
        "\" &\n"
        "                          \"acknowledged\";\n"
        "                     end if;\n"
        "                     Flyology.IO.Finish (Drain_Ready);"
    )
    restart_result_check = (
        "if Cancel_Result.Kind /=\n"
        "                       Complete_Multipart_Response_Available\n"
        "                       or else Cancel_Result.Disposition /=\n"
        "                         Multipart_Completed\n"
        "                       or else Cancel_Result.Failure /= No_Failure\n"
        "                       or else Cancel_Result.Admission /=\n"
        "                         HTTP_Client.Response_Observed\n"
        "                       or else Cancel_Result.Response.Kind /=\n"
        "                         Low_Level.Completed\n"
        "                       or else US.To_String\n"
        "                         "
        "(Cancel_Result.Response.Result.Entity_Tag) /=\n"
        "                           \"\"\"complete-restarted\"\"\""
    )
    require_once(
        client_region,
        cancel_result_check,
        "CompleteMultipartUpload admitted cancellation result",
    )
    require_once(
        client_region,
        drain_finish,
        "CompleteMultipartUpload drain acknowledgement",
    )
    require_once(
        client_region,
        restart_result_check,
        "CompleteMultipartUpload restart result",
    )
    require_ordered(
        client_region,
        [
            "Complete_Admission_Native.Wait_Source",
            "Complete_Drain_Native.Wait_Source",
            "Complete_Admission_Lightweight.Wait_Source",
            "Complete_Drain_Lightweight.Wait_Source",
            "Operations.Wait_Some (Cancel_Set, Completed_Batch)",
            (
                "Operations.Cancel (Cancel_Operation);\n"
                "                     Operations.Wait_All (Cancel_Set);\n"
                "                     Finish (Cancel_Operation, "
                "Cancel_Result);"
            ),
            "HTTP_Client.Possibly_Admitted",
            "Operations.Is_Terminal (Drain_Ready)",
            "Flyology.IO.Finish (Drain_Ready)",
            '"complete-restart"',
            '"complete-restart-id"',
            (
                "Operation => Cancel_Operation);\n"
                "                     Operations.Wait_All (Cancel_Set);\n"
                "                     Finish (Cancel_Operation, "
                "Cancel_Result);"
            ),
            "Multipart_Completed",
        ],
        "CompleteMultipartUpload cancellation client",
    )
    for text, marker in [
        (server, "Complete_Multipart_Upload"),
        (server_test, "CompleteMultipartUpload"),
        (backend, "Complete_Multipart_Upload"),
        (sqlite, "Complete_Multipart_Upload"),
    ]:
        assert marker in text, (
            f"missing CompleteMultipartUpload evidence: {marker}"
        )
    for marker in [
        "Only a complete validated successful response reports",
        "caller reconciles the destination object and exact upload",
        "Native and\nlightweight socket tests cover success",
        "cancel",
        "drain",
    ]:
        assert marker in qualification, (
            f"qualification prose missing: {marker}"
        )


def main() -> None:
    for path in [
        REGISTRY, CERTAINTY, LOW_SPEC, LOW_BODY, TRANSFERS_SPEC,
        TRANSFERS_BODY, TESTING, SOCKET, SERVER, SERVER_TEST, BACKEND,
        SQLITE, QUALIFICATION,
    ]:
        assert_regular(path)
    verify_model(load_model())
    verify_registry()
    verify_certainty()
    verify_sources()
    print("CompleteMultipartUpload preparation evidence: OK")


if __name__ == "__main__":
    main()
