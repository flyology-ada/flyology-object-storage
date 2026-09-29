#!/usr/bin/env python3
"""Exhaustive differential check of the generated S3 model descriptor.

Adversarial verification for review area MODEL.  This program deliberately
does NOT call ``tools/generate-s3-model.py``; regenerating with the generator
would only prove the generator is a function.  It parses

  * the pinned botocore model  ``review/baseline/service-2.json``
  * the committed descriptor   ``src/flyology-object_storage-s3-model.adb``
  * the committed spec         ``src/flyology-object_storage-s3-model.ads``

independently, reconstructs from the Ada source text every attribute the
descriptor claims, derives the expected value from the JSON with the REST-XML
rules written out here, and compares the two for every operation, every shape,
every structure member and every enumeration value.  Attributes the descriptor
deliberately does not expose are reported in an "omitted attributes" summary
instead of as mismatches.

It also cross-checks the hard-coded member ordinals in the descriptor's
consumers under ``src/*.adb``: it evaluates each consumer's shape expression
against the JSON (operation input/output shape, member ordinal, list item
shape) and prints the member every literal ordinal actually names, together
with the identifier or header name the call site uses, so an off-by-one is
visible in the table rather than only in a runtime failure.

Exit status: 0 when no mismatch was found, 1 otherwise, 2 on a missing input.

Usage:  python3 tests/repros/python/model_differential.py [repo-root]

This file lives under ``tests/repros/python/`` and is therefore ignored by
``tests/repros/run-all.sh``, which only scans ``src/``.
"""

from __future__ import annotations

import hashlib
import json
import pathlib
import re
import sys
from collections import Counter

# --------------------------------------------------------------------------
# Problem report collection
# --------------------------------------------------------------------------

MISMATCHES: list[str] = []
OMITTED: list[str] = []
NOTES: list[str] = []


def mismatch(subject: str, attribute: str, json_value: object,
             ada_value: object) -> None:
    MISMATCHES.append(
        f"MISMATCH {subject} :: {attribute}: json={json_value!r} "
        f"ada={ada_value!r}"
    )


def note(text: str) -> None:
    NOTES.append(text)


# --------------------------------------------------------------------------
# JSON loading (duplicate-key aware, order preserving)
# --------------------------------------------------------------------------

DUPLICATE_KEYS: list[str] = []


def _pairs_hook(pairs):
    seen = set()
    for key, _ in pairs:
        if key in seen:
            DUPLICATE_KEYS.append(key)
        seen.add(key)
    return dict(pairs)


def load_model(path: pathlib.Path):
    raw = path.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    model = json.loads(raw.decode("utf-8"), object_pairs_hook=_pairs_hook)
    return raw, digest, model


# --------------------------------------------------------------------------
# Ada lexical helpers
# --------------------------------------------------------------------------

def ada_string_value(literal: str) -> str:
    """Decode an Ada string literal.  Raises on a malformed literal."""
    if len(literal) < 2 or literal[0] != '"' or literal[-1] != '"':
        raise ValueError(f"not an Ada string literal: {literal!r}")
    inner = literal[1:-1]
    out = []
    index = 0
    while index < len(inner):
        char = inner[index]
        if char == '"':
            if index + 1 >= len(inner) or inner[index + 1] != '"':
                raise ValueError(f"unpaired quote in literal: {literal!r}")
            out.append('"')
            index += 2
            continue
        out.append(char)
        index += 1
    return "".join(out)


def decode_value(text: str):
    """Decode one Ada ``return`` expression emitted by the generator."""
    text = text.strip()
    if text.startswith('"'):
        return ada_string_value(text)
    if text == "True":
        return True
    if text == "False":
        return False
    if re.fullmatch(r"[0-9_]+", text):
        return int(text.replace("_", ""))
    return text  # enumeration literal / No_Shape / Shape_Index'First


# --------------------------------------------------------------------------
# Ada body parser
#
# The descriptor body is a sequence of case functions.  A "flat" function has
# one ``when KEY => return VALUE;`` arm per key; a "nested" function has an
# inner ``case Member/Index is`` per key plus one ``when others`` default at
# each level.  Anything the parser does not recognise raises, so a layout
# change cannot be silently mis-read as agreement.
# --------------------------------------------------------------------------

FLAT: dict[str, dict[str, object]] = {}
NESTED: dict[str, dict[str, list[object]]] = {}
NESTED_DEFAULT: dict[str, object] = {}
PARSE_STATISTICS: dict[str, int] = {}


def parse_body(path: pathlib.Path) -> None:
    lines = path.read_text(encoding="utf-8").split("\n")
    PARSE_STATISTICS["return_statements"] = sum(
        1 for line in lines if line.strip().startswith("return "))
    PARSE_STATISTICS["default_arms"] = sum(
        1 for line in lines if line.strip() == "when others =>")
    index = 0
    total = len(lines)
    while index < total:
        line = lines[index]
        start = re.match(r"^   function ([A-Za-z0-9_]+)(?: \(|$)", line)
        if start is None:
            index += 1
            continue
        name = start.group(1)
        index += 1
        while index < total and not re.match(r"^      case ([A-Za-z_]+) is$",
                                             lines[index]):
            if re.match(rf"^   end {name};$", lines[index]):
                raise ValueError(f"{name}: no case statement")
            index += 1
        if index >= total:
            raise ValueError(f"{name}: truncated")
        index += 1
        flat: dict[str, object] = {}
        nested: dict[str, list[object]] = {}
        while index < total:
            line = lines[index]
            if line == "      end case;":
                index += 1
                break
            outer = re.match(r"^         when (.+) =>$", line)
            if outer is None:
                raise ValueError(f"{name}: unexpected line {index + 1}: "
                                 f"{line!r}")
            key = outer.group(1)
            index += 1
            simple = re.match(r"^            return (.*);$", lines[index])
            if simple is not None:
                value = decode_value(simple.group(1))
                if key == "others":
                    NESTED_DEFAULT[name] = value
                else:
                    if key in flat:
                        raise ValueError(f"{name}: duplicate key {key}")
                    flat[key] = value
                index += 1
                continue
            inner_head = re.match(r"^            case ([A-Za-z_]+) is$",
                                  lines[index])
            if inner_head is None:
                raise ValueError(f"{name}: unexpected line {index + 1}: "
                                 f"{lines[index]!r}")
            index += 1
            values: list[object] = []
            expected = 1
            while index < total:
                inner = re.match(r"^               when (.+) =>$",
                                 lines[index])
                if inner is None:
                    raise ValueError(f"{name}: unexpected line {index + 1}")
                inner_key = inner.group(1)
                index += 1
                ret = re.match(r"^                  return (.*);$",
                               lines[index])
                if ret is None:
                    raise ValueError(f"{name}: unexpected line {index + 1}")
                value = decode_value(ret.group(1))
                index += 1
                if inner_key == "others":
                    NESTED_DEFAULT[name] = value
                    if lines[index] != "            end case;":
                        raise ValueError(f"{name}: missing inner end case")
                    index += 1
                    break
                if inner_key != str(expected):
                    raise ValueError(
                        f"{name}: non-sequential inner key {inner_key!r} "
                        f"at line {index}")
                expected += 1
                values.append(value)
            if key in nested:
                raise ValueError(f"{name}: duplicate key {key}")
            nested[key] = values
        while index < total and lines[index] != f"   end {name};":
            index += 1
        index += 1
        if nested:
            NESTED[name] = nested
        else:
            FLAT[name] = flat


# --------------------------------------------------------------------------
# Ada spec parser
# --------------------------------------------------------------------------

