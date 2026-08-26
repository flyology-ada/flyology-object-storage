# Composable object client operations

This note records the implemented contract for the completion-set-aware object
client slice: conditional complete-object Put, generation-bound whole and
single-range Get, bodyless Head, non-replaying Delete, non-replaying multipart
initiation, one-shot UploadPart, one-shot multipart completion and abort,
bounded multipart discovery, CopyObject, UploadPartCopy, DeleteObjects,
ListObjects v1/v2, ListObjectVersions, GetObjectAttributes, and service-level
ListBuckets, CreateBucket, non-replaying DeleteBucket, bodyless HeadBucket,
bounded GetBucketLocation, bounded GetBucketPolicy, GetBucketPolicyStatus, and
GetBucketRequestPayment, bounded GetBucketAbac and
GetBucketAccelerateConfiguration, bounded GetBucketAcl and GetObjectAcl,
bounded GetBucketMetadataTableConfiguration, non-replaying
Put/DeleteBucketPolicy, non-replaying
PutBucketAbac, PutBucketAccelerateConfiguration, and
PutBucketRequestPayment,
Put/GetBucketVersioning,
non-replaying
Put/DeletePublicAccessBlock with bounded GetPublicAccessBlock, and bucket
tagging Put/Get/Delete, bounded GetBucketCors, non-replaying Put/DeleteBucketCors,
non-replaying DeleteBucketLifecycle,
object tagging Put/Get/Delete, and bounded GetObjectLegalHold with
non-replaying PutObjectLegalHold, plus bounded GetObjectRetention with
non-replaying PutObjectRetention, and bounded GetObjectLockConfiguration with
non-replaying PutObjectLockConfiguration. The
prerequisite is published through the Flyology Alire index as lockstep HTTP and
QUIC 0.1.3 development crates.

## Upstream basis

The object-storage design was audited at commit
`81389185a5d45eaa8b893a82218a9c574b667daa`. The indexed
`flyology=0.1.1-dev` source at
`4ec71932fa5d016cce82ad49a4b7a5018a819cae` includes the merged composable
operation model:

- caller-owned `Flyology.Operations.Completion_Set` values with capacity 1
  through 32;
- limited operations, generation-stamped references, typed `Finish`, explicit
  cancellation, consumption, and release;
- `Wait_Some`, `Wait_All`, `Wait_For_Success`, and
  `Wait_For_Successes` first-class gates; and
- `Continue_After` for an outer operation to drive and consume a hidden child
  operation on the owner task's stack.

The exact indexed `flyology_http=0.1.3-dev` dependency selects
`flyology_quic=0.1.3-dev`; both resolve to reviewed source commit
`eb09a80a7e06274e93289861c2cae1ca7e8cb1af`. The Object Storage implementation
uses those exchanges directly; it does not simulate composition with a helper
task or a retained borrowed source, and no committed dependency pin remains.

## Provider-centric public boundary

`Scoped` describes an operation's lifetime and ownership discipline; it is not
the provider that performs the operation. Each domain provider therefore owns
its complete operation vocabulary: `Client.Objects` owns object calls,
`Client.Buckets` owns bucket calls, and `Client.Transfers` owns multipart and
copy calls. Each provider contains the synchronous call, limited constructor,
operation-last reusable initiation procedure, operation type and state, and
typed `Finish` overloads. Ada overload resolution distinguishes these forms
without a second parallel API tree.

This colocation makes the shared state machine and semantics discoverable at
the synchronous provider, avoids duplicated package locations and downstream
wrapper conventions, and keeps documentation and tests attached to the
operation owner. Scoped lifetime remains explicit through the limited
operation, completion-set ownership, cancellation and drain rules, retained
borrows, and typed Finish. The former lifetime-named child was removed on the
current development line without compatibility declarations so new callers
cannot retain the misleading convention. Ordinary
`Flyology.Operations.Reference` values and gates compose these operations;
the object-storage API does not define a competing scheduler or gate type.

The implemented operation order is:

1. conditional complete-object `Put_Object` projections;
2. whole `Get_Object`;
3. generation-bound exact-range `Get_Object`;
4. `Head_Object`;
5. `Delete_Object`;
6. `Create_Multipart_Upload`;
7. `Upload_Part`;
8. `Complete_Multipart_Upload`;
9. `Abort_Multipart_Upload`;
10. `List_Parts` and `List_Multipart_Uploads`;
11. `Copy_Object` and `Delete_Objects`;
12. complete modeled `Put_Object` controls;
13. `List_Objects_V2`;
14. `List_Object_Versions`;
15. `Get_Object_Attributes`;
16. `Upload_Part_Copy`;
17. `List_Objects` (v1);
18. service-level `List_Buckets`;
19. bodyless `Head_Bucket`;
20. non-replaying `Create_Bucket`;
21. non-replaying `Delete_Bucket`;
22. bounded `Get_Bucket_Location`;
23. non-replaying `Put_Bucket_Versioning` and bounded
    `Get_Bucket_Versioning`;
24. bounded `Get_Bucket_Policy`, `Get_Bucket_Policy_Status`,
    `Get_Bucket_Request_Payment`, `Get_ABAC`, and
    `Get_Accelerate_Configuration`, plus non-replaying `Set_ABAC`,
    `Set_Accelerate_Configuration`, and `Set_Request_Payment`;
25. `Set_Public_Access_Block`, `Get_Public_Access_Block`, and
    `Delete_Public_Access_Block`;
26. bounded `Get_Ownership_Controls`, non-replaying
    `Set_Ownership_Controls`, and non-replaying
    `Delete_Ownership_Controls`;
27. bounded `Get_Encryption`, non-replaying `Set_Encryption`, and
    non-replaying `Delete_Encryption`;
28. bounded `Get_CORS`, non-replaying `Set_CORS`, and non-replaying
    `Delete_CORS`;
29. non-replaying `Delete_Lifecycle`;
30. `Put_Bucket_Tagging`, `Get_Bucket_Tagging`, and
    `Delete_Bucket_Tagging`;
