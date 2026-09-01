#!/usr/bin/env python3
"""Verify the narrow derived-private ACL server profile."""

from __future__ import annotations

import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "coverage/s3-operations.toml"
SERVER = ROOT / "src/flyology-object_storage-server-s3_applications.adb"
CORPUS = ROOT / "tests/src/s3_server_application_corpus.adb"
BACKEND_CORPUS = ROOT / "tests/src/object_storage_test_cases.adb"
VERSIONED_CORPUS = ROOT / "tests/src/versioned_object_conformance.adb"
SQLITE_CORPUS = (
    ROOT / "sqlite/tests/src/flyology_object_storage_sqlite_tests.adb"
)
QUALIFICATION = ROOT / "docs/qualification/private-acl-server.md"
COMPATIBILITY = ROOT / "docs/compatibility/s3.md"
VERIFY_COMMAND = [
    "uv",
    "run",
    "--python",
    "3.13",
    "--",
    "tools/verify-private-acl-server.py",
]


def fail(message: str) -> None:
    raise ValueError(message)


def bounded(text: str, start: str, end: str, label: str) -> str:
    if text.count(start) != 1 or text.count(end) < 1:
        fail(f"{label} boundaries changed")
    beginning = text.index(start)
    ending = text.index(end, beginning + len(start))
    return text[beginning:ending]


def require_in_order(text: str, label: str, fragments: list[str]) -> None:
    cursor = 0
    for fragment in fragments:
        position = text.find(fragment, cursor)
        if position < 0:
            fail(f"{label} lacks ordered fragment {fragment}")
        cursor = position + len(fragment)


def require_counts(text: str, label: str, expected: dict[str, int]) -> None:
    for fragment, count in expected.items():
        actual = text.count(fragment)
        if actual != count:
            fail(
                f"{label} has {actual} occurrences of {fragment}, "
                f"not {count}"
            )


def registry_entries() -> tuple[dict[str, dict], dict[str, list]]:
    data = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    operations = {entry["name"]: entry for entry in data["operation"]}
    return operations, data["qualification"]


def verify_registry() -> None:
    operations, qualifications = registry_entries()
    expected = {
        "GetBucketAcl": ("covered", "covered", "get_bucket_acl"),
        "GetObjectAcl": ("covered", "covered", "get_object_acl"),
        "PutBucketAcl": ("covered", "covered", "generated_acl_mutation"),
        "PutObjectAcl": ("covered", "covered", "put_object_acl"),
    }
    for name, (backend, server, lane) in expected.items():
        entry = operations[name]
        if entry["coverage"]["backend"] != backend:
            fail(f"{name} backend coverage changed")
        if entry["coverage"]["server"] != server:
            fail(f"{name} server coverage changed")
        if entry["qualification"] != lane:
            fail(f"{name} qualification lane changed")
        if VERIFY_COMMAND not in qualifications[lane]:
            fail(f"{name} lane lacks the private ACL verifier")
        evidence = entry["evidence"]
        if "tools/verify-private-acl-server.py" not in evidence["corpus"]:
            fail(f"{name} lacks focused verifier evidence")
        if "docs/qualification/private-acl-server.md" not in (
            evidence["corpus"]
        ):
            fail(f"{name} lacks private-profile documentation evidence")
    if operations["PutBucketAcl"]["public_name"] != "Set_ACL":
        fail("PutBucketAcl public name changed")
    if operations["PutObjectAcl"]["public_name"] != "Not_Exposed":
        fail("PutObjectAcl invented a public client API")
    expected_backend_evidence = {
        "PutBucketAcl": [
            "tests/src/object_storage_test_cases.adb",
            "sqlite/tests/src/flyology_object_storage_sqlite_tests.adb",
            "tests/src/s3_server_application_corpus.adb",
        ],
        "PutObjectAcl": [
            "tests/src/object_storage_test_cases.adb",
            "tests/src/versioned_object_conformance.adb",
            "sqlite/tests/src/flyology_object_storage_sqlite_tests.adb",
            "tests/src/s3_server_application_corpus.adb",
        ],
    }
    for name, evidence in expected_backend_evidence.items():
        if operations[name]["evidence"]["backend"] != evidence:
            fail(f"{name} backend substrate evidence changed")
        if operations[name]["provenance"]["backend"] != "handwritten":
            fail(f"{name} backend provenance changed")
    persistence_facts = {
        "PutBucketAcl": "not arbitrary persisted ACL state",
        "PutObjectAcl": "rather than stored ACL state",
    }
    for name, persistence_fact in persistence_facts.items():
        exclusions = " ".join(operations[name]["exclusions"])
        for fact in (
            "x-amz-acl private",
            "XML policy mode",
            "explicit grant headers",
            persistence_fact,
        ):
            if fact not in exclusions:
                fail(f"{name} exclusions lack {fact}")


