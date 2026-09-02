#!/usr/bin/env python3
"""Fail-closed source oracle for the RenameObject rejection profile."""

from __future__ import annotations

import copy
import pathlib
import tomllib


ROOT = pathlib.Path(__file__).resolve().parents[1]
REGISTRY_PATH = ROOT / "coverage" / "s3-operations.toml"
SERVER_SPEC_PATH = ROOT / "src" / (
    "flyology-object_storage-server-s3_applications.ads"
)
SERVER_BODY_PATH = ROOT / "src" / (
    "flyology-object_storage-server-s3_applications.adb"
)
CORPUS_PATH = ROOT / "tests" / "src" / "s3_server_application_corpus.adb"
BACKEND_PATH = ROOT / "src" / "flyology-object_storage-backends.ads"
CORE_TESTS_PATH = ROOT / "tests" / "src" / "object_storage_test_cases.adb"
SQLITE_TESTS_PATH = ROOT / "sqlite" / "tests" / "src" / (
    "flyology_object_storage_sqlite_tests.adb"
)
PROSE_PATH = ROOT / "docs" / "qualification" / "rename-object.md"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def unique_region(source: str, start: str, end: str, label: str) -> str:
    require(source.count(start) == 1, f"{label}: start boundary")
    first = source.index(start)
    require(source.count(end, first + len(start)) == 1,
            f"{label}: end boundary")
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
        item for item in registry["operation"]
        if item["name"] == "RenameObject"
    ]
    require(len(entries) == 1, "RenameObject registry uniqueness")
    return entries[0]


