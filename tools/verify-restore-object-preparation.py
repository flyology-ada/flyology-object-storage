#!/usr/bin/env python3
"""Fail-closed source oracle for the local RestoreObject active-tier profile."""

from __future__ import annotations

import copy
import pathlib
import tomllib


ROOT = pathlib.Path(__file__).resolve().parents[1]
REGISTRY_PATH = ROOT / "coverage" / "s3-operations.toml"
SERVER_PATH = ROOT / "src" / (
    "flyology-object_storage-server-s3_applications.adb"
)
CORPUS_PATH = ROOT / "tests" / "src" / "s3_server_application_corpus.adb"
CONFORMANCE_PATH = ROOT / "tests" / "src" / "versioned_object_conformance.adb"
CORE_TESTS_PATH = ROOT / "tests" / "src" / "object_storage_test_cases.adb"
SQLITE_TESTS_PATH = ROOT / "sqlite" / "tests" / "src" / (
    "flyology_object_storage_sqlite_tests.adb"
)
PROSE_PATH = ROOT / "docs" / "qualification" / "restore-object.md"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def unique_region(source: str, start: str, end: str, label: str) -> str:
    require(source.count(start) == 1, f"{label}: start boundary")
    first = source.index(start)
    require(source.count(end, first + len(start)) == 1, f"{label}: end boundary")
    last = source.index(end, first + len(start))
    return source[first:last]


def require_in_order(source: str, fragments: list[str], label: str) -> None:
    cursor = 0
    for fragment in fragments:
        position = source.find(fragment, cursor)
        require(position >= 0, f"{label}: missing {fragment!r}")
        cursor = position + len(fragment)


def operation(registry: dict) -> dict:
    entries = [
        item for item in registry["operation"] if item["name"] == "RestoreObject"
    ]
    require(len(entries) == 1, "RestoreObject registry uniqueness")
    return entries[0]


def restore_corpus_region(source: str) -> str:
    return unique_region(
        source,
        '   declare\n      Document : constant String :=\n'
        '        "<RestoreRequest><Days>1</Days></RestoreRequest>";\n',
        '   declare\n      Query : constant SigV4.Name_Value_Array :=\n'
        '        (SigV4.Pair ("attributes", ""),',
        "RestoreObject corpus",
    )


EXPECTED_LANE = [
    ["uv", "run", "--python", "3.13", "--",
     "tools/verify-restore-object-preparation.py"],
    ["uv", "run", "--python", "3.13", "--",
     "tests/scripts/verify-restore-object-model.py"],
    ["uv", "run", "--python", "3.13", "--",
     "tools/test-s3-operation-registry.py"],
    ["./tests/scripts/test.sh"],
    ["./tools/verify-coverage.sh"],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]


def assert_registry(registry: dict) -> None:
    entry = operation(registry)
    require(entry["public_name"] == "Not_Exposed", "public API invented")
    require(entry["codec"] ==
            "private_strict_restore_xml_active_tier_only",
            "RestoreObject codec profile")
    require(entry["coverage"] == {
        "backend": "covered",
        "client": "partial",
        "server": "covered",
        "corpus": "covered",
    }, "RestoreObject coverage")
    require(entry["provenance"] == {
        "backend": "handwritten",
        "client": "generated",
        "server": "handwritten",
        "tests": "handwritten",
    }, "RestoreObject provenance")
    require(entry["evidence_tokens"] == ["Versioned_Object_Conformance"],
            "provider-neutral evidence token")
    require(entry["evidence"]["backend"] == [
        "tests/src/versioned_object_conformance.adb",
        "tests/src/object_storage_test_cases.adb",
        "sqlite/tests/src/flyology_object_storage_sqlite_tests.adb",
    ], "provider-neutral backend evidence")
    require(entry["evidence"]["server"] == [
        "src/flyology-object_storage-server-s3_applications.adb",
    ], "server evidence")
    require(entry["evidence"]["corpus"] == [
        "tests/src/s3_server_application_corpus.adb",
        "tests/scripts/verify-restore-object-model.py",
        "tools/verify-restore-object-preparation.py",
    ], "corpus evidence")
    require("no archival state exists" in entry["certainty"],
            "active-tier-only certainty")
    require("no automatic replay" in entry["certainty"],
            "no-replay certainty")
    require("does not prove restore causation" in entry["reconciliation"],
            "no causal reconciliation")
    exclusions = " ".join(entry["exclusions"])
    for fact in [
        "no Low_Level or Objects RestoreObject API",
        "direct Tier-only speed-up",
        "Select",
        "OutputLocation",
        "no archived state",
        "authorize automatic replay",
        "access points",
    ]:
        require(fact in exclusions, f"missing exclusion: {fact}")
    require(registry["qualification"]["restore_object"] == EXPECTED_LANE,
            "RestoreObject qualification lane")


