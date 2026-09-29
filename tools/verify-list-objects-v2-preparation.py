#!/usr/bin/env python3
"""Fail-closed static evidence for reviewed ListObjectsV2 qualification."""

from __future__ import annotations

import hashlib
import re
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "coverage" / "s3-operations.toml"
LOW_SPEC = ROOT / "src" / "flyology-object_storage-client-low_level.ads"
LOW_BODY = ROOT / "src" / "flyology-object_storage-client-low_level.adb"
OBJECTS_SPEC = ROOT / "src" / "flyology-object_storage-client-objects.ads"
OBJECTS_BODY = ROOT / "src" / "flyology-object_storage-client-objects.adb"
SOCKET = ROOT / "tests" / "src" / "s3_http_socket_corpus.adb"
BACKEND = ROOT / "tests" / "src" / "object_storage_test_cases.adb"
SERVER = ROOT / "tests" / "src" / "s3_server_application_corpus.adb"
IMPLEMENTATION = ROOT / "tests" / "src" / "s3_implementation_corpus.adb"

EXPECTED_ERRORS = [
    "authentication",
    "authorization",
    "not_found",
    "invalid_request",
    "unavailable_or_retryable",
    "corrupt_or_invalid_response",
]
EXPECTED_SYMBOLS = [
    "Prepare_List_Objects_V2",
    "Decode_List_Objects_V2_Complete_Response",
    "Execute_List_Objects_V2",
    "List_Objects_V2_Operation",
    "List_Page",
    "Finish",
]
EXPECTED_ABSENCE = (
    "no dedicated absence variant; a well-formed bounded 404 NoSuchBucket "
    "response is a structured typed rejection"
)
EXPECTED_COVERAGE = {
    "backend": "covered",
    "client": "covered",
    "server": "covered",
    "corpus": "covered",
}
EXPECTED_PROVENANCE = {
    "backend": "handwritten",
    "client": "handwritten",
    "server": "handwritten",
    "tests": "handwritten",
}
EXPECTED_EVIDENCE = {
    "backend": ["tests/src/object_storage_test_cases.adb"],
    "client": [
        "src/flyology-object_storage-client-low_level.adb",
        "src/flyology-object_storage-client-objects.adb",
        "tests/src/s3_http_socket_corpus.adb",
    ],
    "server": [
        "tests/src/s3_server_application_corpus.adb",
        "tests/src/s3_http_socket_corpus.adb",
    ],
    "corpus": [
        "tests/src/s3_http_socket_corpus.adb",
        "tests/src/s3_implementation_corpus.adb",
        "tests/src/s3_server_application_corpus.adb",
    ],
}
EXPECTED_ENTRY = {
    "name": "ListObjectsV2",
    "tier": "core",
    "provider": "objects",
    "family": "paginated_rest_xml_read",
    "public_provider": "Flyology.Object_Storage.Client.Objects",
    "codec": "paginated_rest_xml_and_singleton_headers",
    "public_name": "List_Page",
    "absence": EXPECTED_ABSENCE,
    "errors": EXPECTED_ERRORS,
    "certainty": "read_only",
    "reconciliation": "not_applicable",
    "exclusions": [],
    "coverage": EXPECTED_COVERAGE,
    "provenance": EXPECTED_PROVENANCE,
    "implementation_mode": "handwritten",
    "generator_eligible": False,
    "human_decisions_resolved": True,
    "evidence": EXPECTED_EVIDENCE,
    "decision_status": "reviewed",
    "qualification": "list_objects_v2",
    "ada_symbols": EXPECTED_SYMBOLS,
}

#  Exact reviewed source-region identities. These bind predicates and fixtures,
#  not only their diagnostics; changing one requires renewed evidence review.
REGION_DIGESTS = {
    "low-level public contract":
        "c3ad700c32cee6041d28a793b15339d1a50b2d861bb830863e2a6d1388867e4a",
    "low-level implementation":
        "4c9a15d8e70053eaaddb77355f65d87ea05810e467b4c8aad4c59b5657af759b",
    "public composable contract":
        "c752e92b69417692a2afb368221ed01e048993069251ef7c7aca7ca08639b7f7",
    "public synchronous contract":
        "bc5254afcea6e8175d0444d941703729fabe5236b1e70d2434148922f42fdb3f",
    "private operation ownership":
        "0676c43cb4f7b2041f17cb15b74d08cc8d9469c472d8c327ab3d6a8c0e6984c2",
    "provider lifecycle":
        "4344111406a05bb124a17a9f5b60ebcc2c5bcd48c9e3388d166f73f7cf9bdc8f",
    "operation-last restart":
        "055ee97c59ca453ebfb54562f91c045ca89c9489ee19947852f2fe4d0afe7420",
    "socket coordination":
        "50fc7fd30fac71dd0ced9dd7828323528ddc2079a2d1643d93ae927a8be249da",
    "socket server evidence":
        "a607bd4e3103f8a8968e31378c714f4655def81621440e6646f668f2884aeee9",
    "socket cancellation server branch":
        "7b5ac76be0044e94f3a29769a1fa7252d6fd2cb6d523842ecc749e389aafddda",
    "socket client evidence":
        "e41ec955f0220d833c324ca83a93082e8647bec7373fc7980ccf5809d28b4d88",
    "backend listing conformance":
        "cd67f0e2edb262b9bcebd79360df42ab500266d37a7fbb2c8c28f606610ab6ab",
    "backend codec":
        "213085bcc07128717deea235a1521f1e713820e6ba8656d2d403557fb02a00d3",
    "backend low-level request":
        "cda421e2369c4fdfbec7e16afd44e17d903b6fa00bdd0f17d8c7fc10619ddbef",
    "server corpus":
        "35b5957b2efc5f6fde1d6c3c5bfe9becb567c42575ae620ec7e8c8fc5a14d28b",
    "implementation corpus":
        "37e6fc400ec7d7679481d4a6e8d64af7426dbd11fb62e0a5d3a18e281ec3f940",
}


class EvidenceError(RuntimeError):
    """One fail-closed mismatch in the reviewed static evidence."""


def fail(message: str) -> None:
    raise EvidenceError(message)


def read_source(path: Path, label: str) -> str:
    data = path.read_bytes()
    if b"\r" in data:
        fail(f"{label}: carriage-return byte present")
    return data.decode("utf-8")


def region(source: str, start: str, end: str, label: str) -> str:
    if source.count(start) != 1:
        fail(f"{label}: start marker count changed")
    if source.count(end) != 1:
        fail(f"{label}: end marker count changed")
    first = source.index(start)
    last = source.index(end)
    if last < first:
        fail(f"{label}: markers reversed")
    return source[first:last + len(end)]


