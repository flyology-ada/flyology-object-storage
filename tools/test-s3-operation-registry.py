#!/usr/bin/env python3
"""Negative oracles for reviewed S3 operation evidence promotion."""

from __future__ import annotations

import copy
import hashlib
import json
import os
import re
import tempfile
from collections import Counter
from pathlib import Path

import s3_operation
import s3_codegen
import gnatdoc_diagnostics


LIST_BUCKETS_OUTCOME_REGION = """\
   --  Result kind for one bounded ListBuckets page.
   --  @enum Page_Available A modeled bucket page is available
   --  @enum List_Rejected The service returned a structured S3 rejection
   type List_Outcome_Kind is (Page_Available, List_Rejected);

   --  One modeled bucket page or a structured S3 rejection.
   --  @field Kind Selects the page or rejection variant
   --  @field Status HTTP status returned by the completed exchange
   --  @field Page Complete modeled bucket page
   --  @field Error Structured S3 rejection
   type List_Outcome
     (Kind : List_Outcome_Kind := List_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Page_Available =>
            Page : Flyology.Object_Storage.S3.Buckets.List_Buckets_Result;
         when List_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;
"""


CREATE_BUCKET_OUTCOME_REGION = """\
   --  Result kind for one CreateBucket convenience response.
   --  @enum Creation_Completed Modeled creation response headers are available
   --  @enum Create_Rejected The service returned a structured S3 rejection
   type Create_Outcome_Kind is (Creation_Completed, Create_Rejected);

   --  Modeled creation response headers or a structured S3 rejection.
   --  @field Kind Selects the creation or rejection variant
   --  @field Status HTTP status returned by the completed exchange
   --  @field Location Modeled bucket location response value
   --  @field Bucket_ARN Modeled bucket ARN response value
   --  @field Error Structured S3 rejection
   type Create_Outcome
     (Kind : Create_Outcome_Kind := Create_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Creation_Completed =>
            Location   : Ada.Strings.Unbounded.Unbounded_String;
            Bucket_ARN : Ada.Strings.Unbounded.Unbounded_String;
         when Create_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;
"""


DELETE_BUCKET_OUTCOME_REGION = """\
   --  Result kind for one synchronous delete convenience response.
   --  @enum Deletion_Completed Complete modeled success response is available
   --  @enum Delete_Rejected The service returned a structured S3 rejection
   type Delete_Outcome_Kind is (Deletion_Completed, Delete_Rejected);

   --  Complete modeled delete response or a structured S3 rejection.
   --  @field Kind Selects the completion or rejection variant
   --  @field Status HTTP status returned by the completed exchange
   --  @field Error Structured S3 rejection
   type Delete_Outcome
     (Kind : Delete_Outcome_Kind := Delete_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Deletion_Completed =>
            null;
         when Delete_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;
"""


DELETE_ANALYTICS_CONFIGURATION_REGION = """\
   --  Remove one named analytics configuration.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose analytics configuration is removed
   --  @param Identifier Analytics configuration identifier
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Completed deletion or structured S3 rejection
   function Delete_Analytics_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Identifier : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;
"""


DELETE_ENCRYPTION_REGION = """\
   --  Remove the complete default encryption configuration.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose default encryption configuration is removed
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Completed deletion or structured S3 rejection
   function Delete_Encryption
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;
"""


DELETE_INTELLIGENT_TIERING_CONFIGURATION_REGION = """\
   --  Remove one named intelligent-tiering configuration.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose intelligent-tiering policy is removed
   --  @param Identifier Intelligent-tiering configuration identifier
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Completed deletion or structured S3 rejection
   function Delete_Intelligent_Tiering_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Identifier : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;
"""


LIST_DIRECTORY_SYNC_REGION = """\
   --  Read one directory-bucket page by waiting on the same owner-driven
   --  state machine used by composable callers. The wrapper does not start a
   --  hidden continuation request.
   --  @param Client Configured control-endpoint client retained through drain
   --  @param Origin Caller-selected S3 Express control endpoint
   --  @param Parameters Complete modeled cursor and page-size presence
   --  @param Identity Credentials borrowed only during signing
   --  @param Region SigV4 region
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected response and error XML limits
   --  @param Collection_Limit Caller-selected maximum decoded bucket count
   --  @return Typed modeled page or bounded exchange failure
   function List_Directory_Buckets
     (Client           : aliased in out Flyology.HTTP.Client.Client;
      Origin           : Flyology.HTTP.Origin;
      Parameters       : Low_Level.List_Directory_Buckets_Parameters;
      Identity         : Low_Level.Credentials;
      Region           : String;
      Timeout          : Duration;
      Token            : access Flyology.Cancellation.Token;
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Collection_Limit : Positive)
      return List_Directory_Buckets_Result;"""


GENERATED_MUTATION_START_LABELS = (
    ("Set_ACL", "bucket access-control policy", "PutBucketAcl"),
    (
        "Set_Inventory_Configuration",
        "inventory configuration",
        "PutBucketInventoryConfiguration",
    ),
    ("Set_Logging", "bucket logging configuration", "PutBucketLogging"),
    ("Set_Website", "bucket website configuration", "PutBucketWebsite"),
)


BOUNDED_REST_XML_SPEC = (
    s3_operation.ROOT
    / "src/flyology-object_storage-client-bounded_rest_xml_reads.ads"
)


def assert_list_buckets_outcome_documentation(source: str) -> None:
    assert source.count(LIST_BUCKETS_OUTCOME_REGION) == 1, (
        "ListBuckets outcome documentation or declaration region differs"
    )


def assert_create_bucket_outcome_documentation(source: str) -> None:
    assert source.count(CREATE_BUCKET_OUTCOME_REGION) == 1, (
        "CreateBucket outcome documentation or declaration region differs"
    )


def assert_delete_bucket_outcome_documentation(source: str) -> None:
    assert source.count(DELETE_BUCKET_OUTCOME_REGION) == 1, (
        "DeleteBucket outcome documentation or declaration region differs"
    )


def assert_delete_analytics_documentation(source: str) -> None:
    assert source.count(DELETE_ANALYTICS_CONFIGURATION_REGION) == 1, (
        "DeleteBucketAnalyticsConfiguration documentation region differs"
    )


def assert_delete_encryption_documentation(source: str) -> None:
    assert source.count(DELETE_ENCRYPTION_REGION) == 1, (
        "DeleteBucketEncryption documentation region differs"
    )


def assert_delete_intelligent_tiering_documentation(source: str) -> None:
    assert source.count(
        DELETE_INTELLIGENT_TIERING_CONFIGURATION_REGION
    ) == 1, (
        "DeleteBucketIntelligentTieringConfiguration documentation differs"
    )


def assert_list_directory_sync_documentation(source: str) -> None:
    assert source.count(LIST_DIRECTORY_SYNC_REGION) == 1, (
        "ListDirectoryBuckets synchronous documentation region differs"
    )


def generated_leading_comment(source: str, marker: str) -> tuple[str, ...]:
    lines = source.splitlines()
    positions = [
        index for index, line in enumerate(lines) if line == marker
    ]
    assert len(positions) == 1, (
        f"generated provider declaration count differs: {marker}"
    )
    cursor = positions[0] - 1
    block = []
    while cursor >= 0 and lines[cursor].startswith("   --  "):
        block.append(lines[cursor][7:])
        cursor -= 1
    assert block, f"generated provider documentation is detached: {marker}"
    return tuple(reversed(block))


def assert_generated_mutation_start_documentation(source: str) -> None:
    for public_name, label, operation in GENERATED_MUTATION_START_LABELS:
        comment = generated_leading_comment(
            source,
            f"   procedure {public_name}",
        )
        tags = []
        for line in comment:
            if line.startswith("@param "):
                tags.append(line)
            elif tags:
                tags[-1] += " " + line
        assert tuple(tags) == (
            "@param Client HTTP client retained through terminal drain",
            "@param Origin Exact HTTP origin used for routing and signing",
            "@param Bucket Required exact target bucket",
            f"@param Value {label.capitalize()} value serialized before "
            "admission",
            "@param Parameters Complete modeled non-resource "
            f"{operation} controls",
            "@param Identity Credentials borrowed only while signing the "
            "request",
            "@param Deadline Absolute admission, exchange, and drain limit",
            "@param Region Exact SigV4 signing region",
            "@param Style Caller-selected S3 addressing style",
            "@param Limits Caller-selected bounded XML limits",
            "@param Token Optional cancellation source retained to drain",
            "@param Operation Reusable owner-driven operation restarted",
        ), f"generated {public_name} restart parameter documentation differs"


def generated_constructor_documentation(label: str, operation: str) -> str:
    return "\n".join(
        s3_codegen.ada_comment(text)
        for text in (
            f"Construct one owner-driven {label} replacement.",
            "@param Set Caller-owned completion set",
            "@param Client HTTP client retained through terminal drain",
            "@param Origin Exact HTTP origin used for routing and signing",
            "@param Bucket Required exact target bucket",
            f"@param Value {label.capitalize()} value serialized before "
            "admission",
            "@param Parameters Complete modeled non-resource "
            f"{operation} controls",
            "@param Identity Credentials borrowed only while signing the "
            "request",
            "@param Deadline Absolute admission, exchange, and drain limit",
            "@param Region Exact SigV4 signing region",
            "@param Style Caller-selected S3 addressing style",
            "@param Limits Caller-selected bounded XML limits",
            "@param Token Optional cancellation source retained to drain",
            f"@return Started owner-driven {label} replacement",
        )
    ) + "\n"


def generated_constructor_comment(
    source: str,
    public_name: str,
) -> tuple[str, ...]:
    lines = source.splitlines()
    positions = [
        index
        for index, line in enumerate(lines[:-1])
        if line == f"   function {public_name}"
        and lines[index + 1].startswith("     (Set")
    ]
    assert len(positions) == 1, (
        f"generated constructor declaration count differs: {public_name}"
    )
    cursor = positions[0] - 1
    block = []
    while cursor >= 0 and lines[cursor].startswith("   --  "):
        block.append(lines[cursor][7:])
        cursor -= 1
    assert block, (
        f"generated constructor documentation is detached: {public_name}"
    )
    return tuple(reversed(block))


def assert_generated_mutation_constructor_documentation(source: str) -> None:
    for public_name, label, operation in GENERATED_MUTATION_START_LABELS:
        expected_block = generated_constructor_documentation(label, operation)
        assert source.count(expected_block) == 1, (
            f"generated {public_name} constructor block count differs"
        )
        comment = generated_constructor_comment(source, public_name)
        assert all(len("   --  " + line) <= 79 for line in comment), (
            f"generated {public_name} constructor documentation is overwidth"
        )
        logical = [comment[0]]
        for line in comment[1:]:
            if line.startswith("@param ") or line.startswith("@return "):
                logical.append(line)
            else:
                assert (
                    logical[-1].startswith("@param ")
                    or logical[-1].startswith("@return ")
                ), (
                    f"generated {public_name} constructor continuation "
                    "is orphaned"
                )
                assert line and not line.startswith("@"), (
                    f"generated {public_name} constructor continuation "
                    "is malformed"
                )
                logical[-1] += " " + line
        assert tuple(logical) == (
            f"Construct one owner-driven {label} replacement.",
            "@param Set Caller-owned completion set",
            "@param Client HTTP client retained through terminal drain",
            "@param Origin Exact HTTP origin used for routing and signing",
            "@param Bucket Required exact target bucket",
            f"@param Value {label.capitalize()} value serialized before "
            "admission",
            "@param Parameters Complete modeled non-resource "
            f"{operation} controls",
            "@param Identity Credentials borrowed only while signing the "
            "request",
            "@param Deadline Absolute admission, exchange, and drain limit",
            "@param Region Exact SigV4 signing region",
            "@param Style Caller-selected S3 addressing style",
            "@param Limits Caller-selected bounded XML limits",
            "@param Token Optional cancellation source retained to drain",
            f"@return Started owner-driven {label} replacement",
        ), f"generated {public_name} constructor documentation differs"


def bounded_declaration_position(lines: list[str], marker: str) -> int:
    positions = [
        index for index, line in enumerate(lines)
        if line == marker or line.startswith(marker + " ")
    ]
    assert len(positions) == 1, (
        f"bounded lifecycle declaration count differs: {marker}"
    )
    return positions[0]


def bounded_leading_comment(
    lines: list[str], marker: str, indent: str
) -> tuple[str, ...]:
    position = bounded_declaration_position(lines, marker)
    cursor = position - 1
    while cursor >= 0 and lines[cursor].startswith(indent):
        cursor -= 1
    block = lines[cursor + 1:position]
    assert block and all(line.startswith(indent) for line in block), (
        f"bounded lifecycle documentation is detached: {marker}"
    )
    return tuple(line[len(indent):] for line in block)


def bounded_following_comment(
    lines: list[str], marker: str, indent: str
) -> tuple[str, ...]:
    position = bounded_declaration_position(lines, marker)
    cursor = position + 1
    while cursor < len(lines) and lines[cursor].startswith(indent):
        cursor += 1
    block = lines[position + 1:cursor]
    assert block, f"bounded lifecycle documentation is detached: {marker}"
    return tuple(line[len(indent):] for line in block)


