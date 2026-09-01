#!/usr/bin/env python3
"""Fail closed on the coherent bucket-configuration list boundary."""

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
BACKEND = ROOT / "src" / "flyology-object_storage-backends.ads"
MEMORY = ROOT / "src" / "flyology-object_storage-backends-memory.ads"
FILES = ROOT / "src" / "flyology-object_storage-backends-files.ads"
SQLITE = (
    ROOT / "sqlite" / "src"
    / "flyology-object_storage-backends-sqlite.ads"
)
SERVER = ROOT / "src" / "flyology-object_storage-server-s3_applications.adb"
SERVER_TEST = ROOT / "tests" / "src" / "s3_server_application_corpus.adb"
BACKEND_TEST = ROOT / "tests" / "src" / "object_storage_test_cases.adb"
SQLITE_TEST = (
    ROOT / "sqlite" / "tests" / "src"
    / "flyology_object_storage_sqlite_tests.adb"
)
DOCUMENT = ROOT / "docs" / "qualification" / (
    "list-bucket-configurations.md"
)

OPERATIONS = {
    "ListBucketAnalyticsConfigurations": {
        "public": "List_Analytics_Configurations",
        "request": "ListBucketAnalyticsConfigurationsRequest",
        "output": "ListBucketAnalyticsConfigurationsOutput",
        "query": "/{Bucket}?analytics",
        "procedure": "List_Bucket_Analytics_Configurations",
        "codec": "analytics",
        "item": "AnalyticsConfigurationList",
        "output_members": [
            "IsTruncated",
            "ContinuationToken",
            "NextContinuationToken",
            "AnalyticsConfigurationList",
        ],
        "maximum": "100",
    },
    "ListBucketIntelligentTieringConfigurations": {
        "public": "List_Intelligent_Tiering_Configurations",
        "request": "ListBucketIntelligentTieringConfigurationsRequest",
        "output": "ListBucketIntelligentTieringConfigurationsOutput",
        "query": "/{Bucket}?intelligent-tiering",
        "procedure": "List_Bucket_Intelligent_Tiering_Configurations",
        "codec": "intelligent_tiering",
        "item": "IntelligentTieringConfigurationList",
        "output_members": [
            "IsTruncated",
            "ContinuationToken",
            "NextContinuationToken",
            "IntelligentTieringConfigurationList",
        ],
        "maximum": "storage",
    },
    "ListBucketInventoryConfigurations": {
        "public": "List_Inventory_Configurations",
        "request": "ListBucketInventoryConfigurationsRequest",
        "output": "ListBucketInventoryConfigurationsOutput",
        "query": "/{Bucket}?inventory",
        "procedure": "List_Bucket_Inventory_Configurations",
        "codec": "inventory",
        "item": "InventoryConfigurationList",
        "output_members": [
            "ContinuationToken",
            "InventoryConfigurationList",
            "IsTruncated",
            "NextContinuationToken",
        ],
        "maximum": "100",
    },
    "ListBucketMetricsConfigurations": {
        "public": "List_Metrics_Configurations",
        "request": "ListBucketMetricsConfigurationsRequest",
        "output": "ListBucketMetricsConfigurationsOutput",
        "query": "/{Bucket}?metrics",
        "procedure": "List_Bucket_Metrics_Configurations",
        "codec": "metrics",
        "item": "MetricsConfigurationList",
        "output_members": [
            "IsTruncated",
            "ContinuationToken",
            "NextContinuationToken",
            "MetricsConfigurationList",
        ],
        "maximum": "100",
    },
}


class Evidence_Error(RuntimeError):
    """One reviewed bucket-configuration invariant changed."""


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


def expect_failure(action, label: str) -> None:
    try:
        action()
    except (AssertionError, Evidence_Error, IndexError, KeyError, TypeError):
        return
    fail(f"negative candidate was accepted: {label}")