def verify_digest(source: str, expected: str, label: str) -> None:
    if re.fullmatch(r"[0-9a-f]{64}", expected) is None:
        fail(f"{label}: invalid reviewed digest")
    actual = hashlib.sha256(source.encode("utf-8")).hexdigest()
    if actual != expected:
        fail(f"{label}: reviewed region digest changed: {actual}")


def exact_digest(source: str, label: str) -> None:
    verify_digest(source, REGION_DIGESTS[label], label)


def ordered(source: str, fragments: list[str], label: str) -> None:
    normalized = re.sub(r"\s+", " ", source)
    position = -1
    for fragment in fragments:
        expected = re.sub(r"\s+", " ", fragment)
        if normalized.count(expected) != 1:
            fail(f"{label}: fragment count changed: {fragment!r}")
        next_position = normalized.find(expected)
        if next_position <= position:
            fail(f"{label}: fragment order changed: {fragment!r}")
        position = next_position


def in_order(source: str, fragments: list[str], label: str) -> None:
    normalized = re.sub(r"\s+", " ", source)
    position = 0
    for fragment in fragments:
        expected = re.sub(r"\s+", " ", fragment)
        next_position = normalized.find(expected, position)
        if next_position < 0:
            fail(f"{label}: missing or reordered fragment: {fragment!r}")
        position = next_position + len(expected)


def absent(source: str, fragments: list[str], label: str) -> None:
    normalized = re.sub(r"\s+", " ", source)
    for fragment in fragments:
        expected = re.sub(r"\s+", " ", fragment)
        if expected in normalized:
            fail(f"{label}: forbidden fragment present: {fragment!r}")


def exact_entry(entry: dict[str, object]) -> None:
    if entry.keys() != EXPECTED_ENTRY.keys():
        fail("registry entry field inventory changed")
    for key, value in EXPECTED_ENTRY.items():
        if entry[key] != value:
            fail(f"registry {key} changed")


def expect_evidence_error(action, label: str) -> None:
    try:
        action()
    except EvidenceError:
        return
    fail(f"negative oracle accepted {label}")


def verify_helper_failures() -> None:
    if region("BEGIN body END", "BEGIN", "END", "positive") != (
        "BEGIN body END"
    ):
        fail("region helper changed positive extraction")
    digest_fixture = "reviewed digest fixture"
    digest = hashlib.sha256(digest_fixture.encode("utf-8")).hexdigest()
    verify_digest(digest_fixture, digest, "positive digest")
    expect_evidence_error(
        lambda: verify_digest(digest_fixture, "0" * 64, "wrong digest"),
        "wrong reviewed digest",
    )
    expect_evidence_error(
        lambda: verify_digest(digest_fixture, "not-a-digest", "bad digest"),
        "malformed reviewed digest",
    )
    fixtures = [
        ("body END", "BEGIN", "END", "missing start"),
        ("BEGIN body BEGIN END", "BEGIN", "END", "duplicate start"),
        ("BEGIN body", "BEGIN", "END", "missing end"),
        ("BEGIN body END END", "BEGIN", "END", "duplicate end"),
        ("END body BEGIN", "BEGIN", "END", "reversed markers"),
    ]
    for source, start, end, label in fixtures:
        expect_evidence_error(
            lambda source=source, start=start, end=end, label=label: region(
                source, start, end, label
            ),
            label,
        )
    expect_evidence_error(
        lambda: in_order("alpha beta", ["alpha", "gamma"], "fixture"),
        "missing in-order fragment",
    )
    expect_evidence_error(
        lambda: in_order("beta alpha", ["alpha", "beta"], "fixture"),
        "reordered in-order fragment",
    )
    expect_evidence_error(
        lambda: ordered("alpha alpha beta", ["alpha", "beta"], "fixture"),
        "duplicate ordered fragment",
    )
    expect_evidence_error(
        lambda: ordered("beta alpha", ["alpha", "beta"], "fixture"),
        "reordered ordered fragment",
    )
    absent("alpha beta", ["gamma"], "positive absence")
    expect_evidence_error(
        lambda: absent("alpha beta", ["beta"], "fixture"),
        "forbidden present fragment",
    )
    changed_entry = dict(EXPECTED_ENTRY)
    changed_entry["codec"] = "changed"
    expect_evidence_error(
        lambda: exact_entry(changed_entry), "changed registry value"
    )
    extra_entry = dict(EXPECTED_ENTRY)
    extra_entry["unexpected"] = True
    expect_evidence_error(
        lambda: exact_entry(extra_entry), "extra registry field"
    )


def verify_two_round_socket_harness(source: str, label: str) -> None:
    server_rounds = region(
        source,
        "State.Publish (Port);\n      for Round in 1 .. 2 loop",
        "end loop;\n      Sockets.Close_Socket (Listener);",
        f"{label} server rounds",
    )
    if server_rounds.count("for Round in 1 .. 2 loop") != 1:
        fail(f"{label}: server round count changed")
    in_order(
        server_rounds,
        [
            "State.Publish (Port)",
            "for Round in 1 .. 2 loop",
            "end loop",
            "Sockets.Close_Socket (Listener)",
        ],
        f"{label} server rounds",
    )

    results = region(
        source,
        "protected type Client_Results is",
        "end Client_Results;\n\n   Clients : Client_Results;",
        f"{label} client results",
    )
    in_order(
        results,
        [
            "Count : Natural := 0",
            "Count := Count + 1",
            "entry Wait_All",
            "when Count = 2",
        ],
        f"{label} client results",
    )

    clients = region(
        source,
        "Run_And_Report (1);\n"
        "   declare\n      task Lightweight_Client is",
        "Clients.Wait_All (Client_Passed, Client_Detail);",
        f"{label} client rounds",
    )
    if clients.count("Run_And_Report (") != 2:
        fail(f"{label}: native/lightweight client count changed")
    in_order(
        clients,
        [
            "Run_And_Report (1)",
            "task Lightweight_Client is",
            "pragma Task_Info (Flyology.Lightweight_Task)",
            "task body Lightweight_Client is",
            "Run_And_Report (2)",
            "Clients.Wait_All (Client_Passed, Client_Detail)",
        ],
        f"{label} client rounds",
    )


