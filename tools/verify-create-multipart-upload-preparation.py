#!/usr/bin/env python3
"""Verify the isolated CreateMultipartUpload disposition and design corpus."""

from __future__ import annotations

import csv
import re
import sys
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "tests" / "corpora" / "create-multipart-upload"
MEMBERS_PATH = CORPUS / "members.tsv"
VECTORS_PATH = CORPUS / "vectors.tsv"
MODEL_PATH = ROOT / "src" / "flyology-object_storage-s3-model.adb"
LOCK_PATH = ROOT / "coverage" / "corpora.lock.toml"
REGISTRY_PATH = ROOT / "coverage" / "s3-operations.toml"
LOW_SPEC_PATH = ROOT / "src" / "flyology-object_storage-client-low_level.ads"
TRANSFERS_SPEC_PATH = (
    ROOT / "src" / "flyology-object_storage-client-transfers.ads"
)
TRANSFERS_BODY_PATH = (
    ROOT / "src" / "flyology-object_storage-client-transfers.adb"
)
SOCKET_PATH = ROOT / "tests" / "src" / "s3_http_socket_corpus.adb"
CERTAINTY_PATH = (
    ROOT / "tests" / "corpora" / "composable-client"
    / "create-multipart-certainty.tsv"
)
QUALIFICATION_PATH = (
    ROOT / "docs" / "qualification"
    / "create-multipart-upload-preparation.md"
)

EXPECTED_REVISION = "36c34f15391da01cd717c73c0fffa747c9889768"
EXPECTED_SHA256 = "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
EXPECTED = {
    ("request", "135"): [
        "ACL", "Bucket", "CacheControl", "ContentDisposition",
        "ContentEncoding", "ContentLanguage", "ContentType", "Expires",
        "GrantFullControl", "GrantRead", "GrantReadACP", "GrantWriteACP",
        "Key", "Metadata", "ServerSideEncryption", "StorageClass",
        "WebsiteRedirectLocation", "SSECustomerAlgorithm", "SSECustomerKey",
        "SSECustomerKeyMD5", "SSEKMSKeyId", "SSEKMSEncryptionContext",
        "BucketKeyEnabled", "RequestPayer", "Tagging", "ObjectLockMode",
        "ObjectLockRetainUntilDate", "ObjectLockLegalHoldStatus",
        "ExpectedBucketOwner", "ChecksumAlgorithm", "ChecksumType",
    ],
    ("response", "134"): [
        "AbortDate", "AbortRuleId", "Bucket", "Key", "UploadId",
        "ServerSideEncryption", "SSECustomerAlgorithm", "SSECustomerKeyMD5",
        "SSEKMSKeyId", "SSEKMSEncryptionContext", "BucketKeyEnabled",
        "RequestCharged", "ChecksumAlgorithm", "ChecksumType",
    ],
}

MEMBER_HEADER = [
    "direction", "shape", "ordinal", "member", "wire_location",
    "current_boundary", "required_closure", "vector_ids",
]
VECTOR_HEADER = [
    "id", "direction", "layer", "category", "member_refs", "stimulus",
    "expected_contract",
]
ALLOWED_BOUNDARIES = {
    "projected", "generic_only", "partial", "missing",
}
ALLOWED_VECTOR_DIRECTIONS = {"request", "response", "both"}
MANIFEST_TO_MODEL_LOCATION = {
    "uri-label": "URI_Location",
    "header": "Header_Location",
    "header-map": "Headers_Location",
    "body": "Body_Location",
}


def fail(message: str) -> None:
    raise ValueError(message)


def require_once(text: str, marker: str, label: str) -> int:
    count = text.count(marker)
    if count != 1:
        fail(f"{label}: expected once, found {count}: {marker!r}")
    return text.index(marker)


def require_order(text: str, markers: list[str], label: str) -> None:
    cursor = 0
    for marker in markers:
        position = text.find(marker, cursor)
        if position < 0:
            fail(f"{label}: missing ordered marker: {marker!r}")
        cursor = position + len(marker)


def require_region(text: str, start: str, end: str, label: str) -> str:
    first = require_once(text, start, label)
    last = require_once(text, end, label)
    if first >= last:
        fail(f"{label}: invalid region boundary")
    return text[first:last]