31. `Put_Object_Tagging`, `Get_Object_Tagging`, and
    `Delete_Object_Tagging`;
32. bounded `Get_Legal_Hold` and non-replaying `Put_Legal_Hold`;
33. bounded `Get_Retention` and non-replaying `Put_Retention`;
34. bounded `Get_Object_Lock_Configuration` and non-replaying
    `Put_Object_Lock_Configuration`.
35. bounded `Get_ACL` for a bucket access-control policy.
36. bounded `Get_ACL` for an object access-control policy.
37. bounded `Get_Metadata_Table_Configuration`.

The provider surface contains 63 domain operations: 20 in `Client.Objects`,
35 in `Client.Buckets`, and eight in `Client.Transfers`. Those operations map
to 60 prepared-request initiators in `Client.Low_Level`. The count difference
is intentional. `Put_Object`, `Put_If_Absent`, and `Put_If_Matches` are three
provider operations with distinct certainty contracts, but all three select
their condition and use the one `Client.Low_Level.Put_Object`
prepared-request initiator. `Get_Whole` and `Get_Range` are two provider
projections of the one `Client.Low_Level.Get_Object` prepared-request
initiator. Every provider operation therefore has a prepared-request
initiator; none was omitted.

GetBucketAcl follows the same bounded provider-owned read contract. Its exact
prepared initiator, limited constructor, operation-last restart, typed Finish,
and typed synchronous wait retain the signed request and complete ACL response
through terminal drain. The caller's existing XML limits bound both policy and
error payloads; diagnostic headers are physical singletons. The operation
selects no ACL policy, retry, or helper task.

GetObjectAcl is colocated with `Client.Objects` under that same contract. Its
exact prepared initiator, limited constructor, operation-last restart, typed
Finish, and typed synchronous wait preserve the caller's exact key, version,
requester-pays value, expected owner, and XML limits. The complete policy,
request-charged value, and diagnostic headers come from one bounded response;
physical headers are singletons. It performs no retry and selects no ACL,
billing, or resource policy.

GetBucketMetadataTableConfiguration is colocated with `Client.Buckets`. Its
exact prepared initiator, limited constructor, operation-last restart, typed
Finish, and typed synchronous wait retain the signed request and one bounded
response snapshot through terminal drain. The caller's XML limits bound the
configuration and structured error; opaque provider status remains text. The
operation performs no retry and introduces no metadata lifecycle policy.

Each implemented operation has both a limited constructor taking a completion
set and a same-name, operation-last procedure suitable for a reusable component
in a larger state machine. Initiation performs bounded validation and state
setup, then returns without waiting. The established overload accepts only a
fresh, released, or consumed nonterminal operation.

