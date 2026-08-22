# Files backend layout

The files backend requires exclusive ownership of its configured root by one
process. Buckets are ordinary validated directory names. Object keys are
opaque bytes encoded as uppercase hexadecimal and split into bounded path
components; caller-provided slashes and dot segments are never interpreted.

Each object is one versioned binary record containing a magic value, bounded
metadata, the original key, a complete bounded object-tag set, retained
completed-multipart part numbers and sizes, and the body. Version-3 records
carry tags and completed-part metadata. Version-2 tag records and legacy
version-1 records remain readable; both expose no completed-part metadata.
PUT writes a unique temporary record
and publishes it with an operating-system rename, so readers never observe a
new body paired with old metadata. Reads validate the magic, lengths, key, and
exact file size before yielding bytes. GetObjectAttributes reads object
metadata and its bounded part page from that one immutable record, so the
values cannot describe different object generations.

Object-tag replacement and deletion use that same publication gate and record
rename. Because tags and payload form one indivisible record, a tag mutation
copies the existing body into a new record, flushes it, and atomically publishes
the complete tags-plus-body snapshot. This intentionally trades write
amplification proportional to object size for a simple crash-atomic invariant:
readers can observe only the old complete record or the new complete record.
Use SQLite when frequent tag-only mutation makes that cost unsuitable.

`Open` defaults to `Power_Loss_Durable`. Temporary object and part records are
closed and synchronized before publication. Every rename is followed by a
sync of the destination directory and the staging directory; deletion syncs
the directory whose entry changed. Directory trees are created one component
at a time and each child/parent relationship is synchronized. Multipart
initiation is assembled beneath `tmp/`, including a synchronized manifest,
before one rename publishes the active upload. Completion makes the assembled
object durable before durably removing the active-upload tree. A failure after
publication is intentionally reported as ambiguous rather than rolling back a
possibly durable object.

`Process_Crash_Atomic` omits persistence barriers while retaining the same
rename and validation structure. It exists for explicitly labeled comparison
and deployments whose storage layer supplies a stronger external durability
contract; it is not the production default. The deterministic fault corpus
injects a device error at every file/directory barrier across bucket create
and delete, object replacement and delete, object-tag and bucket-tag
replacement, multipart initiation, part replacement, completion, and abort,
then reopens the root and requires a
well-formed old-or-new state. A separate process corpus terminates workers
without Ada finalization immediately before and after all 35 barriers in those
same mutation paths (70 cases), then independently reopens and verifies each
store. The adapter uses `F_FULLFSYNC` where available and falls back to `fsync`
on POSIX. Windows remains unqualified until its directory-metadata persistence
path has an independent host-level crash corpus. Cross-process writers remain
unsupported.

Bucket enumeration holds the backend publication gate used by create and
delete, so each result is one process-local atomic namespace snapshot. Pages
are bytewise sorted, prefix-filtered, and bounded to `MaxBuckets + 1` retained
candidates to determine truncation. The bucket directory modification time is
the creation timestamp: the backend creates its `objects/` and `multipart/`
children before publishing the bucket and does not subsequently mutate the
bucket directory itself. Direct external changes beneath the owned root are
unsupported and malformed bucket entries fail the operation closed. Complete
bucket directories are staged beneath `tmp/` and atomically renamed into the
namespace; opening the exclusively owned root removes interrupted staging
artifacts before accepting work.

Each bucket also owns `configuration/tags.fos`, a versioned, length-prefixed
binary record with strict key/value and exact-file-size checks. Put writes and
syncs a unique root-local temporary record, publishes it by rename under the
same publication gate as bucket deletion, then syncs both affected directories.
Get rejects symlinked configuration or tag paths and returns one validated
snapshot. The three publication barriers have deterministic device-error and
abrupt-process old-or-new coverage.
