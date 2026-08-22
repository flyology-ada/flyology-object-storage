# Flyology Object Storage

Flyology Object Storage is an in-development S3 client and pluggable S3 server
library for Ada. It builds on `flyology_http` and preserves ordinary
synchronous Ada calls for native and Flyology lightweight tasks.

This repository currently establishes the storage boundary and its first
conforming backends. It does **not** yet claim complete S3 compatibility or
production qualification. Supported wire behavior will be listed only in the
executable [compatibility matrix](docs/compatibility/s3.md).

Deterministic protocol and state logic is developed under the
[SPARK assurance boundary](docs/architecture/spark-coverage.md); I/O and C
interfaces stay in narrow contracted adapters.

## Architecture

```text
high-level transfers -> S3 operation client -> signing/wire -> Flyology HTTP

Flyology HTTP server -> S3 wire/auth/policy -> operation service -> backend
                                                              |-> memory
                                                              |-> files
                                                              `-> SQLite add-on
```

The backend interface deals in buckets, object metadata and streaming byte
sources/sinks. It does not see HTTP exchanges or AWS wire DTOs.

The core crate includes:

- a bounded concurrent memory backend with committed, staged, and in-progress
  payload reservations (see
  [memory backend capacity](docs/architecture/memory-backend.md));
- a pure-files backend with opaque key paths and atomic object publication
  for one process owning an exclusive storage root;
- shared storage and transfer vocabulary;
- a generated, pinned, SPARK-proved descriptor for every operation, shape,
  member location, enumeration, XML trait, checksum trait, and authentication
  trait in the 116-operation botocore S3 model;
- AWS-vector-tested SigV4 header signing and bounded, entity-safe REST/XML;
- a backend-neutral streaming checksum foundation for all ten pinned S3
  algorithms, with strict canonical Base64, AWS composite policy, full-object
  CRC linearization, and a reproducible 320-vector differential corpus (see
  [S3 checksum foundation](docs/architecture/s3-checksums.md));
- complete typed, bounded HeadBucket, GetBucketLocation, ListBuckets,
  ListObjects v1/v2 and multipart initiation, completion, ListParts, and
  ListMultipartUploads REST/XML codecs, plus the complete GetObjectAttributes
  request/output model, with high-level paginated ListBuckets and
  ListObjectsV2,
  HeadBucket, CreateBucket, GetBucketLocation, DeleteBucket, and bucket-tag
  convenience
  APIs (see [bucket convenience client](docs/architecture/client-buckets.md));
- high-level GetObjectAttributes and idempotent DeleteObject clients that
  preserve selected metadata, version,
  delete-marker, requester-charged, and structured error outcomes (see
  [object convenience client](docs/architecture/client-objects.md));
- signed, bounded CreateBucket, GetBucketLocation, HeadBucket,
  PutBucketTagging, GetBucketTagging, GetObject,
  HeadObject, PutObject,
  ListBuckets, ListObjects, ListObjectsV2, DeleteBucket,
  DeleteObject, DeleteObjects REST/XML, and multipart
  initiate/upload/complete/abort/ListParts/ListMultipartUploads low-level
  operations over caller-owned `flyology_http` clients, with UploadPart
  bodies borrowed from streaming sources;
- exhaustive request projection and a raw streaming-response execution
  boundary for all 116 pinned operations, while operation-specific typed
  codecs and interoperability gates remain tracked as incomplete;
- an authenticated path-style S3 server application for the initial
  Create/GetLocation/Head/DeleteBucket, Put/GetBucketTagging,
  ListObjects v1/v2, DeleteObjects,
  Put/Copy/Get/Head/GetAttributes/DeleteObject, and core multipart/ListParts/
  ListMultipartUploads slice, with SigV4 admission before body acceptance,
  streamed payload-hash verification before commit, atomic suffix-range
  resolution, and typed S3 error responses;
- the namespace for the low-level and convenience clients.

The optional `flyology_object_storage_sqlite` subcrate vendors a pinned
SQLite amalgamation and supplies a conforming backend. SQLite owns the
transactional namespace and metadata; immutable large payloads remain
external files because SQLite BLOB limits are smaller than S3 objects. Its
publication order flushes the payload and containing directory before the
`synchronous=FULL` catalog commit, and startup reconciles interrupted writes.
One process owns a configured SQLite root, enforced with a system-wide lock.

The separate [`flyology_object_storage_server`](server/README.md) executable
crate selects memory, files, or SQLite at startup and runs the S3 application
under Flyology supervision. Its first slice includes bounded connection
handling, conservative loopback binding, graceful SIGTERM drain, and the same
independent s5cmd qualification on all three backends. It now creates an
owner-only, slow-hashed administrator credential and displays the random
bootstrap password exactly once. A second supervised, loopback-only listener
serves the authenticated management API and a psqlbench-inspired browser
workbench. It reports the actual bound S3 endpoint, selected backend and
dependency-ordered service tree; its external HTML, CSS and JavaScript are
SHA-256-pinned by the binary so a modified asset set stops startup.
Authenticated administrators can create buckets, delete empty buckets through
an inline confirmation, and browse byte-safe, opaque-token-paginated object
metadata. Management pages preserve 64-bit sizes and timestamps exactly;
object mutation remains on the signed S3 endpoint.

The files backend defaults to an fsync-backed `Power_Loss_Durable` commit
policy on qualified POSIX hosts. It synchronizes staged records before rename,
both namespace sides of publication, deletions, and multipart lifecycle
changes. A separately labeled `Process_Crash_Atomic` policy omits persistence
barriers for controlled comparisons. Barrier-by-barrier device-error injection
and 54 actual abrupt-process terminations immediately before and after each
barrier require every reopened namespace to be an intact old-or-new state.
Windows directory-metadata durability and cross-process root sharing remain
unsupported.

The server application remains `partial`, but it now consumes indexed
`flyology_http=0.1.2`: GET, HEAD and range responses use exact stored lengths
without chunked fallback. The dependency also provides 64-bit request
accounting, a 50 TB streaming ceiling, and per-route `Body_Size` limits.

The SQLite backend’s exact commit, recovery, and ownership model is described
in [docs/architecture/sqlite-backend.md](docs/architecture/sqlite-backend.md).

## Alire

Configure the Flyology index, then build:

```sh
alr index --reset-community
alr index --add=git+https://github.com/flyology-ada/alire-index.git \
  --name=flyology --before=community
