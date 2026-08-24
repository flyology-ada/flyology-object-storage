# DeleteObjectAnnotation client qualification

This record qualifies the strict synchronous low-level client and corpus for
`DeleteObjectAnnotation`. It does not claim annotation persistence in a
Flyology backend, an authenticated Flyology server route, or external provider
interoperability.

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

## Synchronous API and admission contract

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

Exact 204 with an exactly empty body is typed deletion success. Every other
status is a strict bounded S3 error. The decoder admits at most one nonempty
physical value for each modeled or diagnostic response header, validates the
exact requester enum and bounded header text, and fails closed on unmodeled
success content. HTTP framing can reject an illegal body on a 204 response
before the operation decoder; that protocol exception is also fail-closed.

Any exception after entry into the blocking provider call leaves the mutation
outcome unknown. Callers must reconcile read-only using the exact object and
generation evidence appropriate to their annotation contract and must not
automatically retry the conditional deletion.

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
headers; duplicate diagnostics; and a response one byte above a caller-selected
ceiling. The root gate drives that same sequence under native and Flyology
lightweight task owners.

The machine ledger records the operation as `missing / covered / missing /
covered`. Client and corpus qualification do not manufacture backend state or
a server route; those require separate persistence, routing, and independent
black-box evidence.

## Formal boundary

This slice changes only non-SPARK client, corpus, and documentation units. None
of the nine `tools/prove.sh` manifest units changes, so the latest serialized
2026-08-24 result remains applicable: 936/936 checks, 180 flow and 756 prover,
with zero warnings, unproved or justified checks, or `pragma Assume`
statements.

## Gate evidence

The root gate passed all 40 AUnit cases, the 88-case abrupt-crash matrix, the
320-vector checksum corpus with 210 chunk boundaries, and three complete
deterministic, native/lightweight signed raw-socket, and TLS repetitions. The
SQLite wrapper, catalog, and backend gate also passed.

The operation verifier reported all nine modeled members and all 12 reciprocal
vectors. The 116-operation coverage verifier and its negative mutation oracle
were green.

GNATdoc produced a nonempty API index and a 12,461-line diagnostic log. The
index contains the parameter, result, outcome, prepare, decode, and execute
declarations; those declarations emitted no targeted warning, and the log
contains no internal error, `LANGKIT_SUPPORT.ERRORS`, infinite-recursion, or
bounded-channel diagnostic.
