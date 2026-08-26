# PutObjectLockConfiguration qualification

## Scope

This qualification covers the backend-independent provider-owned composable
and synchronous `PutObjectLockConfiguration` client contract. It makes no
backend, server, or external-provider interoperability claim.

The locked botocore S3 graph at revision
`36c34f15391da01cd717c73c0fffa747c9889768` defines exact
`PUT /{Bucket}?object-lock`, input shape 552, output shape 551, status 200,
required checksum support, and `ChecksumAlgorithm` as the selector. The
reciprocal inventory covers seven request members, six nested members, and the
sole `RequestCharged` response member.

## Request contract

The XML codec preserves absence independently for the outer configuration,
`ObjectLockEnabled`, `Rule`, `DefaultRetention`, `Mode`, `Days`, and `Years`.
It emits the exact S3 namespace and model order. It does not infer a
relationship among mode, days, and years. The sole enabled token is exact
`Enabled`; modes are exact `GOVERNANCE` and `COMPLIANCE`.

The pinned Days and Years shapes have no numeric bounds. They therefore remain
validated arbitrary-precision signed decimal text, including signs and leading
zeros, rather than being narrowed to a machine integer or canonicalized.
Serialization is incremental under caller-selected document, depth, element,
and aggregate text limits. Inconsistent nested presence and malformed decimal
text reject before HTTP admission.

The request owns serialized bytes and executes through a deliberately
non-rewindable source. Bucket, requester payer, Object Lock token, expected
owner, MD5, and checksum algorithm are validated before admission. Content-MD5
is always signed over owned bytes. All ten pinned SDK algorithms emit their
matching digest over the same bytes used for MD5 and the SigV4 payload hash.

## Response and certainty contract

Only exact status 200 with an empty or XML-whitespace-only bounded body is
successful. `x-amz-request-charged`, `x-amz-request-id`, and `x-amz-id-2` are
physical singletons with bounded nonempty values; charged, when present, must
be exact `requester`. Other statuses decode as bounded structured S3 errors.

`Client.Low_Level.Put_Object_Lock_Configuration` starts only an exactly matching
prepared request and retains one source and one bounded response sink.
`Client.Buckets.Put_Object_Lock_Configuration` colocates the limited
constructor, operation-last reusable procedure, operation state, typed
`Finish`, and parameter-record synchronous wait. The parent owns the serialized
body and exposes it once through a non-rewindable source; the synchronous form
waits on that same state machine.

The call is never retried. Typed Finish distinguishes completion, conclusive
non-application, cancellation before admission, and outcome unknown. Every
post-admission transport failure, retryable response, malformed response, or
lost result remains unknown and requires caller-selected read-only
GetObjectLockConfiguration reconciliation before any retry.
The AWS-documented `InvalidBucketState` response is a conclusive client error;
it proves this attempted mutation was not applied.

## Corpus boundary

The deterministic corpus covers every nested presence state; enabled and both
modes; Days-only, Years-only, full graphs, huge positive and negative integers,
signed zero and leading zeros; inconsistent presence and decimal grammar
mutants; exact and one-past XML limits; both addressing styles; every header
control and its exact/one-past bound; automatic and caller MD5; all ten SDK
checksums; exact success, alternate status and structured-error matrices;
response header and diagnostic failures; and cross-operation rejection.

The raw loopback corpus checks exact full XML bytes, SHA-256 payload binding,
MD5, CRC32, token, payer, owner, absent zero-length payload, typed rejection,
non-whitespace success, duplicate and empty singleton headers, duplicate
diagnostics, one-past response size, and a server-accepted request followed by
a lost response. The composable corpus adds limited construction,
operation-last restart, typed synchronous parity, wrong-prepared-operation
rejection before admission, an actual one-past response-sink failure, every
HTTP terminal failure across all admission-certainty values, and inconsistent
success certainty. The root gate runs the sequence under native and lightweight
task owners.

The machine ledger records `missing / covered / missing / covered`: backend and
server support remain absent, while the complete client and independent corpus
are covered.

## Verification

The pinned verifier reports all 14 modeled members, ten exact checksum values,
and 14 reciprocal vectors. The serializer and provider-owned client are outside
the `tools/prove.sh` manifest, so no proof rerun is required for this slice.

Required gates are `./tests/scripts/test.sh`,
`./sqlite/tests/scripts/test.sh`, `./tools/build-api-docs.sh`, and
`git diff --check`. GNATdoc must produce a nonempty API index containing the
serializer and public prepare/decode/execute functions, with no internal error,
Langkit failure, infinite recursion, or bounded-channel diagnostic.

The root gate passed all 41 AUnit cases, the 126-case abrupt-crash matrix, the
320-vector checksum corpus with 210 chunk boundaries, and three complete
deterministic, native/lightweight signed raw-socket, and TLS repetitions. The
SQLite wrapper, catalog, and backend gate also passed.

GNATdoc produced a nonempty API index and a 43,674-line diagnostic log. The
serializer, prepare/decode/execute APIs, limited operation, all three provider
overloads, and typed Finish are present without new public-declaration
warnings. The log contains no internal error, `LANGKIT_SUPPORT.ERRORS`,
infinite recursion, or Flyology bounded-channel diagnostic.
