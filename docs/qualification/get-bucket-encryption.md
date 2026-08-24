# GetBucketEncryption client qualification

This record qualifies the strict bounded synchronous client and corpus for
`GetBucketEncryption`. It does not claim encryption-configuration persistence
in a Flyology backend, an authenticated Flyology server route, or external
server interoperability.

## Pinned authority and inventory

The machine inventory is tied to botocore S3 model revision
`36c34f15391da01cd717c73c0fffa747c9889768` and service-model SHA-256
`429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
Request shape 232 has required `Bucket` and optional `ExpectedBucketOwner`.
Output shape 231 has the optional configuration shape 648, whose required
flattened Rules list contains shape 649. Rules optionally contain default
encryption shape 647, `BucketKeyEnabled`, and blocked-types shape 45. A present
default requires `SSEAlgorithm` and optionally carries `KMSMasterKeyID`.
Blocked types contain an optional flattened list. The exact enum domains are
`AES256`, `aws:fsx`, `aws:backup`, `aws:kms`, `aws:kms:dsse`, `NONE`, and
`SSE-C`.

The reciprocal member and vector ledgers contain all ten named members and 13
request, response, schema, security, header, limit, and transport contracts.
The verifier also gates both list-member shapes, both flattened flags, and the
two exact enum domains:

```sh
python3 tools/verify-get-bucket-encryption-preparation.py
```

## Synchronous API and response contract

`Client.Low_Level.Prepare_Get_Bucket_Encryption` reuses the strict common
bucket-control projector. It validates the bucket and bounded owner before
transport, signs an empty body, projects only the two modeled inputs, and
supports path and virtual-hosted addressing.

`Execute_Get_Bucket_Encryption` admits only the exact prepared operation and
uses the established synchronous bucket-control HTTP engine to consume one
bounded same-response body. It returns a typed configuration or strict S3
error. There is no retry, helper task, retained borrowed input, or second
protocol engine.

An empty successful body preserves optional outer-payload absence. A present
configuration requires at least one flattened Rule. Every optional structure,
Boolean, string, and blocked-type list retains presence and wire order. The
codec chooses no encryption algorithm, key, bucket-key mode, or blocked-type
policy. Dynamic list and string storage is bounded by caller-selected shared
XML limits because the pinned shapes specify no independent maxima.

The parser rejects missing required lists or algorithms; unknown, duplicate,
misplaced, nested, or attributed fields; altered enum and Boolean spellings;
foreign or mixed namespaces; DTDs, entities, processing instructions,
malformed UTF-8; and caller-limit violations. Diagnostic request and host IDs
must each be absent or one nonempty control-free bounded value.

## Corpus and coverage boundary

The deterministic corpus covers both addressing styles; exact/one-past owner
and diagnostic bounds; outer absence; repeated rules; every algorithm and
blocked type; optional empty strings and Booleans; required-member failures;
strict schemas and namespaces; representative non-200 statuses;
cross-operation rejection; and exact/one-past success and error XML byte,
depth, element, and text limits.

The raw-loopback corpus adds signed nested success, absence, typed rejection,
duplicate and empty physical diagnostic headers, malformed XML, and a body
over the caller limit. The common root gate repeats the entire socket sequence
under native and Flyology lightweight task owners three times.

The machine ledger records `GetBucketEncryption` as `missing / covered /
missing / covered`. Client and corpus qualification does not manufacture
backend state or a server route; those cells require separate persistence,
routing, and independent black-box evidence.

## Formal boundary

This slice changes only non-SPARK client, codec, corpus, and documentation
units. None of the nine `tools/prove.sh` manifest units changes, so the latest
serialized 2026-08-24 result remains applicable: 936/936 checks, 180 flow and
756 prover, with zero warnings, unproved or justified checks, or
`pragma Assume` statements.

## Gate evidence

The root gate passed 40/40 AUnit checks, 88 files crash-recovery scenarios,
320 checksum vectors with 210 chunkings, and three complete deterministic and
native/lightweight socket-corpus repetitions. The SQLite gate also passed.
The preparation verifier, operation-coverage verifier and its negative oracle
all passed. GNATdoc produced a nonempty API index containing the encryption
types and low-level operations, with no targeted warnings or internal parser
errors after documenting the public malformed-response exception.