Each body call moves an acquired `Flyology.Buffers.Unique_Buffer` into the
operation. The public handle is vacant on successful initiation. Validation or
capacity failure either occurs before the move or restores ownership before
returning. Typed `Finish` always restores the exact pool token, length, tag,
metadata, and payload for Put. Whole and range Get also take an acquired buffer,
leaving its handle vacant; Finish restores the token. A successful read sets the
exact readable length, while every non-success restores it with zero readable
length. A response larger than the block produces a typed capacity outcome that
includes the required content length. Head has no body buffer. Its defensive
sink rejects any response-body octet exposed by the HTTP framing layer; bytes
after a complete HEAD response remain owned and policed by HTTP.
UploadPart uses the same token-move contract as Put, but its prepared multipart
identity and part number remain available to the caller for ListParts
reconciliation. The compatibility overload that accepts an arbitrary borrowed
forward-only stream remains synchronous; only the bounded owned-buffer form
can safely outlive initiation as a composable operation.
CompleteMultipartUpload serializes the caller's part manifest exactly once
during bounded initiation. The operation owns that XML and exposes it through
a non-rewindable source, so neither the composable operation nor its typed
synchronous wait can replay a possibly admitted completion.
AbortMultipartUpload supplies a non-rewindable known-empty source. The
operation can be restarted only after typed Finish consumes its prior result;
neither the composable operation nor its typed synchronous wait retries an
admitted abort.
ListObjects v1 retains its complete response under the shared S3 XML parser
limit and binds the bucket, optional prefix, delimiter, exclusive marker,
maximum, URL-encoding mode, and requester-pays response to the exact prepared
request. Explicit-present empty request fields remain distinct from omission.
Each page is an independent read-only service snapshot. The parameter-record
synchronous overload waits on the same owner-driven operation and preserves
typed HTTP failure and admission state; the convenience overload retains the
established raising transport contract and derives a logical next marker only
after typed Finish.
ListBuckets uses the same bounded owner-driven response shape at the S3
service root. Complete decoding binds the optional echoed prefix, requested or
default maximum, and any returned per-bucket region metadata to the exact
prepared filter. The opaque continuation token is copied into the operation's
signed request and never interpreted. Its parameter-record synchronous
overload waits on that same operation; the convenience overload retains its
established raising transport contract. Each bucket page is an independent
read-only service snapshot.
HeadBucket uses one owner-driven bodyless exchange and preserves every modeled
response header, HTTP admission state, and bounded failure reason. Complete
decoding rejects physical duplicates of modeled singleton headers and transfer
coding before reporting success or a bodyless rejection. Its parameter-record
synchronous overload waits on the same operation; the established convenience
overload retains its raising transport contract and signing-region fallback
when a compatible success omits the optional bucket-region header. Restart is
limited to the same HTTP client and cancellation owner. No credentials,
bucket name, owner precondition, or other borrowed request input survives
signing.
CreateBucket serializes the complete modeled configuration once during
initiation and owns those exact signed bytes through terminal drain. Its
non-rewindable source is never replayed, and neither the composable operation
nor the synchronous overload retries a possibly admitted mutation. Typed
Finish distinguishes a validated creation, modeled definite non-creation, a
pre-admission cancellation, and an outcome that requires caller-selected
HeadBucket reconciliation before any retry. Complete decoding rejects physical
duplicates, present-empty singleton metadata, invalid header text, nonempty
success bodies, and malformed or oversized error bodies. The parameter-record
synchronous overload waits on the same owner-driven operation; the convenience
overload preserves its established raising transport contract. Restart is
limited to the same HTTP client and cancellation owner, and no caller request
input remains borrowed after signing.
DeleteBucket supplies a non-rewindable known-empty source and retains its
bounded response through terminal drain. Neither the composable operation nor
the synchronous parameter-record overload replays a possibly admitted
deletion. Typed Finish distinguishes a validated 204, exact non-application,
pre-admission cancellation, and an outcome that requires caller-selected
HeadBucket reconciliation before any retry. Restart requires the same HTTP
client and cancellation owner, and no bucket name, owner precondition,
credentials, or other request input remains borrowed after signing.
GetBucketLocation owns its signed request and retains its response under the
shared S3 XML document limit. Typed Finish preserves the complete modeled
response, HTTP admission state, causal phase, and bounded failure reason. Its
parameter-record synchronous overload waits on the same owner-driven
operation; the established convenience overload keeps the legacy empty/EU
normalization and raising transport contract. This read-only operation has no
request body and relies on Flyology HTTP's bounded safe-GET stale-lease
recovery rather than adding an Object Storage retry. Restart requires the same
HTTP client and cancellation owner, and no bucket name, owner precondition,
credentials, or other request input remains borrowed after signing.
GetBucketVersioning follows the same read-only ownership discipline with the
stricter versioning-codec XML bound. Typed Finish preserves the complete
presence-sensitive configuration, HTTP admission state, causal phase, and
bounded failure reason. Its parameter-record synchronous overload waits on
the same operation, while the established convenience overload preserves its
raising transport contract. Restart requires the same HTTP client and
cancellation owner, and no bucket name, owner precondition, credentials, or
other request input remains borrowed after signing. This read does not imply
that a later PutBucketVersioning mutation is safe to replay.
PutBucketVersioning owns the exact serialized configuration, checksum/MFA and
owner headers, and signed request through terminal drain. Its synchronous and
composable forms drive the same non-rewindable source and state machine. Typed
Finish preserves admission certainty: failures after possible admission are
outcome-unknown, and no automatic mutation replay occurs. A caller may use the
paired composable GetBucketVersioning read to reconcile before selecting any
later retry. Restart is allowed only after Finish with the same HTTP client and
cancellation owner; all newly supplied inputs are copied during preparation.
GetBucketPolicy retains its exact signed owner precondition and one bounded raw
same-response policy document through terminal drain. The limited constructor,
operation-last restart, typed Finish, and typed synchronous wait use the same
provider state machine and caller-selected `Parse_Limits`. The read retains
admission information for diagnostics but does not select retry policy or imply
policy evaluation.
GetBucketPolicyStatus follows the same provider-owned read discipline with its
exact `?policyStatus` prepared operation and strict optional Boolean XML
decoder. Its limited constructor, operation-last restart, typed Finish, typed
synchronous wait, and established convenience overload drive one bounded
state machine. Physical duplicate or present-empty S3 request identifiers and
responses beyond the caller's `Parse_Limits` are rejected. This read reports
modeled policy status; it does not evaluate policy locally or authorize a
retry.
GetBucketRequestPayment likewise owns its exact `?requestPayment` prepared
operation, bounded response, and hidden HTTP exchange through typed Finish.
Its limited constructor, operation-last restart, typed synchronous wait, and
established convenience overload all drive the same state machine. The caller
selects the existing XML document limit, and Object Storage adds no retry or
billing-policy interpretation.
GetBucketAbac owns its exact `?abac` prepared operation and retains the bounded
presence-sensitive status response through typed Finish. Its limited
constructor, operation-last restart, typed synchronous wait, and established
convenience overload all drive one provider-owned state machine. Duplicate or
present-empty S3 response identifiers and responses beyond the caller's
existing XML document limit are rejected. The read selects no mutation retry
policy and retains no caller input after signing.
GetBucketAccelerateConfiguration follows that bounded read discipline with its
exact `?accelerate` prepared operation, owner precondition, requester-pays
control, presence-sensitive status, and optional modeled request-charged
response. Its limited constructor, operation-last restart, typed Finish, typed
synchronous wait, and convenience overload all drive one state machine. All
three modeled singleton response headers and the caller's existing XML
document limit are enforced; the read adds no retry or local acceleration
policy.
PutBucketAbac copies the presence-preserving serialized status document into
its signed prepared request and exposes those owned bytes once through a
non-rewindable source. Its limited constructor, operation-last restart, typed
Finish, typed synchronous wait, and established convenience overload all
drive the same provider-owned state machine. Complete response observation
proves the mutation completed; exact conclusive rejection proves
non-application; any lost, malformed, retryable, or otherwise uncertain
outcome after possible admission requires caller-selected GetBucketAbac
reconciliation. The client never replays the mutation or retains the caller's
status value.
PutBucketAccelerateConfiguration applies the same one-shot provider-owned
mutation discipline to the presence-preserving acceleration status document.
The pinned request shape does not admit Content-MD5, while its modeled checksum
algorithm and expected-owner controls remain exact. Complete response
observation proves completion; exact conclusive rejection proves
non-application; any other possibly admitted outcome requires caller-selected
GetBucketAccelerateConfiguration reconciliation. No overload replays the body
or retains the caller's status value.
PutBucketRequestPayment copies the selected payer document into its signed
prepared request and exposes those owned bytes once through a non-rewindable
source. Its limited constructor, operation-last restart, typed Finish, typed
synchronous wait, and established convenience overload all drive the same
provider-owned state machine. Complete response observation proves the
mutation completed; exact conclusive rejection proves non-application; any
lost, malformed, retryable, or otherwise uncertain outcome after possible
admission requires caller-selected GetBucketRequestPayment reconciliation.
The client never replays the mutation or retains the caller's payer value.
PutBucketPolicy copies the caller's exact bounded raw document into the signed
prepared request and exposes those owned bytes once through a non-rewindable
source. DeleteBucketPolicy uses the same provider-owned mutation discipline
with a known-empty non-rewindable source. Neither mutation is automatically
replayed after possible admission. Typed Finish distinguishes completion,
conclusive non-application, pre-admission cancellation, and outcome-unknown;
the last case requires caller-selected GetBucketPolicy reconciliation before
any retry. Their parameter-record synchronous overloads wait on these same
state machines, and restart retains only the established HTTP client and
cancellation owner.
DeleteBucketLifecycle follows the same mutation discipline with a known-empty
non-rewindable source and the exact pinned `?lifecycle` prepared operation.
Its limited constructor, operation-last reusable initiation, typed Finish, and
typed synchronous wait share one provider-owned state machine. Complete 204
proves deletion, exact conclusive service rejection proves non-application,
and any lost, malformed, retryable, or otherwise uncertain result after
possible admission remains outcome-unknown. The client never replays the
mutation; callers choose a read-only lifecycle reconciliation before any later
retry. Restart retains only the established HTTP client and cancellation
owner, and no request input remains borrowed after signing.
GetObjectLegalHold owns the exact signed generation selector and retains its
same-response XML under the shared S3 document limit. PutObjectLegalHold owns
the presence-preserving serialized XML and exposes it once through a
non-rewindable source. Both operations provide a limited constructor,
operation-last reusable initiation, typed Finish, and a synchronous overload
that waits on the same provider-owned state machine. Put typed Finish keeps
admission certainty separate from failure classification: exact modeled
rejections can prove non-application, while retryable, malformed, or lost
post-admission results remain outcome-unknown and require a caller-selected
generation-bound GetObjectLegalHold reconciliation. Neither form retains a
caller body borrow, creates a helper task, or retries the mutation.
GetObjectRetention and PutObjectRetention use the same provider-owned shape
for the selected object generation. The Get parent retains one bounded
same-response XML document and returns the exact optional mode and ISO-8601
date. The Put parent owns its presence-preserving serialized XML, exposes it
through a non-rewindable source, and never replays after possible admission.
Both provide a limited constructor, operation-last reusable initiation, typed
Finish, and a synchronous overload that waits on the identical state machine.
Put certainty distinguishes exact modeled non-application from ambiguous
post-admission failure; an unknown result requires caller-selected,
generation-bound GetObjectRetention reconciliation before any retry. Neither
operation retains request inputs or starts a helper task.
GetObjectLockConfiguration and PutObjectLockConfiguration are colocated in
`Client.Buckets` because the exact S3 resource is the bucket-only
`/{Bucket}?object-lock` target. The Get parent retains one bounded same-response
XML document and preserves every optional configuration layer. The Put parent
owns its presence-preserving serialized XML and exposes it once through a
non-rewindable source. Both provide a limited constructor, operation-last
reusable initiation, typed Finish, and a synchronous overload that waits on
the identical state machine. Put certainty distinguishes exact modeled
non-application from ambiguous post-admission failure; an unknown result
requires caller-selected GetObjectLockConfiguration reconciliation before any
retry. Neither form retains caller inputs, starts a helper task, or retries the
mutation.
SetPublicAccessBlock owns the exact serialized four-field configuration in a
non-rewindable source, while DeletePublicAccessBlock supplies a non-rewindable
known-empty source. Neither mutation is replayed after possible admission.
Typed Finish distinguishes completion, conclusive non-application,
pre-admission cancellation, and outcome-unknown; the last case requires a
caller-selected GetPublicAccessBlock reconciliation before any retry. The Get
operation retains one same-response configuration bounded by the caller's
shared XML parse limit and preserves absent configuration separately from a
present configuration with absent members. Parameter-record synchronous
overloads wait on the same owner-driven operations, and restart retains only
the established HTTP client and cancellation owner.
PutBucketTagging likewise serializes and owns its complete validated tag set
once, and DeleteBucketTagging supplies a non-rewindable known-empty source.
Neither mutation is replayed after possible admission. Their typed results
distinguish completed mutation, conclusive non-application, pre-admission
cancellation, and an outcome that requires caller-selected
GetBucketTagging reconciliation before retry. GetBucketTagging retains its
complete response under both the shared S3 XML bound and the stricter tagging
document bound. All three parameter-record synchronous overloads wait on the
same owner-driven operations; the convenience forms preserve their established
raising transport behavior. Restart requires the same HTTP client and
cancellation owner, and no request input remains borrowed after signing.
PutObjectTagging owns the exact serialized tag document prepared for signing,
while DeleteObjectTagging supplies a non-rewindable known-empty source. The
mutations are never replayed after possible admission. Their typed results
distinguish completed mutation, conclusive non-application, pre-admission
cancellation, and an outcome requiring caller-selected GetObjectTagging for
the exact selected version before any retry. GetObjectTagging retains one
response bounded by both the shared XML ceiling and the stricter tagging
document ceiling. Parameter-record synchronous overloads wait on the same
operations, and restart requires the same HTTP client and cancellation owner.
ListObjectsV2 retains a bounded response no larger than the shared XML parser
limit and binds the bucket, prefix, delimiter, opaque continuation token,
start-after key, maximum, encoding mode, and requester-pays response to the
exact prepared request. Each page is an independent read-only service
snapshot. Its parameter-record synchronous overload waits on the same
owner-driven operation and preserves typed HTTP failure and admission state.
ListObjectVersions uses the same bounded ownership model and additionally binds
the paired key/version cursor, including explicit-present empty values, the
modeled omitted-MaxKeys default, and requester-pays admission. With URL
encoding enabled, the modeled response retains the encoded key marker; callers
decode that key through `S3.Listings.Decode_URL_Value` before a later Start,
while the version identifier remains opaque and is passed through unchanged.
GetObjectAttributes retains its selected bounded REST/XML document in the same
owner-driven shape. Complete decoding rejects duplicate singleton metadata,
binds requester-pays admission, and requires an explicitly requested opaque
version identifier to be echoed exactly. Its parameter-record synchronous
overload waits on that composable operation and preserves typed HTTP failure
and admission state.
UploadPartCopy is a one-shot mutation with the same exact upload-ID and part
number reconciliation boundary as UploadPart. The operation copies the full
modeled request into its prepared signed message, supplies a non-rewindable
known-empty source, and retains a response no larger than the shared XML
parser limit. Typed Finish reports a part as published only after a complete
validated CopyPartResult, preserves an exact source-precondition rejection,
and distinguishes modeled definite non-publication. Embedded HTTP-200 errors,
malformed or oversized responses, and every failure after possible admission
remain unknown. The caller reconciles unknown results through ListParts before
any retry or completion decision.
Its parameter-record synchronous overload waits on the same owner-driven
operation, preserving HTTP phase, admission certainty, cancellation, and
one-shot behavior.

