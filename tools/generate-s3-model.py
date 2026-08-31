#!/usr/bin/env python3
"""Generate the exhaustive SPARK-readable S3 REST/XML model descriptor."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import sys
import tempfile


EXPECTED_SHA256 = (
    "429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9"
)
EXPECTED_OPERATIONS = 116
EXPECTED_SHAPES = 718

OPERATION_DOCUMENTATION = {
    "CreateBucketMetadataTableConfiguration": (
        "Create metadata-table configuration"
    ),
    "CreateSession": "Create directory-bucket session credentials",
    "DeleteBucketAnalyticsConfiguration": "Delete analytics",
    "DeleteBucketCors": "Delete bucket CORS operation",
    "DeleteBucketEncryption": "Delete bucket encryption",
    "DeleteBucketIntelligentTieringConfiguration": (
        "Delete intelligent-tiering configuration"
    ),
    "DeleteBucketInventoryConfiguration": "Delete inventory configuration",
    "DeleteBucketLifecycle": "Delete bucket lifecycle",
    "DeleteBucketMetadataConfiguration": "Delete metadata configuration",
    "DeleteBucketMetadataTableConfiguration": (
        "Delete metadata-table configuration"
    ),
    "DeleteBucketMetricsConfiguration": "Delete metrics configuration",
    "DeleteBucketOwnershipControls": "Delete bucket ownership controls",
    "DeleteBucketPolicy": "Delete bucket policy",
    "DeleteBucketReplication": "Delete bucket replication",
    "DeleteBucketWebsite": "Delete bucket website",
    "DeleteBucketTagging": "Delete bucket tagging operation",
    "DeletePublicAccessBlock": "Delete public access block",
    "GetBucketCors": "Get bucket CORS operation",
    "GetBucketTagging": "Get bucket tagging operation",
    "GetBucketPolicy": "Get bucket policy",
    "GetPublicAccessBlock": "Get public access block",
    "GetObjectAttributes": "Get object attributes operation",
    "ListParts": "List multipart upload parts",
    "PutBucketTagging": "Put bucket tagging operation",
    "PutBucketCors": "Put bucket CORS operation",
    "PutBucketPolicy": "Put bucket policy",
    "PutPublicAccessBlock": "Put public access block",
    "UploadPart": "Upload multipart upload part",
    "UploadPartCopy": "Upload multipart part from a source object",
}


def ada_name(value: str, suffix: str) -> str:
    value = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", value)
    value = re.sub(r"[^A-Za-z0-9]+", "_", value).strip("_")
    if not value or value[0].isdigit():
        value = "N_" + value
    return value + suffix


def quote(value: str) -> str:
    return '"' + value.replace('"', '""') + '"'


def bool_image(value: object) -> str:
    return "True" if value is True else "False"


def operation_documentation(literal: str, description: str) -> list[str]:
    association = "   --  @enum " + literal
    one_line = association + " " + description
    if len(one_line) <= 79:
        return [one_line]
    continuation = "   --    " + description
    if len(association) > 79 or len(continuation) > 79:
        raise ValueError("operation documentation exceeds source width")
    return [association, continuation]


def line_case_function(
    name: str,
    argument: str,
    result: str,
    entries: list[tuple[str, str]],
) -> list[str]:
    lines = [
        f"   function {name} ({argument}) return {result} is",
        "   begin",
        f"      case {argument.split(':', 1)[0].strip()} is",
    ]
    for key, value in entries:
        lines.extend((f"         when {key} =>", f"            return {value};"))
    lines.extend(("      end case;", f"   end {name};", ""))
    return lines


def nested_case_function(
    name: str,
    result: str,
    entries: list[tuple[str, list[str]]],
    default: str,
    index_name: str = "Member",
) -> list[str]:
    lines = [
        f"   function {name}",
        f"     (Shape : Shape_Index; {index_name} : Positive) return " + result,
        "   is",
        "   begin",
        "      case Shape is",
    ]
    for shape, values in entries:
        lines.extend(
            (f"         when {shape} =>", f"            case {index_name} is")
        )
        for index, value in enumerate(values, 1):
            lines.extend(
                (f"               when {index} =>", f"                  return {value};")
            )
        lines.extend(
            ("               when others =>", f"                  return {default};", "            end case;")
        )
    lines.extend(
        ("         when others =>", f"            return {default};", "      end case;", f"   end {name};", "")
    )
    return lines


def operation_nested_function(
    name: str,
    result: str,
    operations: list[str],
    values: dict[str, list[str]],
    default: str,
) -> list[str]:
    lines = [
        f"   function {name}",
        "     (Operation : Operation_Id; Index : Positive) return " + result,
        "   is",
        "   begin",
        "      case Operation is",
    ]
    for operation in operations:
        items = values[operation]
        if not items:
            continue
        lines.extend(
            (f"         when {ada_name(operation, '_Operation')} =>", "            case Index is")
        )
        for index, value in enumerate(items, 1):
            lines.extend(
                (f"               when {index} =>", f"                  return {value};")
            )
        lines.extend(
            ("               when others =>", f"                  return {default};", "            end case;")
        )
    lines.extend(
        ("         when others =>", f"            return {default};", "      end case;", f"   end {name};", "")
    )
    return lines


def generate(model_path: pathlib.Path) -> tuple[str, str]:
    raw = model_path.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != EXPECTED_SHA256:
        raise ValueError(f"unexpected model SHA-256: {digest}")
    model = json.loads(raw)
    operations_map = model["operations"]
    shapes_map = model["shapes"]
    operations = sorted(operations_map)
    shapes = sorted(shapes_map)
    if len(operations) != EXPECTED_OPERATIONS:
        raise ValueError("unexpected S3 operation count")
    if len(shapes) != EXPECTED_SHAPES:
        raise ValueError("unexpected S3 shape count")

    shape_number = {name: index for index, name in enumerate(shapes, 1)}
    operation_literal = {
        name: ada_name(name, "_Operation") for name in operations
    }
    if len(set(value.lower() for value in operation_literal.values())) != len(
        operation_literal
    ):
        raise ValueError("Ada operation identifier collision")

    spec = [
        "--  Generated by tools/generate-s3-model.py; do not edit.",
        "--  Source: pinned botocore service-2.json recorded below.",
        "pragma Style_Checks (Off);",
        "package Flyology.Object_Storage.S3.Model",
        "  with SPARK_Mode => On",
        "is",
        "",
        f"   Model_SHA256 : constant String := {quote(digest)};",
        f"   Operation_Count : constant := {len(operations)};",
        f"   Shape_Count : constant := {len(shapes)};",
        "",
        "   --  Identifiers for operations in the pinned S3 model.",
    ]
    for name in operations:
        if name in OPERATION_DOCUMENTATION:
            spec.extend(
                operation_documentation(
                    operation_literal[name], OPERATION_DOCUMENTATION[name]
                )
            )
    spec.extend(
        [
            "   type Operation_Id is",
            "     (" + operation_literal[operations[0]] + ",",
        ]
    )
    for name in operations[1:-1]:
        spec.append("      " + operation_literal[name] + ",")
    spec.append("      " + operation_literal[operations[-1]] + ");")
    spec.extend(
        [
            "",
            "   type HTTP_Method is",
            "     (Delete_Method, Get_Method, Head_Method, Post_Method,",
            "      Put_Method);",
            "",
            "   type Shape_Kind is",
            "     (Blob_Shape, Boolean_Shape, Integer_Shape, List_Shape,",
            "      Long_Shape, Map_Shape, String_Shape, Structure_Shape,",
            "      Timestamp_Shape);",
            "",
            "   type Member_Location is",
            "     (Body_Location, Header_Location, Headers_Location,",
            "      Query_Location, URI_Location);",
            "",
            "   subtype Shape_Reference is Natural range 0 .. Shape_Count;",
            "   subtype Shape_Index is Shape_Reference range 1 .. Shape_Count;",
            "   No_Shape : constant Shape_Reference := 0;",
            "",
            "   function Operation_Name (Operation : Operation_Id) return String;",
            "   function Method (Operation : Operation_Id) return HTTP_Method;",
            "   function Request_URI (Operation : Operation_Id) return String;",
            "   function Response_Code (Operation : Operation_Id) return Positive;",
            "   function Input_Shape",
            "     (Operation : Operation_Id) return Shape_Reference;",
            "   function Output_Shape",
            "     (Operation : Operation_Id) return Shape_Reference;",
            "   function Error_Count (Operation : Operation_Id) return Natural;",
            "   function Error_Shape",
            "     (Operation : Operation_Id; Index : Positive)",
            "      return Shape_Reference",
            "   with Pre => Index <= Error_Count (Operation);",
            "   function Unsigned_Payload",
            "     (Operation : Operation_Id) return Boolean;",
            "   function Authentication_Type",
            "     (Operation : Operation_Id) return String;",
            "   function Request_Checksum_Required",
            "     (Operation : Operation_Id) return Boolean;",
            "   function Request_Checksum_Algorithm_Member",
            "     (Operation : Operation_Id) return String;",
            "   function Request_Validation_Mode_Member",
            "     (Operation : Operation_Id) return String;",
            "   function Response_Checksum_Algorithms",
            "     (Operation : Operation_Id) return String;",
            "",
            "   function Shape_Name (Shape : Shape_Index) return String;",
            "   function Kind (Shape : Shape_Index) return Shape_Kind;",
            "   function Location_Name (Shape : Shape_Index) return String;",
            "   function Payload_Member (Shape : Shape_Index) return String;",
            "   function Timestamp_Format (Shape : Shape_Index) return String;",
            "   function Pattern (Shape : Shape_Index) return String;",
            "   function Minimum (Shape : Shape_Index) return String;",
            "   function Maximum (Shape : Shape_Index) return String;",
            "   function Is_Flattened (Shape : Shape_Index) return Boolean;",
            "   function Is_Sensitive (Shape : Shape_Index) return Boolean;",
            "   function XML_Namespace (Shape : Shape_Index) return String;",
            "   function List_Member_Shape",
            "     (Shape : Shape_Index) return Shape_Reference;",
            "   function Map_Key_Shape",
            "     (Shape : Shape_Index) return Shape_Reference;",
            "   function Map_Value_Shape",
            "     (Shape : Shape_Index) return Shape_Reference;",
            "   function Enumeration_Count (Shape : Shape_Index) return Natural;",
            "   function Enumeration_Value",
            "     (Shape : Shape_Index; Index : Positive) return String",
            "   with Pre => Index <= Enumeration_Count (Shape);",
            "",
            "   function Member_Count (Shape : Shape_Index) return Natural;",
            "   function Member_Name",
            "     (Shape : Shape_Index; Member : Positive) return String",
            "   with Pre => Member <= Member_Count (Shape);",
            "   function Member_Shape",
            "     (Shape : Shape_Index; Member : Positive) return Shape_Index",
            "   with Pre => Member <= Member_Count (Shape);",
            "   function Location",
            "     (Shape : Shape_Index; Member : Positive) return Member_Location",
            "   with Pre => Member <= Member_Count (Shape);",
            "   function Member_Location_Name",
            "     (Shape : Shape_Index; Member : Positive) return String",
            "   with Pre => Member <= Member_Count (Shape);",
            "   function Member_Required",
            "     (Shape : Shape_Index; Member : Positive) return Boolean",
            "   with Pre => Member <= Member_Count (Shape);",
            "   function Member_Flattened",
            "     (Shape : Shape_Index; Member : Positive) return Boolean",
            "   with Pre => Member <= Member_Count (Shape);",
            "   function Member_Streaming",
            "     (Shape : Shape_Index; Member : Positive) return Boolean",
            "   with Pre => Member <= Member_Count (Shape);",
            "   function Member_XML_Attribute",
            "     (Shape : Shape_Index; Member : Positive) return Boolean",
            "   with Pre => Member <= Member_Count (Shape);",
            "   function Member_XML_Namespace",
            "     (Shape : Shape_Index; Member : Positive) return String",
            "   with Pre => Member <= Member_Count (Shape);",
            "   function Member_Context_Parameter",
            "     (Shape : Shape_Index; Member : Positive) return String",
            "   with Pre => Member <= Member_Count (Shape);",
            "",
            "end Flyology.Object_Storage.S3.Model;",
            "",
        ]
    )

    body = [
        "--  Generated by tools/generate-s3-model.py; do not edit.",
        "pragma Style_Checks (Off);",
        "package body Flyology.Object_Storage.S3.Model",
        "  with SPARK_Mode => On",
        "is",
        "",
    ]

    body += line_case_function(
        "Operation_Name",
        "Operation : Operation_Id",
        "String",
        [(operation_literal[name], quote(name)) for name in operations],
    )
    method_literal = {
        "DELETE": "Delete_Method",
        "GET": "Get_Method",
        "HEAD": "Head_Method",
        "POST": "Post_Method",
        "PUT": "Put_Method",
    }
    body += line_case_function(
        "Method",
        "Operation : Operation_Id",
        "HTTP_Method",
        [
            (operation_literal[name], method_literal[operations_map[name]["http"]["method"]])
            for name in operations
        ],
    )
    body += line_case_function(
        "Request_URI",
        "Operation : Operation_Id",
        "String",
        [
            (operation_literal[name], quote(operations_map[name]["http"]["requestUri"]))
            for name in operations
        ],
    )
    body += line_case_function(
        "Response_Code",
        "Operation : Operation_Id",
        "Positive",
        [
            (
                operation_literal[name],
                str(operations_map[name]["http"].get("responseCode", 200)),
            )
            for name in operations
        ],
    )
    for function_name, field in (("Input_Shape", "input"), ("Output_Shape", "output")):
        body += line_case_function(
            function_name,
            "Operation : Operation_Id",
            "Shape_Reference",
            [
                (
                    operation_literal[name],
                    str(shape_number.get(operations_map[name].get(field, {}).get("shape", ""), 0)),
                )
                for name in operations
            ],
        )
    errors = {
        name: [str(shape_number[item["shape"]]) for item in operations_map[name].get("errors", [])]
        for name in operations
    }
    body += line_case_function(
        "Error_Count",
        "Operation : Operation_Id",
        "Natural",
        [(operation_literal[name], str(len(errors[name]))) for name in operations],
    )
    body += operation_nested_function(
        "Error_Shape", "Shape_Reference", operations, errors, "No_Shape"
    )

    operation_simple = [
        ("Unsigned_Payload", "Boolean", lambda op: bool_image(op.get("unsignedPayload"))),
        ("Authentication_Type", "String", lambda op: quote(op.get("authtype", ""))),
        (
            "Request_Checksum_Required",
            "Boolean",
            lambda op: bool_image(op.get("httpChecksum", {}).get("requestChecksumRequired")),
        ),
        (
            "Request_Checksum_Algorithm_Member",
            "String",
            lambda op: quote(op.get("httpChecksum", {}).get("requestAlgorithmMember", "")),
        ),
        (
            "Request_Validation_Mode_Member",
            "String",
            lambda op: quote(op.get("httpChecksum", {}).get("requestValidationModeMember", "")),
        ),
        (
            "Response_Checksum_Algorithms",
            "String",
            lambda op: quote(";".join(op.get("httpChecksum", {}).get("responseAlgorithms", []))),
        ),
    ]
    for name, result, value in operation_simple:
        body += line_case_function(
            name,
            "Operation : Operation_Id",
            result,
            [(operation_literal[op], value(operations_map[op])) for op in operations],
        )

    body += line_case_function(
        "Shape_Name",
        "Shape : Shape_Index",
        "String",
        [(str(shape_number[name]), quote(name)) for name in shapes],
    )
    kind_literal = {
        "blob": "Blob_Shape",
        "boolean": "Boolean_Shape",
        "integer": "Integer_Shape",
        "list": "List_Shape",
        "long": "Long_Shape",
        "map": "Map_Shape",
        "string": "String_Shape",
        "structure": "Structure_Shape",
        "timestamp": "Timestamp_Shape",
    }
    shape_simple = [
        ("Kind", "Shape_Kind", lambda shape: kind_literal[shape["type"]]),
        ("Location_Name", "String", lambda shape: quote(shape.get("locationName", ""))),
        ("Payload_Member", "String", lambda shape: quote(shape.get("payload", ""))),
        ("Timestamp_Format", "String", lambda shape: quote(shape.get("timestampFormat", ""))),
        ("Pattern", "String", lambda shape: quote(shape.get("pattern", ""))),
        ("Minimum", "String", lambda shape: quote(str(shape["min"])) if "min" in shape else quote("")),
        ("Maximum", "String", lambda shape: quote(str(shape["max"])) if "max" in shape else quote("")),
        ("Is_Flattened", "Boolean", lambda shape: bool_image(shape.get("flattened"))),
        ("Is_Sensitive", "Boolean", lambda shape: bool_image(shape.get("sensitive"))),
        (
            "XML_Namespace",
            "String",
            lambda shape: quote(shape.get("xmlNamespace", {}).get("uri", "")),
        ),
        (
            "List_Member_Shape",
            "Shape_Reference",
            lambda shape: str(shape_number.get(shape.get("member", {}).get("shape", ""), 0)),
        ),
        (
            "Map_Key_Shape",
            "Shape_Reference",
            lambda shape: str(shape_number.get(shape.get("key", {}).get("shape", ""), 0)),
        ),
        (
            "Map_Value_Shape",
            "Shape_Reference",
            lambda shape: str(shape_number.get(shape.get("value", {}).get("shape", ""), 0)),
        ),
        ("Enumeration_Count", "Natural", lambda shape: str(len(shape.get("enum", [])))),
        ("Member_Count", "Natural", lambda shape: str(len(shape.get("members", {})))),
    ]
    for name, result, value in shape_simple:
        body += line_case_function(
            name,
            "Shape : Shape_Index",
            result,
            [(str(shape_number[shape]), value(shapes_map[shape])) for shape in shapes],
        )

    enumeration_entries = [
        (str(shape_number[name]), [quote(item) for item in shapes_map[name].get("enum", [])])
        for name in shapes
        if shapes_map[name].get("enum")
    ]
    body += nested_case_function(
        "Enumeration_Value", "String", enumeration_entries, quote(""),
        index_name="Index"
    )

    member_shapes: list[tuple[str, list[tuple[str, dict[str, object]]]]] = []
    for shape_name in shapes:
        members = list(shapes_map[shape_name].get("members", {}).items())
        if members:
            member_shapes.append((str(shape_number[shape_name]), members))

    locations = {
        "body": "Body_Location",
        "header": "Header_Location",
        "headers": "Headers_Location",
        "querystring": "Query_Location",
        "uri": "URI_Location",
    }
    member_functions = [
        ("Member_Name", "String", lambda name, member, shape: quote(name), quote("")),
        (
            "Member_Shape",
            "Shape_Index",
            lambda name, member, shape: str(shape_number[member["shape"]]),
            "Shape_Index'First",
        ),
        (
            "Location",
            "Member_Location",
            lambda name, member, shape: locations[member.get("location", "body")],
            "Body_Location",
        ),
        (
            "Member_Location_Name",
            "String",
            lambda name, member, shape: quote(member.get("locationName", name)),
            quote(""),
        ),
        (
            "Member_Required",
            "Boolean",
            lambda name, member, shape: bool_image(name in shape.get("required", [])),
            "False",
        ),
        (
            "Member_Flattened",
            "Boolean",
            lambda name, member, shape: bool_image(member.get("flattened")),
            "False",
        ),
        (
            "Member_Streaming",
            "Boolean",
            lambda name, member, shape: bool_image(member.get("streaming")),
            "False",
        ),
        (
            "Member_XML_Attribute",
            "Boolean",
            lambda name, member, shape: bool_image(member.get("xmlAttribute")),
            "False",
        ),
        (
            "Member_XML_Namespace",
            "String",
            lambda name, member, shape: quote(member.get("xmlNamespace", {}).get("uri", "")),
            quote(""),
        ),
        (
            "Member_Context_Parameter",
            "String",
            lambda name, member, shape: quote(member.get("contextParam", {}).get("name", "")),
            quote(""),
        ),
    ]
    for function_name, result, value, default in member_functions:
        entries: list[tuple[str, list[str]]] = []
        for shape_number_text, members in member_shapes:
            shape = shapes_map[shapes[int(shape_number_text) - 1]]
            entries.append(
                (
                    shape_number_text,
                    [value(member_name, member, shape) for member_name, member in members],
                )
            )
        body += nested_case_function(function_name, result, entries, default)

    body.extend(("end Flyology.Object_Storage.S3.Model;", ""))
    return "\n".join(spec), "\n".join(body)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("model", type=pathlib.Path)
    parser.add_argument("--output-dir", type=pathlib.Path, required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    spec, body = generate(args.model)
    outputs = {
        args.output_dir / "flyology-object_storage-s3-model.ads": spec,
        args.output_dir / "flyology-object_storage-s3-model.adb": body,
    }
    if args.check:
        failed = False
        for path, expected in outputs.items():
            actual = path.read_text() if path.exists() else ""
            if actual != expected:
                print(f"generated S3 model is stale: {path}", file=sys.stderr)
                failed = True
        return 1 if failed else 0
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for path, value in outputs.items():
        with tempfile.NamedTemporaryFile(
            "w", encoding="utf-8", dir=path.parent, delete=False
        ) as stream:
            stream.write(value)
            temporary = pathlib.Path(stream.name)
        temporary.replace(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
