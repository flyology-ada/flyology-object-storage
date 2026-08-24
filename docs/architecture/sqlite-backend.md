# SQLite backend durability model

The optional SQLite crate implements the shared streaming backend contract.
SQLite stores bucket/object identity and metadata. Object bodies are immutable
files beneath `objects/`; caller keys are stored as BLOB values and never used
as paths.

A successful PUT follows this order:

1. stream into an exclusively created file beneath `staging/`;
2. close and flush the complete file to stable storage;
3. atomically rename it to a generated SHA-256 payload name beneath `objects/`;
4. flush the `objects/` directory entry;
5. commit the new payload name and metadata in SQLite WAL mode with
   `synchronous=FULL`.

An interruption before step 5 leaves an unreferenced immutable payload. An
interruption after step 5 leaves a complete referenced payload. At open, the
backend removes all staging files and object payloads not referenced by the
current-object, retained-generation, or multipart catalog, then flushes both
directories. Superseded and deleted bodies are
intentionally retained until that recovery pass so an already-open reader is
never invalidated by replacement.

DeleteObjects preflights every bounded entry under the catalog gate, evaluates
conditions and duplicate keys in request order, and performs all successful
catalog removals in one SQL transaction. A required unversioned state is read
from the bucket row in that transaction before any removal, so a concurrent
versioning commit cannot pass between policy and mutation. Any statement or
commit failure rolls
back the complete catalog batch. Payload names retired by the commit are
collected before publication and reclaimed only after the commit; a cleanup
failure therefore cannot roll back or invalidate the committed result. Startup
reconciliation removes any such unreferenced payload left by a crash or failed
post-commit cleanup.

The database carries a fixed application ID and schema version. Schema version
4 added `object_tags`, keyed by bucket, opaque object key, and a one-based tag
order. Its composite foreign key cascades object deletion. Complete tag-set
replacement and deletion run in one catalog transaction, while object PUT and
multipart completion clear any prior rows in the same transaction that
publishes the replacement payload. Tag reads and object-existence classification
remain under the catalog operation gate, so a reader cannot combine tags from
one version with the body identity of another.

Schema version 10 adds the durable retained-generation foundation without
moving bodies into SQLite. `object_versions` stores one bounded metadata row
per opaque version identity and assigns a monotonically increasing publication
order. `current_object_versions` selects the visible generation in the same
transaction, while generation-specific tag, user-metadata, and completed-part
tables preserve the complete snapshot. A delete-marker row has no payload;
every data generation has exactly one immutable payload reference. Existing
catalogs migrate each current object as the S3 `null` generation and copy its
tags, metadata, and parts under one exclusive transaction. Ordinary PUT reads
the bucket versioning state and publishes its current mirror and retained
generation in the same transaction, returning the matching omitted, opaque,
or null publication identity: unconfigured buckets replace all history
with `null`, enabled buckets append a unique opaque generation, and suspended
buckets replace only the `null` generation. Multipart completion follows the
same three publication modes and snapshots its completed-part metadata with
the generation. Current, null, and exact GET/HEAD, object-attribute, and tag
operations select that same durable snapshot. Enabled current deletion
appends a unique delete marker, suspended deletion replaces only the null
marker, and exact deletion permanently removes the selected data or marker;
removing the latest generation re-exposes the preceding snapshot.

Generation listing reads the normalized rows in bytewise key and
newest-publication order, applies prefix and delimiter projection, and resumes
only from an exact paired key/version cursor. It fails closed on noncanonical
delete-marker metadata. The shared generation state-machine corpus and a
separate reopen oracle gate ordinary and multipart publication, selected
object attributes, per-generation tags, marker transitions, exact deletion,
MFA admission, ordering, pagination, payload reference recovery, and
re-exposure of prior generations. Durable
server routing and black-box S3 interoperability remain separate qualification
boundaries.

Opening a nonempty unrecognized database, an unsupported schema, corrupt metadata, a
missing payload, or a payload with the wrong size fails closed. Foreign keys,
opaque BLOB keys/metadata, bounded metadata, strict statement state, and exact
64-bit size conversions are enforced at the adapter boundary.

Schema version 8 adds checksum algorithm, method, and value columns to object,
staged-part, and completed-part metadata, plus the configured algorithm and
method on multipart uploads. Schema version 7 combines completed-multipart
attributes, bucket tags, and bucket-versioning configuration.
Completed part numbers and sizes live in an
`object_parts` child table. Completion replaces the object row and its part
rows in one transaction; ordinary PUT and COPY remove stale part rows in the
same transaction. GetObjectAttributes selects object metadata, total count,
and one bounded part page while holding the catalog operation gate. The
multipart objects completed by an older development schema have no
reconstructable per-part rows.
HeadObject uses that same gated snapshot and evaluates its HTTP conditions
before releasing the gate. Part selection is resolved from the returned
`object_parts` page, so its size, total count, ETag, and modification time
cannot mix object generations.

Bounded bucket tags use binary unique keys, stable
ordinals, and a cascading bucket foreign key. Put deletes the prior rows and
inserts the complete validated set in one transaction under the catalog gate;
Get returns ordinal order and fails closed on invalid catalog data. Tags do not
participate in the bucket-nonempty check and are removed with their bucket.

Schema version 9 added bounded standard and user object metadata. Version 3
records bucket creation time transactionally. Version 4 introduced
the object-tag table; the independently developed bucket-tag-only version-4
layout is also recognized. Version 5 existed in two released-development
layouts: object tags plus `object_parts`, and object tags plus `bucket_tags`.
The independently developed versioning-only version-4 layout is recognized in
addition to both tag-table version-4 layouts. Opening any recognized version-1
through version-9 catalog upgrades it under exclusive transactions to version
10, creates only missing tables and columns, and preserves existing object tags,
staged and completed-part rows, bucket tags, multipart configuration, and
versioning values. Version-7 checksum columns receive explicit no-checksum
defaults; version-9 objects become `null` generations and no digest or opaque
non-null version ID is invented for historical bodies. Existing
buckets use
`0` to mean that the historical creation time is unavailable, while every new
bucket receives its actual commit-time value. Versioning and MFA-delete use
separate checked state columns; one atomic SQL update merges only configured
fields. The same catalog gate reads current MFA Delete, validates a fail-closed
caller attestation, and publishes the merged row, so concurrent status and MFA
writers have one linearization order. Migrated buckets remain unconfigured.
Bucket pages are selected under the catalog operation gate with binary
ordering, exclusive continuation, prefix filtering, and a SQL
`MaxBuckets + 1` limit, so no unbounded account listing is retained in Ada
memory.

Startup reconciliation is mutually exclusive with live access. A system-wide
root lock rejects a second store or process for the same root. Unix builds
hold a nonblocking exclusive `flock` on one persistent project-private inode;
Windows builds hold a non-shared file handle. The operating system releases
either handle after normal exit or process death, and the lock file is not
unlinked because replacing its inode could split contenders across two locks.
This is an explicit deployment constraint, not an advisory convention. The
same-process exclusion and authenticated process-restart paths are executable
gates; Linux and macOS are the CI-qualified targets.

Durability ultimately depends on the operating system and filesystem honoring
the native file and directory flush operations. A flush failure fails the PUT;
it is never reported as a successful durable commit.
