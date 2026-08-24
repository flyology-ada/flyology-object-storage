# Object-tagging qualification and boundaries

This slice qualifies the authenticated general-purpose path-style server for
`PutObjectTagging`, `GetObjectTagging`, and `DeleteObjectTagging`. Configured
Requester Pays accounting and SDK checksum execution remain explicit typed
capability exclusions. Directory-bucket-specific behavior is not claimed.

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

The qualified source passes the 40/40 AUnit root suite, 88 abrupt files-crash
cases, 320 checksum vectors, 210 chunk boundaries, the 64-GiB CRC linearization
oracle, signed server/application/socket/TLS corpora, the SQLite backend suite,
the 116-operation coverage verifier and negative oracle, and GNATdoc generation.
The admission repair is outside the SPARK manifest and changes no public API,
backend state model, pagination algorithm, or scheduling boundary.
