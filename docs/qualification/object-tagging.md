# Object-tagging qualification and boundaries

The pinned botocore model defines `DeleteObjectTagging` as an empty-body
`DELETE /{Bucket}/{Key+}?tagging` request. Its inputs are the required bucket
and key, optional `versionId`, and optional `x-amz-expected-bucket-owner`; its
only modeled result member is `x-amz-version-id`. Requester Pays and SDK
checksum controls are not members of this operation. The executable inventory
is locked to botocore revision
`36c34f15391da01cd717c73c0fffa747c9889768` and service-model digest
`429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.

Flyology implements deletion for the current object in an unversioned
general-purpose bucket. An absent `versionId` and the AWS null-version value
`versionId=null` select that same current object; the latter returns
`x-amz-version-id: null`. A real version ID is rejected as `NotImplemented`
rather than being mapped to the current object. Expected-owner policy is
enforced. Unmodeled requester-pays, checksum, Content-MD5, and Content-Type
controls fail closed, as do unknown or duplicate query members, mismatched
`x-id`, a request body, transfer coding, and nonzero content length. SigV4
authentication runs before these semantic errors, so malformed controls do not
provide an authentication oracle and never mutate stored tags.

All three backends delete the complete tag set at the object publication
boundary. Memory updates one protected snapshot. Files streams the existing
body and metadata through an atomic replacement, rejects symbolic links and
nonordinary files throughout the object path, and syncs the file and relevant
directories. SQLite deletes all tag rows in one transaction, checks
cancellation after waiting for the catalog gate and before commit, and rolls
back a cancelled mutation. Object overwrite, copy, completion, and deletion
retain their established whole-object tag cleanup rules.

Executable evidence includes:

- `backends.object-tagging-conformance` for memory and files, covering
  cancellation, expired deadlines, missing buckets and keys, idempotence, and
  complete-set replacement and deletion;
- files live/dangling valid-object symlink probes plus six abrupt-process cases
  around the three pre/post durability barriers;
- SQLite commit-cancellation rollback, reopen persistence, malformed stored-tag
  recovery, migration, and backend lifecycle tests;
- the signed application corpus for authentication ordering, exact query and
  header admission, owner policy, null/current versions, real-version and
  requester-pays boundaries, missing resources, and mutation preservation;
- the raw-socket corpus for typed and convenience clients from both native and
  Flyology lightweight tasks, including null-version results, structured S3
  errors, malformed 204 framing, cancellation, and deadlines; and
- the implementation corpus for put/get/delete, repeated delete, null-version
  delete, missing-key classification, and post-delete reads across pinned
  RustFS, SeaweedFS, MinIO, and Flyology memory, files, and SQLite servers.

One complete six-server matrix repetition passed on 2026-08-22 with no
DeleteObjectTagging-specific divergence. Reproduce the local and external
gates with:

```text
./tests/scripts/test.sh
./sqlite/tests/scripts/test.sh
FLYOLOGY_S3_MATRIX_REPEATS=1 ./tests/scripts/test-s3-matrix.sh
```

The coverage ledger therefore remains `covered` for backend, client, and
corpus. Server coverage remains `partial`: real object versions, directory
buckets, Requester Pays policy/accounting, and complete IAM authorization are
not implemented. The qualification does not invent those semantics.
