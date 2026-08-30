#!/usr/bin/env python3
"""Fail-closed evidence for reviewed DeleteBucketTagging qualification."""

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
MODEL_SPEC = ROOT / "src" / "flyology-object_storage-s3-model.ads"
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
    "only a complete validated 204 response reports "
    "Bucket_Tag_Mutation_Completed; an exact recognized non-mutating "
    "rejection or definite non-admission reports "
    "Bucket_Tag_Mutation_Definitely_Not_Applied; pre-admission cancellation "
    "reports Bucket_Tag_Mutation_Cancelled_Before_Admission; possible or "
    "incomplete admission, retryable responses, and malformed or oversized "
    "responses report Bucket_Tag_Mutation_Outcome_Unknown; no automatic "
    "replay"
)
RECONCILIATION = (
    "caller-selected Get_Tags may observe the current NoSuchTagSet state "
    "before a retry but does not prove that the lost deletion caused the "
    "observed absence or upgrade mutation certainty; no automatic replay"
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
    operation = model["operations"]["DeleteBucketTagging"]
    assert operation["http"] == {
        "method": "DELETE",
        "requestUri": "/{Bucket}?tagging",
        "responseCode": 204,
    }
    assert operation["input"] == {"shape": "DeleteBucketTaggingRequest"}
    assert "output" not in operation
    assert "httpChecksum" not in operation
    request = model["shapes"]["DeleteBucketTaggingRequest"]
    assert request["required"] == ["Bucket"]
    assert list(request["members"]) == ["Bucket", "ExpectedBucketOwner"]
    assert request["members"]["ExpectedBucketOwner"]["locationName"] == (
        "x-amz-expected-bucket-owner"
    )


def operation_entry(data: dict[str, object]) -> dict[str, object]:
    matches = [
        item for item in data["operation"]
        if item["name"] == "DeleteBucketTagging"
    ]
    assert len(matches) == 1, "DeleteBucketTagging entry is not unique"
    return matches[0]


def verify_registry(data: dict[str, object] | None = None) -> None:
    if data is None:
        data = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    entry = operation_entry(data)
    expected = {
        "tier": "extended",
        "provider": "buckets",
        "family": "bodyless_mutation",
        "public_provider": "Flyology.Object_Storage.Client.Buckets",
        "codec": "empty_response",
        "public_name": "Delete_Tags",
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
        "implementation_mode": "handwritten",
        "generator_eligible": False,
        "human_decisions_resolved": True,
        "decision_status": "reviewed",
        "qualification": "delete_bucket_tagging",
        "ada_symbols": [
            "Prepare_Delete_Bucket_Tagging",
            "Decode_Delete_Bucket_Tagging_Response",
            "Execute_Delete_Bucket_Tagging",
            "Delete_Bucket_Tagging_Operation",
            "Delete_Tags",
            "Finish",
        ],
    }
    for key, value in expected.items():
        assert entry[key] == value, f"DeleteBucketTagging changed: {key}"
    assert "does not assert prior tag-set presence" in entry["absence"]
    assert "exact NoSuchBucket" in entry["absence"]
    assert "exact HTTP 204" in entry["exclusions"][2]
    assert "exactly empty response body" in entry["exclusions"][2]
    assert "previously present" in entry["exclusions"][3]
    assert "does not establish causation" in entry["exclusions"][4]
    assert data["qualification"]["delete_bucket_tagging"] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-delete-bucket-tagging-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
        [
            "./tools/build-api-docs.sh",
            "/private/tmp/fos-delete-bucket-tagging-gnatdoc",
        ],
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]


