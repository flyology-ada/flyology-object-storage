#!/usr/bin/env python3
"""Fail-closed evidence for reviewed ListObjects v1 qualification."""

from __future__ import annotations

import hashlib
import json
import os
import re
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODEL_SHA256 = (
    "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
)
INPUT_MEMBERS = [
    "Bucket",
    "Delimiter",
    "EncodingType",
    "Marker",
    "MaxKeys",
    "Prefix",
    "RequestPayer",
    "ExpectedBucketOwner",
    "OptionalObjectAttributes",
]
OUTPUT_MEMBERS = [
    "IsTruncated",
    "Marker",
    "NextMarker",
    "Contents",
    "Name",
    "Prefix",
    "Delimiter",
    "MaxKeys",
    "CommonPrefixes",
    "EncodingType",
    "RequestCharged",
]
ERRORS = [
    "authentication",
    "authorization",
    "not_found",
    "invalid_request",
    "unavailable_or_retryable",
    "corrupt_or_invalid_response",
]
ABSENCE = (
    "no dedicated absence variant; a well-formed bounded 404 NoSuchBucket "
    "response is a structured typed rejection"
)
EXCLUSIONS = [
    "directory-bucket, access-point, Object Lambda, and S3 on Outposts "
    "routing are not claimed",
    "FetchOwner is not a pinned ListObjects v1 request member",
    "the local server accepts RestoreStatus request syntax but supports no "
    "archival restore state and emits no RestoreStatus result",
    "the local server validates requester-pays syntax but makes no billing "
    "or x-amz-request-charged emission claim",
    "no object-version-history, automatic pagination, automatic retry, or "
    "cross-page snapshot-consistency claim",
    "the RustFS, SeaweedFS, and MinIO strict no-delimiter continuation "
    "subcase is excluded because those providers emit a non-modeled "
    "NextMarker; their basic ListObjects v1 path remains separately "
    "evidenced",
]
EVIDENCE = {
    "backend": [
        "tests/src/object_storage_test_cases.adb",
        "sqlite/tests/src/flyology_object_storage_sqlite_tests.adb",
    ],
    "client": [
        "src/flyology-object_storage-client-low_level.adb",
        "src/flyology-object_storage-client-objects.adb",
        "tests/src/s3_http_socket_corpus.adb",
    ],
    "server": [
        "tests/src/s3_server_application_corpus.adb",
        "tests/src/s3_http_socket_corpus.adb",
    ],
    "corpus": [
        "tests/src/s3_http_socket_corpus.adb",
        "tests/src/s3_implementation_corpus.adb",
        "tests/src/s3_server_application_corpus.adb",
        "tests/scripts/test-minio.sh",
        "tests/scripts/test-rustfs.sh",
        "tests/scripts/test-seaweedfs.sh",
    ],
}
SYMBOLS = [
    "Prepare_List_Objects",
    "Decode_List_Objects_Complete_Response",
    "Execute_List_Objects",
    "List_Objects_Operation",
    "List_V1_Page",
    "Finish",
]
EXPECTED_ENTRY = {
    "name": "ListObjects",
    "tier": "core",
    "provider": "objects",
    "family": "paginated_rest_xml_read",
    "public_provider": "Flyology.Object_Storage.Client.Objects",
    "codec": "paginated_rest_xml_and_singleton_headers",
    "public_name": "List_V1_Page",
    "absence": ABSENCE,
    "errors": ERRORS,
    "certainty": "read_only",
    "reconciliation": "not_applicable",
    "exclusions": EXCLUSIONS,
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
    "evidence": EVIDENCE,
    "decision_status": "reviewed",
    "qualification": "list_objects_v1",
    "ada_symbols": SYMBOLS,
}
EXPECTED_LANE = [
    [
        "uv",
        "run",
        "--python",
        "3.13",
        "--",
        "tools/verify-list-objects-v1-preparation.py",
    ],
    ["@tests", "alr", "-n", "build"],
    ["@tests", "./bin/s3_http_socket_corpus"],
    ["./tools/verify-coverage.sh"],
    [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-list-objects-v1-gnatdoc",
    ],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]


