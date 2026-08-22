# Files backend layout

The files backend requires exclusive ownership of its configured root by one
process. Buckets are ordinary validated directory names. Object keys are
opaque bytes encoded as uppercase hexadecimal and split into bounded path
components; caller-provided slashes and dot segments are never interpreted.

Each object is one versioned binary record containing a magic value, bounded
metadata, the original key, and the body. PUT writes a unique temporary record
and publishes it with an operating-system rename, so readers never observe a
new body paired with old metadata. Reads validate the magic, lengths, key, and
exact file size before yielding bytes.

The current implementation provides process-crash atomic publication on
platforms where rename replacement is atomic. It does not yet claim
power-loss durability because directory and file fsync are not exposed as a
configured commit policy. Cross-process writers are unsupported.

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