def verify_registry_negatives(data: dict[str, object]) -> None:
    mutations = (
        ("missing public name", "public_name", None),
        ("wrong public name", "public_name", "Delete_Object_Tags"),
        (
            "broadened success",
            "certainty",
            CERTAINTY.replace("validated 204", "validated 200 or 204"),
        ),
        (
            "causal reconciliation",
            "reconciliation",
            "Get_Tags proves the deletion completed",
        ),
        ("cross-operation lane", "qualification", "delete_object_tagging"),
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
        LOW_SPEC, LOW_BODY, BUCKETS_SPEC, BUCKETS_BODY, MODEL_SPEC,
        TESTING, DIRECT, SOCKET, SERVER, SERVER_TEST, QUALIFICATION,
    )
    for path in paths:
        regular(path)
    low_spec = LOW_SPEC.read_text(encoding="utf-8")
    low_body = LOW_BODY.read_text(encoding="utf-8")
    buckets_spec = BUCKETS_SPEC.read_text(encoding="utf-8")
    buckets_body = BUCKETS_BODY.read_text(encoding="utf-8")
    model_spec = MODEL_SPEC.read_text(encoding="utf-8")
    testing = TESTING.read_text(encoding="utf-8")
    direct = DIRECT.read_text(encoding="utf-8")
    socket = SOCKET.read_text(encoding="utf-8")
    server = SERVER.read_text(encoding="utf-8")
    server_test = SERVER_TEST.read_text(encoding="utf-8")
    qualification = collapsed(QUALIFICATION.read_text(encoding="utf-8"))

    low_contract = region(
        low_spec,
        "   --  Complete modeled DeleteBucketTagging request controls.",
        "   --  Every modeled PutBucketVersioning input",
        "low-level contract",
    )
    ordered(
        low_contract,
        [
            "@field Expected_Bucket_Owner",
            "type Delete_Bucket_Tagging_Parameters",
            "Prepare one nonreplaying DeleteBucketTagging request",
            "function Prepare_Delete_Bucket_Tagging",
            "@enum Bucket_Tags_Deleted",
            "@enum Delete_Bucket_Tagging_Rejected",
            "type Delete_Bucket_Tagging_Outcome_Kind",
            "@field Kind",
            "@field Status",
            "@field Error",
            "type Delete_Bucket_Tagging_Outcome",
            "Decode exact HTTP 204 with an exactly empty response body",
            "function Decode_Delete_Bucket_Tagging_Response",
            "function Execute_Delete_Bucket_Tagging",
        ],
        "low-level contract",
    )
    decoder = region(
        low_body,
        "   function Decode_Delete_Bucket_Tagging_Response",
        "   function Execute_Delete_Bucket_Tagging",
        "response decoder",
    )
    ordered(
        decoder,
        [
            "if Status = 204 then",
            "if Payload'Length /= 0 then",
            "Bucket_Tags_Deleted, Status => Status",
            "Delete_Bucket_Tagging_Rejected",
        ],
        "response decoder",
    )
    assert "Status in 200 | 204" not in decoder

    public_contract = region(
        buckets_spec,
        "   --  Shape of a terminal DeleteBucketTagging mutation.",
        "   --  Result kind for one bounded ListBuckets page.",
        "public composable contract",
    )
    for marker in (
        "type Delete_Bucket_Tagging_Result_Kind",
        "type Delete_Bucket_Tagging_Result",
        "type Delete_Bucket_Tagging_Operation",
        "procedure Delete_Tags",
        "function Delete_Tags",
        "procedure Finish",
    ):
        assert marker in public_contract, f"public contract lacks {marker}"
    sync_contract = region(
        buckets_spec,
        "   --  Outcome of one synchronous bucket-tag deletion.",
        "   --  Shape of a terminal GetBucketVersioning read.",
        "synchronous contract",
    )
    ordered(
        sync_contract,
        [
            "@enum Tags_Deleted",
            "@enum Delete_Tags_Rejected",
            "type Delete_Tags_Outcome_Kind",
            "@field Kind",
            "@field Status",
            "@field Error",
            "type Delete_Tags_Outcome",
            "function Delete_Tags",
        ],
        "synchronous contract",
    )
    assert sync_contract.count("function Delete_Tags") == 2
    assert "previously present" in sync_contract
    assert model_spec.count(
        "@enum Delete_Bucket_Tagging_Operation "
        "Delete bucket tagging operation"
    ) == 1
    assert low_spec.count(
        "--  Start a prepared DeleteBucketTagging exchange."
    ) == 1
    assert "@param Operation Fresh or consumed" in region(
        low_spec,
        "   --  Start a prepared DeleteBucketTagging exchange.",
        "   --  Start a prepared PutObjectTagging exchange.",
        "low-level asynchronous start",
    )
    assert buckets_spec.count(
        "--  @exclude\n   function Normalize_Delete_Bucket_Tagging_"
    ) == 2

    provider = region(
        buckets_body,
        "   function Normalize_Delete_Bucket_Tagging_Response",
        "   procedure List_Page",
        "composable provider",
    )
    ordered(
        provider,
        [
            "Bucket_Tag_Mutation_Outcome_Unknown",
            "Bucket_Tag_Mutation_Completed",
            "Bucket_Tag_Mutation_Definitely_Not_Applied",
            "Normalize_Delete_Bucket_Tagging_Failure",
            "Complete_Delete_Bucket_Tagging_Child",
            "Low.Clear_Prepared_Request",
            "procedure Start_Delete_Bucket_Tagging",
            "DeleteBucketTagging restart changed a retained owner",
            "function Delete_Tags",
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
            "Check_Delete_Response",
            "(204, \"\", Bucket_Tag_Mutation_Completed, No_Failure);",
            "NoSuchBucket",
            "Bucket_Tag_Mutation_Definitely_Not_Applied",
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
            "Prepare_Delete_Bucket_Tagging",
            '"/example-bucket?tagging"',
            "Decode_Delete_Bucket_Tagging_Response (204, \"\")",
            "Outcome.Status = 204",
            "DeleteBucketTagging accepted a success body",
            "DeleteBucketTagging accepted a whitespace success body",
        ],
        "direct evidence",
    )
    socket_region = region(
        socket,
        "Operation : Delete_Bucket_Tagging_Operation :=",
        "Get_Result : constant Buckets.Get_Tags_Outcome :=",
        "socket DeleteBucketTagging evidence",
    )
    ordered(
        socket_region,
        [
            "Delete_Tags",
            "Operations.Wait_All (Set);",
            "Finish (Operation, Delete_Result);",
            "HTTP_Client.Response_Observed",
            "Low_Level.Bucket_Tags_Deleted",
            "Delete_Result.Response.Status /= 204",
            "Operation => Operation",
            '"scoped DeleteBucketTagging restart mismatch"',
        ],
        "socket DeleteBucketTagging evidence",
    )
    assert "Delete_Result.Status /= 204" in socket
    server_region = region(
        server,
        "            when Delete_Bucket_Tagging =>",
        "            when Put_Public_Access_Block =>",
        "server route",
    )
    ordered(
        server_region,
        [
            "Check_Expected_Bucket_Owner",
            "Store.Delete_Bucket_Tags",
            'Apps.Respond (X, 204, "", "");',
        ],
        "server route",
    )
    for marker in (
        "DeleteBucketTagging success mismatch",
        "DeleteBucketTagging left a visible tag set",
        "DeleteBucketTagging was not idempotent",
        "DeleteBucketTagging did not distinguish an absent bucket",
    ):
        assert marker in server_test, f"server evidence lacks {marker}"
    ordered(
        qualification,
        [
            "Delete requires and emits 204 with an exactly empty body",
            "neither mutation can be replayed",
            "removed exactly 49 candidate-owned warnings",
            "idempotent completion without asserting prior tag-set presence",
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
        "DeleteBucketTagging preparation: exact 204 empty response, "
        "idempotent completion, certainty, lifecycle, and docs match"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (
        AssertionError, KeyError, OSError, UnicodeError, ValueError
    ) as exc:
        print(
            f"DeleteBucketTagging verification failed: {exc}",
            file=sys.stderr,
        )
        raise SystemExit(1)