An abandoned operation first requests cancellation and drains all HTTP,
kernel, token, descriptor, source, and response leases. Only after no borrower
can reference the payload may finalization release the internally owned buffer
to its pool. No operation deliberately retains credentials or secret keys
after its terminal drain. A signed HTTP request necessarily remains an
in-flight borrow while a protocol may still send or drain it; signed headers
are not copied into results or diagnostics, and the prepared request storage
is released only after the child becomes inactive. This lifecycle release is
not a promise to zero allocator memory or transient stack copies. Required
request strings are copied into explicit bounds or are documented borrows that
remain live through typed Finish and finalization drain.

One absolute monotonic deadline begins at initiation and covers admission,
name resolution, connection establishment, TLS or QUIC, request transmission,
response parsing, and body completion. No child operation restarts it.
Cancellation follows the same drain-before-terminal rule on native and
lightweight lanes. No detached task or callback may outlive the synchronous
owner of the completion set.

## Put publication result

Put sends a complete known-length body with exactly one supported write
condition: create when absent through `If-None-Match: *`, or replace when the
caller's opaque expected generation/entity tag still matches through
`If-Match`. It performs no object-level automatic retry. Its non-raising typed
result has two independent axes. Publication disposition distinguishes:

- `Published`;
- `Precondition_Failed`;
- `Definitely_Not_Published`;
- `Outcome_Unknown`;
- `Cancelled_Before_Publication`.

