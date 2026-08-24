# CreateBucket qualification and boundaries

This slice qualifies the authenticated general-purpose path-style server for
`CreateBucket` on memory, files, and SQLite. Directory buckets, initial tags,
grants, public ACLs, Object Lock, non-enforced ownership, and explicit bucket
namespace selection remain typed capability exclusions rather than silently
discarded policy.

## Admission and region contract

Authentication and bounded body framing precede semantic admission. The XML
document is limited to the established 64 KiB server policy, with the limit
inclusive. The entity-safe parser rejects unknown, duplicate, misplaced,
incomplete, excessive, or malformed configuration structure before backend
mutation. A legacy `EU` constraint normalizes to `eu-west-1`; empty
configuration selects `us-east-1`; other constraints must match the endpoint's
validated configured region.

Every modeled header distinguishes absence from an explicitly empty value.
Duplicate or empty ACL, ownership, Object Lock, namespace, and grant controls
are rejected. The exact `private` ACL and `BucketOwnerEnforced` ownership values
are supported; other valid modeled values receive `NotImplemented`; invalid
enum values receive `InvalidArgument`. Directory configuration and initial tag
sets are parsed completely before their explicit capability results. A corrupt
signature combined with an empty control gates authentication precedence.

Only after all admission succeeds does the backend create the bucket. Failure
leaves no namespace entry. Success returns the absolute path in `Location`.
Duplicate names preserve the existing bucket and return the backend's typed
conflict result.

## Adversarial evidence

The signed in-process corpus covers wrong XML roots, empty and mismatched
locations, directory configuration, tags, every ACL/ownership/lock/namespace
enum class, grants, duplicate and empty headers, exact-limit and one-past
bodies, payload fragmentation, authentication precedence, supported empty/
private/owner-enforced creation, cleanup, and absence checks after every
rejected mutation. The exact boundary oracle intentionally mirrors the server's
document ceiling so a future reviewed policy change cannot drift silently.

Native and lightweight typed and convenience clients create and independently
observe buckets through RustFS, SeaweedFS, supplemental MinIO, and Flyology
memory, files, and SQLite in three repeated lifecycle runs.

The qualified source passes the 40/40 AUnit root suite, 88 abrupt files-crash
cases, 320 checksum vectors, 210 chunk boundaries, the 64-GiB CRC linearization
oracle, signed server/application/socket/TLS corpora, the SQLite backend suite,
the 116-operation coverage verifier and negative oracle, and GNATdoc generation.
The admission repair is outside the SPARK manifest and changes no public API,
backend state model, pagination algorithm, or scheduling boundary.
