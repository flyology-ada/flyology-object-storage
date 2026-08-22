# Flyology Object Storage agent guide

- Keep the public Ada namespace under `Flyology.Object_Storage`; the Alire
  crate is `flyology_object_storage`.
- Resolve `flyology_http` through the Flyology Alire index. Do not commit a
  local path pin for that dependency.
- Keep S3 wire models, authentication and HTTP routing above the backend
  boundary. Backends must not depend on HTTP request or response types.
- Every backend must pass the same conformance suite. Do not claim a feature
  in the compatibility matrix until an independent black-box test gates it.
- Keep object bodies streaming and byte counts 64-bit. Pending work, active
  requests and in-flight bytes must remain explicitly bounded.
- Multi-subject client calls own transfer policy and use Flyology structured
  tasks for execution; no detached task may outlive the synchronous call.
- The pure-files backend contains no database. The optional
  `flyology_object_storage_sqlite` crate vendors SQLite and keeps large
  payloads outside SQLite BLOB values.
- Run `./tests/scripts/test.sh` after core, backend or client changes, and
  `./sqlite/tests/scripts/test.sh` after SQLite binding or backend changes.
- Run the proof gate after deterministic validation, signing, range,
  pagination, multipart-state, or scheduling changes. All generated checks in
  SPARK-enabled units must prove; never suppress proof findings.
- Public specifications use GNATdoc leading comments. Write modest, factual
  prose and distinguish engineering targets from completed qualification.
- Releases use immutable annotated tags named `<crate>/v<version>` and are
  published through the Flyology Alire index only after all required checks.
