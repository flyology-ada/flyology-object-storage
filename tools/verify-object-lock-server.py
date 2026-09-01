#!/usr/bin/env python3
"""Verify the reviewed Object Lock backend and server boundary."""

from __future__ import annotations

import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "coverage/s3-operations.toml"
DOCUMENT = ROOT / "docs/qualification/object-lock-server.md"
BACKEND_SPEC = ROOT / "src/flyology-object_storage-backends.ads"
MEMORY = ROOT / "src/flyology-object_storage-backends-memory.adb"
FILES = ROOT / "src/flyology-object_storage-backends-files.adb"
SQLITE = ROOT / "sqlite/src/flyology-object_storage-backends-sqlite.adb"
CATALOG = ROOT / "sqlite/src/flyology-object_storage-sqlite-catalogs.adb"
SERVER = ROOT / "src/flyology-object_storage-server-s3_applications.adb"
BACKEND_TEST = ROOT / "tests/src/object_storage_test_cases.adb"
SQLITE_TEST = (
    ROOT / "sqlite/tests/src/flyology_object_storage_sqlite_tests.adb"
)
SERVER_TEST = ROOT / "tests/src/s3_server_application_corpus.adb"
CLIENT_RECORDS = (
    ROOT / "docs/qualification/get-object-legal-hold.md",
    ROOT / "docs/qualification/put-object-legal-hold.md",
    ROOT / "docs/qualification/get-object-retention.md",
    ROOT / "docs/qualification/put-object-retention.md",
    ROOT / "docs/qualification/get-object-lock-configuration.md",
    ROOT / "docs/qualification/put-object-lock-configuration.md",
)

OPERATIONS = {
    "GetObjectLegalHold": (
        "Get_Legal_Hold",
        "get_object_legal_hold",
        "tools/verify-get-object-legal-hold-preparation.py",
        "s3_get_object_legal_hold_corpus",
    ),
    "PutObjectLegalHold": (
        "Put_Legal_Hold",
        "put_object_legal_hold",
        "tools/verify-put-object-legal-hold-preparation.py",
        "s3_put_object_legal_hold_corpus",
    ),
    "GetObjectRetention": (
        "Get_Retention",
        "get_object_retention",
        "tools/verify-get-object-retention-preparation.py",
        "s3_get_object_retention_corpus",
    ),
    "PutObjectRetention": (
        "Put_Retention",
        "put_object_retention",
        "tools/verify-put-object-retention-preparation.py",
        "s3_put_object_retention_corpus",
    ),
    "GetObjectLockConfiguration": (
        "Get_Object_Lock_Configuration",
        "get_object_lock_configuration",
        "tools/verify-get-object-lock-configuration-preparation.py",
        "s3_get_object_lock_configuration_corpus",
    ),
    "PutObjectLockConfiguration": (
        "Put_Object_Lock_Configuration",
        "put_object_lock_configuration",
        "tools/verify-put-object-lock-configuration-preparation.py",
        "s3_put_object_lock_configuration_corpus",
    ),
}
BACKEND_EVIDENCE = [
    "tests/src/object_storage_test_cases.adb",
    "sqlite/tests/src/flyology_object_storage_sqlite_tests.adb",
]
SERVER_EVIDENCE = [
    "src/flyology-object_storage-server-s3_applications.adb",
    "tests/src/s3_server_application_corpus.adb",
]
SHARED_CORPUS = (
    "tools/verify-object-lock-server.py",
    "docs/qualification/object-lock-server.md",
    "tests/src/object_storage_test_cases.adb",
    "sqlite/tests/src/flyology_object_storage_sqlite_tests.adb",
    "tests/src/s3_server_application_corpus.adb",
)


class EvidenceError(RuntimeError):
    """One reviewed Object Lock invariant changed."""


def fail(message: str) -> None:
    raise EvidenceError(message)


def source(path: Path) -> str:
    if not path.is_file() or path.is_symlink():
        fail(f"missing or unsafe source: {path}")
    raw = path.read_bytes()
    if b"\r" in raw:
        fail(f"noncanonical CR byte: {path}")
    return raw.decode("utf-8")


def require(text: str, fragment: str, label: str) -> None:
    if fragment not in text:
        fail(f"{label} lacks {fragment!r}")


def require_once(text: str, fragment: str, label: str) -> None:
    count = text.count(fragment)
    if count != 1:
        fail(f"{label} expected one {fragment!r}, found {count}")


def require_in_order(
    text: str, fragments: tuple[str, ...] | list[str], label: str
) -> None:
    position = 0
    for fragment in fragments:
        position = text.find(fragment, position)
        if position < 0:
            fail(f"{label} lacks ordered fragment {fragment!r}")
        position += len(fragment)


