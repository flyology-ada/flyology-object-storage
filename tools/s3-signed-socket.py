#!/usr/bin/env python3
"""Run reviewed S3 signed socket cases against a small typed Ada adapter."""

from __future__ import annotations

import json
import os
import re
import socket
import subprocess
import sys
from pathlib import Path
from typing import Any

import s3_operation

# Test-only authorities shared with the existing signed socket corpus: one
# 4 KiB request-head buffer and a five-second local peer watchdog. They are
# qualification harness bounds, not public client defaults or resource policy.
SIGNED_REQUEST_HEAD_LIMIT = 4_096
SOCKET_TIMEOUT_SECONDS = 5.0


def fail(message: str) -> None:
    raise s3_operation.Audit_Error(message)


def read_request(peer: socket.socket) -> tuple[str, dict[str, list[str]], bytes]:
    data = bytearray()
    while b"\r\n\r\n" not in data:
        chunk = peer.recv(4096)
        if not chunk:
            fail("client closed before the signed request head")
        data.extend(chunk)
        if len(data) > SIGNED_REQUEST_HEAD_LIMIT:
            fail("signed request head exceeds the test harness capacity")
    head, body = bytes(data).split(b"\r\n\r\n", 1)
    lines = head.decode("iso-8859-1").split("\r\n")
    headers: dict[str, list[str]] = {}
    for line in lines[1:]:
        if ":" not in line:
            fail("malformed signed request header")
        name, value = line.split(":", 1)
        headers.setdefault(name.casefold(), []).append(value.strip())
    length_values = headers.get("content-length", ["0"])
    if len(length_values) != 1 or not length_values[0].isdigit():
        fail("invalid signed request content length")
    expected_length = int(length_values[0])
    while len(body) < expected_length:
        chunk = peer.recv(4096)
        if not chunk:
            fail("client closed before the signed request body")
        body += chunk
    return lines[0], headers, body[:expected_length]


def validate_request(
    request_line: str,
    headers: dict[str, list[str]],
    body: bytes,
    exchange: dict[str, Any],
    port: int,
) -> None:
    expected_line = f"{exchange['method']} {exchange['target']} HTTP/1.1"
    if request_line != expected_line:
        fail(f"signed request line mismatch: {request_line!r} != {expected_line!r}")
    if headers.get("host") != [f"127.0.0.1:{port}"]:
        fail("signed request host mismatch")
    authorization = headers.get("authorization")
    if len(authorization or []) != 1 or not authorization[0].startswith(
        "AWS4-HMAC-SHA256 Credential="
    ):
        fail("signed request authorization is absent")
    match = re.search(r"(?:^|,\s*)SignedHeaders=([^,\s]+)", authorization[0])
    if match is None:
        fail("signed request authorization lacks SignedHeaders")
    signed = set(match.group(1).casefold().split(";"))
    for name, expected in exchange["request_headers"].items():
        lower = name.casefold()
        if headers.get(lower) != [expected]:
            fail(f"signed request header mismatch: {name}")
        if lower not in signed:
            fail(f"expected request header is not signed: {name}")
    expected_body = exchange.get("request_body", "").encode("utf-8")
    if body != expected_body:
        fail("signed request body mismatch")


def response_bytes(exchange: dict[str, Any]) -> bytes:
    body = exchange["body"].encode("utf-8")
    lines = [
        f"HTTP/1.1 {exchange['status']}",
        f"Content-Length: {len(body)}",
        *[f"{name}: {value}" for name, value in exchange["headers"]],
        "Connection: close",
        "",
        "",
    ]
    return "\r\n".join(lines).encode("iso-8859-1") + body


