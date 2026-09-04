#!/usr/bin/env python3
"""Fail-closed source oracle for SelectObjectContent rejection coverage."""

from __future__ import annotations

import copy
import pathlib
import re
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
PROSE_PATH = ROOT / "docs" / "qualification" / (
    "select-object-content.md"
)
CLIENT_PATHS = [
    ROOT / "src" / "flyology-object_storage-client-low_level.ads",
    ROOT / "src" / "flyology-object_storage-client-low_level.adb",
    ROOT / "src" / "flyology-object_storage-client-objects.ads",
    ROOT / "src" / "flyology-object_storage-client-objects.adb",
]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def require_in_order(source: str, fragments: list[str], label: str) -> None:
    cursor = 0
    for fragment in fragments:
        position = source.find(fragment, cursor)
        require(position >= 0, f"{label}: missing {fragment!r}")
        cursor = position + len(fragment)


def case_region(source: str, alternative: str, label: str) -> str:
    start = f"            when {alternative} =>"
    require(source.count(start) == 1, f"{label}: case boundary")
    first = source.index(start)
    match = re.search(r"\n            when [A-Za-z_]+(?: \|[^=]+)? =>",
                      source[first + len(start):])
    require(match is not None, f"{label}: next case boundary")
    return source[first:first + len(start) + match.start()]


def operation(registry: dict) -> dict:
    entries = [
        item for item in registry["operation"]
        if item["name"] == "SelectObjectContent"
    ]
    require(len(entries) == 1, "SelectObjectContent registry uniqueness")
    return entries[0]


EXPECTED_LANE = [
    ["uv", "run", "--python", "3.13", "--",
     "tools/verify-select-object-content-preparation.py"],
    ["uv", "run", "--python", "3.13", "--",
     "tests/scripts/verify-select-object-content-model.py"],
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
            "private_strict_select_xml_negative_capability",
            "SelectObjectContent codec")
    require(entry["coverage"] == {
        "backend": "covered",
        "client": "partial",
        "server": "covered",
        "corpus": "covered",
    }, "SelectObjectContent coverage")
    require(entry["provenance"] == {
        "backend": "shared_family",
        "client": "generated",
        "server": "handwritten",
        "tests": "handwritten",
    }, "SelectObjectContent provenance")
    require(entry["evidence_tokens"] == ["Head_Bucket", "Head_Object"],
            "shared backend tokens")
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
        "tests/scripts/verify-select-object-content-model.py",
        "tools/verify-select-object-content-preparation.py",
        "docs/qualification/select-object-content.md",
        "tests/src/s3_server_application_corpus.adb",
    ], "corpus evidence")
    require("never executes a query" in entry["certainty"],
            "negative query certainty")
    require("no automatic replay" in entry["certainty"],
            "no-replay certainty")
    require("cannot resume" in entry["reconciliation"],
            "no resume reconciliation")
    exclusions = " ".join(entry["exclusions"])
    for fact in [
        "no Low_Level or Objects SelectObjectContent API",
        "exact POST object query with select and select-type=2",
        "body bound is derived from the maintained XML limits",
        "do not validate or default Expression",
        "never returns modeled 200 success",
        "calls only Head_Bucket and Head_Object",
        "without reading object bytes",
        "no caller-owned sink",
        "request models no VersionId",
    ]:
        require(fact in exclusions, f"missing exclusion: {fact}")
    require(registry["qualification"]["select_object_content"] ==
            EXPECTED_LANE, "SelectObjectContent qualification lane")


