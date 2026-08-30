#!/usr/bin/env python3
"""Fail closed on the reviewed three-operation object-tagging boundary."""

from __future__ import annotations

import copy
import hashlib
import os
import tomllib
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "coverage" / "s3-operations.toml"
DOCUMENT = ROOT / "docs" / "qualification" / "object-tagging.md"
FIXTURE = (
    ROOT / "tests" / "corpora" / "composable-client"
    / "object-tagging-certainty.tsv"
)
MODEL_SHA256 = (
    "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
)
OPERATIONS = (
    "DeleteObjectTagging",
    "GetObjectTagging",
    "PutObjectTagging",
)
ERRORS = [
    "authentication",
    "authorization",
    "not_found",
    "invalid_request",
    "unavailable_or_retryable",
    "corrupt_or_invalid_response",
]
COMMON_EVIDENCE = {
    "backend": ["tests/src/object_storage_test_cases.adb"],
    "client": [
        "src/flyology-object_storage-client-low_level.ads",
        "src/flyology-object_storage-client-low_level.adb",
        "src/flyology-object_storage-client-objects.ads",
        "src/flyology-object_storage-client-objects.adb",
        "tests/src/flyology-object_storage-client-objects-testing.adb",
        "tests/src/s3_http_socket_corpus.adb",
    ],
    "server": [
        "tests/src/s3_server_application_corpus.adb",
        "tests/src/s3_http_socket_corpus.adb",
    ],
    "corpus": [
        "tests/corpora/composable-client/object-tagging-certainty.tsv",
        "tools/verify-composable-client-fixtures.sh",
        "tools/test-composable-client-fixtures-verifier.sh",
        "tools/verify-object-tagging-preparation.py",
        "docs/qualification/object-tagging.md",
        "tests/src/object_storage_test_cases.adb",
        "tests/src/s3_http_socket_corpus.adb",
        "tests/src/s3_implementation_corpus.adb",
        "tests/src/s3_server_application_corpus.adb",
    ],
}
COMMON_EXCLUSIONS = [
    "directory-bucket endpoint and session semantics, access-point, "
    "Object Lambda, and S3 on Outposts routing are not claimed",
    "same-version and current-version observations do not establish "
    "causation or authorize automatic replay",
    "external-provider behavior beyond the maintained signed "
    "implementation and socket corpus is not claimed",
]


class Evidence_Error(RuntimeError):
    """One reviewed object-tagging invariant changed."""


def fail(message: str) -> None:
    raise Evidence_Error(message)


def source(path: Path) -> str:
    if not path.is_file() or path.is_symlink():
        fail(f"missing or unsafe source: {path}")
    raw = path.read_bytes()
    if b"\r" in raw:
        fail(f"noncanonical CR byte: {path}")
    return raw.decode("utf-8")


def require_once(text: str, fragment: str, label: str) -> None:
    count = text.count(fragment)
    if count != 1:
        fail(f"{label}: expected one occurrence, found {count}: {fragment!r}")


def require_in_order(
    text: str, fragments: list[str] | tuple[str, ...], label: str
) -> None:
    position = 0
    for fragment in fragments:
        position = text.find(fragment, position)
        if position < 0:
            fail(f"{label}: missing or reordered fragment: {fragment!r}")
        position += len(fragment)


def normalized(text: str) -> str:
    return " ".join(text.split())


def require_normalized_in_order(
    text: str, fragments: list[str] | tuple[str, ...], label: str
) -> None:
    require_in_order(
        normalized(text),
        [normalized(fragment) for fragment in fragments],
        label,
    )


def unique_region(text: str, start: str, end: str, label: str) -> str:
    count = text.count(start)
    if count != 1:
        fail(f"{label}: start boundary count is {count}")
    first = text.index(start)
    last = text.find(end, first + len(start))
    if last < 0:
        fail(f"{label}: end boundary is missing")
    return text[first:last + len(end)]


def expect_failure(action, label: str) -> None:
    try:
        action()
    except Evidence_Error:
        return
    fail(f"negative candidate was accepted: {label}")


def lane(name: str) -> list[list[str]]:
    slug = {
        "DeleteObjectTagging": "delete-object-tagging",
        "GetObjectTagging": "get-object-tagging",
        "PutObjectTagging": "put-object-tagging",
    }[name]
    return [
        [
            "uv",
            "run",
            "--python",
            "3.13",
            "--",
            "tools/verify-object-tagging-preparation.py",
        ],
        ["./tools/verify-composable-client-fixtures.sh"],
        ["./tools/test-composable-client-fixtures-verifier.sh"],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
        [
            "./tools/build-api-docs.sh",
            f"/private/tmp/fos-{slug}-gnatdoc",
        ],
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]


