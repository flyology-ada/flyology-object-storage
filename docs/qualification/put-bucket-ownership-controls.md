# PutBucketOwnershipControls client qualification

This record qualifies the strict bounded synchronous client and corpus for
`PutBucketOwnershipControls`. It does not claim ownership-control persistence
in a Flyology backend, an authenticated Flyology server route, or external
server interoperability.

## Pinned authority and inventory

The machine inventory is tied to botocore S3 model revision
`36c34f15391da01cd717c73c0fffa747c9889768` and service-model SHA-256
`429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
Input shape 538 requires `Bucket` and body member `OwnershipControls`, and
optionally contains `ContentMD5`, `ExpectedBucketOwner`, and
`ChecksumAlgorithm`. The operation requires request checksum admission and
names ChecksumAlgorithm as its algorithm member. It has exact status 200 and
no modeled success output.

OwnershipControls shape 501 requires flattened Rules list shape 503. Every
list member shape 502 requires one ObjectOwnership shape 485 with exact values
`BucketOwnerPreferred`, `ObjectWriter`, and `BucketOwnerEnforced`. Checksum
shape 77 contributes the ten exact supported SDK algorithms.

The reciprocal member and vector ledgers contain all seven named members and
13 request, schema, checksum, limit, response, header, and transport contracts.
The verifier gates the operation scalars, required checksum metadata, flattened
list/member graph, three ownership values, and ten checksum values:

```sh
python3 tools/verify-put-bucket-ownership-controls-preparation.py
```

## Bounded serialization contract

`S3.Bucket_Controls.Serialize_Ownership_Controls` accepts only a present
configuration with at least one rule. It emits the exact S3 namespace, root,
flattened Rule sequence, required ObjectOwnership member, and enum spelling in
caller order. It introduces no list ceiling from outside the pinned model.

The caller-selected shared XML limits bound the document before each append,
the exact three-level depth, the root-plus-two-elements-per-rule formula, and
the sum of enum text bytes. Absent configuration, empty rules, and exact
one-past document, depth, element, or text limits fail before request creation.
The qualified read-side parser round-trips every emitted value.

## Synchronous API and checksum contract

`Client.Low_Level.Prepare_Put_Bucket_Ownership_Controls` reuses the established
bucket-control PUT engine. It validates the bucket and bounded owner before
transport, serializes within caller limits, signs an exact path-style or
virtual-hosted ownershipControls target, and binds the immutable serialized
bytes into the payload hash and all digests.

Because the pinned operation requires checksum admission, omission of a
Content-MD5 override computes the exact 16-byte MD5 over the serialized body.
A caller override must be exact base64 for 16 bytes. An optional SDK algorithm
must be one of all ten pinned values and adds both the exact
`x-amz-sdk-checksum-algorithm` value and corresponding digest header over the
same bytes. There is no body replay, retained borrowed input, or transformed
post-signing payload.

`Execute_Put_Bucket_Ownership_Controls` accepts only the exact prepared
operation and drives the existing caller-owned synchronous HTTP client. It
consumes one bounded same-response body through the shared engine. Exact 200
with an empty or XML-whitespace body is update success; any non-whitespace
success body is unmodeled and fails closed. Every other status returns a strict
bounded S3 error. There is no retry, helper task, or second protocol engine.

## Corpus and coverage boundary

The deterministic corpus covers absent and empty configurations; all three
ownership values in caller order; exact serialization and parser round trip;
exact/one-past serialization, owner, diagnostic, and error XML limits; both
addressing styles; automatic and caller-supplied MD5; all ten SDK algorithms;
invalid bucket, digest, owner, and algorithm input; success body semantics;
strict errors; and cross-operation execution rejection.

The raw-loopback corpus adds a signed update with automatic MD5, CRC32, and
owner precondition; structured rejection; non-whitespace success content;
duplicate and empty physical diagnostics; and a semantically bodyless response
over the caller limit. The common root gate repeats the full sequence under
native and Flyology lightweight task owners three times.

The machine ledger records `PutBucketOwnershipControls` as `missing / covered /
missing / covered`. Client and corpus qualification does not manufacture
backend state or a server route; those cells require separate persistence,
routing, and independent black-box evidence.

## Formal boundary

This slice changes only non-SPARK client, bucket-control codec, corpus, and
documentation units. None of the nine `tools/prove.sh` manifest units changes,
so the latest serialized 2026-08-24 result remains applicable: 936/936 checks,
180 flow and 756 prover, with zero warnings, unproved or justified checks, or
`pragma Assume` statements.

## Gate evidence

The root test gate passed all 40 AUnit cases, the 88-case crash corpus, the
320-case checksum corpus, the 210-case multipart-checksum corpus, and three
complete native/lightweight deterministic and raw-loopback repetitions. The
SQLite wrapper, catalog, and backend gate also passed.

The pinned operation verifier reported all seven modeled members, the required
flattened list, all 13 ownership/checksum enum values, and all 13 reciprocal
vectors. The 116-operation coverage verifier and its negative oracle were
green.

GNATdoc produced a nonempty API index containing the serializer and public
prepare/execute declarations. Those declarations emitted no targeted warning,
and the log contained no internal error, `LANGKIT_SUPPORT.ERRORS`, infinite-
recursion, or bounded-channel diagnostic.