def load_model() -> dict[str, object]:
    name = os.environ.get("FLYOLOGY_S3_SERVICE_MODEL", "")
    if not name:
        fail("FLYOLOGY_S3_SERVICE_MODEL is required")
    path = Path(name)
    source(path)
    if digest(path) != MODEL_SHA256:
        fail("pinned S3 model hash changed")
    return json.loads(path.read_text(encoding="utf-8"))


def verify_model(model: dict[str, object]) -> None:
    shapes = model["shapes"]
    for name, expected in OPERATIONS.items():
        operation = model["operations"][name]
        assert operation["http"] == {
            "method": "GET",
            "requestUri": expected["query"],
        }
        assert operation["input"] == {"shape": expected["request"]}
        assert operation["output"] == {"shape": expected["output"]}
        request = shapes[expected["request"]]
        assert request["required"] == ["Bucket"]
        assert list(request["members"]) == [
            "Bucket",
            "ContinuationToken",
            "ExpectedBucketOwner",
        ]
        assert request["members"]["ContinuationToken"] == {
            "shape": "Token",
            "documentation": request["members"]["ContinuationToken"][
                "documentation"
            ],
            "location": "querystring",
            "locationName": "continuation-token",
        }
        output = shapes[expected["output"]]
        assert list(output["members"]) == expected["output_members"]
        assert "responseCode" not in operation["http"]
        if expected["maximum"] == "100":
            assert "does not return more than 100 configurations" in (
                operation["documentation"]
            )
        else:
            assert "does not return more than 100 configurations" not in (
                operation["documentation"]
            )


def expected_lane() -> list[list[str]]:
    return [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-list-bucket-configurations-preparation.py",
        ],
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/test-s3-operation-registry.py",
        ],
        ["@tests", "alr", "-n", "build"],
        *[
            [
                "@tests", "uv", "run", "--python", "3.13", "--",
                "../tools/s3-signed-socket.py", operation,
            ]
            for operation in OPERATIONS
        ],
        ["@tests", "./bin/s3_server_application_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
        [
            "./tools/build-api-docs.sh",
            "{repository}/build/gnatdoc/list-bucket-configurations",
        ],
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]


def expected_symbols(expected: dict[str, object]) -> list[str]:
    procedure = expected["procedure"]
    return [
        f"Prepare_{procedure}",
        f"Execute_{procedure}",
        procedure.removesuffix("_Configurations") + "_Operation",
        expected["public"],
        "Finish",
    ]


def expected_evidence(
    expected: dict[str, object],
) -> dict[str, list[str]]:
    codec = expected["codec"]
    qualification = (
        f"tests/src/s3_list_bucket_{codec}_configurations_qualification.adb"
    )
    return {
        "backend": [
            "tests/src/object_storage_test_cases.adb",
            "sqlite/tests/src/flyology_object_storage_sqlite_tests.adb",
        ],
        "client": [
            "src/flyology-object_storage-s3-paginated_rest_xml_reads.adb",
            f"src/flyology-object_storage-s3-{codec}.adb",
            "src/flyology-object_storage-client-low_level.adb",
            "src/flyology-object_storage-client-buckets.adb",
            qualification,
        ],
        "server": [
            f"src/flyology-object_storage-s3-{codec}.ads",
            f"src/flyology-object_storage-s3-{codec}.adb",
            "src/flyology-object_storage-server-s3_applications.adb",
            "tests/src/s3_server_application_corpus.adb",
        ],
        "corpus": [
            "tools/verify-list-bucket-configurations-preparation.py",
            "docs/qualification/list-bucket-configurations.md",
            "tests/generated/s3-negative-xml.json",
            "tests/generated/s3-signed-socket.json",
            qualification,
            "tests/src/s3_server_application_corpus.adb",
        ],
    }