def expected_lane(
    operation: str, verifier: str, corpus: str
) -> list[list[str]]:
    slug = (
        operation.replace(
            "ObjectLockConfiguration", "-object-lock-configuration"
        )
        .replace("ObjectLegalHold", "-object-legal-hold")
        .replace("ObjectRetention", "-object-retention")
        .replace("Get", "get", 1)
        .replace("Put", "put", 1)
    )
    return [
        ["uv", "run", "--python", "3.13", "--", verifier],
        [
            "uv",
            "run",
            "--python",
            "3.13",
            "--",
            "tools/verify-object-lock-server.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", f"./bin/{corpus}"],
        ["@tests", "./bin/s3_server_application_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
        [
            "./tools/build-api-docs.sh",
            f"{{repository}}/build/gnatdoc/{slug}",
        ],
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]


def verify_registry() -> None:
    registry = tomllib.loads(source(REGISTRY))
    entries = {entry["name"]: entry for entry in registry["operation"]}
    qualification = registry["qualification"]
    for operation, (public_name, lane, verifier, corpus) in OPERATIONS.items():
        entry = entries.get(operation)
        if entry is None:
            fail(f"registry lacks {operation}")
        if entry.get("public_name") != public_name:
            fail(f"{operation} public name changed")
        if entry.get("decision_status") != "reviewed":
            fail(f"{operation} is not reviewed")
        if entry.get("coverage") != {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        }:
            fail(f"{operation} coverage is incomplete")
        if entry.get("provenance") != {
            "backend": "handwritten",
            "client": "handwritten",
            "server": "handwritten",
            "tests": "handwritten",
        }:
            fail(f"{operation} provenance changed")
        evidence = entry.get("evidence", {})
        if evidence.get("backend") != BACKEND_EVIDENCE:
            fail(f"{operation} backend evidence changed")
        if evidence.get("server") != SERVER_EVIDENCE:
            fail(f"{operation} server evidence changed")
        for item in SHARED_CORPUS:
            if evidence.get("corpus", []).count(item) != 1:
                fail(f"{operation} lacks unique shared evidence {item}")
        claims = " ".join(entry.get("exclusions", []))
        if (
            "server route are absent" in claims
            or "Object Lock persistence" in claims
        ):
            fail(f"{operation} retains a stale backend/server exclusion")
        if "Put" in operation and "no automatic replay" not in (
            entry.get("certainty", "") + entry.get("reconciliation", "")
        ):
            fail(f"{operation} lost its no-replay contract")
        if qualification.get(lane) != expected_lane(
            operation, verifier, corpus
        ):
            fail(f"{operation} qualification lane changed")


def verify_backend_sources() -> None:
    interface = source(BACKEND_SPEC)
    for name in (
        "Enable_Bucket_Object_Lock",
        "Get_Bucket_Object_Lock",
        "Put_Object_Legal_Hold",
        "Get_Object_Legal_Hold",
        "Put_Object_Retention",
        "Get_Object_Retention",
    ):
        require(interface, f"procedure {name}", "backend interface")
        for path in (MEMORY, FILES, SQLITE):
            require(source(path), f"overriding procedure {name}", path.name)

    files = source(FILES)
    require(files, 'Magic : constant String := "FOSOBJ06";',
            "filesystem object record")
    require_in_order(
        files,
        (
            "if Object_Lock.Legal_Hold = Object_Legal_Hold_On",
            "case Object_Lock.Retention.Mode is",
            "Object_Lock.Retention.Retain_Until",
            "Object_Lock.Retention.Exact_Text",
            "if File_Magic = Magic then",
            "Hold_Code not in 'F' | 'O'",
            "Mode_Code not in 'N' | 'G' | 'C'",
            "Object_Lock.Legal_Hold :=",
            "Object_Lock.Retention :=",
        ),
        "filesystem object record",
    )
    require(files, '"FOSLCK01"', "filesystem bucket lock record")
    require(
        files,
        'Metadata_Magic : constant String := "FOSOBJ05";',
        "filesystem legacy reader",
    )

    catalog = source(CATALOG)
    require(catalog, "Schema_Version : constant Long_Long_Integer := 23;",
            "SQLite schema")
    require(catalog, "CREATE TABLE bucket_object_locks", "SQLite schema")
    require(catalog, "CREATE TABLE object_version_locks", "SQLite schema")
    require(catalog, "Check_Object_Lock_Bucket_Internal", "SQLite policy")


def verify_backend_evidence() -> None:
    backend = source(BACKEND_TEST)
    require_once(backend, "procedure Exercise_Object_Lock", "backend test")
    require_in_order(
        backend,
        (
            "Object Lock was enabled before bucket versioning",
            "PutObjectLegalHold/GetObjectLegalHold state did not round trip",
            "PutObjectRetention/GetObjectRetention did not round trip",
            "active governance retention was shortened without bypass",
            "protected current delete did not publish a delete marker",
            "procedure Corrupt_Selected_Object_Lock_Record",
            'Matches (Data, Data\'First, "FOSOBJ06")',
            "legal-hold byte was not canonical",
            "Character'Pos ('X')",
            "legal-hold corruption was inert",
            "filesystem reopen lost bucket Object Lock state",
            "filesystem reopen lost exact retention state",
            "FOSOBJ05 did not default legal hold to OFF",
            "filesystem backend accepted corrupt FOSOBJ06 legal hold",
            "filesystem backend did not reject corrupt Object Lock state",
        ),
        "backend Object Lock evidence",
    )
    sqlite = source(SQLITE_TEST)
    require_in_order(
        sqlite,
        (
            "schema-v20 migration invented Object Lock state",
            "schema-v20 migration could not persist Object Lock state",
            "migrated Object Lock state did not survive reopen",
            "legal hold allowed exact protected deletion",
            "active retention allowed exact protected deletion",
            "expired retention did not release exact deletion",
            "schema 23 accepted malformed Object Lock constraints",
        ),
        "SQLite Object Lock evidence",
    )


def verify_server_sources() -> None:
    server = source(SERVER)
    require(server, "function Retention_Deadline", "server timestamp parser")
    require(server, "Round any nonzero fractional", "timestamp policy")
    require_in_order(
        server,
        (
            "Put_Object_Lock_Configuration",
            "Get_Object_Lock_Configuration",
            "Put_Object_Legal_Hold",
            "Get_Object_Legal_Hold",
            "Put_Object_Retention",
            "Get_Object_Retention",
        ),
        "server Object Lock dispatch",
    )
    for fragment in (
        'Parse_Object_Lock_Query\n          (Query_Text, "object-lock"',
        'Parse_Object_Lock_Query\n          (Query_Text, "legal-hold"',
        'Parse_Object_Lock_Query\n          (Query_Text, "retention"',
        "Bypass_Count : constant Natural :=",
        '"x-amz-bypass-governance-retention"',
        "Governance bypass authorization is not implemented",
        "Read_Object_Lock_Document",
        "Store.Enable_Bucket_Object_Lock",
        "Store.Put_Object_Legal_Hold",
        "Store.Get_Object_Legal_Hold",
        "Store.Put_Object_Retention",
        "Store.Get_Object_Retention",
    ):
        require(server, fragment, "server Object Lock boundary")

    corpus = source(SERVER_TEST)
    require_in_order(
        corpus,
        (
            "PutObjectLockConfiguration enabled an unversioned bucket",
            "PutObjectLockConfiguration accepted a default retention rule",
            "enabled Object Lock allowed versioning suspension",
            "Object Lock first version identity was not retained",
            "PutObjectLegalHold rejected an exact selected version",
            "legal-hold exact-version selection leaked across versions",
            "PutObjectRetention accepted governance bypass",
            "PutObjectRetention accepted a mismatched checksum",
            '"2099-01-01T01:00:00.500+01:00"',
            "Retention.Retain_Until = 4_070_908_801",
            "fractional retention deadline was not rounded upward",
            "retention exact-version selection leaked across versions",
            "Retention.Retain_Until = 946_684_800",
            '"2000-01-01T00:00:00.000Z"',
            "all-zero retention fraction changed the deadline",
            "Retention.Retain_Until = 946_684_801",
            '"1999-12-31T23:00:00.500-01:00"',
            "negative-offset retention deadline was not normalized",
            "DeleteObject removed a version under legal hold",
            "current deletion changed the retained exact version",
            "cleared legal hold still prevented exact deletion",
        ),
        "server Object Lock corpus",
    )


def verify_document() -> None:
    document = " ".join(source(DOCUMENT).split())
    require_in_order(
        document,
        (
            "Object Lock backend and server evidence",
            "exact selected object version",
            "does not authorize automatic replay",
            "FOSOBJ06",
            "schema 21",
            "measurement and evidence record, not a qualification claim",
        ),
        "Object Lock qualification addendum",
    )
    for path in CLIENT_RECORDS:
        record = " ".join(source(path).split())
        require(
            record,
            "covered / covered / covered / covered",
            path.name,
        )
        require(record, "object-lock-server.md", path.name)
        for stale in (
            "missing / covered / missing / covered",
            "backend and server support remain absent",
            "does not claim Object Lock persistence",
            "makes no backend, server",
        ):
            if stale in record:
                fail(f"{path.name} retains stale claim {stale!r}")


def main() -> int:
    verify_registry()
    verify_backend_sources()
    verify_backend_evidence()
    verify_server_sources()
    verify_document()
    print(
        "Object Lock server/backend preparation: 6 operations, 3 backends, "
        "exact-version enforcement and fail-closed transport evidence match"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
