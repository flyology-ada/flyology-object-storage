# Correctness discovery: CHECKSUM (S3 checksums, CRC combination, policy, engine, xxHash bridge, trailers)

Scope: `src/flyology-object_storage-s3-checksums.ads/.adb` (all),
`src/flyology-object_storage-s3-checksum_crc.ads/.adb` (all),
`src/flyology-object_storage-s3-checksum_policy.ads/.adb` (all),
`src/flyology-object_storage-checksum_engine.ads/.adb` (all),
`src/flyology_object_storage_xxhash.c` (all), `vendor/xxhash/xxhash.h`
(version macros 548-550, `XXH3_state_s` 1770-1800, `XXH3_128bits_reset`
7046-7048, `XXH128_canonicalFromHash` 7127-7136), `vendor/xxhash/README.md`,
`src/flyology-object_storage-s3-wire_core.adb:1-103` (`Valid_Base64`,
`Base64_Character`), `src/flyology-object_storage.ads:60-112`
(`Checksum_Information` contract), `src/flyology-object_storage-s3-core.ads:40-56`.
Callers: `src/flyology-object_storage-server-s3_applications.adb` regions
1600-1700 (header emission), 3670-3735 (checksum header helpers), 3955-4125
(`Request_Source.Read` body/trailer validation), 4180-4210 (response sink
checksum gating), 5030-5135 (`Verify_Document_Checksum`), 12040-12110
(CreateMultipartUpload policy), 12350-12720 (UploadPart), 13040-13245
(CompleteMultipartUpload), 14600-15125 (PutObject), 15548-15566, 17180-17240
(GetObject checksum mode/range); `src/flyology-object_storage-backends-memory.adb`
2880-3000, 3060-3220, 4725-4860, 4960-5060, 5921-6080;
`src/flyology-object_storage-backends-files.adb` 2696-2750, 11700-11790;
`sqlite/src/flyology-object_storage-backends-sqlite.adb` 4200-4265;
`sqlite/src/flyology-object_storage-sqlite-catalogs.adb` 495-525;
`src/flyology-object_storage-client-transfers.adb` 725-860, 895-950,
1040-1170, 1255-1310. Trailer accessors in the pinned dependency
`~/.local/share/alire/releases/flyology_http_0.1.3_b5cd966d/src/flyology-http-server.adb`
(344-388, 2408-2450, `Finished := Item.Body_Done` at 2072/2390).
Reference: `review/baseline/service-2.json` (ChecksumAlgorithm/ChecksumType
enums, PutObject/UploadPart/CompleteMultipartUpload/GetObject/HeadObject
checksum members and `httpChecksum` traits), `docs/architecture/s3-checksums.md`,
`docs/qualification/put-object.md`, `docs/qualification/complete-multipart-upload.md`,
`docs/qualification/get-object-attributes.md`.
Existing coverage inspected: `tests/src/s3_checksum_corpus.adb`,
`tools/generate_s3_checksum_corpus.py`, `tests/corpora/s3-checksums.tsv`
(320 rows), `tests/src/s3_server_application_corpus.adb` (trailer cases
1047-1091, 2845-3024, 6016-6056; multipart checksum cases 3700-3850,
4060-4150; PutObject preflight 6330-6431), `tests/src/s3_implementation_corpus.adb`
(211-220, 533-555, 2935-2975), `tests/src/object_storage_test_cases.adb`
(3662, 6390-6475), `tests/src/s3_multipart_checksum_benchmark.adb`.
Independent arithmetic check: a Python model of `Checksum_CRC.Combine`
(matrix form) was compared against a separately written polynomial
(`x^(8n) mod P`, square-and-multiply) combiner and against `zlib.crc32`
for CRC32, for random operands at lengths 2^31-1, 2^31, 2^32-1, 2^32,
2^32+1, 2^33+12345, 2^40, 2^62 and 2^63-1 for all three algorithms; the
three 64 GiB expected values in `Check_Large_Logical` were reproduced by
the polynomial method independently of the Ada code.

Severity rubric: P0 = memory/aliasing unsafety, security-relevant bypass or
exposure, data loss or durability violation, hang or deadlock, or an
interop-breaking protocol violation a stock client or server rejects.
P1 = wrong result or unexpected exception on valid input via a reachable
path, or a documented contract (`.ads`, README, compatibility matrix,
qualification document) violated. P2 = edge-case incorrectness, wrong
diagnostics, or contract drift needing unusual input.