alr build
./tests/scripts/test.sh
```

`flyology_http` 0.1.2 is intentionally resolved from that index. This
repository does not carry a machine-local path pin or a development-version
dependency.

The independent S3 interoperability matrix uses digest-pinned RustFS and
SeaweedFS servers as its permissively licensed primary targets, MinIO as an
additional compatibility target, and MIT-licensed s5cmd as a separate byte
oracle. The same s5cmd server slice also runs against the memory, files, and
SQLite Flyology servers, so backend substitution is checked at the public S3
boundary. Every server is ephemeral and exposed only on a random loopback
port:

```sh
./tests/scripts/test-s3-matrix.sh
```

The matrix repeats every server lane three times by default. This is a required
qualification gate for the operations it exercises, but it is kept separate
from the offline default test action because it needs Docker and registry
access. Exact source commits, image digests and reviewed licenses are checked
by `tools/verify-corpora-lock.sh`.

An additional SDK-level lane uses the pinned MIT-licensed `s3t` Go port of
Ceph s3-tests. Build revision
`51506ac904f6e35424b3ec9d38716985023beba6`, then provide its binary to the
same matrix:

```sh
FLYOLOGY_S3T_BIN=/path/to/s3t ./tests/scripts/test-s3-matrix.sh
```

The runner rejects a different or dirty revision and executes the checked
113-node allowlist with four workers, retaining JSON reports under `obj/s3t`.
The memory, files, and SQLite Flyology backends pass 113/113. Pinned RustFS
passes 112 with one exact expected failure (`InvalidArgument` instead of
`NoSuchUpload`), while pinned SeaweedFS passes 107 with six exact expected
failures: four bucket/listing divergences and two UploadPartCopy source-range
validation divergences.
Pinned supplemental MinIO passes 106 with seven exact expected failures: its
six multipart/listing divergences plus `InvalidArgument` in place of
`InvalidRange` for an out-of-bounds UploadPartCopy source range. Unexpected
failures and unexpected passes both fail every lane; MinIO is not used as a
permissively licensed performance oracle.

The server performance comparison is specified in
[docs/qualification/performance.md](docs/qualification/performance.md). It
uses the same client and host for RustFS, SeaweedFS, and each Flyology backend;
durability modes and raw latency/throughput samples remain separate. The
checked [implementation matrix](benchmarks/implementations.tsv) requires both
permissive references and the memory, files, and SQLite backend series; each
Flyology series is reported as an absolute result and as a same-run ratio to
both references.

After the indexed fixed-response HTTP dependency is consumed, run the
correctness-checked aggregate smoke comparison with:

```sh
./benchmarks/run-matrix.sh
```

The launcher refuses the older HTTP dependency so GET framing is comparable.
Dedicated-host campaigns use `FLYOLOGY_BENCH_PROFILE=full` and must record the
host, power, and CPU policies described in the performance guide.

## Client shape

The client will expose the complete model-driven S3 operation surface and a
smaller handwritten convenience layer. The latter owns multipart and
multi-object policy while Flyology performs the actual task-aware waiting:

```ada
package Transfers renames Flyology.Object_Storage.Client.Transfers;

