# SelectObjectContent negative-capability profile

SelectObjectContent is covered only for the maintained local server's
authenticated rejection boundary. The operation remains `Not_Exposed`: there
is no public Low_Level or Objects request, synchronous wrapper, composable
operation, Finish path, result sink, event decoder, or public client GNATdoc
claim.

The private server recognizes only an exact `POST` object query carrying
`select` and `select-type=2`, including the modeled `x-id=SelectObjectContent`
association. Authentication precedes every query, header, and body diagnostic.
The route requires a nonempty bounded, entity-safe, well-formed
`SelectObjectContentRequest` root in the pinned S3 XML namespace. The bound is
derived from the maintained XML limits rather than a new Select-specific or
public policy.

A supplied expected owner is singleton and must match the authenticated
principal. A supplied SSE-C group must contain exactly one algorithm, key, and
key digest, use AES256 over HTTPS, and carry a valid key digest. These checks
establish transport syntax only. They do not establish object encryption,
decrypt an object, or bind the key to stored object state.

After request validation, the route consults only the shared `Head_Bucket` and
`Head_Object` capabilities. An absent bucket returns `NoSuchBucket`; an absent
object in an existing bucket returns `NoSuchKey`; and an existing object
returns `NotImplemented`. The route never calls `Get_Object`, reads object
bytes, executes SQL, serializes selected records, reports success, or mutates
backend state.

Root validation does not interpret or default Expression, SQL,
CSV/JSON/Parquet input, compression, output serialization, progress,
ScanRange, or their cross-field relationships. Records, Stats, Progress, Cont,
and End remain generated-model inventory only. No AWS event-stream prelude,
header, message CRC, error frame, End completion, split-record reconstruction,
result bound, backpressure, cancellation, drain, restart, or resume behavior is
claimed.

The request has no VersionId. The current-object existence check is not a
stable query snapshot, and a later request cannot resume, continue, prove, or
upgrade an earlier result. No automatic replay, service-availability promise,
directory-bucket or Outposts behavior, access-point routing, external-provider
interoperability, or SelectObjectContent qualification is claimed.

Qualification remains conditional on every command in the single
`select_object_content` lane succeeding. The dedicated preparation verifier
pins this negative-capability source boundary, the generated-model verifier
pins the request and five-event inventory, and the maintained root test and
repository gates retain the shared backend and authenticated server evidence.
