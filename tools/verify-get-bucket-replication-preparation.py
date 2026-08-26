#!/usr/bin/env python3
"""Verify the pinned current GetBucketReplication model and implementation."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "src/flyology-object_storage-s3-model.adb"
LOCK = ROOT / "coverage/corpora.lock.toml"
SOURCES = (
    ROOT / "src/flyology-object_storage-client-low_level.ads",
    ROOT / "src/flyology-object_storage-client-low_level.adb",
    ROOT / "src/flyology-object_storage-client-buckets.ads",
    ROOT / "src/flyology-object_storage-client-buckets.adb",
    ROOT / "src/flyology-object_storage-s3-replication.ads",
    ROOT / "src/flyology-object_storage-s3-replication.adb",
    ROOT / "tests/src/s3_get_bucket_replication_corpus.adb",
)
REVISION = "36c34f15391da01cd717c73c0fffa747c9889768"
SHA256 = "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"


def fail(message: str) -> None:
    raise ValueError(message)


def function_body(model: str, function: str) -> str:
    match = re.search(rf"   function {re.escape(function)}(?=\s*\()", model)
    if match is None:
        fail(f"generated model lacks {function}")
    tail = model[match.end():]
    marker = f"end {function};"
    if marker not in tail:
        fail(f"generated model lacks end {function}")
    return tail.split(marker, 1)[0]


def operation_scalar(model: str, function: str) -> str:
    match = re.search(
        r"when Get_Bucket_Replication_Operation =>\s+return\s+([^;]+);",
        function_body(model, function),
    )
    if match is None:
        fail(f"GetBucketReplication lacks {function}")
    return match.group(1).strip().strip('"')


def shape_scalar(model: str, function: str, shape: int) -> str:
    match = re.search(
        rf"when\s+{shape}\s+=>\s+return\s+([^;]+);",
        function_body(model, function),
    )
    if match is None:
        fail(f"shape {shape} lacks {function}")
    return match.group(1).strip().strip('"')


def case_values(model: str, function: str, shape: int) -> list[str]:
    match = re.search(
        rf"when {shape} =>\s+case Member is(.*?)\s+end case;",
        function_body(model, function),
        re.DOTALL,
    )
    if match is None:
        fail(f"shape {shape} lacks {function} members")
    value = (
        r'"([^\"]*)"'
        if function in ("Member_Name", "Member_Location_Name")
        else r"([A-Za-z_][A-Za-z0-9_]*|\d+)"
    )
    pairs = re.findall(
        rf"when\s+(\d+)\s+=>\s+return\s+{value};", match.group(1)
    )
    if [int(index) for index, _ in pairs] != list(range(1, len(pairs) + 1)):
        fail(f"shape {shape} {function} is not contiguous")
    return [item for _, item in pairs]


def enum_values(model: str, shape: int) -> list[str]:
    match = re.search(
        rf"when {shape} =>\s+case Index is(.*?)\s+end case;",
        function_body(model, "Enumeration_Value"),
        re.DOTALL,
    )
    if match is None:
        fail(f"shape {shape} lacks enum values")
    return [
        value
        for _, value in re.findall(
            r'when\s+(\d+)\s+=>\s+return\s+"([^"]*)";', match.group(1)
        )
    ]


def require_shape(
    model: str,
    shape: int,
    names: list[str],
    shapes: list[str],
    required: list[str],
    locations: list[str],
) -> None:
    if (
        case_values(model, "Member_Name", shape) != names
        or case_values(model, "Member_Shape", shape) != shapes
        or case_values(model, "Member_Required", shape) != required
        or case_values(model, "Member_Location_Name", shape) != locations
    ):
        fail(f"generated replication shape {shape} changed")


def main() -> int:
    lock = LOCK.read_text(encoding="utf-8")
    if (
        f'revision = "{REVISION}"' not in lock
        or f'service_model_sha256 = "{SHA256}"' not in lock
    ):
        fail("pinned botocore identity changed")
    model = MODEL.read_text(encoding="utf-8")
    expected_scalars = {
        "Method": "Get_Method",
        "Request_URI": "/{Bucket}?replication",
        "Response_Code": "200",
        "Input_Shape": "261",
        "Output_Shape": "260",
        "Request_Checksum_Required": "False",
        "Request_Checksum_Algorithm_Member": "",
    }
    for function, expected in expected_scalars.items():
        if operation_scalar(model, function) != expected:
            fail(f"generated GetBucketReplication {function} changed")

    require_shape(
        model,
        261,
        ["Bucket", "ExpectedBucketOwner"],
        ["60", "15"],
        ["True", "False"],
        ["Bucket", "x-amz-expected-bucket-owner"],
    )
    require_shape(
        model,
        260,
        ["ReplicationConfiguration"],
        ["588"],
        ["False"],
        ["ReplicationConfiguration"],
    )
    require_shape(
        model,
        588,
        ["Role", "Rules"],
        ["618", "593"],
        ["True", "True"],
        ["Role", "Rule"],
    )
    require_shape(
        model,
        589,
        [
            "ID", "Priority", "Prefix", "Filter", "Status",
            "SourceSelectionCriteria", "ExistingObjectReplication",
            "Destination", "DeleteMarkerReplication",
        ],
        ["308", "518", "517", "591", "592", "659", "203", "179", "162"],
        ["False", "False", "False", "False", "True", "False", "False", "True", "False"],
        [
            "ID", "Priority", "Prefix", "Filter", "Status",
            "SourceSelectionCriteria", "ExistingObjectReplication",
            "Destination", "DeleteMarkerReplication",
        ],
    )
    require_shape(
        model,
        590,
        ["Prefix", "Tags"],
        ["517", "674"],
        ["False", "False"],
        ["Prefix", "Tag"],
    )
    require_shape(
        model,
        591,
        ["Prefix", "Tag", "And"],
        ["517", "672", "590"],
        ["False", "False", "False"],
        ["Prefix", "Tag", "And"],
    )
    for shape, names, shapes, required in (
        (10, ["Owner"], ["500"], ["True"]),
        (162, ["Status"], ["163"], ["False"]),
        (179,
         ["Bucket", "Account", "StorageClass", "AccessControlTranslation",
          "EncryptionConfiguration", "ReplicationTime", "Metrics"],
         ["60", "15", "666", "10", "188", "595", "431"],
         ["True", "False", "False", "False", "False", "False", "False"]),
        (188, ["ReplicaKmsKeyID"], ["585"], ["False"]),
        (203, ["Status"], ["204"], ["True"]),
        (431, ["Status", "EventThreshold"], ["437", "597"],
         ["True", "False"]),
        (586, ["Status"], ["587"], ["True"]),
        (595, ["Status", "Time"], ["596", "597"], ["True", "True"]),
        (597, ["Minutes"], ["438"], ["False"]),
        (659, ["SseKmsEncryptedObjects", "ReplicaModifications"],
         ["660", "586"], ["False", "False"]),
        (660, ["Status"], ["661"], ["True"]),
    ):
        require_shape(model, shape, names, shapes, required, names)
    if (
        shape_scalar(model, "Kind", 593) != "List_Shape"
        or shape_scalar(model, "List_Member_Shape", 593) != "589"
        or shape_scalar(model, "Is_Flattened", 593) != "True"
        or shape_scalar(model, "Kind", 674) != "List_Shape"
        or shape_scalar(model, "List_Member_Shape", 674) != "672"
        or shape_scalar(model, "Is_Flattened", 674) != "False"
        or case_values(model, "Member_Flattened", 590) != ["False", "True"]
    ):
        fail("replication flattened list shapes changed")
    for shape in (163, 204, 437, 587, 592, 596, 661):
        if enum_values(model, shape) != ["Enabled", "Disabled"]:
            fail(f"replication status domain {shape} changed")
    if enum_values(model, 500) != ["Destination"]:
        fail("replication access-control owner domain changed")
    if enum_values(model, 666) != [
        "STANDARD", "REDUCED_REDUNDANCY", "STANDARD_IA", "ONEZONE_IA",
        "INTELLIGENT_TIERING", "GLACIER", "DEEP_ARCHIVE", "OUTPOSTS",
        "GLACIER_IR", "SNOW", "EXPRESS_ONEZONE", "FSX_OPENZFS",
        "FSX_ONTAP", "AWS_BACKUP_WARM", "AWS_BACKUP_LOW_COST_WARM",
    ]:
        fail("replication destination storage-class domain changed")

    source = "\n".join(path.read_text(encoding="utf-8") for path in SOURCES)
    for token in (
        "Prepare_Get_Bucket_Replication",
        "Decode_Get_Bucket_Replication_Response",
        "Execute_Get_Bucket_Replication",
        "Get_Bucket_Replication_Operation",
        "Get_Replication_Configuration",
        "Replication_Configuration",
        "Source_Selection_Criteria",
        "Delete_Marker_Replication",
        "AWS_Backup_Low_Cost_Warm",
    ):
        if token not in source:
            fail(f"typed implementation lacks {token}")
    print(
        "GetBucketReplication preparation: current 2-member input, complete "
        "required Role/rules graph, full nested destination/filter controls, "
        "and exact 15-value storage-class domain"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"GetBucketReplication preparation verification failed: {exc}",
              file=sys.stderr)
        raise SystemExit(1)