def verify_reviewed_contract() -> None:
    registry = tomllib.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
    matches = [
        item
        for item in registry["operation"]
        if item["name"] == "CreateMultipartUpload"
    ]
    if len(matches) != 1:
        fail("CreateMultipartUpload registry entry is not unique")
    entry = matches[0]
    expected = {
        "tier": "core",
        "provider": "transfers",
        "family": "rest_xml_mutation",
        "public_provider": "Flyology.Object_Storage.Client.Transfers",
        "codec": "strict_bodyless_rest_xml_and_singleton_headers",
        "public_name": "Create_Multipart_Upload",
        "errors": [
            "authentication",
            "authorization",
            "not_found",
            "invalid_request",
            "unavailable_or_retryable",
            "corrupt_or_invalid_response",
        ],
        "coverage": {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        },
        "provenance": {
            "backend": "handwritten",
            "client": "handwritten",
            "server": "handwritten",
            "tests": "handwritten",
        },
        "implementation_mode": "handwritten",
        "generator_eligible": False,
        "human_decisions_resolved": True,
        "decision_status": "reviewed",
        "qualification": "create_multipart_upload",
        "exclusions": [
            "server compatibility is limited to authenticated path-style "
            "general-purpose bucket requests; directory-bucket, "
            "access-point, and Outposts routing are not claimed",
            "the qualified server profile supports durable content-type and "
            "checksum initiation policy while authenticated ACL, metadata, "
            "tagging, encryption, storage, payer, redirect, and Object Lock "
            "policies remain explicit typed capability exclusions",
            "lost initiation cannot be uniquely reconciled when concurrent "
            "requests for the same bucket and key are indistinguishable",
            "initiation cannot roll back an upload already created by the "
            "service",
        ],
        "evidence": {
            "backend": [
                "tests/src/object_storage_test_cases.adb",
                "sqlite/tests/src/flyology_object_storage_sqlite_tests.adb",
            ],
            "client": [
                "src/flyology-object_storage-client-low_level.ads",
                "src/flyology-object_storage-client-low_level.adb",
                "src/flyology-object_storage-client-transfers.ads",
                "src/flyology-object_storage-client-transfers.adb",
                "tests/src/"
                "flyology-object_storage-client-transfers-testing.adb",
                "tests/corpora/composable-client/"
                "create-multipart-certainty.tsv",
                "tests/corpora/create-multipart-upload/members.tsv",
                "tests/corpora/create-multipart-upload/vectors.tsv",
                "tools/verify-create-multipart-upload-preparation.py",
                "tools/verify-composable-client-fixtures.sh",
                "tools/test-composable-client-fixtures-verifier.sh",
                "tests/src/s3_http_socket_corpus.adb",
            ],
            "server": [
                "src/flyology-object_storage-server-s3_applications.adb",
                "tests/src/s3_server_application_corpus.adb",
                "tests/src/s3_http_socket_corpus.adb",
            ],
            "corpus": [
                "tests/src/"
                "flyology-object_storage-client-transfers-testing.adb",
                "tests/corpora/composable-client/"
                "create-multipart-certainty.tsv",
                "tests/corpora/create-multipart-upload/members.tsv",
                "tests/corpora/create-multipart-upload/vectors.tsv",
                "tools/verify-create-multipart-upload-preparation.py",
                "tools/verify-composable-client-fixtures.sh",
                "tools/test-composable-client-fixtures-verifier.sh",
                "tests/src/s3_http_socket_corpus.adb",
                "tests/src/s3_implementation_corpus.adb",
                "tests/src/s3_server_application_corpus.adb",
                "tests/scripts/test-minio.sh",
                "tests/scripts/test-rustfs.sh",
                "tests/scripts/test-seaweedfs.sh",
            ],
        },
        "ada_symbols": [
            "Prepare_Create_Multipart_Upload",
            "Decode_Create_Multipart_Complete_Response",
            "Execute_Create_Multipart_Upload",
            "Create_Multipart_Operation",
            "Create_Multipart_Upload",
            "Finish",
        ],
    }
    for key, value in expected.items():
        if entry[key] != value:
            fail(f"CreateMultipartUpload registry field changed: {key}")
    if entry["absence"] != (
        "no dedicated absence variant; exact NoSuchBucket is a structured "
        "typed rejection proving that this request did not create a "
        "multipart upload"
    ):
        fail("CreateMultipartUpload absence decision changed")
    if entry["certainty"] != (
        "only a complete validated 200 initiation result reports "
        "Multipart_Upload_Created; exact modeled non-creating rejections "
        "or definite non-admission report Definitely_Not_Created; "
        "pre-admission cancellation reports "
        "Creation_Cancelled_Before_Admission; possible or incomplete "
        "admission, retryable responses, malformed or oversized responses, "
        "and cancellation after admission report Creation_Outcome_Unknown; "
        "no automatic replay"
    ):
        fail("CreateMultipartUpload certainty decision changed")
    if entry["reconciliation"] != (
        "caller-selected ListMultipartUploads for the exact bucket and key "
        "before any retry; concurrent indistinguishable initiations require "
        "a caller-provided uniqueness invariant or remain unknown"
    ):
        fail("CreateMultipartUpload reconciliation decision changed")
    lane = registry["qualification"].get("create_multipart_upload")
    expected_lane = [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-create-multipart-upload-preparation.py",
        ],
        ["./tools/verify-composable-client-fixtures.sh"],
        ["./tools/test-composable-client-fixtures-verifier.sh"],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
        [
            "./tools/build-api-docs.sh",
            "/private/tmp/fos-create-multipart-upload-gnatdoc",
        ],
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    if lane != expected_lane:
        fail("CreateMultipartUpload qualification lane changed")

    low_spec = LOW_SPEC_PATH.read_text(encoding="utf-8")
    transfers_spec = TRANSFERS_SPEC_PATH.read_text(encoding="utf-8")
    transfers_body = TRANSFERS_BODY_PATH.read_text(encoding="utf-8")
    socket = SOCKET_PATH.read_text(encoding="utf-8")
    certainty = CERTAINTY_PATH.read_text(encoding="utf-8")
    qualification = QUALIFICATION_PATH.read_text(encoding="utf-8")

    low_region = require_region(
        low_spec,
        "type Create_Multipart_Parameters is record",
        "type Upload_Part_Parameters is record",
        "CreateMultipartUpload Low_Level declarations",
    )
    require_order(
        low_region,
        [
            "type Create_Multipart_Parameters is record",
            "function Prepare_Create_Multipart_Upload",
            "type Create_Multipart_Outcome_Kind is",
            "type Create_Multipart_Result is record",
            "type Create_Multipart_Outcome",
            "function Decode_Create_Multipart_Response",
            "function Decode_Create_Multipart_Complete_Response",
            "function Execute_Create_Multipart_Upload",
        ],
        "CreateMultipartUpload Low_Level declaration inventory",
    )
    public_region = require_region(
        transfers_spec,
        "type Multipart_Creation_Disposition is",
        "type Part_Upload_Disposition is",
        "CreateMultipartUpload public contract",
    )
    require_order(
        public_region,
        [
            "type Multipart_Creation_Disposition is",
            "type Create_Multipart_Result",
            "type Create_Multipart_Operation",
            "procedure Create_Multipart_Upload",
            "function Create_Multipart_Upload",
            "procedure Finish",
        ],
        "CreateMultipartUpload public contract",
    )
    provider_region = require_region(
        transfers_body,
        "function Normalize_Create_Multipart_Response",
        "function Normalize_Upload_Part_Response",
        "CreateMultipartUpload provider implementation",
    )
    for marker in [
        "Multipart_Upload_Created",
        "Definitely_Not_Created",
        "Creation_Outcome_Unknown",
        "Creation_Cancelled_Before_Admission",
        "Operations.Cancel (Item.Child);",
        '"CreateMultipartUpload restart changed a retained owner"',
        "Operations.Consume (Operation);",
    ]:
        if marker not in provider_region:
            fail(f"CreateMultipartUpload provider missing: {marker}")

    if len(certainty.splitlines()) != 46:
        fail("CreateMultipartUpload certainty fixture must contain 45 cases")
    for marker in [
        "Response_Complete\tResponse_Observed\t200",
        "Response_Complete\tResponse_Observed\t404\tNoSuchBucket",
        "Cancelled\tNot_Admitted",
        "Cancelled\tPossibly_Admitted",
        "Response_Sink_Failed\tResponse_Observed",
    ]:
        if marker not in certainty:
            fail(f"CreateMultipartUpload certainty fixture missing: {marker}")

    cancellation_inventory = (
        "type Cancellation_Exchange is\n"
        "     (List_Objects_V2_Cancellation,\n"
        "      Put_Object_Cancellation,\n"
        "      Delete_Object_Cancellation,\n"
        "      Complete_Multipart_Cancellation,\n"
        "      Abort_Multipart_Cancellation,\n"
        "      Copy_Object_Cancellation,\n"
        "      Create_Bucket_Cancellation,\n"
        "      Delete_Bucket_Cancellation,\n"
        "      Create_Multipart_Cancellation,\n"
        "      Get_Bucket_Location_Cancellation,\n"
        "      Get_Bucket_Versioning_Cancellation,\n"
        "      Put_Bucket_Versioning_Cancellation);"
    )
    drain_dispatch = (
        "                     when Create_Multipart_Cancellation =>\n"
        "                        if Cancellation_Round = 1 then\n"
        "                           Create_Multipart_Drain_Native.Request;\n"
        "                        else\n"
        "                           "
        "Create_Multipart_Drain_Lightweight.Request;\n"
        "                        end if;"
    )
    admission_dispatch = (
        "                  when Create_Multipart_Cancellation =>\n"
        "                     if Cancellation_Round = 1 then\n"
        "                        Create_Multipart_Admission_Native.Request;\n"
        "                     else\n"
        "                        "
        "Create_Multipart_Admission_Lightweight.Request;\n"
        "                     end if;"
    )
    peer_dispatch = (
        "                        when Create_Multipart_Cancellation =>\n"
        "                           raise Program_Error with\n"
        "                             \"CreateMultipartUpload cancel peer "
        "sent "
        "data \" &\n"
        "                             \"before drain\";"
    )
    cancellation_serve = (
        "         Serve\n"
        "           (\"\", \"POST\",\n"
        "            \"/example-bucket/create-multipart-cancel?uploads\",\n"
        "            Await_Cancellation => True,\n"
        "            Cancellation_Kind => Create_Multipart_Cancellation,\n"
        "            Cancellation_Round => Round);"
    )
    lost_serve = (
        "         Serve\n"
        "           (HTTP_Response (\"200 OK\", Pre_Create_List_XML), "
        "\"GET\",\n"
        "            \"/example-bucket?max-uploads=1000&"
        "prefix=create-lost&uploads\");\n"
        "         Serve\n"
        "           (\"\", \"POST\", \"/example-bucket/"
        "create-lost?uploads\",\n"
        "            Keep_Open => False);\n"
        "         Serve\n"
        "           (HTTP_Response (\"200 OK\", Lost_Create_List_XML), "
        "\"GET\",\n"
        "            \"/example-bucket?max-uploads=1000&"
        "prefix=create-lost&uploads\");"
    )
    round_dispatch = (
        "   Run_And_Report (1);\n"
        "   declare\n"
        "      task Lightweight_Client is\n"
        "         pragma Task_Info (Flyology.Lightweight_Task);\n"
        "      end Lightweight_Client;\n\n"
        "      task body Lightweight_Client is\n"
        "      begin\n"
        "         Run_And_Report (2);\n"
        "      end Lightweight_Client;"
    )

    def check_socket_contract(candidate: str) -> None:
        require_once(
            candidate,
            cancellation_inventory,
            "CreateMultipartUpload cancellation inventory",
        )
        for fragment, label in (
            (drain_dispatch, "drain dispatcher"),
            (admission_dispatch, "admission dispatcher"),
            (peer_dispatch, "peer-data dispatcher"),
            (cancellation_serve, "cancellation Serve"),
            (lost_serve, "lost-response Serve sequence"),
            (round_dispatch, "native/lightweight round dispatcher"),
        ):
            require_once(candidate, fragment, f"CreateMultipartUpload {label}")
        for token in [
            "Create_Multipart_Admission_Native",
            "Create_Multipart_Admission_Lightweight",
            "Create_Multipart_Drain_Native",
            "Create_Multipart_Drain_Lightweight",
        ]:
            if candidate.count(token) != 3:
                fail(
                    "CreateMultipartUpload readiness inventory changed: "
                    f"{token}"
                )

        server = require_region(
            candidate,
            cancellation_serve,
            '"POST", "/example-bucket/object%20key?uploads",',
            "CreateMultipartUpload server lifecycle",
        )
        require_order(
            server,
            [
                cancellation_serve,
                '"example-bucket", "create-multipart-cancel-restart"',
                '"create-multipart-restarted"',
                '"/example-bucket/create-multipart-cancel-restart?uploads"',
                lost_serve,
            ],
            "CreateMultipartUpload server lifecycle",
        )
        client = require_region(
            candidate,
            "Create_Multipart_Admission_Native.Wait_Source",
            "Parameters : Low_Level.Create_Multipart_Parameters;\n"
            "         begin\n"
            "            Parameters.Server_Side_Encryption",
            "CreateMultipartUpload client lifecycle",
        )
        require_order(
            client,
            [
                "Create_Multipart_Admission_Native.Wait_Source",
                "Create_Multipart_Drain_Native.Wait_Source",
                "Create_Multipart_Admission_Lightweight.Wait_Source",
                "Create_Multipart_Drain_Lightweight.Wait_Source",
                "Cancel_Set : aliased Operations.Completion_Set (5);",
                "Operations.Wait_Some (Cancel_Set, Completed_Batch);",
                "Flyology.IO.Finish (Admission_Ready);",
                "Operations.Cancel (Cancel_Operation);",
                "Operations.Wait_All (Cancel_Set);",
                "Finish (Cancel_Operation, Cancel_Result);",
                "Create_Multipart_Exchange_Failed",
                "Creation_Outcome_Unknown",
                "Client_API.Cancelled",
                "HTTP_Client.Cancelled",
                "HTTP_Client.Possibly_Admitted",
                "Operations.Is_Terminal (Drain_Ready)",
                "Flyology.IO.Finish (Drain_Ready);",
                '"create-multipart-cancel-restart"',
                "Operations.Wait_All (Cancel_Set);",
                "Finish (Cancel_Operation, Cancel_Result);",
                "Create_Multipart_Response_Available",
                "Multipart_Upload_Created",
                "No_Failure",
                "HTTP_Client.Response_Observed",
                "Low_Level.Created",
                "Cancel_Result.Response.Result.Bucket",
                '"example-bucket"',
                "Cancel_Result.Response.Result.Key",
                '"create-multipart-cancel-restart"',
                "Cancel_Result.Response.Result.Upload_ID",
                '"create-multipart-restarted"',
                "Before : constant Low_Level.List_Multipart_Uploads_Outcome",
                "Before.Kind /= Low_Level.Multipart_Uploads_Listed",
                "Before.Result.Listing.Uploads.Length) /= 0",
                "Result : constant Create_Multipart_Result",
                "Result.Kind /= Create_Multipart_Exchange_Failed",
                "Result.Disposition /= Creation_Outcome_Unknown",
                "Result.Admission /= HTTP_Client.Possibly_Admitted",
                "Listed : constant Low_Level.List_Multipart_Uploads_Outcome",
                "Listed.Result.Listing.Uploads.Length) /= 1",
                '"create-lost"',
                '"lost-create-id"',
            ],
            "CreateMultipartUpload client lifecycle",
        )
        require_once(
            candidate,
            "Transfers_Testing.Check_Create_Multipart_Certainty_Corpus;",
            "CreateMultipartUpload certainty corpus invocation",
        )

    check_socket_contract(socket)

    def reject_socket_contract(candidate: str, diagnostic: str) -> None:
        try:
            check_socket_contract(candidate)
        except ValueError:
            return
        fail(diagnostic)

    for candidate, diagnostic in (
        (
            socket.replace(drain_dispatch, "", 1),
            "deleted CreateMultipartUpload drain dispatcher was accepted",
        ),
        (
            socket.replace(
                admission_dispatch,
                admission_dispatch.replace(
                    "Create_Multipart_Admission_Native.Request;",
                    "Create_Multipart_Drain_Native.Request;",
                    1,
                ),
                1,
            ),
            "misrouted CreateMultipartUpload admission was accepted",
        ),
        (
            socket.replace(
                lost_serve,
                lost_serve.replace(
                    "Keep_Open => False",
                    "Keep_Open => True",
                    1,
                ),
                1,
            ),
            "replayed CreateMultipartUpload lost response was accepted",
        ),
        (
            socket.replace(
                "                    \"CreateMultipartUpload did not remain "
                "active through \" &\n"
                "                    \"admission\";\n"
                "               end if;\n"
                "               Flyology.IO.Finish (Admission_Ready);",
                "                    \"CreateMultipartUpload did not remain "
                "active through \" &\n"
                "                    \"admission\";\n"
                "               end if;",
                1,
            ),
            "unfinished CreateMultipartUpload admission was accepted",
        ),
        (
            socket.replace(
                "               if not Operations.Is_Terminal (Drain_Ready) "
                "then\n"
                "                  raise Program_Error with\n"
                "                    \"CreateMultipartUpload drain was not "
                "acknowledged\";",
                "               if Operations.Is_Active (Drain_Ready) then\n"
                "                  raise Program_Error with\n"
                "                    \"CreateMultipartUpload drain was not "
                "acknowledged\";",
                1,
            ),
            "nonterminal CreateMultipartUpload drain was accepted",
        ),
        (
            socket.replace(lost_serve, "", 1),
            "deleted CreateMultipartUpload reconciliation sequence accepted",
        ),
        (
            socket.replace("   Run_And_Report (1);\n", "", 1),
            "missing CreateMultipartUpload native round was accepted",
        ),
        (
            socket.replace(
                round_dispatch,
                round_dispatch + "\n" + round_dispatch,
                1,
            ),
            "duplicate CreateMultipartUpload round dispatcher was accepted",
        ),
    ):
        reject_socket_contract(candidate, diagnostic)
    for marker in [
        "lost response is ambiguous",
        "ListMultipartUploads",
        "never auto-retries",
        "admission/cancel",
        "same-operation restart",
    ]:
        if marker not in qualification:
            fail(
                "CreateMultipartUpload qualification prose missing: "
                f"{marker}"
            )


