# Composable object client operations

This note records the implemented contract for the completion-set-aware object
client slice: conditional complete-object Put, generation-bound whole and
single-range Get, bodyless Head, non-replaying Delete, and non-replaying
multipart initiation. The prerequisite is published through the Flyology
Alire index as lockstep HTTP and QUIC 0.1.3 development crates.

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
`a65f24f473bd771356a4fcb355fc10f961202534`. The Object Storage implementation
uses those exchanges directly; it does not simulate composition with a helper
task or a retained borrowed source, and no committed dependency pin remains.

## Intended public boundary

The additive child package is
`Flyology.Object_Storage.Client.Scoped`. Existing synchronous low-level,
object, and transfer calls remain source compatible. Ordinary
`Flyology.Operations.Reference` values and gates compose these operations;
the object-storage API does not define a competing scheduler or gate type.

The initial operation order is:

1. conditional complete `Put_Object`;
2. whole `Get_Object`;
3. generation-bound exact-range `Get_Object`;
4. `Head_Object`; and
5. `Delete_Object`; and
6. `Create_Multipart_Upload`.

Each implemented operation has both a limited constructor taking a completion
set and an established-operation `Start` overload suitable for a reusable
component in a larger state machine. Initiation performs bounded validation and
state setup, then returns without waiting. The established overload accepts
only a fresh, released, or consumed nonterminal operation.

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

An abandoned operation first requests cancellation and drains all HTTP,
kernel, token, descriptor, source, and response leases. Only after no borrower
can reference the payload may finalization release the internally owned buffer
to its pool. No operation retains credentials or secret keys. A signed HTTP
request necessarily remains an in-flight borrow while a protocol may still
send or drain it; signed headers are not copied into results or diagnostics and
are released at terminal completion. Required request strings are copied into
explicit bounds or are documented borrows that remain live through typed
Finish and finalization drain.

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
IDs remain separate values. Malformed successful headers or bodies never
manufacture a successful generation.

## Get and Head results

Whole Get and exact-range Get return owned bytes plus metadata from one S3
response snapshot. Inputs include an exact version selector and entity-tag
validator. A successful result retains the opaque entity tag, version ID,
metadata and checksum fields separately. Range success additionally returns
the validated resolved interval and total representation length; unsolicited,
multipart, inverted, length-inconsistent, or otherwise malformed ranges are
invalid responses. No listing operation participates in recovery.

Head returns the same generation and metadata vocabulary without a body. Its
ambiguous transport outcome is not treated as proof of absence. All ordinary
service rejections are typed, and bounded diagnostic text preserves request
identifiers without retaining arbitrary response data.

DeleteObject uses a deliberately non-replayable known-empty operation source.
A complete validated 204 reports `Deletion_Completed`. Exact modeled request,
authentication, authorization, missing-resource, and precondition rejections
report `Definitely_Not_Deleted`. Conflicts, throttling, service failures,
malformed responses, and every failure after possible admission report
`Deletion_Outcome_Unknown`. Pre-admission cancellation has its own spelling.
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
`Create_Multipart_Upload` overloads are literal waits on the same
`Client.Scoped` state machines and retain their typed certainty, capacity,
metadata, and ownership results. The established raising `Delete_Outcome` and
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

The private `Prepared_Request` message remains encapsulated. A low-level scoped
bridge should start an HTTP exchange from that prepared value; the public
high-level child must not expose or duplicate signed request fields merely to
cross the sibling-package privacy boundary.

The consumer-approved PR #33 head
`686094b124338e5609fd5623ea2ac6bae5e4e3f2` merged into indexed source commit
`a65f24f473bd771356a4fcb355fc10f961202534`. Its qualification includes the
established-child lifecycle, typed buffer restoration, admission certainty,
and owner-driven HTTP/1.1, HTTP/2, and HTTP/3 exchange behavior required by
this design. The revision adds protected bounded round-robin HTTP/2 pump
handoff and a bounded owner-driven settlement probe shared by synchronous and
scoped adapters. Three complete sync/scoped by native/lightweight h2spec
matrices pass 684/684 assertions, alongside the full HTTP test and
documentation gates. Ordinary clients retain zero settlement grace, and the
probe adds no helper task, completion slot, or second protocol engine. Object
Storage still independently gates its semantic mappings and ownership
restoration before claiming the higher-level surface.

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
