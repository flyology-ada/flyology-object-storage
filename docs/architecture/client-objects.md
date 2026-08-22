# Object convenience client

`Flyology.Object_Storage.Client.Objects` contains small, synchronous
single-object operations that do not transfer a representation body. Calls use
a caller-owned Flyology HTTP client, one whole-operation timeout, and an
optional cancellation token.

## Delete

`Delete` is idempotent for an absent key in an existing unversioned bucket, as
required by S3. It optionally selects a version, applies an entity-tag
precondition, checks the expected bucket owner, and opts into Requester Pays.
Success preserves the delete-marker flag, version ID, and request-charged
header; rejection preserves the structured S3 error and request identifiers.

MFA Delete, governance-retention bypass, and directory-bucket modification-time
and size conditions remain on `Client.Low_Level.Delete_Object_Parameters` so a
convenience call cannot silently choose security policy. Version IDs are
bounded to 1,024 bytes and may not contain NUL, consistently across the single
delete query, multi-delete XML, and response headers.

The Flyology server currently implements ordinary unversioned deletion and
expected-owner checks. It returns `NotImplemented` for valid versioning,
conditional, Requester Pays, governance, MFA, and directory-only controls.
Every backend classifies a missing bucket separately from a missing key under
the same namespace-publication boundary, so the server can return
`NoSuchBucket` without a racy preliminary probe.

## Object tagging

`Put_Tags`, `Get_Tags`, and `Delete_Tags` expose the common complete-set
lifecycle without requiring callers to construct modeled member arrays or XML.
They are synchronous operations on the caller-owned HTTP client and share the
same whole-operation timeout and optional cancellation model as `Delete`.
`Put_Tags` serializes a bounded `Object_Tag_Set`, calculates and signs the exact
Content-MD5, and replaces all current tags atomically. `Get_Tags` returns the
ordered complete set, and `Delete_Tags` clears it explicitly. All three preserve
the optional response version ID and structured S3 errors.

The convenience layer exposes version selection and expected-owner policy;
PUT/GET also expose Requester Pays, and PUT exposes the modeled SDK checksum
algorithm. Applications needing direct control can use the corresponding
`Prepare_*_Object_Tagging` and `Execute_*_Object_Tagging` pairs in
`Client.Low_Level`. Multi-object tagging is intentionally not invented here:
S3 has no atomic multi-object tagging operation, so callers should schedule
independent convenience calls through their chosen native or Flyology runtime
task model and aggregate per-object outcomes explicitly.
