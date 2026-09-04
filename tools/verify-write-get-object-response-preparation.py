#!/usr/bin/env python3
"""Fail-closed source oracle for WriteGetObjectResponse dispatch coverage."""

from __future__ import annotations

import copy
import pathlib
import tomllib


ROOT = pathlib.Path(__file__).resolve().parents[1]
REGISTRY_PATH = ROOT / "coverage" / "s3-operations.toml"
SERVER_SPEC_PATH = ROOT / "src" / (
    "flyology-object_storage-server-s3_applications.ads"
)
SERVER_BODY_PATH = ROOT / "src" / (
    "flyology-object_storage-server-s3_applications.adb"
)
PROVIDER_SPEC_PATH = ROOT / "src" / (
    "flyology-object_storage-server-object_lambda_responses.ads"
)
CORPUS_PATH = ROOT / "tests" / "src" / "s3_server_application_corpus.adb"
MODEL_VERIFIER_PATH = ROOT / "tests" / "scripts" / (
    "verify-write-get-object-response-model.py"
)
PROSE_PATH = ROOT / "docs" / "qualification" / (
    "write-get-object-response.md"
)
CLIENT_PATHS = [
    ROOT / "src" / "flyology-object_storage-client-low_level.ads",
    ROOT / "src" / "flyology-object_storage-client-low_level.adb",
    ROOT / "src" / "flyology-object_storage-client-objects.ads",
    ROOT / "src" / "flyology-object_storage-client-objects.adb",
]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def require_in_order(source: str, fragments: list[str], label: str) -> None:
    cursor = 0
    for fragment in fragments:
        position = source.find(fragment, cursor)
        require(position >= 0, f"{label}: missing {fragment!r}")
        cursor = position + len(fragment)


def unique_region(source: str, start: str, end: str, label: str) -> str:
    require(source.count(start) == 1, f"{label}: start boundary")
    first = source.index(start)
    finish = source.find(end, first + len(start))
    require(finish >= 0, f"{label}: end boundary")
    return source[first:finish]


def replace_once(source: str, old: str, new: str, label: str) -> str:
    require(source.count(old) == 1, f"{label}: mutation occurrence")
    result = source.replace(old, new, 1)
    require(result != source, f"{label}: candidate unchanged")
    return result


def mutate_route(source: str, old: str, new: str, label: str) -> str:
    route = unique_region(
        source,
        "if Operation = Write_Get_Object_Response then",
        "if Operation = Put_Multipart_Part and then Has_Encryption_Header",
        f"{label} route",
    )
    changed_route = replace_once(route, old, new, label)
    return replace_once(source, route, changed_route, f"{label} scope")


def operation(registry: dict) -> dict:
    entries = [
        item for item in registry["operation"]
        if item["name"] == "WriteGetObjectResponse"
    ]
    require(len(entries) == 1, "WriteGetObjectResponse registry uniqueness")
    return entries[0]


EXPECTED_LANE = [
    ["uv", "run", "--python", "3.13", "--",
     "tools/verify-write-get-object-response-preparation.py"],
    ["uv", "run", "--python", "3.13", "--",
     "tests/scripts/verify-write-get-object-response-model.py"],
    ["uv", "run", "--python", "3.13", "--",
     "tools/test-s3-operation-registry.py"],
    ["@tests", "alr", "-n", "build"],
    ["@tests", "./bin/s3_server_application_corpus"],
    ["./tools/verify-coverage.sh"],
    ["./tools/build-api-docs.sh",
     "{repository}/build/gnatdoc/write-get-object-response"],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]


