#!/usr/bin/env python3
"""Fail-closed evidence for reviewed ListBuckets qualification."""

from __future__ import annotations

import copy
import hashlib
import json
import os
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODEL_SHA256 = (
    "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
)
REGISTRY = ROOT / "coverage/s3-operations.toml"
S3_BUCKETS_SPEC = ROOT / "src/flyology-object_storage-s3-buckets.ads"
S3_BUCKETS_BODY = ROOT / "src/flyology-object_storage-s3-buckets.adb"
LOW_SPEC = ROOT / "src/flyology-object_storage-client-low_level.ads"
LOW_BODY = ROOT / "src/flyology-object_storage-client-low_level.adb"
BUCKETS_SPEC = ROOT / "src/flyology-object_storage-client-buckets.ads"
BUCKETS_BODY = ROOT / "src/flyology-object_storage-client-buckets.adb"
BUCKETS_TESTING = (
    ROOT / "tests/src/flyology-object_storage-client-buckets-testing.adb"
)
SOCKET = ROOT / "tests/src/s3_http_socket_corpus.adb"
SERVER = ROOT / "src/flyology-object_storage-server-s3_applications.adb"
SERVER_TEST = ROOT / "tests/src/s3_server_application_corpus.adb"
BACKEND = ROOT / "tests/src/object_storage_test_cases.adb"
SQLITE_BACKEND = (
    ROOT / "sqlite/tests/src/flyology_object_storage_sqlite_tests.adb"
)
IMPLEMENTATION = ROOT / "tests/src/s3_implementation_corpus.adb"
TLS_CORPUS = ROOT / "tests/src/s3_create_session_tls_corpus.adb"
QUALIFICATION = ROOT / "docs/qualification/list-buckets.md"


def regular(path: Path) -> None:
    assert path.is_file(), f"missing ListBuckets evidence: {path}"
    assert not path.is_symlink(), f"symlink ListBuckets evidence: {path}"


def once(text: str, marker: str, label: str) -> int:
    count = text.count(marker)
    assert count == 1, f"{label}: expected once, found {count}: {marker}"
    return text.index(marker)


def ordered_once(text: str, markers: list[str], label: str) -> None:
    positions = [once(text, marker, label) for marker in markers]
    assert positions == sorted(positions), f"{label}: evidence order changed"


def between(text: str, start: str, end: str, label: str) -> str:
    first = once(text, start, label)
    last = once(text, end, label)
    assert first < last, f"{label}: invalid region boundary"
    return text[first:last + len(end)]


def load_model() -> dict[str, object]:
    model_name = os.environ.get("FLYOLOGY_S3_SERVICE_MODEL", "")
    assert model_name, "FLYOLOGY_S3_SERVICE_MODEL is required"
    path = Path(model_name)
    regular(path)
    assert hashlib.sha256(path.read_bytes()).hexdigest() == MODEL_SHA256
    return json.loads(path.read_text(encoding="utf-8"))


