# Bucket versioning configuration evidence

This slice qualifies configuration semantics for `PutBucketVersioning` and
`GetBucketVersioning`. It does not qualify object-version creation, delete
markers, version-addressed reads or deletes, or `ListObjectVersions`.

The machine ledger records both configuration operations as `covered` for the
backend, client, server, and corpus columns. The separately qualified
`ListObjectVersions` synchronous boundary is `missing / covered / missing /
covered`; configuring versioning never silently enables an unimplemented
object-version data plane.

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

On 2026-08-22, the default three-repeat post-change campaign passed all 18
lanes: the three digest-pinned external images and Flyology memory, files, and
SQLite, each three times. Every lane retained the independent s5cmd byte,
multi-delete, and cleanup oracles. External MFA Delete is deliberately excluded
because those servers do
not expose a test root owner's physical MFA device; it is not simulated by
treating an ordinary authenticated principal as root. SeaweedFS's
already-ledgered ListMultipartUploads exclusion is unrelated to these
configuration checks.