def parse_spec(path: pathlib.Path) -> dict:
    text = path.read_text(encoding="utf-8")
    lines = text.split("\n")
    out: dict = {}

    digest = re.search(r'Model_SHA256 : constant String := "([0-9a-f]+)";',
                       text)
    out["sha256"] = digest.group(1) if digest else None
    for key, ada in (("operation_count", "Operation_Count"),
                     ("shape_count", "Shape_Count")):
        found = re.search(rf"{ada} : constant := (\d+);", text)
        out[key] = int(found.group(1)) if found else None

    def enum_literals(type_name: str) -> list[str]:
        for index, line in enumerate(lines):
            if line == f"   type {type_name} is":
                break
        else:
            raise ValueError(f"no type {type_name}")
        chunk: list[str] = []
        index += 1
        while index < len(lines):
            chunk.append(lines[index])
            if lines[index].rstrip().endswith(");"):
                break
            index += 1
        else:
            raise ValueError(f"unterminated type {type_name}")
        body = " ".join(chunk).strip()
        if not body.startswith("(") or not body.endswith(");"):
            raise ValueError(f"unexpected {type_name} declaration: {body!r}")
        body = body[1:-2]
        return [item.strip() for item in body.split(",") if item.strip()]

    out["operations"] = enum_literals("Operation_Id")
    out["methods"] = enum_literals("HTTP_Method")
    out["kinds"] = enum_literals("Shape_Kind")
    out["locations"] = enum_literals("Member_Location")

    # Declaration text of every visible function, so preconditions can be
    # checked (a nested accessor without a Pre would let the "others" default
    # answer for an out-of-range index).
    declarations: dict[str, str] = {}
    index = 0
    while index < len(lines):
        head = re.match(r"^   function ([A-Za-z0-9_]+)(?: |$|\()",
                        lines[index])
        if head is None:
            index += 1
            continue
        chunk = [lines[index]]
        while index < len(lines) and not lines[index].rstrip().endswith(";"):
            index += 1
            chunk.append(lines[index])
        declarations[head.group(1)] = " ".join(chunk)
        index += 1
    out["declarations"] = declarations
    return out


# --------------------------------------------------------------------------
# Independent derivation of the expected Ada spelling
# --------------------------------------------------------------------------

def expected_operation_literal(name: str) -> str:
    """CamelCase -> Ada identifier, the descriptor's documented convention."""
    value = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", name)
    value = re.sub(r"[^A-Za-z0-9]+", "_", value).strip("_")
    if not value or value[0].isdigit():
        value = "N_" + value
    return value + "_Operation"


METHOD_LITERAL = {
    "DELETE": "Delete_Method",
    "GET": "Get_Method",
    "HEAD": "Head_Method",
    "POST": "Post_Method",
    "PUT": "Put_Method",
}

