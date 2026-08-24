# CreateBucketMetadataTableConfiguration client qualification

This record qualifies the strict bounded synchronous client and corpus for
`CreateBucketMetadataTableConfiguration`. It does not claim metadata-table
persistence in a Flyology backend, an authenticated Flyology server route, or
external provider interoperability.

## Pinned authority and inventory

The machine inventory is tied to botocore S3 model revision
`36c34f15391da01cd717c73c0fffa747c9889768` and service-model SHA-256
`429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
Input shape 131 requires `Bucket` and body member
`MetadataTableConfiguration`, and optionally contains `ContentMD5`,
`ChecksumAlgorithm`, and `ExpectedBucketOwner`. The operation is exact POST to
`/{Bucket}?metadataTable`, requires request checksum admission, names
`ChecksumAlgorithm` as its algorithm member, has exact status 200, and has no
modeled success output.

MetadataTableConfiguration shape 426 requires one `S3TablesDestination` shape
629. That destination requires `TableBucketArn` shape 627 and `TableName` shape
631. Both are opaque strings with no modeled minimum or maximum, so a present
empty string is valid and remains distinct from absence. Checksum shape 77
contributes the ten exact supported SDK algorithms.

The reciprocal member and vector ledgers contain all eight named members and
13 request, schema, checksum, limit, response, header, and transport contracts.
The verifier gates operation scalars, checksum metadata, the complete nested
graph, both string constraints, and all ten checksum values:

```sh
python3 tools/verify-create-bucket-metadata-table-configuration-preparation.py
```

## Bounded serialization contract

`S3.Metadata_Tables.Serialize_Create` emits the exact established S3 namespace,
root, required destination, `TableBucketArn`, and `TableName`. It preserves
caller bytes, escapes XML text characters, rejects invalid XML controls, and
does not invent a provider-string ceiling or reject modeled empty strings.

The caller-selected shared XML limits bound the document before every append,
the exact three-level depth, the exact four-element graph, and the sum of the
two decoded text lengths. Exact and one-past document, depth, element, and text
budgets are in the deterministic corpus. Escaping is incremental, so expansion
cannot first allocate an unbounded encoded document outside the caller's
document budget.

## Synchronous API and checksum contract

`Client.Low_Level.Prepare_Create_Bucket_Metadata_Table_Configuration` reuses
the shared bucket-control mutation engine. It validates the bucket and bounded
owner before transport, serializes within caller limits, signs the exact POST
target in path or virtual-hosted form, and binds the immutable serialized bytes
into the payload hash and every digest. Its shared physical controls use
`Bucket_Control_Mutation_Parameters`; the established PUT APIs retain
`Put_Bucket_Control_Parameters` as a compatibility subtype of that same type.

Because the pinned operation requires checksum admission, omission of a
Content-MD5 override computes the exact 16-byte MD5 over the serialized body. A
caller override must be exact base64 for 16 bytes. An optional SDK algorithm
must be one of all ten pinned values and adds both the exact
`x-amz-sdk-checksum-algorithm` value and corresponding digest header over the
same bytes. There is no body replay, retained borrowed input, helper task, or
second protocol engine.

`Execute_Create_Bucket_Metadata_Table_Configuration` accepts only a request
prepared for that exact modeled operation and drives the caller-owned
synchronous Flyology.HTTP client. Exact 200 with an empty or XML-whitespace
body is update success; non-whitespace success content fails closed. Every
other status returns a strict bounded S3 error.

An exception after entering the blocking provider call does not provide typed
admission certainty. Callers must classify publication as unknown, reconcile
read-only through `GetBucketMetadataTableConfiguration`, and must not
automatically retry the mutation.

## Corpus and coverage boundary

The deterministic corpus covers exact XML and escaping, valid empty required
strings, invalid XML controls, exact and one-past serialization limits, both
addressing styles, automatic and caller-supplied MD5, all ten SDK checksum
algorithms, invalid buckets, digests, owners, and algorithms, exact success
body semantics, alternate status and strict error matrices, diagnostic-header
boundaries, and cross-operation execution rejection.

The raw loopback corpus adds exact signed POST method, target, root, automatic
MD5, CRC32, and owner projection; structured rejection; non-whitespace success;
duplicate and empty diagnostics; and a semantically bodyless response one byte
above the caller's response ceiling. The common root gate runs the entire
sequence under native and Flyology lightweight task owners.

The machine ledger records the operation as `missing / covered / missing /
covered`. Client and corpus qualification do not manufacture backend state or
a server route; those require separate persistence, routing, and independent
black-box evidence.

## Formal boundary

This slice changes only non-SPARK client, metadata-table codec, corpus, and
documentation units. None of the nine `tools/prove.sh` manifest units changes,
so the latest serialized 2026-08-24 result remains applicable: 936/936 checks,
180 flow and 756 prover, with zero warnings, unproved or justified checks, or
`pragma Assume` statements.

## Gate evidence

The root test gate passed all 40 AUnit cases, the 88-case crash corpus, the
320-vector checksum corpus with 210 chunk boundaries, and three complete
native/lightweight deterministic, signed raw-socket, and TLS repetitions. The
SQLite wrapper, catalog, and backend gate also passed.

The pinned operation verifier reported all eight modeled members, all ten
checksum values, and all 13 reciprocal vectors. The 116-operation coverage
verifier and its negative oracle were green.

GNATdoc produced a nonempty API index and a 12,461-line diagnostic log. The
index contains the destination type, serializer, and public prepare/execute
declarations; those declarations emitted no targeted warning, and the log
contains no internal error, `LANGKIT_SUPPORT.ERRORS`, infinite-recursion, or
bounded-channel diagnostic.
