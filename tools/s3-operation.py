#!/usr/bin/env python3
"""Audit, scaffold, qualify, and generate the reviewed S3 operation registry."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

import s3_operation


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser()
    value.add_argument("--model", help="pinned botocore service-2.json")
    actions = value.add_subparsers(dest="action", required=True)
    for name in ("audit", "scaffold", "qualify"):
        child = actions.add_parser(name)
        child.add_argument("operation")
    actions.add_parser("generate").add_argument(
        "--check", action="store_true", help="fail instead of writing outputs"
    )
    return value


def audit(args: argparse.Namespace, registry: s3_operation.Registry) -> int:
    entry = registry.operations.get(args.operation)
    if entry is None:
        raise s3_operation.Audit_Error(
            f"operation is absent from registry: {args.operation}"
        )
    model = s3_operation.load_model(s3_operation.model_path(args.model))
    s3_operation.verify_registry_model_inventory(registry, model)
    result = s3_operation.operation_audit(model, args.operation)
    unresolved = s3_operation.unresolved_decisions(entry)
    findings = s3_operation.evidence_findings(entry)
    result["registry"] = entry
    result["expected_ada_api"] = {
        "provider": entry["public_provider"],
        "operation": entry["public_name"],
        "symbols": entry.get("ada_symbols", []),
    }
    result["unresolved_human_decisions"] = unresolved
    result["evidence_findings"] = findings
    if "negative_xml" in entry:
        result["generated_negative_xml"] = s3_operation.negative_xml_cases(
            model, args.operation, entry["negative_xml"]
        )
    if "signed_socket" in entry:
        generated_socket = json.loads(
            s3_operation.signed_socket_text(registry, model)
        )["operations"][args.operation]
        result["signed_socket_cases"] = [
            {
                "id": case["id"],
                "lane": case["lane"],
                "exchange_count": len(case["exchange"]),
            }
            for case in generated_socket["cases"]
        ]
    print(json.dumps(result, indent=2, sort_keys=True))
    return 1 if unresolved or findings else 0


def scaffold(args: argparse.Namespace, registry: s3_operation.Registry) -> int:
    entry = registry.operations.get(args.operation)
    if entry is None:
        raise s3_operation.Audit_Error(
            f"operation is absent from registry: {args.operation}"
        )
    unresolved = s3_operation.unresolved_decisions(entry)
    findings = s3_operation.evidence_findings(entry)
    if unresolved or findings:
        raise s3_operation.Audit_Error(
            "scaffold refuses unresolved review inputs: "
            + ", ".join(unresolved + findings)
        )
    model = s3_operation.load_model(s3_operation.model_path(args.model))
    s3_operation.verify_registry_model_inventory(registry, model)
    result = s3_operation.operation_audit(model, args.operation)
    negative = (
        s3_operation.negative_xml_cases(
            model, args.operation, entry["negative_xml"]
        )
        if "negative_xml" in entry
        else []
    )
    print(
        json.dumps(
            {
                "operation": args.operation,
                "family": entry["family"],
                "public_provider": entry["public_provider"],
                "public_name": entry["public_name"],
                "codec": entry["codec"],
                "model": result,
                "generated_negative_xml": negative,
                "signed_socket": (
                    json.loads(s3_operation.signed_socket_text(registry, model))[
                        "operations"
                    ].get(args.operation)
                    if "signed_socket" in entry
                    else None
                ),
                "note": (
                    "deterministic reviewed scaffold input; no source was "
                    "written and no policy was inferred"
                ),
            },
            indent=2,
            sort_keys=True,
        )
    )
    return 0


def qualify(args: argparse.Namespace, registry: s3_operation.Registry) -> int:
    audit_result = audit(args, registry)
    if audit_result != 0:
        return audit_result
    qualification = registry.operations[args.operation].get("qualification")
    if not qualification:
        raise s3_operation.Audit_Error(
            "operation has no focused qualification lane"
        )
    commands = registry.qualification.get(qualification)
    if commands is None:
        raise s3_operation.Audit_Error(
            f"unknown qualification lane: {qualification}"
        )
    s3_operation.run_commands(commands, s3_operation.model_path(args.model))
    return 0


def generate(args: argparse.Namespace, registry: s3_operation.Registry) -> int:
    model = None
    if args.model or os.environ.get("FLYOLOGY_S3_SERVICE_MODEL"):
        model = s3_operation.load_model(s3_operation.model_path(args.model))
        s3_operation.verify_registry_model_inventory(registry, model)
    if args.check:
        s3_operation.check_generated_outputs(registry, model)
        print("S3 operation generated outputs: current")
        return 0
    if any(
        "negative_xml" in entry or "signed_socket" in entry
        for entry in registry.operations.values()
    ) and model is None:
        raise s3_operation.Audit_Error(
            "generating model-derived qualification requires the pinned model"
        )
    for path, expected in s3_operation.generated_outputs(registry, model).items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(expected, encoding="utf-8")
        print(f"generated {path.relative_to(s3_operation.ROOT)}")
    return 0


def main() -> int:
    args = parser().parse_args()
    registry = s3_operation.load_registry()
    if args.action == "audit":
        return audit(args, registry)
    if args.action == "scaffold":
        return scaffold(args, registry)
    if args.action == "qualify":
        return qualify(args, registry)
    if args.action == "generate":
        return generate(args, registry)
    raise AssertionError(args.action)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (
        OSError,
        ValueError,
        json.JSONDecodeError,
        subprocess.CalledProcessError,
    ) as error:
        print(f"s3-operation: {error}", file=sys.stderr)
        raise SystemExit(1)
