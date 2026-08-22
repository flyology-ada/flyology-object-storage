# Bucket convenience client

`Flyology.Object_Storage.Client.Buckets` provides the common general-purpose
bucket lifecycle without requiring callers to assemble signed low-level
requests. Every call uses a caller-owned Flyology HTTP client, accepts a whole
operation timeout and optional cancellation token, and returns either a typed
success record or the structured S3 error.

## List

`List_Page` returns one typed, bounded page and defaults to 1,000 buckets, so
the convenient path follows AWS's recommendation to paginate. Prefix and
bucket-region filters are optional; a returned continuation token can be
passed unchanged to the next call. The complete result preserves owner,
creation time, region, ARN, prefix-presence, and continuation-presence fields.
Callers that must distinguish an explicitly supplied empty query value use the
presence flags on `Client.Low_Level.List_Buckets_Parameters`.

## Create

`Create` creates a general-purpose bucket. For `us-east-1` it omits the legacy
`LocationConstraint`; for another signing region it supplies that region
automatically. An explicit constraint remains available for compatibility
workflows such as the legacy `EU` spelling. Success preserves the `Location`
and optional `x-amz-bucket-arn` response headers.

The convenience API intentionally does not guess policy for ACL grants,
public ACLs, Object Lock, ownership modes, tags, directory buckets, or bucket
namespace controls. Callers that require those inputs use the complete typed
`Client.Low_Level.Create_Bucket_Parameters` surface. The Flyology server
currently accepts private general-purpose buckets with absent or
`BucketOwnerEnforced` ownership. It returns `NotImplemented` for valid advanced
controls and rejects malformed or duplicate controls before backend mutation.

## Inspect and delete

`Head` returns the modeled bucket metadata headers without retaining a body.
`Location` normalizes the legacy empty and `EU` values into signing regions
while preserving the wire spelling. `Delete` removes an empty bucket and
preserves `BucketNotEmpty`, owner-precondition, and other S3 rejections.

`Put_Tags` and `Get_Tags` expose the complete bucket tag set as the shared
HTTP-independent `Tags.Tag_Set`. Put generates the strict REST/XML document and
Content-MD5 automatically and replaces the entire set atomically. Get returns a
typed snapshot; an existing untagged bucket remains the structured
`NoSuchTagSet` rejection. Both convenience calls retain expected-owner,
requester-pays, timeout, cancellation, addressing-style, and signing-region
controls. The low-level surface additionally exposes an explicit Content-MD5
for protocol tests and the modeled checksum-algorithm member; checksum selection
currently fails locally until paired checksum generation is implemented.

These operations are deliberately individual. Parallel work across many
buckets or objects belongs in an application-owned joined scope, while
multi-file data transfer uses `Client.Transfers.Transfer_Many` and its explicit
concurrency, in-flight-byte, failure, deadline, and cancellation policy.