| ID | Title | Severity | Confidence |
|----|-------|----------|------------|
| CHECKSUM-1 | PutObject answers `InvalidRequest` where the pinned model documents `BadDigest` for an `x-amz-sdk-checksum-algorithm` / `x-amz-checksum-<alg>` algorithm mismatch; the corpus asserts the divergent code | P2 | Medium |

---

### CHECKSUM-1: PutObject answers `InvalidRequest` where the pinned model documents `BadDigest` for an SDK-algorithm / value-header mismatch

**Location:** `src/flyology-object_storage-server-s3_applications.adb:14809-14821`
(PutObject); same pattern at
`src/flyology-object_storage-server-s3_applications.adb:15554-15562`
(Put_Object_Annotation). Test asserting the divergent code:
`tests/src/s3_server_application_corpus.adb:6334-6341, 6428-6431`.

**Severity:** P2. **Confidence:** Medium.

**Evidence:**

`src/flyology-object_storage-server-s3_applications.adb:14809-14821`
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

Pinned model, `review/baseline/service-2.json`, shape `PutObjectRequest`,
member `ChecksumAlgorithm` (`x-amz-sdk-checksum-algorithm`), documentation
(HTML stripped): "If the individual checksum value you provide through
x-amz-checksum-algorithm doesn't match the checksum algorithm you set through
x-amz-sdk-checksum-algorithm, Amazon S3 fails the request with a BadDigest
error."

By contrast the model's `UploadPartRequest.ChecksumAlgorithm` says "If you
provide an individual checksum, Amazon S3 ignores any provided
ChecksumAlgorithm parameter", and the server's UploadPart path
(`s3_applications.adb:12535-12556`) indeed ignores the SDK selector when a
value header is present, so the two routes already implement two different
rules; only the PutObject one contradicts its own model text.

`tests/src/s3_server_application_corpus.adb:6334-6341`
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
`tests/src/s3_server_application_corpus.adb:6428-6431`
```ada
        (Has (SDK_Mismatch, "<Code>InvalidRequest</Code>")
         and then Has (SDK_Missing_Value, "<Code>InvalidRequest</Code>")
         and then Has (Invalid_MD5, "<Code>InvalidDigest</Code>"),
         "PutObject checksum-group preflight failed");
```

**Failure scenario:** A client sends `PUT /bucket/key` with
`x-amz-sdk-checksum-algorithm: SHA256` and a well-formed
`x-amz-checksum-crc32: <base64>` header. At line 14809 `Selected` is
`Checksum_SHA256` (parsed at 14790-14805) and `Checksum_Value_Algorithm`
is `Checksum_CRC32`; the branch sends HTTP 400 with `<Code>InvalidRequest</Code>`.
The model's documented response is HTTP 400 with `<Code>BadDigest</Code>`.
Both are 400, so a stock SDK still fails the call; the difference is the
error code a caller (or a conformance harness keyed on `Code`) observes.

**Reproduction test sketch:** In-process loopback via
`tests/src/s3_server_harness.adb` with the memory backend: signed
`PUT /test-bucket/k` with body `"bad"`, headers
`x-amz-sdk-checksum-algorithm: SHA256` and
`x-amz-checksum-crc32: <canonical CRC32 of "bad">`. Expected per model:
status 400, `<Code>BadDigest</Code>`. Actual: status 400,
`<Code>InvalidRequest</Code>` (this is exactly what
`s3_server_application_corpus.adb:6428` currently requires).

**Existing coverage:** `tests/src/s3_server_application_corpus.adb:6334-6341`
sends the mismatch and line 6428 asserts `InvalidRequest`, i.e. the suite
pins the divergent code. No test asserts `BadDigest` for this case.

**Refutation attempts:** (a) Checked whether the model might be silent or
ambiguous: the sentence quoted above is specific to PutObject and names
`BadDigest`. (b) Checked whether the UploadPart rule ("ignores") could be
the intended shared rule: the model gives different text for the two
operations, and the server already implements UploadPart's rule
separately, so the PutObject branch is not a shared-policy consequence.
(c) Checked `docs/qualification/put-object.md` for a documented deliberate
deviation: it lists `ChecksumAlgorithm` as "Select one ordinary full-object
algorithm" and does not document an `InvalidRequest` mapping for this
mismatch. (d) Severity: it is a 400 either way and the body is not stored,
so this is diagnostics drift, not an interop break, hence P2.

---

## Areas reviewed with no findings