def assert_sources(server: str, corpus: str, conformance: str,
                   core_tests: str, sqlite_tests: str, prose: str) -> None:
    parser = unique_region(
        server,
        "Maximum_Restore_Body : constant Byte_Count :=",
        "type Bucket_Policy_Assessment is",
        "RestoreObject XML parser",
    )
    require_in_order(parser, [
        "Maximum_Restore_Body",
        "XML.Default_Limits.Maximum_Document_Bytes",
        "Restore_Days_Field",
        "Restore_Job_Tier_Field",
        "Restore_Positive_Days",
        'Value in "Standard" | "Bulk" | "Expedited"',
        "GlacierJobParameters",
        "unsupported RestoreRequest member",
        "XML.XML_Error",
        "mixed RestoreRequest namespace",
        'if Local_Name /= "RestoreRequest" then',
        "Item.Job_Seen and then not Item.Days_Seen",
    ], "strict supported RestoreRequest")

    route = unique_region(
        server, "when Restore_Object =>", "when Head_Object =>",
        "RestoreObject route",
    )
    require_in_order(route, [
        'Apps.Request_Header_Count (X, "x-amz-request-payer")',
        'Apps.Request_Header_Count (X, "content-md5")',
        '"x-amz-sdk-checksum-algorithm"',
        "Checksum_Header_Count /= Value_Count",
        "Check_Expected_Bucket_Owner",
        "Verify_Document_Checksum (Document)",
        "XML.Parse",
        "Store.Head_Bucket",
        "Store.Head_Object",
        '"ObjectAlreadyInActiveTierError"',
        '"NoSuchVersion"',
    ], "RestoreObject route ordering")
    require("Apps.Respond (X, 200" not in route, "invented 200 restore")
    require("Apps.Respond (X, 202" not in route, "invented 202 restore")
    require("x-amz-request-charged" not in route,
            "success-only charged header on rejection")

    body_policy = unique_region(
        server,
        "if Operation not in Create_Bucket | Put_Bucket_Tagging |",
        "      declare\n         Bucket : constant String :=",
        "request body policy",
    )
    require_in_order(body_policy, [
        "if Operation not in Create_Bucket",
        "Put_Object | Restore_Object |",
        "Length := Body_Length (Length_OK)",
        "Apps.Apply_Body_Policy (X, Accepted)",
    ], "RestoreObject body policy")

    restore_corpus = restore_corpus_region(corpus)
    require_in_order(restore_corpus, [
        '"<RestoreRequest><Days>1</Days></RestoreRequest>"',
        'SigV4.Pair ("restore", "")',
        'SigV4.Pair ("x-id", "RestoreObject")',
        '"<Code>ObjectAlreadyInActiveTierError</Code>"',
        'SigV4.Pair ("versionId", "null")',
        'Has (Response, "404 Not Found")',
        '"<Code>NoSuchVersion</Code>"',
        '"<Code>NoSuchKey</Code>"',
        '"<Code>NoSuchBucket</Code>"',
        '"x-amz-expected-bucket-owner: different-owner"',
        '"x-amz-request-payer: invalid"',
        '"x-amz-sdk-checksum-algorithm: SHA256"',
        '"x-amz-sdk-checksum-algorithm: SHA1"',
        'Checksum_Value (Core.SHA256, "different")',
        '"content-md5: malformed"',
        'Content_MD5 ("different")',
        '"<RestoreRequest><Type>SELECT</Type>"',
        '"RestoreObject accepted mixed XML namespaces"',
        '"RestoreObject accepted GlacierJobParameters without Days"',
        '"<RestoreRequest><Tier>Standard</Tier></RestoreRequest>"',
        '"<RestoreRequest/>"',
        '"RestoreObject rejected a valid empty request"',
        '"RestoreObject accepted a duplicate restore query"',
        '"RestoreObject accepted an empty request body"',
    ], "signed RestoreObject corpus")

    require("procedure Exercise" in conformance,
            "provider-neutral conformance entry point")
    require("Store.Head_Object" in conformance,
            "provider-neutral Head_Object evidence")
    for selector in [
        "Current_Version_Selector",
        "Null_Version_Selector",
        "Exact_Version",
    ]:
        require(selector in conformance,
                f"provider-neutral selector evidence: {selector}")
    require("Versioned_Object_Conformance.Exercise" in core_tests,
            "memory/files conformance invocation")
    require("Versioned_Object_Conformance.Exercise" in sqlite_tests,
            "SQLite conformance invocation")

    normalized = " ".join(prose.split())
    for fact in [
        "Not_Exposed",
        "positive lexical Days",
        "Tier-only speed-up requests are accepted",
        "403 ObjectAlreadyInActiveTierError",
        "never reports 200 or 202",
        "memory, files, and SQLite",
        "does not claim successful restore",
    ]:
        require(fact in normalized, f"qualification prose: {fact}")