def entries(data: dict[str, object]) -> dict[str, dict[str, object]]:
    result = {
        item["name"]: item
        for item in data["operation"]
        if item["name"] in OPERATIONS
    }
    if set(result) != set(OPERATIONS):
        fail("bucket-configuration registry inventory changed")
    if sum(
        item["name"] in OPERATIONS for item in data["operation"]
    ) != len(OPERATIONS):
        fail("bucket-configuration registry entry is duplicated")
    return result


def verify_registry_data(data: dict[str, object]) -> None:
    assert data["model_sha256"] == MODEL_SHA256
    selected = entries(data)
    for name, expected in OPERATIONS.items():
        entry = selected[name]
        assert entry["public_name"] == expected["public"]
        assert entry["family"] == "paginated_rest_xml_read"
        assert entry["implementation_mode"] == "shared-family"
        assert entry["decision_status"] == "reviewed"
        assert entry["human_decisions_resolved"] is True
        assert entry["qualification"] == "list_bucket_configurations"
        assert entry["ada_symbols"] == expected_symbols(expected)
        assert entry["evidence"] == expected_evidence(expected)
        assert entry["coverage"] == {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        }
        assert "exact HTTP 200" in entry["absence"]
        assert "404 NoSuchBucket maps to Not_Found" in entry["absence"]
        assert "no next-page request is automatic" in entry["certainty"]
        assert expected["public"] in entry["reconciliation"]
        assert "does not create a cross-page snapshot" in (
            entry["reconciliation"]
        )
        assert "request identifiers bytewise" in entry["exclusions"][1]
        assert "payload Id remains independent" in entry["exclusions"][1]
        assert "atomic current snapshot" in entry["exclusions"][2]
        assert (
            "tools/verify-list-bucket-configurations-preparation.py"
            in entry["evidence"]["corpus"]
        )
        if expected["maximum"] == "100":
            assert "at most 100" in entry["exclusions"][0]
        else:
            assert "states no Intelligent-Tiering service page maximum" in (
                entry["exclusions"][0]
            )
            assert "1,000-per-family storage ceiling" in (
                entry["exclusions"][0]
            )
            assert "no AWS page-size compatibility claim" in (
                entry["exclusions"][0]
            )
    assert data["qualification"]["list_bucket_configurations"] == (
        expected_lane()
    )


