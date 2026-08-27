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

The parameter-record `List_Page` overload waits on the limited
`Client.Buckets.List_Page` operation and preserves typed HTTP failure, causal phase,
and request-admission certainty. The same limited operation can instead be
constructed directly, composed through a caller-owned completion set, and
restarted after typed `Finish`. It owns the prepared signed request and a
response bounded by the shared S3 XML document limit; credentials are borrowed
only during signing. There is no helper task, automatic retry, or retained
borrowed query input. The convenience overload now waits on this same state
machine and preserves its established raising transport behavior.

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
The parameter-record `Get_Location` overload waits on the provider-owned
limited operation and preserves the raw modeled response, HTTP admission,
causal phase, and bounded failure reason. Directly composed callers use the
same-name constructor or operation-last procedure and typed `Finish`; the
operation owns its signed request and bounded XML response without retaining
credentials, bucket text, or the owner precondition. The convenience overload
waits on that same state machine before applying the established empty/EU
normalization.
The parameter-record `Delete` overload waits on the provider-owned limited
operation and preserves HTTP admission plus deletion certainty. Directly
composed callers use the same-name constructor or operation-last procedure and
typed `Finish`; its known-empty source is deliberately non-replayable. A lost
response after possible admission requires caller-selected `Head` reconciliation
before retry, and no helper task or borrowed request input survives initiation.

`Put_Tags` and `Get_Tags` expose the complete bucket tag set as the shared
HTTP-independent `Tags.Tag_Set`. Put generates the strict REST/XML document and
Content-MD5 automatically and replaces the entire set atomically. Get returns a
typed snapshot; an existing untagged bucket remains the structured
`NoSuchTagSet` rejection. Both convenience calls retain expected-owner,
requester-pays, timeout, cancellation, addressing-style, and signing-region
controls. The low-level surface additionally exposes an explicit Content-MD5
for protocol tests and the modeled checksum-algorithm member; checksum selection
currently fails locally until paired checksum generation is implemented.

`Set_Versioning` enables or suspends versioning configuration and
`Get_Versioning` preserves the distinction between an absent configuration and
Suspended. `Set_Versioning_Configuration` exposes both presence-preserving
configuration fields, the physical MFA credential, concrete checksum
selection, and expected-owner control. It rejects MFA credentials on cleartext
origins and requires an explicit status and credential for an MFA Delete
change. The synchronous request retains the credential only through signing
and execution. These calls configure a bucket; they do not imply object-version
creation, version IDs, or delete markers. The separately qualified
`Client.Objects.List_Versions_Page` is a client-only wire boundary and does not
change that backend limitation.

The parameter-record `Get_Versioning` overload waits on a provider-owned
limited operation that retains the exact signed request and response under the
versioning XML limit. Directly composed callers use the same-name constructor
or operation-last procedure and typed `Finish`; the result preserves the raw
modeled response, HTTP admission, causal phase, and bounded failure reason.
The established convenience overload waits on the same operation and retains
its raising transport behavior. No request text or credential remains borrowed
after signing, and this read-only operation does not select mutation retry
policy.

`Create_Session` likewise has a same-name limited constructor, operation-last
restart, typed Finish, and parameter-record synchronous wait. Its operation
retains the signed request and bounded raw response, not decoded credentials;
Finish constructs the limited zeroizing identity exactly once after validating
the physically captured headers against the signed policy. The established
scalar convenience overload waits on the same state machine. No overload adds
a refresh task, client-side session cache, retained caller borrow, or
operation-level replay; transport recovery remains the configured HTTP policy.

The complete-configuration `Set_Versioning_Configuration` overload likewise
waits on a provider-owned limited mutation. Directly composed callers use its
same-name constructor or operation-last procedure and typed `Finish`. The
prepared request owns the serialized configuration and every signed header;
both synchronous and composable forms expose those exact bytes through one
non-rewindable source. A complete success or exact conclusive rejection can
settle mutation certainty. Every failure after possible admission remains
outcome-unknown and requires caller-directed `Get_Versioning` reconciliation
before any retry. No request input remains borrowed after signing.

