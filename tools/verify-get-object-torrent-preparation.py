#!/usr/bin/env python3
"""Verify the pinned GetObjectTorrent model inventory and corpus graph."""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "tests" / "corpora" / "get-object-torrent"
MODEL = ROOT / "src" / "flyology-object_storage-s3-model.adb"
LOW_SPEC = ROOT / "src" / "flyology-object_storage-client-low_level.ads"
LOW_BODY = ROOT / "src" / "flyology-object_storage-client-low_level.adb"
OBJECTS_SPEC = ROOT / "src" / "flyology-object_storage-client-objects.ads"
OBJECTS_BODY = ROOT / "src" / "flyology-object_storage-client-objects.adb"
SOCKET_CORPUS = ROOT / "tests" / "src" / \
    "s3_get_object_torrent_socket_corpus.adb"
SERVER_SPEC = ROOT / "src" / \
    "flyology-object_storage-server-s3_applications.ads"
SERVER_BODY = ROOT / "src" / \
    "flyology-object_storage-server-s3_applications.adb"
SERVER_RUNTIME = ROOT / "server" / "src" / \
    "flyology_object_storage_server_runtime.adb"
SERVER_CORPUS = ROOT / "tests" / "src" / \
    "s3_server_application_corpus.adb"
QUALIFICATION = ROOT / "docs" / "qualification" / \
    "get-object-torrent.md"
LOCK = ROOT / "coverage" / "corpora.lock.toml"

# These values identify the reviewed upstream model. A change is a model
# upgrade and requires regenerating and reviewing the complete inventory.
EXPECTED_REVISION = "36c34f15391da01cd717c73c0fffa747c9889768"
EXPECTED_SHA256 = (
    "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
)
EXPECTED_MEMBERS = [
    ("request", 289, 1, "Bucket", 60, "uri-label", "true", "projected"),
    ("request", 289, 2, "Key", 471, "uri-label", "true", "projected"),
    ("request", 289, 3, "RequestPayer", 599, "header", "false",
     "projected"),
    ("request", 289, 4, "ExpectedBucketOwner", 15, "header", "false",
     "projected"),
    ("output", 288, 1, "Body", 46, "body", "false", "streamed"),
    ("output", 288, 2, "RequestCharged", 598, "header", "false", "projected"),
]
MEMBER_HEADER = [
    "direction", "shape", "ordinal", "member", "member_shape",
    "wire_location", "required", "current_boundary", "required_contract",
    "vector_ids",
]
VECTOR_HEADER = [
    "id", "direction", "layer", "category", "member_refs", "stimulus",
    "expected_contract",
]
LOCATION = {
    "URI_Location": "uri-label",
    "Header_Location": "header",
    "Body_Location": "body",
}


def fail(message: str) -> None:
    raise ValueError(message)


