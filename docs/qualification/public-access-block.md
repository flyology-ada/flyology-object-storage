# PublicAccessBlock backend and server qualification

This record closes backend, authenticated-server, client, and corpus coverage
for `PutPublicAccessBlock`, `GetPublicAccessBlock`, and
`DeletePublicAccessBlock`. It covers the Flyology memory, pure-files, and
SQLite backends. It does not claim external-provider interoperability or
enforcement of the stored policy against ACL and bucket-policy operations that
are outside the currently implemented server surface.

## Storage contract

The HTTP-independent backend value preserves presence independently for
`BlockPublicAcls`, `IgnorePublicAcls`, `BlockPublicPolicy`, and
`RestrictPublicBuckets`. A separate configured bit distinguishes no stored
configuration from a present configuration whose four optional members are
all absent. The meaningless value bit of an absent member is canonicalized to
false by every backend, so snapshots do not expose backend-specific record
representations.

Put atomically replaces the complete record for an existing bucket. Get
returns one snapshot and resets both the record and configured bit on failure.
Delete is idempotent for an existing unconfigured bucket and distinguishes an
absent bucket. No backend imports an S3 request, response, XML, or HTTP type.

Memory publishes the configured bit and record in one protected operation.
Files stores the canonical eight-Boolean record behind the versioned
`FOSPAB01` discriminator, publishes a synced temporary file by rename, and
syncs the configuration and temporary directories. As with other files
mutations, a failure after rename can be an ambiguous durable-publication
outcome. Reads reject noncanonical records, unexpected bytes, symlinks, and
nonordinary paths. SQLite schema 11 adds one normalized row per configured
bucket with Boolean checks, a primary key, and a cascading bucket foreign key;
schema 10 and every maintained historical fixture migrate transactionally
without inventing a configuration.

## Authenticated S3 route

The server admits only the exact `publicAccessBlock` subresource and matching
operation-specific `x-id` forms after authentication. Extra, duplicate, and
operation-mismatched query members are rejected. All three operations enforce
the expected-bucket-owner precondition and reject RequestPayer because it is
absent from the pinned model.

Put streams under the shared S3 XML document bound, validates the signed
payload hash, validates Content-MD5 when supplied, and validates each of the
ten modeled SDK checksum algorithm/header pairs before mutation. It rejects
duplicate or inconsistent checksum groups and checksum mismatches. The exact
namespace-aware codec preserves member presence and rejects malformed XML,
foreign namespaces, attributes, unknown or duplicate fields, non-lowercase
Boolean spellings, DTD/entity input, and resource-limit violations. Success is
an empty 200 response.

Get serializes one atomic backend snapshot and returns
`NoSuchPublicAccessBlockConfiguration` separately from `NoSuchBucket`.
Delete returns an exact empty 204 and is idempotent for an existing bucket.
Bodyless operations reject a request body before backend access.

## Evidence and coverage boundary

The reviewed `DeletePublicAccessBlock` client contract accepts only a complete
empty 204 response as mutation completion. Exact recognized rejections and
definite non-admission prove non-application; a possibly admitted exchange,
retryable response, or malformed response remains outcome-unknown and is
never replayed automatically. A later `Get_Public_Access_Block` can observe
the current bucket configuration or exact
`NoSuchPublicAccessBlockConfiguration`, but that observation neither proves
the lost deletion caused the state nor upgrades mutation certainty.

The focused `delete_public_access_block` lane is conditional on every
maintained command succeeding. It does not claim directory-bucket support,
account- or organization-level effective-policy interpretation, external
provider interoperability, or repository-wide GNATdoc qualification.

The shared backend conformance exercises absent buckets, new unconfigured
buckets, present-empty configurations, every Boolean presence/value form,
canonical replacement, deletion, idempotence, cancellation, and deadlines on
memory and files. The SQLite gate repeats the state transitions, validates
schema migration and topology, and requires the configuration to survive a
close/reopen boundary. The authenticated in-memory server corpus covers exact
routing, present-empty and populated documents, all ten checksum algorithms,
digest mismatch, malformed Boolean input, expected-owner rejection, extra
query members, body rejection, deletion, and absent bucket/configuration
errors.

The machine ledger records all three operations as `covered / covered /
covered / covered`. The maintained 116-operation ledger verifier and its
negative oracle gate those claims. The root and SQLite deterministic suites,
repository checks, documentation build, and proof result for the exact landed
tree are recorded with the commit that introduces this slice.
