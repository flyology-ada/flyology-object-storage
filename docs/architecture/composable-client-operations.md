# Composable object client operations

This note records the contract for the first completion-set-aware convenience
client slice. It is a design and qualification boundary, not a claim that the
API is implemented. Production declarations remain deferred until the matching
Flyology HTTP client operation API is merged, released, and available through
the Flyology Alire index.

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

Flyology HTTP main at
`f4fd9c3ee5c4cb52a046b0b124a8bbf705a34871` contains composable server
request-head and request-body operations. Its public client still exposes only
blocking `Execute`, `Read_Body`, and `Read_All`. The indexed
`flyology_http=0.1.2` source at
`8f34e73b49b1f6b61e3f4a86a56fe2650d0ff1ca` also depends on
`flyology=0.1.0`, before completion sets existed. A genuine object client
operation therefore requires the separate HTTP client-operation prerequisite;
it must not be simulated with a helper task or a retained borrowed source.

## Intended public boundary

The additive child package is
`Flyology.Object_Storage.Client.Scoped`. Existing synchronous low-level,
object, and transfer calls remain source compatible. Ordinary
`Flyology.Operations.Reference` values and gates compose these operations;
the object-storage API does not define a competing scheduler or gate type.

The initial operation order is:

1. conditional complete `Put_Object`;
2. whole `Get_Object`;
3. generation-bound exact-range `Get_Object`; and
4. `Head_Object`.

Each operation has both a limited constructor taking a completion set and an
established-operation `Start` overload suitable for a reusable component in a
larger state machine. Initiation performs bounded validation and state setup,
then returns without waiting. The established overload accepts only a fresh,
released, or consumed nonterminal operation.

Each body call moves an acquired `Flyology.Buffers.Unique_Buffer` into the
operation. The public handle is vacant on successful initiation. Validation or
capacity failure either occurs before the move or restores ownership before
returning. Typed `Finish` always restores the exact pool token, length, tag,
metadata, and payload for Put. Get also takes an acquired buffer, leaving its
handle vacant; Finish restores the token. A successful read sets the exact
readable length, while every non-success restores it with zero readable
length. A response larger than the block produces a typed capacity outcome
that includes the required content length.

An abandoned operation first requests cancellation and drains all HTTP,
kernel, token, descriptor, source, and response leases. Only after no borrower
can reference the payload may finalization release the internally owned buffer
to its pool. No operation retains credentials, secret keys, signed headers, or
unbounded raw error text. Required request strings are copied into explicit
bounds or are documented borrows that remain live through typed Finish and
finalization drain.

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
result distinguishes:

- `Published`;
- `Precondition_Failed`;
- `Definitely_Not_Published`;
- `Outcome_Unknown`;
- `Cancelled_Before_Publication`;
- `Auth_Or_Authorization_Failed`;
- `Unavailable_Or_Retryable`; and
- `Corrupt_Or_Invalid_Response`.

Contract and internal-invariant violations remain exceptions. A parsed 200,
412, or authentication/authorization rejection is conclusive. Cancellation,
deadline expiry, or transport failure after the request could have reached the
server is `Outcome_Unknown`, including local cancellation. A failure proven to
precede possible server admission is definitely unpublished (with the
special cancellation spelling where applicable). The raw HTTP transmission
stage exists only as a test seam; application code receives the semantic
classification.

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

The Flyology.DB recovery sequence enabled by these operations is:

1. publish an immutable batch with `If-None-Match: *`;
2. replace `meta/HEAD` with `If-Match` on the prior opaque generation;
3. reconcile an ambiguous batch publication using generation-bound whole Get
   plus exact byte identity; and
4. reconcile an ambiguous HEAD transition using whole Get and transition
   decoding.

The sequence never retries automatically and never infers commit state from a
listing.

## HTTP prerequisite

The HTTP client slice must provide completion-set operations for request
execution and complete response consumption over HTTP/1.1, HTTP/2, and
HTTP/3. It must retain the existing pool, redirect, stale-transport,
cancellation, deadline, and limited-response semantics. It must also expose a
bounded semantic observation sufficient to distinguish failure before any
possible server admission from failure after possible admission. This is not
a public wire-progress counter.

An outer object operation must be able to keep an HTTP operation as an
established child, call `Continue_After`, consume it with typed Finish, release
its slot, and continue response-body work without blocking or moving work to a
helper task. A synthetic parent regression in HTTP must prove this lifecycle,
including parent cancellation while the child owns request or response data.

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
| Whole Get | empty, one byte, block limit, missing object, exact version, matching and stale entity tag, malformed/multiple length and checksum fields | bytes and metadata share one response; exact ETag/version/checksum separation; no partial success |
| Range Get | first, middle, final, one-byte, full-span, suffix/open-ended request as applicable, unsatisfied, unsolicited 206, malformed and multipart ranges | exact resolved interval and total length; body length equals interval; generation-bound validator retained |
| Head | found, absent, exact version, matching/stale condition, malformed success metadata, bodyful HEAD error | same typed metadata vocabulary; no body lease; ambiguity never implies absence |
| Protocol/lane | HTTP/1.1, HTTP/2, HTTP/3; native and lightweight owner tasks; pooled and fresh connections | identical semantic outcomes and deadlines; bounded protocol storage; no retained stream/transport lease |
| Multi-object DB flow | concurrent immutable batch puts; one CAS winner for `meta/HEAD`; one unrelated wait wins first; ambiguous batch and HEAD recovery | ordinary Flyology gate composition; exact input order where promised; reconciliation by exact whole Get, never listing |
| Cleanup stress | cancel or finalize at every deterministic driver phase; client shutdown race; completion-set capacity reuse; repeated 10,000-operation campaign | zero live operation, buffer, token, response, stream, descriptor, admission waiter, and pool-accounting drift |
| Backends/oracles | authenticated Flyology memory, files, and SQLite S3 servers; pinned Apache-2.0 RustFS and SeaweedFS where their documented behavior supports the case; supplemental pinned MinIO only under its existing AGPL test policy | three repeated native/lightweight socket runs; implementation differences recorded as exact exclusions, never weakened assertions |

The implementation gate is the complete root test script, SQLite test script,
strict socket/application corpora, the repeated S3 matrix, documentation, and
an independent P1 review/fix cycle. Scheduling and deterministic state-machine
changes additionally require the serialized proof gate after functional
qualification and explicit authorization.
