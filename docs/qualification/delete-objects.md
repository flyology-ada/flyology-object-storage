# DeleteObjects qualification and boundaries

This slice qualifies the independent current-object semantics of
`DeleteObjects`. It does not qualify object versions, delete-marker creation,
MFA Delete enforcement, directory buckets, Requester Pays accounting, or
Object Lock governance enforcement.

The request boundary accepts at most 1,000 entries and a bounded XML body. It
requires one canonical Content-MD5 computed over the exact body bytes and can
verify one matching SDK checksum algorithm/value pair for every algorithm in
the pinned model. XML namespace, attributes, member order, duplicates, UTF-8,
key limits, booleans, nonnegative 64-bit sizes, ETag syntax, and HTTP dates are
validated before the relevant entry can reach storage. A malformed checksum
group is `InvalidRequest`; a validly encoded digest that does not match is
`BadDigest`.

For unversioned general-purpose buckets, valid `requester`, governance-bypass,
and nonempty MFA headers are accepted as no-ops because no corresponding
bucket policy is active. Expected owner is enforced. LastModifiedTime and Size
are rejected per entry with the explicit directory-bucket boundary. VersionId
is rejected per entry as `NotImplemented`, while independent current-object
entries in the same request still run. If bucket versioning or MFA Delete is
configured, the whole request is rejected before mutation: silently deleting
the current object would incorrectly emulate S3 delete-marker behavior. That
precondition is part of the backend batch boundary, not a preceding server
lookup: memory checks it in the protected operation, files under the
publication gate, and SQLite inside the deletion transaction. Deterministic
regressions publish versioning after an earlier unconfigured observation and
require all three backends, plus the server path, to preserve the object.

All backends implement the same ordered batch contract. The complete request
is structurally validated before mutation, unconditioned missing keys are
idempotent successes, conditioned missing keys are `NoSuchKey`, and ETag
mismatches are `PreconditionFailed`. Quiet mode suppresses only success
entries. Memory uses one protected publication; SQLite uses one catalog
transaction and reclaims retired payload files after commit. Files uses a
whole-request preflight and one publication gate, but each file removal is a
separate durable namespace mutation. An I/O failure, cancellation, deadline,
process crash, or power loss during that loop may leave an idempotently
retryable prefix applied. No whole-batch cross-file atomicity is claimed.

Executable evidence is provided by:

- `backends.delete-objects-conformance` for memory and files, including
  duplicate entries, condition results, whole-request validation, and
  failpoints;
- the SQLite conformance, rollback-trigger, migration, reopen, and orphan
  payload recovery cases;
- `s3.delete-objects-result-codec` and `s3.low-level-delete-requests` for every
  modeled request/result member and all ten checksum algorithms;
- `s3_server_application_corpus` for authenticated Content-MD5/checksum/control
  admission, conditions, ordering, quiet results, and explicit boundaries;
- `s3_http_socket_corpus` for a signed, checksummed typed request and complete
  Deleted/Error response over fragmented real sockets from both Flyology task
  models; and
- `s3_implementation_corpus` plus the s5cmd oracle for interoperable batch
  deletion across the pinned external servers and Flyology memory, files, and
  SQLite servers.

Reproduce the deterministic local qualification with:

```text
./tools/verify-coverage.sh
./tests/scripts/test.sh
./sqlite/tests/scripts/test.sh
```

The coverage ledger marks the client covered because it projects every pinned
request member and decodes every result member. Backend and server remain
partial solely for the explicit version/directory/policy boundaries above;
corpus coverage remains covered.