def check_bounded_generic_documentation(spec: str) -> None:
    """Enforce exact dual association for the bounded lifecycle generic."""
    lines = spec.splitlines()
    assert all(len(line) <= 79 for line in lines)
    assert "@exclude" not in spec
    skeleton = " ".join(
        "\n".join(
            line.split("--", 1)[0] for line in lines
        ).split()
    )
    assert hashlib.sha256(skeleton.encode("utf-8")).hexdigest() == (
        "a3826c1280b8d96f71b843ca0754f09097e4ffae5d2d4f60c4da3409890ebedb"
    )
    assert bounded_leading_comment(lines, "generic", "--  ") == (
        "Share owner-driven state for bounded REST/XML read operations. "
        "Provider",
        "packages retain request preparation, response decoding, and "
        "modeled result",
        "classification; this generic owns buffering, child lifetime, "
        "cancellation,",
        "drain, restart, and Finish mechanics.",
        "@formal Result_Type Typed provider result retained for Finish",
        "@formal Operation_Name Operation name used in diagnostic messages",
        "@formal Start_Exchange Start the operation-specific child exchange",
        "@formal Decode_Response Decode one complete response into "
        "Result_Type",
        "@formal Normalize_Failure Map a terminal exchange failure to "
        "Result_Type",
    )
    formal_comments = (
        (
            "   type Result_Type is private;",
            "Typed provider result retained for Finish.",
        ),
        (
            "   Operation_Name : String;",
            "Operation name used in diagnostic messages.",
        ),
        (
            "   with procedure Start_Exchange",
            "Start the operation-specific child exchange.",
        ),
        (
            "   with function Decode_Response",
            "Decode one complete response into Result_Type.",
        ),
        (
            "   with function Normalize_Failure",
            "Map a terminal exchange failure to Result_Type.",
        ),
    )
    positions = []
    for marker, summary in formal_comments:
        positions.append(bounded_declaration_position(lines, marker))
        assert bounded_leading_comment(lines, marker, "   --  ") == (
            summary,
        )
    package_position = bounded_declaration_position(
        lines,
        "package Flyology.Object_Storage.Client.Bounded_REST_XML_Reads is",
    )
    assert bounded_following_comment(
        lines,
        "package Flyology.Object_Storage.Client.Bounded_REST_XML_Reads is",
        "   --  ",
    ) == (
        "Share owner-driven state for bounded REST/XML read operations. "
        "Provider",
        "packages retain request preparation, response decoding, and modeled",
        "result classification; this generic owns buffering, child lifetime,",
        "cancellation, drain, restart, and Finish mechanics.",
        "@formal Result_Type Typed provider result retained for Finish",
        "@formal Operation_Name Operation name used in diagnostic messages",
        "@formal Start_Exchange Start the operation-specific child exchange",
        "@formal Decode_Response Decode one complete response into "
        "Result_Type",
        "@formal Normalize_Failure Map a terminal exchange failure to "
        "Result_Type",
    )
    private_position = bounded_declaration_position(lines, "private")
    public_lines = lines[package_position:private_position]
    state_position = bounded_declaration_position(
        public_lines,
        "   type State",
    )
    assert public_lines[state_position - 1] == (
        "   --  Retain one reusable provider lifecycle."
    )
    assert public_lines[state_position + 1:state_position + 3] == [
        "     ( --  Completion set that owns the child exchange.",
        "      Set : not null access "
        "Flyology.Operations.Completion_Set'Class) is",
    ]
    assert bounded_declaration_position(lines, "generic") < positions[0]
    assert positions == sorted(positions) and positions[-1] < package_position
    assert Counter(
        line.strip().split()[1]
        for line in lines
        if line.strip().startswith("--  @")
    ) == Counter({"@formal": 10, "@param": 18})
    assert "@field" not in spec


def reject_bounded_generic_documentation(
    original: str, candidate: str, diagnostic: str
) -> None:
    assert candidate != original
    try:
        check_bounded_generic_documentation(candidate)
    except AssertionError:
        return
    raise AssertionError(diagnostic)


_PAGINATED_DOCUMENTATION = {
    "skeleton_sha256": (
        "48cf8576d8f4f7bb8d3fd9d48cafae5554ca601e6a6c68ab7bf3bda51cd59cea"
    ),
    "package": (
        "Share owner-driven state for paginated REST/XML read operations.",
        "Provider packages retain request preparation, response decoding, and",
        "modeled result classification; this generic owns bounded buffering,",
        "child lifetime, cancellation, drain, restart, and Finish mechanics.",
    ),
    "formals": (
        ("   type Result_Type is private;",
         "Typed provider result retained for Finish."),
        ("   Operation_Name : String;",
         "Operation name used in diagnostic messages."),
        ("   with procedure Start_Exchange",
         "Start the operation-specific child exchange."),
        ("   with function Decode_Response",
         "Decode one complete page into Result_Type."),
        ("   with function Normalize_Failure",
         "Map a terminal exchange failure to Result_Type."),
    ),
    "entities": (
        (
            "   type State",
            (
                "Retain one reusable provider lifecycle.",
                "@field Set Completion set that owns the child exchange",
            ),
        ),
        (
            "   procedure Write",
            (
                "Append one response-body slice within the configured XML "
                "limit.",
                "@param Item Lifecycle state receiving the response",
                "@param Data Next response-body slice",
            ),
        ),
        (
            "   procedure Drive",
            (
                "Advance the parent lifecycle for one driver event.",
                "@param Item Lifecycle state being advanced",
                "@param Parent Parent operation completed by this lifecycle",
                "@param Sink Operation-specific response sink",
                "@param Client HTTP client retained by the parent operation",
                "@param Cancellation Optional cancellation source",
                "@param Event Driver event to process",
            ),
        ),
        (
            "   procedure Request_Cancellation",
            (
                "Forward cancellation to the active child exchange.",
                "@param Item Lifecycle state whose child is cancelled",
            ),
        ),
        (
            "   procedure Finalize",
            (
                "Clear the retained prepared request and buffered response.",
                "@param Item Lifecycle state being finalized",
            ),
        ),
        (
            "   procedure Start",
            (
                "Install one prepared request and start its parent operation.",
                "@param Item Lifecycle state to initialize",
                "@param Parent Parent operation to start",
                "@param Prepared Prepared operation-specific request",
                "@param Deadline Absolute deadline retained for the child "
                "exchange",
                "@param Limits Caller-selected XML parse limits",
                "@param Collection_Limit Caller-selected decoded collection "
                "limit",
            ),
        ),
        (
            "   procedure Finish",
            (
                "Consume one terminal parent and expose its typed result.",
                "@param Item Lifecycle state holding terminal evidence",
                "@param Parent Terminal parent operation to consume",
                "@param Result Typed provider result produced by the child "
                "exchange",
            ),
        ),
    ),
}


def _paginated_position(lines: list[str], marker: str) -> int:
    positions = [
        index for index, line in enumerate(lines)
        if line == marker or line.startswith(marker + " ")
    ]
    assert len(positions) == 1, (
        f"Paginated_REST_XML_Reads declaration count differs: {marker}"
    )
    return positions[0]


def _paginated_leading(lines: list[str], marker: str) -> tuple[str, ...]:
    position = _paginated_position(lines, marker)
    cursor = position - 1
    while cursor >= 0 and lines[cursor].startswith("   --  "):
        cursor -= 1
    block = lines[cursor + 1:position]
    assert block, f"Paginated_REST_XML_Reads docs detached: {marker}"
    return tuple(line[7:] for line in block)


def _paginated_following(lines: list[str], marker: str) -> tuple[str, ...]:
    position = _paginated_position(lines, marker)
    cursor = position + 1
    while cursor < len(lines) and lines[cursor].startswith("   --  "):
        cursor += 1
    block = lines[position + 1:cursor]
    assert block, f"Paginated_REST_XML_Reads package docs detached: {marker}"
    return tuple(line[7:] for line in block)


def _check_paginated_rest_xml_docs(spec: str) -> None:
    lines = spec.splitlines()
    assert all(len(line) <= 79 for line in lines), (
        "Paginated_REST_XML_Reads exceeds 79 columns"
    )
    assert "@exclude" not in spec
    skeleton = re.sub(
        r"\s+",
        " ",
        "\n".join(
            line for line in lines if not line.lstrip().startswith("--")
        ),
    ).strip()
    assert hashlib.sha256(skeleton.encode("utf-8")).hexdigest() == (
        _PAGINATED_DOCUMENTATION["skeleton_sha256"]
    ), "Paginated_REST_XML_Reads declaration skeleton differs"

    package_marker = (
        "package Flyology.Object_Storage.Client.Paginated_REST_XML_Reads is"
    )
    assert _paginated_following(lines, package_marker) == (
        _PAGINATED_DOCUMENTATION["package"]
    ), "Paginated_REST_XML_Reads package documentation differs"
    for marker, summary in _PAGINATED_DOCUMENTATION["formals"]:
        assert _paginated_leading(lines, marker) == (summary,), (
            f"Paginated_REST_XML_Reads formal docs differ: {marker}"
        )

    package_position = _paginated_position(lines, package_marker)
    private_position = _paginated_position(lines, "private")
    public_lines = lines[package_position:private_position]
    entity_positions = []
    for marker, expected in _PAGINATED_DOCUMENTATION["entities"]:
        entity_positions.append(_paginated_position(public_lines, marker))
        assert _paginated_leading(public_lines, marker) == expected, (
            f"Paginated_REST_XML_Reads entity docs differ: {marker}"
        )
    assert entity_positions == sorted(entity_positions), (
        "Paginated_REST_XML_Reads entity order differs"
    )

    tags = Counter()
    for line in lines:
        match = re.fullmatch(
            r"\s*--  @(field|param)(?: [^ ]+)(?: .+)", line
        )
        if match is not None:
            tags[match.group(1)] += 1
        elif re.match(r"\s*--  @", line):
            raise AssertionError(
                "Paginated_REST_XML_Reads documentation tag is malformed"
            )
    assert tags == Counter({"field": 1, "param": 19}), (
        "Paginated_REST_XML_Reads tag inventory differs"
    )
    prose = " ".join(
        line.lstrip()[4:] for line in lines
        if line.lstrip().startswith("--  ")
    )
    assert not re.search(
        r"\b(?:TODO|TBD|placeholder|undocumented)\b", prose, re.I
    ), "Paginated_REST_XML_Reads placeholder documentation remains"


def _reject_paginated_docs(
    original: str, candidate: str, diagnostic: str
) -> None:
    assert candidate != original, "Paginated negative did not mutate source"
    try:
        _check_paginated_rest_xml_docs(candidate)
    except AssertionError:
        return
    raise AssertionError(diagnostic)