class EvidenceError(RuntimeError):
    """One reviewed ListObjects v1 invariant changed."""


def fail(message: str) -> None:
    raise EvidenceError(message)


def normalized(source: str) -> str:
    return re.sub(r"\s+", " ", source)


def require_order(source: str, fragments: list[str], label: str) -> None:
    value = normalized(source)
    position = 0
    for fragment in fragments:
        expected = normalized(fragment)
        next_position = value.find(expected, position)
        if next_position < 0:
            fail(f"{label}: missing or reordered fragment: {fragment!r}")
        position = next_position + len(expected)


def require_once(source: str, fragment: str, label: str) -> None:
    count = normalized(source).count(normalized(fragment))
    if count != 1:
        fail(f"{label}: fragment count is {count}: {fragment!r}")


def require_region(source: str, start: str, end: str, label: str) -> str:
    start_count = source.count(start)
    end_count = source.count(end)
    if start_count != 1 or end_count != 1:
        fail(
            f"{label}: boundary counts are {start_count} and {end_count}"
        )
    first = source.index(start)
    last = source.index(end, first + len(start))
    return source[first:last + len(end)]


def expect_failure(action, label: str) -> None:
    try:
        action()
    except EvidenceError:
        return
    fail(f"negative fixture was accepted: {label}")


def load_model() -> dict[str, object]:
    value = os.environ.get("FLYOLOGY_S3_SERVICE_MODEL")
    if not value:
        fail("FLYOLOGY_S3_SERVICE_MODEL is not set")
    path = Path(value)
    if not path.is_file() or path.is_symlink():
        fail("pinned model is not one regular non-symlink file")
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != MODEL_SHA256:
        fail("pinned model digest changed")
    return json.loads(data)


def verify_model(model: dict[str, object]) -> None:
    operations = model.get("operations")
    shapes = model.get("shapes")
    if not isinstance(operations, dict) or not isinstance(shapes, dict):
        fail("pinned model top-level inventory changed")
    operation = operations.get("ListObjects")
    if not isinstance(operation, dict):
        fail("pinned ListObjects operation is missing")
    http = operation.get("http")
    if not isinstance(http, dict) or http != {
        "method": "GET",
        "requestUri": "/{Bucket}",
    }:
        fail("pinned ListObjects HTTP contract changed")
    if operation.get("input") != {"shape": "ListObjectsRequest"}:
        fail("pinned ListObjects input binding changed")
    if operation.get("output") != {"shape": "ListObjectsOutput"}:
        fail("pinned ListObjects output binding changed")
    if operation.get("errors") != [{"shape": "NoSuchBucket"}]:
        fail("pinned ListObjects error inventory changed")
    request = shapes.get("ListObjectsRequest")
    response = shapes.get("ListObjectsOutput")
    if not isinstance(request, dict) or not isinstance(response, dict):
        fail("pinned ListObjects shapes are missing")
    if request.get("required") != ["Bucket"]:
        fail("pinned ListObjects required members changed")
    if list(request.get("members", {})) != INPUT_MEMBERS:
        fail("pinned ListObjects input member order changed")
    if list(response.get("members", {})) != OUTPUT_MEMBERS:
        fail("pinned ListObjects output member order changed")


def verify_registry() -> None:
    registry = tomllib.loads(
        (ROOT / "coverage" / "s3-operations.toml").read_text(
            encoding="utf-8"
        )
    )
    entries = [
        entry
        for entry in registry["operation"]
        if entry.get("name") == "ListObjects"
    ]
    if entries != [EXPECTED_ENTRY]:
        fail("reviewed ListObjects registry entry changed")
    if registry["qualification"].get("list_objects_v1") != EXPECTED_LANE:
        fail("reviewed ListObjects qualification lane changed")
    for paths in EVIDENCE.values():
        for value in paths:
            path = ROOT / value
            if not path.is_file() or path.is_symlink():
                fail(f"evidence path is not one regular file: {value}")