def verify_server() -> None:
    source = SERVER.read_text(encoding="utf-8")
    query_parser = bounded(
        source,
        "      function Parse_ACL_Query",
        "      end Parse_ACL_Query;",
        "ACL query parser",
    )
    require_in_order(
        query_parser,
        "ACL query parser",
        [
            "Request_Method : String",
            'Name = "acl"',
            'Name = "versionId"',
            "Deletions.Valid_Version_ID (Value)",
            'Name = "x-id"',
            'Request_Method = "PUT"',
            'then "PutObjectAcl" else "GetObjectAcl"',
            'Request_Method = "PUT"',
            '"PutBucketAcl"',
            '"GetBucketAcl"',
            "Result.Valid := Seen_ACL;",
        ],
    )
    require_counts(
        query_parser,
        "ACL query parser",
        {
            '"PutObjectAcl"': 1,
            '"PutBucketAcl"': 1,
            "Deletions.Valid_Version_ID (Value)": 1,
        },
    )
    require_in_order(
        source,
        "ACL PUT dispatch",
        [
            'Method in "GET" | "PUT" and then Looks_Like_ACL_Query',
            'elsif Method = "PUT" then Put_Bucket_ACL',
            'Method in "GET" | "PUT" and then Looks_Like_ACL_Query',
            'elsif Method = "PUT" then Put_Object_ACL',
        ],
    )
    helper = bounded(
        source,
        "      procedure Validate_Private_Canned_ACL",
        "      end Validate_Private_Canned_ACL;",
        "private canned ACL validator",
    )
    require_in_order(
        helper,
        "private canned ACL validator",
        [
            'Apps.Request_Header_Count (X, "x-amz-acl")',
            'Apps.Request_Header_Count (X, "content-md5")',
            'Apps.Request_Header_Count (X, "x-amz-grant-full-control")',
            'Apps.Request_Header_Count (X, "x-amz-grant-read")',
            'Apps.Request_Header_Count (X, "x-amz-grant-read-acp")',
            'Apps.Request_Header_Count (X, "x-amz-grant-write")',
            'Apps.Request_Header_Count (X, "x-amz-grant-write-acp")',
            '"A " & Operation_Name & " header is duplicated"',
            '"The " & Operation_Name & " ACL modes conflict"',
            '"Explicit ACL grants are not implemented"',
            'Operation_Name & " requires one canned ACL"',
            'Apps.Request_Header (X, "x-amz-acl") /= "private"',
            'Operation_Name & " requires Content-MD5"',
            'Apps.Request_Header (X, "content-md5") /= Content_MD5 ("")',
            '"The Content-MD5 does not match the empty request body"',
            '"Additional ACL checksum algorithms are not implemented"',
            '"The PutObjectAcl RequestPayer header is invalid"',
            '"PutBucketAcl does not define RequestPayer"',
            "Accepted := True;",
        ],
    )
    require_counts(
        helper,
        "private canned ACL validator",
        {
            '"Explicit ACL grants are not implemented"': 1,
            '"Only the private canned ACL is implemented"': 1,
            "Accepted := True;": 1,
        },
    )
    bucket = bounded(
        source,
        "            when Put_Bucket_ACL =>",
        "            when Get_Bucket_ACL =>",
        "PutBucketAcl route",
    )
    require_in_order(
        bucket,
        "PutBucketAcl route",
        [
            'Validate_Private_Canned_ACL\n                    ("PutBucketAcl"',
            "Check_Expected_Bucket_Owner",
            "Store.Head_Bucket",
            "if Result = Success then",
            'Apps.Respond (X, 200, "", "")',
        ],
    )
    object_route = bounded(
        source,
        "            when Put_Object_ACL =>",
        "            when Get_Object_ACL =>",
        "PutObjectAcl route",
    )
    require_in_order(
        object_route,
        "PutObjectAcl route",
        [
            "Backends.Current_Version_Selector",
            "Backends.Null_Version_Selector",
            "Kind => Backends.Exact_Version",
            'Validate_Private_Canned_ACL\n                    ("PutObjectAcl"',
            "Check_Expected_Bucket_Owner",
            "Store.Head_Object",
            "Selector => Selector",
            'Apps.Set_Header\n                                (X, '
            '"x-amz-request-charged", "requester")',
            'Apps.Respond (X, 200, "", "")',
            "Store.Head_Bucket",
        ],
    )
    if "Put_Bucket_ACL | Put_Object_ACL" in source:
        fail("private ACL mutations unexpectedly entered a body-stream lane")


