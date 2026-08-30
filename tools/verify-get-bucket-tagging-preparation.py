#!/usr/bin/env python3
"""Fail-closed evidence for reviewed GetBucketTagging qualification."""

from __future__ import annotations

import copy
import hashlib
import json
import os
import sys
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODEL_SHA256 = (
    "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
)
REGISTRY = ROOT / "coverage" / "s3-operations.toml"
LOW_SPEC = ROOT / "src" / "flyology-object_storage-client-low_level.ads"
LOW_BODY = ROOT / "src" / "flyology-object_storage-client-low_level.adb"
BUCKETS_SPEC = ROOT / "src" / "flyology-object_storage-client-buckets.ads"
BUCKETS_BODY = ROOT / "src" / "flyology-object_storage-client-buckets.adb"
TESTING = (
    ROOT / "tests" / "src" /
    "flyology-object_storage-client-buckets-testing.adb"
)
DIRECT = ROOT / "tests" / "src" / "object_storage_test_cases.adb"
SOCKET = ROOT / "tests" / "src" / "s3_http_socket_corpus.adb"
SERVER = ROOT / "src" / "flyology-object_storage-server-s3_applications.adb"
SERVER_TEST = ROOT / "tests" / "src" / "s3_server_application_corpus.adb"
QUALIFICATION = ROOT / "docs" / "qualification" / "bucket-tagging.md"


def regular(path: Path) -> None:
    assert path.is_file(), f"missing evidence path: {path}"
    assert not path.is_symlink(), f"symlink evidence path: {path}"


def once(text: str, marker: str, label: str) -> int:
    count = text.count(marker)
    assert count == 1, f"{label}: expected once, found {count}: {marker}"
    return text.index(marker)


def region(text: str, start: str, end: str, label: str) -> str:
    start_at = once(text, start, label)
    end_at = text.find(end, start_at + len(start))
    assert end_at >= 0, f"{label}: missing end: {end}"
    return text[start_at:end_at]


def ordered(text: str, markers: list[str], label: str) -> None:
    cursor = 0
    for marker in markers:
        position = text.find(marker, cursor)
        assert position >= 0, f"{label}: missing ordered marker: {marker}"
        cursor = position + len(marker)


def exact_ordered(text: str, markers: list[str], label: str) -> None:
    ordered(text, markers, label)
    for marker in markers:
        assert text.count(marker) == 1, (
            f"{label}: marker count differs: {marker}"
        )


def load_model() -> dict[str, object]:
    name = os.environ.get("FLYOLOGY_S3_SERVICE_MODEL", "")
    assert name, "FLYOLOGY_S3_SERVICE_MODEL is required"
    path = Path(name)
    regular(path)
    assert hashlib.sha256(path.read_bytes()).hexdigest() == MODEL_SHA256
    return json.loads(path.read_text(encoding="utf-8"))


def verify_model(model: dict[str, object]) -> None:
    operation = model["operations"]["GetBucketTagging"]
    assert operation["http"] == {
        "method": "GET",
        "requestUri": "/{Bucket}?tagging",
    }
    assert operation["input"] == {"shape": "GetBucketTaggingRequest"}
    assert operation["output"] == {"shape": "GetBucketTaggingOutput"}
    request = model["shapes"]["GetBucketTaggingRequest"]
    assert request["required"] == ["Bucket"]
    assert list(request["members"]) == ["Bucket", "ExpectedBucketOwner"]
    assert request["members"]["Bucket"]["location"] == "uri"
    owner = request["members"]["ExpectedBucketOwner"]
    assert owner["location"] == "header"
    assert owner["locationName"] == "x-amz-expected-bucket-owner"
    output = model["shapes"]["GetBucketTaggingOutput"]
    assert output["required"] == ["TagSet"]
    assert list(output["members"]) == ["TagSet"]
    assert output["members"]["TagSet"]["shape"] == "TagSet"
    assert model["shapes"]["TagSet"]["type"] == "list"
    assert model["shapes"]["TagSet"]["member"]["shape"] == "Tag"
    assert model["shapes"]["Tag"]["required"] == ["Key", "Value"]


