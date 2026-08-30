# GetObjectAttributes qualification and boundaries

Qualification remains conditional on the complete `get_object_attributes`
lane succeeding. The committed runtime and evidence cover the backend, typed
client, authenticated general-purpose path-style server, and implementation
corpus; they do not replace a clean current qualification run.

Directory buckets, configured SSE-C object state, access-point, Object Lambda,
and S3 on Outposts routing remain explicit capability exclusions. External
provider behavior beyond the maintained signed implementation and socket
corpus is not claimed.

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
Unavailable optional attributes are omitted rather than invented. An explicit
nonempty `VersionId` must be echoed exactly; omission observes the generation
current at read time. Neither observation proves the cause of a prior mutation,
authorizes automatic replay, or upgrades mutation certainty.

Prepared requests retain the exact selected attribute groups, optional-control
presence, and values. A returned parts page must echo the explicit controls or
their modeled defaults of marker zero and maximum 1000. An explicitly present
`MaxParts=0` yields an empty terminal page while retaining the total count. The
bounded codec rejects duplicate or misplaced fields, mixed checksum algorithms,
invalid algorithm/type pairs, malformed Base64, overflowing counts, unrequested
groups, and stale or inconsistent pagination. Checksum values are structurally
validated and exposed but are not recomputed by this client slice.

## Adversarial evidence

The signed in-process corpus covers missing and duplicate selection, request
bodies, maximum and marker bounds, matching and mismatched owner, empty and
duplicate owner, valid/invalid/duplicate payer, incomplete and duplicate SSE-C
groups, invalid algorithms, malformed keys, mismatched digests, plaintext
SSE-C, valid unsupported HTTPS, unrelated encryption headers, and a combined
bad-signature precedence request. Multipart fixtures require exact object and
part checksums from the same completed snapshot.

The fragmented native/lightweight socket corpus checks typed and convenience
clients, selected version encoding, response identity, structured errors,
explicit-zero and omitted-default pagination binding, admitted cancellation,
typed drain and `Finish`, retained-owner substitution rejection, same-object
restart, and bounded parsing. The implementation corpus repeats current-object
and completed-multipart behavior against RustFS, SeaweedFS, and Flyology
memory, files, and SQLite; narrow pinned external response divergences remain
explicit and do not weaken the production decoder.

## Gates

The maintained focused command is:

```sh
FLYOLOGY_S3_SERVICE_MODEL=/path/to/service-2.json \
  UV_CACHE_DIR=/path/to/uv-cache \
  uv run --python 3.13 -- \
  tools/s3-operation.py qualify GetObjectAttributes
```

It owns the dedicated preparation verifier, warning-strict build, socket
corpus, 116-operation coverage gate, fresh selected-operation GNATdoc site,
pinned-model repository gate, and final diff check. The GNATdoc gate receives
`--operation GetObjectAttributes` from the qualification planner.

The source stage passed the maintained root wrapper: generated-current and
registry gates, 41/41 AUnit tests, the server and HTTP socket corpora, three
socket/TLS repetitions, and signed qualification corpora. A fresh GNATdoc
measurement removed exactly 54 candidate-owned warnings and left the changed
GetObjectAttributes declaration regions warning-free. Unrelated repository
GNATdoc warnings currently keep the global classifier gate closed, so this is
region-scoped measurement evidence rather than selected-operation or
repository-wide qualification.
