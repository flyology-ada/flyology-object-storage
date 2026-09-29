#!/usr/bin/env python3
"""Stock-client (boto3) checksum probe against the memory-backed S3 server.

How to run
----------
Start the standalone server (it prints ``PORT <n>`` on stdout and serves
path-style S3 on 127.0.0.1 until SIGTERM)::

    cd <repo root>
    AWS_ACCESS_KEY_ID=AKIDEXAMPLE \
    AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY \
      ./tests/bin/s3_memory_server 0 &

Then drive it with a throwaway boto3 resolved by uv (nothing is installed
system-wide)::

    uv run --python 3.13 --with boto3 python3 \
      tests/repros/python/checksum_boto3_probe.py <port>

What it asserts
---------------
Every operation below is issued by a stock boto3 client with modern botocore
defaults (``request_checksum_calculation`` defaults to ``when_supported``
since botocore 1.36, so boto3 adds ``x-amz-checksum-crc32`` on its own).  The
script records, for each call, the exact request headers boto3 put on the
wire, the request body shape, and the server's status and body.  It exits 1
if the server rejects any of them, so a green run means a stock client's
default checksum behaviour is accepted end to end.

Operations, in order:
  a. create_bucket
  b. put_object of 1 KiB with boto3 defaults
  c. the same put_object with ChecksumAlgorithm='CRC32'
  d. a multipart upload of two 5 MiB parts with ChecksumAlgorithm='CRC32' on
     create/upload_part/complete -- recording the exact composite value boto3
     sends on CompleteMultipartUpload (does it carry a '-N' suffix, and does
     the server accept it?)
  e. delete_objects with two keys and boto3 defaults (no Content-MD5)
  f. put_bucket_versioning with boto3 defaults
  g. head_object and get_object with ChecksumMode='ENABLED'
"""

import logging
import sys
import traceback

import boto3
import botocore
import botocore.config
from botocore.exceptions import ClientError

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 0
BUCKET = "boto3-checksum-probe"
KEY_DEFAULT = "default-put"
KEY_CRC32 = "crc32-put"
KEY_MPU = "multipart-crc32"
PART = b"m" * (5 * 1024 * 1024)
SMALL = b"z" * 1024

logging.basicConfig(stream=sys.stderr, level=logging.WARNING)
boto3.set_stream_logger("botocore.endpoint", logging.DEBUG)
boto3.set_stream_logger("botocore.parsers", logging.DEBUG)

failures = []          # (label, detail) for stock-default requests refused
observations = []      # printable per-operation records
_wire = {"request": None, "response": None}


def _body_shape(body):
    if body is None:
        return "<none>"
    if isinstance(body, (bytes, bytearray)):
        text = bytes(body)
        if len(text) <= 600:
            return "bytes(%d): %r" % (len(text), text)
        return "bytes(%d): %r..." % (len(text), text[:300])
    return "<stream %s>" % type(body).__name__


def on_before_send(request, **kwargs):
    _wire["request"] = {
        "method": request.method,
        "url": request.url,
        "headers": dict(request.headers),
        "body": _body_shape(getattr(request, "body", None)),
    }
    return None


def on_after_call(http_response, parsed, model, **kwargs):
    # Never touch .text for a streaming-output operation (GetObject): reading
    # it here would drain the body the caller is about to read.
    streaming = getattr(model, "has_streaming_output", False)
    if streaming and http_response.status_code < 300:
        text = "<streaming body, read by the caller>"
    else:
        text = http_response.text[:1200]
    _wire["response"] = {
        "status": http_response.status_code,
        "headers": dict(http_response.headers),
        "text": text,
    }
    return None


def record(label, fn, stock_default=True, checksum_related=True):
    """Run one call, print its wire evidence, and note a rejection."""
    _wire["request"] = None
    _wire["response"] = None
    print("\n=== %s ===" % label)
    result, error = None, None
    try:
        result = fn()
    except ClientError as exc:
        error = exc
    except Exception as exc:  # noqa: BLE001 - probe must keep going
        error = exc
        traceback.print_exc()

    req = _wire["request"]
    if req:
        print("--- request %s %s" % (req["method"], req["url"]))
        for name in sorted(req["headers"]):
            print("    %s: %s" % (name, req["headers"][name]))
        print("--- request body: %s" % req["body"])
    else:
        print("--- request: not captured")

    resp = _wire["response"]
    if resp:
        print("--- response status %s" % resp["status"])
        for name in sorted(resp["headers"]):
            print("    %s: %s" % (name, resp["headers"][name]))
        print("--- response body: %r" % resp["text"])
        rejected = resp["status"] >= 400
    else:
        print("--- response: not captured")
        rejected = error is not None

    if error is not None:
        print("--- CLIENT ERROR: %s" % error)
    if rejected or error is not None:
        detail = "status %s" % (resp["status"] if resp else "n/a")
        if error is not None:
            detail += "; %s" % error
        if stock_default:
            failures.append((label, detail, checksum_related))
        observations.append((label, "REJECTED", detail))
    else:
        observations.append((label, "accepted", "status %s" % resp["status"]))
    return result


