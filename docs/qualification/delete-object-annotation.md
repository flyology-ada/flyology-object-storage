# DeleteObjectAnnotation client qualification

This record qualifies the strict low-level request boundary, provider-owned
composable operation, typed synchronous wait, and corpus for
`DeleteObjectAnnotation`. The separately maintained
[backend and server evidence](object-annotations-backend-server.md) records
the shared Flyology persistence and authenticated route. External-provider
annotation interoperability remains outside both records.

## Pinned authority and inventory

The machine inventory is tied to botocore S3 model revision
`36c34f15391da01cd717c73c0fffa747c9889768` and service-model SHA-256
`429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
The exact operation is DELETE to `/{Bucket}/{Key+}?annotation`, has exact
success status 204, input shape 167, and output shape 166. It has no request
checksum requirement or checksum-algorithm member.

The input graph contains required `Bucket`, `Key`, and `AnnotationName`, plus
optional `VersionId`, `RequestPayer`, `ExpectedBucketOwner`, and
`ObjectIfMatch`. The output graph contains optional `ObjectVersionId` and
`RequestCharged` response headers. `RequestPayer` and `RequestCharged` each
admit only the exact `requester` token. The key has a one-byte minimum; the
annotation name, version, owner, and object-CAS token are opaque strings with
no model-selected length ceiling or pattern.

The reciprocal ledgers contain all nine members and 12 request, response, and
transport contracts. The verifier gates the operation scalars, complete member
graphs and wire locations, scalar constraints, exact enums, implementation
surface, and reciprocal vector reachability:

```sh
python3 tools/verify-delete-object-annotation-preparation.py
```

## Provider-owned API and admission contract

`Client.Low_Level.Prepare_Delete_Object_Annotation` validates the bucket and
the complete pinned model before transport, preserves the greedy object key,
projects the required annotation name and optional version into the canonical
query, signs every optional physical header, and emits an empty payload with
the established SHA-256 digest. A present empty annotation name is distinct
from omission and remains valid because its pinned shape has no minimum.

`Execute_Delete_Object_Annotation` accepts only a prepared request bound to
that exact modeled operation. It uses `Non_Replayable_Empty_Source`, so the
HTTP engine cannot transparently resubmit a conditional mutation after stale
connection admission. There is no helper task, retained borrowed input,
second protocol engine, or automatic retry.

`Client.Low_Level.Delete_Object_Annotation` starts that exact prepared request
with a caller-owned non-rewindable empty source and bounded response sink. It
rejects any other modeled operation before HTTP admission.

`Client.Objects.Delete_Annotation` owns the complete provider vocabulary: a
limited constructor, same-name operation-last restart, typed `Finish`, and a
typed synchronous overload that waits on the same state machine. Preparation
copies the annotation name plus exact version, requester-pays, expected-owner,
and object-CAS values before initiation returns. The operation retains no
caller string or credential borrow, creates no helper task, and never retries
the mutation.

Exact 204 with an exactly empty body is typed deletion success. Every other
status is a strict bounded S3 error. The decoder admits at most one nonempty
physical value for each modeled or diagnostic response header, validates the
exact requester enum and bounded header text, and fails closed on unmodeled
success content. HTTP framing can reject an illegal body on a 204 response
before the operation decoder; that protocol exception is also fail-closed.

The typed provider result preserves HTTP admission certainty independently of
the failure reason. Exact 204 proves completion. Exact conclusive rejection or
non-admission proves the requested deletion was not applied. A retryable,
unknown, malformed, oversized, or post-admission transport outcome is
`Annotation_Deletion_Outcome_Unknown`. Callers must reconcile read-only using
the exact object and generation evidence appropriate to their annotation
contract and must not automatically retry the conditional deletion.

## Corpus and coverage boundary

The deterministic corpus covers both addressing styles, greedy key and query
encoding, empty annotation presence, all optional projections together,
one-byte and empty keys, invalid buckets, requester enum variants, unsafe
header controls, exact success, alternate success and representative error
statuses, exact diagnostics, modeled response headers, malformed responses,
exact and one-past XML limits, and cross-operation rejection before admission.

The common raw loopback sequence adds exact signed DELETE method, target,
requester, owner, version, and object-CAS projection; typed success and
structured rejection; a forbidden success body; duplicate and empty modeled
headers; duplicate diagnostics; and a response one byte above a
caller-selected ceiling. Provider coverage adds typed synchronous rejection,
composed success, restart after Finish, mutation of every caller input after
initiation, a bounded exchange failure, and exact prepared-operation rejection.
The normalization oracle covers every maintained response pair, every
non-observed admission state, and every expected HTTP failure across all
admission certainties. The root gate drives the same socket sequence under
native and Flyology lightweight task owners.

The machine ledger records the operation as `covered / covered / covered /
covered`. The client evidence in this record remains independently scoped;
the shared backend/server record pins persistence, routing, and cross-backend
evidence without treating one operation's lane as proof for another.

## Formal boundary

This slice changes only non-SPARK client, corpus, and documentation units. None
of the nine `tools/prove.sh` manifest units changes, so the latest serialized
result remains applicable: 936/936 checks, 180 flow and 756 prover,
with zero warnings, unproved or justified checks, or `pragma Assume`
statements.

## Gate evidence

The root gate passed all 41 AUnit cases, the 132-case abrupt-crash matrix, the
320-vector checksum corpus with 210 chunk boundaries, and three complete
deterministic, native/lightweight signed raw-socket, and TLS repetitions. The
focused provider/socket rerun also passed. The SQLite binding and backend were
unchanged, so their separate gate was not required for this client-only slice.

The operation verifier reported all nine modeled members and all 12 reciprocal
vectors, including the new Low_Level and provider-owned surface. The
116-operation coverage verifier and its negative mutation oracle were green.
The repository integrity gate passed dependency, script, workflow, conflict,
whitespace, Markdown-link, lock, coverage, and generated-corpus checks.

GNATdoc produced a nonempty API index and a 44,022-line diagnostic log. The
index contains the provider operation, result, constructor, restart, Finish,
and synchronous wait declarations. Those declarations emitted no targeted
warning; the sole exact operation-name warning is the preexisting generated
model enumeration. The log contains no internal error,
`LANGKIT_SUPPORT.ERRORS`, infinite-recursion, or bounded-channel diagnostic.

Backend/server promotion remains conditional on the shared verifier and every
command in the `delete_object_annotation` lane succeeding. The historical
client result above does not by itself qualify the newly added backend/server
surface or external-provider behavior.