A separate bounded failure reason preserves authentication, authorization,
invalid request, missing destination, cancellation, timeout, client,
connection, transport, request-source, unavailable/retryable, and
corrupt/invalid-response causes. A failure reason never substitutes for the
publication disposition.

Contract and internal-invariant violations remain exceptions. A parsed 200,
`PreconditionFailed`, or modeled authentication/authorization error is
conclusive. A 400 or 404 is conclusive only when its complete parsed S3 error
code specifically proves rejection. Cancellation, deadline expiry, transport
failure, conditional conflict, throttling, 5xx response, or malformed,
oversized, incomplete response after the request could have reached the server
retains `Outcome_Unknown`. A failure proven to precede possible server
admission is definitely unpublished (with the special cancellation spelling
where applicable). The raw HTTP transmission stage exists only as a test seam;
application code receives both semantic axes.

The success result retains the complete validated `Put_Object_Result`,
including opaque entity tag and version ID. Entity tags, checksums, and version
IDs remain separate values. A requested full-object checksum must be echoed
exactly, and a charged response is accepted only when requester-pays was
present in the exact prepared request. Malformed, unbound, or incomplete
successful headers or bodies never manufacture a successful generation.

## Get and Head results

Whole Get and exact-range Get return owned bytes plus metadata from one S3
response snapshot. Inputs include an exact version selector and entity-tag
validator. A successful result retains the opaque entity tag, version ID,
metadata and checksum fields separately. Range success additionally returns
the validated resolved interval and total representation length; unsolicited,
multipart, inverted, length-inconsistent, or otherwise malformed ranges are
invalid responses. No listing operation participates in recovery.

Object Head returns the same generation and metadata vocabulary without a body. Its
ambiguous transport outcome is not treated as proof of absence. All ordinary
service rejections are typed, and bounded diagnostic text preserves request
identifiers without retaining arbitrary response data.

Bucket Head is likewise read-only and bodyless. A complete 404 is typed as
not found, while redirect/request, authentication, authorization, and transient
service statuses retain separate bounded failure reasons. Transport failure is
not proof that the bucket is absent, and the operation never retries or changes
mutation certainty.

DeleteObject uses a deliberately non-replayable known-empty operation source.
A complete validated 204 reports `Deletion_Completed`. Exact modeled request,
authentication, authorization, missing-resource, and precondition rejections
report `Definitely_Not_Deleted`. Conflicts, throttling, service failures,
malformed responses, and every failure after possible admission report
`Deletion_Outcome_Unknown`. Pre-admission cancellation has its own spelling.

CreateMultipartUpload and UploadPart likewise use deliberately non-replayable
sources. UploadPart reports `Part_Published` only for a complete validated 200.
Definite non-admission reports `Definitely_Not_Staged`, with a separate
pre-admission cancellation spelling. Every complete rejection or failure after
possible admission reports `Part_Outcome_Unknown`; callers reconcile the exact
upload ID and part number with ListParts before any retry or completion choice.
The result retains HTTP admission certainty independently of its bounded
failure reason, and the operation never retries automatically.

CreateMultipartUpload also uses a deliberately non-replayable known-empty
source. A complete validated 200 returns the complete modeled initiation
response and reports `Multipart_Upload_Created`. Exact modeled request,
authentication, authorization, and missing-bucket rejections report
`Definitely_Not_Created`. Conflicts, throttling, service failures, malformed
responses, and every failure after possible admission report
`Creation_Outcome_Unknown`; pre-admission cancellation has a separate
spelling. A lost successful response may leave an active upload without its
identifier. The caller must therefore reconcile before retry, and must not
assume that an ordinary upload listing uniquely identifies the lost request
when concurrent indistinguishable initiations are possible.

