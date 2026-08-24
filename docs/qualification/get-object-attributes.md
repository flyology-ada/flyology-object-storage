# GetObjectAttributes qualification and boundaries

This slice qualifies `GetObjectAttributes` across the backend, typed client,
authenticated general-purpose path-style server, and implementation corpus.
Directory buckets, configured Requester Pays accounting, SSE-C object state,
and retained exact generations in the pure-files backend remain explicit
capability exclusions.

## Request and admission

The pinned request has 11 modeled members: bucket, key, version ID, maximum
parts, part-number marker, the three SSE-C headers, requester payer, expected
bucket owner, and the required attribute-selection header. Authentication and
body rejection precede semantic parsing. The server then requires one bounded
selection, validates the optional part-page controls, enforces expected owner,
and admits only the exact `requester` billing token.

The SSE-C fields form one indivisible group. Duplicate or incomplete fields are
`InvalidRequest`; the algorithm must be `AES256`; the request must use HTTPS;
and the Base64 key must match its supplied MD5. The key is borrowed only for
that check and is never retained or logged. A valid secure group receives
authenticated `NotImplemented` because encrypted multipart initiation state is
not represented. Other encryption controls also fail explicitly. No policy
failure observes object or multipart state.

## Atomic selected snapshot

The backend returns object metadata and one bounded completed-part page from a
single immutable selected generation. Current and explicit null selectors are
supported by memory, files, and SQLite. Memory and SQLite also select opaque
retained generations; files returns its typed capability result for an opaque
exact selector. SQLite persists part rows and checksum metadata with the
retained object generation and reopens them under the object foreign key.

The response projects only requested attributes. ETag, object size, checksum,
storage class, and `ObjectParts` pagination are derived from the same snapshot.
Unavailable optional attributes are omitted rather than invented. The bounded
codec rejects duplicate or misplaced fields, mixed checksum algorithms,
invalid algorithm/type pairs, malformed Base64, overflowing counts, and stale
or inconsistent part pagination.

## Adversarial evidence

The signed in-process corpus covers missing and duplicate selection, request
bodies, maximum and marker bounds, matching and mismatched owner, empty and
duplicate owner, valid/invalid/duplicate payer, incomplete and duplicate SSE-C
groups, invalid algorithms, malformed keys, mismatched digests, plaintext
SSE-C, valid unsupported HTTPS, unrelated encryption headers, and a combined
bad-signature precedence request. Multipart fixtures require exact object and
part checksums from the same completed snapshot.

The fragmented native/lightweight socket corpus checks typed and convenience
clients, selected version encoding, response identity, structured errors, and
bounded parsing. The implementation corpus repeats current-object and
completed-multipart behavior against RustFS, SeaweedFS, and Flyology memory,
files, and SQLite; narrow pinned external response divergences remain explicit
and do not weaken the production decoder.

## Gates

The qualified source passes the 40/40 AUnit root suite, the 88-case files crash
matrix, 320 checksum vectors, 210 chunk boundaries, the 64-GiB CRC
linearization oracle, signed server/application/socket/TLS corpora, the SQLite
backend suite, the 116-operation coverage verifier and negative oracle, and
GNATdoc generation. The server admission change is outside the SPARK manifest
and changes no public API, pagination algorithm, multipart state machine, or
scheduling boundary.