def run_case(
    operation_name: str,
    adapter: str,
    case: dict[str, Any],
) -> None:
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    listener.settimeout(SOCKET_TIMEOUT_SECONDS)
    port = listener.getsockname()[1]
    environment = os.environ.copy()
    environment.update(
        {
            "FLYOLOGY_S3_QUALIFICATION_PORT": str(port),
            "FLYOLOGY_S3_QUALIFICATION_CASE": case["id"],
            "FLYOLOGY_S3_QUALIFICATION_LANE": case["lane"],
            "FLYOLOGY_S3_QUALIFICATION_BUCKET": case["exchange"][0][
                "input_values"
            ]["Bucket"],
            "FLYOLOGY_S3_QUALIFICATION_EXPECTED": case["expected"],
        }
    )
    for member, value in case["exchange"][0]["input_values"].items():
        environment[
            "FLYOLOGY_S3_QUALIFICATION_INPUT_"
            + re.sub(r"(?<!^)(?=[A-Z])", "_", member).upper()
        ] = value
    if "expected_value" in case:
        environment["FLYOLOGY_S3_QUALIFICATION_EXPECTED_VALUE"] = case[
            "expected_value"
        ]
    for name, value in case.get("limits", {}).items():
        environment["FLYOLOGY_S3_QUALIFICATION_" + name.upper()] = str(value)
    process = subprocess.Popen(
        [adapter],
        cwd=s3_operation.ROOT / "tests",
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        for exchange in case["exchange"]:
            peer, _ = listener.accept()
            with peer:
                peer.settimeout(SOCKET_TIMEOUT_SECONDS)
                request_line, headers, body = read_request(peer)
                validate_request(request_line, headers, body, exchange, port)
                wire = response_bytes(exchange)
                separator = wire.index(b"\r\n\r\n") + 4
                peer.sendall(wire[:separator])
                peer.sendall(wire[separator:])
        output, error = process.communicate(
            timeout=(len(case["exchange"]) + 1) * SOCKET_TIMEOUT_SECONDS
        )
    except Exception:
        process.kill()
        output, error = process.communicate()
        raise
    finally:
        listener.close()
    if process.returncode != 0:
        fail(
            f"{operation_name}/{case['id']} adapter failed with "
            f"{process.returncode}: {error or output}"
        )


def generated_negative_cases(
    socket_operation: dict[str, Any], operation_name: str
) -> list[dict[str, Any]]:
    if "negative_template" not in socket_operation:
        return []
    value = json.loads(
        s3_operation.NEGATIVE_XML_PATH.read_text(encoding="utf-8")
    )
    generated = value["operations"][operation_name]["cases"]
    template_id = socket_operation["negative_template"]
    template = next(
        case for case in socket_operation["cases"] if case["id"] == template_id
    )
    exchange_template = template["exchange"][0]
    result = []
    for generated_case in generated:
        exchange = {
            **exchange_template,
            "status": "200 OK",
            "headers": [],
            "body": generated_case["body"],
        }
        result.append(
            {
                "id": "generated-" + generated_case["id"],
                "lane": "invalid_xml",
                "expected": generated_case["expected_http_result"],
                "limits": generated_case["limits"],
                "exchange": [exchange],
            }
        )
    return result


def main() -> int:
    if len(sys.argv) != 2:
        fail("usage: s3-signed-socket.py OPERATION")
    operation_name = sys.argv[1]
    registry = s3_operation.load_registry()
    s3_operation.validate_committed_negative_xml(registry)
    s3_operation.validate_committed_signed_socket(registry)
    if operation_name not in registry.operations:
        fail(f"operation is absent from registry: {operation_name}")
    value = json.loads(
        s3_operation.SIGNED_SOCKET_PATH.read_text(encoding="utf-8")
    )
    socket_config = value.get("operations", {}).get(operation_name)
    if socket_config is None:
        fail(f"operation has no signed socket qualification: {operation_name}")
    cases = list(socket_config["cases"])
    cases.extend(generated_negative_cases(socket_config, operation_name))
    for case in cases:
        try:
            run_case(operation_name, socket_config["adapter"], case)
        except Exception as error:
            fail(f"{operation_name}/{case['id']}: {error}")
    print(
        f"S3 signed socket qualification: {operation_name} "
        f"{len(cases)} cases OK"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (
        OSError,
        ValueError,
        json.JSONDecodeError,
        socket.timeout,
        subprocess.TimeoutExpired,
    ) as error:
        print(f"s3-signed-socket: {error}", file=sys.stderr)
        raise SystemExit(1)
