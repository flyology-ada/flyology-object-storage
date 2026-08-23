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

The same private synchronous state machine serves the thirteen other bodyless
bucket-configuration deletes: analytics, encryption, intelligent tiering,
inventory, lifecycle, metadata, metadata table, metrics, ownership controls,
policy, replication, website, and public access block. Analytics, intelligent
tiering, inventory, and metrics require a caller-supplied configuration
identifier; every operation preserves the optional expected-owner
precondition. The public functions and low-level preparer/executor pairs
remain operation-specific, so sharing transport and response logic does not
allow a prepared request to be executed as another operation. These are
client-only wire boundaries and make no backend, Flyology server, or external
provider interoperability claim.

Five small bucket-control reads use a second shared synchronous state machine:
transfer acceleration, raw bucket policy, policy status, requester-pays, and
public-access block. Their public preparers, executors, outcomes, and
convenience calls remain operation-specific. Optional modeled fields preserve
absence, including each of the four public-access-block booleans; enum and
boolean spellings are exact. Policy is returned as the bounded same-response
payload without XML interpretation. The four XML responses use the caller's
shared S3 XML resource limits and accept the established compatible empty or
AWS S3 namespace, while rejecting foreign namespaces, attributes, unknown or
duplicate fields, nesting, DTDs, and entities. This is a client-only boundary:
Flyology backends and the authenticated server do not implement these five
operations, and external-provider interoperability is not claimed.