def main() -> None:
    buckets_source = (
        s3_operation.ROOT
        / "src/flyology-object_storage-client-buckets.ads"
    ).read_text(encoding="utf-8")
    assert_list_buckets_outcome_documentation(buckets_source)
    for label, invalid_source in {
        "missing enum association": buckets_source.replace(
            "   --  @enum Page_Available A modeled bucket page is available\n",
            "",
            1,
        ),
        "wrong field association": buckets_source.replace(
            "   --  @field Status HTTP status returned by the completed "
            "exchange\n",
            "   --  @field HTTP_Status HTTP status returned by the completed "
            "exchange\n",
            1,
        ),
        "detached record documentation": buckets_source.replace(
            "   --  @field Error Structured S3 rejection\n"
            "   type List_Outcome\n",
            "   --  @field Error Structured S3 rejection\n\n"
            "   type List_Outcome\n",
            1,
        ),
    }.items():
        try:
            assert_list_buckets_outcome_documentation(invalid_source)
        except AssertionError:
            pass
        else:
            raise AssertionError(
                f"ListBuckets outcome {label} was accepted"
            )

    assert_create_bucket_outcome_documentation(buckets_source)
    for label, invalid_source in {
        "missing enum association": buckets_source.replace(
            "   --  @enum Creation_Completed Modeled creation response "
            "headers are available\n",
            "",
            1,
        ),
        "wrong field association": buckets_source.replace(
            "   --  @field Bucket_ARN Modeled bucket ARN response value\n",
            "   --  @field BucketARN Modeled bucket ARN response value\n",
            1,
        ),
        "detached record documentation": buckets_source.replace(
            "   --  @field Error Structured S3 rejection\n"
            "   type Create_Outcome\n",
            "   --  @field Error Structured S3 rejection\n\n"
            "   type Create_Outcome\n",
            1,
        ),
        "duplicate declaration region": buckets_source.replace(
            CREATE_BUCKET_OUTCOME_REGION,
            CREATE_BUCKET_OUTCOME_REGION * 2,
            1,
        ),
    }.items():
        try:
            assert_create_bucket_outcome_documentation(invalid_source)
        except AssertionError:
            pass
        else:
            raise AssertionError(
                f"CreateBucket outcome {label} was accepted"
            )

    assert_delete_bucket_outcome_documentation(buckets_source)
    for label, invalid_source in {
        "missing enum association": buckets_source.replace(
            "   --  @enum Deletion_Completed Complete modeled success "
            "response is available\n",
            "",
            1,
        ),
        "wrong field association": buckets_source.replace(
            DELETE_BUCKET_OUTCOME_REGION,
            DELETE_BUCKET_OUTCOME_REGION.replace(
                "   --  @field Status HTTP status returned by the completed "
                "exchange\n",
                "   --  @field HTTP_Status HTTP status returned by the "
                "completed exchange\n",
                1,
            ),
            1,
        ),
        "detached record documentation": buckets_source.replace(
            "   --  @field Error Structured S3 rejection\n"
            "   type Delete_Outcome\n",
            "   --  @field Error Structured S3 rejection\n\n"
            "   type Delete_Outcome\n",
            1,
        ),
        "duplicate declaration region": buckets_source.replace(
            DELETE_BUCKET_OUTCOME_REGION,
            DELETE_BUCKET_OUTCOME_REGION * 2,
            1,
        ),
    }.items():
        try:
            assert_delete_bucket_outcome_documentation(invalid_source)
        except AssertionError:
            pass
        else:
            raise AssertionError(
                f"DeleteBucket outcome {label} was accepted"
            )

    assert_delete_analytics_documentation(buckets_source)
    for label, invalid_source in {
        "missing identifier association": buckets_source.replace(
            "   --  @param Identifier Analytics configuration identifier\n",
            "",
            1,
        ),
        "wrong parameter association": buckets_source.replace(
            "   --  @param Identifier Analytics configuration identifier\n",
            "   --  @param Configuration_Identifier Analytics configuration "
            "identifier\n",
            1,
        ),
        "detached documentation": buckets_source.replace(
            "   --  @return Completed deletion or structured S3 rejection\n"
            "   function Delete_Analytics_Configuration\n",
            "   --  @return Completed deletion or structured S3 rejection\n\n"
            "   function Delete_Analytics_Configuration\n",
            1,
        ),
        "duplicate declaration region": buckets_source.replace(
            DELETE_ANALYTICS_CONFIGURATION_REGION,
            DELETE_ANALYTICS_CONFIGURATION_REGION * 2,
            1,
        ),
    }.items():
        try:
            assert_delete_analytics_documentation(invalid_source)
        except AssertionError:
            pass
        else:
            raise AssertionError(
                "DeleteBucketAnalyticsConfiguration "
                f"{label} was accepted"
            )

    assert_delete_encryption_documentation(buckets_source)
    for label, invalid_source in {
        "missing bucket association": buckets_source.replace(
            "   --  @param Bucket Bucket whose default encryption "
            "configuration is removed\n",
            "",
            1,
        ),
        "wrong parameter association": buckets_source.replace(
            "   --  @param Bucket Bucket whose default encryption "
            "configuration is removed\n",
            "   --  @param Bucket_Name Bucket whose default encryption "
            "configuration is removed\n",
            1,
        ),
        "detached documentation": buckets_source.replace(
            "   --  @return Completed deletion or structured S3 rejection\n"
            "   function Delete_Encryption\n",
            "   --  @return Completed deletion or structured S3 rejection\n\n"
            "   function Delete_Encryption\n",
            1,
        ),
        "duplicate declaration region": buckets_source.replace(
            DELETE_ENCRYPTION_REGION,
            DELETE_ENCRYPTION_REGION * 2,
            1,
        ),
    }.items():
        try:
            assert_delete_encryption_documentation(invalid_source)
        except AssertionError:
            pass
        else:
            raise AssertionError(
                f"DeleteBucketEncryption {label} was accepted"
            )

    assert_delete_intelligent_tiering_documentation(buckets_source)
    for label, invalid_source in {
        "missing identifier association": buckets_source.replace(
            "   --  @param Identifier Intelligent-tiering configuration "
            "identifier\n",
            "",
            1,
        ),
        "wrong parameter association": buckets_source.replace(
            "   --  @param Identifier Intelligent-tiering configuration "
            "identifier\n",
            "   --  @param Configuration_Identifier Intelligent-tiering "
            "configuration identifier\n",
            1,
        ),
        "detached documentation": buckets_source.replace(
            "   --  @return Completed deletion or structured S3 rejection\n"
            "   function Delete_Intelligent_Tiering_Configuration\n",
            "   --  @return Completed deletion or structured S3 rejection\n\n"
            "   function Delete_Intelligent_Tiering_Configuration\n",
            1,
        ),
        "duplicate declaration region": buckets_source.replace(
            DELETE_INTELLIGENT_TIERING_CONFIGURATION_REGION,
            DELETE_INTELLIGENT_TIERING_CONFIGURATION_REGION * 2,
            1,
        ),
    }.items():
        try:
            assert_delete_intelligent_tiering_documentation(invalid_source)
        except AssertionError:
            pass
        else:
            raise AssertionError(
                "DeleteBucketIntelligentTieringConfiguration "
                f"{label} was accepted"
            )

    list_directory_provider = s3_codegen._list_directory_provider_spec()
    assert_list_directory_sync_documentation(list_directory_provider)
    for label, invalid_source in {
        "missing collection-limit association": (
            list_directory_provider.replace(
                LIST_DIRECTORY_SYNC_REGION,
                LIST_DIRECTORY_SYNC_REGION.replace(
                    "   --  @param Collection_Limit Caller-selected maximum "
                    "decoded bucket count\n",
                    "",
                    1,
                ),
                1,
            )
        ),
        "wrong parameter association": list_directory_provider.replace(
            LIST_DIRECTORY_SYNC_REGION,
            LIST_DIRECTORY_SYNC_REGION.replace(
                "   --  @param Collection_Limit Caller-selected maximum "
                "decoded bucket count\n",
                "   --  @param Page_Limit Caller-selected maximum decoded "
                "bucket count\n",
                1,
            ),
            1,
        ),
        "detached documentation": list_directory_provider.replace(
            LIST_DIRECTORY_SYNC_REGION,
            LIST_DIRECTORY_SYNC_REGION.replace(
                "   --  @return Typed modeled page or bounded "
                "exchange failure\n"
                "   function List_Directory_Buckets\n",
                "   --  @return Typed modeled page or bounded "
                "exchange failure\n\n"
                "   function List_Directory_Buckets\n",
                1,
            ),
            1,
        ),
        "duplicate declaration region": list_directory_provider.replace(
            LIST_DIRECTORY_SYNC_REGION,
            LIST_DIRECTORY_SYNC_REGION * 2,
            1,
        ),
    }.items():
        try:
            assert_list_directory_sync_documentation(invalid_source)
        except AssertionError:
            pass
        else:
            raise AssertionError(
                f"ListDirectoryBuckets synchronous {label} was accepted"
            )

    mutation_provider = s3_codegen._generated_mutation_provider_spec(
        s3_codegen.GENERATED_MUTATIONS
    )
    assert_generated_mutation_start_documentation(mutation_provider)
    assert_generated_mutation_constructor_documentation(mutation_provider)
    for label, invalid_source in {
        "missing operation association": mutation_provider.replace(
            "   --  @param Operation Reusable owner-driven operation "
            "restarted\n",
            "",
            1,
        ),
        "wrong parameter association": mutation_provider.replace(
            "   --  @param Operation Reusable owner-driven operation "
            "restarted\n",
            "   --  @param Operation_State Reusable owner-driven operation "
            "restarted\n",
            1,
        ),
        "wrong operation description": mutation_provider.replace(
            "   --  @param Operation Reusable owner-driven operation "
            "restarted\n",
            "   --  @param Operation Fresh operation value\n",
            1,
        ),
        "detached documentation": mutation_provider.replace(
            "   --  @param Operation Reusable owner-driven operation "
            "restarted\n"
            "   procedure Set_ACL\n",
            "   --  @param Operation Reusable owner-driven operation "
            "restarted\n\n"
            "   procedure Set_ACL\n",
            1,
        ),
        "duplicate operation association": mutation_provider.replace(
            "   --  @param Operation Reusable owner-driven operation "
            "restarted\n",
            "   --  @param Operation Reusable owner-driven operation "
            "restarted\n"
            "   --  @param Operation Reusable owner-driven operation "
            "restarted\n",
            1,
        ),
    }.items():
        try:
            assert_generated_mutation_start_documentation(invalid_source)
        except AssertionError:
            pass
        else:
            raise AssertionError(
                f"generated mutation restart {label} was accepted"
            )

    constructor_set = (
        s3_codegen.ada_comment("@param Set Caller-owned completion set")
        + "\n"
    )
    constructor_client = (
        s3_codegen.ada_comment(
            "@param Client HTTP client retained through terminal drain"
        )
        + "\n"
    )
    constructor_value = (
        s3_codegen.ada_comment(
            "@param Value Bucket access-control policy value serialized "
            "before admission"
        )
        + "\n"
    )
    constructor_value_lines = constructor_value.splitlines(keepends=True)
    assert len(constructor_value_lines) == 2
    constructor_value_tag, constructor_value_continuation = (
        constructor_value_lines
    )
    assert constructor_value_tag.startswith("   --  @param Value ")
    assert constructor_value_continuation.startswith("   --  ")
    assert not constructor_value_continuation.startswith("   --  @")
    constructor_value_prefix = (
        s3_codegen.ada_comment("@param Value") + "\n"
    )
    constructor_repeated_value_tag = constructor_value_continuation.replace(
        "   --  ",
        "   --  @param Value ",
        1,
    )
    constructor_return = (
        s3_codegen.ada_comment(
            "@return Started owner-driven bucket access-control policy "
            "replacement"
        )
        + "\n"
    )
    constructor_wrong_return = (
        s3_codegen.ada_comment(
            "@return Started owner-driven bucket access-control policy "
            "inspection"
        )
        + "\n"
    )
    constructor_overwidth_return = (
        "   --  @return Started owner-driven bucket access-control policy "
        "replacement with deliberately overlong explanatory prose\n"
    )
    constructor_acl_block = generated_constructor_documentation(
        "bucket access-control policy",
        "PutBucketAcl",
    )

    def replace_constructor_block(mutated_block: str) -> str:
        assert mutated_block != constructor_acl_block
        assert mutation_provider.count(constructor_acl_block) == 1
        return mutation_provider.replace(
            constructor_acl_block,
            mutated_block,
            1,
        )

    constructor_swapped_facts_block = (
        constructor_acl_block.replace(
            "Required exact target bucket",
            "__SWAPPED_BUCKET_FACT__",
            1,
        )
        .replace(
            "Complete modeled non-resource PutBucketAcl controls",
            "Required exact target bucket",
            1,
        )
        .replace(
            "__SWAPPED_BUCKET_FACT__",
            "Complete modeled non-resource PutBucketAcl controls",
            1,
        )
    )
    assert constructor_swapped_facts_block != constructor_acl_block
    assert all(
        len(line) <= 79 for line in constructor_return.splitlines()
    )
    assert len(constructor_overwidth_return.removesuffix("\n")) > 79
    for label, invalid_source in {
        "missing Set association": mutation_provider.replace(
            constructor_set,
            "",
            1,
        ),
        "wrong Set association": mutation_provider.replace(
            constructor_set,
            constructor_set.replace("@param Set", "@param Completion_Set"),
            1,
        ),
        "reversed parameter order": mutation_provider.replace(
            constructor_set + constructor_client,
            constructor_client + constructor_set,
            1,
        ),
        "swapped parameter facts": replace_constructor_block(
            constructor_swapped_facts_block,
        ),
        "wrong Value fact": replace_constructor_block(
            constructor_acl_block.replace(
                constructor_value,
                constructor_value.replace(
                    "Bucket access-control policy",
                    "Bucket logging configuration",
                ),
                1,
            ),
        ),
        "missing Value continuation": replace_constructor_block(
            constructor_acl_block.replace(
                constructor_value,
                constructor_value_tag,
                1,
            ),
        ),
        "orphaned Value continuation": replace_constructor_block(
            constructor_acl_block.replace(
                constructor_value,
                constructor_value_tag
                + "\n"
                + constructor_value_continuation,
                1,
            ),
        ),
        "prefix-only Value association": replace_constructor_block(
            constructor_acl_block.replace(
                constructor_value,
                constructor_value_prefix,
                1,
            ),
        ),
        "repeated Value tag on continuation": replace_constructor_block(
            constructor_acl_block.replace(
                constructor_value,
                constructor_value_tag + constructor_repeated_value_tag,
                1,
            ),
        ),
        "missing return association": mutation_provider.replace(
            constructor_return,
            "",
            1,
        ),
        "wrong return association": mutation_provider.replace(
            constructor_return,
            constructor_return.replace("@return", "@param Result"),
            1,
        ),
        "wrong return description": mutation_provider.replace(
            constructor_return,
            constructor_wrong_return,
            1,
        ),
        "detached constructor documentation": mutation_provider.replace(
            constructor_return + "   function Set_ACL\n",
            constructor_return + "\n   function Set_ACL\n",
            1,
        ),
        "duplicate Set association": mutation_provider.replace(
            constructor_set,
            constructor_set * 2,
            1,
        ),
        "detached duplicate constructor block": (
            constructor_acl_block + mutation_provider
        ),
        "overwidth return association": mutation_provider.replace(
            constructor_return,
            constructor_overwidth_return,
            1,
        ),
    }.items():
        assert invalid_source != mutation_provider, (
            "generated mutation constructor negative did not mutate source"
        )
        try:
            assert_generated_mutation_constructor_documentation(
                invalid_source
            )
        except AssertionError:
            pass
        else:
            raise AssertionError(
                f"generated mutation constructor {label} was accepted"
            )

    bounded_spec = BOUNDED_REST_XML_SPEC.read_text(encoding="utf-8")
    check_bounded_generic_documentation(bounded_spec)
    first_formal = (
        "--  @formal Result_Type Typed provider result retained for Finish"
    )
    for candidate, diagnostic in (
        (
            bounded_spec.replace(first_formal + "\n", "", 1),
            "missing bounded generic @formal was accepted",
        ),
        (
            bounded_spec.replace(
                first_formal,
                first_formal + "\n" + first_formal,
                1,
            ),
            "duplicate bounded generic @formal was accepted",
        ),
        (
            bounded_spec.replace(
                "   --  Typed provider result retained for Finish.\n",
                "",
                1,
            ),
            "missing bounded formal declaration comment was accepted",
        ),
        (
            bounded_spec.replace(
                "     ( --  Completion set that owns the child exchange.\n",
                "     (",
                1,
            ),
            "missing bounded State discriminant comment was accepted",
        ),
        (
            bounded_spec.replace("\ngeneric\n", "\n\ngeneric\n", 1),
            "detached bounded generic documentation was accepted",
        ),
        (
            bounded_spec.replace(
                "   Operation_Name : String;",
                "   Wrong_Name : String;",
                1,
            ),
            "changed bounded generic declaration was accepted",
        ),
    ):
        reject_bounded_generic_documentation(
            bounded_spec, candidate, diagnostic
        )
    paginated_path = s3_operation.ROOT / (
        "src/"
        "flyology-object_storage-client-paginated_rest_xml_reads.ads"
    )
    paginated_spec = paginated_path.read_text(encoding="utf-8")
    _check_paginated_rest_xml_docs(paginated_spec)
    for candidate, diagnostic in (
        (
            paginated_spec.replace(
                "   --  Typed provider result retained for Finish.\n",
                "",
                1,
            ),
            "missing Paginated_REST_XML_Reads formal docs accepted",
        ),
        (
            paginated_spec.replace(
                "@param Collection_Limit",
                "@param Wrong",
                1,
            ),
            "wrong Paginated_REST_XML_Reads parameter accepted",
        ),
        (
            paginated_spec.replace(
                "Paginated_REST_XML_Reads is\n   --  Share",
                "Paginated_REST_XML_Reads is\n\n   --  Share",
                1,
            ),
            "detached Paginated_REST_XML_Reads package docs accepted",
        ),
        (
            paginated_spec.replace(
                "      Collection_Limit : Positive);",
                "      Wrong_Limit : Positive);",
                1,
            ),
            "changed Paginated_REST_XML_Reads skeleton accepted",
        ),
        (
            paginated_spec.replace(
                "   --  Typed provider result retained for Finish.",
                "   --  Typed provider result retained for Finish.\n"
                "   --  Typed provider result retained for Finish.",
                1,
            ),
            "duplicate Paginated_REST_XML_Reads formal docs accepted",
        ),
    ):
        _reject_paginated_docs(paginated_spec, candidate, diagnostic)

    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary).resolve()
        repository = root / "repository"
        dependency = root / "dependency"
        (repository / "src").mkdir(parents=True)
        dependency.mkdir()
        (repository / "src/owned.ads").write_text(
            "package Owned is end Owned;\n", encoding="utf-8"
        )
        (dependency / "external.ads").write_text(
            "package External is end External;\n", encoding="utf-8"
        )
        source_manifest = root / "gnatdoc-sources.txt"
        source_manifest.write_text(
            f"{repository / 'src/owned.ads'}\n"
            f"{dependency / 'external.ads'}\n",
            encoding="utf-8",
        )
        project_directory = repository / "tools"
        project_directory.mkdir()
        public_project = project_directory / "public-api.gpr"
        public_project.write_text(
            "project Public_API is\n"
            '   for Source_Files use ("owned.ads");\n'
            "end Public_API;\n",
            encoding="utf-8",
        )
        assert gnatdoc_diagnostics.check_source_manifest(
            source_manifest,
            repository,
            public_project,
            expected_public_source_count=1,
        ) == (1, 1)
        custom_spec = dependency / "custom_interface.ads"
        custom_body = dependency / "custom_implementation.adb"
        custom_spec.write_text(
            "package Custom_Interface is end Custom_Interface;\n",
            encoding="utf-8",
        )
        custom_body.write_text(
            "package body Custom_Implementation is "
            "end Custom_Implementation;\n",
            encoding="utf-8",
        )
        dependency_manifest = root / "gprls-dependency-sources.txt"
        dependency_manifest.write_text(
            f"   {custom_body}\n"
            f"   {repository / 'src/owned.ads'}\n"
            f"   {dependency / 'external.ads'}\n"
            f"   {custom_spec}\n"
            f"   {dependency / 'external.ads'}\n",
            encoding="utf-8",
        )
        normalized_manifest = root / "normalized-sources.txt"
        assert gnatdoc_diagnostics.normalize_source_manifests(
            source_manifest,
            dependency_manifest,
            normalized_manifest,
            repository,
            public_project,
            expected_public_source_count=1,
        ) == (1, 3, 2, 5, 4)
        assert normalized_manifest.read_text(encoding="utf-8") == "".join(
            f"{source}\n"
            for source in sorted(
                (
                    custom_body,
                    custom_spec,
                    dependency / "external.ads",
                    repository / "src/owned.ads",
                )
            )
        )
        empty_log = root / "empty-gnatdoc.log"
        empty_log.write_text("", encoding="utf-8")
        assert gnatdoc_diagnostics.check_diagnostics(
            empty_log, repository, normalized_manifest
        ) == 0
        custom_log = root / "custom-source-gnatdoc.log"
        custom_log.write_text(
            "custom_interface.ads:1:1: warning: custom dependency spec\n"
            "custom_implementation.adb:1:1: "
            "warning: custom dependency body\n",
            encoding="utf-8",
        )
        assert gnatdoc_diagnostics.check_diagnostics(
            custom_log, repository, normalized_manifest
        ) == 2
        normalization_sentinel = "previous accepted manifest\n"
        normalized_manifest.write_text(
            normalization_sentinel, encoding="utf-8"
        )
        invalid_dependency_manifest = root / "invalid-dependency-sources.txt"
        invalid_dependency_manifest.write_text(
            f"  {repository / 'src/owned.ads'}\n",
            encoding="utf-8",
        )
        try:
            gnatdoc_diagnostics.normalize_source_manifests(
                source_manifest,
                invalid_dependency_manifest,
                normalized_manifest,
                repository,
                public_project,
                expected_public_source_count=1,
            )
        except gnatdoc_diagnostics.Diagnostic_Error:
            pass
        else:
            raise AssertionError("invalid dependency grammar was accepted")
        assert normalized_manifest.read_text(encoding="utf-8") == (
            normalization_sentinel
        )
        dependency_directory = dependency / "directory.adb"
        dependency_directory.mkdir()
        non_ada_dependency = dependency / "not-ada.txt"
        non_ada_dependency.write_text("not Ada\n", encoding="utf-8")
        symlink_dependency = dependency / "external-link.ads"
        symlink_dependency.symlink_to(dependency / "external.ads")
        invalid_dependency_rows = (
            "",
            "\n",
            f"{dependency / 'external.ads'}\n",
            f" {dependency / 'external.ads'}\n",
            f"  {dependency / 'external.ads'}\n",
            f"    {dependency / 'external.ads'}\n",
            f"   {dependency / 'external.ads'} \n",
            "   relative/source.ads\n",
            f"   {non_ada_dependency}\n",
            f"   {root / 'missing.ads'}\n",
            f"   {dependency_directory}\n",
            f"   {symlink_dependency}\n",
            f"   {dependency / 'external.ads'}\n\n"
            f"   {dependency / 'external.ads'}\n",
        )
        for invalid_rows in invalid_dependency_rows:
            invalid_dependency_manifest.write_text(
                invalid_rows, encoding="utf-8"
            )
            try:
                gnatdoc_diagnostics.normalize_source_manifests(
                    source_manifest,
                    invalid_dependency_manifest,
                    normalized_manifest,
                    repository,
                    public_project,
                    expected_public_source_count=1,
                )
            except gnatdoc_diagnostics.Diagnostic_Error:
                pass
            else:
                raise AssertionError(
                    "invalid dependency source row was accepted"
                )
        invalid_dependency_manifest.write_bytes(b"\xff\n")
        try:
            gnatdoc_diagnostics.normalize_source_manifests(
                source_manifest,
                invalid_dependency_manifest,
                normalized_manifest,
                repository,
                public_project,
                expected_public_source_count=1,
            )
        except UnicodeError:
            pass
        else:
            raise AssertionError(
                "invalid dependency source encoding was accepted"
            )
        assert normalized_manifest.read_text(encoding="utf-8") == (
            normalization_sentinel
        )
        missing_direct_dependency = root / "missing-direct-dependency.txt"
        missing_direct_dependency.write_text(
            f"   {dependency / 'external.ads'}\n", encoding="utf-8"
        )
        try:
            gnatdoc_diagnostics.normalize_source_manifests(
                source_manifest,
                missing_direct_dependency,
                normalized_manifest,
                repository,
                public_project,
                expected_public_source_count=1,
            )
        except gnatdoc_diagnostics.Diagnostic_Error as error:
            assert "missing a direct source" in str(error)
        else:
            raise AssertionError("incomplete dependency closure was accepted")
        repository_body = repository / "src/owned.adb"
        repository_body.write_text(
            "package body Owned is end Owned;\n", encoding="utf-8"
        )
        repository_body_dependency = root / "repository-body-dependency.txt"
        repository_body_dependency.write_text(
            f"   {repository / 'src/owned.ads'}\n"
            f"   {repository_body}\n"
            f"   {dependency / 'external.ads'}\n",
            encoding="utf-8",
        )
        try:
            gnatdoc_diagnostics.normalize_source_manifests(
                source_manifest,
                repository_body_dependency,
                normalized_manifest,
                repository,
                public_project,
                expected_public_source_count=1,
            )
        except gnatdoc_diagnostics.Diagnostic_Error as error:
            assert "unexpected repository source" in str(error)
        else:
            raise AssertionError("repository body closure was accepted")
        for aliased_output in (source_manifest, dependency_manifest):
            try:
                gnatdoc_diagnostics.normalize_source_manifests(
                    source_manifest,
                    dependency_manifest,
                    aliased_output,
                    repository,
                    public_project,
                    expected_public_source_count=1,
                )
            except gnatdoc_diagnostics.Diagnostic_Error as error:
                assert "must differ from both raw inputs" in str(error)
            else:
                raise AssertionError(
                    "source manifest input alias was accepted"
                )
        normalization_target = root / "normalization-target.txt"
        normalization_target.write_text(
            normalization_sentinel, encoding="utf-8"
        )
        normalization_alias = root / "normalization-alias.txt"
        normalization_alias.symlink_to(normalization_target)
        try:
            gnatdoc_diagnostics.normalize_source_manifests(
                source_manifest,
                dependency_manifest,
                normalization_alias,
                repository,
                public_project,
                expected_public_source_count=1,
            )
        except gnatdoc_diagnostics.Diagnostic_Error as error:
            assert "must not be a symbolic link" in str(error)
        else:
            raise AssertionError("symbolic output manifest was accepted")
        assert normalization_target.read_text(encoding="utf-8") == (
            normalization_sentinel
        )
        try:
            gnatdoc_diagnostics.check_source_manifest(
                source_manifest, repository, public_project
            )
        except gnatdoc_diagnostics.Diagnostic_Error as error:
            assert "source count differs" in str(error)
        else:
            raise AssertionError("non-production public source count passed")
        missing_public_source = root / "missing-public-source.txt"
        missing_public_source.write_text(
            f"{dependency / 'external.ads'}\n", encoding="utf-8"
        )
        unexpected_repository_source = repository / "src/unexpected.ads"
        unexpected_repository_source.write_text(
            "package Unexpected is end Unexpected;\n", encoding="utf-8"
        )
        extra_public_source = root / "extra-public-source.txt"
        extra_public_source.write_text(
            f"{repository / 'src/owned.ads'}\n"
            f"{unexpected_repository_source}\n"
            f"{dependency / 'external.ads'}\n",
            encoding="utf-8",
        )
        contaminated_source_manifest = root / "contaminated-sources.txt"
        contaminated_source_manifest.write_text(
            "Setup\n"
            f"{repository / 'src/owned.ads'}\n"
            f"{dependency / 'external.ads'}\n",
            encoding="utf-8",
        )
        whitespace_source_manifests = []
        for name, affix in (("leading", " "), ("trailing", " ")):
            whitespace_manifest = root / f"{name}-whitespace-sources.txt"
            source_line = str(repository / "src/owned.ads")
            if name == "leading":
                source_line = affix + source_line
            else:
                source_line += affix
            whitespace_manifest.write_text(
                source_line + "\n", encoding="utf-8"
            )
            whitespace_source_manifests.append(whitespace_manifest)
        source_directory = dependency / "directory.ads"
        source_directory.mkdir()
        directory_source_manifest = root / "directory-source.txt"
        directory_source_manifest.write_text(
            f"{source_directory}\n", encoding="utf-8"
        )
        for invalid_source_manifest in (
            missing_public_source,
            extra_public_source,
            contaminated_source_manifest,
            *whitespace_source_manifests,
            directory_source_manifest,
        ):
            try:
                gnatdoc_diagnostics.check_source_manifest(
                    invalid_source_manifest,
                    repository,
                    public_project,
                    expected_public_source_count=1,
                )
            except gnatdoc_diagnostics.Diagnostic_Error:
                pass
            else:
                raise AssertionError(
                    "invalid public project source closure was accepted"
                )
        for source_count in (39, 41):
            count_project = project_directory / f"public-{source_count}.gpr"
            count_sources = []
            count_manifest = root / f"public-{source_count}-sources.txt"
            for index in range(source_count):
                name = f"public_{source_count}_{index:02d}.ads"
                source = repository / "src" / name
                source.write_text(
                    f"package Public_{source_count}_{index:02d} is end "
                    f"Public_{source_count}_{index:02d};\n",
                    encoding="utf-8",
                )
                count_sources.append(name)
            count_project.write_text(
                f"project Public_{source_count} is\n"
                "   for Source_Files use ("
                + ", ".join(f'\"{name}\"' for name in count_sources)
                + ");\n"
                f"end Public_{source_count};\n",
                encoding="utf-8",
            )
            count_manifest.write_text(
                "".join(
                    f"{repository / 'src' / name}\n"
                    for name in count_sources
                ),
                encoding="utf-8",
            )
            try:
                gnatdoc_diagnostics.check_source_manifest(
                    count_manifest, repository, count_project
                )
            except gnatdoc_diagnostics.Diagnostic_Error as error:
                assert "source count differs" in str(error)
            else:
                raise AssertionError(
                    f"public {source_count}-source closure was accepted"
                )

        def check_log(text: str) -> int:
            log = root / "gnatdoc.log"
            log.write_text(text, encoding="utf-8")
            return gnatdoc_diagnostics.check_diagnostics(
                log, repository, source_manifest
            )

        assert check_log(
            "external.ads:1:1: warning: dependency documentation\n"
        ) == 1
        materialization_log = root / "public-api-build-run.txt"
        materialization_log.write_text(
            "external.ads:1:1: warning: dependency compilation\n",
            encoding="utf-8",
        )
        assert gnatdoc_diagnostics.check_diagnostics(
            materialization_log, repository, source_manifest
        ) == 1
        materialization_log.write_text(
            "owned.ads:1:1: warning: repository compilation\n",
            encoding="utf-8",
        )
        try:
            gnatdoc_diagnostics.check_diagnostics(
                materialization_log, repository, source_manifest
            )
        except gnatdoc_diagnostics.Diagnostic_Error as error:
            assert "repository-owned project warning" in str(error)
        else:
            raise AssertionError(
                "repository-owned materialization warning was accepted"
            )
        assert check_log(
            f"{dependency / 'external.ads'}:1:1: "
            "warning: absolute dependency documentation\n"
        ) == 1
        duplicate_dependency = root / "duplicate-dependency"
        duplicate_dependency.mkdir()
        (duplicate_dependency / "external.ads").write_text(
            "package External is end External;\n", encoding="utf-8"
        )
        ambiguous_manifest = root / "ambiguous-sources.txt"
        ambiguous_manifest.write_text(
            f"{dependency / 'external.ads'}\n"
            f"{duplicate_dependency / 'external.ads'}\n",
            encoding="utf-8",
        )
        (root / "gnatdoc.log").write_text(
            "external.ads:1:1: warning: ambiguous dependency source\n",
            encoding="utf-8",
        )
        try:
            gnatdoc_diagnostics.check_diagnostics(
                root / "gnatdoc.log", repository, ambiguous_manifest
            )
        except gnatdoc_diagnostics.Diagnostic_Error:
            pass
        else:
            raise AssertionError("ambiguous dependency source was accepted")
        ambiguous_dependency_manifest = root / "ambiguous-dependency.txt"
        ambiguous_dependency_manifest.write_text(
            f"   {repository / 'src/owned.ads'}\n"
            f"   {dependency / 'external.ads'}\n"
            f"   {duplicate_dependency / 'external.ads'}\n",
            encoding="utf-8",
        )
        try:
            gnatdoc_diagnostics.normalize_source_manifests(
                source_manifest,
                ambiguous_dependency_manifest,
                normalized_manifest,
                repository,
                public_project,
                expected_public_source_count=1,
            )
        except gnatdoc_diagnostics.Diagnostic_Error as error:
            assert "basename is ambiguous" in str(error)
        else:
            raise AssertionError(
                "ambiguous dependency closure was accepted"
            )
        for rejected in (
            "owned.ads:1:1: warning: repository documentation\n",
            f"{repository / 'src/owned.ads'}:1:1: "
            "warning: absolute repository documentation\n",
            "src/owned.ads:1:1: warning: qualified repository documentation\n",
            "owned.ads:1:1: error: repository parse failure\n",
            "external.ads:1:1: error: dependency parse failure\n",
            "missing.ads:1:1: warning: unresolved source\n",
            "warning: diagnostic without a source path\n",
            "error: diagnostic without a source path\n",
            "owned.ads:1:1: Warning: changed diagnostic spelling\n",
        ):
            try:
                check_log(rejected)
            except gnatdoc_diagnostics.Diagnostic_Error:
                pass
            else:
                raise AssertionError(
                    "unclassified or repository GNATdoc diagnostic was "
                    "accepted"
                )
        (dependency / "owned.ads").write_text(
            "package Owned is end Owned;\n", encoding="utf-8"
        )
        source_manifest.write_text(
            f"{repository / 'src/owned.ads'}\n"
            f"{dependency / 'external.ads'}\n"
            f"{dependency / 'owned.ads'}\n",
            encoding="utf-8",
        )
        try:
            check_log(
                "owned.ads:1:1: warning: ambiguous owned source\n"
            )
        except gnatdoc_diagnostics.Diagnostic_Error:
            pass
        else:
            raise AssertionError(
                "repository/dependency basename collision was accepted"
            )
        for invalid_source in (
            "relative/source.ads\n",
            f"{root / 'missing.ads'}\n",
            "\n",
            f"{dependency / 'external.ads'}\n\n",
            f"{dependency / 'external.ads'}\n"
            f"{dependency / 'external.ads'}\n",
        ):
            invalid_manifest = root / "invalid-sources.txt"
            invalid_manifest.write_text(invalid_source, encoding="utf-8")
            try:
                gnatdoc_diagnostics.check_diagnostics(
                    root / "gnatdoc.log", repository, invalid_manifest
                )
            except gnatdoc_diagnostics.Diagnostic_Error:
                pass
            else:
                raise AssertionError("invalid source manifest was accepted")
        non_ada = root / "not-ada.txt"
        non_ada.write_text("not Ada\n", encoding="utf-8")
        invalid_manifest = root / "invalid-sources.txt"
        invalid_manifest.write_text(f"{non_ada}\n", encoding="utf-8")
        try:
            gnatdoc_diagnostics.check_diagnostics(
                root / "gnatdoc.log", repository, invalid_manifest
            )
        except gnatdoc_diagnostics.Diagnostic_Error:
            pass
        else:
            raise AssertionError("non-Ada source manifest entry was accepted")

        provider_source = (
            repository / "src/flyology-object_storage-client-buckets.ads"
        )
        provider_source.write_text(
            "package Flyology.Object_Storage.Client.Buckets is\n"
            "   --  Maintained adjacent public documentation.\n"
            "   --  @param Item Synthetic value\n"
            "   procedure Do_Thing (Item : Integer);\n"
            "end Flyology.Object_Storage.Client.Buckets;\n",
            encoding="utf-8",
        )
        source_manifest.write_text(
            f"{repository / 'src/owned.ads'}\n"
            f"{provider_source}\n"
            f"{dependency / 'external.ads'}\n",
            encoding="utf-8",
        )
        api_registry = root / "s3-operations.toml"
        api_registry.write_text(
            "[[operation]]\n"
            'name = "ExampleOperation"\n'
            'public_provider = "Flyology.Object_Storage.Client.Buckets"\n'
            'public_name = "Do_Thing"\n',
            encoding="utf-8",
        )
        site = root / "site"
        site.mkdir()
        (site / "index.html").write_text(
            "<!DOCTYPE html><h1>Index</h1>\n", encoding="utf-8"
        )
        provider_page = site / "provider.html"
        valid_provider_html = (
            "<!DOCTYPE html>"
            "<h1>Flyology.Object_Storage.Client.Buckets</h1>"
            "<h4>Do_Thing</h4>"
            "<pre>procedure Do_Thing (Item : Integer);</pre>"
            "<p>Maintained adjacent public documentation.</p>"
            "<h5>Parameters</h5><dl><dt>Item</dt>"
            "<dd><p>Synthetic value</p></dd></dl>"
        )
        provider_page.write_text(valid_provider_html, encoding="utf-8")
        assert gnatdoc_diagnostics.check_selected_apis(
            site,
            api_registry,
            ["ExampleOperation"],
            repository,
            source_manifest,
        ) == 1
        provider_source.write_text(
            "package Flyology.Object_Storage.Client.Buckets is\n"
            "   --  Maintained adjacent public documentation.\n"
            "   procedure Do_Thing (Item : Integer);\n"
            "   --  Maintained adjacent public documentation. Extended.\n"
            "   procedure Do_Thing (Item : Float);\n"
            "end Flyology.Object_Storage.Client.Buckets;\n",
            encoding="utf-8",
        )
        provider_page.write_text(
            valid_provider_html
            + "<h4>Do_Thing</h4>"
            + "<pre>procedure Do_Thing (Item : Float);</pre>"
            + "<p>Maintained adjacent public documentation.</p>",
            encoding="utf-8",
        )
        try:
            gnatdoc_diagnostics.check_selected_apis(
                site,
                api_registry,
                ["ExampleOperation"],
                repository,
                source_manifest,
            )
        except gnatdoc_diagnostics.Diagnostic_Error:
            pass
        else:
            raise AssertionError("non-bijective API comments were accepted")
        provider_source.write_text(
            "package Flyology.Object_Storage.Client.Buckets is\n"
            "   --  Maintained adjacent public documentation.\n"
            "   --  @param Item Synthetic value\n"
            "   procedure Do_Thing (Item : Integer);\n"
            "end Flyology.Object_Storage.Client.Buckets;\n",
            encoding="utf-8",
        )
        provider_page.write_text(valid_provider_html, encoding="utf-8")
        for rejected_operations in (
            ["ExampleOperation", "ExampleOperation"],
            ["UnknownOperation"],
            [],
        ):
            try:
                gnatdoc_diagnostics.check_selected_apis(
                    site,
                    api_registry,
                    rejected_operations,
                    repository,
                    source_manifest,
                )
            except gnatdoc_diagnostics.Diagnostic_Error:
                pass
            else:
                raise AssertionError(
                    "invalid documentation operation selection was accepted"
                )
        api_registry.write_text(
            api_registry.read_text(encoding="utf-8")
            + "[[operation]]\n"
            + 'name = "AmbiguousOperation"\n'
            + 'public_provider = "Flyology.Object_Storage.Client.Buckets"\n'
            + 'public_name = "do_thing"\n',
            encoding="utf-8",
        )
        try:
            gnatdoc_diagnostics.check_selected_apis(
                site,
                api_registry,
                ["ExampleOperation", "AmbiguousOperation"],
                repository,
                source_manifest,
            )
        except gnatdoc_diagnostics.Diagnostic_Error:
            pass
        else:
            raise AssertionError("ambiguous selected public API was accepted")
        api_registry.write_text(
            "[[operation]]\n"
            'name = "ExampleOperation"\n'
            'public_provider = "Flyology.Object_Storage.Client.Buckets"\n'
            'public_name = "Do_Thing"\n',
            encoding="utf-8",
        )
        malformed_registry = root / "malformed-registry.toml"
        malformed_registry.write_text("[[operation]\n", encoding="utf-8")
        try:
            gnatdoc_diagnostics.check_selected_apis(
                site,
                malformed_registry,
                ["ExampleOperation"],
                repository,
                source_manifest,
            )
        except gnatdoc_diagnostics.Diagnostic_Error:
            pass
        else:
            raise AssertionError("malformed operation registry was accepted")
        for invalid_html in (
            "<h1>Flyology.Object_Storage.Client.Buckets</h1>",
            "<h1>Flyology.Object_Storage.Client.Buckets</h1>"
            "<h4>Do_Thing</h4><pre>procedure Do_Thing;</pre>",
            "<h1>Flyology.Object_Storage.Client.Buckets</h1>"
            "<p>Do_Thing is only an ambiguous token match.</p>",
            "<h1>Flyology.Object_Storage.Client.Buckets</h1>"
            "<h4>Do_Thing</h4>"
            "<pre>procedure Do_Thing (Item : Integer);</pre>"
            "<p>Maintained adjacent public documentation. Stale.</p>",
        ):
            provider_page.write_text(invalid_html, encoding="utf-8")
            try:
                gnatdoc_diagnostics.check_selected_apis(
                    site,
                    api_registry,
                    ["ExampleOperation"],
                    repository,
                    source_manifest,
                )
            except gnatdoc_diagnostics.Diagnostic_Error:
                pass
            else:
                raise AssertionError(
                    "missing API or adjacent documentation was accepted"
                )
        provider_page.write_text(
            "<h1>Flyology.Object_Storage.Client.Buckets</h1>"
            "<h4>Do_Thing</h4><pre>procedure Do_Thing;</pre>"
            "<p>Different documentation.</p>",
            encoding="utf-8",
        )
        try:
            gnatdoc_diagnostics.check_selected_apis(
                site,
                api_registry,
                ["ExampleOperation"],
                repository,
                source_manifest,
            )
        except gnatdoc_diagnostics.Diagnostic_Error:
            pass
        else:
            raise AssertionError("stale API documentation was accepted")
        provider_page.write_text(valid_provider_html, encoding="utf-8")
        duplicate_page = site / "duplicate.html"
        duplicate_page.write_text(valid_provider_html, encoding="utf-8")
        try:
            gnatdoc_diagnostics.check_selected_apis(
                site,
                api_registry,
                ["ExampleOperation"],
                repository,
                source_manifest,
            )
        except gnatdoc_diagnostics.Diagnostic_Error:
            pass
        else:
            raise AssertionError("ambiguous documentation page was accepted")

    documentation_gate = (
        s3_operation.ROOT / "tools/build-api-docs.sh"
    ).read_text(encoding="utf-8")
    assert "uv run --python 3.13 -- python" in documentation_gate
    assert '>"$LOG_DIR/gnatdoc-run.txt" 2>&1' in documentation_gate
    assert "if ! alr -n exec -- gprbuild" in documentation_gate
    assert 'if ! alr -n exec -- "$GNATDOC_BIN"' in documentation_gate
    assert "tee" not in documentation_gate
    materialization_command = 'gprbuild -P"$PUBLIC_PROJECT" -p -c'
    direct_source_command = 'exec gprls -P"$1" -U -s >"$2" 2>"$3"'
    dependency_source_command = (
        'exec gprls -P"$1" -U -s -d >"$2" 2>"$3"'
    )
    assert materialization_command in documentation_gate
    assert documentation_gate.count(direct_source_command) == 1
    assert documentation_gate.count(dependency_source_command) == 1
    assert '-P "$PUBLIC_PROJECT"' in documentation_gate
    for artifact in (
        'DIRECT_SOURCE_MANIFEST="$LOG_DIR/gprls-direct-sources.txt"',
        'DIRECT_SOURCE_LOG="$LOG_DIR/gprls-direct-run.txt"',
        'DIRECT_SOURCE_DIAGNOSTICS="$LOG_DIR/gprls-direct-stderr.txt"',
        'DEPENDENCY_SOURCE_MANIFEST='
        '"$LOG_DIR/gprls-dependency-sources.txt"',
        'DEPENDENCY_SOURCE_LOG="$LOG_DIR/gprls-dependency-run.txt"',
        'DEPENDENCY_SOURCE_DIAGNOSTICS='
        '"$LOG_DIR/gprls-dependency-stderr.txt"',
        'SOURCE_NORMALIZATION_LOG='
        '"$LOG_DIR/gnatdoc-source-normalization.txt"',
    ):
        assert artifact in documentation_gate
    assert '[ -s "$DIRECT_SOURCE_DIAGNOSTICS" ]' in documentation_gate
    assert '[ -s "$DEPENDENCY_SOURCE_DIAGNOSTICS" ]' in documentation_gate
    assert '--direct-sources "$DIRECT_SOURCE_MANIFEST"' in documentation_gate
    assert (
        '--dependency-sources "$DEPENDENCY_SOURCE_MANIFEST"'
        in documentation_gate
    )
    assert "--normalize-sources-only" in documentation_gate
    assert '--public-project "$PUBLIC_PROJECT"' in documentation_gate
    assert "--check-sources-only" in documentation_gate
    assert "--check-log-only" in documentation_gate
    assert '--log "$PUBLIC_BUILD_LOG"' in documentation_gate
    assert "gnatdoc_diagnostics.py" in documentation_gate
    assert '--sources "$SOURCE_MANIFEST"' in documentation_gate
    assert '--site "$OUTPUT_DIR"' in documentation_gate
    assert "--operation" not in documentation_gate
    assert 'test -s "$OUTPUT_DIR/index.html"' in documentation_gate
    assert "Flyology.Object_Storage" in documentation_gate
    assert "--warnings" in documentation_gate
    public_build = documentation_gate.index(materialization_command)
    direct_gprls = documentation_gate.index(direct_source_command)
    direct_validation = documentation_gate.index(
        'if [ ! -s "$DIRECT_SOURCE_MANIFEST" ]'
    )
    dependency_gprls = documentation_gate.index(dependency_source_command)
    dependency_validation = documentation_gate.index(
        'if [ ! -s "$DEPENDENCY_SOURCE_MANIFEST" ]'
    )
    normalization = documentation_gate.index("--normalize-sources-only")
    source_check = documentation_gate.index("--check-sources-only")
    build_log_check = documentation_gate.index("--check-log-only")
    gnatdoc = documentation_gate.index(
        'if ! alr -n exec -- "$GNATDOC_BIN"'
    )
    assert (
        public_build
        < direct_gprls
        < direct_validation
        < dependency_gprls
        < dependency_validation
        < normalization
        < source_check
        < build_log_check
        < gnatdoc
    )
    public_build_failure = documentation_gate[
        documentation_gate.index("if ! alr -n exec -- gprbuild") :
        documentation_gate.index("if ! alr -n exec -- /bin/sh")
    ]
    assert " -U" not in public_build_failure
    assert " -c" in public_build_failure
    assert 'cat "$PUBLIC_BUILD_LOG" >&2' in public_build_failure
    assert "exit 1" in public_build_failure
    direct_gprls_start = documentation_gate.index(
        "if ! alr -n exec -- /bin/sh"
    )
    dependency_gprls_start = documentation_gate.index(
        "if ! alr -n exec -- /bin/sh", direct_validation
    )
    direct_gprls_failure = documentation_gate[
        direct_gprls_start:direct_validation
    ]
    assert 'cat "$DIRECT_SOURCE_LOG" "$DIRECT_SOURCE_DIAGNOSTICS"' in (
        direct_gprls_failure
    )
    assert "exit 1" in direct_gprls_failure
    direct_manifest_failure = documentation_gate[
        direct_validation:dependency_gprls_start
    ]
    assert "direct gprls did not produce a clean source stream" in (
        direct_manifest_failure
    )
    assert "exit 1" in direct_manifest_failure
    dependency_gprls_failure = documentation_gate[
        dependency_gprls_start:dependency_validation
    ]
    assert (
        'cat "$DEPENDENCY_SOURCE_LOG" '
        '"$DEPENDENCY_SOURCE_DIAGNOSTICS"'
        in dependency_gprls_failure
    )
    assert "exit 1" in dependency_gprls_failure
    dependency_manifest_failure = documentation_gate[
        dependency_validation:
        documentation_gate.rindex(
            "if ! alr -n exec -- uv run --python 3.13 -- python",
            0,
            normalization,
        )
    ]
    assert "dependency gprls did not produce a clean source stream" in (
        dependency_manifest_failure
    )
    assert "exit 1" in dependency_manifest_failure
    normalization_start = documentation_gate.rindex(
        "if ! alr -n exec -- uv run --python 3.13 -- python",
        0,
        normalization,
    )
    normalization_failure = documentation_gate[
        normalization_start:source_check
    ]
    assert 'cat "$SOURCE_NORMALIZATION_LOG" >&2' in normalization_failure
    assert "exit 1" in normalization_failure
    source_failure_gate = documentation_gate[source_check:gnatdoc]
    assert 'cat "$SOURCE_CHECK_LOG" >&2' in source_failure_gate
    assert "exit 1" in source_failure_gate
    build_log_failure_gate = documentation_gate[build_log_check:gnatdoc]
    assert 'cat "$PUBLIC_BUILD_CHECK_LOG" >&2' in (
        build_log_failure_gate
    )
    assert "exit 1" in build_log_failure_gate
    assert documentation_gate.index('test -s "$OUTPUT_DIR/index.html"') < (
        documentation_gate.index("Flyology.Object_Storage")
    ) < documentation_gate.rindex("gnatdoc_diagnostics.py")
    architecture = (
        s3_operation.ROOT / "docs/architecture/s3-operation-automation.md"
    ).read_text(encoding="utf-8")
    assert "maintained qualification path" in architecture
    assert "selected public APIs and their adjacent comments" in (
        " ".join(architecture.split())
    )
    assert 'find "$OUTPUT_DIR" -mindepth 1 -print -quit' in documentation_gate
    assert "output directory is not fresh and empty" in documentation_gate
    assert 'if [ -L "$OUTPUT_DIR" ]' in documentation_gate
    assert "rm " not in documentation_gate
    public_project = (
        s3_operation.ROOT
        / "tools/flyology_object_storage_public_api.gpr"
    ).read_text(encoding="utf-8")
    for required_library_shape in (
        'for Library_Name use "Flyology_Object_Storage_Public_API";',
        'for Library_Dir use "../obj/docs/public-api-library";',
        'for Library_Kind use "static";',
        'for Default_Switches ("Ada") use ("-gnatc");',
    ):
        assert required_library_shape in public_project
    for invalid_gate, invalid_project in (
        (
            documentation_gate.replace(
                materialization_command,
                'gprbuild -P"$PUBLIC_PROJECT" -p -U',
                1,
            ),
            public_project,
        ),
        (
            documentation_gate.replace(
                "if ! alr -n exec -- gprbuild",
                "alr -n exec -- gprbuild",
                1,
            ),
            public_project,
        ),
        (
            documentation_gate,
            public_project.replace('(\"-gnatc\")', '(\"-gnatp\")', 1),
        ),
        (
            documentation_gate,
            public_project.replace(
                'for Library_Kind use "static";', "", 1
            ),
        ),
        (
            documentation_gate.replace(
                "#!/usr/bin/env bash",
                '#!/usr/bin/env bash\n'
                '# exec gprls -P"$1" -U -s >"$2" 2>"$3"',
                1,
            ),
            public_project,
        ),
        (
            documentation_gate.replace(
                "#!/usr/bin/env bash",
                '#!/usr/bin/env bash\n'
                '# exec gprls -P"$1" -U -s -d >"$2" 2>"$3"',
                1,
            ),
            public_project,
        ),
    ):
        try:
            invalid_materialization = invalid_gate[
                invalid_gate.index("if ! alr -n exec -- gprbuild") :
                invalid_gate.index("if ! alr -n exec -- /bin/sh")
            ]
            assert materialization_command in invalid_materialization
            assert " -U" not in invalid_materialization
            assert 'cat "$PUBLIC_BUILD_LOG" >&2' in (
                invalid_materialization
            )
            assert "exit 1" in invalid_materialization
            assert invalid_gate.index(materialization_command) < (
                invalid_gate.index(direct_source_command)
            ) < invalid_gate.index(dependency_source_command) < (
                invalid_gate.index("--normalize-sources-only")
            ) < invalid_gate.index("--check-sources-only") < (
                invalid_gate.index("--check-log-only")
            ) < (
                invalid_gate.index(
                    'if ! alr -n exec -- "$GNATDOC_BIN"'
                )
            )
            for required_library_shape in (
                'for Library_Name use '
                '"Flyology_Object_Storage_Public_API";',
                'for Library_Dir use '
                '"../obj/docs/public-api-library";',
                'for Library_Kind use "static";',
                'for Default_Switches ("Ada") use ("-gnatc");',
            ):
                assert required_library_shape in invalid_project
        except (AssertionError, ValueError):
            pass
        else:
            raise AssertionError(
                "invalid public ALI materialization shape was accepted"
            )
    expected_public_sources = (
        "flyology-object_storage.ads",
        "flyology-object_storage-client.ads",
        "flyology-object_storage-client-bounded_rest_xml_reads.ads",
        "flyology-object_storage-client-buckets.ads",
        "flyology-object_storage-client-low_level.ads",
        "flyology-object_storage-client-objects.ads",
        "flyology-object_storage-client-paginated_rest_xml_reads.ads",
        "flyology-object_storage-client-rest_xml_mutations.ads",
        "flyology-object_storage-s3.ads",
        "flyology-object_storage-s3-acl.ads",
        "flyology-object_storage-s3-analytics.ads",
        "flyology-object_storage-s3-annotations.ads",
        "flyology-object_storage-s3-attributes.ads",
        "flyology-object_storage-s3-bucket_controls.ads",
        "flyology-object_storage-s3-buckets.ads",
        "flyology-object_storage-s3-copies.ads",
        "flyology-object_storage-s3-core.ads",
        "flyology-object_storage-s3-deletions.ads",
        "flyology-object_storage-s3-encryption.ads",
        "flyology-object_storage-s3-errors.ads",
        "flyology-object_storage-s3-intelligent_tiering.ads",
        "flyology-object_storage-s3-inventory.ads",
        "flyology-object_storage-s3-lifecycle.ads",
        "flyology-object_storage-s3-listings.ads",
        "flyology-object_storage-s3-logging.ads",
        "flyology-object_storage-s3-metadata_configurations.ads",
        "flyology-object_storage-s3-metadata_tables.ads",
        "flyology-object_storage-s3-metrics.ads",
        "flyology-object_storage-s3-model.ads",
        "flyology-object_storage-s3-multipart.ads",
        "flyology-object_storage-s3-multipart_uploads.ads",
        "flyology-object_storage-s3-notifications.ads",
        "flyology-object_storage-s3-object_lock.ads",
        "flyology-object_storage-s3-replication.ads",
        "flyology-object_storage-s3-sigv4.ads",
        "flyology-object_storage-s3-versioning.ads",
        "flyology-object_storage-s3-versions.ads",
        "flyology-object_storage-s3-website.ads",
        "flyology-object_storage-s3-xml.ads",
        "flyology-object_storage-tags.ads",
    )
    assert tuple(re.findall(r'"(flyology[^\"]+\.ads)"', public_project)) == (
        expected_public_sources
    )
    assert len(expected_public_sources) == 40
    gnatdoc_diagnostics_source = (
        s3_operation.ROOT / "tools/gnatdoc_diagnostics.py"
    ).read_text(encoding="utf-8")
    assert "EXPECTED_PUBLIC_SOURCE_COUNT = 40" in (
        gnatdoc_diagnostics_source
    )
    for source_normalization_contract in (
        'modes.add_argument("--normalize-sources-only"',
        'parser.add_argument("--direct-sources"',
        'parser.add_argument("--dependency-sources"',
        "dependency source closure is missing a direct source",
        "canonical source manifest must differ from both raw inputs",
        "canonical source manifest must not be a symbolic link",
        "os.replace(temporary_path, output_path)",
    ):
        assert source_normalization_contract in gnatdoc_diagnostics_source
    assert 're.fullmatch(r"   (/.*\\.(?:ads|adb))"' in (
        gnatdoc_diagnostics_source
    )
    assert 'modes.add_argument("--check-log-only"' in (
        gnatdoc_diagnostics_source
    )
    assert ".adb" not in public_project
    assert "-generated_" not in public_project
    assert "-backends" not in public_project
    assert "-server" not in public_project
    assert "flyology_object_storage_config.gpr" not in public_project

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
    batch_operations = [
        "PutBucketInventoryConfiguration",
        "PutBucketLogging",
        "PutBucketWebsite",
    ]
    qualification, commands = s3_operation.qualification_plan(
        registry, batch_operations
    )
    assert qualification == "generated_bucket_configuration_mutation_batch"
    assert len(commands) == 8
    documentation_commands = [
        command
        for command in commands
        if command[0] == "./tools/build-api-docs.sh"
    ]
    assert len(documentation_commands) == 1
    assert documentation_commands[0][-6:] == [
        "--operation",
        "PutBucketInventoryConfiguration",
        "--operation",
        "PutBucketLogging",
        "--operation",
        "PutBucketWebsite",
    ]
    try:
        s3_operation.qualification_plan(registry, batch_operations[:-1])
    except s3_operation.Audit_Error as error:
        assert "complete reviewed qualification lane" in str(error)
    else:
        raise AssertionError(
            "incomplete reviewed qualification lane was accepted"
        )
    try:
        s3_operation.qualification_plan(registry, ["PutBucketLogging"])
    except s3_operation.Audit_Error as error:
        assert "complete reviewed qualification lane" in str(error)
    else:
        raise AssertionError("singleton batch omission was accepted")
    try:
        s3_operation.qualification_plan(
            registry,
            ["PutBucketLogging", "PutBucketLogging"],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate batch operation was accepted")
    try:
        s3_operation.qualification_plan(
            registry,
            ["PutBucketLogging", "PutBucketAcl"],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed qualification lanes were accepted")
    list_qualification, list_commands = s3_operation.qualification_plan(
        registry, ["ListObjectsV2"]
    )
    assert list_qualification == "list_objects_v2"
    list_documentation = [
        command
        for command in list_commands
        if command[0] == "./tools/build-api-docs.sh"
    ]
    assert len(list_documentation) == 1
    assert list_documentation[0][-2:] == [
        "--operation",
        "ListObjectsV2",
    ]
    list_v1_qualification, list_v1_commands = (
        s3_operation.qualification_plan(registry, ["ListObjects"])
    )
    assert list_v1_qualification == "list_objects_v1"
    assert list_v1_commands == [
        [
            "uv",
            "run",
            "--python",
            "3.13",
            "--",
            "tools/verify-list-objects-v1-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
        [
            "./tools/build-api-docs.sh",
            "/private/tmp/fos-list-objects-v1-gnatdoc",
            "--operation",
            "ListObjects",
        ],
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    versions_qualification, versions_commands = (
        s3_operation.qualification_plan(registry, ["ListObjectVersions"])
    )
    assert versions_qualification == "list_object_versions"
    assert versions_commands == [
        [
            "uv",
            "run",
            "--python",
            "3.13",
            "--",
            "tools/verify-list-object-versions-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_list_object_versions_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
        [
            "./tools/build-api-docs.sh",
            "/private/tmp/fos-list-object-versions-gnatdoc",
            "--operation",
            "ListObjectVersions",
        ],
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    put_qualification, put_commands = s3_operation.qualification_plan(
        registry, ["PutObject"]
    )
    assert put_qualification == "put_object"
    assert put_commands[0] == [
        "uv",
        "run",
        "--python",
        "3.13",
        "--",
        "tools/verify-put-object-preparation.py",
    ]
    put_documentation = [
        command
        for command in put_commands
        if command[0] == "./tools/build-api-docs.sh"
    ]
    assert len(put_documentation) == 1
    assert put_documentation[0][-2:] == ["--operation", "PutObject"]
    abort_qualification, abort_commands = s3_operation.qualification_plan(
        registry, ["AbortMultipartUpload"]
    )
    assert abort_qualification == "abort_multipart_upload"
    assert abort_commands[:3] == [
        [
            "uv",
            "run",
            "--python",
            "3.13",
            "--",
            "tools/verify-abort-multipart-upload-preparation.py",
        ],
        ["./tools/verify-composable-client-fixtures.sh"],
        ["./tools/test-composable-client-fixtures-verifier.sh"],
    ]
    abort_documentation = [
        command
        for command in abort_commands
        if command[0] == "./tools/build-api-docs.sh"
    ]
    assert len(abort_documentation) == 1
    assert abort_documentation[0][-2:] == [
        "--operation",
        "AbortMultipartUpload",
    ]
    delete_qualification, delete_commands = s3_operation.qualification_plan(
        registry, ["DeleteObject"]
    )
    assert delete_qualification == "delete_object"
    assert delete_commands[:3] == [
        [
            "uv",
            "run",
            "--python",
            "3.13",
            "--",
            "tools/verify-delete-object-preparation.py",
        ],
        ["./tools/verify-composable-client-fixtures.sh"],
        ["./tools/test-composable-client-fixtures-verifier.sh"],
    ]
    delete_documentation = [
        command
        for command in delete_commands
        if command[0] == "./tools/build-api-docs.sh"
    ]
    assert len(delete_documentation) == 1
    assert delete_documentation[0][-2:] == [
        "--operation",
        "DeleteObject",
    ]
    delete_objects_public_name = "Delete_Objects"

    def assert_delete_objects_registry(candidate):
        entry = candidate.operations["DeleteObjects"]
        assert entry.get("public_name") == delete_objects_public_name
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "delete_objects"
        assert entry.get("ada_symbols") == [
            "Prepare_Delete_Objects",
            "Decode_Delete_Objects_Complete_Response",
            "Execute_Delete_Objects",
            "Delete_Objects_Operation",
            "Delete_Objects",
            "Finish",
        ]
        assert "no automatic replay" in entry["certainty"]
        assert "duplicate-preserving" in entry["certainty"]
        assert "do not prove" in entry["reconciliation"]
        assert (
            "tests/corpora/composable-client/"
            "delete-objects-certainty.tsv"
        ) in entry["evidence"]["corpus"]
        assert "tools/verify-delete-objects-preparation.py" in (
            entry["evidence"]["corpus"]
        )

    def reject_delete_objects_registry(candidate, label):
        try:
            assert_delete_objects_registry(candidate)
        except (AssertionError, KeyError, TypeError):
            return
        raise AssertionError(f"{label} DeleteObjects registry accepted")

    assert_delete_objects_registry(registry)
    missing_delete_objects_name = copy.deepcopy(registry)
    del missing_delete_objects_name.operations["DeleteObjects"][
        "public_name"
    ]
    reject_delete_objects_registry(
        missing_delete_objects_name,
        "missing public name",
    )
    wrong_delete_objects_name = copy.deepcopy(registry)
    wrong_delete_objects_name.operations["DeleteObjects"][
        "public_name"
    ] = "Delete_Object"
    reject_delete_objects_registry(
        wrong_delete_objects_name,
        "wrong public name",
    )
    cross_delete_objects_symbol = copy.deepcopy(registry)
    cross_delete_objects_symbol.operations["DeleteObjects"][
        "ada_symbols"
    ][0] = "Prepare_Delete_Object"
    reject_delete_objects_registry(
        cross_delete_objects_symbol,
        "cross-operation symbol",
    )
    delete_objects_qualification, delete_objects_commands = (
        s3_operation.qualification_plan(registry, ["DeleteObjects"])
    )
    assert delete_objects_qualification == "delete_objects"
    assert delete_objects_commands[:3] == [
        [
            "uv",
            "run",
            "--python",
            "3.13",
            "--",
            "tools/verify-delete-objects-preparation.py",
        ],
        ["./tools/verify-composable-client-fixtures.sh"],
        ["./tools/test-composable-client-fixtures-verifier.sh"],
    ]
    assert delete_objects_commands[3:6] == [
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert delete_objects_commands[6] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-objects-gnatdoc",
        "--operation",
        "DeleteObjects",
    ]
    assert delete_objects_commands[7:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    malformed_delete_objects_lane = copy.deepcopy(registry)
    malformed_delete_objects_lane.operations["DeleteObjects"][
        "qualification"
    ] = "missing_delete_objects_lane"
    try:
        s3_operation.qualification_plan(
            malformed_delete_objects_lane,
            ["DeleteObjects"],
        )
    except s3_operation.Audit_Error as error:
        assert "unknown qualification lane" in str(error)
    else:
        raise AssertionError("malformed DeleteObjects lane was accepted")
    try:
        s3_operation.qualification_plan(
            registry,
            ["DeleteObjects", "DeleteObjects"],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate DeleteObjects lane was accepted")
    try:
        s3_operation.qualification_plan(
            registry,
            ["DeleteObject", "DeleteObjects"],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed DeleteObjects lane was accepted")
    get_object_public_name = "Get_Whole"

    def assert_get_object_registry(candidate):
        entry = candidate.operations["GetObject"]
        assert entry.get("public_name") == get_object_public_name
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "get_object"
        assert entry.get("ada_symbols") == [
            "Prepare_Get_Object",
            "Decode_Get_Object_Response_Head",
            "Decode_Get_Object_Complete_Response",
            "Execute_Get_Object",
            "Whole_Get_Operation",
            "Get_Whole",
            "Range_Get_Operation",
            "Get_Range",
            "Finish",
        ]
        assert "must be echoed exactly" in entry["absence"]
        assert "exposes no bytes" in entry["certainty"]
        assert "does not recompute" in entry["exclusions"][0]
        assert "tools/verify-get-object-preparation.py" in (
            entry["evidence"]["corpus"]
        )

    def reject_get_object_registry(candidate, label):
        try:
            assert_get_object_registry(candidate)
        except (AssertionError, KeyError, TypeError):
            return
        raise AssertionError(f"{label} GetObject registry accepted")

    assert_get_object_registry(registry)
    missing_get_object_name = copy.deepcopy(registry)
    del missing_get_object_name.operations["GetObject"]["public_name"]
    reject_get_object_registry(
        missing_get_object_name,
        "missing public name",
    )
    wrong_get_object_name = copy.deepcopy(registry)
    wrong_get_object_name.operations["GetObject"]["public_name"] = (
        "Get_Range"
    )
    reject_get_object_registry(
        wrong_get_object_name,
        "wrong public name",
    )
    cross_get_object_symbol = copy.deepcopy(registry)
    cross_get_object_symbol.operations["GetObject"]["ada_symbols"][0] = (
        "Prepare_Head_Object"
    )
    reject_get_object_registry(
        cross_get_object_symbol,
        "cross-operation symbol",
    )
    get_object_qualification, get_object_commands = (
        s3_operation.qualification_plan(registry, ["GetObject"])
    )
    assert get_object_qualification == "get_object"
    assert get_object_commands[:3] == [
        [
            "uv",
            "run",
            "--python",
            "3.13",
            "--",
            "tools/verify-get-object-preparation.py",
        ],
        ["./tools/verify-composable-client-fixtures.sh"],
        ["./tools/test-composable-client-fixtures-verifier.sh"],
    ]
    assert get_object_commands[3:6] == [
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert get_object_commands[6] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-get-object-gnatdoc",
        "--operation",
        "GetObject",
    ]
    assert get_object_commands[7:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    malformed_get_object_lane = copy.deepcopy(registry)
    malformed_get_object_lane.operations["GetObject"]["qualification"] = (
        "missing_get_object_lane"
    )
    try:
        s3_operation.qualification_plan(
            malformed_get_object_lane,
            ["GetObject"],
        )
    except s3_operation.Audit_Error as error:
        assert "unknown qualification lane" in str(error)
    else:
        raise AssertionError("malformed GetObject lane was accepted")
    try:
        s3_operation.qualification_plan(
            registry,
            ["GetObject", "GetObject"],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate GetObject lane was accepted")
    try:
        s3_operation.qualification_plan(
            registry,
            ["GetObject", "DeleteObjects"],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed GetObject lane was accepted")
    head_object_public_name = "Head_Object"

    def assert_head_object_registry(candidate):
        entry = candidate.operations["HeadObject"]
        assert entry.get("public_name") == head_object_public_name
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "head_object"
        assert entry.get("ada_symbols") == [
            "Prepare_Head_Object",
            "Decode_Head_Object_Response",
            "Decode_Head_Object_Complete_Response",
            "Execute_Head_Object",
            "Head_Operation",
            "Head_Object",
            "Finish",
        ]
        assert "must be echoed exactly" in entry["absence"]
        assert "bind to the prepared request" in entry["certainty"]
        assert "no payload to recompute" in entry["exclusions"][0]
        assert "tools/verify-head-object-preparation.py" in (
            entry["evidence"]["corpus"]
        )

    def reject_head_object_registry(candidate, label):
        try:
            assert_head_object_registry(candidate)
        except (AssertionError, KeyError, TypeError):
            return
        raise AssertionError(f"{label} HeadObject registry accepted")

    assert_head_object_registry(registry)
    missing_head_object_name = copy.deepcopy(registry)
    del missing_head_object_name.operations["HeadObject"]["public_name"]
    reject_head_object_registry(
        missing_head_object_name,
        "missing public name",
    )
    wrong_head_object_name = copy.deepcopy(registry)
    wrong_head_object_name.operations["HeadObject"]["public_name"] = "Head"
    reject_head_object_registry(
        wrong_head_object_name,
        "wrong public name",
    )
    cross_head_object_symbol = copy.deepcopy(registry)
    cross_head_object_symbol.operations["HeadObject"]["ada_symbols"][0] = (
        "Prepare_Head_Bucket"
    )
    reject_head_object_registry(
        cross_head_object_symbol,
        "cross-operation symbol",
    )
    head_object_qualification, head_object_commands = (
        s3_operation.qualification_plan(registry, ["HeadObject"])
    )
    assert head_object_qualification == "head_object"
    assert head_object_commands[:4] == [
        [
            "uv",
            "run",
            "--python",
            "3.13",
            "--",
            "tools/verify-head-object-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert head_object_commands[4] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-head-object-gnatdoc",
        "--operation",
        "HeadObject",
    ]
    assert head_object_commands[5:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    malformed_head_object_lane = copy.deepcopy(registry)
    malformed_head_object_lane.operations["HeadObject"]["qualification"] = (
        "missing_head_object_lane"
    )
    try:
        s3_operation.qualification_plan(
            malformed_head_object_lane,
            ["HeadObject"],
        )
    except s3_operation.Audit_Error as error:
        assert "unknown qualification lane" in str(error)
    else:
        raise AssertionError("malformed HeadObject lane was accepted")
    try:
        s3_operation.qualification_plan(
            registry,
            ["HeadObject", "HeadObject"],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate HeadObject lane was accepted")
    try:
        s3_operation.qualification_plan(
            registry,
            ["HeadObject", "GetObject"],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed HeadObject lane was accepted")
    copy_qualification, copy_commands = s3_operation.qualification_plan(
        registry, ["CopyObject"]
    )
    assert copy_qualification == "copy_object"
    assert copy_commands[:3] == [
        [
            "uv",
            "run",
            "--python",
            "3.13",
            "--",
            "tools/verify-copy-object-preparation.py",
        ],
        ["./tools/verify-composable-client-fixtures.sh"],
        ["./tools/test-composable-client-fixtures-verifier.sh"],
    ]
    copy_documentation = [
        command
        for command in copy_commands
        if command[0] == "./tools/build-api-docs.sh"
    ]
    assert len(copy_documentation) == 1
    assert copy_documentation[0][-2:] == ["--operation", "CopyObject"]
    create_bucket_qualification, create_bucket_commands = (
        s3_operation.qualification_plan(registry, ["CreateBucket"])
    )
    assert create_bucket_qualification == "create_bucket"
    assert create_bucket_commands[0] == [
        "uv",
        "run",
        "--python",
        "3.13",
        "--",
        "tools/verify-create-bucket-preparation.py",
    ]
    create_bucket_documentation = [
        command
        for command in create_bucket_commands
        if command[0] == "./tools/build-api-docs.sh"
    ]
    assert len(create_bucket_documentation) == 1
    assert create_bucket_documentation[0][-2:] == [
        "--operation",
        "CreateBucket",
    ]
    create_multipart_qualification, create_multipart_commands = (
        s3_operation.qualification_plan(
            registry, ["CreateMultipartUpload"]
        )
    )
    assert create_multipart_qualification == "create_multipart_upload"
    assert create_multipart_commands[:3] == [
        [
            "uv",
            "run",
            "--python",
            "3.13",
            "--",
            "tools/verify-create-multipart-upload-preparation.py",
        ],
        ["./tools/verify-composable-client-fixtures.sh"],
        ["./tools/test-composable-client-fixtures-verifier.sh"],
    ]
    create_multipart_documentation = [
        command
        for command in create_multipart_commands
        if command[0] == "./tools/build-api-docs.sh"
    ]
    assert len(create_multipart_documentation) == 1
    assert create_multipart_documentation[0][-2:] == [
        "--operation",
        "CreateMultipartUpload",
    ]
    get_location_qualification, get_location_commands = (
        s3_operation.qualification_plan(registry, ["GetBucketLocation"])
    )
    assert get_location_qualification == "get_bucket_location"
    assert get_location_commands[0] == [
        "uv",
        "run",
        "--python",
        "3.13",
        "--",
        "tools/verify-get-bucket-location-preparation.py",
    ]
    get_location_documentation = [
        command
        for command in get_location_commands
        if command[0] == "./tools/build-api-docs.sh"
    ]
    assert len(get_location_documentation) == 1
    assert get_location_documentation[0][-2:] == [
        "--operation",
        "GetBucketLocation",
    ]
    head_bucket_qualification, head_bucket_commands = (
        s3_operation.qualification_plan(registry, ["HeadBucket"])
    )
    assert head_bucket_qualification == "head_bucket"
    assert head_bucket_commands[0] == [
        "uv",
        "run",
        "--python",
        "3.13",
        "--",
        "tools/verify-head-bucket-preparation.py",
    ]
    head_bucket_documentation = [
        command
        for command in head_bucket_commands
        if command[0] == "./tools/build-api-docs.sh"
    ]
    assert len(head_bucket_documentation) == 1
    assert head_bucket_documentation[0][-2:] == [
        "--operation",
        "HeadBucket",
    ]
    list_buckets_qualification, list_buckets_commands = (
        s3_operation.qualification_plan(registry, ["ListBuckets"])
    )
    assert list_buckets_qualification == "list_buckets"
    assert list_buckets_commands[0] == [
        "uv",
        "run",
        "--python",
        "3.13",
        "--",
        "tools/verify-list-buckets-preparation.py",
    ]
    list_buckets_documentation = [
        command
        for command in list_buckets_commands
        if command[0] == "./tools/build-api-docs.sh"
    ]
    assert len(list_buckets_documentation) == 1
    assert list_buckets_documentation[0][-2:] == [
        "--operation",
        "ListBuckets",
    ]
    list_uploads_qualification, list_uploads_commands = (
        s3_operation.qualification_plan(registry, ["ListMultipartUploads"])
    )
    assert list_uploads_qualification == "list_multipart_uploads"
    assert list_uploads_commands[0] == [
        "uv",
        "run",
        "--python",
        "3.13",
        "--",
        "tools/verify-list-multipart-uploads-preparation.py",
    ]
    list_uploads_documentation = [
        command
        for command in list_uploads_commands
        if command[0] == "./tools/build-api-docs.sh"
    ]
    assert len(list_uploads_documentation) == 1
    assert list_uploads_documentation[0][-2:] == [
        "--operation",
        "ListMultipartUploads",
    ]
    tagging_lanes = {
        "DeleteObjectTagging": (
            "delete_object_tagging",
            "/private/tmp/fos-delete-object-tagging-gnatdoc",
        ),
        "GetObjectTagging": (
            "get_object_tagging",
            "/private/tmp/fos-get-object-tagging-gnatdoc",
        ),
        "PutObjectTagging": (
            "put_object_tagging",
            "/private/tmp/fos-put-object-tagging-gnatdoc",
        ),
    }
    tagging_public_names = {
        "DeleteObjectTagging": "Delete_Tags",
        "GetObjectTagging": "Get_Tags",
        "PutObjectTagging": "Put_Tags",
    }

    def assert_tagging_public_names(candidate):
        actual = {
            operation: candidate.operations[operation].get("public_name")
            for operation in tagging_public_names
        }
        assert actual == tagging_public_names
        assert all(isinstance(value, str) for value in actual.values())
        assert len(set(actual.values())) == len(tagging_public_names)

    def reject_tagging_public_names(candidate, label):
        try:
            assert_tagging_public_names(candidate)
        except (AssertionError, TypeError):
            return
        raise AssertionError(f"{label} object-tagging public names accepted")

    assert_tagging_public_names(registry)
    missing_tagging_public_name = copy.deepcopy(registry)
    del missing_tagging_public_name.operations["DeleteObjectTagging"][
        "public_name"
    ]
    reject_tagging_public_names(
        missing_tagging_public_name,
        "missing",
    )
    wrong_tagging_public_name = copy.deepcopy(registry)
    wrong_tagging_public_name.operations["GetObjectTagging"][
        "public_name"
    ] = "Get_Object_Tags"
    reject_tagging_public_names(wrong_tagging_public_name, "wrong")
    swapped_tagging_public_names = copy.deepcopy(registry)
    swapped_tagging_public_names.operations["DeleteObjectTagging"][
        "public_name"
    ] = "Get_Tags"
    swapped_tagging_public_names.operations["GetObjectTagging"][
        "public_name"
    ] = "Delete_Tags"
    reject_tagging_public_names(swapped_tagging_public_names, "swapped")
    duplicate_tagging_public_name = copy.deepcopy(registry)
    duplicate_tagging_public_name.operations["PutObjectTagging"][
        "public_name"
    ] = "Get_Tags"
    reject_tagging_public_names(duplicate_tagging_public_name, "duplicate")
    malformed_tagging_public_name = copy.deepcopy(registry)
    malformed_tagging_public_name.operations["PutObjectTagging"][
        "public_name"
    ] = ["Put_Tags"]
    reject_tagging_public_names(malformed_tagging_public_name, "malformed")
    for operation, (lane, root) in tagging_lanes.items():
        qualification, commands = s3_operation.qualification_plan(
            registry, [operation]
        )
        assert qualification == lane
        assert commands[:3] == [
            [
                "uv",
                "run",
                "--python",
                "3.13",
                "--",
                "tools/verify-object-tagging-preparation.py",
            ],
            ["./tools/verify-composable-client-fixtures.sh"],
            ["./tools/test-composable-client-fixtures-verifier.sh"],
        ]
        assert commands[3:6] == [
            ["@tests", "alr", "-n", "build"],
            ["@tests", "./bin/s3_http_socket_corpus"],
            ["./tools/verify-coverage.sh"],
        ]
        assert commands[6] == [
            "./tools/build-api-docs.sh",
            root,
            "--operation",
            operation,
        ]
        assert commands[7:] == [
            ["./tools/ci/check-repository.sh", "{model}"],
            ["git", "diff", "--check"],
        ]
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "DeleteObjectTagging",
                "GetObjectTagging",
                "PutObjectTagging",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed object-tagging lanes were accepted")
    try:
        s3_operation.qualification_plan(registry, [])
    except s3_operation.Audit_Error as error:
        assert "at least one operation is required" in str(error)
    else:
        raise AssertionError("empty object-tagging lane was accepted")
    try:
        s3_operation.qualification_plan(
            registry,
            ["PutObjectTagging", "PutObjectTagging"],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate object-tagging operation was accepted")
    malformed_tagging = copy.deepcopy(registry)
    malformed_tagging.operations["DeleteObjectTagging"]["qualification"] = (
        "missing_object_tagging_lane"
    )
    try:
        s3_operation.qualification_plan(
            malformed_tagging, ["DeleteObjectTagging"]
        )
    except s3_operation.Audit_Error as error:
        assert "unknown qualification lane" in str(error)
    else:
        raise AssertionError("missing object-tagging lane was accepted")
    omitted_tagging = copy.deepcopy(registry)
    omitted_tagging.operations["PutObjectTagging"]["qualification"] = (
        "delete_object_tagging"
    )
    try:
        s3_operation.qualification_plan(
            omitted_tagging, ["DeleteObjectTagging"]
        )
    except s3_operation.Audit_Error as error:
        assert "complete reviewed qualification lane" in str(error)
    else:
        raise AssertionError("omitted object-tagging operation was accepted")
    cross_family_tagging = copy.deepcopy(registry)
    cross_family_tagging.operations["GetObjectTagging"]["qualification"] = (
        "delete_object_tagging"
    )
    try:
        s3_operation.qualification_plan(
            cross_family_tagging,
            ["DeleteObjectTagging", "GetObjectTagging"],
        )
    except s3_operation.Audit_Error as error:
        assert "one provider and family" in str(error)
    else:
        raise AssertionError("cross-family object-tagging lane was accepted")
    get_versioning_qualification, get_versioning_commands = (
        s3_operation.qualification_plan(registry, ["GetBucketVersioning"])
    )
    assert get_versioning_qualification == "get_bucket_versioning"
    assert get_versioning_commands[0] == [
        "uv",
        "run",
        "--python",
        "3.13",
        "--",
        "tools/verify-get-bucket-versioning-preparation.py",
    ]
    get_versioning_documentation = [
        command
        for command in get_versioning_commands
        if command[0] == "./tools/build-api-docs.sh"
    ]
    assert len(get_versioning_documentation) == 1
    assert get_versioning_documentation[0][-2:] == [
        "--operation",
        "GetBucketVersioning",
    ]
    delete_bucket_qualification, delete_bucket_commands = (
        s3_operation.qualification_plan(registry, ["DeleteBucket"])
    )
    assert delete_bucket_qualification == "delete_bucket"
    assert delete_bucket_commands[0] == [
        "uv",
        "run",
        "--python",
        "3.13",
        "--",
        "tools/verify-delete-bucket-preparation.py",
    ]
    delete_bucket_documentation = [
        command
        for command in delete_bucket_commands
        if command[0] == "./tools/build-api-docs.sh"
    ]
    assert len(delete_bucket_documentation) == 1
    assert delete_bucket_documentation[0][-2:] == [
        "--operation",
        "DeleteBucket",
    ]
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
        raise AssertionError(
            "unrelated reviewed XML payload alias was accepted"
        )

    stale = copy.deepcopy(negative)
    stale["model_sha256"] = "0" * 64
    with tempfile.TemporaryDirectory(
        prefix="s3-operation-registry-"
    ) as directory:
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
    with tempfile.TemporaryDirectory(
        prefix="s3-operation-registry-"
    ) as directory:
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
        generated_mutations = {
            item.operation: item for item in s3_codegen.GENERATED_MUTATIONS
        }
        for operation, expected in {
            "PutBucketAcl": ("PUT", "acl", True, True),
            "PutBucketInventoryConfiguration": (
                "PUT", "inventory", False, False
            ),
            "PutBucketLogging": ("PUT", "logging", True, True),
            "PutBucketWebsite": ("PUT", "website", True, True),
        }.items():
            contract = s3_codegen.mutation_http_contract(
                model, generated_mutations[operation]
            )
            assert (
                contract.method,
                contract.subresource,
                contract.has_content_md5,
                contract.requires_checksum,
            ) == expected
        invalid_mutation_model = copy.deepcopy(model)
        invalid_mutation_model["operations"]["PutBucketLogging"]["http"][
            "requestUri"
        ] += "&unsupported"
        try:
            s3_codegen.mutation_http_contract(
                invalid_mutation_model,
                generated_mutations["PutBucketLogging"],
            )
        except s3_operation.Audit_Error:
            pass
        else:
            raise AssertionError(
                "multi-query generated mutation binding was accepted"
            )
        invalid_checksum_model = copy.deepcopy(model)
        logging_input = invalid_checksum_model["operations"][
            "PutBucketLogging"
        ]["input"]["shape"]
        del invalid_checksum_model["shapes"][logging_input]["members"][
            "ChecksumAlgorithm"
        ]
        try:
            s3_codegen.mutation_http_contract(
                invalid_checksum_model,
                generated_mutations["PutBucketLogging"],
            )
        except s3_operation.Audit_Error:
            pass
        else:
            raise AssertionError(
                "required checksum without its algorithm member was accepted"
            )
        invalid_md5_model = copy.deepcopy(model)
        invalid_md5_model["shapes"][logging_input]["members"]["ContentMD5"][
            "locationName"
        ] = "x-unexpected-md5"
        try:
            s3_codegen.mutation_http_contract(
                invalid_md5_model,
                generated_mutations["PutBucketLogging"],
            )
        except s3_operation.Audit_Error:
            pass
        else:
            raise AssertionError("unexpected ContentMD5 binding was accepted")
        post_mutation_model = copy.deepcopy(model)
        post_mutation_model["operations"]["PutBucketLogging"]["http"].update(
            method="POST",
            requestUri="/{Bucket}?metadataConfiguration",
        )
        post_contract = s3_codegen.mutation_http_contract(
            post_mutation_model,
            generated_mutations["PutBucketLogging"],
        )
        assert (post_contract.method, post_contract.subresource) == (
            "POST",
            "metadataConfiguration",
        )
        metadata_contract = s3_codegen.metadata_mutation_model_contract(model)
        assert set(metadata_contract["operations"]) == {
            "CreateBucketMetadataConfiguration",
            "UpdateBucketMetadataAnnotationTableConfiguration",
            "UpdateBucketMetadataInventoryTableConfiguration",
            "UpdateBucketMetadataJournalTableConfiguration",
        }
        assert metadata_contract["enums"]["TableSseAlgorithm"] == [
            "aws:kms",
            "AES256",
        ]
        invalid_metadata_required = copy.deepcopy(model)
        invalid_metadata_required["shapes"]["MetadataConfiguration"][
            "required"
        ] = []
        try:
            s3_codegen.metadata_mutation_model_contract(
                invalid_metadata_required
            )
        except s3_operation.Audit_Error:
            pass
        else:
            raise AssertionError(
                "metadata mutation missing required member was accepted"
            )
        invalid_metadata_enum = copy.deepcopy(model)
        invalid_metadata_enum["shapes"]["TableSseAlgorithm"]["enum"].append(
            "provider-default"
        )
        try:
            s3_codegen.metadata_mutation_model_contract(invalid_metadata_enum)
        except s3_operation.Audit_Error:
            pass
        else:
            raise AssertionError(
                "metadata mutation expanded enum was accepted"
            )
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
