#!/usr/bin/env python3
"""Shared pinned-model and evidence support for S3 operation work."""

from __future__ import annotations

import hashlib
import http
import json
import os
import re
import shlex
import subprocess
import tomllib
import urllib.parse
import xml.etree.ElementTree as ET
from copy import deepcopy
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

ROOT = Path(__file__).resolve().parents[1]
REGISTRY_PATH = ROOT / "coverage/s3-operations.toml"
LEDGER_PATH = ROOT / "coverage/aws-s3-operations.tsv"
COUNTS_PATH = ROOT / "coverage/s3-operation-counts.json"
INVENTORY_PATH = ROOT / "coverage/s3-operation-inventory.json"
TEST_REGISTRATION_PATH = ROOT / "tests/generated/s3-operation-tests.sh"
DOCUMENTATION_PATH = ROOT / "docs/generated/s3-operation-registry.md"
NEGATIVE_XML_PATH = ROOT / "tests/generated/s3-negative-xml.json"
SIGNED_SOCKET_PATH = ROOT / "tests/generated/s3-signed-socket.json"
# These values identify the committed Botocore service model that owns the
# generated S3 schema. Changing any of them is a model compatibility update,
# not a coverage-policy choice.
EXPECTED_MODEL_SHA256 = (
    "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
)
EXPECTED_MODEL_REVISION = "36c34f15391da01cd717c73c0fffa747c9889768"
EXPECTED_OPERATION_COUNT = 116
EXPECTED_SHAPE_COUNT = 718
LAYERS = ("backend", "client", "server", "corpus")
COVERAGE_STATES = {"missing", "partial", "covered"}
PROVENANCE_STATES = {"absent", "handwritten", "generated", "shared_family"}
IMPLEMENTATION_MODES = {"handwritten", "generated", "shared-family"}
PROVIDERS = {"buckets", "objects", "transfers"}
FAMILIES = {
    "bodyless_mutation",
    "bounded_binary_read",
    "bounded_document_read",
    "bounded_rest_xml_read",
    "event_stream_read",
    "paginated_rest_xml_read",
    "response_head_read",
    "rest_xml_mutation",
    "streaming_mutation",
    "streaming_read",
}


class Audit_Error(ValueError):
    """A registry or pinned-model invariant is not satisfied."""


@dataclass(frozen=True)
class Registry:
    metadata: dict[str, Any]
    operations: dict[str, dict[str, Any]]
    qualification: dict[str, list[list[str]]]


def load_registry(path: Path = REGISTRY_PATH) -> Registry:
    raw = tomllib.loads(path.read_text(encoding="utf-8"))
    if raw.get("schema_version") != 2:
        raise Audit_Error("unsupported S3 operation registry schema")
    if raw.get("model_sha256") != EXPECTED_MODEL_SHA256:
        raise Audit_Error("registry names an unexpected pinned model hash")
    if raw.get("model_revision") != EXPECTED_MODEL_REVISION:
        raise Audit_Error("registry names an unexpected pinned model revision")
    default_decision_status = raw.get("default_decision_status")
    if default_decision_status != "inventory_only":
        raise Audit_Error("unexpected default operation decision status")
    default_public_name = raw.get("default_public_name")
    if default_public_name != "legacy_preserved":
        raise Audit_Error("unexpected default public operation name")
    entries = raw.get("operation", [])
    for entry in entries:
        entry.setdefault("decision_status", default_decision_status)
        entry.setdefault("public_name", default_public_name)
    operations = {entry["name"]: entry for entry in entries}
    if len(operations) != len(entries):
        raise Audit_Error("duplicate operation registry entry")
    if len(operations) != EXPECTED_OPERATION_COUNT:
        raise Audit_Error(
            f"registry has {len(operations)} operations, expected "
            f"{EXPECTED_OPERATION_COUNT}"
        )
    for name, entry in operations.items():
        required = (
            "tier",
            "provider",
            "family",
            "public_provider",
            "codec",
            "absence",
            "errors",
            "certainty",
            "reconciliation",
            "exclusions",
            "coverage",
            "provenance",
            "implementation_mode",
            "generator_eligible",
            "human_decisions_resolved",
            "evidence",
        )
        missing = [field for field in required if field not in entry]
        if missing:
            raise Audit_Error(
                f"registry entry {name} lacks fields: {', '.join(missing)}"
            )
        coverage = entry["coverage"]
        provenance = entry["provenance"]
        if set(coverage) != set(LAYERS):
            raise Audit_Error(f"invalid coverage layers: {name}")
        if any(state not in COVERAGE_STATES for state in coverage.values()):
            raise Audit_Error(f"invalid coverage state: {name}")
        expected_provenance = {"backend", "client", "server", "tests"}
        if set(provenance) != expected_provenance:
            raise Audit_Error(f"invalid provenance layers: {name}")
        if any(state not in PROVENANCE_STATES for state in provenance.values()):
            raise Audit_Error(f"invalid provenance state: {name}")
        if entry["implementation_mode"] not in IMPLEMENTATION_MODES:
            raise Audit_Error(f"invalid implementation mode: {name}")
        expected_mode = {
            "handwritten": "handwritten",
            "generated": "generated",
            "shared_family": "shared-family",
        }[provenance["client"]]
        if entry["implementation_mode"] != expected_mode:
            raise Audit_Error(
                f"client provenance/implementation mode mismatch: {name}"
            )
        if not isinstance(entry["generator_eligible"], bool):
            raise Audit_Error(f"invalid generator eligibility: {name}")
        if not isinstance(entry["human_decisions_resolved"], bool):
            raise Audit_Error(f"invalid human decision state: {name}")
        if entry["human_decisions_resolved"] != (
            entry["decision_status"] == "reviewed"
        ):
            raise Audit_Error(f"decision status/state mismatch: {name}")
        if entry["generator_eligible"] and entry["implementation_mode"] != "generated":
            raise Audit_Error(
                f"authoritative existing implementation marked generator eligible: {name}"
            )
        generation = entry.get("generation")
        if entry["generator_eligible"]:
            required_generation = {
                "public_result",
                "response_representation",
                "replay",
                "ownership",
                "retained_borrows",
                "cross_field_validation",
                "intentional_exclusions",
            }
            if not isinstance(generation, dict) or set(generation) != required_generation:
                raise Audit_Error(f"invalid generation decisions: {name}")
            if any(
                not isinstance(generation[field], str)
                or not generation[field]
                for field in required_generation - {"intentional_exclusions"}
            ) or not isinstance(generation["intentional_exclusions"], list):
                raise Audit_Error(f"invalid generation decision values: {name}")
        elif generation is not None:
            raise Audit_Error(
                f"non-eligible operation carries generation decisions: {name}"
            )
        if entry["provider"] not in PROVIDERS:
            raise Audit_Error(f"invalid provider: {name}")
        if entry["family"] not in FAMILIES:
            raise Audit_Error(f"invalid operation family: {name}")
        expected_provider = (
            "Flyology.Object_Storage.Client."
            + entry["provider"].capitalize()
        )
        if entry["public_provider"] != expected_provider:
            raise Audit_Error(f"provider/package ownership mismatch: {name}")
        if any(
            coverage[layer] == "missing" and provenance[layer] != "absent"
            for layer in ("backend", "client", "server")
        ):
            raise Audit_Error(f"missing layer has non-absent provenance: {name}")
        evidence = entry["evidence"]
        if set(evidence) != set(LAYERS) or any(
            not isinstance(paths, list)
            or any(not isinstance(path, str) or not path for path in paths)
            for paths in evidence.values()
        ):
            raise Audit_Error(f"invalid layer-specific evidence: {name}")
        if any(
            coverage[layer] == "missing" and evidence[layer]
            for layer in LAYERS
        ):
            raise Audit_Error(f"missing layer cites evidence: {name}")
        if any(
            coverage[layer] == "covered" and not evidence[layer]
            for layer in LAYERS
        ):
            raise Audit_Error(f"covered layer lacks evidence: {name}")
    qualification = raw.get("qualification", {})
    for name, commands in qualification.items():
        if not isinstance(commands, list) or any(
            not isinstance(command, list)
            or not command
            or any(not isinstance(part, str) or not part for part in command)
            for command in commands
        ):
            raise Audit_Error(f"invalid qualification command list: {name}")
    registration = raw.get("test_registration", {})
    for name in ("model_verifiers", "corpora", "socket_qualifiers"):
        commands = registration.get(name)
        if not isinstance(commands, list) or any(
            not isinstance(command, list)
            or not command
            or any(not isinstance(part, str) or not part for part in command)
            for command in commands
        ):
            raise Audit_Error(f"invalid generated test registration: {name}")
        if len({tuple(command) for command in commands}) != len(commands):
            raise Audit_Error(f"duplicate generated test registration: {name}")
    expected_counts = {
        "model_verifiers": registration.get("model_verifier_count"),
        "corpora": registration.get("corpus_count"),
        "socket_qualifiers": registration.get("socket_qualifier_count"),
    }
    for name, expected in expected_counts.items():
        if expected != len(registration[name]):
            raise Audit_Error(
                f"generated test registration count changed: {name}"
            )
    if (
        not isinstance(registration.get("corpus_repetitions"), int)
        or isinstance(registration["corpus_repetitions"], bool)
        or registration["corpus_repetitions"] < 1
    ):
        raise Audit_Error("invalid generated corpus repetition count")
    validate_test_registration(registration, set(operations))
    for name, entry in operations.items():
        validate_operation_qualification(name, entry)
    return Registry(raw, operations, qualification)