def operation_entry(data: dict[str, object]) -> dict[str, object]:
    matches = [
        item for item in data["operation"]
        if item["name"] == "GetBucketTagging"
    ]
    assert len(matches) == 1, "GetBucketTagging entry is not unique"
    return matches[0]


def verify_registry(data: dict[str, object] | None = None) -> None:
    if data is None:
        data = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    entry = operation_entry(data)
    expected = {
        "tier": "core",
        "provider": "buckets",
        "family": "bounded_rest_xml_read",
        "public_provider": "Flyology.Object_Storage.Client.Buckets",
        "codec": "rest_xml_and_headers",
        "public_name": "Get_Tags",
        "errors": [
            "authentication",
            "authorization",
            "not_found",
            "invalid_request",
            "unavailable_or_retryable",
            "corrupt_or_invalid_response",
        ],
        "certainty": "read_only",
        "reconciliation": "not_applicable",
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
        "decision_status": "reviewed",
        "qualification": "get_bucket_tagging",
        "ada_symbols": [
            "Prepare_Get_Bucket_Tagging",
            "Decode_Get_Bucket_Tagging_Response",
            "Execute_Get_Bucket_Tagging",
            "Get_Bucket_Tagging_Operation",
            "Get_Tags",
            "Finish",
        ],
    }
    for key, value in expected.items():
        assert entry[key] == value, f"GetBucketTagging changed: {key}"
    assert entry["absence"] == (
        "exact 404 NoSuchTagSet maps to Not_Found; a 200 response returns "
        "the complete current bucket tag snapshot and exact NoSuchBucket "
        "remains a bounded structured typed rejection"
    )
    assert entry["exclusions"] == [
        (
            "directory buckets, as specified by the pinned operation "
            "documentation"
        ),
        (
            "automatic endpoint discovery or rewriting, including S3 Express "
            "control-endpoint selection, is not claimed; caller-supplied "
            "Origin remains authoritative"
        ),
        "cross-region redirect following is not qualified",
        (
            "the read reports the current bucket tag snapshot but does not "
            "authorize or perform a tag mutation"
        ),
    ]
    assert entry["evidence"]["backend"] == [
        "tests/src/object_storage_test_cases.adb"
    ]
    assert entry["evidence"]["client"] == [
        "src/flyology-object_storage-client-low_level.ads",
        "src/flyology-object_storage-client-low_level.adb",
        "src/flyology-object_storage-client-buckets.ads",
        "src/flyology-object_storage-client-buckets.adb",
        "tests/src/flyology-object_storage-client-buckets-testing.adb",
        "tests/src/object_storage_test_cases.adb",
        "tests/src/s3_http_socket_corpus.adb",
    ]
    assert entry["evidence"]["server"] == [
        "src/flyology-object_storage-server-s3_applications.adb",
        "tests/src/s3_server_application_corpus.adb",
        "tests/src/s3_http_socket_corpus.adb",
    ]
    assert entry["evidence"]["corpus"] == [
        "tests/src/flyology-object_storage-client-buckets-testing.adb",
        "tests/src/object_storage_test_cases.adb",
        "tests/src/s3_http_socket_corpus.adb",
        "tests/src/s3_server_application_corpus.adb",
    ]
    assert data["qualification"]["get_bucket_tagging"] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-get-bucket-tagging-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
        [
            "./tools/build-api-docs.sh",
            "/private/tmp/fos-get-bucket-tagging-gnatdoc",
        ],
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]


