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
import s3_codegen


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser()
    value.add_argument("--model", help="pinned botocore service-2.json")
    actions = value.add_subparsers(dest="action", required=True)
    for name in ("audit", "scaffold", "qualify"):
        child = actions.add_parser(name)
        child.add_argument(
            "operation",
            nargs="+" if name in {"audit", "qualify"} else None,
        )
        if name == "scaffold":
            child.add_argument(
                "--output-dir",
                help="write deterministic generated Ada descriptors here",
            )
            child.add_argument(
                "--prospective",
                action="store_true",
                help="emit a temporary canary for an authoritative operation",
            )
    actions.add_parser("generate").add_argument(
        "--check", action="store_true", help="fail instead of writing outputs"
    )
    return value


def audit_operation(
    registry: s3_operation.Registry,
    model: dict[str, object],
    operation: str,
) -> tuple[dict[str, object], bool]:
    entry = registry.operations.get(operation)
    if entry is None:
        raise s3_operation.Audit_Error(
            f"operation is absent from registry: {operation}"
        )
    result = s3_operation.operation_audit(model, operation)
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
    if entry["family"] in {
        "bounded_rest_xml_read",
        "paginated_rest_xml_read",
    }:
        result["generated_codec_plan"] = s3_codegen.codec_plan(
            model, operation, entry
        )
    if "negative_xml" in entry:
        result["generated_negative_xml"] = s3_operation.negative_xml_cases(
            model, operation, entry["negative_xml"]
        )
    if "signed_socket" in entry:
        generated_socket = json.loads(
            s3_operation.signed_socket_text(registry, model)
        )["operations"][operation]
        result["signed_socket_cases"] = [
            {
                "id": case["id"],
                "lane": case["lane"],
                "exchange_count": len(case["exchange"]),
            }
            for case in generated_socket["cases"]
        ]
    return result, bool(unresolved or findings)


def audit(args: argparse.Namespace, registry: s3_operation.Registry) -> int:
    operations = list(args.operation)
    s3_operation.validate_operation_names(operations)
    model = s3_operation.load_model(s3_operation.model_path(args.model))
    s3_operation.verify_registry_model_inventory(registry, model)
    results = [
        audit_operation(registry, model, operation)
        for operation in operations
    ]
    output: object = results[0][0]
    if len(results) > 1:
        output = {
            "batch": {
                "operation_count": len(operations),
                "operations": operations,
            },
            "operations": [result for result, _ in results],
        }
    print(json.dumps(output, indent=2, sort_keys=True))
    return 1 if any(failed for _, failed in results) else 0


def scaffold(args: argparse.Namespace, registry: s3_operation.Registry) -> int:
    entry = registry.operations.get(args.operation)
    if entry is None:
        raise s3_operation.Audit_Error(
            f"operation is absent from registry: {args.operation}"
        )
    unresolved = s3_operation.unresolved_decisions(entry)
    if unresolved:
        raise s3_operation.Audit_Error(
            "scaffold refuses unresolved review inputs: "
            + ", ".join(unresolved)
        )
    if not entry["generator_eligible"] and not args.prospective:
        raise s3_operation.Audit_Error(
            "scaffold refuses an authoritative existing implementation; "
            "use --prospective only for non-destructive equivalence output"
        )
    model = s3_operation.load_model(s3_operation.model_path(args.model))
    s3_operation.verify_registry_model_inventory(registry, model)
    result = s3_operation.operation_audit(model, args.operation)
    descriptor = None
    generated_files: list[str] = []
    if entry["family"] in {
        "bounded_rest_xml_read",
        "paginated_rest_xml_read",
    }:
        unit, spec, body = s3_codegen.codec_descriptor_text(
            model, args.operation, entry
        )
        descriptor = s3_codegen.codec_plan(model, args.operation, entry)
        output_name = args.output_dir
        if (
            output_name is None
            and entry["generator_eligible"]
            and not args.prospective
        ):
            output_name = str(s3_operation.ROOT / "src")
        if output_name:
            output = Path(output_name).resolve()
            if args.prospective and output.is_relative_to(s3_operation.ROOT):
                raise s3_operation.Audit_Error(
                    "prospective canary output must remain outside the "
                    "tracked repository"
                )
            output.mkdir(parents=True, exist_ok=True)
            for suffix, text in (("ads", spec), ("adb", body)):
                path = output / f"{unit}.{suffix}"
                generated_header = (
                    "with Flyology.Object_Storage.S3.XML;\n\n"
                    "--  Generated by tools/s3-operation.py; do not edit."
                    if suffix == "ads"
                    else (
                        "with Flyology.Object_Storage.S3."
                        "Strict_XML_Codecs;"
                    )
                )
                if path.exists() and not path.read_text(
                    encoding="utf-8"
                ).startswith(generated_header):
                    raise s3_operation.Audit_Error(
                        f"scaffold refuses non-generated output: {path}"
                    )
                path.write_text(text, encoding="utf-8")
                generated_files.append(str(path))
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
                "generated_codec_plan": descriptor,
                "generated_files": generated_files,
                "generated_negative_xml": negative,
                "signed_socket": (
                    json.loads(s3_operation.signed_socket_text(registry, model))[
                        "operations"
                    ].get(args.operation)
                    if "signed_socket" in entry
                    else None
                ),
                "note": (
                    "deterministic reviewed scaffold; no policy was inferred"
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
    operations = list(args.operation)
    qualification, commands = s3_operation.qualification_plan(
        registry, operations
    )
    print(
        json.dumps(
            {
                "qualification": qualification,
                "operations": operations,
                "command_count": len(commands),
            },
            indent=2,
            sort_keys=True,
        ),
        flush=True,
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
        if model is not None:
            s3_codegen.check_generated_ada_outputs(registry, model)
        print("S3 operation generated outputs: current")
        return 0
    if any(
        "negative_xml" in entry or "signed_socket" in entry
        for entry in registry.operations.values()
    ) and model is None:
        raise s3_operation.Audit_Error(
            "generating model-derived qualification requires the pinned model"
        )
    ada_outputs: dict[Path, str] = {}
    if model is not None:
        ada_outputs = s3_codegen.generated_ada_outputs(registry, model)
    outputs = s3_operation.generated_outputs(
        registry, model, source_overrides=ada_outputs
    )
    outputs.update(ada_outputs)
    for path, expected in outputs.items():
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
