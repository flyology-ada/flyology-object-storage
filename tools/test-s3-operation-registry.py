#!/usr/bin/env python3
"""Negative oracles for reviewed S3 operation evidence promotion."""

from __future__ import annotations

import copy
import hashlib
import json
import os
import tempfile
from collections import Counter
from pathlib import Path

import s3_operation
import s3_codegen


def main() -> None:
    original_source = "package Example is\n\nprivate\n\nend Example;\n"
    materialized = s3_codegen.materialize_generated_region(
        original_source,
        "EXAMPLE_VISIBLE",
        "   Generated_Value : constant := 1;",
        "private",
    )
    assert materialized.startswith("package Example is\n\n--  BEGIN")
    assert materialized.endswith("private\n\nend Example;\n")
    replaced = s3_codegen.materialize_generated_region(
        materialized,
        "EXAMPLE_VISIBLE",
        "   Generated_Value : constant := 2;",
        "private",
    )
    assert "constant := 1" not in replaced
    assert replaced.count("constant := 2") == 1
    assert replaced.replace("constant := 2", "constant := 1") == materialized
    try:
        s3_codegen.materialize_generated_region(
            materialized.replace("--  END S3 OPERATION GENERATOR", "--  LOST"),
            "EXAMPLE_VISIBLE",
            "",
            "private",
        )
    except s3_operation.Audit_Error:
        pass
    else:
        raise AssertionError("unbalanced generated source region was accepted")
    replacement = s3_codegen.materialize_generated_replacement(
        "before\nlegacy\nafter\n",
        "EXAMPLE_REPLACEMENT",
        "generated",
        "legacy",
    )
    assert "legacy" not in replacement
    assert "generated" in replacement
    assert s3_codegen.materialize_generated_replacement(
        replacement,
        "EXAMPLE_REPLACEMENT",
        "updated",
        "legacy",
    ).replace("updated", "generated") == replacement

    registry = s3_operation.load_registry()
    assert Counter(
        entry["implementation_mode"]
        for entry in registry.operations.values()
    ) == {
        "handwritten": 78,
        "generated": 21,
        "shared-family": 17,
    }
    assert {
        name
        for name, entry in registry.operations.items()
        if entry["generator_eligible"]
    } == {
        "ListDirectoryBuckets",
        "PutBucketAcl",
        "PutBucketInventoryConfiguration",
        "PutBucketLogging",
        "PutBucketWebsite",
    }
    canary = registry.operations["GetBucketReplication"]
    assert not s3_operation.evidence_findings(
        canary, include_partial=False
    )

    promoted = copy.deepcopy(registry.operations["CreateSession"])
    promoted["coverage"]["server"] = "covered"
    promoted["provenance"]["server"] = "handwritten"
    findings = s3_operation.evidence_findings(
        promoted, include_partial=False
    )
    assert "covered server lacks executable evidence" in findings

    disconnected = copy.deepcopy(canary)
    disconnected["evidence"]["client"] = [
        "tests/src/s3_checksum_corpus.adb"
    ]
    assert (
        "client evidence does not name GetBucketReplication"
        in s3_operation.evidence_findings(
            disconnected, include_partial=False
        )
    )
    negative = json.loads(
        s3_operation.NEGATIVE_XML_PATH.read_text(encoding="utf-8")
    )
    cases = negative["operations"]["GetBucketReplication"]["cases"]
    assert len(cases) == 17
    assert Counter(case["category"] for case in cases) == {
        "duplicate-singleton": 4,
        "empty-required-flattened-list": 1,
        "invalid-enum": 1,
        "limit-failure": 4,
        "missing-required-member": 4,
        "namespace-violation": 1,
        "unexpected-attribute": 1,
        "unknown-member": 1,
    }
    metrics_cases = negative["operations"][
        "GetBucketMetricsConfiguration"
    ]["cases"]
    assert len(metrics_cases) == 17
    assert Counter(case["category"] for case in metrics_cases) == {
        "duplicate-singleton": 7,
        "limit-failure": 4,
        "missing-required-member": 3,
        "namespace-violation": 1,
        "unexpected-attribute": 1,
        "unknown-member": 1,
    }
    logging_cases = negative["operations"]["GetBucketLogging"]["cases"]
    assert len(logging_cases) == 38
    assert Counter(case["category"] for case in logging_cases) == {
        "attribute-namespace-violation": 3,
        "duplicate-singleton": 16,
        "invalid-attribute-enum": 3,
        "invalid-enum": 4,
        "limit-failure": 4,
        "missing-required-attribute": 3,
        "missing-required-member": 2,
        "namespace-violation": 1,
        "unexpected-attribute": 1,
        "unknown-member": 1,
    }
    website_cases = negative["operations"]["GetBucketWebsite"]["cases"]
    assert len(website_cases) == 32
    assert Counter(case["category"] for case in website_cases) == {
        "duplicate-singleton": 18,
        "invalid-enum": 2,
        "limit-failure": 4,
        "missing-required-member": 5,
        "namespace-violation": 1,
        "unexpected-attribute": 1,
        "unknown-member": 1,
    }
    invalid_logging_decisions = copy.deepcopy(
        registry.operations["GetBucketLogging"]["negative_xml"]
    )
    invalid_logging_decisions["payload_shape"] = "GetBucketLoggingRequest"
    try:
        s3_operation.negative_xml_cases(
            s3_operation.load_model(s3_operation.model_path(None)),
            "GetBucketLogging",
            invalid_logging_decisions,
        )
    except s3_operation.Audit_Error:
        pass
    else:
        raise AssertionError("unrelated reviewed XML payload alias was accepted")

    stale = copy.deepcopy(negative)
    stale["model_sha256"] = "0" * 64
    with tempfile.TemporaryDirectory(prefix="s3-operation-registry-") as directory:
        path = Path(directory) / "negative.json"
        path.write_text(json.dumps(stale), encoding="utf-8")
        try:
            s3_operation.validate_committed_negative_xml(registry, path)
        except s3_operation.Audit_Error:
            pass
        else:
            raise AssertionError("stale negative XML model hash was accepted")

    socket_plan = json.loads(
        s3_operation.SIGNED_SOCKET_PATH.read_text(encoding="utf-8")
    )
    socket_operation = socket_plan["operations"]["GetBucketReplication"]
    assert len(socket_operation["cases"]) == 6
    request = socket_operation["cases"][0]["exchange"][0]
    assert request["method"] == "GET"
    assert request["target"] == "/qualified-low-level?replication"
    assert request["request_headers"] == {
        "x-amz-expected-bucket-owner": "123456789012"
    }
    metrics_socket_operation = socket_plan["operations"][
        "GetBucketMetricsConfiguration"
    ]
    assert len(metrics_socket_operation["cases"]) == 7
    metrics_request = metrics_socket_operation["cases"][0]["exchange"][0]
    assert metrics_request["target"] == (
        "/qualified-low-level?id=low-level%25%20metrics&metrics"
    )
    assert metrics_request["request_headers"] == {
        "x-amz-expected-bucket-owner": "123456789012"
    }
    empty_id_request = metrics_socket_operation["cases"][2]["exchange"][0]
    assert empty_id_request["target"] == (
        "/qualified-empty-id?id&metrics"
    )
    logging_socket_operation = socket_plan["operations"]["GetBucketLogging"]
    assert len(logging_socket_operation["cases"]) == 7
    logging_request = logging_socket_operation["cases"][0]["exchange"][0]
    assert logging_request["target"] == "/qualified-low-level?logging"
    assert logging_request["request_headers"] == {
        "x-amz-expected-bucket-owner": "123456789012"
    }
    website_socket_operation = socket_plan["operations"]["GetBucketWebsite"]
    assert len(website_socket_operation["cases"]) == 7
    website_request = website_socket_operation["cases"][0]["exchange"][0]
    assert website_request["target"] == "/qualified-low-level?website"
    assert website_request["request_headers"] == {
        "x-amz-expected-bucket-owner": "123456789012"
    }
    stale_socket = copy.deepcopy(socket_plan)
    stale_socket["model_sha256"] = "0" * 64
    with tempfile.TemporaryDirectory(prefix="s3-operation-registry-") as directory:
        path = Path(directory) / "signed-socket.json"
        path.write_text(json.dumps(stale_socket), encoding="utf-8")
        try:
            s3_operation.validate_committed_signed_socket(registry, path)
        except s3_operation.Audit_Error:
            pass
        else:
            raise AssertionError("stale signed socket model hash was accepted")

    model_name = os.environ.get("FLYOLOGY_S3_SERVICE_MODEL")
    if model_name:
        model = s3_operation.load_model(Path(model_name))
        website_canary = s3_codegen.get_bucket_website_canary(registry, model)
        assert website_canary["status"] == "equivalent"
        assert website_canary["findings"] == []
        assert website_canary["model_contract"] == {
            "method": "GET",
            "uri": "/{Bucket}?website",
            "response_status": 200,
            "input_shape": "GetBucketWebsiteRequest",
            "output_shape": "GetBucketWebsiteOutput",
            "reachable_shape_count": 20,
            "payload_shape": "WebsiteConfiguration",
            "wire_node_count": 19,
        }
        assert website_canary["strict_xml"]["negative_case_count"] == 32
        assert website_canary["strict_xml"][
            "unsupported_generator_traits"
        ] == []
        assert website_canary["prospective_output"]["committed"] is False
        assert website_canary["prospective_output"]["spec_lines"] > 40
        assert website_canary["prospective_output"]["body_lines"] > 200
        directory_plan = s3_codegen.codec_plan(
            model,
            "ListDirectoryBuckets",
            registry.operations["ListDirectoryBuckets"],
        )
        assert directory_plan["unsupported_generator_traits"] == []
        assert any(
            node["pattern"] == "arn:[^:]+:(s3|s3express):.*"
            for node in directory_plan["nodes"]
        )
        _, directory_spec, directory_body = (
            s3_codegen.codec_descriptor_text(
                model,
                "ListDirectoryBuckets",
                registry.operations["ListDirectoryBuckets"],
            )
        )
        assert "function Matches_Pattern" in directory_spec
        assert "Matches_S3_Bucket_ARN" in directory_body
        for mutation, expected in {
            "PutBucketInventoryConfiguration": (
                "InventoryConfiguration",
                "IncludedObjectVersions",
            ),
            "PutBucketLogging": (
                "BucketLoggingStatus",
                "PartitionDateSource",
            ),
            "PutBucketWebsite": (
                "WebsiteConfiguration",
                "RoutingRules",
            ),
        }.items():
            unit, serializer_spec, serializer_body = (
                s3_codegen.mutation_serializer_text (model, mutation)
            )
            assert unit.startswith(
                "flyology-object_storage-s3-generated_put_bucket_"
            )
            assert "Generated by tools/s3-operation.py" in serializer_spec
            assert f'Root_Name : constant String := "{expected[0]}"' in (
                serializer_body
            )
            assert expected[1] in serializer_body
            assert "XML_Writers.Initialize (Item, Limits)" in serializer_body
            signed = s3_operation.generated_mutation_signed_socket(
                mutation, registry.operations[mutation]
            )
            assert len(signed["case"]) == 9
            assert {case["lane"] for case in signed["case"]} == {
                "low_level",
                "synchronous",
                "composable",
                "restart",
                "invalid_xml",
            }
            assert signed["case"][-1]["limits"][
                "maximum_document_bytes"
            ] > len(signed["case"][0]["exchange"][0]["request_body"])
        derived = s3_operation.negative_xml_cases(
            model, "GetBucketReplication", canary["negative_xml"]
        )
        assert derived == cases
        assert (
            s3_operation.signed_socket_text(registry, model)
            == s3_operation.SIGNED_SOCKET_PATH.read_text(encoding="utf-8")
        )
        query_request = s3_operation.signed_socket_exchange(
            model,
            "GetBucketMetricsConfiguration",
            {
                "input_values": {
                    "Bucket": "model-bucket",
                    "Id": "qualified metric/id",
                    "ExpectedBucketOwner": "123456789012",
                },
                "status": "modeled_success",
                "headers": [],
                "body": "",
            },
        )
        assert query_request["target"] == (
            "/model-bucket?id=qualified%20metric%2Fid&metrics"
        )
        assert query_request["status"] == "200 OK"
        mutation_request = s3_operation.signed_socket_exchange(
            model,
            "PutBucketMetricsConfiguration",
            {
                "input_values": {
                    "Bucket": "model-bucket",
                    "Id": "qualified metric/id",
                    "ExpectedBucketOwner": "123456789012",
                },
                "request_body": "<MetricsConfiguration/>",
                "expected_request_headers": {
                    "content-type": "application/xml"
                },
                "status": "modeled_success",
                "headers": [],
                "body": "",
            },
        )
        assert mutation_request["method"] == "PUT"
        assert mutation_request["target"] == (
            "/model-bucket?id=qualified%20metric%2Fid&metrics"
        )
        assert mutation_request["request_body"] == (
            "<MetricsConfiguration/>"
        )
        assert mutation_request["request_headers"] == {
            "x-amz-expected-bucket-owner": "123456789012",
            "content-type": "application/xml",
            "x-amz-content-sha256": hashlib.sha256(
                b"<MetricsConfiguration/>"
            ).hexdigest(),
        }
        try:
            s3_operation.signed_socket_exchange(
                model,
                "PutBucketMetricsConfiguration",
                {
                    "input_values": {
                        "Bucket": "model-bucket",
                        "Id": "missing-body",
                    },
                    "status": "modeled_success",
                    "headers": [],
                    "body": "",
                },
            )
        except s3_operation.Audit_Error:
            pass
        else:
            raise AssertionError("required mutation request body was omitted")
        try:
            s3_operation.signed_socket_exchange(
                model,
                "PutBucketMetricsConfiguration",
                {
                    "input_values": {
                        "Bucket": "model-bucket",
                        "Id": "duplicate-hash",
                    },
                    "request_body": "<MetricsConfiguration/>",
                    "expected_request_headers": {
                        "X-Amz-Content-SHA256": "reviewed-but-derived"
                    },
                    "status": "modeled_success",
                    "headers": [],
                    "body": "",
                },
            )
        except s3_operation.Audit_Error:
            pass
        else:
            raise AssertionError("derived request header was duplicated")
        invalid_seed = copy.deepcopy(canary["negative_xml"])
        invalid_seed["valid_document"] = (
            "<ReplicationConfiguration "
            'xmlns="http://s3.amazonaws.com/doc/2006-03-01/">'
            "<Rule><Status>Enabled</Status><Destination><Bucket>b</Bucket>"
            "</Destination></Rule></ReplicationConfiguration>"
        )
        try:
            s3_operation.negative_xml_cases(
                model, "GetBucketReplication", invalid_seed
            )
        except s3_operation.Audit_Error:
            pass
        else:
            raise AssertionError("invalid negative XML seed was accepted")
    print("S3 operation registry evidence negative oracles: OK")


if __name__ == "__main__":
    main()
