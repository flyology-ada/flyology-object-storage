# Object convenience client

`Flyology.Object_Storage.Client.Objects` contains small, synchronous
single-object operations that do not transfer a representation body. Calls use
a caller-owned Flyology HTTP client, one whole-operation timeout, and an
optional cancellation token.

## List objects

`List_V1_Page` exposes one bounded ListObjects v1 page without requiring
callers to construct the modeled request or decode XML. It carries prefix,
delimiter, and an exclusive marker. A truncated delimiter page returns the
modeled `NextMarker`; a truncated page without a delimiter derives the next
marker from the last object key, as AWS requires. With `encoding-type=url`,
the returned wire fields remain encoded but the derived marker is strictly
decoded before publication, so passing it to the next call cannot
double-encode the cursor. FetchOwner is not a ListObjects v1 input; owner is
an optional member of each returned object.

`List_Page` exposes one bounded ListObjectsV2 page without requiring callers
to assemble modeled parameters or decode XML. It carries prefix and delimiter
scope, an exclusive `Start_After` for the initial page, and an opaque
continuation token for later pages. A truncated successful result returns the
next token unchanged; callers pass it back with the same scope. FetchOwner,
URL encoding, RestoreStatus selection, expected-owner, and Requester Pays are
explicit policy inputs.

Both calls own one whole-operation timeout and honor the optional cancellation
token while preparing, exchanging, and decoding. Neither retries a rejected
or truncated page implicitly. This keeps multi-page scheduling with the caller
while preserving S3's page boundary and structured error result.

## Get object attributes

`Get_Attributes` retrieves selected metadata without downloading the object
body. Its default selection requests ETag, checksum, completed-part metadata,
storage class, and object size; callers may select any nonempty subset. Version,
part-page controls, expected-owner, Requester Pays, and SSE-C inputs remain
explicit. Independent presence flags distinguish an omitted page header from
an explicitly supplied zero.

Success returns all modeled response headers together with the bounded typed
REST/XML result. An unavailable optional selection is represented by absence,
not a fabricated checksum or storage class. Rejection preserves the structured
S3 error and request identifiers. The low-level API exposes the same complete
request and output models for callers that need direct signing or a fixed
timestamp.

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