def assert_registry(registry: dict) -> None:
    entry = operation(registry)
    require(entry["public_name"] == "Deliver", "public dispatcher name")
    require(entry["public_surface"] == "server", "public dispatcher surface")
    require(entry["public_provider"] ==
            "Flyology.Object_Storage.Server.Object_Lambda_Responses",
            "public dispatcher provider")
    require(entry["codec"] ==
            "strict_object_lambda_callback_stream",
            "WriteGetObjectResponse codec")
    require(entry["coverage"] == {
        "backend": "covered",
        "client": "partial",
        "server": "covered",
        "corpus": "covered",
    }, "WriteGetObjectResponse coverage")
    require(entry["provenance"] == {
        "backend": "handwritten",
        "client": "generated",
        "server": "handwritten",
        "tests": "handwritten",
    }, "WriteGetObjectResponse provenance")
    require(entry["evidence"]["backend"] == [
        "src/flyology-object_storage-server-object_lambda_responses.ads",
        "src/flyology-object_storage-server-s3_applications.ads",
        "src/flyology-object_storage-server-s3_applications.adb",
        "tests/src/s3_server_application_corpus.adb",
    ], "backend evidence")
    require(entry["evidence"]["server"] == [
        "src/flyology-object_storage-server-object_lambda_responses.ads",
        "src/flyology-object_storage-server-s3_applications.ads",
        "src/flyology-object_storage-server-s3_applications.adb",
        "tests/src/s3_server_application_corpus.adb",
    ], "server evidence")
    require(entry["evidence"]["corpus"] == [
        "tests/scripts/verify-write-get-object-response-model.py",
        "tools/verify-write-get-object-response-preparation.py",
        "docs/qualification/write-get-object-response.md",
        "tests/src/s3_server_application_corpus.adb",
    ], "corpus evidence")
    require("one synchronous caller-provider dispatch" in entry["certainty"],
            "single dispatch certainty")
    require("Delivered requires the provider to consume the body through EOF"
            in entry["certainty"], "complete delivery certainty")
    require("Invalid_Token is conclusive only before token consumption" in
            entry["certainty"], "pre-admission token certainty")
    require("cancellation or timeout after possible admission leaves delivery"
            in entry["certainty"], "cancellation certainty")
    require("Delivery_Failed or cancellation or timeout after possible "
            "admission leaves delivery outcome unknown" in
            entry["certainty"], "unknown delivery certainty")
    require("never retries the single-use token automatically" in
            entry["certainty"],
            "no-replay certainty")
    require("caller provider owns token and pending-response state" in
            entry["reconciliation"], "provider-owned reconciliation")
    exclusions = " ".join(entry["exclusions"])
    for fact in [
        "no Low_Level or Objects client request",
        "exact POST /WriteGetObjectResponse with no query",
        "secure HTTPS",
        "checksum one-of and decoded lengths",
        "atomic single-use consumption",
        "no token store, scheduler, task, allocation policy",
        "never calls the bucket or object persistence backend",
        "empty 200 callback acknowledgement",
    ]:
        require(fact in exclusions, f"missing exclusion: {fact}")
    require(registry["qualification"]["write_get_object_response"] ==
            EXPECTED_LANE, "WriteGetObjectResponse qualification lane")
    require(entry["ada_symbols"] == [
        "Provider", "Deliver", "Response_Description", "Delivery_Result",
    ], "public dispatcher symbol inventory")