def verify_model(model: dict[str, object]) -> None:
    operation = model["operations"]["ListBuckets"]
    assert operation["http"] == {"method": "GET", "requestUri": "/"}
    assert operation["input"] == {"shape": "ListBucketsRequest"}
    assert operation["output"] == {"shape": "ListBucketsOutput"}
    request = model["shapes"]["ListBucketsRequest"]
    assert request["type"] == "structure"
    assert list(request["members"]) == [
        "MaxBuckets",
        "ContinuationToken",
        "Prefix",
        "BucketRegion",
    ]
    assert [
        request["members"][name]["shape"] for name in request["members"]
    ] == ["MaxBuckets", "Token", "Prefix", "BucketRegion"]
    assert [
        request["members"][name]["locationName"]
        for name in request["members"]
    ] == [
        "max-buckets",
        "continuation-token",
        "prefix",
        "bucket-region",
    ]
    assert all(
        request["members"][name]["location"] == "querystring"
        for name in request["members"]
    )
    output = model["shapes"]["ListBucketsOutput"]
    assert output["type"] == "structure"
    assert list(output["members"]) == [
        "Buckets",
        "Owner",
        "ContinuationToken",
        "Prefix",
    ]
    assert [
        output["members"][name]["shape"] for name in output["members"]
    ] == ["Buckets", "Owner", "NextToken", "Prefix"]
    shapes = model["shapes"]
    assert shapes["MaxBuckets"] == {
        "type": "integer",
        "box": True,
        "max": 10_000,
        "min": 1,
    }
    for name in ("Token", "Prefix", "BucketRegion", "NextToken"):
        assert shapes[name] == {"type": "string"}
    assert shapes["Buckets"] == {
        "type": "list",
        "member": {"shape": "Bucket", "locationName": "Bucket"},
    }
    assert shapes["Bucket"]["type"] == "structure"
    assert list(shapes["Bucket"]["members"]) == [
        "Name",
        "CreationDate",
        "BucketRegion",
        "BucketArn",
    ]
    assert [
        shapes["Bucket"]["members"][name]["shape"]
        for name in shapes["Bucket"]["members"]
    ] == [
        "BucketName",
        "CreationDate",
        "BucketRegion",
        "S3RegionalOrS3ExpressBucketArnString",
    ]
    assert shapes["Owner"]["type"] == "structure"
    assert list(shapes["Owner"]["members"]) == ["DisplayName", "ID"]
    assert [
        shapes["Owner"]["members"][name]["shape"]
        for name in shapes["Owner"]["members"]
    ] == ["DisplayName", "ID"]
    assert shapes["CreationDate"] == {"type": "timestamp"}
    assert shapes["DisplayName"] == {"type": "string"}
    assert shapes["ID"] == {"type": "string"}
    assert shapes["S3RegionalOrS3ExpressBucketArnString"] == {
        "type": "string",
        "max": 128,
        "min": 1,
        "pattern": "arn:[^:]+:(s3|s3express):.*",
    }


