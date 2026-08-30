#!/usr/bin/env python3
"""Fail closed on the reviewed GetObjectAttributes qualification boundary."""

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
MODEL_SPEC = ROOT / "src" / "flyology-object_storage-s3-model.ads"
MODEL_GENERATOR = ROOT / "tools" / "generate-s3-model.py"
SOCKET = ROOT / "tests" / "src" / "s3_http_socket_corpus.adb"
SERVER = ROOT / "tests" / "src" / "s3_server_application_corpus.adb"
DOCUMENT = ROOT / "docs" / "qualification" / "get-object-attributes.md"


class Evidence_Error(RuntimeError):
    """One reviewed GetObjectAttributes invariant changed."""


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
    operation = model["operations"]["GetObjectAttributes"]
    shapes = model["shapes"]
    assert operation["http"] == {
        "method": "GET",
        "requestUri": "/{Bucket}/{Key+}?attributes",
    }
    assert operation["input"] == {"shape": "GetObjectAttributesRequest"}
    assert operation["output"] == {"shape": "GetObjectAttributesOutput"}
    request = shapes["GetObjectAttributesRequest"]
    assert request["required"] == ["Bucket", "Key", "ObjectAttributes"]
    assert len(request["members"]) == 11
    for name in (
        "VersionId",
        "MaxParts",
        "PartNumberMarker",
        "RequestPayer",
        "ExpectedBucketOwner",
        "ObjectAttributes",
    ):
        assert name in request["members"]
    output = shapes["GetObjectAttributesOutput"]
    assert len(output["members"]) == 9
    for name in (
        "VersionId",
        "RequestCharged",
        "ETag",
        "Checksum",
        "ObjectParts",
        "StorageClass",
        "ObjectSize",
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
            "tools/verify-get-object-attributes-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
        [
            "./tools/build-api-docs.sh",
            "/private/tmp/fos-get-object-attributes-gnatdoc",
        ],
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]


def get_entry(data: dict[str, object]) -> dict[str, object]:
    matches = [
        item
        for item in data["operation"]
        if item["name"] == "GetObjectAttributes"
    ]
    if len(matches) != 1:
        fail("GetObjectAttributes registry entry is not unique")
    return matches[0]


def verify_registry_data(data: dict[str, object]) -> None:
    if data["model_sha256"] != MODEL_SHA256:
        fail("registry model pin changed")
    entry = get_entry(data)
    assert entry["public_name"] == "Get_Attributes"
    assert entry["decision_status"] == "reviewed"
    assert entry["human_decisions_resolved"] is True
    assert entry["qualification"] == "get_object_attributes"
    assert entry["ada_symbols"] == [
        "Prepare_Get_Object_Attributes",
        "Decode_Get_Object_Attributes_Response",
        "Decode_Get_Object_Attributes_Complete_Response",
        "Execute_Get_Object_Attributes",
        "Get_Object_Attributes_Operation",
        "Get_Attributes",
        "Finish",
    ]
    assert "MaxParts=0" in entry["absence"]
    assert "bind to the prepared request" in entry["certainty"]
    assert "does not recompute" in entry["exclusions"][0]
    assert "tools/verify-get-object-attributes-preparation.py" in (
        entry["evidence"]["corpus"]
    )
    assert data["qualification"]["get_object_attributes"] == expected_lane()