def assert_sources(provider_spec: str, server_spec: str, server_body: str,
                   corpus: str, model_verifier: str, prose: str,
                   client: str) -> None:
    require("validated caller-dispatched WriteGetObjectResponse routing" in
            server_spec, "server specification boundary")
    require_in_order(server_spec, [
        "@formal Object_Lambda_Response_Provider",
        "Object_Lambda_Response_Provider :",
        "Object_Lambda_Responses.Provider_Access := null;",
    ], "optional provider generic formal")
    require("Write_Get_Object_Response" not in client,
            "public client API invented")
    require("WriteGetObjectResponse" not in client,
            "generated operation leaked into public client")

    require_in_order(provider_spec, [
        "package Flyology.Object_Storage.Server.Object_Lambda_Responses is",
        "type Body_Length (Is_Known : Boolean := False) is record",
        "Bytes : Byte_Count;",
        "type Optional_Text is record",
        "type Forwarded_Field is",
        "Status_Code,",
        "Checksum_CRC32,",
        "Checksum_XXHASH128,",
        "Object_Lock_Mode,",
        "SSE_KMS_Key_ID,",
        "Bucket_Key_Enabled);",
        "type Response_Description is record",
        "Content_Length : Body_Length",
        "Fields          : Forwarded_Field_Set",
        "Metadata        : Metadata_Entry_Vectors.Vector;",
        "type Delivery_Result is",
        "(Delivered, Invalid_Token, Delivery_Failed);",
        "type Provider is limited interface;",
        "type Response_Body_Source is limited interface;",
        "procedure Read",
        "Item         : in out Response_Body_Source;",
        "Data         : out Ada.Streams.Stream_Element_Array;",
        "Last         : out Ada.Streams.Stream_Element_Offset;",
        "Finished     : out Boolean;",
        "procedure Deliver",
        "Principal     : String;",
        "Request_Route : String;",
        "Request_Token : String;",
        "Response      : Response_Description;",
        "Source        : in out Response_Body_Source'Class;",
        "Cancellation  : access Flyology.Cancellation.Token;",
        "Deadline      : Ada.Real_Time.Time;",
        "Result        : out Delivery_Result) is abstract;",
    ], "public synchronous dispatch contract")
    for fact in [
        "must copy retained",
        "values and must not retain or outlive the body source",
        "Field identity is structurally typed",
        "field values remain exact validated",
        "text. Cancellation and timeout propagate",
        "atomic single-use",
        "consumption, and delivery to the pending GetObject response",
        "The server never retries a callback automatically",
        "EOF before returning Delivered",
    ]:
        require(fact in provider_spec, f"provider ownership fact: {fact}")
    require(provider_spec.count("@enum ") == 44,
            "provider enum documentation inventory")
    require(provider_spec.count("@field ") == 9,
            "provider field documentation inventory")
    require(provider_spec.count("@param ") == 15,
            "provider parameter documentation inventory")
    require("Flyology.Object_Storage.Backends" not in provider_spec,
            "public provider leaked storage backend dependency")

    routing = unique_region(
        server_body,
        "Write_Get_Object_Response_Target : constant String :=",
        "Parsed      : constant Requests.Target_Result :=",
        "WriteGetObjectResponse routing",
    )
    require_in_order(routing, [
        'Write_Get_Object_Response_Target : constant String :=',
        '"/WriteGetObjectResponse"',
        "Looks_Like_Write_Get_Object_Response : constant Boolean :=",
        "Target_Text'Length >= Write_Get_Object_Response_Target'Length",
        "Write_Get_Object_Response_Target'Length) = '?'",
    ], "exact WriteGetObjectResponse target")
    require_in_order(server_body, [
        "and then not Looks_Like_Write_Get_Object_Response",
        "if Looks_Like_Write_Get_Object_Response then",
        "Operation := Write_Get_Object_Response",
        "Apps.Configure_Route",
        "Apps.Seal_Route (X)",
        "Authentication.Verify_Request",
        "Apps.Set_Principal",
        "if Operation = Write_Get_Object_Response then",
    ], "authentication before callback validation")

    route = unique_region(
        server_body,
        "if Operation = Write_Get_Object_Response then",
        "if Operation = Put_Multipart_Part and then Has_Encryption_Header",
        "WriteGetObjectResponse route",
    )
    require_in_order(route, [
        'Apps.Request_Header_Count (X, "x-amz-request-route")',
        'Apps.Request_Header_Count (X, "x-amz-request-token")',
        'Apps.Request_Header_Count (X, "host")',
        'Apps.Request_Header (X, "x-amz-request-route")',
        'Apps.Request_Header (X, "x-amz-request-token")',
        'Apps.Request_Header (X, "host")',
        "Route'Length > 0",
        "Host'Length > Route'Length",
        'Route & "."',
        'Method /= "POST"',
        "Target_Text /= Write_Get_Object_Response_Target",
        "Apps.Request_Scheme (X)",
        "Flyology.HTTP.Secure_HTTPS",
        "Auth.Payload_Hash",
        "S3.SigV4.Unsigned_Payload",
        "Route_Count /= 1",
        "Token_Count /= 1",
        "Host_Count /= 1",
        "Route'Length = 0",
        "Token'Length = 0",
        "Valid_Header_Text",
        "not Valid_Header_Text (Token)",
        "not Host_Matches_Route",
        "Apps.Apply_Body_Policy (X, Accepted)",
        "Parse_Write_Response (Length, Response, Response_Valid)",
        "Length.Kind = Backends.Unknown",
        "Drain_Write_Response_Body (Source)",
        "Response_Valid := Source.Observed = 0",
        "Drain_Write_Response_Body (Source)",
        "Object_Lambda_Response_Provider = null",
        '501, "NotImplemented"',
        "Deliver_Write_Response",
        "Object_Lambda_Responses.Delivered",
        "Source.Completed",
        'Apps.Respond (X, 200, "", "")',
        "Pre_Admission_Invalid_Token",
        "Result = Object_Lambda_Responses.Invalid_Token",
        "Source.Observed = 0",
        "Best_Effort_Drain_Write_Response_Body (Source)",
        '400, "ValidationError"',
        '500, "InternalError"',
        "return;",
    ], "strict WriteGetObjectResponse dispatch")
    for name in [
        "x-amz-request-route",
        "x-amz-request-token",
    ]:
        require(route.count(f'Apps.Request_Header_Count (X, "{name}")') == 1,
                f"{name} singleton validation count")
        require(route.count(f'Apps.Request_Header (X, "{name}")') >= 1,
                f"{name} value validation")
    for forbidden in ["Store.", "Apps.Response_Header", "Persist"]:
        require(forbidden not in route,
                f"WriteGetObjectResponse route contains {forbidden!r}")

    body_policy = unique_region(
        server_body,
        "Apps.Configure_Route",
        "Apps.Seal_Route (X)",
        "WriteGetObjectResponse body policy",
    )
    require(
        "(if Operation = Write_Get_Object_Response\n"
        "          then Apps.Stream_Body" in body_policy,
        "streaming authenticated callback body",
    )
    require("Apps.Required_Authentication" in body_policy,
            "authenticated callback body")

    request_source = unique_region(
        server_body,
        "package body Request_IO is",
        "end Request_IO;",
        "request body source",
    )
    require_in_order(request_source, [
        "overriding procedure Read",
        "if Token /= null and then Token.Requested then",
        "raise Flyology.Cancellation.Operation_Cancelled",
        "Apps.Read_Body",
    ], "request body source cancellation")

    parser = unique_region(
        server_body,
        "function Write_Response_Header_Name",
        "function Read_Document",
        "WriteGetObjectResponse parser",
    )
    required_headers = [
        "x-amz-fwd-status", "x-amz-fwd-error-code",
        "x-amz-fwd-error-message", "x-amz-fwd-header-accept-ranges",
        "x-amz-fwd-header-cache-control",
        "x-amz-fwd-header-content-disposition",
        "x-amz-fwd-header-content-encoding",
        "x-amz-fwd-header-content-language",
        "x-amz-fwd-header-content-range",
        "x-amz-fwd-header-content-type",
        "x-amz-fwd-header-x-amz-checksum-crc32",
        "x-amz-fwd-header-x-amz-checksum-crc32c",
        "x-amz-fwd-header-x-amz-checksum-crc64nvme",
        "x-amz-fwd-header-x-amz-checksum-sha1",
        "x-amz-fwd-header-x-amz-checksum-sha256",
        "x-amz-fwd-header-x-amz-checksum-sha512",
        "x-amz-fwd-header-x-amz-checksum-md5",
        "x-amz-fwd-header-x-amz-checksum-xxhash64",
        "x-amz-fwd-header-x-amz-checksum-xxhash3",
        "x-amz-fwd-header-x-amz-checksum-xxhash128",
        "x-amz-fwd-header-x-amz-delete-marker", "x-amz-fwd-header-etag",
        "x-amz-fwd-header-expires",
        "x-amz-fwd-header-x-amz-expiration",
        "x-amz-fwd-header-last-modified",
        "x-amz-fwd-header-x-amz-missing-meta",
        "x-amz-fwd-header-x-amz-object-lock-mode",
        "x-amz-fwd-header-x-amz-object-lock-legal-hold",
        "x-amz-fwd-header-x-amz-object-lock-retain-until-date",
        "x-amz-fwd-header-x-amz-mp-parts-count",
        "x-amz-fwd-header-x-amz-replication-status",
        "x-amz-fwd-header-x-amz-request-charged",
        "x-amz-fwd-header-x-amz-restore",
        "x-amz-fwd-header-x-amz-server-side-encryption",
        "x-amz-fwd-header-x-amz-storage-class",
        "x-amz-fwd-header-x-amz-tagging-count",
        "x-amz-fwd-header-x-amz-version-id",
    ]
    for header in required_headers:
        require(parser.count(f'"{header}"') == 1,
                f"modeled forwarded header mapping: {header}")
    require_in_order(parser, [
        '"x-amz-fwd-header-x-amz-server-side-encryption-customer-"',
        '"algorithm"',
        '"x-amz-fwd-header-x-amz-server-side-encryption-aws-kms-"',
        '"key-id"',
        '"x-amz-fwd-header-x-amz-server-side-encryption-customer-"',
        '"key-md5"',
        '"x-amz-fwd-header-x-amz-server-side-encryption-bucket-key-"',
        '"enabled"',
    ], "wrapped forwarded-header mapping")
    require_in_order(parser, [
        "Valid_Write_Response_Status",
        "Valid_Write_Response_Error_Code",
        "Valid_Write_Response_ISO_8601",
        "S3.Wire_Core.Valid_Base64",
        "Checksum_Count > 1",
        'Starts_With (Name, "x-amz-fwd-")',
        "not Known_Forwarded_Header (Name)",
        'Starts_With (Name, "x-amz-meta-")',
        "Response.Metadata.Append",
        "Length.Kind = Backends.Unknown or else Length.Bytes = 0",
        "Has_Error and then (Successful or else not Empty_Body)",
        "procedure Drain_Write_Response_Body",
        "procedure Best_Effort_Drain_Write_Response_Body",
        "when others =>",
        "null;",
        "procedure Deliver_Write_Response",
        "if Provider = null then",
        "Object_Lambda_Responses.Deliver",
    ], "complete forwarded-control validation")
    require(
        "return Value'Length > 0 and then Valid_Header_Text (Value);"
        in parser,
        "modeled error code text validation",
    )

    corpus_region = unique_region(
        corpus,
        'Route : constant String := "route-id";',
        'Document : constant String :=\n        "<ObjectEncryption "',
        "WriteGetObjectResponse corpus",
    )
    signing_helper = unique_region(
        corpus,
        "function Signed_Request\n",
        "end Signed_Request;",
        "signed request helper",
    )
    require_in_order(signing_helper, [
        "Extra_Header_Count",
        "Headers : SigV4.Name_Value_Array",
        "Headers (3 + Index) := SigV4.Pair",
        "SigV4.Sign",
        "Extra_Headers",
    ], "signed callback control headers")
    require_in_order(corpus_region, [
        'Route : constant String := "route-id";',
        'Token : constant String := "token-id";',
        '"x-amz-request-route: " & Route',
        '"x-amz-request-token: " & Token',
        "function Write_Response",
        'Target        : String := "/WriteGetObjectResponse";',
        "Payload_Hash  : String := SigV4.Unsigned_Payload;",
        "Flyology.HTTP.Secure_HTTPS",
        "Signed_Request",
        "Method, Target, Payload, Extra",
        '"501 Not Implemented"',
        "not Has (Value, Token)",
        '"WriteGetObjectResponse did not reject callback admission"',
        '"WriteGetObjectResponse did not drain its rejected body"',
        '"WriteGetObjectResponse accepted a missing route"',
        '"WriteGetObjectResponse accepted a missing token"',
        '"WriteGetObjectResponse accepted a duplicate route"',
        '"WriteGetObjectResponse accepted a duplicate token"',
        '"WriteGetObjectResponse accepted an empty route"',
        '"WriteGetObjectResponse accepted an unsafe token"',
        '"WriteGetObjectResponse accepted a route and Host mismatch"',
        '"WriteGetObjectResponse accepted a query"',
        '"WriteGetObjectResponse accepted UNSIGNED-PAYLOAD over HTTP"',
        '"WriteGetObjectResponse accepted a signed payload hash"',
        '"WriteGetObjectResponse validated controls before authentication"',
        '"WriteGetObjectResponse did not dispatch forwarded controls"',
        '"WriteGetObjectResponse rejected complete modeled controls"',
        "(Object_Lambda_Responses.Expires,\n"
        '               "Wed, 21 Oct 2015 07:28:00 GMT")',
        "(Object_Lambda_Responses.Last_Modified,\n"
        '               "Wed, 21 Oct 2015 07:28:00 GMT")',
        "(Object_Lambda_Responses.Missing_Metadata, \"2\")",
        '"WriteGetObjectResponse rejected a modeled checksum"',
        '"WriteGetObjectResponse rejected a digit-bearing error code"',
        '"WriteGetObjectResponse accepted an invalid control class"',
        '"WriteGetObjectResponse accepted an invalid response status"',
        '"WriteGetObjectResponse accepted an error response body"',
        '"WriteGetObjectResponse accepted duplicate metadata names"',
        '"WriteGetObjectResponse accepted an unmodeled forwarded field"',
        '"WriteGetObjectResponse accepted multiple checksums"',
        '"WriteGetObjectResponse accepted or retried an invalid token"',
        '"WriteGetObjectResponse made an admitted invalid token " &\n'
        '            "conclusive"',
        '"WriteGetObjectResponse hid or retried a delivery failure"',
        '"WriteGetObjectResponse accepted or retried unread delivery"',
        '"WriteGetObjectResponse lost or retried a malformed " &\n'
        '            "invalid token"',
        '"WriteGetObjectResponse lost or retried malformed " &\n'
        '            "delivery failure"',
        '"WriteGetObjectResponse lost or retried malformed " &\n'
        '            "unread delivery"',
        '"WriteGetObjectResponse lost or retried a provider exception"',
        '"WriteGetObjectResponse did not propagate cancellation once"',
        '"WriteGetObjectResponse retained a cancelled body source"',
        '"WriteGetObjectResponse retried or reused a provider token"',
        '"WriteGetObjectResponse routing changed ordinary S3 requests"',
    ], "WriteGetObjectResponse signed corpus")

    require_in_order(model_verifier, [
        '"method": "POST", "requestUri": "/WriteGetObjectResponse"',
        '"v4-unsigned-body"',
        '"unsignedPayload"',
        '"hostPrefix": "{RequestRoute}."',
        '["RequestRoute", "RequestToken"]',
    ], "generated WriteGetObjectResponse model")
    require('"x-amz-request-route"' in model_verifier,
            "model request-route header")
    require('"x-amz-request-token"' in model_verifier,
            "model request-token header")

    prose_logical = " ".join(prose.split())
    require_in_order(prose_logical, [
        "public server provider boundary",
        "exact `POST /WriteGetObjectResponse` with no query",
        "Authentication precedes route, header, payload-policy, and body",
        "lends the non-rewindable body source to exactly one synchronous",
        "Field identity is structurally typed; field values remain exact",
        "provider owns token authenticity, expiry, route binding, atomic",
        "Backend coverage is supplied by this caller-owned",
        "`Delivered` is accepted only after",
        "may return `Invalid_Token` only before token consumption",
        "without replay",
        "Cancellation and timeout propagate",
        "no independent observation",
    ], "conditional WriteGetObjectResponse prose")


