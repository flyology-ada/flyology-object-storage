# Bucket tagging evidence

This slice qualifies PutBucketTagging, GetBucketTagging, and
DeleteBucketTagging for the pinned S3 model. The authoritative request shapes
contain ExpectedBucketOwner on all three operations and ContentMD5 plus the
ten-value ChecksumAlgorithm enum on Put. RequestPayer and RequestCharged are
not modeled; the unreleased strict high-level API omits them, while retained
low-level development-compatibility fields reject nonempty values.

The server returns 200 for Put, matching the primary AWS response syntax and
the pinned model. The AWS documentation also contains a 204 example, so the
client accepts both 200 and 204 without inventing response metadata. Delete
requires and emits 204 with an exactly empty body.

The additive `Client.Scoped` family exposes one owner-driven operation each
for PutBucketTagging, GetBucketTagging, and DeleteBucketTagging. Put serializes
and owns the exact signed tag document once; Delete owns a known-empty source;
neither mutation can be replayed. Get retains a bounded whole response and
decodes the tag snapshot only after a complete observed response. The
parameter-record `Client.Buckets` overloads wait on those same operations, so
the synchronous and composable forms share request ownership, decoding, and
certainty mapping.

The deterministic normalization corpus covers exact completed and conclusive
responses, paired retryable status/code responses, mismatched or absent error
codes, every typed HTTP failure kind, and every admission state. The raw socket
corpus drives all three operations directly, verifies a consumed Put operation
can restart with the same retained owners, and exercises the legacy wrappers
through the same state machines under native and lightweight tasks.

The reproducible offline gates are:

```text
./tests/scripts/test.sh
./sqlite/tests/scripts/test.sh
```

They cover atomic memory, files, and SQLite replacement/deletion; file and
catalog reopen; every recognized SQLite migration; cancellation and expired
deadlines; filesystem publication barriers; live and dangling symlink
rejection; strict namespace-aware XML and tag limits; SigV4 auth-before-
semantics; exact query and owner controls; Content-MD5; all ten checksum header
groups; physical checksum trailers; duplicate and malformed controls;
non-mutation on rejection; and typed low/high clients over fragmented sockets.

The independent black-box gate is:

```text
./tests/scripts/test-s3-matrix.sh
```

The shared implementation corpus performs put/get, complete replacement/get,
delete/get-NoSuchTagSet, and repeated idempotent delete against digest-pinned
RustFS and SeaweedFS, supplemental pinned MinIO, and Flyology memory, files,
and SQLite. A complete one-repetition six-server campaign passed on
2026-08-22. The default three-repetition campaign remains the final release
gate.

For comparative control-plane throughput, run:

```text
./benchmarks/run-bucket-tagging-matrix.sh
```

That driver uses one persistent client, alternates exact tag values, and
validates every timed Put/Get/Delete/Get-NoSuchTagSet lifecycle. Its negative
self-oracles reject stale Put, successful-no-op Delete, and mismatched HTTP
status/error-code observations.
The retained clean-source smoke campaign is
[`20260822-bucket-tagging-smoke`](../../benchmarks/evidence/20260822-bucket-tagging-smoke/).
It contains metadata, normalized and raw samples, the six-role summary, and a
hash manifest for all retained artifacts. The executable gate
`./tools/verify-bucket-tagging-benchmark-evidence.sh` checks the artifact
schema, raw-to-normalized-to-summary derivation, exact six-role population,
three samples per role, four requests per lifecycle, clean Flyology revision
ancestry, corpora provenance, rates, and hashes. The launcher initially wrote
the malformed `alr=APPLICATION` field; only that provenance field was
corrected post-campaign from `alr --version` on the same host and tool (`alr
2.1.1`). The measured rows and source revision were not regenerated or
altered. The host, power, and CPU-policy labels are deliberately unqualified,
so these development-machine smoke rates are tuning evidence only. A release
threshold requires the full profile's clean revision and qualified host policy
metadata.

The exact composable source tree passed the warning-strict maintained proof
gate with 936/936 checks proved. The required post-run host audit found no
GNATprove, Why3, SMT, TLC, or TLAPS process before the exclusive lane was
released.
