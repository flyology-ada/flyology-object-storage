# Object-tagging qualification and boundaries

This record defines the reviewed evidence boundary for the authenticated
general-purpose path-style server and composable client for
`PutObjectTagging`, `GetObjectTagging`, and `DeleteObjectTagging`. Each
operation is qualified only when its complete registered lane succeeds.
Configured Requester Pays accounting and SDK checksum execution remain
explicit typed server capability exclusions. Directory-bucket-specific
behavior is not claimed.

The committed source and retained API site currently establish only a
region-scoped documentation measurement: the 155 candidate-owned Low_Level
and Objects warnings are absent with no added warning. Repository-wide and
selected-operation qualification remain blocked by unrelated pre-existing
Buckets specification warnings. This record does not convert that measurement
into a qualification claim.

## Admission and atomicity

Authentication and route body policy precede tagging semantics. All three
operations reject duplicate owner, payer, and SDK checksum-algorithm controls;
expected-owner matching uses the authenticated principal; requester payer
accepts only the exact `requester` token; and SDK checksum algorithm names must
belong to the ten modeled algorithms. Valid requester and SDK-checksum controls
receive `NotImplemented` before storage because their configured execution state
is not represented. Invalid or empty tokens receive typed client errors instead.

PutObjectTagging requires a known body length no greater than the public
16 KiB tagging document ceiling, exactly one Content-MD5 over the received XML,
and an optional XML content type. The bound is inclusive. Digest, size, content
type, payload hash, and strict XML validation all complete before the backend
can replace the tag set. Rejected Put or Delete controls leave the previous set
unchanged.

The backend replaces, reads, or clears the entire tag set atomically with the
selected immutable object generation. Current and explicit null selectors work
on memory, files, and SQLite. Memory and SQLite also select retained opaque
generations; pure files reports its typed exclusion for an opaque exact
selector. Responses publish only the selected generation identity.

## Bounded XML and query model

The entity-safe XML parser permits at most ten unique tags, preserves wire
order, enforces AWS Unicode code-point limits and repertoire rules, and rejects
DTDs, unknown structure, duplicate structure, or excess depth/elements/text.
Query parsing is bounded, percent-decodes version IDs, and rejects unknown,
duplicate, or mismatched SDK operation controls. Bodies on Get and Delete are
rejected by the sealed route before tagging state is observed.

## Adversarial evidence

The signed in-process corpus covers a valid lifecycle, exact-limit and one-past
bodies, missing/duplicate/mismatched Content-MD5, malformed XML with a matching
digest, invalid content type, unknown/duplicate query controls, null and opaque
generation routing, missing buckets and keys, and body rejection. A three-method
matrix repeats invalid/empty/duplicate/valid payer, invalid/duplicate/valid SDK
checksum algorithm, empty/duplicate owner, and corrupt-signature precedence for
Put, Get, and Delete, then proves every rejected mutation preserved the prior
tag set.

The native/lightweight socket and implementation corpora exercise typed and
convenience clients against RustFS, SeaweedFS, supplemental MinIO, and Flyology
memory, files, and SQLite. Retained-generation isolation and SQLite reopen are
also black-box gated.

## Composable client

The `Client.Objects` provider exposes operation-specific Put, Get, and
Delete operations. Put serializes and owns the exact signed tag document once;
Delete owns a known-empty non-rewindable source; neither mutation can be
replayed. Get retains a complete response bounded by both the shared XML limit
and the stricter tagging-document limit. Exact version selection is retained in
the signed request, and successful responses preserve the selected
`x-amz-version-id` from that same exchange.

Typed mutation results report completion only for a validated modeled response.
Exact service rejection or HTTP non-admission can prove non-application;
possible admission, malformed or lost responses, and retryable service results
remain unknown and require caller-selected GetObjectTagging reconciliation for
the exact version before any retry. Parameter-record `Client.Objects`
overloads wait on these operations, while the convenience overloads retain
their established raising transport behavior.

The direct normalization corpus crosses every typed HTTP failure with every
admission state and covers exact completed, conclusive, retryable, and
mismatched service responses. The native/lightweight socket corpus drives all
three operations directly, verifies same-owner restart, fragmented bounded
reads, exact returned version identities, cancellation and deadline handling,
and the convenience wrappers through the same state machines.

Each operation-specific lane requires the dedicated preparation verifier, the
composable certainty fixture and its negative self-test, the warning-strict
test build and socket corpus, the 116-operation coverage verifier, selected
API documentation, the repository gate, and a clean diff. The retained root
wrapper is green, including 41/41 AUnit tests, the files crash matrix, checksum
and chunk-boundary oracles, and signed server/application/socket corpora. The
composable addition changes no backend state model or pagination boundary.
Those retained results remain evidence only until every registered lane,
including the repository-wide documentation classifier, succeeds.