- `Checksum_CRC.Make_Table`, `Update`, `Finish`: reflected table-driven
  CRC with init and final XOR of all-ones for CRC32 (0xEDB88320), CRC32C
  (0x82F63B78) and CRC64NVME (0x9A6C9329AC4BC9B5, verified as the
  bit-reflection of 0xAD93D23594C93659); the corpus "123456789" vectors
  encode the published check values 0xCBF43926, 0xE3069283 and
  0xAE8B14860A799888.
- `Checksum_CRC.Combine`, `Matrix_Square`, `Matrix_Times`: zlib
  `crc32_combine` generalised to 64 bits; the zero-length operand returns
  `Left xor Right` (correct because the empty-string CRC is 0 for all three
  algorithms and the identity `crc(A||B) = zeros^{|B|}(crc(A)) xor crc(B)`
  holds when init = xorout); lengths use `Byte_Count` (63-bit) with one
  squaring per bit, verified against an independent polynomial combiner up
  to 2^63-1; masks keep 32-bit operands in 32 bits; `Loop_Variant`s are
  correct. The `Check_Large_Logical` expected values are independent of the
  Ada code (reproduced here by a different method), so the corpus does
  catch an error in bits 17..35 of the length; higher bits use the same
  uniform loop.
- `Checksums.Encode_Base64` / `Decode_Base64` / `Wire_Core.Valid_Base64`:
  exact encoded length per algorithm (CRC32/CRC32C 8, CRC64NVME/XXH64/XXH3
  12, MD5/XXH128 24, SHA1 28, SHA256 44, SHA512 88), standard alphabet only,
  required `=` padding, zero unused pad bits (`A|Q|g|w` for 1 trailing byte,
  the sixteen multiples-of-4 for 2), no whitespace; decode loop traced for
  4, 8, 16, 20, 32 and 64 byte digests.
- `Checksums.Composite`: hashes concatenated raw big-endian part digests
  in the order supplied; callers supply manifest order, which
  `Complete_Multipart_Upload` requires to be strictly ascending (and
  consecutive from 1 for composites), so parts are ordered by part number.
  Matches the AWS SHA256 tutorial vector in the corpus and the
  checksum-of-checksums rule used by CRT and MinIO for CRC types.
- `Checksums.Full_Object` / `To_CRC` / `From_CRC`: left-fold of `Combine`
  with each right part's stored `Info.Size`; first part length unused
  (correct); zero-length last part is a no-op.
- `Encode_Object` / `Decode_Object`: composite gets exact `-<N>` suffix
  including `-1` for a single part; full-object has none; decode requires
  exact suffix and rejects wrong part counts (tested).
- `Checksum_Policy`: multipart matrix (CRC64NVME full-object only; digests
  and xxHash composite only; CRC32/CRC32C both), `Default_Type`,
  `Ordinary_Object_Supported`; CreateMultipartUpload admission at
  `s3_applications.adb:12047-12100` enforces it and defaults omitted
  selection to CRC64NVME/FULL_OBJECT.
- `Checksum_Engine`: `Valid_Configuration`, `Valid_Direct_Configuration`,
  `Valid_Digest`, `Valid_Object_Digest`, `Matches_Stored_Object_Digest`
  (header value is raw Base64, stored composite carries suffix, part count
  = manifest length), `Multipart_Object_Value` (consistency checks before
  the preconditioned calls). The multipart-only `Policy.Supported` gate in
  `Valid_Object_Digest` is reached only for objects with completed parts
  (`files.adb:2707-2716`, `catalogs.adb:508-522`), never for direct-put
  SHA/MD5/xxHash full-object digests.
- `Checksums.Context` state machine: `Initialize` resets; `Finish` is
  non-destructive for every algorithm (CRC pure, GNAT digests take a copy,
  xxHash digest takes a const state); `Update` after `Finish`, `Reset`,
  empty slices (Null_Address, length 0 accepted by xxHash) and arbitrary
  chunk boundaries (210 combinations in the corpus) are correct; no
  per-context byte counter exists to overflow, and part lengths are
  `Byte_Count`.
- xxHash bridge: vendored header is v0.8.3 as claimed (`XXH_VERSION_*`
  548-550); `sizeof(struct)` 640 <= 1024 and `_Alignof` 64 <= 64 checked at
  every reset; `XXH3_128bits_reset` is literally `XXH3_64bits_reset`
  (7046-7048) so sharing the reset is correct; `size_t` lengths, NULL only
  with length 0, output sizes checked; XXH64/XXH3 canonical is big-endian,
  XXH128 canonical is big-endian high64 then low64 (7127-7136), matching
  the `xxhsum -H1/-H3/-H2` oracles used by the corpus generator.
