# PutBucketEncryption client qualification

This record qualifies the strict bounded low-level and provider-owned clients
for `PutBucketEncryption`. It does not claim bucket-encryption persistence in a
Flyology backend, an authenticated Flyology server route, or external server
interoperability.

## Pinned authority and inventory

The machine inventory is tied to botocore S3 model revision
`36c34f15391da01cd717c73c0fffa747c9889768` and service-model SHA-256
`429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
Input shape 528 requires `Bucket` and
`ServerSideEncryptionConfiguration`; `ContentMD5`, `ChecksumAlgorithm`, and
`ExpectedBucketOwner` are optional. The operation requires request-checksum
admission, returns exact status 200, and has no modeled success output.

The configuration requires flattened Rules shape 650. Rule shape 649 contains
optional default encryption, bucket-key Boolean, and blocked-encryption
structures. A present default requires one of `AES256`, `aws:fsx`,
`aws:backup`, `aws:kms`, or `aws:kms:dsse`; the optional KMS key remains an
opaque string. The optional flattened blocked list admits exactly `NONE` and
`SSE-C`. Checksum shape 77 contributes ten exact SDK algorithms.

The reciprocal member and vector ledgers cover all 12 named members and 13
request, schema, checksum, limit, response, header, and transport contracts.
The maintained verifier gates the complete operation and shape graph:

```sh
python3 tools/verify-put-bucket-encryption-preparation.py
```

## Serialization and request contract

`S3.Encryption.Serialize` requires a present configuration with at least one
rule. It emits the exact S3 namespace, flattened rule and blocked-type lists,
presence-sensitive optional structures, lowercase Boolean values, pinned enum
spellings, and XML-escaped opaque key text in caller order. It introduces no
list or string ceiling outside the caller-selected shared XML limits.

Those limits bound the complete encoded document, maximum depth, element
count, and decoded text bytes. Inconsistent optional-container/list state,
absent or empty required rules, and every one-past limit fail before HTTP
admission. The strict GetBucketEncryption parser round-trips every emitted
value while preserving absent, present-empty, and present-populated members.

`Client.Low_Level.Prepare_Put_Bucket_Encryption` signs the exact path-style or
virtual-hosted `?encryption` target. It computes Content-MD5 when omitted,
validates an exact caller override, and projects any of the ten modeled SDK
checksum algorithms over the immutable serialized bytes. The prepared request
owns those bytes. Its request source is deliberately non-rewindable, so neither
the low-level executor nor the provider operation can replay the mutation.

`Execute_Put_Bucket_Encryption` accepts only that prepared operation and drives
the caller-owned synchronous HTTP client. Exact 200 plus an empty or XML-
whitespace body is success; non-whitespace success content and malformed or
over-limit responses fail closed. Every other status becomes one bounded typed
S3 rejection.

## Provider-owned composition and certainty

`Client.Buckets.Set_Encryption` colocates the limited constructor,
operation-last reusable procedure, typed `Finish`, and synchronous wait. The
parent owns its prepared request, source position, bounded response bytes,
deadline, and cancellation source through terminal drain. Restart requires a
consumed prior result and the same retained HTTP and cancellation owners. No
caller configuration or credential borrow survives signing.

A complete response observed as exact 200 is completed. Only a response-
observed exact modeled pre-mutation rejection, or a failure known not to have
entered HTTP admission, is definitely not applied. Cancellation before
admission is distinct. Every other possibly admitted failure and every unknown
response remains outcome unknown and requires caller-selected read
reconciliation before any retry.

## Evidence boundary

The deterministic corpus covers exact serialization and round trip, sparse and
full presence, XML escaping, both addressing styles, automatic MD5, all ten SDK
checksums, invalid inputs, caller limit boundaries, and cross-operation
rejection. The signed loopback corpus covers low-level execution, synchronous
provider waiting, limited construction, copied input lifetime, operation-last
restart, typed response-observed certainty, and exact prepared-operation
identity. The normalization corpus crosses every typed HTTP failure with every
admission certainty.

These client and corpus results advance only the client and corpus coverage
cells. Backend state, authenticated routing, and independent external-provider
behavior remain separate work.

## Maintained gate results

The exact implementation tree passed the maintained root and test builds,
the focused deterministic and signed-socket corpora, and the full core suite:

```sh
alr -n build
(cd tests && alr -n build)
./tests/scripts/test.sh
```

The full suite passed all 41 shared conformance cases, all 126 filesystem
crash-injection cases, all 320 checksum vectors, all 210 chunk-boundary cases,
and all three required repetitions. The SQLite backend suite also passed:

```sh
./sqlite/tests/scripts/test.sh
```

Repository integrity, generated-corpus reciprocity, and whitespace checks
passed through `./tools/ci/check-repository.sh` and `git diff --check`. The
maintained GNATdoc build exited successfully, produced a nonempty API index
containing `Put_Bucket_Encryption_Operation` and every `Set_Encryption`
overload, introduced no public documentation warning, and emitted no internal
or fatal diagnostic. This slice does not change any unit selected by the
maintained SPARK proof manifest, so proof remains an exact-tree integration
gate rather than evidence for the serializer or client operation in isolation.
