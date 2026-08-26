#!/usr/bin/env python3
"""Negative oracles for reviewed S3 operation evidence promotion."""

from __future__ import annotations

import copy

import s3_operation


def main() -> None:
    registry = s3_operation.load_registry()
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
    print("S3 operation registry evidence negative oracles: OK")


if __name__ == "__main__":
    main()