def verify_registry() -> None:
    data = tomllib.loads(source(REGISTRY))
    verify_registry_data(data)
    mutations = [
        ("missing public name", lambda item: item.pop("public_name")),
        (
            "wrong public name",
            lambda item: item.__setitem__("public_name", "Get_Whole"),
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
    candidate["qualification"]["get_object_attributes"].pop(0)
    expect_failure(
        lambda: verify_registry_data(candidate),
        "missing lane command",
    )


def verify_sources() -> None:
    low_spec = unique_region(
        source(LOW_SPEC),
        "   --  Every non-resource member in the pinned "
        "GetObjectAttributes request.",
        "   function Execute_Get_Object_Attributes",
        "Low_Level GetObjectAttributes specification",
    )
    require_in_order(
        low_spec,
        [
            "type Get_Object_Attributes_Parameters is record",
            "function Prepare_Get_Object_Attributes",
            "type Get_Object_Attributes_Result is record",
            "type Get_Object_Attributes_Outcome_Kind is",
            "type Get_Object_Attributes_Outcome",
            "function Decode_Get_Object_Attributes_Response",
            "function Decode_Get_Object_Attributes_Complete_Response",
            "function Execute_Get_Object_Attributes",
        ],
        "Low_Level GetObjectAttributes public surface",
    )
    low_body = source(LOW_BODY)
    prepare = unique_region(
        low_body,
        "   function Prepare_Get_Object_Attributes\n",
        "   end Prepare_Get_Object_Attributes;",
        "Low_Level GetObjectAttributes preparation",
    )
    require_in_order(
        prepare,
        [
            "Requested_Get_Attributes_Request_Payer :=",
            "Requested_Get_Attributes_Version_ID :=",
            "Requested_Get_Attributes_Selection :=",
            "Requested_Get_Attributes_Has_Max_Parts :=",
            "Requested_Get_Attributes_Max_Parts :=",
            "Requested_Get_Attributes_Has_Part_Marker :=",
            "Requested_Get_Attributes_Part_Marker :=",
        ],
        "Low_Level GetObjectAttributes retained request facts",
    )
    binding = unique_region(
        low_body,
        "   function Decode_Get_Object_Attributes_Complete_Response\n",
        "   end Decode_Get_Object_Attributes_Complete_Response;",
        "Low_Level GetObjectAttributes response binding",
    )
    require_in_order(
        binding,
        [
            "GetObjectAttributes response does not match request",
            "GetObjectAttributes returned an unrequested attribute",
            "Requested_Get_Attributes_Has_Part_Marker",
            "else 0",
            "Requested_Get_Attributes_Has_Max_Parts",
            "else 1_000",
            "Page.Part_Number_Marker.Value /=",
            "Page.Max_Parts.Value /= Requested_Maximum",
            "invalid GetObjectAttributes pagination geometry",
            "invalid GetObjectAttributes zero-size page",
        ],
        "Low_Level GetObjectAttributes response binding",
    )
    objects_spec = unique_region(
        source(OBJECTS_SPEC),
        "   --  Shape of a terminal GetObjectAttributes read.",
        "   procedure Finish\n"
        "     (Operation : in out Get_Object_Attributes_Operation;",
        "Objects GetObjectAttributes public surface",
    )
    require_in_order(
        objects_spec,
        [
            "type Get_Object_Attributes_Result_Kind is",
            "type Get_Object_Attributes_Result",
            "type Get_Object_Attributes_Operation",
            "procedure Get_Attributes",
            "function Get_Attributes",
            "procedure Finish",
        ],
        "Objects GetObjectAttributes public surface",
    )
    normalization = unique_region(
        source(OBJECTS_BODY),
        "   function Normalize_Get_Object_Attributes_Response\n",
        "   end Normalize_Get_Object_Attributes_Response;",
        "GetObjectAttributes response normalization",
    )
    require_in_order(
        normalization,
        [
            "Value.Status = 400",
            '"InvalidArgument" | "InvalidDigest" | "InvalidRequest"',
            "then Invalid_Request",
        ],
        "GetObjectAttributes response normalization",
    )
    socket = unique_region(
        source(SOCKET),
        "            procedure Run_Get_Object_Attributes_Cancellation is",
        "            end Run_Get_Object_Attributes_Cancellation;",
        "GetObjectAttributes cancellation corpus",
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
            '"GetObjectAttributes restart changed a "',
            '"GetObjectAttributes restart changed a "',
            "Get_Attributes",
            "Operations.Wait_All (Cancel_Set);",
            "Finish (Operation, Result);",
            "Result.Response.Status /= 200",
            '"same-object GetObjectAttributes restart mismatch"',
        ],
        "GetObjectAttributes cancellation corpus",
    )
    if socket.count('"GetObjectAttributes restart changed a "') != 2:
        fail("GetObjectAttributes owner-substitution assertions changed")
    full_socket = source(SOCKET)
    for fragment in (
        "zero-attributes",
        "scoped-attributes-page",
        "scoped-attributes-default-max",
        "scoped-attributes-default-marker",
        "scoped-attributes-zero-page",
        "scoped-attributes-unrequested",
        "normalized-attributes-digest",
    ):
        if fragment not in full_socket:
            fail(f"GetObjectAttributes socket case missing: {fragment}")
    server = unique_region(
        source(SERVER),
        '               "x-amz-max-parts: 0" & CRLF &',
        '            "GetObjectAttributes MaxParts zero behavior mismatch: "',
        "GetObjectAttributes server zero-page case",
    )
    require_in_order(
        server,
        [
            '"x-amz-max-parts: 0"',
            '"x-amz-part-number-marker: 0"',
            "Parsed.Object_Parts.Max_Parts.Value = 0",
            "not Parsed.Object_Parts.Is_Truncated",
            "Parsed.Object_Parts.Parts.Is_Empty",
            '"GetObjectAttributes MaxParts zero behavior mismatch: "',
        ],
        "GetObjectAttributes server zero-page evidence",
    )
    generator = source(MODEL_GENERATOR)
    require_once(
        generator,
        '"GetObjectAttributes": "Get object attributes operation"',
        "generated operation documentation owner",
    )
    require_once(
        source(MODEL_SPEC),
        "--  @enum Get_Object_Attributes_Operation "
        "Get object attributes operation",
        "generated operation documentation render",
    )


def verify_document() -> None:
    document = normalized(source(DOCUMENT))
    require_in_order(
        document,
        [
            normalized(
                "Qualification remains conditional on the complete "
                "`get_object_attributes` lane succeeding"
            ),
            normalized(
                "An explicit nonempty `VersionId` must be echoed exactly"
            ),
            normalized(
                "Neither observation proves the cause of a prior mutation"
            ),
            normalized(
                "An explicitly present `MaxParts=0` yields an empty "
                "terminal page"
            ),
            "--operation GetObjectAttributes",
            normalized(
                "removed exactly 54 candidate-owned warnings"
            ),
            normalized(
                "Unrelated repository GNATdoc warnings currently keep "
                "the global classifier gate closed"
            ),
        ],
        "conditional GetObjectAttributes qualification prose",
    )


def main() -> None:
    verify_model(load_model())
    verify_registry()
    verify_sources()
    verify_document()
    print(
        "GetObjectAttributes preparation: pinned model, exact attribute and "
        "pagination binding, lifecycle, registry, and conditional evidence "
        "match"
    )


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, Evidence_Error, KeyError, TypeError) as error:
        raise SystemExit(
            f"GetObjectAttributes preparation: {error}"
        ) from error
