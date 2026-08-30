#!/usr/bin/env python3
"""Fail closed on the reviewed GetObject qualification boundary."""

from __future__ import annotations

import copy
import hashlib
import json
import os
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODEL_SHA256 = (
    "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
)
REGISTRY = ROOT / "coverage" / "s3-operations.toml"
LOW_SPEC = ROOT / "src" / "flyology-object_storage-client-low_level.ads"
LOW_BODY = ROOT / "src" / "flyology-object_storage-client-low_level.adb"
OBJECTS_SPEC = ROOT / "src" / "flyology-object_storage-client-objects.ads"
OBJECTS_BODY = ROOT / "src" / "flyology-object_storage-client-objects.adb"
DIRECT_TEST = ROOT / "tests" / "src" / "object_storage_test_cases.adb"
SOCKET = ROOT / "tests" / "src" / "s3_http_socket_corpus.adb"
FIXTURE = ROOT / "tests" / "corpora" / "composable-client" / "range-get.tsv"
FIXTURE_VERIFY = ROOT / "tools" / "verify-composable-client-fixtures.sh"
FIXTURE_NEGATIVE = (
    ROOT / "tools" / "test-composable-client-fixtures-verifier.sh"
)
DOCUMENT = ROOT / "docs" / "qualification" / "get-object.md"


class Evidence_Error(RuntimeError):
    """One reviewed GetObject invariant changed."""


def fail(message: str) -> None:
    raise Evidence_Error(message)


def source(path: Path) -> str:
    if not path.is_file() or path.is_symlink():
        fail(f"missing or unsafe evidence path: {path}")
    raw = path.read_bytes()
    if b"\r" in raw:
        fail(f"noncanonical CR byte: {path}")
    return raw.decode("utf-8")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require_once(text: str, fragment: str, label: str) -> int:
    count = text.count(fragment)
    if count != 1:
        fail(f"{label}: expected once, found {count}: {fragment!r}")
    return text.index(fragment)


def require_in_order(text: str, fragments: list[str], label: str) -> None:
    position = 0
    for fragment in fragments:
        position = text.find(fragment, position)
        if position < 0:
            fail(f"{label}: missing or reordered fragment: {fragment!r}")
        position += len(fragment)


def unique_region(text: str, start: str, end: str, label: str) -> str:
    first = require_once(text, start, label)
    finish = text.find(end, first + len(start))
    if finish < 0:
        fail(f"{label}: missing end boundary")
    return text[first : finish + len(end)]


def normalized(text: str) -> str:
    return " ".join(text.split())


def expect_failure(action, label: str) -> None:
    try:
        action()
    except (AssertionError, Evidence_Error, KeyError, TypeError):
        return
    fail(f"negative candidate was accepted: {label}")


def load_model() -> dict[str, object]:
    value = os.environ.get("FLYOLOGY_S3_SERVICE_MODEL", "")
    if not value:
        fail("FLYOLOGY_S3_SERVICE_MODEL is required")
    path = Path(value)
    source(path)
    if digest(path) != MODEL_SHA256:
        fail("pinned S3 model hash changed")
    return json.loads(path.read_text(encoding="utf-8"))


def verify_model(model: dict[str, object]) -> None:
    operation = model["operations"]["GetObject"]
    shapes = model["shapes"]
    assert operation["http"] == {
        "method": "GET",
        "requestUri": "/{Bucket}/{Key+}",
    }
    assert operation["input"] == {"shape": "GetObjectRequest"}
    assert operation["output"] == {"shape": "GetObjectOutput"}
    assert operation["httpChecksum"] == {
        "requestValidationModeMember": "ChecksumMode",
        "responseAlgorithms": [
            "CRC64NVME",
            "CRC32",
            "CRC32C",
            "SHA256",
            "SHA1",
            "SHA512",
            "MD5",
            "XXHASH64",
            "XXHASH3",
            "XXHASH128",
        ],
    }
    request = shapes["GetObjectRequest"]
    assert request["required"] == ["Bucket", "Key"]
    assert list(request["members"]) == [
        "Bucket",
        "IfMatch",
        "IfModifiedSince",
        "IfNoneMatch",
        "IfUnmodifiedSince",
        "Key",
        "Range",
        "ResponseCacheControl",
        "ResponseContentDisposition",
        "ResponseContentEncoding",
        "ResponseContentLanguage",
        "ResponseContentType",
        "ResponseExpires",
        "VersionId",
        "SSECustomerAlgorithm",
        "SSECustomerKey",
        "SSECustomerKeyMD5",
        "RequestPayer",
        "PartNumber",
        "ExpectedBucketOwner",
        "ChecksumMode",
    ]
    output = shapes["GetObjectOutput"]
    assert output["payload"] == "Body"
    assert len(output["members"]) == 43
    for name in (
        "Body",
        "ContentLength",
        "ContentRange",
        "ETag",
        "VersionId",
        "RequestCharged",
        "ChecksumSHA256",
        "ChecksumType",
    ):
        assert name in output["members"]


