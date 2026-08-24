# PutObjectLegalHold client qualification

This record qualifies the bounded synchronous one-shot client and corpus for
`PutObjectLegalHold`. It does not claim legal-hold persistence in a Flyology
backend, an authenticated Flyology server route, or external provider
interoperability.

## Pinned authority and inventory

The machine inventory is tied to botocore S3 model revision
`36c34f15391da01cd717c73c0fffa747c9889768` and service-model SHA-256
`429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
The operation is exact PUT to `/{Bucket}/{Key+}?legal-hold`, has exact success
status 200, input shape 550, output shape 549, requires request checksum
admission, and names `ChecksumAlgorithm` as its algorithm member.

The input graph contains required `Bucket` and `Key`, plus optional
`LegalHold`, `RequestPayer`, `VersionId`, `ContentMD5`, `ChecksumAlgorithm`,
and `ExpectedBucketOwner`. LegalHold shape 476 has one optional `Status`
member with exact values `ON` and `OFF`. The output contains optional exact
`RequestCharged`, whose sole value is `requester`; the request-payer enum has
the same sole value. The checksum algorithm has all ten pinned SDK values.

The reciprocal ledgers contain all ten members and 13 request, codec,
checksum, response, and transport contracts. The verifier gates operation
scalars, checksum metadata, the complete input/nested/output graphs and wire
locations, enum values, implementation ownership/replay markers, and
reciprocal vector reachability:

```sh
python3 tools/verify-put-object-legal-hold-preparation.py
```

## Bounded presence-preserving codec

`S3.Object_Lock.Serialize_Legal_Hold` preserves outer and nested model
presence. An absent outer member produces the model-permitted empty payload;
a present outer member produces the exact S3-namespaced `LegalHold` root and
optionally an exact `Status`. It does not invent a default hold state.

For a present value, caller-selected limits bound the document before every
append, the one- or two-element graph, the one- or two-level depth, and the
zero-, two-, or three-byte enum text. Inconsistent absent-outer/present-status
input fails before signing. Exact and one-past document, depth, element, and
text limits are independently gated.

## Synchronous checksum and ownership contract

`Prepare_Put_Object_Legal_Hold` validates the bucket, nonempty greedy key,
requester enum, physical owner header, MD5 override, checksum algorithm, and
XML limits before transport. It signs exact path or virtual-hosted targets and
an optional opaque version selector.

The serialized payload is copied into private prepared-request storage. The
request message does not retain a second replayable body. Execution copies the
owned bytes into a local `Request_Body_Source` whose non-rewindable class is
the Flyology.HTTP replay authority; no caller borrow, detached helper task,
second protocol engine, or automatic retry exists.

Because the pinned operation requires checksum admission, omission of a
Content-MD5 override computes exact MD5 over the owned serialized bytes,
including the absent empty payload. A caller override must be canonical base64
for exactly 16 bytes. An optional SDK algorithm must be one of all ten pinned
values and adds both the exact algorithm header and matching digest over the
same bytes used by MD5 and the SigV4 payload hash.

`Execute_Put_Object_Legal_Hold` accepts only a request prepared for the exact
operation. Exact 200 with an empty or XML-whitespace body is update success;
non-whitespace success content fails closed. Every other status returns a
strict bounded S3 error. Modeled and diagnostic headers must each be absent or
one bounded nonempty physical value, and requester-charged must match its exact
enum.

Any exception after entry into the blocking provider call leaves publication
unknown. Callers must reconcile through a read-only generation-bound
`GetObjectLegalHold` and must not automatically retry the mutation.

## Corpus and coverage boundary

The deterministic corpus covers absent outer payload, present empty root, ON
and OFF, inconsistent presence, exact XML, exact and one-past codec limits,
both addressing styles, greedy key and version encoding, every physical
control, automatic and caller MD5, all ten SDK checksums, invalid buckets,
keys, version and owner controls, enums, digests and algorithms, exact success
semantics, alternate status and error matrices, response headers, diagnostics,
error limits, and cross-operation rejection before admission.

The shared raw loopback corpus adds exact signed PUT method, target, body hash,
MD5, CRC32, version, payer, and owner projection; the absent zero-length source
with the exact empty-payload MD5; typed success and structured rejection;
non-whitespace success; duplicate and empty modeled headers;
duplicate diagnostics; a response one byte above the caller limit; and a
server-accepted request followed by a lost response. The next server oracle
proves that no automatic replay occurs. The root gate drives the sequence under
native and Flyology lightweight task owners.

The machine ledger records the operation as `missing / covered / missing /
covered`. Client and corpus qualification do not manufacture backend state or
a server route; those require separate persistence, routing, and independent
black-box evidence.

## Formal boundary

This slice changes only non-SPARK client, Object Lock codec, corpus, and
documentation units. None of the nine `tools/prove.sh` manifest units changes,
so the latest serialized 2026-08-24 result remains applicable: 936/936 checks,
180 flow and 756 prover, with zero warnings, unproved or justified checks, or
`pragma Assume` statements.

## Gate evidence

The root gate passed all 40 AUnit cases, the 88-case abrupt-crash matrix, the
320-vector checksum corpus with 210 chunk boundaries, and three complete
deterministic, native/lightweight signed raw-socket, and TLS repetitions. The
SQLite wrapper, catalog, and backend gate also passed.

The pinned verifier reported all ten modeled members, all ten exact checksum
values, and all 13 reciprocal vectors. The 116-operation coverage verifier and
its negative mutation oracle were green.

GNATdoc produced a nonempty API index and a 12,461-line diagnostic log. The
index contains the serializer, parameter, result, outcome, prepare, decode, and
execute declarations; those declarations emitted no targeted warning, and the
log contains no internal error, `LANGKIT_SUPPORT.ERRORS`, infinite-recursion,
or bounded-channel diagnostic.
