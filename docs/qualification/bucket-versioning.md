# Bucket versioning configuration evidence

This slice qualifies configuration semantics for `PutBucketVersioning` and
`GetBucketVersioning`. Retained memory, pure-files, and SQLite ordinary PUT,
delete-marker, version-addressed read/tag/delete, and ListObjectVersions
behavior are qualified separately. Pure-files and SQLite retained-generation
multipart completion and selected part attributes are also qualified.

Object tagging returns the current, null, or opaque retained identity from the
same locked or transactional snapshot that reads or mutates the complete tag
set. The authenticated memory corpus covers current and exact identities,
exact-version isolation, missing selectors, and explicit null selection; the
shared backend conformance repeats the identity contract on memory, files, and
SQLite, and both durable backends reopen a suspended null generation without
losing its tags or identity.

Ordinary PutObject likewise returns its success identity from the mutation
that publishes the complete object tuple. Unconfigured publication omits an
identity, enabled memory/files/SQLite publication returns its exact opaque
version, and suspended memory/files/SQLite publication returns the
distinguished null identity.

CopyObject uses the same identity model at both ends. Memory, files, and SQLite
select current, null, or exact retained sources.
The successful mutation returns both the selected source identity and the
published destination identity atomically, including the distinguished
`null` value while suspended.

The machine ledger records both configuration operations as `covered` for the
backend, client, server, and corpus columns. The separately qualified
`ListObjectVersions` boundary is `covered / covered / covered / covered`; the
independently qualified files and SQLite generation data planes consume the
same durable configuration state.

Evidence is reproducible with these exact repository gates:

```text
./tools/verify-coverage.sh
./tests/scripts/test.sh
./sqlite/tests/scripts/test.sh
```

The core gate includes the strict XML adversarial corpus, including required
S3 request namespaces, rejected foreign namespaces and attributes, exact
input/output serializer member ordering, bounded compatibility parsing for
namespace-free responses, and an empty optional configuration as an atomic
no-op; exact Content-MD5 and all ten modeled direct or physical-trailer
checksum algorithms; expected-owner ordering; bounded MFA credentials and
typed fail-closed verifier outcomes; and atomic memory/files backend
conformance. Sixteen-round two-writer races prove that MFA enablement and an
unverified status change have one publication order. Files reopen with MFA
Delete enabled, reject symlinked configuration, and pass the 88-case
abrupt-crash matrix with only complete old/new Status/MfaDelete pairs. Signed
application requests cover valid, missing, invalid, duplicate, overlong,
insecure, non-root, unavailable, null, and raising verifier paths without
mutation. Typed plus complete convenience clients run over fragmented sockets
from native and Flyology lightweight tasks. The SQLite gate repeats the atomic
race, persists MFA-enabled configuration across reopen, and upgrades every
recognized version-1 through version-7 layout to schema 8 without inventing
configuration or checksum metadata.

`tests/src/s3_implementation_corpus.adb` supplies the independent black-box
oracle. Its setup phase creates a dedicated empty probe bucket, checks initial
absence, transitions Enabled with the complete convenience API and a concrete
SHA-256 request checksum, transitions to Suspended, observes each state through
a separate GET, and deletes the probe without ever creating a versionable
object. The pinned RustFS, SeaweedFS, supplemental MinIO, and Flyology
memory/files/SQLite launchers run this same executable.

When the launcher identifies an authenticated Flyology files or SQLite server,
same setup also creates an independent version-enabled probe and runs the
retained ordinary-generation, exact GET/HEAD/delete, marker publication,
listing, re-exposure, and cleanup lifecycle recorded in the
ListObjectVersions qualification, including a process restart on the same
storage root. Other implementations retain the configuration-only oracle, so
this durable-backend evidence does not silently widen an external capability
claim.

On 2026-08-22, the default three-repeat post-change campaign passed all 18
lanes: the three digest-pinned external images and Flyology memory, files, and
SQLite, each three times. Every lane retained the independent s5cmd byte,
multi-delete, and cleanup oracles. External MFA Delete is deliberately excluded
because those servers do
not expose a test root owner's physical MFA device; it is not simulated by
treating an ordinary authenticated principal as root. SeaweedFS's
already-ledgered ListMultipartUploads exclusion is unrelated to these
configuration checks.