def validate_test_registration(
    registration: dict[str, Any], operation_names: set[str]
) -> None:
    """Bind generated commands to maintained verifier and corpus sources."""
    for command in registration["model_verifiers"]:
        if command[:5] != ["uv", "run", "--python", "3.13", "--"]:
            raise Audit_Error(
                f"model verifier does not use pinned uv Python: {command}"
            )
        verifier = repository_path(command[-1])
        if not verifier.is_file() or verifier.suffix != ".py":
            raise Audit_Error(f"missing registered model verifier: {command[-1]}")
    for command in registration["corpora"]:
        binary = Path(command[0])
        if (
            len(command) != 1
            or not command[0].startswith("./bin/")
            or binary.parts != ("bin", binary.name)
            or not binary.name.replace("_", "").isalnum()
        ):
            raise Audit_Error(f"invalid registered operation corpus: {command}")
        source = ROOT / "tests/src" / (binary.name + ".adb")
        if not source.is_file():
            raise Audit_Error(
                f"registered operation corpus lacks maintained source: {source.name}"
            )
    for command in registration["socket_qualifiers"]:
        if command[:5] != ["uv", "run", "--python", "3.13", "--"]:
            raise Audit_Error(
                f"socket qualifier does not use pinned uv Python: {command}"
            )
        if len(command) != 7 or command[5] != "../tools/s3-signed-socket.py":
            raise Audit_Error(f"invalid socket qualifier command: {command}")
        if command[6] not in operation_names:
            raise Audit_Error(
                f"socket qualifier names unknown operation: {command[6]}"
            )


