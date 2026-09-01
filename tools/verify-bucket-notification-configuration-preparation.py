#!/usr/bin/env python3
"""Verify the pinned current bucket-notification inventory and boundary."""

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
    ROOT / "src/flyology-object_storage-s3-notifications.ads",
    ROOT / "src/flyology-object_storage-s3-notifications.adb",
    ROOT / "tests/src/s3_bucket_notification_configuration_corpus.adb",
)
BACKEND_SPEC = ROOT / "src/flyology-object_storage-backends.ads"
MEMORY = ROOT / "src/flyology-object_storage-backends-memory.adb"
FILES = ROOT / "src/flyology-object_storage-backends-files.adb"
SQLITE = ROOT / "sqlite/src/flyology-object_storage-backends-sqlite.adb"
CATALOG = ROOT / "sqlite/src/flyology-object_storage-sqlite-catalogs.adb"
SERVER = ROOT / "src/flyology-object_storage-server-s3_applications.adb"
SERVER_CORPUS = ROOT / "tests/src/s3_server_application_corpus.adb"
BACKEND_CORPUS = ROOT / "tests/src/object_storage_test_cases.adb"
SQLITE_CORPUS = (
    ROOT / "sqlite/tests/src/flyology_object_storage_sqlite_tests.adb"
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


def operation_scalar(model: str, operation: str, function: str) -> str:
    match = re.search(
        rf"when {re.escape(operation)} =>\s+return\s+([^;]+);",
        function_body(model, function),
    )
    if match is None:
        fail(f"{operation} lacks {function}")
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


def require_members(
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
        fail(f"generated notification shape {shape} changed")


def require_fragments(
    text: str, label: str, fragments: tuple[str, ...]
) -> None:
    for fragment in fragments:
        if fragment not in text:
            fail(f"{label} lacks {fragment}")


def main() -> int:
    lock = LOCK.read_text(encoding="utf-8")
    if (
        f'revision = "{REVISION}"' not in lock
        or f'service_model_sha256 = "{SHA256}"' not in lock
    ):
        fail("pinned botocore identity changed")
    model = MODEL.read_text(encoding="utf-8")
    operations = {
        "Get_Bucket_Notification_Operation": {
            "Method": "Get_Method",
            "Request_URI": "/{Bucket}?notification",
            "Response_Code": "200",
            "Input_Shape": "253",
            "Output_Shape": "459",
            "Request_Checksum_Required": "False",
            "Request_Checksum_Algorithm_Member": "",
        },
        "Get_Bucket_Notification_Configuration_Operation": {
            "Method": "Get_Method",
            "Request_URI": "/{Bucket}?notification",
            "Response_Code": "200",
            "Input_Shape": "253",
            "Output_Shape": "458",
            "Request_Checksum_Required": "False",
            "Request_Checksum_Algorithm_Member": "",
        },
        "Put_Bucket_Notification_Configuration_Operation": {
            "Method": "Put_Method",
            "Request_URI": "/{Bucket}?notification",
            "Response_Code": "200",
            "Input_Shape": "536",
            "Output_Shape": "0",
            "Request_Checksum_Required": "False",
            "Request_Checksum_Algorithm_Member": "",
        },
        "Put_Bucket_Notification_Operation": {
            "Method": "Put_Method",
            "Request_URI": "/{Bucket}?notification",
            "Response_Code": "200",
            "Input_Shape": "537",
            "Output_Shape": "0",
            "Request_Checksum_Required": "True",
            "Request_Checksum_Algorithm_Member": "ChecksumAlgorithm",
        },
    }
    for operation, scalars in operations.items():
        for function, expected in scalars.items():
            if operation_scalar(model, operation, function) != expected:
                fail(f"generated {operation} {function} changed")

    require_members(
        model,
        253,
        ["Bucket", "ExpectedBucketOwner"],
        ["60", "15"],
        ["True", "False"],
        ["Bucket", "x-amz-expected-bucket-owner"],
    )
    require_members(
        model,
        459,
        [
            "TopicConfiguration",
            "QueueConfiguration",
            "CloudFunctionConfiguration",
        ],
        ["690", "562", "93"],
        ["False", "False", "False"],
        [
            "TopicConfiguration",
            "QueueConfiguration",
            "CloudFunctionConfiguration",
        ],
    )
    require_members(
        model,
        690,
        ["Id", "Events", "Event", "Topic"],
        ["461", "202", "200", "688"],
        ["False", "False", "False", "False"],
        ["Id", "Event", "Event", "Topic"],
    )
    require_members(
        model,
        562,
        ["Id", "Event", "Events", "Queue"],
        ["461", "200", "202", "560"],
        ["False", "False", "False", "False"],
        ["Id", "Event", "Event", "Queue"],
    )
    require_members(
        model,
        93,
        ["Id", "Event", "Events", "CloudFunction", "InvocationRole"],
        ["461", "200", "202", "92", "94"],
        ["False", "False", "False", "False", "False"],
        ["Id", "Event", "Event", "CloudFunction", "InvocationRole"],
    )
    require_members(
        model,
        536,
        [
            "Bucket",
            "NotificationConfiguration",
            "ExpectedBucketOwner",
            "SkipDestinationValidation",
        ],
        ["60", "458", "15", "658"],
        ["True", "True", "False", "False"],
        [
            "Bucket",
            "NotificationConfiguration",
            "x-amz-expected-bucket-owner",
            "x-amz-skip-destination-validation",
        ],
    )
    require_members(
        model,
        537,
        [
            "Bucket",
            "ContentMD5",
            "ChecksumAlgorithm",
            "NotificationConfiguration",
            "ExpectedBucketOwner",
        ],
        ["60", "111", "77", "459", "15"],
        ["True", "False", "False", "True", "False"],
        [
            "Bucket",
            "Content-MD5",
            "x-amz-sdk-checksum-algorithm",
            "NotificationConfiguration",
            "x-amz-expected-bucket-owner",
        ],
    )
    require_members(
        model,
        458,
        [
            "TopicConfigurations",
            "QueueConfigurations",
            "LambdaFunctionConfigurations",
            "EventBridgeConfiguration",
        ],
        ["691", "563", "369", "201"],
        ["False", "False", "False", "False"],
        [
            "TopicConfiguration",
            "QueueConfiguration",
            "CloudFunctionConfiguration",
            "EventBridgeConfiguration",
        ],
    )
    for shape, destination_shape, destination_name in (
        (689, "688", "Topic"),
        (561, "560", "Queue"),
        (368, "367", "CloudFunction"),
    ):
        require_members(
            model,
            shape,
            ["Id", destination_name + ("Arn" if destination_name != "CloudFunction" else "Arn"), "Events", "Filter"]
            if destination_name != "CloudFunction"
            else ["Id", "LambdaFunctionArn", "Events", "Filter"],
            ["461", destination_shape, "202", "460"],
            ["False", "True", "True", "False"],
            ["Id", destination_name, "Event", "Filter"],
        )
    require_members(model, 460, ["Key"], ["623"], ["False"], ["S3Key"])
    require_members(
        model, 623, ["FilterRules"], ["218"], ["False"], ["FilterRule"]
    )
    require_members(
        model,
        217,
        ["Name", "Value"],
        ["219", "220"],
        ["False", "False"],
        ["Name", "Value"],
    )
    for shape, member in ((691, "689"), (563, "561"), (369, "368"),
                          (218, "217"), (202, "200")):
        if (
            shape_scalar(model, "Kind", shape) != "List_Shape"
            or shape_scalar(model, "List_Member_Shape", shape) != member
            or shape_scalar(model, "Is_Flattened", shape) != "True"
        ):
            fail(f"generated flattened list shape {shape} changed")
    if enum_values(model, 219) != ["prefix", "suffix"] or len(
        enum_values(model, 200)
    ) != 30:
        fail("generated notification enum domain changed")

    source = "\n".join(path.read_text(encoding="utf-8") for path in SOURCES)
    low_level = SOURCES[1].read_text(encoding="utf-8")
    prepare = function_body(
        low_level, "Prepare_Put_Bucket_Notification_Configuration"
    )
    for token in (
        "Model.Put_Bucket_Notification_Configuration_Operation",
        "Notifications.Serialize (Value, Limits)",
        "Content_MD5           => US.Null_Unbounded_String",
        "Checksum_Algorithm    => US.Null_Unbounded_String",
        "Has_Skip_Destination_Validation => True",
    ):
        if prepare.count(token) != 1:
            fail(f"maintained notification preparation lacks exact {token}")
    if "Model.Put_Bucket_Notification_Operation" in prepare:
        fail("deprecated notification operation identity is unexpectedly used")
    for token in (
        "Prepare_Get_Bucket_Notification_Configuration",
        "Decode_Get_Bucket_Notification_Configuration_Response",
        "Execute_Get_Bucket_Notification_Configuration",
        "Prepare_Put_Bucket_Notification_Configuration",
        "Execute_Put_Bucket_Notification_Configuration",
        "Get_Bucket_Notification_Operation",
        "Put_Bucket_Notification_Operation",
        "Get_Notification_Configuration",
        "Set_Notification_Configuration",
        "x-amz-skip-destination-validation",
        "Event_Bridge_Is_Set",
    ):
        if token not in source:
            fail(f"typed implementation lacks {token}")

    backend_spec = BACKEND_SPEC.read_text(encoding="utf-8")
    memory = MEMORY.read_text(encoding="utf-8")
    files = FILES.read_text(encoding="utf-8")
    sqlite = SQLITE.read_text(encoding="utf-8")
    catalog = CATALOG.read_text(encoding="utf-8")
    server = SERVER.read_text(encoding="utf-8")
    server_corpus = SERVER_CORPUS.read_text(encoding="utf-8")
    backend_corpus = BACKEND_CORPUS.read_text(encoding="utf-8")
    sqlite_corpus = SQLITE_CORPUS.read_text(encoding="utf-8")
    require_fragments(
        backend_spec,
        "backend notification contract",
        (
            "function Valid_Bucket_Notification_Document",
            "type Bucket_Notification_Backend is limited interface",
            "Item     : in out Bucket_Notification_Backend",
            "procedure Put_Bucket_Notification_If_Supported",
            "procedure Get_Bucket_Notification_If_Supported",
            "Item     : in out Backend'Class",
            "procedure Put_Bucket_Notification",
            "procedure Get_Bucket_Notification",
            "backend does not deliver notifications",
            "Not_Implemented without the capability",
        ),
    )
    require_fragments(
        memory,
        "memory notification persistence",
        (
            "Notification_Configuration, Document, \"\", Result",
            "Bucket, Notification_Configuration, Document, Ignored_Metadata",
        ),
    )
    require_fragments(
        files,
        "files notification persistence",
        (
            'Bucket_Notification_Magic : constant String := "FOSNOT01"',
            '"notification.fos"',
            "Write_Bucket_Notification'Access",
            "Read_Bucket_Notification'Access",
        ),
    )
    require_fragments(
        sqlite + catalog,
        "SQLite notification persistence",
        (
            "Catalogs.Put_Bucket_Notification",
            "Catalogs.Get_Bucket_Notification",
            'Schema_Version : constant Long_Long_Integer := 21',
            '"CREATE TABLE bucket_notification_documents ("',
            "procedure Upgrade_From_V19",
        ),
    )
    require_fragments(
        server,
        "notification server boundary",
        (
            "Put_Bucket_Notification_Configuration",
            "Get_Bucket_Notification_Configuration",
            '"x-amz-skip-destination-validation"',
            '"Destination validation is unavailable"',
            "Store.Put_Bucket_Notification_If_Supported",
            "Store.Get_Bucket_Notification_If_Supported",
            "Empty_Notification_Document",
        ),
    )
    for operation in (
        "PutBucketNotification",
        "PutBucketNotificationConfiguration",
        "GetBucketNotification",
        "GetBucketNotificationConfiguration",
    ):
        if server.count(operation) < 2:
            fail(f"server lacks exact {operation} query and dispatch evidence")
        if operation not in server_corpus:
            fail(f"server corpus lacks {operation}")
    require_fragments(
        server_corpus,
        "notification server corpus",
        (
            '"current notification PUT skipped destination validation"',
            '"legacy notification PUT claimed destination validation"',
            '"legacy notification PUT misclassified a deprecated-only shape"',
            '"legacy notification PUT accepted missing checksum transport"',
            '"legacy notification PUT accepted a Content-MD5 mismatch"',
            '"legacy notification PUT rejected a generated checksum"',
            '"legacy notification PUT accepted a generated checksum mismatch"',
            '"notification GET accepted an extra query member"',
        ),
    )
    require_fragments(
        backend_corpus + sqlite_corpus,
        "notification backend corpora",
        (
            '"bucket notification configuration did not round trip"',
            '"schema-v19 migration did not publish schema 21 atomically"',
        ),
    )
    print(
        "Bucket notification configuration preparation: deprecated GET and "
        "PUT partial boundaries; legacy PUT five-member checksum request, "
        "current PUT four-member unchecksummed request, complete current "
        "destination/filter graph, 30-event exact domain, shared backend "
        "persistence, and exact current/legacy server routes"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, UnicodeError, ValueError) as exc:
        print(
            f"Bucket notification configuration verification failed: {exc}",
            file=sys.stderr,
        )
        raise SystemExit(1)