def verify_sources() -> None:
    low_spec = (ROOT / "src" /
                "flyology-object_storage-client-low_level.ads").read_text()
    low_body = (ROOT / "src" /
                "flyology-object_storage-client-low_level.adb").read_text()
    objects_spec = (ROOT / "src" /
                    "flyology-object_storage-client-objects.ads").read_text()
    objects_body = (ROOT / "src" /
                    "flyology-object_storage-client-objects.adb").read_text()
    socket = (ROOT / "tests" / "src" /
              "s3_http_socket_corpus.adb").read_text()
    backend = (ROOT / "tests" / "src" /
               "object_storage_test_cases.adb").read_text()
    sqlite = (ROOT / "sqlite" / "tests" / "src" /
              "flyology_object_storage_sqlite_tests.adb").read_text()
    server = (ROOT / "tests" / "src" /
              "s3_server_application_corpus.adb").read_text()
    implementation = (ROOT / "tests" / "src" /
                      "s3_implementation_corpus.adb").read_text()
    minio = (ROOT / "tests" / "scripts" / "test-minio.sh").read_text()
    rustfs = (ROOT / "tests" / "scripts" / "test-rustfs.sh").read_text()
    seaweedfs = (ROOT / "tests" / "scripts" /
                "test-seaweedfs.sh").read_text()
    qualification = (ROOT / "docs" / "qualification" /
                     "list-objects-v1.md").read_text()
    lifecycle = require_region(
        socket,
        "procedure Require_Normalized_List_Objects_Failure",
        '"same-object ListObjects restart mismatch";',
        "ListObjects client evidence",
    )
    provider_lifecycle = require_region(
        objects_body,
        "function Normalize_List_Objects_Response",
        "end Start_List_Objects;",
        "ListObjects provider lifecycle",
    )

    require_order(
        low_spec,
        [
            "function Prepare_List_Objects",
            "type List_Objects_Result is record",
            "type List_Objects_Outcome",
            "function Decode_List_Objects_Complete_Response",
            "function Execute_List_Objects",
            "procedure List_Objects",
            "List_Objects_Operation",
        ],
        "Low_Level declaration inventory",
    )
    require_order(
        low_body,
        [
            "Model.List_Objects_Operation",
            "Result.Operation := List_Objects_Operation",
            "if Prepared.Operation /= List_Objects_Operation then",
            "Decode_List_Objects_Complete_Response",
            "ListObjects response does not match prepared request",
        ],
        "Low_Level exact-operation and response binding",
    )
    require_order(
        objects_spec,
        [
            "type List_Objects_Result_Kind is",
            "type List_Objects_Result",
            "type List_Objects_Operation",
            "procedure List_V1_Page",
            "function List_V1_Page",
            "procedure Finish",
        ],
        "public composable inventory",
    )
    require_order(
        provider_lifecycle,
        [
            "function Normalize_List_Objects_Response",
            "Admission /= HTTP_Client.Response_Observed",
            "Corrupt_Or_Invalid_Response",
            "Value.Kind = Low_Level.Listed",
            "No_Failure",
            "Value.Status = 400",
            "Invalid_Request",
            "Authentication_Failed",
            "Authorization_Failed",
            "Not_Found",
            "Unavailable_Or_Retryable",
            "if Operation.HTTP /= Client or else "
            "Operation.Cancellation /= Token then",
            "ListObjects restart changed a retained owner",
        ],
        "provider normalization and ownership",
    )
    owner_guard = (
        "if Operation.HTTP /= Client or else "
        "Operation.Cancellation /= Token then"
    )
    require_once(provider_lifecycle, owner_guard, "provider owner guard")
    require_order(
        lifecycle,
        [
            "Require_Normalized_List_Objects_Failure",
            "Authentication_Failed, 401, \"InvalidAccessKeyId\"",
            "Authorization_Failed, 403, \"AccessDenied\"",
            "Not_Found, 404, \"NoSuchBucket\"",
            "Invalid_Request, 400, \"InvalidArgument\"",
            "Unavailable_Or_Retryable, 503, \"SlowDown\"",
            "Corrupt_Or_Invalid_Response, 400",
            "\"UnclassifiedListObjectsError\"",
            "List_V1_Admission_Native.Wait_Source",
            "List_V1_Drain_Native.Wait_Source",
            "List_V1_Admission_Lightweight.Wait_Source",
            "List_V1_Drain_Lightweight.Wait_Source",
            "Operations.Completion_Set (5)",
            "Operations.Wait_Some",
            "Operations.Cancel (Cancel_Operation)",
            "Operations.Wait_All (Cancel_Set)",
            "Finish (Cancel_Operation, Cancel_Result)",
            "admitted ListObjects cancellation mismatch",
            "ListObjects drain was not acknowledged",
            "Changed_HTTP'Access",
            "ListObjects restart changed a retained owner",
            "ListObjects accepted changed retained HTTP client",
            "Changed_Token'Access",
            "ListObjects restart changed a retained owner",
            "ListObjects accepted changed retained cancellation token",
            "same-object ListObjects restart mismatch",
        ],
        "ListObjects client evidence",
    )
    for fragment in [
        "Authentication_Failed, 401, \"InvalidAccessKeyId\"",
        "Authorization_Failed, 403, \"AccessDenied\"",
        "Not_Found, 404, \"NoSuchBucket\"",
        "Invalid_Request, 400, \"InvalidArgument\"",
        "Unavailable_Or_Retryable, 503, \"SlowDown\"",
        "\"UnclassifiedListObjectsError\"",
        "Operations.Cancel (Cancel_Operation)",
        "List_V1_Admission_Native.Wait_Source",
        "List_V1_Admission_Lightweight.Wait_Source",
        "List_V1_Drain_Native.Wait_Source",
        "List_V1_Drain_Lightweight.Wait_Source",
        "Changed_HTTP'Access",
        "Changed_Token'Access",
        "List_V1_Admission_Native.Request",
        "List_V1_Admission_Lightweight.Request",
        "List_V1_Drain_Native.Request",
        "List_V1_Drain_Lightweight.Request",
        "admitted ListObjects cancellation mismatch",
        "ListObjects drain was not acknowledged",
        "ListObjects accepted changed retained HTTP client",
        "ListObjects accepted changed retained cancellation token",
        "same-object ListObjects restart mismatch",
    ]:
        evidence = socket if ".Request" in fragment else lifecycle
        require_once(evidence, fragment, "ListObjects evidence")

    expect_failure(
        lambda: require_order(
            lifecycle.replace(
                "Operations.Cancel (Cancel_Operation);", "", 1
            ),
            [
                "Operations.Wait_Some",
                "Operations.Cancel (Cancel_Operation)",
                "Operations.Wait_All (Cancel_Set)",
            ],
            "missing cancellation",
        ),
        "missing owner cancellation",
    )
    expect_failure(
        lambda: require_once(
            lifecycle + "\nListObjects drain was not acknowledged\n",
            "ListObjects drain was not acknowledged",
            "duplicate drain evidence",
        ),
        "duplicate drain evidence",
    )
    expect_failure(
        lambda: require_once(
            provider_lifecycle.replace(
                "Operation.HTTP /= Client or else ", "", 1
            ),
            owner_guard,
            "missing retained HTTP owner",
        ),
        "missing retained HTTP owner",
    )
    expect_failure(
        lambda: require_once(
            provider_lifecycle.replace(
                "or else Operation.Cancellation /= Token", "", 1
            ),
            owner_guard,
            "missing retained cancellation owner",
        ),
        "missing retained cancellation owner",
    )

    evidence_checks = [
        (
            backend,
            [
                "ListObjects v1/v2 backend key setup",
                "Store.List_Objects",
                "ListObjects v1/v2 backend bounded-page property",
                "ListObjects v1/v2 mutation-safe exclusive continuation",
                "ListObjects v1/v2 multi-character delimiter projection",
                "ListObjects v1/v2 projected-prefix continuation",
            ],
            "backend listing evidence",
        ),
        (
            sqlite,
            [
                "SQLite ListObjects v1/v2 key setup failed",
                "Store.List_Objects",
                "SQLite ListObjects v1/v2 first page failed",
                "SQLite ListObjects v1/v2 mutation-safe continuation failed",
                "SQLite ListObjects v1/v2 continuation failed",
                "SQLite ListObjects v1/v2 delimiter listing failed",
                "SQLite ListObjects v1/v2 multi-delimiter projection failed",
                "SQLite ListObjects v1/v2 projected continuation failed",
            ],
            "SQLite listing evidence",
        ),
        (
            server,
            [
                "ListObjects v1 default response mismatch",
                "ListObjects v1 first marker page mismatch",
                "ListObjects v1 marker continuation mismatch",
                "ListObjects v1 delimiter next marker mismatch",
                "ListObjects v1 zero-sized page mismatch",
                "duplicate ListObjects v1 parameter was accepted",
                "ListObjects v1 absent bucket mismatch",
                "ListObjects v1 explicit-empty presence mismatch",
                "ListObjects v1 owner requester-payer behavior mismatch",
                "ListObjects v1 invalid requester payer was accepted",
                "ListObjects v1 matching expected owner was rejected",
                "ListObjects v1 mismatched expected owner was accepted",
                "ListObjects v1 nonarchival RestoreStatus behavior mismatch",
                "ListObjects v1 invalid optional attributes were accepted",
                "ListObjects v1 duplicate modeled header was accepted",
            ],
            "server ListObjects evidence",
        ),
        (
            implementation,
            [
                "FLYOLOGY_LIST_OBJECTS_V1_ORACLE_MODE",
                "rustfs-rc3-next-marker-without-delimiter",
                "seaweedfs-4.43-next-marker-without-delimiter",
                "minio-2025-next-marker-without-delimiter",
                "unknown ListObjects v1 oracle mode",
                "S3 implementation failed typed ListObjects v1",
                "S3 implementation failed high-level ListObjects v1",
                "S3 implementation failed ListObjects v1 first page",
                "S3 implementation failed ListObjects v1 continuation",
            ],
            "implementation ListObjects evidence",
        ),
        (
            qualification,
            [
                "# ListObjects v1 qualification evidence",
                "six modeled error-normalization classes",
                "explicit transport drain acknowledgement",
                "retained-owner substitution rejection",
                "uv run --python 3.13 -- tools/s3-operation.py qualify "
                "ListObjects",
            ],
            "qualification evidence",
        ),
    ]
    for source, fragments, label in evidence_checks:
        require_order(source, fragments, label)
        expect_failure(
            lambda source=source, fragments=fragments, label=label:
            require_order(
                source.replace(fragments[0], "", 1), fragments, label
            ),
            f"missing {label}",
        )

    for script, mode, label in [
        (minio, "minio-2025-next-marker-without-delimiter", "MinIO"),
        (rustfs, "rustfs-rc3-next-marker-without-delimiter", "RustFS"),
        (
            seaweedfs,
            "seaweedfs-4.43-next-marker-without-delimiter",
            "SeaweedFS",
        ),
    ]:
        require_order(
            script,
            ["FLYOLOGY_LIST_OBJECTS_V1_ORACLE_MODE", mode, "ListObjects v1"],
            f"{label} ListObjects evidence",
        )
        expect_failure(
            lambda script=script, mode=mode, label=label: require_order(
                script.replace(mode, "", 1),
                ["FLYOLOGY_LIST_OBJECTS_V1_ORACLE_MODE", mode],
                f"{label} ListObjects evidence",
            ),
            f"missing {label} ListObjects mode",
        )


def main() -> int:
    verify_model(load_model())
    verify_registry()
    verify_sources()
    print("ListObjects v1 preparation evidence: OK")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except EvidenceError as error:
        raise SystemExit(f"ListObjects v1 preparation failed: {error}")
    except (OSError, UnicodeError, json.JSONDecodeError,
            tomllib.TOMLDecodeError, KeyError, TypeError) as error:
        raise SystemExit(
            f"ListObjects v1 preparation failed: unreadable evidence: {error}"
        )
