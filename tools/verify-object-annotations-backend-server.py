#!/usr/bin/env python3
"""Fail closed on the shared object-annotation backend/server boundary."""

from __future__ import annotations

import copy
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OPERATIONS = (
    "DeleteObjectAnnotation",
    "GetObjectAnnotation",
    "ListObjectAnnotations",
    "PutObjectAnnotation",
)
SHARED_COMMAND = [
    "uv",
    "run",
    "--python",
    "3.13",
    "--",
    "tools/verify-object-annotations-backend-server.py",
]
BACKEND_EVIDENCE = [
    "src/flyology-object_storage-backends.ads",
    "src/flyology-object_storage-backends-memory.adb",
    "src/flyology-object_storage-backends-files.adb",
    "sqlite/src/flyology-object_storage-backends-sqlite.adb",
    "sqlite/src/flyology-object_storage-sqlite-catalogs.adb",
    "tests/src/object_storage_test_cases.adb",
    "sqlite/tests/src/flyology_object_storage_sqlite_tests.adb",
]
SERVER_EVIDENCE = [
    "src/flyology-object_storage-s3-annotations.adb",
    "src/flyology-object_storage-server-s3_applications.adb",
    "tests/src/s3_server_application_corpus.adb",
]


class Evidence_Error(RuntimeError):
    """One reviewed object-annotation invariant changed."""


def fail(message: str) -> None:
    raise Evidence_Error(message)


def source(relative: str) -> str:
    path = ROOT / relative
    if not path.is_file() or path.is_symlink():
        fail(f"missing or unsafe source: {relative}")
    raw = path.read_bytes()
    if b"\r" in raw:
        fail(f"noncanonical CR byte: {relative}")
    return raw.decode("utf-8")


def require_once(text: str, fragment: str, label: str) -> None:
    count = text.count(fragment)
    if count != 1:
        fail(f"{label}: expected one occurrence, found {count}")


def require_in_order(
    text: str,
    fragments: tuple[str, ...] | list[str],
    label: str,
) -> None:
    position = 0
    for fragment in fragments:
        position = text.find(fragment, position)
        if position < 0:
            fail(f"{label}: missing or reordered fragment {fragment!r}")
        position += len(fragment)


def unique_region(text: str, start: str, end: str, label: str) -> str:
    if text.count(start) != 1:
        fail(f"{label}: start boundary is not unique")
    first = text.index(start)
    last = text.find(end, first + len(start))
    if last < 0:
        fail(f"{label}: end boundary is missing")
    return text[first:last]


def normalized(text: str) -> str:
    return " ".join(text.split())


def operation_entries(data: dict[str, object]) -> dict[str, dict]:
    entries = {}
    for entry in data["operation"]:
        name = entry["name"]
        if name in OPERATIONS:
            if name in entries:
                fail(f"duplicate registry operation: {name}")
            entries[name] = entry
    if set(entries) != set(OPERATIONS):
        fail("object-annotation registry operation set changed")
    return entries


def verify_registry(data: dict[str, object]) -> None:
    entries = operation_entries(data)
    expected_client = {
        "DeleteObjectAnnotation": ("covered", "handwritten"),
        "GetObjectAnnotation": ("partial", "generated"),
        "ListObjectAnnotations": ("covered", "shared_family"),
        "PutObjectAnnotation": ("partial", "generated"),
    }
    expected_names = {
        "DeleteObjectAnnotation": "Delete_Annotation",
        "GetObjectAnnotation": "Not_Exposed",
        "ListObjectAnnotations": "List_Annotations",
        "PutObjectAnnotation": "Not_Exposed",
    }
    qualification = data["qualification"]
    for name in OPERATIONS:
        entry = entries[name]
        client, provenance = expected_client[name]
        if entry["public_name"] != expected_names[name]:
            fail(f"{name}: public name changed")
        if entry["coverage"] != {
            "backend": "covered",
            "client": client,
            "server": "covered",
            "corpus": "covered",
        }:
            fail(f"{name}: coverage overclaim or omission")
        if entry["provenance"]["backend"] != "handwritten":
            fail(f"{name}: backend provenance changed")
        if entry["provenance"]["client"] != provenance:
            fail(f"{name}: client provenance changed")
        if entry["provenance"]["server"] != "handwritten":
            fail(f"{name}: server provenance changed")
        if entry["evidence"]["backend"] != BACKEND_EVIDENCE:
            fail(f"{name}: backend evidence changed")
        if entry["evidence"]["server"] != SERVER_EVIDENCE:
            fail(f"{name}: server evidence changed")
        if "tools/verify-object-annotations-backend-server.py" not in (
            entry["evidence"]["corpus"]
        ):
            fail(f"{name}: shared verifier evidence missing")
        lane = qualification[entry["qualification"]]
        if lane.count(SHARED_COMMAND) != 1:
            fail(f"{name}: shared verifier lane association changed")
    if "no public client operation" not in entries[
        "GetObjectAnnotation"
    ]["certainty"]:
        fail("GetObjectAnnotation client boundary was overclaimed")
    if "no public client request-body source" not in entries[
        "PutObjectAnnotation"
    ]["certainty"]:
        fail("PutObjectAnnotation client boundary was overclaimed")
    if "bytewise UTF-8" not in entries["ListObjectAnnotations"][
        "certainty"
    ]:
        fail("ListObjectAnnotations ordering contract changed")
    if "without automatic replay" not in entries[
        "DeleteObjectAnnotation"
    ]["certainty"]:
        fail("DeleteObjectAnnotation replay boundary changed")


