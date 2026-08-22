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
catalog, then flushes both directories. Superseded and deleted bodies are
intentionally retained until that recovery pass so an already-open reader is
never invalidated by replacement.

The database carries a fixed application ID and schema version. Opening a
nonempty unrecognized database, an unsupported schema, corrupt metadata, a
missing payload, or a payload with the wrong size fails closed. Foreign keys,
opaque BLOB keys/metadata, bounded metadata, strict statement state, and exact
64-bit size conversions are enforced at the adapter boundary.

Startup reconciliation is mutually exclusive with live access. A system-wide
root lock rejects a second store or process for the same root. This is an
explicit deployment constraint, not an advisory convention.

Durability ultimately depends on the operating system and filesystem honoring
the native file and directory flush operations. A flush failure fails the PUT;
it is never reported as a successful durable commit.