def verify_registry() -> None:
    data = tomllib.loads(source(REGISTRY))
    verify_registry_data(data)

    def reject(candidate: dict[str, object], label: str) -> None:
        if candidate == data:
            fail(f"negative candidate did not mutate: {label}")
        expect_failure(
            lambda candidate=candidate: verify_registry_data(candidate),
            label,
        )

    mutations = [
        (
            "wrong empty-page result",
            lambda item: item.__setitem__("absence", "empty means absent"),
        ),
        (
            "automatic next page",
            lambda item: item.__setitem__(
                "certainty", "read-only; automatically fetch next page"
            ),
        ),
        (
            "cross-page snapshot",
            lambda item: item.__setitem__(
                "reconciliation", "token freezes a cross-page snapshot"
            ),
        ),
        (
            "payload identifier order",
            lambda item: item["exclusions"].__setitem__(
                1, "payload Id determines page order"
            ),
        ),
        (
            "missing server coverage",
            lambda item: item["coverage"].__setitem__(
                "server", "missing"
            ),
        ),
    ]
    for label, mutate in mutations:
        candidate = copy.deepcopy(data)
        mutate(entries(candidate)["ListBucketAnalyticsConfigurations"])
        reject(candidate, label)
    candidate = copy.deepcopy(data)
    entries(candidate)[
        "ListBucketIntelligentTieringConfigurations"
    ]["exclusions"][0] = "AWS returns at most 100 configurations"
    reject(candidate, "invented Intelligent-Tiering page cap")
    candidate = copy.deepcopy(data)
    candidate["qualification"]["list_bucket_configurations"].pop(0)
    reject(candidate, "missing preparation verifier")
    candidate = copy.deepcopy(data)
    entries(candidate)["ListBucketMetricsConfigurations"][
        "qualification"
    ] = "list_bucket_metrics_configurations"
    reject(candidate, "detached family lane")
    candidate = copy.deepcopy(data)
    candidate["operation"].append(
        copy.deepcopy(
            entries(candidate)["ListBucketAnalyticsConfigurations"]
        )
    )
    reject(candidate, "duplicate registry entry")
    candidate = copy.deepcopy(data)
    selected = entries(candidate)
    selected["ListBucketAnalyticsConfigurations"]["public_name"] = (
        "List_Metrics_Configurations"
    )
    selected["ListBucketMetricsConfigurations"]["public_name"] = (
        "List_Analytics_Configurations"
    )
    reject(candidate, "cross-operation public names")
    candidate = copy.deepcopy(data)
    selected = entries(candidate)
    analytics = selected["ListBucketAnalyticsConfigurations"]
    metrics = selected["ListBucketMetricsConfigurations"]
    analytics["ada_symbols"], metrics["ada_symbols"] = (
        metrics["ada_symbols"],
        analytics["ada_symbols"],
    )
    reject(candidate, "cross-operation Ada symbols")
    for section in ("client", "server"):
        candidate = copy.deepcopy(data)
        selected = entries(candidate)
        analytics = selected["ListBucketAnalyticsConfigurations"]
        metrics = selected["ListBucketMetricsConfigurations"]
        analytics["evidence"][section], metrics["evidence"][section] = (
            metrics["evidence"][section],
            analytics["evidence"][section],
        )
        reject(candidate, f"cross-operation {section} evidence")
    candidate = copy.deepcopy(data)
    entries(candidate)["ListBucketInventoryConfigurations"]["evidence"][
        "corpus"
    ].remove(
        "tests/src/s3_list_bucket_inventory_configurations_qualification.adb"
    )
    reject(candidate, "missing operation corpus evidence")
    candidate = copy.deepcopy(data)
    candidate["qualification"]["list_bucket_configurations"].pop(4)
    reject(candidate, "missing middle signed-socket command")


def verify_backend_sources() -> None:
    backend = source(BACKEND)
    require_in_order(
        backend,
        [
            "type Listed_Bucket_Configuration is record",
            "Identifier : Ada.Strings.Unbounded.Unbounded_String;",
            "Document   : Ada.Strings.Unbounded.Unbounded_String;",
            "type List_Bucket_Configurations_Options is record",
            "Has_After     : Boolean;",
            "After         : Ada.Strings.Unbounded.Unbounded_String;",
            "Maximum       : List_Limit;",
            "Maximum_Bytes : Byte_Count;",
            "type Bucket_Configuration_Page is record",
            "Configurations : Listed_Bucket_Configuration_Vectors.Vector;",
            "Is_Truncated   : Boolean := False;",
            "Next_After     : Ada.Strings.Unbounded.Unbounded_String;",
        ],
        "backend page contract",
    )
    assert "Identifier remains independent from any modeled Id" in backend
    for expected in OPERATIONS.values():
        marker = f"procedure {expected['procedure']}\n"
        require_once(backend, marker, "abstract backend operation")
        for path in (MEMORY, FILES, SQLITE):
            require_once(
                source(path),
                f"overriding procedure {expected['procedure']}\n",
                f"{path.name} backend override",
            )


