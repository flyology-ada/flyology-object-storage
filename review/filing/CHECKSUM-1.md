Title: PutObject answers InvalidRequest for an SDK-algorithm and value-header mismatch where the model documents BadDigest
Labels: bug
Refs: none

## Summary

When a PutObject request carries `x-amz-sdk-checksum-algorithm: <A>` together with a value header `x-amz-checksum-<B>` for a different algorithm, the preflight answers 400 `InvalidRequest` with "The checksum algorithm and value header differ". The pinned model's documentation for `PutObjectRequest.ChecksumAlgorithm` says Amazon S3 fails that request with a `BadDigest` error. The status is 400 either way and the object is not stored either way, so what differs is the `<Code>` a caller or a conformance harness keyed on the error code observes.

## Problem

Commit `5fe6e3e`.

The selector is taken from the SDK header (`src/flyology-object_storage-server-s3_applications.adb:14786-14802`), and the branch inside `Checksum_Value_Header_Count = 1` rejects a disagreement (`:14813-14821`):

```ada
                     if Count ("x-amz-sdk-checksum-algorithm") = 1
                       and then Selected /= Checksum_Value_Algorithm
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "The checksum algorithm and value header differ",
                           Target_Text);
                        return;
                     end if;
```

`Put_Object_Annotation` uses the same mapping with the message "The checksum algorithm and value differ" (`:15555-15562`), but that is a Flyology extension operation with no model text and is unaffected either way.

The pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) documents the opposite code. `shapes.PutObjectRequest.members.ChecksumAlgorithm`, with HTML stripped:

```
Indicates the algorithm used to create the checksum for the object when you
use the SDK. ... If the individual checksum value you provide through
x-amz-checksum-algorithm doesn't match the checksum algorithm you set through
x-amz-sdk-checksum-algorithm , Amazon S3 fails the request with a BadDigest
error.
```

The server is not missing a `BadDigest` mapping: it emits that code at 18 sites in the same unit, including `:17689` and `:18017`, and does so on this very operation for a genuine value mismatch, as the second control below shows.

Two facts weigh against the model's prose, and they are why this is a question about which code is right rather than a plain defect.

First, `BadDigest` is not a modelled error shape anywhere in the pinned model (a search for a shape whose name contains `BadDigest` returns nothing), while PutObject's modelled `errors` list is exactly:

```
--- PutObject errors --- ['InvalidRequest', 'InvalidWriteOffset', 'TooManyParts', 'EncryptionTypeMismatch']
```

so the code the server emits is PutObject's own modelled error, and `BadDigest` appears only inside documentation strings.

Second, the model's error-code table defines `BadDigest` as a content mismatch, which is exactly the meaning this server reserves it for:

```
Code: BadDigest
Description: The Content-MD5 you specified did not match what we received.
HTTP Status Code: 400 Bad Request
SOAP Fault Code Prefix: Client
```

Reserving `BadDigest` for a real digest mismatch and `InvalidRequest` for an inconsistent header combination is a defensible reading of the same document.

The model gives UploadPart a different rule for the same header pair, "If you provide an individual checksum, Amazon S3 ignores any provided ChecksumAlgorithm parameter", and the server implements that separately, so the PutObject branch is not a consequence of one shared policy.

Nothing in the crate records a deliberate deviation. `docs/qualification/put-object.md:33` is the only statement about the member and says nothing about error codes:

```
| 11 | `ChecksumAlgorithm` | Select one ordinary full-object algorithm. |
```

An existing test pins the current code. `tests/src/s3_server_application_corpus.adb:6334-6341` builds the mismatched request:

```ada
      SDK_Mismatch : constant String := Run
        (Signed_Request
           ("PUT", "/test-bucket/put-budget", "bad",
            Extra_Headers =>
              "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
              "x-amz-checksum-crc32: " & Checksum_Value (Core.CRC32, "bad") &
              CRLF,
            Hash_Override => Wrong_Hash));
```

and `:6428` requires the answer this issue questions, under the message at `:6431`:

```ada
      Require
        (Has (SDK_Mismatch, "<Code>InvalidRequest</Code>")
         and then Has (SDK_Missing_Value, "<Code>InvalidRequest</Code>")
         and then Has (Invalid_MD5, "<Code>InvalidDigest</Code>"),
         "PutObject checksum-group preflight failed");
```