def validate_operation_qualification(name: str, entry: dict[str, Any]) -> None:
    negative = entry.get("negative_xml")
    socket = entry.get("signed_socket")
    if negative is not None:
        if entry["family"] not in {
            "bounded_rest_xml_read",
            "paginated_rest_xml_read",
            "bounded_document_read",
        }:
            raise Audit_Error(f"negative XML configured for non-XML read: {name}")
        if not {"valid_document", "xml_namespace"}.issubset(negative) or not set(
            negative
        ).issubset({"valid_document", "xml_namespace", "payload_shape"}):
            raise Audit_Error(f"invalid negative XML decisions: {name}")
        if not isinstance(negative["valid_document"], str) or not negative[
            "valid_document"
        ]:
            raise Audit_Error(f"negative XML valid document is empty: {name}")
        if not isinstance(negative["xml_namespace"], str):
            raise Audit_Error(f"invalid XML namespace decision: {name}")
        if "payload_shape" in negative and (
            not isinstance(negative["payload_shape"], str)
            or not negative["payload_shape"]
        ):
            raise Audit_Error(f"invalid XML payload shape decision: {name}")
    if socket is None:
        return
    adapter = socket.get("adapter")
    required_socket_fields = {"adapter", "case"}
    if not required_socket_fields.issubset(socket) or not set(socket).issubset(
        required_socket_fields | {"negative_template"}
    ):
        raise Audit_Error(f"invalid signed socket decisions: {name}")
    if negative is None and "negative_template" in socket:
        raise Audit_Error(
            f"signed socket negative template lacks negative XML: {name}"
        )
    if negative is not None and "negative_template" not in socket:
        raise Audit_Error(
            f"signed socket negative template is required: {name}"
        )
    if not isinstance(adapter, str) or not adapter.startswith("./bin/"):
        raise Audit_Error(f"invalid signed socket adapter: {name}")
    adapter_source = ROOT / "tests/src" / (Path(adapter).name + ".adb")
    if not adapter_source.is_file():
        raise Audit_Error(f"missing signed socket adapter source: {name}")
    cases = socket.get("case")
    if not isinstance(cases, list) or not cases:
        raise Audit_Error(f"signed socket qualification has no cases: {name}")
    identifiers: set[str] = set()
    for case in cases:
        identifier = case.get("id")
        if (
            not isinstance(identifier, str)
            or not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", identifier)
            or identifier in identifiers
        ):
            raise Audit_Error(f"invalid signed socket case id: {name}")
        identifiers.add(identifier)
        allowed_case_fields = {
            "exchange",
            "expected",
            "expected_value",
            "id",
            "lane",
            "limits",
        }
        if not set(case).issubset(allowed_case_fields):
            raise Audit_Error(f"invalid signed socket case fields: {name}/{identifier}")
        if case.get("lane") not in {
            "low_level",
            "synchronous",
            "composable",
            "restart",
            "invalid_xml",
        }:
            raise Audit_Error(f"invalid signed socket call lane: {name}/{identifier}")
        if case.get("expected") not in {
            "success",
            "authentication_failed",
            "authorization_failed",
            "not_found",
            "invalid_request",
            "response_invalid",
            "response_sink_failed",
        }:
            raise Audit_Error(f"invalid signed socket expectation: {name}/{identifier}")
        if "expected_value" in case and not isinstance(
            case["expected_value"], str
        ):
            raise Audit_Error(
                f"invalid signed socket expected value: {name}/{identifier}"
            )
        limits = case.get("limits", {})
        if not isinstance(limits, dict) or any(
            key
            not in {
                "maximum_document_bytes",
                "maximum_depth",
                "maximum_elements",
                "maximum_text_bytes",
            }
            or not isinstance(value, int)
            or isinstance(value, bool)
            or value < 1
            for key, value in limits.items()
        ):
            raise Audit_Error(f"invalid signed socket limits: {name}/{identifier}")
        exchanges = case.get("exchange")
        if not isinstance(exchanges, list) or not exchanges:
            raise Audit_Error(
                f"signed socket case has no exchange: {name}/{identifier}"
            )
        for exchange in exchanges:
            required = {"input_values", "status", "headers", "body"}
            optional = {"request_body", "expected_request_headers"}
            if not required.issubset(exchange) or not set(exchange).issubset(
                required | optional
            ):
                raise Audit_Error(
                    f"invalid signed socket exchange fields: {name}/{identifier}"
                )
            if (
                not isinstance(exchange["input_values"], dict)
                or any(
                    not isinstance(member, str)
                    or not member
                    or not isinstance(value, str)
                    for member, value in exchange["input_values"].items()
                )
            ):
                raise Audit_Error(
                    f"invalid signed socket input values: {name}/{identifier}"
                )
            headers = exchange["headers"]
            if not isinstance(exchange["status"], str) or not exchange["status"]:
                raise Audit_Error(
                    f"invalid signed response status: {name}/{identifier}"
                )
            if not isinstance(exchange["body"], str):
                raise Audit_Error(
                    f"invalid signed response body: {name}/{identifier}"
                )
            if "request_body" in exchange and not isinstance(
                exchange["request_body"], str
            ):
                raise Audit_Error(
                    f"invalid signed request body: {name}/{identifier}"
                )
            expected_request_headers = exchange.get(
                "expected_request_headers", {}
            )
            if not isinstance(expected_request_headers, dict) or any(
                not isinstance(header_name, str)
                or not header_name
                or not isinstance(header_value, str)
                for header_name, header_value in expected_request_headers.items()
            ):
                raise Audit_Error(
                    f"invalid expected signed request headers: "
                    f"{name}/{identifier}"
                )
            if not isinstance(headers, list) or any(
                not isinstance(item, list)
                or len(item) != 2
                or any(not isinstance(value, str) for value in item)
                for item in headers
            ):
                raise Audit_Error(
                    f"invalid signed response headers: {name}/{identifier}"
                )
    if negative is not None and socket.get("negative_template") not in identifiers:
        raise Audit_Error(f"unknown signed socket negative template: {name}")


def model_path(explicit: str | None) -> Path:
    candidate = explicit or os.environ.get("FLYOLOGY_S3_SERVICE_MODEL")
    if not candidate:
        raise Audit_Error(
            "set FLYOLOGY_S3_SERVICE_MODEL or pass --model with the pinned "
            "botocore service-2.json"
        )
    return Path(candidate).expanduser().resolve()


def repository_path(path_text: str) -> Path:
    path = (ROOT / path_text).resolve()
    if not path.is_relative_to(ROOT):
        raise Audit_Error(f"path escapes repository: {path_text}")
    return path


def load_model(path: Path) -> dict[str, Any]:
    raw = path.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != EXPECTED_MODEL_SHA256:
        raise Audit_Error(f"unexpected model SHA-256: {digest}")
    model = json.loads(raw)
    if len(model.get("operations", {})) != EXPECTED_OPERATION_COUNT:
        raise Audit_Error("unexpected pinned operation count")
    if len(model.get("shapes", {})) != EXPECTED_SHAPE_COUNT:
        raise Audit_Error("unexpected pinned shape count")
    return model


def verify_registry_model_inventory(
    registry: Registry, model: dict[str, Any]
) -> None:
    registered = set(registry.operations)
    modeled = set(model["operations"])
    if registered != modeled:
        missing = sorted(modeled - registered)
        extra = sorted(registered - modeled)
        raise Audit_Error(
            f"registry/model operation mismatch; missing={missing}, extra={extra}"
        )


def references(shape: dict[str, Any]) -> Iterable[str]:
    for member in shape.get("members", {}).values():
        if "shape" in member:
            yield member["shape"]
    for key in ("member", "key", "value"):
        if key in shape and "shape" in shape[key]:
            yield shape[key]["shape"]


def reachable_shapes(model: dict[str, Any], operation_name: str) -> list[str]:
    operation = model["operations"].get(operation_name)
    if operation is None:
        raise Audit_Error(f"operation is absent from pinned model: {operation_name}")
    pending = [
        item["shape"]
        for item in (
            [operation[key] for key in ("input", "output") if key in operation]
            + operation.get("errors", [])
        )
    ]
    closure: set[str] = set()
    while pending:
        name = pending.pop()
        if name in closure:
            continue
        shape = model["shapes"].get(name)
        if shape is None:
            raise Audit_Error(f"missing reachable shape: {name}")
        closure.add(name)
        pending.extend(references(shape))
    return sorted(closure)


def member_record(
    owner: dict[str, Any], name: str, member: dict[str, Any]
) -> dict[str, Any]:
    structural = {
        "shape",
        "location",
        "locationName",
        "xmlName",
        "flattened",
        "xmlAttribute",
        "xmlNamespace",
        "streaming",
    }
    result = {
        "name": name,
        "shape": member["shape"],
        "required": name in owner.get("required", []),
        "location": member.get("location", "body"),
        "location_name": member.get(
            "locationName", member.get("xmlName", name)
        ),
        "flattened": bool(member.get("flattened", False)),
        "xml_attribute": bool(member.get("xmlAttribute", False)),
        "xml_namespace": member.get("xmlNamespace", {}),
        "streaming": bool(member.get("streaming", False)),
    }
    traits = {
        key: value
        for key, value in member.items()
        if key not in structural and key != "documentation"
    }
    if traits:
        result["traits"] = traits
    return result