Uploaded := Transfers.Upload_File
  (Client, Origin, "bucket", "key", "archive.tar", Identity);
Downloaded := Transfers.Download_File
  (Client, Origin, "bucket", "key", "archive.tar", Identity);
Copied := Transfers.Copy_Object
  (Client, Origin, "source-bucket", "source key", "bucket", "copy key",
   Identity);
Head := Transfers.Head_Object
  (Client, Origin, "bucket", "key", Identity);
Transfers.Transfer_Many
  (Client, Origin, Items, Results, Identity, Options => Options);
```

`Upload_File` switches to multipart at 64 MiB by default, streams 16 MiB parts
from one open descriptor, and exposes both thresholds as trailing policy
parameters. `Copy_Object` owns copy-source URI encoding and signing, including
special-character keys, and returns compact copy metadata or the structured
S3 error. `Head_Object` is the bodyless reconciliation primitive: its common
fields expose 64-bit size, entity tag, modification/content/version metadata,
while `Details` preserves every modeled response member. Trailing named
arguments cover all modeled conditions, range, response overrides, SSE-C,
request-payer, part, owner, and checksum controls. A structured rejection
preserves request IDs even when the HEAD response has no XML body. Multipart
parts for one file are deliberately sequential; batch
parallelism is across independent subjects. `Transfer_Many` remains a
synchronous structured scope and bounds concurrent objects, HTTP requests and
in-flight bytes independently. Flyology's runtime owns multiplexing,
backpressure and waiting, so the convenience layer does not create one task
per chunk or retain a massive object.

A lost response to CompleteMultipartUpload is inherently ambiguous: the
server may have committed the object. Best-effort abort is cleanup, not
rollback; applications that require certainty should reconcile with
HeadObject or an application-level manifest. The detailed policy is in
[client transfers](docs/architecture/client-transfers.md).

## Secret erasure boundary

Secure erasure does not inherently require C. This crate uses one tiny C11
volatile-store shim because it provides a stable optimizer-resistant boundary
across the supported Ada compilers. It wipes owned access keys, secret keys,
session tokens and derived SigV4 keys during finalization; it cannot erase
copies made by callers, runtimes, kernels, crash dumps or swap.

This is memory-secret hygiene, not a promise to physically erase deleted
objects. Filesystems with copy-on-write, snapshots, journaling, SSD wear
leveling, and SQLite/WAL history make physical object erasure a deployment and
storage-device policy. DeleteObject removes the live logical object according
to backend semantics.

## License

The Ada sources are available under MIT OR Apache-2.0. Vendored SQLite is in
the public domain; its exact provenance is recorded in
`sqlite/vendor/sqlite/README.md`.
