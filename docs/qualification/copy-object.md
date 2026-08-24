# CopyObject qualification scope

The authoritative inventory is botocore S3 revision
`36c34f15391da01cd717c73c0fffa747c9889768`, service-model SHA-256
`429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
Its `CopyObjectRequest` has 44 members. `CopyObjectOutput` has 11 top-level
members, one of which is the 13-member `CopyObjectResult`, for 24 modeled
output positions in the qualification inventory. The table below is the
audited disposition supporting the covered client ledger entry and the
server's explicit path-style capability profile. An omitted value
is not the same as silently ignoring a supplied value.

Disposition meanings:

- **Persist** means the value affects the immutable source snapshot or the
  atomic destination publication and survives backend reopen where applicable.
- **Validate/no-op** means the value is parsed and checked, but the backend's
  deliberately narrower single-owner or unversioned model makes the accepted
  value have no additional state to store.
- **Authenticated NotImplemented** means a supplied value is rejected only
  after route sealing and authentication. It is never ignored.
- **Persist** for a checksum means recomputing a full-object digest over the
  copied bytes and publishing it in the same body/metadata/tag tuple. A
  multipart composite checksum is never transplanted onto the ordinary
  destination object.

## Request members (44)

| # | Pinned member / wire location | Required disposition |
|---:|---|---|
| 1 | `ACL` / `x-amz-acl` | Validate/no-op for `private`; authenticated NotImplemented for every other modeled ACL. |
| 2 | `Bucket` / destination host or path | Persist as the destination namespace. |
| 3 | `CacheControl` / `Cache-Control` | Persist on `REPLACE`; copy on `COPY`. |
| 4 | `ChecksumAlgorithm` / `x-amz-checksum-algorithm` | Persist; validate all ten pinned algorithms and compute the selected destination full-object checksum. If absent, inherit the source algorithm or use CRC64NVME. |
| 5 | `ContentDisposition` / `Content-Disposition` | Persist on `REPLACE`; copy on `COPY`. |
| 6 | `ContentEncoding` / `Content-Encoding` | Persist on `REPLACE`; copy on `COPY`. |
| 7 | `ContentLanguage` / `Content-Language` | Persist on `REPLACE`; copy on `COPY`. |
| 8 | `ContentType` / `Content-Type` | Persist on `REPLACE`; copy on `COPY`; default replacement is `application/octet-stream`. |
| 9 | `CopySource` / `x-amz-copy-source` | Parse strictly, including one optional bounded `versionId`, and select that immutable current, null, or exact source snapshot. Memory and SQLite support retained exact versions; files supports current and null and rejects opaque exact IDs. |
| 10 | `CopySourceIfMatch` / `x-amz-copy-source-if-match` | Evaluate strongly against that source snapshot. |
| 11 | `CopySourceIfModifiedSince` / `x-amz-copy-source-if-modified-since` | Parse all recipient HTTP dates and evaluate against that source snapshot. |
| 12 | `CopySourceIfNoneMatch` / `x-amz-copy-source-if-none-match` | Evaluate weakly against that source snapshot; failure is 412. |
| 13 | `CopySourceIfUnmodifiedSince` / `x-amz-copy-source-if-unmodified-since` | Parse all recipient HTTP dates and evaluate with S3 ETag precedence. |
| 14 | `Expires` / `Expires` | Persist on `REPLACE`; copy on `COPY`. |
| 15 | `GrantFullControl` / `x-amz-grant-full-control` | Authenticated NotImplemented when supplied. |
| 16 | `GrantRead` / `x-amz-grant-read` | Authenticated NotImplemented when supplied. |
| 17 | `GrantReadACP` / `x-amz-grant-read-acp` | Authenticated NotImplemented when supplied. |
| 18 | `GrantWriteACP` / `x-amz-grant-write-acp` | Authenticated NotImplemented when supplied. |
| 19 | `IfMatch` / `If-Match` | Persist as an atomic destination publication predicate. |
| 20 | `IfNoneMatch` / `If-None-Match` | Persist as an atomic destination publication predicate. |
| 21 | `Key` / destination path | Persist as the destination key. |
| 22 | `Metadata` / `x-amz-meta-*` map | Bounded unique map; persist on `REPLACE`; copy on `COPY`. |
| 23 | `MetadataDirective` / `x-amz-metadata-directive` | Strict `COPY` or `REPLACE`; controls all modeled system and user metadata. |
| 24 | `TaggingDirective` / `x-amz-tagging-directive` | Strict `COPY` or `REPLACE`; publish the resulting tag set atomically with the destination object. |
| 25 | `AnnotationDirective` / `x-amz-object-annotation-directive` | Validate/no-op for `COPY` or `EXCLUDE` while the backend cannot contain annotations. |
| 26 | `ServerSideEncryption` / `x-amz-server-side-encryption` | Authenticated NotImplemented when supplied. |
| 27 | `StorageClass` / `x-amz-storage-class` | Validate/no-op for `STANDARD`; authenticated NotImplemented for other modeled classes. |
| 28 | `WebsiteRedirectLocation` / `x-amz-website-redirect-location` | Persist only when explicitly supplied; never inherited merely by `COPY`. |
| 29 | `SSECustomerAlgorithm` / destination SSE-C algorithm | Authenticated NotImplemented when supplied. |
| 30 | `SSECustomerKey` / destination SSE-C key | Authenticated NotImplemented when supplied; never retain or log. |
| 31 | `SSECustomerKeyMD5` / destination SSE-C key digest | Authenticated NotImplemented when supplied. |
| 32 | `SSEKMSKeyId` / KMS key ID | Authenticated NotImplemented when supplied. |
| 33 | `SSEKMSEncryptionContext` / KMS context | Authenticated NotImplemented when supplied; never retain or log. |
| 34 | `BucketKeyEnabled` / S3 bucket-key flag | Authenticated NotImplemented when supplied. |
| 35 | `CopySourceSSECustomerAlgorithm` / source SSE-C algorithm | Authenticated NotImplemented when supplied. |
| 36 | `CopySourceSSECustomerKey` / source SSE-C key | Authenticated NotImplemented when supplied; never retain or log. |
| 37 | `CopySourceSSECustomerKeyMD5` / source SSE-C key digest | Authenticated NotImplemented when supplied. |
| 38 | `RequestPayer` / `x-amz-request-payer` | Strictly validate `requester`, then authenticated NotImplemented because Requester Pays is not modeled. |
| 39 | `Tagging` / `x-amz-tagging` | Strict bounded query-tag parser; accepted only with replacement semantics and atomically persisted. |
| 40 | `ObjectLockMode` / object-lock mode | Authenticated NotImplemented when supplied. |
| 41 | `ObjectLockRetainUntilDate` / retention timestamp | Authenticated NotImplemented when supplied. |
| 42 | `ObjectLockLegalHoldStatus` / legal-hold state | Authenticated NotImplemented when supplied. |
| 43 | `ExpectedBucketOwner` / destination owner | Validate exactly against the authenticated destination owner; mismatch is 403. |
| 44 | `ExpectedSourceBucketOwner` / `x-amz-source-expected-bucket-owner` | Validate exactly against the authenticated source owner; mismatch is 403. |

`Expires` uses the S3 SDK's canonical IMF-fixdate wire representation, not a
generic HTTP-date recipient parser. The backend stores a signed typed instant
covering canonical years 0001 through 9999. A written leap second is accepted
and normalized after validating the written weekday; the terminal
`Fri, 31 Dec 9999 23:59:60 GMT` is rejected because its normalized instant
cannot be rendered in the four-digit domain. Source conditional-date headers
remain HTTP recipients and accept the three RFC 9110 date forms.

When `MetadataDirective` is absent or `COPY`, supplying a replacement cache,
content, Expires, or user-metadata field is an `InvalidRequest`; no supplied
member is silently discarded. Website redirect is the AWS-specific exception:
it is applied only when explicitly supplied and is never inherited by `COPY`.
Likewise, `x-amz-tagging` is accepted only with `TaggingDirective=REPLACE`.

## Output positions (24)

| # | Pinned output position | Required disposition |
|---:|---|---|
| 1 | `CopyObjectResult` body | Return only after complete atomic publication; a 200 `Error` body remains a typed rejection. |
| 2 | `Expiration` header | Omit: lifecycle expiration is not modeled. |
| 3 | `CopySourceVersionId` header | Emit from the same immutable source snapshot when its identity is authoritative: exact opaque IDs for enabled memory/SQLite generations and `null` for null generations. Omit for an unconfigured current source. |
| 4 | `VersionId` header | Emit from the same destination publication: exact opaque IDs for enabled memory/SQLite destinations and `null` for suspended memory/files/SQLite destinations. Omit for an unconfigured destination. Files rejects enabled publication before rename. |
| 5 | `ServerSideEncryption` header | Omit because encryption requests are rejected. |
| 6 | `SSECustomerAlgorithm` header | Omit because SSE-C requests are rejected. |
| 7 | `SSECustomerKeyMD5` header | Omit because SSE-C requests are rejected. |
| 8 | `SSEKMSKeyId` header | Omit because KMS requests are rejected. |
| 9 | `SSEKMSEncryptionContext` header | Omit because KMS requests are rejected. |
| 10 | `BucketKeyEnabled` header | Omit because bucket-key requests are rejected. |
| 11 | `RequestCharged` header | Omit because Requester Pays requests are rejected. |
| 12 | result `ETag` | Emit the quoted destination entity tag. |
| 13 | result `LastModified` | Emit the destination publication timestamp in S3 timestamp form. |
| 14 | result `ChecksumType` | Emit `FULL_OBJECT` for the ordinary copied destination. |
| 15 | result `ChecksumCRC32` | Emit only when selected or inherited. |
| 16 | result `ChecksumCRC32C` | Emit only when selected or inherited. |
| 17 | result `ChecksumCRC64NVME` | Emit only when selected, inherited, or defaulted. |
| 18 | result `ChecksumSHA1` | Emit only when selected or inherited. |
| 19 | result `ChecksumSHA256` | Emit only when selected or inherited. |
| 20 | result `ChecksumSHA512` | Emit only when selected or inherited. |
| 21 | result `ChecksumMD5` | Emit only when selected or inherited. |
| 22 | result `ChecksumXXHASH64` | Emit only when selected or inherited. |
| 23 | result `ChecksumXXHASH3` | Emit only when selected or inherited. |
| 24 | result `ChecksumXXHASH128` | Emit only when selected or inherited. |

## Snapshot and size boundary

Memory copies its protected, capacity-accounted source snapshot. The SQLite
backend opens the immutable external payload while the catalog operation gate
still protects the row-to-payload association; later publication uses a new
payload name, and retirement is best-effort until no Windows reader owns the
old file. The pure-files backend creates a private body snapshot while holding
its publication gate, closes the source path, then releases the gate before
destination publication. This avoids relying on POSIX unlink semantics and
allows overwrite, delete, and same-key races on Windows.

The backend primitive returns success-only source and destination
`Version_Identity` values with the copied metadata. Their omitted, opaque, and
null states are derived inside the protected, locked, or transactional source
selection and destination publication boundaries. The server therefore emits
both version headers without a racy follow-up HEAD. Every failure clears both
identities; an ambiguous post-publication backend failure remains a failure
and does not expose a success identity.

`Maximum_Copy_Object_Size` is exactly `5 * 1_024 * 1_024 * 1_024` bytes. The
pure boundary predicate accepts that value and rejects the following byte, so
the off-by-one policy is tested without allocating a 5 GiB body.

## Publication certainty

`Success` confirms that the complete body, information, metadata, tags, and
checksum tuple was published. A synchronous `Backend_Unavailable`, transport
failure, timeout, or cancellation is not evidence of nonpublication once the
destination publication boundary may have been crossed. In particular, the
pure-files backend can rename the complete temporary object successfully and
then fail a directory synchronization or cleanup step. Callers that require
certainty must reconcile by an exact generation-bound read; they must not
blindly replay a conditional mutation. Preflight validation and failed source
or destination predicates remain conclusively before publication.

## Pure-files serialization cost

The portable snapshot strategy is deliberately not a zero-copy path. For each
body byte, CopyObject reads the published source, writes the private snapshot,
reads the snapshot, and writes the destination temporary object before atomic
publication. It also holds the global publication gate during the first read
and snapshot write. This four-stream I/O amplification and serialization are
the correctness cost of allowing same-key copy and concurrent source
overwrite/delete without relying on POSIX open-unlink behavior.

`benchmarks/run-files-copy.sh [MiB] [copies]` is the bounded, repeatable direct
backend smoke benchmark. It uses `Process_Crash_Atomic` so filesystem sync
latency does not obscure the copy-path cost; it reports logical object MiB/s,
not physical device traffic. An unqualified Apple arm64 smoke run on
2026-08-22 used four 64 MiB copies and reported 282.74 logical MiB/s
(0.905429 seconds). This is developer evidence, not a portable threshold or a
power-loss-durable result. The cross-implementation S3 benchmark remains the
release performance oracle once the full wire feature disposition is closed.

The pinned SeaweedFS 4.43 image at revision
`6c7f184381e3c4f7908934f4c1d8cb7dcca41894` publishes the copy but emits a
bare `ETag` value in `CopyObjectResult`. Its generated response type serializes
that value without adding quotes. The matrix therefore requires both typed
client layers to reject the response as invalid while independently checking
the published destination bytes. This is a narrow oracle profile; the
production decoder continues to require one strong quoted entity-tag.

## Functional evidence

The final functional campaign on 2026-08-22 used the clean CopyObject stack
rebased onto `03ee379ae1069b595922fd875288d4508eb3a26a`:

- `./tests/scripts/test.sh` passed. It included 34/34 AUnit cases, all 88
  abrupt-crash cases, shared memory/files CopyObject conformance, namespace
  symlink probes, the 320-vector checksum corpus, authenticated application
  corpus, and three native/lightweight socket repetitions.
- `./sqlite/tests/scripts/test.sh` passed the vendored SQLite wrapper, exact
  schema and migration audit, external-payload catalog, reopen, and backend
  conformance gate.
- `./tests/scripts/test-s3-matrix.sh` passed all 18 lanes: three repetitions
  each for pinned RustFS, pinned SeaweedFS, supplemental MinIO, and Flyology
  memory, files, and SQLite. Every lane used native and lightweight typed
  clients plus the digest-pinned s5cmd byte and deletion oracle.

The SeaweedFS profile does not relax production parsing. After its expected
strict `Invalid_Response`, the corpus downloads and byte-compares both typed
CopyObject destinations. DeleteObjects setup copies are independently checked
before deletion, and both destinations must independently return `HEAD 404`
afterward.