def entry(
    name: str,
    public_name: str,
    family: str,
    absence: str,
    certainty: str,
    reconciliation: str,
    server_exclusion: str,
    qualification: str,
    symbols: list[str],
) -> dict[str, object]:
    return {
        "name": name,
        "tier": "core",
        "provider": "objects",
        "family": family,
        "public_provider": "Flyology.Object_Storage.Client.Objects",
        "public_name": public_name,
        "codec": "rest_xml_and_headers",
        "absence": absence,
        "errors": ERRORS,
        "certainty": certainty,
        "reconciliation": reconciliation,
        "exclusions": [
            COMMON_EXCLUSIONS[0],
            server_exclusion,
            COMMON_EXCLUSIONS[1],
            COMMON_EXCLUSIONS[2],
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
        "evidence": COMMON_EVIDENCE,
        "decision_status": "reviewed",
        "qualification": qualification,
        "ada_symbols": symbols,
    }


MUTATION_CERTAINTY = {
    "DeleteObjectTagging": (
        "only a complete validated 204 with one nonempty text-safe version "
        "id reports Object_Tag_Mutation_Completed; an exact recognized S3 "
        "rejection or definite non-admission reports "
        "Object_Tag_Mutation_Definitely_Not_Applied, pre-admission "
        "cancellation reports Object_Tag_Mutation_Cancelled_Before_Admission, "
        "and every other possibly admitted or incomplete outcome reports "
        "Object_Tag_Mutation_Outcome_Unknown; no automatic replay"
    ),
    "PutObjectTagging": (
        "only a complete validated 200 with one nonempty text-safe version "
        "id reports Object_Tag_Mutation_Completed; an exact recognized S3 "
        "rejection or definite non-admission reports "
        "Object_Tag_Mutation_Definitely_Not_Applied, pre-admission "
        "cancellation reports Object_Tag_Mutation_Cancelled_Before_Admission, "
        "and every other possibly admitted or incomplete outcome reports "
        "Object_Tag_Mutation_Outcome_Unknown; no automatic replay"
    ),
}
MUTATION_RECONCILIATION = (
    "an explicit VersionId permits an exact same-version current-state "
    "GetObjectTagging observation and an omitted VersionId permits only a "
    "current-version observation; neither proves that the lost mutation "
    "caused the observed state or upgrades mutation certainty without "
    "caller-supplied serialization authority"
)
GET_RECONCILIATION = (
    "an explicit VersionId yields an exact same-version current-state "
    "observation and an omitted VersionId yields only a current-version "
    "observation; neither proves causation or upgrades any prior mutation "
    "certainty without caller-supplied serialization authority"
)
EXPECTED = {
    "DeleteObjectTagging": entry(
        "DeleteObjectTagging",
        "Delete_Tags",
        "bodyless_mutation",
        "not_applicable",
        MUTATION_CERTAINTY["DeleteObjectTagging"],
        MUTATION_RECONCILIATION,
        "configured server Requester Pays accounting and SDK checksum "
        "execution remain explicit typed capability exclusions; exact "
        "client control construction remains covered",
        "delete_object_tagging",
        [
            "Prepare_Delete_Object_Tagging",
            "Decode_Delete_Object_Tagging_Response",
            "Execute_Delete_Object_Tagging",
            "Delete_Object_Tagging_Operation",
            "Delete_Tags",
            "Finish",
        ],
    ),
    "GetObjectTagging": entry(
        "GetObjectTagging",
        "Get_Tags",
        "bounded_rest_xml_read",
        "an existing selected version with no tags returns one successful "
        "empty TagSet; a missing bucket, key, or selected version is a "
        "structured typed rejection",
        "read_only",
        GET_RECONCILIATION,
        "configured server Requester Pays accounting remains an explicit "
        "typed capability exclusion; exact client control construction "
        "remains covered",
        "get_object_tagging",
        [
            "Prepare_Get_Object_Tagging",
            "Decode_Get_Object_Tagging_Response",
            "Execute_Get_Object_Tagging",
            "Get_Object_Tagging_Operation",
            "Get_Tags",
            "Finish",
        ],
    ),
    "PutObjectTagging": entry(
        "PutObjectTagging",
        "Put_Tags",
        "rest_xml_mutation",
        "not_applicable",
        MUTATION_CERTAINTY["PutObjectTagging"],
        MUTATION_RECONCILIATION,
        "configured server Requester Pays accounting and SDK checksum "
        "execution remain explicit typed capability exclusions; exact "
        "Content-MD5 and client generated-checksum construction remain "
        "covered",
        "put_object_tagging",
        [
            "Prepare_Put_Object_Tagging",
            "Decode_Put_Object_Tagging_Response",
            "Execute_Put_Object_Tagging",
            "Put_Object_Tagging_Operation",
            "Put_Tags",
            "Finish",
        ],
    ),
}


def registry_data() -> dict[str, object]:
    return tomllib.loads(source(REGISTRY))


def verify_registry(data: dict[str, object]) -> None:
    entries = data.get("operation")
    qualifications = data.get("qualification")
    if not isinstance(entries, list) or not isinstance(qualifications, dict):
        fail("registry top-level structure changed")
    selected = [item for item in entries if item.get("name") in OPERATIONS]
    if len(selected) != 3:
        fail("registry must contain exactly three object-tagging entries")
    by_name = {item["name"]: item for item in selected}
    if set(by_name) != set(OPERATIONS):
        fail("object-tagging operation inventory changed")
    for name in OPERATIONS:
        if by_name[name] != EXPECTED[name]:
            fail(f"{name}: reviewed registry entry changed")
        lane_name = str(EXPECTED[name]["qualification"])
        if qualifications.get(lane_name) != lane(name):
            fail(f"{name}: qualification lane changed")


def verify_model() -> None:
    value = os.environ.get("FLYOLOGY_S3_SERVICE_MODEL")
    if not value:
        fail("FLYOLOGY_S3_SERVICE_MODEL is not set")
    path = Path(value)
    if not path.is_file() or path.is_symlink():
        fail("pinned model is not one regular non-symlink file")
    if hashlib.sha256(path.read_bytes()).hexdigest() != MODEL_SHA256:
        fail("pinned model digest changed")


def verify_source_facts() -> None:
    low_spec = source(
        ROOT / "src" / "flyology-object_storage-client-low_level.ads"
    )
    low_body = source(
        ROOT / "src" / "flyology-object_storage-client-low_level.adb"
    )
    objects_spec = source(
        ROOT / "src" / "flyology-object_storage-client-objects.ads"
    )
    objects_body = source(
        ROOT / "src" / "flyology-object_storage-client-objects.adb"
    )
    direct = source(ROOT / "tests" / "src" / "object_storage_test_cases.adb")
    socket = source(ROOT / "tests" / "src" / "s3_http_socket_corpus.adb")
    operation_types = {
        "DeleteObjectTagging": (
            "One-shot DeleteObjectTagging parent with nonreplayable empty "
            "source."
        ),
        "GetObjectTagging": (
            "One bounded read-only GetObjectTagging parent with one HTTP "
            "child."
        ),
        "PutObjectTagging": (
            "One-shot PutObjectTagging parent owning its serialized tag "
            "document."
        ),
    }
    for operation, summary in operation_types.items():
        ada = operation.replace("ObjectTagging", "_Object_Tagging")
        require_once(low_spec, f"function Prepare_{ada}", operation)
        require_once(low_spec, f"function Execute_{ada}", operation)
        type_name = f"type {ada}_Operation"
        if objects_spec.count(type_name) != 2:
            fail(f"{operation}: public/private type inventory changed")
        public_start = f"   --  {summary}\n   {type_name}"
        private_start = f"   --  @exclude\n   {type_name}"
        public_region = unique_region(
            objects_spec,
            public_start,
            "with private;",
            f"{operation} visible incomplete type",
        )
        private_region = unique_region(
            objects_spec,
            private_start,
            "   end record;",
            f"{operation} private full type",
        )
        if objects_spec.index(public_region) >= objects_spec.index(
            private_region
        ):
            fail(f"{operation}: public/private type order changed")
        if public_region.count(type_name) != 1:
            fail(f"{operation}: visible type declaration is malformed")
        if private_region.count(type_name) != 1:
            fail(f"{operation}: private type completion is malformed")
    require_once(
        low_spec,
        "Requested_Object_Tagging_Version_ID :",
        "prepared exact version retention",
    )
    require_in_order(
        low_body,
        [
            'Model_Value_Of ("ContentMD5", Content_MD5 (Payload))',
            "Generate_Request_Checksum => True",
            "Result.Requested_Object_Tagging_Version_ID :=",
            "Parameters.Version_ID",
        ],
        "PutObjectTagging prepared body binding",
    )
    for operation in ("Get", "Delete"):
        require_in_order(
            low_body,
            [
                f"function Prepare_{operation}_Object_Tagging",
                "Result.Requested_Object_Tagging_Version_ID :=",
                "Parameters.Version_ID",
            ],
            f"{operation}ObjectTagging exact version retention",
        )
    for fragment in (
        "invalid object tagging version header multiplicity",
        "not Valid_List_Response_Header_Text (Value)",
        "not S3.Deletions.Valid_Version_ID (Value)",
        "Version_ID /= Requested_Version_ID",
        "object tagging response does not match prepared request",
    ):
        if fragment not in low_body:
            fail(f"synchronous response binding changed: {fragment!r}")
    for fragment in (
        "function Tagging_Version_ID",
        "Character'Pos (Item) >= 16#20#",
        "Character'Pos (Item) /= 16#7F#",
        "Value /= Expected",
    ):
        if fragment not in objects_body:
            fail(f"composable tagging contract changed: {fragment!r}")
    normalization_regions = {
        "PutObjectTagging": unique_region(
            objects_body,
            "   function Normalize_Put_Object_Tagging_Response",
            "   end Normalize_Put_Object_Tagging_Response;",
            "PutObjectTagging response normalization",
        ),
        "GetObjectTagging": unique_region(
            objects_body,
            "   function Normalize_Get_Object_Tagging_Response",
            "   end Normalize_Get_Object_Tagging_Response;",
            "GetObjectTagging response normalization",
        ),
        "DeleteObjectTagging": unique_region(
            objects_body,
            "   function Normalize_Delete_Object_Tagging_Response",
            "   end Normalize_Delete_Object_Tagging_Response;",
            "DeleteObjectTagging response normalization",
        ),
    }
    put_normalization = normalization_regions["PutObjectTagging"]
    get_normalization = normalization_regions["GetObjectTagging"]
    delete_normalization = normalization_regions["DeleteObjectTagging"]
    for fragment in (
        "Conclusive_Object_Tag_Rejection (Value.Status, Code, True)",
        "Object_Tag_Response_Failure (Value.Status, Code, True)",
    ):
        if put_normalization.count(fragment) != 1:
            fail(f"PutObjectTagging normalization changed: {fragment!r}")
    for fragment in (
        "Object_Tag_Read_Response_Failure",
        "Object_Tag_Response_Failure (Value.Status, Code, False)",
        "Conclusive_Object_Tag_Rejection (Value.Status, Code, False)",
    ):
        if fragment in put_normalization:
            fail(f"PutObjectTagging normalization leaked: {fragment!r}")
    get_call = "Object_Tag_Read_Response_Failure (Value.Status, Code)"
    if get_normalization.count(get_call) != 1:
        fail("GetObjectTagging read normalization changed")
    for fragment in (
        "Object_Tag_Response_Failure",
        "Conclusive_Object_Tag_Rejection",
    ):
        if fragment in get_normalization:
            fail(f"GetObjectTagging mutation normalization leaked: {fragment}")
    for fragment in (
        "Conclusive_Object_Tag_Rejection (Value.Status, Code, False)",
        "Object_Tag_Response_Failure (Value.Status, Code, False)",
    ):
        if delete_normalization.count(fragment) != 1:
            fail(f"DeleteObjectTagging normalization changed: {fragment!r}")
    for fragment in (
        "Object_Tag_Read_Response_Failure",
        "Object_Tag_Response_Failure (Value.Status, Code, True)",
        "Conclusive_Object_Tag_Rejection (Value.Status, Code, True)",
    ):
        if fragment in delete_normalization:
            fail(f"DeleteObjectTagging normalization leaked: {fragment!r}")
    direct_region = unique_region(
        direct,
        "   procedure Check_Low_Level_Object_Tagging",
        "   end Check_Low_Level_Object_Tagging;",
        "direct object-tagging preparation evidence",
    )
    require_in_order(
        direct_region,
        [
            "Document : constant String :=",
            "Flyology.Object_Storage.S3.Tagging.Serialize (Tags);",
            "SHA256_Digest : constant String :=",
            "MD5_Digest : constant String :=",
            '"content-md5"',
            '"x-amz-checksum-sha256"',
            '"x-amz-checksum-sha256:" & SHA256_Digest & ASCII.LF',
            '"content-md5:" & MD5_Digest & ASCII.LF',
        ],
        "exact PutObjectTagging checksum evidence",
    )
    for prefix, operation, status in (
        ("Put", "PutObjectTagging", "200"),
        ("Get", "GetObjectTagging", "200"),
        ("Delete", "DeleteObjectTagging", "204"),
    ):
        region = unique_region(
            socket,
            f"               procedure Run_{prefix}_Tagging_Cancellation is",
            f"               end Run_{prefix}_Tagging_Cancellation;",
            f"{operation} cancellation campaign",
        )
        for other in OPERATIONS:
            if other != operation and other in region:
                fail(f"{operation}: contains {other} evidence")
        if region.count(
            "Cancel_Set : aliased Operations.Completion_Set (5);"
        ) != 1:
            fail(f"{operation}: Completion_Set inventory changed")
        if region.count("Finish (Operation, Result);") != 2:
            fail(f"{operation}: typed Finish inventory changed")
        if region.count("Flyology.IO.Finish (Drain_Ready);") != 1:
            fail(f"{operation}: drain completion changed")
        owner_head = f'"{operation} restart changed a " &'
        owner_tail = '"retained owner";'
        if region.count(owner_head) != 2 or region.count(owner_tail) != 2:
            fail(f"{operation}: owner-substitution evidence changed")
        require_in_order(
            region,
            [
                "Operations.Cancel (Operation);",
                "Operations.Wait_All (Cancel_Set);",
                "Finish (Operation, Result);",
                "Flyology.IO.Finish (Drain_Ready);",
                owner_head,
                owner_tail,
                owner_head,
                owner_tail,
                "Operations.Wait_All (Cancel_Set);",
                "Finish (Operation, Result);",
                f"Result.Response.Status /= {status}",
                f'"same-object {operation} restart mismatch"',
            ],
            f"{operation} cancellation and restart order",
        )


def verify_fixture() -> None:
    lines = source(FIXTURE).splitlines()
    header = (
        "operation\thttp_result\tadmission\tstatus\ts3_code\t"
        "disposition\tfailure_reason\treconcile\tselection\tnote"
    )
    if len(lines) != 51 or lines[0] != header:
        fail("object-tagging certainty fixture geometry changed")
    rows = lines[1:]
    if len(rows) != len(set(rows)):
        fail("object-tagging certainty fixture contains a duplicate")
    counts = Counter(row.split("\t", 1)[0] for row in rows)
    if counts != Counter(
        {
            "PutObjectTagging": 17,
            "GetObjectTagging": 16,
            "DeleteObjectTagging": 17,
        }
    ):
        fail("object-tagging certainty operation inventory changed")
    required = [
        "exact same-version current-state observation, not causal proof",
        "current-version observation only, with no mutation certainty",
        "possibly admitted mutation is never replayed",
        "put-only checksum error is not delete evidence",
        "put-only checksum error is not a read contract",
    ]
    for fragment in required:
        if not any(fragment in row for row in rows):
            fail(f"object-tagging certainty fact changed: {fragment!r}")


def verify_document() -> None:
    document = source(DOCUMENT)
    require_normalized_in_order(
        document,
        [
            "Each operation is qualified only when its complete registered "
            "lane succeeds.",
            "region-scoped documentation measurement",
            "Repository-wide and selected-operation qualification remain "
            "blocked",
            "This record does not convert that measurement into a "
            "qualification claim.",
            "Those retained results remain evidence only until every "
            "registered lane",
        ],
        "conditional qualification prose",
    )


def verify_negatives(data: dict[str, object]) -> None:
    missing = copy.deepcopy(data)
    missing["operation"] = [
        item
        for item in missing["operation"]
        if item["name"] != "PutObjectTagging"
    ]
    expect_failure(lambda: verify_registry(missing), "missing operation")

    duplicate = copy.deepcopy(data)
    duplicate["operation"].append(
        copy.deepcopy(EXPECTED["GetObjectTagging"])
    )
    expect_failure(lambda: verify_registry(duplicate), "duplicate operation")

    mixed = copy.deepcopy(data)
    for item in mixed["operation"]:
        if item["name"] == "GetObjectTagging":
            item["qualification"] = "delete_object_tagging"
    expect_failure(lambda: verify_registry(mixed), "mixed lane association")

    cross_family = copy.deepcopy(data)
    for item in cross_family["operation"]:
        if item["name"] == "DeleteObjectTagging":
            item["family"] = "rest_xml_mutation"
    expect_failure(lambda: verify_registry(cross_family), "cross-family drift")

    malformed = copy.deepcopy(data)
    malformed["qualification"]["put_object_tagging"][0].pop()
    expect_failure(lambda: verify_registry(malformed), "malformed command")

    causal = copy.deepcopy(data)
    for item in causal["operation"]:
        if item["name"] == "PutObjectTagging":
            item["reconciliation"] = "same-version observation proves cause"
    expect_failure(lambda: verify_registry(causal), "causal overclaim")


def main() -> int:
    verify_model()
    data = registry_data()
    verify_registry(data)
    verify_source_facts()
    verify_fixture()
    verify_document()
    verify_negatives(data)
    print("Object tagging preparation evidence: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
