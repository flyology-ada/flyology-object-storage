# Adversarial verification: CHECKSUM (S3 checksums, CRC combination, policy, engine, xxHash bridge, trailers)

Scope verified by reading: `src/flyology-object_storage-server-s3_applications.adb`
(PutObject preflight 14770-14900, `Put_Object_Annotation` 15520-15600,
`Verify_Document_Checksum` 5033-5140, `Put_Bucket_Versioning` 10351-10412,
`Put_Bucket_Tagging` 7995-8035, the 18 `BadDigest` sites),
`src/flyology-object_storage-s3-checksums.ads`,
`src/flyology-object_storage-s3-core.ads:42-56`,
`review/baseline/service-2.json` (PutObject/UploadPart/DeleteObjects/
PutBucketVersioning/PutBucketTagging shapes, `httpChecksum` traits, modeled
`errors`), `tests/src/s3_server_application_corpus.adb:6320-6440`,
`docs/qualification/put-object.md`, `docs/qualification/bucket-versioning.md`,
`docs/qualification/bucket-tagging.md`, `docs/qualification/delete-objects.md`,
`docs/compatibility/s3.md`, `tests/src/s3_memory_server.adb`.
Harness programs added: `tests/repros/src/repro_checksum_1.adb`,
`tests/repros/src/repro_checksum_2.adb`,
`tests/repros/python/checksum_boto3_probe.py`. Nothing tracked was modified.

| ID | Verdict | Severity (discovery) | Repro |
|----|---------|----------------------|-------|
| CHECKSUM-1 | CONFIRMED (against model prose only; two partial refutations) | P2 (P2) | `tests/repros/src/repro_checksum_1.adb` |
| CHECKSUM-2 | CONFIRMED (new, found while verifying) | P0 (n/a) | `tests/repros/src/repro_checksum_2.adb` |

CHECKSUM-2 was found by the stock-client probe required for this area and is
numbered here because it is a checksum-header policy defect. The DeleteObjects
instance of the same mechanism is recorded under "Cross-area evidence" as
directed, not numbered.

---
### CHECKSUM-1: PutObject answers `InvalidRequest` where the pinned model documents `BadDigest` for an SDK-algorithm / value-header mismatch

**Verdict:** CONFIRMED (as a divergence from the pinned model's prose; see the
refutation notes, which weaken it).

**Severity:** P2 (discovery said P2; unchanged).

Verified by reading:

- `src/flyology-object_storage-server-s3_applications.adb:14812-14821` — inside
  the `Checksum_Value_Header_Count = 1` branch:
  `if Count ("x-amz-sdk-checksum-algorithm") = 1 and then Selected /=
  Checksum_Value_Algorithm then Send_Error (X, 400, "InvalidRequest", "The
  checksum algorithm and value header differ", Target_Text); return; end if;`
  `Selected` was set from the SDK header at 14786-14802.
- `src/flyology-object_storage-server-s3_applications.adb:15553-15562` — the
  same shape in `Put_Object_Annotation`, message "The checksum algorithm and
  value differ".
- `review/baseline/service-2.json`, shape `PutObjectRequest`, member
  `ChecksumAlgorithm` (`{"shape":"ChecksumAlgorithm","location":"header",
  "locationName":"x-amz-sdk-checksum-algorithm"}`), documentation with HTML
  stripped (extracted with python3): "… If the individual checksum value you
  provide through x-amz-checksum-algorithm doesn't match the checksum
  algorithm you set through x-amz-sdk-checksum-algorithm, Amazon S3 fails the
  request with a BadDigest error."
- `review/baseline/service-2.json`, shape `UploadPartRequest`, member
  `ChecksumAlgorithm`: "… If you provide an individual checksum, Amazon S3
  ignores any provided ChecksumAlgorithm parameter." — a different rule, which
  the server implements separately for UploadPart, so the PutObject branch is
  not a shared-policy consequence.
- `tests/src/s3_server_application_corpus.adb:6334-6341` builds `SDK_Mismatch`
  (`x-amz-sdk-checksum-algorithm: SHA256` plus `x-amz-checksum-crc32:
  Checksum_Value (Core.CRC32, "bad")`), and line 6428 asserts
  `Has (SDK_Mismatch, "<Code>InvalidRequest</Code>")` under the message
  "PutObject checksum-group preflight failed" (line 6431). The suite therefore
  pins the divergent code; nothing asserts `BadDigest` for this case.
- `docs/qualification/put-object.md:33` is the only mention of
  `ChecksumAlgorithm` there ("Select one ordinary full-object algorithm.") — no
  documented deviation and no error-code mapping for this case.

Refutation attempts that failed (and two that partly succeeded):

- Checked whether some other guard fires first: no. The repro's control 1 shows
  the identical request with a matching selector is accepted (200), so the
  request shape, the payload hash and the CRC32 value are all valid, and the
  branch at 14812 is what answers.
- Checked whether the server simply lacks a `BadDigest` mapping: it does not —
  `s3_applications.adb` sends `BadDigest` at 18 sites (1986, 3864, 5263, 5345,
  8243, 8255, 10191, 10206, 10403, 10418, 13129, 13810, 15935, 16468, 17689,
  17721, 18017, 18026), and the repro's control 2 observes
  `<Code>BadDigest</Code>` for a value/content mismatch on the same operation.
- Checked `docs/qualification/put-object.md` and `docs/compatibility/s3.md` for
  a documented deliberate deviation: none found.
- **Partly refuting (a):** `BadDigest` is *not a shape* in the pinned model
  (`[k for k in shapes if 'BadDigest' in k]` is empty), and PutObject's modeled
  `errors` list is exactly `InvalidRequest`, `InvalidWriteOffset`,
  `TooManyParts`, `EncryptionTypeMismatch`. The code the server emits is
  therefore the one PutObject actually models; `BadDigest` appears only in
  documentation prose (5 occurrences, all inside `documentation` strings).
- **Partly refuting (b):** the model's own error-code table defines BadDigest as
  "The Content-MD5 you specified did not match what we received", i.e. a
  content mismatch, which is how this server uses it. Reserving `BadDigest` for
  a real digest mismatch and `InvalidRequest` for a malformed header
  combination is a defensible reading of the same document.

Because of (a) and (b) this is diagnostics drift against prose in a vendored
model, not a shape/binding violation and not an interop break: both answers are
400, the body is not stored either way, and no stock client distinguishes them
(botocore raises `ClientError` on both). P2 is correct.

**Repro:** `tests/repros/src/repro_checksum_1.adb`. Creates a bucket in the
in-process memory-backed application, computes the canonical CRC32 of the body
`"bad"` with the crate's own `Flyology.Object_Storage.S3.Checksums` API
(`Compute` + `Encode_Base64`), then runs three signed PutObjects: a control
with `x-amz-sdk-checksum-algorithm: CRC32` and the matching value header
(expects 200), a control with a well-formed but wrong CRC32 value (expects
`BadDigest`), and the finding — `x-amz-sdk-checksum-algorithm: SHA256` with
`x-amz-checksum-crc32` carrying the true CRC32 — asserting the model's
documented `BadDigest`.