def operation_audit(model: dict[str, Any], name: str) -> dict[str, Any]:
    operation = model["operations"].get(name)
    if operation is None:
        raise Audit_Error(f"operation is absent from pinned model: {name}")
    shapes = model["shapes"]
    closure = reachable_shapes(model, name)
    shape_details = []
    for shape_name in closure:
        shape = shapes[shape_name]
        detail: dict[str, Any] = {
            "name": shape_name,
            "type": shape["type"],
            "flattened": bool(shape.get("flattened", False)),
        }
        if shape.get("enum") is not None:
            detail["enum"] = list(shape["enum"])
        if shape.get("members") is not None:
            detail["members"] = [
                member_record(shape, member_name, member)
                for member_name, member in shape["members"].items()
            ]
        for key in ("member", "key", "value"):
            if key in shape:
                detail[key] = shape[key]["shape"]
        for key in (
            "locationName",
            "payload",
            "xmlNamespace",
            "min",
            "max",
            "pattern",
            "streaming",
        ):
            if key in shape:
                detail[key] = shape[key]
        structural = {
            "type",
            "enum",
            "members",
            "member",
            "key",
            "value",
            "documentation",
            "locationName",
            "payload",
            "xmlNamespace",
            "min",
            "max",
            "pattern",
            "streaming",
        }
        traits = {
            key: value for key, value in shape.items() if key not in structural
        }
        if traits:
            detail["traits"] = traits
        shape_details.append(detail)
    http = operation["http"]
    return {
        "operation": name,
        "method": http["method"],
        "uri": http["requestUri"],
        "response_status": int(http.get("responseCode", 200)),
        "input_shape": operation.get("input", {}).get("shape"),
        "output_shape": operation.get("output", {}).get("shape"),
        "error_shapes": [item["shape"] for item in operation.get("errors", [])],
        "checksum": operation.get("httpChecksum", {}),
        "operation_traits": {
            key: value
            for key, value in operation.items()
            if key
            not in {
                "name",
                "http",
                "input",
                "output",
                "errors",
                "documentation",
                "documentationUrl",
                "httpChecksum",
            }
        },
        "reachable_shape_count": len(closure),
        "shapes": shape_details,
    }


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def namespace_uri(tag: str) -> str:
    return tag[1:].split("}", 1)[0] if tag.startswith("{") else ""


def xml_member_specs(
    model: dict[str, Any], shape_name: str
) -> list[dict[str, Any]]:
    shape = model["shapes"][shape_name]
    if shape["type"] == "list":
        member = shape["member"]
        member_shape_name = member["shape"]
        member_shape = model["shapes"][member_shape_name]
        return [
            {
                "name": member_shape_name,
                "tag": member.get(
                    "locationName",
                    member_shape.get("locationName", member_shape_name),
                ),
                "shape": member_shape_name,
                "required": False,
                "flattened": False,
                "list": True,
                "xml_attribute": False,
                "attribute_namespace": "",
            }
        ]
    if shape["type"] != "structure":
        return []
    result = []
    for member_name, member in shape.get("members", {}).items():
        member_shape_name = member["shape"]
        member_shape = model["shapes"][member_shape_name]
        flattened = (
            member_shape["type"] == "list"
            and bool(
                member.get("flattened", False)
                or member_shape.get("flattened", False)
            )
        )
        target_shape = (
            member_shape["member"]["shape"] if flattened else member_shape_name
        )
        xml_attribute = bool(member.get("xmlAttribute", False))
        raw_tag = member.get("locationName", member.get("xmlName", member_name))
        shape_namespace = shape.get("xmlNamespace", {})
        attribute_namespace = ""
        if xml_attribute and ":" in raw_tag:
            prefix, raw_tag = raw_tag.split(":", 1)
            if shape_namespace.get("prefix") == prefix:
                attribute_namespace = shape_namespace.get("uri", "")
        result.append(
            {
                "name": member_name,
                "tag": raw_tag,
                "shape": target_shape,
                "required": member_name in shape.get("required", []),
                "flattened": flattened,
                "list": member_shape["type"] == "list",
                "xml_attribute": xml_attribute,
                "attribute_namespace": attribute_namespace,
            }
        )
    return result


def output_payload_shape(model: dict[str, Any], operation_name: str) -> str:
    operation = model["operations"][operation_name]
    output_name = operation.get("output", {}).get("shape")
    if output_name is None:
        raise Audit_Error(f"operation has no XML output shape: {operation_name}")
    output = model["shapes"][output_name]
    payload = output.get("payload")
    if payload is None:
        return output_name
    member = output.get("members", {}).get(payload)
    if member is None:
        raise Audit_Error(f"output payload member is absent: {operation_name}")
    return member["shape"]


