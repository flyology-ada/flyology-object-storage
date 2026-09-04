#!/usr/bin/env python3
"""Fail-closed source oracle for UpdateObjectEncryption rejection coverage."""

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
VERSIONED_PATH = ROOT / "tests" / "src" / (
    "versioned_object_conformance.adb"
)
CORE_TESTS_PATH = ROOT / "tests" / "src" / "object_storage_test_cases.adb"
SQLITE_TESTS_PATH = ROOT / "sqlite" / "tests" / "src" / (
    "flyology_object_storage_sqlite_tests.adb"
)
PROSE_PATH = ROOT / "docs" / "qualification" / (
    "update-object-encryption.md"
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


def bounded_region(source: str, start: str, end: str, label: str) -> str:
    require(source.count(start) == 1, f"{label}: start boundary")
    first = source.index(start)
    finish = source.find(end, first + len(start))
    require(finish >= 0, f"{label}: end boundary")
    return source[first:finish]


def case_region(source: str, alternative: str, label: str) -> str:
    start = f"            when {alternative} =>"
    require(source.count(start) == 1, f"{label}: case boundary")
    first = source.index(start)
    match = re.search(
        r"\n            when [A-Za-z_]+(?: \|[^=]+)? =>",
        source[first + len(start):],
    )
    require(match is not None, f"{label}: next case boundary")
    return source[first:first + len(start) + match.start()]


def operation(registry: dict) -> dict:
    entries = [
        item for item in registry["operation"]
        if item["name"] == "UpdateObjectEncryption"
    ]
    require(len(entries) == 1, "UpdateObjectEncryption registry uniqueness")
    return entries[0]


EXPECTED_LANE = [
    ["uv", "run", "--python", "3.13", "--",
     "tools/verify-update-object-encryption-preparation.py"],
    ["uv", "run", "--python", "3.13", "--",
     "tests/scripts/verify-update-object-encryption-model.py"],
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
            "private_strict_object_encryption_xml_negative_capability",
            "UpdateObjectEncryption codec")
    require(entry["coverage"] == {
        "backend": "covered",
        "client": "partial",
        "server": "covered",
        "corpus": "covered",
    }, "UpdateObjectEncryption coverage")
    require(entry["provenance"] == {
        "backend": "shared_family",
        "client": "generated",
        "server": "handwritten",
        "tests": "handwritten",
    }, "UpdateObjectEncryption provenance")
    require(entry["evidence_tokens"] == ["Head_Bucket", "Head_Object"],
            "shared backend tokens")
    require(entry["evidence"]["backend"] == [
        "src/flyology-object_storage-backends.ads",
        "tests/src/versioned_object_conformance.adb",
        "tests/src/object_storage_test_cases.adb",
        "sqlite/tests/src/flyology_object_storage_sqlite_tests.adb",
    ], "shared backend evidence")
    require(entry["evidence"]["server"] == [
        "src/flyology-object_storage-server-s3_applications.ads",
        "src/flyology-object_storage-server-s3_applications.adb",
        "tests/src/s3_server_application_corpus.adb",
    ], "server evidence")
    require(entry["evidence"]["corpus"] == [
        "tests/scripts/verify-update-object-encryption-model.py",
        "tools/verify-update-object-encryption-preparation.py",
        "docs/qualification/update-object-encryption.md",
        "tests/src/s3_server_application_corpus.adb",
    ], "corpus evidence")
    require("never updates encryption" in entry["certainty"],
            "negative mutation certainty")
    require("no automatic replay" in entry["certainty"],
            "no-replay certainty")
    require("cannot prove causation" in entry["reconciliation"],
            "noncausal reconciliation")
    exclusions = " ".join(entry["exclusions"])
    for fact in [
        "no Low_Level or Objects UpdateObjectEncryption API",
        "authenticated exact PUT object query with encryption",
        "optional modeled x-id=UpdateObjectEncryption",
        "preserves current, null, and exact-generation selection",
        "sole SSE-KMS union member",
        "omission of BucketKeyEnabled remains absence",
        "required generated-checksum selector",
        "calls only Head_Bucket and version-aware Head_Object",
        "without reading object bytes",
        "KMS account or organization ownership",
        "modeled default HTTP 200 response",
    ]:
        require(fact in exclusions, f"missing exclusion: {fact}")
    require(registry["qualification"]["update_object_encryption"] ==
            EXPECTED_LANE, "UpdateObjectEncryption qualification lane")


def assert_sources(server_spec: str, server_body: str, corpus: str,
                   backend: str, versioned: str, core_tests: str,
                   sqlite_tests: str, prose: str, client: str) -> None:
    require("validated negative-capability UpdateObjectEncryption routing" in
            server_spec, "server specification boundary")

    query = bounded_region(
        server_body,
        "Update_Object_Encryption_Request : constant",
        "ACL_Query_Invalid : Boolean := False;",
        "UpdateObjectEncryption query parser",
    )
    require_in_order(query, [
        "Object_Lock_Query_Result :=",
        "Parse_Object_Lock_Query",
        '(Query_Text, "encryption", "UpdateObjectEncryption",',
        "Allow_Version => True",
    ], "exact UpdateObjectEncryption query")
    require_in_order(server_body, [
        "Update_Object_Encryption_Query_Invalid :=",
        "Has_Update_Object_Encryption_Query",
        "not Update_Object_Encryption_Request.Valid",
        "Operation := Update_Object_Encryption",
        "Auth := Authentication.Verify_Request",
        "elsif Update_Object_Encryption_Query_Invalid then",
        '"The UpdateObjectEncryption request query is invalid"',
    ], "authenticated UpdateObjectEncryption routing")

    validator = bounded_region(
        server_body,
        "Maximum_Update_Object_Encryption_Body : constant Byte_Count :=",
        "type Select_XML_Validator is",
        "UpdateObjectEncryption XML validator",
    )
    require_in_order(validator, [
        "Maximum_Update_Object_Encryption_Body : constant Byte_Count :=",
        "Byte_Count (XML.Default_Limits.Maximum_Document_Bytes)",
        "type Object_Encryption_XML_Field is",
        "Object_Encryption_XML_Validator",
        "Value'Length not in 20 .. 2_048",
        'Value (Partition_End + 1 .. Service_End - 1) = "kms"',
        'Value (Account_End + 1 .. Account_End + 4) = "key/"',
        'Local_Name /= "ObjectEncryption"',
        'Local_Name /= "SSE-KMS"',
        'Local_Name = "KMSKeyArn"',
        'Local_Name = "BucketKeyEnabled"',
        "Attribute_Count /= 0",
        "Namespace_URI /=",
        '"http://s3.amazonaws.com/doc/2006-03-01/"',
        'Value not in "true" | "false"',
        'Local_Name /= "SSE-KMS" or else not Item.KMS_ARN_Seen',
        'Local_Name /= "ObjectEncryption"',
        "Item.Root_Closed := True",
    ], "strict ObjectEncryption XML validator")

    route = case_region(server_body, "Update_Object_Encryption",
                        "UpdateObjectEncryption route")
    require_in_order(route, [
        "function Has_Unmodeled_Encryption_Header return Boolean is",
        "Apps.Request_Header_Name (X, Index)",
        '"x-amz-server-side-encryption"',
        '"x-amz-copy-source-server-side-" &',
        '"encryption"',
        'Apps.Request_Header_Count (X, "x-amz-request-payer")',
        'Apps.Request_Header_Count (X, "content-md5")',
        '"x-amz-sdk-checksum-algorithm"',
        "Checksum_Value_Header_Count",
        'Apps.Request_Header_Count (X, "x-amz-trailer")',
        "To_Version_Selector",
        "Update_Object_Encryption_Request.Has_Version_ID",
        "Update_Object_Encryption_Request.Version_ID",
        "SDK_Count /= 1",
        "Value_Count + Trailer_Count /= 1",
        'Apps.Request_Header_Count (X, "content-type") > 1',
        "and then Apps.Request_Header",
        '(X, "x-amz-request-payer") /= "requester"',
        "S3.Wire_Core.Valid_Base64",
        "elsif Has_Unmodeled_Encryption_Header then",
        "Maximum_Update_Object_Encryption_Body",
        '400, "EntityTooLarge"',
        "Check_Expected_Bucket_Owner",
        "Request_IO.Request_Source",
        "Read_Document (Source)",
        "Verify_Document_Checksum (Document)",
        "Document_Checksum_Mismatch",
        '400, "BadDigest"',
        "XML.Parse (Document, Validator, XML.Default_Limits)",
        "Validator.Root_Seen",
        "Validator.Root_Closed",
        "Store.Head_Bucket",
        "Store.Head_Object",
        "Selector => Selector",
        '501, "NotImplemented"',
        "Update_Object_Encryption_Request.Has_Version_ID",
        '404, "NoSuchVersion"',
    ], "UpdateObjectEncryption rejection route")
    require(route.count("Store.Head_Bucket") == 1,
            "UpdateObjectEncryption bucket classification count")
    require(route.count("Store.Head_Object") == 1,
            "UpdateObjectEncryption object observation count")
    for forbidden in [
        "Store.Get_Object", "Store.Put_Object", "Apps.Respond (X, 200",
        '"x-amz-request-charged"', "Execute_Update", "Update_Encryption",
    ]:
        require(forbidden not in route,
                f"UpdateObjectEncryption invented behavior: {forbidden}")

    corpus_region = bounded_region(
        corpus,
        'Document : constant String :=\n        "<ObjectEncryption "',
        'Document : constant String :=\n'
        '        "<SelectObjectContentRequest "',
        "UpdateObjectEncryption corpus",
    )
    require_in_order(corpus_region, [
        "UpdateObjectEncryption did not reject unavailable mutation",
        "UpdateObjectEncryption rejected omitted BucketKeyEnabled",
        "UpdateObjectEncryption rejected its exact operation identifier",
        "UpdateObjectEncryption rejected its bare query form",
        "UpdateObjectEncryption rejected reverse operation identifier",
        "UpdateObjectEncryption query validation preceded authentication",
        "UpdateObjectEncryption body validation preceded authentication",
        "UpdateObjectEncryption accepted a missing request checksum",
        "UpdateObjectEncryption accepted a malformed checksum",
        "UpdateObjectEncryption accepted a mismatched checksum",
        "UpdateObjectEncryption accepted an empty body",
        "UpdateObjectEncryption accepted an oversized body",
        "UpdateObjectEncryption did not bind checksum before XML parsing",
        "UpdateObjectEncryption accepted malformed XML",
        "UpdateObjectEncryption accepted an unnamespaced payload",
        "UpdateObjectEncryption invented an SSES3 union member",
        "UpdateObjectEncryption accepted SSE-KMS without KMSKeyArn",
        "UpdateObjectEncryption accepted an invalid KMS key ARN",
        "UpdateObjectEncryption accepted an invalid boolean value",
        "UpdateObjectEncryption accepted an unmodeled transport header",
        "UpdateObjectEncryption did not distinguish a missing bucket",
        "UpdateObjectEncryption did not distinguish a missing key",
        "UpdateObjectEncryption did not bind the null generation",
        "UpdateObjectEncryption did not distinguish a missing version",
        "rejected UpdateObjectEncryption changed the source object",
    ], "UpdateObjectEncryption corpus order")
    for diagnostic in [
        "UpdateObjectEncryption did not reject unavailable mutation",
        "UpdateObjectEncryption rejected omitted BucketKeyEnabled",
        "UpdateObjectEncryption rejected its exact operation identifier",
        "UpdateObjectEncryption rejected its bare query form",
        "UpdateObjectEncryption rejected reverse operation identifier",
        "UpdateObjectEncryption accepted an operation identifier without ",
        "UpdateObjectEncryption accepted duplicate encryption controls",
        "UpdateObjectEncryption accepted an unknown query member",
        "UpdateObjectEncryption accepted an empty version selector",
        "UpdateObjectEncryption query validation preceded authentication",
        "UpdateObjectEncryption body validation preceded authentication",
        "UpdateObjectEncryption accepted a missing request checksum",
        "UpdateObjectEncryption accepted a malformed checksum",
        "UpdateObjectEncryption accepted a mismatched checksum",
        "UpdateObjectEncryption rejected a matching Content-MD5",
        "UpdateObjectEncryption accepted a mismatched Content-MD5",
        "UpdateObjectEncryption rejected the requester payer value",
        "UpdateObjectEncryption accepted an invalid request payer",
        "UpdateObjectEncryption rejected its expected bucket owner",
        "UpdateObjectEncryption ignored an expected-owner mismatch",
        "UpdateObjectEncryption accepted duplicate expected owners",
        "UpdateObjectEncryption did not distinguish a missing bucket",
        "UpdateObjectEncryption did not distinguish a missing key",
        "UpdateObjectEncryption did not distinguish a missing version",
        "UpdateObjectEncryption accepted an empty body",
        "UpdateObjectEncryption accepted an oversized body",
        "UpdateObjectEncryption did not bind checksum before XML parsing",
        "UpdateObjectEncryption accepted malformed XML",
        "UpdateObjectEncryption accepted an unnamespaced payload",
        "UpdateObjectEncryption invented an SSES3 union member",
        "UpdateObjectEncryption accepted SSE-KMS without KMSKeyArn",
        "UpdateObjectEncryption accepted an invalid KMS key ARN",
        "UpdateObjectEncryption accepted an invalid boolean value",
        "UpdateObjectEncryption accepted an unmodeled transport header",
        "UpdateObjectEncryption did not bind the null generation",
        "rejected UpdateObjectEncryption changed the source object",
    ]:
        require(corpus_region.count(diagnostic) == 1,
                f"server corpus diagnostic: {diagnostic}")

    require("procedure Head_Bucket" in backend,
            "shared Head_Bucket contract")
    require("procedure Head_Object" in backend,
            "shared Head_Object contract")
    for source, label in [
        (versioned, "versioned conformance"),
        (core_tests, "memory/files"),
        (sqlite_tests, "SQLite"),
    ]:
        require("Head_Object" in source, f"{label} Head_Object evidence")
    for source, label in [
        (core_tests, "memory/files"), (sqlite_tests, "SQLite"),
    ]:
        require("Head_Bucket" in source, f"{label} Head_Bucket evidence")
    for symbol in [
        "Prepare_Update_Object_Encryption",
        "Execute_Update_Object_Encryption",
        "Update_Object_Encryption_Operation",
        "Update_Object_Encryption",
    ]:
        require(symbol not in client, f"public client exposes {symbol}")

    normalized = " ".join(prose.split())
    for fact in [
        "Not_Exposed", "Authentication precedes every", "NoSuchBucket",
        "NoSuchKey", "NoSuchVersion", "NotImplemented",
        "never calls `Get_Object` or `Put_Object`", "reports success",
        "one required KMS key ARN", "optional exact lowercase Boolean",
        "chooses no checksum algorithm", "No encryption state changes",
        "cannot prove causation", "No automatic replay",
    ]:
        require(fact in normalized, f"qualification prose: {fact}")


def reject_registry(candidate: dict, label: str) -> None:
    try:
        assert_registry(candidate)
    except AssertionError:
        return
    raise AssertionError(f"{label} registry mutation accepted")


def reject_sources(server_spec: str, server_body: str, corpus: str,
                   backend: str, versioned: str, core_tests: str,
                   sqlite_tests: str, prose: str, client: str,
                   label: str) -> None:
    try:
        assert_sources(server_spec, server_body, corpus, backend, versioned,
                       core_tests, sqlite_tests, prose, client)
    except AssertionError:
        return
    raise AssertionError(f"{label} source mutation accepted")


def main() -> None:
    registry = tomllib.loads(REGISTRY_PATH.read_text())
    server_spec = SERVER_SPEC_PATH.read_text()
    server_body = SERVER_BODY_PATH.read_text()
    corpus = CORPUS_PATH.read_text()
    backend = BACKEND_PATH.read_text()
    versioned = VERSIONED_PATH.read_text()
    core_tests = CORE_TESTS_PATH.read_text()
    sqlite_tests = SQLITE_TESTS_PATH.read_text()
    prose = PROSE_PATH.read_text()
    client = "\n".join(path.read_text() for path in CLIENT_PATHS)

    assert_registry(registry)
    assert_sources(server_spec, server_body, corpus, backend, versioned,
                   core_tests, sqlite_tests, prose, client)

    for label, mutate in [
        ("invented public API",
         lambda item: item.update(public_name="Update_Encryption")),
        ("invented client coverage",
         lambda item: item["coverage"].update(client="covered")),
        ("missing backend coverage",
         lambda item: item["coverage"].update(backend="missing")),
        ("missing server coverage",
         lambda item: item["coverage"].update(server="missing")),
        ("invented success",
         lambda item: item.update(certainty="encryption update succeeds")),
        ("invented object mutation",
         lambda item: item["exclusions"].__setitem__(
             4, "the server updates encryption through Put_Object")),
        ("invented bucket-key default",
         lambda item: item["exclusions"].__setitem__(
             2, "omitted BucketKeyEnabled defaults to false")),
        ("causal reconciliation",
         lambda item: item.update(
             reconciliation="HeadObject proves update causation")),
    ]:
        candidate = copy.deepcopy(registry)
        mutate(operation(candidate))
        require(candidate != registry, f"{label}: mutation guard")
        reject_registry(candidate, label)

    duplicate_lane = copy.deepcopy(registry)
    duplicate_lane["qualification"]["update_object_encryption"].append(
        ["./tests/scripts/test.sh"]
    )
    require(duplicate_lane != registry, "duplicate lane mutation guard")
    reject_registry(duplicate_lane, "duplicate root test")

    route = case_region(server_body, "Update_Object_Encryption",
                        "UpdateObjectEncryption mutation scope")
    source_mutations = [
        ("invented object mutation",
         server_body.replace(
             route, route.replace(
                 "Store.Head_Object", "Store.Put_Object", 1), 1),
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
             "UpdateObjectEncryption query validation preceded "
             "authentication",
             "UpdateObjectEncryption query validation order", 1)),
        ("missing SSES3 rejection",
         server_body,
         corpus.replace(
             "UpdateObjectEncryption invented an SSES3 union member",
             "UpdateObjectEncryption SSES3 case", 1)),
    ]
    for label, bad_server, bad_corpus in source_mutations:
        require((bad_server, bad_corpus) != (server_body, corpus),
                f"{label}: source mutation guard")
        reject_sources(server_spec, bad_server, bad_corpus, backend,
                       versioned, core_tests, sqlite_tests, prose, client,
                       label)

    print(
        "UpdateObjectEncryption negative-capability preparation evidence: OK"
    )


if __name__ == "__main__":
    main()
