# DeleteObjects qualification and boundaries

This slice qualifies current, null, and exact-generation `DeleteObjects` for
the memory, pure-files, and SQLite backends, including delete-marker
publication/removal and MFA Delete enforcement. Directory buckets, Requester
Pays accounting, and Object Lock governance enforcement are not qualified.

The request boundary accepts at most 1,000 entries and a bounded XML body. It
requires one canonical Content-MD5 computed over the exact body bytes and can
verify one matching SDK checksum algorithm/value pair for every algorithm in
the pinned model. XML namespace, attributes, member order, duplicates, UTF-8,
key limits, booleans, nonnegative 64-bit sizes, ETag syntax, and HTTP dates are
validated before the relevant entry can reach storage. A malformed checksum
group is `InvalidRequest`; a validly encoded digest that does not match is
`BadDigest`.

For policy-inactive general-purpose buckets, valid `requester` and
governance-bypass headers remain accepted no-ops. Expected owner is enforced.
LastModifiedTime and Size are rejected per entry with the explicit
directory-bucket boundary. An omitted VersionId selects the current
generation; `null` selects the distinguished null generation; any other
canonical value selects that exact opaque generation. Enabled current deletion
publishes a marker, suspended current deletion replaces the null generation
with a null marker, and selected null/exact deletion permanently removes only
that generation. Successful responses preserve the requested VersionId and
report marker identity when a marker is created or removed. A missing
unconditioned selected generation is idempotent success.

When MFA Delete is enabled, any actionable null/exact entry requires one
verified `x-amz-mfa` credential. A missing or invalid credential rejects the
request before backend mutation; the verified authorization is carried into
the same batch boundary that reads bucket policy and publishes deletions.
Memory performs that boundary in its protected state, SQLite in one catalog
transaction, and files under one publication gate with durable per-generation
namespace mutations. The legacy `Require_Unversioned` backend requirement
remains available for callers
that specifically require pre-versioning semantics and is still checked under
the same publication boundary.

All backends implement the same ordered batch contract. The complete request
is structurally validated before mutation, unconditioned missing selections
are idempotent successes, conditioned missing selections are `NoSuchKey`, and
ETag mismatches are `PreconditionFailed`. Each outcome retains its exact
publication kind and typed generation identity. Quiet mode suppresses only
success entries. Memory uses one protected publication; SQLite uses one
catalog transaction and reclaims retired payload files after commit. The
SQLite rollback oracle injects failure on the authoritative `object_versions`
table after an earlier selected removal and requires zero committed catalog or
payload-retirement outputs. Files uses a whole-request preflight and one
publication gate, but each file removal is a separate durable namespace
mutation. An I/O failure, cancellation, deadline, process crash, or power loss
during that loop may leave a prefix applied. No whole-batch cross-file
atomicity is claimed, and callers must reconcile before retrying an
indeterminate conditional batch.

Executable evidence is provided by:

- `backends.delete-objects-conformance` for memory and files, including
  duplicate entries, condition results, whole-request validation, selected
  null/exact semantics, and failpoints;
- the shared memory/files/SQLite retained-generation conformance for mixed
  exact, current-marker, missing-exact, and conditional entries in one batch;
- the SQLite conformance, authoritative-generation rollback trigger,
  migration, reopen, MFA, and orphan-payload recovery cases;
- `s3.delete-objects-result-codec` and `s3.low-level-delete-requests` for every
  modeled request/result member and all ten checksum algorithms;
- `s3_server_application_corpus` for authenticated Content-MD5/checksum/control
  admission, conditions, ordering, quiet results, exact VersionId echo,
  marker identity, selected-generation nonmutation, and explicit boundaries;
- `s3_http_socket_corpus` for a signed, checksummed typed request and complete
  Deleted/Error response over fragmented real sockets from both Flyology task
  models; and
- `s3_implementation_corpus` plus the s5cmd oracle for interoperable batch
  deletion across the pinned external servers and Flyology memory, files, and
  SQLite servers; the files and SQLite lanes additionally delete two exact
  retained generations in one signed batch and check the returned identities
  through a real server restart.

Reproduce the deterministic local qualification with:

```text
./tools/verify-coverage.sh
./tests/scripts/test.sh
./sqlite/tests/scripts/test.sh
```

The coverage ledger marks backend, client, server, and corpus covered. The
directory and policy exclusions above remain explicit capability boundaries;
they do not weaken the qualified general-purpose bucket operation.
