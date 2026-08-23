# PutObject qualification and boundaries

The authoritative inventory is botocore S3 revision
`36c34f15391da01cd717c73c0fffa747c9889768`, service-model SHA-256
`429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
Its `PutObjectRequest` has 46 members and `PutObjectOutput` has 22 members.
The backend, client, and corpus ledger cells are covered. The server remains
partial because it explicitly rejects 17 modeled controls, has no signed
inner `aws-chunked` signature-chain decoder, and intentionally requires the
physical `x-amz-content-sha256` header to appear in SigV4 `SignedHeaders`.

The generated-model inventory test fails closed on member count, order, or
name drift. Its arithmetic partition is a target inventory; independent
backend, authenticated application, raw socket, and six-server tests establish
the behavior described below.

## Request members (46)

| # | Pinned member | Qualified disposition and effect |
|---:|---|---|
| 1 | `ACL` | Authenticated `NotImplemented`. |
| 2 | `Body` | Stream, verify completely, and atomically publish. |
| 3 | `Bucket` | Select the destination namespace. |
| 4 | `CacheControl` | Persist in the immutable metadata tuple. |
| 5 | `ContentDisposition` | Persist in the immutable metadata tuple. |
| 6 | `ContentEncoding` | Persist verbatim for ordinary encodings; `aws-chunked` is authenticated `NotImplemented`. |
| 7 | `ContentLanguage` | Persist in the immutable metadata tuple. |
| 8 | `ContentLength` | Validate the exact streamed byte count and 5 GiB limit. |
| 9 | `ContentMD5` | Verify the exact full body before publication. |
| 10 | `ContentType` | Persist in `Object_Information`. |
| 11 | `ChecksumAlgorithm` | Select one ordinary full-object algorithm. |
| 12 | `ChecksumCRC32` | Verify canonical CRC32 and persist the recomputed digest. |
| 13 | `ChecksumCRC32C` | Verify canonical CRC32C and persist the recomputed digest. |
| 14 | `ChecksumCRC64NVME` | Verify canonical CRC64NVME and persist the recomputed digest. |
| 15 | `ChecksumSHA1` | Verify canonical SHA1 and persist the recomputed digest. |
| 16 | `ChecksumSHA256` | Verify canonical SHA256 and persist the recomputed digest. |
| 17 | `ChecksumSHA512` | Verify canonical SHA512 and persist the recomputed digest. |
| 18 | `ChecksumMD5` | Verify canonical checksum MD5 and persist the recomputed digest. |
| 19 | `ChecksumXXHASH64` | Verify canonical XXHASH64 and persist the recomputed digest. |
| 20 | `ChecksumXXHASH3` | Verify canonical XXHASH3 and persist the recomputed digest. |
| 21 | `ChecksumXXHASH128` | Verify canonical XXHASH128 and persist the recomputed digest. |
| 22 | `Expires` | Parse canonical S3 IMF-fixdate and persist a typed instant. |
| 23 | `IfMatch` | Evaluate atomically at destination publication. |
| 24 | `IfNoneMatch` | Evaluate atomically at destination publication. |
| 25 | `GrantFullControl` | Authenticated `NotImplemented`. |
| 26 | `GrantRead` | Authenticated `NotImplemented`. |
| 27 | `GrantReadACP` | Authenticated `NotImplemented`. |
| 28 | `GrantWriteACP` | Authenticated `NotImplemented`. |
| 29 | `Key` | Select the destination key. |
| 30 | `WriteOffsetBytes` | Authenticated `NotImplemented`. |
| 31 | `Metadata` | Persist a bounded, case-fold-unique `x-amz-meta-*` map. |
| 32 | `ServerSideEncryption` | Authenticated `NotImplemented`. |
| 33 | `StorageClass` | `STANDARD` is a validated no-op; every other modeled value is authenticated `NotImplemented`. |
| 34 | `WebsiteRedirectLocation` | Persist in the immutable metadata tuple. |
| 35 | `SSECustomerAlgorithm` | Authenticated `NotImplemented`. |
| 36 | `SSECustomerKey` | Authenticated `NotImplemented`; never retain or log. |
| 37 | `SSECustomerKeyMD5` | Authenticated `NotImplemented`. |
| 38 | `SSEKMSKeyId` | Authenticated `NotImplemented`. |
| 39 | `SSEKMSEncryptionContext` | Authenticated `NotImplemented`; never retain or log. |
| 40 | `BucketKeyEnabled` | Authenticated `NotImplemented`. |
| 41 | `RequestPayer` | Authenticated `NotImplemented`. |
| 42 | `Tagging` | Parse the bounded query form and atomically persist the tag set. |
| 43 | `ObjectLockMode` | Authenticated `NotImplemented`. |
| 44 | `ObjectLockRetainUntilDate` | Authenticated `NotImplemented`. |
| 45 | `ObjectLockLegalHoldStatus` | Authenticated `NotImplemented`. |
| 46 | `ExpectedBucketOwner` | Compare exactly with the authenticated bucket owner before reading the source. |

This partitions into 28 implemented semantic members, one qualified no-op,
and 17 authenticated rejections. A modeled control is never silently ignored.
Those rejection paths are post-authentication and pre-source. Their corpus
requests use wrong payload hashes, so the operation-specific 501 response
rather than a payload-hash mismatch proves that the source was not consumed.

## Output positions (22)

| # | Pinned member | Qualified disposition |
|---:|---|---|
| 1 | `Expiration` | Strictly decode from external servers; the Flyology server omits it. |
| 2 | `ETag` | Require one nonempty strong quoted entity-tag. |
| 3 | `ChecksumCRC32` | Emit/decode only as one canonical full-object digest. |
| 4 | `ChecksumCRC32C` | Emit/decode only as one canonical full-object digest. |
| 5 | `ChecksumCRC64NVME` | Emit/decode only as one canonical full-object digest. |
| 6 | `ChecksumSHA1` | Emit/decode only as one canonical full-object digest. |
| 7 | `ChecksumSHA256` | Emit/decode only as one canonical full-object digest. |
| 8 | `ChecksumSHA512` | Emit/decode only as one canonical full-object digest. |
| 9 | `ChecksumMD5` | Emit/decode only as one canonical full-object digest. |
| 10 | `ChecksumXXHASH64` | Emit/decode only as one canonical full-object digest. |
| 11 | `ChecksumXXHASH3` | Emit/decode only as one canonical full-object digest. |
| 12 | `ChecksumXXHASH128` | Emit/decode only as one canonical full-object digest. |
| 13 | `ChecksumType` | Require `FULL_OBJECT` when a checksum is present; normalize an omitted external type to full-object. |
| 14 | `ServerSideEncryption` | Strict external decode; omitted by the Flyology server. |
| 15 | `VersionId` | Bounded decode; omitted for Flyology's unversioned objects. |
| 16 | `SSECustomerAlgorithm` | Strict external decode and relationship checks; omitted by Flyology. |
| 17 | `SSECustomerKeyMD5` | Canonical Base64 external decode; omitted by Flyology. |
| 18 | `SSEKMSKeyId` | Bounded external decode and relationship checks; omitted by Flyology. |
| 19 | `SSEKMSEncryptionContext` | Canonical Base64 external decode; omitted by Flyology. |
| 20 | `BucketKeyEnabled` | Strict boolean external decode and relationship checks; omitted by Flyology. |
| 21 | `Size` | Require one canonical nonnegative byte count. |
| 22 | `RequestCharged` | Strict external enum decode; omitted by Flyology. |

This partitions into 14 server projection or deliberate-omission contracts and
eight additional external-provider decode positions. Success is exactly an
empty HTTP 200 body. Present-empty, duplicate, malformed, over-bound, or
cross-field-inconsistent headers are `Invalid_Response`, not partial success.

## Atomic publication and direct checksums

Memory publishes under its protected store action. Pure-files writes a private
complete FOSOBJ05 record and renames it under the publication gate. SQLite
publishes the catalog row and immutable external payload association in one
transaction. Every backend commits the body, entity information, system and
user metadata, tags, and checksum as one tuple. A source exception, malformed
validator, failed condition, capacity failure, or checksum mismatch leaves the
prior tuple byte-for-byte and information-for-information unchanged.

Ordinary complete objects accept all ten pinned full-body algorithms. This is
deliberately separate from the multipart algorithm/type predicate. HeadObject
and GetObject accept raw full-object digests for all ten, while composite
values require the multipart suffix and a supported multipart algorithm.
Explicit or inferred composite CRC64NVME is rejected. The conformance suite
derives every digest independently from the payload, checks exact ETag/size/
version/timestamp bounds, races distinct complete tuples, reopens files and
SQLite, and accounts memory and staging-file cleanup.

## Client publication certainty

The low-level and convenience calls borrow a synchronous one-shot source and
never make it rewindable merely because PUT is normally repeatable. Validation
and request preparation occur before admission. Once HTTP can no longer prove
that no request was handed off, timeout, cancellation, transport loss, or an
invalid/missing response is outcome-unknown. The accepted/drop-response socket
gate observes exactly one PUT and then requires an exact generation-bound GET;
there is no transparent replay. Expected S3 rejections remain structured and
typed; programming errors are not accepted as a transport-loss oracle.

## Server compatibility boundaries

Every physical `x-amz-*` request header must occur in SigV4 `SignedHeaders`.
Unique names and physical duplicate occurrences have separate bounded caps;
canonical reconstruction preserves physical value order. The server also
requires `x-amz-content-sha256` itself to be signed. AWS permits that field to
be omitted from `SignedHeaders` because its value is already the canonical
request payload hash, so this is an intentional stricter boundary.

The route accepts ordinary fixed-length and HTTP transfer-chunked bodies. It
fails closed on `Content-Encoding: aws-chunked`: genuine SigV4 streaming needs
an inner chunk-frame and signature-chain decoder, and stripping the token while
hashing encoded framing bytes would be unsafe. The 17 modeled unsupported
controls above are authenticated `NotImplemented`, which is why the server
ledger cell remains partial even though their dispositions are explicit.

HeadObject and GetObject project supported retained metadata from the same
immutable `Object_Information` snapshot as the ETag, checksum, and body.
Response-query overrides replace rather than duplicate stored headers.
HEAD 304 carries validators but no stored representation metadata; 412 and 416
also omit stored encoding, disposition, expiry, redirect, and user metadata.
`x-amz-tagging-count` is omitted because tags are not present in the atomic
read-information snapshot; the server does not invent a racy count.

## External oracle profiles

The matrix pins these immutable images and verifies their reported provenance:

- RustFS 1.0.0-rc.3 revision
  `1aae6803739a5bac67e0d702ac46d43f09fb06dd`, image digest
  `sha256:800cf3f352a0a27e3275ca854a51f0027975d7acc7a0d52089a35bcc9fcbf0b5`;
- SeaweedFS 4.43 revision
  `6c7f184381e3c4f7908934f4c1d8cb7dcca41894`, Apache-2.0 image digest
  `sha256:7bea581f48155c069d3c725e60c386c88210c67cde8bce412344ff6ebea264da`;
- MinIO `RELEASE.2025-09-07T16-13-09Z` revision
  `07c3a429bfed433e49018cb0f78a52145d4bedeb`, image digest
  `sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e`;
- s5cmd 2.3.0 revision `991c9fb`, image digest
  `sha256:2ff939e2ee3c76adcadd78dbfc3e2569b18a3743ed9dcfccb1ec589af7fb9903`.

RustFS and SeaweedFS return the exact requested SHA256 digest on HeadObject and a
generation-bound GetObject but omit the optional `x-amz-checksum-type` header.
The exact pinned oracle profiles permit only that omission. The production
decoder contains no oracle-specific branch: it treats an absent type with one
canonical raw digest as `FULL_OBJECT`, while explicit types and composite
suffixes retain strict relationship checks. Every oracle must still return
exact ETag, size, system/user metadata, tags, checksum, and generation-bound
bytes for the complete-tuple key. The separate digest-pinned s5cmd slice
independently verifies uploaded-object bytes and deletion. MinIO and all
Flyology servers use the strict oracle profile, and unknown profile values fail
closed.

Pinned RustFS also returns a bodyless HTTP 412, without the modeled
`PreconditionFailed` error code, when a generation-bound GetObject uses a stale
`If-Match`. The implementation corpus recognizes only that exact external
capability exclusion and still requires the 412; the production decoder is not
weakened and the Flyology lanes must return the structured modeled error.

## Reproducible functional evidence

The final functional tree is
`4c6ae563b107f8fb023147f0fa908b303c9e78d8` with tree
`61c20dc09cfeafd4616fc64aba26a47c38d705dd`, rebased from authoritative local
main `92e22030127952470b7d64895302cfc8f297094d`.

```text
./tests/scripts/test.sh
./sqlite/tests/scripts/test.sh
./tests/scripts/test-s3-matrix.sh
```

On 2026-08-23 the root gate passed 36/36 AUnit cases, all 88 abrupt-crash
cases, the 320-vector checksum corpus, authenticated application corpus, and
three native/lightweight socket runs. The SQLite gate passed the vendored
wrapper, exact schema/migration audit, external-payload catalog, tuple reopen,
race, and source-failure checks. The default matrix passed all 18 lanes: three
runs each of pinned RustFS, SeaweedFS, MinIO, and Flyology memory, pure-files,
and SQLite, with native and lightweight typed clients plus the independent
digest-pinned s5cmd byte/deletion oracle.

The functional campaign was followed by one clean serialized proof run on
commit `971670bfd4816a7d795f004cf3d907a6edadb8fb`, started at
2026-08-23T07:48:01Z with FSF GNATprove 16.1.0. `./tools/prove.sh` forced all
nine manifest units at level 0 with output headers and warnings as errors. It
proved all 936/936 checks: 180 flow checks and 756 prover checks (45
initialization, 521 run-time, 125 assertions, 94 functional contracts, and 151
termination), with a maximum of 663 prover steps. The report contains zero
warnings, justified or unproved checks, and the proof surface contains zero
Assume, Suppress, False_Positive, or SPARK Off constructs. The exact invocation
and report are retained in `obj/proof/logs/gnatprove-run.txt` and
`obj/proof/gnatprove/gnatprove.out`.