CompleteMultipartUpload reports `Multipart_Completed` only for a complete,
validated success response. Definite non-admission reports
`Definitely_Not_Completed`, with a separate pre-admission cancellation
spelling. Every complete service rejection and every failure after possible
admission reports `Completion_Outcome_Unknown`; this includes S3 error XML
embedded in HTTP 200, because the provider can report an error after beginning
or committing completion work. The operation never retries automatically.
The caller reconciles the destination object and exact upload read-only before
choosing a later completion retry or abort; abort is cleanup, not rollback.

AbortMultipartUpload reports `Multipart_Aborted` only for a complete validated
204 response. Definite non-admission reports `Definitely_Not_Aborted`, with a
separate pre-admission cancellation spelling. Every complete service rejection
and every failure after possible admission reports `Abort_Outcome_Unknown`.
The caller reconciles the exact upload read-only before choosing any later
retry or completion action. `NoSuchUpload` is deliberately not conclusive: it
can follow this abort, a concurrent abort, or successful completion.

ListParts is the read-only multipart reconciliation primitive. Its operation
owns the prepared signed request and a response buffer bounded by the existing
S3 XML document limit, and drives one message-only HTTP exchange on the
caller's stack. Typed Finish returns either a complete modeled page or the
HTTP terminal kind, phase, admission certainty, and bounded failure detail.
Because the operation does not mutate state, it has no publication
disposition and does not authorize retries. A successful page is accepted
only when its bucket, key, upload ID, marker, and maximum echo the exact
prepared request. Restart is permitted only after typed Finish consumes the
prior terminal result, and every page remains an independent service snapshot.

ListMultipartUploads is the bounded bucket-level discovery primitive. Its
operation owns the prepared signed request and one XML-limit-bounded response
buffer, drives one message-only HTTP exchange, and exposes the same typed
terminal HTTP diagnostics as ListParts. A successful page must bind the exact
bucket, paired key/upload-ID cursor, prefix, delimiter, maximum, URL-encoding
mode, and Requester Pays admission of the prepared request. Restart is allowed
only after typed Finish, and no snapshot is promised across pages.

CopyObject is a non-replaying mutation. Its operation owns the encoded raw
source, destination, complete options record, and one XML-limit-bounded
response sink before it starts one hidden HTTP child. The request body is an
empty one-shot source rather than a rewindable adapter. Typed Finish reports
`Published` only after a complete validated result, reports exact
precondition and modeled pre-mutation rejections separately, and retains
`Outcome_Unknown` after possible admission for transport loss, invalid or
oversized responses, and embedded HTTP-200 service errors. Restart is allowed
only after Finish consumes the previous terminal result; the operation never
replays or retains borrowed request strings.

The Flyology.DB recovery sequence enabled by these operations is:

1. publish an immutable batch with `If-None-Match: *`;
2. replace `meta/HEAD` with `If-Match` on the prior opaque generation;
3. reconcile an ambiguous batch publication using generation-bound whole Get
   plus exact byte identity; and
4. reconcile an ambiguous HEAD transition using whole Get and transition
   decoding.

The sequence never retries automatically and never infers commit state from a
listing.

## Synchronous convergence

The buffer-owned `Client.Objects.Put_If_Absent`, `Put_If_Matches`, `Get_Whole`,
`Get_Range`, and `Head_Object` overloads and the typed-result `Delete` and
`Create_Multipart_Upload`, `Upload_Part`, and
`Complete_Multipart_Upload`, `Abort_Multipart_Upload`, `List_Parts_Page`, and
`List_Multipart_Uploads_Page` overloads, plus the typed-result `Copy_Object`,
`Get_Public_Access_Block`, `Get_Policy_Status`, `Get_Request_Payment`,
`Set_ABAC`, `Set_Accelerate_Configuration`, `Set_Request_Payment`,
`Get_Ownership_Controls`, and
`Set_Ownership_Controls`, `Delete_Ownership_Controls`, `Get_Encryption`,
`Set_Encryption`, `Delete_Encryption`, `Get_CORS`, `Set_CORS`, and
`Delete_CORS`, `Delete_Lifecycle` overloads, and the
`Get_Object_Lock_Configuration` and
`Put_Object_Lock_Configuration` overloads,
are literal waits on the same provider-owned state machines and retain their
typed certainty, capacity, metadata, and ownership results. The established
raising `Delete_Outcome` and
`Create_Multipart_Outcome`, older one-shot source, owned-bytes, and transfer
overloads remain source compatible.
Because they do not expose transport admission certainty, a caller treats
every mutation exception after call entry as an unknown publication outcome
and reconciles before choosing any later retry.

A conditional synchronous Put must use a one-shot type derived directly from
`Flyology.HTTP.Client.Request_Body_Source`. The stock array, string, bytes,
file, and unique-buffer adapters implement `Rewindable_Request_Body_Source`;
the conditional helpers reject them before request preparation. Using one
would opt an idempotent PUT into HTTP's guarded stale-transport replay. A
replayed request can observe the first successful conditional publication as
a later 412, so it is not an acceptable mutation source. The
native/lightweight socket corpus and the six-server implementation corpus use
a direct non-rewindable source for this reason.

The buffer-owned `Client.Objects.Get_Whole` performs reconciliation with
`If_Match` equal to the exact quoted ETag and no range, decodes the successful
head, and consumes a caller-bounded body from that same response. Its result
retains the ETag and version ID as separate opaque generation fields. The
single absolute HTTP deadline covers the complete body exchange. Head remains
useful for existence and size checks, but it is not substituted for this
same-response whole Get in recovery.

## Published HTTP dependency

