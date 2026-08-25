# ListObjects v1 qualification evidence

This slice qualifies `ListObjects` from the pinned botocore S3 service model.
The model is pinned at botocore revision
`36c34f15391da01cd717c73c0fffa747c9889768`; its normalized model digest is
`429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
The implementation was audited against that model and the AWS ListObjects API
reference before the ledger promotion.

The request accounts for Bucket, Delimiter, EncodingType, Marker, MaxKeys,
Prefix, RequestPayer, ExpectedBucketOwner, and OptionalObjectAttributes.
FetchOwner is not a v1 input. The response accounts for every modeled
top-level field and every nested Object member, including optional owner,
checksum, and restore status shapes. Presence is retained for optional empty
strings and explicit zero values where the model permits them.

Memory, files, and SQLite take one atomic namespace snapshot per backend call.
They apply bytewise prefix filtering, exclusive Marker filtering, delimiter
projection, and the shared object/common-prefix MaxKeys budget before
publishing the immutable page. A truncated delimiter page publishes the last
emitted entry as NextMarker. A truncated page without a delimiter omits
NextMarker; `List_V1_Page` derives its next logical marker from the last object
key. When EncodingType is `url`, the convenience cursor is strictly decoded
before the next request signs and percent-encodes it. Tests cover slash, space,
literal percent, non-ASCII bytes, malformed escapes, multiple-character
delimiters, mutation between pages, cancellation, and deadline propagation.

The public `Client.Objects.List_V1_Page` operation owns the prepared request
and bounded response bytes until typed Finish. It can restart after Finish on
the same retained HTTP client and cancellation token, without a helper task or
automatic retry. Complete-response decoding enforces physical singleton
headers and binds the bucket, optional echoed prefix/delimiter/marker,
requested or default maximum, URL-encoding mode, and requester-pays charge to
the signed request. The parameter-record synchronous overload waits on this
operation; the convenience overload preserves its raising transport contract
and applies marker fallback afterward. The socket corpus covers success,
modeled error normalization, wrong echoes, duplicate headers, unrequested
payer charges, pre-admission cancellation, and direct-operation restart.

The authenticated general-purpose path-style server projects its static
principal as the bucket and object owner. It enforces expected-owner and
accepts syntactically valid Requester Pays input as an owner request without
claiming requester billing or emitting `x-amz-request-charged`. RestoreStatus
is accepted and omitted for the supported non-archival objects. Directory
buckets, archival state, object-version history, access points, Outposts, and
requester-billing policy are not claimed.

The six-server matrix repeats the same native and Flyology-lightweight client
corpus against digest-pinned RustFS, SeaweedFS, supplemental MinIO, and
Flyology memory, files, and SQLite. All 18 lanes passed on 2026-08-22. Pinned
RustFS, SeaweedFS, and MinIO each emit a non-model NextMarker on a truncated
v1 page without a delimiter. Their strict no-delimiter continuation subcase is
excluded explicitly; the basic v1 path remains enabled, while every Flyology
backend passes the complete two-page AWS fallback rule.

Reproduce the deterministic qualification with:

```text
./tests/scripts/test.sh
./sqlite/tests/scripts/test.sh
./tests/scripts/test-s3-matrix.sh
./tools/verify-coverage.sh
./tools/test-coverage-verifier.sh
./tools/verify-benchmark-plan.sh
```

The retained unqualified-host smoke evidence is
[`20260822-listobjects-v1-smoke.tsv`](../../benchmarks/evidence/20260822-listobjects-v1-smoke.tsv).
Its signed raw-XML oracle ran before and after the measured request against
RustFS, SeaweedFS, and Flyology memory, files, and SQLite. Every run required
HTTP 200, the exact ordered unique 64-key set, `MaxKeys=1000`,
`IsTruncated=false`, one v1 Marker element, and no NextMarker, KeyCount, or
continuation-token elements. The evidence records immutable server revisions,
candidate revision, curl provenance, raw XML digests, and retained campaign
metadata/sample/summary digests. These development-host throughput numbers
are correctness and tuning evidence, not a release performance baseline.
