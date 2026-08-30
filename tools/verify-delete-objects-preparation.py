#!/usr/bin/env python3
"""Fail closed on the reviewed DeleteObjects qualification boundary."""

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
FIXTURE_SHA256 = (
    "d078b0233c87651c588bf09b6ed51a90b918581b64dd23802b8b5482e20f8a67"
)
REGISTRY = ROOT / "coverage" / "s3-operations.toml"
LOW_SPEC = ROOT / "src" / "flyology-object_storage-client-low_level.ads"
LOW_BODY = ROOT / "src" / "flyology-object_storage-client-low_level.adb"
OBJECTS_SPEC = ROOT / "src" / "flyology-object_storage-client-objects.ads"
OBJECTS_BODY = ROOT / "src" / "flyology-object_storage-client-objects.adb"
DIRECT_TEST = ROOT / "tests" / "src" / "object_storage_test_cases.adb"
SOCKET = ROOT / "tests" / "src" / "s3_http_socket_corpus.adb"
FIXTURE = (
    ROOT
    / "tests"
    / "corpora"
    / "composable-client"
    / "delete-objects-certainty.tsv"
)
FIXTURE_VERIFY = ROOT / "tools" / "verify-composable-client-fixtures.sh"
FIXTURE_NEGATIVE = (
    ROOT / "tools" / "test-composable-client-fixtures-verifier.sh"
)
DOCUMENT = ROOT / "docs" / "qualification" / "delete-objects.md"


class Evidence_Error(RuntimeError):
    """One reviewed DeleteObjects invariant changed."""


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


def require_in_order(
    text: str, fragments: list[str] | tuple[str, ...], label: str
) -> None:
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
        fail(f"{label}: end boundary is missing")
    return text[first : finish + len(end)]


def normalized(text: str) -> str:
    return " ".join(text.split())


def expect_failure(action, label: str) -> None:
    try:
        action()
    except (Evidence_Error, AssertionError, KeyError, TypeError):
        return
    fail(f"negative candidate was accepted: {label}")


def load_model() -> dict[str, object]:
    model_path = os.environ.get("FLYOLOGY_S3_SERVICE_MODEL", "")
    if not model_path:
        fail("FLYOLOGY_S3_SERVICE_MODEL is required")
    path = Path(model_path)
    source(path)
    if digest(path) != MODEL_SHA256:
        fail("pinned S3 model hash changed")
    return json.loads(path.read_text(encoding="utf-8"))


def verify_model(model: dict[str, object]) -> None:
    operation = model["operations"]["DeleteObjects"]
    shapes = model["shapes"]
    assert operation["http"] == {
        "method": "POST",
        "requestUri": "/{Bucket}?delete",
    }
    assert operation["input"] == {"shape": "DeleteObjectsRequest"}
    assert operation["output"] == {"shape": "DeleteObjectsOutput"}
    assert operation["httpChecksum"] == {
        "requestAlgorithmMember": "ChecksumAlgorithm",
        "requestChecksumRequired": True,
    }
    request = shapes["DeleteObjectsRequest"]
    assert request["required"] == ["Bucket", "Delete"]
    assert list(request["members"]) == [
        "Bucket",
        "Delete",
        "MFA",
        "RequestPayer",
        "BypassGovernanceRetention",
        "ExpectedBucketOwner",
        "ChecksumAlgorithm",
    ]
    assert request["payload"] == "Delete"
    delete = shapes["Delete"]
    assert delete["required"] == ["Objects"]
    assert list(delete["members"]) == ["Objects", "Quiet"]
    identifier = shapes["ObjectIdentifier"]
    assert identifier["required"] == ["Key"]
    assert list(identifier["members"]) == [
        "Key",
        "VersionId",
        "ETag",
        "LastModifiedTime",
        "Size",
    ]
    assert list(shapes["DeleteObjectsOutput"]["members"]) == [
        "Deleted",
        "RequestCharged",
        "Errors",
    ]
    assert list(shapes["DeletedObject"]["members"]) == [
        "Key",
        "VersionId",
        "DeleteMarker",
        "DeleteMarkerVersionId",
    ]
    assert list(shapes["Error"]["members"]) == [
        "Key",
        "VersionId",
        "Code",
        "Message",
    ]


def expected_lane() -> list[list[str]]:
    return [
        [
            "uv",
            "run",
            "--python",
            "3.13",
            "--",
            "tools/verify-delete-objects-preparation.py",
        ],
        ["./tools/verify-composable-client-fixtures.sh"],
        ["./tools/test-composable-client-fixtures-verifier.sh"],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
        [
            "./tools/build-api-docs.sh",
            "/private/tmp/fos-delete-objects-gnatdoc",
        ],
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]