def verify_owner_driven_cancel(source: str, label: str) -> None:
    owners = region(
        source,
        "State : Coordination;",
        "protected type Client_Results is",
        f"{label} readiness owners",
    )
    ordered(
        owners,
        [
            "List_V2_Admission_Native : aliased "
            "Flyology.Cancellation.Token",
            "List_V2_Admission_Lightweight : aliased "
            "Flyology.Cancellation.Token",
            "List_V2_Drain_Native : aliased Flyology.Cancellation.Token",
            "List_V2_Drain_Lightweight : aliased "
            "Flyology.Cancellation.Token",
        ],
        f"{label} readiness owners",
    )
    cancellation = region(
        source,
        "--  Five slots are the derived composed stack: listing parent,",
        '"same-object ListObjectsV2 restart mismatch";',
        f"{label} owner-driven cancellation",
    )
    in_order(
        cancellation,
        [
            "Admission_FD : Flyology.IO.Descriptor",
            "Admission_Requested : Boolean",
            "Drain_FD : Flyology.IO.Descriptor",
            "Drain_Requested : Boolean",
            "if Round = 1 then",
            "List_V2_Admission_Native.Wait_Source",
            "List_V2_Drain_Native.Wait_Source",
            "elsif Round = 2 then",
            "List_V2_Admission_Lightweight.Wait_Source",
            "List_V2_Drain_Lightweight.Wait_Source",
            '"invalid ListObjectsV2 client round"',
            "if Admission_Requested",
            "or else Drain_Requested",
            "or else Admission_FD < 0",
            "or else Drain_FD < 0",
            '"stale ListObjectsV2 cancellation readiness"',
            "Set : aliased Operations.Completion_Set (5)",
            "Operation : List_Objects_V2_Operation :=",
            "Admission_Ready : Flyology.IO.Readiness_Operation :=",
            "Flyology.IO.Wait (Set'Access, Admission_FD",
            "Drain_Ready : Flyology.IO.Readiness_Operation :=",
            "Flyology.IO.Wait (Set'Access, Drain_FD",
            "Completed_Batch : Operations.Completion_Batch (Set.Capacity)",
            "Operations.Wait_Some (Set, Completed_Batch)",
            "Completed_Batch.Count = 0",
            "not Operations.Is_Terminal (Admission_Ready)",
            "not Operations.Is_Active (Drain_Ready)",
            "not Operations.Is_Active (Operation)",
            '"ListObjectsV2 did not remain active through admission"',
            "Flyology.IO.Finish (Admission_Ready)",
            "Operations.Cancel (Operation)",
            "Operations.Wait_All (Set)",
            "Finish (Operation, Result)",
            '"admitted ListObjectsV2 cancellation mismatch"',
            "not Operations.Is_Terminal (Drain_Ready)",
            '"ListObjectsV2 transport drain was not acknowledged"',
            "Flyology.IO.Finish (Drain_Ready)",
            "Operation => Operation",
            "Operations.Wait_All (Set)",
            "Finish (Operation, Result)",
            '"same-object ListObjectsV2 restart mismatch"',
        ],
        f"{label} owner-driven cancellation",
    )
    absent(
        cancellation,
        [
            "task Cancel_After_Admission",
            "pragma Task_Info (Flyology.Native_Task)",
            "Cancel_Passed",
            "Cancel_Detail",
            "Sockets.Create_Socket_Pair",
        ],
        f"{label} owner-driven cancellation",
    )
    if cancellation.count("Operations.Cancel (Operation)") != 1:
        fail(f"{label}: cancellation must be issued exactly once by owner")
    if cancellation.count("Flyology.IO.Finish") != 2:
        fail(f"{label}: readiness operations are not consumed exactly once")


def operation_entry() -> dict[str, object]:
    raw = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    matches = [
        entry for entry in raw["operation"]
        if entry.get("name") == "ListObjectsV2"
    ]
    if len(matches) != 1:
        fail("registry entry count changed")
    lane = raw["qualification"].get("list_objects_v2")
    if lane != [
        ["uv", "run", "--python", "3.13", "--",
         "tools/verify-list-objects-v2-preparation.py"],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
        ["./tools/build-api-docs.sh",
         "/private/tmp/fos-list-objects-v2-gnatdoc"],
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]:
        fail("qualification lane changed")
    return matches[0]


