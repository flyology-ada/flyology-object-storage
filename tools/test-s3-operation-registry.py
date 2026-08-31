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
    (
        "Create_Metadata_Configuration",
        "bucket metadata configuration",
        "CreateBucketMetadataConfiguration",
    ),
    (
        "Set_Metadata_Inventory_Table_Configuration",
        "metadata inventory-table configuration",
        "UpdateBucketMetadataInventoryTableConfiguration",
    ),
    (
        "Set_Metadata_Journal_Table_Configuration",
        "metadata journal-table configuration",
        "UpdateBucketMetadataJournalTableConfiguration",
    ),
    (
        "Set_Metadata_Annotation_Table_Configuration",
        "metadata annotation-table configuration",
        "UpdateBucketMetadataAnnotationTableConfiguration",
    ),
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


def generated_overload_comment(
    source: str,
    marker: str,
    next_prefix: str,
) -> tuple[str, ...]:
    lines = source.splitlines()
    positions = [
        index
        for index, line in enumerate(lines[:-1])
        if line == marker and lines[index + 1].startswith(next_prefix)
    ]
    assert len(positions) == 1, (
        f"generated overload declaration count differs: {marker}"
    )
    cursor = positions[0] - 1
    block = []
    while cursor >= 0 and lines[cursor].startswith("   --  "):
        block.append(lines[cursor][7:])
        cursor -= 1
    assert block, f"generated overload documentation is detached: {marker}"
    return tuple(reversed(block))


def generated_logical_tags(comment: tuple[str, ...]) -> tuple[str, ...]:
    tags: list[str] = []
    for line in comment:
        if line.startswith("@param ") or line.startswith("@return "):
            tags.append(line)
        elif tags:
            assert line and not line.startswith("@"), (
                "generated documentation continuation is malformed"
            )
            tags[-1] += " " + line
    return tuple(tags)


def assert_generated_mutation_low_level_documentation(source: str) -> None:
    for item in s3_codegen.GENERATED_MUTATIONS:
        prepare = generated_leading_comment(
            source,
            f"   function {item.low_prepare}",
        )
        assert generated_logical_tags(prepare) == (
            "@param Origin Exact HTTP origin used for routing and signing",
            "@param Style Caller-selected S3 addressing style",
            "@param Bucket Required exact target bucket",
            f"@param Value {item.label.capitalize()} value serialized before "
            "admission",
            "@param Parameters Complete modeled non-resource "
            f"{item.operation} controls",
            "@param Identity Credentials borrowed only while signing the "
            "request",
            "@param Region Exact SigV4 signing region",
            "@param Timestamp Exact SigV4 signing timestamp",
            "@param Limits Caller-selected bounded XML limits",
            "@return Prepared signed request with an owned one-shot body",
        ), f"generated {item.operation} Prepare documentation differs"
        execute = generated_leading_comment(
            source,
            f"   function {item.low_execute}",
        )
        assert generated_logical_tags(execute) == (
            "@param Client HTTP client retained through terminal drain",
            "@param Prepared Exact prepared request and owned body",
            "@param Timeout Whole request and drain budget",
            "@param Token Caller-selected cancellation source or null",
            "@param Limits Caller-selected bounded response XML limits",
            "@return Complete modeled response or structured rejection",
        ), f"generated {item.operation} Execute documentation differs"
        start = generated_leading_comment(
            source,
            f"   procedure {item.ada_stem}",
        )
        assert generated_logical_tags(start) == (
            "@param Client HTTP client retained through terminal drain",
            "@param Prepared Exact prepared request retained through drain",
            "@param Source One-shot request body source",
            "@param Sink Bounded response body sink",
            "@param Deadline Absolute admission, exchange, and drain limit",
            "@param Token Caller-selected cancellation source or null",
            "@param Operation Caller-owned HTTP exchange operation",
        ), f"generated {item.operation} Start documentation differs"
        assert all(
            len("   --  " + line) <= 79
            for comment in (prepare, execute, start)
            for line in comment
        ), f"generated {item.operation} Low_Level documentation is overwidth"


def assert_generated_mutation_terminal_documentation(source: str) -> None:
    for item in s3_codegen.GENERATED_MUTATIONS:
        finish = generated_overload_comment(
            source,
            "   procedure Finish",
            f"     (Operation : in out {item.operation_type};",
        )
        assert generated_logical_tags(finish) == (
            "@param Operation Terminal owner-driven operation consumed",
            "@param Result Complete typed terminal evidence",
        ), f"generated {item.operation} Finish documentation differs"
        sync = generated_overload_comment(
            source,
            f"   function {item.public_name}",
            "     (Client",
        )
        assert generated_logical_tags(sync) == (
            "@param Client HTTP client retained through terminal drain",
            "@param Origin Exact HTTP origin used for routing and signing",
            "@param Bucket Required exact target bucket",
            f"@param Value {item.label.capitalize()} value serialized before "
            "admission",
            "@param Parameters Complete modeled non-resource "
            f"{item.operation} controls",
            "@param Identity Credentials borrowed only while signing the "
            "request",
            "@param Region Exact SigV4 signing region",
            "@param Style Caller-selected S3 addressing style",
            "@param Timeout Whole owner-driven operation budget",
            "@param Token Caller-selected cancellation source or null",
            "@param Limits Caller-selected bounded XML limits",
            f"@return Terminal typed {item.label} replacement evidence",
        ), f"generated {item.operation} synchronous documentation differs"
        assert all(
            len("   --  " + line) <= 79
            for comment in (finish, sync)
            for line in comment
        ), f"generated {item.operation} terminal documentation is overwidth"


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
            elif len(logical) == 1:
                assert line and not line.startswith("@"), (
                    f"generated {public_name} constructor summary "
                    "continuation is malformed"
                )
                logical[0] += " " + line
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
    "formal_associations": (
        "@formal Result_Type Typed provider result retained for Finish",
        "@formal Operation_Name Operation name used in diagnostic messages",
        "@formal Start_Exchange Start the operation-specific child exchange",
        "@formal Decode_Response Decode one complete page into Result_Type",
        "@formal Normalize_Failure Map a terminal exchange failure to "
        "Result_Type",
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
    expected_package = (
        *_PAGINATED_DOCUMENTATION["package"],
        *_PAGINATED_DOCUMENTATION["formal_associations"],
    )
    assert bounded_leading_comment(lines, "generic", "--  ") == (
        expected_package
    ), "Paginated_REST_XML_Reads generic documentation differs"
    assert _paginated_following(lines, package_marker) == (
        expected_package
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
            r"\s*--  @(field|formal|param)(?: [^ ]+)(?: .+)", line
        )
        if match is not None:
            tags[match.group(1)] += 1
        elif re.match(r"\s*--  @", line):
            raise AssertionError(
                "Paginated_REST_XML_Reads documentation tag is malformed"
            )
    assert tags == Counter({"field": 1, "formal": 10, "param": 19}), (
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

    mutation_low_level = s3_codegen._generated_mutation_low_level_spec(
        s3_codegen.GENERATED_MUTATIONS
    )
    assert_generated_mutation_low_level_documentation(mutation_low_level)
    prepare_return = s3_codegen.ada_comment(
        "@return Prepared signed request with an owned one-shot body"
    )
    invalid_low_level = mutation_low_level.replace(
        prepare_return + "\n",
        "",
        1,
    )
    assert invalid_low_level != mutation_low_level
    try:
        assert_generated_mutation_low_level_documentation(invalid_low_level)
    except AssertionError:
        pass
    else:
        raise AssertionError(
            "generated mutation missing Prepare return was accepted"
        )

    mutation_provider = s3_codegen._generated_mutation_provider_spec(
        s3_codegen.GENERATED_MUTATIONS
    )
    assert_generated_mutation_start_documentation(mutation_provider)
    assert_generated_mutation_constructor_documentation(mutation_provider)
    assert_generated_mutation_terminal_documentation(mutation_provider)
    sync_timeout = s3_codegen.ada_comment(
        "@param Timeout Whole owner-driven operation budget"
    )
    invalid_terminal = mutation_provider.replace(
        sync_timeout,
        sync_timeout.replace("Timeout", "Deadline", 1),
        1,
    )
    assert invalid_terminal != mutation_provider
    try:
        assert_generated_mutation_terminal_documentation(invalid_terminal)
    except AssertionError:
        pass
    else:
        raise AssertionError(
            "generated mutation wrong synchronous parameter was accepted"
        )
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
                "--  @formal Result_Type Typed provider result retained "
                "for Finish\n",
                "",
                1,
            ),
            "missing Paginated_REST_XML_Reads @formal accepted",
        ),
        (
            paginated_spec.replace(
                "@formal Result_Type Typed provider result retained for "
                "Finish",
                "@formal Wrong Typed provider result retained for Finish",
                1,
            ),
            "wrong Paginated_REST_XML_Reads @formal accepted",
        ),
        (
            paginated_spec.replace(
                "--  @formal Normalize_Failure Map a terminal exchange "
                "failure to Result_Type\ngeneric\n",
                "--  @formal Normalize_Failure Map a terminal exchange "
                "failure to Result_Type\n\ngeneric\n",
                1,
            ),
            "detached Paginated_REST_XML_Reads generic docs accepted",
        ),
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
    get_object_annotation_certainty = (
        "read-only model coverage only; no public client operation, "
        "response-body sink, header decoder, or runtime evidence exists, "
        "so this review exposes no annotation bytes and makes no "
        "response-validation or retry claim"
    )

    def assert_get_object_annotation_registry(candidate):
        entry = candidate.operations["GetObjectAnnotation"]
        assert entry.get("public_name") == "Not_Exposed"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "get_object_annotation"
        assert entry.get("codec") == (
            "generated_model_only_streaming_bytes_and_headers"
        )
        assert entry.get("certainty") == get_object_annotation_certainty
        assert entry.get("ada_symbols") is None
        assert entry["coverage"] == {
            "backend": "missing", "client": "partial",
            "server": "missing", "corpus": "covered",
        }
        assert entry["provenance"]["client"] == "generated"
        assert "no public client decoder" in entry["absence"]
        assert "neither same-version observation" in entry["reconciliation"]
        assert "registry sentinel and not an Ada declaration" in (
            entry["exclusions"][0]
        )
        assert "are inventory only" in entry["exclusions"][1]
        assert "does not invent a public bound" in entry["exclusions"][2]
        assert entry["evidence"]["client"] == [
            "src/flyology-object_storage-s3-model.adb",
            "tests/scripts/verify-get-object-annotation-model.py",
        ]
        assert candidate.qualification["get_object_annotation"] == [
            ["uv", "run", "--python", "3.13", "--",
             "tests/scripts/verify-get-object-annotation-model.py"],
            ["./tools/verify-coverage.sh"],
            ["./tools/ci/check-repository.sh", "{model}"],
            ["git", "diff", "--check"],
        ]

    def reject_get_object_annotation_registry(candidate, label):
        try:
            assert_get_object_annotation_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(f"{label} GetObjectAnnotation registry accepted")

    assert_get_object_annotation_registry(registry)
    invented_get_object_annotation_api = copy.deepcopy(registry)
    invented_get_object_annotation_api.operations[
        "GetObjectAnnotation"
    ]["public_name"] = "Get_Annotation"
    reject_get_object_annotation_registry(
        invented_get_object_annotation_api, "invented public API"
    )
    full_get_object_annotation = copy.deepcopy(registry)
    full_get_object_annotation.operations[
        "GetObjectAnnotation"
    ]["coverage"]["client"] = "covered"
    reject_get_object_annotation_registry(
        full_get_object_annotation, "invented complete client coverage"
    )
    binding_get_object_annotation = copy.deepcopy(registry)
    binding_get_object_annotation.operations[
        "GetObjectAnnotation"
    ]["reconciliation"] = "the response proves exact version binding"
    reject_get_object_annotation_registry(
        binding_get_object_annotation, "invented version binding"
    )
    checksum_get_object_annotation = copy.deepcopy(registry)
    checksum_get_object_annotation.operations[
        "GetObjectAnnotation"
    ]["exclusions"][1] = "the client validates every payload checksum"
    reject_get_object_annotation_registry(
        checksum_get_object_annotation, "invented checksum validation"
    )
    missing_get_object_annotation_model = copy.deepcopy(registry)
    missing_get_object_annotation_model.operations[
        "GetObjectAnnotation"
    ]["evidence"]["client"] = []
    reject_get_object_annotation_registry(
        missing_get_object_annotation_model, "missing model evidence"
    )
    get_object_annotation_lane, get_object_annotation_commands = (
        s3_operation.qualification_plan(registry, ["GetObjectAnnotation"])
    )
    assert get_object_annotation_lane == "get_object_annotation"
    assert get_object_annotation_commands == (
        registry.qualification["get_object_annotation"]
    )
    documented_get_object_annotation = copy.deepcopy(registry)
    documented_get_object_annotation.qualification[
        "get_object_annotation"
    ].insert(2, [
        "./tools/build-api-docs.sh", "/private/tmp/fos-impossible-gnatdoc",
    ])
    try:
        s3_operation.qualification_plan(
            documented_get_object_annotation, ["GetObjectAnnotation"]
        )
    except s3_operation.Audit_Error as error:
        assert "model-only qualification lane" in str(error)
    else:
        raise AssertionError("model-only GNATdoc lane accepted")
    mixed_exposure_lane = copy.deepcopy(registry)
    mixed_exposure_lane.operations["GetObject"]["qualification"] = (
        "get_object_annotation"
    )
    try:
        s3_operation.qualification_plan(
            mixed_exposure_lane, ["GetObject", "GetObjectAnnotation"]
        )
    except s3_operation.Audit_Error as error:
        assert "mixes exposed and model-only" in str(error)
    else:
        raise AssertionError("mixed exposed/model-only lane accepted")
    exposed_without_docs = copy.deepcopy(registry)
    exposed_without_docs.qualification["get_object"] = [
        command
        for command in exposed_without_docs.qualification["get_object"]
        if command[0] != "./tools/build-api-docs.sh"
    ]
    try:
        s3_operation.qualification_plan(exposed_without_docs, ["GetObject"])
    except s3_operation.Audit_Error as error:
        assert "must contain exactly one documentation gate" in str(error)
    else:
        raise AssertionError("exposed lane without GNATdoc accepted")
    try:
        s3_operation.qualification_plan(
            registry, ["GetObjectAnnotation", "GetObjectAnnotation"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate GetObjectAnnotation lane accepted")
    try:
        s3_operation.qualification_plan(
            registry, ["GetObject", "GetObjectAnnotation"]
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed GetObjectAnnotation lane accepted")

    put_object_acl_certainty = (
        "mutation model coverage only; no public ACL source, grant-header "
        "builder, checksum binding, response decoder, or runtime evidence "
        "exists, so this review reports no successful mutation, no "
        "admission certainty, and no automatic replay"
    )
    put_object_acl_reconciliation = (
        "the model carries an optional VersionId and ACL controls, but no "
        "implemented request, response, or ACL-state binding path exists; "
        "this review claims no selected-version mutation, later ACL "
        "observation, causal proof, certainty upgrade, or automatic replay"
    )

    def assert_put_object_acl_registry(candidate):
        entry = candidate.operations["PutObjectAcl"]
        assert entry.get("public_name") == "Not_Exposed"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "put_object_acl"
        assert entry.get("codec") == (
            "generated_model_only_acl_xml_and_headers"
        )
        assert entry.get("certainty") == put_object_acl_certainty
        assert entry.get("reconciliation") == put_object_acl_reconciliation
        assert entry.get("ada_symbols") is None
        assert entry["coverage"] == {
            "backend": "missing", "client": "partial",
            "server": "missing", "corpus": "covered",
        }
        assert entry["provenance"] == {
            "backend": "absent", "client": "generated",
            "server": "absent", "tests": "handwritten",
        }
        assert "registry sentinel and not an Ada declaration" in (
            entry["exclusions"][0]
        )
        assert "are inventory only" in entry["exclusions"][1]
        assert "structural inventory only" in entry["exclusions"][2]
        assert entry["evidence"] == {
            "backend": [],
            "client": [
                "src/flyology-object_storage-s3-model.adb",
                "tests/scripts/verify-put-object-acl-model.py",
            ],
            "server": [],
            "corpus": ["tests/scripts/verify-put-object-acl-model.py"],
        }
        assert candidate.qualification["put_object_acl"] == [
            ["uv", "run", "--python", "3.13", "--",
             "tests/scripts/verify-put-object-acl-model.py"],
            ["./tools/verify-coverage.sh"],
            ["./tools/ci/check-repository.sh", "{model}"],
            ["git", "diff", "--check"],
        ]

    def reject_put_object_acl_registry(candidate, label):
        try:
            assert_put_object_acl_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(f"{label} PutObjectAcl registry accepted")

    assert_put_object_acl_registry(registry)
    invented_put_object_acl_api = copy.deepcopy(registry)
    invented_put_object_acl_api.operations[
        "PutObjectAcl"
    ]["public_name"] = "Put_ACL"
    reject_put_object_acl_registry(
        invented_put_object_acl_api, "invented public API"
    )
    full_put_object_acl = copy.deepcopy(registry)
    full_put_object_acl.operations[
        "PutObjectAcl"
    ]["coverage"]["client"] = "covered"
    reject_put_object_acl_registry(
        full_put_object_acl, "invented complete client coverage"
    )
    validated_put_object_acl = copy.deepcopy(registry)
    validated_put_object_acl.operations[
        "PutObjectAcl"
    ]["exclusions"][2] = "the client enforces every ACL permission"
    reject_put_object_acl_registry(
        validated_put_object_acl, "invented ACL validation"
    )
    checksum_put_object_acl = copy.deepcopy(registry)
    checksum_put_object_acl.operations[
        "PutObjectAcl"
    ]["exclusions"][1] = "the client computes the required checksum"
    reject_put_object_acl_registry(
        checksum_put_object_acl, "invented checksum binding"
    )
    version_put_object_acl = copy.deepcopy(registry)
    version_put_object_acl.operations[
        "PutObjectAcl"
    ]["reconciliation"] = "the response proves exact version mutation"
    reject_put_object_acl_registry(
        version_put_object_acl, "invented version binding"
    )
    replay_put_object_acl = copy.deepcopy(registry)
    replay_put_object_acl.operations[
        "PutObjectAcl"
    ]["certainty"] = "automatically replay after transport failure"
    reject_put_object_acl_registry(
        replay_put_object_acl, "automatic replay"
    )
    causal_put_object_acl = copy.deepcopy(registry)
    causal_put_object_acl.operations[
        "PutObjectAcl"
    ]["reconciliation"] = "a later ACL read proves mutation causation"
    reject_put_object_acl_registry(
        causal_put_object_acl, "causal reconciliation"
    )
    missing_put_object_acl_model = copy.deepcopy(registry)
    missing_put_object_acl_model.operations[
        "PutObjectAcl"
    ]["evidence"]["client"] = []
    reject_put_object_acl_registry(
        missing_put_object_acl_model, "missing model evidence"
    )
    put_object_acl_lane, put_object_acl_commands = (
        s3_operation.qualification_plan(registry, ["PutObjectAcl"])
    )
    assert put_object_acl_lane == "put_object_acl"
    assert put_object_acl_commands == registry.qualification["put_object_acl"]
    try:
        s3_operation.qualification_plan(
            registry, ["PutObjectAcl", "PutObjectAcl"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate PutObjectAcl lane accepted")

    rename_object_certainty = (
        "mutation model coverage only; no public rename request, "
        "conditional-header encoder, client-token binding, response "
        "decoder, or runtime evidence exists, so this review reports no "
        "successful mutation, no admission certainty, and no automatic "
        "replay"
    )
    rename_object_reconciliation = (
        "the model describes a caller-supplied idempotency token for exact "
        "repeated parameters, but no implemented token generation, "
        "persistence, parameter binding, response binding, or retry path "
        "exists; this review claims no idempotent completion, causal proof, "
        "certainty upgrade, or automatic replay"
    )
    rename_object_errors = [
        "authentication", "authorization", "not_found", "invalid_request",
        "unavailable_or_retryable", "corrupt_or_invalid_response",
    ]
    rename_object_exclusions = [
        "Not_Exposed is a registry sentinel and not an Ada declaration; no "
        "Low_Level or Objects RenameObject API, composable operation, "
        "synchronous wrapper, Finish path, or GNATdoc qualification is "
        "claimed",
        "the modeled rename-source, destination and source preconditions, "
        "client token, empty response, and IdempotencyParameterMismatch "
        "error are inventory only; no URL encoding, conditional-header "
        "formatting, token validation, response validation, or retry "
        "behavior is implemented",
        "directory-bucket S3 Express One Zone endpoint and session semantics "
        "are not implemented or qualified; no same-bucket enforcement, "
        "atomicity, overwrite prevention, persistence, or external-provider "
        "behavior is claimed",
        "the model prose describes a maximum 64-character ASCII client "
        "token, but its generated ClientToken shape carries no corresponding "
        "bound or pattern; this review does not invent a public token limit, "
        "encoding policy, or token-generation policy",
    ]

    def assert_rename_object_registry(candidate):
        entry = candidate.operations["RenameObject"]
        assert entry.get("public_name") == "Not_Exposed"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "rename_object"
        assert entry.get("family") == "bodyless_mutation"
        assert entry.get("codec") == (
            "generated_model_only_bodyless_conditional_headers"
        )
        assert entry.get("certainty") == rename_object_certainty
        assert entry.get("reconciliation") == rename_object_reconciliation
        assert entry.get("errors") == rename_object_errors
        assert entry.get("exclusions") == rename_object_exclusions
        assert entry.get("ada_symbols") is None
        assert entry["coverage"] == {
            "backend": "missing", "client": "partial",
            "server": "missing", "corpus": "covered",
        }
        assert entry["provenance"] == {
            "backend": "absent", "client": "generated",
            "server": "absent", "tests": "handwritten",
        }
        assert entry["evidence"] == {
            "backend": [],
            "client": [
                "src/flyology-object_storage-s3-model.adb",
                "tests/scripts/verify-rename-object-model.py",
            ],
            "server": [],
            "corpus": ["tests/scripts/verify-rename-object-model.py"],
        }
        assert candidate.qualification["rename_object"] == [
            ["uv", "run", "--python", "3.13", "--",
             "tests/scripts/verify-rename-object-model.py"],
            ["./tools/verify-coverage.sh"],
            ["./tools/ci/check-repository.sh", "{model}"],
            ["git", "diff", "--check"],
        ]

    def reject_rename_object_registry(candidate, label):
        try:
            assert_rename_object_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(f"{label} RenameObject registry accepted")

    assert_rename_object_registry(registry)
    invented_rename_object_api = copy.deepcopy(registry)
    invented_rename_object_api.operations[
        "RenameObject"
    ]["public_name"] = "Rename_Object"
    reject_rename_object_registry(
        invented_rename_object_api, "invented public API"
    )
    full_rename_object = copy.deepcopy(registry)
    full_rename_object.operations[
        "RenameObject"
    ]["coverage"]["client"] = "covered"
    reject_rename_object_registry(
        full_rename_object, "invented complete client coverage"
    )
    bodied_rename_object = copy.deepcopy(registry)
    bodied_rename_object.operations[
        "RenameObject"
    ]["family"] = "rest_xml_mutation"
    reject_rename_object_registry(
        bodied_rename_object, "invented request body"
    )
    conditional_rename_object = copy.deepcopy(registry)
    conditional_rename_object.operations[
        "RenameObject"
    ]["exclusions"][1] = "the client validates every precondition"
    reject_rename_object_registry(
        conditional_rename_object, "invented conditional-header binding"
    )
    encoded_rename_source = copy.deepcopy(registry)
    encoded_rename_source.operations[
        "RenameObject"
    ]["exclusions"][1] += "; the client URL-encodes RenameSource"
    reject_rename_object_registry(
        encoded_rename_source, "invented RenameSource encoding"
    )
    automated_rename_session = copy.deepcopy(registry)
    automated_rename_session.operations[
        "RenameObject"
    ]["exclusions"][2] += "; the client refreshes S3 Express sessions"
    reject_rename_object_registry(
        automated_rename_session, "invented session automation"
    )
    decoded_rename_error = copy.deepcopy(registry)
    decoded_rename_error.operations[
        "RenameObject"
    ]["errors"] = ["idempotency_parameter_mismatch"]
    reject_rename_object_registry(
        decoded_rename_error, "invented error decoder"
    )
    token_rename_object = copy.deepcopy(registry)
    token_rename_object.operations[
        "RenameObject"
    ]["reconciliation"] = "the client token proves exact completion"
    reject_rename_object_registry(
        token_rename_object, "invented idempotency-token binding"
    )
    replay_rename_object = copy.deepcopy(registry)
    replay_rename_object.operations[
        "RenameObject"
    ]["certainty"] = "automatically replay after transport failure"
    reject_rename_object_registry(
        replay_rename_object, "automatic replay"
    )
    causal_rename_object = copy.deepcopy(registry)
    causal_rename_object.operations[
        "RenameObject"
    ]["reconciliation"] = "a later object read proves rename causation"
    reject_rename_object_registry(
        causal_rename_object, "causal reconciliation"
    )
    bounded_rename_token = copy.deepcopy(registry)
    bounded_rename_token.operations[
        "RenameObject"
    ]["exclusions"][3] = "the public client token is limited to 64 bytes"
    reject_rename_object_registry(
        bounded_rename_token, "invented client-token policy"
    )
    missing_rename_object_model = copy.deepcopy(registry)
    missing_rename_object_model.operations[
        "RenameObject"
    ]["evidence"]["client"] = []
    reject_rename_object_registry(
        missing_rename_object_model, "missing model evidence"
    )
    rename_object_lane, rename_object_commands = (
        s3_operation.qualification_plan(registry, ["RenameObject"])
    )
    assert rename_object_lane == "rename_object"
    assert rename_object_commands == registry.qualification["rename_object"]
    try:
        s3_operation.qualification_plan(
            registry, ["RenameObject", "RenameObject"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate RenameObject lane accepted")

    restore_object_certainty = (
        "mutation model coverage only; no public restore request, XML "
        "serializer, checksum binding, response decoder, or runtime evidence "
        "exists, so this review reports no accepted or completed restore, no "
        "admission certainty, and no automatic replay"
    )
    restore_object_reconciliation = (
        "the model carries an optional VersionId and documents later "
        "HeadObject restore-state observation, but neither request binding "
        "nor restore-state decoding is implemented; explicit or omitted "
        "version selection, later observation, causal proof, certainty "
        "upgrade, and automatic replay are not claimed"
    )
    restore_object_errors = [
        "authentication", "authorization", "not_found", "invalid_request",
        "unavailable_or_retryable", "corrupt_or_invalid_response",
    ]
    restore_object_exclusions = [
        "Not_Exposed is a registry sentinel and not an Ada declaration; no "
        "Low_Level or Objects RestoreObject API, composable operation, "
        "synchronous wrapper, Finish path, or GNATdoc qualification is "
        "claimed",
        "the modeled RestoreRequest XML, optional checksum algorithm, "
        "VersionId, requester-pays controls, response headers, and "
        "active-tier error are inventory only; no XML serialization, "
        "cross-field validation, digest generation, signing binding, version "
        "binding, response validation, or error decoding is implemented",
        "regular restore, speed upgrade, and deprecated Select restore shapes "
        "are structural inventory only; no Days or tier policy, Select "
        "support, output-location policy, ACL, tag, metadata, encryption, "
        "SQL, body-size, or collection bound is claimed",
        "only ObjectAlreadyInActiveTierError is a modeled operation error "
        "shape; documentation-only RestoreAlreadyInProgress and "
        "GlacierExpeditedRetrievalNotAvailable codes and modeled HTTP 200 "
        "versus documented 202 behavior are not normalized or qualified",
        "later HeadObject x-amz-restore observation cannot prove that a lost "
        "request caused the observed state, upgrade mutation certainty, or "
        "authorize automatic replay",
        "directory buckets are documented as unsupported; access-point "
        "behavior and conflicting inherited Outposts routing prose are not "
        "implemented or resolved",
    ]

    def assert_restore_object_registry(candidate):
        entry = candidate.operations["RestoreObject"]
        assert entry.get("public_name") == "Not_Exposed"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "restore_object"
        assert entry.get("family") == "rest_xml_mutation"
        assert entry.get("codec") == (
            "generated_model_only_restore_xml_and_headers"
        )
        assert entry.get("certainty") == restore_object_certainty
        assert entry.get("reconciliation") == restore_object_reconciliation
        assert entry.get("errors") == restore_object_errors
        assert entry.get("exclusions") == restore_object_exclusions
        assert entry.get("ada_symbols") is None
        assert entry["coverage"] == {
            "backend": "missing", "client": "partial",
            "server": "missing", "corpus": "covered",
        }
        assert entry["provenance"] == {
            "backend": "absent", "client": "generated",
            "server": "absent", "tests": "handwritten",
        }
        assert entry["evidence"] == {
            "backend": [],
            "client": [
                "src/flyology-object_storage-s3-model.adb",
                "tests/scripts/verify-restore-object-model.py",
            ],
            "server": [],
            "corpus": ["tests/scripts/verify-restore-object-model.py"],
        }
        assert candidate.qualification["restore_object"] == [
            ["uv", "run", "--python", "3.13", "--",
             "tests/scripts/verify-restore-object-model.py"],
            ["./tools/verify-coverage.sh"],
            ["./tools/ci/check-repository.sh", "{model}"],
            ["git", "diff", "--check"],
        ]

    def reject_restore_object_registry(candidate, label):
        try:
            assert_restore_object_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(f"{label} RestoreObject registry accepted")

    assert_restore_object_registry(registry)
    invented_restore_object_api = copy.deepcopy(registry)
    invented_restore_object_api.operations[
        "RestoreObject"
    ]["public_name"] = "Restore_Object"
    reject_restore_object_registry(
        invented_restore_object_api, "invented public API"
    )
    full_restore_object = copy.deepcopy(registry)
    full_restore_object.operations[
        "RestoreObject"
    ]["coverage"]["client"] = "covered"
    reject_restore_object_registry(
        full_restore_object, "invented complete client coverage"
    )
    bodyless_restore_object = copy.deepcopy(registry)
    bodyless_restore_object.operations[
        "RestoreObject"
    ]["family"] = "bodyless_mutation"
    reject_restore_object_registry(
        bodyless_restore_object, "missing XML request body"
    )
    serialized_restore_object = copy.deepcopy(registry)
    serialized_restore_object.operations[
        "RestoreObject"
    ]["exclusions"][1] += "; the client serializes and validates the XML"
    reject_restore_object_registry(
        serialized_restore_object, "invented XML serializer"
    )
    checksum_restore_object = copy.deepcopy(registry)
    checksum_restore_object.operations[
        "RestoreObject"
    ]["exclusions"][1] += "; the client computes the selected checksum"
    reject_restore_object_registry(
        checksum_restore_object, "invented checksum binding"
    )
    version_restore_object = copy.deepcopy(registry)
    version_restore_object.operations[
        "RestoreObject"
    ]["reconciliation"] = "the response proves exact version binding"
    reject_restore_object_registry(
        version_restore_object, "invented version binding"
    )
    decoded_restore_object = copy.deepcopy(registry)
    decoded_restore_object.operations[
        "RestoreObject"
    ]["exclusions"][3] += "; the client distinguishes 200, 202, 409, and 503"
    reject_restore_object_registry(
        decoded_restore_object, "invented status and error decoder"
    )
    selected_restore_object = copy.deepcopy(registry)
    selected_restore_object.operations[
        "RestoreObject"
    ]["exclusions"][2] += "; Select restore is supported"
    reject_restore_object_registry(
        selected_restore_object, "invented Select support"
    )
    bounded_restore_object = copy.deepcopy(registry)
    bounded_restore_object.operations[
        "RestoreObject"
    ]["exclusions"][2] += "; serialized restore bodies are bounded"
    reject_restore_object_registry(
        bounded_restore_object, "invented restore bounds"
    )
    routed_restore_object = copy.deepcopy(registry)
    routed_restore_object.operations[
        "RestoreObject"
    ]["exclusions"][5] += "; access points and Outposts are supported"
    reject_restore_object_registry(
        routed_restore_object, "invented endpoint support"
    )
    replay_restore_object = copy.deepcopy(registry)
    replay_restore_object.operations[
        "RestoreObject"
    ]["certainty"] = "automatically replay after transport failure"
    reject_restore_object_registry(
        replay_restore_object, "automatic replay"
    )
    causal_restore_object = copy.deepcopy(registry)
    causal_restore_object.operations[
        "RestoreObject"
    ]["reconciliation"] = "HeadObject proves restore causation"
    reject_restore_object_registry(
        causal_restore_object, "causal reconciliation"
    )
    missing_restore_object_model = copy.deepcopy(registry)
    missing_restore_object_model.operations[
        "RestoreObject"
    ]["evidence"]["client"] = []
    reject_restore_object_registry(
        missing_restore_object_model, "missing model evidence"
    )
    restore_object_lane, restore_object_commands = (
        s3_operation.qualification_plan(registry, ["RestoreObject"])
    )
    assert restore_object_lane == "restore_object"
    assert restore_object_commands == registry.qualification["restore_object"]
    try:
        s3_operation.qualification_plan(
            registry, ["RestoreObject", "RestoreObject"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate RestoreObject lane accepted")

    select_object_content_certainty = (
        "read model coverage only; no public Select request serializer, "
        "accepted query, event-stream decoder, complete End event, result "
        "sink, resume path, or runtime evidence exists, so this review "
        "exposes no selected records and claims no automatic replay"
    )
    select_object_content_reconciliation = (
        "a partial or interrupted event stream is not an implemented "
        "resumable observation; a fresh request would start a new query "
        "against potentially changed current-object data and cannot "
        "continue, prove, or upgrade the earlier result"
    )
    select_object_content_errors = [
        "authentication", "authorization", "not_found", "invalid_request",
        "unavailable_or_retryable", "corrupt_or_invalid_response",
    ]
    select_object_content_exclusions = [
        "Not_Exposed is a registry sentinel and not an Ada declaration; no "
        "Low_Level or Objects SelectObjectContent API, composable operation, "
        "synchronous wrapper, Finish path, or GNATdoc qualification is "
        "claimed",
        "the modeled SQL, CSV/JSON/Parquet serializers, progress and scan "
        "range, SSE-C headers, expected owner, and XML request are inventory "
        "only; no request serialization, cross-field validation, SSE-C key "
        "or MD5 binding, HTTPS enforcement, range validation, or default is "
        "implemented",
        "the Records, Stats, Progress, Cont, and End variants are structural "
        "inventory only; no event-stream prelude, header, message CRC, "
        "unknown-event, error-frame, truncation, End-required completion, or "
        "split-record reconstruction policy is implemented",
        "no caller-owned sink, backpressure, per-frame or aggregate bound, "
        "cancellation drain, typed Finish, owner retention, same-object "
        "restart, or task-lifetime behavior is claimed",
        "the operation models no error shapes; documentation-only special "
        "errors, modeled default HTTP 200, in-stream errors, success "
        "completion, and malformed response behavior are not decoded or "
        "qualified",
        "S3 Select is documented as unavailable to new customers; exposure "
        "policy, directory-bucket and Outposts exclusions, access-point "
        "routing, and external-provider behavior are not implemented or "
        "qualified",
        "the request models no VersionId; this review claims no "
        "selected-version binding, stable snapshot, continuation, or causal "
        "relationship across a later reissued query",
    ]

    def assert_select_object_content_registry(candidate):
        entry = candidate.operations["SelectObjectContent"]
        assert entry.get("public_name") == "Not_Exposed"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "select_object_content"
        assert entry.get("family") == "event_stream_read"
        assert entry.get("codec") == (
            "generated_model_only_select_xml_and_event_stream"
        )
        assert entry.get("certainty") == select_object_content_certainty
        assert entry.get("reconciliation") == (
            select_object_content_reconciliation
        )
        assert entry.get("errors") == select_object_content_errors
        assert entry.get("exclusions") == select_object_content_exclusions
        assert entry.get("ada_symbols") is None
        assert entry["coverage"] == {
            "backend": "missing", "client": "partial",
            "server": "missing", "corpus": "covered",
        }
        assert entry["provenance"] == {
            "backend": "absent", "client": "generated",
            "server": "absent", "tests": "handwritten",
        }
        assert entry["evidence"] == {
            "backend": [],
            "client": [
                "src/flyology-object_storage-s3-model.adb",
                "tests/scripts/verify-select-object-content-model.py",
            ],
            "server": [],
            "corpus": ["tests/scripts/verify-select-object-content-model.py"],
        }
        assert candidate.qualification["select_object_content"] == [
            ["uv", "run", "--python", "3.13", "--",
             "tests/scripts/verify-select-object-content-model.py"],
            ["./tools/verify-coverage.sh"],
            ["./tools/ci/check-repository.sh", "{model}"],
            ["git", "diff", "--check"],
        ]

    def reject_select_object_content_registry(candidate, label):
        try:
            assert_select_object_content_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} SelectObjectContent registry accepted"
        )

    assert_select_object_content_registry(registry)
    invented_select_api = copy.deepcopy(registry)
    invented_select_api.operations[
        "SelectObjectContent"
    ]["public_name"] = "Select_Content"
    reject_select_object_content_registry(invented_select_api, "invented API")
    full_select_client = copy.deepcopy(registry)
    full_select_client.operations[
        "SelectObjectContent"
    ]["coverage"]["client"] = "covered"
    reject_select_object_content_registry(
        full_select_client, "invented complete client coverage"
    )
    nonstreaming_select = copy.deepcopy(registry)
    nonstreaming_select.operations[
        "SelectObjectContent"
    ]["family"] = "bounded_document_read"
    reject_select_object_content_registry(
        nonstreaming_select, "missing event stream"
    )
    serialized_select = copy.deepcopy(registry)
    serialized_select.operations[
        "SelectObjectContent"
    ]["exclusions"][1] += "; the client validates and serializes every query"
    reject_select_object_content_registry(
        serialized_select, "invented request serializer"
    )
    encrypted_select = copy.deepcopy(registry)
    encrypted_select.operations[
        "SelectObjectContent"
    ]["exclusions"][1] += "; the client derives and binds SSE-C MD5"
    reject_select_object_content_registry(
        encrypted_select, "invented SSE-C binding"
    )
    ranged_select = copy.deepcopy(registry)
    ranged_select.operations[
        "SelectObjectContent"
    ]["exclusions"][1] += "; the client enforces ScanRange defaults"
    reject_select_object_content_registry(
        ranged_select, "invented scan-range policy"
    )
    decoded_select = copy.deepcopy(registry)
    decoded_select.operations[
        "SelectObjectContent"
    ]["exclusions"][2] += "; the client validates every frame and CRC"
    reject_select_object_content_registry(
        decoded_select, "invented event decoder"
    )
    aggregated_select = copy.deepcopy(registry)
    aggregated_select.operations[
        "SelectObjectContent"
    ]["exclusions"][3] += "; the client reconstructs bounded records"
    reject_select_object_content_registry(
        aggregated_select, "invented sink and record aggregation"
    )
    successful_select = copy.deepcopy(registry)
    successful_select.operations[
        "SelectObjectContent"
    ]["exclusions"][4] += "; End proves a successful query"
    reject_select_object_content_registry(
        successful_select, "invented success decoder"
    )
    replayed_select = copy.deepcopy(registry)
    replayed_select.operations[
        "SelectObjectContent"
    ]["certainty"] = "resume or automatically replay an interrupted stream"
    reject_select_object_content_registry(
        replayed_select, "invented resume or replay"
    )
    versioned_select = copy.deepcopy(registry)
    versioned_select.operations[
        "SelectObjectContent"
    ]["exclusions"][6] += "; the query binds an exact VersionId"
    reject_select_object_content_registry(
        versioned_select, "invented version binding"
    )
    available_select = copy.deepcopy(registry)
    available_select.operations[
        "SelectObjectContent"
    ]["exclusions"][5] += "; Select is supported for every caller"
    reject_select_object_content_registry(
        available_select, "invented service availability"
    )
    routed_select = copy.deepcopy(registry)
    routed_select.operations[
        "SelectObjectContent"
    ]["exclusions"][5] += "; directory, Outposts, and access points work"
    reject_select_object_content_registry(
        routed_select, "invented endpoint support"
    )
    causal_select = copy.deepcopy(registry)
    causal_select.operations[
        "SelectObjectContent"
    ]["reconciliation"] = "a reissued query continues and proves the result"
    reject_select_object_content_registry(
        causal_select, "causal query continuation"
    )
    missing_select_model = copy.deepcopy(registry)
    missing_select_model.operations[
        "SelectObjectContent"
    ]["evidence"]["client"] = []
    reject_select_object_content_registry(
        missing_select_model, "missing model evidence"
    )
    select_lane, select_commands = s3_operation.qualification_plan(
        registry, ["SelectObjectContent"]
    )
    assert select_lane == "select_object_content"
    assert select_commands == registry.qualification["select_object_content"]
    try:
        s3_operation.qualification_plan(
            registry, ["SelectObjectContent", "SelectObjectContent"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate SelectObjectContent lane accepted")

    update_object_encryption_certainty = (
        "mutation model coverage only; no public encryption-update request, "
        "XML serializer, checksum binding, response decoder, or runtime "
        "evidence exists, so this review reports no accepted or completed "
        "update, no admission certainty, and no automatic replay"
    )
    update_object_encryption_reconciliation = (
        "the model carries an optional VersionId, but neither explicit nor "
        "omitted-version request binding nor later HeadObject "
        "encryption-state decoding is implemented; later observation cannot "
        "prove causation, upgrade mutation certainty, or authorize automatic "
        "replay"
    )
    update_object_encryption_errors = [
        "authentication", "authorization", "not_found", "invalid_request",
        "unavailable_or_retryable", "corrupt_or_invalid_response",
    ]
    update_object_encryption_exclusions = [
        "Not_Exposed is a registry sentinel and not an Ada declaration; no "
        "Low_Level or Objects UpdateObjectEncryption API, composable "
        "operation, synchronous wrapper, Finish path, or GNATdoc "
        "qualification is claimed",
        "the actual ObjectEncryption union exposes only SSEKMS even though "
        "surrounding prose also mentions SSES3, and BucketKeyEnabled is "
        "merely optional despite prose describing false when omitted; this "
        "review does not invent an SSES3 variant, a public false default, or "
        "a conflict resolution",
        "the modeled XML, Content-MD5, required generated-checksum selection, "
        "VersionId, requester-pays controls, and response header are "
        "inventory "
        "only; no serialization, digest computation, signing binding, "
        "version binding, response validation, or rewind behavior is "
        "implemented",
        "the KMS ARN shape, account and organization ownership prose, "
        "permissions, current-encryption restrictions, Object Lock "
        "conditions, and sensitive value are service inventory only; no "
        "client validation, policy, authorization, or logging behavior is "
        "claimed",
        "the operation models NoSuchKey, InvalidRequest, and synthetic "
        "AccessDenied error shapes plus a default HTTP 200 response; no "
        "status, error, RequestCharged, success, or malformed-response "
        "decoder is implemented or qualified",
        "a later HeadObject encryption observation can reflect concurrent or "
        "already-matching state and cannot prove that a lost update caused "
        "the observation",
        "directory buckets and S3 on Outposts are documented as unsupported; "
        "access-point routing and external-provider behavior are not "
        "implemented or qualified",
    ]

    def assert_update_object_encryption_registry(candidate):
        entry = candidate.operations["UpdateObjectEncryption"]
        assert entry.get("public_name") == "Not_Exposed"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "update_object_encryption"
        assert entry.get("family") == "rest_xml_mutation"
        assert entry.get("codec") == (
            "generated_model_only_object_encryption_xml_and_headers"
        )
        assert entry.get("certainty") == update_object_encryption_certainty
        assert entry.get("reconciliation") == (
            update_object_encryption_reconciliation
        )
        assert entry.get("errors") == update_object_encryption_errors
        assert entry.get("exclusions") == update_object_encryption_exclusions
        assert entry.get("ada_symbols") is None
        assert entry["coverage"] == {
            "backend": "missing", "client": "partial",
            "server": "missing", "corpus": "covered",
        }
        assert entry["provenance"] == {
            "backend": "absent", "client": "generated",
            "server": "absent", "tests": "handwritten",
        }
        assert entry["evidence"] == {
            "backend": [],
            "client": [
                "src/flyology-object_storage-s3-model.adb",
                "tests/scripts/verify-update-object-encryption-model.py",
            ],
            "server": [],
            "corpus": ["tests/scripts/verify-update-object-encryption-model.py"],
        }
        assert candidate.qualification["update_object_encryption"] == [
            ["uv", "run", "--python", "3.13", "--",
             "tests/scripts/verify-update-object-encryption-model.py"],
            ["./tools/verify-coverage.sh"],
            ["./tools/ci/check-repository.sh", "{model}"],
            ["git", "diff", "--check"],
        ]

    def reject_update_object_encryption_registry(candidate, label):
        try:
            assert_update_object_encryption_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} UpdateObjectEncryption registry accepted"
        )

    assert_update_object_encryption_registry(registry)
    invented_update_encryption_api = copy.deepcopy(registry)
    invented_update_encryption_api.operations[
        "UpdateObjectEncryption"
    ]["public_name"] = "Update_Encryption"
    reject_update_object_encryption_registry(
        invented_update_encryption_api, "invented public API"
    )
    full_update_encryption = copy.deepcopy(registry)
    full_update_encryption.operations[
        "UpdateObjectEncryption"
    ]["coverage"]["client"] = "covered"
    reject_update_object_encryption_registry(
        full_update_encryption, "invented complete client coverage"
    )
    bodyless_update_encryption = copy.deepcopy(registry)
    bodyless_update_encryption.operations[
        "UpdateObjectEncryption"
    ]["family"] = "bodyless_mutation"
    reject_update_object_encryption_registry(
        bodyless_update_encryption, "missing XML request body"
    )
    sse_s3_update_encryption = copy.deepcopy(registry)
    sse_s3_update_encryption.operations[
        "UpdateObjectEncryption"
    ]["exclusions"][1] += "; the public union includes SSES3"
    reject_update_object_encryption_registry(
        sse_s3_update_encryption, "invented SSES3 variant"
    )
    defaulted_update_encryption = copy.deepcopy(registry)
    defaulted_update_encryption.operations[
        "UpdateObjectEncryption"
    ]["exclusions"][1] += "; omitted BucketKeyEnabled defaults to false"
    reject_update_object_encryption_registry(
        defaulted_update_encryption, "invented bucket-key default"
    )
    checked_update_encryption = copy.deepcopy(registry)
    checked_update_encryption.operations[
        "UpdateObjectEncryption"
    ]["exclusions"][3] += "; the client validates KMS ownership and ARN"
    reject_update_object_encryption_registry(
        checked_update_encryption, "invented KMS policy"
    )
    serialized_update_encryption = copy.deepcopy(registry)
    serialized_update_encryption.operations[
        "UpdateObjectEncryption"
    ]["exclusions"][2] += "; XML, MD5, and checksums bind exact bytes"
    reject_update_object_encryption_registry(
        serialized_update_encryption, "invented checksum binding"
    )
    versioned_update_encryption = copy.deepcopy(registry)
    versioned_update_encryption.operations[
        "UpdateObjectEncryption"
    ]["reconciliation"] = "the response proves exact VersionId binding"
    reject_update_object_encryption_registry(
        versioned_update_encryption, "invented version binding"
    )
    decoded_update_encryption = copy.deepcopy(registry)
    decoded_update_encryption.operations[
        "UpdateObjectEncryption"
    ]["exclusions"][4] += "; the client decodes success and every error"
    reject_update_object_encryption_registry(
        decoded_update_encryption, "invented response decoder"
    )
    routed_update_encryption = copy.deepcopy(registry)
    routed_update_encryption.operations[
        "UpdateObjectEncryption"
    ]["exclusions"][6] += "; directory, Outposts, and access points work"
    reject_update_object_encryption_registry(
        routed_update_encryption, "invented endpoint support"
    )
    replayed_update_encryption = copy.deepcopy(registry)
    replayed_update_encryption.operations[
        "UpdateObjectEncryption"
    ]["certainty"] = "automatically replay after transport failure"
    reject_update_object_encryption_registry(
        replayed_update_encryption, "automatic replay"
    )
    causal_update_encryption = copy.deepcopy(registry)
    causal_update_encryption.operations[
        "UpdateObjectEncryption"
    ]["reconciliation"] = "HeadObject proves the update caused encryption"
    reject_update_object_encryption_registry(
        causal_update_encryption, "causal reconciliation"
    )
    missing_update_encryption_model = copy.deepcopy(registry)
    missing_update_encryption_model.operations[
        "UpdateObjectEncryption"
    ]["evidence"]["client"] = []
    reject_update_object_encryption_registry(
        missing_update_encryption_model, "missing model evidence"
    )
    documented_update_encryption = copy.deepcopy(registry)
    documented_update_encryption.qualification[
        "update_object_encryption"
    ].insert(1, ["./tools/build-api-docs.sh", "/tmp/impossible"])
    reject_update_object_encryption_registry(
        documented_update_encryption, "invented GNATdoc gate"
    )
    update_encryption_lane, update_encryption_commands = (
        s3_operation.qualification_plan(registry, ["UpdateObjectEncryption"])
    )
    assert update_encryption_lane == "update_object_encryption"
    assert update_encryption_commands == (
        registry.qualification["update_object_encryption"]
    )
    try:
        s3_operation.qualification_plan(
            registry, ["UpdateObjectEncryption", "UpdateObjectEncryption"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate UpdateObjectEncryption lane accepted")

    write_get_object_response_certainty = (
        "streaming mutation model coverage only; no public request, source "
        "ownership, endpoint routing, response decoder, admission evidence, "
        "or runtime path exists, so this review reports no accepted or "
        "completed callback and permits no automatic replay of the "
        "single-use request token"
    )
    write_get_object_response_reconciliation = (
        "the modeled callback has no output or operation errors and no "
        "implemented observation can bind a later GetObject result to a "
        "particular token, body, or forwarded-header set; later state cannot "
        "prove completion or causation"
    )
    write_get_object_response_errors = [
        "authentication", "authorization", "invalid_request",
        "unavailable_or_retryable", "corrupt_or_invalid_response",
    ]
    write_get_object_response_exclusions = [
        "Not_Exposed is a registry sentinel and not an Ada declaration; no "
        "Low_Level or Objects WriteGetObjectResponse API, composable "
        "operation, synchronous wrapper, Finish path, or GNATdoc "
        "qualification is claimed",
        "the Object Lambda host prefix, static endpoint context, RequestRoute "
        "validation, and external endpoint construction are model inventory "
        "only; directory buckets are documented as unsupported",
        "RequestToken is modeled as a required unbounded string and described "
        "as single-use, but retention, redaction, admission, idempotency, "
        "retry, and replay policy are not implemented",
        "the optional streaming Body and its length, backpressure, "
        "cancellation, drain, rewind, source ownership, and lifetime are not "
        "implemented or bounded",
        "the modeled forwarded status, error, metadata, checksum, encryption, "
        "Object Lock, version, and content headers are inventory only; "
        "documentation-only mutual exclusions, status lists, error-code "
        "syntax, checksum one-of rules, signed-space encoding, metadata "
        "ordering, duplicate handling, and sensitive KMS forwarding are not "
        "enforced",
        "the operation uses v4-unsigned-body and an unsigned payload and has "
        "no modeled output, operation error shapes, or request checksum "
        "trait; no success, failure, malformed-response, or token-admission "
        "decoder is implemented",
        "a later GetObject result can reflect concurrent or already-matching "
        "state and cannot prove that this callback delivered the body or "
        "headers",
    ]
    model_only_verifier_commands = [
        ["uv", "run", "--python", "3.13", "--",
         "tests/scripts/verify-get-object-annotation-model.py"],
        ["uv", "run", "--python", "3.13", "--",
         "tests/scripts/verify-put-object-acl-model.py"],
        ["uv", "run", "--python", "3.13", "--",
         "tests/scripts/verify-put-object-annotation-model.py"],
        ["uv", "run", "--python", "3.13", "--",
         "tests/scripts/verify-rename-object-model.py"],
        ["uv", "run", "--python", "3.13", "--",
         "tests/scripts/verify-restore-object-model.py"],
        ["uv", "run", "--python", "3.13", "--",
         "tests/scripts/verify-select-object-content-model.py"],
        ["uv", "run", "--python", "3.13", "--",
         "tests/scripts/verify-update-object-encryption-model.py"],
        ["uv", "run", "--python", "3.13", "--",
         "tests/scripts/verify-write-get-object-response-model.py"],
    ]

    def assert_write_get_object_response_registry(candidate):
        entry = candidate.operations["WriteGetObjectResponse"]
        assert entry.get("public_name") == "Not_Exposed"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "write_get_object_response"
        assert entry.get("family") == "streaming_mutation"
        assert entry.get("codec") == (
            "generated_model_only_unsigned_stream_and_forwarded_headers"
        )
        assert entry.get("certainty") == write_get_object_response_certainty
        assert entry.get("reconciliation") == (
            write_get_object_response_reconciliation
        )
        assert entry.get("errors") == write_get_object_response_errors
        assert entry.get("exclusions") == write_get_object_response_exclusions
        assert entry.get("ada_symbols") is None
        assert entry["coverage"] == {
            "backend": "missing", "client": "partial",
            "server": "missing", "corpus": "covered",
        }
        assert entry["provenance"] == {
            "backend": "absent", "client": "generated",
            "server": "absent", "tests": "handwritten",
        }
        assert entry["evidence"] == {
            "backend": [],
            "client": [
                "src/flyology-object_storage-s3-model.adb",
                "tests/scripts/verify-write-get-object-response-model.py",
            ],
            "server": [],
            "corpus": [
                "tests/scripts/verify-write-get-object-response-model.py",
            ],
        }
        assert candidate.qualification["write_get_object_response"] == [
            ["uv", "run", "--python", "3.13", "--",
             "tests/scripts/verify-write-get-object-response-model.py"],
            ["./tools/verify-coverage.sh"],
            ["./tools/ci/check-repository.sh", "{model}"],
            ["git", "diff", "--check"],
        ]
        registration = candidate.metadata["test_registration"]
        assert registration["model_verifier_count"] == 37
        for command in model_only_verifier_commands:
            assert registration["model_verifiers"].count(command) == 1

    def reject_write_get_object_response_registry(candidate, label):
        try:
            assert_write_get_object_response_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} WriteGetObjectResponse registry accepted"
        )

    assert_write_get_object_response_registry(registry)
    public_write_response = copy.deepcopy(registry)
    public_write_response.operations[
        "WriteGetObjectResponse"
    ]["public_name"] = "Write_Get_Object_Response"
    reject_write_get_object_response_registry(
        public_write_response, "invented public API"
    )
    complete_write_response = copy.deepcopy(registry)
    complete_write_response.operations[
        "WriteGetObjectResponse"
    ]["coverage"]["client"] = "covered"
    reject_write_get_object_response_registry(
        complete_write_response, "invented complete client coverage"
    )
    bodyless_write_response = copy.deepcopy(registry)
    bodyless_write_response.operations[
        "WriteGetObjectResponse"
    ]["family"] = "bodyless_mutation"
    reject_write_get_object_response_registry(
        bodyless_write_response, "missing streaming body"
    )
    signed_write_response = copy.deepcopy(registry)
    signed_write_response.operations[
        "WriteGetObjectResponse"
    ]["exclusions"][5] += "; the payload is signed and checksummed"
    reject_write_get_object_response_registry(
        signed_write_response, "invented signed payload"
    )
    routed_write_response = copy.deepcopy(registry)
    routed_write_response.operations[
        "WriteGetObjectResponse"
    ]["exclusions"][1] += "; every access point route is implemented"
    reject_write_get_object_response_registry(
        routed_write_response, "invented endpoint routing"
    )
    owned_write_response = copy.deepcopy(registry)
    owned_write_response.operations[
        "WriteGetObjectResponse"
    ]["exclusions"][3] += "; the body is bounded, rewindable, and retained"
    reject_write_get_object_response_registry(
        owned_write_response, "invented body ownership"
    )
    validated_write_response = copy.deepcopy(registry)
    validated_write_response.operations[
        "WriteGetObjectResponse"
    ]["exclusions"][4] += "; all status and error combinations are validated"
    reject_write_get_object_response_registry(
        validated_write_response, "invented cross-field validation"
    )
    normalized_write_response = copy.deepcopy(registry)
    normalized_write_response.operations[
        "WriteGetObjectResponse"
    ]["exclusions"][4] += "; metadata and checksums are normalized"
    reject_write_get_object_response_registry(
        normalized_write_response, "invented forwarded-header normalization"
    )
    replayed_write_response = copy.deepcopy(registry)
    replayed_write_response.operations[
        "WriteGetObjectResponse"
    ]["certainty"] = "the single-use token is idempotent and replayable"
    reject_write_get_object_response_registry(
        replayed_write_response, "invented token replay"
    )
    admitted_write_response = copy.deepcopy(registry)
    admitted_write_response.operations[
        "WriteGetObjectResponse"
    ]["certainty"] = "a transport write proves callback admission"
    reject_write_get_object_response_registry(
        admitted_write_response, "invented admission certainty"
    )
    decoded_write_response = copy.deepcopy(registry)
    decoded_write_response.operations[
        "WriteGetObjectResponse"
    ]["exclusions"][5] += "; completion and failures are decoded"
    reject_write_get_object_response_registry(
        decoded_write_response, "invented response decoder"
    )
    causal_write_response = copy.deepcopy(registry)
    causal_write_response.operations[
        "WriteGetObjectResponse"
    ]["reconciliation"] = "a later GetObject proves callback completion"
    reject_write_get_object_response_registry(
        causal_write_response, "causal reconciliation"
    )
    missing_write_response_model = copy.deepcopy(registry)
    missing_write_response_model.operations[
        "WriteGetObjectResponse"
    ]["evidence"]["client"] = []
    reject_write_get_object_response_registry(
        missing_write_response_model, "missing model evidence"
    )
    documented_write_response = copy.deepcopy(registry)
    documented_write_response.qualification[
        "write_get_object_response"
    ].insert(1, ["./tools/build-api-docs.sh", "/tmp/impossible"])
    reject_write_get_object_response_registry(
        documented_write_response, "invented GNATdoc gate"
    )
    missing_model_test = copy.deepcopy(registry)
    missing_model_test.metadata["test_registration"][
        "model_verifiers"
    ].remove(model_only_verifier_commands[0])
    reject_write_get_object_response_registry(
        missing_model_test, "missing model-only test registration"
    )
    duplicated_model_test = copy.deepcopy(registry)
    duplicated_model_test.metadata["test_registration"][
        "model_verifiers"
    ].append(model_only_verifier_commands[0])
    reject_write_get_object_response_registry(
        duplicated_model_test, "duplicate model-only test registration"
    )
    crossed_model_test = copy.deepcopy(registry)
    crossed_model_test.metadata["test_registration"][
        "model_verifiers"
    ][-1] = model_only_verifier_commands[0]
    reject_write_get_object_response_registry(
        crossed_model_test, "cross-operation model-test registration"
    )
    write_response_lane, write_response_commands = (
        s3_operation.qualification_plan(registry, ["WriteGetObjectResponse"])
    )
    assert write_response_lane == "write_get_object_response"
    assert write_response_commands == (
        registry.qualification["write_get_object_response"]
    )
    try:
        s3_operation.qualification_plan(
            registry, ["WriteGetObjectResponse", "WriteGetObjectResponse"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate WriteGetObjectResponse lane accepted")

    put_object_annotation_certainty = (
        "mutation model coverage only; no public request-body source, "
        "checksum binding, response decoder, or runtime evidence exists, "
        "so this review reports no successful mutation, no admission "
        "certainty, and no automatic replay"
    )

    def assert_put_object_annotation_registry(candidate):
        entry = candidate.operations["PutObjectAnnotation"]
        assert entry.get("public_name") == "Not_Exposed"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "put_object_annotation"
        assert entry.get("codec") == (
            "generated_model_only_streaming_request_and_headers"
        )
        assert entry.get("certainty") == put_object_annotation_certainty
        assert entry.get("ada_symbols") is None
        assert entry["coverage"] == {
            "backend": "missing", "client": "partial",
            "server": "missing", "corpus": "covered",
        }
        assert "no observation, causal proof" in entry["reconciliation"]
        assert "registry sentinel and not an Ada declaration" in (
            entry["exclusions"][0]
        )
        assert "are inventory only" in entry["exclusions"][1]
        assert "does not invent public limits" in entry["exclusions"][2]
        assert entry["evidence"]["client"] == [
            "src/flyology-object_storage-s3-model.adb",
            "tests/scripts/verify-put-object-annotation-model.py",
        ]
        assert candidate.qualification["put_object_annotation"] == [
            ["uv", "run", "--python", "3.13", "--",
             "tests/scripts/verify-put-object-annotation-model.py"],
            ["./tools/verify-coverage.sh"],
            ["./tools/ci/check-repository.sh", "{model}"],
            ["git", "diff", "--check"],
        ]

    def reject_put_object_annotation_registry(candidate, label):
        try:
            assert_put_object_annotation_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(f"{label} PutObjectAnnotation registry accepted")

    assert_put_object_annotation_registry(registry)
    invented_put_annotation_api = copy.deepcopy(registry)
    invented_put_annotation_api.operations[
        "PutObjectAnnotation"
    ]["public_name"] = "Put_Annotation"
    reject_put_object_annotation_registry(
        invented_put_annotation_api, "invented public API"
    )
    full_put_annotation = copy.deepcopy(registry)
    full_put_annotation.operations[
        "PutObjectAnnotation"
    ]["coverage"]["client"] = "covered"
    reject_put_object_annotation_registry(
        full_put_annotation, "invented complete client coverage"
    )
    replay_put_annotation = copy.deepcopy(registry)
    replay_put_annotation.operations[
        "PutObjectAnnotation"
    ]["certainty"] = "automatically replay after transport failure"
    reject_put_object_annotation_registry(
        replay_put_annotation, "automatic replay"
    )
    causal_put_annotation = copy.deepcopy(registry)
    causal_put_annotation.operations[
        "PutObjectAnnotation"
    ]["reconciliation"] = "a later read proves mutation causation"
    reject_put_object_annotation_registry(
        causal_put_annotation, "causal reconciliation"
    )
    bounded_put_annotation = copy.deepcopy(registry)
    bounded_put_annotation.operations[
        "PutObjectAnnotation"
    ]["exclusions"][2] = "the client enforces a one MiB public limit"
    reject_put_object_annotation_registry(
        bounded_put_annotation, "invented public limit"
    )
    put_annotation_lane, put_annotation_commands = (
        s3_operation.qualification_plan(registry, ["PutObjectAnnotation"])
    )
    assert put_annotation_lane == "put_object_annotation"
    assert put_annotation_commands == (
        registry.qualification["put_object_annotation"]
    )
    try:
        s3_operation.qualification_plan(
            registry, ["PutObjectAnnotation", "PutObjectAnnotation"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate PutObjectAnnotation lane accepted")

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
    get_object_attributes_public_name = "Get_Attributes"

    def assert_get_object_attributes_registry(candidate):
        entry = candidate.operations["GetObjectAttributes"]
        assert entry.get("public_name") == (
            get_object_attributes_public_name
        )
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "get_object_attributes"
        assert entry.get("ada_symbols") == [
            "Prepare_Get_Object_Attributes",
            "Decode_Get_Object_Attributes_Response",
            "Decode_Get_Object_Attributes_Complete_Response",
            "Execute_Get_Object_Attributes",
            "Get_Object_Attributes_Operation",
            "Get_Attributes",
            "Finish",
        ]
        assert "MaxParts=0" in entry["absence"]
        assert "bind to the prepared request" in entry["certainty"]
        assert "does not recompute" in entry["exclusions"][0]
        assert "tools/verify-get-object-attributes-preparation.py" in (
            entry["evidence"]["corpus"]
        )

    def reject_get_object_attributes_registry(candidate, label):
        try:
            assert_get_object_attributes_registry(candidate)
        except (AssertionError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} GetObjectAttributes registry accepted"
        )

    assert_get_object_attributes_registry(registry)
    missing_attributes_name = copy.deepcopy(registry)
    del missing_attributes_name.operations["GetObjectAttributes"][
        "public_name"
    ]
    reject_get_object_attributes_registry(
        missing_attributes_name,
        "missing public name",
    )
    wrong_attributes_name = copy.deepcopy(registry)
    wrong_attributes_name.operations["GetObjectAttributes"][
        "public_name"
    ] = "Get_Whole"
    reject_get_object_attributes_registry(
        wrong_attributes_name,
        "wrong public name",
    )
    cross_attributes_symbol = copy.deepcopy(registry)
    cross_attributes_symbol.operations["GetObjectAttributes"][
        "ada_symbols"
    ][0] = "Prepare_Head_Object"
    reject_get_object_attributes_registry(
        cross_attributes_symbol,
        "cross-operation symbol",
    )
    attributes_qualification, attributes_commands = (
        s3_operation.qualification_plan(
            registry,
            ["GetObjectAttributes"],
        )
    )
    assert attributes_qualification == "get_object_attributes"
    assert attributes_commands[:4] == [
        [
            "uv",
            "run",
            "--python",
            "3.13",
            "--",
            "tools/verify-get-object-attributes-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert attributes_commands[4] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-get-object-attributes-gnatdoc",
        "--operation",
        "GetObjectAttributes",
    ]
    assert attributes_commands[5:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    malformed_attributes_lane = copy.deepcopy(registry)
    malformed_attributes_lane.operations["GetObjectAttributes"][
        "qualification"
    ] = "missing_get_object_attributes_lane"
    try:
        s3_operation.qualification_plan(
            malformed_attributes_lane,
            ["GetObjectAttributes"],
        )
    except s3_operation.Audit_Error as error:
        assert "unknown qualification lane" in str(error)
    else:
        raise AssertionError(
            "malformed GetObjectAttributes lane was accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            ["GetObjectAttributes", "GetObjectAttributes"],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate GetObjectAttributes lane was accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            ["GetObjectAttributes", "HeadObject"],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed GetObjectAttributes lane was accepted")
    get_object_torrent_symbols = [
        "Prepare_Get_Object_Torrent",
        "Decode_Get_Object_Torrent_Response_Head",
        "Decode_Get_Object_Torrent_Complete_Response",
        "Execute_Get_Object_Torrent",
        "Get_Object_Torrent_Operation",
        "Get_Torrent",
        "Finish",
    ]

    def assert_get_object_torrent_registry(candidate):
        entry = candidate.operations["GetObjectTorrent"]
        assert entry.get("public_name") == "Get_Torrent"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "get_object_torrent"
        assert entry.get("ada_symbols") == get_object_torrent_symbols
        assert "structured typed rejection" in entry["absence"]
        assert "no automatic retry" in entry["certainty"]
        assert "does not prove prior object state" in entry["reconciliation"]
        assert "no public operation-specific body ceiling" in (
            entry["exclusions"][1]
        )
        assert entry["coverage"] == {
            "backend": "missing",
            "client": "covered",
            "server": "missing",
            "corpus": "covered",
        }
        assert "tools/verify-get-object-torrent-preparation.py" in (
            entry["evidence"]["corpus"]
        )

    def reject_get_object_torrent_registry(candidate, label):
        try:
            assert_get_object_torrent_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(f"{label} GetObjectTorrent registry accepted")

    assert_get_object_torrent_registry(registry)
    torrent_mutations = [
        ("missing public name", "public_name", None),
        ("wrong public name", "public_name", "Get_Object_Torrent"),
        ("automatic retry", "certainty", "read and retry automatically"),
        (
            "causal reconciliation",
            "reconciliation",
            "the read proves prior object state",
        ),
        ("missing exclusion", "exclusions", ["unbounded body"]),
    ]
    for label, key, value in torrent_mutations:
        candidate = copy.deepcopy(registry)
        entry = candidate.operations["GetObjectTorrent"]
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        assert candidate != registry
        reject_get_object_torrent_registry(candidate, label)
    cross_torrent_symbol = copy.deepcopy(registry)
    cross_torrent_symbol.operations["GetObjectTorrent"]["ada_symbols"][0] = (
        "Prepare_Get_Object_Attributes"
    )
    assert cross_torrent_symbol != registry
    reject_get_object_torrent_registry(
        cross_torrent_symbol,
        "cross-operation symbol",
    )
    torrent_qualification, torrent_commands = (
        s3_operation.qualification_plan(registry, ["GetObjectTorrent"])
    )
    assert torrent_qualification == "get_object_torrent"
    assert torrent_commands[:5] == [
        [
            "uv",
            "run",
            "--python",
            "3.13",
            "--",
            "tools/verify-get-object-torrent-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_get_object_torrent_corpus"],
        ["@tests", "./bin/s3_get_object_torrent_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert torrent_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-get-object-torrent-gnatdoc",
        "--operation",
        "GetObjectTorrent",
    ]
    assert torrent_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    for operations, expected in (
        (["GetObjectTorrent", "GetObjectTorrent"], "appears more than once"),
        (
            ["GetObjectTorrent", "GetObjectAttributes"],
            "do not share one qualification lane",
        ),
    ):
        try:
            s3_operation.qualification_plan(registry, operations)
        except s3_operation.Audit_Error as error:
            assert expected in str(error)
        else:
            raise AssertionError(
                f"invalid GetObjectTorrent plan {operations} accepted"
            )
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
    list_parts_symbols = [
        "Prepare_List_Parts",
        "Decode_List_Parts_Complete_Response",
        "Execute_List_Parts",
        "List_Parts_Operation",
        "List_Parts_Page",
        "Finish",
    ]

    def assert_list_parts_registry(candidate):
        entry = candidate.operations["ListParts"]
        assert entry.get("public_name") == "List_Parts_Page"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "list_parts"
        assert entry.get("certainty") == "read_only"
        assert entry.get("reconciliation") == "not_applicable"
        assert entry.get("ada_symbols") == list_parts_symbols
        assert "NoSuchUpload or NoSuchBucket" in entry["absence"]
        assert "PartNumberMarker" in entry["exclusions"][3]
        assert (
            candidate.qualification["list_parts"][0][-1]
            == "tools/verify-list-parts-preparation.py"
        )

    def reject_list_parts_registry(candidate, label):
        try:
            assert_list_parts_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(f"{label} ListParts registry accepted")

    assert_list_parts_registry(registry)
    missing_list_parts_name = copy.deepcopy(registry)
    del missing_list_parts_name.operations["ListParts"]["public_name"]
    reject_list_parts_registry(missing_list_parts_name, "missing public name")
    wrong_list_parts_name = copy.deepcopy(registry)
    wrong_list_parts_name.operations["ListParts"][
        "public_name"
    ] = "List_Multipart_Uploads_Page"
    reject_list_parts_registry(wrong_list_parts_name, "wrong public name")
    legacy_list_parts_absence = copy.deepcopy(registry)
    legacy_list_parts_absence.operations["ListParts"][
        "absence"
    ] = "legacy_preserved"
    reject_list_parts_registry(legacy_list_parts_absence, "legacy absence")
    cross_list_parts_symbol = copy.deepcopy(registry)
    cross_list_parts_symbol.operations["ListParts"][
        "ada_symbols"
    ][0] = "Prepare_List_Multipart_Uploads"
    reject_list_parts_registry(
        cross_list_parts_symbol, "cross-operation symbol"
    )
    list_parts_qualification, list_parts_commands = (
        s3_operation.qualification_plan(registry, ["ListParts"])
    )
    assert list_parts_qualification == "list_parts"
    assert list_parts_commands[:4] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-list-parts-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert list_parts_commands[4] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-list-parts-gnatdoc",
        "--operation",
        "ListParts",
    ]
    assert list_parts_commands[5:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(registry, ["ListParts", "ListParts"])
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate ListParts lane accepted")
    try:
        s3_operation.qualification_plan(
            registry, ["ListParts", "ListMultipartUploads"]
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed ListParts lane accepted")
    upload_part_certainty = (
        "only a complete validated 200 response observed with Part_Uploaded "
        "reports Part_Published; definite non-admission reports "
        "Definitely_Not_Staged, pre-admission cancellation reports "
        "Part_Cancelled_Before_Admission, and every complete rejection or "
        "possible or incomplete admission reports Part_Outcome_Unknown; no "
        "automatic replay"
    )
    upload_part_reconciliation = (
        "read-only ListParts for the exact bucket, key, upload identifier, "
        "and part number before any caller-selected retry or completion "
        "decision"
    )
    upload_part_symbols = [
        "Prepare_Upload_Part",
        "Decode_Upload_Part_Complete_Response",
        "Execute_Upload_Part",
        "Upload_Part_Operation",
        "Upload_Part",
        "Finish",
    ]

    def assert_upload_part_registry(candidate):
        entry = candidate.operations["UploadPart"]
        assert entry.get("public_name") == "Upload_Part"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "upload_part"
        assert entry.get("certainty") == upload_part_certainty
        assert entry.get("reconciliation") == upload_part_reconciliation
        assert entry.get("ada_symbols") == upload_part_symbols
        assert "NoSuchBucket and NoSuchUpload" in entry["absence"]
        assert "aws-chunked" in entry["exclusions"][2]
        assert (
            candidate.qualification["upload_part"][0][-1]
            == "tools/verify-upload-part-preparation.py"
        )

    def reject_upload_part_registry(candidate, label):
        try:
            assert_upload_part_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(f"{label} UploadPart registry accepted")

    assert_upload_part_registry(registry)
    missing_upload_part_name = copy.deepcopy(registry)
    del missing_upload_part_name.operations["UploadPart"]["public_name"]
    reject_upload_part_registry(missing_upload_part_name, "missing name")
    wrong_upload_part_name = copy.deepcopy(registry)
    wrong_upload_part_name.operations["UploadPart"][
        "public_name"
    ] = "Upload_Part_Copy"
    reject_upload_part_registry(wrong_upload_part_name, "wrong name")
    replay_upload_part = copy.deepcopy(registry)
    replay_upload_part.operations["UploadPart"][
        "reconciliation"
    ] = "automatically replay UploadPart"
    reject_upload_part_registry(replay_upload_part, "automatic replay")
    cross_upload_part_symbol = copy.deepcopy(registry)
    cross_upload_part_symbol.operations["UploadPart"][
        "ada_symbols"
    ][0] = "Prepare_Upload_Part_Copy"
    reject_upload_part_registry(
        cross_upload_part_symbol, "cross-operation symbol"
    )
    upload_part_qualification, upload_part_commands = (
        s3_operation.qualification_plan(registry, ["UploadPart"])
    )
    assert upload_part_qualification == "upload_part"
    assert upload_part_commands[:6] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-upload-part-preparation.py",
        ],
        ["./tools/verify-composable-client-fixtures.sh"],
        ["./tools/test-composable-client-fixtures-verifier.sh"],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert upload_part_commands[6] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-upload-part-gnatdoc",
        "--operation",
        "UploadPart",
    ]
    assert upload_part_commands[7:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(registry, ["UploadPart", "UploadPart"])
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate UploadPart lane accepted")
    try:
        s3_operation.qualification_plan(
            registry, ["UploadPart", "UploadPartCopy"]
        )
    except s3_operation.Audit_Error as error:
        assert (
            "operation has no focused qualification lane" in str(error)
            or "do not share one qualification lane" in str(error)
        )
    else:
        raise AssertionError("mixed UploadPart lane accepted")
    upload_part_copy_certainty = (
        "only a complete validated 200 Part_Copied response observed reports "
        "Published; exact 412 PreconditionFailed reports Precondition_Failed; "
        "recognized complete authentication, authorization, not-found, "
        "invalid-request, and NotImplemented rejections or definite "
        "non-admission report Definitely_Not_Published; pre-admission "
        "cancellation reports Cancelled_Before_Publication; possible or "
        "incomplete admission and embedded or retryable errors report "
        "Outcome_Unknown; no automatic replay"
    )
    upload_part_copy_reconciliation = (
        "read-only ListParts for the exact destination bucket, key, upload "
        "identifier, and part number before any caller-selected retry or "
        "completion decision"
    )
    upload_part_copy_symbols = [
        "Prepare_Upload_Part_Copy",
        "Decode_Upload_Part_Copy_Complete_Response",
        "Execute_Upload_Part_Copy",
        "Upload_Part_Copy_Operation",
        "Upload_Part_Copy",
        "Finish",
    ]

    def assert_upload_part_copy_registry(candidate):
        entry = candidate.operations["UploadPartCopy"]
        assert entry.get("public_name") == "Upload_Part_Copy"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "upload_part_copy"
        assert entry.get("certainty") == upload_part_copy_certainty
        assert entry.get("reconciliation") == upload_part_copy_reconciliation
        assert entry.get("ada_symbols") == upload_part_copy_symbols
        assert "NoSuchUpload" in entry["absence"]
        assert "caller-selected source version" in entry["exclusions"][1]
        assert (
            candidate.qualification["upload_part_copy"][0][-1]
            == "tools/verify-upload-part-copy-preparation.py"
        )

    def reject_upload_part_copy_registry(candidate, label):
        try:
            assert_upload_part_copy_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(f"{label} UploadPartCopy registry accepted")

    assert_upload_part_copy_registry(registry)
    missing_upload_part_copy_name = copy.deepcopy(registry)
    del missing_upload_part_copy_name.operations["UploadPartCopy"][
        "public_name"
    ]
    reject_upload_part_copy_registry(
        missing_upload_part_copy_name, "missing name"
    )
    wrong_upload_part_copy_name = copy.deepcopy(registry)
    wrong_upload_part_copy_name.operations["UploadPartCopy"][
        "public_name"
    ] = "Upload_Part"
    reject_upload_part_copy_registry(wrong_upload_part_copy_name, "wrong name")
    replay_upload_part_copy = copy.deepcopy(registry)
    replay_upload_part_copy.operations["UploadPartCopy"][
        "reconciliation"
    ] = "automatically replay UploadPartCopy"
    reject_upload_part_copy_registry(
        replay_upload_part_copy, "automatic replay"
    )
    cross_upload_part_copy_symbol = copy.deepcopy(registry)
    cross_upload_part_copy_symbol.operations["UploadPartCopy"][
        "ada_symbols"
    ][0] = "Prepare_Upload_Part"
    reject_upload_part_copy_registry(
        cross_upload_part_copy_symbol, "cross-operation symbol"
    )
    upload_part_copy_qualification, upload_part_copy_commands = (
        s3_operation.qualification_plan(registry, ["UploadPartCopy"])
    )
    assert upload_part_copy_qualification == "upload_part_copy"
    assert upload_part_copy_commands[:4] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-upload-part-copy-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert upload_part_copy_commands[4] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-upload-part-copy-gnatdoc",
        "--operation",
        "UploadPartCopy",
    ]
    assert upload_part_copy_commands[5:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry, ["UploadPartCopy", "UploadPartCopy"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate UploadPartCopy lane accepted")
    try:
        s3_operation.qualification_plan(
            registry, ["UploadPartCopy", "UploadPart"]
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed UploadPartCopy lane accepted")
    get_object_acl_certainty = (
        "read-only; only one complete validated 200 Object_ACL_Found response "
        "observed exposes the presence-preserving ACL and requester-charge "
        "result; every incomplete, invalid, or non-observed response exposes "
        "no ACL; the client performs no automatic retry"
    )
    get_object_acl_reconciliation = (
        "an explicit VersionId observes the ACL derived for that selected "
        "object generation and an omitted VersionId observes the generation "
        "current at read time; neither form proves that a prior mutation "
        "caused the observed ACL"
    )
    get_object_acl_symbols = [
        "Prepare_Get_Object_ACL",
        "Decode_Get_Object_ACL_Response",
        "Execute_Get_Object_ACL",
        "Get_Object_ACL_Operation",
        "Get_ACL",
        "Finish",
    ]

    def assert_get_object_acl_registry(candidate):
        entry = candidate.operations["GetObjectAcl"]
        assert entry.get("public_name") == "Get_ACL"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "get_object_acl"
        assert entry.get("certainty") == get_object_acl_certainty
        assert entry.get("reconciliation") == get_object_acl_reconciliation
        assert entry.get("ada_symbols") == get_object_acl_symbols
        assert entry["coverage"]["backend"] == "missing"
        assert entry["provenance"]["backend"] == "absent"
        assert "NoSuchVersion" in entry["absence"]
        assert "no version identifier" in entry["exclusions"][0]
        assert (
            candidate.qualification["get_object_acl"][0][-1]
            == "tools/verify-get-object-acl-preparation.py"
        )

    def reject_get_object_acl_registry(candidate, label):
        try:
            assert_get_object_acl_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(f"{label} GetObjectAcl registry accepted")

    assert_get_object_acl_registry(registry)
    missing_get_object_acl_name = copy.deepcopy(registry)
    del missing_get_object_acl_name.operations["GetObjectAcl"]["public_name"]
    reject_get_object_acl_registry(
        missing_get_object_acl_name, "missing name"
    )
    wrong_get_object_acl_name = copy.deepcopy(registry)
    wrong_get_object_acl_name.operations["GetObjectAcl"][
        "public_name"
    ] = "Get_ACL_Policy"
    reject_get_object_acl_registry(wrong_get_object_acl_name, "wrong name")
    retry_get_object_acl = copy.deepcopy(registry)
    retry_get_object_acl.operations["GetObjectAcl"][
        "certainty"
    ] = "read-only; retry automatically"
    reject_get_object_acl_registry(retry_get_object_acl, "automatic retry")
    backend_get_object_acl = copy.deepcopy(registry)
    backend_get_object_acl.operations["GetObjectAcl"]["coverage"][
        "backend"
    ] = "covered"
    reject_get_object_acl_registry(
        backend_get_object_acl, "invented backend coverage"
    )
    cross_get_object_acl_symbol = copy.deepcopy(registry)
    cross_get_object_acl_symbol.operations["GetObjectAcl"][
        "ada_symbols"
    ][0] = "Prepare_Get_Bucket_ACL"
    reject_get_object_acl_registry(
        cross_get_object_acl_symbol, "cross-operation symbol"
    )
    get_object_acl_qualification, get_object_acl_commands = (
        s3_operation.qualification_plan(registry, ["GetObjectAcl"])
    )
    assert get_object_acl_qualification == "get_object_acl"
    assert get_object_acl_commands[:5] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-get-object-acl-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_get_object_acl_corpus"],
        ["@tests", "./bin/s3_server_application_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
    ]
    assert get_object_acl_commands[5] == ["./tools/verify-coverage.sh"]
    assert get_object_acl_commands[6] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-get-object-acl-gnatdoc",
        "--operation",
        "GetObjectAcl",
    ]
    assert get_object_acl_commands[7:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry, ["GetObjectAcl", "GetObjectAcl"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate GetObjectAcl lane accepted")
    try:
        s3_operation.qualification_plan(
            registry, ["GetObjectAcl", "GetObject"]
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed GetObjectAcl lane accepted")
    get_bucket_acl_certainty = (
        "read-only; only one complete validated 200 Bucket_ACL_Found response "
        "observed exposes the presence-preserving ACL; every incomplete, "
        "invalid, or non-observed response exposes no ACL; the client "
        "performs no automatic retry"
    )
    get_bucket_acl_reconciliation = (
        "the result is a read-only observation of the bucket ACL projection "
        "at response time and does not prove that any prior mutation caused "
        "the observed policy"
    )
    get_bucket_acl_symbols = [
        "Prepare_Get_Bucket_ACL",
        "Decode_Get_Bucket_ACL_Response",
        "Execute_Get_Bucket_ACL",
        "Get_Bucket_ACL_Operation",
        "Get_ACL",
        "Finish",
    ]

    def assert_get_bucket_acl_registry(candidate):
        entry = candidate.operations["GetBucketAcl"]
        assert entry.get("public_name") == "Get_ACL"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "get_bucket_acl"
        assert entry.get("certainty") == get_bucket_acl_certainty
        assert entry.get("reconciliation") == get_bucket_acl_reconciliation
        assert entry.get("ada_symbols") == get_bucket_acl_symbols
        assert entry["coverage"]["backend"] == "missing"
        assert entry["provenance"]["backend"] == "absent"
        assert "NoSuchBucket" in entry["absence"]
        assert "does not persist arbitrary ACL state" in entry["exclusions"][0]
        assert (
            candidate.qualification["get_bucket_acl"][0][-1]
            == "tools/verify-get-bucket-acl-preparation.py"
        )

    def reject_get_bucket_acl_registry(candidate, label):
        try:
            assert_get_bucket_acl_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(f"{label} GetBucketAcl registry accepted")

    assert_get_bucket_acl_registry(registry)
    missing_get_bucket_acl_name = copy.deepcopy(registry)
    del missing_get_bucket_acl_name.operations["GetBucketAcl"]["public_name"]
    reject_get_bucket_acl_registry(
        missing_get_bucket_acl_name, "missing name"
    )
    wrong_get_bucket_acl_name = copy.deepcopy(registry)
    wrong_get_bucket_acl_name.operations["GetBucketAcl"][
        "public_name"
    ] = "Get_Object_ACL"
    reject_get_bucket_acl_registry(wrong_get_bucket_acl_name, "wrong name")
    retry_get_bucket_acl = copy.deepcopy(registry)
    retry_get_bucket_acl.operations["GetBucketAcl"][
        "certainty"
    ] = "read-only; retry automatically"
    reject_get_bucket_acl_registry(retry_get_bucket_acl, "automatic retry")
    backend_get_bucket_acl = copy.deepcopy(registry)
    backend_get_bucket_acl.operations["GetBucketAcl"]["coverage"][
        "backend"
    ] = "covered"
    reject_get_bucket_acl_registry(
        backend_get_bucket_acl, "invented backend coverage"
    )
    cross_get_bucket_acl_symbol = copy.deepcopy(registry)
    cross_get_bucket_acl_symbol.operations["GetBucketAcl"][
        "ada_symbols"
    ][0] = "Prepare_Get_Object_ACL"
    reject_get_bucket_acl_registry(
        cross_get_bucket_acl_symbol, "cross-operation symbol"
    )
    get_bucket_acl_qualification, get_bucket_acl_commands = (
        s3_operation.qualification_plan(registry, ["GetBucketAcl"])
    )
    assert get_bucket_acl_qualification == "get_bucket_acl"
    assert get_bucket_acl_commands[:5] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-get-bucket-acl-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_get_bucket_acl_corpus"],
        ["@tests", "./bin/s3_server_application_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
    ]
    assert get_bucket_acl_commands[5] == ["./tools/verify-coverage.sh"]
    assert get_bucket_acl_commands[6] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-get-bucket-acl-gnatdoc",
        "--operation",
        "GetBucketAcl",
    ]
    assert get_bucket_acl_commands[7:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry, ["GetBucketAcl", "GetBucketAcl"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate GetBucketAcl lane accepted")
    try:
        s3_operation.qualification_plan(
            registry, ["GetBucketAcl", "GetObjectAcl"]
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed GetBucketAcl lane accepted")
    get_object_legal_hold_certainty = (
        "read-only; only one complete validated 200 Object_Legal_Hold_Found "
        "response observed exposes the presence-preserving legal-hold value; "
        "every incomplete, invalid, or non-observed response exposes no "
        "legal-hold state; the client performs no automatic retry"
    )
    get_object_legal_hold_reconciliation = (
        "an explicit VersionId observes legal-hold state for that selected "
        "object generation and an omitted VersionId observes the generation "
        "current at read time; the modeled response does not echo a version "
        "identifier and neither form proves that a prior mutation caused the "
        "observed state"
    )
    get_object_legal_hold_symbols = [
        "Prepare_Get_Object_Legal_Hold",
        "Decode_Get_Object_Legal_Hold_Response",
        "Execute_Get_Object_Legal_Hold",
        "Get_Legal_Hold_Operation",
        "Get_Legal_Hold",
        "Finish",
    ]

    def assert_get_object_legal_hold_registry(candidate):
        entry = candidate.operations["GetObjectLegalHold"]
        assert entry.get("public_name") == "Get_Legal_Hold"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "get_object_legal_hold"
        assert entry.get("certainty") == get_object_legal_hold_certainty
        assert (
            entry.get("reconciliation") == get_object_legal_hold_reconciliation
        )
        assert entry.get("ada_symbols") == get_object_legal_hold_symbols
        assert entry["coverage"]["backend"] == "missing"
        assert entry["coverage"]["server"] == "missing"
        assert entry["provenance"]["backend"] == "absent"
        assert entry["provenance"]["server"] == "absent"
        assert "NoSuchVersion" in entry["absence"]
        assert "server route are absent" in entry["exclusions"][0]
        assert (
            candidate.qualification["get_object_legal_hold"][0][-1]
            == "tools/verify-get-object-legal-hold-preparation.py"
        )

    def reject_get_object_legal_hold_registry(candidate, label):
        try:
            assert_get_object_legal_hold_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(f"{label} GetObjectLegalHold registry accepted")

    assert_get_object_legal_hold_registry(registry)
    missing_get_object_legal_hold_name = copy.deepcopy(registry)
    del missing_get_object_legal_hold_name.operations["GetObjectLegalHold"][
        "public_name"
    ]
    reject_get_object_legal_hold_registry(
        missing_get_object_legal_hold_name, "missing name"
    )
    wrong_get_object_legal_hold_name = copy.deepcopy(registry)
    wrong_get_object_legal_hold_name.operations["GetObjectLegalHold"][
        "public_name"
    ] = "Get_Retention"
    reject_get_object_legal_hold_registry(
        wrong_get_object_legal_hold_name, "wrong name"
    )
    retry_get_object_legal_hold = copy.deepcopy(registry)
    retry_get_object_legal_hold.operations["GetObjectLegalHold"][
        "certainty"
    ] = "read-only; retry automatically"
    reject_get_object_legal_hold_registry(
        retry_get_object_legal_hold, "automatic retry"
    )
    server_get_object_legal_hold = copy.deepcopy(registry)
    server_get_object_legal_hold.operations["GetObjectLegalHold"]["coverage"][
        "server"
    ] = "covered"
    reject_get_object_legal_hold_registry(
        server_get_object_legal_hold, "invented server coverage"
    )
    cross_get_object_legal_hold_symbol = copy.deepcopy(registry)
    cross_get_object_legal_hold_symbol.operations["GetObjectLegalHold"][
        "ada_symbols"
    ][0] = "Prepare_Get_Object_Retention"
    reject_get_object_legal_hold_registry(
        cross_get_object_legal_hold_symbol, "cross-operation symbol"
    )
    get_object_legal_hold_qualification, get_object_legal_hold_commands = (
        s3_operation.qualification_plan(registry, ["GetObjectLegalHold"])
    )
    assert get_object_legal_hold_qualification == "get_object_legal_hold"
    assert get_object_legal_hold_commands[:4] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-get-object-legal-hold-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_get_object_legal_hold_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
    ]
    assert get_object_legal_hold_commands[4] == ["./tools/verify-coverage.sh"]
    assert get_object_legal_hold_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-get-object-legal-hold-gnatdoc",
        "--operation",
        "GetObjectLegalHold",
    ]
    assert get_object_legal_hold_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry, ["GetObjectLegalHold", "GetObjectLegalHold"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate GetObjectLegalHold lane accepted")
    try:
        s3_operation.qualification_plan(
            registry, ["GetObjectLegalHold", "PutObjectLegalHold"]
        )
    except s3_operation.Audit_Error as error:
        assert (
            "do not share one qualification lane" in str(error)
            or "has no focused qualification lane" in str(error)
        )
    else:
        raise AssertionError("mixed GetObjectLegalHold lane accepted")
    put_object_legal_hold_certainty = (
        "only a complete validated 200 reports "
        "Legal_Hold_Mutation_Completed; an exact recognized S3 rejection or "
        "definite non-admission reports "
        "Legal_Hold_Mutation_Definitely_Not_Applied, pre-admission "
        "cancellation reports "
        "Legal_Hold_Mutation_Cancelled_Before_Admission, and every other "
        "possibly admitted or incomplete outcome reports "
        "Legal_Hold_Mutation_Outcome_Unknown; no automatic replay"
    )
    put_object_legal_hold_reconciliation = (
        "an explicit VersionId permits a read-only GetObjectLegalHold "
        "observation of that selected object generation and an omitted "
        "VersionId permits only an observation of the generation current at "
        "reconciliation time; neither observation proves that the lost "
        "mutation caused the state or upgrades mutation certainty without "
        "caller-supplied serialization authority"
    )
    put_object_legal_hold_symbols = [
        "Prepare_Put_Object_Legal_Hold",
        "Decode_Put_Object_Legal_Hold_Response",
        "Execute_Put_Object_Legal_Hold",
        "Put_Legal_Hold_Operation",
        "Put_Legal_Hold",
        "Finish",
    ]

    def assert_put_object_legal_hold_registry(candidate):
        entry = candidate.operations["PutObjectLegalHold"]
        assert entry.get("public_name") == "Put_Legal_Hold"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "put_object_legal_hold"
        assert entry.get("certainty") == put_object_legal_hold_certainty
        assert (
            entry.get("reconciliation") == put_object_legal_hold_reconciliation
        )
        assert entry.get("ada_symbols") == put_object_legal_hold_symbols
        assert entry["coverage"]["backend"] == "missing"
        assert entry["coverage"]["server"] == "missing"
        assert entry["provenance"]["backend"] == "absent"
        assert entry["provenance"]["server"] == "absent"
        assert "no automatic replay" in entry["certainty"]
        assert "server route are absent" in entry["exclusions"][0]
        assert (
            candidate.qualification["put_object_legal_hold"][0][-1]
            == "tools/verify-put-object-legal-hold-preparation.py"
        )

    def reject_put_object_legal_hold_registry(candidate, label):
        try:
            assert_put_object_legal_hold_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(f"{label} PutObjectLegalHold registry accepted")

    assert_put_object_legal_hold_registry(registry)
    missing_put_object_legal_hold_name = copy.deepcopy(registry)
    del missing_put_object_legal_hold_name.operations["PutObjectLegalHold"][
        "public_name"
    ]
    reject_put_object_legal_hold_registry(
        missing_put_object_legal_hold_name, "missing name"
    )
    wrong_put_object_legal_hold_name = copy.deepcopy(registry)
    wrong_put_object_legal_hold_name.operations["PutObjectLegalHold"][
        "public_name"
    ] = "Put_Retention"
    reject_put_object_legal_hold_registry(
        wrong_put_object_legal_hold_name, "wrong name"
    )
    retry_put_object_legal_hold = copy.deepcopy(registry)
    retry_put_object_legal_hold.operations["PutObjectLegalHold"][
        "certainty"
    ] = "mutation; retry automatically after a lost response"
    reject_put_object_legal_hold_registry(
        retry_put_object_legal_hold, "automatic retry"
    )
    causal_put_object_legal_hold = copy.deepcopy(registry)
    causal_put_object_legal_hold.operations["PutObjectLegalHold"][
        "reconciliation"
    ] = "GetObjectLegalHold proves the lost mutation caused the state"
    reject_put_object_legal_hold_registry(
        causal_put_object_legal_hold, "causal reconciliation"
    )
    server_put_object_legal_hold = copy.deepcopy(registry)
    server_put_object_legal_hold.operations["PutObjectLegalHold"]["coverage"][
        "server"
    ] = "covered"
    reject_put_object_legal_hold_registry(
        server_put_object_legal_hold, "invented server coverage"
    )
    cross_put_object_legal_hold_symbol = copy.deepcopy(registry)
    cross_put_object_legal_hold_symbol.operations["PutObjectLegalHold"][
        "ada_symbols"
    ][0] = "Prepare_Put_Object_Retention"
    reject_put_object_legal_hold_registry(
        cross_put_object_legal_hold_symbol, "cross-operation symbol"
    )
    put_object_legal_hold_qualification, put_object_legal_hold_commands = (
        s3_operation.qualification_plan(registry, ["PutObjectLegalHold"])
    )
    assert put_object_legal_hold_qualification == "put_object_legal_hold"
    assert put_object_legal_hold_commands[:4] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-put-object-legal-hold-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_put_object_legal_hold_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
    ]
    assert put_object_legal_hold_commands[4] == ["./tools/verify-coverage.sh"]
    assert put_object_legal_hold_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-put-object-legal-hold-gnatdoc",
        "--operation",
        "PutObjectLegalHold",
    ]
    assert put_object_legal_hold_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry, ["PutObjectLegalHold", "PutObjectLegalHold"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate PutObjectLegalHold lane accepted")
    try:
        s3_operation.qualification_plan(
            registry, ["PutObjectLegalHold", "GetObjectLegalHold"]
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed PutObjectLegalHold lane accepted")
    def assert_bucket_control_backend_server(entry):
        assert entry["coverage"]["backend"] == "covered"
        assert entry["coverage"]["server"] == "covered"
        assert entry["provenance"]["backend"] == "handwritten"
        assert entry["provenance"]["server"] == "handwritten"
        assert entry["evidence"]["backend"] == [
            "tests/src/object_storage_test_cases.adb",
            "sqlite/tests/src/flyology_object_storage_sqlite_tests.adb",
        ]
        assert entry["evidence"]["server"] == [
            "src/flyology-object_storage-server-s3_applications.adb",
            "tests/src/s3_server_application_corpus.adb",
        ]

    for operation in (
        "DeleteBucketLifecycle",
        "GetBucketLifecycle",
        "GetBucketLifecycleConfiguration",
        "GetBucketLogging",
        "PutBucketLifecycleConfiguration",
        "PutBucketLogging",
    ):
        entry = registry.operations[operation]
        assert_bucket_control_backend_server(entry)
        assert "tests/src/s3_server_application_corpus.adb" in (
            entry["evidence"]["corpus"]
        )
        missing_server = copy.deepcopy(entry)
        missing_server["coverage"]["server"] = "missing"
        try:
            assert_bucket_control_backend_server(missing_server)
        except AssertionError:
            pass
        else:
            raise AssertionError(
                f"{operation} missing server coverage was accepted"
            )

    for operation in (
        "DeleteBucketReplication",
        "GetBucketReplication",
        "PutBucketReplication",
        "DeleteBucketWebsite",
        "GetBucketWebsite",
        "PutBucketWebsite",
    ):
        entry = registry.operations[operation]
        assert_bucket_control_backend_server(entry)
        exclusions = " ".join(entry["exclusions"])
        generation_exclusions = " ".join(
            entry.get("generation", {}).get("intentional_exclusions", [])
        )
        assert "backend persistence" not in exclusions
        assert "authenticated server routing" not in exclusions
        assert "no backend or server compatibility claim" not in (
            generation_exclusions
        )
        for label, mutate in (
            (
                "missing backend evidence",
                lambda item: item["evidence"].update(backend=[]),
            ),
            (
                "missing server evidence",
                lambda item: item["evidence"].update(server=[]),
            ),
        ):
            candidate = copy.deepcopy(entry)
            mutate(candidate)
            try:
                assert_bucket_control_backend_server(candidate)
            except AssertionError:
                pass
            else:
                raise AssertionError(f"{operation} {label} was accepted")

    for operation in ("GetBucketLogging", "PutBucketLogging"):
        assert "log delivery" in (
            " ".join(registry.operations[operation]["exclusions"])
            + " "
            + " ".join(
                registry.operations[operation]
                .get("generation", {})
                .get("intentional_exclusions", [])
            )
        )

    get_bucket_encryption_certainty = (
        "read-only; only one complete validated exact 200 "
        "Bucket_Control_Found response observed exposes the "
        "presence-preserving encryption configuration; every incomplete, "
        "invalid, or non-observed response exposes no configuration state; "
        "the client performs no automatic retry"
    )
    get_bucket_encryption_reconciliation = (
        "a later GetBucketEncryption observes only the bucket encryption "
        "configuration current at read time; it does not prove that a prior "
        "mutation caused the observed state or authorize automatic replay"
    )
    get_bucket_encryption_symbols = [
        "Prepare_Get_Bucket_Encryption",
        "Decode_Get_Bucket_Encryption_Response",
        "Execute_Get_Bucket_Encryption",
        "Get_Bucket_Encryption_Operation",
        "Get_Encryption",
        "Finish",
    ]

    def assert_get_bucket_encryption_registry(candidate):
        entry = candidate.operations["GetBucketEncryption"]
        assert entry.get("public_name") == "Get_Encryption"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "get_bucket_encryption"
        assert entry.get("certainty") == get_bucket_encryption_certainty
        assert entry.get("reconciliation") == (
            get_bucket_encryption_reconciliation
        )
        assert entry.get("ada_symbols") == get_bucket_encryption_symbols
        assert_bucket_control_backend_server(entry)
        assert "absent optional" in entry["absence"]
        assert "preserve the exact modeled encryption" in (
            entry["exclusions"][0]
        )
        assert candidate.qualification["get_bucket_encryption"][0][-1] == (
            "tools/verify-get-bucket-encryption-preparation.py"
        )

    def reject_get_bucket_encryption_registry(candidate, label):
        try:
            assert_get_bucket_encryption_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} GetBucketEncryption registry accepted"
        )

    assert_get_bucket_encryption_registry(registry)
    missing_get_bucket_encryption_name = copy.deepcopy(registry)
    del missing_get_bucket_encryption_name.operations[
        "GetBucketEncryption"
    ]["public_name"]
    reject_get_bucket_encryption_registry(
        missing_get_bucket_encryption_name, "missing name"
    )
    wrong_get_bucket_encryption_name = copy.deepcopy(registry)
    wrong_get_bucket_encryption_name.operations[
        "GetBucketEncryption"
    ]["public_name"] = "Set_Encryption"
    reject_get_bucket_encryption_registry(
        wrong_get_bucket_encryption_name, "wrong name"
    )
    retry_get_bucket_encryption = copy.deepcopy(registry)
    retry_get_bucket_encryption.operations[
        "GetBucketEncryption"
    ]["certainty"] = "read-only; retry automatically"
    reject_get_bucket_encryption_registry(
        retry_get_bucket_encryption, "automatic retry"
    )
    causal_get_bucket_encryption = copy.deepcopy(registry)
    causal_get_bucket_encryption.operations[
        "GetBucketEncryption"
    ]["reconciliation"] = "the read proves the prior mutation caused state"
    reject_get_bucket_encryption_registry(
        causal_get_bucket_encryption, "causal reconciliation"
    )
    missing_server_get_bucket_encryption = copy.deepcopy(registry)
    missing_server_get_bucket_encryption.operations[
        "GetBucketEncryption"
    ]["coverage"]["server"] = "missing"
    reject_get_bucket_encryption_registry(
        missing_server_get_bucket_encryption, "missing server coverage"
    )
    cross_get_bucket_encryption_symbol = copy.deepcopy(registry)
    cross_get_bucket_encryption_symbol.operations[
        "GetBucketEncryption"
    ]["ada_symbols"][0] = "Prepare_Put_Bucket_Encryption"
    reject_get_bucket_encryption_registry(
        cross_get_bucket_encryption_symbol, "cross-operation symbol"
    )
    get_bucket_encryption_qualification, encryption_commands = (
        s3_operation.qualification_plan(registry, ["GetBucketEncryption"])
    )
    assert get_bucket_encryption_qualification == "get_bucket_encryption"
    assert encryption_commands[:4] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-get-bucket-encryption-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_get_bucket_encryption_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
    ]
    assert encryption_commands[4] == ["./tools/verify-coverage.sh"]
    assert encryption_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-get-bucket-encryption-gnatdoc",
        "--operation",
        "GetBucketEncryption",
    ]
    assert encryption_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry, ["GetBucketEncryption", "GetBucketEncryption"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate GetBucketEncryption lane accepted")
    try:
        s3_operation.qualification_plan(
            registry, ["GetBucketEncryption", "PutBucketEncryption"]
        )
    except s3_operation.Audit_Error as error:
        assert (
            "do not share one qualification lane" in str(error)
            or "has no focused qualification lane" in str(error)
        )
    else:
        raise AssertionError("mixed BucketEncryption lane accepted")
    put_bucket_encryption_certainty = (
        "only a complete validated exact 200 Bucket_Control_Updated response "
        "observed reports Bucket_Encryption_Mutation_Completed; a "
        "response-observed exact recognized authentication, authorization, "
        "not-found, invalid-request, checksum, malformed-XML, or "
        "NotImplemented rejection or definite non-admission reports "
        "Bucket_Encryption_Mutation_Definitely_Not_Applied; pre-admission "
        "cancellation reports "
        "Bucket_Encryption_Mutation_Cancelled_Before_Admission; every other "
        "possibly admitted, incomplete, retryable, or corrupt outcome "
        "reports Bucket_Encryption_Mutation_Outcome_Unknown; no automatic "
        "replay"
    )
    put_bucket_encryption_reconciliation = (
        "a later GetBucketEncryption may observe the bucket encryption "
        "configuration current at read time before a caller-selected retry, "
        "but it neither proves that the lost mutation caused the observed "
        "state nor upgrades mutation certainty; no automatic replay"
    )
    put_bucket_encryption_symbols = [
        "Prepare_Put_Bucket_Encryption",
        "Execute_Put_Bucket_Encryption",
        "Put_Bucket_Encryption_Operation",
        "Set_Encryption",
        "Finish",
    ]

    def assert_put_bucket_encryption_registry(candidate):
        entry = candidate.operations["PutBucketEncryption"]
        assert entry.get("public_name") == "Set_Encryption"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "put_bucket_encryption"
        assert entry.get("certainty") == put_bucket_encryption_certainty
        assert entry.get("reconciliation") == (
            put_bucket_encryption_reconciliation
        )
        assert entry.get("ada_symbols") == put_bucket_encryption_symbols
        assert_bucket_control_backend_server(entry)
        assert entry.get("absence") == "not_applicable"
        assert "preserve caller-selected modeled algorithms" in (
            entry["exclusions"][0]
        )
        assert "exact same immutable" in entry["exclusions"][1]
        assert candidate.qualification["put_bucket_encryption"][0][-1] == (
            "tools/verify-put-bucket-encryption-preparation.py"
        )

    def reject_put_bucket_encryption_registry(candidate, label):
        try:
            assert_put_bucket_encryption_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} PutBucketEncryption registry accepted"
        )

    assert_put_bucket_encryption_registry(registry)
    missing_put_bucket_encryption_name = copy.deepcopy(registry)
    del missing_put_bucket_encryption_name.operations[
        "PutBucketEncryption"
    ]["public_name"]
    reject_put_bucket_encryption_registry(
        missing_put_bucket_encryption_name, "missing name"
    )
    wrong_put_bucket_encryption_name = copy.deepcopy(registry)
    wrong_put_bucket_encryption_name.operations[
        "PutBucketEncryption"
    ]["public_name"] = "Get_Encryption"
    reject_put_bucket_encryption_registry(
        wrong_put_bucket_encryption_name, "wrong name"
    )
    replay_put_bucket_encryption = copy.deepcopy(registry)
    replay_put_bucket_encryption.operations[
        "PutBucketEncryption"
    ]["certainty"] = "automatically replay PutBucketEncryption"
    reject_put_bucket_encryption_registry(
        replay_put_bucket_encryption, "automatic replay"
    )
    causal_put_bucket_encryption = copy.deepcopy(registry)
    causal_put_bucket_encryption.operations[
        "PutBucketEncryption"
    ]["reconciliation"] = "the read proves the mutation caused state"
    reject_put_bucket_encryption_registry(
        causal_put_bucket_encryption, "causal reconciliation"
    )
    missing_server_put_bucket_encryption = copy.deepcopy(registry)
    missing_server_put_bucket_encryption.operations[
        "PutBucketEncryption"
    ]["coverage"]["server"] = "missing"
    reject_put_bucket_encryption_registry(
        missing_server_put_bucket_encryption, "missing server coverage"
    )
    cross_put_bucket_encryption_symbol = copy.deepcopy(registry)
    cross_put_bucket_encryption_symbol.operations[
        "PutBucketEncryption"
    ]["ada_symbols"][0] = "Prepare_Get_Bucket_Encryption"
    reject_put_bucket_encryption_registry(
        cross_put_bucket_encryption_symbol, "cross-operation symbol"
    )
    put_bucket_encryption_qualification, put_encryption_commands = (
        s3_operation.qualification_plan(registry, ["PutBucketEncryption"])
    )
    assert put_bucket_encryption_qualification == "put_bucket_encryption"
    assert put_encryption_commands[:4] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-put-bucket-encryption-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_get_bucket_encryption_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
    ]
    assert put_encryption_commands[4] == ["./tools/verify-coverage.sh"]
    assert put_encryption_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-put-bucket-encryption-gnatdoc",
        "--operation",
        "PutBucketEncryption",
    ]
    assert put_encryption_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry, ["PutBucketEncryption", "PutBucketEncryption"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate PutBucketEncryption lane accepted")
    try:
        s3_operation.qualification_plan(
            registry, ["PutBucketEncryption", "GetBucketEncryption"]
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed PutBucketEncryption lane accepted")
    get_bucket_ownership_controls_certainty = (
        "read-only; only one complete validated exact 200 "
        "Bucket_Control_Found response observed exposes the "
        "presence-preserving ownership-controls configuration; every "
        "incomplete, invalid, or non-observed response exposes no "
        "configuration state; the client performs no automatic retry"
    )
    get_bucket_ownership_controls_reconciliation = (
        "a later GetBucketOwnershipControls observes only the bucket "
        "ownership-controls configuration current at read time; it does not "
        "prove that a prior mutation caused the observed state or authorize "
        "automatic replay"
    )
    get_bucket_ownership_controls_symbols = [
        "Prepare_Get_Bucket_Ownership_Controls",
        "Decode_Get_Bucket_Ownership_Controls_Response",
        "Execute_Get_Bucket_Ownership_Controls",
        "Get_Bucket_Ownership_Controls_Operation",
        "Get_Ownership_Controls",
        "Finish",
    ]

    def assert_get_bucket_ownership_controls_registry(candidate):
        entry = candidate.operations["GetBucketOwnershipControls"]
        assert entry.get("public_name") == "Get_Ownership_Controls"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == (
            "get_bucket_ownership_controls"
        )
        assert entry.get("certainty") == (
            get_bucket_ownership_controls_certainty
        )
        assert entry.get("reconciliation") == (
            get_bucket_ownership_controls_reconciliation
        )
        assert entry.get("ada_symbols") == (
            get_bucket_ownership_controls_symbols
        )
        assert_bucket_control_backend_server(entry)
        assert "OwnershipControlsNotFoundError" in entry["absence"]
        assert "preserve caller-observed" in entry["exclusions"][0]
        assert candidate.qualification[
            "get_bucket_ownership_controls"
        ][0][-1] == "tools/verify-get-bucket-ownership-controls-preparation.py"

    def reject_get_bucket_ownership_controls_registry(candidate, label):
        try:
            assert_get_bucket_ownership_controls_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} GetBucketOwnershipControls registry accepted"
        )

    assert_get_bucket_ownership_controls_registry(registry)
    missing_get_bucket_ownership_controls_name = copy.deepcopy(registry)
    del missing_get_bucket_ownership_controls_name.operations[
        "GetBucketOwnershipControls"
    ]["public_name"]
    reject_get_bucket_ownership_controls_registry(
        missing_get_bucket_ownership_controls_name, "missing name"
    )
    wrong_get_bucket_ownership_controls_name = copy.deepcopy(registry)
    wrong_get_bucket_ownership_controls_name.operations[
        "GetBucketOwnershipControls"
    ]["public_name"] = "Set_Ownership_Controls"
    reject_get_bucket_ownership_controls_registry(
        wrong_get_bucket_ownership_controls_name, "wrong name"
    )
    retry_get_bucket_ownership_controls = copy.deepcopy(registry)
    retry_get_bucket_ownership_controls.operations[
        "GetBucketOwnershipControls"
    ]["certainty"] = "read-only; retry automatically"
    reject_get_bucket_ownership_controls_registry(
        retry_get_bucket_ownership_controls, "automatic retry"
    )
    causal_get_bucket_ownership_controls = copy.deepcopy(registry)
    causal_get_bucket_ownership_controls.operations[
        "GetBucketOwnershipControls"
    ]["reconciliation"] = "the read proves the prior mutation caused state"
    reject_get_bucket_ownership_controls_registry(
        causal_get_bucket_ownership_controls, "causal reconciliation"
    )
    missing_server_get_bucket_ownership_controls = copy.deepcopy(registry)
    missing_server_get_bucket_ownership_controls.operations[
        "GetBucketOwnershipControls"
    ]["coverage"]["server"] = "missing"
    reject_get_bucket_ownership_controls_registry(
        missing_server_get_bucket_ownership_controls,
        "missing server coverage",
    )
    cross_get_bucket_ownership_controls_symbol = copy.deepcopy(registry)
    cross_get_bucket_ownership_controls_symbol.operations[
        "GetBucketOwnershipControls"
    ]["ada_symbols"][0] = "Prepare_Put_Bucket_Ownership_Controls"
    reject_get_bucket_ownership_controls_registry(
        cross_get_bucket_ownership_controls_symbol,
        "cross-operation symbol",
    )
    ownership_qualification, ownership_commands = (
        s3_operation.qualification_plan(
            registry, ["GetBucketOwnershipControls"]
        )
    )
    assert ownership_qualification == "get_bucket_ownership_controls"
    assert ownership_commands[:4] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-get-bucket-ownership-controls-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_get_bucket_ownership_controls_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
    ]
    assert ownership_commands[4] == ["./tools/verify-coverage.sh"]
    assert ownership_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-get-bucket-ownership-controls-gnatdoc",
        "--operation",
        "GetBucketOwnershipControls",
    ]
    assert ownership_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry,
            ["GetBucketOwnershipControls", "GetBucketOwnershipControls"],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate GetBucketOwnershipControls lane accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            ["GetBucketOwnershipControls", "PutBucketOwnershipControls"],
        )
    except s3_operation.Audit_Error as error:
        assert (
            "do not share one qualification lane" in str(error)
            or "has no focused qualification lane" in str(error)
        )
    else:
        raise AssertionError("mixed OwnershipControls lane accepted")
    put_bucket_ownership_controls_certainty = (
        "only a complete validated exact 200 Bucket_Control_Updated response "
        "observed reports Bucket_Ownership_Controls_Mutation_Completed; a "
        "response-observed exact recognized authentication, authorization, "
        "not-found, invalid-request, checksum, malformed-XML, or "
        "NotImplemented rejection or definite non-admission reports "
        "Bucket_Ownership_Controls_Mutation_Definitely_Not_Applied; "
        "pre-admission cancellation reports "
        "Bucket_Ownership_Controls_Mutation_Cancelled_Before_Admission; every "
        "other possibly admitted, incomplete, retryable, or corrupt outcome "
        "reports Bucket_Ownership_Controls_Mutation_Outcome_Unknown; no "
        "automatic replay"
    )
    put_bucket_ownership_controls_reconciliation = (
        "a later GetBucketOwnershipControls may observe the bucket "
        "ownership-controls configuration current at read time before a "
        "caller-selected retry, but it neither proves that the lost mutation "
        "caused the observed state nor upgrades mutation certainty; no "
        "automatic replay"
    )
    put_bucket_ownership_controls_symbols = [
        "Prepare_Put_Bucket_Ownership_Controls",
        "Execute_Put_Bucket_Ownership_Controls",
        "Put_Bucket_Ownership_Controls_Operation",
        "Set_Ownership_Controls",
        "Finish",
    ]

    def assert_put_bucket_ownership_controls_registry(candidate):
        entry = candidate.operations["PutBucketOwnershipControls"]
        assert entry.get("public_name") == "Set_Ownership_Controls"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == (
            "put_bucket_ownership_controls"
        )
        assert entry.get("certainty") == (
            put_bucket_ownership_controls_certainty
        )
        assert entry.get("reconciliation") == (
            put_bucket_ownership_controls_reconciliation
        )
        assert entry.get("ada_symbols") == (
            put_bucket_ownership_controls_symbols
        )
        assert_bucket_control_backend_server(entry)
        assert entry.get("absence") == "not_applicable"
        assert "preserve caller-selected modeled ownership rules" in (
            entry["exclusions"][0]
        )
        assert "exact same immutable" in entry["exclusions"][1]
        assert candidate.qualification[
            "put_bucket_ownership_controls"
        ][0][-1] == "tools/verify-put-bucket-ownership-controls-preparation.py"

    def reject_put_bucket_ownership_controls_registry(candidate, label):
        try:
            assert_put_bucket_ownership_controls_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} PutBucketOwnershipControls registry accepted"
        )

    assert_put_bucket_ownership_controls_registry(registry)
    missing_put_bucket_ownership_controls_name = copy.deepcopy(registry)
    del missing_put_bucket_ownership_controls_name.operations[
        "PutBucketOwnershipControls"
    ]["public_name"]
    reject_put_bucket_ownership_controls_registry(
        missing_put_bucket_ownership_controls_name, "missing name"
    )
    wrong_put_bucket_ownership_controls_name = copy.deepcopy(registry)
    wrong_put_bucket_ownership_controls_name.operations[
        "PutBucketOwnershipControls"
    ]["public_name"] = "Get_Ownership_Controls"
    reject_put_bucket_ownership_controls_registry(
        wrong_put_bucket_ownership_controls_name, "wrong name"
    )
    replay_put_bucket_ownership_controls = copy.deepcopy(registry)
    replay_put_bucket_ownership_controls.operations[
        "PutBucketOwnershipControls"
    ]["certainty"] = "automatically replay PutBucketOwnershipControls"
    reject_put_bucket_ownership_controls_registry(
        replay_put_bucket_ownership_controls, "automatic replay"
    )
    causal_put_bucket_ownership_controls = copy.deepcopy(registry)
    causal_put_bucket_ownership_controls.operations[
        "PutBucketOwnershipControls"
    ]["reconciliation"] = "the read proves the mutation caused state"
    reject_put_bucket_ownership_controls_registry(
        causal_put_bucket_ownership_controls, "causal reconciliation"
    )
    missing_server_put_bucket_ownership_controls = copy.deepcopy(registry)
    missing_server_put_bucket_ownership_controls.operations[
        "PutBucketOwnershipControls"
    ]["coverage"]["server"] = "missing"
    reject_put_bucket_ownership_controls_registry(
        missing_server_put_bucket_ownership_controls,
        "missing server coverage",
    )
    cross_put_bucket_ownership_controls_symbol = copy.deepcopy(registry)
    cross_put_bucket_ownership_controls_symbol.operations[
        "PutBucketOwnershipControls"
    ]["ada_symbols"][0] = "Prepare_Get_Bucket_Ownership_Controls"
    reject_put_bucket_ownership_controls_registry(
        cross_put_bucket_ownership_controls_symbol,
        "cross-operation symbol",
    )
    put_ownership_qualification, put_ownership_commands = (
        s3_operation.qualification_plan(
            registry, ["PutBucketOwnershipControls"]
        )
    )
    assert put_ownership_qualification == "put_bucket_ownership_controls"
    assert put_ownership_commands[:4] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-put-bucket-ownership-controls-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_put_bucket_ownership_controls_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
    ]
    assert put_ownership_commands[4] == ["./tools/verify-coverage.sh"]
    assert put_ownership_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-put-bucket-ownership-controls-gnatdoc",
        "--operation",
        "PutBucketOwnershipControls",
    ]
    assert put_ownership_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry,
            ["PutBucketOwnershipControls", "PutBucketOwnershipControls"],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate PutBucketOwnershipControls lane accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            ["PutBucketOwnershipControls", "GetBucketOwnershipControls"],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed PutBucketOwnershipControls lane accepted")
    get_bucket_lifecycle_configuration_certainty = (
        "read-only; only one complete validated exact 200 "
        "Bucket_Control_Found response observed exposes the "
        "presence-preserving lifecycle configuration and transition-minimum "
        "header; every incomplete, invalid, or non-observed response exposes "
        "no configuration state; the client performs no automatic retry"
    )
    get_bucket_lifecycle_configuration_reconciliation = (
        "a later GetBucketLifecycleConfiguration observes only the bucket "
        "lifecycle configuration current at read time; it does not prove "
        "that a prior mutation caused the observed state or authorize "
        "automatic replay"
    )
    get_bucket_lifecycle_configuration_symbols = [
        "Prepare_Get_Bucket_Lifecycle_Configuration",
        "Decode_Get_Bucket_Lifecycle_Configuration_Response",
        "Execute_Get_Bucket_Lifecycle_Configuration",
        "Get_Bucket_Lifecycle_Operation",
        "Get_Lifecycle_Configuration",
        "Finish",
    ]

    def assert_get_bucket_lifecycle_configuration_registry(candidate):
        entry = candidate.operations["GetBucketLifecycleConfiguration"]
        assert entry.get("public_name") == "Get_Lifecycle_Configuration"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == (
            "get_bucket_lifecycle_configuration"
        )
        assert entry.get("certainty") == (
            get_bucket_lifecycle_configuration_certainty
        )
        assert entry.get("reconciliation") == (
            get_bucket_lifecycle_configuration_reconciliation
        )
        assert entry.get("ada_symbols") == (
            get_bucket_lifecycle_configuration_symbols
        )
        assert_bucket_control_backend_server(entry)
        assert "NoSuchLifecycleConfiguration" in entry["absence"]
        assert "lifecycle action execution" in entry["exclusions"][0]
        assert "without inventing a public numeric" in entry["exclusions"][1]
        assert candidate.qualification[
            "get_bucket_lifecycle_configuration"
        ][0][-1] == (
            "tools/verify-get-bucket-lifecycle-configuration-preparation.py"
        )

    def reject_get_bucket_lifecycle_configuration_registry(candidate, label):
        try:
            assert_get_bucket_lifecycle_configuration_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} GetBucketLifecycleConfiguration registry accepted"
        )

    assert_get_bucket_lifecycle_configuration_registry(registry)
    missing_get_bucket_lifecycle_configuration_name = copy.deepcopy(registry)
    del missing_get_bucket_lifecycle_configuration_name.operations[
        "GetBucketLifecycleConfiguration"
    ]["public_name"]
    reject_get_bucket_lifecycle_configuration_registry(
        missing_get_bucket_lifecycle_configuration_name, "missing name"
    )
    wrong_get_bucket_lifecycle_configuration_name = copy.deepcopy(registry)
    wrong_get_bucket_lifecycle_configuration_name.operations[
        "GetBucketLifecycleConfiguration"
    ]["public_name"] = "Get_Lifecycle"
    reject_get_bucket_lifecycle_configuration_registry(
        wrong_get_bucket_lifecycle_configuration_name, "deprecated name"
    )
    retry_get_bucket_lifecycle_configuration = copy.deepcopy(registry)
    retry_get_bucket_lifecycle_configuration.operations[
        "GetBucketLifecycleConfiguration"
    ]["certainty"] = "read-only; retry automatically"
    reject_get_bucket_lifecycle_configuration_registry(
        retry_get_bucket_lifecycle_configuration, "automatic retry"
    )
    causal_get_bucket_lifecycle_configuration = copy.deepcopy(registry)
    causal_get_bucket_lifecycle_configuration.operations[
        "GetBucketLifecycleConfiguration"
    ]["reconciliation"] = "the read proves the prior mutation caused state"
    reject_get_bucket_lifecycle_configuration_registry(
        causal_get_bucket_lifecycle_configuration, "causal reconciliation"
    )
    bounded_get_bucket_lifecycle_configuration = copy.deepcopy(registry)
    bounded_get_bucket_lifecycle_configuration.operations[
        "GetBucketLifecycleConfiguration"
    ]["exclusions"][1] = "lifecycle numbers are limited to 32 bits"
    reject_get_bucket_lifecycle_configuration_registry(
        bounded_get_bucket_lifecycle_configuration, "invented numeric bound"
    )
    cross_get_bucket_lifecycle_configuration_symbol = copy.deepcopy(registry)
    cross_get_bucket_lifecycle_configuration_symbol.operations[
        "GetBucketLifecycleConfiguration"
    ]["ada_symbols"][0] = "Prepare_Get_Bucket_Lifecycle"
    reject_get_bucket_lifecycle_configuration_registry(
        cross_get_bucket_lifecycle_configuration_symbol,
        "deprecated-operation symbol",
    )
    lifecycle_qualification, lifecycle_commands = (
        s3_operation.qualification_plan(
            registry, ["GetBucketLifecycleConfiguration"]
        )
    )
    assert lifecycle_qualification == "get_bucket_lifecycle_configuration"
    assert lifecycle_commands[:4] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-get-bucket-lifecycle-configuration-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_get_bucket_lifecycle_configuration_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
    ]
    assert lifecycle_commands[4] == ["./tools/verify-coverage.sh"]
    assert lifecycle_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-get-bucket-lifecycle-configuration-gnatdoc",
        "--operation",
        "GetBucketLifecycleConfiguration",
    ]
    assert lifecycle_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "GetBucketLifecycleConfiguration",
                "GetBucketLifecycleConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate GetBucketLifecycleConfiguration lane accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            ["GetBucketLifecycleConfiguration", "PutBucketLifecycleConfiguration"],
        )
    except s3_operation.Audit_Error as error:
        assert (
            "do not share one qualification lane" in str(error)
            or "has no focused qualification lane" in str(error)
        )
    else:
        raise AssertionError("mixed LifecycleConfiguration lane accepted")
    get_bucket_lifecycle_symbols = [
        "Prepare_Get_Bucket_Lifecycle_Configuration",
        "Decode_Get_Bucket_Lifecycle_Configuration_Response",
        "Execute_Get_Bucket_Lifecycle_Configuration",
        "Get_Bucket_Lifecycle_Operation",
        "Get_Lifecycle_Configuration",
        "Finish",
    ]

    def assert_get_bucket_lifecycle_registry(candidate):
        entry = candidate.operations["GetBucketLifecycle"]
        assert entry.get("public_name") == "Get_Lifecycle_Configuration"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "get_bucket_lifecycle"
        assert entry.get("codec") == (
            "strict_rest_xml_request_and_bounded_response"
        )
        assert entry.get("ada_symbols") == get_bucket_lifecycle_symbols
        assert entry["coverage"] == {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        }
        assert_bucket_control_backend_server(entry)
        assert entry["provenance"]["client"] == "handwritten"
        assert entry["provenance"]["tests"] == "handwritten"
        assert "structural subset" in entry["exclusions"][1]
        assert "does not prove" in entry["reconciliation"]
        commands = candidate.qualification["get_bucket_lifecycle"]
        assert commands[0][-1] == (
            "tools/verify-get-bucket-lifecycle-configuration-preparation.py"
        )
        assert commands[5][-2:] == ["--operation", "GetBucketLifecycle"]

    def reject_get_bucket_lifecycle_registry(candidate, label):
        try:
            assert_get_bucket_lifecycle_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(f"{label} GetBucketLifecycle registry accepted")

    assert_get_bucket_lifecycle_registry(registry)
    missing_get_bucket_lifecycle_name = copy.deepcopy(registry)
    del missing_get_bucket_lifecycle_name.operations["GetBucketLifecycle"][
        "public_name"
    ]
    reject_get_bucket_lifecycle_registry(
        missing_get_bucket_lifecycle_name, "missing compatibility name"
    )
    wrong_get_bucket_lifecycle_name = copy.deepcopy(registry)
    wrong_get_bucket_lifecycle_name.operations["GetBucketLifecycle"][
        "public_name"
    ] = "Get_Lifecycle"
    reject_get_bucket_lifecycle_registry(
        wrong_get_bucket_lifecycle_name, "obsolete public name"
    )
    unresolved_get_bucket_lifecycle = copy.deepcopy(registry)
    unresolved_get_bucket_lifecycle.operations["GetBucketLifecycle"][
        "human_decisions_resolved"
    ] = False
    reject_get_bucket_lifecycle_registry(
        unresolved_get_bucket_lifecycle, "unresolved alias"
    )
    cross_get_bucket_lifecycle_symbol = copy.deepcopy(registry)
    cross_get_bucket_lifecycle_symbol.operations["GetBucketLifecycle"][
        "ada_symbols"
    ][0] = "Prepare_Get_Bucket_Lifecycle"
    reject_get_bucket_lifecycle_registry(
        cross_get_bucket_lifecycle_symbol, "obsolete symbol"
    )
    causal_get_bucket_lifecycle = copy.deepcopy(registry)
    causal_get_bucket_lifecycle.operations["GetBucketLifecycle"][
        "reconciliation"
    ] = "the read proves the prior mutation caused state"
    reject_get_bucket_lifecycle_registry(
        causal_get_bucket_lifecycle, "causal observation"
    )
    malformed_get_bucket_lifecycle_lane = copy.deepcopy(registry)
    malformed_get_bucket_lifecycle_lane.qualification[
        "get_bucket_lifecycle"
    ][5][-1] = "GetBucketLifecycleConfiguration"
    reject_get_bucket_lifecycle_registry(
        malformed_get_bucket_lifecycle_lane, "cross-operation lane"
    )
    legacy_lifecycle_qualification, legacy_lifecycle_commands = (
        s3_operation.qualification_plan(registry, ["GetBucketLifecycle"])
    )
    assert legacy_lifecycle_qualification == "get_bucket_lifecycle"
    assert legacy_lifecycle_commands[0][-1] == (
        "tools/verify-get-bucket-lifecycle-configuration-preparation.py"
    )
    assert legacy_lifecycle_commands[2] == [
        "@tests", "./bin/s3_get_bucket_lifecycle_configuration_corpus"
    ]
    assert legacy_lifecycle_commands[5][-2:] == [
        "--operation", "GetBucketLifecycle"
    ]
    try:
        s3_operation.qualification_plan(
            registry,
            ["GetBucketLifecycle", "GetBucketLifecycleConfiguration"],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed legacy lifecycle lane accepted")
    put_bucket_lifecycle_configuration_certainty = (
        "only a complete validated exact 200 Bucket_Control_Updated response "
        "observed reports Bucket_Lifecycle_Mutation_Completed; a "
        "response-observed exact recognized authentication, authorization, "
        "not-found, invalid-request, checksum, malformed-XML, or "
        "NotImplemented rejection or definite non-admission reports "
        "Bucket_Lifecycle_Mutation_Definitely_Not_Applied; pre-admission "
        "cancellation reports "
        "Bucket_Lifecycle_Mutation_Cancelled_Before_Admission; every other "
        "possibly admitted, incomplete, retryable, or corrupt outcome "
        "reports Bucket_Lifecycle_Mutation_Outcome_Unknown; no automatic "
        "replay"
    )
    put_bucket_lifecycle_configuration_reconciliation = (
        "a later GetBucketLifecycleConfiguration may observe the bucket "
        "lifecycle configuration current at read time before a "
        "caller-selected retry, but it neither proves that the lost mutation "
        "caused the observed state nor upgrades mutation certainty; no "
        "automatic replay"
    )
    put_bucket_lifecycle_configuration_symbols = [
        "Prepare_Put_Bucket_Lifecycle_Configuration",
        "Decode_Put_Bucket_Lifecycle_Configuration_Response",
        "Execute_Put_Bucket_Lifecycle_Configuration",
        "Put_Bucket_Lifecycle_Operation",
        "Set_Lifecycle_Configuration",
        "Finish",
    ]

    def assert_put_bucket_lifecycle_configuration_registry(candidate):
        entry = candidate.operations["PutBucketLifecycleConfiguration"]
        assert entry.get("public_name") == "Set_Lifecycle_Configuration"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == (
            "put_bucket_lifecycle_configuration"
        )
        assert entry.get("codec") == (
            "strict_rest_xml_request_checksum_and_singleton_headers"
        )
        assert entry.get("certainty") == (
            put_bucket_lifecycle_configuration_certainty
        )
        assert entry.get("reconciliation") == (
            put_bucket_lifecycle_configuration_reconciliation
        )
        assert entry.get("ada_symbols") == (
            put_bucket_lifecycle_configuration_symbols
        )
        assert_bucket_control_backend_server(entry)
        assert entry.get("absence") == "not_applicable"
        assert "1,000-rule ceiling" in entry["exclusions"][1]
        assert "ten modeled checksum algorithms" in entry["exclusions"][2]
        assert candidate.qualification[
            "put_bucket_lifecycle_configuration"
        ][0][-1] == (
            "tools/verify-put-bucket-lifecycle-configuration-preparation.py"
        )

    def reject_put_bucket_lifecycle_configuration_registry(candidate, label):
        try:
            assert_put_bucket_lifecycle_configuration_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} PutBucketLifecycleConfiguration registry accepted"
        )

    assert_put_bucket_lifecycle_configuration_registry(registry)
    missing_put_bucket_lifecycle_configuration_name = copy.deepcopy(registry)
    del missing_put_bucket_lifecycle_configuration_name.operations[
        "PutBucketLifecycleConfiguration"
    ]["public_name"]
    reject_put_bucket_lifecycle_configuration_registry(
        missing_put_bucket_lifecycle_configuration_name, "missing name"
    )
    wrong_put_bucket_lifecycle_configuration_name = copy.deepcopy(registry)
    wrong_put_bucket_lifecycle_configuration_name.operations[
        "PutBucketLifecycleConfiguration"
    ]["public_name"] = "Get_Lifecycle_Configuration"
    reject_put_bucket_lifecycle_configuration_registry(
        wrong_put_bucket_lifecycle_configuration_name, "wrong name"
    )
    replay_put_bucket_lifecycle_configuration = copy.deepcopy(registry)
    replay_put_bucket_lifecycle_configuration.operations[
        "PutBucketLifecycleConfiguration"
    ]["certainty"] = "automatically replay PutBucketLifecycleConfiguration"
    reject_put_bucket_lifecycle_configuration_registry(
        replay_put_bucket_lifecycle_configuration, "automatic replay"
    )
    causal_put_bucket_lifecycle_configuration = copy.deepcopy(registry)
    causal_put_bucket_lifecycle_configuration.operations[
        "PutBucketLifecycleConfiguration"
    ]["reconciliation"] = "the read proves the mutation caused state"
    reject_put_bucket_lifecycle_configuration_registry(
        causal_put_bucket_lifecycle_configuration, "causal reconciliation"
    )
    checksum_put_bucket_lifecycle_configuration = copy.deepcopy(registry)
    checksum_put_bucket_lifecycle_configuration.operations[
        "PutBucketLifecycleConfiguration"
    ]["codec"] = "rest_xml_and_headers"
    reject_put_bucket_lifecycle_configuration_registry(
        checksum_put_bucket_lifecycle_configuration, "missing checksum"
    )
    bounded_put_bucket_lifecycle_configuration = copy.deepcopy(registry)
    bounded_put_bucket_lifecycle_configuration.operations[
        "PutBucketLifecycleConfiguration"
    ]["exclusions"][1] = "lifecycle rules are limited to 1,000"
    reject_put_bucket_lifecycle_configuration_registry(
        bounded_put_bucket_lifecycle_configuration, "invented policy bound"
    )
    cross_put_bucket_lifecycle_configuration_symbol = copy.deepcopy(registry)
    cross_put_bucket_lifecycle_configuration_symbol.operations[
        "PutBucketLifecycleConfiguration"
    ]["ada_symbols"][0] = "Prepare_Get_Bucket_Lifecycle_Configuration"
    reject_put_bucket_lifecycle_configuration_registry(
        cross_put_bucket_lifecycle_configuration_symbol,
        "cross-operation symbol",
    )
    put_lifecycle_qualification, put_lifecycle_commands = (
        s3_operation.qualification_plan(
            registry, ["PutBucketLifecycleConfiguration"]
        )
    )
    assert put_lifecycle_qualification == "put_bucket_lifecycle_configuration"
    assert put_lifecycle_commands[:4] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-put-bucket-lifecycle-configuration-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_put_bucket_lifecycle_configuration_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
    ]
    assert put_lifecycle_commands[4] == ["./tools/verify-coverage.sh"]
    assert put_lifecycle_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-put-bucket-lifecycle-configuration-gnatdoc",
        "--operation",
        "PutBucketLifecycleConfiguration",
    ]
    assert put_lifecycle_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "PutBucketLifecycleConfiguration",
                "PutBucketLifecycleConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate PutBucketLifecycleConfiguration lane accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "PutBucketLifecycleConfiguration",
                "GetBucketLifecycleConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError(
            "mixed PutBucketLifecycleConfiguration lane accepted"
        )
    put_bucket_lifecycle_certainty = (
        "mutation compatibility subset; "
        + put_bucket_lifecycle_configuration_certainty
    )
    put_bucket_lifecycle_reconciliation = (
        "a later GetBucketLifecycle or GetBucketLifecycleConfiguration may "
        "observe the bucket lifecycle configuration current at read time "
        "before a caller-selected retry, but it neither proves that the lost "
        "mutation caused the observed state nor upgrades mutation certainty; "
        "no automatic replay"
    )
    put_bucket_lifecycle_symbols = [
        "Prepare_Put_Bucket_Lifecycle_Configuration",
        "Decode_Put_Bucket_Lifecycle_Configuration_Response",
        "Execute_Put_Bucket_Lifecycle_Configuration",
        "Put_Bucket_Lifecycle_Operation",
        "Set_Lifecycle_Configuration",
        "Finish",
    ]

    def assert_put_bucket_lifecycle_registry(candidate):
        entry = candidate.operations["PutBucketLifecycle"]
        assert entry.get("public_name") == "Set_Lifecycle_Configuration"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "put_bucket_lifecycle"
        assert entry.get("codec") == (
            "strict_current_rest_xml_mutation_compatibility_subset"
        )
        assert entry.get("certainty") == put_bucket_lifecycle_certainty
        assert entry.get("reconciliation") == (
            put_bucket_lifecycle_reconciliation
        )
        assert entry.get("ada_symbols") == put_bucket_lifecycle_symbols
        assert entry["coverage"]["backend"] == "missing"
        assert entry["coverage"]["server"] == "missing"
        assert entry["coverage"]["client"] == "partial"
        assert entry["coverage"]["corpus"] == "covered"
        assert entry["provenance"]["client"] == "handwritten"
        assert entry["provenance"]["tests"] == "handwritten"
        assert entry.get("absence") == "not_applicable"
        assert "client coverage is deliberately partial" in (
            entry["exclusions"][1]
        )
        assert "current operation identity" in entry["exclusions"][1]
        assert "does not reject modern Filter-only rules" in (
            entry["exclusions"][1]
        )
        assert "optional legacy ContentMD5 override is not surfaced" in (
            entry["exclusions"][2]
        )
        assert "caller-selected generated checksum" in entry["exclusions"][2]
        assert "exact immutable serialized body" in entry["exclusions"][2]
        assert candidate.qualification["put_bucket_lifecycle"][0][-1] == (
            "tools/verify-put-bucket-lifecycle-configuration-preparation.py"
        )

    def reject_put_bucket_lifecycle_registry(candidate, label):
        try:
            assert_put_bucket_lifecycle_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} PutBucketLifecycle registry accepted"
        )

    assert_put_bucket_lifecycle_registry(registry)
    missing_put_bucket_lifecycle_name = copy.deepcopy(registry)
    del missing_put_bucket_lifecycle_name.operations[
        "PutBucketLifecycle"
    ]["public_name"]
    reject_put_bucket_lifecycle_registry(
        missing_put_bucket_lifecycle_name, "missing name"
    )
    wrong_put_bucket_lifecycle_name = copy.deepcopy(registry)
    wrong_put_bucket_lifecycle_name.operations[
        "PutBucketLifecycle"
    ]["public_name"] = "Put_Bucket_Lifecycle"
    reject_put_bucket_lifecycle_registry(
        wrong_put_bucket_lifecycle_name, "wrong name"
    )
    replay_put_bucket_lifecycle = copy.deepcopy(registry)
    replay_put_bucket_lifecycle.operations[
        "PutBucketLifecycle"
    ]["certainty"] = "automatically replay PutBucketLifecycle"
    reject_put_bucket_lifecycle_registry(
        replay_put_bucket_lifecycle, "automatic replay"
    )
    causal_put_bucket_lifecycle = copy.deepcopy(registry)
    causal_put_bucket_lifecycle.operations[
        "PutBucketLifecycle"
    ]["reconciliation"] = "the later read proves the mutation caused state"
    reject_put_bucket_lifecycle_registry(
        causal_put_bucket_lifecycle, "causal reconciliation"
    )
    broad_put_bucket_lifecycle = copy.deepcopy(registry)
    broad_put_bucket_lifecycle.operations[
        "PutBucketLifecycle"
    ]["exclusions"][1] = "all lifecycle payloads are compatible"
    reject_put_bucket_lifecycle_registry(
        broad_put_bucket_lifecycle, "hidden structural subset"
    )
    covered_put_bucket_lifecycle = copy.deepcopy(registry)
    covered_put_bucket_lifecycle.operations[
        "PutBucketLifecycle"
    ]["coverage"]["client"] = "covered"
    reject_put_bucket_lifecycle_registry(
        covered_put_bucket_lifecycle, "full client coverage"
    )
    checksum_put_bucket_lifecycle = copy.deepcopy(registry)
    checksum_put_bucket_lifecycle.operations[
        "PutBucketLifecycle"
    ]["exclusions"][2] = "the body is signed"
    reject_put_bucket_lifecycle_registry(
        checksum_put_bucket_lifecycle, "missing checksum binding"
    )
    cross_put_bucket_lifecycle_symbol = copy.deepcopy(registry)
    cross_put_bucket_lifecycle_symbol.operations[
        "PutBucketLifecycle"
    ]["ada_symbols"][0] = "Prepare_Put_Bucket_Notification_Configuration"
    reject_put_bucket_lifecycle_registry(
        cross_put_bucket_lifecycle_symbol, "cross-operation symbol"
    )
    legacy_put_lifecycle_qualification, legacy_put_lifecycle_commands = (
        s3_operation.qualification_plan(registry, ["PutBucketLifecycle"])
    )
    assert legacy_put_lifecycle_qualification == "put_bucket_lifecycle"
    assert legacy_put_lifecycle_commands[:4] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-put-bucket-lifecycle-configuration-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_put_bucket_lifecycle_configuration_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
    ]
    assert legacy_put_lifecycle_commands[4] == [
        "./tools/verify-coverage.sh"
    ]
    assert legacy_put_lifecycle_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-put-bucket-lifecycle-gnatdoc",
        "--operation",
        "PutBucketLifecycle",
    ]
    assert legacy_put_lifecycle_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry, ["PutBucketLifecycle", "PutBucketLifecycle"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate PutBucketLifecycle lane accepted")
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "PutBucketLifecycle",
                "PutBucketLifecycleConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed PutBucketLifecycle lane accepted")
    get_bucket_notification_configuration_certainty = (
        "read-only; only one complete validated exact 200 "
        "Bucket_Control_Found response observed exposes the complete current "
        "notification configuration; every incomplete, invalid, or "
        "non-observed response exposes no configuration state; the client "
        "performs no automatic retry"
    )
    get_bucket_notification_configuration_reconciliation = (
        "a later GetBucketNotificationConfiguration observes only the bucket "
        "notification configuration current at read time; it does not prove "
        "that a prior mutation caused the observed state or authorize "
        "automatic replay"
    )
    get_bucket_notification_configuration_symbols = [
        "Prepare_Get_Bucket_Notification_Configuration",
        "Decode_Get_Bucket_Notification_Configuration_Response",
        "Execute_Get_Bucket_Notification_Configuration",
        "Get_Bucket_Notification_Operation",
        "Get_Notification_Configuration",
        "Finish",
    ]

    def assert_get_bucket_notification_configuration_registry(candidate):
        entry = candidate.operations["GetBucketNotificationConfiguration"]
        assert entry.get("public_name") == "Get_Notification_Configuration"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == (
            "get_bucket_notification_configuration"
        )
        assert entry.get("certainty") == (
            get_bucket_notification_configuration_certainty
        )
        assert entry.get("reconciliation") == (
            get_bucket_notification_configuration_reconciliation
        )
        assert entry.get("ada_symbols") == (
            get_bucket_notification_configuration_symbols
        )
        assert entry["coverage"]["backend"] == "missing"
        assert entry["coverage"]["server"] == "missing"
        assert entry["provenance"]["backend"] == "absent"
        assert entry["provenance"]["server"] == "absent"
        assert "exact 200 empty notification document" in entry["absence"]
        assert "30-event domains" in entry["exclusions"][1]
        assert candidate.qualification[
            "get_bucket_notification_configuration"
        ][0][-1] == (
            "tools/verify-bucket-notification-configuration-preparation.py"
        )

    def reject_get_bucket_notification_configuration_registry(
        candidate, label
    ):
        try:
            assert_get_bucket_notification_configuration_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} GetBucketNotificationConfiguration registry accepted"
        )

    assert_get_bucket_notification_configuration_registry(registry)
    missing_get_bucket_notification_configuration_name = copy.deepcopy(
        registry
    )
    del missing_get_bucket_notification_configuration_name.operations[
        "GetBucketNotificationConfiguration"
    ]["public_name"]
    reject_get_bucket_notification_configuration_registry(
        missing_get_bucket_notification_configuration_name, "missing name"
    )
    wrong_get_bucket_notification_configuration_name = copy.deepcopy(registry)
    wrong_get_bucket_notification_configuration_name.operations[
        "GetBucketNotificationConfiguration"
    ]["public_name"] = "Get_Notification"
    reject_get_bucket_notification_configuration_registry(
        wrong_get_bucket_notification_configuration_name, "deprecated name"
    )
    retry_get_bucket_notification_configuration = copy.deepcopy(registry)
    retry_get_bucket_notification_configuration.operations[
        "GetBucketNotificationConfiguration"
    ]["certainty"] = "read-only; retry automatically"
    reject_get_bucket_notification_configuration_registry(
        retry_get_bucket_notification_configuration, "automatic retry"
    )
    causal_get_bucket_notification_configuration = copy.deepcopy(registry)
    causal_get_bucket_notification_configuration.operations[
        "GetBucketNotificationConfiguration"
    ]["reconciliation"] = "the read proves the mutation caused state"
    reject_get_bucket_notification_configuration_registry(
        causal_get_bucket_notification_configuration, "causal reconciliation"
    )
    absent_get_bucket_notification_configuration = copy.deepcopy(registry)
    absent_get_bucket_notification_configuration.operations[
        "GetBucketNotificationConfiguration"
    ]["absence"] = "404 NoSuchNotificationConfiguration means absent"
    reject_get_bucket_notification_configuration_registry(
        absent_get_bucket_notification_configuration, "invented absence code"
    )
    cross_get_bucket_notification_configuration_symbol = copy.deepcopy(
        registry
    )
    cross_get_bucket_notification_configuration_symbol.operations[
        "GetBucketNotificationConfiguration"
    ]["ada_symbols"][0] = "Prepare_Get_Bucket_Notification"
    reject_get_bucket_notification_configuration_registry(
        cross_get_bucket_notification_configuration_symbol,
        "deprecated-operation symbol",
    )
    get_notification_qualification, get_notification_commands = (
        s3_operation.qualification_plan(
            registry, ["GetBucketNotificationConfiguration"]
        )
    )
    assert get_notification_qualification == (
        "get_bucket_notification_configuration"
    )
    assert get_notification_commands[:4] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-bucket-notification-configuration-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_bucket_notification_configuration_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
    ]
    assert get_notification_commands[4] == ["./tools/verify-coverage.sh"]
    assert get_notification_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-get-bucket-notification-configuration-gnatdoc",
        "--operation",
        "GetBucketNotificationConfiguration",
    ]
    assert get_notification_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "GetBucketNotificationConfiguration",
                "GetBucketNotificationConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate GetBucketNotificationConfiguration lane accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "GetBucketNotificationConfiguration",
                "PutBucketNotificationConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert (
            "do not share one qualification lane" in str(error)
            or "has no focused qualification lane" in str(error)
        )
    else:
        raise AssertionError(
            "mixed BucketNotificationConfiguration lane accepted"
        )
    get_bucket_notification_symbols = [
        "Prepare_Get_Bucket_Notification_Configuration",
        "Decode_Get_Bucket_Notification_Configuration_Response",
        "Execute_Get_Bucket_Notification_Configuration",
        "Get_Bucket_Notification_Operation",
        "Get_Notification_Configuration",
        "Finish",
    ]

    def assert_get_bucket_notification_registry(candidate):
        entry = candidate.operations["GetBucketNotification"]
        assert entry.get("public_name") == "Get_Notification_Configuration"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "get_bucket_notification"
        assert entry.get("codec") == (
            "strict_current_rest_xml_compatibility_subset"
        )
        assert entry.get("ada_symbols") == get_bucket_notification_symbols
        assert entry["coverage"] == {
            "backend": "missing",
            "client": "partial",
            "server": "missing",
            "corpus": "covered",
        }
        assert entry["provenance"]["client"] == "handwritten"
        assert entry["provenance"]["tests"] == "handwritten"
        assert "deliberately partial" in entry["exclusions"][1]
        assert "InvocationRole" in entry["exclusions"][1]
        assert "legacy-only" in entry["certainty"]
        assert "does not prove" in entry["reconciliation"]
        commands = candidate.qualification["get_bucket_notification"]
        assert commands[0][-1] == (
            "tools/verify-bucket-notification-configuration-preparation.py"
        )
        assert commands[5][-2:] == [
            "--operation", "GetBucketNotification"
        ]

    def reject_get_bucket_notification_registry(candidate, label):
        try:
            assert_get_bucket_notification_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} GetBucketNotification registry accepted"
        )

    assert_get_bucket_notification_registry(registry)
    missing_get_bucket_notification_name = copy.deepcopy(registry)
    del missing_get_bucket_notification_name.operations[
        "GetBucketNotification"
    ]["public_name"]
    reject_get_bucket_notification_registry(
        missing_get_bucket_notification_name, "missing compatibility name"
    )
    full_get_bucket_notification = copy.deepcopy(registry)
    full_get_bucket_notification.operations["GetBucketNotification"][
        "coverage"
    ]["client"] = "covered"
    reject_get_bucket_notification_registry(
        full_get_bucket_notification, "invented complete client coverage"
    )
    hidden_get_bucket_notification_gap = copy.deepcopy(registry)
    hidden_get_bucket_notification_gap.operations[
        "GetBucketNotification"
    ]["exclusions"][1] = "all deprecated output shapes are accepted"
    reject_get_bucket_notification_registry(
        hidden_get_bucket_notification_gap, "hidden legacy gap"
    )
    cross_get_bucket_notification_symbol = copy.deepcopy(registry)
    cross_get_bucket_notification_symbol.operations[
        "GetBucketNotification"
    ]["ada_symbols"][0] = "Prepare_Get_Bucket_Notification"
    reject_get_bucket_notification_registry(
        cross_get_bucket_notification_symbol, "obsolete symbol"
    )
    malformed_get_bucket_notification_lane = copy.deepcopy(registry)
    malformed_get_bucket_notification_lane.qualification[
        "get_bucket_notification"
    ][5][-1] = "GetBucketNotificationConfiguration"
    reject_get_bucket_notification_registry(
        malformed_get_bucket_notification_lane, "cross-operation lane"
    )
    legacy_notification_qualification, legacy_notification_commands = (
        s3_operation.qualification_plan(registry, ["GetBucketNotification"])
    )
    assert legacy_notification_qualification == "get_bucket_notification"
    assert legacy_notification_commands[0][-1] == (
        "tools/verify-bucket-notification-configuration-preparation.py"
    )
    assert legacy_notification_commands[2] == [
        "@tests", "./bin/s3_bucket_notification_configuration_corpus"
    ]
    assert legacy_notification_commands[5][-2:] == [
        "--operation", "GetBucketNotification"
    ]
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "GetBucketNotification",
                "GetBucketNotificationConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed legacy notification lane accepted")
    put_bucket_notification_configuration_certainty = (
        "only a complete validated exact 200 Bucket_Control_Updated response "
        "observed reports Bucket_Notification_Mutation_Completed; a "
        "response-observed exact recognized authentication, authorization, "
        "not-found, invalid-request, malformed-XML, MethodNotAllowed, or "
        "NotImplemented rejection or definite non-admission reports "
        "Bucket_Notification_Mutation_Definitely_Not_Applied; pre-admission "
        "cancellation reports "
        "Bucket_Notification_Mutation_Cancelled_Before_Admission; every "
        "other possibly admitted, incomplete, retryable, or corrupt outcome "
        "reports Bucket_Notification_Mutation_Outcome_Unknown; no automatic "
        "replay"
    )
    put_bucket_notification_configuration_reconciliation = (
        "a later GetBucketNotificationConfiguration may observe the bucket "
        "notification configuration current at read time before a "
        "caller-selected retry, but it neither proves that the lost mutation "
        "caused the observed state nor upgrades mutation certainty; no "
        "automatic replay"
    )
    put_bucket_notification_configuration_symbols = [
        "Prepare_Put_Bucket_Notification_Configuration",
        "Execute_Put_Bucket_Notification_Configuration",
        "Put_Bucket_Notification_Operation",
        "Set_Notification_Configuration",
        "Finish",
    ]

    def assert_put_bucket_notification_configuration_registry(candidate):
        entry = candidate.operations["PutBucketNotificationConfiguration"]
        assert entry.get("public_name") == "Set_Notification_Configuration"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == (
            "put_bucket_notification_configuration"
        )
        assert entry.get("codec") == (
            "strict_rest_xml_request_and_empty_response"
        )
        assert entry.get("certainty") == (
            put_bucket_notification_configuration_certainty
        )
        assert entry.get("reconciliation") == (
            put_bucket_notification_configuration_reconciliation
        )
        assert entry.get("ada_symbols") == (
            put_bucket_notification_configuration_symbols
        )
        assert entry["coverage"]["backend"] == "missing"
        assert entry["coverage"]["server"] == "missing"
        assert entry["provenance"]["backend"] == "absent"
        assert entry["provenance"]["server"] == "absent"
        assert entry.get("absence") == "not_applicable"
        assert "30-event domains" in entry["exclusions"][1]
        assert "no SDK checksum or Content-MD5" in entry["exclusions"][2]
        assert candidate.qualification[
            "put_bucket_notification_configuration"
        ][0][-1] == (
            "tools/verify-bucket-notification-configuration-preparation.py"
        )

    def reject_put_bucket_notification_configuration_registry(
        candidate, label
    ):
        try:
            assert_put_bucket_notification_configuration_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} PutBucketNotificationConfiguration registry accepted"
        )

    assert_put_bucket_notification_configuration_registry(registry)
    missing_put_bucket_notification_configuration_name = copy.deepcopy(
        registry
    )
    del missing_put_bucket_notification_configuration_name.operations[
        "PutBucketNotificationConfiguration"
    ]["public_name"]
    reject_put_bucket_notification_configuration_registry(
        missing_put_bucket_notification_configuration_name, "missing name"
    )
    wrong_put_bucket_notification_configuration_name = copy.deepcopy(registry)
    wrong_put_bucket_notification_configuration_name.operations[
        "PutBucketNotificationConfiguration"
    ]["public_name"] = "Get_Notification_Configuration"
    reject_put_bucket_notification_configuration_registry(
        wrong_put_bucket_notification_configuration_name, "wrong name"
    )
    replay_put_bucket_notification_configuration = copy.deepcopy(registry)
    replay_put_bucket_notification_configuration.operations[
        "PutBucketNotificationConfiguration"
    ]["certainty"] = "automatically replay PutBucketNotificationConfiguration"
    reject_put_bucket_notification_configuration_registry(
        replay_put_bucket_notification_configuration, "automatic replay"
    )
    causal_put_bucket_notification_configuration = copy.deepcopy(registry)
    causal_put_bucket_notification_configuration.operations[
        "PutBucketNotificationConfiguration"
    ]["reconciliation"] = "the read proves the mutation caused state"
    reject_put_bucket_notification_configuration_registry(
        causal_put_bucket_notification_configuration, "causal reconciliation"
    )
    checksum_put_bucket_notification_configuration = copy.deepcopy(registry)
    checksum_put_bucket_notification_configuration.operations[
        "PutBucketNotificationConfiguration"
    ]["exclusions"][2] = "the client adds Content-MD5"
    reject_put_bucket_notification_configuration_registry(
        checksum_put_bucket_notification_configuration, "invented checksum"
    )
    cross_put_bucket_notification_configuration_symbol = copy.deepcopy(
        registry
    )
    cross_put_bucket_notification_configuration_symbol.operations[
        "PutBucketNotificationConfiguration"
    ]["ada_symbols"][0] = "Prepare_Put_Bucket_Notification"
    reject_put_bucket_notification_configuration_registry(
        cross_put_bucket_notification_configuration_symbol,
        "deprecated-operation symbol",
    )
    put_notification_qualification, put_notification_commands = (
        s3_operation.qualification_plan(
            registry, ["PutBucketNotificationConfiguration"]
        )
    )
    assert put_notification_qualification == (
        "put_bucket_notification_configuration"
    )
    assert put_notification_commands[:4] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-bucket-notification-configuration-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_bucket_notification_configuration_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
    ]
    assert put_notification_commands[4] == ["./tools/verify-coverage.sh"]
    assert put_notification_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-put-bucket-notification-configuration-gnatdoc",
        "--operation",
        "PutBucketNotificationConfiguration",
    ]
    assert put_notification_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "PutBucketNotificationConfiguration",
                "PutBucketNotificationConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate PutBucketNotificationConfiguration lane accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "PutBucketNotificationConfiguration",
                "GetBucketNotificationConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError(
            "mixed PutBucketNotificationConfiguration lane accepted"
        )
    put_bucket_notification_certainty = (
        "mutation compatibility subset; "
        + put_bucket_notification_configuration_certainty
    )
    put_bucket_notification_reconciliation = (
        "a later GetBucketNotification or "
        "GetBucketNotificationConfiguration may observe the bucket "
        "notification configuration current at read time before a "
        "caller-selected retry, but it neither proves that the lost mutation "
        "caused the observed state nor upgrades mutation certainty; no "
        "automatic replay"
    )
    put_bucket_notification_symbols = [
        "Prepare_Put_Bucket_Notification_Configuration",
        "Execute_Put_Bucket_Notification_Configuration",
        "Put_Bucket_Notification_Operation",
        "Set_Notification_Configuration",
        "Finish",
    ]

    def assert_put_bucket_notification_registry(candidate):
        entry = candidate.operations["PutBucketNotification"]
        assert entry.get("public_name") == "Set_Notification_Configuration"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "put_bucket_notification"
        assert entry.get("codec") == (
            "strict_current_rest_xml_mutation_compatibility_subset"
        )
        assert entry.get("certainty") == put_bucket_notification_certainty
        assert entry.get("reconciliation") == (
            put_bucket_notification_reconciliation
        )
        assert entry.get("ada_symbols") == put_bucket_notification_symbols
        assert entry["coverage"] == {
            "backend": "missing",
            "client": "partial",
            "server": "missing",
            "corpus": "covered",
        }
        assert entry["provenance"]["client"] == "handwritten"
        assert entry["provenance"]["tests"] == "handwritten"
        assert "client coverage is deliberately partial" in (
            entry["exclusions"][1]
        )
        assert "InvocationRole" in entry["exclusions"][1]
        assert "modern filters" in entry["exclusions"][1]
        assert "legacy operation requires checksum transport" in (
            entry["exclusions"][2]
        )
        assert "maintained current operation sends neither" in (
            entry["exclusions"][2]
        )
        commands = candidate.qualification["put_bucket_notification"]
        assert commands[0][-1] == (
            "tools/verify-bucket-notification-configuration-preparation.py"
        )

    def reject_put_bucket_notification_registry(candidate, label):
        try:
            assert_put_bucket_notification_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} PutBucketNotification registry accepted"
        )

    assert_put_bucket_notification_registry(registry)
    missing_put_bucket_notification_name = copy.deepcopy(registry)
    del missing_put_bucket_notification_name.operations[
        "PutBucketNotification"
    ]["public_name"]
    reject_put_bucket_notification_registry(
        missing_put_bucket_notification_name, "missing compatibility name"
    )
    full_put_bucket_notification = copy.deepcopy(registry)
    full_put_bucket_notification.operations[
        "PutBucketNotification"
    ]["coverage"]["client"] = "covered"
    reject_put_bucket_notification_registry(
        full_put_bucket_notification, "invented complete client coverage"
    )
    hidden_put_bucket_notification_gap = copy.deepcopy(registry)
    hidden_put_bucket_notification_gap.operations[
        "PutBucketNotification"
    ]["exclusions"][1] = "all deprecated notification shapes are accepted"
    reject_put_bucket_notification_registry(
        hidden_put_bucket_notification_gap, "hidden legacy shape gap"
    )
    checksum_put_bucket_notification = copy.deepcopy(registry)
    checksum_put_bucket_notification.operations[
        "PutBucketNotification"
    ]["exclusions"][2] = "the current client sends the legacy checksums"
    reject_put_bucket_notification_registry(
        checksum_put_bucket_notification, "invented checksum transport"
    )
    replay_put_bucket_notification = copy.deepcopy(registry)
    replay_put_bucket_notification.operations[
        "PutBucketNotification"
    ]["certainty"] = "automatically replay PutBucketNotification"
    reject_put_bucket_notification_registry(
        replay_put_bucket_notification, "automatic replay"
    )
    causal_put_bucket_notification = copy.deepcopy(registry)
    causal_put_bucket_notification.operations[
        "PutBucketNotification"
    ]["reconciliation"] = "the later read proves the mutation caused state"
    reject_put_bucket_notification_registry(
        causal_put_bucket_notification, "causal reconciliation"
    )
    cross_put_bucket_notification_symbol = copy.deepcopy(registry)
    cross_put_bucket_notification_symbol.operations[
        "PutBucketNotification"
    ]["ada_symbols"][0] = "Prepare_Get_Bucket_Notification_Configuration"
    reject_put_bucket_notification_registry(
        cross_put_bucket_notification_symbol, "cross-operation symbol"
    )
    malformed_put_bucket_notification_lane = copy.deepcopy(registry)
    malformed_put_bucket_notification_lane.qualification[
        "put_bucket_notification"
    ][0][-1] = "tools/verify-put-bucket-lifecycle-configuration-preparation.py"
    reject_put_bucket_notification_registry(
        malformed_put_bucket_notification_lane, "cross-operation lane"
    )
    legacy_put_notification_qualification, legacy_put_notification_commands = (
        s3_operation.qualification_plan(registry, ["PutBucketNotification"])
    )
    assert legacy_put_notification_qualification == "put_bucket_notification"
    assert legacy_put_notification_commands[:4] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-bucket-notification-configuration-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_bucket_notification_configuration_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
    ]
    assert legacy_put_notification_commands[4] == [
        "./tools/verify-coverage.sh"
    ]
    assert legacy_put_notification_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-put-bucket-notification-gnatdoc",
        "--operation",
        "PutBucketNotification",
    ]
    assert legacy_put_notification_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry, ["PutBucketNotification", "PutBucketNotification"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate PutBucketNotification lane accepted")
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "PutBucketNotification",
                "PutBucketNotificationConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed PutBucketNotification lane accepted")
    get_object_lock_configuration_certainty = (
        "read-only; only one complete validated 200 "
        "Object_Lock_Configuration_Found response observed exposes the "
        "presence-preserving configuration; every incomplete, invalid, or "
        "non-observed response exposes no configuration state; the client "
        "performs no automatic retry"
    )
    get_object_lock_configuration_reconciliation = (
        "a later GetObjectLockConfiguration observes only the bucket "
        "configuration current at read time; it does not prove that a prior "
        "mutation caused the observed state or authorize automatic replay"
    )
    get_object_lock_configuration_symbols = [
        "Prepare_Get_Object_Lock_Configuration",
        "Decode_Get_Object_Lock_Configuration_Response",
        "Execute_Get_Object_Lock_Configuration",
        "Get_Object_Lock_Configuration_Operation",
        "Get_Object_Lock_Configuration",
        "Finish",
    ]

    def assert_get_object_lock_configuration_registry(candidate):
        entry = candidate.operations["GetObjectLockConfiguration"]
        assert entry.get("public_name") == "Get_Object_Lock_Configuration"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "get_object_lock_configuration"
        assert (
            entry.get("certainty") == get_object_lock_configuration_certainty
        )
        assert entry.get("reconciliation") == (
            get_object_lock_configuration_reconciliation
        )
        assert entry.get("ada_symbols") == get_object_lock_configuration_symbols
        assert entry["coverage"]["backend"] == "missing"
        assert entry["coverage"]["server"] == "missing"
        assert entry["provenance"]["backend"] == "absent"
        assert entry["provenance"]["server"] == "absent"
        assert "ObjectLockConfiguration" in entry["absence"]
        assert "server route are absent" in entry["exclusions"][0]
        assert candidate.qualification[
            "get_object_lock_configuration"
        ][0][-1] == "tools/verify-get-object-lock-configuration-preparation.py"

    def reject_get_object_lock_configuration_registry(candidate, label):
        try:
            assert_get_object_lock_configuration_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} GetObjectLockConfiguration registry accepted"
        )

    assert_get_object_lock_configuration_registry(registry)
    missing_get_object_lock_configuration_name = copy.deepcopy(registry)
    del missing_get_object_lock_configuration_name.operations[
        "GetObjectLockConfiguration"
    ]["public_name"]
    reject_get_object_lock_configuration_registry(
        missing_get_object_lock_configuration_name, "missing name"
    )
    wrong_get_object_lock_configuration_name = copy.deepcopy(registry)
    wrong_get_object_lock_configuration_name.operations[
        "GetObjectLockConfiguration"
    ]["public_name"] = "Get_Retention"
    reject_get_object_lock_configuration_registry(
        wrong_get_object_lock_configuration_name, "wrong name"
    )
    retry_get_object_lock_configuration = copy.deepcopy(registry)
    retry_get_object_lock_configuration.operations[
        "GetObjectLockConfiguration"
    ]["certainty"] = "read-only; retry automatically"
    reject_get_object_lock_configuration_registry(
        retry_get_object_lock_configuration, "automatic retry"
    )
    causal_get_object_lock_configuration = copy.deepcopy(registry)
    causal_get_object_lock_configuration.operations[
        "GetObjectLockConfiguration"
    ]["reconciliation"] = "the read proves the prior mutation caused state"
    reject_get_object_lock_configuration_registry(
        causal_get_object_lock_configuration, "causal reconciliation"
    )
    server_get_object_lock_configuration = copy.deepcopy(registry)
    server_get_object_lock_configuration.operations[
        "GetObjectLockConfiguration"
    ]["coverage"]["server"] = "covered"
    reject_get_object_lock_configuration_registry(
        server_get_object_lock_configuration, "invented server coverage"
    )
    cross_get_object_lock_configuration_symbol = copy.deepcopy(registry)
    cross_get_object_lock_configuration_symbol.operations[
        "GetObjectLockConfiguration"
    ]["ada_symbols"][0] = "Prepare_Get_Object_Retention"
    reject_get_object_lock_configuration_registry(
        cross_get_object_lock_configuration_symbol, "cross-operation symbol"
    )
    get_object_lock_configuration_qualification, lock_commands = (
        s3_operation.qualification_plan(
            registry, ["GetObjectLockConfiguration"]
        )
    )
    assert (
        get_object_lock_configuration_qualification
        == "get_object_lock_configuration"
    )
    assert lock_commands[:4] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-get-object-lock-configuration-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_get_object_lock_configuration_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
    ]
    assert lock_commands[4] == ["./tools/verify-coverage.sh"]
    assert lock_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-get-object-lock-configuration-gnatdoc",
        "--operation",
        "GetObjectLockConfiguration",
    ]
    assert lock_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry,
            ["GetObjectLockConfiguration", "GetObjectLockConfiguration"],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate GetObjectLockConfiguration lane accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            ["GetObjectLockConfiguration", "PutObjectLockConfiguration"],
        )
    except s3_operation.Audit_Error as error:
        assert (
            "do not share one qualification lane" in str(error)
            or "has no focused qualification lane" in str(error)
        )
    else:
        raise AssertionError("mixed ObjectLockConfiguration lane accepted")
    put_object_lock_configuration_certainty = (
        "only a complete validated 200 reports "
        "Object_Lock_Configuration_Mutation_Completed; an exact recognized "
        "S3 rejection or definite non-admission reports "
        "Object_Lock_Configuration_Mutation_Definitely_Not_Applied, "
        "pre-admission cancellation reports "
        "Object_Lock_Configuration_Mutation_Cancelled_Before_Admission, and "
        "every other possibly admitted or incomplete outcome reports "
        "Object_Lock_Configuration_Mutation_Outcome_Unknown; no automatic "
        "replay"
    )
    put_object_lock_configuration_reconciliation = (
        "a later GetObjectLockConfiguration may observe the bucket "
        "configuration current at read time before a caller-selected retry, "
        "but it neither proves that the lost mutation caused the observed "
        "state nor upgrades mutation certainty; no automatic replay"
    )
    put_object_lock_configuration_symbols = [
        "Prepare_Put_Object_Lock_Configuration",
        "Decode_Put_Object_Lock_Configuration_Response",
        "Execute_Put_Object_Lock_Configuration",
        "Put_Object_Lock_Configuration_Operation",
        "Put_Object_Lock_Configuration",
        "Finish",
    ]

    def assert_put_object_lock_configuration_registry(candidate):
        entry = candidate.operations["PutObjectLockConfiguration"]
        assert entry.get("public_name") == "Put_Object_Lock_Configuration"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "put_object_lock_configuration"
        assert (
            entry.get("certainty") == put_object_lock_configuration_certainty
        )
        assert entry.get("reconciliation") == (
            put_object_lock_configuration_reconciliation
        )
        assert entry.get("ada_symbols") == put_object_lock_configuration_symbols
        assert entry["coverage"]["backend"] == "missing"
        assert entry["coverage"]["server"] == "missing"
        assert entry["provenance"]["backend"] == "absent"
        assert entry["provenance"]["server"] == "absent"
        assert "no automatic replay" in entry["certainty"]
        assert "server route are absent" in entry["exclusions"][0]
        assert candidate.qualification[
            "put_object_lock_configuration"
        ][0][-1] == "tools/verify-put-object-lock-configuration-preparation.py"

    def reject_put_object_lock_configuration_registry(candidate, label):
        try:
            assert_put_object_lock_configuration_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} PutObjectLockConfiguration registry accepted"
        )

    assert_put_object_lock_configuration_registry(registry)
    missing_put_object_lock_configuration_name = copy.deepcopy(registry)
    del missing_put_object_lock_configuration_name.operations[
        "PutObjectLockConfiguration"
    ]["public_name"]
    reject_put_object_lock_configuration_registry(
        missing_put_object_lock_configuration_name, "missing name"
    )
    wrong_put_object_lock_configuration_name = copy.deepcopy(registry)
    wrong_put_object_lock_configuration_name.operations[
        "PutObjectLockConfiguration"
    ]["public_name"] = "Put_Retention"
    reject_put_object_lock_configuration_registry(
        wrong_put_object_lock_configuration_name, "wrong name"
    )
    retry_put_object_lock_configuration = copy.deepcopy(registry)
    retry_put_object_lock_configuration.operations[
        "PutObjectLockConfiguration"
    ]["certainty"] = "mutation; retry automatically after a lost response"
    reject_put_object_lock_configuration_registry(
        retry_put_object_lock_configuration, "automatic retry"
    )
    causal_put_object_lock_configuration = copy.deepcopy(registry)
    causal_put_object_lock_configuration.operations[
        "PutObjectLockConfiguration"
    ]["reconciliation"] = "the read proves the prior mutation caused state"
    reject_put_object_lock_configuration_registry(
        causal_put_object_lock_configuration, "causal reconciliation"
    )
    server_put_object_lock_configuration = copy.deepcopy(registry)
    server_put_object_lock_configuration.operations[
        "PutObjectLockConfiguration"
    ]["coverage"]["server"] = "covered"
    reject_put_object_lock_configuration_registry(
        server_put_object_lock_configuration, "invented server coverage"
    )
    cross_put_object_lock_configuration_symbol = copy.deepcopy(registry)
    cross_put_object_lock_configuration_symbol.operations[
        "PutObjectLockConfiguration"
    ]["ada_symbols"][0] = "Prepare_Put_Object_Retention"
    reject_put_object_lock_configuration_registry(
        cross_put_object_lock_configuration_symbol, "cross-operation symbol"
    )
    put_object_lock_configuration_qualification, lock_commands = (
        s3_operation.qualification_plan(
            registry, ["PutObjectLockConfiguration"]
        )
    )
    assert (
        put_object_lock_configuration_qualification
        == "put_object_lock_configuration"
    )
    assert lock_commands[:4] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-put-object-lock-configuration-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_put_object_lock_configuration_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
    ]
    assert lock_commands[4] == ["./tools/verify-coverage.sh"]
    assert lock_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-put-object-lock-configuration-gnatdoc",
        "--operation",
        "PutObjectLockConfiguration",
    ]
    assert lock_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry,
            ["PutObjectLockConfiguration", "PutObjectLockConfiguration"],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate PutObjectLockConfiguration lane accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            ["PutObjectLockConfiguration", "GetObjectLockConfiguration"],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed PutObjectLockConfiguration lane accepted")
    get_object_retention_certainty = (
        "read-only; only one complete validated 200 Object_Retention_Found "
        "response observed exposes the presence-preserving retention value; "
        "every incomplete, invalid, or non-observed response exposes no "
        "retention state; the client performs no automatic retry"
    )
    get_object_retention_reconciliation = (
        "an explicit VersionId observes retention for that selected object "
        "generation and an omitted VersionId observes the generation current "
        "at read time; the modeled response does not echo a version identifier "
        "and neither form proves that a prior mutation caused the observed "
        "retention state"
    )
    get_object_retention_symbols = [
        "Prepare_Get_Object_Retention",
        "Decode_Get_Object_Retention_Response",
        "Execute_Get_Object_Retention",
        "Get_Retention_Operation",
        "Get_Retention",
        "Finish",
    ]

    def assert_get_object_retention_registry(candidate):
        entry = candidate.operations["GetObjectRetention"]
        assert entry.get("public_name") == "Get_Retention"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "get_object_retention"
        assert entry.get("certainty") == get_object_retention_certainty
        assert (
            entry.get("reconciliation") == get_object_retention_reconciliation
        )
        assert entry.get("ada_symbols") == get_object_retention_symbols
        assert entry["coverage"]["backend"] == "missing"
        assert entry["coverage"]["server"] == "missing"
        assert entry["provenance"]["backend"] == "absent"
        assert entry["provenance"]["server"] == "absent"
        assert "NoSuchVersion" in entry["absence"]
        assert "server route are absent" in entry["exclusions"][0]
        assert (
            candidate.qualification["get_object_retention"][0][-1]
            == "tools/verify-get-object-retention-preparation.py"
        )

    def reject_get_object_retention_registry(candidate, label):
        try:
            assert_get_object_retention_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(f"{label} GetObjectRetention registry accepted")

    assert_get_object_retention_registry(registry)
    missing_get_object_retention_name = copy.deepcopy(registry)
    del missing_get_object_retention_name.operations["GetObjectRetention"][
        "public_name"
    ]
    reject_get_object_retention_registry(
        missing_get_object_retention_name, "missing name"
    )
    wrong_get_object_retention_name = copy.deepcopy(registry)
    wrong_get_object_retention_name.operations["GetObjectRetention"][
        "public_name"
    ] = "Get_Legal_Hold"
    reject_get_object_retention_registry(
        wrong_get_object_retention_name, "wrong name"
    )
    retry_get_object_retention = copy.deepcopy(registry)
    retry_get_object_retention.operations["GetObjectRetention"][
        "certainty"
    ] = "read-only; retry automatically"
    reject_get_object_retention_registry(
        retry_get_object_retention, "automatic retry"
    )
    server_get_object_retention = copy.deepcopy(registry)
    server_get_object_retention.operations["GetObjectRetention"]["coverage"][
        "server"
    ] = "covered"
    reject_get_object_retention_registry(
        server_get_object_retention, "invented server coverage"
    )
    cross_get_object_retention_symbol = copy.deepcopy(registry)
    cross_get_object_retention_symbol.operations["GetObjectRetention"][
        "ada_symbols"
    ][0] = "Prepare_Get_Object_Legal_Hold"
    reject_get_object_retention_registry(
        cross_get_object_retention_symbol, "cross-operation symbol"
    )
    get_object_retention_qualification, get_object_retention_commands = (
        s3_operation.qualification_plan(registry, ["GetObjectRetention"])
    )
    assert get_object_retention_qualification == "get_object_retention"
    assert get_object_retention_commands[:4] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-get-object-retention-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_get_object_retention_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
    ]
    assert get_object_retention_commands[4] == ["./tools/verify-coverage.sh"]
    assert get_object_retention_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-get-object-retention-gnatdoc",
        "--operation",
        "GetObjectRetention",
    ]
    assert get_object_retention_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry, ["GetObjectRetention", "GetObjectRetention"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate GetObjectRetention lane accepted")
    try:
        s3_operation.qualification_plan(
            registry, ["GetObjectRetention", "PutObjectRetention"]
        )
    except s3_operation.Audit_Error as error:
        assert (
            "do not share one qualification lane" in str(error)
            or "has no focused qualification lane" in str(error)
        )
    else:
        raise AssertionError("mixed GetObjectRetention lane accepted")
    put_object_retention_certainty = (
        "only a complete validated 200 reports "
        "Retention_Mutation_Completed; an exact recognized S3 rejection or "
        "definite non-admission reports "
        "Retention_Mutation_Definitely_Not_Applied, pre-admission "
        "cancellation reports "
        "Retention_Mutation_Cancelled_Before_Admission, and every other "
        "possibly admitted or incomplete outcome reports "
        "Retention_Mutation_Outcome_Unknown; no automatic replay"
    )
    put_object_retention_reconciliation = (
        "an explicit VersionId permits a read-only GetObjectRetention "
        "observation of that selected object generation and an omitted "
        "VersionId permits only an observation of the generation current at "
        "reconciliation time; neither observation proves that the lost "
        "mutation caused the state or upgrades mutation certainty without "
        "caller-supplied serialization authority"
    )
    put_object_retention_symbols = [
        "Prepare_Put_Object_Retention",
        "Decode_Put_Object_Retention_Response",
        "Execute_Put_Object_Retention",
        "Put_Retention_Operation",
        "Put_Retention",
        "Finish",
    ]

    def assert_put_object_retention_registry(candidate):
        entry = candidate.operations["PutObjectRetention"]
        assert entry.get("public_name") == "Put_Retention"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "put_object_retention"
        assert entry.get("certainty") == put_object_retention_certainty
        assert (
            entry.get("reconciliation") == put_object_retention_reconciliation
        )
        assert entry.get("ada_symbols") == put_object_retention_symbols
        assert entry["coverage"]["backend"] == "missing"
        assert entry["coverage"]["server"] == "missing"
        assert entry["provenance"]["backend"] == "absent"
        assert entry["provenance"]["server"] == "absent"
        assert "no automatic replay" in entry["certainty"]
        assert "server route are absent" in entry["exclusions"][0]
        assert (
            candidate.qualification["put_object_retention"][0][-1]
            == "tools/verify-put-object-retention-preparation.py"
        )

    def reject_put_object_retention_registry(candidate, label):
        try:
            assert_put_object_retention_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(f"{label} PutObjectRetention registry accepted")

    assert_put_object_retention_registry(registry)
    missing_put_object_retention_name = copy.deepcopy(registry)
    del missing_put_object_retention_name.operations["PutObjectRetention"][
        "public_name"
    ]
    reject_put_object_retention_registry(
        missing_put_object_retention_name, "missing name"
    )
    wrong_put_object_retention_name = copy.deepcopy(registry)
    wrong_put_object_retention_name.operations["PutObjectRetention"][
        "public_name"
    ] = "Put_Legal_Hold"
    reject_put_object_retention_registry(
        wrong_put_object_retention_name, "wrong name"
    )
    retry_put_object_retention = copy.deepcopy(registry)
    retry_put_object_retention.operations["PutObjectRetention"][
        "certainty"
    ] = "mutation; retry automatically after a lost response"
    reject_put_object_retention_registry(
        retry_put_object_retention, "automatic retry"
    )
    causal_put_object_retention = copy.deepcopy(registry)
    causal_put_object_retention.operations["PutObjectRetention"][
        "reconciliation"
    ] = "GetObjectRetention proves the lost mutation caused the state"
    reject_put_object_retention_registry(
        causal_put_object_retention, "causal reconciliation"
    )
    server_put_object_retention = copy.deepcopy(registry)
    server_put_object_retention.operations["PutObjectRetention"]["coverage"][
        "server"
    ] = "covered"
    reject_put_object_retention_registry(
        server_put_object_retention, "invented server coverage"
    )
    cross_put_object_retention_symbol = copy.deepcopy(registry)
    cross_put_object_retention_symbol.operations["PutObjectRetention"][
        "ada_symbols"
    ][0] = "Prepare_Put_Object_Legal_Hold"
    reject_put_object_retention_registry(
        cross_put_object_retention_symbol, "cross-operation symbol"
    )
    put_object_retention_qualification, put_object_retention_commands = (
        s3_operation.qualification_plan(registry, ["PutObjectRetention"])
    )
    assert put_object_retention_qualification == "put_object_retention"
    assert put_object_retention_commands[:4] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-put-object-retention-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_put_object_retention_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
    ]
    assert put_object_retention_commands[4] == ["./tools/verify-coverage.sh"]
    assert put_object_retention_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-put-object-retention-gnatdoc",
        "--operation",
        "PutObjectRetention",
    ]
    assert put_object_retention_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry, ["PutObjectRetention", "PutObjectRetention"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate PutObjectRetention lane accepted")
    try:
        s3_operation.qualification_plan(
            registry, ["PutObjectRetention", "GetObjectRetention"]
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed PutObjectRetention lane accepted")
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
    get_bucket_tagging_public_name = "Get_Tags"

    def assert_get_bucket_tagging_registry(candidate):
        entry = candidate.operations["GetBucketTagging"]
        assert entry.get("public_name") == get_bucket_tagging_public_name
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "get_bucket_tagging"
        assert entry.get("certainty") == "read_only"
        assert entry.get("reconciliation") == "not_applicable"
        assert entry.get("ada_symbols") == [
            "Prepare_Get_Bucket_Tagging",
            "Decode_Get_Bucket_Tagging_Response",
            "Execute_Get_Bucket_Tagging",
            "Get_Bucket_Tagging_Operation",
            "Get_Tags",
            "Finish",
        ]
        assert "NoSuchTagSet maps to Not_Found" in entry["absence"]
        assert "current bucket tag snapshot" in entry["absence"]
        assert "does not authorize or perform" in entry["exclusions"][3]
        assert "tools/verify-get-bucket-tagging-preparation.py" in (
            candidate.qualification["get_bucket_tagging"][0]
        )

    def reject_get_bucket_tagging_registry(candidate, label):
        try:
            assert_get_bucket_tagging_registry(candidate)
        except (AssertionError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} GetBucketTagging registry accepted"
        )

    assert_get_bucket_tagging_registry(registry)
    missing_get_bucket_tagging_name = copy.deepcopy(registry)
    del missing_get_bucket_tagging_name.operations["GetBucketTagging"][
        "public_name"
    ]
    reject_get_bucket_tagging_registry(
        missing_get_bucket_tagging_name,
        "missing public name",
    )
    wrong_get_bucket_tagging_name = copy.deepcopy(registry)
    wrong_get_bucket_tagging_name.operations["GetBucketTagging"][
        "public_name"
    ] = "Get_Object_Tags"
    reject_get_bucket_tagging_registry(
        wrong_get_bucket_tagging_name,
        "wrong public name",
    )
    cross_get_bucket_tagging_symbol = copy.deepcopy(registry)
    cross_get_bucket_tagging_symbol.operations["GetBucketTagging"][
        "ada_symbols"
    ][0] = "Prepare_Get_Object_Tagging"
    reject_get_bucket_tagging_registry(
        cross_get_bucket_tagging_symbol,
        "cross-operation symbol",
    )
    get_bucket_tagging_qualification, get_bucket_tagging_commands = (
        s3_operation.qualification_plan(registry, ["GetBucketTagging"])
    )
    assert get_bucket_tagging_qualification == "get_bucket_tagging"
    assert get_bucket_tagging_commands[:4] == [
        [
            "uv",
            "run",
            "--python",
            "3.13",
            "--",
            "tools/verify-get-bucket-tagging-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert get_bucket_tagging_commands[4] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-get-bucket-tagging-gnatdoc",
        "--operation",
        "GetBucketTagging",
    ]
    assert get_bucket_tagging_commands[5:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    malformed_get_bucket_tagging_lane = copy.deepcopy(registry)
    malformed_get_bucket_tagging_lane.operations["GetBucketTagging"][
        "qualification"
    ] = "missing_get_bucket_tagging_lane"
    try:
        s3_operation.qualification_plan(
            malformed_get_bucket_tagging_lane,
            ["GetBucketTagging"],
        )
    except s3_operation.Audit_Error as error:
        assert "unknown qualification lane" in str(error)
    else:
        raise AssertionError("malformed GetBucketTagging lane was accepted")
    try:
        s3_operation.qualification_plan(
            registry,
            ["GetBucketTagging", "GetBucketTagging"],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate GetBucketTagging lane was accepted")
    try:
        s3_operation.qualification_plan(
            registry,
            ["GetBucketTagging", "GetBucketVersioning"],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed GetBucketTagging lane was accepted")
    put_bucket_tagging_certainty = (
        "only a complete validated 200 or 204 response reports "
        "Bucket_Tag_Mutation_Completed; an exact recognized non-mutating "
        "rejection or definite non-admission reports "
        "Bucket_Tag_Mutation_Definitely_Not_Applied; pre-admission "
        "cancellation reports "
        "Bucket_Tag_Mutation_Cancelled_Before_Admission; possible or "
        "incomplete admission, retryable responses, and malformed or "
        "oversized responses report Bucket_Tag_Mutation_Outcome_Unknown; "
        "no automatic replay"
    )
    put_bucket_tagging_reconciliation = (
        "caller-selected Get_Tags may observe the current complete bucket "
        "tag set before a retry but does not prove that the lost mutation "
        "caused the observed state or upgrade mutation certainty; no "
        "automatic replay"
    )

    def assert_put_bucket_tagging_registry(candidate):
        entry = candidate.operations["PutBucketTagging"]
        assert entry.get("public_name") == "Put_Tags"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "put_bucket_tagging"
        assert entry.get("codec") == "rest_xml_and_headers"
        assert entry.get("certainty") == put_bucket_tagging_certainty
        assert entry.get("reconciliation") == (
            put_bucket_tagging_reconciliation
        )
        assert entry.get("ada_symbols") == [
            "Prepare_Put_Bucket_Tagging",
            "Decode_Put_Bucket_Tagging_Response",
            "Execute_Put_Bucket_Tagging",
            "Put_Bucket_Tagging_Operation",
            "Put_Tags",
            "Finish",
        ]
        assert "exact NoSuchBucket" in entry["absence"]
        assert "exact HTTP 200" in entry["exclusions"][2]
        assert "exact 200 or 204" in entry["exclusions"][2]
        assert "whitespace-only success payload" in entry["exclusions"][3]
        assert "does not establish causation" in entry["exclusions"][4]
        assert "tools/verify-put-bucket-tagging-preparation.py" in (
            candidate.qualification["put_bucket_tagging"][0]
        )

    def reject_put_bucket_tagging_registry(candidate, label):
        try:
            assert_put_bucket_tagging_registry(candidate)
        except (AssertionError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} PutBucketTagging registry accepted"
        )

    assert_put_bucket_tagging_registry(registry)
    missing_put_bucket_tagging_name = copy.deepcopy(registry)
    del missing_put_bucket_tagging_name.operations["PutBucketTagging"][
        "public_name"
    ]
    reject_put_bucket_tagging_registry(
        missing_put_bucket_tagging_name,
        "missing public name",
    )
    wrong_put_bucket_tagging_name = copy.deepcopy(registry)
    wrong_put_bucket_tagging_name.operations["PutBucketTagging"][
        "public_name"
    ] = "Put_Object_Tags"
    reject_put_bucket_tagging_registry(
        wrong_put_bucket_tagging_name,
        "wrong public name",
    )
    narrowed_put_bucket_tagging_success = copy.deepcopy(registry)
    narrowed_put_bucket_tagging_success.operations["PutBucketTagging"][
        "certainty"
    ] = put_bucket_tagging_certainty.replace("200 or 204", "200")
    reject_put_bucket_tagging_registry(
        narrowed_put_bucket_tagging_success,
        "narrowed client success status",
    )
    causal_put_bucket_tagging_reconciliation = copy.deepcopy(registry)
    causal_put_bucket_tagging_reconciliation.operations[
        "PutBucketTagging"
    ]["reconciliation"] = "Get_Tags proves the mutation completed"
    reject_put_bucket_tagging_registry(
        causal_put_bucket_tagging_reconciliation,
        "causal reconciliation",
    )
    cross_put_bucket_tagging_symbol = copy.deepcopy(registry)
    cross_put_bucket_tagging_symbol.operations["PutBucketTagging"][
        "ada_symbols"
    ][0] = "Prepare_Put_Object_Tagging"
    reject_put_bucket_tagging_registry(
        cross_put_bucket_tagging_symbol,
        "cross-operation symbol",
    )
    put_bucket_tagging_qualification, put_bucket_tagging_commands = (
        s3_operation.qualification_plan(registry, ["PutBucketTagging"])
    )
    assert put_bucket_tagging_qualification == "put_bucket_tagging"
    assert put_bucket_tagging_commands[:4] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-put-bucket-tagging-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert put_bucket_tagging_commands[4] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-put-bucket-tagging-gnatdoc",
        "--operation",
        "PutBucketTagging",
    ]
    assert put_bucket_tagging_commands[5:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    malformed_put_bucket_tagging_lane = copy.deepcopy(registry)
    malformed_put_bucket_tagging_lane.operations["PutBucketTagging"][
        "qualification"
    ] = "missing_put_bucket_tagging_lane"
    try:
        s3_operation.qualification_plan(
            malformed_put_bucket_tagging_lane,
            ["PutBucketTagging"],
        )
    except s3_operation.Audit_Error as error:
        assert "unknown qualification lane" in str(error)
    else:
        raise AssertionError("malformed PutBucketTagging lane was accepted")
    try:
        s3_operation.qualification_plan(
            registry,
            ["PutBucketTagging", "PutBucketTagging"],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate PutBucketTagging lane was accepted")
    try:
        s3_operation.qualification_plan(
            registry,
            ["PutBucketTagging", "PutBucketVersioning"],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed PutBucketTagging lane was accepted")
    delete_bucket_tagging_certainty = (
        "only a complete validated 204 response reports "
        "Bucket_Tag_Mutation_Completed; an exact recognized non-mutating "
        "rejection or definite non-admission reports "
        "Bucket_Tag_Mutation_Definitely_Not_Applied; pre-admission "
        "cancellation reports "
        "Bucket_Tag_Mutation_Cancelled_Before_Admission; possible or "
        "incomplete admission, retryable responses, and malformed or "
        "oversized responses report Bucket_Tag_Mutation_Outcome_Unknown; "
        "no automatic replay"
    )
    delete_bucket_tagging_reconciliation = (
        "caller-selected Get_Tags may observe the current NoSuchTagSet "
        "state before a retry but does not prove that the lost deletion "
        "caused the observed absence or upgrade mutation certainty; no "
        "automatic replay"
    )

    def assert_delete_bucket_tagging_registry(candidate):
        entry = candidate.operations["DeleteBucketTagging"]
        assert entry.get("public_name") == "Delete_Tags"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "delete_bucket_tagging"
        assert entry.get("codec") == "empty_response"
        assert entry.get("certainty") == delete_bucket_tagging_certainty
        assert entry.get("reconciliation") == (
            delete_bucket_tagging_reconciliation
        )
        assert entry.get("ada_symbols") == [
            "Prepare_Delete_Bucket_Tagging",
            "Decode_Delete_Bucket_Tagging_Response",
            "Execute_Delete_Bucket_Tagging",
            "Delete_Bucket_Tagging_Operation",
            "Delete_Tags",
            "Finish",
        ]
        assert "does not assert prior tag-set presence" in entry["absence"]
        assert "exact NoSuchBucket" in entry["absence"]
        assert "exact HTTP 204" in entry["exclusions"][2]
        assert "exactly empty response body" in entry["exclusions"][2]
        assert "previously present" in entry["exclusions"][3]
        assert "does not establish causation" in entry["exclusions"][4]
        assert (
            candidate.qualification["delete_bucket_tagging"][0][-1]
            == "tools/verify-delete-bucket-tagging-preparation.py"
        )

    def reject_delete_bucket_tagging_registry(candidate, label):
        try:
            assert_delete_bucket_tagging_registry(candidate)
        except (AssertionError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} DeleteBucketTagging registry accepted"
        )

    assert_delete_bucket_tagging_registry(registry)
    missing_delete_bucket_tagging_name = copy.deepcopy(registry)
    del missing_delete_bucket_tagging_name.operations[
        "DeleteBucketTagging"
    ]["public_name"]
    reject_delete_bucket_tagging_registry(
        missing_delete_bucket_tagging_name,
        "missing public name",
    )
    wrong_delete_bucket_tagging_name = copy.deepcopy(registry)
    wrong_delete_bucket_tagging_name.operations["DeleteBucketTagging"][
        "public_name"
    ] = "Delete_Object_Tags"
    reject_delete_bucket_tagging_registry(
        wrong_delete_bucket_tagging_name,
        "wrong public name",
    )
    broadened_delete_bucket_tagging_success = copy.deepcopy(registry)
    broadened_delete_bucket_tagging_success.operations[
        "DeleteBucketTagging"
    ]["certainty"] = delete_bucket_tagging_certainty.replace(
        "validated 204", "validated 200 or 204"
    )
    reject_delete_bucket_tagging_registry(
        broadened_delete_bucket_tagging_success,
        "broadened success status",
    )
    causal_delete_bucket_tagging_reconciliation = copy.deepcopy(registry)
    causal_delete_bucket_tagging_reconciliation.operations[
        "DeleteBucketTagging"
    ]["reconciliation"] = "Get_Tags proves the deletion completed"
    reject_delete_bucket_tagging_registry(
        causal_delete_bucket_tagging_reconciliation,
        "causal reconciliation",
    )
    cross_delete_bucket_tagging_symbol = copy.deepcopy(registry)
    cross_delete_bucket_tagging_symbol.operations["DeleteBucketTagging"][
        "ada_symbols"
    ][0] = "Prepare_Delete_Object_Tagging"
    reject_delete_bucket_tagging_registry(
        cross_delete_bucket_tagging_symbol,
        "cross-operation symbol",
    )
    delete_bucket_tagging_qualification, delete_bucket_tagging_commands = (
        s3_operation.qualification_plan(registry, ["DeleteBucketTagging"])
    )
    assert delete_bucket_tagging_qualification == "delete_bucket_tagging"
    assert delete_bucket_tagging_commands[:4] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-delete-bucket-tagging-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert delete_bucket_tagging_commands[4] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-bucket-tagging-gnatdoc",
        "--operation",
        "DeleteBucketTagging",
    ]
    assert delete_bucket_tagging_commands[5:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    malformed_delete_bucket_tagging_lane = copy.deepcopy(registry)
    malformed_delete_bucket_tagging_lane.operations[
        "DeleteBucketTagging"
    ]["qualification"] = "missing_delete_bucket_tagging_lane"
    try:
        s3_operation.qualification_plan(
            malformed_delete_bucket_tagging_lane,
            ["DeleteBucketTagging"],
        )
    except s3_operation.Audit_Error as error:
        assert "unknown qualification lane" in str(error)
    else:
        raise AssertionError(
            "malformed DeleteBucketTagging lane was accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            ["DeleteBucketTagging", "DeleteBucketTagging"],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate DeleteBucketTagging lane was accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            ["DeleteBucketTagging", "DeleteBucket"],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed DeleteBucketTagging lane was accepted")
    delete_bucket_cors_certainty = (
        "only a complete validated 204 response with an exactly empty body "
        "reports Bucket_CORS_Mutation_Completed; an exact recognized "
        "non-mutating rejection or definite non-admission reports "
        "Bucket_CORS_Mutation_Definitely_Not_Applied; pre-admission "
        "cancellation reports "
        "Bucket_CORS_Mutation_Cancelled_Before_Admission; possible or "
        "incomplete admission, retryable responses, and malformed or "
        "oversized responses report Bucket_CORS_Mutation_Outcome_Unknown; "
        "no automatic replay"
    )
    delete_bucket_cors_reconciliation = (
        "caller-selected Get_CORS may observe the current "
        "NoSuchCORSConfiguration state before a retry but does not prove "
        "that the lost deletion caused the observed absence or upgrade "
        "mutation certainty; no automatic replay"
    )

    def assert_delete_bucket_cors_registry(candidate):
        entry = candidate.operations["DeleteBucketCors"]
        assert entry.get("public_name") == "Delete_CORS"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "delete_bucket_cors"
        assert entry.get("codec") == "empty_response"
        assert entry.get("certainty") == delete_bucket_cors_certainty
        assert entry.get("reconciliation") == (
            delete_bucket_cors_reconciliation
        )
        assert entry.get("coverage") == {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        }
        assert entry.get("ada_symbols") == [
            "Prepare_Delete_Bucket_CORS",
            "Decode_Delete_Bucket_CORS_Response",
            "Execute_Delete_Bucket_CORS",
            "Delete_Bucket_Cors_Operation",
            "Delete_CORS",
            "Finish",
        ]
        assert "does not assert prior CORS-configuration presence" in (
            entry["absence"]
        )
        assert "exact NoSuchBucket" in entry["absence"]
        assert "exact HTTP 204" in entry["exclusions"][2]
        assert "exactly empty response body" in entry["exclusions"][2]
        assert "previously present" in entry["exclusions"][3]
        assert "does not establish causation" in entry["exclusions"][4]
        assert (
            candidate.qualification["delete_bucket_cors"][0][-1]
            == "tools/verify-delete-bucket-cors-preparation.py"
        )

    def reject_delete_bucket_cors_registry(candidate, label):
        try:
            assert_delete_bucket_cors_registry(candidate)
        except (AssertionError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} DeleteBucketCors registry accepted"
        )

    assert_delete_bucket_cors_registry(registry)
    missing_delete_bucket_cors_name = copy.deepcopy(registry)
    del missing_delete_bucket_cors_name.operations[
        "DeleteBucketCors"
    ]["public_name"]
    reject_delete_bucket_cors_registry(
        missing_delete_bucket_cors_name,
        "missing public name",
    )
    wrong_delete_bucket_cors_name = copy.deepcopy(registry)
    wrong_delete_bucket_cors_name.operations["DeleteBucketCors"][
        "public_name"
    ] = "Delete_Configuration"
    reject_delete_bucket_cors_registry(
        wrong_delete_bucket_cors_name,
        "wrong public name",
    )
    broadened_delete_bucket_cors_success = copy.deepcopy(registry)
    broadened_delete_bucket_cors_success.operations["DeleteBucketCors"][
        "certainty"
    ] = delete_bucket_cors_certainty.replace(
        "validated 204", "validated 200 or 204"
    )
    reject_delete_bucket_cors_registry(
        broadened_delete_bucket_cors_success,
        "broadened success status",
    )
    causal_delete_bucket_cors_reconciliation = copy.deepcopy(registry)
    causal_delete_bucket_cors_reconciliation.operations[
        "DeleteBucketCors"
    ]["reconciliation"] = "Get_CORS proves the deletion completed"
    reject_delete_bucket_cors_registry(
        causal_delete_bucket_cors_reconciliation,
        "causal reconciliation",
    )
    cross_delete_bucket_cors_symbol = copy.deepcopy(registry)
    cross_delete_bucket_cors_symbol.operations["DeleteBucketCors"][
        "ada_symbols"
    ][0] = "Prepare_Delete_Bucket_Tagging"
    reject_delete_bucket_cors_registry(
        cross_delete_bucket_cors_symbol,
        "cross-operation symbol",
    )
    delete_bucket_cors_qualification, delete_bucket_cors_commands = (
        s3_operation.qualification_plan(registry, ["DeleteBucketCors"])
    )
    assert delete_bucket_cors_qualification == "delete_bucket_cors"
    assert delete_bucket_cors_commands[:6] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-delete-bucket-cors-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_delete_bucket_cors_corpus"],
        ["@tests", "./bin/s3_server_application_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert delete_bucket_cors_commands[6] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-bucket-cors-gnatdoc",
        "--operation",
        "DeleteBucketCors",
    ]
    assert delete_bucket_cors_commands[7:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    malformed_delete_bucket_cors_lane = copy.deepcopy(registry)
    malformed_delete_bucket_cors_lane.operations["DeleteBucketCors"][
        "qualification"
    ] = "missing_delete_bucket_cors_lane"
    try:
        s3_operation.qualification_plan(
            malformed_delete_bucket_cors_lane,
            ["DeleteBucketCors"],
        )
    except s3_operation.Audit_Error as error:
        assert "unknown qualification lane" in str(error)
    else:
        raise AssertionError(
            "malformed DeleteBucketCors lane was accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            ["DeleteBucketCors", "DeleteBucketCors"],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate DeleteBucketCors lane was accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            ["DeleteBucketCors", "DeleteBucketTagging"],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed DeleteBucketCors lane was accepted")
    delete_encryption_certainty = (
        "only a complete validated 204 response with an exactly empty body "
        "reports Bucket_Encryption_Mutation_Completed; an exact recognized "
        "non-mutating rejection or definite non-admission reports "
        "Bucket_Encryption_Mutation_Definitely_Not_Applied; pre-admission "
        "cancellation reports "
        "Bucket_Encryption_Mutation_Cancelled_Before_Admission; possible or "
        "incomplete admission, retryable responses, and malformed or "
        "oversized responses report "
        "Bucket_Encryption_Mutation_Outcome_Unknown; no automatic replay"
    )
    delete_encryption_reconciliation = (
        "caller-selected Get_Encryption may observe the current "
        "default-encryption configuration before a retry, including SSE-S3 "
        "reset state, but does not prove that the lost deletion caused the "
        "observed state or upgrade mutation certainty; no automatic replay"
    )

    def assert_delete_encryption_registry(candidate):
        entry = candidate.operations["DeleteBucketEncryption"]
        assert entry.get("public_name") == "Delete_Encryption"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "delete_bucket_encryption"
        assert entry.get("codec") == "empty_response"
        assert entry.get("certainty") == delete_encryption_certainty
        assert entry.get("reconciliation") == (
            delete_encryption_reconciliation
        )
        assert_bucket_control_backend_server(entry)
        assert entry.get("ada_symbols") == [
            "Prepare_Delete_Bucket_Encryption",
            "Execute_Delete_Bucket_Encryption",
            "Delete_Bucket_Encryption_Operation",
            "Delete_Encryption",
            "Finish",
        ]
        assert "resets bucket default encryption to SSE-S3" in (
            entry["absence"]
        )
        assert "exact HTTP 204" in entry["exclusions"][1]
        assert "does not establish an absent configuration" in (
            entry["exclusions"][2]
        )
        assert (
            candidate.qualification["delete_bucket_encryption"][0][-1]
            == "tools/verify-delete-bucket-configurations-preparation.py"
        )

    def reject_delete_encryption_registry(candidate, label):
        try:
            assert_delete_encryption_registry(candidate)
        except (AssertionError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} DeleteBucketEncryption registry accepted"
        )

    assert_delete_encryption_registry(registry)
    missing_delete_encryption_name = copy.deepcopy(registry)
    del missing_delete_encryption_name.operations[
        "DeleteBucketEncryption"
    ]["public_name"]
    reject_delete_encryption_registry(
        missing_delete_encryption_name,
        "missing public name",
    )
    wrong_delete_encryption_name = copy.deepcopy(registry)
    wrong_delete_encryption_name.operations["DeleteBucketEncryption"][
        "public_name"
    ] = "Delete_CORS"
    reject_delete_encryption_registry(
        wrong_delete_encryption_name,
        "wrong public name",
    )
    broadened_delete_encryption_success = copy.deepcopy(registry)
    broadened_delete_encryption_success.operations[
        "DeleteBucketEncryption"
    ]["certainty"] = delete_encryption_certainty.replace(
        "validated 204", "validated 200 or 204"
    )
    reject_delete_encryption_registry(
        broadened_delete_encryption_success,
        "broadened success status",
    )
    causal_delete_encryption_reconciliation = copy.deepcopy(registry)
    causal_delete_encryption_reconciliation.operations[
        "DeleteBucketEncryption"
    ]["reconciliation"] = "Get_Encryption proves the reset completed"
    reject_delete_encryption_registry(
        causal_delete_encryption_reconciliation,
        "causal reconciliation",
    )
    missing_delete_encryption_server = copy.deepcopy(registry)
    missing_delete_encryption_server.operations[
        "DeleteBucketEncryption"
    ]["coverage"]["server"] = "missing"
    reject_delete_encryption_registry(
        missing_delete_encryption_server,
        "missing server coverage",
    )
    cross_delete_encryption_symbol = copy.deepcopy(registry)
    cross_delete_encryption_symbol.operations["DeleteBucketEncryption"][
        "ada_symbols"
    ][0] = "Prepare_Delete_Bucket_CORS"
    reject_delete_encryption_registry(
        cross_delete_encryption_symbol,
        "cross-operation symbol",
    )
    delete_encryption_qualification, delete_encryption_commands = (
        s3_operation.qualification_plan(
            registry, ["DeleteBucketEncryption"]
        )
    )
    assert delete_encryption_qualification == "delete_bucket_encryption"
    assert delete_encryption_commands[:5] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-delete-bucket-configurations-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_delete_bucket_configurations_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert delete_encryption_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-bucket-encryption-gnatdoc",
        "--operation",
        "DeleteBucketEncryption",
    ]
    assert delete_encryption_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry,
            ["DeleteBucketEncryption", "DeleteBucketEncryption"],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate DeleteBucketEncryption lane was accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            ["DeleteBucketEncryption", "DeleteBucketCors"],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError(
            "mixed DeleteBucketEncryption lane was accepted"
        )
    delete_lifecycle_certainty = (
        "only a complete validated 204 response with an exactly empty body "
        "reports Bucket_Lifecycle_Mutation_Completed; an exact recognized "
        "non-mutating rejection or definite non-admission reports "
        "Bucket_Lifecycle_Mutation_Definitely_Not_Applied; pre-admission "
        "cancellation reports "
        "Bucket_Lifecycle_Mutation_Cancelled_Before_Admission; possible or "
        "incomplete admission, retryable responses, and malformed or "
        "oversized responses report "
        "Bucket_Lifecycle_Mutation_Outcome_Unknown; no automatic replay"
    )
    delete_lifecycle_reconciliation = (
        "caller-selected Get_Lifecycle_Configuration may observe the current "
        "lifecycle configuration or exact NoSuchLifecycleConfiguration before "
        "a retry, but does not prove that the lost deletion caused the "
        "observed absence or upgrade mutation certainty; no automatic replay"
    )

    def assert_delete_lifecycle_registry(candidate):
        entry = candidate.operations["DeleteBucketLifecycle"]
        assert entry.get("public_name") == "Delete_Lifecycle"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "delete_bucket_lifecycle"
        assert entry.get("codec") == "empty_response"
        assert entry.get("certainty") == delete_lifecycle_certainty
        assert entry.get("reconciliation") == delete_lifecycle_reconciliation
        assert entry.get("coverage") == {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        }
        assert_bucket_control_backend_server(entry)
        assert entry.get("ada_symbols") == [
            "Prepare_Delete_Bucket_Lifecycle",
            "Execute_Delete_Bucket_Lifecycle",
            "Delete_Bucket_Lifecycle_Operation",
            "Delete_Lifecycle",
            "Finish",
        ]
        assert "removes all lifecycle configuration rules" in entry["absence"]
        assert "exact HTTP 204" in entry["exclusions"][1]
        assert "does not establish causation" in entry["exclusions"][2]
        assert (
            candidate.qualification["delete_bucket_lifecycle"][0][-1]
            == "tools/verify-delete-bucket-configurations-preparation.py"
        )

    def reject_delete_lifecycle_registry(candidate, label):
        try:
            assert_delete_lifecycle_registry(candidate)
        except (AssertionError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} DeleteBucketLifecycle registry accepted"
        )

    assert_delete_lifecycle_registry(registry)
    missing_delete_lifecycle_name = copy.deepcopy(registry)
    del missing_delete_lifecycle_name.operations[
        "DeleteBucketLifecycle"
    ]["public_name"]
    reject_delete_lifecycle_registry(
        missing_delete_lifecycle_name,
        "missing public name",
    )
    wrong_delete_lifecycle_name = copy.deepcopy(registry)
    wrong_delete_lifecycle_name.operations["DeleteBucketLifecycle"][
        "public_name"
    ] = "Delete_Encryption"
    reject_delete_lifecycle_registry(
        wrong_delete_lifecycle_name,
        "wrong public name",
    )
    broadened_delete_lifecycle_success = copy.deepcopy(registry)
    broadened_delete_lifecycle_success.operations[
        "DeleteBucketLifecycle"
    ]["certainty"] = delete_lifecycle_certainty.replace(
        "validated 204", "validated 200 or 204"
    )
    reject_delete_lifecycle_registry(
        broadened_delete_lifecycle_success,
        "broadened success status",
    )
    causal_delete_lifecycle_reconciliation = copy.deepcopy(registry)
    causal_delete_lifecycle_reconciliation.operations[
        "DeleteBucketLifecycle"
    ]["reconciliation"] = (
        "Get_Lifecycle_Configuration proves the deletion completed"
    )
    reject_delete_lifecycle_registry(
        causal_delete_lifecycle_reconciliation,
        "causal reconciliation",
    )
    cross_delete_lifecycle_symbol = copy.deepcopy(registry)
    cross_delete_lifecycle_symbol.operations["DeleteBucketLifecycle"][
        "ada_symbols"
    ][0] = "Prepare_Delete_Bucket_Encryption"
    reject_delete_lifecycle_registry(
        cross_delete_lifecycle_symbol,
        "cross-operation symbol",
    )
    delete_lifecycle_qualification, delete_lifecycle_commands = (
        s3_operation.qualification_plan(registry, ["DeleteBucketLifecycle"])
    )
    assert delete_lifecycle_qualification == "delete_bucket_lifecycle"
    assert delete_lifecycle_commands[:5] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-delete-bucket-configurations-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_delete_bucket_configurations_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert delete_lifecycle_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-bucket-lifecycle-gnatdoc",
        "--operation",
        "DeleteBucketLifecycle",
    ]
    assert delete_lifecycle_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry,
            ["DeleteBucketLifecycle", "DeleteBucketLifecycle"],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate DeleteBucketLifecycle lane was accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            ["DeleteBucketLifecycle", "DeleteBucketEncryption"],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError(
            "mixed DeleteBucketLifecycle lane was accepted"
        )
    delete_replication_certainty = (
        "only a complete validated 204 response with an exactly empty body "
        "reports Bucket_Replication_Mutation_Completed; an exact recognized "
        "non-mutating rejection or definite non-admission reports "
        "Bucket_Replication_Mutation_Definitely_Not_Applied; pre-admission "
        "cancellation reports "
        "Bucket_Replication_Mutation_Cancelled_Before_Admission; possible or "
        "incomplete admission, retryable responses, and malformed or "
        "oversized responses report "
        "Bucket_Replication_Mutation_Outcome_Unknown; no automatic replay"
    )
    delete_replication_reconciliation = (
        "caller-selected Get_Replication_Configuration may observe the "
        "current replication configuration or exact "
        "ReplicationConfigurationNotFoundError before a retry, but does not "
        "prove that the lost deletion caused the observed absence or upgrade "
        "mutation certainty; no automatic replay"
    )

    def assert_delete_replication_registry(candidate):
        entry = candidate.operations["DeleteBucketReplication"]
        assert entry.get("public_name") == "Delete_Replication"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "delete_bucket_replication"
        assert entry.get("codec") == "empty_response"
        assert entry.get("certainty") == delete_replication_certainty
        assert entry.get("reconciliation") == delete_replication_reconciliation
        assert entry.get("coverage") == {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        }
        assert entry.get("ada_symbols") == [
            "Prepare_Delete_Bucket_Replication",
            "Execute_Delete_Bucket_Replication",
            "Delete_Bucket_Replication_Operation",
            "Delete_Replication",
            "Finish",
        ]
        assert "removes the bucket replication configuration" in (
            entry["absence"]
        )
        assert "exact HTTP 204" in entry["exclusions"][2]
        assert "does not establish causation" in entry["exclusions"][3]
        assert (
            candidate.qualification["delete_bucket_replication"][0][-1]
            == "tools/verify-delete-bucket-configurations-preparation.py"
        )

    def reject_delete_replication_registry(candidate, label):
        try:
            assert_delete_replication_registry(candidate)
        except (AssertionError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} DeleteBucketReplication registry accepted"
        )

    assert_delete_replication_registry(registry)
    missing_delete_replication_name = copy.deepcopy(registry)
    del missing_delete_replication_name.operations[
        "DeleteBucketReplication"
    ]["public_name"]
    reject_delete_replication_registry(
        missing_delete_replication_name,
        "missing public name",
    )
    wrong_delete_replication_name = copy.deepcopy(registry)
    wrong_delete_replication_name.operations["DeleteBucketReplication"][
        "public_name"
    ] = "Delete_Lifecycle"
    reject_delete_replication_registry(
        wrong_delete_replication_name,
        "wrong public name",
    )
    broadened_delete_replication_success = copy.deepcopy(registry)
    broadened_delete_replication_success.operations[
        "DeleteBucketReplication"
    ]["certainty"] = delete_replication_certainty.replace(
        "validated 204", "validated 200 or 204"
    )
    reject_delete_replication_registry(
        broadened_delete_replication_success,
        "broadened success status",
    )
    causal_delete_replication_reconciliation = copy.deepcopy(registry)
    causal_delete_replication_reconciliation.operations[
        "DeleteBucketReplication"
    ]["reconciliation"] = (
        "Get_Replication_Configuration proves the deletion completed"
    )
    reject_delete_replication_registry(
        causal_delete_replication_reconciliation,
        "causal reconciliation",
    )
    cross_delete_replication_symbol = copy.deepcopy(registry)
    cross_delete_replication_symbol.operations["DeleteBucketReplication"][
        "ada_symbols"
    ][0] = "Prepare_Delete_Bucket_Lifecycle"
    reject_delete_replication_registry(
        cross_delete_replication_symbol,
        "cross-operation symbol",
    )
    delete_replication_qualification, delete_replication_commands = (
        s3_operation.qualification_plan(registry, ["DeleteBucketReplication"])
    )
    assert delete_replication_qualification == "delete_bucket_replication"
    assert delete_replication_commands[:5] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-delete-bucket-configurations-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_delete_bucket_configurations_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert delete_replication_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-bucket-replication-gnatdoc",
        "--operation",
        "DeleteBucketReplication",
    ]
    assert delete_replication_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry,
            ["DeleteBucketReplication", "DeleteBucketReplication"],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate DeleteBucketReplication lane was accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            ["DeleteBucketReplication", "DeleteBucketLifecycle"],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError(
            "mixed DeleteBucketReplication lane was accepted"
        )
    delete_website_certainty = (
        "only a complete validated 204 response with an exactly empty body "
        "reports Bucket_Website_Mutation_Completed; an exact recognized "
        "non-mutating rejection or definite non-admission reports "
        "Bucket_Website_Mutation_Definitely_Not_Applied; pre-admission "
        "cancellation reports "
        "Bucket_Website_Mutation_Cancelled_Before_Admission; possible or "
        "incomplete admission, retryable responses, and malformed or "
        "oversized responses report Bucket_Website_Mutation_Outcome_Unknown; "
        "no automatic replay"
    )
    delete_website_reconciliation = (
        "caller-selected Get_Website may observe the current website "
        "configuration or exact NoSuchWebsiteConfiguration before a retry, "
        "but does not prove that the lost deletion caused the observed "
        "absence or upgrade mutation certainty; no automatic replay"
    )

    def assert_delete_website_registry(candidate):
        entry = candidate.operations["DeleteBucketWebsite"]
        assert entry.get("public_name") == "Delete_Website"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "delete_bucket_website"
        assert entry.get("codec") == "empty_response"
        assert entry.get("certainty") == delete_website_certainty
        assert entry.get("reconciliation") == delete_website_reconciliation
        assert entry.get("coverage") == {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        }
        assert entry.get("ada_symbols") == [
            "Prepare_Delete_Bucket_Website",
            "Execute_Delete_Bucket_Website",
            "Delete_Bucket_Website_Operation",
            "Delete_Website",
            "Finish",
        ]
        assert "removes the bucket website configuration" in entry["absence"]
        assert "exact HTTP 204" in entry["exclusions"][2]
        assert "previously present" in entry["exclusions"][3]
        assert "does not establish causation" in entry["exclusions"][4]
        assert (
            candidate.qualification["delete_bucket_website"][0][-1]
            == "tools/verify-delete-bucket-configurations-preparation.py"
        )

    def reject_delete_website_registry(candidate, label):
        try:
            assert_delete_website_registry(candidate)
        except (AssertionError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} DeleteBucketWebsite registry accepted"
        )

    assert_delete_website_registry(registry)
    missing_delete_website_name = copy.deepcopy(registry)
    del missing_delete_website_name.operations["DeleteBucketWebsite"][
        "public_name"
    ]
    reject_delete_website_registry(
        missing_delete_website_name,
        "missing public name",
    )
    wrong_delete_website_name = copy.deepcopy(registry)
    wrong_delete_website_name.operations["DeleteBucketWebsite"][
        "public_name"
    ] = "Delete_Replication"
    reject_delete_website_registry(
        wrong_delete_website_name,
        "wrong public name",
    )
    broadened_delete_website_success = copy.deepcopy(registry)
    broadened_delete_website_success.operations["DeleteBucketWebsite"][
        "certainty"
    ] = delete_website_certainty.replace(
        "validated 204", "validated 200 or 204"
    )
    reject_delete_website_registry(
        broadened_delete_website_success,
        "broadened success status",
    )
    causal_delete_website_reconciliation = copy.deepcopy(registry)
    causal_delete_website_reconciliation.operations["DeleteBucketWebsite"][
        "reconciliation"
    ] = "Get_Website proves the deletion completed"
    reject_delete_website_registry(
        causal_delete_website_reconciliation,
        "causal reconciliation",
    )
    cross_delete_website_symbol = copy.deepcopy(registry)
    cross_delete_website_symbol.operations["DeleteBucketWebsite"][
        "ada_symbols"
    ][0] = "Prepare_Delete_Bucket_Replication"
    reject_delete_website_registry(
        cross_delete_website_symbol,
        "cross-operation symbol",
    )
    delete_website_qualification, delete_website_commands = (
        s3_operation.qualification_plan(registry, ["DeleteBucketWebsite"])
    )
    assert delete_website_qualification == "delete_bucket_website"
    assert delete_website_commands[:5] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-delete-bucket-configurations-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_delete_bucket_configurations_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert delete_website_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-bucket-website-gnatdoc",
        "--operation",
        "DeleteBucketWebsite",
    ]
    assert delete_website_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry,
            ["DeleteBucketWebsite", "DeleteBucketWebsite"],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate DeleteBucketWebsite lane was accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            ["DeleteBucketWebsite", "DeleteBucketReplication"],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError(
            "mixed DeleteBucketWebsite lane was accepted"
        )
    delete_analytics_certainty = (
        "only a complete validated 204 response with an exactly empty body "
        "reports Bucket_Analytics_Configuration_Mutation_Completed; an exact "
        "recognized non-mutating rejection or definite non-admission reports "
        "Bucket_Analytics_Configuration_Mutation_Definitely_Not_Applied; "
        "pre-admission cancellation reports "
        "Bucket_Analytics_Configuration_Mutation_Cancelled_Before_Admission; "
        "possible or incomplete admission, retryable responses, and malformed "
        "or oversized responses report "
        "Bucket_Analytics_Configuration_Mutation_Outcome_Unknown; no "
        "automatic replay"
    )
    delete_analytics_reconciliation = (
        "caller-selected Get_Analytics_Configuration for the same identifier "
        "may observe the current configuration or exact NoSuchConfiguration "
        "before a retry, but does not prove that the lost deletion caused the "
        "observed absence or upgrade mutation certainty; no automatic replay"
    )

    def assert_delete_analytics_registry(candidate):
        entry = candidate.operations["DeleteBucketAnalyticsConfiguration"]
        assert entry.get("public_name") == "Delete_Analytics_Configuration"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "delete_bucket_analytics"
        assert entry.get("codec") == "empty_response"
        assert entry.get("certainty") == delete_analytics_certainty
        assert entry.get("reconciliation") == delete_analytics_reconciliation
        assert entry.get("coverage") == {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        }
        assert entry.get("ada_symbols") == [
            "Prepare_Delete_Bucket_Analytics_Configuration",
            "Execute_Delete_Bucket_Analytics_Configuration",
            "Delete_Bucket_Analytics_Operation",
            "Delete_Analytics_Configuration",
            "Finish",
        ]
        assert "removes the selected bucket analytics" in entry["absence"]
        assert "exact HTTP 204" in entry["exclusions"][2]
        assert "previously present" in entry["exclusions"][3]
        assert "does not establish causation" in entry["exclusions"][4]
        assert (
            candidate.qualification["delete_bucket_analytics"][0][-1]
            == "tools/verify-delete-bucket-configurations-preparation.py"
        )

    def reject_delete_analytics_registry(candidate, label):
        try:
            assert_delete_analytics_registry(candidate)
        except (AssertionError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} DeleteBucketAnalyticsConfiguration registry accepted"
        )

    assert_delete_analytics_registry(registry)
    missing_delete_analytics_name = copy.deepcopy(registry)
    del missing_delete_analytics_name.operations[
        "DeleteBucketAnalyticsConfiguration"
    ]["public_name"]
    reject_delete_analytics_registry(
        missing_delete_analytics_name,
        "missing public name",
    )
    wrong_delete_analytics_name = copy.deepcopy(registry)
    wrong_delete_analytics_name.operations[
        "DeleteBucketAnalyticsConfiguration"
    ]["public_name"] = "Delete_Website"
    reject_delete_analytics_registry(
        wrong_delete_analytics_name,
        "wrong public name",
    )
    broadened_delete_analytics_success = copy.deepcopy(registry)
    broadened_delete_analytics_success.operations[
        "DeleteBucketAnalyticsConfiguration"
    ]["certainty"] = delete_analytics_certainty.replace(
        "validated 204", "validated 200 or 204"
    )
    reject_delete_analytics_registry(
        broadened_delete_analytics_success,
        "broadened success status",
    )
    causal_delete_analytics_reconciliation = copy.deepcopy(registry)
    causal_delete_analytics_reconciliation.operations[
        "DeleteBucketAnalyticsConfiguration"
    ]["reconciliation"] = (
        "Get_Analytics_Configuration proves the deletion completed"
    )
    reject_delete_analytics_registry(
        causal_delete_analytics_reconciliation,
        "causal reconciliation",
    )
    cross_delete_analytics_symbol = copy.deepcopy(registry)
    cross_delete_analytics_symbol.operations[
        "DeleteBucketAnalyticsConfiguration"
    ]["ada_symbols"][0] = "Prepare_Delete_Bucket_Website"
    reject_delete_analytics_registry(
        cross_delete_analytics_symbol,
        "cross-operation symbol",
    )
    delete_analytics_qualification, delete_analytics_commands = (
        s3_operation.qualification_plan(
            registry, ["DeleteBucketAnalyticsConfiguration"]
        )
    )
    assert delete_analytics_qualification == "delete_bucket_analytics"
    assert delete_analytics_commands[:5] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-delete-bucket-configurations-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_delete_bucket_configurations_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert delete_analytics_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-bucket-analytics-gnatdoc",
        "--operation",
        "DeleteBucketAnalyticsConfiguration",
    ]
    assert delete_analytics_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "DeleteBucketAnalyticsConfiguration",
                "DeleteBucketAnalyticsConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate DeleteBucketAnalyticsConfiguration lane was accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            ["DeleteBucketAnalyticsConfiguration", "DeleteBucketWebsite"],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError(
            "mixed DeleteBucketAnalyticsConfiguration lane was accepted"
        )
    delete_intelligent_tiering_certainty = (
        "only a complete validated 204 response with an exactly empty body "
        "reports Intelligent_Tiering_Mutation_Completed; an exact recognized "
        "non-mutating rejection or definite non-admission reports "
        "Intelligent_Tiering_Mutation_Definitely_Not_Applied; pre-admission "
        "cancellation reports Intelligent_Tiering_Mutation_Cancelled_Before_"
        "Admission; possible or incomplete admission, retryable responses, "
        "and malformed or oversized responses report "
        "Intelligent_Tiering_Mutation_Outcome_Unknown; no automatic replay"
    )
    delete_intelligent_tiering_reconciliation = (
        "caller-selected Get_Intelligent_Tiering_Configuration for the same "
        "identifier may observe the current configuration or exact "
        "NoSuchConfiguration before a retry, but does not prove that the "
        "lost deletion caused the observed absence or upgrade mutation "
        "certainty; no automatic replay"
    )

    def assert_delete_intelligent_tiering_registry(candidate):
        entry = candidate.operations[
            "DeleteBucketIntelligentTieringConfiguration"
        ]
        assert (
            entry.get("public_name")
            == "Delete_Intelligent_Tiering_Configuration"
        )
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert (
            entry.get("qualification")
            == "delete_bucket_intelligent_tiering"
        )
        assert entry.get("codec") == "empty_response"
        assert entry.get("certainty") == delete_intelligent_tiering_certainty
        assert (
            entry.get("reconciliation")
            == delete_intelligent_tiering_reconciliation
        )
        assert entry.get("coverage") == {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        }
        assert entry.get("ada_symbols") == [
            "Prepare_Delete_Bucket_Intelligent_Tiering_Configuration",
            "Execute_Delete_Bucket_Intelligent_Tiering_Configuration",
            "Delete_Bucket_Tiering_Operation",
            "Delete_Intelligent_Tiering_Configuration",
            "Finish",
        ]
        assert "removes the selected bucket intelligent-tiering" in entry[
            "absence"
        ]
        assert "exact HTTP 204" in entry["exclusions"][2]
        assert "previously present" in entry["exclusions"][3]
        assert "does not establish causation" in entry["exclusions"][4]
        assert (
            candidate.qualification[
                "delete_bucket_intelligent_tiering"
            ][0][-1]
            == "tools/verify-delete-bucket-configurations-preparation.py"
        )

    def reject_delete_intelligent_tiering_registry(candidate, label):
        try:
            assert_delete_intelligent_tiering_registry(candidate)
        except (AssertionError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} DeleteBucketIntelligentTieringConfiguration registry "
            "accepted"
        )

    assert_delete_intelligent_tiering_registry(registry)
    missing_delete_intelligent_tiering_name = copy.deepcopy(registry)
    del missing_delete_intelligent_tiering_name.operations[
        "DeleteBucketIntelligentTieringConfiguration"
    ]["public_name"]
    reject_delete_intelligent_tiering_registry(
        missing_delete_intelligent_tiering_name,
        "missing public name",
    )
    wrong_delete_intelligent_tiering_name = copy.deepcopy(registry)
    wrong_delete_intelligent_tiering_name.operations[
        "DeleteBucketIntelligentTieringConfiguration"
    ]["public_name"] = "Delete_Analytics_Configuration"
    reject_delete_intelligent_tiering_registry(
        wrong_delete_intelligent_tiering_name,
        "wrong public name",
    )
    broadened_delete_intelligent_tiering_success = copy.deepcopy(registry)
    broadened_delete_intelligent_tiering_success.operations[
        "DeleteBucketIntelligentTieringConfiguration"
    ]["certainty"] = delete_intelligent_tiering_certainty.replace(
        "validated 204", "validated 200 or 204"
    )
    reject_delete_intelligent_tiering_registry(
        broadened_delete_intelligent_tiering_success,
        "broadened success status",
    )
    causal_delete_intelligent_tiering_reconciliation = copy.deepcopy(
        registry
    )
    causal_delete_intelligent_tiering_reconciliation.operations[
        "DeleteBucketIntelligentTieringConfiguration"
    ]["reconciliation"] = (
        "Get_Intelligent_Tiering_Configuration proves deletion completed"
    )
    reject_delete_intelligent_tiering_registry(
        causal_delete_intelligent_tiering_reconciliation,
        "causal reconciliation",
    )
    cross_delete_intelligent_tiering_symbol = copy.deepcopy(registry)
    cross_delete_intelligent_tiering_symbol.operations[
        "DeleteBucketIntelligentTieringConfiguration"
    ]["ada_symbols"][0] = "Prepare_Delete_Bucket_Analytics_Configuration"
    reject_delete_intelligent_tiering_registry(
        cross_delete_intelligent_tiering_symbol,
        "cross-operation symbol",
    )
    (
        delete_intelligent_tiering_qualification,
        delete_intelligent_tiering_commands,
    ) = s3_operation.qualification_plan(
        registry, ["DeleteBucketIntelligentTieringConfiguration"]
    )
    assert (
        delete_intelligent_tiering_qualification
        == "delete_bucket_intelligent_tiering"
    )
    assert delete_intelligent_tiering_commands[:5] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-delete-bucket-configurations-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_delete_bucket_configurations_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert delete_intelligent_tiering_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-bucket-intelligent-tiering-gnatdoc",
        "--operation",
        "DeleteBucketIntelligentTieringConfiguration",
    ]
    assert delete_intelligent_tiering_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "DeleteBucketIntelligentTieringConfiguration",
                "DeleteBucketIntelligentTieringConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate DeleteBucketIntelligentTieringConfiguration lane was "
            "accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "DeleteBucketIntelligentTieringConfiguration",
                "DeleteBucketAnalyticsConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError(
            "mixed DeleteBucketIntelligentTieringConfiguration lane was "
            "accepted"
        )
    delete_inventory_certainty = (
        "only a complete validated 204 response with an exactly empty body "
        "reports Bucket_Inventory_Configuration_Mutation_Completed; an exact "
        "recognized non-mutating rejection or definite non-admission reports "
        "Bucket_Inventory_Configuration_Mutation_Definitely_Not_Applied; "
        "pre-admission cancellation reports "
        "Bucket_Inventory_Configuration_Mutation_Cancelled_Before_Admission; "
        "possible or incomplete admission, retryable responses, and malformed "
        "or oversized responses report "
        "Bucket_Inventory_Configuration_Mutation_Outcome_Unknown; no "
        "automatic replay"
    )
    delete_inventory_reconciliation = (
        "caller-selected Get_Inventory_Configuration for the same identifier "
        "may observe the current configuration or exact NoSuchConfiguration "
        "before a retry, but does not prove that the lost deletion caused the "
        "observed absence or upgrade mutation certainty; no automatic replay"
    )

    def assert_delete_inventory_registry(candidate):
        entry = candidate.operations["DeleteBucketInventoryConfiguration"]
        assert entry.get("public_name") == "Delete_Inventory_Configuration"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "delete_bucket_inventory"
        assert entry.get("codec") == "empty_response"
        assert entry.get("certainty") == delete_inventory_certainty
        assert entry.get("reconciliation") == delete_inventory_reconciliation
        assert entry.get("coverage") == {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        }
        assert entry.get("ada_symbols") == [
            "Prepare_Delete_Bucket_Inventory_Configuration",
            "Execute_Delete_Bucket_Inventory_Configuration",
            "Delete_Bucket_Inventory_Configuration_Operation",
            "Delete_Inventory_Configuration",
            "Finish",
        ]
        assert "removes the selected bucket inventory" in entry["absence"]
        assert "exact HTTP 204" in entry["exclusions"][2]
        assert "previously present" in entry["exclusions"][3]
        assert "does not establish causation" in entry["exclusions"][4]
        assert (
            candidate.qualification["delete_bucket_inventory"][0][-1]
            == "tools/verify-delete-bucket-configurations-preparation.py"
        )

    def reject_delete_inventory_registry(candidate, label):
        try:
            assert_delete_inventory_registry(candidate)
        except (AssertionError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} DeleteBucketInventoryConfiguration registry accepted"
        )

    assert_delete_inventory_registry(registry)
    missing_delete_inventory_name = copy.deepcopy(registry)
    del missing_delete_inventory_name.operations[
        "DeleteBucketInventoryConfiguration"
    ]["public_name"]
    reject_delete_inventory_registry(
        missing_delete_inventory_name,
        "missing public name",
    )
    wrong_delete_inventory_name = copy.deepcopy(registry)
    wrong_delete_inventory_name.operations[
        "DeleteBucketInventoryConfiguration"
    ]["public_name"] = "Delete_Intelligent_Tiering_Configuration"
    reject_delete_inventory_registry(
        wrong_delete_inventory_name,
        "wrong public name",
    )
    broadened_delete_inventory_success = copy.deepcopy(registry)
    broadened_delete_inventory_success.operations[
        "DeleteBucketInventoryConfiguration"
    ]["certainty"] = delete_inventory_certainty.replace(
        "validated 204", "validated 200 or 204"
    )
    reject_delete_inventory_registry(
        broadened_delete_inventory_success,
        "broadened success status",
    )
    causal_delete_inventory_reconciliation = copy.deepcopy(registry)
    causal_delete_inventory_reconciliation.operations[
        "DeleteBucketInventoryConfiguration"
    ]["reconciliation"] = (
        "Get_Inventory_Configuration proves deletion completed"
    )
    reject_delete_inventory_registry(
        causal_delete_inventory_reconciliation,
        "causal reconciliation",
    )
    cross_delete_inventory_symbol = copy.deepcopy(registry)
    cross_delete_inventory_symbol.operations[
        "DeleteBucketInventoryConfiguration"
    ]["ada_symbols"][0] = (
        "Prepare_Delete_Bucket_Intelligent_Tiering_Configuration"
    )
    reject_delete_inventory_registry(
        cross_delete_inventory_symbol,
        "cross-operation symbol",
    )
    delete_inventory_qualification, delete_inventory_commands = (
        s3_operation.qualification_plan(
            registry, ["DeleteBucketInventoryConfiguration"]
        )
    )
    assert delete_inventory_qualification == "delete_bucket_inventory"
    assert delete_inventory_commands[:5] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-delete-bucket-configurations-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_delete_bucket_configurations_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert delete_inventory_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-bucket-inventory-gnatdoc",
        "--operation",
        "DeleteBucketInventoryConfiguration",
    ]
    assert delete_inventory_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "DeleteBucketInventoryConfiguration",
                "DeleteBucketInventoryConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate DeleteBucketInventoryConfiguration lane was accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "DeleteBucketInventoryConfiguration",
                "DeleteBucketIntelligentTieringConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError(
            "mixed DeleteBucketInventoryConfiguration lane was accepted"
        )
    delete_metadata_certainty = (
        "only a complete validated 204 response with an exactly empty body "
        "reports Bucket_Metadata_Configuration_Mutation_Completed; an exact "
        "recognized non-mutating rejection or definite non-admission reports "
        "Bucket_Metadata_Configuration_Mutation_Definitely_Not_Applied; "
        "pre-admission cancellation reports "
        "Bucket_Metadata_Configuration_Mutation_Cancelled_Before_Admission; "
        "possible or incomplete admission, retryable responses, and malformed "
        "or oversized responses report "
        "Bucket_Metadata_Configuration_Mutation_Outcome_Unknown; no automatic "
        "replay"
    )
    delete_metadata_reconciliation = (
        "caller-selected Get_Metadata_Configuration may observe the current "
        "modeled configuration response or structured rejection before a "
        "retry, but does not prove that the lost deletion caused the "
        "observation or upgrade mutation certainty; no automatic replay"
    )

    def assert_delete_metadata_registry(candidate):
        entry = candidate.operations["DeleteBucketMetadataConfiguration"]
        assert entry.get("public_name") == "Delete_Metadata_Configuration"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "delete_bucket_metadata"
        assert entry.get("codec") == "empty_response"
        assert entry.get("certainty") == delete_metadata_certainty
        assert entry.get("reconciliation") == delete_metadata_reconciliation
        assert entry.get("coverage") == {
            "backend": "missing",
            "client": "covered",
            "server": "missing",
            "corpus": "covered",
        }
        assert entry.get("ada_symbols") == [
            "Prepare_Delete_Bucket_Metadata_Configuration",
            "Execute_Delete_Bucket_Metadata_Configuration",
            "Delete_Bucket_Metadata_Operation",
            "Delete_Metadata_Configuration",
            "Finish",
        ]
        assert "removes the bucket metadata" in entry["absence"]
        assert "exact HTTP 204" in entry["exclusions"][2]
        assert "previously present" in entry["exclusions"][3]
        assert "does not establish causation" in entry["exclusions"][4]
        assert (
            candidate.qualification["delete_bucket_metadata"][0][-1]
            == "tools/verify-delete-bucket-configurations-preparation.py"
        )

    def reject_delete_metadata_registry(candidate, label):
        try:
            assert_delete_metadata_registry(candidate)
        except (AssertionError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} DeleteBucketMetadataConfiguration registry accepted"
        )

    assert_delete_metadata_registry(registry)
    missing_delete_metadata_name = copy.deepcopy(registry)
    del missing_delete_metadata_name.operations[
        "DeleteBucketMetadataConfiguration"
    ]["public_name"]
    reject_delete_metadata_registry(
        missing_delete_metadata_name,
        "missing public name",
    )
    wrong_delete_metadata_name = copy.deepcopy(registry)
    wrong_delete_metadata_name.operations[
        "DeleteBucketMetadataConfiguration"
    ]["public_name"] = "Delete_Inventory_Configuration"
    reject_delete_metadata_registry(
        wrong_delete_metadata_name,
        "wrong public name",
    )
    broadened_delete_metadata_success = copy.deepcopy(registry)
    broadened_delete_metadata_success.operations[
        "DeleteBucketMetadataConfiguration"
    ]["certainty"] = delete_metadata_certainty.replace(
        "validated 204", "validated 200 or 204"
    )
    reject_delete_metadata_registry(
        broadened_delete_metadata_success,
        "broadened success status",
    )
    causal_delete_metadata_reconciliation = copy.deepcopy(registry)
    causal_delete_metadata_reconciliation.operations[
        "DeleteBucketMetadataConfiguration"
    ]["reconciliation"] = (
        "Get_Metadata_Configuration proves deletion completed"
    )
    reject_delete_metadata_registry(
        causal_delete_metadata_reconciliation,
        "causal reconciliation",
    )
    cross_delete_metadata_symbol = copy.deepcopy(registry)
    cross_delete_metadata_symbol.operations[
        "DeleteBucketMetadataConfiguration"
    ]["ada_symbols"][0] = "Prepare_Delete_Bucket_Inventory_Configuration"
    reject_delete_metadata_registry(
        cross_delete_metadata_symbol,
        "cross-operation symbol",
    )
    delete_metadata_qualification, delete_metadata_commands = (
        s3_operation.qualification_plan(
            registry, ["DeleteBucketMetadataConfiguration"]
        )
    )
    assert delete_metadata_qualification == "delete_bucket_metadata"
    assert delete_metadata_commands[:5] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-delete-bucket-configurations-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_delete_bucket_configurations_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert delete_metadata_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-bucket-metadata-gnatdoc",
        "--operation",
        "DeleteBucketMetadataConfiguration",
    ]
    assert delete_metadata_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "DeleteBucketMetadataConfiguration",
                "DeleteBucketMetadataConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate DeleteBucketMetadataConfiguration lane was accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "DeleteBucketMetadataConfiguration",
                "DeleteBucketInventoryConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError(
            "mixed DeleteBucketMetadataConfiguration lane was accepted"
        )
    delete_metadata_table_certainty = (
        "only a complete validated 204 response with an exactly empty body "
        "reports Bucket_Metadata_Table_Mutation_Completed; an exact "
        "recognized non-mutating rejection or definite non-admission reports "
        "Bucket_Metadata_Table_Mutation_Definitely_Not_Applied; pre-admission "
        "cancellation reports "
        "Bucket_Metadata_Table_Mutation_Cancelled_Before_Admission; possible "
        "or incomplete admission, retryable responses, and malformed or "
        "oversized responses report "
        "Bucket_Metadata_Table_Mutation_Outcome_Unknown; no automatic replay"
    )
    delete_metadata_table_reconciliation = (
        "caller-selected Get_Metadata_Table_Configuration may observe the "
        "current modeled configuration response or structured rejection "
        "before a retry, but does not prove that the lost deletion caused the "
        "observation or upgrade mutation certainty; no automatic replay"
    )

    def assert_delete_metadata_table_registry(candidate):
        entry = candidate.operations[
            "DeleteBucketMetadataTableConfiguration"
        ]
        assert (
            entry.get("public_name")
            == "Delete_Metadata_Table_Configuration"
        )
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "delete_bucket_metadata_table"
        assert entry.get("codec") == "empty_response"
        assert entry.get("certainty") == delete_metadata_table_certainty
        assert (
            entry.get("reconciliation")
            == delete_metadata_table_reconciliation
        )
        assert entry.get("coverage") == {
            "backend": "missing",
            "client": "covered",
            "server": "missing",
            "corpus": "covered",
        }
        assert entry.get("ada_symbols") == [
            "Prepare_Delete_Bucket_Metadata_Table_Configuration",
            "Execute_Delete_Bucket_Metadata_Table_Configuration",
            "Delete_Bucket_Metadata_Table_Operation",
            "Delete_Metadata_Table_Configuration",
            "Finish",
        ]
        assert "removes the bucket metadata-table" in entry["absence"]
        assert "exact HTTP 204" in entry["exclusions"][2]
        assert "previously present" in entry["exclusions"][3]
        assert "does not establish causation" in entry["exclusions"][4]
        assert (
            candidate.qualification["delete_bucket_metadata_table"][0][-1]
            == "tools/verify-delete-bucket-configurations-preparation.py"
        )

    def reject_delete_metadata_table_registry(candidate, label):
        try:
            assert_delete_metadata_table_registry(candidate)
        except (AssertionError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} DeleteBucketMetadataTableConfiguration registry "
            "accepted"
        )

    assert_delete_metadata_table_registry(registry)
    missing_delete_metadata_table_name = copy.deepcopy(registry)
    del missing_delete_metadata_table_name.operations[
        "DeleteBucketMetadataTableConfiguration"
    ]["public_name"]
    reject_delete_metadata_table_registry(
        missing_delete_metadata_table_name,
        "missing public name",
    )
    wrong_delete_metadata_table_name = copy.deepcopy(registry)
    wrong_delete_metadata_table_name.operations[
        "DeleteBucketMetadataTableConfiguration"
    ]["public_name"] = "Delete_Metadata_Configuration"
    reject_delete_metadata_table_registry(
        wrong_delete_metadata_table_name,
        "wrong public name",
    )
    broadened_delete_metadata_table_success = copy.deepcopy(registry)
    broadened_delete_metadata_table_success.operations[
        "DeleteBucketMetadataTableConfiguration"
    ]["certainty"] = delete_metadata_table_certainty.replace(
        "validated 204", "validated 200 or 204"
    )
    reject_delete_metadata_table_registry(
        broadened_delete_metadata_table_success,
        "broadened success status",
    )
    causal_delete_metadata_table_reconciliation = copy.deepcopy(registry)
    causal_delete_metadata_table_reconciliation.operations[
        "DeleteBucketMetadataTableConfiguration"
    ]["reconciliation"] = (
        "Get_Metadata_Table_Configuration proves deletion completed"
    )
    reject_delete_metadata_table_registry(
        causal_delete_metadata_table_reconciliation,
        "causal reconciliation",
    )
    cross_delete_metadata_table_symbol = copy.deepcopy(registry)
    cross_delete_metadata_table_symbol.operations[
        "DeleteBucketMetadataTableConfiguration"
    ]["ada_symbols"][0] = "Prepare_Delete_Bucket_Metadata_Configuration"
    reject_delete_metadata_table_registry(
        cross_delete_metadata_table_symbol,
        "cross-operation symbol",
    )
    delete_metadata_table_qualification, delete_metadata_table_commands = (
        s3_operation.qualification_plan(
            registry, ["DeleteBucketMetadataTableConfiguration"]
        )
    )
    assert (
        delete_metadata_table_qualification == "delete_bucket_metadata_table"
    )
    assert delete_metadata_table_commands[:5] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-delete-bucket-configurations-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_delete_bucket_configurations_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert delete_metadata_table_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-bucket-metadata-table-gnatdoc",
        "--operation",
        "DeleteBucketMetadataTableConfiguration",
    ]
    assert delete_metadata_table_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "DeleteBucketMetadataTableConfiguration",
                "DeleteBucketMetadataTableConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate DeleteBucketMetadataTableConfiguration lane was "
            "accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "DeleteBucketMetadataTableConfiguration",
                "DeleteBucketMetadataConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError(
            "mixed DeleteBucketMetadataTableConfiguration lane was accepted"
        )
    delete_metrics_certainty = (
        "only a complete validated 204 response with an exactly empty body "
        "reports Bucket_Metrics_Configuration_Mutation_Completed; an exact "
        "recognized non-mutating rejection or definite non-admission reports "
        "Bucket_Metrics_Configuration_Mutation_Definitely_Not_Applied; "
        "pre-admission cancellation reports "
        "Bucket_Metrics_Configuration_Mutation_Cancelled_Before_Admission; "
        "possible or incomplete admission, retryable responses, and malformed "
        "or oversized responses report "
        "Bucket_Metrics_Configuration_Mutation_Outcome_Unknown; no automatic "
        "replay"
    )
    delete_metrics_reconciliation = (
        "caller-selected Get_Metrics_Configuration for the same identifier "
        "may observe the current configuration or exact NoSuchConfiguration "
        "before a retry, but does not prove that the lost deletion caused the "
        "observed absence or upgrade mutation certainty; no automatic replay"
    )

    def assert_delete_metrics_registry(candidate):
        entry = candidate.operations["DeleteBucketMetricsConfiguration"]
        assert entry.get("public_name") == "Delete_Metrics_Configuration"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "delete_bucket_metrics"
        assert entry.get("codec") == "empty_response"
        assert entry.get("certainty") == delete_metrics_certainty
        assert entry.get("reconciliation") == delete_metrics_reconciliation
        assert entry.get("coverage") == {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        }
        assert entry.get("ada_symbols") == [
            "Prepare_Delete_Bucket_Metrics_Configuration",
            "Execute_Delete_Bucket_Metrics_Configuration",
            "Delete_Bucket_Metrics_Operation",
            "Delete_Metrics_Configuration",
            "Finish",
        ]
        assert "removes the selected bucket metrics" in entry["absence"]
        assert "exact HTTP 204" in entry["exclusions"][2]
        assert "previously present" in entry["exclusions"][3]
        assert "does not establish causation" in entry["exclusions"][4]
        assert (
            candidate.qualification["delete_bucket_metrics"][0][-1]
            == "tools/verify-delete-bucket-configurations-preparation.py"
        )

    def reject_delete_metrics_registry(candidate, label):
        try:
            assert_delete_metrics_registry(candidate)
        except (AssertionError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} DeleteBucketMetricsConfiguration registry accepted"
        )

    assert_delete_metrics_registry(registry)
    missing_delete_metrics_name = copy.deepcopy(registry)
    del missing_delete_metrics_name.operations[
        "DeleteBucketMetricsConfiguration"
    ]["public_name"]
    reject_delete_metrics_registry(
        missing_delete_metrics_name, "missing public name"
    )
    wrong_delete_metrics_name = copy.deepcopy(registry)
    wrong_delete_metrics_name.operations[
        "DeleteBucketMetricsConfiguration"
    ]["public_name"] = "Delete_Analytics_Configuration"
    reject_delete_metrics_registry(
        wrong_delete_metrics_name, "wrong public name"
    )
    broadened_delete_metrics_success = copy.deepcopy(registry)
    broadened_delete_metrics_success.operations[
        "DeleteBucketMetricsConfiguration"
    ]["certainty"] = delete_metrics_certainty.replace(
        "validated 204", "validated 200 or 204"
    )
    reject_delete_metrics_registry(
        broadened_delete_metrics_success, "broadened success status"
    )
    causal_delete_metrics_reconciliation = copy.deepcopy(registry)
    causal_delete_metrics_reconciliation.operations[
        "DeleteBucketMetricsConfiguration"
    ]["reconciliation"] = "Get_Metrics_Configuration proves deletion"
    reject_delete_metrics_registry(
        causal_delete_metrics_reconciliation, "causal reconciliation"
    )
    cross_delete_metrics_symbol = copy.deepcopy(registry)
    cross_delete_metrics_symbol.operations[
        "DeleteBucketMetricsConfiguration"
    ]["ada_symbols"][0] = "Prepare_Delete_Bucket_Analytics_Configuration"
    reject_delete_metrics_registry(
        cross_delete_metrics_symbol, "cross-operation symbol"
    )
    delete_metrics_qualification, delete_metrics_commands = (
        s3_operation.qualification_plan(
            registry, ["DeleteBucketMetricsConfiguration"]
        )
    )
    assert delete_metrics_qualification == "delete_bucket_metrics"
    assert delete_metrics_commands[:5] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-delete-bucket-configurations-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_delete_bucket_configurations_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert delete_metrics_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-bucket-metrics-gnatdoc",
        "--operation",
        "DeleteBucketMetricsConfiguration",
    ]
    assert delete_metrics_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "DeleteBucketMetricsConfiguration",
                "DeleteBucketMetricsConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate DeleteBucketMetricsConfiguration lane was accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "DeleteBucketMetricsConfiguration",
                "DeleteBucketAnalyticsConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError(
            "mixed DeleteBucketMetricsConfiguration lane was accepted"
        )
    delete_ownership_controls_certainty = (
        "only a complete validated 204 response with an exactly empty body "
        "reports Bucket_Ownership_Controls_Mutation_Completed; an exact "
        "recognized non-mutating rejection or definite non-admission reports "
        "Bucket_Ownership_Controls_Mutation_Definitely_Not_Applied; "
        "pre-admission cancellation reports "
        "Bucket_Ownership_Controls_Mutation_Cancelled_Before_Admission; "
        "possible or incomplete admission, retryable responses, and malformed "
        "or oversized responses report "
        "Bucket_Ownership_Controls_Mutation_Outcome_Unknown; no automatic "
        "replay"
    )
    delete_ownership_controls_reconciliation = (
        "caller-selected Get_Ownership_Controls may observe the current "
        "ownership-controls configuration or exact "
        "OwnershipControlsNotFoundError before a retry, but does not prove "
        "that the lost deletion caused the observed absence or upgrade "
        "mutation certainty; no automatic replay"
    )

    def assert_delete_ownership_controls_registry(candidate):
        entry = candidate.operations["DeleteBucketOwnershipControls"]
        assert entry.get("public_name") == "Delete_Ownership_Controls"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == (
            "delete_bucket_ownership_controls"
        )
        assert entry.get("codec") == "empty_response"
        assert entry.get("certainty") == (
            delete_ownership_controls_certainty
        )
        assert entry.get("reconciliation") == (
            delete_ownership_controls_reconciliation
        )
        assert_bucket_control_backend_server(entry)
        assert entry.get("ada_symbols") == [
            "Prepare_Delete_Bucket_Ownership_Controls",
            "Execute_Delete_Bucket_Ownership_Controls",
            "Delete_Ownership_Controls_Operation",
            "Delete_Ownership_Controls",
            "Finish",
        ]
        assert "removes the bucket ownership-controls" in entry["absence"]
        assert "exact HTTP 204" in entry["exclusions"][2]
        assert "previously present" in entry["exclusions"][3]
        assert "does not establish causation" in entry["exclusions"][4]
        assert (
            candidate.qualification[
                "delete_bucket_ownership_controls"
            ][0][-1]
            == "tools/verify-delete-bucket-configurations-preparation.py"
        )

    def reject_delete_ownership_controls_registry(candidate, label):
        try:
            assert_delete_ownership_controls_registry(candidate)
        except (AssertionError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} DeleteBucketOwnershipControls registry accepted"
        )

    assert_delete_ownership_controls_registry(registry)
    missing_delete_ownership_controls_name = copy.deepcopy(registry)
    del missing_delete_ownership_controls_name.operations[
        "DeleteBucketOwnershipControls"
    ]["public_name"]
    reject_delete_ownership_controls_registry(
        missing_delete_ownership_controls_name, "missing public name"
    )
    wrong_delete_ownership_controls_name = copy.deepcopy(registry)
    wrong_delete_ownership_controls_name.operations[
        "DeleteBucketOwnershipControls"
    ]["public_name"] = "Delete_Metrics_Configuration"
    reject_delete_ownership_controls_registry(
        wrong_delete_ownership_controls_name, "wrong public name"
    )
    broadened_delete_ownership_controls_success = copy.deepcopy(registry)
    broadened_delete_ownership_controls_success.operations[
        "DeleteBucketOwnershipControls"
    ]["certainty"] = delete_ownership_controls_certainty.replace(
        "validated 204", "validated 200 or 204"
    )
    reject_delete_ownership_controls_registry(
        broadened_delete_ownership_controls_success,
        "broadened success status",
    )
    causal_delete_ownership_controls_reconciliation = copy.deepcopy(registry)
    causal_delete_ownership_controls_reconciliation.operations[
        "DeleteBucketOwnershipControls"
    ]["reconciliation"] = "Get_Ownership_Controls proves deletion"
    reject_delete_ownership_controls_registry(
        causal_delete_ownership_controls_reconciliation,
        "causal reconciliation",
    )
    missing_delete_ownership_controls_server = copy.deepcopy(registry)
    missing_delete_ownership_controls_server.operations[
        "DeleteBucketOwnershipControls"
    ]["coverage"]["server"] = "missing"
    reject_delete_ownership_controls_registry(
        missing_delete_ownership_controls_server,
        "missing server coverage",
    )
    cross_delete_ownership_controls_symbol = copy.deepcopy(registry)
    cross_delete_ownership_controls_symbol.operations[
        "DeleteBucketOwnershipControls"
    ]["ada_symbols"][0] = "Prepare_Delete_Bucket_Metrics_Configuration"
    reject_delete_ownership_controls_registry(
        cross_delete_ownership_controls_symbol, "cross-operation symbol"
    )
    delete_ownership_controls_qualification, ownership_controls_commands = (
        s3_operation.qualification_plan(
            registry, ["DeleteBucketOwnershipControls"]
        )
    )
    assert delete_ownership_controls_qualification == (
        "delete_bucket_ownership_controls"
    )
    assert ownership_controls_commands[:5] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-delete-bucket-configurations-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_delete_bucket_configurations_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert ownership_controls_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-bucket-ownership-controls-gnatdoc",
        "--operation",
        "DeleteBucketOwnershipControls",
    ]
    assert ownership_controls_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "DeleteBucketOwnershipControls",
                "DeleteBucketOwnershipControls",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate DeleteBucketOwnershipControls lane was accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "DeleteBucketOwnershipControls",
                "DeleteBucketMetricsConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError(
            "mixed DeleteBucketOwnershipControls lane was accepted"
        )
    delete_policy_certainty = (
        "only a complete validated 204 response with an exactly empty body "
        "reports Bucket_Policy_Mutation_Completed; an exact recognized "
        "non-mutating rejection or definite non-admission reports "
        "Bucket_Policy_Mutation_Definitely_Not_Applied; pre-admission "
        "cancellation reports Bucket_Policy_Mutation_Cancelled_Before_Admission; "
        "possible or incomplete admission, retryable responses, and malformed "
        "or oversized responses report Bucket_Policy_Mutation_Outcome_Unknown; "
        "no automatic replay"
    )
    delete_policy_reconciliation = (
        "caller-selected Get_Policy may observe the current bucket policy or "
        "exact NoSuchBucketPolicy before a retry, but does not prove that the "
        "lost deletion caused the observed absence or upgrade mutation "
        "certainty; no automatic replay"
    )

    def assert_delete_policy_registry(candidate):
        entry = candidate.operations["DeleteBucketPolicy"]
        assert entry.get("public_name") == "Delete_Policy"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "delete_bucket_policy"
        assert entry.get("codec") == "empty_response"
        assert entry.get("certainty") == delete_policy_certainty
        assert entry.get("reconciliation") == delete_policy_reconciliation
        assert entry.get("coverage") == {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        }
        assert entry.get("ada_symbols") == [
            "Prepare_Delete_Bucket_Policy",
            "Execute_Delete_Bucket_Policy",
            "Delete_Bucket_Policy_Operation",
            "Delete_Policy",
            "Finish",
        ]
        assert "removes the bucket policy" in entry["absence"]
        assert "exact HTTP 204" in entry["exclusions"][1]
        assert "previously present" in entry["exclusions"][2]
        assert "does not establish causation" in entry["exclusions"][3]
        assert (
            candidate.qualification["delete_bucket_policy"][0][-1]
            == "tools/verify-delete-bucket-configurations-preparation.py"
        )

    def reject_delete_policy_registry(candidate, label):
        try:
            assert_delete_policy_registry(candidate)
        except (AssertionError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} DeleteBucketPolicy registry accepted"
        )

    assert_delete_policy_registry(registry)
    missing_delete_policy_name = copy.deepcopy(registry)
    del missing_delete_policy_name.operations["DeleteBucketPolicy"][
        "public_name"
    ]
    reject_delete_policy_registry(
        missing_delete_policy_name, "missing public name"
    )
    wrong_delete_policy_name = copy.deepcopy(registry)
    wrong_delete_policy_name.operations["DeleteBucketPolicy"][
        "public_name"
    ] = "Delete_Ownership_Controls"
    reject_delete_policy_registry(
        wrong_delete_policy_name, "wrong public name"
    )
    broadened_delete_policy_success = copy.deepcopy(registry)
    broadened_delete_policy_success.operations["DeleteBucketPolicy"][
        "certainty"
    ] = delete_policy_certainty.replace(
        "validated 204", "validated 200 or 204"
    )
    reject_delete_policy_registry(
        broadened_delete_policy_success, "broadened success status"
    )
    causal_delete_policy_reconciliation = copy.deepcopy(registry)
    causal_delete_policy_reconciliation.operations["DeleteBucketPolicy"][
        "reconciliation"
    ] = "Get_Policy proves deletion"
    reject_delete_policy_registry(
        causal_delete_policy_reconciliation, "causal reconciliation"
    )
    cross_delete_policy_symbol = copy.deepcopy(registry)
    cross_delete_policy_symbol.operations["DeleteBucketPolicy"][
        "ada_symbols"
    ][0] = "Prepare_Delete_Bucket_Ownership_Controls"
    reject_delete_policy_registry(
        cross_delete_policy_symbol, "cross-operation symbol"
    )
    delete_policy_qualification, delete_policy_commands = (
        s3_operation.qualification_plan(registry, ["DeleteBucketPolicy"])
    )
    assert delete_policy_qualification == "delete_bucket_policy"
    assert delete_policy_commands[:6] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-delete-bucket-configurations-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_delete_bucket_configurations_corpus"],
        ["@tests", "./bin/s3_server_application_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert delete_policy_commands[6] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-bucket-policy-gnatdoc",
        "--operation",
        "DeleteBucketPolicy",
    ]
    assert delete_policy_commands[7:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry, ["DeleteBucketPolicy", "DeleteBucketPolicy"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate DeleteBucketPolicy lane was accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            ["DeleteBucketPolicy", "DeleteBucketOwnershipControls"],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError(
            "mixed DeleteBucketPolicy lane was accepted"
        )
    def assert_get_policy_registry(candidate):
        entry = candidate.operations["GetBucketPolicy"]
        assert entry.get("public_name") == "Get_Policy"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "get_bucket_policy"
        assert entry.get("codec") == "bounded_bytes_and_headers"
        assert entry.get("certainty") == "read_only"
        assert entry.get("reconciliation") == "not_applicable"
        assert entry.get("coverage") == {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        }
        assert entry.get("ada_symbols") == [
            "Prepare_Get_Bucket_Policy",
            "Execute_Get_Bucket_Policy",
            "Get_Bucket_Policy_Operation",
            "Get_Policy",
            "Finish",
        ]
        assert "exact bounded bucket-policy bytes" in entry["absence"]
        assert "NoSuchBucketPolicy" in entry["absence"]
        assert "exact HTTP 200" in entry["exclusions"][1]
        assert "distinct from NoSuchBucket" in entry["exclusions"][2]
        assert (
            candidate.qualification["get_bucket_policy"][0][-1]
            == "tools/verify-delete-bucket-configurations-preparation.py"
        )

    def reject_get_policy_registry(candidate, label):
        try:
            assert_get_policy_registry(candidate)
        except (AssertionError, KeyError, TypeError):
            return
        raise AssertionError(f"{label} GetBucketPolicy registry accepted")

    assert_get_policy_registry(registry)
    missing_get_policy_name = copy.deepcopy(registry)
    del missing_get_policy_name.operations["GetBucketPolicy"]["public_name"]
    reject_get_policy_registry(missing_get_policy_name, "missing public name")
    wrong_get_policy_name = copy.deepcopy(registry)
    wrong_get_policy_name.operations["GetBucketPolicy"][
        "public_name"
    ] = "Get_Policy_Status"
    reject_get_policy_registry(wrong_get_policy_name, "wrong public name")
    mutation_get_policy = copy.deepcopy(registry)
    mutation_get_policy.operations["GetBucketPolicy"][
        "certainty"
    ] = "outcome_unknown"
    reject_get_policy_registry(mutation_get_policy, "mutation certainty")
    reconciled_get_policy = copy.deepcopy(registry)
    reconciled_get_policy.operations["GetBucketPolicy"][
        "reconciliation"
    ] = "Get retries itself"
    reject_get_policy_registry(
        reconciled_get_policy, "invented reconciliation"
    )
    cross_get_policy_symbol = copy.deepcopy(registry)
    cross_get_policy_symbol.operations["GetBucketPolicy"][
        "ada_symbols"
    ][0] = "Prepare_Get_Bucket_Policy_Status"
    reject_get_policy_registry(
        cross_get_policy_symbol, "cross-operation symbol"
    )
    get_policy_qualification, get_policy_commands = (
        s3_operation.qualification_plan(registry, ["GetBucketPolicy"])
    )
    assert get_policy_qualification == "get_bucket_policy"
    assert get_policy_commands[:6] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-delete-bucket-configurations-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_get_bucket_controls_corpus"],
        ["@tests", "./bin/s3_server_application_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert get_policy_commands[6] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-get-bucket-policy-gnatdoc",
        "--operation",
        "GetBucketPolicy",
    ]
    assert get_policy_commands[7:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry, ["GetBucketPolicy", "GetBucketPolicy"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate GetBucketPolicy lane accepted")
    try:
        s3_operation.qualification_plan(
            registry, ["GetBucketPolicy", "DeleteBucketPolicy"]
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed GetBucketPolicy lane accepted")
    def assert_get_cors_registry(candidate):
        entry = candidate.operations["GetBucketCors"]
        assert entry.get("public_name") == "Get_CORS"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "get_bucket_cors"
        assert entry.get("certainty") == "read_only"
        assert entry.get("reconciliation") == "not_applicable"
        assert entry.get("coverage") == {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        }
        assert entry.get("ada_symbols") == [
            "Prepare_Get_Bucket_CORS",
            "Execute_Get_Bucket_CORS",
            "Get_Bucket_CORS_Operation",
            "Get_CORS",
            "Finish",
        ]
        assert "NoSuchCORSConfiguration" in entry["absence"]
        assert "NoSuchBucket" in entry["absence"]
        assert "exact HTTP 200" in entry["exclusions"][0]
        assert "browser CORS enforcement" in entry["exclusions"][3]
        assert (
            candidate.qualification["get_bucket_cors"][0][-1]
            == "tools/verify-get-bucket-cors-preparation.py"
        )

    def reject_get_cors_registry(candidate, label):
        try:
            assert_get_cors_registry(candidate)
        except (AssertionError, KeyError, TypeError):
            return
        raise AssertionError(f"{label} GetBucketCors registry accepted")

    assert_get_cors_registry(registry)
    missing_get_cors_name = copy.deepcopy(registry)
    del missing_get_cors_name.operations["GetBucketCors"]["public_name"]
    reject_get_cors_registry(missing_get_cors_name, "missing public name")
    wrong_get_cors_name = copy.deepcopy(registry)
    wrong_get_cors_name.operations["GetBucketCors"][
        "public_name"
    ] = "Get_Policy"
    reject_get_cors_registry(wrong_get_cors_name, "wrong public name")
    broadened_get_cors_success = copy.deepcopy(registry)
    broadened_get_cors_success.operations["GetBucketCors"][
        "exclusions"
    ][0] = "success accepts HTTP 200 or 204"
    reject_get_cors_registry(
        broadened_get_cors_success, "broadened success"
    )
    mutation_get_cors_certainty = copy.deepcopy(registry)
    mutation_get_cors_certainty.operations["GetBucketCors"][
        "certainty"
    ] = "Outcome_Unknown"
    reject_get_cors_registry(
        mutation_get_cors_certainty, "mutation certainty"
    )
    cross_get_cors_symbol = copy.deepcopy(registry)
    cross_get_cors_symbol.operations["GetBucketCors"][
        "ada_symbols"
    ][0] = "Prepare_Get_Bucket_Policy"
    reject_get_cors_registry(cross_get_cors_symbol, "cross-operation symbol")
    get_cors_qualification, get_cors_commands = (
        s3_operation.qualification_plan(registry, ["GetBucketCors"])
    )
    assert get_cors_qualification == "get_bucket_cors"
    assert get_cors_commands[:6] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-get-bucket-cors-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_get_bucket_cors_corpus"],
        ["@tests", "./bin/s3_server_application_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert get_cors_commands[6] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-get-bucket-cors-gnatdoc",
        "--operation",
        "GetBucketCors",
    ]
    assert get_cors_commands[7:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry, ["GetBucketCors", "GetBucketCors"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate GetBucketCors lane accepted")
    try:
        s3_operation.qualification_plan(
            registry, ["GetBucketCors", "GetBucketPolicy"]
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed GetBucketCors lane accepted")

    put_cors_certainty = (
        "only a complete validated 200 response with an empty or "
        "XML-whitespace body reports Bucket_CORS_Mutation_Completed; an "
        "exact recognized non-mutating rejection or definite non-admission "
        "reports Bucket_CORS_Mutation_Definitely_Not_Applied; pre-admission "
        "cancellation reports "
        "Bucket_CORS_Mutation_Cancelled_Before_Admission; "
        "possible or incomplete admission, retryable responses, and malformed "
        "or oversized responses report Bucket_CORS_Mutation_Outcome_Unknown; "
        "no automatic replay"
    )
    put_cors_reconciliation = (
        "caller-selected Get_CORS may observe the current exact CORS "
        "configuration or NoSuchCORSConfiguration before a retry, but does "
        "not prove that the lost replacement caused the observed state or "
        "upgrade mutation certainty; no automatic replay"
    )

    def assert_put_cors_registry(candidate):
        entry = candidate.operations["PutBucketCors"]
        assert entry.get("public_name") == "Set_CORS"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "put_bucket_cors"
        assert entry.get("certainty") == put_cors_certainty
        assert entry.get("reconciliation") == put_cors_reconciliation
        assert entry.get("coverage") == {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        }
        assert entry.get("ada_symbols") == [
            "Prepare_Put_Bucket_CORS",
            "Execute_Put_Bucket_CORS",
            "Put_Bucket_CORS_Operation",
            "Set_CORS",
            "Finish",
        ]
        assert "atomically replaces" in entry["absence"]
        assert "exact HTTP 200" in entry["exclusions"][0]
        assert "Content-MD5" in entry["exclusions"][1]
        assert "does not establish causation" in entry["exclusions"][3]
        assert (
            candidate.qualification["put_bucket_cors"][0][-1]
            == "tools/verify-put-bucket-cors-preparation.py"
        )

    def reject_put_cors_registry(candidate, label):
        try:
            assert_put_cors_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(f"{label} PutBucketCors registry accepted")

    assert_put_cors_registry(registry)
    missing_put_cors_name = copy.deepcopy(registry)
    del missing_put_cors_name.operations["PutBucketCors"]["public_name"]
    reject_put_cors_registry(missing_put_cors_name, "missing public name")
    wrong_put_cors_name = copy.deepcopy(registry)
    wrong_put_cors_name.operations["PutBucketCors"][
        "public_name"
    ] = "Get_CORS"
    reject_put_cors_registry(wrong_put_cors_name, "wrong public name")
    broadened_put_cors_success = copy.deepcopy(registry)
    broadened_put_cors_success.operations["PutBucketCors"][
        "exclusions"
    ][0] = "success accepts HTTP 200 or 204"
    reject_put_cors_registry(broadened_put_cors_success, "broadened success")
    causal_put_cors_reconciliation = copy.deepcopy(registry)
    causal_put_cors_reconciliation.operations["PutBucketCors"][
        "reconciliation"
    ] = "Get_CORS proves replacement"
    reject_put_cors_registry(
        causal_put_cors_reconciliation, "causal reconciliation"
    )
    cross_put_cors_symbol = copy.deepcopy(registry)
    cross_put_cors_symbol.operations["PutBucketCors"][
        "ada_symbols"
    ][0] = "Prepare_Get_Bucket_CORS"
    reject_put_cors_registry(cross_put_cors_symbol, "cross-operation symbol")
    put_cors_qualification, put_cors_commands = (
        s3_operation.qualification_plan(registry, ["PutBucketCors"])
    )
    assert put_cors_qualification == "put_bucket_cors"
    assert put_cors_commands[:6] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-put-bucket-cors-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_get_bucket_cors_corpus"],
        ["@tests", "./bin/s3_server_application_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert put_cors_commands[6] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-put-bucket-cors-gnatdoc",
        "--operation",
        "PutBucketCors",
    ]
    assert put_cors_commands[7:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry, ["PutBucketCors", "PutBucketCors"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate PutBucketCors lane accepted")
    try:
        s3_operation.qualification_plan(
            registry, ["PutBucketCors", "GetBucketCors"]
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed PutBucketCors lane accepted")

    put_policy_certainty = (
        "only a complete validated 200 response with an empty or "
        "whitespace-only body reports Bucket_Policy_Mutation_Completed; an "
        "exact recognized non-mutating rejection or definite non-admission "
        "reports Bucket_Policy_Mutation_Definitely_Not_Applied; "
        "pre-admission cancellation reports "
        "Bucket_Policy_Mutation_Cancelled_Before_Admission; possible or "
        "incomplete admission, retryable responses, and malformed or "
        "oversized responses report Bucket_Policy_Mutation_Outcome_Unknown; "
        "no automatic replay"
    )
    put_policy_reconciliation = (
        "caller-selected Get_Policy may observe the current exact policy "
        "bytes or NoSuchBucketPolicy before a retry, but does not prove that "
        "the lost replacement caused the observed state or upgrade mutation "
        "certainty; no automatic replay"
    )

    def assert_put_policy_registry(candidate):
        entry = candidate.operations["PutBucketPolicy"]
        assert entry.get("public_name") == "Set_Policy"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "put_bucket_policy"
        assert entry.get("codec") == "empty_response"
        assert entry.get("certainty") == put_policy_certainty
        assert entry.get("reconciliation") == put_policy_reconciliation
        assert entry.get("coverage") == {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        }
        assert entry.get("ada_symbols") == [
            "Prepare_Put_Bucket_Policy",
            "Execute_Put_Bucket_Policy",
            "Put_Bucket_Policy_Operation",
            "Set_Policy",
            "Finish",
        ]
        assert "atomically replaces" in entry["absence"]
        assert "exact HTTP 200" in entry["exclusions"][1]
        assert "Content-MD5" in entry["exclusions"][2]
        assert "does not establish causation" in entry["exclusions"][4]
        assert (
            candidate.qualification["put_bucket_policy"][0][-1]
            == "tools/verify-delete-bucket-configurations-preparation.py"
        )

    def reject_put_policy_registry(candidate, label):
        try:
            assert_put_policy_registry(candidate)
        except (AssertionError, KeyError, TypeError):
            return
        raise AssertionError(f"{label} PutBucketPolicy registry accepted")

    assert_put_policy_registry(registry)
    missing_put_policy_name = copy.deepcopy(registry)
    del missing_put_policy_name.operations["PutBucketPolicy"]["public_name"]
    reject_put_policy_registry(missing_put_policy_name, "missing public name")
    wrong_put_policy_name = copy.deepcopy(registry)
    wrong_put_policy_name.operations["PutBucketPolicy"][
        "public_name"
    ] = "Set_Public_Access_Block"
    reject_put_policy_registry(wrong_put_policy_name, "wrong public name")
    broadened_put_policy_success = copy.deepcopy(registry)
    broadened_put_policy_success.operations["PutBucketPolicy"][
        "certainty"
    ] = put_policy_certainty.replace("validated 200", "validated 200 or 204")
    reject_put_policy_registry(
        broadened_put_policy_success, "broadened success status"
    )
    causal_put_policy_reconciliation = copy.deepcopy(registry)
    causal_put_policy_reconciliation.operations["PutBucketPolicy"][
        "reconciliation"
    ] = "Get_Policy proves replacement"
    reject_put_policy_registry(
        causal_put_policy_reconciliation, "causal reconciliation"
    )
    cross_put_policy_symbol = copy.deepcopy(registry)
    cross_put_policy_symbol.operations["PutBucketPolicy"][
        "ada_symbols"
    ][0] = "Prepare_Put_Public_Access_Block"
    reject_put_policy_registry(
        cross_put_policy_symbol, "cross-operation symbol"
    )
    put_policy_qualification, put_policy_commands = (
        s3_operation.qualification_plan(registry, ["PutBucketPolicy"])
    )
    assert put_policy_qualification == "put_bucket_policy"
    assert put_policy_commands[:6] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-delete-bucket-configurations-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_put_bucket_controls_corpus"],
        ["@tests", "./bin/s3_server_application_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert put_policy_commands[6] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-put-bucket-policy-gnatdoc",
        "--operation",
        "PutBucketPolicy",
    ]
    assert put_policy_commands[7:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry, ["PutBucketPolicy", "PutBucketPolicy"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate PutBucketPolicy lane accepted")
    try:
        s3_operation.qualification_plan(
            registry, ["PutBucketPolicy", "GetBucketPolicy"]
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed PutBucketPolicy lane accepted")
    delete_public_access_block_certainty = (
        "only a complete validated 204 response with an exactly empty body "
        "reports Public_Access_Block_Mutation_Completed; an exact recognized "
        "non-mutating rejection or definite non-admission reports "
        "Public_Access_Block_Mutation_Definitely_Not_Applied; pre-admission "
        "cancellation reports "
        "Public_Access_Block_Mutation_Cancelled_Before_Admission; possible or "
        "incomplete admission, retryable responses, and malformed or oversized "
        "responses report Public_Access_Block_Mutation_Outcome_Unknown; no "
        "automatic replay"
    )
    delete_public_access_block_reconciliation = (
        "caller-selected Get_Public_Access_Block may observe the current "
        "bucket public-access-block configuration or exact "
        "NoSuchPublicAccessBlockConfiguration before a retry, but does not "
        "prove that the lost deletion caused the observed absence or upgrade "
        "mutation certainty; no automatic replay"
    )

    def assert_delete_public_access_block_registry(candidate):
        entry = candidate.operations["DeletePublicAccessBlock"]
        assert entry.get("public_name") == "Delete_Public_Access_Block"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "delete_public_access_block"
        assert entry.get("codec") == "empty_response"
        assert entry.get("certainty") == delete_public_access_block_certainty
        assert entry.get("reconciliation") == (
            delete_public_access_block_reconciliation
        )
        assert entry.get("coverage") == {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        }
        assert entry.get("ada_symbols") == [
            "Prepare_Delete_Public_Access_Block",
            "Execute_Delete_Public_Access_Block",
            "Delete_Public_Access_Block_Operation",
            "Delete_Public_Access_Block",
            "Finish",
        ]
        assert "removes the bucket public-access-block" in entry["absence"]
        assert "exact HTTP 204" in entry["exclusions"][2]
        assert "previously present" in entry["exclusions"][3]
        assert "does not establish causation" in entry["exclusions"][4]
        assert (
            candidate.qualification["delete_public_access_block"][0][-1]
            == "tools/verify-delete-bucket-configurations-preparation.py"
        )

    def reject_delete_public_access_block_registry(candidate, label):
        try:
            assert_delete_public_access_block_registry(candidate)
        except (AssertionError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} DeletePublicAccessBlock registry accepted"
        )

    assert_delete_public_access_block_registry(registry)
    missing_public_access_name = copy.deepcopy(registry)
    del missing_public_access_name.operations["DeletePublicAccessBlock"][
        "public_name"
    ]
    reject_delete_public_access_block_registry(
        missing_public_access_name, "missing public name"
    )
    wrong_public_access_name = copy.deepcopy(registry)
    wrong_public_access_name.operations["DeletePublicAccessBlock"][
        "public_name"
    ] = "Delete_Policy"
    reject_delete_public_access_block_registry(
        wrong_public_access_name, "wrong public name"
    )
    broadened_public_access_success = copy.deepcopy(registry)
    broadened_public_access_success.operations["DeletePublicAccessBlock"][
        "certainty"
    ] = delete_public_access_block_certainty.replace(
        "validated 204", "validated 200 or 204"
    )
    reject_delete_public_access_block_registry(
        broadened_public_access_success, "broadened success status"
    )
    causal_public_access_reconciliation = copy.deepcopy(registry)
    causal_public_access_reconciliation.operations[
        "DeletePublicAccessBlock"
    ]["reconciliation"] = "Get_Public_Access_Block proves deletion"
    reject_delete_public_access_block_registry(
        causal_public_access_reconciliation, "causal reconciliation"
    )
    cross_public_access_symbol = copy.deepcopy(registry)
    cross_public_access_symbol.operations["DeletePublicAccessBlock"][
        "ada_symbols"
    ][0] = "Prepare_Delete_Bucket_Policy"
    reject_delete_public_access_block_registry(
        cross_public_access_symbol, "cross-operation symbol"
    )
    public_access_qualification, public_access_commands = (
        s3_operation.qualification_plan(registry, ["DeletePublicAccessBlock"])
    )
    assert public_access_qualification == "delete_public_access_block"
    assert public_access_commands[:6] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-delete-bucket-configurations-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_delete_bucket_configurations_corpus"],
        ["@tests", "./bin/s3_server_application_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert public_access_commands[6] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-public-access-block-gnatdoc",
        "--operation",
        "DeletePublicAccessBlock",
    ]
    assert public_access_commands[7:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry, ["DeletePublicAccessBlock", "DeletePublicAccessBlock"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate DeletePublicAccessBlock lane was accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry, ["DeletePublicAccessBlock", "DeleteBucketPolicy"]
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError(
            "mixed DeletePublicAccessBlock lane was accepted"
        )
    def assert_get_public_access_block_registry(candidate):
        entry = candidate.operations["GetPublicAccessBlock"]
        assert entry.get("public_name") == "Get_Public_Access_Block"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "get_public_access_block"
        assert entry.get("codec") == "rest_xml_and_headers"
        assert entry.get("certainty") == "read_only"
        assert entry.get("reconciliation") == "not_applicable"
        assert entry.get("coverage") == {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        }
        assert entry.get("ada_symbols") == [
            "Prepare_Get_Public_Access_Block",
            "Execute_Get_Public_Access_Block",
            "Get_Public_Access_Block_Operation",
            "Get_Public_Access_Block",
            "Finish",
        ]
        assert "independent member presence" in entry["absence"]
        assert "NoSuchPublicAccessBlockConfiguration" in entry["absence"]
        assert "exact HTTP 200" in entry["exclusions"][2]
        assert "distinct from NoSuchBucket" in entry["exclusions"][3]
        assert (
            candidate.qualification["get_public_access_block"][0][-1]
            == "tools/verify-delete-bucket-configurations-preparation.py"
        )

    def reject_get_public_access_block_registry(candidate, label):
        try:
            assert_get_public_access_block_registry(candidate)
        except (AssertionError, KeyError, TypeError):
            return
        raise AssertionError(f"{label} GetPublicAccessBlock registry accepted")

    assert_get_public_access_block_registry(registry)
    missing_get_public_access_name = copy.deepcopy(registry)
    del missing_get_public_access_name.operations["GetPublicAccessBlock"][
        "public_name"
    ]
    reject_get_public_access_block_registry(
        missing_get_public_access_name, "missing public name"
    )
    wrong_get_public_access_name = copy.deepcopy(registry)
    wrong_get_public_access_name.operations["GetPublicAccessBlock"][
        "public_name"
    ] = "Get_Policy"
    reject_get_public_access_block_registry(
        wrong_get_public_access_name, "wrong public name"
    )
    mutation_get_public_access = copy.deepcopy(registry)
    mutation_get_public_access.operations["GetPublicAccessBlock"][
        "certainty"
    ] = "outcome_unknown"
    reject_get_public_access_block_registry(
        mutation_get_public_access, "mutation certainty"
    )
    reconciled_get_public_access = copy.deepcopy(registry)
    reconciled_get_public_access.operations["GetPublicAccessBlock"][
        "reconciliation"
    ] = "Get retries itself"
    reject_get_public_access_block_registry(
        reconciled_get_public_access, "invented reconciliation"
    )
    cross_get_public_access_symbol = copy.deepcopy(registry)
    cross_get_public_access_symbol.operations["GetPublicAccessBlock"][
        "ada_symbols"
    ][0] = "Prepare_Get_Bucket_Policy"
    reject_get_public_access_block_registry(
        cross_get_public_access_symbol, "cross-operation symbol"
    )
    get_public_access_qualification, get_public_access_commands = (
        s3_operation.qualification_plan(registry, ["GetPublicAccessBlock"])
    )
    assert get_public_access_qualification == "get_public_access_block"
    assert get_public_access_commands[:6] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-delete-bucket-configurations-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_get_bucket_controls_corpus"],
        ["@tests", "./bin/s3_server_application_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert get_public_access_commands[6] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-get-public-access-block-gnatdoc",
        "--operation",
        "GetPublicAccessBlock",
    ]
    assert get_public_access_commands[7:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry, ["GetPublicAccessBlock", "GetPublicAccessBlock"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate GetPublicAccessBlock lane accepted")
    try:
        s3_operation.qualification_plan(
            registry, ["GetPublicAccessBlock", "DeletePublicAccessBlock"]
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed GetPublicAccessBlock lane accepted")
    put_public_access_block_certainty = (
        "only a complete validated 200 response with an empty or "
        "whitespace-only body reports "
        "Public_Access_Block_Mutation_Completed; an exact recognized "
        "non-mutating rejection or definite non-admission reports "
        "Public_Access_Block_Mutation_Definitely_Not_Applied; pre-admission "
        "cancellation reports "
        "Public_Access_Block_Mutation_Cancelled_Before_Admission; possible "
        "or incomplete admission, retryable responses, and malformed or "
        "oversized responses report "
        "Public_Access_Block_Mutation_Outcome_Unknown; no automatic replay"
    )
    put_public_access_block_reconciliation = (
        "caller-selected Get_Public_Access_Block may observe the current "
        "bucket public-access-block configuration or exact "
        "NoSuchPublicAccessBlockConfiguration before a retry, but does not "
        "prove that the lost replacement caused the observed state or "
        "upgrade mutation certainty; no automatic replay"
    )

    def assert_put_public_access_block_registry(candidate):
        entry = candidate.operations["PutPublicAccessBlock"]
        assert entry.get("public_name") == "Set_Public_Access_Block"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "put_public_access_block"
        assert entry.get("codec") == "empty_response"
        assert entry.get("certainty") == put_public_access_block_certainty
        assert entry.get("reconciliation") == (
            put_public_access_block_reconciliation
        )
        assert entry.get("coverage") == {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        }
        assert entry.get("ada_symbols") == [
            "Prepare_Put_Public_Access_Block",
            "Execute_Put_Public_Access_Block",
            "Put_Public_Access_Block_Operation",
            "Set_Public_Access_Block",
            "Finish",
        ]
        assert "atomically replaces" in entry["absence"]
        assert "exact HTTP 200" in entry["exclusions"][2]
        assert "Content-MD5" in entry["exclusions"][3]
        assert "does not establish causation" in entry["exclusions"][4]
        assert (
            candidate.qualification["put_public_access_block"][0][-1]
            == "tools/verify-delete-bucket-configurations-preparation.py"
        )

    def reject_put_public_access_block_registry(candidate, label):
        try:
            assert_put_public_access_block_registry(candidate)
        except (AssertionError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} PutPublicAccessBlock registry accepted"
        )

    assert_put_public_access_block_registry(registry)
    missing_put_public_access_name = copy.deepcopy(registry)
    del missing_put_public_access_name.operations["PutPublicAccessBlock"][
        "public_name"
    ]
    reject_put_public_access_block_registry(
        missing_put_public_access_name, "missing public name"
    )
    wrong_put_public_access_name = copy.deepcopy(registry)
    wrong_put_public_access_name.operations["PutPublicAccessBlock"][
        "public_name"
    ] = "Set_Policy"
    reject_put_public_access_block_registry(
        wrong_put_public_access_name, "wrong public name"
    )
    broadened_put_public_access_success = copy.deepcopy(registry)
    broadened_put_public_access_success.operations["PutPublicAccessBlock"][
        "certainty"
    ] = put_public_access_block_certainty.replace(
        "validated 200", "validated 200 or 204"
    )
    reject_put_public_access_block_registry(
        broadened_put_public_access_success, "broadened success status"
    )
    causal_put_public_access_reconciliation = copy.deepcopy(registry)
    causal_put_public_access_reconciliation.operations[
        "PutPublicAccessBlock"
    ]["reconciliation"] = "Get_Public_Access_Block proves replacement"
    reject_put_public_access_block_registry(
        causal_put_public_access_reconciliation, "causal reconciliation"
    )
    cross_put_public_access_symbol = copy.deepcopy(registry)
    cross_put_public_access_symbol.operations["PutPublicAccessBlock"][
        "ada_symbols"
    ][0] = "Prepare_Put_Bucket_Policy"
    reject_put_public_access_block_registry(
        cross_put_public_access_symbol, "cross-operation symbol"
    )
    put_public_access_qualification, put_public_access_commands = (
        s3_operation.qualification_plan(registry, ["PutPublicAccessBlock"])
    )
    assert put_public_access_qualification == "put_public_access_block"
    assert put_public_access_commands[:6] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-delete-bucket-configurations-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_put_bucket_controls_corpus"],
        ["@tests", "./bin/s3_server_application_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert put_public_access_commands[6] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-put-public-access-block-gnatdoc",
        "--operation",
        "PutPublicAccessBlock",
    ]
    assert put_public_access_commands[7:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry, ["PutPublicAccessBlock", "PutPublicAccessBlock"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate PutPublicAccessBlock lane accepted")
    try:
        s3_operation.qualification_plan(
            registry, ["PutPublicAccessBlock", "GetPublicAccessBlock"]
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed PutPublicAccessBlock lane accepted")
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
        "handwritten": 82,
        "generated": 17,
        "shared-family": 17,
    }
    assert {
        name
        for name, entry in registry.operations.items()
        if entry["generator_eligible"]
    } == {
        "CreateBucketMetadataConfiguration",
        "ListDirectoryBuckets",
        "PutBucketAcl",
        "PutBucketInventoryConfiguration",
        "PutBucketLogging",
        "PutBucketWebsite",
        "UpdateBucketMetadataInventoryTableConfiguration",
        "UpdateBucketMetadataJournalTableConfiguration",
        "UpdateBucketMetadataAnnotationTableConfiguration",
    }
    canary = registry.operations["GetBucketReplication"]
    assert not s3_operation.evidence_findings(
        canary, include_partial=False
    )

    create_session = registry.operations["CreateSession"]
    assert create_session["public_name"] == "Create_Session"
    assert create_session["decision_status"] == "reviewed"
    assert create_session["human_decisions_resolved"] is True
    assert create_session["certainty"] == "read_only"
    assert create_session["reconciliation"] == "not_applicable"
    assert create_session["qualification"] == "create_session"
    assert create_session["ada_symbols"] == [
        "Prepare_Create_Session",
        "Decode_Create_Session_Complete_Response",
        "Execute_Create_Session",
        "Create_Session_Operation",
        "Create_Session",
        "Finish",
    ]
    assert "exact HTTP 200" in create_session["exclusions"][1]
    assert "zeroizing Credentials" in create_session["exclusions"][2]
    assert "no refresh task" in create_session["exclusions"][3]
    for label, key, value in (
        ("missing name", "public_name", None),
        ("wrong name", "public_name", "Create_Directory_Session"),
        ("mutation certainty", "certainty", "outcome_unknown"),
        ("cross lane", "qualification", "create_multipart_upload"),
    ):
        candidate = copy.deepcopy(registry.operations["CreateSession"])
        if value is None:
            del candidate[key]
        else:
            candidate[key] = value
        assert candidate != create_session
        rejected = False
        try:
            assert candidate["public_name"] == "Create_Session"
            assert candidate["certainty"] == "read_only"
            assert candidate["qualification"] == "create_session"
        except (AssertionError, KeyError):
            rejected = True
        assert rejected, f"{label} CreateSession mutation was accepted"
    create_session_qualification, create_session_commands = (
        s3_operation.qualification_plan(registry, ["CreateSession"])
    )
    assert create_session_qualification == "create_session"
    assert create_session_commands[:4] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-create-session-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_create_session_tls_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert create_session_commands[4] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-create-session-gnatdoc",
        "--operation",
        "CreateSession",
    ]
    assert create_session_commands[5:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]

    promoted = copy.deepcopy(create_session)
    promoted["coverage"]["server"] = "covered"
    promoted["provenance"]["server"] = "handwritten"
    findings = s3_operation.evidence_findings(
        promoted, include_partial=False
    )
    assert "covered server lacks executable evidence" in findings

    point_configuration_operations = {
        "DeleteBucketAnalyticsConfiguration": "analytics report generation",
        "GetBucketAnalyticsConfiguration": "analytics report generation",
        "PutBucketAnalyticsConfiguration": "analytics report generation",
        "DeleteBucketMetricsConfiguration": "CloudWatch metrics emission",
        "GetBucketMetricsConfiguration": "CloudWatch metrics emission",
        "PutBucketMetricsConfiguration": "CloudWatch metrics emission",
    }
    promoted_named_configuration_operations = {
        "DeleteBucketIntelligentTieringConfiguration": (
            "tier-transition execution", False
        ),
        "GetBucketIntelligentTieringConfiguration": (
            "tier-transition execution", True
        ),
        "PutBucketIntelligentTieringConfiguration": (
            "tier-transition execution", True
        ),
        "DeleteBucketInventoryConfiguration": (
            "inventory report generation", False
        ),
        "GetBucketInventoryConfiguration": (
            "inventory report generation", True
        ),
        "PutBucketInventoryConfiguration": (
            "inventory report generation", False
        ),
    }
    point_backend_evidence = {
        "tests/src/object_storage_test_cases.adb",
        "sqlite/tests/src/flyology_object_storage_sqlite_tests.adb",
    }
    point_server_evidence = {
        "src/flyology-object_storage-server-s3_applications.adb",
        "tests/src/s3_server_application_corpus.adb",
    }

    def assert_point_configuration_coverage(candidate, operation, excluded):
        entry = candidate.operations[operation]
        assert entry["coverage"] == {
            "backend": "covered",
            "client": "covered",
            "server": "covered",
            "corpus": "covered",
        }
        assert entry["provenance"]["backend"] == "handwritten"
        assert entry["provenance"]["server"] == "handwritten"
        assert point_backend_evidence.issubset(entry["evidence"]["backend"])
        assert point_server_evidence.issubset(entry["evidence"]["server"])
        assert any(excluded in item for item in entry["exclusions"])
        if operation.startswith("PutBucket"):
            assert "TooManyConfigurations at HTTP 400" in entry["errors"]

    for operation, excluded in point_configuration_operations.items():
        assert_point_configuration_coverage(registry, operation, excluded)
        for label, mutate in (
            (
                "missing backend coverage",
                lambda entry: entry["coverage"].update(backend="missing"),
            ),
            (
                "missing server evidence",
                lambda entry: entry["evidence"].update(server=[]),
            ),
            (
                "missing execution exclusion",
                lambda entry: entry.update(exclusions=[]),
            ),
        ):
            candidate = copy.deepcopy(registry)
            mutate(candidate.operations[operation])
            try:
                assert_point_configuration_coverage(
                    candidate, operation, excluded
                )
            except (AssertionError, KeyError, TypeError):
                pass
            else:
                raise AssertionError(
                    f"{label} accepted for {operation}"
                )
    assert set(promoted_named_configuration_operations) == {
        "DeleteBucketIntelligentTieringConfiguration",
        "GetBucketIntelligentTieringConfiguration",
        "PutBucketIntelligentTieringConfiguration",
        "DeleteBucketInventoryConfiguration",
        "GetBucketInventoryConfiguration",
        "PutBucketInventoryConfiguration",
    }
    for operation, (excluded, has_socket_cases) in (
        promoted_named_configuration_operations.items()
    ):
        assert_point_configuration_coverage(registry, operation, excluded)
        entry = registry.operations[operation]
        assert set(entry["evidence"]["backend"]) == point_backend_evidence
        assert set(entry["evidence"]["server"]) == point_server_evidence
        if operation.startswith("PutBucket"):
            assert any(
                "query id and payload Id" in item
                for item in entry["exclusions"]
            )
        if has_socket_cases:
            empty_cases = [
                case for case in entry["signed_socket"]["case"]
                if case["id"] == "empty-identifier-success"
            ]
            assert len(empty_cases) == 1
            assert len(empty_cases[0]["exchange"]) == 1
            exchange = empty_cases[0]["exchange"][0]
            assert exchange["input_values"]["Id"] == ""
            if operation.startswith("PutBucket"):
                assert "<Id></Id>" in exchange["request_body"]
        for label, mutate in (
            (
                "missing backend evidence",
                lambda item: item["evidence"].update(backend=[]),
            ),
            (
                "missing server coverage",
                lambda item: item["coverage"].update(server="missing"),
            ),
            (
                "missing execution exclusion",
                lambda item: item.update(exclusions=[]),
            ),
        ):
            candidate = copy.deepcopy(registry)
            mutate(candidate.operations[operation])
            assert candidate.operations[operation] != entry
            try:
                assert_point_configuration_coverage(
                    candidate, operation, excluded
                )
            except (AssertionError, KeyError, TypeError):
                pass
            else:
                raise AssertionError(
                    f"{label} accepted for {operation}"
                )

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
    create_metadata_table_certainty = (
        "only a complete validated 200 response with an empty or "
        "XML-whitespace body reports "
        "Metadata_Table_Configuration_Mutation_Completed; an exact "
        "recognized non-mutating rejection or definite non-admission reports "
        "Metadata_Table_Configuration_Mutation_Definitely_Not_Applied; "
        "pre-admission cancellation reports "
        "Metadata_Table_Configuration_Mutation_Cancelled_Before_Admission; "
        "possible or incomplete admission, retryable responses, "
        "non-whitespace success content, and malformed or oversized responses "
        "report Metadata_Table_Configuration_Mutation_Outcome_Unknown; no "
        "automatic replay"
    )
    create_metadata_table_reconciliation = (
        "caller-selected Get_Metadata_Table_Configuration may observe the "
        "current modeled configuration response or structured rejection "
        "before a retry, but does not prove that the lost mutation caused the "
        "observation or upgrade mutation certainty; no automatic replay"
    )

    def assert_create_metadata_table_registry(candidate):
        entry = candidate.operations[
            "CreateBucketMetadataTableConfiguration"
        ]
        assert entry.get("public_name") == (
            "Create_Metadata_Table_Configuration"
        )
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == (
            "create_bucket_metadata_table_configuration"
        )
        assert entry.get("codec") == "empty_response"
        assert entry.get("certainty") == create_metadata_table_certainty
        assert entry.get("reconciliation") == (
            create_metadata_table_reconciliation
        )
        assert entry.get("coverage") == {
            "backend": "missing",
            "client": "covered",
            "server": "missing",
            "corpus": "covered",
        }
        assert entry.get("ada_symbols") == [
            "Prepare_Create_Bucket_Metadata_Table_Configuration",
            "Execute_Create_Bucket_Metadata_Table_Configuration",
            "Create_Bucket_Metadata_Table_Configuration_Operation",
            "Create_Metadata_Table_Configuration",
            "Finish",
        ]
        assert "exact HTTP 200" in entry["exclusions"][2]
        assert "Content-MD5" in entry["exclusions"][3]
        assert "does not establish causation" in entry["exclusions"][4]
        assert candidate.qualification[
            "create_bucket_metadata_table_configuration"
        ][0][-1] == (
            "tools/verify-create-bucket-metadata-table-configuration-"
            "preparation.py"
        )

    def reject_create_metadata_table_registry(candidate, label):
        try:
            assert_create_metadata_table_registry(candidate)
        except (AssertionError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} CreateBucketMetadataTableConfiguration registry accepted"
        )

    assert_create_metadata_table_registry(registry)
    for label, key, value in (
        ("missing public name", "public_name", None),
        (
            "wrong public name",
            "public_name",
            "Create_Metadata_Configuration",
        ),
        (
            "broadened success",
            "certainty",
            create_metadata_table_certainty.replace(
                "validated 200", "validated 200 or 204"
            ),
        ),
        (
            "causal reconciliation",
            "reconciliation",
            "Get_Metadata_Table_Configuration proves mutation completion",
        ),
    ):
        candidate = copy.deepcopy(registry)
        entry = candidate.operations[
            "CreateBucketMetadataTableConfiguration"
        ]
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        assert candidate != registry
        reject_create_metadata_table_registry(candidate, label)
    cross_create_metadata_table_symbol = copy.deepcopy(registry)
    cross_create_metadata_table_symbol.operations[
        "CreateBucketMetadataTableConfiguration"
    ]["ada_symbols"][0] = "Prepare_Create_Bucket_Metadata_Configuration"
    assert cross_create_metadata_table_symbol != registry
    reject_create_metadata_table_registry(
        cross_create_metadata_table_symbol,
        "cross-operation symbol",
    )
    create_metadata_table_qualification, create_metadata_table_commands = (
        s3_operation.qualification_plan(
            registry, ["CreateBucketMetadataTableConfiguration"]
        )
    )
    assert create_metadata_table_qualification == (
        "create_bucket_metadata_table_configuration"
    )
    assert create_metadata_table_commands[:5] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-create-bucket-metadata-table-configuration-"
            "preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        [
            "@tests",
            "./bin/s3_create_bucket_metadata_table_configuration_corpus",
        ],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert create_metadata_table_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-create-bucket-metadata-table-gnatdoc",
        "--operation",
        "CreateBucketMetadataTableConfiguration",
    ]
    assert create_metadata_table_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "CreateBucketMetadataTableConfiguration",
                "CreateBucketMetadataTableConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate CreateBucketMetadataTableConfiguration lane was "
            "accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "CreateBucketMetadataTableConfiguration",
                "DeleteBucketMetadataTableConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError(
            "mixed CreateBucketMetadataTableConfiguration lane was accepted"
        )
    delete_object_annotation_certainty = (
        "only a complete validated exact 204 with an exactly empty body "
        "reports Annotation_Deletion_Completed; an exact recognized "
        "non-applying rejection or definite non-admission reports "
        "Annotation_Deletion_Definitely_Not_Applied, pre-admission "
        "cancellation reports "
        "Annotation_Deletion_Cancelled_Before_Admission, and every other "
        "possibly admitted, incomplete, retryable, malformed, or oversized "
        "outcome reports Annotation_Deletion_Outcome_Unknown; no automatic "
        "replay"
    )
    delete_object_annotation_reconciliation = (
        "caller-selected read-only observation using the exact bucket, key, "
        "annotation name, and explicit version or generation evidence before "
        "retry; an observation does not prove that the lost deletion caused "
        "the current state or upgrade mutation certainty"
    )
    delete_object_annotation_symbols = [
        "Prepare_Delete_Object_Annotation",
        "Decode_Delete_Object_Annotation_Response",
        "Execute_Delete_Object_Annotation",
        "Delete_Object_Annotation_Operation",
        "Delete_Annotation",
        "Finish",
    ]

    def assert_delete_object_annotation_registry(candidate):
        entry = candidate.operations["DeleteObjectAnnotation"]
        assert entry.get("public_name") == "Delete_Annotation"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "delete_object_annotation"
        assert entry.get("certainty") == delete_object_annotation_certainty
        assert entry.get("reconciliation") == (
            delete_object_annotation_reconciliation
        )
        assert entry.get("ada_symbols") == delete_object_annotation_symbols
        assert entry["coverage"]["backend"] == "missing"
        assert entry["coverage"]["server"] == "missing"
        assert entry["provenance"]["backend"] == "absent"
        assert entry["provenance"]["server"] == "absent"
        assert entry.get("absence") == "not_applicable"
        assert "external-provider interoperability" in entry["exclusions"][0]
        assert "exact HTTP 204" in entry["exclusions"][2]
        assert candidate.qualification["delete_object_annotation"][0][-1] == (
            "tools/verify-delete-object-annotation-preparation.py"
        )

    def reject_delete_object_annotation_registry(candidate, label):
        try:
            assert_delete_object_annotation_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} DeleteObjectAnnotation registry accepted"
        )

    assert_delete_object_annotation_registry(registry)
    missing_delete_object_annotation_name = copy.deepcopy(registry)
    del missing_delete_object_annotation_name.operations[
        "DeleteObjectAnnotation"
    ]["public_name"]
    assert missing_delete_object_annotation_name != registry
    reject_delete_object_annotation_registry(
        missing_delete_object_annotation_name, "missing name"
    )
    wrong_delete_object_annotation_name = copy.deepcopy(registry)
    wrong_delete_object_annotation_name.operations[
        "DeleteObjectAnnotation"
    ]["public_name"] = "Delete_Tags"
    assert wrong_delete_object_annotation_name != registry
    reject_delete_object_annotation_registry(
        wrong_delete_object_annotation_name, "cross-operation name"
    )
    replay_delete_object_annotation = copy.deepcopy(registry)
    replay_delete_object_annotation.operations[
        "DeleteObjectAnnotation"
    ]["certainty"] = "automatically replay after admission"
    assert replay_delete_object_annotation != registry
    reject_delete_object_annotation_registry(
        replay_delete_object_annotation, "automatic replay"
    )
    causal_delete_object_annotation = copy.deepcopy(registry)
    causal_delete_object_annotation.operations[
        "DeleteObjectAnnotation"
    ]["reconciliation"] = "the observation proves deletion"
    assert causal_delete_object_annotation != registry
    reject_delete_object_annotation_registry(
        causal_delete_object_annotation, "causal reconciliation"
    )
    cross_delete_object_annotation_symbol = copy.deepcopy(registry)
    cross_delete_object_annotation_symbol.operations[
        "DeleteObjectAnnotation"
    ]["ada_symbols"][0] = "Prepare_Delete_Object_Tagging"
    assert cross_delete_object_annotation_symbol != registry
    reject_delete_object_annotation_registry(
        cross_delete_object_annotation_symbol, "cross-operation symbol"
    )
    missing_delete_object_annotation_lane = copy.deepcopy(registry)
    del missing_delete_object_annotation_lane.qualification[
        "delete_object_annotation"
    ]
    assert missing_delete_object_annotation_lane != registry
    reject_delete_object_annotation_registry(
        missing_delete_object_annotation_lane, "missing lane"
    )
    annotation_qualification, annotation_commands = (
        s3_operation.qualification_plan(registry, ["DeleteObjectAnnotation"])
    )
    assert annotation_qualification == "delete_object_annotation"
    assert annotation_commands[:5] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-delete-object-annotation-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_delete_object_annotation_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert annotation_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-delete-object-annotation-gnatdoc",
        "--operation",
        "DeleteObjectAnnotation",
    ]
    assert annotation_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry,
            ["DeleteObjectAnnotation", "DeleteObjectAnnotation"],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate DeleteObjectAnnotation lane was accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry, ["DeleteObjectAnnotation", "DeleteObjectTagging"]
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed DeleteObjectAnnotation lane was accepted")

    accelerate_certainty = (
        "read-only; only one complete validated exact 200 "
        "Bucket_Control_Found response observed exposes the complete "
        "presence-preserving acceleration configuration and "
        "requester-charged value; every incomplete, invalid, or "
        "non-observed response exposes no configuration state; the client "
        "performs no automatic retry"
    )
    accelerate_reconciliation = (
        "a later GetBucketAccelerateConfiguration observes only the bucket "
        "acceleration configuration current at read time; it does not prove "
        "that a prior mutation caused the observed state or authorize "
        "automatic replay"
    )
    accelerate_symbols = [
        "Prepare_Get_Bucket_Accelerate_Configuration",
        "Decode_Get_Bucket_Accelerate_Response",
        "Execute_Get_Bucket_Accelerate_Configuration",
        "Get_Bucket_Accelerate_Configuration_Operation",
        "Get_Accelerate_Configuration",
        "Finish",
    ]

    def assert_accelerate_registry(candidate):
        entry = candidate.operations["GetBucketAccelerateConfiguration"]
        assert entry.get("public_name") == "Get_Accelerate_Configuration"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == (
            "get_bucket_accelerate_configuration"
        )
        assert entry.get("certainty") == accelerate_certainty
        assert entry.get("reconciliation") == accelerate_reconciliation
        assert entry.get("ada_symbols") == accelerate_symbols
        assert entry.get("evidence_tokens") == ["Get_Bucket_Acceleration"]
        assert_bucket_control_backend_server(entry)
        assert "absent, Enabled, or Suspended" in entry["absence"]
        assert "billing or effective acceleration policy" in (
            entry["exclusions"][3]
        )
        assert candidate.qualification[
            "get_bucket_accelerate_configuration"
        ][0][-1] == "tools/verify-get-bucket-controls-preparation.py"

    def reject_accelerate_registry(candidate, label):
        try:
            assert_accelerate_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} GetBucketAccelerateConfiguration registry accepted"
        )

    assert_accelerate_registry(registry)
    accelerate_mutations = [
        ("missing name", "public_name", None),
        ("wrong name", "public_name", "Get_Acceleration"),
        ("automatic retry", "certainty", "read-only; retry automatically"),
        (
            "causal reconciliation",
            "reconciliation",
            "the read proves the prior mutation",
        ),
        ("collapsed absence", "absence", "missing Status means Suspended"),
    ]
    for label, key, value in accelerate_mutations:
        candidate = copy.deepcopy(registry)
        entry = candidate.operations["GetBucketAccelerateConfiguration"]
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        assert candidate != registry
        reject_accelerate_registry(candidate, label)
    cross_accelerate_symbol = copy.deepcopy(registry)
    cross_accelerate_symbol.operations[
        "GetBucketAccelerateConfiguration"
    ]["ada_symbols"][0] = "Prepare_Put_Bucket_Accelerate_Configuration"
    assert cross_accelerate_symbol != registry
    reject_accelerate_registry(cross_accelerate_symbol, "cross-operation")
    missing_accelerate_lane = copy.deepcopy(registry)
    del missing_accelerate_lane.qualification[
        "get_bucket_accelerate_configuration"
    ]
    assert missing_accelerate_lane != registry
    reject_accelerate_registry(missing_accelerate_lane, "missing lane")
    accelerate_qualification, accelerate_commands = (
        s3_operation.qualification_plan(
            registry, ["GetBucketAccelerateConfiguration"]
        )
    )
    assert accelerate_qualification == "get_bucket_accelerate_configuration"
    assert accelerate_commands[:5] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-get-bucket-controls-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_get_bucket_controls_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert accelerate_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-get-bucket-accelerate-configuration-gnatdoc",
        "--operation",
        "GetBucketAccelerateConfiguration",
    ]
    assert accelerate_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "GetBucketAccelerateConfiguration",
                "GetBucketAccelerateConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate GetBucketAccelerateConfiguration lane accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "GetBucketAccelerateConfiguration",
                "PutBucketAccelerateConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert (
            "do not share one qualification lane" in str(error)
            or "has no focused qualification lane" in str(error)
        )
    else:
        raise AssertionError(
            "mixed GetBucketAccelerateConfiguration lane accepted"
        )

    abac_certainty = (
        "read-only; only one complete validated exact 200 "
        "Bucket_Control_Found response observed exposes the "
        "presence-preserving ABAC status; every incomplete, invalid, or "
        "non-observed response exposes no ABAC state; the client performs "
        "no automatic retry"
    )
    abac_reconciliation = (
        "a later GetBucketAbac observes only the bucket ABAC status current "
        "at read time; it does not prove that a prior mutation caused the "
        "observed state or authorize automatic replay"
    )
    abac_symbols = [
        "Prepare_Get_Bucket_Abac",
        "Decode_Get_Bucket_Abac_Response",
        "Execute_Get_Bucket_Abac",
        "Get_Bucket_ABAC_Operation",
        "Get_ABAC",
        "Finish",
    ]

    def assert_abac_registry(candidate):
        entry = candidate.operations["GetBucketAbac"]
        assert entry.get("public_name") == "Get_ABAC"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "get_bucket_abac"
        assert entry.get("certainty") == abac_certainty
        assert entry.get("reconciliation") == abac_reconciliation
        assert entry.get("ada_symbols") == abac_symbols
        assert_bucket_control_backend_server(entry)
        assert "absent, Enabled, or Disabled" in entry["absence"]
        assert "effective ABAC policy" in entry["exclusions"][3]
        assert candidate.qualification["get_bucket_abac"][0][-1] == (
            "tools/verify-get-bucket-controls-preparation.py"
        )

    def reject_abac_registry(candidate, label):
        try:
            assert_abac_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(f"{label} GetBucketAbac registry accepted")

    assert_abac_registry(registry)
    abac_mutations = [
        ("missing name", "public_name", None),
        ("wrong name", "public_name", "Get_ABAC_Status"),
        ("automatic retry", "certainty", "read-only; retry automatically"),
        (
            "causal reconciliation",
            "reconciliation",
            "the read proves the prior mutation",
        ),
        ("collapsed absence", "absence", "missing Status means Disabled"),
    ]
    for label, key, value in abac_mutations:
        candidate = copy.deepcopy(registry)
        entry = candidate.operations["GetBucketAbac"]
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        assert candidate != registry
        reject_abac_registry(candidate, label)
    cross_abac_symbol = copy.deepcopy(registry)
    cross_abac_symbol.operations["GetBucketAbac"]["ada_symbols"][0] = (
        "Prepare_Put_Bucket_Abac"
    )
    assert cross_abac_symbol != registry
    reject_abac_registry(cross_abac_symbol, "cross-operation")
    missing_abac_lane = copy.deepcopy(registry)
    del missing_abac_lane.qualification["get_bucket_abac"]
    assert missing_abac_lane != registry
    reject_abac_registry(missing_abac_lane, "missing lane")
    abac_qualification, abac_commands = s3_operation.qualification_plan(
        registry, ["GetBucketAbac"]
    )
    assert abac_qualification == "get_bucket_abac"
    assert abac_commands[:5] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-get-bucket-controls-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_get_bucket_controls_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert abac_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-get-bucket-abac-gnatdoc",
        "--operation",
        "GetBucketAbac",
    ]
    assert abac_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry, ["GetBucketAbac", "GetBucketAbac"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate GetBucketAbac lane accepted")
    try:
        s3_operation.qualification_plan(
            registry, ["GetBucketAbac", "PutBucketAbac"]
        )
    except s3_operation.Audit_Error as error:
        assert (
            "do not share one qualification lane" in str(error)
            or "has no focused qualification lane" in str(error)
        )
    else:
        raise AssertionError("mixed GetBucketAbac lane accepted")

    policy_status_certainty = (
        "read-only; only one complete validated exact 200 "
        "Bucket_Control_Found response observed exposes the "
        "presence-preserving IsPublic status; every incomplete, invalid, "
        "or non-observed response exposes no policy-status state; the "
        "client performs no automatic retry"
    )
    policy_status_reconciliation = (
        "a later GetBucketPolicyStatus observes only the bucket policy "
        "status current at read time; it does not prove that a prior policy "
        "mutation caused the observed state or authorize automatic replay"
    )
    policy_status_symbols = [
        "Prepare_Get_Bucket_Policy_Status",
        "Decode_Get_Bucket_Policy_Status_Response",
        "Execute_Get_Bucket_Policy_Status",
        "Get_Bucket_Policy_Status_Operation",
        "Get_Policy_Status",
        "Finish",
    ]

    def assert_policy_status_registry(candidate):
        entry = candidate.operations["GetBucketPolicyStatus"]
        assert entry.get("public_name") == "Get_Policy_Status"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "get_bucket_policy_status"
        assert entry.get("certainty") == policy_status_certainty
        assert entry.get("reconciliation") == policy_status_reconciliation
        assert entry.get("ada_symbols") == policy_status_symbols
        assert entry["coverage"]["backend"] == "missing"
        assert entry["coverage"]["server"] == "missing"
        assert "absent, false, or true" in entry["absence"]
        assert "authorization enforcement" in entry["exclusions"][3]
        assert candidate.qualification["get_bucket_policy_status"][0][
            -1
        ] == "tools/verify-get-bucket-controls-preparation.py"

    def reject_policy_status_registry(candidate, label):
        try:
            assert_policy_status_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} GetBucketPolicyStatus registry accepted"
        )

    assert_policy_status_registry(registry)
    policy_status_mutations = [
        ("missing name", "public_name", None),
        ("wrong name", "public_name", "Get_Public_Policy_Status"),
        ("automatic retry", "certainty", "read-only; retry automatically"),
        (
            "causal reconciliation",
            "reconciliation",
            "the read proves the prior policy mutation",
        ),
        ("collapsed absence", "absence", "missing IsPublic means false"),
    ]
    for label, key, value in policy_status_mutations:
        candidate = copy.deepcopy(registry)
        entry = candidate.operations["GetBucketPolicyStatus"]
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        assert candidate != registry
        reject_policy_status_registry(candidate, label)
    cross_policy_status_symbol = copy.deepcopy(registry)
    cross_policy_status_symbol.operations["GetBucketPolicyStatus"][
        "ada_symbols"
    ][0] = "Prepare_Get_Bucket_Policy"
    assert cross_policy_status_symbol != registry
    reject_policy_status_registry(
        cross_policy_status_symbol, "cross-operation"
    )
    missing_policy_status_lane = copy.deepcopy(registry)
    del missing_policy_status_lane.qualification["get_bucket_policy_status"]
    assert missing_policy_status_lane != registry
    reject_policy_status_registry(missing_policy_status_lane, "missing lane")
    policy_status_qualification, policy_status_commands = (
        s3_operation.qualification_plan(registry, ["GetBucketPolicyStatus"])
    )
    assert policy_status_qualification == "get_bucket_policy_status"
    assert policy_status_commands[:5] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-get-bucket-controls-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_get_bucket_controls_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert policy_status_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-get-bucket-policy-status-gnatdoc",
        "--operation",
        "GetBucketPolicyStatus",
    ]
    assert policy_status_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry, ["GetBucketPolicyStatus", "GetBucketPolicyStatus"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate GetBucketPolicyStatus lane accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry, ["GetBucketPolicyStatus", "PutBucketPolicy"]
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed GetBucketPolicyStatus lane accepted")

    request_payment_certainty = (
        "read-only; only one complete validated exact 200 "
        "Bucket_Control_Found response observed exposes the "
        "presence-preserving payer configuration; every incomplete, "
        "invalid, or non-observed response exposes no request-payment "
        "state; the client performs no automatic retry"
    )
    request_payment_reconciliation = (
        "a later GetBucketRequestPayment observes only the bucket "
        "request-payment configuration current at read time; it does not "
        "prove that a prior mutation caused the observed state or authorize "
        "automatic replay"
    )
    request_payment_symbols = [
        "Prepare_Get_Bucket_Request_Payment",
        "Decode_Get_Bucket_Request_Payment_Response",
        "Execute_Get_Bucket_Request_Payment",
        "Get_Bucket_Request_Payment_Operation",
        "Get_Request_Payment",
        "Finish",
    ]

    def assert_request_payment_registry(candidate):
        entry = candidate.operations["GetBucketRequestPayment"]
        assert entry.get("public_name") == "Get_Request_Payment"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "get_bucket_request_payment"
        assert entry.get("certainty") == request_payment_certainty
        assert entry.get("reconciliation") == request_payment_reconciliation
        assert entry.get("ada_symbols") == request_payment_symbols
        assert_bucket_control_backend_server(entry)
        assert "absent, Requester, or BucketOwner" in entry["absence"]
        assert "enforcing Requester Pays" in entry["exclusions"][3]
        assert candidate.qualification["get_bucket_request_payment"][0][
            -1
        ] == "tools/verify-get-bucket-controls-preparation.py"

    def reject_request_payment_registry(candidate, label):
        try:
            assert_request_payment_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} GetBucketRequestPayment registry accepted"
        )

    assert_request_payment_registry(registry)
    request_payment_mutations = [
        ("missing name", "public_name", None),
        ("wrong name", "public_name", "Get_Requester_Pays"),
        ("automatic retry", "certainty", "read-only; retry automatically"),
        (
            "causal reconciliation",
            "reconciliation",
            "the read proves the prior mutation",
        ),
        ("collapsed absence", "absence", "missing Payer means BucketOwner"),
    ]
    for label, key, value in request_payment_mutations:
        candidate = copy.deepcopy(registry)
        entry = candidate.operations["GetBucketRequestPayment"]
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        assert candidate != registry
        reject_request_payment_registry(candidate, label)
    cross_request_payment_symbol = copy.deepcopy(registry)
    cross_request_payment_symbol.operations["GetBucketRequestPayment"][
        "ada_symbols"
    ][0] = "Prepare_Put_Bucket_Request_Payment"
    assert cross_request_payment_symbol != registry
    reject_request_payment_registry(
        cross_request_payment_symbol, "cross-operation"
    )
    missing_request_payment_lane = copy.deepcopy(registry)
    del missing_request_payment_lane.qualification[
        "get_bucket_request_payment"
    ]
    assert missing_request_payment_lane != registry
    reject_request_payment_registry(
        missing_request_payment_lane, "missing lane"
    )
    request_payment_qualification, request_payment_commands = (
        s3_operation.qualification_plan(
            registry, ["GetBucketRequestPayment"]
        )
    )
    assert request_payment_qualification == "get_bucket_request_payment"
    assert request_payment_commands[:5] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-get-bucket-controls-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_get_bucket_controls_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert request_payment_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-get-bucket-request-payment-gnatdoc",
        "--operation",
        "GetBucketRequestPayment",
    ]
    assert request_payment_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry,
            ["GetBucketRequestPayment", "GetBucketRequestPayment"],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate GetBucketRequestPayment lane accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            ["GetBucketRequestPayment", "PutBucketRequestPayment"],
        )
    except s3_operation.Audit_Error as error:
        assert (
            "do not share one qualification lane" in str(error)
            or "has no focused qualification lane" in str(error)
        )
    else:
        raise AssertionError(
            "mixed GetBucketRequestPayment lane accepted"
        )

    put_abac_certainty = (
        "only a complete validated exact 200 response observed with an empty "
        "or whitespace-only body reports ABAC_Mutation_Completed; an exact "
        "recognized non-mutating rejection or definite non-admission reports "
        "ABAC_Mutation_Definitely_Not_Applied; pre-admission cancellation "
        "reports ABAC_Mutation_Cancelled_Before_Admission; possible or "
        "incomplete admission, retryable responses, and malformed or "
        "oversized responses report ABAC_Mutation_Outcome_Unknown; no "
        "automatic replay"
    )
    put_abac_reconciliation = (
        "caller-selected Get_ABAC may observe only the bucket ABAC status "
        "current at read time before a retry, but does not prove that the "
        "lost mutation caused the observed state or upgrade mutation "
        "certainty; no automatic replay"
    )
    put_abac_symbols = [
        "Prepare_Put_Bucket_Abac",
        "Execute_Put_Bucket_Abac",
        "Put_Bucket_ABAC_Operation",
        "Set_ABAC",
        "Finish",
    ]

    def assert_put_abac_registry(candidate):
        entry = candidate.operations["PutBucketAbac"]
        assert entry.get("public_name") == "Set_ABAC"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "put_bucket_abac"
        assert entry.get("certainty") == put_abac_certainty
        assert entry.get("reconciliation") == put_abac_reconciliation
        assert entry.get("ada_symbols") == put_abac_symbols
        assert_bucket_control_backend_server(entry)
        assert entry["absence"] == "not_applicable"
        assert "exact same immutable serialized ABAC document" in (
            entry["exclusions"][3]
        )
        assert candidate.qualification["put_bucket_abac"][0][-1] == (
            "tools/verify-put-bucket-controls-preparation.py"
        )

    def reject_put_abac_registry(candidate, label):
        try:
            assert_put_abac_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(f"{label} PutBucketAbac registry accepted")

    assert_put_abac_registry(registry)
    put_abac_mutations = [
        ("missing name", "public_name", None),
        ("wrong name", "public_name", "Put_ABAC"),
        ("automatic retry", "certainty", "retry automatically"),
        (
            "causal reconciliation",
            "reconciliation",
            "Get_ABAC proves the lost mutation succeeded",
        ),
        ("wrong success", "certainty", "HTTP 204 proves completion"),
    ]
    for label, key, value in put_abac_mutations:
        candidate = copy.deepcopy(registry)
        entry = candidate.operations["PutBucketAbac"]
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        assert candidate != registry
        reject_put_abac_registry(candidate, label)
    cross_put_abac_symbol = copy.deepcopy(registry)
    cross_put_abac_symbol.operations["PutBucketAbac"]["ada_symbols"][0] = (
        "Prepare_Get_Bucket_Abac"
    )
    assert cross_put_abac_symbol != registry
    reject_put_abac_registry(cross_put_abac_symbol, "cross-operation")
    missing_put_abac_lane = copy.deepcopy(registry)
    del missing_put_abac_lane.qualification["put_bucket_abac"]
    assert missing_put_abac_lane != registry
    reject_put_abac_registry(missing_put_abac_lane, "missing lane")
    put_abac_qualification, put_abac_commands = (
        s3_operation.qualification_plan(registry, ["PutBucketAbac"])
    )
    assert put_abac_qualification == "put_bucket_abac"
    assert put_abac_commands[:5] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-put-bucket-controls-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_put_bucket_controls_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert put_abac_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-put-bucket-abac-gnatdoc",
        "--operation",
        "PutBucketAbac",
    ]
    assert put_abac_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry, ["PutBucketAbac", "PutBucketAbac"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate PutBucketAbac lane accepted")
    try:
        s3_operation.qualification_plan(
            registry, ["PutBucketAbac", "GetBucketAbac"]
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed PutBucketAbac lane accepted")

    put_accelerate_certainty = (
        "only a complete validated exact 200 response observed with an empty "
        "or whitespace-only body reports Acceleration_Mutation_Completed; "
        "an exact recognized non-mutating rejection or definite "
        "non-admission reports "
        "Acceleration_Mutation_Definitely_Not_Applied; pre-admission "
        "cancellation reports Acceleration_Mutation_Cancelled_Before_Admission; "
        "possible or incomplete admission, retryable responses, and malformed "
        "or oversized responses report Acceleration_Mutation_Outcome_Unknown; "
        "no automatic replay"
    )
    put_accelerate_reconciliation = (
        "caller-selected Get_Accelerate_Configuration may observe only the "
        "bucket acceleration configuration current at read time before a "
        "retry, but does not prove that the lost mutation caused the observed "
        "state or upgrade mutation certainty; no automatic replay"
    )
    put_accelerate_symbols = [
        "Prepare_Put_Bucket_Accelerate_Configuration",
        "Execute_Put_Bucket_Accelerate_Configuration",
        "Put_Bucket_Accelerate_Configuration_Operation",
        "Set_Accelerate_Configuration",
        "Finish",
    ]

    def assert_put_accelerate_registry(candidate):
        entry = candidate.operations["PutBucketAccelerateConfiguration"]
        assert entry.get("public_name") == "Set_Accelerate_Configuration"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == (
            "put_bucket_accelerate_configuration"
        )
        assert entry.get("certainty") == put_accelerate_certainty
        assert entry.get("reconciliation") == put_accelerate_reconciliation
        assert entry.get("ada_symbols") == put_accelerate_symbols
        assert entry.get("evidence_tokens") == ["Put_Bucket_Acceleration"]
        assert_bucket_control_backend_server(entry)
        assert "no Content-MD5 member" in entry["exclusions"][3]
        assert candidate.qualification[
            "put_bucket_accelerate_configuration"
        ][0][-1] == "tools/verify-put-bucket-controls-preparation.py"

    def reject_put_accelerate_registry(candidate, label):
        try:
            assert_put_accelerate_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} PutBucketAccelerateConfiguration registry accepted"
        )

    assert_put_accelerate_registry(registry)
    put_accelerate_mutations = [
        ("missing name", "public_name", None),
        ("wrong name", "public_name", "Set_Acceleration"),
        ("automatic retry", "certainty", "retry automatically"),
        (
            "causal reconciliation",
            "reconciliation",
            "the GET proves the lost mutation succeeded",
        ),
        ("invented MD5", "exclusions", ["Content-MD5 is required"]),
    ]
    for label, key, value in put_accelerate_mutations:
        candidate = copy.deepcopy(registry)
        entry = candidate.operations["PutBucketAccelerateConfiguration"]
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        assert candidate != registry
        reject_put_accelerate_registry(candidate, label)
    cross_put_accelerate_symbol = copy.deepcopy(registry)
    cross_put_accelerate_symbol.operations[
        "PutBucketAccelerateConfiguration"
    ]["ada_symbols"][0] = "Prepare_Get_Bucket_Accelerate_Configuration"
    assert cross_put_accelerate_symbol != registry
    reject_put_accelerate_registry(
        cross_put_accelerate_symbol, "cross-operation"
    )
    missing_put_accelerate_lane = copy.deepcopy(registry)
    del missing_put_accelerate_lane.qualification[
        "put_bucket_accelerate_configuration"
    ]
    assert missing_put_accelerate_lane != registry
    reject_put_accelerate_registry(
        missing_put_accelerate_lane, "missing lane"
    )
    put_accelerate_qualification, put_accelerate_commands = (
        s3_operation.qualification_plan(
            registry, ["PutBucketAccelerateConfiguration"]
        )
    )
    assert put_accelerate_qualification == (
        "put_bucket_accelerate_configuration"
    )
    assert put_accelerate_commands[:5] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-put-bucket-controls-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_put_bucket_controls_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert put_accelerate_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-put-bucket-accelerate-configuration-gnatdoc",
        "--operation",
        "PutBucketAccelerateConfiguration",
    ]
    assert put_accelerate_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "PutBucketAccelerateConfiguration",
                "PutBucketAccelerateConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate PutBucketAccelerateConfiguration lane accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "PutBucketAccelerateConfiguration",
                "GetBucketAccelerateConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError(
            "mixed PutBucketAccelerateConfiguration lane accepted"
        )

    put_payment_certainty = (
        "only a complete validated exact 200 response observed with an empty "
        "or whitespace-only body reports "
        "Request_Payment_Mutation_Completed; an exact recognized "
        "non-mutating rejection or definite non-admission reports "
        "Request_Payment_Mutation_Definitely_Not_Applied; pre-admission "
        "cancellation reports "
        "Request_Payment_Mutation_Cancelled_Before_Admission; possible or "
        "incomplete admission, retryable responses, and malformed or "
        "oversized responses report Request_Payment_Mutation_Outcome_Unknown; "
        "no automatic replay"
    )
    put_payment_reconciliation = (
        "caller-selected Get_Request_Payment may observe only the bucket "
        "request-payment configuration current at read time before a retry, "
        "but does not prove that the lost mutation caused the observed state "
        "or upgrade mutation certainty; no automatic replay"
    )
    put_payment_symbols = [
        "Prepare_Put_Bucket_Request_Payment",
        "Execute_Put_Bucket_Request_Payment",
        "Put_Bucket_Request_Payment_Operation",
        "Set_Request_Payment",
        "Finish",
    ]

    def assert_put_payment_registry(candidate):
        entry = candidate.operations["PutBucketRequestPayment"]
        assert entry.get("public_name") == "Set_Request_Payment"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "put_bucket_request_payment"
        assert entry.get("certainty") == put_payment_certainty
        assert entry.get("reconciliation") == put_payment_reconciliation
        assert entry.get("ada_symbols") == put_payment_symbols
        assert_bucket_control_backend_server(entry)
        assert "required generated-checksum path" in entry["exclusions"][3]
        assert "Requester or BucketOwner" in entry["exclusions"][4]
        assert candidate.qualification["put_bucket_request_payment"][0][
            -1
        ] == "tools/verify-put-bucket-controls-preparation.py"

    def reject_put_payment_registry(candidate, label):
        try:
            assert_put_payment_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} PutBucketRequestPayment registry accepted"
        )

    assert_put_payment_registry(registry)
    put_payment_mutations = [
        ("missing name", "public_name", None),
        ("wrong name", "public_name", "Put_Request_Payment"),
        ("automatic retry", "certainty", "retry automatically"),
        ("causal reconciliation", "reconciliation", "GET proves mutation"),
        ("missing checksum", "exclusions", ["checksum is optional"]),
    ]
    for label, key, value in put_payment_mutations:
        candidate = copy.deepcopy(registry)
        entry = candidate.operations["PutBucketRequestPayment"]
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        assert candidate != registry
        reject_put_payment_registry(candidate, label)
    cross_put_payment_symbol = copy.deepcopy(registry)
    cross_put_payment_symbol.operations["PutBucketRequestPayment"][
        "ada_symbols"
    ][0] = "Prepare_Get_Bucket_Request_Payment"
    assert cross_put_payment_symbol != registry
    reject_put_payment_registry(cross_put_payment_symbol, "cross-operation")
    missing_put_payment_lane = copy.deepcopy(registry)
    del missing_put_payment_lane.qualification["put_bucket_request_payment"]
    assert missing_put_payment_lane != registry
    reject_put_payment_registry(missing_put_payment_lane, "missing lane")
    put_payment_qualification, put_payment_commands = (
        s3_operation.qualification_plan(registry, ["PutBucketRequestPayment"])
    )
    assert put_payment_qualification == "put_bucket_request_payment"
    assert put_payment_commands[:5] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-put-bucket-controls-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_put_bucket_controls_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert put_payment_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-put-bucket-request-payment-gnatdoc",
        "--operation",
        "PutBucketRequestPayment",
    ]
    assert put_payment_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry, ["PutBucketRequestPayment", "PutBucketRequestPayment"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate PutBucketRequestPayment lane accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry, ["PutBucketRequestPayment", "GetBucketRequestPayment"]
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed PutBucketRequestPayment lane accepted")

    replication_certainty = (
        "only a complete validated exact 200 response observed reports "
        "Bucket_Replication_Mutation_Completed; an exact recognized "
        "non-mutating rejection or definite non-admission reports "
        "Bucket_Replication_Mutation_Definitely_Not_Applied; pre-admission "
        "cancellation reports "
        "Bucket_Replication_Mutation_Cancelled_Before_Admission; possible "
        "or incomplete admission, retryable responses, and malformed or "
        "oversized responses report "
        "Bucket_Replication_Mutation_Outcome_Unknown; no automatic replay"
    )
    replication_reconciliation = (
        "caller-selected Get_Replication_Configuration may observe only the "
        "bucket replication configuration current at read time before a "
        "retry, but does not prove that the lost mutation caused the observed "
        "state or upgrade mutation certainty; no automatic replay"
    )
    replication_symbols = [
        "Prepare_Put_Bucket_Replication",
        "Execute_Put_Bucket_Replication",
        "Put_Bucket_Replication_Operation",
        "Set_Replication_Configuration",
        "Finish",
    ]

    def assert_put_replication_registry(candidate):
        entry = candidate.operations["PutBucketReplication"]
        assert entry.get("public_name") == "Set_Replication_Configuration"
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == "put_bucket_replication"
        assert entry.get("certainty") == replication_certainty
        assert entry.get("reconciliation") == replication_reconciliation
        assert entry.get("ada_symbols") == replication_symbols
        assert entry["coverage"]["backend"] == "covered"
        assert entry["coverage"]["server"] == "covered"
        assert "required generated checksum" in entry["exclusions"][3]
        assert "prose-only filter-cardinality" in entry["exclusions"][4]
        assert "does not enforce Object Lock token policy" in (
            entry["exclusions"][5]
        )
        assert candidate.qualification["put_bucket_replication"][0][
            -1
        ] == "tools/verify-put-bucket-replication-preparation.py"

    def reject_put_replication_registry(candidate, label):
        try:
            assert_put_replication_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} PutBucketReplication registry accepted"
        )

    assert_put_replication_registry(registry)
    replication_mutations = [
        ("missing name", "public_name", None),
        ("wrong name", "public_name", "Put_Replication"),
        ("automatic retry", "certainty", "retry automatically"),
        ("causal reconciliation", "reconciliation", "GET proves mutation"),
        ("missing checksum", "exclusions", ["checksums are optional"]),
    ]
    for label, key, value in replication_mutations:
        candidate = copy.deepcopy(registry)
        entry = candidate.operations["PutBucketReplication"]
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        assert candidate != registry
        reject_put_replication_registry(candidate, label)
    cross_replication_symbol = copy.deepcopy(registry)
    cross_replication_symbol.operations["PutBucketReplication"][
        "ada_symbols"
    ][0] = "Prepare_Get_Bucket_Replication"
    assert cross_replication_symbol != registry
    reject_put_replication_registry(cross_replication_symbol, "cross-operation")
    invented_token_policy = copy.deepcopy(registry)
    invented_token_policy.operations["PutBucketReplication"]["exclusions"][
        5
    ] = "the authenticated server enforces Object Lock token policy"
    assert invented_token_policy != registry
    reject_put_replication_registry(
        invented_token_policy, "invented Object Lock token policy"
    )
    missing_replication_lane = copy.deepcopy(registry)
    del missing_replication_lane.qualification["put_bucket_replication"]
    assert missing_replication_lane != registry
    reject_put_replication_registry(missing_replication_lane, "missing lane")
    replication_qualification, replication_commands = (
        s3_operation.qualification_plan(registry, ["PutBucketReplication"])
    )
    assert replication_qualification == "put_bucket_replication"
    assert replication_commands[:5] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-put-bucket-replication-preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        ["@tests", "./bin/s3_put_bucket_replication_corpus"],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert replication_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-put-bucket-replication-gnatdoc",
        "--operation",
        "PutBucketReplication",
    ]
    assert replication_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry, ["PutBucketReplication", "PutBucketReplication"]
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError("duplicate PutBucketReplication lane accepted")
    try:
        s3_operation.qualification_plan(
            registry, ["PutBucketReplication", "GetBucketReplication"]
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError("mixed PutBucketReplication lane accepted")

    metadata_table_certainty = (
        "read_only; only a complete bounded exact 200 response yields modeled "
        "metadata-table state; malformed, oversized, wrong-status, and "
        "incomplete exchanges expose no partial state; no automatic retry"
    )
    metadata_table_reconciliation = (
        "a later Get_Metadata_Table_Configuration observes only the "
        "metadata-table configuration current at read time and does not "
        "establish prior state or mutation causality; no automatic retry"
    )
    metadata_table_symbols = [
        "Prepare_Get_Bucket_Metadata_Table_Configuration",
        "Decode_Get_Bucket_Metadata_Table_Configuration_Response",
        "Execute_Get_Bucket_Metadata_Table_Configuration",
        "Get_Bucket_Metadata_Table_Configuration_Operation",
        "Get_Metadata_Table_Configuration",
        "Finish",
    ]

    def assert_metadata_table_registry(candidate):
        entry = candidate.operations[
            "GetBucketMetadataTableConfiguration"
        ]
        assert entry.get("public_name") == (
            "Get_Metadata_Table_Configuration"
        )
        assert entry.get("decision_status") == "reviewed"
        assert entry.get("human_decisions_resolved") is True
        assert entry.get("qualification") == (
            "get_bucket_metadata_table_configuration"
        )
        assert entry.get("certainty") == metadata_table_certainty
        assert entry.get("reconciliation") == (
            metadata_table_reconciliation
        )
        assert entry.get("ada_symbols") == metadata_table_symbols
        assert "empty body preserves optional outer-result absence" in (
            entry["absence"]
        )
        assert "no non-200 response" in entry["absence"]
        assert entry["coverage"]["backend"] == "missing"
        assert entry["coverage"]["server"] == "missing"
        assert "V1 API" in entry["exclusions"][0]
        assert "exact 405" in entry["exclusions"][0]
        assert "S3 Express control-endpoint" in entry["exclusions"][1]
        assert candidate.qualification[
            "get_bucket_metadata_table_configuration"
        ][0][-1] == (
            "tools/verify-get-bucket-metadata-table-configuration-"
            "preparation.py"
        )

    def reject_metadata_table_registry(candidate, label):
        try:
            assert_metadata_table_registry(candidate)
        except (AssertionError, IndexError, KeyError, TypeError):
            return
        raise AssertionError(
            f"{label} GetBucketMetadataTableConfiguration registry accepted"
        )

    assert_metadata_table_registry(registry)
    metadata_table_mutations = [
        ("missing name", "public_name", None),
        ("wrong name", "public_name", "Get_Metadata_Configuration"),
        ("automatic retry", "certainty", "read and retry automatically"),
        (
            "causal reconciliation",
            "reconciliation",
            "the read proves a prior mutation caused the current state",
        ),
        (
            "collapsed absence",
            "absence",
            "all non-200 responses prove the configuration is absent",
        ),
        ("missing V1 boundary", "exclusions", ["V2 is equivalent"]),
    ]
    for label, key, value in metadata_table_mutations:
        candidate = copy.deepcopy(registry)
        entry = candidate.operations[
            "GetBucketMetadataTableConfiguration"
        ]
        if value is None:
            del entry[key]
        else:
            entry[key] = value
        assert candidate != registry
        reject_metadata_table_registry(candidate, label)
    cross_metadata_table_symbol = copy.deepcopy(registry)
    cross_metadata_table_symbol.operations[
        "GetBucketMetadataTableConfiguration"
    ]["ada_symbols"][0] = "Prepare_Get_Bucket_Metadata_Configuration"
    assert cross_metadata_table_symbol != registry
    reject_metadata_table_registry(
        cross_metadata_table_symbol, "cross-operation"
    )
    missing_metadata_table_lane = copy.deepcopy(registry)
    del missing_metadata_table_lane.qualification[
        "get_bucket_metadata_table_configuration"
    ]
    assert missing_metadata_table_lane != registry
    reject_metadata_table_registry(
        missing_metadata_table_lane, "missing lane"
    )
    metadata_table_qualification, metadata_table_commands = (
        s3_operation.qualification_plan(
            registry, ["GetBucketMetadataTableConfiguration"]
        )
    )
    assert metadata_table_qualification == (
        "get_bucket_metadata_table_configuration"
    )
    assert metadata_table_commands[:5] == [
        [
            "uv", "run", "--python", "3.13", "--",
            "tools/verify-get-bucket-metadata-table-configuration-"
            "preparation.py",
        ],
        ["@tests", "alr", "-n", "build"],
        [
            "@tests",
            "./bin/s3_get_bucket_metadata_table_configuration_corpus",
        ],
        ["@tests", "./bin/s3_http_socket_corpus"],
        ["./tools/verify-coverage.sh"],
    ]
    assert metadata_table_commands[5] == [
        "./tools/build-api-docs.sh",
        "/private/tmp/fos-get-bucket-metadata-table-configuration-gnatdoc",
        "--operation",
        "GetBucketMetadataTableConfiguration",
    ]
    assert metadata_table_commands[6:] == [
        ["./tools/ci/check-repository.sh", "{model}"],
        ["git", "diff", "--check"],
    ]
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "GetBucketMetadataTableConfiguration",
                "GetBucketMetadataTableConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "appears more than once" in str(error)
    else:
        raise AssertionError(
            "duplicate GetBucketMetadataTableConfiguration lane accepted"
        )
    try:
        s3_operation.qualification_plan(
            registry,
            [
                "GetBucketMetadataTableConfiguration",
                "GetBucketMetadataConfiguration",
            ],
        )
    except s3_operation.Audit_Error as error:
        assert "do not share one qualification lane" in str(error)
    else:
        raise AssertionError(
            "mixed GetBucketMetadataTableConfiguration lane accepted"
        )

    print("S3 operation registry evidence negative oracles: OK")


if __name__ == "__main__":
    main()