The indexed HTTP client slice provides completion-set operations for request
execution and complete response consumption over HTTP/1.1, HTTP/2, and
HTTP/3. It retains the existing pool, redirect, stale-transport, cancellation,
deadline, and limited-response semantics. It also exposes a
bounded semantic observation sufficient to distinguish failure before any
possible server admission from failure after possible admission. This is not
a public wire-progress counter.

An outer object operation keeps an HTTP operation as an
established child, call `Continue_After`, consume it with typed Finish, release
its slot, and continue response-body work without blocking or moving work to a
helper task. A synthetic parent regression in HTTP must prove this lifecycle,
including parent cancellation while the child owns request or response data.

### Approved HTTP alignment

The consumer-approved HTTP PR #33 baseline supplies an absolute
`Monotonic_Deadline`, monotonic `Admission_Certainty`, bounded typed exchange
results, a set-independent nonblocking request source, immediate
response sinks, ownership-moving response buffers, and constructor plus
established `Start` forms across HTTP/1.1, HTTP/2, and HTTP/3.

The request-source contract must use a query-to-arm readiness protocol rather
than letting the source arm the visible operation itself. After `Read_Now`
reports that it needs source readiness, HTTP queries for a borrowed readiness
descriptor and `Ready_Now`. A transition between the query and the complete
operation arm must remain latched and wake that arm; a true `Ready_Now`
reschedules without arming an invalid descriptor. The previous complete arm is
disarmed before another `Read_Now` and before `Release_Source`. Source
descriptors are retained only through the applicable arm and terminal drain,
and `Release_Source` remains exactly once for every successfully attached
source.

HTTP must build one complete readiness set rather than arming source and
transport separately. Current Flyology main bounds an operation at four
readiness sources, while a streamed multiplexed exchange can simultaneously
need source, transport, connection close, protocol outbound, manager shutdown,
and caller cancellation. The prerequisite must raise the proven bound or
coalesce sources without losing their distinct wake semantics. It must never
truncate or silently omit a source when the current bound is insufficient.

The object-storage implementation uses a visible parent operation with one
hidden HTTP exchange child. Put owns its caller buffer in a detached provider
handle and presents a nonblocking source component to an HTTP sink exchange;
the sink retains only a bounded S3 error body. Get passes the caller's acquired
destination directly to the HTTP buffer exchange. Typed object Finish first
consumes and releases the hidden child, then maps the body-complete response and
restores object-level ownership invariants.

The private `Prepared_Request` message remains encapsulated. A low-level
composable bridge should start an HTTP exchange from that prepared value; the
public high-level child must not expose or duplicate signed request fields
merely to cross the sibling-package privacy boundary.

The consumer-approved PR #33 head
`686094b124338e5609fd5623ea2ac6bae5e4e3f2` is included in indexed source commit
`eb09a80a7e06274e93289861c2cae1ca7e8cb1af`. Its qualification includes the
established-child lifecycle, typed buffer restoration, admission certainty,
and owner-driven HTTP/1.1, HTTP/2, and HTTP/3 exchange behavior required by
this design. The revision adds protected bounded round-robin HTTP/2 pump
handoff and a bounded owner-driven settlement probe shared by synchronous and
composable adapters. Three complete synchronous/composable by
native/lightweight h2spec matrices pass 684/684 assertions, alongside the full
HTTP test and documentation gates. Ordinary clients retain zero settlement
grace, and the probe adds no helper task, completion slot, or second protocol
engine. Object Storage still independently gates its semantic mappings and
ownership restoration before claiming the higher-level surface.

The indexed successor also contains the qualified stale pooled-HTTP/1 repair.
Only source-free GET/HEAD bounded-buffer or response-head exchanges with no
received response bytes can replace one stale reused lease. Source-bearing and
mutation exchanges are never replayed, and the repair does not weaken request
admission certainty.

### Publication mapping oracle

The compile-independent mapping corpus at
`tests/corpora/composable-client/put-certainty.tsv` is normative for the first
Put slice. The indexed development coordinates remain exact CI inputs until a
separately qualified successor is selected. The mapping rules are:

- a complete, valid 200 response is `Published`;
- a complete 412 plus exact `PreconditionFailed` code is
  `Precondition_Failed`;
- complete, modeled authentication and authorization errors are definitely
  unpublished and retain the corresponding failure reason;
- cancellation before possible admission is
  `Cancelled_Before_Publication`;
- other failures known to precede possible admission are
  `Definitely_Not_Published`;
- cancellation, deadline, connection, transport, or request-source failure
  after possible admission is `Outcome_Unknown`;
- invalid or oversized response data, or a failed bounded response sink,
  retains `Outcome_Unknown` after possible admission and records
  `Corrupt_Or_Invalid_Response` as its reason; and
- parsed conditional conflict, throttling, and 5xx service responses retain
  `Outcome_Unknown` and record `Unavailable_Or_Retryable`. The convenience
  operation does not retry them. The caller reconciles before choosing a later
  retry.

The parallel compile-independent initiation oracle is
`tests/corpora/composable-client/create-multipart-certainty.tsv`. It gates the
complete success identity, exact conclusive S3 rejection pairs, every HTTP
terminal failure across all admission-certainty states, and the rule that an
unknown creation disposition always requires caller-selected reconciliation.
The executable normalization corpus applies the same mapping in Ada.

The completion oracle is
`tests/corpora/composable-client/complete-multipart-certainty.tsv`. Its 46
tuples gate successful completion, modeled service errors including an error
embedded in HTTP 200, and every composable HTTP terminal failure across all
admission-certainty states. Unknown completion always requires read-only
reconciliation; the verifier rejects any fixture that treats a modeled
completion rejection as proof of non-publication.

The abort oracle is
`tests/corpora/composable-client/abort-multipart-certainty.tsv`. Its 45 tuples
gate complete validated acceptance, the exact modeled rejection set, and every
composable HTTP terminal failure across all admission-certainty states.
Unknown abort state always requires exact-upload reconciliation; the verifier
rejects any fixture that treats a modeled rejection as proof that this abort
was not accepted.