def reject_registry(candidate: dict, label: str) -> None:
    try:
        assert_registry(candidate)
    except AssertionError:
        return
    raise AssertionError(f"{label} registry mutation accepted")


def reject_source(server: str, corpus: str, label: str,
                  conformance: str, core_tests: str,
                  sqlite_tests: str, prose: str) -> None:
    try:
        assert_sources(
            server, corpus, conformance, core_tests, sqlite_tests, prose,
        )
    except AssertionError:
        return
    raise AssertionError(f"{label} source mutation accepted")


def main() -> None:
    registry = tomllib.loads(REGISTRY_PATH.read_text())
    server = SERVER_PATH.read_text()
    corpus = CORPUS_PATH.read_text()
    conformance = CONFORMANCE_PATH.read_text()
    core_tests = CORE_TESTS_PATH.read_text()
    sqlite_tests = SQLITE_TESTS_PATH.read_text()
    prose = PROSE_PATH.read_text()

    assert_registry(registry)
    assert_sources(server, corpus, conformance, core_tests, sqlite_tests, prose)

    for label, mutate in [
        ("invented public API",
         lambda item: item.update(public_name="Restore_Object")),
        ("invented complete client",
         lambda item: item["coverage"].update(client="covered")),
        ("missing backend evidence",
         lambda item: item["evidence"].update(backend=[])),
        ("invented archival success",
         lambda item: item.update(certainty="restore completed with 202")),
    ]:
        candidate = copy.deepcopy(registry)
        mutate(operation(candidate))
        reject_registry(candidate, label)

    duplicate_lane = copy.deepcopy(registry)
    duplicate_lane["qualification"]["restore_object"].append(
        ["./tests/scripts/test.sh"]
    )
    reject_registry(duplicate_lane, "duplicate root test")

    route = unique_region(
        server, "when Restore_Object =>", "when Head_Object =>",
        "RestoreObject route mutation scope",
    )
    restore_corpus = restore_corpus_region(corpus)
    wrong_lookup_route = route.replace(
        "Store.Head_Bucket", "Store.Head_Object", 1,
    )
    invented_success_route = route.replace(
        'Send_Error\n                       (X, 403, '
        '"ObjectAlreadyInActiveTierError"',
        'Apps.Respond\n                       (X, 202, '
        '"application/xml"', 1,
    )
    no_select_corpus = restore_corpus.replace(
        "<RestoreRequest><Type>SELECT</Type>", "", 1,
    )
    no_checksum_corpus = restore_corpus.replace(
        'Checksum_Value (Core.SHA256, "different")',
        'Checksum_Value (Core.SHA256, Document)', 1,
    )
    no_mixed_namespace_corpus = restore_corpus.replace(
        "RestoreObject accepted mixed XML namespaces",
        "RestoreObject accepted XML namespaces", 1,
    )
    no_job_days_corpus = restore_corpus.replace(
        "RestoreObject accepted GlacierJobParameters without Days",
        "RestoreObject accepted GlacierJobParameters", 1,
    )
    mutations = [
        ("lookup order",
         server.replace(route, wrong_lookup_route, 1), corpus),
        ("invented success",
         server.replace(route, invented_success_route, 1), corpus),
        ("missing Select rejection", server,
         corpus.replace(restore_corpus, no_select_corpus, 1)),
        ("missing checksum rejection", server,
         corpus.replace(restore_corpus, no_checksum_corpus, 1)),
        ("missing mixed namespace rejection", server,
         corpus.replace(restore_corpus, no_mixed_namespace_corpus, 1)),
        ("missing job Days rejection", server,
         corpus.replace(restore_corpus, no_job_days_corpus, 1)),
    ]
    for label, bad_server, bad_corpus in mutations:
        require((bad_server, bad_corpus) != (server, corpus),
                f"{label}: mutation guard")
        reject_source(
            bad_server, bad_corpus, label, conformance, core_tests,
            sqlite_tests, prose,
        )

    print("RestoreObject active-tier preparation evidence: OK")


if __name__ == "__main__":
    main()
