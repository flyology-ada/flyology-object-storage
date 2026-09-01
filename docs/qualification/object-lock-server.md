# Object Lock backend and server evidence

This record covers the shared Flyology backend and authenticated S3 server
boundary for `GetObjectLegalHold`, `PutObjectLegalHold`,
`GetObjectRetention`, `PutObjectRetention`,
`GetObjectLockConfiguration`, and `PutObjectLockConfiguration`. The six
operation-specific qualification records continue to own client request,
response, and certainty details.

## Stored contract

- Bucket Object Lock can be enabled only after versioning is enabled. Once
  enabled, the bucket cannot suspend versioning or disable Object Lock.
- Legal-hold and retention state belongs to an exact selected object version.
  Legal hold defaults to `OFF`; retention defaults to absent.
- An active legal hold rejects permanent deletion. Active compliance
  retention cannot be shortened, removed, or changed. Active governance
  retention accepts only same-mode non-shortening updates because governance
  bypass is deliberately unsupported.
- Deleting the current object in an enabled versioning bucket publishes a
  delete marker without changing the protected exact selected object version.
- Mutation failure does not authorize automatic replay. A later read observes
  current state and does not prove which mutation caused it.

The memory, filesystem, and SQLite backends implement the same contract. The
filesystem writes `FOSOBJ06` object records and `FOSLCK01` bucket records,
while retaining read compatibility with `FOSOBJ01` through `FOSOBJ05`.
SQLite schema 21 migrates prior catalogs and validates both Object Lock tables
before accepting a catalog.

## Server contract

The authenticated server recognizes only the exact `object-lock`,
`legal-hold`, and `retention` subresources. Object-level operations preserve
the exact optional `versionId`. Put operations require bounded XML bodies and
validated integrity headers. Malformed, duplicate, unsupported bypass, and
cross-operation inputs fail closed without changing stored state.

Retention timestamps preserve their exact wire text and use a parsed Unix
deadline. Fractional seconds are rounded upward so a protected object cannot
be released before the requested instant.

## Maintained evidence

- `tools/verify-object-lock-server.py` pins the six registry entries, their
  separate qualification lanes, the backend implementations, durable formats,
  migration checks, authenticated routes, and consolidated corpora.
- `tests/src/object_storage_test_cases.adb` exercises the memory and filesystem
  backends, exact-version protection, delete-marker behavior, filesystem
  reopen, metadata rewrite preservation, legacy `FOSOBJ05`, corrupt
  `FOSOBJ06` object state, and corrupt bucket-lock state.
- `sqlite/tests/src/flyology_object_storage_sqlite_tests.adb` exercises schema
  20 migration into schema 21, durable reopen, exact-version enforcement,
  expiry, malformed schema rejection, and atomic publication.
- `tests/src/s3_server_application_corpus.adb` exercises all six routes,
  version selection, integrity validation, unsupported bypass, persistence,
  versioning prerequisites, positive and negative offset conversion,
  zero and nonzero fractional deadline handling, and protected deletion.

Each operation keeps its own client verifier, corpus, selected GNATdoc command,
and qualification lane. This file is a region-scoped measurement and evidence
record, not a qualification claim. Qualification remains conditional on every
maintained lane and repository diagnostic gate succeeding.