def verify_corpus() -> None:
    corpus = CORPUS.read_text(encoding="utf-8")
    region = bounded(
        corpus,
        "      Bucket_Query : constant SigV4.Name_Value_Array :=",
        "   declare\n      First_ETag : constant String :=",
        "private ACL server corpus",
    )
    require_in_order(
        region,
        "private ACL server corpus",
        [
            'SigV4.Pair ("x-id", "PutBucketAcl")',
            'SigV4.Pair ("x-id", "PutObjectAcl")',
            '"1B2M2Y8AsgTpgAmY7PhCfg=="',
            '"PutBucketAcl rejected the private canned ACL"',
            '"GetBucketAcl after private replacement"',
            '"PutBucketAcl accepted a non-private canned ACL"',
            '"PutBucketAcl accepted an explicit grant"',
            '"PutBucketAcl did not verify bucket existence"',
            '"PutBucketAcl accepted a missing Content-MD5"',
            '"PutBucketAcl accepted duplicate canned ACL fields"',
            '"PutBucketAcl accepted duplicate Content-MD5 fields"',
            '"PutBucketAcl accepted conflicting ACL modes"',
            '"PutBucketAcl accepted an additional checksum algorithm"',
            '"PutObjectAcl rejected the private canned ACL"',
            '"PutObjectAcl rejected the null version selector"',
            '"x-amz-request-charged: requester"',
            '"GetObjectAcl after private replacement"',
            '"PutObjectAcl accepted a non-private canned ACL"',
            '"PutObjectAcl accepted a missing Content-MD5"',
            '"PutObjectAcl accepted a mismatched empty-body digest"',
            '"PutObjectAcl did not verify object existence"',
            '"PutObjectAcl did not distinguish an absent bucket"',
        ],
    )
    for name in ("PutBucketAcl", "PutObjectAcl"):
        if region.count(name) < 8:
            fail(f"{name} corpus evidence is incomplete")
    exact_region = bounded(
        corpus,
        "            Target_ID : constant String := US.To_String",
        "         declare\n            Marker_Query",
        "exact-version private ACL corpus",
    )
    require_in_order(
        exact_region,
        "exact-version private ACL corpus",
        [
            'SigV4.Pair ("acl", "")',
            'SigV4.Pair ("versionId", Target_ID)',
            'SigV4.Pair ("versionId", "unknown-generation")',
            '"x-amz-acl: private"',
            '"Content-MD5: " & Content_MD5 ("")',
            '"<Permission>FULL_CONTROL</Permission>"',
            '"<Code>NoSuchKey</Code>"',
            '"exact-version PutObjectAcl selection mismatch"',
        ],
    )


def verify_backend_and_docs() -> None:
    backend = BACKEND_CORPUS.read_text(encoding="utf-8")
    versioned = VERSIONED_CORPUS.read_text(encoding="utf-8")
    sqlite_source = SQLITE_CORPUS.read_text(encoding="utf-8")
    sqlite = bounded(
        sqlite_source,
        "      --  GetBucketAcl derives its private projection",
        '      Exercise_Conditional_Read (Store, "sqlite-bucket", Key);',
        "SQLite backend ACL substrate",
    )
    memory = bounded(
        backend,
        "   procedure Check_Memory_Lifecycle",
        "   end Check_Memory_Lifecycle;",
        "memory backend ACL substrate",
    )
    files = bounded(
        backend,
        "   procedure Check_Filesystem_Conformance",
        "   end Check_Filesystem_Conformance;",
        "files backend ACL substrate",
    )
    for text, label in (
        (memory, "memory backend"),
        (files, "files backend"),
        (sqlite, "SQLite"),
    ):
        for fragment in (
            "GetBucketAcl derives its private projection",
            "GetObjectAcl derives its private projection",
            "Head_Bucket",
            "Head_Object",
        ):
            if fragment not in text:
                fail(f"{label} corpus lacks {fragment}")
    for fragment in (
        "GetObjectAcl derives its private projection",
        "Head_Object",
        "Null_Version_Selector",
        "Exact_Version",
    ):
        if fragment not in versioned:
            fail(f"versioned backend corpus lacks {fragment}")
    qualification = QUALIFICATION.read_text(encoding="utf-8")
    require_in_order(
        qualification,
        "private ACL qualification",
        [
            "ACL state\nis therefore derived",
            "it is not stored independently",
            "current,\nnull, or exact object generation",
            "x-amz-acl: private",
            "changes no backend state",
            "does not automatically replay",
            "XML policy bodies",
            "PutObjectAcl` client remains model-only",
            "not general S3 ACL interoperability",
        ],
    )
    compatibility = COMPATIBILITY.read_text(encoding="utf-8")
    for operation in (
        "GetBucketAcl",
        "PutBucketAcl",
        "GetObjectAcl",
        "PutObjectAcl",
    ):
        if compatibility.count(f"| {operation} |") != 1:
            fail(f"compatibility matrix lacks exact {operation} row")


def main() -> int:
    verify_registry()
    verify_server()
    verify_corpus()
    verify_backend_and_docs()
    print("private ACL server profile: OK")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, TypeError, ValueError) as error:
        print(
            f"private ACL server verification failed: {error}",
            file=sys.stderr,
        )
        raise SystemExit(1)
