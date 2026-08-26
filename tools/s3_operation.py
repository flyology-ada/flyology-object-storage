#!/usr/bin/env python3
"""Shared pinned-model and evidence support for S3 operation work."""

from __future__ import annotations

import hashlib
import json
import os
import shlex
import subprocess
import tomllib
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

ROOT = Path(__file__).resolve().parents[1]
REGISTRY_PATH = ROOT / "coverage/s3-operations.toml"
LEDGER_PATH = ROOT / "coverage/aws-s3-operations.tsv"
COUNTS_PATH = ROOT / "coverage/s3-operation-counts.json"
TEST_REGISTRATION_PATH = ROOT / "tests/generated/s3-operation-tests.sh"
DOCUMENTATION_PATH = ROOT / "docs/generated/s3-operation-registry.md"
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
    if raw.get("schema_version") != 1:
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
    for name in ("model_verifiers", "corpora"):
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
    validate_test_registration(registration)
    return Registry(raw, operations, qualification)


def validate_test_registration(registration: dict[str, Any]) -> None:
    """Bind generated commands to maintained verifier and corpus sources."""
    for command in registration["model_verifiers"]:
        if command[:5] != ["uv", "run", "--python", "3.13", "--"]:
            raise Audit_Error(f"model verifier does not use pinned uv Python: {command}")
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
        for layer, state in entry["provenance"].items():
            counts["provenance"][layer][state] += 1
    return json.dumps(counts, indent=2, sort_keys=True) + "\n"


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
        "| Operation | Public API | Provider | Family | Backend | Client | Server | Tests |",
        "| --- | --- | --- | --- | --- | --- | --- | --- |",
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
                    f"{coverage['backend']} / {entry['provenance']['backend']}",
                    f"{coverage['client']} / {entry['provenance']['client']}",
                    f"{coverage['server']} / {entry['provenance']['server']}",
                    f"{coverage['corpus']} / {entry['provenance']['tests']}",
                )
            )
            + " |"
        )
    return "\n".join(lines) + "\n"


def generated_outputs(registry: Registry) -> dict[Path, str]:
    return {
        LEDGER_PATH: ledger_text(registry),
        COUNTS_PATH: counts_text(registry),
        TEST_REGISTRATION_PATH: test_registration_text(registry),
        DOCUMENTATION_PATH: documentation_text(registry),
    }


def check_generated_outputs(registry: Registry) -> None:
    findings = {
        name: evidence_findings(entry, include_partial=False)
        for name, entry in registry.operations.items()
    }
    findings = {name: values for name, values in findings.items() if values}
    if findings:
        raise Audit_Error(f"covered operation evidence findings: {findings}")
    for path, expected in generated_outputs(registry).items():
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
