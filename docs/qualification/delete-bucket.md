# DeleteBucket qualification and boundaries

This slice qualifies authenticated path-style DeleteBucket requests for
general-purpose buckets. It does not recursively remove objects, retained
versions, delete markers, or multipart state. Directory-bucket control
endpoints, access points, and Outposts routing remain outside this profile.

## Public result and certainty

The limited `Client.Buckets.Delete` operation owns its prepared bodyless
request and bounded error response. The HTTP client and optional cancellation
token remain retained through terminal drain; typed `Finish` consumes the
operation after its child is terminal. The same operation object may restart
only after it has been consumed and its retained owner is unchanged.

Only a complete validated 204 proves `Bucket_Deletion_Completed`. Exact
recognized non-applying responses and definite non-admission prove
`Bucket_Definitely_Not_Deleted`. Cancellation before possible admission is
reported separately. Retryable responses, malformed or oversized responses,
and any failure after possible admission remain
`Bucket_Deletion_Outcome_Unknown`. No result authorizes automatic replay.

## Reconciliation and concurrent state

An unknown result requires caller-selected HeadBucket reconciliation for the
exact bucket name and expected-owner context before retry. Current absence ends
deletion work. A present or ownership-ambiguous result requires caller policy;
HeadBucket establishes current state, not which concurrent request deleted or
recreated the bucket. Deletion cannot roll back an already-deleted bucket.

## Maintained evidence

The signed socket corpus covers typed and composable success, exact normalized
rejections and transport failures, operation-last restart, native and
lightweight admitted cancellation, terminal drain acknowledgement, typed
Finish, same-operation restart after drain, and a dropped-response sequence
whose next request must be HeadBucket rather than a replayed DELETE.

The focused lane runs the independent preparation oracle, warning-strict test
build, signed socket corpus, 116-operation coverage verifier, fresh public API
documentation, pinned-model repository gate, and diff check. DeleteBucket is
qualified only when every maintained gate reaches its success sentinel. Any
repository-owned GNATdoc warning prevents a qualification claim.
