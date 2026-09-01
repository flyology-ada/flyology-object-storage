# PutObjectRetention qualification

## Scope

This record covers the provider-owned composable and synchronous
`PutObjectRetention` client contract. Shared Flyology memory, files, SQLite,
and authenticated server evidence is recorded in `object-lock-server.md`; it
makes no external-provider interoperability claim.

The source model is the locked botocore S3 service graph at revision
`36c34f15391da01cd717c73c0fffa747c9889768`, whose recorded service-model
SHA-256 is `429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
The request is exact `PUT /{Bucket}/{Key+}?retention`, input shape 556,
output shape 555, exact success status 200, required checksum support, and
`ChecksumAlgorithm` as its algorithm selector.

The reciprocal inventory covers all nine request members (`Bucket`, `Key`,
`Retention`, `RequestPayer`, `VersionId`, `BypassGovernanceRetention`,
`ContentMD5`, `ChecksumAlgorithm`, and `ExpectedBucketOwner`), both nested
retention members (`Mode` and `RetainUntilDate`), and the sole response member
(`RequestCharged`).

## Request contract

`Retention` preserves independent outer and nested presence. An absent outer
member produces the model-permitted empty payload. A present value emits the
exact S3 namespace and `Retention` root, followed in pinned model order by an
optional `Mode` and optional `RetainUntilDate`. No mode or date is invented.
The only modes are exact `GOVERNANCE` and `COMPLIANCE`; dates must satisfy the
pinned ISO-8601 grammar, including calendar validity, fractional precision,
and zone bounds.

Serialization is incremental and bounded by caller-selected document, depth,
element, and aggregate text limits. Exact and one-past boundaries are tested
for the full three-element graph. Inconsistent absent-outer values and invalid
dates reject before HTTP admission.

The prepared request owns a copy of the serialized bytes. The provider-owned
limited parent implements the non-rewindable request source directly, reports
its exact known length, owns the bounded response sink, and never retains
caller input. Its limited constructor, same-name operation-last procedure, and
typed `Finish` expose composition from `Client.Objects`; the parameter-record
synchronous overload waits on that same state machine. The established
low-level blocking form uses the same prepared wire contract. Bucket, key,
version, payer, owner, and the explicit governance bypass are validated before
admission. The bypass preserves absent, explicit `true`, and explicit `false`;
only a present control is signed.

The client always signs `Content-MD5` over the owned bytes. A caller override
must be canonical base64 for exactly 16 digest bytes. Every exact pinned SDK
checksum algorithm is admitted (`CRC32`, `CRC32C`, `SHA1`, `SHA256`,
`CRC64NVME`, `SHA512`, `MD5`, `XXHASH64`, `XXHASH3`, and `XXHASH128`) and emits
its matching digest header over the same bytes used by MD5 and the SigV4
payload hash.

## Response and certainty contract

Only exact status 200 with an empty or XML-whitespace-only bounded body is
successful. `x-amz-request-charged`, `x-amz-request-id`, and `x-amz-id-2`
must each be absent or one bounded, nonempty physical header. The modeled
charged value, when present, must be exact `requester`. Every non-200 response
is decoded as a bounded structured S3 error with exact status and diagnostics.

The mutation is deliberately not retried. Typed Finish distinguishes modeled
completion, exact non-application, cancellation before admission, and an
outcome that remains unknown after possible admission. A caller that needs
certainty must reconcile with generation-bound GetObjectRetention before
selecting any retry; neither the composable nor synchronous form replays the
retention mutation automatically.

## Corpus boundary

The deterministic corpus covers outer and nested absence, empty root, each
member alone, both exact modes, valid leap-day/fraction/zone dates, invalid
calendar/time/fraction/zone variants, exact XML, exact and one-past codec
limits, both addressing styles, greedy key and version encoding, all physical
controls, tri-state governance bypass, automatic and caller MD5, all ten SDK
checksums, exact key/version/owner bounds, malformed inputs, exact success,
alternate status and error matrices, response headers and diagnostics, error
limits, and cross-operation rejection before admission.

The raw loopback corpus adds exact signed PUT method, target, body hash, MD5,
CRC32, payer, version, owner, and governance `true`/`false` projection; the
absent zero-length source with exact empty-payload MD5; typed success and
structured rejection; non-whitespace success; duplicate and empty modeled
headers; duplicate diagnostics; a response one byte above the caller limit;
exact prepared-operation rejection before admission; limited construction,
operation-last restart, typed Finish, synchronous parity, and an actual
one-past composable sink failure; plus a server-accepted request followed by a
lost response. The next server oracle proves that no automatic replay occurs.
The direct normalization oracle crosses every terminal HTTP failure with every
admission certainty. The root gate drives this sequence under native and
Flyology lightweight task owners.

The machine ledger records the operation as `covered / covered / covered /
covered`. This client record remains operation-specific; the shared Object
Lock record owns backend persistence, authenticated routing, and black-box
server evidence.

## Verification

The pinned verifier reports all twelve modeled members, all ten exact checksum
values, and fourteen reciprocal contract vectors. The repository coverage
verifier and its negative mutation oracle gate the client/corpus transition.

The serializer and low-level client are outside the nine units selected by
`tools/prove.sh`, so the latest serialized proof result remains applicable:
936/936 checks, 180 flow and 756 prover, with zero warnings, unproved or
justified checks, or `pragma Assume` statements.

The required gates are:

- `./tests/scripts/test.sh`
- `./sqlite/tests/scripts/test.sh`
- `./tools/build-api-docs.sh`
- `git diff --check`

The root gate passed all 41 AUnit cases, the 126-case abrupt-crash matrix, the
320-vector checksum corpus with 210 chunk boundaries, and three complete
deterministic, native/lightweight signed raw-socket, and TLS repetitions. The
SQLite wrapper, catalog, and backend gate also passed. GNATdoc 26 completed a
43,629-line run with a nonempty 430-file API index containing the new provider
operations and typed result surface, with no warning on the new declarations
or internal documentation error.

GNATdoc produced a nonempty API index and a 12,461-line diagnostic log. The
new serializer and prepare/decode/execute APIs are present in the generated
HTML, and the log contains no internal error, `LANGKIT_SUPPORT.ERRORS`,
infinite recursion, or Flyology bounded-channel diagnostic.

GNATdoc must produce a nonempty API index containing the serializer and all
three public low-level subprograms, with no internal error, Langkit failure,
infinite recursion, or Flyology bounded-channel diagnostic.