def negative_xml_cases(
    model: dict[str, Any], operation_name: str, decisions: dict[str, Any]
) -> list[dict[str, Any]]:
    """Derive routine invalid REST/XML documents from reviewed valid input."""
    modeled_payload_shape = output_payload_shape(model, operation_name)
    payload_shape = decisions.get("payload_shape", modeled_payload_shape)
    if (
        payload_shape not in model["shapes"]
        or model["shapes"][payload_shape]["type"] != "structure"
    ):
        raise Audit_Error(
            f"reviewed XML payload shape is invalid: {operation_name}"
        )
    if payload_shape != modeled_payload_shape:
        def without_documentation(value: Any) -> Any:
            if isinstance(value, dict):
                return {
                    key: without_documentation(item)
                    for key, item in value.items()
                    if key != "documentation"
                }
            if isinstance(value, list):
                return [without_documentation(item) for item in value]
            return value

        modeled_contract = without_documentation(
            model["shapes"][modeled_payload_shape]
        )
        reviewed_contract = without_documentation(
            model["shapes"][payload_shape]
        )
        #  The reviewed alias supplies the wire root name. A differing member
        #  locationName remains contract-significant and is still compared.
        modeled_contract.pop("locationName", None)
        reviewed_contract.pop("locationName", None)
        if reviewed_contract != modeled_contract:
            raise Audit_Error(
                f"reviewed XML payload alias is not structurally equivalent: "
                f"{operation_name}"
            )
    valid_document = decisions["valid_document"]
    try:
        valid_root = ET.fromstring(valid_document)
    except ET.ParseError as error:
        raise Audit_Error(
            f"reviewed valid XML is not well formed: {operation_name}: {error}"
        ) from error
    expected_root = model["shapes"][payload_shape].get(
        "locationName", payload_shape
    )
    if local_name(valid_root.tag) != expected_root:
        raise Audit_Error(
            f"reviewed XML root/model payload mismatch: {operation_name}"
        )
    validate_reviewed_xml(
        model,
        payload_shape,
        valid_root,
        decisions["xml_namespace"],
        operation_name,
    )

    cases: list[dict[str, Any]] = []
    identifiers: set[str] = set()

    def add_case(
        category: str,
        path: list[str],
        root: ET.Element,
        *,
        limits: dict[str, int] | None = None,
        expected_http_result: str = "response_invalid",
    ) -> None:
        stem = "-".join([category, *path])
        identifier = re.sub(r"[^a-z0-9]+", "-", stem.casefold()).strip("-")
        if identifier in identifiers:
            raise Audit_Error(
                f"duplicate generated XML case id: {operation_name}/{identifier}"
            )
        identifiers.add(identifier)
        cases.append(
            {
                "id": identifier,
                "category": category,
                "body": ET.tostring(root, encoding="unicode"),
                "limits": limits or {},
                "expected_http_result": expected_http_result,
            }
        )

    def walk(element: ET.Element, shape_name: str, path: list[str]) -> None:
        specs = xml_member_specs(model, shape_name)
        children = list(element)
        for spec in specs:
            if spec["xml_attribute"]:
                attribute_name = (
                    "{" + spec["attribute_namespace"] + "}" + spec["tag"]
                    if spec["attribute_namespace"]
                    else spec["tag"]
                )
                matching_attributes = [
                    name
                    for name in element.attrib
                    if namespace_uri(name) == spec["attribute_namespace"]
                    and local_name(name) == spec["tag"]
                ]
                member_path = [*path, spec["name"]]
                if spec["required"] and matching_attributes:
                    changed = deepcopy(valid_root)
                    target = find_element(changed, path)
                    del target.attrib[attribute_name]
                    add_case("missing-required-attribute", member_path, changed)
                target_shape = model["shapes"][spec["shape"]]
                if (
                    matching_attributes
                    and target_shape["type"] == "string"
                    and target_shape.get("enum")
                ):
                    changed = deepcopy(valid_root)
                    target = find_element(changed, path)
                    target.set(attribute_name, "__INVALID_MODEL_ENUM__")
                    add_case("invalid-attribute-enum", member_path, changed)
                if matching_attributes and spec["attribute_namespace"]:
                    changed = deepcopy(valid_root)
                    target = find_element(changed, path)
                    value = target.attrib.pop(attribute_name)
                    target.set(
                        "{urn:flyology:invalid-attribute-namespace}"
                        + spec["tag"],
                        value,
                    )
                    add_case("attribute-namespace-violation", member_path, changed)
                continue
            matching = [
                child for child in children if local_name(child.tag) == spec["tag"]
            ]
            member_path = [*path, spec["name"]]
            if spec["required"] and matching:
                changed = deepcopy(valid_root)
                target = find_element(changed, path)
                changed_matches = [
                    child
                    for child in list(target)
                    if local_name(child.tag) == spec["tag"]
                ]
                if spec["flattened"]:
                    for child in changed_matches:
                        target.remove(child)
                    add_case("empty-required-flattened-list", member_path, changed)
                else:
                    target.remove(changed_matches[0])
                    add_case("missing-required-member", member_path, changed)
            if matching and not spec["list"]:
                changed = deepcopy(valid_root)
                target = find_element(changed, path)
                changed_match = next(
                    child
                    for child in list(target)
                    if local_name(child.tag) == spec["tag"]
                )
                target.insert(
                    list(target).index(changed_match) + 1,
                    deepcopy(changed_match),
                )
                add_case("duplicate-singleton", member_path, changed)
            target_shape = model["shapes"][spec["shape"]]
            if target_shape["type"] == "string" and target_shape.get("enum"):
                for index, _ in enumerate(matching):
                    changed = deepcopy(valid_root)
                    target = find_element(changed, path)
                    changed_matches = [
                        child
                        for child in list(target)
                        if local_name(child.tag) == spec["tag"]
                    ]
                    changed_matches[index].text = "__INVALID_MODEL_ENUM__"
                    add_case("invalid-enum", [*member_path, str(index + 1)], changed)
            if target_shape["type"] in {"structure", "list"}:
                for index, child in enumerate(matching):
                    walk(child, spec["shape"], [*member_path, str(index + 1)])

    def find_element(root: ET.Element, path: list[str]) -> ET.Element:
        if not path:
            return root
        current = root
        current_shape = payload_shape
        cursor = 0
        while cursor < len(path):
            member_name = path[cursor]
            cursor += 1
            spec = next(
                item
                for item in xml_member_specs(model, current_shape)
                if item["name"] == member_name
            )
            index = int(path[cursor]) if cursor < len(path) else 1
            if cursor < len(path):
                cursor += 1
            matches = [
                child for child in list(current) if local_name(child.tag) == spec["tag"]
            ]
            current = matches[index - 1]
            current_shape = spec["shape"]
        return current

    walk(valid_root, payload_shape, [])

    changed = deepcopy(valid_root)
    ET.SubElement(changed, "UnknownModelMember")
    add_case("unknown-member", [expected_root], changed)

    changed = deepcopy(valid_root)
    changed.set("unexpected-model-attribute", "true")
    add_case("unexpected-attribute", [expected_root], changed)

    if decisions["xml_namespace"]:
        changed = deepcopy(valid_root)
        changed.tag = "{urn:flyology:invalid-s3-namespace}" + local_name(changed.tag)
        add_case("namespace-violation", [expected_root], changed)

    statistics = xml_statistics(valid_root, valid_document)
    for field, value in statistics.items():
        if value > 1:
            add_case(
                "limit-failure",
                [field.replace("maximum_", "")],
                deepcopy(valid_root),
                limits={field: value - 1},
                expected_http_result=(
                    "response_sink_failed"
                    if field == "maximum_document_bytes"
                    else "response_invalid"
                ),
            )
    return sorted(cases, key=lambda item: item["id"])


def validate_reviewed_xml(
    model: dict[str, Any],
    shape_name: str,
    element: ET.Element,
    namespace: str,
    operation_name: str,
) -> None:
    """Reject a scaffold seed that is not structurally valid by the model."""
    if namespace:
        actual_namespace = (
            element.tag[1:].split("}", 1)[0] if element.tag.startswith("{") else ""
        )
        if actual_namespace != namespace:
            raise Audit_Error(
                f"reviewed XML namespace mismatch: {operation_name}"
            )
    specs = xml_member_specs(model, shape_name)
    child_specs = [spec for spec in specs if not spec["xml_attribute"]]
    attribute_specs = [spec for spec in specs if spec["xml_attribute"]]
    known = {spec["tag"] for spec in child_specs}
    known_attributes = {
        (spec["attribute_namespace"], spec["tag"])
        for spec in attribute_specs
    }
    unknown_attributes = [
        name
        for name in element.attrib
        if (namespace_uri(name), local_name(name)) not in known_attributes
    ]
    if unknown_attributes:
        raise Audit_Error(
            f"reviewed XML has unknown attributes for {operation_name}: "
            f"{unknown_attributes}"
        )
    children = list(element)
    unknown = [
        local_name(child.tag)
        for child in children
        if local_name(child.tag) not in known
    ]
    if unknown:
        raise Audit_Error(
            f"reviewed XML has unknown members for {operation_name}: {unknown}"
        )
    for spec in attribute_specs:
        values = [
            value
            for attribute_name, value in element.attrib.items()
            if namespace_uri(attribute_name) == spec["attribute_namespace"]
            and local_name(attribute_name) == spec["tag"]
        ]
        if spec["required"] and not values:
            raise Audit_Error(
                f"reviewed XML lacks required attribute {spec['name']}: "
                f"{operation_name}"
            )
        target_shape = model["shapes"][spec["shape"]]
        if target_shape["type"] == "string" and target_shape.get("enum"):
            if any(value not in target_shape["enum"] for value in values):
                raise Audit_Error(
                    f"reviewed XML attribute enum is outside {spec['name']}: "
                    f"{operation_name}"
                )
    for spec in child_specs:
        matching = [child for child in children if local_name(child.tag) == spec["tag"]]
        if spec["required"] and not matching:
            raise Audit_Error(
                f"reviewed XML lacks required {spec['name']}: {operation_name}"
            )
        if not spec["list"] and len(matching) > 1:
            raise Audit_Error(
                f"reviewed XML duplicates singleton {spec['name']}: {operation_name}"
            )
        target_shape = model["shapes"][spec["shape"]]
        if target_shape["type"] == "string" and target_shape.get("enum"):
            for child in matching:
                if (child.text or "") not in target_shape["enum"]:
                    raise Audit_Error(
                        f"reviewed XML enum is outside {spec['name']}: {operation_name}"
                    )
        if target_shape["type"] in {"structure", "list"}:
            for child in matching:
                validate_reviewed_xml(
                    model, spec["shape"], child, namespace, operation_name
                )


