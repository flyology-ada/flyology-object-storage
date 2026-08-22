# Bucket convenience client

`Flyology.Object_Storage.Client.Buckets` provides the common general-purpose
bucket lifecycle without requiring callers to assemble signed low-level
requests. Every call uses a caller-owned Flyology HTTP client, accepts a whole
operation timeout and optional cancellation token, and returns either a typed
success record or the structured S3 error.

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

These operations are deliberately individual. Parallel work across many
buckets or objects belongs in an application-owned joined scope, while
multi-file data transfer uses `Client.Transfers.Transfer_Many` and its explicit
concurrency, in-flight-byte, failure, deadline, and cancellation policy.