def expected_lane() -> list[list[str]]:
    return [
        [
            "uv",
            "run",
            "--python",
            "3.13",
            "--",
            "tools/verify-get-object-preparation.py",
        ],
        ["./tools/verify-composable-client-fixtures.sh"],
        ["./tools/test-composable-client-fixtures-verifier.sh"],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
        [
            "./tools/build-api-docs.sh",
            "/private/tmp/fos-get-object-gnatdoc",
        ],
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]


def get_entry(data: dict[str, object]) -> dict[str, object]:
    matches = [
        item for item in data["operation"] if item["name"] == "GetObject"
    ]
    if len(matches) != 1:
        fail("GetObject registry entry is not unique")
    return matches[0]


def verify_registry_data(data: dict[str, object]) -> None:
    if data["model_sha256"] != MODEL_SHA256:
        fail("registry model pin changed")
    entry = get_entry(data)
    assert entry["public_name"] == "Get_Whole"
    assert entry["decision_status"] == "reviewed"
    assert entry["human_decisions_resolved"] is True
    assert entry["qualification"] == "get_object"
    assert entry["ada_symbols"] == [
        "Prepare_Get_Object",
        "Decode_Get_Object_Response_Head",
        "Decode_Get_Object_Complete_Response",
        "Execute_Get_Object",
        "Whole_Get_Operation",
        "Get_Whole",
        "Range_Get_Operation",
        "Get_Range",
        "Finish",
    ]
    assert "must be echoed exactly" in entry["absence"]
    assert "exposes no bytes" in entry["certainty"]
    assert "does not recompute" in entry["exclusions"][0]
    assert "tools/verify-get-object-preparation.py" in (
        entry["evidence"]["corpus"]
    )
    assert data["qualification"]["get_object"] == expected_lane()


def verify_registry() -> None:
    data = tomllib.loads(source(REGISTRY))
    verify_registry_data(data)
    mutations = [
        ("missing public name", lambda item: item.pop("public_name")),
        (
            "wrong public name",
            lambda item: item.__setitem__("public_name", "Get_Range"),
        ),
        (
            "wrong certainty",
            lambda item: item.__setitem__("certainty", "read only"),
        ),
        (
            "cross-operation symbol",
            lambda item: item["ada_symbols"].__setitem__(
                0, "Prepare_Head_Object"
            ),
        ),
    ]
    for label, mutate in mutations:
        candidate = copy.deepcopy(data)
        mutate(get_entry(candidate))
        expect_failure(
            lambda candidate=candidate: verify_registry_data(candidate),
            label,
        )
    candidate = copy.deepcopy(data)
    candidate["qualification"]["get_object"].pop(0)
    expect_failure(
        lambda: verify_registry_data(candidate),
        "missing lane command",
    )


