#!/usr/bin/env python3
"""Fail closed on the reviewed HeadObject qualification boundary."""

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
DOCUMENT = ROOT / "docs" / "qualification" / "head-object.md"


class Evidence_Error(RuntimeError):
    """One reviewed HeadObject invariant changed."""


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
    operation = model["operations"]["HeadObject"]
    shapes = model["shapes"]
    assert operation["http"] == {
        "method": "HEAD",
        "requestUri": "/{Bucket}/{Key+}",
    }
    assert operation["input"] == {"shape": "HeadObjectRequest"}
    assert operation["output"] == {"shape": "HeadObjectOutput"}
    request = shapes["HeadObjectRequest"]
    assert request["required"] == ["Bucket", "Key"]
    assert len(request["members"]) == 21
    for name in (
        "Bucket",
        "Key",
        "VersionId",
        "RequestPayer",
        "ExpectedBucketOwner",
        "ChecksumMode",
    ):
        assert name in request["members"]
    output = shapes["HeadObjectOutput"]
    assert len(output["members"]) == 43
    for name in (
        "ContentLength",
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
            "tools/verify-head-object-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
        [
            "./tools/build-api-docs.sh",
            "/private/tmp/fos-head-object-gnatdoc",
        ],
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]


def get_entry(data: dict[str, object]) -> dict[str, object]:
    matches = [
        item for item in data["operation"] if item["name"] == "HeadObject"
    ]
    if len(matches) != 1:
        fail("HeadObject registry entry is not unique")
    return matches[0]


def verify_registry_data(data: dict[str, object]) -> None:
    if data["model_sha256"] != MODEL_SHA256:
        fail("registry model pin changed")
    entry = get_entry(data)
    assert entry["public_name"] == "Head_Object"
    assert entry["decision_status"] == "reviewed"
    assert entry["human_decisions_resolved"] is True
    assert entry["qualification"] == "head_object"
    assert entry["ada_symbols"] == [
        "Prepare_Head_Object",
        "Decode_Head_Object_Response",
        "Decode_Head_Object_Complete_Response",
        "Execute_Head_Object",
        "Head_Operation",
        "Head_Object",
        "Finish",
    ]
    assert "must be echoed exactly" in entry["absence"]
    assert "bind to the prepared request" in entry["certainty"]
    assert "no payload to recompute" in entry["exclusions"][0]
    assert "tools/verify-head-object-preparation.py" in (
        entry["evidence"]["corpus"]
    )
    assert data["qualification"]["head_object"] == expected_lane()