- Server trailer path (`Request_Source.Read`, PutObject 14806-14830,
  UploadPart 12540-12580, `Verify_Document_Checksum`): `x-amz-trailer` must
  name exactly the SDK algorithm's header (case-folded), a value header and
  a trailer cannot be combined, trailer access happens only after
  `Finished` (which the HTTP crate sets from `Body_Done`, i.e. after the
  trailer block is parsed), the trailer value is canonical-validated and
  compared to the streamed digest, and the response echoes the
  backend-computed value plus `x-amz-checksum-type` via
  `Set_Checksum_Headers`.
- Stored/returned checksum for multipart objects: backends store the
  object-level value (composite `base64-N`, full-object bare) with the
  initiation method; GetObject/HeadObject emit it only with
  `x-amz-checksum-mode: ENABLED` together with `x-amz-checksum-type`;
  `partNumber` requests emit the part's bare value; GetObjectAttributes and
  CompleteMultipartUpload carry `ChecksumType` from the same record
  (corpus 3700-3850, 4060-4150 assert this end to end).
- Client `Hash_File` / `Complete_Parameters`: per-part and whole-object
  contexts fed from the same buffer; composite computed from the local part
  digests with the `-N` suffix for the completion result and the raw value
  for the completion header; part-count plan validated by
  `Core.Valid_Multipart_Plan` before the 10,000 cap can matter.

## Observations not counted

- Composite completion header form: the server requires the raw Base64
  (no `-N`) in `x-amz-checksum-<alg>` on CompleteMultipartUpload
  (`Matches_Stored_Object_Digest` decodes `Expected_Raw` with
  `Decode_Base64`), and the typed client strips the suffix
  (`transfers.adb:901-913`). The pinned model has no `httpChecksum` trait on
  CompleteMultipartUpload, so botocore never adds this header itself; what
  the CRT/aws-cli send for COMPOSITE completions is unverified here. The
  implementation corpus sends the raw form to RustFS/SeaweedFS/MinIO
  (`s3_implementation_corpus.adb:543-555`). Checkable with aws-cli
  `--checksum-algorithm SHA256` against the loopback server.
- XXHASH128 byte order: no AWS-published vector exists in the repository;
  the implementation follows xxHash's canonical big-endian (high64, low64)
  form. Whether AWS uses the same order is from memory, unverified.
- The C bridge checks `_Alignof <= 64` but not that the actual storage
  address is 64-byte aligned; correctness relies on GNAT honouring
  `Alignment => 64` on `XXH_Storage` for stack objects (all current
  contexts are stack-allocated). Low-confidence, no evidence of a failure.
- UploadPart echoes the backend-computed `x-amz-checksum-<alg>` even when
  the client sent no part checksum (`s3_applications.adb:12717-12721`); the
  model says the header is present only when provided. Extra header is
  harmless to stock clients.
- Trailer-borne checksums are reachable only with plain HTTP/1.1 chunked
  trailers because `aws-chunked` is answered `501 NotImplemented`
  (PutObject 14882-14886, UploadPart 12618-12622); stock SDK trailing
  checksums use `aws-chunked`. Documented capability boundary in
  `docs/qualification/put-object.md` and `complete-multipart-upload.md`.
- Ranged GetObject on a full-object-CRC object returns the full-object
  checksum header with the 206; composite values are suppressed on ranges
  (`Suppress_Composite_Checksum`). AWS behaviour for ranged responses is
  from memory, unverified; stock SDKs skip validation on 206.
- `Request_Source.Read` rejects any request whose trailer block contains
  more than the one declared checksum trailer (`Request_Trailer_Count (X)
  /= 1`); strictness choice, not a protocol rule in the model.
- CompleteMultipartUpload accepts and validates an `x-amz-checksum-algorithm`
  request header that the pinned model does not define for that operation
  (`s3_applications.adb:13048-13060`); lenient extension.
- Policy values (not defects): CRC64NVME/FULL_OBJECT default for PutObject
  and CreateMultipartUpload without a selection; 5 GiB PutObject and
  `Maximum_Multipart_Part_Size` caps; 10,000-entry caps in `Hash_File`;
  `Maximum_Checksum_Length = 96` in the files manifest (covers `<88-char
  SHA512>-10000`).
- Not reviewed: the HTTP crate's chunked-trailer parser itself
  (`flyology_http`, outside this repository; only the accessor contract and
  `Finished`/`Body_Done` coupling were read); SQLite schema handling beyond
  the `Multipart_Object_Value` call site and `Checksum_From_Columns`.