def verify_server_and_tests() -> None:
    server = source(SERVER)
    server_test = source(SERVER_TEST)
    backend_test = source(BACKEND_TEST)
    sqlite_test = source(SQLITE_TEST)
    list_region = unique_region(
        server,
        "            when List_Bucket_Analytics | List_Bucket_Metrics |",
        "            when Delete_Bucket_Analytics | Delete_Bucket_Metrics |",
        "server list-configuration branch",
    )
    for name, expected in OPERATIONS.items():
        procedure = expected["procedure"]
        if procedure not in list_region:
            fail(f"server omits {procedure}")
        if name not in server_test:
            fail(f"server corpus omits {name}")
        if procedure not in backend_test:
            fail(f"backend corpus omits {procedure}")
        if procedure not in sqlite_test:
            fail(f"SQLite corpus omits {procedure}")
    require_in_order(
        list_region,
        [
            "Maximum_Bytes => Maximum_Bucket_Configuration_Body",
            "Bucket_Configuration_Page",
            "<IsTruncated>",
            "Request.Has_Continuation_Token",
            "<ContinuationToken>",
            "Page.Is_Truncated",
            "<NextContinuationToken>",
            "Encode_Configuration_Continuation",
            "for Configuration of Page.Configurations loop",
        ],
        "server response construction",
    )
    require_in_order(
        list_region,
        [
            "Request.Has_Continuation_Token",
            "Resolve_Configuration_Continuation",
            "Options.Has_After := True;",
            "Options.After := Resolved_After;",
            "Load_Page (Options, Page, Result);",
            "if Result = Invalid_Request then",
            "The backend page cannot be represented within ",
            "elsif Result /= Success then",
            "Page.Is_Truncated",
            "Page.Configurations.Is_Empty",
            "Response : constant String := Serialize_Page;",
            "if Response'Length <= Response_Budget then",
            "Apps.Respond",
            "Returned_Bytes := Returned_Bytes +",
            "Overflow : constant Byte_Count :=",
            "Byte_Count (Response'Length - Response_Budget);",
            "if Overflow >= Returned_Bytes",
            "else Returned_Bytes - Overflow",
        ],
        "server pagination path",
    )
    assert "The continuation token provided is incorrect" in list_region
    for fragment, label in (
        (
            "configuration listing did not reserve its XML envelope",
            "near-limit envelope test",
        ),
        (
            "an empty-identifier cursor restarted the listing",
            "empty-identifier progress test",
        ),
        (
            "an over-envelope configuration produced a partial page",
            "over-envelope rejection test",
        ),
        (
            "configuration cursor did not preserve a large binary id",
            "large binary identifier cursor test",
        ),
        (
            "malformed configuration continuation token was accepted",
            "malformed cursor rejection test",
        ),
        (
            "deleted marker did not invalidate configuration cursor",
            "deleted cursor marker rejection test",
        ),
    ):
        require_once(server_test, fragment, label)
    require_once(
        backend_test,
        "an unrepresentable named-configuration page did not fail closed",
        "backend unrepresentable-page test",
    )
    require_once(
        sqlite_test,
        "SQLite unrepresentable configuration page did not fail closed",
        "SQLite unrepresentable-page test",
    )


def verify_document() -> None:
    document = source(DOCUMENT)
    normalized = " ".join(document.split())
    require_in_order(
        normalized,
        [
            "exact bytewise lexical order",
            "bound internally to the exact bucket and configuration family",
            "empty token supplied by the caller remains explicitly present",
            "one atomic snapshot current at that call",
            "neither freezes a cross-page snapshot",
            "deleting that marker invalidates the token",
            "at most 100 configurations per page for Analytics",
            "states no page maximum for Intelligent-Tiering",
            "existing 1,000 configuration per-family storage ceiling",
            "not an AWS page-size compatibility claim",
            "fails closed rather than exposing a partial configuration",
            "does not independently claim qualification",
        ],
        "qualification contract",
    )
    candidate = normalized.replace(
        "neither freezes a cross-page snapshot",
        "freezes a cross-page snapshot",
        1,
    )
    if candidate == normalized:
        fail("documentation negative did not mutate")
    expect_failure(
        lambda: require_in_order(
            candidate,
            ["neither freezes a cross-page snapshot"],
            "cross-page overclaim",
        ),
        "cross-page overclaim",
    )


def main() -> None:
    verify_model(load_model())
    verify_registry()
    verify_backend_sources()
    verify_server_and_tests()
    verify_document()
    print("ListBucketConfigurations preparation evidence: OK")


if __name__ == "__main__":
    main()