def verify_backend_contract() -> None:
    domain = source("src/flyology-object_storage.ads")
    information = unique_region(
        domain,
        "type Object_Annotation_Information is record",
        "function Valid_Object_Annotation_Name",
        "annotation information and presence",
    )
    require_in_order(
        information,
        [
            "Size       : Byte_Count;",
            "Modified   : Unix_Time;",
            "Entity_Tag : Ada.Strings.Unbounded.Unbounded_String;",
            "Checksum   : Checksum_Information;",
            "Version    : Ada.Strings.Unbounded.Unbounded_String;",
            "type Object_Annotation_Presence is",
            "Annotation_Absent",
            "Annotation_Present",
        ],
        "annotation information and presence",
    )
    spec = source("src/flyology-object_storage-backends.ads")
    region = unique_region(
        spec,
        "type Object_Annotation_Backend is limited interface;",
        "procedure Put_Object_Annotation_If_Supported",
        "backend annotation interface",
    )
    require_in_order(
        region,
        [
            "type Put_Object_Annotation_Options is record",
            "Expected_Checksum : Checksum_Information;",
            "procedure Put_Object_Annotation",
            "Source   : in out Byte_Source'Class;",
            "procedure Get_Object_Annotation",
            "Sink     : in out Annotation_Byte_Sink'Class;",
            "procedure Delete_Object_Annotation",
            "Conditions : Object_Annotation_Conditions;",
            "procedure List_Object_Annotations",
        ],
        "backend annotation contract",
    )
    copy_region = unique_region(
        spec,
        "type Copy_Annotation_Directive is",
        "type Copy_Options is record",
        "copy annotation directive",
    )
    require_in_order(
        copy_region,
        ["Copy_Annotations", "Exclude_Annotations"],
        "copy annotation directive",
    )
    require_once(
        spec,
        "Annotation_Directive : Copy_Annotation_Directive := "
        "Copy_Annotations;",
        "copy annotation default",
    )


def verify_implementations() -> None:
    implementations = (
        (
            "memory",
            "src/flyology-object_storage-backends-memory.ads",
            "src/flyology-object_storage-backends-memory.adb",
        ),
        (
            "files",
            "src/flyology-object_storage-backends-files.ads",
            "src/flyology-object_storage-backends-files.adb",
        ),
        (
            "sqlite",
            "sqlite/src/flyology-object_storage-backends-sqlite.ads",
            "sqlite/src/flyology-object_storage-backends-sqlite.adb",
        ),
    )
    procedures = (
        "Put_Object_Annotation",
        "Get_Object_Annotation",
        "Delete_Object_Annotation",
        "List_Object_Annotations",
    )
    for label, spec_path, body_path in implementations:
        spec = source(spec_path)
        body = source(body_path)
        for procedure in procedures:
            require_once(
                spec,
                f"overriding procedure {procedure}",
                f"{label} {procedure} declaration",
            )
            require_once(
                body,
                f"overriding procedure {procedure}",
                f"{label} {procedure} body",
            )

    files = source("src/flyology-object_storage-backends-files.adb")
    require_in_order(
        files,
        [
            "Maximum_Annotation_Payload_Bytes",
            "function Annotations_Path",
            "overriding procedure Put_Object_Annotation",
            "overriding procedure Get_Object_Annotation",
        ],
        "files external annotation payload",
    )

    catalogs = source(
        "sqlite/src/flyology-object_storage-sqlite-catalogs.adb"
    )
    require_once(
        catalogs,
        "Schema_Version : constant Long_Long_Integer := 23;",
        "SQLite schema version",
    )
    require_in_order(
        catalogs,
        [
            '"CREATE TABLE object_annotations ("',
            '"payload TEXT NOT NULL,"',
            "Append_Version_Annotation_Payloads_Internal",
            "procedure Put_Object_Annotation",
            "procedure Get_Object_Annotation",
            "procedure Delete_Object_Annotation",
            "procedure List_Object_Annotations",
        ],
        "SQLite annotation catalog",
    )
    sqlite_tests = source(
        "sqlite/tests/src/flyology_object_storage_sqlite_tests.adb"
    )
    require_in_order(
        sqlite_tests,
        [
            "Create_V22_Database;",
            "PRAGMA user_version",
            "object_annotations",
            "schema-v22 migration did not publish annotations atomically",
        ],
        "SQLite schema 23 migration",
    )


