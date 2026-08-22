# Bucket versioning configuration evidence

This slice qualifies configuration semantics for `PutBucketVersioning` and
`GetBucketVersioning`. It does not qualify object-version creation, delete
markers, version-addressed reads or deletes, or `ListObjectVersions`.

The machine ledger records both configuration operations as `covered` for the
backend, client, and corpus columns and `partial` for the server. The server
qualification is intentionally partial because MFA-delete enforcement and SDK
checksum negotiation return explicit `NotImplemented` responses. The
`ListObjectVersions` row remains `missing / partial / missing / missing`.

Evidence is reproducible with these exact repository gates:

```text
./tools/verify-coverage.sh
./tests/scripts/test.sh
./sqlite/tests/scripts/test.sh
```

The authorized scoped proof command was:

```text
alr -n exec -- "$PROVE" \
  -P tools/flyology_object_storage_proof.gpr -j0 --level=0 \
  --output=oneline --output-header --warnings=error \
  -u flyology-object_storage.adb
```

Here `PROVE` is resolved exactly as in `tools/prove.sh` from the active Alire
installation.

It proved 46/46 checks in all eight domain-unit subprograms, including the
`Merge_Bucket_Versioning` postcondition, with zero justified or unproved
checks, zero warnings, and zero `Assume` statements. This scoped result is
retained alongside the later manifest-wide qualification in
`proof-status.md`.

The core gate includes the strict XML adversarial corpus; atomic memory and
files backend conformance; files reopen, bucket-recreation, symlink, and
76-case abrupt-crash checks; signed application requests; and typed plus
convenience clients over fragmented loopback sockets from native and Flyology
lightweight tasks. The SQLite gate covers atomic independent-field merge,
catalog reopen, backend dispatch, and every recognized version-1 through
version-6 migration to schema version 7 without inventing configuration.

`tests/src/s3_implementation_corpus.adb` supplies the independent black-box
oracle. Its setup phase creates a dedicated empty probe bucket, checks initial
absence, transitions Enabled then Suspended through the convenience API,
observes each state through a separate GET, and deletes the probe without ever
creating a versionable object. The pinned RustFS, SeaweedFS, supplemental
MinIO, and Flyology memory/files/SQLite launchers run this same executable.

On 2026-08-22, one complete campaign passed against all six implementations:
the three digest-pinned external images and Flyology memory, files, and SQLite.
Each run also retained the existing independent s5cmd byte, multi-delete, and
cleanup oracles. SeaweedFS's already-ledgered ListMultipartUploads exclusion
is unrelated to these versioning-configuration checks.
