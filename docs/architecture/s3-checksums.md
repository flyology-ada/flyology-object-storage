# S3 checksum foundation

Flyology.Object_Storage.S3.Checksums provides one backend-neutral streaming
interface for every checksum algorithm in the pinned S3 model: CRC32, CRC32C,
CRC64NVME, SHA1, SHA256, SHA512, MD5, XXHASH64, XXHASH3, and XXHASH128. This
package computes and validates checksum values; it does not depend on HTTP
requests, storage backends, multipart catalogs, or object metadata schemas.
Those layers can therefore persist the canonical bytes or Base64 form without
moving S3 wire types below the backend boundary.

Each context consumes caller-owned byte slices incrementally. CRCs use a
portable table-driven Ada implementation. MD5 and SHA contexts use GNAT's
binary digest interfaces. The three xxHash algorithms use the unmodified
BSD-2-Clause upstream v0.8.3 single-header implementation through a narrow C
bridge. The bridge stores its state in a fixed, aligned Ada record: context
creation, update, and finish do not allocate. Version, archive digest, header
digest, license, and integration choices are recorded in
[vendor/xxhash/README.md](../../vendor/xxhash/README.md).

Digest bytes are canonical big-endian bytes before RFC 4648 Base64 encoding.
The decoder accepts only the fixed encoded length for the selected algorithm,
the standard alphabet, required padding, and zero unused pad bits. It rejects
whitespace, URL-safe variants, missing or surplus padding, and noncanonical
equivalent encodings. Object-level composite values append the exact
'-part-count' suffix; part values and full-object values do not.

## Multipart policy

Flyology.Object_Storage.S3.Checksum_Policy represents the current AWS
multipart matrix:

| Algorithm | FULL_OBJECT | COMPOSITE |
| --- | --- | --- |
| CRC64NVME | yes | no |
| CRC32, CRC32C | yes | yes |
| SHA1, SHA256, SHA512, MD5 | no | yes |
| XXHASH64, XXHASH3, XXHASH128 | no | yes |

Composite calculation hashes the concatenated raw part digests in consecutive
part order. Full-object CRCs can be calculated while streaming the assembled
body or linearized from finalized part CRCs and their 64-bit lengths. SHA,
MD5, and xxHash are deliberately not exposed as full-object multipart
selections because S3 permits them only as composites. The policy follows the
[AWS integrity guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity-upload.html)
and the
[CompleteMultipartUpload API](https://docs.aws.amazon.com/AmazonS3/latest/API/API_CompleteMultipartUpload.html).

CreateMultipartUpload persists the selected policy, or AWS's
CRC64NVME/FULL_OBJECT default when no selection is sent. UploadPart streams and
stores the configured raw part checksum; CompleteMultipartUpload validates
consecutive parts and publishes the exact full-object or composite checksum in
one backend commit. Memory, FOSOBJ04 files, and SQLite schema 8 retain the
policy and completed metadata across reads and reopen. Older file manifests
remain backward-readable, and SQLite schema 7 migrates without fabricating
checksum metadata.

The typed client signs the selection, per-part values, and whole-object
completion assertion. The high-level `Upload_File` API computes an explicit
selection in the same pass as its SigV4 hashes, forces a small composite upload
through multipart, and requires exact checksum echoes before returning
success.

## Test and oracle evidence

The offline root gate runs s3_checksum_corpus. Its checked corpus contains
320 vectors spanning all ten algorithms and 32 lengths chosen around digest,
block, xxHash3 dispatch, and I/O chunk boundaries. Standard-library hash
implementations and the upstream xxHash v0.8.3 CLI generate the expected
values through
[tools/generate_s3_checksum_corpus.py](../../tools/generate_s3_checksum_corpus.py).
The generator is retained so reviewers can reproduce the TSV independently of
the Ada code.

The executable also checks published standard vectors, the AWS SHA256
checksum-of-checksums example and suffix, canonical Base64 rejection cases,
210 incremental chunk boundaries, direct-versus-linearized CRCs, and
independently generated 64 GiB logical CRC vectors. It hashes only bounded
physical buffers for the logical-length case.
