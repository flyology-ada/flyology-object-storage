#!/usr/bin/env python3
"""Fail-closed source oracle for WriteGetObjectResponse rejection coverage."""

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
    ["./tests/scripts/test.sh"],
    ["./tools/verify-coverage.sh"],
    ["./tools/ci/check-repository.sh", "{model}"],
    ["git", "diff", "--check"],
]


def assert_registry(registry: dict) -> None:
    entry = operation(registry)
    require(entry["public_name"] == "Not_Exposed", "public API invented")
    require(entry["codec"] ==
            "private_strict_object_lambda_callback_negative_capability",
            "WriteGetObjectResponse codec")
    require(entry["coverage"] == {
        "backend": "missing",
        "client": "partial",
        "server": "covered",
        "corpus": "covered",
    }, "WriteGetObjectResponse coverage")
    require(entry["provenance"] == {
        "backend": "absent",
        "client": "generated",
        "server": "handwritten",
        "tests": "handwritten",
    }, "WriteGetObjectResponse provenance")
    require(entry["evidence"]["backend"] == [], "backend evidence invented")
    require(entry["evidence"]["server"] == [
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
    require("returns only NotImplemented" in entry["certainty"],
            "terminal rejection certainty")
    require("never accepts or completes a callback" in entry["certainty"],
            "callback negative capability")
    require("no automatic replay" in entry["certainty"],
            "no-replay certainty")
    require("cannot prove callback completion or causation" in
            entry["reconciliation"], "noncausal reconciliation")
    exclusions = " ".join(entry["exclusions"])
    for fact in [
        "no Low_Level or Objects WriteGetObjectResponse API",
        "exact POST /WriteGetObjectResponse target with no query",
        "secure HTTPS and exact UNSIGNED-PAYLOAD",
        "singleton nonempty text-safe signed x-amz-request-route",
        "exact route-dot Host prefix",
        "consumed and discarded",
        "RequestToken is never echoed",
        "never calls the storage backend",
        "never a 2xx callback result",
    ]:
        require(fact in exclusions, f"missing exclusion: {fact}")
    require(registry["qualification"]["write_get_object_response"] ==
            EXPECTED_LANE, "WriteGetObjectResponse qualification lane")


def assert_sources(server_spec: str, server_body: str, corpus: str,
                   model_verifier: str, prose: str, client: str) -> None:
    require("validated negative-capability WriteGetObjectResponse routing" in
            server_spec,
            "server specification boundary")
    require("Write_Get_Object_Response" not in client,
            "public client API invented")
    require("WriteGetObjectResponse" not in client,
            "generated operation leaked into public client")

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
        '501, "NotImplemented"',
        '"Object Lambda response callbacks are not implemented"',
        "return;",
    ], "strict WriteGetObjectResponse rejection")
    for name in [
        "x-amz-request-route",
        "x-amz-request-token",
    ]:
        require(route.count(f'Apps.Request_Header_Count (X, "{name}")') == 1,
                f"{name} singleton validation count")
        require(route.count(f'Apps.Request_Header (X, "{name}")') >= 1,
                f"{name} value validation")
    for forbidden in [
        "Store.",
        "Apps.Response_Header",
        "Apps.Respond (X, 200",
        "Apps.Respond (X, 201",
        "Apps.Respond (X, 202",
        "Forward",
        "Persist",
    ]:
        require(forbidden not in route,
                f"WriteGetObjectResponse route contains {forbidden!r}")

    body_policy = unique_region(
        server_body,
        "Apps.Configure_Route",
        "Apps.Seal_Route (X)",
        "WriteGetObjectResponse body policy",
    )
    require_in_order(body_policy, [
        "Write_Get_Object_Response",
        "Apps.Discard_Request_Body",
        "Apps.Required_Authentication",
    ], "bounded authenticated callback body")

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
        'not Has (Value, "200 OK")',
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
        '"WriteGetObjectResponse interpreted forwarded response fields"',
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
        "authenticated Object Lambda rejection boundary",
        "exact `POST /WriteGetObjectResponse` with no query",
        "Authentication precedes route, header, payload-policy, and body",
        "`501 NotImplemented`",
        "never reports 2xx success",
        "Backend coverage intentionally remains missing",
        "cannot prove callback completion or causation",
    ], "conditional WriteGetObjectResponse prose")


def rejected_registry(registry: dict, label: str) -> None:
    try:
        assert_registry(registry)
    except (AssertionError, KeyError, TypeError):
        return
    raise AssertionError(f"{label}: registry mutation accepted")


def rejected_sources(server_spec: str, server_body: str, corpus: str,
                     model_verifier: str, prose: str, client: str,
                     label: str) -> None:
    try:
        assert_sources(
            server_spec, server_body, corpus, model_verifier, prose, client,
        )
    except AssertionError:
        return
    raise AssertionError(f"{label}: source mutation accepted")


def main() -> None:
    registry = tomllib.loads(REGISTRY_PATH.read_text())
    server_spec = SERVER_SPEC_PATH.read_text()
    server_body = SERVER_BODY_PATH.read_text()
    corpus = CORPUS_PATH.read_text()
    model_verifier = MODEL_VERIFIER_PATH.read_text()
    prose = PROSE_PATH.read_text()
    client = "\n".join(path.read_text() for path in CLIENT_PATHS)

    assert_registry(registry)
    assert_sources(
        server_spec, server_body, corpus, model_verifier, prose, client,
    )

    for field, value, label in [
        ("backend", "covered", "invented backend coverage"),
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
    operation(candidate)["evidence"]["backend"] = ["invented.adb"]
    rejected_registry(candidate, "invented backend evidence")
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
        ('501, "NotImplemented"', '200, "Success"', "callback success"),
    ]
    for old, new, label in route_mutations:
        changed = mutate_route(server_body, old, new, label)
        rejected_sources(
            server_spec, changed, corpus, model_verifier, prose, client,
            label,
        )
    for old, new, label in [
        ('"/WriteGetObjectResponse"', '"/writeGetObjectResponse"',
         "wrong target"),
        ("Apps.Discard_Request_Body", "Apps.Stream_Body",
         "body not discarded"),
    ]:
        changed = replace_once(server_body, old, new, label)
        rejected_sources(
            server_spec, changed, corpus, model_verifier, prose, client,
            label,
        )

    changed_corpus = replace_once(
        corpus,
        '"WriteGetObjectResponse accepted a duplicate token"',
        '"WriteGetObjectResponse accepted a token"',
        "missing duplicate-token negative",
    )
    rejected_sources(
        server_spec, server_body, changed_corpus, model_verifier, prose,
        client, "missing duplicate-token negative",
    )

    print("WriteGetObjectResponse preparation evidence: OK")


if __name__ == "__main__":
    main()
