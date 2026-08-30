# Bucket-policy backend and server qualification

This record closes backend, authenticated-server, client, and corpus coverage
for `PutBucketPolicy`, `GetBucketPolicy`, and `DeleteBucketPolicy`. It covers
the Flyology memory, pure-files, and SQLite backends. It does not claim policy
interpretation, `GetBucketPolicyStatus`, authorization enforcement derived
from stored policy contents, or external-provider interoperability.

## Storage contract

The HTTP-independent backend boundary treats a policy as an opaque Ada
`String`. A separate configured bit distinguishes no policy from a present
empty policy. Put atomically replaces the exact bytes for an existing bucket;
Get returns one snapshot and resets both outputs on failure; Delete is
idempotent for an existing unconfigured bucket and distinguishes an absent
bucket. No backend imports HTTP, S3 request/response, or JSON types.

Every backend applies the established 16 MiB S3 document ceiling. The value is
private backend policy derived from `S3.XML.Default_Limits`, rather than a new
public constant, and changing it changes accepted and persisted compatibility.
Memory charges retained policy bytes against its existing byte capacity and
publishes the bytes and configured bit in one protected operation.

Files stores one `configuration/policy.fos` record behind the `FOSPOL01`
discriminator. The record is length-prefixed and exact-size checked. Put
synchronizes a unique temporary record, renames it under the publication gate,
then synchronizes the configuration and staging directories. A failure after
rename can therefore report `Backend_Unavailable` after the complete new policy
is visible; callers must not infer nonpublication. Delete has the analogous
post-unlink synchronization ambiguity. Reads reject malformed, trailing,
symlinked, and nonordinary records.

SQLite schema 12 adds one BLOB policy row per configured bucket, constrained by
the same byte ceiling and a cascading bucket foreign key. Put and delete use
one transaction, while Get uses the catalog gate and byte-safe BLOB access.
Schema 11 migrates transactionally without inventing policy state.

## Authenticated S3 route

The server admits only the exact `policy` subresource and matching
operation-specific `x-id` forms after authentication. Extra, duplicate, and
operation-mismatched query members are rejected. All three operations enforce
the expected-bucket-owner precondition and reject RequestPayer because it is
not modeled for these operations.

Put streams under the shared S3 document bound, requires and validates the
modeled Content-MD5, validates each modeled SDK checksum algorithm/header pair
when supplied, and preserves exact payload bytes without JSON interpretation.
It validates the optional self-access-removal confirmation spelling and returns
an empty 200 on success. Get returns the exact same-snapshot bytes as
`application/json`, distinguishing `NoSuchBucketPolicy` from `NoSuchBucket`.
Delete returns an exact empty 204 and is idempotent for an existing bucket.
Bodyless operations reject a request body before backend access.

## Evidence and coverage boundary

The shared backend conformance exercises absent buckets, absent and present
empty policy state, arbitrary bytes including NUL, replacement, deletion,
idempotence, cancellation, deadlines, files reopen, and files live/dangling
symlink rejection. The SQLite gate repeats the state transitions, exact-byte
and reopen checks, schema-11 migration, schema topology, and malformed-row
fail-closed behavior.

The authenticated in-memory server corpus covers exact routing, absent and
present-empty state, exact raw bytes, every modeled checksum algorithm, missing
and mismatched MD5, invalid confirmation, expected-owner rejection, unsupported
RequestPayer, extra query members, body rejection, deletion, and absent bucket
and policy errors.

The provider-owned Get client uses one bounded response sink and retains the
prepared request until its HTTP child drains. Its limited constructor,
operation-last restart, typed `Finish`, and typed synchronous wait share the
same state machine and caller-selected `Parse_Limits`. The normalization corpus
covers modeled success and rejection, inconsistent admission, and every typed
HTTP failure across all admission states. Native and lightweight signed sockets
cover blocking success, limited-root success, and a restarted structured 403.

The machine ledger records all three operations as `covered / covered /
covered / covered`. The maintained 116-operation ledger verifier and its
negative oracle gate those claims. The root and SQLite deterministic suites,
repository checks, documentation build, and exact-tree proof result are
recorded with the commit that introduces this slice.

The `DeleteBucketPolicy` registry lane is conditional on every maintained
command succeeding. It records exact empty-204 completion, admission-aware
nonreplaying certainty, and observational `Get_Policy` reconciliation without
claiming that a later policy or `NoSuchBucketPolicy` observation proves the
lost deletion caused that state. Its generated-model documentation evidence
is a region-scoped warning measurement only; repository-wide and selected
GNATdoc qualification remain blocked by pre-existing warnings outside that
declaration region.