def expected_entry() -> dict[str, object]:
    return {
        "name": "DeleteObjects",
        "tier": "core",
        "provider": "objects",
        "family": "rest_xml_mutation",
        "public_provider": "Flyology.Object_Storage.Client.Objects",
        "public_name": "Delete_Objects",
        "codec": "rest_xml_and_headers",
        "absence": (
            "quiet responses suppress only successful requested entries; "
            "unconditioned missing selected generations remain per-entry "
            "idempotent success, while exact modeled top-level rejections "
            "remain structured non-processing results"
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
            "only a complete validated 200 whose Deleted and Error entries "
            "bind to the duplicate-preserving requested key and version "
            "multiset reports Batch_Processed; exact recognized "
            "non-applying rejections or definite non-admission report "
            "Batch_Definitely_Not_Processed, pre-admission cancellation "
            "reports Batch_Cancelled_Before_Admission, and every other "
            "possibly admitted or incomplete outcome reports "
            "Batch_Outcome_Unknown; no automatic replay"
        ),
        "reconciliation": (
            "caller-selected generation-bound HeadObject observations for "
            "every requested bucket, key, and explicit or omitted version "
            "selection before any retry; observations do not prove which "
            "batch attempt caused the current state"
        ),
        "exclusions": [
            (
                "directory-bucket endpoint and session semantics, "
                "access-point, Object Lambda, and S3 on Outposts routing "
                "are not claimed"
            ),
            (
                "configured Requester Pays accounting and active Object "
                "Lock governance enforcement remain explicit server "
                "capability exclusions"
            ),
            (
                "quiet success suppression does not weaken exact Error "
                "binding or prove whole-batch atomicity"
            ),
            (
                "files backend namespace publication may be prefix-applied "
                "after a process or storage failure, so uncertain batches "
                "require caller reconciliation"
            ),
        ],
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
        "evidence": {
            "backend": [
                "tests/src/object_storage_test_cases.adb",
                (
                    "sqlite/tests/src/"
                    "flyology_object_storage_sqlite_tests.adb"
                ),
            ],
            "client": [
                "src/flyology-object_storage-client-low_level.ads",
                "src/flyology-object_storage-client-low_level.adb",
                "src/flyology-object_storage-client-objects.ads",
                "src/flyology-object_storage-client-objects.adb",
                (
                    "tests/src/"
                    "flyology-object_storage-client-objects-testing.adb"
                ),
                (
                    "tests/corpora/composable-client/"
                    "delete-objects-certainty.tsv"
                ),
                "tools/verify-composable-client-fixtures.sh",
                "tools/test-composable-client-fixtures-verifier.sh",
                "tests/src/s3_http_socket_corpus.adb",
            ],
            "server": [
                "tests/src/s3_server_application_corpus.adb",
                "tests/src/s3_http_socket_corpus.adb",
            ],
            "corpus": [
                (
                    "tests/corpora/composable-client/"
                    "delete-objects-certainty.tsv"
                ),
                "tools/verify-composable-client-fixtures.sh",
                "tools/test-composable-client-fixtures-verifier.sh",
                "tools/verify-delete-objects-preparation.py",
                "docs/qualification/delete-objects.md",
                "tests/src/object_storage_test_cases.adb",
                "tests/src/s3_http_socket_corpus.adb",
                "tests/src/s3_implementation_corpus.adb",
                "tests/src/s3_server_application_corpus.adb",
                "tests/scripts/run-s3-implementation.sh",
                "tests/scripts/run-s3-server-slice.sh",
            ],
        },
        "decision_status": "reviewed",
        "qualification": "delete_objects",
        "ada_symbols": [
            "Prepare_Delete_Objects",
            "Decode_Delete_Objects_Complete_Response",
            "Execute_Delete_Objects",
            "Delete_Objects_Operation",
            "Delete_Objects",
            "Finish",
        ],
    }


def delete_objects_entry(data: dict[str, object]) -> dict[str, object]:
    matches = [
        item for item in data["operation"]
        if item["name"] == "DeleteObjects"
    ]
    if len(matches) != 1:
        fail("DeleteObjects registry entry is not unique")
    return matches[0]


def verify_registry_data(data: dict[str, object]) -> None:
    if data["model_sha256"] != MODEL_SHA256:
        fail("registry model pin changed")
    if delete_objects_entry(data) != expected_entry():
        fail("DeleteObjects registry contract changed")
    if data["qualification"].get("delete_objects") != expected_lane():
        fail("DeleteObjects qualification lane changed")
    for paths in expected_entry()["evidence"].values():
        for item in paths:
            source(ROOT / item)