## What happens now

Spike: the program below creates a bucket in the in-process memory-backed application, computes the canonical CRC32 of the body `"bad"` with the crate's own checksum API, and sends three signed PutObjects. Control 1 is the same request with a matching selector, which must be accepted. Control 2 is a well-formed but wrong CRC32 value, which must be `BadDigest`. The third is the finding: `x-amz-sdk-checksum-algorithm: SHA256` with an `x-amz-checksum-crc32` carrying the body's true CRC32, asserting the `BadDigest` the model documents.

```ada
      Mismatch : constant String := Run
        (Signed_Request
           ("PUT", "/" & Bucket & "/" & Key, Body_Text,
            Extra_Headers =>
              "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
              "x-amz-checksum-crc32: " & CRC32_Value & CRLF));
```

Output, exit status 1:

```
  -- canonical CRC32 of "bad" = gis5+w==
  -- CreateBucket status 200
  ok: control: CreateBucket is 200
  -- matching selector status 200
  ok: control: matching sdk-algorithm/value header is accepted
  -- value/content mismatch status 400
  -- value/content mismatch body: <?xml version="1.0" encoding="UTF-8"?><Error><Code>BadDigest</Code><Message>The checksum does not match the request body</Message><Resource>/checksum1-bucket/mismatch-key-wrong</Resource></Error>
  ok: control: a value/content mismatch is answered BadDigest
  -- algorithm-name mismatch status 400
  -- algorithm-name mismatch body: <?xml version="1.0" encoding="UTF-8"?><Error><Code>InvalidRequest</Code><Message>The checksum algorithm and value header differ</Message><Resource>/checksum1-bucket/mismatch-key</Resource></Error>
  ok: algorithm-name mismatch is a 400
  FAILED: model documents BadDigest for an sdk-algorithm/value mismatch
  FAILED: algorithm-name mismatch is not answered InvalidRequest
BUG REPRODUCED: 2 failed expectation(s)
```

Control 1 shows the request shape, the payload hash and the CRC32 value are all valid, so the rejection comes from the selector disagreement alone; control 2 shows the server does emit `BadDigest` on this operation when the digest itself is wrong.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Shapes checked against the pinned botocore S3 model.

## What should happen

One of the two codes must be the crate's answer for this input, chosen against the pinned model and written down. Today the model's `ChecksumAlgorithm` prose names `BadDigest`, its modelled `errors` list for PutObject names `InvalidRequest`, its error table defines `BadDigest` as a content mismatch, and the crate documents nothing.

## Suggested treatment

The error code is externally visible, so this needs a maintainer decision:

- Emit `BadDigest` at `src/flyology-object_storage-server-s3_applications.adb:14813-14821`, matching the model's `ChecksumAlgorithm` documentation literally. This is a one-line change, and it overloads a code the same model's error table defines as a content mismatch, which the server currently uses for exactly that. `tests/src/s3_server_application_corpus.adb:6428` asserts `InvalidRequest` for this case and would have to change.
- Keep `InvalidRequest` and record the reading in `docs/qualification/put-object.md`, beside the `ChecksumAlgorithm` row at `:33`: `BadDigest` is reserved for a digest that does not match the body, and an inconsistent header combination is a malformed request, which is the general one of PutObject's four modelled errors. Nothing changes on the wire and the existing assertion stands, with the divergence from the model's prose disclosed rather than silent.

Whichever is chosen, `Put_Object_Annotation` at `:15555-15562` should be brought into line with it so the two paths do not drift apart.

The regression test belongs in `tests/src/s3_server_application_corpus.adb`, where the case already exists: the fixture at `:6334-6341` stays and the assertion at `:6428` states the chosen code. The spike is the test.

## Severity

A client that sets both checksum headers inconsistently gets 400 with a different `<Code>` than the model's prose describes. Nothing else changes: the status is 400 either way, the object is not stored either way, and a stock SDK raises the same exception class for both, so no caller is known to branch on the difference. It is reached only by a client that names one algorithm in the SDK header and another in the value header, which a stock SDK does not do on its own. A conformance harness keyed on the error code is the case that sees it. Deterministic.