EXPECTED_LANE = [
    ["uv", "run", "--python", "3.13", "--",
     "tools/verify-rename-object-preparation.py"],
    ["uv", "run", "--python", "3.13", "--",
     "tests/scripts/verify-rename-object-model.py"],
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
    require(entry["codec"] == "private_strict_rename_negative_capability",
            "RenameObject codec profile")
    require(entry["coverage"] == {
        "backend": "covered",
        "client": "partial",
        "server": "covered",
        "corpus": "covered",
    }, "RenameObject coverage")
    require(entry["provenance"] == {
        "backend": "shared_family",
        "client": "generated",
        "server": "handwritten",
        "tests": "handwritten",
    }, "RenameObject provenance")
    require(entry["implementation_mode"] == "generated",
            "RenameObject implementation mode")
    require(entry["evidence_tokens"] == ["Head_Bucket"],
            "shared backend evidence token")
    require(entry["evidence"]["backend"] == [
        "src/flyology-object_storage-backends.ads",
        "tests/src/object_storage_test_cases.adb",
        "sqlite/tests/src/flyology_object_storage_sqlite_tests.adb",
    ], "shared backend evidence")
    require(entry["evidence"]["server"] == [
        "src/flyology-object_storage-server-s3_applications.ads",
        "src/flyology-object_storage-server-s3_applications.adb",
        "tests/src/s3_server_application_corpus.adb",
    ], "server evidence")
    require(entry["evidence"]["corpus"] == [
        "tests/scripts/verify-rename-object-model.py",
        "tools/verify-rename-object-preparation.py",
        "docs/qualification/rename-object.md",
        "tests/src/s3_server_application_corpus.adb",
    ], "corpus evidence")
    require("never accepts or completes a rename" in entry["certainty"],
            "negative mutation certainty")
    require("no automatic replay" in entry["certainty"],
            "no-replay certainty")
    require("never persisted or bound" in entry["reconciliation"],
            "no token binding")
    require("does not prove rename causation" in entry["reconciliation"],
            "no causal reconciliation")
    exclusions = " ".join(entry["exclusions"])
    for fact in [
        "no Low_Level or Objects RenameObject API",
        "same-bucket object RenameSource",
        "existing bucket returns NotImplemented",
        "no source or destination object lookup",
        "never evaluated",
        "no operation-specific token length cap",
        "IdempotencyParameterMismatch",
        "external-provider interoperability",
    ]:
        require(fact in exclusions, f"missing exclusion: {fact}")
    require(registry["qualification"]["rename_object"] == EXPECTED_LANE,
            "RenameObject qualification lane")


def assert_sources(server_spec: str, server_body: str, corpus: str,
                   backend: str, core_tests: str, sqlite_tests: str,
                   prose: str) -> None:
    query = unique_region(
        server_body,
        "Is_Rename_Object_Query : constant Boolean :=",
        "Is_Get_Bucket_Location_Query : constant Boolean :=",
        "RenameObject query",
    )
    require_in_order(query, [
        'Method = "PUT"',
        'Query_Text = "renameObject"',
        'Query_Text = "renameObject="',
        'Query_Text = "renameObject=&x-id=RenameObject"',
        'Query_Text = "x-id=RenameObject&renameObject="',
    ], "exact RenameObject query forms")

    route = unique_region(
        server_body, "when Rename_Object =>", "when Copy_Object =>",
        "RenameObject route",
    )
    require_in_order(route, [
        'Source_Name : constant String := "x-amz-rename-source"',
        'Token_Name  : constant String := "x-amz-client-token"',
        '"if-match"',
        '"if-none-match"',
        '"if-modified-since"',
        '"if-unmodified-since"',
        '"x-amz-rename-source-if-match"',
        '"x-amz-rename-source-if-none-match"',
        '"x-amz-rename-source-if-modified-since"',
        '"x-amz-rename-source-if-unmodified-since"',
        "Duplicate_Control_Header",
        "Valid_Entity_Tag_Header",
        "Valid_Date_Header",
        "Requests.Parse_Target",
        "Requests.Bucket_Name",
        "Source_Bucket /= Bucket",
        "Valid_Header_Text",
        "Store.Head_Bucket",
        '501, "NotImplemented"',
    ], "RenameObject route ordering")
    for forbidden in [
        "Store.Copy_Object",
        "Store.Delete_Object",
        "Store.Head_Object",
        "Apps.Respond (X, 200",
        "IdempotencyParameterMismatch",
        "Evaluate_",
        "Maximum_Rename",
        "Token'Length >",
    ]:
        require(forbidden not in route,
                f"RenameObject route invented behavior: {forbidden}")
    require(route.count("Store.") == 1,
            "RenameObject route gained another backend operation")

    routing = unique_region(
        server_body,
        "Target_Text : constant String := Apps.Request_Target (X);",
        "if Operation not in Create_Bucket | Put_Bucket_Tagging |",
        "RenameObject authenticated routing",
    )
    require_in_order(routing, [
        '"renameObject"',
        '"&x-id=RenameObject&"',
        "Rename_Object_Query_Invalid",
        "Rename_Object",
        "Auth := Authentication.Verify_Request",
        '"The RenameObject request query is invalid"',
    ], "RenameObject authentication and query order")

    corpus_region = unique_region(
        corpus,
        '   declare\n      Query : constant SigV4.Name_Value_Array :=\n'
        '        (1 => SigV4.Pair ("renameObject", ""));',
        '   declare\n      Document : constant String :=\n'
        '        "<RestoreRequest><Days>1</Days></RestoreRequest>";',
        "RenameObject corpus",
    )
    require_in_order(corpus_region, [
        'SigV4.Pair ("renameObject", "")',
        '"x-amz-rename-source: /test-bucket/object"',
        '"501 Not Implemented"',
        '"<Code>NotImplemented</Code>"',
        'SigV4.Pair ("x-id", "RenameObject")',
        'Raw_Query => "renameObject"',
        'Raw_Query => "x-id=RenameObject&renameObject="',
        'Raw_Query => "x-id=RenameObject"',
        'Raw_Query => "renameObject=&renameObject="',
        '"<Code>NoSuchBucket</Code>"',
        '"RenameObject query validation preceded authentication"',
        '"RenameObject header validation preceded authentication"',
        '"RenameObject accepted a missing source"',
        '"RenameObject accepted duplicate sources"',
        '"RenameObject accepted an empty source"',
        '"RenameObject accepted a cross-bucket source"',
        '"RenameObject accepted a source query"',
        '"RenameObject accepted an unmodeled source control"',
        '"RenameObject accepted an empty client token"',
        '"RenameObject accepted a duplicate client token"',
        "Long_Token'Length > 64",
        '"RenameObject invented an operation-specific client-token cap"',
        '"RenameObject accepted malformed " & Name',
        '"RenameObject accepted duplicate " & Name',
        '"RenameObject rejected valid inactive controls"',
        '"RenameObject inspected source existence"',
        '"RenameObject accepted a request body"',
        '"RenameObject body validation preceded authentication"',
        '"rejected RenameObject changed its source"',
        '"rejected RenameObject created its destination"',
    ], "signed RenameObject corpus")
    require(corpus_region.count(
        '"RenameObject accepted malformed " & Name') == 2,
        "ETag and date malformed-condition loops")
    require(corpus_region.count(
        '"RenameObject accepted duplicate " & Name') == 2,
        "ETag and date duplicate-condition loops")
    for name in [
        "if-match", "if-none-match", "if-modified-since",
        "if-unmodified-since", "x-amz-rename-source-if-match",
        "x-amz-rename-source-if-none-match",
        "x-amz-rename-source-if-modified-since",
        "x-amz-rename-source-if-unmodified-since",
    ]:
        require(corpus_region.count(f'"{name}') == 2,
                f"valid and invalid coverage for {name}")

    require("validated negative-capability RenameObject routing" in
            server_spec, "RenameObject server specification boundary")
    require("procedure Head_Bucket" in backend,
            "shared Head_Bucket contract")
    require("Store.Head_Bucket" in core_tests,
            "memory/files Head_Bucket evidence")
    require("Store.Head_Bucket" in sqlite_tests,
            "SQLite Head_Bucket evidence")

    normalized = " ".join(prose.split())
    for fact in [
        "Not_Exposed",
        "NoSuchBucket",
        "NotImplemented",
        "Conditions are never evaluated",
        "never reports success",
        "no operation-specific token length limit",
        "does not claim directory-bucket persistence",
    ]:
        require(fact in normalized, f"qualification prose: {fact}")


def reject_registry(candidate: dict, label: str) -> None:
    try:
        assert_registry(candidate)
    except AssertionError:
        return
    raise AssertionError(f"{label} registry mutation accepted")


def reject_source(server_spec: str, server_body: str, corpus: str,
                  backend: str, core_tests: str, sqlite_tests: str,
                  prose: str, label: str) -> None:
    try:
        assert_sources(server_spec, server_body, corpus, backend, core_tests,
                       sqlite_tests, prose)
    except AssertionError:
        return
    raise AssertionError(f"{label} source mutation accepted")


def main() -> None:
    registry = tomllib.loads(REGISTRY_PATH.read_text())
    server_spec = SERVER_SPEC_PATH.read_text()
    server_body = SERVER_BODY_PATH.read_text()
    corpus = CORPUS_PATH.read_text()
    backend = BACKEND_PATH.read_text()
    core_tests = CORE_TESTS_PATH.read_text()
    sqlite_tests = SQLITE_TESTS_PATH.read_text()
    prose = PROSE_PATH.read_text()

    assert_registry(registry)
    assert_sources(server_spec, server_body, corpus, backend, core_tests,
                   sqlite_tests, prose)

    for label, mutate in [
        ("invented public API",
         lambda item: item.update(public_name="Rename_Object")),
        ("invented complete client",
         lambda item: item["coverage"].update(client="covered")),
        ("missing backend evidence",
         lambda item: item["evidence"].update(backend=[])),
        ("missing server evidence",
         lambda item: item["evidence"].update(server=[])),
        ("invented rename success",
         lambda item: item.update(certainty="rename completed with 200")),
        ("invented condition enforcement",
         lambda item: item["exclusions"].__setitem__(
             3, "all preconditions are evaluated atomically")),
        ("invented client-token idempotency",
         lambda item: item.update(
             reconciliation="client token proves completion")),
    ]:
        candidate = copy.deepcopy(registry)
        mutate(operation(candidate))
        reject_registry(candidate, label)

    duplicate_lane = copy.deepcopy(registry)
    duplicate_lane["qualification"]["rename_object"].append(
        ["./tests/scripts/test.sh"]
    )
    reject_registry(duplicate_lane, "duplicate root test")

    route = unique_region(
        server_body, "when Rename_Object =>", "when Copy_Object =>",
        "RenameObject route mutation scope",
    )
    corpus_region = unique_region(
        corpus,
        '   declare\n      Query : constant SigV4.Name_Value_Array :=\n'
        '        (1 => SigV4.Pair ("renameObject", ""));',
        '   declare\n      Document : constant String :=\n'
        '        "<RestoreRequest><Days>1</Days></RestoreRequest>";',
        "RenameObject corpus mutation scope",
    )
    copied_route = route.replace("Store.Head_Bucket", "Store.Copy_Object", 1)
    successful_route = route.replace(
        'Send_Error\n                       (X, 501, "NotImplemented"',
        'Apps.Respond\n                       (X, 200, ""', 1,
    )
    no_auth_corpus = corpus_region.replace(
        "RenameObject query validation preceded authentication",
        "RenameObject query validation order", 1,
    )
    no_state_corpus = corpus_region.replace(
        "rejected RenameObject changed its source",
        "rejected RenameObject source check", 1,
    )
    capped_token_corpus = corpus_region.replace(
        "Long_Token'Length > 64", "Long_Token'Length > 32", 1,
    )
    no_missing_source_corpus = corpus_region.replace(
        "RenameObject inspected source existence",
        "RenameObject source existence", 1,
    )
    no_body_auth_corpus = corpus_region.replace(
        "RenameObject body validation preceded authentication",
        "RenameObject body validation order", 1,
    )
    mutations = [
        ("mutation call", server_body.replace(route, copied_route, 1), corpus),
        ("invented success",
         server_body.replace(route, successful_route, 1), corpus),
        ("missing authentication-order case", server_body,
         corpus.replace(corpus_region, no_auth_corpus, 1)),
        ("missing state-preservation case", server_body,
         corpus.replace(corpus_region, no_state_corpus, 1)),
        ("missing no-cap token case", server_body,
         corpus.replace(corpus_region, capped_token_corpus, 1)),
        ("missing absent-source case", server_body,
         corpus.replace(corpus_region, no_missing_source_corpus, 1)),
        ("missing body authentication case", server_body,
         corpus.replace(corpus_region, no_body_auth_corpus, 1)),
    ]
    for label, bad_server, bad_corpus in mutations:
        require((bad_server, bad_corpus) != (server_body, corpus),
                f"{label}: mutation guard")
        reject_source(server_spec, bad_server, bad_corpus, backend,
                      core_tests, sqlite_tests, prose, label)

    print("RenameObject negative-capability preparation evidence: OK")


if __name__ == "__main__":
    main()