def verify_registry(data: dict[str, object] | None = None) -> None:
    if data is None:
        data = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    matches = [
        entry for entry in data["operation"]
        if entry["name"] == "ListBuckets"
    ]
    assert len(matches) == 1, "ListBuckets registry entry is not unique"
    entry = matches[0]
    expected = {
        "tier": "core",
        "provider": "buckets",
        "family": "paginated_rest_xml_read",
        "public_provider": "Flyology.Object_Storage.Client.Buckets",
        "codec": "strict_bounded_rest_xml_and_singleton_headers",
        "public_name": "List_Page",
        "absence": (
            "no dedicated absence variant and no ListBuckets-specific "
            "absence classification; a completed non-200 response remains "
            "a structured typed S3 rejection"
        ),
        "errors": [
            "authentication",
            "authorization",
            "invalid_request",
            "unavailable_or_retryable",
            "corrupt_or_invalid_response",
        ],
        "certainty": "read_only",
        "reconciliation": (
            "not applicable; every bounded page is an independent service "
            "snapshot, continuation tokens remain opaque, and no request "
            "or cross-page snapshot is retried automatically"
        ),
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
        "qualification": "list_buckets",
        "ada_symbols": [
            "Prepare_List_Buckets",
            "Decode_List_Buckets_Complete_Response",
            "Execute_List_Buckets",
            "List_Buckets_Operation",
            "List_Page",
            "Finish",
        ],
    }
    for key, value in expected.items():
        assert entry[key] == value, f"ListBuckets field changed: {key}"
    assert entry["exclusions"] == [
        (
            "the pinned operation excludes directory buckets; no "
            "directory-bucket compatibility is claimed"
        ),
        (
            "the caller supplies the exact service origin and signing "
            "region; when BucketRegion is present it must match that "
            "regional endpoint, and endpoint discovery or rewriting is "
            "not claimed"
        ),
    ]
    assert entry["evidence"]["backend"] == [
        "tests/src/object_storage_test_cases.adb",
        "sqlite/tests/src/flyology_object_storage_sqlite_tests.adb",
    ]
    assert entry["evidence"]["client"] == [
        "src/flyology-object_storage-s3-buckets.ads",
        "src/flyology-object_storage-s3-buckets.adb",
        "src/flyology-object_storage-client-low_level.ads",
        "src/flyology-object_storage-client-low_level.adb",
        "src/flyology-object_storage-client-buckets.ads",
        "src/flyology-object_storage-client-buckets.adb",
        "tests/src/flyology-object_storage-client-buckets-testing.adb",
        "tools/verify-list-buckets-preparation.py",
        "tests/src/s3_http_socket_corpus.adb",
    ]
    assert entry["evidence"]["server"] == [
        "src/flyology-object_storage-s3-buckets.ads",
        "src/flyology-object_storage-s3-buckets.adb",
        "src/flyology-object_storage-server-s3_applications.adb",
        "tests/src/s3_server_application_corpus.adb",
        "tests/src/s3_http_socket_corpus.adb",
    ]
    assert entry["evidence"]["corpus"] == [
        "tests/src/flyology-object_storage-client-buckets-testing.adb",
        "tests/src/s3_create_session_tls_corpus.adb",
        "tests/src/s3_http_socket_corpus.adb",
        "tests/src/s3_implementation_corpus.adb",
        "tests/src/s3_server_application_corpus.adb",
        "tests/scripts/run-s3-server-slice.sh",
        "docs/qualification/list-buckets.md",
    ]
    assert data["qualification"]["list_buckets"] == [
        [
            "uv",
            "run",
            "--python",
            "3.13",
            "--",
            "tools/verify-list-buckets-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
        [
            "./tools/build-api-docs.sh",
            "/private/tmp/fos-list-buckets-gnatdoc",
        ],
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]


def verify_sources() -> None:
    paths = [
        S3_BUCKETS_SPEC,
        S3_BUCKETS_BODY,
        LOW_SPEC,
        LOW_BODY,
        BUCKETS_SPEC,
        BUCKETS_BODY,
        BUCKETS_TESTING,
        SOCKET,
        SERVER,
        SERVER_TEST,
        BACKEND,
        SQLITE_BACKEND,
        IMPLEMENTATION,
        TLS_CORPUS,
        QUALIFICATION,
    ]
    for path in paths:
        regular(path)
    s3_buckets_spec = S3_BUCKETS_SPEC.read_text(encoding="utf-8")
    s3_buckets_body = S3_BUCKETS_BODY.read_text(encoding="utf-8")
    low_spec = LOW_SPEC.read_text(encoding="utf-8")
    low_body = LOW_BODY.read_text(encoding="utf-8")
    buckets_spec = BUCKETS_SPEC.read_text(encoding="utf-8")
    buckets_body = BUCKETS_BODY.read_text(encoding="utf-8")
    testing = BUCKETS_TESTING.read_text(encoding="utf-8")
    socket = SOCKET.read_text(encoding="utf-8")
    server = SERVER.read_text(encoding="utf-8")
    server_test = SERVER_TEST.read_text(encoding="utf-8")
    backend = BACKEND.read_text(encoding="utf-8")
    sqlite_backend = SQLITE_BACKEND.read_text(encoding="utf-8")
    implementation = IMPLEMENTATION.read_text(encoding="utf-8")
    tls = TLS_CORPUS.read_text(encoding="utf-8")
    docs = QUALIFICATION.read_text(encoding="utf-8")

    for marker in (
        "type List_Buckets_Parameters is record",
        "function Prepare_List_Buckets",
        "type List_Buckets_Outcome_Kind is",
        "function Decode_List_Buckets_Complete_Response",
        "function Execute_List_Buckets",
        "procedure List_Buckets",
    ):
        assert marker in low_spec, (
            f"missing ListBuckets Low_Level API: {marker}"
        )
    assert """\
   type List_Buckets_Parameters is record
      Max_Buckets        : S3.Buckets.Max_Buckets_Value := 10_000;
      Has_Max_Buckets    : Boolean := False;
      Continuation_Token : Ada.Strings.Unbounded.Unbounded_String;
      Has_Continuation_Token : Boolean := False;
      Prefix             : Ada.Strings.Unbounded.Unbounded_String;
      Has_Prefix         : Boolean := False;
      Bucket_Region      : Ada.Strings.Unbounded.Unbounded_String;
   end record;
""" in low_spec, "ListBuckets parameter inventory differs"
    for profile, label in (
        ("""\
   function Prepare_List_Buckets
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Parameters : List_Buckets_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;
""", "prepare profile"),
        ("""\
   type List_Buckets_Outcome_Kind is
     (Buckets_Listed, List_Buckets_Rejected);

   type List_Buckets_Outcome
     (Kind : List_Buckets_Outcome_Kind := List_Buckets_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Buckets_Listed =>
            Result : S3.Buckets.List_Buckets_Result;
         when List_Buckets_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;
""", "outcome profile"),
        ("""\
   function Decode_List_Buckets_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Buckets_Outcome;
""", "decode profile"),
        ("""\
   function Decode_List_Buckets_Complete_Response
     (Response : Flyology.HTTP.Client.Response;
      Payload  : String;
      Prepared : Prepared_Request;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Buckets_Outcome;
""", "complete-response decode profile"),
        ("""\
   function Execute_List_Buckets
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Buckets_Outcome;
""", "execute profile"),
        ("""\
   procedure List_Buckets
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);
""", "composable exchange profile"),
    ):
        assert low_spec.count(profile) == 1, (
            f"ListBuckets Low_Level {label} differs"
        )
    assert """\
   subtype Max_Buckets_Value is Positive range 1 .. 10_000;
   Maximum_Bucket_Region_Length : constant := 63;
   Maximum_Continuation_Token_Length : constant := 1_024;
""" in s3_buckets_spec, "ListBuckets public bounds differ"
    for profile, label in (
        ("""\
   type List_Buckets_Request is record
      Max_Buckets            : Max_Buckets_Value := Max_Buckets_Value'Last;
      Has_Max_Buckets        : Boolean := False;
      Continuation_Token     : Ada.Strings.Unbounded.Unbounded_String;
      Has_Continuation_Token : Boolean := False;
      Prefix                 : Ada.Strings.Unbounded.Unbounded_String;
      Has_Prefix             : Boolean := False;
      Bucket_Region          : Ada.Strings.Unbounded.Unbounded_String;
   end record;
""", "request profile"),
        ("""\
   type Bucket_Entry is record
      Name          : Ada.Strings.Unbounded.Unbounded_String;
      Creation_Date : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Region : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_ARN    : Ada.Strings.Unbounded.Unbounded_String;
   end record;
""", "bucket profile"),
        ("""\
   type Bucket_Owner is record
      Display_Name : Ada.Strings.Unbounded.Unbounded_String;
      ID           : Ada.Strings.Unbounded.Unbounded_String;
   end record;
""", "owner profile"),
        ("""\
   type List_Buckets_Result is record
      Buckets            : Bucket_List;
      Has_Owner          : Boolean := False;
      Owner              : Bucket_Owner;
      Continuation_Token : Ada.Strings.Unbounded.Unbounded_String;
      Has_Continuation_Token : Boolean := False;
      Prefix             : Ada.Strings.Unbounded.Unbounded_String;
      Has_Prefix         : Boolean := False;
   end record;
""", "result profile"),
        ("""\
   function Parse_List_Buckets_Query
     (Query : String) return List_Buckets_Request;
""", "query parser profile"),
        ("""\
   function Parse_List_Buckets
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return List_Buckets_Result;
""", "result parser profile"),
        ("""\
   function Serialize_List_Buckets
     (Value : List_Buckets_Result) return String;
""", "serializer profile"),
    ):
        assert s3_buckets_spec.count(profile) == 1, (
            f"ListBuckets S3.Buckets {label} differs"
        )
    query_parser = between(
        s3_buckets_body,
        "function Parse_List_Buckets_Query",
        "end Parse_List_Buckets_Query;",
        "ListBuckets query parser",
    )
    ordered_once(
        query_parser,
        [
            "Query'Length > Maximum_Query_Length",
            "if Count > 5 then",
            "Number.Value not in Max_Buckets_Value'Range",
            "Maximum_Continuation_Token_Length",
            'Name = "prefix"',
            '"duplicate ListBuckets prefix"',
            "Maximum_Bucket_Region_Length",
            "SigV4_Encoding.Valid_Scope_Segment (Value)",
            'Name = "x-id"',
            'Value /= "ListBuckets"',
            '"unsupported ListBuckets query parameter"',
        ],
        "ListBuckets query parser",
    )
    validator = between(
        s3_buckets_body,
        "procedure Validate (Value : List_Buckets_Result)",
        "end Validate;",
        "ListBuckets result validator",
    )
    ordered_once(
        validator,
        [
            "Value.Buckets.Length > 10_000",
            "Maximum_Continuation_Token_Length",
            "not Value.Has_Owner",
            '"ListBuckets owner lacks presence state"',
        ],
        "ListBuckets result validator",
    )
    result_parser = between(
        s3_buckets_body,
        "function Parse_List_Buckets\n",
        "end Parse_List_Buckets;",
        "ListBuckets result parser",
    )
    ordered_once(
        result_parser,
        [
            "XML.Parse (Document, Handler, Limits);",
            "Validate (Handler.Value);",
            '"malformed ListBuckets XML"',
        ],
        "ListBuckets result parser",
    )
    serializer = between(
        s3_buckets_body,
        "function Serialize_List_Buckets\n",
        "end Serialize_List_Buckets;",
        "ListBuckets serializer",
    )
    ordered_once(
        serializer,
        [
            "Validate (Value);",
            '"<ListAllMyBucketsResult xmlns=""http://s3.amazonaws.com/doc/"',
            '"<Owner>"',
            '"<Buckets>"',
            '"CreationDate"',
            '"BucketRegion"',
            '"BucketArn"',
            '"ContinuationToken"',
            '"Prefix"',
            '"</ListAllMyBucketsResult>"',
        ],
        "ListBuckets serializer",
    )
    preparer = between(
        low_body,
        "function Prepare_List_Buckets",
        "end Prepare_List_Buckets;",
        "ListBuckets preparer",
    )
    ordered_once(
        preparer,
        [
            "S3.Buckets.Maximum_Continuation_Token_Length",
            '"MaxBuckets"',
            '"ContinuationToken"',
            '"Prefix"',
            '"BucketRegion"',
            "Prepare_Model_Request",
            "Result.Operation := List_Buckets_Operation;",
            "Result.Requested_List_Buckets_Max :=",
            "Result.Requested_List_Buckets_Prefix := Parameters.Prefix;",
            "Result.Requested_List_Buckets_Has_Prefix :=",
            "Result.Requested_List_Buckets_Region := "
            "Parameters.Bucket_Region;",
        ],
        "ListBuckets preparer",
    )
    complete_decoder = between(
        low_body,
        "function Decode_List_Buckets_Complete_Response",
        "end Decode_List_Buckets_Complete_Response;",
        "ListBuckets complete decoder",
    )
    ordered_once(
        complete_decoder,
        [
            "Flyology.HTTP.Client.Header_Count (Response, Name);",
            '"invalid ListBuckets response header multiplicity"',
            "Prepared.Operation /= List_Buckets_Operation",
            "Decode_List_Buckets_Response",
            'Singleton_Header ("x-amz-request-id")',
            'Singleton_Header ("x-amz-id-2")',
            "Natural (Page.Buckets.Length) >",
            "Natural (Prepared.Requested_List_Buckets_Max)",
            "Prepared.Requested_List_Buckets_Has_Prefix",
            "US.To_String (Page.Prefix) /= Requested_Prefix",
            '"ListBuckets response does not match prepared request"',
            "for Bucket of Page.Buckets loop",
            "Name'Length < Requested_Prefix'Length",
            "Bucket_Region /= Requested_Region",
            '"ListBuckets response does not match prepared "',
            '"request";',
        ],
        "ListBuckets complete decoder",
    )
    for marker in (
        "type List_Buckets_Result_Kind is",
        "type List_Buckets_Result",
        "type List_Buckets_Operation",
        "procedure List_Page",
        "function List_Page",
        "procedure Finish",
    ):
        assert marker in buckets_spec, f"missing ListBuckets API: {marker}"
    assert """\
   type List_Buckets_Result
     (Kind : List_Buckets_Result_Kind := List_Buckets_Exchange_Failed)
   is record
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when List_Buckets_Response_Available =>
            Response : Low_Level.List_Buckets_Outcome;
         when List_Buckets_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;
""" in buckets_spec, "ListBuckets public result profile differs"
    assert """\
   type List_Buckets_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Response_Body_Sink with private;
""" in buckets_spec, "ListBuckets public operation profile differs"
    assert """\
   procedure List_Page
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Parameters : Low_Level.List_Buckets_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out List_Buckets_Operation)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);
""" in buckets_spec, "ListBuckets restart profile differs"
    assert """\
   function List_Page
     (Set      : not null access Flyology.Operations.Completion_Set'Class;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Parameters : Low_Level.List_Buckets_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Buckets_Operation;
""" in buckets_spec, "ListBuckets constructor profile differs"
    assert """\
   procedure Finish
     (Operation : in out List_Buckets_Operation;
      Result    : out List_Buckets_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);
""" in buckets_spec, "ListBuckets Finish profile differs"
    normalization = between(
        buckets_body,
        "function Normalize_List_Buckets_Response",
        "end Normalize_List_Buckets_Failure;",
        "ListBuckets normalization",
    )
    assert """\
      Failure : constant Failure_Reason :=
        (if Admission /= HTTP_Client.Response_Observed
         then Corrupt_Or_Invalid_Response
         elsif Value.Kind = Low_Level.Buckets_Listed
         then No_Failure
         elsif Value.Status = 400
           and then Code in "InvalidArgument" | "InvalidRequest"
         then Invalid_Request
         elsif Value.Status = 501 and then Code = "NotImplemented"
         then Invalid_Request
         elsif Value.Status = 401 and then Code = "InvalidAccessKeyId"
         then Authentication_Failed
         elsif Value.Status = 403 and then Code = "AccessDenied"
         then Authorization_Failed
         elsif (Value.Status = 409 and then Code = "OperationAborted")
           or else (Value.Status = 429 and then Code = "SlowDown")
           or else (Value.Status = 500 and then Code = "InternalError")
           or else (Value.Status = 502 and then Code = "BadGateway")
           or else (Value.Status = 503 and then Code = "SlowDown")
           or else (Value.Status = 504 and then Code = "RequestTimeout")
         then Unavailable_Or_Retryable
         else Corrupt_Or_Invalid_Response);
""" in normalization, "ListBuckets response normalization differs"
    ordered_once(
        normalization,
        [
            "function Normalize_List_Buckets_Response",
            "function Normalize_List_Buckets_Failure",
            "Failure     => Failed_Reason (Kind)",
            "HTTP_Result => Kind",
        ],
        "ListBuckets normalization",
    )
    failure_helper = between(
        testing,
        "procedure Check_List_Buckets_Failure",
        "end Check_List_Buckets_Failure;",
        "ListBuckets failure helper",
    )
    assert """\
      Expected_Failure : constant Failure_Reason :=
        (case Kind is
            when HTTP_Client.Pre_Admission_Rejected => Invalid_Request,
            when HTTP_Client.Cancelled => Cancelled,
            when HTTP_Client.Timed_Out => Timed_Out,
            when HTTP_Client.Client_Unavailable => Client_Unavailable,
            when HTTP_Client.Connection_Failed => Connection_Failed,
            when HTTP_Client.Transport_Failed => Transport_Failed,
            when HTTP_Client.Request_Source_Failed => Request_Source_Failed,
            when HTTP_Client.Response_Body_Too_Large => Response_Too_Large,
            when HTTP_Client.Response_Invalid |
                 HTTP_Client.Response_Sink_Failed =>
              Corrupt_Or_Invalid_Response,
            when HTTP_Client.Response_Complete =>
              raise Program_Error with "complete response is not a failure");
""" in failure_helper, "ListBuckets failure mapping differs"
    corpus = between(
        testing,
        "procedure Check_List_Buckets_Result_Corpus is",
        "end Check_List_Buckets_Result_Corpus;",
        "ListBuckets normalization corpus",
    )
    assert """\
      Failure_Kinds : constant Failure_Kind_Array :=
        (HTTP_Client.Pre_Admission_Rejected,
         HTTP_Client.Cancelled,
         HTTP_Client.Timed_Out,
         HTTP_Client.Client_Unavailable,
         HTTP_Client.Connection_Failed,
         HTTP_Client.Transport_Failed,
         HTTP_Client.Request_Source_Failed,
         HTTP_Client.Response_Invalid,
         HTTP_Client.Response_Body_Too_Large,
         HTTP_Client.Response_Sink_Failed);
""" in corpus, "ListBuckets failure inventory differs"
    ordered_once(
        corpus,
        [
            'Check_List_Buckets_Response (200, "", No_Failure);',
            '(400, "InvalidArgument", Invalid_Request);',
            '(400, "InvalidRequest", Invalid_Request);',
            '(401, "InvalidAccessKeyId", Authentication_Failed);',
            '(403, "AccessDenied", Authorization_Failed);',
            '(409, "OperationAborted", Unavailable_Or_Retryable);',
            '(429, "SlowDown", Unavailable_Or_Retryable);',
            '(500, "InternalError", Unavailable_Or_Retryable);',
            '(502, "BadGateway", Unavailable_Or_Retryable);',
            '(503, "SlowDown", Unavailable_Or_Retryable);',
            '(504, "RequestTimeout", Unavailable_Or_Retryable);',
            '(501, "NotImplemented", Invalid_Request);',
            '(400, "", Corrupt_Or_Invalid_Response);',
            "HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted",
            "for Kind of Failure_Kinds loop",
            "for Admission in HTTP_Client.Admission_Certainty loop",
            "Check_List_Buckets_Failure (Kind, Admission);",
        ],
        "ListBuckets normalization corpus",
    )

    server_cancel = between(
        socket,
        "if Await_Cancellation then",
        "elsif Response'Length = 0 then",
        "shared cancellation server",
    )
    for block in (
        """\
                  when List_Buckets_Cancellation =>
                     if Cancellation_Round = 1 then
                        List_Buckets_Admission_Native.Request;
                     else
                        List_Buckets_Admission_Lightweight.Request;
                     end if;
""",
        """\
                     when List_Buckets_Cancellation =>
                        if Cancellation_Round = 1 then
                           List_Buckets_Drain_Native.Request;
                        else
                           List_Buckets_Drain_Lightweight.Request;
                        end if;
""",
    ):
        assert server_cancel.count(block) == 1, (
            "ListBuckets server readiness mapping differs"
        )
    admission = once(
        server_cancel,
        "List_Buckets_Admission_Native.Request;",
        "ListBuckets server admission",
    )
    receive = once(
        server_cancel,
        "Sockets.Receive (Peer, Buffer, Last, Timeout => 5.0);",
        "ListBuckets server cancellation receive",
    )
    eof_check = once(
        server_cancel,
        '"ListBuckets cancel peer sent data before drain"',
        "ListBuckets server EOF/reset check",
    )
    drain_calls = [
        once(
            server_cancel,
            "\n                        Request_Drain;\n",
            "ListBuckets exceptional server drain call",
        ),
        once(
            server_cancel,
            "\n               Request_Drain;\n",
            "ListBuckets terminal server drain call",
        ),
    ]
    assert admission < receive < eof_check < drain_calls[-1], (
        "ListBuckets server admission/drain order changed"
    )
    assert """\
         Serve
           ("", "GET",
            "/?bucket-region=us-east-1&max-buckets=1&prefix=socket-",
            Await_Cancellation => True,
            Cancellation_Kind => List_Buckets_Cancellation,
            Cancellation_Round => Round);
         Serve
           (HTTP_Response ("200 OK", List_Buckets_XML),
            "GET",
            "/?bucket-region=us-east-1&max-buckets=1&prefix=socket-",
            Fragmented => True);
""" in socket, "ListBuckets cancellation/restart exchanges differ"
    for marker, expected_count in (
        ("List_Buckets_Admission_Native", 3),
        ("List_Buckets_Admission_Lightweight", 3),
        ("List_Buckets_Drain_Native", 3),
        ("List_Buckets_Drain_Lightweight", 3),
    ):
        assert socket.count(marker) == expected_count, (
            f"ListBuckets readiness count changed: {marker}"
        )
    assert socket.count("List_Buckets_Cancellation") == 5
    lifecycle = between(
        socket,
        "               if Round = 1 then\n"
        "                  List_Buckets_Admission_Native.Wait_Source",
        '"same-operation ListBuckets restart mismatch"',
        "ListBuckets client lifecycle",
    )
    assert """\
               if Round = 1 then
                  List_Buckets_Admission_Native.Wait_Source
                    (Admission_FD, Admission_Requested);
                  List_Buckets_Drain_Native.Wait_Source
                    (Drain_FD, Drain_Requested);
               elsif Round = 2 then
                  List_Buckets_Admission_Lightweight.Wait_Source
                    (Admission_FD, Admission_Requested);
                  List_Buckets_Drain_Lightweight.Wait_Source
                    (Drain_FD, Drain_Requested);
               else
                  raise Program_Error with
                    "invalid ListBuckets cancellation round";
               end if;
""" in lifecycle, "ListBuckets client round selection differs"
    assert """\
               if Admission_Requested
                 or else Drain_Requested
                 or else Admission_FD < 0
                 or else Drain_FD < 0
               then
                  raise Program_Error with "stale ListBuckets readiness";
               end if;
""" in lifecycle, "ListBuckets stale readiness check differs"
    assert "Cancel_Set : aliased Operations.Completion_Set (5);" in lifecycle
    cancellation = between(
        lifecycle,
        "Operations.Wait_Some (Cancel_Set, Completed_Batch);",
        "Flyology.IO.Finish (Drain_Ready);",
        "ListBuckets cancellation phase",
    )
    ordered_once(
        cancellation,
        [
            "Operations.Wait_Some (Cancel_Set, Completed_Batch);",
            "Completed_Batch.Count = 0",
            "not Operations.Is_Terminal (Admission_Ready)",
            "not Operations.Is_Active (Drain_Ready)",
            "not Operations.Is_Active (Cancel_Operation)",
            "Flyology.IO.Finish (Admission_Ready);",
            "Operations.Cancel (Cancel_Operation);",
            "Operations.Wait_All (Cancel_Set);",
            "Finish (Cancel_Operation, Cancel_Result);",
            "HTTP_Client.Possibly_Admitted",
            '"ListBuckets drain was not acknowledged"',
            "Flyology.IO.Finish (Drain_Ready);",
        ],
        "ListBuckets cancellation phase",
    )
    restart = between(
        lifecycle,
        "Token => Changed_Token'Access",
        '"same-operation ListBuckets restart mismatch"',
        "ListBuckets restart phase",
    )
    ordered_once(
        restart,
        [
            "Token => Changed_Token'Access",
            '"ListBuckets restart changed a retained owner"',
            '"ListBuckets accepted changed retained owner"',
            "Token => Cancel_Token'Access",
            "Operations.Wait_All (Cancel_Set);",
            "Finish (Cancel_Operation, Cancel_Result);",
            "HTTP_Client.Response_Observed",
            '"same-operation ListBuckets restart mismatch"',
        ],
        "ListBuckets restart phase",
    )
    for text, markers in (
        (server, ("when List_Buckets =>", "Buckets.Parse_List_Buckets_Query",
                  "Store.List_Buckets", "Buckets.Serialize_List_Buckets")),
        (server_test, ("ListBuckets first page metadata mismatch",
                       "ListBuckets continuation page mismatch")),
        (backend, ("Store.List_Buckets",
                   "ListBuckets continuation token was not prefix-bound")),
        (sqlite_backend, ("Store.List_Buckets",
                          "SQLite backend bucket listing")),
        (implementation, ("Client_Buckets.List_Page",
                           "S3 implementation rejected ListBuckets")),
        (tls, ("Low_Level.Prepare_List_Buckets",
               "CreateSession accepted a ListBuckets prepared request")),
    ):
        for marker in markers:
            assert marker in text, f"missing ListBuckets evidence: {marker}"
    assert all(len(line) <= 79 for line in docs.splitlines())
    normalized_docs = " ".join(docs.split())
    for marker in (
        "one hidden Flyology HTTP child",
        "Each page is an independent service snapshot",
        "transport drain acknowledgement",
        "retained-owner substitution rejection",
        "repository-owned warning",
    ):
        assert marker in normalized_docs, (
            f"missing ListBuckets prose: {marker}"
        )


def verify_negative_registry() -> None:
    original = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    index = next(
        position for position, entry in enumerate(original["operation"])
        if entry["name"] == "ListBuckets"
    )
    for label, key, value in (
        ("legacy absence", "absence", "legacy_preserved"),
        ("legacy errors", "errors", ["legacy_preserved"]),
        ("unresolved decision", "human_decisions_resolved", False),
        ("wrong public name", "public_name", "List_Buckets"),
        ("wrong certainty", "certainty", "possibly_applied"),
        ("missing qualification", "qualification", ""),
    ):
        candidate = copy.deepcopy(original)
        candidate["operation"][index][key] = value
        try:
            verify_registry(candidate)
        except AssertionError:
            pass
        else:
            raise AssertionError(f"ListBuckets {label} was accepted")


def main() -> None:
    verify_model(load_model())
    verify_registry()
    verify_sources()
    verify_negative_registry()
    print("ListBuckets preparation evidence: OK")


if __name__ == "__main__":
    main()
