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
