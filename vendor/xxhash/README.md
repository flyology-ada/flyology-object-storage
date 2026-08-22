# Vendored xxHash

The file 'xxhash.h' is the unmodified single-header library from immutable
upstream release v0.8.3 of <https://github.com/Cyan4973/xxHash>. It is used
under the BSD 2-Clause license in 'LICENSE'.

- Upstream release archive SHA-256:
  aae608dfe8213dfd05d909a57718ef82f30722c392344583d3f39050c7f29a80
- Vendored xxhash.h SHA-256:
  17973c0dc49d9854ca26caa191f0e12f7a424b68858d9a78de3860d959d85e4b

The Ada-facing bridge compiles the header with XXH_INLINE_ALL, keeps each
streaming state in caller-owned fixed storage, uses seed zero as required by
the S3 algorithms, and converts final hashes to canonical big-endian bytes
before Base64 encoding.
