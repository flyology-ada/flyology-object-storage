# Adversarial verification: TRANSFERS (multi-subject transfer client and multipart planning/codecs)

Scope verified by reading:
`src/flyology-object_storage-client-transfers.ads` (Download_File contract
1662-1714, Upload_File / Checksum_Selection region),
`src/flyology-object_storage-client-transfers.adb:1690-1740` and the
`Upload_Multipart_File` completion region 880-1160,
`src/flyology-object_storage-client-low_level.adb:5933-6005`
(`Valid_Content_Range`, `Validate_Get_Object_Headers`),
`src/flyology-object_storage-s3-multipart.adb` `Parse_Query` 120-170 and
`Validate` (ListParts result) 1620-1650,
`docs/architecture/client-transfers.md`,
`tests/src/s3_http_socket_corpus.adb` (server `Serve` 961-2036, listener
setup 2549-2557, download lanes 16920-16995),
`tests/scripts/test-minio.sh`,
`docs/compatibility/s3.md` (the "Single byte range", "CompleteMultipartUpload"
and "ListParts" rows), and the pinned botocore model
`review/baseline/service-2.json` (`CompleteMultipartUploadRequest`,
`CompleteMultipartUploadOutput` and `ListPartsOutput` shapes).
Harness programs added: `tests/repros/src/repro_transfers_1.adb`,
`tests/repros/src/repro_transfers_minio_probe.adb`.
Nothing tracked was modified.

| ID | Verdict | Severity (discovery) | Repro |
|----|---------|----------------------|-------|
| TRANSFERS-1 | CONFIRMED (one sub-claim refuted) | P2 (P2) | `tests/repros/src/repro_transfers_1.adb` |

The findings sweep produced no new defect: the MinIO probe below accepted every
request the high-level client sends, so there is no TRANSFERS-2. TRANSFERS-1 is
the only actionable finding in this area, and it is P2.

---

### TRANSFERS-1: `Download_File` misdiagnoses a 200 answer to a `Range` request as an "unsolicited representation interval"

**Verdict:** CONFIRMED for the finding itself. One sub-claim of the discovery
entry is REFUTED: it states "In `Transfer_Many` the same text lands in
`Transfer_Result.Message` for that subject ... the wrong text is
caller-visible through both public entry points". It is not.
`Execute_Transfer` calls `Download_File` at
`src/flyology-object_storage-client-transfers.adb:663-669` with the argument
list ending at `Token`, and `Subject`
(`src/flyology-object_storage-client-transfers.ads:1731-1737`) has no range
field, so `Transfer_Many` can never pass a non-empty `Byte_Range_Header`. Only
the *first* disjunct (no `Range`, status /= 200) is reachable from
`Transfer_Many`, and there the existing text is accurate. The misleading text
is reachable only through the direct `Download_File` entry point.