def assert_sources(server_spec: str, server_body: str, corpus: str,
                   backend: str, core_tests: str, sqlite_tests: str,
                   prose: str, client: str) -> None:
    require("validated negative-capability SelectObjectContent routing" in
            server_spec, "server specification boundary")
    require_in_order(server_body, [
        "Is_Select_Object_Content_Query : constant Boolean :=",
        'Query_Text = "select&select-type=2"',
        'Query_Text = "select=&select-type=2"',
        '"select&select-type=2&x-id=SelectObjectContent"',
        '"select=&select-type=2&x-id=SelectObjectContent"',
        '"x-id=SelectObjectContent&select&select-type=2"',
        '"x-id=SelectObjectContent&select=&select-type=2"',
        "Has_Select_Object_Content_Query : constant Boolean :=",
        '"&select&"',
        '"&select="',
        '"&select-type="',
        '"&x-id=SelectObjectContent&"',
    ], "exact SelectObjectContent query forms")
    require_in_order(server_body, [
        "Select_Object_Content_Query_Invalid :=",
        "Has_Select_Object_Content_Query",
        "not Is_Select_Object_Content_Query",
        "Operation := Select_Object_Content",
        "Auth := Authentication.Verify_Request",
        "elsif Select_Object_Content_Query_Invalid then",
        '"The SelectObjectContent request query is invalid"',
    ], "authenticated SelectObjectContent query routing")

    validator = server_body[
        server_body.index("type Select_XML_Validator is"):
        server_body.index("type Restore_XML_Field is")
    ]
    require_in_order(validator, [
        "overriding procedure Text",
        "Value : String) is null",
        'Local_Name /= "SelectObjectContentRequest"',
        "if not Item.Root_Seen",
        "Attribute_Count /= 0",
        "Namespace_URI /=",
        '"http://s3.amazonaws.com/doc/2006-03-01/"',
        'Local_Name /= "SelectObjectContentRequest"',
        "Item.Root_Closed := True",
    ], "strict SelectObjectContent root validator")
    require("Namespace_URI'Length > 0" not in validator,
            "empty SelectObjectContent namespace accepted")

    route = case_region(server_body, "Select_Object_Content",
                        "SelectObjectContent route")
    require_in_order(route, [
        "function Has_Unmodeled_Encryption_Header return Boolean is",
        "Apps.Request_Header_Name (X, Index)",
        "Name (Name'First .. Name'First + 27)",
        '"x-amz-server-side-encryption"',
        "Name (Name'First .. Name'First + 39)",
        '"x-amz-copy-source-server-side-"',
        "Name not in",
        '"x-amz-server-side-encryption-customer-"',
        '"x-amz-server-side-encryption-customer-key"',
        '"x-amz-server-side-encryption-customer-key-"',
        "return True",
        '"x-amz-server-side-encryption-customer-algorithm"',
        '"x-amz-server-side-encryption-customer-key"',
        '"x-amz-server-side-encryption-customer-key-md5"',
        '"x-amz-expected-bucket-owner"',
        '"content-type"',
        "Algorithm_Count + Key_Count + MD5_Count not in 0 | 3",
        "elsif Has_Unmodeled_Encryption_Header then",
        '"AES256"',
        "Flyology.HTTP.Secure_HTTPS",
        "Checksums.Valid_SSE_C_Key_MD5",
        "Maximum_Select_Object_Content_Body",
        '400, "EntityTooLarge"',
        "Check_Expected_Bucket_Owner",
        "Auth.Payload_Hash",
        "Read_Document (Source)",
        "XML.Parse (Document, Validator, XML.Default_Limits)",
        "Validator.Root_Seen",
        "Validator.Root_Closed",
        "Store.Head_Bucket",
        "Store.Head_Object",
        '501, "NotImplemented"',
    ], "SelectObjectContent rejection route")
    require(route.count("Store.Head_Bucket") == 1,
            "SelectObjectContent bucket classification count")
    require(route.count("Store.Head_Object") == 1,
            "SelectObjectContent object observation count")
    for forbidden in [
        "Store.Get_Object", "Apps.Respond (X, 200", "Event_Stream",
        "Records", "Stats", "Progress", "Continuation", "End_Event",
        "Execute_", "Select_SQL", "Version_Selector",
    ]:
        require(forbidden not in route,
                f"SelectObjectContent invented behavior: {forbidden}")

    for diagnostic in [
        "SelectObjectContent did not reject unavailable event streaming",
        "SelectObjectContent rejected its exact operation identifier",
        "SelectObjectContent rejected its bare query form",
        "SelectObjectContent rejected its reverse operation identifier",
        "SelectObjectContent accepted an operation identifier without ",
        "SelectObjectContent accepted a duplicate select control",
        "SelectObjectContent accepted the wrong select type",
        "SelectObjectContent accepted an unknown query member",
        "SelectObjectContent query validation preceded authentication",
        "SelectObjectContent body validation preceded authentication",
        "SelectObjectContent did not distinguish a missing bucket",
        "SelectObjectContent did not distinguish a missing object",
        "SelectObjectContent accepted an empty body",
        "SelectObjectContent accepted an oversized document",
        "SelectObjectContent accepted malformed XML",
        "SelectObjectContent accepted an unnamespaced request root",
        "SelectObjectContent accepted the wrong request root",
        "SelectObjectContent rejected its expected bucket owner",
        "SelectObjectContent ignored an expected-owner mismatch",
        "SelectObjectContent accepted duplicate expected-owner headers",
        "SelectObjectContent accepted an incomplete SSE-C group",
        "SelectObjectContent accepted an unmodeled encryption header",
        "SelectObjectContent accepted an invalid SSE-C algorithm",
        "SelectObjectContent accepted SSE-C over plaintext",
        "SelectObjectContent accepted an SSE-C key/digest mismatch",
        "SelectObjectContent rejected a valid SSE-C transport group",
        "SelectObjectContent accepted duplicate content-type headers",
        "rejected SelectObjectContent changed its source object",
    ]:
        require(corpus.count(diagnostic) == 1,
                f"signed corpus diagnostic: {diagnostic}")
    require_in_order(corpus, [
        '"SelectObjectContent accepted valid SSE-C with an unmodeled " &',
        '"encryption header"',
        '"SelectObjectContent accepted valid SSE-C with a copy-source " &',
        '"encryption header"',
    ], "wrapped mixed-encryption diagnostics")

    require("procedure Head_Bucket" in backend,
            "shared Head_Bucket contract")
    require("procedure Head_Object" in backend,
            "shared Head_Object contract")
    for source, label in [
        (core_tests, "memory/files"), (sqlite_tests, "SQLite"),
    ]:
        require("Store.Head_Bucket" in source,
                f"{label} Head_Bucket evidence")
        require("Store.Head_Object" in source,
                f"{label} Head_Object evidence")
    for symbol in [
        "Prepare_Select_Object_Content", "Execute_Select_Object_Content",
        "Select_Object_Content_Operation", "Select_Object_Content",
    ]:
        require(symbol not in client, f"public client exposes {symbol}")

    normalized = " ".join(prose.split())
    for fact in [
        "Not_Exposed", "Authentication precedes", "NoSuchBucket",
        "NoSuchKey", "NotImplemented", "never calls `Get_Object`",
        "reports success, or mutates backend state",
        "does not interpret or default Expression",
        "No automatic replay", "no VersionId",
    ]:
        require(fact in normalized, f"qualification prose: {fact}")