def read_tsv(path: Path, header: list[str]) -> list[dict[str, str]]:
    if b"\r" in path.read_bytes():
        fail(f"{path}: CR characters are not canonical")
    with path.open("r", encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        if reader.fieldnames != header:
            fail(f"{path}: header mismatch")
        rows = list(reader)
    if not rows:
        fail(f"{path}: no rows")
    for number, row in enumerate(rows, 2):
        if None in row or any(value == "" for value in row.values()):
            fail(f"{path}:{number}: empty or surplus field")
    return rows


def function_body(model: str, function: str) -> str:
    match = re.search(rf"   function {re.escape(function)}(?=\s*\()", model)
    if match is None:
        fail(f"generated model has no {function}")
    tail = model[match.end():]
    marker = f"end {function};"
    if marker not in tail:
        fail(f"generated model has no end for {function}")
    return tail.split(marker, 1)[0]


def operation_scalar(model: str, function: str) -> str:
    match = re.search(
        r"when Get_Object_Torrent_Operation =>\s+return\s+([^;]+);",
        function_body(model, function),
    )
    if match is None:
        fail(f"generated model lacks GetObjectTorrent {function}")
    return match.group(1).strip().strip('"')


def shape_block(model: str, function: str, shape: int) -> str:
    match = re.search(
        rf"when {shape} =>\s+case Member is(?P<body>.*?)\s+end case;",
        function_body(model, function),
        re.DOTALL,
    )
    if match is None:
        fail(f"generated model lacks {function} block for shape {shape}")
    return match.group("body")


def member_values(model: str, function: str, shape: int) -> list[str]:
    if function == "Member_Name":
        value = r'"([^"]*)"'
    else:
        value = r"([A-Za-z_][A-Za-z0-9_]*|\d+)"
    pairs = re.findall(
        rf"when\s+(\d+)\s+=>\s+return\s+{value};",
        shape_block(model, function, shape),
    )
    ordinals = [int(number) for number, _ in pairs]
    if ordinals != list(range(1, len(pairs) + 1)):
        fail(f"shape {shape} {function} order is not contiguous")
    return [item for _, item in pairs]


def member_count(model: str, shape: int) -> int:
    match = re.search(
        rf"when\s+{shape}\s+=>\s+return\s+(\d+);",
        function_body(model, "Member_Count"),
    )
    if match is None:
        fail(f"generated model lacks member count for shape {shape}")
    return int(match.group(1))


def enumeration_values(model: str, shape: int) -> list[str]:
    count_match = re.search(
        rf"when\s+{shape}\s+=>\s+return\s+(\d+);",
        function_body(model, "Enumeration_Count"),
    )
    if count_match is None:
        fail(f"generated model lacks enumeration count for shape {shape}")
    block_match = re.search(
        rf"when {shape} =>\s+case Index is(?P<body>.*?)\s+end case;",
        function_body(model, "Enumeration_Value"),
        re.DOTALL,
    )
    if block_match is None:
        fail(f"generated model lacks enumeration values for shape {shape}")
    pairs = re.findall(
        r'when\s+(\d+)\s+=>\s+return\s+"([^"]*)";',
        block_match.group("body"),
    )
    values = [value for _, value in pairs]
    if len(values) != int(count_match.group(1)):
        fail(f"generated enumeration cardinality changed for shape {shape}")
    return values


def comma_values(value: str) -> list[str]:
    values = value.split(",")
    if any(item == "" or item != item.strip() for item in values):
        fail(f"noncanonical comma list: {value!r}")
    if len(values) != len(set(values)):
        fail(f"duplicate comma-list value: {value!r}")
    return values


def unique_region(source: str, start: str, end: str, label: str) -> str:
    if source.count(start) != 1:
        fail(f"{label}: start delimiter is not unique")
    first = source.index(start)
    last = source.find(end, first + len(start))
    if last < 0:
        fail(f"{label}: end delimiter is missing")
    return source[first:last]


def require_in_order(region: str, fragments: list[str], label: str) -> None:
    cursor = 0
    for fragment in fragments:
        found = region.find(fragment, cursor)
        if found < 0:
            fail(f"{label}: missing or reordered {fragment!r}")
        cursor = found + len(fragment)


def require_once(region: str, fragment: str, label: str) -> None:
    if region.count(fragment) != 1:
        fail(f"{label}: expected one {fragment!r}")


def main() -> int:
    lock = LOCK.read_text(encoding="utf-8")
    if f'revision = "{EXPECTED_REVISION}"' not in lock:
        fail("pinned botocore revision changed")
    if f'service_model_sha256 = "{EXPECTED_SHA256}"' not in lock:
        fail("pinned botocore service hash changed")

    model = MODEL.read_text(encoding="utf-8")
    if operation_scalar(model, "Request_URI") != "/{Bucket}/{Key+}?torrent":
        fail("generated request URI changed")
    if operation_scalar(model, "Response_Code") != "200":
        fail("generated success status changed")
    if operation_scalar(model, "Input_Shape") != "289" or \
            operation_scalar(model, "Output_Shape") != "288":
        fail("generated operation shapes changed")
    if operation_scalar(model, "Method") != "Get_Method":
        fail("generated HTTP method changed")
    if member_count(model, 289) != 4 or member_count(model, 288) != 2:
        fail("generated member counts changed")

    generated: list[tuple[str, int, int, str, int, str, str, str]] = []
    for direction, shape in (("request", 289), ("output", 288)):
        names = member_values(model, "Member_Name", shape)
        shapes = member_values(model, "Member_Shape", shape)
        locations = member_values(model, "Location", shape)
        required = member_values(model, "Member_Required", shape)
        streaming = member_values(model, "Member_Streaming", shape)
        for index, name in enumerate(names):
            boundary = (
                "streamed" if streaming[index] == "True" else "projected"
            )
            generated.append(
                (direction, shape, index + 1, name, int(shapes[index]),
                 LOCATION[locations[index]], required[index].lower(), boundary)
            )
    if generated != EXPECTED_MEMBERS:
        fail(f"generated operation inventory changed: {generated!r}")
    if operation_scalar(model, "Request_Checksum_Required") != "False":
        fail("generated request checksum requirement changed")
    if enumeration_values(model, 598) != ["requester"] or \
            enumeration_values(model, 599) != ["requester"]:
        fail("generated payer or charged enumeration changed")
    if re.search(r"when 288 =>\s+return \"Body\";",
                 function_body(model, "Payload_Member")) is None:
        fail("generated streaming payload member changed")

    members = read_tsv(CORPUS / "members.tsv", MEMBER_HEADER)
    manifest = [
        (row["direction"], int(row["shape"]), int(row["ordinal"]),
         row["member"], int(row["member_shape"]), row["wire_location"],
         row["required"], row["current_boundary"])
        for row in members
    ]
    if manifest != EXPECTED_MEMBERS:
        fail("manifest does not match the generated inventory")

    vectors = read_tsv(CORPUS / "vectors.tsv", VECTOR_HEADER)
    vector_by_id: dict[str, dict[str, str]] = {}
    for vector in vectors:
        vector_id = vector["id"]
        if not re.fullmatch(r"GOT-(?:RQ|RS|TR)-\d{3}", vector_id):
            fail(f"noncanonical vector id: {vector_id}")
        if vector_id in vector_by_id:
            fail(f"duplicate vector id: {vector_id}")
        vector_by_id[vector_id] = vector

    member_keys = {f'{row["direction"]}:{row["member"]}' for row in members}
    referenced: set[str] = set()
    for member in members:
        key = f'{member["direction"]}:{member["member"]}'
        for vector_id in comma_values(member["vector_ids"]):
            vector = vector_by_id.get(vector_id)
            if vector is None:
                fail(f"{key}: unknown vector {vector_id}")
            if key not in comma_values(vector["member_refs"]):
                fail(f"{key}: {vector_id} lacks reciprocal reference")
            referenced.add(vector_id)
    for vector_id, vector in vector_by_id.items():
        refs = comma_values(vector["member_refs"])
        for reference in refs:
            if reference != "operation:GetObjectTorrent" and \
                    reference not in member_keys:
                fail(f"{vector_id}: unknown member reference {reference}")
        if vector_id not in referenced and \
                "operation:GetObjectTorrent" not in refs:
            fail(f"{vector_id}: unreachable vector")

    if len(vectors) != 21:
        fail(f"expected 21 reciprocal vectors, found {len(vectors)}")

    spec = LOW_SPEC.read_text(encoding="utf-8")
    body = LOW_BODY.read_text(encoding="utf-8")
    for token in (
        "type Get_Object_Torrent_Parameters is record",
        "type Get_Object_Torrent_Outcome",
    ):
        if token not in spec:
            fail(f"typed client surface lacks {token}")
    for token in (
        "function Prepare_Get_Object_Torrent",
        "function Execute_Get_Object_Torrent",
        "procedure Get_Object_Torrent",
        "function Decode_Get_Object_Torrent_Complete_Response",
        "function Decode_Get_Object_Torrent_Response_Head",
    ):
        if token not in spec or token not in body:
            fail(f"typed client surface lacks {token}")

    objects_spec = OBJECTS_SPEC.read_text(encoding="utf-8")
    objects_body = OBJECTS_BODY.read_text(encoding="utf-8")
    for token in (
        "type Get_Object_Torrent_Operation",
        "type Get_Object_Torrent_Result_Kind",
        "type Get_Object_Torrent_Result",
        "function Get_Torrent",
        "procedure Get_Torrent",
        "procedure Finish",
    ):
        if token not in objects_spec:
            fail(f"provider composable surface lacks {token}")
    for token in (
        "Get_Object_Torrent_Response_Available",
        "Get_Object_Torrent_Exchange_Failed",
        "function Get_Torrent",
        "procedure Get_Torrent",
        "procedure Finish",
    ):
        if token not in objects_body:
            fail(f"provider lifecycle implementation lacks {token}")
    visible_operation = re.findall(
        r"   type Get_Object_Torrent_Operation\s*"
        r"\(Set : not null access "
        r"Flyology\.Operations\.Completion_Set'Class;\s*"
        r"HTTP : not null access Flyology\.HTTP\.Client\.Client;\s*"
        r"Destination : not null access Flyology\.Buffers\.Unique_Buffer;\s*"
        r"Cancellation : access Flyology\.Cancellation\.Token\) is\s*"
        r"new Flyology\.Operations\.Operation and\s*"
        r"Flyology\.HTTP\.Client\.Response_Body_Sink with private;",
        objects_spec,
        re.DOTALL,
    )
    private_operation = re.findall(
        r"   --  @exclude\s*"
        r"type Get_Object_Torrent_Operation\s*"
        r"\(Set : not null access "
        r"Flyology\.Operations\.Completion_Set'Class;\s*"
        r"HTTP : not null access Flyology\.HTTP\.Client\.Client;\s*"
        r"Destination : not null access Flyology\.Buffers\.Unique_Buffer;\s*"
        r"Cancellation : access Flyology\.Cancellation\.Token\) is\s*"
        r"new Flyology\.Operations\.Operation \(Set\) and\s*"
        r"Flyology\.HTTP\.Client\.Response_Body_Sink\s*with record",
        objects_spec,
        re.DOTALL,
    )
    if len(visible_operation) != 1 or len(private_operation) != 1:
        fail("provider operation type geometry changed")
    provider_signatures = re.findall(
        r"(?:function|procedure) Get_Torrent\s*\((.*?)\)\s*"
        r"(?:return\s+[^;]+)?(?:;|with)",
        objects_spec,
        re.DOTALL,
    )
    if len(provider_signatures) != 3:
        fail("provider must expose exactly three Get_Torrent overloads")
    for signature in provider_signatures:
        positions = [
            signature.find("Parameters"),
            signature.find("Destination"),
            signature.find("Identity"),
        ]
        if positions != sorted(positions) or \
                any(item < 0 for item in positions):
            fail("provider Get_Torrent parameter order changed")
    for token in (
        "Operation.HTTP /= Client",
        "Operation.Destination /= Destination",
        "Operation.Cancellation /= Token",
        "Response_Body_Too_Large",
        "Response_Too_Large",
        "Low_Level.Get_Object_Torrent",
        "Operations.Wait_All",
        "Finish (Operation, Result)",
    ):
        if token not in objects_body:
            fail(f"provider lifecycle implementation lacks {token}")

    socket_corpus = SOCKET_CORPUS.read_text(encoding="utf-8")
    if "Scenarios_Per_Client : constant Positive := 20;" not in socket_corpus:
        fail("socket lifecycle corpus scenario cardinality changed")
    for token in (
        "limited-root binary success",
        "typed rejection restored a nonempty buffer",
        "known capacity failure mismatch",
        "operation-last restart mismatch",
        "admitted cancellation did not drain",
        "Completion_Set (5)",
        "Operations.Wait_Some",
        "GetObjectTorrent transport drain was not acknowledged",
        "synchronous/composable equivalence mismatch",
        "retained HTTP owner was replaceable",
        "retained destination owner was replaceable",
        "retained cancellation owner was replaceable",
        "buffer exact-operation pre-admission rejection failed",
        "sink exact-operation pre-admission rejection failed",
        "Result.Admission /= HTTP_Client.Possibly_Admitted",
    ):
        if token not in socket_corpus:
            fail(f"socket lifecycle corpus lacks {token}")

    server_spec = SERVER_SPEC.read_text(encoding="utf-8")
    server_body = SERVER_BODY.read_text(encoding="utf-8")
    server_runtime = SERVER_RUNTIME.read_text(encoding="utf-8")
    server_corpus = SERVER_CORPUS.read_text(encoding="utf-8")
    qualification = QUALIFICATION.read_text(encoding="utf-8")
    generic_region = unique_region(
        server_spec,
        "--  @formal Backend_Type Concrete pluggable backend type",
        "package Flyology.Object_Storage.Server.S3_Applications is",
        "server generic contract",
    )
    require_in_order(
        generic_region,
        [
            "--  @formal Clock Trusted wall-clock source\n"
            "--  @formal Torrent_Piece_Length Caller-selected "
            "GetObjectTorrent piece size\n"
            "--  @formal Metadata_Provider",
            "generic",
            "Torrent_Piece_Length : Positive;",
        ],
        "server generic contract",
    )
    require_once(
        generic_region,
        "Torrent_Piece_Length : Positive;",
        "server generic contract",
    )
    if re.search(
        r"Torrent_Piece_Length\s*:\s*Positive\s*:=", generic_region
    ):
        fail("server torrent piece length acquired a default")
    require_in_order(
        server_runtime,
        [
            "Server_Torrent_Piece_Length : constant Positive :=",
            "256 * 1_024;",
            "Torrent_Piece_Length     => Server_Torrent_Piece_Length",
        ],
        "server torrent deployment policy",
    )
    query_region = unique_region(
        server_body,
        "Is_Get_Object_Torrent_Query : constant Boolean :=",
        "Is_Get_Bucket_Location_Query : constant Boolean :=",
        "server torrent query",
    )
    require_in_order(
        query_region,
        [
            'Query_Text = "torrent"',
            'Query_Text = "torrent="',
            'Query_Text = "torrent=&x-id=GetObjectTorrent"',
            'Query_Text = "x-id=GetObjectTorrent&torrent="',
        ],
        "server torrent query",
    )
    io_region = unique_region(
        server_body,
        "--  The pinned GetObjectTorrent contract permits objects strictly",
        "package Annotation_Response_IO is",
        "server torrent sink",
    )
    require_in_order(
        io_region,
        [
            "Maximum_Torrent_Object_Size : constant Byte_Count :=",
            "5 * 1_024 * 1_024 * 1_024 - 1;",
            "type Response_Sink is limited new Backends.Byte_Sink",
            "Checksums.Context (S3.Core.SHA1)",
            "procedure Check_Context",
            "Piece_Count : constant Byte_Count :=",
            "Content_Length > Maximum_Torrent_Object_Size",
            "raise Object_Too_Large;",
            "torrent digest length overflow",
            '"d4:infod6:lengthi"',
            '"e4:name"',
            '"12:piece lengthi"',
            '"e6:pieces"',
            '"application/x-bittorrent"',
            "Check_Context (Token, Deadline);",
            "Checksums.Update",
            "Emit_Digest (Item);",
            "backend produced an invalid torrent digest count",
            'Emit (Item, "ee");',
            "torrent response length does not match its framing",
        ],
        "server torrent sink",
    )
    for fragment in (
        "Checksums.Finish (Item.Piece_Hash)",
        "elsif Piece_Count > Byte_Count'Last / 20 then",
        "if Digest_Length > Byte_Count'Last - Framing_Length then",
    ):
        require_once(io_region, fragment, "server torrent sink")
    handler_region = unique_region(
        server_body,
        "when Get_Object_Torrent =>",
        "when Get_Object =>",
        "server torrent handler",
    )
    require_in_order(
        handler_region,
        [
            'Apps.Request_Header_Count (X, "x-amz-request-payer")',
            "and then Apps.Request_Header",
            '(X, "x-amz-request-payer") /= "requester"',
            "Check_Expected_Bucket_Owner",
            "Sink.Name := US.To_Unbounded_String (Key);",
            "Store.Get_Object",
            "Backends.Current_Version_Selector",
            "Torrent_Response_IO.Finish (Sink);",
            "Apps.End_Stream (X);",
            "elsif not Apps.Wire_Response_Started (X) then",
            "Apps.Mark_Failed (X);",
            "when Torrent_Response_IO.Object_Too_Large =>",
            '"GetObjectTorrent requires an object smaller than "',
        ],
        "server torrent handler",
    )
    cancellation_region = unique_region(
        server_corpus,
        "procedure Check_Get_Object_Torrent_Cancellation is",
        "end Check_Get_Object_Torrent_Cancellation;",
        "server torrent cancellation",
    )
    require_in_order(
        cancellation_region,
        [
            "Stop.Request;",
            "GetObjectTorrent cancellation did not propagate",
            "Admitted_Wire.Cancel_On_Send := True;",
            "Admitted_Wire.Cancellation_Requested",
            "GetObjectTorrent admitted cancellation did not drain",
        ],
        "server torrent cancellation",
    )
    evidence_region = unique_region(
        server_corpus,
        '"d4:infod6:lengthi11e4:name6:object',
        "Check_Get_Object_Torrent_Cancellation;",
        "server torrent evidence",
    )
    require_in_order(
        evidence_region,
        [
            "GetObjectTorrent metainfo mismatch",
            "GetObjectTorrent requester-payer route mismatch",
            "GetObjectTorrent full decoded key name mismatch",
            "Boundary_Body : constant String (1 .. 16 * 1_024 + 1)",
            "GetObjectTorrent callback-boundary metainfo mismatch",
            "GetObjectTorrent empty-object metainfo mismatch",
        ],
        "server torrent evidence",
    )
    for token in (
        "GetObjectTorrent metainfo mismatch",
        "GetObjectTorrent requester-payer route mismatch",
        "GetObjectTorrent callback-boundary metainfo mismatch",
        "GetObjectTorrent empty-object metainfo mismatch",
        "GetObjectTorrent missing object mismatch",
        "GetObjectTorrent accepted malformed query state",
        "GetObjectTorrent ignored the expected owner",
        "GetObjectTorrent cancellation did not propagate",
        "GetObjectTorrent admitted cancellation did not drain",
        "GetObjectTorrent full decoded key name mismatch",
    ):
        require_once(server_corpus, token, "server torrent corpus")
    qualification_collapsed = re.sub(r"\s+", " ", qualification)
    require_in_order(
        qualification_collapsed,
        [
            "backend cell is shared-family evidence",
            "complete decoded object-key string accepted by authenticated",
            "without an additional naming normalization",
            "broader request-target claim",
            "production executable explicitly selects 256 KiB",
            "backend-fragment-boundary",
            "response-start cancellation",
        ],
        "GetObjectTorrent qualification policy",
    )

    print(
        "GetObjectTorrent preparation: 4 request members, 2 output members, "
        f"{len(vectors)} reciprocal contract vectors; pinned model matches"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, UnicodeError, ValueError) as exc:
        print(
            f"GetObjectTorrent preparation verification failed: {exc}",
            file=sys.stderr,
        )
        raise SystemExit(1)