**Output** (`cd tests/repros && ./run.sh repro_checksum_1`, exit status **1**):

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

**Description:** When a PutObject request carries both
`x-amz-sdk-checksum-algorithm: <A>` and a value header
`x-amz-checksum-<B>` for a different algorithm B, the preflight at
`src/flyology-object_storage-server-s3_applications.adb:14812-14821` answers
`400 InvalidRequest` with "The checksum algorithm and value header differ".
The pinned botocore model's documentation for `PutObjectRequest.ChecksumAlgorithm`
says Amazon S3 fails that request "with a BadDigest error". The consequence is
purely which `<Code>` a caller or a conformance harness keyed on the error code
observes; the status is 400 either way, the object is not stored either way, and
a stock SDK surfaces the same exception class. It is deterministic and reachable
by any client that sets both headers inconsistently. Two things weigh against
treating this as a defect: `BadDigest` is not a modeled error shape anywhere in
the pinned model, whereas `InvalidRequest` *is* PutObject's modeled error, and
the model's own error table defines BadDigest as a content mismatch — exactly
the meaning this server reserves it for (repro control 2). `Put_Object_Annotation`
(`s3_applications.adb:15553-15562`) uses the same mapping, but that is a
Flyology extension operation with no model text, so it is unaffected either way.
Existing test asserting the current code: `tests/src/s3_server_application_corpus.adb:6428`.
A fix would need a maintainer decision — it changes an externally visible error
code and would require editing that corpus assertion.

---

### CHECKSUM-2: operations the model marks `requestChecksumRequired` reject every stock SDK request, because the server demands `Content-MD5` and ignores the `x-amz-checksum-<alg>` group the SDK sends instead

**Verdict:** CONFIRMED. New finding, discovered by the stock-client probe.

**Severity:** P0 (not in the discovery report). Per this area's rubric, P0 when
a stock client's default operation fails; it is also the shared rubric's
"interop-breaking protocol violation that a stock client or server rejects".

Verified by reading:

- `review/baseline/service-2.json`: 27 operations carry
  `"httpChecksum": {"requestAlgorithmMember": "ChecksumAlgorithm",
  "requestChecksumRequired": true}` — `DeleteObjects`, `PutBucketAcl`,
  `PutBucketCors`, `PutBucketEncryption`, `PutBucketLifecycle`,
  `PutBucketLifecycleConfiguration`, `PutBucketLogging`,
  `PutBucketNotification`, `PutBucketOwnershipControls`, `PutBucketPolicy`,
  `PutBucketReplication`, `PutBucketRequestPayment`, `PutBucketTagging`,
  `PutBucketVersioning`, `PutBucketWebsite`, `PutObjectAcl`,
  `PutObjectLegalHold`, `PutObjectLockConfiguration`, `PutObjectRetention`,
  `PutObjectTagging`, `PutPublicAccessBlock`,
  `CreateBucketMetadataConfiguration`,
  `CreateBucketMetadataTableConfiguration`,
  `UpdateBucketMetadataAnnotationTableConfiguration`,
  `UpdateBucketMetadataInventoryTableConfiguration`,
  `UpdateBucketMetadataJournalTableConfiguration`, `UpdateObjectEncryption`.
- `src/flyology-object_storage-server-s3_applications.adb:10352-10370`
  (`Put_Bucket_Versioning`): `if MD5_Count /= 1 or else not
  S3.Wire_Core.Valid_Base64 (…, 16) then Send_Error (X, 400, "InvalidRequest",
  "PutBucketVersioning requires one valid " & "Content-MD5 header", …)`.
  This runs *before* the branch at 10376-10412 that reads the document and
  calls `Verify_Document_Checksum`.
- `src/flyology-object_storage-server-s3_applications.adb:8013-8019`
  (`Put_Bucket_Tagging`): the same precondition, "PutBucketTagging requires a
  valid Content-MD5".
- `src/flyology-object_storage-server-s3_applications.adb:5033-5140`
  (`Verify_Document_Checksum`): the server already parses and verifies the
  full `x-amz-sdk-checksum-algorithm` / `x-amz-checksum-<alg>` / `x-amz-trailer`
  group for these documents, for all ten algorithms. The capability exists; it
  is simply not accepted as an alternative to `Content-MD5`.
- `review/baseline/service-2.json`, `DeleteObjectsRequest`: **has no
  `ContentMD5` member at all**. `PutBucketVersioningRequest` and
  `PutBucketTaggingRequest` do have one, documented as "For requests made
  using the … CLI or … SDKs, this field is calculated automatically" — which
  modern botocore no longer does; it fills the checksum instead.
- Wire evidence (boto3/botocore 1.43.89, `request_checksum_calculation =
  when_supported`): for both operations the client sent
  `x-amz-checksum-crc32` + `x-amz-sdk-checksum-algorithm: CRC32` and **no**
  `Content-MD5`. Full headers in the "Stock client probe" section below.

Refutation attempts that failed:

- Checked whether the requests were malformed in some other way: no. The repro
  sends byte-identical bodies twice, once with a legacy `Content-MD5` and once
  with the boto3 header pair; the `Content-MD5` form is accepted with 200 for
  both operations, so only the integrity-header choice differs.