def verify_sources() -> None:
    low_spec = unique_region(
        source(LOW_SPEC),
        "   --  GetObject has the same 21 modeled request members",
        "   function Decode_Get_Object_Complete_Response",
        "Low_Level GetObject specification",
    )
    require_in_order(
        low_spec,
        [
            "subtype Get_Object_Parameters is Head_Object_Parameters;",
            "function Prepare_Get_Object",
            "type Get_Object_Result is record",
            "type Get_Object_Head_Outcome_Kind is",
            "type Get_Object_Head_Outcome",
            "function Execute_Get_Object",
            "function Decode_Get_Object_Response_Head",
            "function Decode_Get_Object_Complete_Response",
        ],
        "Low_Level GetObject public surface",
    )
    low_body = unique_region(
        source(LOW_BODY),
        "   function Prepare_Get_Object\n",
        "   end Decode_Get_Object_Complete_Response;",
        "Low_Level GetObject implementation",
    )
    require_in_order(
        low_body,
        [
            "S3.Deletions.Valid_Version_ID (Version_ID)",
            "Valid_List_Response_Header_Text (Version_ID)",
            "Requested_Get_Object_Version_ID := Parameters.Version_ID",
            "Requested_Get_Object_Request_Payer :=",
            "function Decode_Get_Object_Complete_Response",
            "GetObject response duplicates a singleton header",
            "Validate_Get_Object_Headers (Result, Status);",
        ],
        "Low_Level GetObject preparation and response",
    )
    objects_spec = unique_region(
        source(OBJECTS_SPEC),
        "   --  Same-response bounded whole GetObject operation.",
        "   --  Shape of a terminal ListObjects v1 read.",
        "Objects GetObject public surface",
    )
    require_in_order(
        objects_spec,
        [
            "type Whole_Get_Operation",
            "procedure Get_Whole",
            "function Get_Whole",
            "procedure Finish",
            "type Range_Get_Operation",
            "procedure Get_Range",
            "function Get_Range",
            "procedure Finish",
        ],
        "Objects GetObject public surface",
    )
    objects_body = source(OBJECTS_BODY)
    binding = unique_region(
        objects_body,
        "   function Get_Object_Response_Bound",
        "   end Get_Object_Response_Bound;",
        "GetObject response binding",
    )
    require_in_order(
        binding,
        [
            "Requested_Version'Length = 0",
            "Result.Version_ID",
            "Requested_Version",
            'Returned_Payer /= "requester"',
            'Requested_Payer = "requester"',
        ],
        "GetObject response binding",
    )
    if objects_body.count("not Get_Object_Response_Bound") != 3:
        fail("whole/range GetObject binding call count changed")
    direct_text = source(DIRECT_TEST)
    projection = unique_region(
        direct_text,
        (
            "            declare\n"
            "               Get_Prepared : constant "
            "Low_Level.Prepared_Request :="
        ),
        '"GetObject projects all 21 modeled request members");',
        "direct GetObject projection test",
    )
    require_in_order(
        projection,
        [
            "Low_Level.Prepare_Get_Object",
            "Low_Level.Target (Get_Prepared)",
            "Low_Level.Signed_Headers (Get_Prepared)",
            '"GetObject projects all 21 modeled request members"',
        ],
        "direct GetObject projection test",
    )
    unsafe = unique_region(
        direct_text,
        (
            "         Parameters.SSE_Customer_Algorithm :=\n"
            '           US.To_Unbounded_String ("AES512");'
        ),
        '"GetObject accepted an unsafe version identifier");',
        "direct GetObject rejection tests",
    )
    require_in_order(
        unsafe,
        [
            "Low_Level.Prepare_Get_Object",
            '"GetObject accepted a non-AES256 SSE-C algorithm"',
            "Character'Val (16#7F#)",
            "Low_Level.Prepare_Get_Object",
            '"GetObject accepted an unsafe version identifier"',
        ],
        "direct GetObject rejection tests",
    )
    socket = unique_region(
        source(SOCKET),
        "               procedure Run_Whole_Get_Cancellation is",
        "               end Run_Whole_Get_Cancellation;",
        "GetObject cancellation corpus",
    )
    require_in_order(
        socket,
        [
            "Operations.Completion_Set (5)",
            "Operations.Wait_Some",
            "Flyology.IO.Finish (Admission_Ready);",
            "Operations.Cancel (Operation);",
            "Operations.Wait_All (Cancel_Set);",
            "Finish (Operation, Result);",
            "Flyology.IO.Finish (Drain_Ready);",
            '"whole GET restart changed a retained owner"',
            '"whole GET restart changed a retained owner"',
            '"whole GET restart changed a retained owner"',
            "Objects.Get_Whole",
            "Operations.Wait_All (Cancel_Set);",
            "Finish (Operation, Result);",
            "Result.Response.Status /= 200",
            '"same-object GetObject restart mismatch"',
        ],
        "GetObject cancellation corpus",
    )
    if socket.count('"whole GET restart changed a retained owner"') != 3:
        fail("GetObject owner-substitution assertions changed")
    full_socket = source(SOCKET)
    for fragment in (
        "scoped-get-version-missing",
        "scoped-get-version-mismatch",
        "scoped-get-version-duplicate",
        "scoped-get-version-control",
        "scoped-get-version-del",
        "scoped-get-payer-mismatch",
        "range GetObject accepted mismatched version binding",
    ):
        if fragment not in full_socket:
            fail(f"GetObject response-binding case missing: {fragment}")


def verify_fixture_and_document() -> None:
    fixture = source(FIXTURE)
    assert fixture.splitlines()[0].split("\t") == [
        "case",
        "scope",
        "concern",
        "request",
        "response",
        "required_observation",
    ]
    for fragment in (
        "whole-exclusion",
        "generation",
        "multipart/byteranges",
        "checksum",
    ):
        if fragment not in fixture:
            fail(f"range fixture fact missing: {fragment}")
    require_in_order(
        source(FIXTURE_VERIFY),
        ["range-get.tsv", "composable client fixtures: OK"],
        "range fixture verifier",
    )
    require_in_order(
        source(FIXTURE_NEGATIVE),
        ["range-get", "composable client fixture verifier self-tests: OK"],
        "range fixture negatives",
    )
    document = normalized(source(DOCUMENT))
    require_in_order(
        document,
        [
            normalized(
                "Qualification remains conditional on the complete "
                "`get_object` lane succeeding"
            ),
            normalized(
                "An explicit nonempty `VersionId` must be a valid "
                "text-safe selector"
            ),
            normalized(
                "this client slice does not recompute them over the "
                "returned payload"
            ),
            normalized(
                "do not authorize automatic replay or a mutation "
                "certainty upgrade"
            ),
            "--operation GetObject",
            normalized(
                "Unrelated repository GNATdoc warnings currently keep "
                "that global gate closed"
            ),
        ],
        "conditional GetObject qualification prose",
    )


def main() -> None:
    verify_model(load_model())
    verify_registry()
    verify_sources()
    verify_fixture_and_document()
    print(
        "GetObject preparation: pinned model, exact response binding, "
        "lifecycle, registry, and conditional evidence match"
    )


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, Evidence_Error, KeyError, TypeError) as error:
        raise SystemExit(f"GetObject preparation: {error}") from error