def verify_registry() -> None:
    data = tomllib.loads(source(REGISTRY))
    verify_registry_data(data)
    for label, mutate in [
        (
            "missing public name",
            lambda candidate: candidate["operation"][
                next(
                    index for index, item in enumerate(candidate["operation"])
                    if item["name"] == "DeleteObjects"
                )
            ].pop("public_name"),
        ),
        (
            "wrong certainty",
            lambda candidate: delete_objects_entry(candidate).__setitem__(
                "certainty", "automatic replay"
            ),
        ),
        (
            "cross-operation symbol",
            lambda candidate: delete_objects_entry(candidate)[
                "ada_symbols"
            ].__setitem__(0, "Prepare_Delete_Object"),
        ),
        (
            "missing lane command",
            lambda candidate: candidate["qualification"][
                "delete_objects"
            ].pop(0),
        ),
    ]:
        candidate = copy.deepcopy(data)
        mutate(candidate)
        expect_failure(
            lambda candidate=candidate: verify_registry_data(candidate),
            label,
        )


def verify_fixture() -> None:
    text = source(FIXTURE)
    if digest(FIXTURE) != FIXTURE_SHA256:
        fail("DeleteObjects certainty fixture changed")
    lines = text.splitlines()
    assert lines[0].split("\t") == [
        "http_result",
        "admission",
        "status",
        "s3_code",
        "disposition",
        "failure_reason",
        "reconcile",
        "note",
    ]
    rows = [tuple(line.split("\t")) for line in lines[1:]]
    assert len(lines) == 43
    assert len(rows) == 42
    keys = [row[:4] for row in rows]
    assert len(set(keys)) == 42
    assert rows[0][:7] == (
        "Response_Complete",
        "Response_Observed",
        "200",
        "none",
        "Batch_Processed",
        "No_Failure",
        "no",
    )
    cancelled = sum(
        row[4] == "Batch_Cancelled_Before_Admission" for row in rows
    )
    assert cancelled == 1
    assert all(
        (row[4] == "Batch_Outcome_Unknown") == (row[6] == "yes")
        for row in rows
    )
    verifier = source(FIXTURE_VERIFY)
    negative = source(FIXTURE_NEGATIVE)
    require_in_order(
        verifier,
        [
            "delete-objects-certainty.tsv",
            "unexpected DeleteObjects fixture header",
            "DeleteObjects fixture must contain exactly 42 rows",
            "composable client fixtures: OK",
        ],
        "fixture verifier",
    )
    for label in (
        "missing exact tuple",
        "duplicate exact tuple",
        "extra unknown tuple",
        "invalid admission pairing",
        "wrong failure reason",
        "wrong disposition relation",
        "checksum certainty leakage",
    ):
        if label not in negative:
            fail(f"fixture negative is missing: {label}")


