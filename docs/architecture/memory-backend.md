# Memory backend capacity

The memory backend's `Byte_Capacity` is a hard bound on retained payload
buffer capacity, not a sum of logical S3 object sizes. It covers committed
objects, staged multipart parts, allocator slack in unknown-length objects,
buffers reserved by in-progress PutObject and UploadPart calls, and immutable
snapshots held while GetObject calls invoke caller sinks. Bucket, key, and
control metadata are bounded separately by the bucket/object slot limits and
are not charged to this byte counter. A completed object slot also retains at
most 10,000 selected multipart part numbers and sizes. GetObjectAttributes
copies only its requested page while holding the protected state, so its
object metadata and part page always describe the same generation.

Known-length sources reserve their exact declared length before the first
source read. Unknown-length sources reserve before every allocation growth;
when geometric growth will not fit, they retry the exact required size. A
growth reserves the full replacement while the old array remains charged, so
the allocator's temporary old-plus-new peak is also inside the bound. A
failed, short, malformed, cancelled, timed-out, or exceptional source frees
its buffer before returning its reservation. Commit atomically converts the
reservation into retained capacity. `Bytes_Used` reports committed, staged,
and in-progress retained capacity, so it can exceed the sum of object sizes
when an unknown-length buffer has spare capacity.

This bound intentionally includes coexistence during atomic replacement and
streaming reads. An overwrite needs room for both the old committed payload
and the incoming buffer until publication. Multipart completion likewise
needs room for the staged parts and the contiguous assembled object at the
same time. Each active nonempty GetObject reserves an exact immutable body
snapshot so a concurrent overwrite or delete cannot change the bytes being
streamed. CopyObject holds that source snapshot while its destination buffer
is built, so its conservative peak is the resident source plus one snapshot
plus one destination buffer. Operators should therefore budget approximately
twice the largest completing or concurrently read object, or three times the
largest copied object, plus unrelated resident data. If that headroom is
unavailable, the operation returns `Capacity_Exceeded`; a failed
multipart completion does not consume the upload and can be retried after
capacity is freed or the store is replaced with a larger instance.

These rules make the volatile backend resistant to concurrent body-retention
exhaustion, but they do not turn it into a durable store. Use the files or
SQLite backend for restart persistence.

Each object slot also contains one fixed-capacity complete tag set. The
protected state replaces, reads, and clears that set atomically with respect to
object overwrite, delete, and multipart completion. Tags are bounded control
metadata and are not charged to `Byte_Capacity`; the ten-tag and key/value byte
limits are enforced before publication. Object replacement always starts with
an empty set, so tags cannot leak from an older body version.

Bucket creation and listing run inside the same protected state. A listing is
therefore one atomic namespace snapshot, sorted bytewise and bounded to the S3
`MaxBuckets` ceiling. The exclusive continuation cursor and prefix filter are
applied before publication of the page. Creation times are captured when the
bucket slot is committed and remain stable for that slot's lifetime.
