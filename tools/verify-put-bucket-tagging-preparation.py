#!/usr/bin/env python3
"""Fail-closed evidence for reviewed PutBucketTagging qualification."""

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

CERTAINTY = (
    "only a complete validated 200 or 204 response reports "
    "Bucket_Tag_Mutation_Completed; an exact recognized non-mutating "
    "rejection or definite non-admission reports "
    "Bucket_Tag_Mutation_Definitely_Not_Applied; pre-admission cancellation "
    "reports Bucket_Tag_Mutation_Cancelled_Before_Admission; possible or "
    "incomplete admission, retryable responses, and malformed or oversized "
    "responses report Bucket_Tag_Mutation_Outcome_Unknown; no automatic "
    "replay"
)
RECONCILIATION = (
    "caller-selected Get_Tags may observe the current complete bucket tag "
    "set before a retry but does not prove that the lost mutation caused the "
    "observed state or upgrade mutation certainty; no automatic replay"
)


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


def collapsed(text: str) -> str:
    return " ".join(text.split())


def load_model() -> dict[str, object]:
    name = os.environ.get("FLYOLOGY_S3_SERVICE_MODEL", "")
    assert name, "FLYOLOGY_S3_SERVICE_MODEL is required"
    path = Path(name)
    regular(path)
    assert hashlib.sha256(path.read_bytes()).hexdigest() == MODEL_SHA256
    return json.loads(path.read_text(encoding="utf-8"))


def verify_model(model: dict[str, object]) -> None:
    operation = model["operations"]["PutBucketTagging"]
    assert operation["http"] == {
        "method": "PUT",
        "requestUri": "/{Bucket}?tagging",
    }
    assert operation["input"] == {"shape": "PutBucketTaggingRequest"}
    assert "output" not in operation
    assert operation["httpChecksum"] == {
        "requestAlgorithmMember": "ChecksumAlgorithm",
        "requestChecksumRequired": True,
    }
    request = model["shapes"]["PutBucketTaggingRequest"]
    assert request["required"] == ["Bucket", "Tagging"]
    assert list(request["members"]) == [
        "Bucket",
        "ContentMD5",
        "ChecksumAlgorithm",
        "Tagging",
        "ExpectedBucketOwner",
    ]
    assert request["payload"] == "Tagging"
    assert request["members"]["ContentMD5"]["locationName"] == "Content-MD5"
    assert request["members"]["ChecksumAlgorithm"]["locationName"] == (
        "x-amz-sdk-checksum-algorithm"
    )
    assert request["members"]["ExpectedBucketOwner"]["locationName"] == (
        "x-amz-expected-bucket-owner"
    )
    assert model["shapes"]["ChecksumAlgorithm"]["enum"] == [
        "CRC32", "CRC32C", "SHA1", "SHA256", "CRC64NVME", "SHA512",
        "MD5", "XXHASH64", "XXHASH3", "XXHASH128",
    ]


def operation_entry(data: dict[str, object]) -> dict[str, object]:
    matches = [
        item for item in data["operation"]
        if item["name"] == "PutBucketTagging"
    ]
    assert len(matches) == 1, "PutBucketTagging entry is not unique"
    return matches[0]


def verify_registry(data: dict[str, object] | None = None) -> None:
    if data is None:
        data = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    entry = operation_entry(data)
    expected = {
        "tier": "core",
        "provider": "buckets",
        "family": "rest_xml_mutation",
        "public_provider": "Flyology.Object_Storage.Client.Buckets",
        "codec": "rest_xml_and_headers",
        "public_name": "Put_Tags",
        "errors": [
            "authentication",
            "authorization",
            "not_found",
            "invalid_request",
            "unavailable_or_retryable",
            "corrupt_or_invalid_response",
        ],
        "certainty": CERTAINTY,
        "reconciliation": RECONCILIATION,
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
        "qualification": "put_bucket_tagging",
        "ada_symbols": [
            "Prepare_Put_Bucket_Tagging",
            "Decode_Put_Bucket_Tagging_Response",
            "Execute_Put_Bucket_Tagging",
            "Put_Bucket_Tagging_Operation",
            "Put_Tags",
            "Finish",
        ],
    }
    for key, value in expected.items():
        assert entry[key] == value, f"PutBucketTagging changed: {key}"
    assert "exact NoSuchBucket" in entry["absence"]
    assert "exact HTTP 200" in entry["exclusions"][2]
    assert "exact 200 or 204" in entry["exclusions"][2]
    assert "whitespace-only success payload" in entry["exclusions"][3]
    assert "does not establish causation" in entry["exclusions"][4]
    assert data["qualification"]["put_bucket_tagging"] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-put-bucket-tagging-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
        [
            "./tools/build-api-docs.sh",
            "/private/tmp/fos-put-bucket-tagging-gnatdoc",
        ],
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]