These operations are deliberately individual. Parallel work across many
buckets or objects belongs in an application-owned joined scope, while
multi-file data transfer uses `Client.Transfers.Transfer_Many` and its explicit
concurrency, in-flight-byte, failure, deadline, and cancellation policy.

`Client.Buckets.Delete_CORS` removes one bucket's complete CORS configuration
through the exact bodyless `DeleteBucketCors` operation. It preserves the
optional expected-owner precondition and returns either exact `204` completion
or a bounded structured S3 rejection. This client-only boundary does not imply
that Flyology backends store CORS configuration or that the authenticated
server routes the operation.

The same operation-specific request and response contract serves the twelve
other bodyless bucket-configuration deletes: analytics, encryption,
intelligent tiering,
inventory, lifecycle, metadata, metadata table, metrics, ownership controls,
replication, website, and public access block. Analytics, intelligent tiering,
inventory, and metrics require a caller-supplied configuration identifier;
every operation preserves the optional expected-owner precondition. The
inventory, lifecycle, replication, and website clients additionally expose
provider-owned non-replaying composable operations and typed synchronous waits
over those state machines. Public functions and low-level preparer/executor
pairs remain
operation-specific, so sharing transport and response logic does not allow a
prepared request to be executed as another operation. These are client-only
wire boundaries and make no backend, Flyology server, or external provider
interoperability claim.

Six small bucket-control reads share low-level request and response machinery:
ABAC, transfer acceleration, raw bucket policy, policy status, requester-pays,
and public-access block. Their public preparers, executors, outcomes, and
convenience calls remain operation-specific. Optional modeled fields preserve
absence, including each of the four public-access-block booleans; enum and
boolean spellings are exact. Policy is returned as the bounded same-response
payload without XML interpretation. Its provider-owned composable form owns
the signed request and retained bytes through typed `Finish`, supports
operation-last restart, and uses the caller's existing response limit. The four
XML responses use the caller's shared S3 XML resource limits and accept the
established compatible empty or AWS S3 namespace, while rejecting foreign
namespaces, attributes, unknown or duplicate fields, nesting, DTDs, and
entities. Bucket policy and public-access block have independently qualified
backend and authenticated-server implementations; the other four controls
remain client-only, and external-provider interoperability is not claimed.

`Client.Buckets.Get_Metrics_Configuration` reads one caller-selected metrics
identifier through the shared bounded REST/XML state machine. The low-level
preparer binds the required `id` query and optional expected-owner header to
GetBucketMetricsConfiguration, while the typed result preserves the required
identifier and every modeled optional Prefix, Tag, AccessPointArn, and And
member. And/Tag is an ordered flattened list bounded by the caller's XML
limits. The pinned structural model does not encode the prose-only filter
cardinality rules, so the decoder preserves the graph without inventing them.
The limited constructor, operation-last restart, typed `Finish`, and
synchronous wait share one state machine; no backend, server, or external
provider support is claimed.

The scalar write companion covers ABAC, acceleration, raw bucket policy,
requester payment, and public-access block. The four structured operations
serialize exact AWS-namespaced XML; policy preserves the caller's bytes
without XML interpretation and bounds them with the caller's existing S3 XML
document limit. The client generates Content-MD5 for the four operations that
model it and can compute and sign each of the ten modeled concrete checksum
algorithms. Policy also preserves the optional modeled
`x-amz-confirm-remove-self-bucket-access` Boolean. Acceleration rejects a
supplied Content-MD5 because that member is absent from its pinned request
shape. Exact operation binding is checked again before HTTP, and 200 success
must contain only an empty or whitespace body. Except for raw bucket policy,
these remain client-only configuration calls with no backend or
authenticated-server claim.

Raw policy replacement and deletion additionally have provider-owned
composable forms. `Set_Policy` owns the exact caller policy copied during
bounded preparation and exposes it once through a non-rewindable source;
`Delete_Policy` uses a non-rewindable known-empty source. Both typed results
retain HTTP admission certainty and distinguish completion, conclusive
non-application, pre-admission cancellation, and an outcome that requires a
caller-selected `Get_Policy` reconciliation before any retry. Their
parameter-record synchronous overloads wait on those same state machines, and
operation-last restart retains only the established HTTP client and optional
cancellation owner.