def xml_statistics(root: ET.Element, document: str) -> dict[str, int]:
    def depth(element: ET.Element) -> int:
        children = list(element)
        return 1 if not children else 1 + max(depth(child) for child in children)

    return {
        "maximum_document_bytes": len(document.encode("utf-8")),
        "maximum_depth": depth(root),
        "maximum_elements": sum(1 for _ in root.iter()),
        "maximum_text_bytes": sum(
            len((element.text or "").encode("utf-8")) for element in root.iter()
        ),
    }


def negative_xml_text(registry: Registry, model: dict[str, Any]) -> str:
    operations = {
        name: {
            "cases": negative_xml_cases(model, name, entry["negative_xml"]),
            "valid_document": entry["negative_xml"]["valid_document"],
        }
        for name, entry in sorted(registry.operations.items())
        if "negative_xml" in entry
    }
    return json.dumps(
        {
            "model_revision": EXPECTED_MODEL_REVISION,
            "model_sha256": EXPECTED_MODEL_SHA256,
            "operations": operations,
        },
        indent=2,
        sort_keys=True,
    ) + "\n"


def signed_socket_exchange(
    model: dict[str, Any], operation_name: str, exchange: dict[str, Any]
) -> dict[str, Any]:
    """Derive one exact signed request from reviewed operation inputs."""
    operation = model["operations"][operation_name]
    input_shape = model["shapes"][operation["input"]["shape"]]
    members = input_shape.get("members", {})
    required = set(input_shape.get("required", []))
    payload_member = input_shape.get("payload")
    values = exchange["input_values"]
    unknown = set(values) - set(members)
    if unknown:
        raise Audit_Error(
            f"signed socket inputs are absent from {operation_name}: "
            + ", ".join(sorted(unknown))
        )
    required_inputs = required - ({payload_member} if payload_member else set())
    missing = required_inputs - set(values)
    if missing:
        raise Audit_Error(
            f"signed socket inputs omit required {operation_name} members: "
            + ", ".join(sorted(missing))
        )

    if payload_member and payload_member in values:
        raise Audit_Error(
            f"signed socket payload must use request_body for "
            f"{operation_name}.{payload_member}"
        )
    if payload_member in required and "request_body" not in exchange:
        raise Audit_Error(
            f"signed socket omits required {operation_name}.{payload_member} "
            "request body"
        )
    if not payload_member and "request_body" in exchange:
        raise Audit_Error(
            f"signed socket request body is not modeled for {operation_name}"
        )

    target = operation["http"]["requestUri"]
    request_headers: dict[str, str] = {}
    query_values: list[tuple[str, str]] = []
    for member_name, spec in members.items():
        if member_name not in values:
            continue
        value = values[member_name]
        location = spec.get("location")
        location_name = spec.get("locationName", member_name)
        if location == "uri":
            marker = "{" + location_name + "}"
            greedy_marker = "{" + location_name + "+}"
            if greedy_marker in target:
                #  Smithy greedy labels preserve path separators while each
                #  key byte remains URI encoded. Ordinary labels encode '/'.
                encoded = urllib.parse.quote(value, safe="/-_.~")
                target = target.replace(greedy_marker, encoded)
            elif marker in target:
                encoded = urllib.parse.quote(value, safe="-_.~")
                target = target.replace(marker, encoded)
            else:
                raise Audit_Error(
                    f"model URI omits {operation_name}.{member_name} marker"
                )
        elif location == "querystring":
            marker = "{" + location_name + "}"
            if marker in target:
                target = target.replace(marker, encoded)
            else:
                query_values.append((location_name, value))
        elif location == "header":
            request_headers[location_name] = value
        elif member_name == payload_member and location is None:
            continue
        else:
            raise Audit_Error(
                f"signed socket cannot derive {operation_name}.{member_name} "
                f"at location {location!r}"
            )
    if re.search(r"\{[^}]+\}", target):
        raise Audit_Error(
            f"model URI remains unresolved for {operation_name}: {target}"
        )
    path, separator, existing_query = target.partition("?")
    query_components = (
        existing_query.split("&") if separator and existing_query else []
    )
    if query_values:
        query_components.extend(
            (
                urllib.parse.quote(name, safe="-_.~")
                if value == ""
                else urllib.parse.quote(name, safe="-_.~")
                + "="
                + urllib.parse.quote(value, safe="-_.~")
            )
            for name, value in query_values
        )
    target = path
    if query_components:
        # The signer writes the canonical query ordering. Botocore owns the
        # fixed and member components; lexical ordering is the SigV4 wire
        # representation already used by the generated low-level client.
        target += "?" + "&".join(sorted(query_components))
    status = exchange["status"]
    if status == "modeled_success":
        response_code = int(operation["http"].get("responseCode", 200))
        try:
            status = f"{response_code} {http.HTTPStatus(response_code).phrase}"
        except ValueError as error:
            raise Audit_Error(
                f"model names an unsupported HTTP status for {operation_name}: "
                f"{response_code}"
            ) from error
    elif not re.fullmatch(r"[1-5][0-9][0-9] [\x20-\x7e]+", status):
        raise Audit_Error(
            f"reviewed signed socket status is invalid: {operation_name}/{status}"
        )
    if "request_body" in exchange:
        request_headers["x-amz-content-sha256"] = hashlib.sha256(
            exchange["request_body"].encode("utf-8")
        ).hexdigest()
    expected_request_headers = exchange.get("expected_request_headers", {})
    duplicate_headers = {
        name.casefold() for name in request_headers
    } & {name.casefold() for name in expected_request_headers}
    if duplicate_headers:
        raise Audit_Error(
            f"signed socket repeats derived request headers for "
            f"{operation_name}: {', '.join(sorted(duplicate_headers))}"
        )
    request_headers.update(expected_request_headers)
    result = {
        "body": exchange["body"],
        "headers": exchange["headers"],
        "input_values": values,
        "method": operation["http"]["method"],
        "request_headers": request_headers,
        "status": status,
        "target": target,
    }
    if "request_body" in exchange:
        result["request_body"] = exchange["request_body"]
    return result


