# Composable HeadBucket qualification

`Flyology.Object_Storage.Client.Buckets.Head` provides the owner-driven
bodyless bucket probe. Its operation-last procedure restarts a consumed
operation only with its retained HTTP client and cancellation owner. The
operation owns its prepared signed request through terminal drain and retains
no borrowed bucket, owner-precondition, credential, or region input after
initiation.

`Decode_Head_Bucket_Complete_Response` is shared by blocking and composable
paths. It rejects response bodies, transfer coding, duplicate modeled
singleton headers, invalid optional Boolean metadata, invalid region or
location syntax, and oversized modeled values. Complete bodyless rejections
preserve request and host identifiers. A bodyless 404 is normalized to
`Not_Found`; because HeadBucket has no response body, that status does not
prove bucket absence rather than an authorization or endpoint condition.

The maintained focused lane checks the pinned request and response inventory,
the six bounded failure categories, and the exact public symbol set. Its raw
socket corpus covers native and lightweight admission, cancellation, drain
acknowledgement, typed `Finish`, retained-owner rejection, and restart of the
same operation object. The convenience call waits the same state machine and
retains its established transport behavior and signing-region fallback.

Qualification covers caller-supplied origins for general-purpose buckets.
Directory-bucket and S3 Express endpoint selection, access-point, Object
Lambda, and Outposts endpoint discovery or rewriting, and cross-region
redirect following remain outside this focused lane. Backend and provider
compatibility remain separately gated by their maintained black-box suites.