def rejected_registry(registry: dict, label: str) -> None:
    try:
        assert_registry(registry)
    except (AssertionError, KeyError, TypeError):
        return
    raise AssertionError(f"{label}: registry mutation accepted")


def rejected_sources(provider_spec: str, server_spec: str, server_body: str,
                     corpus: str, model_verifier: str, prose: str,
                     client: str, label: str) -> None:
    try:
        assert_sources(
            provider_spec, server_spec, server_body, corpus, model_verifier,
            prose, client,
        )
    except AssertionError:
        return
    raise AssertionError(f"{label}: source mutation accepted")


def main() -> None:
    registry = tomllib.loads(REGISTRY_PATH.read_text())
    provider_spec = PROVIDER_SPEC_PATH.read_text()
    server_spec = SERVER_SPEC_PATH.read_text()
    server_body = SERVER_BODY_PATH.read_text()
    corpus = CORPUS_PATH.read_text()
    model_verifier = MODEL_VERIFIER_PATH.read_text()
    prose = PROSE_PATH.read_text()
    client = "\n".join(path.read_text() for path in CLIENT_PATHS)

    assert_registry(registry)
    assert_sources(
        provider_spec, server_spec, server_body, corpus, model_verifier,
        prose, client,
    )

    for field, value, label in [
        ("backend", "missing", "missing backend coverage"),
        ("server", "missing", "missing server coverage"),
        ("client", "covered", "invented client completion"),
    ]:
        candidate = copy.deepcopy(registry)
        operation(candidate)["coverage"][field] = value
        rejected_registry(candidate, label)
    candidate = copy.deepcopy(registry)
    operation(candidate)["evidence"]["server"] = []
    rejected_registry(candidate, "missing server evidence")
    candidate = copy.deepcopy(registry)
    operation(candidate)["evidence"]["backend"] = []
    rejected_registry(candidate, "missing backend evidence")
    candidate = copy.deepcopy(registry)
    candidate["qualification"]["write_get_object_response"].pop(0)
    rejected_registry(candidate, "missing dedicated verifier")

    route_mutations = [
        ('Method /= "POST"', 'Method /= "PUT"', "wrong method"),
        ("S3.SigV4.Unsigned_Payload", '"STREAMING-AWS4-HMAC"',
         "signed payload accepted"),
        ('Apps.Request_Header_Count (X, "x-amz-request-route");',
         'Apps.Request_Header_Count (X, "x-request-route");',
         "wrong request-route header"),
        ('Apps.Request_Header_Count (X, "x-amz-request-token");',
         'Apps.Request_Header_Count (X, "x-request-token");',
         "wrong request-token header"),
        ('400, "ValidationError"', '200, "Success"',
         "invalid token accepted"),
    ]
    for old, new, label in route_mutations:
        changed = mutate_route(server_body, old, new, label)
        rejected_sources(
            provider_spec, server_spec, changed, corpus, model_verifier,
            prose, client, label,
        )
    for old, new, label in [
        ('"/WriteGetObjectResponse"', '"/writeGetObjectResponse"',
         "wrong target"),
        ("(if Operation = Write_Get_Object_Response\n"
         "          then Apps.Stream_Body",
         "(if Operation = Write_Get_Object_Response\n"
         "          then Apps.Discard_Request_Body",
         "body not streamed"),
    ]:
        changed = replace_once(server_body, old, new, label)
        rejected_sources(
            provider_spec, server_spec, changed, corpus, model_verifier,
            prose, client, label,
        )

    changed_corpus = replace_once(
        corpus,
        '"WriteGetObjectResponse accepted a duplicate token"',
        '"WriteGetObjectResponse accepted a token"',
        "missing duplicate-token negative",
    )
    rejected_sources(
        provider_spec, server_spec, server_body, changed_corpus,
        model_verifier, prose, client, "missing duplicate-token negative",
    )

    for old, new, label in [
        ("Length.Kind = Backends.Unknown or else Length.Bytes = 0",
         "Length.Kind = Backends.Known and then Length.Bytes = 0",
         "unknown empty body rejected"),
        ("Response_Valid := Source.Observed = 0",
         "Response_Valid := True",
         "unknown error body not checked"),
        ("and then Source.Observed = 0;",
         "and then Source.Observed >= 0;",
         "late invalid token accepted conclusively"),
        ("pragma Unreferenced (Deadline);\n"
         "            Chunk_Length : Byte_Count := 0;\n"
         "         begin\n"
         "            if Token /= null and then Token.Requested then",
         "pragma Unreferenced (Deadline);\n"
         "            Chunk_Length : Byte_Count := 0;\n"
         "         begin\n"
         "            if False then",
         "body-source cancellation ignored"),
    ]:
        changed_body = replace_once(server_body, old, new, label)
        rejected_sources(
            provider_spec, server_spec, changed_body, corpus,
            model_verifier, prose, client, label,
        )

    for old, new, label in [
        ('"WriteGetObjectResponse lost or retried a provider exception"',
         '"WriteGetObjectResponse observed a provider exception"',
         "missing provider exception evidence"),
        ('"WriteGetObjectResponse made an admitted invalid token "',
         '"WriteGetObjectResponse observed an admitted invalid token "',
         "missing admitted-token uncertainty evidence"),
        ('"WriteGetObjectResponse lost or retried malformed " &\n'
         '            "unread delivery"',
         '"WriteGetObjectResponse observed malformed " &\n'
         '            "unread delivery"',
         "missing malformed terminal-result evidence"),
        ('"WriteGetObjectResponse did not propagate cancellation once"',
         '"WriteGetObjectResponse observed cancellation"',
         "missing cancellation evidence"),
        ('"WriteGetObjectResponse accepted an invalid control class"',
         '"WriteGetObjectResponse observed an invalid control"',
         "missing validation-class evidence"),
    ]:
        changed_corpus = replace_once(corpus, old, new, label)
        rejected_sources(
            provider_spec, server_spec, server_body, changed_corpus,
            model_verifier, prose, client, label,
        )

    for old, new, label in [
        ("EOF before returning Delivered",
         "may return Delivered before EOF", "weakened provider completion"),
        ("The server never retries a callback automatically",
         "The server retries callbacks", "invented automatic retry"),
        ("Result        : out Delivery_Result) is abstract;",
         "Result        : out Delivery_Result);",
         "non-abstract provider operation"),
    ]:
        changed_provider = replace_once(provider_spec, old, new, label)
        rejected_sources(
            changed_provider, server_spec, server_body, corpus,
            model_verifier, prose, client, label,
        )

    print("WriteGetObjectResponse preparation evidence: OK")


if __name__ == "__main__":
    main()