def signed_socket_text(registry: Registry, model: dict[str, Any]) -> str:
    operations: dict[str, Any] = {}
    for name, entry in sorted(registry.operations.items()):
        if "signed_socket" not in entry:
            continue
        source = entry["signed_socket"]
        cases = []
        for case in source["case"]:
            generated = {
                key: value for key, value in case.items() if key != "exchange"
            }
            generated["exchange"] = [
                signed_socket_exchange(model, name, exchange)
                for exchange in case["exchange"]
            ]
            cases.append(generated)
        operation = {
            "adapter": source["adapter"],
            "cases": cases,
        }
        if "negative_template" in source:
            operation["negative_template"] = source["negative_template"]
        operations[name] = operation
    return json.dumps(
        {
            "model_revision": EXPECTED_MODEL_REVISION,
            "model_sha256": EXPECTED_MODEL_SHA256,
            "operations": operations,
        },
        indent=2,
        sort_keys=True,
    ) + "\n"


def unresolved_decisions(entry: dict[str, Any]) -> list[str]:
    required = (
        "provider",
        "family",
        "public_provider",
        "public_name",
        "codec",
        "absence",
        "errors",
        "certainty",
        "reconciliation",
        "exclusions",
        "coverage",
        "provenance",
        "implementation_mode",
        "generator_eligible",
        "human_decisions_resolved",
        "decision_status",
    )
    missing = [name for name in required if name not in entry]
    if entry.get("decision_status") not in (None, "reviewed"):
        missing.append(f"decision_status={entry['decision_status']}")
    for field in (
        "public_name",
        "absence",
        "errors",
        "certainty",
        "reconciliation",
    ):
        value = entry.get(field)
        values = value if isinstance(value, list) else [value]
        if any(
            isinstance(item, str) and item.startswith("legacy_preserved")
            for item in values
        ):
            missing.append(f"{field}: operation-specific review")
    generation = entry.get("generation")
    if entry.get("generator_eligible"):
        if not isinstance(generation, dict):
            missing.append("generation: reviewed human decisions")
        else:
            for field, value in generation.items():
                values = value if isinstance(value, list) else [value]
                if any(
                    isinstance(item, str) and item.startswith("unresolved")
                    for item in values
                ):
                    missing.append(f"generation.{field}: human decision")
    return missing


def evidence_findings(
    entry: dict[str, Any], *, include_partial: bool = True
) -> list[str]:
    findings: list[str] = []
    name = entry["name"]
    tokens = [name, camel_to_ada(name), *entry.get("evidence_tokens", [])]
    for layer in LAYERS:
        state = entry["coverage"][layer]
        paths = entry["evidence"][layer]
        if state == "covered" and not paths:
            findings.append(f"covered {layer} lacks executable evidence")
        if state == "partial" and include_partial and not paths:
            findings.append(f"partial {layer} coverage lacks executable evidence")
        if state != "covered" and not (include_partial and state == "partial"):
            continue
        found_token = False
        for path_text in paths:
            path = repository_path(path_text)
            if not path.is_file():
                findings.append(f"missing {layer} evidence path: {path_text}")
                continue
            source = path.read_text(encoding="utf-8", errors="ignore").casefold()
            if any(token.casefold() in source for token in tokens):
                found_token = True
        if paths and not found_token:
            findings.append(f"{layer} evidence does not name {name}")
    for symbol in entry.get("ada_symbols", []):
        result = subprocess.run(
            ["git", "grep", "-q", "-F", symbol, "--", "*.ads", "*.adb"],
            cwd=ROOT,
            check=False,
        )
        if result.returncode != 0:
            findings.append(f"missing Ada API/evidence symbol: {symbol}")
    return findings


def camel_to_ada(name: str) -> str:
    result = []
    for index, character in enumerate(name):
        if index and character.isupper() and name[index - 1].islower():
            result.append("_")
        result.append(character)
    return "".join(result)


def ledger_text(registry: Registry) -> str:
    lines = ["operation\ttier\tbackend\tclient\tserver\tcorpus"]
    for name in sorted(registry.operations):
        entry = registry.operations[name]
        coverage = entry["coverage"]
        lines.append(
            "\t".join(
                [
                    name,
                    entry["tier"],
                    coverage["backend"],
                    coverage["client"],
                    coverage["server"],
                    coverage["corpus"],
                ]
            )
        )
    return "\n".join(lines) + "\n"


def check_ledger(registry: Registry) -> None:
    expected = ledger_text(registry)
    actual = LEDGER_PATH.read_text(encoding="utf-8")
    if actual != expected:
        raise Audit_Error(
            "generated coverage ledger differs; run s3-operation.py generate"
        )


def counts_text(registry: Registry) -> str:
    counts: dict[str, Any] = {"operations": len(registry.operations)}
    for layer in ("backend", "client", "server", "corpus"):
        counts[layer] = {state: 0 for state in ("missing", "partial", "covered")}
        for entry in registry.operations.values():
            counts[layer][entry["coverage"][layer]] += 1
    counts["providers"] = {}
    counts["families"] = {}
    counts["decision_status"] = {}
    counts["implementation_mode"] = {
        state: 0 for state in sorted(IMPLEMENTATION_MODES)
    }
    counts["generator_eligible"] = {"false": 0, "true": 0}
    counts["provenance"] = {
        layer: {state: 0 for state in sorted(PROVENANCE_STATES)}
        for layer in ("backend", "client", "server", "tests")
    }
    for entry in registry.operations.values():
        for key, source in (("providers", "provider"), ("families", "family")):
            value = entry[source]
            counts[key][value] = counts[key].get(value, 0) + 1
        status = entry["decision_status"]
        counts["decision_status"][status] = (
            counts["decision_status"].get(status, 0) + 1
        )
        counts["implementation_mode"][entry["implementation_mode"]] += 1
        counts["generator_eligible"][
            str(entry["generator_eligible"]).lower()
        ] += 1
        for layer, state in entry["provenance"].items():
            counts["provenance"][layer][state] += 1
    return json.dumps(counts, indent=2, sort_keys=True) + "\n"


def inventory_text(registry: Registry) -> str:
    """Lossless generated view of implementation and executable evidence."""
    operations = {}
    for name in sorted(registry.operations):
        entry = registry.operations[name]
        operations[name] = {
            "coverage": entry["coverage"],
            "implementation_mode": entry["implementation_mode"],
            "provider": entry["provider"],
            "family": entry["family"],
            "evidence": entry["evidence"],
            "provenance": entry["provenance"],
            "generator_eligible": entry["generator_eligible"],
            "human_decisions_resolved": entry["human_decisions_resolved"],
        }
    return json.dumps(
        {
            "model_revision": EXPECTED_MODEL_REVISION,
            "model_sha256": EXPECTED_MODEL_SHA256,
            "operation_count": len(operations),
            "operations": operations,
        },
        indent=2,
        sort_keys=True,
    ) + "\n"