- Checked whether it is a documented deliberate deviation: the requirement is
  *described* — `docs/compatibility/s3.md:638` ("The authenticated server
  requires Content-MD5 for Put…"), `docs/qualification/bucket-versioning.md:47`
  ("exact Content-MD5 and all ten modeled direct or physical-trailer checksum
  algorithms"), `docs/qualification/delete-objects.md:11` ("requires one
  canonical Content-MD5 computed over the exact body bytes") — but always as
  Content-MD5 *plus* the checksum group, never as an acknowledged interop
  boundary, and no document states that stock SDKs cannot call these
  operations. A documented policy that a stock client rejects is still an
  interop break under the rubric, so this is not DOCUMENTED LIMITATION.
- Checked whether an older botocore would send `Content-MD5`: irrelevant to the
  verdict — the pinned model itself marks these operations
  `requestChecksumRequired`, which is precisely the trait that tells an SDK to
  send a checksum rather than an MD5, and the observed stock client does so.
- Checked whether the memory backend is at fault: no, the rejection happens in
  the shared S3 application preflight, before any backend call.

**Repro:** `tests/repros/src/repro_checksum_2.adb`. Creates a bucket in the
in-process memory-backed application, then issues four signed requests:
`PUT /bucket?versioning` and `PUT /bucket?tagging` with a legacy `Content-MD5`
(controls, expected 200), and the same two bodies with exactly the two headers
boto3 1.43.89 puts on the wire (`x-amz-sdk-checksum-algorithm: CRC32` and
`x-amz-checksum-crc32: <canonical CRC32 of the body>`, no `Content-MD5`),
asserting they are accepted. Digests are computed with the crate's own
`Flyology.Object_Storage.S3.Checksums` API.

**Output** (`cd tests/repros && ./run.sh repro_checksum_2`, exit status **1**):

```
  ok: control: CreateBucket is 200
  -- PutBucketVersioning with Content-MD5: status 200
  ok: control: PutBucketVersioning with Content-MD5 is accepted
  -- PutBucketVersioning, boto3 default headers: status 400
  -- body: <?xml version="1.0" encoding="UTF-8"?><Error><Code>InvalidRequest</Code><Message>PutBucketVersioning requires one valid Content-MD5 header</Message><Resource>/checksum2-bucket?versioning</Resource></Error>
  FAILED: stock boto3 PutBucketVersioning (CRC32, no Content-MD5) is accepted
  -- PutBucketTagging with Content-MD5: status 200
  ok: control: PutBucketTagging with Content-MD5 is accepted
  -- PutBucketTagging, boto3 default headers: status 400
  -- body: <?xml version="1.0" encoding="UTF-8"?><Error><Code>InvalidRequest</Code><Message>PutBucketTagging requires a valid Content-MD5</Message><Resource>/checksum2-bucket?tagging</Resource></Error>
  FAILED: stock boto3 PutBucketTagging (CRC32, no Content-MD5) is accepted
BUG REPRODUCED: 2 failed expectation(s)
```

**Description:** Since botocore 1.36 the default `request_checksum_calculation`
is `when_supported`, so a stock AWS SDK satisfies an operation's
`httpChecksum.requestChecksumRequired` trait by sending
`x-amz-sdk-checksum-algorithm: CRC32` together with `x-amz-checksum-crc32`, and
it sends no `Content-MD5` at all. This server's preflight for those operations
requires exactly one syntactically valid `Content-MD5` and returns
`400 InvalidRequest` before it reaches `Verify_Document_Checksum`, which does
implement the checksum group. The observable consequence is that every one of
the 27 `requestChecksumRequired` operations is uncallable from a current
boto3, aws-cli v2 or any other modern SDK using default settings — confirmed on
the wire for `DeleteObjects` and `PutBucketVersioning`, and in-process for
`PutBucketVersioning` and `PutBucketTagging`. It is fully deterministic: the
guard is a pure header check with no timing or backend dependence. Every user
of these operations hits it; the only workarounds are setting
`request_checksum_calculation=when_required` *and* passing `ContentMD5=` by
hand (impossible for `DeleteObjects`, whose pinned request shape has no
`ContentMD5` member), so `DeleteObjects` is unreachable from a stock SDK under
any configuration. Object-path checksums are unaffected: `PutObject`,
`UploadPart`, `CreateMultipartUpload`, `CompleteMultipartUpload`, `HeadObject`
and `GetObject` all accepted the stock client's default and explicit checksum
requests (see the probe below). A fix is a maintainer decision about the
integrity-header contract: accept a valid checksum group as an alternative to
`Content-MD5` on the `requestChecksumRequired` operations (the natural reading
of the model, and what the code at 5033-5140 is already able to verify), keep
requiring `Content-MD5` only where the model still defines that member, or
require at least one of the two. Existing tests pin the current behaviour —
the qualification prose at `docs/qualification/bucket-versioning.md:47`,
`docs/qualification/bucket-tagging.md:51` and
`docs/qualification/delete-objects.md:11` and the corresponding corpora would
need updating alongside any change.

---

## Stock client probe

Real stock client, no repository code in the path: **boto3 1.43.89 /
botocore 1.43.89**, Python 3.13.7, resolved from PyPI by
`uv run --python 3.13 --with boto3` (nothing installed system-wide). Client
config: `endpoint_url='http://127.0.0.1:<port>'`, `region_name='us-east-1'`,
`Config(s3={'addressing_style': 'path'})`; wire logging via
`boto3.set_stream_logger('botocore.endpoint'/'botocore.parsers', DEBUG)` plus a
`before-send` / `after-call` event pair that records the exact prepared request
headers and the raw response.

Server: the repository's prebuilt standalone memory-backed server
`tests/bin/s3_memory_server` (not rebuilt), started as
`AWS_ACCESS_KEY_ID=AKIDEXAMPLE AWS_SECRET_ACCESS_KEY=… ./tests/bin/s3_memory_server 0`.
Two runs were made: PID 94752 on port 50198 (aborted mid-(g) by a bug in an
early version of my probe, not by the server) and PID 99302 on port 50691 for
the clean run below. Both were stopped with `kill -TERM`; no Docker was used.

Client-reported defaults: `request_checksum_calculation = when_supported`,
`response_checksum_validation = when_supported`.

Script: `tests/repros/python/checksum_boto3_probe.py` (header comment carries
the run instructions). It exits 1 when the server rejects any of these
requests; it exited **1**, on (e) and (f) only.

| Op | Integrity headers boto3 actually sent | Server |
|----|---------------------------------------|--------|
| a. `create_bucket` | none | 200 |
| b. `put_object` 1 KiB, defaults | `x-amz-sdk-checksum-algorithm: CRC32`, `x-amz-checksum-crc32: YrjmBQ==`, plain body, `Expect: 100-continue` | 200, echoes `x-amz-checksum-crc32: YrjmBQ==`, `x-amz-checksum-type: FULL_OBJECT` |
| c. `put_object` `ChecksumAlgorithm='CRC32'` | identical to (b) | 200, same echo |
| d1. `create_multipart_upload` | `x-amz-checksum-algorithm: CRC32` | 200 |
| d2. `upload_part` ×2 (5 MiB) | `x-amz-sdk-checksum-algorithm: CRC32`, `x-amz-checksum-crc32: 6seAYg==` | 200, echoes the part value |
| d3. `complete_multipart_upload` | `x-amz-checksum-type: COMPOSITE` **and no `x-amz-checksum-<alg>` header**; per-part `<ChecksumCRC32>` elements in the body | 200 |
| e. `delete_objects` (2 keys), defaults | `x-amz-sdk-checksum-algorithm: CRC32`, `x-amz-checksum-crc32: ApXd/g==`, no `Content-MD5` | **400 `InvalidRequest`** |
| f. `put_bucket_versioning`, defaults | `x-amz-sdk-checksum-algorithm: CRC32`, `x-amz-checksum-crc32: C8vlPQ==`, no `Content-MD5` | **400 `InvalidRequest`** |
| g. `head_object` / `get_object` ×3 keys, `ChecksumMode='ENABLED'` | `x-amz-checksum-mode: ENABLED` | 200 for all six; see below |

### What this settles

**The aws-chunked / trailer boundary is not reached by a stock client here.**
The discovery report's observation that trailing checksums are answered
`501 NotImplemented` because stock SDKs use `aws-chunked` did not materialise:
over plain HTTP with a seekable body, botocore 1.43.89 computed the CRC32 up
front and sent a **plain body with a precomputed `x-amz-checksum-crc32`
header** — no `aws-chunked`, no `x-amz-decoded-content-length`, no trailer. The
501 path was never exercised by (b), (c) or (d2). This narrows, but does not
eliminate, that observation: a non-seekable/streaming body or a different SDK
may still choose `aws-chunked`.

**The CompleteMultipartUpload composite-suffix question is settled: botocore
sends no object-level checksum at all.** On `CompleteMultipartUpload` the stock
client sent only `x-amz-checksum-type: COMPOSITE` plus per-part
`<ChecksumCRC32>` elements in the XML body — it sent neither the raw Base64 nor
a `-N`-suffixed value in an `x-amz-checksum-crc32` header. This confirms the
discovery report's reasoning (the pinned model has no `httpChecksum` trait on
that operation), so the server's requirement that a *supplied*
`x-amz-checksum-<alg>` on completion be the raw un-suffixed form is never
exercised by botocore, and remains unverified against a client that does send
one (aws-cli/CRT). The exact request body sent:

```
<CompleteMultipartUpload xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Part><ETag>"d198b1e6a044dcd989829ee8a1860a93"</ETag><PartNumber>1</PartNumber><ChecksumCRC32>6seAYg==</ChecksumCRC32></Part><Part><ETag>"d198b1e6a044dcd989829ee8a1860a93"</ETag><PartNumber>2</PartNumber><ChecksumCRC32>6seAYg==</ChecksumCRC32></Part></CompleteMultipartUpload>
```

and the server's 200 response, which boto3 parsed without complaint:

```
<CompleteMultipartUploadResult …><ETag>"35e3a324abe0ed41ea0cd4344b69ea0f-2"</ETag><ChecksumCRC32>NtfOlg==-2</ChecksumCRC32><ChecksumType>COMPOSITE</ChecksumType></CompleteMultipartUploadResult>
```

**Composite `-N` values on the response side are accepted by the stock client.**
`HeadObject` and `GetObject` on the multipart object returned
`x-amz-checksum-crc32: NtfOlg==-2` with `x-amz-checksum-type: COMPOSITE`, and
botocore surfaced them as `{'ChecksumCRC32': 'NtfOlg==-2', 'ChecksumType':
'COMPOSITE'}` and streamed all 10,485,760 bytes without a validation error
(`response_checksum_validation = when_supported`). Full-object objects returned
the bare value and validated normally.

### Full probe output

Command: `uv run --python 3.13 --with boto3 python3 tests/repros/python/checksum_boto3_probe.py 50691`, exit status **1**.

```
boto3 1.43.89 botocore 1.43.89
endpoint http://127.0.0.1:50691  (path-style, us-east-1)
request_checksum_calculation = when_supported
response_checksum_validation = when_supported

=== a. create_bucket ===
--- request PUT http://127.0.0.1:50691/boto3-checksum-probe
    Authorization: b'AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20260907/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-content-sha256;x-amz-date, Signature=76bb8b75367f6f99322f7462e2bfbed3ffaf264cb8904e9f83ae6b599f216de9'
    Content-Length: 0
    User-Agent: b'Boto3/1.43.89 md/Botocore#1.43.89 ua/2.1 os/macos#25.6.0 md/arch#arm64 lang/python#3.13.7 md/pyimpl#CPython m/b,N,Z,e,D cfg/retry-mode#legacy Botocore/1.43.89'
    X-Amz-Content-SHA256: b'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
    X-Amz-Date: b'20260907T015226Z'
    amz-sdk-invocation-id: b'f86cc435-b3fa-45d9-aea9-c55c1ce75892'
    amz-sdk-request: b'attempt=1'
--- request body: <none>
--- response status 200
    Connection: keep-alive
    Content-Length: 0
    Date: Mon, 07 Sep 2026 01:52:26 GMT
    Location: /boto3-checksum-probe
--- response body: ''

=== b. put_object 1 KiB, boto3 defaults ===
--- request PUT http://127.0.0.1:50691/boto3-checksum-probe/default-put
    Authorization: b'AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20260907/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-checksum-crc32;x-amz-content-sha256;x-amz-date;x-amz-sdk-checksum-algorithm, Signature=ebd28af2eb1fed1027a41ff6298ed4f896be7d2e47e7d18b483b889b5410052d'
    Content-Length: 1024
    Expect: b'100-continue'
    User-Agent: b'Boto3/1.43.89 md/Botocore#1.43.89 ua/2.1 os/macos#25.6.0 md/arch#arm64 lang/python#3.13.7 md/pyimpl#CPython m/b,U,N,Z,e,D cfg/retry-mode#legacy Botocore/1.43.89'
    X-Amz-Content-SHA256: b'1a165b0441c13a4aeef71979af0ae17b407ec3cba0a6247e62b5282fba3a1af1'
    X-Amz-Date: b'20260907T015226Z'
    amz-sdk-invocation-id: b'10202ff1-2a83-487c-bbbb-59fcd3a38bae'
    amz-sdk-request: b'attempt=1'
    x-amz-checksum-crc32: b'YrjmBQ=='
    x-amz-sdk-checksum-algorithm: b'CRC32'
--- request body: <stream BytesIO>
--- response status 200
    Connection: keep-alive
    Content-Length: 0
    Date: Mon, 07 Sep 2026 01:52:26 GMT
    ETag: "0be7de869d1e7f8ebacf59954ce005cc"
    x-amz-checksum-crc32: YrjmBQ==
    x-amz-checksum-type: FULL_OBJECT
    x-amz-object-size: 1024
--- response body: ''

=== c. put_object 1 KiB, ChecksumAlgorithm=CRC32 ===
--- request PUT http://127.0.0.1:50691/boto3-checksum-probe/crc32-put
    Authorization: b'AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20260907/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-checksum-crc32;x-amz-content-sha256;x-amz-date;x-amz-sdk-checksum-algorithm, Signature=fb58974ddf790fe00a3d081fc40f826f823b9fb1f48f575ef53586f7d58258ab'
    Content-Length: 1024
    Expect: b'100-continue'
    User-Agent: b'Boto3/1.43.89 md/Botocore#1.43.89 ua/2.1 os/macos#25.6.0 md/arch#arm64 lang/python#3.13.7 md/pyimpl#CPython m/b,U,N,Z,e,D cfg/retry-mode#legacy Botocore/1.43.89'
    X-Amz-Content-SHA256: b'1a165b0441c13a4aeef71979af0ae17b407ec3cba0a6247e62b5282fba3a1af1'
    X-Amz-Date: b'20260907T015226Z'
    amz-sdk-invocation-id: b'3b6b4347-c831-49a7-93dd-bed4e2aac48c'
    amz-sdk-request: b'attempt=1'
    x-amz-checksum-crc32: b'YrjmBQ=='
    x-amz-sdk-checksum-algorithm: b'CRC32'
--- request body: <stream BytesIO>
--- response status 200
    Connection: keep-alive
    Content-Length: 0
    Date: Mon, 07 Sep 2026 01:52:26 GMT
    ETag: "0be7de869d1e7f8ebacf59954ce005cc"
    x-amz-checksum-crc32: YrjmBQ==
    x-amz-checksum-type: FULL_OBJECT
    x-amz-object-size: 1024
--- response body: ''

=== d1. create_multipart_upload ChecksumAlgorithm=CRC32 ===
--- request POST http://127.0.0.1:50691/boto3-checksum-probe/multipart-crc32?uploads
    Authorization: b'AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20260907/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-checksum-algorithm;x-amz-content-sha256;x-amz-date, Signature=e0eff432377bc0d58a455eba9efb433922042591ddb883fc3b16f6f776c9b55f'
    Content-Length: 0
    User-Agent: b'Boto3/1.43.89 md/Botocore#1.43.89 ua/2.1 os/macos#25.6.0 md/arch#arm64 lang/python#3.13.7 md/pyimpl#CPython m/b,N,Z,e,D cfg/retry-mode#legacy Botocore/1.43.89'
    X-Amz-Content-SHA256: b'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
    X-Amz-Date: b'20260907T015226Z'
    amz-sdk-invocation-id: b'737f0322-3113-43c3-a015-71291b10da2e'
    amz-sdk-request: b'attempt=1'
    x-amz-checksum-algorithm: b'CRC32'
--- request body: <none>
--- response status 200
    Connection: keep-alive
    Content-Length: 297
    Content-Type: application/xml
    Date: Mon, 07 Sep 2026 01:52:26 GMT
--- response body: '<?xml version="1.0" encoding="UTF-8"?><InitiateMultipartUploadResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Bucket>boto3-checksum-probe</Bucket><Key>multipart-crc32</Key><UploadId>8160bed092743a8ddefdafd229a994bec5cb9e09d139c667e45a12a72c00cbc1</UploadId></InitiateMultipartUploadResult>'
    UploadId=8160bed092743a8ddefdafd229a994bec5cb9e09d139c667e45a12a72c00cbc1 ChecksumAlgorithm=None ChecksumType=None

=== d2.1 upload_part 1 (5 MiB) ChecksumAlgorithm=CRC32 ===
--- request PUT http://127.0.0.1:50691/boto3-checksum-probe/multipart-crc32?uploadId=8160bed092743a8ddefdafd229a994bec5cb9e09d139c667e45a12a72c00cbc1&partNumber=1
    Authorization: b'AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20260907/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-checksum-crc32;x-amz-content-sha256;x-amz-date;x-amz-sdk-checksum-algorithm, Signature=e2e7cceeef41a26ec5c190f1543b4338bef893c21b0dfca602b351fdb94bce25'
    Content-Length: 5242880
    Expect: b'100-continue'
    User-Agent: b'Boto3/1.43.89 md/Botocore#1.43.89 ua/2.1 os/macos#25.6.0 md/arch#arm64 lang/python#3.13.7 md/pyimpl#CPython m/b,U,N,Z,e,D cfg/retry-mode#legacy Botocore/1.43.89'
    X-Amz-Content-SHA256: b'f1f30bc985f38d10ced7ccb81e74898cb828aaa7b8a501e0789e03dc91019b80'
    X-Amz-Date: b'20260907T015226Z'
    amz-sdk-invocation-id: b'9788fea3-4d3e-4b6a-8213-d593907e19d2'
    amz-sdk-request: b'attempt=1'
    x-amz-checksum-crc32: b'6seAYg=='
    x-amz-sdk-checksum-algorithm: b'CRC32'
--- request body: <stream BytesIO>
--- response status 200
    Connection: keep-alive
    Content-Length: 0
    Date: Mon, 07 Sep 2026 01:52:26 GMT
    ETag: "d198b1e6a044dcd989829ee8a1860a93"
    x-amz-checksum-crc32: 6seAYg==
--- response body: ''
    part 1 ETag="d198b1e6a044dcd989829ee8a1860a93" ChecksumCRC32='6seAYg=='

=== d2.2 upload_part 2 (5 MiB) ChecksumAlgorithm=CRC32 ===
--- request PUT http://127.0.0.1:50691/boto3-checksum-probe/multipart-crc32?uploadId=8160bed092743a8ddefdafd229a994bec5cb9e09d139c667e45a12a72c00cbc1&partNumber=2
    Authorization: b'AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20260907/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-checksum-crc32;x-amz-content-sha256;x-amz-date;x-amz-sdk-checksum-algorithm, Signature=6385f82bbc93129dd9351d26b968c6ae20fa111535379033165c148a9215c506'
    Content-Length: 5242880
    Expect: b'100-continue'
    User-Agent: b'Boto3/1.43.89 md/Botocore#1.43.89 ua/2.1 os/macos#25.6.0 md/arch#arm64 lang/python#3.13.7 md/pyimpl#CPython m/b,U,N,Z,e,D cfg/retry-mode#legacy Botocore/1.43.89'
    X-Amz-Content-SHA256: b'f1f30bc985f38d10ced7ccb81e74898cb828aaa7b8a501e0789e03dc91019b80'
    X-Amz-Date: b'20260907T015226Z'
    amz-sdk-invocation-id: b'430eadef-e369-4575-b33e-4f5f9b3e75ae'
    amz-sdk-request: b'attempt=1'
    x-amz-checksum-crc32: b'6seAYg=='
    x-amz-sdk-checksum-algorithm: b'CRC32'
--- request body: <stream BytesIO>
--- response status 200
    Connection: keep-alive
    Content-Length: 0
    Date: Mon, 07 Sep 2026 01:52:26 GMT
    ETag: "d198b1e6a044dcd989829ee8a1860a93"
    x-amz-checksum-crc32: 6seAYg==
--- response body: ''
    part 2 ETag="d198b1e6a044dcd989829ee8a1860a93" ChecksumCRC32='6seAYg=='

=== d3. complete_multipart_upload (composite CRC32) ===
--- request POST http://127.0.0.1:50691/boto3-checksum-probe/multipart-crc32?uploadId=8160bed092743a8ddefdafd229a994bec5cb9e09d139c667e45a12a72c00cbc1
    Authorization: b'AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20260907/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-checksum-type;x-amz-content-sha256;x-amz-date, Signature=edb066ed3b1d96d2aa665497058ff35b11bcc2cba00464664523527e1f25644a'
    Content-Length: 349
    User-Agent: b'Boto3/1.43.89 md/Botocore#1.43.89 ua/2.1 os/macos#25.6.0 md/arch#arm64 lang/python#3.13.7 md/pyimpl#CPython m/b,N,Z,e,D cfg/retry-mode#legacy Botocore/1.43.89'
    X-Amz-Content-SHA256: b'5a1de4ebff03f8ee6b47b86599275bf11f62b578e24407b3cfedd194a014e9bc'
    X-Amz-Date: b'20260907T015226Z'
    amz-sdk-invocation-id: b'04a95bbd-0872-4b08-bf2d-b1542068e48c'
    amz-sdk-request: b'attempt=1'
    x-amz-checksum-type: b'COMPOSITE'
--- request body: bytes(349): b'<CompleteMultipartUpload xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Part><ETag>"d198b1e6a044dcd989829ee8a1860a93"</ETag><PartNumber>1</PartNumber><ChecksumCRC32>6seAYg==</ChecksumCRC32></Part><Part><ETag>"d198b1e6a044dcd989829ee8a1860a93"</ETag><PartNumber>2</PartNumber><ChecksumCRC32>6seAYg==</ChecksumCRC32></Part></CompleteMultipartUpload>'
--- response status 200
    Connection: keep-alive
    Content-Length: 398
    Content-Type: application/xml
    Date: Mon, 07 Sep 2026 01:52:26 GMT
--- response body: '<?xml version="1.0" encoding="UTF-8"?><CompleteMultipartUploadResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Location>/boto3-checksum-probe/multipart-crc32</Location><Bucket>boto3-checksum-probe</Bucket><Key>multipart-crc32</Key><ETag>"35e3a324abe0ed41ea0cd4344b69ea0f-2"</ETag><ChecksumCRC32>NtfOlg==-2</ChecksumCRC32><ChecksumType>COMPOSITE</ChecksumType></CompleteMultipartUploadResult>'
    completed ChecksumCRC32='NtfOlg==-2' ChecksumType='COMPOSITE'

=== e. delete_objects (two keys), boto3 defaults ===
--- request POST http://127.0.0.1:50691/boto3-checksum-probe?delete
    Authorization: b'AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20260907/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-checksum-crc32;x-amz-content-sha256;x-amz-date;x-amz-sdk-checksum-algorithm, Signature=0d66677361991751a5aa830d2e1d90397ddf65bdce0db432ae73e19fea7f8af5'
    Content-Length: 137
    User-Agent: b'Boto3/1.43.89 md/Botocore#1.43.89 ua/2.1 os/macos#25.6.0 md/arch#arm64 lang/python#3.13.7 md/pyimpl#CPython m/b,U,N,Z,e,D cfg/retry-mode#legacy Botocore/1.43.89'
    X-Amz-Content-SHA256: b'4795d650e61e4eca68f8f20f376576c402445deb89b9b58ec953d1a43eb9f038'
    X-Amz-Date: b'20260907T015226Z'
    amz-sdk-invocation-id: b'6f7c223f-5ff9-4e51-9d7f-8cf9e48d7336'
    amz-sdk-request: b'attempt=1'
    x-amz-checksum-crc32: b'ApXd/g=='
    x-amz-sdk-checksum-algorithm: b'CRC32'
--- request body: bytes(137): b'<Delete xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Object><Key>absent-1</Key></Object><Object><Key>absent-2</Key></Object></Delete>'
--- response status 400
    Connection: keep-alive
    Content-Length: 199
    Content-Type: application/xml
    Date: Mon, 07 Sep 2026 01:52:26 GMT
--- response body: '<?xml version="1.0" encoding="UTF-8"?><Error><Code>InvalidRequest</Code><Message>DeleteObjects requires one valid Content-MD5 header</Message><Resource>/boto3-checksum-probe?delete</Resource></Error>'
--- CLIENT ERROR: An error occurred (InvalidRequest) when calling the DeleteObjects operation: DeleteObjects requires one valid Content-MD5 header

=== f. put_bucket_versioning, boto3 defaults ===
--- request PUT http://127.0.0.1:50691/boto3-checksum-probe?versioning
    Authorization: b'AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20260907/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-checksum-crc32;x-amz-content-sha256;x-amz-date;x-amz-sdk-checksum-algorithm, Signature=f63589660d452b4872d7286ef14372802e148610c2a5f95ef8b5f2f6f1eb679c'
    Content-Length: 123
    User-Agent: b'Boto3/1.43.89 md/Botocore#1.43.89 ua/2.1 os/macos#25.6.0 md/arch#arm64 lang/python#3.13.7 md/pyimpl#CPython m/b,U,N,Z,e,D cfg/retry-mode#legacy Botocore/1.43.89'
    X-Amz-Content-SHA256: b'482d4e510b5cdcf0bbf3a044e82832dc711f4f28757a6c06eb21758282a73ef7'
    X-Amz-Date: b'20260907T015226Z'
    amz-sdk-invocation-id: b'd59f8cfc-3b1c-40f9-abec-a6da6f943b4f'
    amz-sdk-request: b'attempt=1'
    x-amz-checksum-crc32: b'C8vlPQ=='
    x-amz-sdk-checksum-algorithm: b'CRC32'
--- request body: bytes(123): b'<VersioningConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Status>Enabled</Status></VersioningConfiguration>'
--- response status 400
    Connection: close
    Content-Length: 209
    Content-Type: application/xml
    Date: Mon, 07 Sep 2026 01:52:26 GMT
--- response body: '<?xml version="1.0" encoding="UTF-8"?><Error><Code>InvalidRequest</Code><Message>PutBucketVersioning requires one valid Content-MD5 header</Message><Resource>/boto3-checksum-probe?versioning</Resource></Error>'
--- CLIENT ERROR: An error occurred (InvalidRequest) when calling the PutBucketVersioning operation: PutBucketVersioning requires one valid Content-MD5 header

=== g1. head_object default-put ChecksumMode=ENABLED ===
--- request HEAD http://127.0.0.1:50691/boto3-checksum-probe/default-put
    Authorization: b'AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20260907/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-checksum-mode;x-amz-content-sha256;x-amz-date, Signature=8e029fb231838578ce03f241ef93638a47f2e4315640743f843bdf1a2bcf352e'
    User-Agent: b'Boto3/1.43.89 md/Botocore#1.43.89 ua/2.1 os/macos#25.6.0 md/arch#arm64 lang/python#3.13.7 md/pyimpl#CPython m/b,N,Z,e,D cfg/retry-mode#legacy Botocore/1.43.89'
    X-Amz-Content-SHA256: b'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
    X-Amz-Date: b'20260907T015226Z'
    amz-sdk-invocation-id: b'94c9e817-f07d-427f-8b3e-a9ae2f9b2c63'
    amz-sdk-request: b'attempt=1'
    x-amz-checksum-mode: b'ENABLED'
--- request body: <none>
--- response status 200
    Accept-Ranges: bytes
    Connection: keep-alive
    Content-Length: 1024
    Content-Type: application/octet-stream
    Date: Mon, 07 Sep 2026 01:52:26 GMT
    ETag: "0be7de869d1e7f8ebacf59954ce005cc"
    Last-Modified: Mon, 07 Sep 2026 01:52:27 GMT
    x-amz-checksum-crc32: YrjmBQ==
    x-amz-checksum-type: FULL_OBJECT
    x-amz-version-id: null
--- response body: ''
    HEAD checksums: {'ChecksumCRC32': 'YrjmBQ==', 'ChecksumType': 'FULL_OBJECT'}

=== g2. get_object default-put ChecksumMode=ENABLED ===
--- request GET http://127.0.0.1:50691/boto3-checksum-probe/default-put
    Authorization: b'AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20260907/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-checksum-mode;x-amz-content-sha256;x-amz-date, Signature=8ea183c3eee57821b6d7769e9d45f4f0ee3e2bc2128eb59dbf29f019dffb40f8'
    User-Agent: b'Boto3/1.43.89 md/Botocore#1.43.89 ua/2.1 os/macos#25.6.0 md/arch#arm64 lang/python#3.13.7 md/pyimpl#CPython m/b,N,Z,e,D cfg/retry-mode#legacy Botocore/1.43.89'
    X-Amz-Content-SHA256: b'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
    X-Amz-Date: b'20260907T015226Z'
    amz-sdk-invocation-id: b'062751e8-2ac1-407d-8983-ce3e4eb6c50c'
    amz-sdk-request: b'attempt=1'
    x-amz-checksum-mode: b'ENABLED'
--- request body: <none>
--- response status 200
    Accept-Ranges: bytes
    Connection: keep-alive
    Content-Length: 1024
    Content-Type: application/octet-stream
    Date: Mon, 07 Sep 2026 01:52:26 GMT
    ETag: "0be7de869d1e7f8ebacf59954ce005cc"
    Last-Modified: Mon, 07 Sep 2026 01:52:27 GMT
    x-amz-checksum-crc32: YrjmBQ==
    x-amz-checksum-type: FULL_OBJECT
--- response body: '<streaming body, read by the caller>'
    GET 1024 bytes, checksums: {'ChecksumCRC32': 'YrjmBQ==', 'ChecksumType': 'FULL_OBJECT'}

=== g1. head_object crc32-put ChecksumMode=ENABLED ===
--- request HEAD http://127.0.0.1:50691/boto3-checksum-probe/crc32-put
    Authorization: b'AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20260907/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-checksum-mode;x-amz-content-sha256;x-amz-date, Signature=4bbd054971f58c83f93a478ba431c89f0ddfbb7e2410aaa87b5939a1e0da80af'
    User-Agent: b'Boto3/1.43.89 md/Botocore#1.43.89 ua/2.1 os/macos#25.6.0 md/arch#arm64 lang/python#3.13.7 md/pyimpl#CPython m/b,N,Z,e,D cfg/retry-mode#legacy Botocore/1.43.89'
    X-Amz-Content-SHA256: b'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
    X-Amz-Date: b'20260907T015226Z'
    amz-sdk-invocation-id: b'0ec7449c-1a51-4fae-a066-6116855f2e51'
    amz-sdk-request: b'attempt=1'
    x-amz-checksum-mode: b'ENABLED'
--- request body: <none>
--- response status 200
    Accept-Ranges: bytes
    Connection: keep-alive
    Content-Length: 1024
    Content-Type: application/octet-stream
    Date: Mon, 07 Sep 2026 01:52:26 GMT
    ETag: "0be7de869d1e7f8ebacf59954ce005cc"
    Last-Modified: Mon, 07 Sep 2026 01:52:27 GMT
    x-amz-checksum-crc32: YrjmBQ==
    x-amz-checksum-type: FULL_OBJECT
    x-amz-version-id: null
--- response body: ''
    HEAD checksums: {'ChecksumCRC32': 'YrjmBQ==', 'ChecksumType': 'FULL_OBJECT'}

=== g2. get_object crc32-put ChecksumMode=ENABLED ===
--- request GET http://127.0.0.1:50691/boto3-checksum-probe/crc32-put
    Authorization: b'AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20260907/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-checksum-mode;x-amz-content-sha256;x-amz-date, Signature=f8a6997168f11c17f8d26a0996aba99b21f9bb51a41c19432e8513491e10f348'
    User-Agent: b'Boto3/1.43.89 md/Botocore#1.43.89 ua/2.1 os/macos#25.6.0 md/arch#arm64 lang/python#3.13.7 md/pyimpl#CPython m/b,N,Z,e,D cfg/retry-mode#legacy Botocore/1.43.89'
    X-Amz-Content-SHA256: b'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
    X-Amz-Date: b'20260907T015226Z'
    amz-sdk-invocation-id: b'68a951a5-1fc7-4ffa-ae23-d236559a5200'
    amz-sdk-request: b'attempt=1'
    x-amz-checksum-mode: b'ENABLED'
--- request body: <none>
--- response status 200
    Accept-Ranges: bytes
    Connection: keep-alive
    Content-Length: 1024
    Content-Type: application/octet-stream
    Date: Mon, 07 Sep 2026 01:52:26 GMT
    ETag: "0be7de869d1e7f8ebacf59954ce005cc"
    Last-Modified: Mon, 07 Sep 2026 01:52:27 GMT
    x-amz-checksum-crc32: YrjmBQ==
    x-amz-checksum-type: FULL_OBJECT
--- response body: '<streaming body, read by the caller>'
    GET 1024 bytes, checksums: {'ChecksumCRC32': 'YrjmBQ==', 'ChecksumType': 'FULL_OBJECT'}

=== g1. head_object multipart-crc32 ChecksumMode=ENABLED ===
--- request HEAD http://127.0.0.1:50691/boto3-checksum-probe/multipart-crc32
    Authorization: b'AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20260907/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-checksum-mode;x-amz-content-sha256;x-amz-date, Signature=818733370fa3546c68b90bb0421f5f30bef1dcca4455aaf4a454c11b7f21d9f3'
    User-Agent: b'Boto3/1.43.89 md/Botocore#1.43.89 ua/2.1 os/macos#25.6.0 md/arch#arm64 lang/python#3.13.7 md/pyimpl#CPython m/b,N,Z,e,D cfg/retry-mode#legacy Botocore/1.43.89'
    X-Amz-Content-SHA256: b'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
    X-Amz-Date: b'20260907T015226Z'
    amz-sdk-invocation-id: b'9dbcc986-be23-40d0-8cdc-78f4ca7c143b'
    amz-sdk-request: b'attempt=1'
    x-amz-checksum-mode: b'ENABLED'
--- request body: <none>
--- response status 200
    Accept-Ranges: bytes
    Connection: keep-alive
    Content-Length: 10485760
    Content-Type: application/octet-stream
    Date: Mon, 07 Sep 2026 01:52:26 GMT
    ETag: "35e3a324abe0ed41ea0cd4344b69ea0f-2"
    Last-Modified: Mon, 07 Sep 2026 01:52:27 GMT
    x-amz-checksum-crc32: NtfOlg==-2
    x-amz-checksum-type: COMPOSITE
    x-amz-version-id: null
--- response body: ''
    HEAD checksums: {'ChecksumCRC32': 'NtfOlg==-2', 'ChecksumType': 'COMPOSITE'}

=== g2. get_object multipart-crc32 ChecksumMode=ENABLED ===
--- request GET http://127.0.0.1:50691/boto3-checksum-probe/multipart-crc32
    Authorization: b'AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20260907/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-checksum-mode;x-amz-content-sha256;x-amz-date, Signature=4a74ab4cf508505754147ad91d8e930d8e4adf4eb8869f2ce3c6117ad2ca8db5'
    User-Agent: b'Boto3/1.43.89 md/Botocore#1.43.89 ua/2.1 os/macos#25.6.0 md/arch#arm64 lang/python#3.13.7 md/pyimpl#CPython m/b,N,Z,e,D cfg/retry-mode#legacy Botocore/1.43.89'
    X-Amz-Content-SHA256: b'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
    X-Amz-Date: b'20260907T015226Z'
    amz-sdk-invocation-id: b'008fac74-3146-4505-9a6c-16693d96835f'
    amz-sdk-request: b'attempt=1'
    x-amz-checksum-mode: b'ENABLED'
--- request body: <none>
--- response status 200
    Accept-Ranges: bytes
    Connection: keep-alive
    Content-Length: 10485760
    Content-Type: application/octet-stream
    Date: Mon, 07 Sep 2026 01:52:26 GMT
    ETag: "35e3a324abe0ed41ea0cd4344b69ea0f-2"
    Last-Modified: Mon, 07 Sep 2026 01:52:27 GMT
    x-amz-checksum-crc32: NtfOlg==-2
    x-amz-checksum-type: COMPOSITE
--- response body: '<streaming body, read by the caller>'
    GET 10485760 bytes, checksums: {'ChecksumCRC32': 'NtfOlg==-2', 'ChecksumType': 'COMPOSITE'}

=== SUMMARY ===
accepted   a. create_bucket  (status 200)
accepted   b. put_object 1 KiB, boto3 defaults  (status 200)
accepted   c. put_object 1 KiB, ChecksumAlgorithm=CRC32  (status 200)
accepted   d1. create_multipart_upload ChecksumAlgorithm=CRC32  (status 200)
accepted   d2.1 upload_part 1 (5 MiB) ChecksumAlgorithm=CRC32  (status 200)
accepted   d2.2 upload_part 2 (5 MiB) ChecksumAlgorithm=CRC32  (status 200)
accepted   d3. complete_multipart_upload (composite CRC32)  (status 200)
REJECTED   e. delete_objects (two keys), boto3 defaults  (status 400; An error occurred (InvalidRequest) when calling the DeleteObjects operation: DeleteObjects requires one valid Content-MD5 header)
REJECTED   f. put_bucket_versioning, boto3 defaults  (status 400; An error occurred (InvalidRequest) when calling the PutBucketVersioning operation: PutBucketVersioning requires one valid Content-MD5 header)
accepted   g1. head_object default-put ChecksumMode=ENABLED  (status 200)
accepted   g2. get_object default-put ChecksumMode=ENABLED  (status 200)
accepted   g1. head_object crc32-put ChecksumMode=ENABLED  (status 200)
accepted   g2. get_object crc32-put ChecksumMode=ENABLED  (status 200)
accepted   g1. head_object multipart-crc32 ChecksumMode=ENABLED  (status 200)
accepted   g2. get_object multipart-crc32 ChecksumMode=ENABLED  (status 200)

STOCK CLIENT REQUESTS REJECTED:
  e. delete_objects (two keys), boto3 defaults -> status 400; An error occurred (InvalidRequest) when calling the DeleteObjects operation: DeleteObjects requires one valid Content-MD5 header
  f. put_bucket_versioning, boto3 defaults -> status 400; An error occurred (InvalidRequest) when calling the PutBucketVersioning operation: PutBucketVersioning requires one valid Content-MD5 header
```

## Cross-area evidence

### DeleteObjects rejects a stock boto3 client's default request (for SERVER consolidation)

Recorded here rather than numbered in this area, as directed. It is the same
mechanism as CHECKSUM-2 — the server requires `Content-MD5` on an operation the
pinned model marks `httpChecksum.requestChecksumRequired: true`, and does not
accept the `x-amz-checksum-<alg>` group a modern SDK sends instead — but with a
sharper edge: **`DeleteObjectsRequest` has no `ContentMD5` member at all in
`review/baseline/service-2.json`**, so no SDK caller can supply the header the
server demands through the modeled API. `DeleteObjects` is therefore unreachable
from a stock SDK under any client configuration.

Server guard: `src/flyology-object_storage-server-s3_applications.adb:17683`,
`"DeleteObjects requires one valid Content-MD5 header"`.

Exact request (boto3 1.43.89 / botocore 1.43.89, defaults, path-style,
`http://127.0.0.1:50691`):

```
POST http://127.0.0.1:50691/boto3-checksum-probe?delete
    Authorization: AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20260907/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-checksum-crc32;x-amz-content-sha256;x-amz-date;x-amz-sdk-checksum-algorithm, Signature=0d66677361991751a5aa830d2e1d90397ddf65bdce0db432ae73e19fea7f8af5
    Content-Length: 137
    User-Agent: Boto3/1.43.89 md/Botocore#1.43.89 ua/2.1 os/macos#25.6.0 md/arch#arm64 lang/python#3.13.7 md/pyimpl#CPython m/b,U,N,Z,e,D cfg/retry-mode#legacy Botocore/1.43.89
    X-Amz-Content-SHA256: 4795d650e61e4eca68f8f20f376576c402445deb89b9b58ec953d1a43eb9f038
    X-Amz-Date: 20260907T015226Z
    x-amz-checksum-crc32: ApXd/g==
    x-amz-sdk-checksum-algorithm: CRC32
    (no Content-MD5)

body: <Delete xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Object><Key>absent-1</Key></Object><Object><Key>absent-2</Key></Object></Delete>
```

Exact response:

```
HTTP/1.1 400
    Connection: keep-alive
    Content-Length: 199
    Content-Type: application/xml

<?xml version="1.0" encoding="UTF-8"?><Error><Code>InvalidRequest</Code><Message>DeleteObjects requires one valid Content-MD5 header</Message><Resource>/boto3-checksum-probe?delete</Resource></Error>
```

botocore surfaced this as
`ClientError: An error occurred (InvalidRequest) when calling the DeleteObjects operation: DeleteObjects requires one valid Content-MD5 header`.

### Minor, non-checksum: the server closed the connection on the PutBucketVersioning error

The 400 for `put_bucket_versioning` (f) came back with `Connection: close`,
while the otherwise identical 400 for `delete_objects` (e) came back with
`Connection: keep-alive`. Both requests were sent by the same client over
keep-alive connections and neither asked for a close. This did not break the
client (botocore reconnected transparently), so it is noted only as an
inconsistency for the SERVER area to judge, not a finding here.

---

## Observations from the discovery report that this verification touched

- **Trailer-borne checksums are unreachable via `aws-chunked` (501).** Not
  exercised by a stock client in this probe: boto3 1.43.89 sent a plain body
  with a precomputed checksum header for all three upload paths. The
  observation stands as written but its practical reach is narrower than
  "stock SDK trailing checksums use aws-chunked" implies, at least for
  seekable bodies over plain HTTP.
- **Composite completion header form (raw Base64, no `-N`).** Settled for
  botocore: it sends no object-level checksum header on
  `CompleteMultipartUpload` at all, so the server's raw-form requirement is
  never exercised by boto3. Still unverified for aws-cli/CRT.
- **UploadPart echoes `x-amz-checksum-<alg>` even when unsolicited.** Confirmed
  harmless in practice: the probe's `upload_part` calls all supplied a
  checksum, and boto3 read the echoed value back as `ChecksumCRC32` without
  issue. Not separately provoked.
- **XXHASH128 byte order, C-bridge alignment, ranged-GET checksum emission.**
  Not addressed by this verification; they remain as recorded in the discovery
  report.
