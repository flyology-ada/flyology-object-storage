# GetBucketLocation qualification boundary

`GetBucketLocation` is a read-only operation exposed as
`Flyology.Object_Storage.Client.Buckets.Get_Location`. The caller supplies the
origin, bucket name, expected-owner precondition, credentials, deadline,
region, addressing style, and optional cancellation source. The client signs
one `GET /{Bucket}?location` request and does not select or rewrite endpoints.

A complete validated `200` response returns `Bucket_Location_Found`. The
location text is preserved exactly: an empty element is the legacy
`us-east-1` representation and `EU` is not rewritten. A bounded well-formed
S3 error remains a typed rejection. The maintained normalization corpus covers
the reviewed authentication, authorization, absence, invalid-request,
retryable, and corrupt-response classes across all admission states.

The composable operation owns its prepared request and retained response bytes
through terminal `Finish`. Qualification exercises native and lightweight
completion sets, pre-admission cancellation, admitted cancellation, `Wait_All`,
typed `Finish`, explicit drain acknowledgement, rejection of a changed retained
owner, and restart of the same consumed operation object. Read-only operations
need no mutation-certainty or reconciliation policy and are never replayed by
this layer.

The boundary excludes directory-bucket and S3 Express endpoint selection,
access-point, Object Lambda, and Outposts endpoint discovery or rewriting, and
cross-region redirect following. Caller-supplied general-purpose-bucket origins
remain authoritative.

The focused lane runs the preparation verifier, warning-strict tests build,
signed loopback corpus, 116-operation coverage verifier, fresh selected API
documentation, pinned-model repository gate, and final diff check. The
repository-owned GNATdoc warning gate remains fail-closed: passing earlier
phases alone is not a qualification claim.