def read_tsv(path: Path, expected_header: list[str]) -> list[dict[str, str]]:
    raw = path.read_bytes()
    if b"\r" in raw:
        fail(f"{path}: CR characters are not canonical")
    with path.open("r", encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        if reader.fieldnames != expected_header:
            fail(f"{path}: header mismatch: {reader.fieldnames!r}")
        rows = list(reader)
    if not rows:
        fail(f"{path}: no rows")
    for number, row in enumerate(rows, start=2):
        if None in row or any(value == "" for value in row.values()):
            fail(f"{path}:{number}: empty or surplus field")
    return rows


def generated_block(model: str, function: str, shape: str) -> str:
    marker = f"   function {function}\n"
    try:
        function_body = model.split(marker, 1)[1].split(
            f"end {function};", 1
        )[0]
    except IndexError as exc:
        raise ValueError(f"generated model has no {function} body") from exc
    match = re.search(
        rf"when {re.escape(shape)} =>\s+case Member is"
        rf"(?P<body>.*?)\s+end case;",
        function_body,
        flags=re.DOTALL,
    )
    if match is None:
        fail(f"generated model has no {function} block for shape {shape}")
    return match.group("body")


def generated_members(model: str, shape: str) -> list[str]:
    pairs = re.findall(
        r'when\s+(\d+)\s+=>\s+return\s+"([^"]+)";',
        generated_block(model, "Member_Name", shape),
    )
    ordinals = [int(ordinal) for ordinal, _ in pairs]
    if ordinals != list(range(1, len(pairs) + 1)):
        fail(f"generated model shape {shape} member order is not contiguous")
    return [name for _, name in pairs]


def generated_locations(model: str, shape: str) -> list[str]:
    pairs = re.findall(
        r"when\s+(\d+)\s+=>\s+return\s+([A-Za-z_]+);",
        generated_block(model, "Location", shape),
    )
    ordinals = [int(ordinal) for ordinal, _ in pairs]
    if ordinals != list(range(1, len(pairs) + 1)):
        fail(f"generated model shape {shape} location order is not contiguous")
    return [location for _, location in pairs]


def generated_count(model: str, shape: str) -> int:
    try:
        body = model.split("function Member_Count", 1)[1].split(
            "end Member_Count;", 1
        )[0]
    except IndexError as exc:
        raise ValueError("generated model has no Member_Count body") from exc
    match = re.search(
        rf"when\s+{re.escape(shape)}\s+=>\s+return\s+(\d+);", body
    )
    if match is None:
        fail(f"generated model has no count for shape {shape}")
    return int(match.group(1))


def split_csv(value: str) -> list[str]:
    values = value.split(",")
    if any(item == "" or item != item.strip() for item in values):
        fail(f"noncanonical comma list: {value!r}")
    if len(values) != len(set(values)):
        fail(f"duplicate item in comma list: {value!r}")
    return values


def main() -> int:
    lock = LOCK_PATH.read_text(encoding="utf-8")
    if f'revision = "{EXPECTED_REVISION}"' not in lock:
        fail("pinned botocore revision changed")
    if f'service_model_sha256 = "{EXPECTED_SHA256}"' not in lock:
        fail("pinned botocore service hash changed")

    model = MODEL_PATH.read_text(encoding="utf-8")
    members = read_tsv(MEMBERS_PATH, MEMBER_HEADER)
    vectors = read_tsv(VECTORS_PATH, VECTOR_HEADER)

    vector_by_id: dict[str, dict[str, str]] = {}
    for row in vectors:
        vector_id = row["id"]
        if vector_id in vector_by_id:
            fail(f"duplicate vector id: {vector_id}")
        if not re.fullmatch(r"CM-(?:RQ|RS|LC|OR)-\d{3}", vector_id):
            fail(f"noncanonical vector id: {vector_id}")
        if row["direction"] not in ALLOWED_VECTOR_DIRECTIONS:
            fail(f"invalid vector direction: {vector_id}")
        vector_by_id[vector_id] = row

    member_keys: set[str] = set()
    grouped: dict[tuple[str, str], list[dict[str, str]]] = {}
    for row in members:
        key = (row["direction"], row["shape"])
        grouped.setdefault(key, []).append(row)
        member_key = f'{row["direction"]}:{row["member"]}'
        if member_key in member_keys:
            fail(f"duplicate manifest member: {member_key}")
        member_keys.add(member_key)
        if row["current_boundary"] not in ALLOWED_BOUNDARIES:
            fail(f"invalid current boundary for {member_key}")

    if set(grouped) != set(EXPECTED):
        fail(f"unexpected direction/shape groups: {sorted(grouped)}")

    for key, expected_names in EXPECTED.items():
        rows = grouped[key]
        ordinals = [int(row["ordinal"]) for row in rows]
        names = [row["member"] for row in rows]
        if ordinals != list(range(1, len(expected_names) + 1)):
            fail(f"{key}: manifest ordinals are not contiguous")
        if names != expected_names:
            fail(f"{key}: manifest names do not match the pinned inventory")
        if generated_members(model, key[1]) != expected_names:
            fail(f"{key}: generated Ada model differs from expected inventory")
        if generated_count(model, key[1]) != len(expected_names):
            fail(f"{key}: generated Ada member count differs")
        expected_locations = generated_locations(model, key[1])
        manifest_locations = []
        for row in rows:
            try:
                manifest_locations.append(
                    MANIFEST_TO_MODEL_LOCATION[row["wire_location"]]
                )
            except KeyError as exc:
                raise ValueError(
                    f'{key}: unknown wire location {row["wire_location"]!r}'
                ) from exc
        if manifest_locations != expected_locations:
            fail(f"{key}: manifest locations differ from generated Ada model")

    referenced_vectors: set[str] = set()
    for row in members:
        member_key = f'{row["direction"]}:{row["member"]}'
        for vector_id in split_csv(row["vector_ids"]):
            vector = vector_by_id.get(vector_id)
            if vector is None:
                fail(f"{member_key}: unknown vector {vector_id}")
            refs = set(split_csv(vector["member_refs"]))
            if member_key not in refs:
                fail(
                    f"{member_key}: vector {vector_id} lacks reciprocal "
                    "reference"
                )
            referenced_vectors.add(vector_id)

    for vector_id, vector in vector_by_id.items():
        refs = split_csv(vector["member_refs"])
        for ref in refs:
            if ref.startswith("operation:"):
                if ref != "operation:CreateMultipartUpload":
                    fail(f"{vector_id}: unexpected operation reference {ref}")
            elif ref not in member_keys:
                fail(f"{vector_id}: unknown member reference {ref}")
        if vector_id not in referenced_vectors and not any(
            ref == "operation:CreateMultipartUpload" for ref in refs
        ):
            fail(f"{vector_id}: vector is not reachable from the manifest")

    verify_reviewed_contract()

    request_count = len(grouped[("request", "135")])
    response_count = len(grouped[("response", "134")])
    print(
        "CreateMultipartUpload preparation: "
        f"{request_count} request members, {response_count} response members, "
        f"{len(vectors)} contract vectors; pinned model and references match"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, UnicodeError, ValueError) as exc:
        print(
            f"CreateMultipartUpload preparation verification failed: {exc}",
            file=sys.stderr,
        )
        raise SystemExit(1)