def main() -> int:
    verify_helper_failures()
    entry = operation_entry()
    exact_entry(entry)

    low_spec = read_source(LOW_SPEC, "low-level spec")
    low_body = read_source(LOW_BODY, "low-level body")
    objects_spec = read_source(OBJECTS_SPEC, "Objects spec")
    objects_body = read_source(OBJECTS_BODY, "Objects body")

    low_contract = region(
        low_spec,
        "function Prepare_List_Objects_V2\n",
        "return List_Objects_V2_Outcome;\n\n"
        "   --  Every non-bucket member in the pinned "
        "ListObjectVersions request.",
        "low-level public contract",
    )
    exact_digest(low_contract, "low-level public contract")
    in_order(
        low_contract,
        [
            "function Prepare_List_Objects_V2",
            "Origin : Flyology.HTTP.Origin",
            "Style : Addressing_Style",
            "Bucket : String",
            "Parameters : List_Objects_V2_Parameters",
            "Identity : Credentials",
            "Region : String",
            "Timestamp : String) return Prepared_Request",
            "type List_Objects_V2_Outcome",
            "function Decode_List_Objects_V2_Response",
            "function Decode_List_Objects_V2_Complete_Response",
            "Response : Flyology.HTTP.Client.Response",
            "Payload : String",
            "Prepared : Prepared_Request",
            "Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits",
            "function Execute_List_Objects_V2",
            "Client : aliased in out Flyology.HTTP.Client.Client",
            "Timeout : Duration := 30.0",
            "Token : access Flyology.Cancellation.Token := null",
        ],
        "low-level public contract",
    )

    low_implementation = region(
        low_body,
        "function Prepare_List_Objects_V2\n",
        "end Execute_List_Objects_V2;",
        "low-level implementation",
    )
    exact_digest(low_implementation, "low-level implementation")

    low_region = region(
        low_body,
        "function Decode_List_Objects_V2_Complete_Response",
        "end Decode_List_Objects_V2_Complete_Response;",
        "complete decoder",
    )
    ordered(
        low_region,
        [
            "Count : constant Natural :=",
            "Flyology.HTTP.Client.Header_Count (Response, Name)",
            "if Count > 1 then",
            '"invalid ListObjectsV2 response header multiplicity"',
            "elsif Count = 0 then",
            'return ""',
            "Flyology.HTTP.Client.Header (Response, Name)",
            "if Value'Length = 0",
            "not Valid_List_Response_Header_Text (Value)",
            '"invalid ListObjectsV2 response header value"',
        ],
        "complete decoder singleton headers",
    )
    in_order(
        low_region,
        [
            "Prepared.Operation /= List_Objects_V2_Operation",
            'Singleton_Header ("x-amz-request-charged")',
            'Singleton_Header ("x-amz-request-id")',
            'Singleton_Header ("x-amz-id-2")',
            "Prepared.Requested_URL_Encoding",
            "Outcome.Listing.Name /= Prepared.Requested_Bucket",
            "Outcome.Listing.Prefix",
            "Prepared.Requested_Prefix",
            "Outcome.Listing.Delimiter",
            "Prepared.Requested_Delimiter",
            "Outcome.Listing.Continuation_Token",
            "Prepared.Requested_Continuation_Token",
            "Outcome.Listing.Start_After",
            "Prepared.Requested_Start_After",
            "Outcome.Listing.Max_Keys",
            "Prepared.Requested_Max_Keys",
            "Outcome.Listing.Encoding_Type",
            "Expected_Encoding",
            '"ListObjectsV2 response does not match prepared request"',
        ],
        "complete decoder",
    )
    for symbol in EXPECTED_SYMBOLS[:3]:
        if symbol not in low_spec or symbol not in low_body:
            fail(f"low-level symbol missing: {symbol}")

    public_region = region(
        objects_spec,
        "type List_Objects_V2_Result_Kind is",
        "with Pre => Flyology.Operations.Is_Terminal (Operation);\n\n"
        "   --  Shape of a terminal ListObjectVersions read.",
        "public composable contract",
    )
    exact_digest(public_region, "public composable contract")
    in_order(
        public_region,
        [
            "List_Objects_V2_Response_Available",
            "List_Objects_V2_Exchange_Failed",
            "type List_Objects_V2_Result",
            "Failure : Failure_Reason := Corrupt_Or_Invalid_Response",
            "Admission : Flyology.HTTP.Client.Admission_Certainty",
            "when List_Objects_V2_Response_Available =>",
            "Response : Low_Level.List_Objects_V2_Outcome",
            "when List_Objects_V2_Exchange_Failed =>",
            "HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind",
            "HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase",
            "Detail : Ada.Strings.Unbounded.Unbounded_String",
            "type List_Objects_V2_Operation",
            "Set : not null access Flyology.Operations.Completion_Set'Class",
            "HTTP : not null access Flyology.HTTP.Client.Client",
            "Cancellation : access Flyology.Cancellation.Token) is",
            "new Flyology.Operations.Operation and",
            "Flyology.HTTP.Client.Response_Body_Sink with private;",
            "HTTP client and optional cancellation owner through terminal "
            "drain",
            "each completed page is an independent read-only service "
            "snapshot",
            "procedure List_Page",
            "Operation : in out List_Objects_V2_Operation",
            "with Pre => not Flyology.Operations.Is_Active (Operation)",
            "and then not Flyology.Operations.Is_Terminal (Operation)",
            "function List_Page",
            "Set : not null access Flyology.Operations.Completion_Set'Class",
            "return List_Objects_V2_Operation",
            "procedure Finish",
            "Result : out List_Objects_V2_Result",
            "with Pre => Flyology.Operations.Is_Terminal (Operation)",
        ],
        "public composable contract",
    )
    if public_region.count("procedure List_Page") != 1:
        fail("public composable contract: operation-last profile changed")
    if public_region.count("function List_Page") != 1:
        fail("public composable contract: constructor profile changed")
    if public_region.count("procedure Finish") != 1:
        fail("public composable contract: Finish profile changed")

    sync_region = region(
        objects_spec,
        "--  List one bounded page of current objects with S3 ListObjectsV2.",
        "return List_Objects_V2_Result;\n\n"
        "   --  One complete typed version-listing page or structured S3 "
        "rejection.",
        "public synchronous contract",
    )
    exact_digest(sync_region, "public synchronous contract")
    in_order(
        sync_region,
        [
            "function List_Page",
            "Client : aliased in out Flyology.HTTP.Client.Client",
            "Origin : Flyology.HTTP.Origin",
            "Bucket : String",
            "Identity : Low_Level.Credentials",
            'Region : String := "us-east-1"',
            "Style : Low_Level.Addressing_Style := Low_Level.Path_Style",
            "Prefix : String := \"\"",
            "Delimiter : String := \"\"",
            "Maximum : S3.Core.Page_Size := 1_000",
            "Continuation_Token : String := \"\"",
            "Start_After : String := \"\"",
            "Fetch_Owner : Boolean := False",
            "URL_Encoding : Boolean := False",
            "Include_Restore_Status : Boolean := False",
            "Expected_Bucket_Owner : String := \"\"",
            "Request_Payer : String := \"\"",
            "Timeout : Duration := 30.0",
            "Token : access Flyology.Cancellation.Token := null",
            "return List_Outcome",
            "function List_Page",
            "Parameters : Low_Level.List_Objects_V2_Parameters",
            "return List_Objects_V2_Result",
        ],
        "public synchronous contract",
    )
    if sync_region.count("function List_Page") != 2:
        fail("public synchronous contract: overload inventory changed")

    private_region = region(
        objects_spec,
        "--  @exclude\n"
        "   type List_Objects_V2_Operation\n"
        "     (Set : not null access "
        "Flyology.Operations.Completion_Set'Class;\n"
        "      HTTP : not null access Flyology.HTTP.Client.Client;",
        "Saved_Error : Ada.Exceptions.Exception_Occurrence;\n"
        "   end record;\n\n   --  @exclude\n"
        "   type List_Object_Versions_Operation",
        "private operation ownership",
    )
    exact_digest(private_region, "private operation ownership")
    in_order(
        private_region,
        [
            "Set : not null access Flyology.Operations.Completion_Set'Class",
            "HTTP : not null access Flyology.HTTP.Client.Client",
            "Cancellation : access Flyology.Cancellation.Token",
            "new Flyology.Operations.Operation (Set)",
            "Flyology.HTTP.Client.Response_Body_Sink",
            "Deadline : Flyology.HTTP.Client.Monotonic_Deadline",
            "Prepared : aliased Low_Level.Prepared_Request",
            "Child : Flyology.HTTP.Client.Exchange_Operation (Set)",
            "Response_Data : Flyology.Bytes.Unbounded_Bytes",
            "Response_Limit : Natural := 0",
            "Final_Result : List_Objects_V2_Result",
            "Has_Final_Result : Boolean := False",
            "Has_Saved_Error : Boolean := False",
            "Saved_Error : Ada.Exceptions.Exception_Occurrence",
        ],
        "private operation ownership",
    )
    start_region = region(
        objects_body,
        "procedure Start_List_Objects_V2",
        "end Start_List_Objects_V2;",
        "provider restart",
    )
    ordered(
        start_region,
        [
            "Operation.HTTP /= Client or else "
            "Operation.Cancellation /= Token",
            '"ListObjectsV2 restart changed a retained owner"',
            "Low_Level.Prepare_List_Objects_V2",
            "Flyology.Bytes.Clear (Operation.Response_Data);",
            "S3.XML.Default_Limits.Maximum_Document_Bytes",
            "Operation_Drivers.Start (Operation);",
            "Operations.Drive",
            "Operation_Drivers.Rollback_Start (Operation);",
            "Low.Clear_Prepared_Request (Operation.Prepared);",
        ],
        "provider restart",
    )
    finalize_region = region(
        objects_body,
        "overriding procedure Finalize\n"
        "     (Item : in out List_Objects_V2_Operation) is",
        "end Finalize;\n\n   procedure Start_List_Objects_V2",
        "provider finalization",
    )
    ordered(
        finalize_region,
        [
            "Operations.Finalize (Operations.Operation (Item))",
            "Low.Clear_Prepared_Request (Item.Prepared)",
            "Flyology.Bytes.Clear (Item.Response_Data)",
        ],
        "provider finalization",
    )
    drive_region = region(
        objects_body,
        "overriding procedure Drive\n"
        "     (Item : in out List_Objects_V2_Operation;",
        "end Drive;\n\n   overriding procedure Request_Cancellation\n"
        "     (Item : in out List_Objects_V2_Operation) is",
        "provider drive",
    )
    ordered(
        drive_region,
        [
            "Low.List_Objects_V2 (Item.HTTP, Item.Prepared'Access, "
            "Item'Access, Item.Deadline, Item.Cancellation, Item.Child);",
            "Operations.Continue_After (Item, Item.Child);",
            "Complete_List_Objects_V2_Child (Item);",
            "Operation_Drivers.Complete (Item, Operations.Failed);",
        ],
        "provider drive",
    )

    constructor_region = region(
        objects_body,
        "function List_Page\n"
        "     (Set      : not null access Operations.Completion_Set'Class;",
        "end List_Page;\n\n   procedure Finish\n"
        "     (Operation : in out List_Objects_V2_Operation;",
        "provider constructor",
    )
    ordered(
        constructor_region,
        [
            "return List_Objects_V2_Operation is",
            "return Result : List_Objects_V2_Operation "
            "(Set, Client, Token) do",
            "Start_List_Objects_V2",
            "Result, Client, Origin, Bucket, Parameters, Identity, Deadline",
            "Region, Style, Token",
        ],
        "provider constructor",
    )

    finish_region = region(
        objects_body,
        "procedure Finish\n"
        "     (Operation : in out List_Objects_V2_Operation;\n"
        "      Result    : out List_Objects_V2_Result) is",
        "end Finish;\n\n   procedure Append_Object_Lock_Response",
        "typed Finish",
    )
    ordered(
        finish_region,
        [
            "Operations.Consume (Operation)",
            "Low.Clear_Prepared_Request (Operation.Prepared)",
            "if Operation.Has_Saved_Error then",
            "elsif not Operation.Has_Final_Result then",
            'raise Program_Error with "ListObjectsV2 has no terminal result"',
            "Result := Operation.Final_Result",
        ],
        "typed Finish",
    )
    absent(
        finish_region,
        ["Flyology.Bytes.Clear", "Response_Data"],
        "typed Finish",
    )

    operation_last_region = region(
        objects_body,
        "procedure List_Page\n"
        "     (Client   : not null access Flyology.HTTP.Client.Client;\n"
        "      Origin   : Flyology.HTTP.Origin;\n"
        "      Bucket   : String;\n"
        "      Parameters : Low_Level.List_Objects_V2_Parameters;",
        "end List_Page;\n\n   procedure List_Versions_Page",
        "operation-last restart",
    )
    exact_digest(operation_last_region, "operation-last restart")
    in_order(
        operation_last_region,
        [
            "Operation : in out List_Objects_V2_Operation",
            "Start_List_Objects_V2 (Operation, Client, Origin, Bucket, "
            "Parameters, Identity, Deadline, Region, Style, Token)",
        ],
        "operation-last restart",
    )

    normalizer_region = region(
        objects_body,
        "function Normalize_List_Objects_V2_Response",
        "end Normalize_List_Objects_V2_Response;",
        "response normalizer",
    )
    in_order(
        normalizer_region,
        [
            "Admission /= HTTP_Client.Response_Observed",
            "then Corrupt_Or_Invalid_Response",
            "Value.Kind = Low_Level.Listed",
            "then No_Failure",
            'Value.Status = 400 and then Code in "InvalidArgument" '
            '| "InvalidRequest"',
            "then Invalid_Request",
            'Value.Status = 501 and then Code = "NotImplemented"',
            "then Invalid_Request",
            'Value.Status = 401 and then Code = "InvalidAccessKeyId"',
            "then Authentication_Failed",
            'Value.Status = 403 and then Code = "AccessDenied"',
            "then Authorization_Failed",
            'Value.Status = 404 and then Code = "NoSuchBucket"',
            "then Not_Found",
            'Value.Status = 409 and then Code = "OperationAborted"',
            'Value.Status = 429 and then Code = "SlowDown"',
            'Value.Status = 500 and then Code = "InternalError"',
            'Value.Status = 502 and then Code = "BadGateway"',
            'Value.Status = 503 and then Code = "SlowDown"',
            'Value.Status = 504 and then Code = "RequestTimeout"',
            "then Unavailable_Or_Retryable",
            "else Corrupt_Or_Invalid_Response",
            "Kind => List_Objects_V2_Response_Available",
            "Failure => Failure",
            "Admission => Admission",
            "Response => Value",
        ],
        "response normalizer",
    )
    normalized_normalizer = re.sub(r"\s+", " ", normalizer_region)
    exact_mapping_counts = {
        "then Corrupt_Or_Invalid_Response": 1,
        "then No_Failure": 1,
        "then Invalid_Request": 2,
        "then Authentication_Failed": 1,
        "then Authorization_Failed": 1,
        "then Not_Found": 1,
        "then Unavailable_Or_Retryable": 1,
        "else Corrupt_Or_Invalid_Response": 1,
    }
    for fragment, expected_count in exact_mapping_counts.items():
        if normalized_normalizer.count(fragment) != expected_count:
            fail(f"response normalizer: mapping count changed: {fragment}")

    lifecycle_region = region(
        objects_body,
        "function Normalize_List_Objects_V2_Response",
        "end Finish;\n\n   procedure Append_Object_Lock_Response",
        "provider lifecycle",
    )
    exact_digest(lifecycle_region, "provider lifecycle")
    write_region = region(
        lifecycle_region,
        "overriding procedure Write\n"
        "     (Item : in out List_Objects_V2_Operation;",
        "end Write;",
        "provider bounded sink",
    )
    ordered(
        write_region,
        [
            "Natural (Data'Length) > Item.Response_Limit - "
            "Flyology.Bytes.Length (Item.Response_Data)",
            "raise Response_Limit_Exceeded",
            '"ListObjectsV2 response exceeds the S3 XML limit"',
            "Flyology.Bytes.Append (Item.Response_Data, Data)",
        ],
        "provider bounded sink",
    )
    completion_region = region(
        lifecycle_region,
        "procedure Complete_List_Objects_V2_Child",
        "end Complete_List_Objects_V2_Child;",
        "provider child completion",
    )
    in_order(
        completion_region,
        [
            "HTTP_Client.Finish (Item.Child, HTTP_Result, Response)",
            "when Response_Limit_Exceeded =>",
            "Operations.Release (Item.Child)",
            "HTTP_Client.Response_Sink_Failed",
            "Operation_Drivers.Complete (Item, Operations.Succeeded)",
            "when Error : others =>",
            "Operations.Release (Item.Child)",
            "Ada.Exceptions.Save_Occurrence",
            "Operation_Drivers.Complete (Item, Operations.Failed)",
            "Operations.Release (Item.Child)",
            "HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete",
            "Normalize_List_Objects_V2_Failure",
            "Decode_List_Objects_V2_Complete_Response",
            "when Low_Level.Invalid_Response =>",
            "HTTP_Client.Response_Invalid",
            "Low.Clear_Prepared_Request (Item.Prepared)",
            "Item.Has_Final_Result := True",
            "Operation_Drivers.Complete (Item, Operations.Succeeded)",
        ],
        "provider child completion",
    )
    cancellation_region = region(
        lifecycle_region,
        "overriding procedure Request_Cancellation\n"
        "     (Item : in out List_Objects_V2_Operation) is",
        "end Request_Cancellation;",
        "provider cancellation",
    )
    ordered(
        cancellation_region,
        [
            "Operations.Is_Active (Item.Child)",
            "Operations.Cancel (Item.Child)",
        ],
        "provider cancellation",
    )

    socket = region(
        read_source(SOCKET, "socket corpus"),
        "procedure Run_Client (Round : Positive) is",
        "end Run_Client;",
        "socket client procedure",
    )
    if socket.count("use type Flyology.IO.Descriptor;") != 1:
        fail("socket client procedure: descriptor operators not visible")
    socket_region = region(
        socket,
        "Result : constant Low_Level.List_Objects_V2_Outcome :=\n"
        "              Low_Level.Execute_List_Objects_V2\n"
        "                (HTTP, Prepared, Timeout => 5.0);\n"
        "         begin\n"
        "            if Result.Kind /= Low_Level.Listed",
        '"composed ListObjectsV2 continuation mismatch";',
        "socket evidence",
    )
    exact_digest(socket_region, "socket client evidence")
    in_order(
        socket_region,
        [
            "Low_Level.Execute_List_Objects_V2",
            '"typed ListObjectsV2 socket success mismatch"',
            "Require_Invalid_List_Objects_V2",
            '"ListObjectsV2 accepted a wrong echoed bucket"',
            '"ListObjectsV2 accepted a duplicate singleton header"',
            '"pre-admission ListObjectsV2 cancellation mismatch"',
            '"socket error result mismatch"',
            "Require_Normalized_List_Objects_V2_Failure",
            "Authentication_Failed, 401, \"InvalidAccessKeyId\"",
            "Authorization_Failed, 403, \"AccessDenied\"",
            "Not_Found, 404, \"NoSuchBucket\"",
            "Invalid_Request, 400, \"InvalidArgument\"",
            "Unavailable_Or_Retryable, 503, \"SlowDown\"",
            "Corrupt_Or_Invalid_Response, 400, "
            '"UnclassifiedListObjectsV2Error"',
            "List_V2_Admission_Native.Wait_Source",
            "List_V2_Drain_Native.Wait_Source",
            "List_V2_Admission_Lightweight.Wait_Source",
            "List_V2_Drain_Lightweight.Wait_Source",
            "Admission_Requested",
            "Drain_Requested",
            "Set : aliased Operations.Completion_Set (5)",
            "Admission_Ready : Flyology.IO.Readiness_Operation :=",
            "Flyology.IO.Wait (Set'Access, Admission_FD",
            "Drain_Ready : Flyology.IO.Readiness_Operation :=",
            "Flyology.IO.Wait (Set'Access, Drain_FD",
            "Operations.Wait_Some (Set, Completed_Batch)",
            "Operations.Is_Terminal (Admission_Ready)",
            "Operations.Is_Active (Drain_Ready)",
            "Operations.Is_Active (Operation)",
            "Flyology.IO.Finish (Admission_Ready)",
            "Operations.Cancel (Operation)",
            "Operations.Wait_All (Set)",
            "Finish (Operation, Result)",
            "Result.Admission /= HTTP_Client.Possibly_Admitted",
            '"admitted ListObjectsV2 cancellation mismatch"',
            "Operations.Is_Terminal (Drain_Ready)",
            "Flyology.IO.Finish (Drain_Ready)",
            "Deadline => HTTP_Client.Deadline_After (5.0)",
            "Token => null",
            "Operation => Operation",
            "Operations.Wait_All (Set)",
            "Finish (Operation, Result)",
            '"same-object ListObjectsV2 restart mismatch"',
            '"oversized socket response accepted"',
            '"high-level ListObjectsV2 ignored cancellation/deadline"',
            '"high-level ListObjectsV2 lost truncated-page token"',
            '"high-level ListObjectsV2 continuation mismatch"',
            "Operation : List_Objects_V2_Operation :=",
            "Operations.Wait_All (Set)",
            "Finish (Operation, Result)",
            '"composed ListObjectsV2 first page mismatch"',
            "Page_Parameters.Continuation_Token :=",
            "Page_Parameters.Has_Continuation_Token := True",
            "Operation => Operation",
            "Operations.Wait_All (Set)",
            "Finish (Operation, Result)",
            '"composed ListObjectsV2 continuation mismatch"',
        ],
        "socket evidence",
    )

    socket_source = read_source(SOCKET, "socket corpus")
    verify_two_round_socket_harness(socket_source, "socket harness")
    expect_evidence_error(
        lambda: verify_two_round_socket_harness(
            socket_source.replace(
                "for Round in 1 .. 2 loop",
                "for Round in 1 .. 1 loop",
                1,
            ),
            "one-round fixture",
        ),
        "one server round",
    )
    expect_evidence_error(
        lambda: verify_two_round_socket_harness(
            socket_source.replace(
                "task body Lightweight_Client is\n"
                "      begin\n"
                "         Run_And_Report (2);\n"
                "      end Lightweight_Client;",
                "task body Lightweight_Client is\n"
                "      begin\n"
                "         null;\n"
                "      end Lightweight_Client;",
                1,
            ),
            "missing-lightweight fixture",
        ),
        "missing lightweight client",
    )
    verify_owner_driven_cancel(socket_source, "ListObjectsV2")
    cancel_fixtures = [
        (
            socket_source.replace(
                "not Operations.Is_Terminal (Admission_Ready)",
                "False",
                1,
            ),
            "missing admission terminal predicate",
        ),
        (
            socket_source.replace(
                "Flyology.IO.Finish (Admission_Ready);\n"
                "               Operations.Cancel (Operation);",
                "Operations.Cancel (Operation);\n"
                "               Flyology.IO.Finish (Admission_Ready);",
                1,
            ),
            "cancel before admission consumption",
        ),
        (
            socket_source.replace(
                "if not Operations.Is_Terminal (Drain_Ready) then\n"
                "                  raise Program_Error with\n"
                "                    \"ListObjectsV2 transport drain was not "
                "acknowledged\";\n"
                "               end if;\n",
                "",
                1,
            ),
            "missing drain terminal requirement",
        ),
        (
            socket_source.replace(
                "Flyology.IO.Finish (Drain_Ready);",
                "null;",
                1,
            ),
            "unconsumed drain readiness",
        ),
        (
            socket_source.replace(
                "List_V2_Admission_Lightweight.Wait_Source",
                "List_V2_Admission_Native.Wait_Source",
                1,
            ),
            "native token reused by lightweight round",
        ),
        (
            socket_source.replace(
                "List_V2_Drain_Native.Wait_Source",
                "List_V2_Admission_Native.Wait_Source",
                1,
            ),
            "admission token reused for drain",
        ),
    ]
    for fixture, label in cancel_fixtures:
        expect_evidence_error(
            lambda fixture=fixture, label=label: verify_owner_driven_cancel(
                fixture, label
            ),
            label,
        )
    coordination_region = region(
        socket_source,
        "protected type Coordination is",
        "State : Coordination;",
        "socket coordination",
    )
    exact_digest(coordination_region, "socket coordination")
    in_order(
        coordination_region,
        [
            "procedure Publish (Value : Sockets.Port)",
            "entry Wait_Ready (Value : out Sockets.Port)",
            "procedure Complete (Passed : Boolean; Detail : String := \"\")",
            "entry Wait_Done",
        ],
        "socket coordination",
    )
    absent(
        coordination_region,
        [
            "List_V2_Cancel_Admitted",
            "List_V2_Cancel_Drained",
            "Wait_List_V2_Cancel",
            "Report_List_V2_Cancel",
        ],
        "socket coordination",
    )
    socket_server_region = region(
        socket_source,
        "Serve\n"
        "           (HTTP_Response\n"
        "              (\"200 OK\", Success_XML,\n"
        "               \"x-amz-request-charged: requester\" & CRLF), "
        '"GET",\n'
        "            \"/example-bucket?list-type=2&max-keys=2\",\n"
        "            Expected_Request_Payer => \"requester\",\n"
        "            Expected_Bucket_Owner => \"123456789012\",\n"
        "            Expected_Object_Attributes => \"RestoreStatus\",\n"
        "            Fragmented => True);",
        "Serve\n"
        "           (HTTP_Response\n"
        "              (\"200 OK\", List_Uploads_XML,",
        "socket server evidence",
    )
    exact_digest(socket_server_region, "socket server evidence")
    in_order(
        socket_server_region,
        [
            '"401 Unauthorized"',
            "InvalidAccessKeyId",
            '"403 Forbidden", Error_XML',
            '"404 Not Found"',
            "NoSuchBucket",
            '"400 Bad Request"',
            "InvalidArgument",
            '"503 Service Unavailable"',
            "SlowDown",
            "UnclassifiedListObjectsV2Error",
            "Await_Cancellation => True",
            "Cancellation_Round => Round",
            '"200 OK", Success_XML',
        ],
        "socket server evidence",
    )
    serve_cancellation = region(
        socket_source,
        "if Await_Cancellation then",
        "Request_Drain;\n"
        "               return;",
        "socket cancellation server branch",
    )
    exact_digest(serve_cancellation, "socket cancellation server branch")
    in_order(
        serve_cancellation,
        [
            "procedure Request_Drain is",
            "List_V2_Drain_Native.Request",
            "List_V2_Drain_Lightweight.Request",
            "end Request_Drain",
            "if Cancellation_Round = 1 then",
            "List_V2_Admission_Native.Request",
            "elsif Cancellation_Round = 2 then",
            "List_V2_Admission_Lightweight.Request",
            '"invalid ListObjectsV2 cancellation round"',
            "Sockets.Receive",
            "Last >= Buffer'First",
            '"ListObjectsV2 cancel peer sent data before drain"',
            "Sockets.Close_Socket (Peer)",
            "when Occurrence : others =>",
            "Ada.Exceptions.Save_Occurrence (Saved, Occurrence)",
            "if Sockets.Is_Open (Peer) then",
            "Sockets.Close_Socket (Peer)",
            "Request_Drain",
            "Ada.Exceptions.Reraise_Occurrence (Saved)",
            "Request_Drain",
            "return",
        ],
        "socket cancellation server branch",
    )
    for token in [
        "List_V2_Admission_Native.Request",
        "List_V2_Admission_Lightweight.Request",
        "List_V2_Drain_Native.Request",
        "List_V2_Drain_Lightweight.Request",
    ]:
        if serve_cancellation.count(token) != 1:
            fail(f"socket cancellation server branch: count changed: {token}")
    expect_evidence_error(
        lambda: in_order(
            serve_cancellation.replace(
                "Request_Drain;\n"
                "                        Ada.Exceptions.Reraise_Occurrence",
                "Ada.Exceptions.Reraise_Occurrence",
                1,
            ),
            [
                "when Occurrence : others =>",
                "Sockets.Close_Socket (Peer)",
                "Request_Drain",
                "Ada.Exceptions.Reraise_Occurrence (Saved)",
            ],
            "server exceptional drain fixture",
        ),
        "missing exceptional drain publication",
    )

    backend = read_source(BACKEND, "backend corpus")
    listing_region = region(
        backend,
        "procedure Exercise_Listing\n"
        "     (Store : in out "
        "Flyology.Object_Storage.Backends.Backend'Class;",
        "end Exercise_Listing;",
        "backend listing conformance",
    )
    exact_digest(listing_region, "backend listing conformance")
    in_order(
        listing_region,
        [
            'Store.List_Objects ("missing-bucket"',
            '"listing absent bucket"',
            "Options.Maximum := 2",
            '"plain listing lexical first page"',
            '"plain listing continuation"',
            '"delimiter listing collapses and counts prefixes"',
            '"prefix-relative delimiter grouping"',
            '"exclusive listing cursor"',
            '"zero-sized listing is empty and final"',
            "for Maximum in 1 .. 6 loop",
            "Natural (Page.Objects.Length) = Maximum",
            "Page.Is_Truncated = (Maximum < 6)",
            '"ListObjects v1/v2 backend bounded-page property"',
            'Put_Listing_Key ("aardvark")',
            'Put_Listing_Key ("dir/aa")',
            '"ListObjects v1/v2 mutation-safe exclusive continuation"',
            'Options.Delimiter := US.To_Unbounded_String ("--")',
            '"ListObjects v1/v2 multi-character delimiter projection"',
            '"ListObjects v1/v2 projected-prefix continuation"',
            "Cancel.Request",
            '"listing observes pre-cancellation"',
            "Ada.Real_Time.Time_First",
            '"listing observes an expired deadline"',
        ],
        "backend listing conformance",
    )
    for invocation in [
        'Exercise_Listing (Store, "memory-list-bucket");',
        'Exercise_Listing (Store, "files-list-bucket");',
    ]:
        if backend.count(invocation) != 1:
            fail(f"backend listing invocation changed: {invocation}")
    codec_region = region(
        backend,
        "procedure Check_List_Objects_V2_Codec",
        "end Check_List_Objects_V2_Codec;",
        "backend ListObjectsV2 codec",
    )
    exact_digest(codec_region, "backend codec")
    in_order(
        codec_region,
        [
            "Parse_List_Objects_V2",
            "<Future><Nested>ignored</Nested>",
            "Serialize_List_Objects_V2",
            '"ListObjectsV2 serialization round trip"',
            '"ListObjectsV2 wrong root was accepted"',
            '"ListObjectsV2 duplicate singleton was accepted"',
            '"ListObjectsV2 truncated page without token was accepted"',
            '"ListObjectsV2 query decoding"',
            '"present empty ListObjectsV2 query members were collapsed"',
            '"listing continuation binding and tamper detection"',
        ],
        "backend ListObjectsV2 codec",
    )
    backend_low = region(
        backend,
        "procedure Check_Low_Level_List_Request",
        "end Check_Low_Level_List_Request;",
        "backend low-level ListObjectsV2",
    )
    exact_digest(backend_low, "backend low-level request")
    in_order(
        backend_low,
        [
            "Low_Level.Prepare_List_Objects_V2",
            '"path-style ListObjectsV2 target and authority"',
            '"ListObjectsV2 request signing matches exact wire target"',
            '"present empty ListObjectsV2 inputs were not preserved"',
            '"virtual-hosted ListObjectsV2 target"',
            '"oversized ListObjectsV2 target was accepted"',
            '"invalid ListObjectsV2 requester payer was accepted"',
            '"invalid ListObjectsV2 bucket was accepted"',
            "Low_Level.Decode_List_Objects_V2_Response",
            '"successful ListObjectsV2 response decoding"',
            '"typed ListObjectsV2 S3 error decoding and header fallback"',
            '"invalid ListObjectsV2 response header was accepted"',
            '"malformed successful S3 response was accepted"',
        ],
        "backend low-level ListObjectsV2",
    )
    if backend.count("Check_List_Objects_V2_Codec'Access") != 1:
        fail("backend ListObjectsV2 codec registration changed")

    server = read_source(SERVER, "server corpus")
    server_region = region(
        server,
        '"ListObjectsV2 setup failed"',
        '"ListObjectsV2 absent bucket mismatch"',
        "server ListObjectsV2 corpus",
    )
    exact_digest(server_region, "server corpus")
    in_order(
        server_region,
        [
            '"ListObjectsV2 setup failed"',
            '"ListObjectsV2 response framing mismatch"',
            '"ListObjectsV2 first page mismatch"',
            '"ListObjectsV2 continuation page mismatch"',
            '"ListObjectsV2 delimiter or URL encoding mismatch"',
            '"ListObjectsV2 present empty continuation token mismatch"',
            '"ListObjectsV2 StartAfter was not exclusive"',
            '"invalid ListObjectsV2 token was accepted"',
            '"duplicate ListObjectsV2 parameter was accepted"',
            '"ListObjectsV2 FetchOwner projection mismatch"',
            '"ListObjectsV2 mismatched expected owner was accepted"',
            '"invalid ListObjectsV2 request payer was accepted"',
            '"duplicate ListObjectsV2 expected owner was accepted"',
            '"ListObjectsV2 absent bucket mismatch"',
        ],
        "server ListObjectsV2 corpus",
    )

    implementation = read_source(IMPLEMENTATION, "implementation corpus")
    implementation_region = region(
        implementation,
        "procedure Require_Listed_Object is",
        "end Require_Listed_Object;",
        "implementation ListObjectsV2 corpus",
    )
    exact_digest(implementation_region, "implementation corpus")
    in_order(
        implementation_region,
        [
            "Low_Level.Prepare_List_Objects_V2",
            "Low_Level.Execute_List_Objects_V2",
            '"S3 implementation did not expose the completed object"',
            "Client_Objects.List_Page",
            '"S3 implementation failed high-level ListObjectsV2"',
        ],
        "implementation ListObjectsV2 corpus",
    )

    print(
        "ListObjectsV2 preparation: reviewed composable contract and "
        "cross-layer evidence OK"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except EvidenceError as error:
        raise SystemExit(f"ListObjectsV2 preparation failed: {error}")
    except (OSError, UnicodeError, tomllib.TOMLDecodeError, KeyError) as error:
        raise SystemExit(
            "ListObjectsV2 preparation failed: unreadable evidence: "
            f"{error}"
        )