def verify_registry() -> None:
    data = tomllib.loads(source(REGISTRY))
    verify_registry_data(data)
    mutations = [
        ("missing public name", lambda item: item.pop("public_name")),
        (
            "wrong public name",
            lambda item: item.__setitem__("public_name", "Head"),
        ),
        (
            "wrong certainty",
            lambda item: item.__setitem__("certainty", "read only"),
        ),
        (
            "cross-operation symbol",
            lambda item: item["ada_symbols"].__setitem__(
                0, "Prepare_Head_Bucket"
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
    candidate["qualification"]["head_object"].pop(0)
    expect_failure(
        lambda: verify_registry_data(candidate),
        "missing lane command",
    )


def verify_sources() -> None:
    low_spec = unique_region(
        source(LOW_SPEC),
        "   --  Every input member in the pinned HeadObject request shape.",
        "   function Execute_Head_Object",
        "Low_Level HeadObject specification",
    )
    require_in_order(
        low_spec,
        [
            "type Head_Object_Parameters is record",
            "function Prepare_Head_Object",
            "type Head_Object_Result is record",
            "type Head_Object_Outcome_Kind is",
            "type Head_Object_Outcome",
            "function Decode_Head_Object_Response",
            "function Decode_Head_Object_Complete_Response",
            "function Execute_Head_Object",
        ],
        "Low_Level HeadObject public surface",
    )
    low_body = source(LOW_BODY)
    prepare = unique_region(
        low_body,
        "   function Prepare_Head_Object\n",
        "   end Prepare_Head_Object;",
        "Low_Level HeadObject preparation",
    )
    require_in_order(
        prepare,
        [
            "S3.Deletions.Valid_Version_ID (Version_ID)",
            "Valid_List_Response_Header_Text (Version_ID)",
            "Requested_Head_Object_Version_ID := Parameters.Version_ID",
            "Requested_Head_Object_Request_Payer :=",
        ],
        "Low_Level HeadObject preparation",
    )
    binding = unique_region(
        low_body,
        "   function Head_Object_Response_Bound",
        "   end Head_Object_Response_Bound;",
        "Low_Level HeadObject response binding",
    )
    require_in_order(
        binding,
        [
            "Requested_Version'Length = 0",
            "Value.Version_ID",
            "Requested_Version",
            'Returned_Payer /= "requester"',
            'Requested_Payer = "requester"',
        ],
        "Low_Level HeadObject response binding",
    )
    execute = unique_region(
        low_body,
        "   function Execute_Head_Object\n",
        "   end Execute_Head_Object;",
        "Low_Level HeadObject execution",
    )
    require_in_order(
        execute,
        [
            "Decode_Head_Object_Complete_Response",
            "not Head_Object_Response_Bound",
            'raise Invalid_Response with',
        ],
        "Low_Level HeadObject execution",
    )
    objects_spec = unique_region(
        source(OBJECTS_SPEC),
        "   --  Shape of a terminal bodyless HeadObject result.",
        "   procedure Finish\n     (Operation : in out Head_Operation;",
        "Objects HeadObject public surface",
    )
    require_in_order(
        objects_spec,
        [
            "type Head_Result_Kind is",
            "type Head_Result",
            "type Head_Operation",
            "procedure Head_Object",
            "function Head_Object",
            "procedure Finish",
        ],
        "Objects HeadObject public surface",
    )
    objects_body = source(OBJECTS_BODY)
    composed = unique_region(
        objects_body,
        "   function Head_Object_Response_Bound",
        "   end Head_Object_Response_Bound;",
        "composable HeadObject response binding",
    )
    require_in_order(
        composed,
        [
            "Requested_Version'Length = 0",
            "Result.Version_ID",
            'Returned_Payer /= "requester"',
            'Requested_Payer = "requester"',
        ],
        "composable HeadObject response binding",
    )
    if objects_body.count("not Head_Object_Response_Bound") != 1:
        fail("composable HeadObject binding call count changed")
    direct = source(DIRECT_TEST)
    for fragment in (
        "HeadObject accepted an unsafe version identifier",
        "HeadObject accepted an unsafe version ID",
        "HeadObject accepted invalid request charging",
    ):
        if fragment not in direct:
            fail(f"HeadObject direct rejection case missing: {fragment}")
    socket = unique_region(
        source(SOCKET),
        "               procedure Run_Head_Object_Cancellation is",
        "               end Run_Head_Object_Cancellation;",
        "HeadObject cancellation corpus",
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
            '"HeadObject restart changed a retained owner"',
            '"HeadObject restart changed a retained owner"',
            "Objects.Head_Object",
            "Operations.Wait_All (Cancel_Set);",
            "Finish (Operation, Result);",
            "Result.Response.Status /= 200",
            '"same-object HeadObject restart mismatch"',
        ],
        "HeadObject cancellation corpus",
    )
    if socket.count('"HeadObject restart changed a retained owner"') != 2:
        fail("HeadObject owner-substitution assertions changed")
    full_socket = source(SOCKET)
    for fragment in (
        "scoped-head-version-missing",
        "scoped-head-version-mismatch",
        "scoped-head-version-control",
        "scoped-head-version-del",
        "scoped-head-payer-mismatch",
    ):
        if fragment not in full_socket:
            fail(f"HeadObject response-binding case missing: {fragment}")


def verify_document() -> None:
    document = normalized(source(DOCUMENT))
    require_in_order(
        document,
        [
            normalized(
                "Qualification remains conditional on the complete "
                "`head_object` lane succeeding"
            ),
            normalized(
                "An explicit nonempty `VersionId` must be a valid "
                "text-safe selector"
            ),
            normalized(
                "do not prove the cause of a prior mutation, authorize "
                "automatic replay, or upgrade mutation certainty"
            ),
            "--operation HeadObject",
            normalized(
                "exact region-scoped GNATdoc reduction of 96 prior "
                "Low_Level warnings"
            ),
            normalized(
                "Unrelated repository GNATdoc warnings currently keep "
                "that global gate closed"
            ),
        ],
        "conditional HeadObject qualification prose",
    )


def main() -> None:
    verify_model(load_model())
    verify_registry()
    verify_sources()
    verify_document()
    print(
        "HeadObject preparation: pinned model, exact response binding, "
        "lifecycle, registry, and conditional evidence match"
    )


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, Evidence_Error, KeyError, TypeError) as error:
        raise SystemExit(f"HeadObject preparation: {error}") from error