def verify_sources() -> None:
    low_spec = unique_region(
        source(LOW_SPEC),
        "   --  Every non-Bucket/Delete member in the pinned DeleteObjects",
        "   function Execute_Delete_Objects",
        "Low_Level DeleteObjects specification",
    )
    require_in_order(
        low_spec,
        [
            "type Delete_Objects_Parameters is record",
            "function Prepare_Delete_Objects",
            "type Delete_Objects_Result is record",
            "type Delete_Objects_Outcome_Kind is",
            "type Delete_Objects_Outcome",
            "function Decode_Delete_Objects_Response",
            "function Decode_Delete_Objects_Complete_Response",
            "function Execute_Delete_Objects",
        ],
        "Low_Level public surface",
    )
    low_body = unique_region(
        source(LOW_BODY),
        "   function Prepare_Delete_Objects",
        "   end Execute_Delete_Objects;",
        "Low_Level DeleteObjects body",
    )
    require_in_order(
        low_body,
        [
            "function Valid_MFA_Header",
            "Value'Length > 2 * 1_024",
            "Character'Pos (Character_Value) < 32",
            "Character'Pos (Character_Value) = 127",
            "Flyology.HTTP.Secure_HTTPS",
            "Payload : constant String :=",
            "S3.Deletions.Serialize_Request (Request)",
            'Add ("content-md5", Content_MD5 (Payload));',
            'Add ("x-amz-mfa", US.To_String (Parameters.MFA));',
            "Checksums.Compute",
            'Add ("x-amz-sdk-checksum-algorithm", Algorithm_Text);',
            "Owned_Request_Payload",
            "function Decode_Delete_Objects_Complete_Response",
            "procedure Validate_Result_Binding",
            "Remaining : S3.Deletions.Delete_Objects_Request",
            "Remaining.Objects.Delete (Index);",
            "if Remaining.Quiet and then not Value.Deleted.Is_Empty",
            "for Item of Value.Deleted loop",
            "for Item of Value.Errors loop",
            "if not Remaining.Quiet and then not Remaining.Objects.Is_Empty",
            "return Outcome;",
            "function Execute_Delete_Objects",
            "Non_Replayable_Buffer_Source",
        ],
        "Low_Level preparation and response binding",
    )
    objects_spec = unique_region(
        source(OBJECTS_SPEC),
        "   --  @enum Batch_Processed Complete validated response",
        "   --  Shape of a terminal ListObjects v1 read.",
        "Objects DeleteObjects public surface",
    )
    require_in_order(
        objects_spec,
        [
            "type Delete_Objects_Disposition is",
            "type Delete_Objects_Result_Kind is",
            "type Delete_Objects_Result",
            "type Delete_Objects_Operation",
            "procedure Delete_Objects",
            "function Delete_Objects",
            "procedure Finish",
        ],
        "Objects public surface",
    )
    objects_body = unique_region(
        source(OBJECTS_BODY),
        "   function Normalize_Delete_Objects_Response",
        "   end Normalize_Delete_Objects_Failure;",
        "Objects DeleteObjects normalization",
    )
    require_in_order(
        objects_body,
        [
            "InvalidDigest",
            "XAmzContentSHA256Mismatch",
            "Batch_Processed",
            "Batch_Definitely_Not_Processed",
            "Batch_Outcome_Unknown",
            "Batch_Cancelled_Before_Admission",
        ],
        "DeleteObjects certainty normalization",
    )
    direct = unique_region(
        source(DIRECT_TEST),
        "   procedure Check_Low_Level_Delete_Requests",
        "   end Check_Low_Level_Delete_Requests;",
        "direct DeleteObjects tests",
    )
    require_in_order(
        direct,
        [
            "Low_Level.Prepare_Delete_Objects",
            "DeleteObjects Content-MD5 and modeled headers are signed",
            "DeleteObjects prepared MFA over insecure transport",
            "DeleteObjects prepared oversized MFA",
            "DeleteObjects prepared control-bearing MFA",
            "DeleteObjects prepared DEL-bearing MFA",
            "typed DeleteObjects success response",
            "typed DeleteObjects error response",
        ],
        "direct DeleteObjects tests",
    )
    socket = unique_region(
        source(SOCKET),
        "               procedure Run_Delete_Objects_Cancellation is",
        "               end Run_Delete_Objects_Cancellation;",
        "DeleteObjects cancellation corpus",
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
            "HTTP_Client.Possibly_Admitted",
            "Flyology.IO.Finish (Drain_Ready);",
            '"DeleteObjects restart changed a retained " &',
            '"owner";',
            '"DeleteObjects restart changed a retained " &',
            '"owner";',
            '"DeleteObjects accepted a changed owner";',
            "Operations.Wait_All (Cancel_Set);",
            "Finish (Operation, Result);",
            "Result.Response.Status /= 200",
            '"same-object DeleteObjects restart mismatch";',
        ],
        "DeleteObjects cancellation corpus",
    )
    if socket.count('"DeleteObjects restart changed a retained " &') != 2:
        fail("DeleteObjects owner-substitution assertions changed")


def verify_document() -> None:
    document = normalized(source(DOCUMENT))
    require_in_order(
        document,
        [
            normalized(
                "Qualification remains conditional on the complete "
                "`delete_objects` lane succeeding, including the "
                "repository-wide GNATdoc classifier."
            ),
            normalized(
                "Quiet mode rejects success members, binds every Error "
                "occurrence, and treats only the unreported requested "
                "entries as suppressed successes."
            ),
            normalized(
                "Generation-bound observations may inform a caller-selected "
                "retry but do not prove that one lost batch caused the "
                "current state."
            ),
            "--operation DeleteObjects",
            normalized(
                "unrelated repository GNATdoc warnings currently keep that "
                "global gate closed."
            ),
        ],
        "conditional DeleteObjects qualification prose",
    )


def main() -> None:
    verify_model(load_model())
    verify_registry()
    verify_fixture()
    verify_sources()
    verify_document()
    print(
        "DeleteObjects preparation: pinned model, exact batch binding, "
        "certainty, lifecycle, registry, and conditional evidence match"
    )


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, Evidence_Error, KeyError, TypeError) as error:
        raise SystemExit(f"DeleteObjects preparation: {error}") from error