def verify_registry_negatives(data: dict[str, object]) -> None:
    mutations = (
        ("missing public name", "public_name", None),
        ("wrong public name", "public_name", "Put_Object_Tags"),
        ("200-only client", "certainty", CERTAINTY.replace(
            "200 or 204", "200"
        )),
        ("causal reconciliation", "reconciliation",
         "Get_Tags proves the mutation completed"),
        ("cross-operation lane", "qualification", "put_object_tagging"),
    )
    for label, key, value in mutations:
        candidate = copy.deepcopy(data)
        entry = operation_entry(candidate)
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        assert candidate != data, f"{label}: candidate did not change"
        try:
            verify_registry(candidate)
        except (AssertionError, KeyError, TypeError):
            continue
        raise AssertionError(f"{label}: candidate was accepted")


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
    qualification = collapsed(QUALIFICATION.read_text(encoding="utf-8"))

    low_contract = region(
        low_spec,
        "   --  Every modeled PutBucketTagging control.",
        "   --  Complete modeled GetBucketTagging request controls.",
        "low-level contract",
    )
    ordered(
        low_contract,
        [
            "@field Content_MD5",
            "@field Checksum_Algorithm",
            "@field Expected_Bucket_Owner",
            "@field Request_Payer",
            "function Prepare_Put_Bucket_Tagging",
            "type Put_Bucket_Tagging_Result",
            "type Put_Bucket_Tagging_Outcome_Kind",
            "type Put_Bucket_Tagging_Outcome",
            "Decode exact HTTP 200 or 204",
            "Whitespace-only success payload is tolerated",
            "function Decode_Put_Bucket_Tagging_Response",
            "function Execute_Put_Bucket_Tagging",
        ],
        "low-level contract",
    )
    decoder = region(
        low_body,
        "   function Decode_Put_Bucket_Tagging_Response",
        "   function Execute_Put_Bucket_Tagging",
        "response decoder",
    )
    ordered(
        decoder,
        [
            "if Status in 200 | 204 then",
            "if not Whitespace_Only (Payload) then",
            "elsif Charged'Length > 0 then",
            "Kind => Bucket_Tags_Replaced, Status => Status",
            "Put_Bucket_Tagging_Rejected",
        ],
        "response decoder",
    )
    assert "Status in 200 | 201 | 204" not in decoder

    public_contract = region(
        buckets_spec,
        "   --  Shape of a terminal PutBucketTagging mutation.",
        "   --  Shape of a terminal GetBucketTagging read.",
        "public composable contract",
    )
    for marker in (
        "type Put_Bucket_Tagging_Result_Kind",
        "type Put_Bucket_Tagging_Result",
        "type Put_Bucket_Tagging_Operation",
        "procedure Put_Tags",
        "function Put_Tags",
        "procedure Finish",
    ):
        assert marker in public_contract, f"public contract lacks {marker}"
    sync_contract = region(
        buckets_spec,
        "   --  Outcome of one synchronous bucket-tag replacement.",
        "   --  Result shape for one completed bucket-tag read.",
        "synchronous contract",
    )
    ordered(
        sync_contract,
        [
            "@enum Tags_Replaced",
            "@enum Put_Tags_Rejected",
            "type Put_Tags_Outcome_Kind",
            "@field Kind",
            "@field Status",
            "@field Error",
            "type Put_Tags_Outcome",
            "function Put_Tags",
        ],
        "synchronous contract",
    )
    provider = region(
        buckets_body,
        "   function Normalize_Put_Bucket_Tagging_Response",
        "   function Normalize_Get_Bucket_Tagging_Response",
        "composable provider",
    )
    ordered(
        provider,
        [
            "Bucket_Tag_Mutation_Outcome_Unknown",
            "Bucket_Tag_Mutation_Completed",
            "Bucket_Tag_Response_Failure",
            "procedure Start_Put_Bucket_Tagging",
            "PutBucketTagging restart changed a retained owner",
            "function Put_Tags",
            "procedure Finish",
        ],
        "composable provider",
    )

    certainty = region(
        testing,
        "   procedure Check_Bucket_Tagging_Certainty_Corpus is",
        "   end Check_Bucket_Tagging_Certainty_Corpus;",
        "certainty corpus",
    )
    ordered(
        certainty,
        [
            "Bucket_Tag_Mutation_Cancelled_Before_Admission",
            "if Status in 200 | 204",
            "Result.Response.Status /= Status",
            "(200, \"\", Bucket_Tag_Mutation_Completed, No_Failure);",
            "(204, \"\", Bucket_Tag_Mutation_Completed, No_Failure);",
            "Bucket_Tag_Mutation_Outcome_Unknown",
        ],
        "certainty corpus",
    )
    direct_region = region(
        direct,
        "   procedure Check_Low_Level_Bucket_Lifecycle",
        "   procedure Check_Low_Level_Delete_Requests",
        "direct evidence",
    )
    ordered(
        direct_region,
        [
            "Prepare_Put_Bucket_Tagging",
            "content-md5;host;x-amz-content-sha256;x-amz-date;",
            "for Algorithm in Checksum_Policy.Algorithm loop",
            "Outcome_200",
            "Outcome_204",
            "Outcome_Whitespace",
            "Outcome_200.Status = 200",
            "Outcome_204.Status = 204",
            "Outcome_Whitespace.Status = 200",
        ],
        "direct evidence",
    )
    socket_region = region(
        socket,
        "Operation : Put_Bucket_Tagging_Operation :=",
        "Operation : Get_Bucket_Tagging_Operation :=",
        "socket PutBucketTagging evidence",
    )
    ordered(
        socket_region,
        [
            "Put_Tags",
            "Operations.Wait_All (Set);",
            "Finish (Operation, Put_Result);",
            "HTTP_Client.Response_Observed",
            "Low_Level.Bucket_Tags_Replaced",
            "Operation => Operation",
            '"scoped PutBucketTagging restart mismatch"',
        ],
        "socket PutBucketTagging evidence",
    )
    server_region = region(
        server,
        "            when Put_Bucket_Tagging =>",
        "            when Get_Bucket_Tagging =>",
        "server route",
    )
    ordered(
        server_region,
        [
            "MD5_Count",
            "Checksum_Count",
            "Check_Expected_Bucket_Owner",
            "Store.Put_Bucket_Tags",
            'Apps.Respond (X, 200, "", "");',
        ],
        "server route",
    )
    for marker in (
        "PutBucketTagging success mismatch",
        "PutBucketTagging did not replace the complete set",
        "PutBucketTagging accepted a missing Content-MD5",
        "PutBucketTagging accepted a mismatched optional checksum",
    ):
        assert marker in server_test, f"server evidence lacks {marker}"
    ordered(
        qualification,
        [
            "server returns 200 for Put",
            "client accepts both 200 and 204",
            "neither mutation can be replayed",
            "removed exactly 48 candidate-owned warnings",
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
        "PutBucketTagging preparation: exact request/checksum graph, "
        "200|204 client compatibility, certainty, lifecycle, and docs match"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (
        AssertionError, KeyError, OSError, UnicodeError, ValueError
    ) as exc:
        print(f"PutBucketTagging verification failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