def main():
    print("boto3 %s botocore %s" % (boto3.__version__, botocore.__version__))
    print("endpoint http://127.0.0.1:%d  (path-style, us-east-1)" % PORT)
    cfg = botocore.config.Config(s3={"addressing_style": "path"})
    s3 = boto3.client(
        "s3",
        endpoint_url="http://127.0.0.1:%d" % PORT,
        region_name="us-east-1",
        aws_access_key_id="AKIDEXAMPLE",
        aws_secret_access_key="wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
        config=cfg,
    )
    s3.meta.events.register("before-send", on_before_send)
    s3.meta.events.register("after-call", on_after_call)
    try:
        print("request_checksum_calculation = %s" %
              s3.meta.config.request_checksum_calculation)
        print("response_checksum_validation = %s" %
              s3.meta.config.response_checksum_validation)
    except AttributeError:
        print("request_checksum_calculation: not exposed by this botocore")

    # (a)
    record("a. create_bucket", lambda: s3.create_bucket(Bucket=BUCKET))

    # (b)
    record("b. put_object 1 KiB, boto3 defaults",
           lambda: s3.put_object(Bucket=BUCKET, Key=KEY_DEFAULT, Body=SMALL))

    # (c)
    record("c. put_object 1 KiB, ChecksumAlgorithm=CRC32",
           lambda: s3.put_object(Bucket=BUCKET, Key=KEY_CRC32, Body=SMALL,
                                 ChecksumAlgorithm="CRC32"))

    # (d)
    create = record(
        "d1. create_multipart_upload ChecksumAlgorithm=CRC32",
        lambda: s3.create_multipart_upload(Bucket=BUCKET, Key=KEY_MPU,
                                           ChecksumAlgorithm="CRC32"))
    parts = []
    if create is not None:
        upload_id = create["UploadId"]
        print("    UploadId=%s ChecksumAlgorithm=%s ChecksumType=%s" %
              (upload_id, create.get("ChecksumAlgorithm"),
               create.get("ChecksumType")))
        for number in (1, 2):
            out = record(
                "d2.%d upload_part %d (5 MiB) ChecksumAlgorithm=CRC32"
                % (number, number),
                lambda n=number: s3.upload_part(
                    Bucket=BUCKET, Key=KEY_MPU, UploadId=upload_id,
                    PartNumber=n, Body=PART, ChecksumAlgorithm="CRC32"))
            if out is None:
                break
            print("    part %d ETag=%s ChecksumCRC32=%r"
                  % (number, out.get("ETag"), out.get("ChecksumCRC32")))
            parts.append({"ETag": out["ETag"], "PartNumber": number,
                          "ChecksumCRC32": out["ChecksumCRC32"]})
        if len(parts) == 2:
            done = record(
                "d3. complete_multipart_upload (composite CRC32)",
                lambda: s3.complete_multipart_upload(
                    Bucket=BUCKET, Key=KEY_MPU, UploadId=upload_id,
                    MultipartUpload={"Parts": parts},
                    ChecksumType="COMPOSITE"))
            if done is not None:
                print("    completed ChecksumCRC32=%r ChecksumType=%r"
                      % (done.get("ChecksumCRC32"), done.get("ChecksumType")))

    # (e)
    record("e. delete_objects (two keys), boto3 defaults",
           lambda: s3.delete_objects(
               Bucket=BUCKET,
               Delete={"Objects": [{"Key": "absent-1"}, {"Key": "absent-2"}]}))

    # (f)
    record("f. put_bucket_versioning, boto3 defaults",
           lambda: s3.put_bucket_versioning(
               Bucket=BUCKET,
               VersioningConfiguration={"Status": "Enabled"}))

    # (g)
    for key in (KEY_DEFAULT, KEY_CRC32, KEY_MPU):
        head = record("g1. head_object %s ChecksumMode=ENABLED" % key,
                      lambda k=key: s3.head_object(Bucket=BUCKET, Key=k,
                                                   ChecksumMode="ENABLED"))
        if head is not None:
            print("    HEAD checksums: %s" %
                  {n: v for n, v in head.items()
                   if n.startswith("Checksum")})
        got = record("g2. get_object %s ChecksumMode=ENABLED" % key,
                     lambda k=key: s3.get_object(Bucket=BUCKET, Key=k,
                                                 ChecksumMode="ENABLED"))
        if got is not None:
            data = got["Body"].read()
            print("    GET %d bytes, checksums: %s" %
                  (len(data), {n: v for n, v in got.items()
                               if n.startswith("Checksum")}))

    print("\n=== SUMMARY ===")
    for label, verdict, detail in observations:
        print("%-10s %s  (%s)" % (verdict, label, detail))
    if failures:
        print("\nSTOCK CLIENT REQUESTS REJECTED:")
        for label, detail, checksum_related in failures:
            print("  %s -> %s%s" % (label, detail,
                                    "" if checksum_related else " [non-checksum]"))
        return 1
    print("\nno stock-client default request was rejected")
    return 0


if __name__ == "__main__":
    sys.exit(main())