def verify_registry_negatives(data: dict[str, object]) -> None:
    for label, key, value in (
        ("missing public name", "public_name", None),
        ("wrong public name", "public_name", "Get_Bucket_Tags"),
        ("wrong certainty", "certainty", "mutation_unknown"),
        ("wrong qualification", "qualification", "get_bucket_versioning"),
    ):
        candidate = copy.deepcopy(data)
        entry = operation_entry(candidate)
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        try:
            verify_registry(candidate)
        except (AssertionError, KeyError):
            continue
        raise AssertionError(f"{label} was accepted")


def verify_sources() -> None:
    paths = (
        LOW_SPEC, LOW_BODY, BUCKETS_SPEC, BUCKETS_BODY, TESTING, DIRECT,
        SOCKET, SERVER, SERVER_TEST, QUALIFICATION,
    )
    for path in paths:
        regular(path)
    low_spec = LOW_SPEC.read_text(encoding="utf-8")
    low_body = LOW_BODY.read_text(encoding="utf-8")
    buckets_spec = BUCKETS_SPEC.read_text(encoding="utf-8")
    buckets_body = BUCKETS_BODY.read_text(encoding="utf-8")
    testing = TESTING.read_text(encoding="utf-8")
    direct = DIRECT.read_text(encoding="utf-8")
    socket = SOCKET.read_text(encoding="utf-8")
    server = SERVER.read_text(encoding="utf-8")
    server_test = SERVER_TEST.read_text(encoding="utf-8")
    qualification = QUALIFICATION.read_text(encoding="utf-8")
    qualification_normalized = " ".join(qualification.split())

    low_region = region(
        low_spec,
        "--  Complete modeled GetBucketTagging request controls.",
        "   type Delete_Bucket_Tagging_Parameters is record",
        "Low_Level public contract",
    )
    exact_ordered(
        low_region,
        [
            "type Get_Bucket_Tagging_Parameters is record",
            "function Prepare_Get_Bucket_Tagging",
            "type Get_Bucket_Tagging_Result is record",
            "type Get_Bucket_Tagging_Outcome_Kind is",
            "type Get_Bucket_Tagging_Outcome\n     (",
            "function Decode_Get_Bucket_Tagging_Response",
            "function Execute_Get_Bucket_Tagging",
        ],
        "Low_Level public contract",
    )
    execute = region(
        low_body,
        "   function Execute_Get_Bucket_Tagging",
        "   function Prepare_Delete_Bucket_Tagging",
        "synchronous response ceiling",
    )
    exact_ordered(
        execute,
        [
            "Flyology.HTTP.Client.Read_All",
            "Natural'Min",
            "Limits.Maximum_Document_Bytes",
            "S3.Tagging.Maximum_Bucket_Document_Bytes",
            "Decode_Get_Bucket_Tagging_Response",
        ],
        "synchronous response ceiling",
    )
    provider = region(
        buckets_body,
        "   function Normalize_Get_Bucket_Tagging_Response",
        "   function Normalize_Delete_Bucket_Tagging_Response",
        "composable provider",
    )
    exact_ordered(
        provider,
        [
            "function Get_Bucket_Tagging_Response_Limit",
            "Natural'Min",
            "Limits.Maximum_Document_Bytes",
            "Maximum_Bucket_Document_Bytes",
            "procedure Start_Get_Bucket_Tagging",
            "GetBucketTagging restart changed a retained owner",
            "Operation.Response_Limit := Get_Bucket_Tagging_Response_Limit",
            "function Get_Tags",
            "procedure Finish",
        ],
        "composable provider",
    )
    for marker in (
        "type Get_Bucket_Tagging_Operation",
        "procedure Get_Tags",
        "function Get_Tags",
        "procedure Finish",
        "type Get_Tags_Outcome_Kind",
        "type Get_Tags_Outcome",
    ):
        assert marker in buckets_spec, f"Buckets contract lacks {marker}"

    certainty = region(
        testing,
        "   procedure Check_Bucket_Tagging_Certainty_Corpus is",
        "   end Check_Bucket_Tagging_Certainty_Corpus;",
        "certainty corpus",
    )
    ordered(
        certainty,
        [
            "Caller_Lowered_Limits.Maximum_Document_Bytes := 8 * 1_024;",
            (
                "Caller_Raised_Limits.Maximum_Document_Bytes := "
                "2 * 1_024 * 1_024;"
            ),
            "Get_Bucket_Tagging_Response_Limit (Caller_Lowered_Limits)",
            "Get_Bucket_Tagging_Response_Limit (Caller_Raised_Limits)",
            "Maximum_Bucket_Document_Bytes",
            'Check_Get_Response (200, "", No_Failure);',
            'Check_Get_Response (403, "AccessDenied", Authorization_Failed);',
            'Check_Get_Response (404, "NoSuchTagSet", Not_Found);',
        ],
        "certainty corpus",
    )
    assert certainty.count("Maximum_Bucket_Document_Bytes") == 2

    codec = region(
        direct,
        "   procedure Check_Low_Level_Bucket_Lifecycle",
        "   procedure Check_Low_Level_Delete_Requests",
        "direct codec evidence",
    )
    ordered(
        codec,
        [
            "for Index in 1 .. 50 loop",
            "Maximum_Document_Bytes",
            '"GetBucketTagging large response fixture is not over 16 KiB"',
            "Decode_Get_Bucket_Tagging_Response",
            "Outcome.Result.Value.Length = 50",
        ],
        "direct codec evidence",
    )
    assert codec.count("for Index in 1 .. 50 loop") == 1
    assert codec.count(
        '"GetBucketTagging large response fixture is not over 16 KiB"'
    ) == 1
    assert codec.count("Outcome.Result.Value.Length = 50") == 1
    socket_region = region(
        socket,
        "Operation : Get_Bucket_Tagging_Operation :=",
        "Operation : Delete_Bucket_Tagging_Operation :=",
        "socket GetBucketTagging evidence",
    )
    ordered(
        socket_region,
        [
            "Get_Tags",
            "Operations.Wait_All (Set);",
            "Finish (Operation, Get_Result);",
            "HTTP_Client.Response_Observed",
            "Low_Level.Bucket_Tags_Found",
            '"scoped GetBucketTagging socket mismatch"',
            "Operation => Operation",
            '"scoped GetBucketTagging restart mismatch"',
        ],
        "socket GetBucketTagging evidence",
    )
    assert socket_region.count(
        '"scoped GetBucketTagging socket mismatch"'
    ) == 1
    assert socket_region.count(
        '"scoped GetBucketTagging restart mismatch"'
    ) == 1
    server_region = region(
        server,
        "            when Get_Bucket_Tagging =>",
        "            when Delete_Bucket_Tagging =>",
        "server route",
    )
    exact_ordered(
        server_region,
        [
            "when Get_Bucket_Tagging =>",
            "Check_Expected_Bucket_Owner",
            "Store.Get_Bucket_Tags",
            "Tagging.Serialize_Bucket (Value)",
        ],
        "server route",
    )
    for marker in (
        "GetBucketTagging ignored expected owner",
        "GetBucketTagging accepted non-modeled RequestPayer",
        "GetBucketTagging accepted a request body",
    ):
        assert marker in server_test, f"server evidence lacks {marker}"
    ordered(
        qualification_normalized,
        [
            "lower of the caller XML limit",
            "1 MiB bucket-document ceiling",
            "larger than 16 KiB",
            "removed exactly 39 candidate-owned warnings",
            "no global documentation qualification claim",
        ],
        "qualification prose",
    )


def main() -> int:
    model = load_model()
    verify_model(model)
    data = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    verify_registry(data)
    verify_registry_negatives(data)
    verify_sources()
    print(
        "GetBucketTagging preparation: exact request/tag graph, 1 MiB "
        "bounded response, read-only certainty, lifecycle, and docs match"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (
        AssertionError, KeyError, OSError, UnicodeError, ValueError
    ) as exc:
        print(f"GetBucketTagging verification failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
