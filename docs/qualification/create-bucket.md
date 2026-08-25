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

## Composable client boundary

The limited `Client.Buckets.Create` operation owns the exact serialized
configuration and supplies it as a one-shot non-rewindable source. The blocking
typed and convenience overloads wait on that same operation. No helper task,
second protocol engine, retained borrowed input, or automatic mutation retry is
introduced. Typed Finish preserves HTTP admission certainty and distinguishes
validated creation, modeled definite non-creation, cancellation before
admission, and an unknown outcome that requires caller-selected HeadBucket
reconciliation before retry.

The signed socket corpus covers fragmented success metadata, the convenience
wait-through path, duplicate physical singleton headers, same-owner restart
through a modeled conflict, cancellation, and an expired deadline on native and
lightweight tasks. The normalization corpus covers every HTTP terminal kind in
every admission-certainty state and the maintained conclusive, retryable, and
unknown S3 status/code classes.

The qualified source passes the 41/41 AUnit root suite, 126 abrupt files-crash
cases, 320 checksum vectors, 210 chunk boundaries, the 64-GiB CRC linearization
oracle, signed server/application/socket/TLS corpora, the 116-operation coverage
verifier and negative oracle, GNATdoc generation, the repository integrity
gate, and the warning-strict 936/936 GNATprove campaign. The composable change
does not alter the backend state model, server admission policy, pagination
algorithm, or scheduling engine.