KIND_LITERAL = {
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

LOCATION_LITERAL = {
    "body": "Body_Location",
    "header": "Header_Location",
    "headers": "Headers_Location",
    "querystring": "Query_Location",
    "uri": "URI_Location",
}

# Every attribute name the pinned model uses anywhere, so a new attribute in a
# future model bump is reported rather than silently ignored.
KNOWN_SHAPE_KEYS = {
    "type", "members", "member", "key", "value", "enum", "max", "min",
    "pattern", "documentation", "flattened", "sensitive", "locationName",
    "xmlNamespace", "payload", "required", "timestampFormat", "error",
    "exception", "box", "union", "streaming", "requiresLength", "deprecated",
    "deprecatedMessage", "xmlOrder", "eventstream", "event",
    "idempotencyToken", "contextParam", "hostLabel", "jsonvalue",
    "xmlAttribute", "deprecatedSince", "enumType", "fault", "retryable", "synthetic",
}

KNOWN_MEMBER_KEYS = {
    "shape", "documentation", "location", "locationName", "flattened",
    "streaming", "xmlNamespace", "contextParam", "hostLabel",
    "idempotencyToken", "xmlAttribute", "deprecated", "deprecatedMessage",
    "queryName", "box", "eventpayload", "eventheader", "jsonvalue",
    "requiresLength", "xmlName", "staticContextParams", "deprecatedSince",
}

KNOWN_OPERATION_KEYS = {
    "name", "http", "input", "output", "errors", "documentation",
    "documentationUrl", "alias", "httpChecksum", "authtype",
    "unsignedPayload", "staticContextParams", "deprecated",
    "deprecatedMessage", "endpoint", "requestcompression",
    "httpChecksumRequired", "idempotent",
}

NESTED_ACCESSORS = (
    "Error_Shape", "Enumeration_Value", "Member_Name", "Member_Shape",
    "Location", "Member_Location_Name", "Member_Required",
    "Member_Flattened", "Member_Streaming", "Member_XML_Attribute",
    "Member_XML_Namespace", "Member_Context_Parameter",
)

OPERATION_FUNCTIONS = (
    "Operation_Name", "Method", "Request_URI", "Response_Code",
    "Input_Shape", "Output_Shape", "Error_Count", "Unsigned_Payload",
    "Authentication_Type", "Request_Checksum_Required",
    "Request_Checksum_Algorithm_Member", "Request_Validation_Mode_Member",
    "Response_Checksum_Algorithms",
)


# --------------------------------------------------------------------------
# The differential
# --------------------------------------------------------------------------

def main() -> int:
    root = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else \
        pathlib.Path(__file__).resolve().parents[3]
    model_path = root / "review" / "baseline" / "service-2.json"
    body_path = root / "src" / "flyology-object_storage-s3-model.adb"
    spec_path = root / "src" / "flyology-object_storage-s3-model.ads"
    for path in (model_path, body_path, spec_path):
        if not path.is_file():
            print(f"missing input: {path}", file=sys.stderr)
            return 2

    raw, digest, model = load_model(model_path)
    parse_body(body_path)
    spec = parse_spec(spec_path)

    operations_map = model["operations"]
    shapes_map = model["shapes"]
    operations = sorted(operations_map)
    shapes = sorted(shapes_map)
    shape_number = {name: index for index, name in enumerate(shapes, 1)}

    print("=" * 74)
    print("model differential: pinned JSON vs committed Ada descriptor")
    print("=" * 74)
    print(f"model      : {model_path}")
    print(f"descriptor : {body_path}")
    print(f"sha256     : {digest}")
    if DUPLICATE_KEYS:
        note("JSON contains duplicate object keys: "
             + ", ".join(sorted(set(DUPLICATE_KEYS))))

    # ---- header constants -------------------------------------------------
    if spec["sha256"] != digest:
        mismatch("<spec>", "Model_SHA256", digest, spec["sha256"])
    if spec["operation_count"] != len(operations):
        mismatch("<spec>", "Operation_Count", len(operations),
                 spec["operation_count"])
    if spec["shape_count"] != len(shapes):
        mismatch("<spec>", "Shape_Count", len(shapes), spec["shape_count"])

    # ---- operation identifiers -------------------------------------------
    expected_literals = [expected_operation_literal(name)
                         for name in operations]
    if len(spec["operations"]) != len(expected_literals):
        mismatch("Operation_Id", "literal count", len(expected_literals),
                 len(spec["operations"]))
    for index, want in enumerate(expected_literals):
        got = spec["operations"][index] if index < len(spec["operations"]) \
            else "<absent>"
        if want != got:
            mismatch(f"Operation_Id[{index + 1}]", "literal", want, got)
    lowered = Counter(item.lower() for item in expected_literals)
    for literal, count in lowered.items():
        if count > 1:
            mismatch("Operation_Id", "case-insensitive collision", literal,
                     count)
    literal_of = dict(zip(operations, spec["operations"]))

    # ---- Ada enumeration domains -----------------------------------------
    if sorted(spec["methods"]) != sorted(set(METHOD_LITERAL.values())):
        mismatch("HTTP_Method", "literals",
                 sorted(set(METHOD_LITERAL.values())), sorted(spec["methods"]))
    if sorted(spec["kinds"]) != sorted(set(KIND_LITERAL.values())):
        mismatch("Shape_Kind", "literals", sorted(set(KIND_LITERAL.values())),
                 sorted(spec["kinds"]))
    if sorted(spec["locations"]) != sorted(set(LOCATION_LITERAL.values())):
        mismatch("Member_Location", "literals",
                 sorted(set(LOCATION_LITERAL.values())),
                 sorted(spec["locations"]))

    # ---- indexed accessors must be guarded --------------------------------
    for function in NESTED_ACCESSORS:
        declaration = spec["declarations"].get(function)
        if declaration is None:
            mismatch("<spec>", f"{function} declaration", "present",
                     "<absent>")
        elif "with Pre =>" not in declaration:
            mismatch("<spec>", f"{function} precondition",
                     "Index/Member bounded by the count accessor",
                     "<no Pre; the case default would answer>")

    # ---- unexpected JSON attributes --------------------------------------
    seen_operation_keys: set[str] = set()
    seen_shape_keys: set[str] = set()
    seen_member_keys: set[str] = set()
    for name in operations:
        seen_operation_keys |= set(operations_map[name])
    for name in shapes:
        shape = shapes_map[name]
        seen_shape_keys |= set(shape)
        for member in shape.get("members", {}).values():
            seen_member_keys |= set(member)
        for role in ("member", "key", "value"):
            if isinstance(shape.get(role), dict):
                seen_member_keys |= set(shape[role])
    for label, seen, known in (
            ("operation", seen_operation_keys, KNOWN_OPERATION_KEYS),
            ("shape", seen_shape_keys, KNOWN_SHAPE_KEYS),
            ("member", seen_member_keys, KNOWN_MEMBER_KEYS)):
        unknown = seen - known
        if unknown:
            note(f"unclassified {label} attributes in the model: "
                 + ", ".join(sorted(unknown)))

    # ---- operation-level differential ------------------------------------
    counts: Counter = Counter()
    default_response_code: list[str] = []
    reachable: set[str] = set()

    def flat_operation(function: str, operation: str):
        table = FLAT.get(function)
        if table is None:
            mismatch(operation, function, "<function>", "<absent from body>")
            return None
        return table.get(literal_of[operation], "<no case arm>")

    def visit(shape_name: str) -> None:
        pending = [shape_name]
        while pending:
            current = pending.pop()
            if current in reachable:
                continue
            reachable.add(current)
            shape = shapes_map[current]
            for member in shape.get("members", {}).values():
                pending.append(member["shape"])
            for role in ("member", "key", "value"):
                if isinstance(shape.get(role), dict):
                    pending.append(shape[role]["shape"])

    for name in operations:
        operation = operations_map[name]
        subject = f"operation {name}"
        counts["operations"] += 1

        if operation.get("name") not in (None, name):
            mismatch(subject, "operations key vs .name", name,
                     operation.get("name"))

        got = flat_operation("Operation_Name", name)
        if got != name:
            mismatch(subject, "Operation_Name", name, got)

        http = operation.get("http", {})
        method = http.get("method")
        if method not in METHOD_LITERAL:
            mismatch(subject, "http.method", method, "<unmappable>")
        else:
            got = flat_operation("Method", name)
            if got != METHOD_LITERAL[method]:
                mismatch(subject, "Method", METHOD_LITERAL[method], got)

        got = flat_operation("Request_URI", name)
        if got != http.get("requestUri"):
            mismatch(subject, "Request_URI", http.get("requestUri"), got)

        if "responseCode" in http:
            want_code = http["responseCode"]
            if not isinstance(want_code, int) or isinstance(want_code, bool):
                mismatch(subject, "http.responseCode type",
                         type(want_code).__name__, "<expected int>")
        else:
            want_code = 200
            default_response_code.append(name)
        got = flat_operation("Response_Code", name)
        if got != want_code:
            mismatch(subject, "Response_Code", want_code, got)

        for function, field in (("Input_Shape", "input"),
                                ("Output_Shape", "output")):
            binding = operation.get(field, {})
            reference = binding.get("shape")
            got = flat_operation(function, name)
            if reference:
                if reference not in shapes_map:
                    mismatch(subject, f"{field}.shape", reference,
                             "<undefined shape>")
                else:
                    if got != shape_number[reference]:
                        mismatch(subject, function,
                                 f"{reference} (#{shape_number[reference]})",
                                 got)
                    visit(reference)
            elif got != 0:
                mismatch(subject, function, "0 (No_Shape)", got)
            extra = set(binding) - {"shape", "locationName", "xmlNamespace",
                                    "documentation", "resultWrapper"}
            if extra:
                note(f"{subject}: unhandled {field} attributes "
                     + ", ".join(sorted(extra)))
            if "locationName" in binding:
                OMITTED.append(f"{subject}.{field}.locationName="
                               f"{binding['locationName']!r}")
            if "xmlNamespace" in binding:
                OMITTED.append(f"{subject}.{field}.xmlNamespace="
                               f"{binding['xmlNamespace']!r}")

        errors = operation.get("errors", [])
        got = flat_operation("Error_Count", name)
        if got != len(errors):
            mismatch(subject, "Error_Count", len(errors), got)
        ada_errors = NESTED.get("Error_Shape", {}).get(literal_of[name], [])
        want_errors = [shape_number[item["shape"]] for item in errors
                       if item["shape"] in shapes_map]
        if ada_errors != want_errors:
            mismatch(subject, "Error_Shape list",
                     [f"{item['shape']}"
                      f"(#{shape_number.get(item['shape'])})"
                      for item in errors], ada_errors)
        for item in errors:
            if item["shape"] not in shapes_map:
                mismatch(subject, "errors[].shape", item["shape"],
                         "<undefined shape>")
                continue
            error_shape = shapes_map[item["shape"]]
            visit(item["shape"])
            counts["error_shapes"] += 1
            status = error_shape.get("error", {}).get("httpStatusCode")
            OMITTED.append(f"{subject}.errors[{item['shape']}]"
                           f".error.httpStatusCode={status!r}")
            if not error_shape.get("exception"):
                note(f"{subject}: error shape {item['shape']} is not "
                     "marked exception")

        got = flat_operation("Unsigned_Payload", name)
        if got is not (operation.get("unsignedPayload") is True):
            mismatch(subject, "Unsigned_Payload",
                     operation.get("unsignedPayload") is True, got)

        got = flat_operation("Authentication_Type", name)
        if got != operation.get("authtype", ""):
            mismatch(subject, "Authentication_Type",
                     operation.get("authtype", ""), got)

        checksum = operation.get("httpChecksum", {})
        extra = set(checksum) - {"requestAlgorithmMember",
                                 "requestChecksumRequired",
                                 "requestValidationModeMember",
                                 "responseAlgorithms"}
        if extra:
            note(f"{subject}: unhandled httpChecksum keys "
                 + ", ".join(sorted(extra)))
        got = flat_operation("Request_Checksum_Required", name)
        if got is not (checksum.get("requestChecksumRequired") is True):
            mismatch(subject, "Request_Checksum_Required",
                     checksum.get("requestChecksumRequired") is True, got)
        got = flat_operation("Request_Checksum_Algorithm_Member", name)
        if got != checksum.get("requestAlgorithmMember", ""):
            mismatch(subject, "Request_Checksum_Algorithm_Member",
                     checksum.get("requestAlgorithmMember", ""), got)
        got = flat_operation("Request_Validation_Mode_Member", name)
        if got != checksum.get("requestValidationModeMember", ""):
            mismatch(subject, "Request_Validation_Mode_Member",
                     checksum.get("requestValidationModeMember", ""), got)
        algorithms = checksum.get("responseAlgorithms", [])
        for algorithm in algorithms:
            if ";" in algorithm:
                mismatch(subject, "responseAlgorithms separator", algorithm,
                         "';' would make the joined image ambiguous")
        got = flat_operation("Response_Checksum_Algorithms", name)
        if got != ";".join(algorithms):
            mismatch(subject, "Response_Checksum_Algorithms",
                     ";".join(algorithms), got)
        if checksum:
            counts["httpChecksum"] += 1
        for key in ("requestAlgorithmMember", "requestValidationModeMember"):
            member_name = checksum.get(key)
            field = "input" if key == "requestAlgorithmMember" else "input"
            reference = operation.get(field, {}).get("shape")
            if member_name and reference in shapes_map and member_name not in \
                    shapes_map[reference].get("members", {}):
                mismatch(subject, f"httpChecksum.{key}", member_name,
                         f"<not a member of {reference}>")

        # Attributes the descriptor does not expose at all.
        if "endpoint" in operation:
            OMITTED.append(f"{subject}.endpoint={operation['endpoint']!r}")
        if "staticContextParams" in operation:
            OMITTED.append(f"{subject}.staticContextParams="
                           f"{sorted(operation['staticContextParams'])}")
        if operation.get("deprecated"):
            OMITTED.append(f"{subject}.deprecated=True")
        if "requestcompression" in operation:
            OMITTED.append(f"{subject}.requestcompression present")
        if "alias" in operation:
            OMITTED.append(f"{subject}.alias={operation['alias']!r}")
        if operation.get("idempotent"):
            OMITTED.append(f"{subject}.idempotent=True")
        if operation.get("httpChecksumRequired"):
            OMITTED.append(f"{subject}.httpChecksumRequired=True")

        # ---- URI label / query-literal consistency (self-derived) --------
        uri = http.get("requestUri", "")
        path_part = uri.split("?", 1)[0]
        labels = [item.rstrip("+") for item in
                  re.findall(r"\{([^}]*)\}", path_part)]
        reference = operation.get("input", {}).get("shape")
        uri_members = []
        if reference in shapes_map:
            for member_name, member in \
                    shapes_map[reference].get("members", {}).items():
                if member.get("location") == "uri":
                    uri_members.append(member.get("locationName", member_name))
        if sorted(labels) != sorted(uri_members):
            mismatch(subject, "uri labels vs uri members", sorted(labels),
                     sorted(uri_members))
        if len(set(labels)) != len(labels):
            mismatch(subject, "duplicate uri label", labels, "<duplicate>")
        if "?" in uri:
            counts["query_literal_uri"] += 1
        if "+}" in uri:
            counts["greedy_uri"] += 1

    print(f"operations checked        : {counts['operations']}")

    # ---- shape-level differential ----------------------------------------
    member_total = 0
    enum_total = 0

    def flat_shape(function: str, number: int):
        table = FLAT.get(function)
        if table is None:
            mismatch(f"<body {function}>", "function", "present",
                     "<absent from body>")
            return "<function absent>"
        return table.get(str(number), "<no case arm>")

    for number, name in enumerate(shapes, 1):
        shape = shapes_map[name]
        subject = f"shape #{number} {name}"

        got = flat_shape("Shape_Name", number)
        if got != name:
            mismatch(subject, "Shape_Name", name, got)

        kind = shape.get("type")
        if kind not in KIND_LITERAL:
            mismatch(subject, "type", kind, "<unmappable>")
        else:
            got = flat_shape("Kind", number)
            if got != KIND_LITERAL[kind]:
                mismatch(subject, "Kind", KIND_LITERAL[kind], got)

        for function, key in (("Location_Name", "locationName"),
                              ("Payload_Member", "payload"),
                              ("Timestamp_Format", "timestampFormat"),
                              ("Pattern", "pattern")):
            want = shape.get(key, "")
            got = flat_shape(function, number)
            if got != want:
                mismatch(subject, function, want, got)
            if key == "timestampFormat" and want:
                counts["timestampFormat"] += 1
            if key == "pattern" and want:
                counts["pattern"] += 1

        if "payload" in shape:
            payload = shape["payload"]
            members = shape.get("members", {})
            if payload not in members:
                mismatch(subject, "payload names a member", payload,
                         sorted(members))
            elif members[payload].get("location") is not None:
                mismatch(subject, "payload member location", "body",
                         members[payload]["location"])
            counts["payload"] += 1

        for function, key in (("Minimum", "min"), ("Maximum", "max")):
            if key in shape:
                value = shape[key]
                if not isinstance(value, int) or isinstance(value, bool):
                    mismatch(subject, f"{key} type", type(value).__name__,
                             "<expected int>")
                want = str(value)
                counts[key] += 1
            else:
                want = ""
            got = flat_shape(function, number)
            if got != want:
                mismatch(subject, function, want, got)

        for function, key in (("Is_Flattened", "flattened"),
                              ("Is_Sensitive", "sensitive")):
            want = shape.get(key) is True
            got = flat_shape(function, number)
            if got is not want:
                mismatch(subject, function, want, got)
            if want and key == "flattened":
                counts["flattened_shapes"] += 1

        namespace = shape.get("xmlNamespace", {})
        if namespace and not isinstance(namespace, dict):
            mismatch(subject, "xmlNamespace form", namespace,
                     "<expected object>")
            namespace = {}
        want = namespace.get("uri", "") if namespace else ""
        got = flat_shape("XML_Namespace", number)
        if got != want:
            mismatch(subject, "XML_Namespace", want, got)
        if want:
            counts["xmlNamespace"] += 1
        if isinstance(namespace, dict) and "prefix" in namespace:
            OMITTED.append(f"{subject}.xmlNamespace.prefix="
                           f"{namespace['prefix']!r}")

        for function, role in (("List_Member_Shape", "member"),
                               ("Map_Key_Shape", "key"),
                               ("Map_Value_Shape", "value")):
            entry = shape.get(role)
            got = flat_shape(function, number)
            if isinstance(entry, dict):
                target = entry.get("shape")
                if target not in shapes_map:
                    mismatch(subject, f"{role}.shape", target,
                             "<undefined shape>")
                elif got != shape_number[target]:
                    mismatch(subject, function,
                             f"{target} (#{shape_number[target]})", got)
                for key in sorted(set(entry) - {"shape", "documentation"}):
                    OMITTED.append(f"{subject}.{role}.{key}={entry[key]!r}")
            elif got != 0:
                mismatch(subject, function, "0 (No_Shape)", got)

        if kind == "list" and not isinstance(shape.get("member"), dict):
            mismatch(subject, "list without member", None, "<missing>")
        if kind == "map" and not (isinstance(shape.get("key"), dict)
                                  and isinstance(shape.get("value"), dict)):
            mismatch(subject, "map without key/value", None, "<missing>")

        enums = shape.get("enum", [])
        enum_total += len(enums)
        got = flat_shape("Enumeration_Count", number)
        if got != len(enums):
            mismatch(subject, "Enumeration_Count", len(enums), got)
        ada_enums = NESTED.get("Enumeration_Value", {}).get(str(number), [])
        if ada_enums != enums:
            mismatch(subject, "Enumeration_Value list", enums, ada_enums)
        if len(set(enums)) != len(enums):
            mismatch(subject, "duplicate enum value", enums, "<duplicate>")
        if len({item.lower() for item in enums}) != len(enums):
            note(f"{subject}: enum values collide case-insensitively")
        if enums:
            counts["enum_shapes"] += 1

        members = shape.get("members", {})
        member_total += len(members)
        got = flat_shape("Member_Count", number)
        if got != len(members):
            mismatch(subject, "Member_Count", len(members), got)
        if members and kind != "structure":
            mismatch(subject, "members on non-structure", kind, "<unexpected>")

        required = shape.get("required", [])
        for entry in required:
            if entry not in members:
                mismatch(subject, "required names a member", entry,
                         sorted(members))

        member_names = list(members)
        for member_name in member_names:
            if members[member_name].get("shape") not in shapes_map:
                mismatch(f"{subject} member {member_name}", "shape",
                         members[member_name].get("shape"),
                         "<undefined shape>")
        expectations = (
            ("Member_Name", member_names),
            ("Member_Shape",
             [shape_number.get(members[m].get("shape"), "<undefined>")
              for m in member_names]),
            ("Location",
             [LOCATION_LITERAL.get(members[m].get("location", "body"),
                                   f"<unmapped:{members[m].get('location')}>")
              for m in member_names]),
            ("Member_Location_Name",
             [members[m].get("locationName", m) for m in member_names]),
            ("Member_Required", [m in required for m in member_names]),
            ("Member_Flattened",
             [members[m].get("flattened") is True for m in member_names]),
            ("Member_Streaming",
             [members[m].get("streaming") is True for m in member_names]),
            ("Member_XML_Attribute",
             [members[m].get("xmlAttribute") is True for m in member_names]),
            ("Member_XML_Namespace",
             [members[m].get("xmlNamespace", {}).get("uri", "")
              if isinstance(members[m].get("xmlNamespace"), dict) else ""
              for m in member_names]),
            ("Member_Context_Parameter",
             [members[m].get("contextParam", {}).get("name", "")
              if isinstance(members[m].get("contextParam"), dict) else ""
              for m in member_names]),
        )
        for function, expected in expectations:
            ada = NESTED.get(function, {}).get(str(number), [])
            if ada == expected:
                continue
            if len(ada) != len(expected):
                mismatch(subject, f"{function} arity", len(expected),
                         len(ada))
            for index, member_name in enumerate(member_names):
                want = expected[index]
                got = ada[index] if index < len(ada) else "<absent>"
                if want != got:
                    mismatch(f"{subject} member {index + 1} {member_name}",
                             function, want, got)

        for member_name, member in members.items():
            where = f"{subject} member {member_name}"
            location = member.get("location", "body")
            if location not in LOCATION_LITERAL:
                mismatch(where, "location", location,
                         "<no Ada Member_Location literal exists>")
            if location == "headers":
                counts["headers_maps"] += 1
            if member.get("streaming"):
                counts["streaming_members"] += 1
            for key in ("xmlName", "idempotencyToken", "hostLabel",
                        "deprecated", "box", "eventpayload", "eventheader",
                        "jsonvalue", "queryName", "requiresLength",
                        "staticContextParams"):
                if key in member and member[key] not in (False, None):
                    OMITTED.append(f"{where}.{key}={member[key]!r}")
            namespace = member.get("xmlNamespace", {})
            if isinstance(namespace, dict) and "prefix" in namespace:
                OMITTED.append(f"{where}.xmlNamespace.prefix="
                               f"{namespace['prefix']!r}")
            if namespace and not isinstance(namespace, dict):
                mismatch(where, "xmlNamespace form", namespace,
                         "<expected object>")
            context = member.get("contextParam")
            if isinstance(context, dict) and set(context) - {"name"}:
                OMITTED.append(f"{where}.contextParam extra keys "
                               f"{sorted(set(context) - {'name'})}")

        for key in ("union", "eventstream", "event", "box", "deprecated",
                    "requiresLength", "xmlOrder", "idempotencyToken",
                    "jsonvalue", "enumType", "streaming", "fault",
                    "retryable", "synthetic"):
            if key in shape and shape[key] not in (False, None):
                OMITTED.append(f"{subject}.{key}={shape[key]!r}")
        if shape.get("error"):
            OMITTED.append(f"{subject}.error={shape['error']!r}")
        if shape.get("exception"):
            OMITTED.append(f"{subject}.exception=True")

    print(f"shapes checked            : {len(shapes)} "
          f"({len(reachable)} reachable from operation "
          f"input/output/errors)")
    print(f"structure members checked : {member_total}")
    print(f"enumeration values checked: {enum_total} "
          f"in {counts['enum_shapes']} shapes")
    print(f"error shape links checked : {counts['error_shapes']} "
          f"({len({item['shape'] for operation in operations_map.values() for item in operation.get('errors', [])})} distinct error shapes)")
    print(f"operations with httpChecksum        : {counts['httpChecksum']}")
    print(f"operations using responseCode 200 default: "
          f"{len(default_response_code)}")
    print(f"requestUri with a query literal     : "
          f"{counts['query_literal_uri']}")
    print(f"requestUri with a greedy label      : {counts['greedy_uri']}")
    print(f"shapes with min / max / pattern     : "
          f"{counts['min']} / {counts['max']} / {counts['pattern']}")
    print(f"shapes with timestampFormat         : "
          f"{counts['timestampFormat']}")
    print(f"shapes with xmlNamespace / flattened: "
          f"{counts['xmlNamespace']} / {counts['flattened_shapes']}")
    print(f"payload shapes / streaming members / header maps: "
          f"{counts['payload']} / {counts['streaming_members']} / "
          f"{counts['headers_maps']}")

    unreachable = set(shapes) - reachable
    if unreachable:
        note(f"{len(unreachable)} shape(s) not reachable from any operation: "
             f"{sorted(unreachable)}")

    # ---- descriptor case-arm coverage ------------------------------------
    shape_domain = {str(index) for index in range(1, len(shapes) + 1)}
    operation_domain = set(spec["operations"])
    for function, table in sorted(FLAT.items()):
        domain = operation_domain if function in OPERATION_FUNCTIONS \
            else shape_domain
        missing = domain - set(table)
        extra = set(table) - domain
        if missing:
            mismatch(f"<body {function}>", "missing case arms", 0,
                     f"{len(missing)} missing, e.g. {sorted(missing)[:5]}")
        if extra:
            mismatch(f"<body {function}>", "extra case arms", 0,
                     sorted(extra)[:5])
    for function, table in sorted(NESTED.items()):
        domain = operation_domain if function == "Error_Shape" \
            else shape_domain
        extra = set(table) - domain
        if extra:
            mismatch(f"<body {function}>", "extra case arms", 0,
                     sorted(extra)[:5])
    expected_functions = set(OPERATION_FUNCTIONS) | set(NESTED_ACCESSORS) | {
        "Shape_Name", "Kind", "Location_Name", "Payload_Member",
        "Timestamp_Format", "Pattern", "Minimum", "Maximum", "Is_Flattened",
        "Is_Sensitive", "XML_Namespace", "List_Member_Shape", "Map_Key_Shape",
        "Map_Value_Shape", "Enumeration_Count", "Member_Count"}
    emitted_functions = set(FLAT) | set(NESTED)
    if emitted_functions != expected_functions:
        mismatch("<body>", "function inventory",
                 sorted(expected_functions - emitted_functions),
                 sorted(emitted_functions - expected_functions))
    print(f"descriptor case functions parsed    : {len(emitted_functions)} "
          f"({len(FLAT)} flat, {len(NESTED)} indexed)")
    value_arms = sum(len(table) for table in FLAT.values()) + sum(
        len(items) for table in NESTED.values() for items in table.values())
    default_arms = PARSE_STATISTICS["default_arms"]
    returns = PARSE_STATISTICS["return_statements"]
    print(f"descriptor case arms compared       : {value_arms} value arms "
          f"+ {default_arms} 'when others' defaults = {returns} of the "
          f"{returns} return statements in the body")
    if value_arms + default_arms != returns:
        mismatch("<body>", "return-statement accounting", returns,
                 f"{value_arms} value arms + {default_arms} defaults "
                 f"(the parser did not read every arm)")

    # ---- string safety ----------------------------------------------------
    emitted: list[tuple[str, str]] = []
    for name in operations:
        operation = operations_map[name]
        emitted.append((f"operation {name} name", name))
        emitted.append((f"operation {name} requestUri",
                        operation.get("http", {}).get("requestUri", "")))
        emitted.append((f"operation {name} authtype",
                        operation.get("authtype", "")))
    for name in shapes:
        shape = shapes_map[name]
        emitted.append((f"shape {name} name", name))
        for key in ("locationName", "payload", "timestampFormat", "pattern"):
            emitted.append((f"shape {name} {key}", shape.get(key, "")))
        for value in shape.get("enum", []):
            emitted.append((f"shape {name} enum", value))
        for member_name, member in shape.get("members", {}).items():
            emitted.append((f"shape {name} member {member_name}",
                            member_name))
            emitted.append((f"shape {name} member {member_name} locationName",
                            member.get("locationName", member_name)))
    unsafe = 0
    for where, value in emitted:
        for char in value:
            if ord(char) < 0x20 or ord(char) > 0x7E:
                mismatch(where, "non-printable/non-ASCII character",
                         repr(char),
                         "<not portably representable in an Ada literal>")
                unsafe += 1
                break
    print(f"strings screened for non-ASCII      : {len(emitted)} "
          f"({unsafe} unsafe)")

    # ---- indexed-accessor defaults ---------------------------------------
    note("indexed-accessor 'when others' defaults (unreachable under the "
         "declared preconditions): "
         + ", ".join(f"{key}={NESTED_DEFAULT[key]!r}"
                     for key in sorted(NESTED_DEFAULT)))

    # ---- consumer ordinal cross-check ------------------------------------
    consumer_problems = consumer_ordinals(root, operations_map, shapes_map)

    # ---- report ----------------------------------------------------------
    print()
    print("-" * 74)
    print("omitted attributes (present in the JSON, absent from the "
          "descriptor)")
    print("-" * 74)
    summarise_omitted()

    if NOTES:
        print()
        print("-" * 74)
        print("notes")
        print("-" * 74)
        for text in NOTES:
            print("  " + text)

    print()
    print("-" * 74)
    print("result")
    print("-" * 74)
    for line in MISMATCHES:
        print(line)
    total = len(MISMATCHES) + consumer_problems
    if total == 0:
        print("no mismatch: the committed descriptor agrees with the pinned "
              "model on every operation, shape, member, enumeration value "
              "and trait checked above, and every literal member ordinal in "
              "src/*.adb names the member its call site expects.")
        return 0
    print(f"{len(MISMATCHES)} descriptor mismatch(es), "
          f"{consumer_problems} consumer ordinal problem(s)")
    return 1


# --------------------------------------------------------------------------
# Omitted-attribute summary
# --------------------------------------------------------------------------

CONSUMER_OF_OMISSION = {
    "errors[*].error.httpStatusCode":
        "a client or server that maps a modeled error shape to an HTTP "
        "status without a hand-written table; no src/ consumer reads "
        "Error_Shape today",
    "exception":
        "a generic modeled-error dispatcher",
    "error":
        "a generic modeled-error dispatcher",
    "endpoint":
        "endpoint host-prefix expansion (WriteGetObjectResponse); the "
        "client lane is 'partial' and the server reads x-amz-request-route "
        "directly",
    "member.locationName":
        "an XML codec that names repeated list elements from the "
        "descriptor; tools/s3_codegen.py reads the pinned JSON directly",
    "key.locationName":
        "a descriptor-driven XML codec for modeled maps",
    "value.locationName":
        "a descriptor-driven XML codec for modeled maps",
    "member.flattened":
        "a descriptor-driven XML codec",
    "xmlNamespace.prefix":
        "an XML serializer emitting a namespace-prefixed attribute name "
        "from the descriptor; the generated serializers resolve the xsi "
        "prefix from the JSON at generation time",
    "input.locationName":
        "a descriptor-driven request-body root element name",
    "output.locationName":
        "a descriptor-driven response-body root element name",
    "idempotencyToken":
        "a client that auto-fills an idempotency token (RenameObject)",
    "deprecated":
        "a deprecation diagnostic",
    "staticContextParams":
        "endpoint-rule evaluation",
    "union":
        "a union-aware codec",
    "box":
        "a boxed-primitive-aware codec",
    "hostLabel":
        "endpoint host-prefix expansion",
    "queryName":
        "a query-protocol serializer (not used by REST-XML)",
    "xmlName":
        "a codec that distinguishes the XML name from the location name",
    "input.xmlNamespace":
        "a descriptor-driven request-body root namespace "
        "(SelectObjectContent); the generated serializers take the "
        "namespace from the JSON at generation time",
    "member.box": "a boxed-primitive-aware codec",
    "member.deprecated": "a deprecation diagnostic",
    "member.eventpayload": "an event-stream codec (SelectObjectContent)",
    "member.hostLabel":
        "endpoint host-prefix expansion (WriteGetObjectResponse "
        "RequestRoute); the server reads x-amz-request-route directly",
    "member.idempotencyToken":
        "a client that auto-fills an idempotency token "
        "(RenameObject ClientToken)",
    "event": "an event-stream codec (SelectObjectContent)",
    "eventstream": "an event-stream codec (SelectObjectContent)",
    "synthetic":
        "nothing; botocore marks AccessDenied as synthesised rather than "
        "modeled",
}


def summarise_omitted() -> None:
    buckets: dict[str, list[str]] = {}
    for entry in OMITTED:
        key = entry.split("=", 1)[0]
        key = re.sub(r"^operation [A-Za-z0-9]+", "", key)
        key = re.sub(r"^shape #\d+ [A-Za-z0-9]+", "", key)
        key = re.sub(r"\berrors\[[^\]]*\]", "errors[*]", key)
        key = re.sub(r"\bmember [A-Za-z0-9]+", "member", key)
        key = key.strip().lstrip(".").strip()
        buckets.setdefault(key or "<root>", []).append(entry)
    if not buckets:
        print("  (none)")
        return
    for key in sorted(buckets):
        entries = buckets[key]
        consumer = CONSUMER_OF_OMISSION.get(key, "no consumer identified")
        print(f"  {key}  x{len(entries)}")
        if len(entries) <= 12:
            for entry in entries:
                print(f"      {entry}")
        else:
            print(f"      example  : {entries[0]}")
        print(f"      needed by: {consumer}")


# --------------------------------------------------------------------------
# Consumer ordinal cross-check
# --------------------------------------------------------------------------


def strip_comments(text: str) -> str:
    """Blank out Ada comments, respecting string and character literals."""
    out: list[str] = []
    for line in text.split("\n"):
        index = 0
        in_string = False
        cut = len(line)
        while index < len(line):
            char = line[index]
            if in_string:
                if char == '"':
                    in_string = False
                index += 1
                continue
            if char == '"':
                in_string = True
                index += 1
                continue
            if char == "'" and index + 2 < len(line) and line[index + 2] == "'":
                index += 3
                continue
            if char == "-" and index + 1 < len(line) and line[index + 1] == "-":
                cut = index
                break
            index += 1
        out.append(line[:cut])
    return "\n".join(out)


def flatten_with_lines(text: str) -> tuple[str, list[int]]:
    """Collapse whitespace runs to one space, keeping a char->line map."""
    out: list[str] = []
    lines: list[int] = []
    line = 1
    pending = False
    for char in text:
        if char == "\n":
            line += 1
            pending = True
            continue
        if char.isspace():
            pending = True
            continue
        if pending and out:
            out.append(" ")
            lines.append(line)
        pending = False
        out.append(char)
        lines.append(line)
    return "".join(out), lines


def split_arguments(text: str) -> list[str]:
    out: list[str] = []
    depth = 0
    current: list[str] = []
    in_string = False
    for char in text:
        if char == '"':
            in_string = not in_string
        if not in_string:
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
            elif char == "," and depth == 0:
                out.append("".join(current))
                current = []
                continue
        current.append(char)
    out.append("".join(current))
    return out


def matching_paren(text: str, open_index: int) -> int:
    depth = 0
    in_string = False
    index = open_index
    while index < len(text):
        char = text[index]
        if char == '"':
            in_string = not in_string
        elif not in_string:
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    return index
        index += 1
    raise ValueError("unbalanced parentheses")


def enclosing_call(text: str, position: int, levels: int = 3):
    """Yield (callee, argument-text) for the calls enclosing ``position``."""
    index = position
    depth = 0
    found = 0
    while index > 0 and found < levels:
        index -= 1
        char = text[index]
        if char == ")":
            depth += 1
        elif char == "(":
            if depth > 0:
                depth -= 1
                continue
            head = re.search(r"([A-Za-z_][A-Za-z0-9_.]*) $", text[:index + 1]) \
                or re.search(r"([A-Za-z_][A-Za-z0-9_.]*)$", text[:index])
            try:
                close = matching_paren(text, index)
            except ValueError:
                return
            found += 1
            yield (head.group(1) if head else "",
                   text[index + 1:close])


def normalise(text: str) -> str:
    return re.sub(r"[^a-z0-9]", "", text.lower())


def agrees(context: str, member: str, wire: str) -> bool:
    """True when the call-site token and the modeled member name agree."""
    left = normalise(context)
    if len(left) < 3:
        return True
    for right in (normalise(member), normalise(wire)):
        if not right:
            continue
        if left == right or right in left or left in right:
            return True
    return False


# --------------------------------------------------------------------------

CONSTANT_DECLARATION = re.compile(
    r"([A-Za-z_][A-Za-z0-9_]*) : constant Model\.Shape_(?:Index|Reference) "
    r":= ?")

FUNCTION_DECLARATION = re.compile(
    r"function ([A-Za-z_][A-Za-z0-9_]*) \(([^()]*(?:\([^()]*\)[^()]*)*)\) "
    r"return ([A-Za-z_][A-Za-z0-9_.]*)")

MEMBER_SHAPE_CALL = re.compile(
    r"Model\.Member_Shape \(([A-Za-z_][A-Za-z0-9_]*), ([A-Za-z0-9_]+)\)")

QUALIFIED_NAME = re.compile(
    r"\b[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+\b")


class Consumer:
    """Resolve one .adb file's Model.* shape expressions against the JSON."""

    def __init__(self, name, flat, linemap, operations_map, shapes_map,
                 literal_to_operation):
        self.name = name
        self.flat = flat
        self.linemap = linemap
        self.operations_map = operations_map
        self.shapes_map = shapes_map
        self.literal_to_operation = literal_to_operation
        self.constants: list[tuple[int, str, str]] = []
        self.helpers: list[dict] = []
        self.enum_spans: list[tuple[int, int]] = []
        self.uses: list[dict] = []
        self.problems: list[str] = []
        self.recording = False

    def line_of(self, position: int) -> int:
        return self.linemap[min(max(position, 0), len(self.linemap) - 1)]

    def lookup(self, name: str, position: int):
        best = None
        for pos, ada_name, shape in self.constants:
            if ada_name == name and pos <= position and \
                    (best is None or pos > best[0]):
                best = (pos, shape)
        return best[1] if best else None

    def helper_at(self, name: str, position: int):
        best = None
        for helper in self.helpers:
            if helper["name"] == name and helper["position"] <= position and \
                    (best is None or helper["position"] > best["position"]):
                best = helper
        return best

    def record(self, base: str, ordinal: int, position: int, via: str,
               arguments: str = ""):
        members = list(self.shapes_map[base].get("members", {}))
        if ordinal < 1 or ordinal > len(members):
            if self.recording:
                self.problems.append(
                    f"MISMATCH consumer {self.name}:{self.line_of(position)}:"
                    f" {via} ordinal {ordinal} is out of range for {base} "
                    f"(Member_Count = {len(members)})")
            return None
        member_name = members[ordinal - 1]
        member = self.shapes_map[base]["members"][member_name]
        if self.recording:
            self.uses.append({
                "file": self.name, "line": self.line_of(position),
                "via": via, "shape": base, "ordinal": ordinal,
                "member": member_name,
                "wire": member.get("locationName", member_name),
                "target": member["shape"], "position": position,
                "arguments": arguments,
            })
        return member["shape"]

    def evaluate(self, expression: str, position: int, depth: int = 0):
        """Return the JSON shape name an Ada shape expression denotes."""
        text = expression.strip()
        if depth > 12 or not text:
            return None
        while text.startswith("(") and text.endswith(")"):
            try:
                if matching_paren(text, 0) != len(text) - 1:
                    break
            except ValueError:
                break
            text = text[1:-1].strip()
        call = re.match(r"^([A-Za-z_][A-Za-z0-9_.]*) ?\(", text)
        if call is not None:
            try:
                close = matching_paren(text, text.index("("))
            except ValueError:
                return None
            if close != len(text) - 1:
                return None
            head = call.group(1)
            arguments = [item.strip() for item in
                         split_arguments(text[text.index("(") + 1:close])]
            if head in ("Model.Shape_Index", "Model.Shape_Reference",
                        "Shape_Index"):
                return self.evaluate(arguments[0], position, depth + 1)
            if head in ("Model.Input_Shape", "Model.Output_Shape"):
                literal = arguments[0].strip()
                if literal.startswith("Model."):
                    literal = literal[len("Model."):]
                operation = self.literal_to_operation.get(literal)
                if operation is None:
                    return None
                field = "input" if head.endswith("Input_Shape") else "output"
                return self.operations_map[operation].get(
                    field, {}).get("shape")
            if head in ("Model.List_Member_Shape", "Model.Map_Key_Shape",
                        "Model.Map_Value_Shape"):
                role = {"Model.List_Member_Shape": "member",
                        "Model.Map_Key_Shape": "key",
                        "Model.Map_Value_Shape": "value"}[head]
                base = self.evaluate(arguments[0], position, depth + 1)
                if base is None or base not in self.shapes_map:
                    return None
                entry = self.shapes_map[base].get(role)
                return entry.get("shape") if isinstance(entry, dict) else None
            if head == "Model.Member_Shape" and len(arguments) == 2:
                base = self.evaluate(arguments[0], position, depth + 1)
                if base is None or base not in self.shapes_map:
                    return None
                if re.fullmatch(r"\d+", arguments[1]):
                    return self.record(base, int(arguments[1]), position,
                                       "<direct>")
                return None
            helper = self.helper_at(head, position)
            if helper is not None and helper["returns_shape"] and \
                    helper["slot"] < len(arguments) and \
                    re.fullmatch(r"\d+", arguments[helper["slot"]]):
                return self.record(helper["shape"],
                                   int(arguments[helper["slot"]]), position,
                                   head)
            return None
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", text):
            return self.lookup(text, position)
        return None

    # -- discovery ------------------------------------------------------

    def function_body(self, start: int, name: str) -> str:
        closing = self.flat.find(f"end {name};", start)
        if closing >= 0 and closing - start < 6000:
            return self.flat[start:closing]
        depth = 0
        index = start
        in_string = False
        while index < len(self.flat) and index - start < 6000:
            char = self.flat[index]
            if char == '"':
                in_string = not in_string
            elif not in_string:
                if char == "(":
                    depth += 1
                elif char == ")":
                    depth -= 1
                elif char == ";" and depth == 0:
                    return self.flat[start:index]
            index += 1
        return self.flat[start:start + 2000]

    def discover(self) -> None:
        for _ in range(6):
            before = (len(self.constants), len(self.helpers))

            for match in CONSTANT_DECLARATION.finditer(self.flat):
                end = self.flat.find(";", match.end())
                if end < 0:
                    continue
                shape = self.evaluate(self.flat[match.end():end],
                                      match.start())
                if shape is None or shape not in self.shapes_map:
                    continue
                entry = (match.start(), match.group(1), shape)
                if entry not in self.constants:
                    self.constants.append(entry)

            for match in FUNCTION_DECLARATION.finditer(self.flat):
                name, profile, result = match.groups()
                if self.helper_at(name, match.start()) is not None and \
                        any(item["position"] == match.start()
                            for item in self.helpers):
                    continue
                parameters = profile.split(";")
                candidates = []
                for slot, item in enumerate(parameters):
                    parts = item.split(":")
                    if len(parts) != 2:
                        continue
                    if not parts[1].strip().startswith("Positive"):
                        continue
                    for token in parts[0].split(","):
                        candidates.append((slot, token.strip()))
                if not candidates:
                    continue
                body = self.function_body(match.end(), name)
                for slot, index_name in candidates:
                    call = re.search(
                        r"Model\.Member_Shape \(([A-Za-z_][A-Za-z0-9_]*), "
                        + re.escape(index_name) + r"\)", body)
                    if call is None:
                        continue
                    base_name = call.group(1)
                    base = self.lookup(base_name, match.end() + call.start())
                    if base is None:
                        inner = re.search(
                            re.escape(base_name)
                            + r" : constant Model\.Shape_(?:Index|Reference)"
                              r" := ?", body)
                        if inner is not None:
                            stop = body.find(";", inner.end())
                            base = self.evaluate(body[inner.end():stop],
                                                 match.end() + inner.start())
                    if base is None or base not in self.shapes_map:
                        continue
                    self.helpers.append({
                        "name": name, "position": match.start(),
                        "shape": base, "slot": slot,
                        "returns_shape": result.endswith("Shape_Index"),
                        "uses_enum": ("Model.Enumeration_Count" in body
                                      or "Model.Enumeration_Value" in body),
                    })
                    break

            if (len(self.constants), len(self.helpers)) == before:
                break

        # Spans of calls to any local function that consults an enumeration,
        # so a shape handed to such a function is treated as an enum use.
        for match in FUNCTION_DECLARATION.finditer(self.flat):
            name = match.group(1)
            body = self.function_body(match.end(), name)
            if "Model.Enumeration_Count" not in body and \
                    "Model.Enumeration_Value" not in body:
                continue
            for call in re.finditer(
                    rf"(?<![A-Za-z0-9_.]){re.escape(name)} \(", self.flat):
                if call.start() <= match.start():
                    continue
                try:
                    close = matching_paren(self.flat,
                                           self.flat.index("(", call.start()))
                except ValueError:
                    continue
                self.enum_spans.append((call.start(), close))

    # -- recording ------------------------------------------------------

    def collect(self) -> None:
        self.recording = True
        for match in MEMBER_SHAPE_CALL.finditer(self.flat):
            if not re.fullmatch(r"\d+", match.group(2)):
                continue
            base = self.lookup(match.group(1), match.start())
            if base is None or base not in self.shapes_map:
                self.problems.append(
                    f"UNRESOLVED consumer {self.name}:"
                    f"{self.line_of(match.start())}: cannot resolve the base "
                    f"shape {match.group(1)!r} of Member_Shape ordinal "
                    f"{match.group(2)}")
                continue
            self.record(base, int(match.group(2)), match.start(), "<direct>")

        for helper in self.helpers:
            for call in re.finditer(
                    rf"(?<![A-Za-z0-9_.]){re.escape(helper['name'])} \(",
                    self.flat):
                if call.start() <= helper["position"]:
                    continue
                if self.helper_at(helper["name"], call.start()) is not helper:
                    continue
                try:
                    close = matching_paren(self.flat,
                                           self.flat.index("(", call.start()))
                except ValueError:
                    continue
                arguments = [item.strip() for item in split_arguments(
                    self.flat[self.flat.index("(", call.start()) + 1:close])]
                if helper["slot"] >= len(arguments):
                    continue
                if not re.fullmatch(r"\d+", arguments[helper["slot"]]):
                    continue
                self.record(helper["shape"],
                            int(arguments[helper["slot"]]), call.start(),
                            helper["name"], ", ".join(arguments))

    # -- context --------------------------------------------------------

    def context_of(self, use: dict, source_lines: list[str]) -> str:
        position = use["position"]
        # 1. The constant this shape is being bound to.
        prefix = self.flat[max(0, position - 90):position]
        constant = re.search(
            r"([A-Za-z_][A-Za-z0-9_]*) : constant "
            r"Model\.Shape_(?:Index|Reference) := ?$", prefix)
        if constant is not None:
            name = constant.group(1)
            for suffix in ("_Member_Shape", "_List_Shape", "_Shape",
                           "_List"):
                if name.endswith(suffix) and len(name) > len(suffix):
                    name = name[:-len(suffix)]
                    break
            return name
        # 2. A qualified name in this call's own arguments, then in an
        #    enclosing call's arguments.
        for arguments in [use.get("arguments", "")] + [
                item for _, item in enclosing_call(self.flat, position)]:
            if not arguments:
                continue
            for candidate in QUALIFIED_NAME.finditer(arguments):
                text = candidate.group(0)
                if text.startswith(("Model.", "US.", "Ada.", "S3.",
                                    "Apps.", "Flyology.")):
                    continue
                return text.split(".")[-1]
            literal = re.search(r'"([A-Za-z0-9\-]+)"', arguments)
            if literal is not None:
                return literal.group(1)
        # 3. A validated element or header name just before the call.
        window = self.flat[max(0, position - 320):position]
        required = re.findall(r'Require_Name \("([A-Za-z0-9]+)"\)', window)
        if required:
            return required[-1]
        header = re.findall(r'"(x-amz-[a-z0-9\-]+)"', window)
        if header:
            return header[-1]
        # 4. The enclosing case arm in the original source.
        for offset in range(use["line"], max(0, use["line"] - 16), -1):
            found = re.match(r"\s*when ([A-Za-z0-9_]+) =>",
                             source_lines[offset - 1])
            if found is not None:
                return found.group(1)
        return "?"

    def in_enum_span(self, position: int) -> bool:
        return any(start <= position <= stop
                   for start, stop in self.enum_spans)


def consumer_ordinals(root: pathlib.Path, operations_map, shapes_map) -> int:
    literal_to_operation = {}
    for name in operations_map:
        literal = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", name)
        literal = re.sub(r"[^A-Za-z0-9]+", "_", literal).strip("_")
        literal_to_operation[literal + "_Operation"] = name

    rows: list[dict] = []
    problems: list[str] = []
    files = 0

    for path in sorted((root / "src").glob("*.adb")):
        source = path.read_text(encoding="utf-8")
        if "Model." not in source or path.name.endswith("s3-model.adb"):
            continue
        files += 1
        flat, linemap = flatten_with_lines(strip_comments(source))
        consumer = Consumer(path.name, flat, linemap, operations_map,
                            shapes_map, literal_to_operation)
        consumer.discover()
        consumer.collect()
        source_lines = source.split("\n")
        seen: set[tuple] = set()
        for use in consumer.uses:
            key = (use["line"], use["shape"], use["ordinal"], use["via"])
            if key in seen:
                continue
            seen.add(key)
            use["context"] = consumer.context_of(use, source_lines)
            use["enum_use"] = consumer.in_enum_span(use["position"]) or any(
                helper["name"] == use["via"] and helper["uses_enum"]
                for helper in consumer.helpers)
            rows.append(use)
        problems.extend(consumer.problems)

    print()
    print("-" * 74)
    print("consumer ordinal cross-check (literal member ordinals in "
          "src/*.adb, resolved against the pinned JSON member order)")
    print("-" * 74)
    header = (f"{'file':44} {'line':>5} {'via':27} {'shape':30} {'#':>3} "
              f"{'member':27} {'wire name':33} {'E':1} {'call site':26} "
              f"{'verdict'}")
    print(header)
    print("-" * len(header))
    enum_checked = 0
    unknown_context = 0
    for use in sorted(rows, key=lambda item: (item["file"], item["line"],
                                              item["ordinal"])):
        target = shapes_map.get(use["target"], {})
        scalar = target
        if target.get("type") == "list":
            scalar = shapes_map.get(
                target.get("member", {}).get("shape", ""), {})
        has_enum = bool(scalar.get("enum"))
        context = use["context"]
        verdict = "OK"
        if context == "?":
            verdict = "NO CONTEXT"
            unknown_context += 1
        elif not agrees(context, use["member"], use["wire"]):
            verdict = "NAME MISMATCH"
            problems.append(
                f"MISMATCH consumer {use['file']}:{use['line']}: "
                f"{use['via']}({use['ordinal']}) resolves to "
                f"{use['shape']}.{use['member']} (wire name {use['wire']}) "
                f"but the call site names {context!r}")
        if use["enum_use"]:
            enum_checked += 1
            if not has_enum:
                verdict = "NO ENUMERATION"
                problems.append(
                    f"MISMATCH consumer {use['file']}:{use['line']}: "
                    f"{use['via']}({use['ordinal']}) resolves to "
                    f"{use['shape']}.{use['member']}, whose shape "
                    f"{use['target']} carries no enumeration, so the "
                    f"enumeration check can never accept a value")
        print(f"{use['file']:44} {use['line']:>5} {use['via']:27} "
              f"{use['shape']:30} {use['ordinal']:>3} {use['member']:27} "
              f"{use['wire']:33} {'E' if has_enum else '-'} "
              f"{context:26} {verdict}")
    print(f"({len(rows)} literal ordinals resolved in {files} consumer "
          f"file(s); {enum_checked} feed an enumeration lookup; "
          f"{unknown_context} without a call-site name to compare; "
          f"'E' marks a member whose shape carries enumeration values)")

    if problems:
        print()
        for line in problems:
            print(line)
    return len(problems)


if __name__ == "__main__":
    raise SystemExit(main())