**Severity:** P2 (discovery said P2; unchanged). The refusal itself is the
documented policy, only the operator-facing text is wrong, which is exactly
the rubric's "wrong diagnostics" band. It is not P1: no valid input produces a
wrong *result*, and the documented contract ("a successful 206 atomically
publishes the selected interval", `.ads:1688-1689`) is honoured.

Verified by reading:

- `src/flyology-object_storage-client-transfers.adb:1711-1716`: the single
  `elsif` covers both `(Byte_Range_Header'Length = 0 and then Head.Status /=
  200)` and `(Byte_Range_Header'Length > 0 and then Head.Status /= 206)`, and
  both raise `Low_Level.Invalid_Response with "GetObject returned an
  unsolicited representation interval"`. `rg` finds that literal at exactly
  one site in the whole repository, so no other message distinguishes the two
  cases.
- `src/flyology-object_storage-client-low_level.adb:5981-5987`
  (`Validate_Get_Object_Headers`): a `200` is rejected only when it *carries*
  `Content-Range`; a plain `200` with `Content-Length` and no `Content-Range`
  is a valid head, so the decode step cannot produce a better message and the
  transfers-level check is the only gate.
- `src/flyology-object_storage-client-transfers.ads:1688-1689` documents range
  mode as "a successful 206 atomically publishes the selected interval",
  and `docs/architecture/client-transfers.md` (Multi-subject transfers) says
  range mode "accepts only HTTP 206 with a strict, coherent single
  `Content-Range`". The refusal is therefore intended; the text is not.
- `src/flyology-object_storage-client-transfers.adb:710-716`
  (`Execute_Transfer`) stores
  `Exception_Name & ": " & Exception_Message` into `Transfer_Result.Message`,
  so an `Invalid_Response` text does surface to `Transfer_Many` callers -- but
  only from the accurate first disjunct, because the call at 663-669 passes no
  `Byte_Range_Header` (see the verdict above).
- Existing coverage: `tests/src/s3_http_socket_corpus.adb:16935-16957`
  (`download-unexpected-range`) exercises only the *first* disjunct and
  asserts nothing about the message; `:16959-16978` (`download-range`)
  exercises a real 206. No maintained lane sends a `Range` and answers 200, so
  the suite never observes the misleading text. No existing test asserts the
  wrong behaviour.

Refutation attempts that failed:

- Looked for an earlier guard that would reject a ranged 200 with an accurate
  message: `Decode_Get_Object_Response_Head`
  (`low_level.adb:7264-7288` -> `Validate_Get_Object_Headers`) never sees the
  request, so it cannot know a `Range` was sent. Confirmed empirically below:
  the head decodes cleanly and the transfers-level `elsif` is what fires.
- Looked for a caller that never passes `Byte_Range_Header`: it is a public
  parameter of `Download_File` with an empty default
  (`.ads:1710`) and is exercised by the maintained suite at
  `s3_http_socket_corpus.adb:16965`, so the path is reachable from the public
  API.
- Looked for a documented policy that makes the text correct: the architecture
  document and the `.ads` justify *refusing*, not the wording. RFC 9110 14.2
  permits a server to ignore `Range` (from memory, unverified), so a 200 to a
  ranged GET is a legitimate server answer and a plausible proxy behaviour,
  not a protocol violation the message should describe as an interval.
- Checked whether the message is only reachable through an internal helper:
  it propagates out of both public entry points (direct `Download_File` and
  `Transfer_Many`'s `Transfer_Result.Message`).

**Repro:** `tests/repros/src/repro_transfers_1.adb`. A tiny loopback
HTTP/1.1 server task (`Flyology.IO.Sockets`, same accept/receive/send shape as
`s3_http_socket_corpus.adb`'s `Serve`) answers three GETs on 127.0.0.1. The
first two answer `200 OK` + `Content-Length: 27` + `ETag` + the whole 27-byte
body regardless of any `Range` header; the third answers an unsolicited
`206` + `Content-Range: bytes 7-13/27`. The program then drives
`Transfers.Download_File` against that origin: (1) unranged, as a control
that the harness and the 200 answer work; (2) with
`Byte_Range_Header => "bytes=7-13"`, asserting the correct diagnostic; (3)
unranged against the 206, as a control showing the *same* text is emitted for
the opposite event. It also asserts the destination is preserved on both
failures and that no download temporary is left in the scratch directory.

**Output** (`cd tests/repros && ./run.sh repro_transfers_1 90`, exit status
**1**):

```
  -- fake HTTP/1.1 server on 127.0.0.1:51619 answers every GET with 200 and the whole 27-byte body
  -- control unranged request: GET /example-bucket/range-ignored HTTP/1.1
  -- control unranged outcome: status 200, bytes 27
  ok: control: unranged Download_File publishes the 200 body
  ok: control: published bytes round-trip
  -- ranged request line: GET /example-bucket/range-ignored HTTP/1.1
  -- ranged request Range header: bytes=7-13
  -- server answered: HTTP/1.1 200 OK, Content-Length 27, no Content-Range
  -- Invalid_Response raised: TRUE
  -- message: "GetObject returned an unsolicited representation interval"
  ok: control: a 200 answer to a ranged request is refused
  ok: control: the refused ranged download leaves the destination untouched
  FAILED: ranged-200 diagnostic does not claim an UNSOLICITED interval (no interval was returned at all)
  FAILED: ranged-200 diagnostic names the actual event: the server ignored the Range and returned the whole representation
  -- unsolicited-206 message: "GetObject returned an unsolicited representation interval"
  ok: control: an unrequested 206 is refused
  ok: control: the unrequested-206 case is the one the 'unsolicited representation interval' text describes
  ok: control: the refused 206 leaves the destination untouched
  -- files left in the scratch directory: 3 (the three destinations)
  ok: control: no download temporary is left behind
BUG REPRODUCED: 2 failed expectation(s)
```

**Description:** `Download_File` uses one status gate for two opposite
protocol events. When the caller passed no `Range` and the server answered
`206`, "GetObject returned an unsolicited representation interval" is exactly
right. When the caller *did* pass a `Range` and the server answered `200` with
the whole representation and no `Content-Range` -- which RFC 9110 permits, and
which a `Range`-stripping proxy or a cache produces in practice -- the same
text is emitted, and it is false in every particular: no interval was
returned, and nothing was unsolicited. The program above shows both cases
producing byte-identical messages. The consequence is diagnostic only: the
destination file is correctly left untouched, no temporary is left behind, and
the refusal matches the documented range-mode contract. Who hits it: any
caller of `Download_File` whose server or intermediary ignores `Range`;
`Transfer_Many` cannot reach it because it never supplies a range. It is
fully deterministic -- the branch is a pure function of
`Byte_Range_Header'Length` and `Head.Status`. A fix needs no new public
constant or parameter: split the `elsif` into two branches with two messages,
for example "GetObject ignored the requested Range and returned the whole
representation" for the ranged-200 case, keeping the existing text for the
unrequested-206 case. No maintained test asserts the current wording, so
splitting it breaks nothing.

---

## MinIO probe

Driven by `tests/repros/src/repro_transfers_minio_probe.adb` against a MinIO
container started **by hand** (not through `tests/scripts/test-minio.sh`, so no
`alr -n build` was triggered and no repository test script was run):

- **Image digest:**
  `quay.io/minio/minio@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e`
  (the exact digest pinned in `tests/scripts/test-minio.sh`).
- **Release string** (`docker run --rm <image> --version`):
  `minio version RELEASE.2025-09-07T16-13-09Z (commit-id=07c3a429bfed433e49018cb0f78a52145d4bedeb)`,
  `Runtime: go1.24.6 linux/arm64` -- matching the provenance the script
  requires.
- Started as `flyology-review-transfers-1292` with
  `--publish 127.0.0.1::9000`, `MINIO_ROOT_USER=FLYOLOGYS3ORACLE`,
  `MINIO_ROOT_PASSWORD=flyology-s3-oracle-secret-key-tests`, waited on
  `/minio/health/live`, mapped to `127.0.0.1:32802`, and
  `docker stop`ped (the container ran `--rm`, so it is gone) at the end.
- The probe reads `FLYOLOGY_REPRO_MINIO_PORT`, `AWS_ACCESS_KEY_ID` and
  `AWS_SECRET_ACCESS_KEY` from the environment and was run through the harness:
  `cd tests/repros && FLYOLOGY_REPRO_MINIO_PORT=32802
  AWS_ACCESS_KEY_ID=FLYOLOGYS3ORACLE
  AWS_SECRET_ACCESS_KEY=flyology-s3-oracle-secret-key-tests
  ./run.sh repro_transfers_minio_probe 300` -> exit status **0 (PASS)**.

### Per-operation results

Object under test: 5,243,904 bytes (5 MiB + 1 KiB) with
`Multipart_Part_Size => 5 MiB`, i.e. exactly two parts. Everything else is the
`Upload_File` / `Download_File` default except the checksum selection, which is
the point of the probe.

| Operation | Request the client sent | MinIO answered |
|---|---|---|
| CreateBucket (raw signed) | `PUT /flyology-review-transfers` | 200, then 409 on the second run |
| `Upload_File`, COMPOSITE **CRC32**, 2 parts | CreateMultipartUpload + 2 UploadParts + CompleteMultipartUpload carrying `x-amz-checksum-crc32: xzKZAw==` (**no `-2` suffix**), `x-amz-checksum-type: COMPOSITE`, `x-amz-mp-object-size` | **HTTP 200**, no error code; body echoed `ChecksumCRC32 = xzKZAw==-2`, `ChecksumType = COMPOSITE`, `ETag "0745720b11a20bf85c34e642ee5abf2c-2"` |
| `Download_File` of that object | plain GET | 200, 5,243,904 bytes, file size matches |
| `Upload_File`, COMPOSITE **SHA256**, 2 parts | same shape, `x-amz-checksum-sha256: GzMp1JDld7Dqf/RUFE2YITbNQwUPPHMSt4So1HTY1x8=` (**no `-2` suffix**) | **HTTP 200**, no error code; body echoed `...x8=-2`, `ChecksumType = COMPOSITE` |
| `Download_File` of that object | plain GET | 200, 5,243,904 bytes, file size matches |
| Hand-built COMPOSITE CRC32 upload completed with the **bare** digest (the form `Upload_File` sends) | `x-amz-checksum-crc32: xzKZAw==` | **HTTP 200**, body `ChecksumCRC32 xzKZAw==-2` |
| Same, completed with the **`-2` suffixed** digest | `x-amz-checksum-crc32: xzKZAw==-2` | **HTTP 200**, body `ChecksumCRC32 xzKZAw==-2` |
| Same, completed with a **deliberately wrong** bare digest | `x-amz-checksum-crc32: AAAAAA==` | **HTTP 400**, `<Code>XAmzContentChecksumMismatch</Code>` |
| `List_Parts_Page`, default page | `max-parts=1000`, marker 0 | 200; 2 parts, `MaxParts 1000`, `PartNumberMarker 0`, `NextPartNumberMarker 0`, `IsTruncated false` -- **accepted by the client** |
| `List_Parts_Page` page walk, page 1 | `max-parts=1`, marker 0 | 200; 1 part, `NextPartNumberMarker 1`, `IsTruncated true` -- accepted |
| `List_Parts_Page` page walk, page 2 | `max-parts=1`, marker 1 | 200; 1 part, `NextPartNumberMarker 0`, `IsTruncated false` -- accepted |
| `List_Parts_Page` page walk, page 3 (past the end) | `max-parts=1`, marker 2 | 200; 0 parts, `NextPartNumberMarker 0`, `IsTruncated false` -- accepted |
| ListParts with `max-parts=2000` | **not expressible through the typed client** (`List_Parts_Parameters.Max_Parts` is `S3.Core.Page_Size`, `Natural range 0 .. 1_000`, `client-low_level.ads:7184` / `s3-core.ads:28`), so sent as a raw signed request | 200, echoed `<MaxParts>2000</MaxParts>`, `IsTruncated false`, `NextPartNumberMarker 0` -- MinIO does **not** clamp |
| AbortMultipartUpload (raw signed) | `DELETE ...?uploadId=` | 204 |

**Nothing the high-level client sends by default was rejected**, so there is no
TRANSFERS-2.

**Output** (`cd tests/repros && FLYOLOGY_REPRO_MINIO_PORT=32802
AWS_ACCESS_KEY_ID=FLYOLOGYS3ORACLE
AWS_SECRET_ACCESS_KEY=flyology-s3-oracle-secret-key-tests ./run.sh
repro_transfers_minio_probe 300`, exit status **0**):

```
  -- MinIO endpoint http://127.0.0.1:32802
  -- source file /private/tmp/claude-501/repro-transfers-minio/two-part.bin is 5243904 bytes
  -- CreateBucket: HTTP 409 (200 = created, 409 = already there)
  ok: test bucket exists on MinIO
  -- --- COMPOSITE CRC32, 5243904 bytes, part size 5242880 (2 parts) ---
  -- CRC32 CompleteMultipartUpload: HTTP 200, no error code
  -- CRC32 completion echoed checksum: "xzKZAw==-2"
  -- CRC32 completion echoed ChecksumType: "COMPOSITE"
  -- CRC32 ETag: "0745720b11a20bf85c34e642ee5abf2c-2"
  ok: MinIO accepts CompleteMultipartUpload with the unsuffixed x-amz-checksum-CRC32 header (CRC32)
  -- CRC32 Download_File: HTTP 200, bytes 5243904
  ok: Download_File round-trips the composite object (CRC32)
  ok: downloaded file has the uploaded size (CRC32)
  -- --- COMPOSITE SHA256, 5243904 bytes, part size 5242880 (2 parts) ---
  -- SHA256 CompleteMultipartUpload: HTTP 200, no error code
  -- SHA256 completion echoed checksum: "GzMp1JDld7Dqf/RUFE2YITbNQwUPPHMSt4So1HTY1x8=-2"
  -- SHA256 completion echoed ChecksumType: "COMPOSITE"
  -- SHA256 ETag: "0745720b11a20bf85c34e642ee5abf2c-2"
  ok: MinIO accepts CompleteMultipartUpload with the unsuffixed x-amz-checksum-SHA256 header (SHA256)
  -- SHA256 Download_File: HTTP 200, bytes 5243904
  ok: Download_File round-trips the composite object (SHA256)
  ok: downloaded file has the uploaded size (SHA256)
  -- --- does MinIO validate the CompleteMultipartUpload checksum header? ---
  -- client-computed composite digest: bare "xzKZAw==", suffixed "xzKZAw==-2"
  -- bare digest, the form Upload_File sends (x-amz-checksum-crc32: xzKZAw==): HTTP 200, Code <>, ChecksumCRC32 <xzKZAw==-2>, ChecksumType <>
  -- suffixed digest (x-amz-checksum-crc32: xzKZAw==-2): HTTP 200, Code <>, ChecksumCRC32 <xzKZAw==-2>, ChecksumType <>
  -- deliberately wrong bare digest (x-amz-checksum-crc32: AAAAAA==): HTTP 400, Code <XAmzContentChecksumMismatch>, ChecksumCRC32 <>, ChecksumType <>
  -- CreateMultipartUpload (raw): HTTP 200
  ok: MinIO returned an upload id
  -- UploadPart 1 (raw): HTTP 200, ETag "f5c72844814e523517b0bcbc17eb638b"
  ok: raw UploadPart 1 succeeded
  -- UploadPart 2 (raw): HTTP 200, ETag "0be7de869d1e7f8ebacf59954ce005cc"
  ok: raw UploadPart 2 succeeded
  -- --- ListParts against a real MinIO two-part upload ---
  -- ListParts default page (max-parts 1000): HTTP 200, parts 2, MaxParts 1000, PartNumberMarker 0, NextPartNumberMarker 0, IsTruncated FALSE
  ok: ListParts default page (max-parts 1000) was accepted by the client
  -- ListParts page walk, page 1 (max-parts 1): HTTP 200, parts 1, MaxParts 1, PartNumberMarker 0, NextPartNumberMarker 1, IsTruncated TRUE
  ok: ListParts page walk, page 1 (max-parts 1) was accepted by the client
  -- ListParts page walk, page 2 (max-parts 1, marker 1): HTTP 200, parts 1, MaxParts 1, PartNumberMarker 1, NextPartNumberMarker 0, IsTruncated FALSE
  ok: ListParts page walk, page 2 (max-parts 1, marker 1) was accepted by the client
  -- ListParts page walk, page 3 (max-parts 1, marker 2): HTTP 200, parts 0, MaxParts 1, PartNumberMarker 2, NextPartNumberMarker 0, IsTruncated FALSE
  ok: ListParts page walk, page 3 (max-parts 1, marker 2) was accepted by the client
  -- List_Parts_Parameters.Max_Parts is S3.Core.Page_Size = Natural range 0 .. 1000, so the typed client cannot send max-parts above 1000; probing MinIO with a raw signed request instead
  -- raw ListParts max-parts=2000: HTTP 200, MaxParts echo <2000>, IsTruncated <false>, NextPartNumberMarker <0>, Code <>
  -- AbortMultipartUpload (raw): HTTP 204
PASS
```

(The `409` on CreateBucket is from the second run of the probe against the same
container; the first run answered `200`.)

### What this settles, and what it does not

- **The `-N` suffix question is settled for MinIO.** The unsuffixed
  `x-amz-checksum-*` completion header that `Upload_Multipart_File` sends
  (`transfers.adb:897-913` strips everything from the last `-`) is accepted by
  the pinned MinIO release, for CRC32 and for SHA256, and MinIO echoes the
  `-N` form the client then requires at `transfers.adb:1146-1156`. The
  wrong-digest run returning `400 XAmzContentChecksumMismatch` proves MinIO
  actually validates that header rather than ignoring it, so the 200 is real
  acceptance. MinIO also accepts the suffixed form, i.e. it is permissive
  about the suffix in the request.
- **AWS is not settled by this.** From memory and marked **unverified**: AWS
  publishes a composite object checksum in the `<digest>-<part count>` form and
  returns it that way. What the pinned botocore model does say
  (`review/baseline/service-2.json`) is indirect but consistent with the
  client's choice: every `CompleteMultipartUploadRequest` checksum member is
  documented as "the Base64 encoded, N-bit ... checksum of the object", with no
  mention of a part-count suffix, while the corresponding
  `CompleteMultipartUploadOutput` members warn that for a multipart object the
  value "may not be a direct checksum value of the full object. Instead, it's a
  calculation based on the checksum values of each individual part". That is
  suggestive, not decisive: the model carries shapes and prose, not the
  server's validation rule, and MinIO's acceptance of the bare form does not
  prove AWS's. Settling it needs a real AWS S3 run.
- **The `IsTruncated = (NextPartNumberMarker > 0)` strictness observation does
  not bite on MinIO.** Every page of a real two-part upload -- truncated,
  final, and past-the-end -- satisfies the rule, so
  `s3-multipart.adb:1636-1637` never raised `Malformed_Multipart`. The
  observation's AWS half (whether AWS echoes the last part number on an
  untruncated page) remains unverified here for the same reason. The pinned
  model's `ListPartsOutput.NextPartNumberMarker` prose -- "When a list is
  truncated, this element specifies the last part in the list" -- says nothing
  about the untruncated case, so it neither supports nor refutes the strict
  rule.
- **The `max-parts` > 1000 observation is a server-side rule, not a client
  one.** `Parse_Query` (`s3-multipart.adb:145-158`) rejects `max-parts` above
  `Core.Page_Size'Last` when *this repository's S3 server* parses an incoming
  query. The client cannot emit such a request at all: `Max_Parts` is typed
  `Page_Size`. One correction to the discovery observation: it says "MinIO
  clamps over-large `max-parts`"; the pinned release does not clamp, it echoes
  `<MaxParts>2000</MaxParts>` verbatim. That has no consequence for this
  client, which cannot ask for it.

---

## Checked, no finding

- **Two-part COMPOSITE upload against a stock server** (CRC32 and SHA256),
  including the CompleteMultipartUpload checksum-header form, the echoed
  `ChecksumType`, the multipart `ETag`, and a full `Download_File` round trip.
  All accepted, evidence above.
- **MinIO validates the completion checksum header** (`400
  XAmzContentChecksumMismatch` on a wrong digest), so acceptance of the
  unsuffixed form is meaningful.
- **ListParts pagination strictness** against a real MinIO two-part upload,
  three-page walk plus the default page. No client-side rejection.
- **`max-parts` above 1000**: not expressible through the typed client;
  MinIO's own behaviour recorded for completeness.