def reject_registry(candidate: dict, label: str) -> None:
    try:
        assert_registry(candidate)
    except AssertionError:
        return
    raise AssertionError(f"{label} registry mutation accepted")


def reject_sources(server_spec: str, server_body: str, corpus: str,
                   backend: str, core_tests: str, sqlite_tests: str,
                   prose: str, client: str, label: str) -> None:
    try:
        assert_sources(server_spec, server_body, corpus, backend, core_tests,
                       sqlite_tests, prose, client)
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
    client = "\n".join(path.read_text() for path in CLIENT_PATHS)

    assert_registry(registry)
    assert_sources(server_spec, server_body, corpus, backend, core_tests,
                   sqlite_tests, prose, client)

    for label, mutate in [
        ("invented public API",
         lambda item: item.update(public_name="Select_Content")),
        ("invented client coverage",
         lambda item: item["coverage"].update(client="covered")),
        ("missing backend coverage",
         lambda item: item["coverage"].update(backend="missing")),
        ("missing server coverage",
         lambda item: item["coverage"].update(server="missing")),
        ("invented success",
         lambda item: item.update(certainty="returns selected records")),
        ("invented object read",
         lambda item: item["exclusions"].__setitem__(
             4, "the server reads object bytes with Get_Object")),
        ("invented resume",
         lambda item: item.update(reconciliation="resume from prior End")),
    ]:
        candidate = copy.deepcopy(registry)
        mutate(operation(candidate))
        require(candidate != registry, f"{label}: mutation guard")
        reject_registry(candidate, label)

    duplicate_lane = copy.deepcopy(registry)
    duplicate_lane["qualification"]["select_object_content"].append(
        ["./tests/scripts/test.sh"]
    )
    require(duplicate_lane != registry, "duplicate lane mutation guard")
    reject_registry(duplicate_lane, "duplicate root test")

    route = case_region(server_body, "Select_Object_Content",
                        "SelectObjectContent mutation scope")
    source_mutations = [
        ("invented object read",
         server_body.replace(
             route, route.replace(
                 "Store.Head_Bucket", "Store.Get_Object", 1), 1),
         corpus),
        ("missing bucket-before-object order",
         server_body.replace(
             route, route.replace(
                 "Store.Head_Bucket", "Store.Head_Object", 1), 1),
         corpus),
        ("invented success",
         server_body.replace(
             route, route.replace(
                 '501, "NotImplemented"', '200, ""', 1), 1),
         corpus),
        ("missing authentication order",
         server_body,
         corpus.replace(
             "SelectObjectContent query validation preceded authentication",
             "SelectObjectContent query validation order", 1)),
        ("missing namespace rejection",
         server_body,
         corpus.replace(
             "SelectObjectContent accepted an unnamespaced request root",
             "SelectObjectContent namespace case", 1)),
    ]
    for label, bad_server, bad_corpus in source_mutations:
        require((bad_server, bad_corpus) != (server_body, corpus),
                f"{label}: source mutation guard")
        reject_sources(server_spec, bad_server, bad_corpus, backend,
                       core_tests, sqlite_tests, prose, client, label)

    print("SelectObjectContent negative-capability preparation evidence: OK")


if __name__ == "__main__":
    main()