def verify_server_and_tests() -> None:
    wire = source("src/flyology-object_storage-s3-annotations.adb")
    continuation = unique_region(
        wire,
        "function Encode_Continuation",
        "end Decode_Continuation;",
        "annotation continuation binding",
    )
    require_in_order(
        continuation,
        [
            "Bucket, Key, Version_ID, Prefix, After",
            "Token_Digest",
            "function Decode_Continuation",
            "Bucket, Key, Version_ID, Prefix",
            "Valid_Object_Annotation_Name",
            "Token_Digest",
        ],
        "annotation continuation binding",
    )
    server = source(
        "src/flyology-object_storage-server-s3_applications.adb"
    )
    annotation_region = unique_region(
        server,
        "when Put_Object_Annotation | Get_Object_Annotation |",
        "when Put_Object_Tagging | Get_Object_Tagging |",
        "annotation server route",
    )
    require_in_order(
        annotation_region,
        [
            "Valid_Common_Headers",
            "Valid_Object_Delete_ETag_Condition",
            "Operation = Put_Object_Annotation",
            "Expected_Checksum =>",
            "Backends.Put_Object_Annotation_If_Supported",
            "Backends.Get_Object_Annotation_If_Supported",
            "Backends.Delete_Object_Annotation_If_Supported",
            "Annotations.Decode_Continuation",
            "Backends.List_Object_Annotations_If_Supported",
            "Annotations.Encode_Continuation",
        ],
        "annotation server route",
    )
    copy_region = unique_region(
        server,
        "Copy_Options_Value.Annotation_Directive :=",
        "Check_Expected_Bucket_Owner",
        "copy annotation server directive",
    )
    require_in_order(
        copy_region,
        [
            '"x-amz-object-annotation-directive"',
            '(X, "x-amz-object-annotation-directive") = "EXCLUDE"',
            "Backends.Exclude_Annotations",
            "Backends.Copy_Annotations",
        ],
        "copy annotation server directive",
    )

    backend_tests = source("tests/src/object_storage_test_cases.adb")
    exercise = unique_region(
        backend_tests,
        "procedure Exercise_Object_Annotations",
        "end Exercise_Object_Annotations;",
        "backend annotation tests",
    )
    require_in_order(
        exercise,
        [
            "Put_Object_Annotation_If_Supported",
            "Read_Annotation",
            "List_Object_Annotations_If_Supported",
            'Assert (Result = Success, "annotation COPY directive failed")',
            "Options.Annotation_Directive := Exclude_Annotations",
            "Delete_Object_Annotation_If_Supported",
            "Annotation_Absent",
        ],
        "backend annotation tests",
    )
    server_tests = source("tests/src/s3_server_application_corpus.adb")
    route_tests = unique_region(
        server_tests,
        'Alpha_Name    : constant String := "alpha";',
        "CopyObject EXCLUDE changed source annotation state",
        "server annotation tests",
    )
    require_in_order(
        route_tests,
        [
            "PutObjectAnnotation",
            "GetObjectAnnotation",
            "DeleteObjectAnnotation",
            "BadDigest",
            "ListObjectAnnotations",
            '"x-amz-object-annotation-directive", "COPY"',
            '"x-amz-object-annotation-directive", "EXCLUDE"',
            "CopyObject EXCLUDE retained destination annotation state",
        ],
        "server annotation tests",
    )


def verify_document() -> None:
    document = normalized(source(
        "docs/qualification/object-annotations-backend-server.md"
    ))
    require_in_order(
        document,
        [
            "It is conditional",
            "Memory, pure-files, and SQLite",
            "SQLite schema version 23",
            "COPY preserves",
            "EXCLUDE publishes none",
            "Client coverage is intentionally asymmetric",
            "GetObjectAnnotation and PutObjectAnnotation remain "
            "generated-model-only",
            "Passing the shared verifier alone does not qualify",
            "Generated coverage outputs remain stale",
        ],
        "conditional annotation documentation",
    )


def main() -> None:
    data = tomllib.loads(source("coverage/s3-operations.toml"))
    verify_registry(data)
    verify_backend_contract()
    verify_implementations()
    verify_server_and_tests()
    verify_document()

    missing = copy.deepcopy(data)
    missing["qualification"]["get_object_annotation"].remove(
        SHARED_COMMAND
    )
    try:
        verify_registry(missing)
    except Evidence_Error:
        pass
    else:
        fail("missing shared-verifier mutation was accepted")

    overclaim = copy.deepcopy(data)
    for entry in overclaim["operation"]:
        if entry["name"] == "PutObjectAnnotation":
            entry["coverage"]["client"] = "covered"
    try:
        verify_registry(overclaim)
    except Evidence_Error:
        pass
    else:
        fail("client-overclaim mutation was accepted")

    print("Object annotation backend/server preparation: OK")


if __name__ == "__main__":
    main()