def shell_words(command: list[str]) -> str:
    return shlex.join(command)


def test_registration_text(registry: Registry) -> str:
    registration = registry.metadata["test_registration"]
    lines = [
        "# Generated by tools/s3-operation.py; do not edit.",
        "# Source: coverage/s3-operations.toml",
        "",
        "s3_operation_corpus_repetitions="
        + str(registration["corpus_repetitions"]),
        "",
        "run_s3_model_verifiers() {",
    ]
    for command in registration["model_verifiers"]:
        lines.append("  " + shell_words(command))
    lines.extend(("}", "", "run_s3_operation_corpora() {"))
    for command in registration["corpora"]:
        lines.append("  " + shell_words(command))
    lines.extend(("}", "", "run_s3_socket_qualifiers() {"))
    for command in registration["socket_qualifiers"]:
        lines.append("  " + shell_words(command))
    lines.extend(("}", ""))
    return "\n".join(lines)


def documentation_text(registry: Registry) -> str:
    lines = [
        "<!-- Generated by tools/s3-operation.py; do not edit. -->",
        "<!-- Source: coverage/s3-operations.toml -->",
        "# S3 operation registry",
        "",
        "The pinned inventory contains 116 operations. Coverage is promoted only",
        "when the human-owned registry cites executable evidence and the generated",
        "ledger passes its maintained evidence verifier. Historical partial cells",
        "remain inventory-only until their audits gain executable evidence.",
        "",
        "| Operation | Public API | Provider | Family | Implementation | Generator eligible | Decisions resolved | Backend | Client | Server | Tests |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for name in sorted(registry.operations):
        entry = registry.operations[name]
        coverage = entry["coverage"]
        lines.append(
            "| "
            + " | ".join(
                (
                    name,
                    entry["public_name"],
                    entry["provider"],
                    entry["family"],
                    entry["implementation_mode"],
                    str(entry["generator_eligible"]).lower(),
                    str(entry["human_decisions_resolved"]).lower(),
                    f"{coverage['backend']} / {entry['provenance']['backend']}",
                    f"{coverage['client']} / {entry['provenance']['client']}",
                    f"{coverage['server']} / {entry['provenance']['server']}",
                    f"{coverage['corpus']} / {entry['provenance']['tests']}",
                )
            )
            + " |"
        )
    return "\n".join(lines) + "\n"


def generated_outputs(
    registry: Registry, model: dict[str, Any] | None = None
) -> dict[Path, str]:
    result = {
        LEDGER_PATH: ledger_text(registry),
        COUNTS_PATH: counts_text(registry),
        INVENTORY_PATH: inventory_text(registry),
        TEST_REGISTRATION_PATH: test_registration_text(registry),
        DOCUMENTATION_PATH: documentation_text(registry),
    }
    if model is not None:
        result[NEGATIVE_XML_PATH] = negative_xml_text(registry, model)
        result[SIGNED_SOCKET_PATH] = signed_socket_text(registry, model)
    return result


def validate_committed_negative_xml(
    registry: Registry, path: Path = NEGATIVE_XML_PATH
) -> None:
    if not path.is_file():
        raise Audit_Error("generated negative XML corpus is missing")
    value = json.loads(path.read_text(encoding="utf-8"))
    if value.get("model_revision") != EXPECTED_MODEL_REVISION:
        raise Audit_Error("negative XML corpus names an unexpected model revision")
    if value.get("model_sha256") != EXPECTED_MODEL_SHA256:
        raise Audit_Error("negative XML corpus names an unexpected model hash")
    expected = {
        name for name, entry in registry.operations.items() if "negative_xml" in entry
    }
    if set(value.get("operations", {})) != expected:
        raise Audit_Error("negative XML operation inventory differs from registry")
    for name, operation in value["operations"].items():
        cases = operation.get("cases")
        if not isinstance(cases, list) or not cases:
            raise Audit_Error(f"negative XML operation has no cases: {name}")
        identifiers = [case.get("id") for case in cases]
        if len(set(identifiers)) != len(identifiers):
            raise Audit_Error(f"duplicate negative XML case: {name}")


def validate_committed_signed_socket(
    registry: Registry, path: Path = SIGNED_SOCKET_PATH
) -> None:
    if not path.is_file():
        raise Audit_Error("generated signed socket plan is missing")
    value = json.loads(path.read_text(encoding="utf-8"))
    if value.get("model_revision") != EXPECTED_MODEL_REVISION:
        raise Audit_Error("signed socket plan names an unexpected model revision")
    if value.get("model_sha256") != EXPECTED_MODEL_SHA256:
        raise Audit_Error("signed socket plan names an unexpected model hash")
    expected = {
        name for name, entry in registry.operations.items() if "signed_socket" in entry
    }
    if set(value.get("operations", {})) != expected:
        raise Audit_Error("signed socket operation inventory differs from registry")
    for name, operation in value["operations"].items():
        cases = operation.get("cases")
        if not isinstance(cases, list) or not cases:
            raise Audit_Error(f"signed socket operation has no cases: {name}")
        identifiers = [case.get("id") for case in cases]
        if len(set(identifiers)) != len(identifiers):
            raise Audit_Error(f"duplicate signed socket case: {name}")
        source = registry.operations[name]
        if "negative_xml" in source and operation.get(
            "negative_template"
        ) not in identifiers:
            raise Audit_Error(f"signed socket negative template is absent: {name}")
        if "negative_xml" not in source and "negative_template" in operation:
            raise Audit_Error(
                f"signed socket has unexpected negative template: {name}"
            )


def check_generated_outputs(
    registry: Registry, model: dict[str, Any] | None = None
) -> None:
    findings = {
        name: evidence_findings(entry, include_partial=False)
        for name, entry in registry.operations.items()
    }
    findings = {name: values for name, values in findings.items() if values}
    if findings:
        raise Audit_Error(f"covered operation evidence findings: {findings}")
    validate_committed_negative_xml(registry)
    validate_committed_signed_socket(registry)
    for path, expected in generated_outputs(registry, model).items():
        if not path.exists() or path.read_text(encoding="utf-8") != expected:
            raise Audit_Error(
                f"generated output differs: {path.relative_to(ROOT)}"
            )


def run_commands(commands: list[list[str]], pinned_model: Path) -> None:
    for command in commands:
        cwd = ROOT
        arguments = list(command)
        if arguments[0] == "@tests":
            cwd = ROOT / "tests"
            arguments.pop(0)
        arguments = [
            str(pinned_model) if part == "{model}" else part
            for part in arguments
        ]
        print("+", shlex.join(arguments), flush=True)
        subprocess.run(arguments, cwd=cwd, check=True)