ListParts response normalization is exercised directly in the Ada testing
child across modeled success and service failures, every composable HTTP
terminal failure, and all admission-certainty states. The native/lightweight
socket oracle adds pre-admission cancellation, operation restart across two
continuation pages, strict physical singleton handling, and rejection of every
wrong echoed request field. The six-server matrix uses the typed synchronous
wait over the same state machine.

ListMultipartUploads has the same direct normalization cross-product and
native/lightweight cancellation, restart, physical-singleton, Requester Pays,
paired-cursor, and exact-scope socket checks. The implementation matrix drives
its typed synchronous wait across every positive provider lane.

CopyObject response normalization is exercised directly across exact modeled
success and rejection pairs, embedded HTTP-200 errors, inconsistent admission
certainty, and every composable HTTP terminal failure across all admission
states. Native/lightweight sockets gate pre-admission cancellation, restart,
physical singleton headers, Requester Pays binding, and full modeled success.
The six-server matrix drives the typed synchronous wait over the same state
machine and treats SeaweedFS's malformed post-publication ETag as unknown while
an independent whole-object read proves which bytes were published.

The sibling `range-get.tsv` and `head-object.tsv` corpora are normative for the
read surface. They enumerate typed request forms, physical singleton handling,
same-response range binding, bodylessness, capacity, cancellation, restart,
abandonment, and native/lightweight transport behavior. Their verifier rejects
missing mandatory lanes, duplicate case identities, malformed schemas, and an
unexpectedly narrow corpus before the Ada socket tests run.

`Response_Observed` alone is not a conclusive publication result. Only a
complete response whose status and modeled fields validate can establish one
of the conclusive service outcomes. The raw driver phase is diagnostic test
input and cannot make admission certainty move backward.

## Qualification matrix

Every row below is required before the first scoped operation is documented as
available. A narrow green smoke test does not promote the feature.

| Area | Required cases | Required evidence |
| --- | --- | --- |
| Initiation | immediate completion; delayed admission; invalid origin, request, condition, or capacity; occupied/vacant wrong buffer state | bounded Start; invalid Start does not move ownership; no completion slot leak |
| Ownership | Put success, every typed failure, cancellation, deadline, source failure, and abandon; Get success, rejection, too-small destination, and abandon | exact token/tag/metadata restoration; Put bytes and length unchanged; failed Get length zero; pool outstanding count returns to baseline |
| Gates | operation already terminal before gate construction; delayed member; `Wait_Some`, `Wait_All`, success and impossible-success gates; two competing gates observing one member | exact terminal identities and outcomes; no double Finish; generation-stale references rejected |
| Parent composition | established HTTP child in a synthetic object parent; `Continue_After`; typed Finish and Release; parent restart | owner-stack-only drive; hidden child absent from user batch; reusable slots after every terminal path |
| Conditions | create-if-absent win and collision; replace-if-generation win; stale and missing `If-Match`; malformed validators | exact signed headers; parsed 412 maps only to `Precondition_Failed`; one winner under concurrent races |
| Publication certainty | validation failure; pre-admission cancellation/deadline/connect failure; post-admission cancellation/deadline; accepted request with lost response; malformed 200; parsed auth and 412; 429 and 5xx | exact typed class; no automatic object retry; raw admission stage visible only to tests |
| Put body | empty, one byte, block limit, checksum/signature corpus, source exception at every chunk boundary, zero progress, early EOF, declared-length overrun | server never exposes a partial replacement; prior object and generation unchanged on incomplete body |
| Source readiness | ready during query-to-arm window; `Ready_Now`; read/write direction; simultaneous source, transport, close, outbound, shutdown, and cancellation; cancel/finalize while armed | readiness remains latched; complete arm is disarmed before `Read_Now` or `Release_Source`; no source is dropped at the fan-in bound; descriptor borrow ends after drain |
| Whole Get | empty, one byte, block limit, missing object, exact version, matching and stale entity tag, malformed/multiple length and checksum fields | bytes and metadata share one response; exact ETag/version/checksum separation; no partial success |
| Range Get | first, middle, final, one-byte, full-span, suffix/open-ended request as applicable, unsatisfied, unsolicited 206, malformed and multipart ranges | exact resolved interval and total length; body length equals interval; generation-bound validator retained |
| Head | found, absent, exact version, matching/stale condition, malformed success metadata, bodyful HEAD error | same typed metadata vocabulary; no body lease; ambiguity never implies absence |
| Delete | versioned success, exact precondition rejection, conflict, malformed singleton headers, cancellation, deadline, and every HTTP admission class | non-replayable empty source; exact typed deletion certainty; ambiguous outcomes require reconciliation |
| Protocol/lane | HTTP/1.1, HTTP/2, HTTP/3; native and lightweight owner tasks; pooled and fresh connections | identical semantic outcomes and deadlines; bounded protocol storage; no retained stream/transport lease |
| Multi-object DB flow | concurrent immutable batch puts; one CAS winner for `meta/HEAD`; one unrelated wait wins first; ambiguous batch and HEAD recovery | ordinary Flyology gate composition; exact input order where promised; reconciliation by exact whole Get, never listing |
| Cleanup stress | cancel or finalize at every deterministic driver phase; client shutdown race; completion-set capacity reuse; repeated 10,000-operation campaign | zero live operation, buffer, token, response, stream, descriptor, admission waiter, and pool-accounting drift |
| Backends/oracles | authenticated Flyology memory, files, and SQLite S3 servers; pinned Apache-2.0 RustFS and SeaweedFS where their documented behavior supports the case; supplemental pinned MinIO only under its existing AGPL test policy | three repeated native/lightweight socket runs; implementation differences recorded as exact exclusions, never weakened assertions |

The implementation gate is the complete root test script, SQLite test script,
strict socket/application corpora, the repeated S3 matrix, documentation, and
an independent P1 review/fix cycle. Scheduling and deterministic state-machine
changes additionally require the serialized proof gate after functional
qualification and explicit authorization.
