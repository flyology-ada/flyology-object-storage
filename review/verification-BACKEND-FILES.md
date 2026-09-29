# Adversarial verification: BACKEND-FILES (pure-files backend)

Scope verified by reading:
`src/flyology-object_storage-backends-files.ads`,
`src/flyology-object_storage-backends-files.adb` (path encoding 820-1060,
generation selection and publication numbering 1130-1300, chunked and
unbounded string IO 1470-1650, singleton configuration record readers
1775-2005, header write/read 2340-2910, manifest reading 3060-3095 and
3412-3460, object PUT 7005-7480, delete family 8118-8545, annotations
8930-9200, multipart 10790-12014),
`src/flyology-object_storage-backends.ads` (object, delete, annotation and
multipart contracts, `Byte_Source`/`Byte_Sink`, `Maximum_Bucket_Policy_Bytes`),
`src/flyology-object_storage-backends.adb` (`Valid_Bucket_Policy`),
`src/flyology-object_storage.ads`/`.adb` (`Valid_Object_Key`,
`Object_Annotation_Information`),
`src/flyology-object_storage-backends-memory.adb` (multipart completion,
`Upload_Index`, version publication) as the reference oracle,
`src/flyology-object_storage-server-s3_applications.adb:176-187`, `:1951-1954`,
`:3189-3200`, `:15622-15740` (admission bounds, status mapping, annotation
routing), `docs/architecture/files-layout.md`,
`docs/qualification/delete-object.md`, `docs/compatibility/s3.md`,
`review/baseline/service-2.json` (`ObjectKey` shape), the GNAT 16.1.0
toolchain `s-parame.adb` (default task stack) and flyology 0.1.1
`src/flyology-io-structured_servers.adb:386-391` (HTTP worker task
declaration).

Harness programs added: `tests/repros/src/repro_backend_files_support.ads`,
`tests/repros/src/repro_backend_files_support.adb`, and
`tests/repros/src/repro_backend_files_1.adb` through
`repro_backend_files_6.adb`. Every program was built and run only through
`tests/repros/run.sh`. Nothing tracked was modified; `git status --short`
shows only untracked additions under `review/` and `tests/repros/`. No Docker
server was used: every finding in this area is a backend-local claim.

Host: macOS (Darwin 25.6.0, arm64), `getconf PATH_MAX /` = 1024, GNAT 16.1.0
via Alire.

| ID | Verdict | Severity (discovery) | Repro |
|----|---------|----------------------|-------|
| BACKEND-FILES-1 | CONFIRMED (one sub-claim corrected) | P1 (P1) | `tests/repros/src/repro_backend_files_1.adb` |
| BACKEND-FILES-2 | CONFIRMED | P1 (P1) | `tests/repros/src/repro_backend_files_2.adb` |
| BACKEND-FILES-3 | CONFIRMED (worse than described) | P0 (P1) | `tests/repros/src/repro_backend_files_3.adb` |
| BACKEND-FILES-4 | CONFIRMED (variant (a); (b) read-verified, (c) unverifiable here) | P0 (P1) | `tests/repros/src/repro_backend_files_4.adb` |
| BACKEND-FILES-5 | CONFIRMED | P2 (P2) | `tests/repros/src/repro_backend_files_5.adb` |
| BACKEND-FILES-6 | CONFIRMED | P2 (P2) | `tests/repros/src/repro_backend_files_6.adb` |

No finding in this area was refuted, and no new defect (BACKEND-FILES-7 or
later) was found while verifying. Severity rubric is the shared one from the
brief.

---

### BACKEND-FILES-1: CompleteMultipartUpload in an unversioned bucket inherits the replaced object's annotations and orphans the previous annotation sidecar

**Verdict:** CONFIRMED (both sub-claims), with one correction to the
discovery's failure scenario: the *ordinary PUT then COMPLETE* sequence does
**not** expose the PUT generation's annotations through the API (the PUT
minted a fresh generation ID, so the path-derived ID of the completed record
differs) — that sequence produces only the orphan. Inheritance appears when
the replaced generation was itself produced by a completion, i.e. two
completions in a row on the same unversioned key.

**Severity:** P1 (discovery said P1). Annotations acknowledged against one
object generation are served for a different generation's bytes through a
plain S3 request sequence, and the sidecar leak is unreachable through the
API.

Verified by reading:

- `src/flyology-object_storage-backends-files.adb:2340-2350`,`:2493-2494` —
  `Write_Header` takes `Annotation_Generation_ID : String := ""` and writes it
  as the trailing header field.
- `src/flyology-object_storage-backends-files.adb:2811-2827` —
  `Read_Header_Any_With_Metadata` reads that trailing field back into
  `Info.Version`; the object's wire version ID is never persisted in the
  header.
- `src/flyology-object_storage-backends-files.adb:2873-2907` —
  `Stored_Annotation_Generation_ID` returns `Info.Version` when it is 64 bytes
  and `GNAT.SHA256.Digest (Selected.Path)` when it is empty.
- `src/flyology-object_storage-backends-files.adb:7093-7099` and `:7128-7132`
  — ordinary PUT mints a fresh ID per publication and writes it into the
  header; `:7247-7249` reads the previous generation's ID and `:7388-7392`
  removes that sidecar after the rename.
- `src/flyology-object_storage-backends-files.adb:11810-11811` and `:11854`
  — `Complete_Multipart_Upload` targets the fixed `Object_Path` when the
  bucket is `Versioning_Unconfigured` and calls
  `Write_Header (File, Key, Info, Parts => Completed_Parts)` with **no**
  `Annotation_Generation_ID`; the whole procedure never calls
  `Remove_Annotation_Generation*` (`rg` over `:11554-11954` finds none).
- `src/flyology-object_storage-backends-files.adb:891-909` — annotation
  reads/writes resolve the sidecar directory through
  `Annotation_Generation_Directory` → `Stored_Annotation_Generation_ID`.
- `src/flyology-object_storage-backends-memory.adb:3345` — the reference
  backend executes `Objects (Object_At).Annotations.Clear;` inside
  `Complete_Multipart_Upload`, so the intended contract is an empty
  annotation set on the newly published generation.
- Contract `src/flyology-object_storage-backends.ads:2288-2290` ("Atomically
  replace one named annotation on a **selected generation**").

Refutation attempts that failed:

- Checked whether the S3 adapter refuses annotations on a files store: `Store`
  is declared `... and Object_Annotation_Backend`
  (`src/flyology-object_storage-backends-files.ads:16-19`), and the adapter
  dispatches through the `*_If_Supported` wrappers.
- Checked versioned buckets: `:11812-11843` publishes under a generation file
  name containing the publication number, so the path-derived ID differs per
  publication and the defect is confined to `Versioning_Unconfigured` (the
  repro therefore uses an unversioned bucket).
- Checked whether the discovery's own step 1-4 scenario (PUT, annotate,
  COMPLETE) shows inheritance: it does not — see the "A:" lines in the output
  below, where the annotation correctly disappears from the API. Only the
  orphan survives there. This is the one sub-claim I had to weaken.
- Checked `Delete_Bucket` for a sidecar sweep: `:3575-3875` inspects
  `objects/`, `versions/`, `multipart/` and `configuration/`, so an orphan
  `generation-*` directory cannot be cleaned through the API.

**Repro:** `tests/repros/src/repro_backend_files_1.adb` (helper
`tests/repros/src/repro_backend_files_support.ad?`). It runs the same two
scenarios against the memory backend (control) and a files store on a fresh
scratch root: **A** ordinary `PutObject` → `PutObjectAnnotation` →
one-part `CompleteMultipartUpload` on the same key; **B**
`CompleteMultipartUpload` → `PutObjectAnnotation` →
`CompleteMultipartUpload` again. After each it asserts an empty annotation
page and `Annotation_Absent`, and finally counts `generation-*` directories
left on disk under each key's `annotations/` subtree.

**Output** (`cd tests/repros && ./run.sh repro_backend_files_1`, exit status
**1**):

```
  -- files root /private/tmp/claude-501/repro-bf1-67051-296774000
  ok: memory (control) CreateBucket succeeds
  ok: memory (control) PutObject succeeds
  ok: memory (control) PutObjectAnnotation put-then-complete/alpha
  ok: memory (control) ListObjectAnnotations put-then-complete succeeds
  ok: memory (control) the annotation is visible before replacement
  ok: memory (control) CreateMultipartUpload put-then-complete
  ok: memory (control) UploadPart put-then-complete
  ok: memory (control) CompleteMultipartUpload put-then-complete
  ok: memory (control) ListObjectAnnotations put-then-complete succeeds
  -- memory (control) A: annotations after COMPLETE replaced a PUT = 0
  ok: memory (control) ListObjectAnnotations put-then-complete succeeds
  ok: memory (control) A: the completed object starts with no annotations
  ok: memory (control) A: GetObjectAnnotation reports the annotation absent
  ok: memory (control) CreateMultipartUpload complete-twice
  ok: memory (control) UploadPart complete-twice
  ok: memory (control) CompleteMultipartUpload complete-twice
  ok: memory (control) PutObjectAnnotation complete-twice/beta
  ok: memory (control) ListObjectAnnotations complete-twice succeeds
  ok: memory (control) the annotation is visible before the second completion
  ok: memory (control) CreateMultipartUpload complete-twice
  ok: memory (control) UploadPart complete-twice
  ok: memory (control) CompleteMultipartUpload complete-twice
  ok: memory (control) ListObjectAnnotations complete-twice succeeds
  -- memory (control) B: annotations after the second COMPLETE = 0
  ok: memory (control) ListObjectAnnotations complete-twice succeeds
  ok: memory (control) B: the second completed object starts with no annotations
  ok: memory (control) B: GetObjectAnnotation reports the annotation absent
  ok: files  (subject) CreateBucket succeeds
  ok: files  (subject) PutObject succeeds
  ok: files  (subject) PutObjectAnnotation put-then-complete/alpha
  ok: files  (subject) ListObjectAnnotations put-then-complete succeeds
  ok: files  (subject) the annotation is visible before replacement
  ok: files  (subject) CreateMultipartUpload put-then-complete
  ok: files  (subject) UploadPart put-then-complete
  ok: files  (subject) CompleteMultipartUpload put-then-complete
  ok: files  (subject) ListObjectAnnotations put-then-complete succeeds
  -- files  (subject) A: annotations after COMPLETE replaced a PUT = 0
  ok: files  (subject) ListObjectAnnotations put-then-complete succeeds
  ok: files  (subject) A: the completed object starts with no annotations
  ok: files  (subject) A: GetObjectAnnotation reports the annotation absent
  ok: files  (subject) CreateMultipartUpload complete-twice
  ok: files  (subject) UploadPart complete-twice
  ok: files  (subject) CompleteMultipartUpload complete-twice
  ok: files  (subject) PutObjectAnnotation complete-twice/beta
  ok: files  (subject) ListObjectAnnotations complete-twice succeeds
  ok: files  (subject) the annotation is visible before the second completion
  ok: files  (subject) CreateMultipartUpload complete-twice
  ok: files  (subject) UploadPart complete-twice
  ok: files  (subject) CompleteMultipartUpload complete-twice
  ok: files  (subject) ListObjectAnnotations complete-twice succeeds
  -- files  (subject) B: annotations after the second COMPLETE = 1
  ok: files  (subject) ListObjectAnnotations complete-twice succeeds
  FAILED: files  (subject) B: the second completed object starts with no annotations
  FAILED: files  (subject) B: GetObjectAnnotation reports the annotation absent
  -- files A: sidecar generation- directories left under /private/tmp/claude-501/repro-bf1-67051-296774000/buckets/anno-bucket/annotations/7075742D7468656E2D636F6D706C657465.annotations = 1
  FAILED: files  (subject) A: the PUT generation's sidecar directory is removed by the completion that replaced it (no orphan)
  -- files B: sidecar generation- directories left under /private/tmp/claude-501/repro-bf1-67051-296774000/buckets/anno-bucket/annotations/636F6D706C6574652D7477696365.annotations = 1
  FAILED: files  (subject) B: the replaced completion's sidecar directory is removed by the second completion
  BUG REPRODUCED: 4 failed expectation(s)
```

**Description:** `Complete_Multipart_Upload` publishes its record through
`Write_Header` without supplying an `Annotation_Generation_ID`
(`files.adb:11854`), so the persisted generation field is empty and
`Stored_Annotation_Generation_ID` falls back to `SHA256(object path)`
(`files.adb:2892-2896`). In an unversioned bucket every generation of a key
lives at the same fixed `objects/<hex>.fos` path, so two completions in a row
share one annotation-sidecar identity: annotations written against the first
completed object are served, byte for byte and with their original ETag, as
annotations of the second completed object. The completion also never removes
the replaced generation's sidecar, which ordinary PUT does
(`files.adb:7388-7392`), so a completion that replaces a PUT-created
generation leaves a `generation-<minted id>` directory that no later request
can read or delete — `Delete_Bucket` does not inspect `annotations/`, so the
leak is permanent for the life of the root. Both effects are deterministic
and need no concurrency; any client that uses annotations plus multipart
uploads on an unversioned bucket hits them. The reference memory backend
clears the annotation map on completion
(`memory.adb:3345`), so the two backends disagree and no conformance test
covers the difference (`tests/src/multipart_part_conformance.adb` has no
annotation case; `tests/src/object_storage_test_cases.adb` has no
files-backend annotation-plus-multipart sequence). A fix needs a maintainer
decision on one point only: whether completion should mint a fresh annotation
generation ID (matching PUT) and remove the previous sidecar, or whether the
path-derived legacy fallback should be retired for records written by current
code; the latter changes the on-disk contract for FOSOBJ01-06 records.

---
### BACKEND-FILES-2: valid object keys beyond ~464 bytes are unusable on the files backend (macOS `PATH_MAX`)

**Verdict:** CONFIRMED. Measured threshold on this host: **464 bytes is the
largest key a files store rooted at a 49-byte path accepts; 465 bytes already
returns `Backend_Unavailable`.**

**Severity:** P1 (discovery said P1). A key the crate's own documented
boundary admits, and that the reference backend stores, is permanently
unusable on a CI-qualified platform, and the failure is reported as a
retryable 503.

Verified by reading:

- `src/flyology-object_storage.adb:479-489` — `Valid_Object_Key` admits
  `Value'Length in 1 .. 1_024` with no NUL; `src/flyology-object_storage.ads:667-670`
  documents "a nonempty key of at most 1,024 bytes without NUL".
- `src/flyology-object_storage-backends-files.adb:835-859` —
  `Encoded_Object_Path` emits two uppercase hex characters per key byte and
  starts a new path component every 100 characters (50 key bytes).
- `src/flyology-object_storage-backends-files.adb:217-239` (`Ensure_Directory`
  → `Ada.Directories.Create_Directory` on absolute paths) and `:7443-7457`
  (the `when others` handler maps the resulting `Use_Error` to
  `Backend_Unavailable`).
- `src/flyology-object_storage-server-s3_applications.adb:1951-1954` —
  `Capacity_Exceeded | Backend_Unavailable` → HTTP 503 `SlowDown`.
- `getconf PATH_MAX /` on this host returns **1024**.
- Pinned model `review/baseline/service-2.json`: the `ObjectKey` shape is
  `{"type":"string","min":1}` — no maximum is expressed. AWS S3's own 1,024-byte
  key limit is from memory, unverified; the crate's own documented bound
  (1,024 bytes) is what the repro asserts against.

Refutation attempts that failed:

- Searched `docs/architecture/files-layout.md`, `docs/compatibility/s3.md` and
  `src/flyology-object_storage-backends-files.ads` for a files-specific key
  length limit: none exists. `files-layout.md:4-6` says keys are "split into
  bounded path components", which bounds each component, not the total path.
- Checked `Maximum_Object_Path_Depth = 32` (`files.adb:113`): a 1,024-byte key
  needs 21 components, so the depth guard never fires; the failure is byte
  length, not depth.
- Checked for descriptor-relative access (`openat`, `O_NOFOLLOW`): every
  operation composes an absolute path through `Ada.Directories`/`Stream_IO`.
- Checked whether the memory backend also rejects long keys: it accepts the
  1,024-byte key (see the control line in the output).

The measured threshold matches the arithmetic exactly: a 49-byte root plus
`/buckets/long-key-bucket/objects` (33 bytes) is 82 bytes; a 464-byte key is
928 hex characters = 9 full components (9 x 101 = 909 with separators) plus
28 characters and `.fos` with its separator (33), giving 82 + 909 + 32 = 1023
= `PATH_MAX - 1`. Each further key byte adds two characters and crosses the
limit. A deployment with a longer root therefore has a proportionally lower
key ceiling.

**Repro:** `tests/repros/src/repro_backend_files_2.adb`. It asserts the
documented boundary, PUTs a 1,024-byte key on the memory backend (control)
and on a files store, then binary-searches the largest accepted key length on
this host and prints it.

**Output** (`cd tests/repros && ./run.sh repro_backend_files_2`, exit status
**1**):

```
  -- files root /private/tmp/claude-501/repro-bf2-67160-042364000 (49 bytes)
  ok: a 1,024-byte key satisfies the documented storage boundary
  ok: 1,024 bytes is the documented maximum
  ok: memory (control) CreateBucket
  -- memory (control) PUT 1024-byte key -> SUCCESS
  ok: memory (control) accepts a 1,024-byte key
  ok: files  (subject) CreateBucket
  -- files  (subject) PUT 8-byte key -> SUCCESS
  ok: files  (subject) accepts a short key (harness control)
  -- files  (subject) PUT 1024-byte key -> BACKEND_UNAVAILABLE
  FAILED: files  (subject) accepts a 1,024-byte key
  -- files  (subject) largest accepted key length on this host = 464 bytes; 465 bytes already fails
  -- files  (subject) status at 465 bytes -> BACKEND_UNAVAILABLE
  -- the S3 adapter maps Backend_Unavailable to 503 SlowDown (server-s3_applications.adb:1951-1954)
  BUG REPRODUCED: 1 failed expectation(s)
```

**Description:** The files backend expands every key byte to two hexadecimal
characters and inserts a path separator every 100 characters, so a key of N
bytes costs roughly 2.02N path bytes below `buckets/<name>/objects/`. macOS
enforces `PATH_MAX` = 1024 on every path-taking syscall, so `mkdir` on an
intermediate component fails `ENAMETOOLONG`, `Ada.Directories.Create_Directory`
raises `Use_Error`, and `Put_Object_Internal`'s `when others` handler reports
`Backend_Unavailable`, which the S3 adapter renders as 503 `SlowDown` — a
status stock clients (aws-cli, boto3) retry with backoff, so the request never
completes and never reports a permanent error. HEAD, GET and DELETE of such a
key fail identically, so an object written on Linux (where the limit is 4096)
becomes unreadable if the same root is opened on macOS. The threshold depends
on the root path length, so it is a deployment-dependent silent ceiling rather
than a fixed documented one. macOS is a qualified CI platform
(`.github/workflows/ci.yml` runs `os: [ubuntu-latest, macos-latest]`), and no
existing test puts a key longer than a few dozen bytes into a `Files.Store`
(`tests/src/object_storage_test_cases.adb` uses 1,024-byte keys only for
request parsing). A fix needs a maintainer decision on externally visible
policy: either a documented files-backend key-length limit reported as
`Invalid_Request`/`Capacity_Exceeded` rather than `Backend_Unavailable`, or a
path encoding that bounds total path length (for example digest-prefixed
sharding), which changes the on-disk layout.

---

### BACKEND-FILES-3: singleton bucket-configuration readers allocate the whole document on the calling task's stack; a 3 MiB acknowledged policy kills the reading process

**Verdict:** CONFIRMED, and worse than described: the failure in a
default-`Storage_Size` task is not a recoverable `Storage_Error` mapped to a
503 but an abrupt process termination (SIGKILL, shell status 137) with no Ada
exception and no diagnostic.

**Severity:** P0 (discovery said P1). Corrected upward because the reader
allocates a frame roughly 1 MiB below the end of a 2 MiB task stack — an
unchecked stack overflow, i.e. memory unsafety — and the observed effect is
the death of the whole process, which on a server takes down every concurrent
request, not just the offending one. If a maintainer's rubric treats an
unchecked overflow as availability-only, this is still at minimum P1 (an
acknowledged configuration that can never be read back).

Verified by reading:

- `src/flyology-object_storage-backends-files.adb:1579-1583` — `Read_String`
  declares `Result : String (1 .. Length)`, a dynamically sized local on the
  primary stack; only the 64 KiB `Data` buffer is chunked.
- `src/flyology-object_storage-backends-files.adb:1780-1796` —
  `Read_Bucket_Policy` (`:1780`) ends at `:1795` in `Policy :=
  US.To_Unbounded_String (Read_String (File, Length))`. The CORS
  (`:1809`, read at `:1824`), encryption (`:1839`/`:1857`),
  ownership-controls (`:1872`/`:1890`), lifecycle (`:1908`/`:1930`), logging
  (`:1947`/`:1965`) and notification (`:1980`/`:1998`) readers are identical
  in shape; the lifecycle reader additionally reads its metadata field the
  same way.
- `src/flyology-object_storage-backends-files.adb:1478-1504` and `:1610-1631`
  — the writer (`Write_String`) and the metadata/replication/website/named
  readers (`Read_Unbounded_String`) already chunk at 64 KiB, so the reader is
  the only unbounded step.
- `src/flyology-object_storage-backends.ads:2792` — `Maximum_Bucket_Policy_Bytes
  = 16 MiB`; `src/flyology-object_storage-backends.adb:199-200` —
  `Valid_Bucket_Policy` admits anything up to that bound.
- Toolchain `gnat_flyology_native_16.1.0_.../adainclude/s-parame.adb:55-66` —
  `Default_Stack_Size` returns `2 * 1024 * 1024` when
  `__gl_default_stack_size` is -1 (the default).
- flyology 0.1.1 `src/flyology-io-structured_servers.adb:386-391` — the
  handler `task type Worker` carries only `CPU => Handler_CPU` and a
  `Task_Info` pragma; **no `Storage_Size`**, so every HTTP worker runs on the
  2 MiB default.
- `src/flyology-object_storage-backends-files.adb:6258-6270` —
  `Get_Bucket_Policy`'s `when others` handler is what would turn a caught
  `Storage_Error` into `Backend_Unavailable`; in a secondary task the process
  never reaches it.

Refutation attempts that failed:

- Checked whether the S3 adapter clamps policies to AWS's 20 KB before they
  reach the backend: `src/flyology-object_storage-server-s3_applications.adb:176-187`
  sizes both the CORS and policy request bodies from
  `XML.Default_Limits.Maximum_Document_Bytes` (16 MiB).
- Checked whether GNAT heap-allocates a large dynamically sized local: it does
  not; only the returned copy uses the (heap-backed) secondary stack. The
  1 MiB child-process control in the repro succeeds and the 3 MiB one dies,
  bracketing the failure at the 2 MiB task stack.
- Checked whether the environment task hides the defect: it does not — the
  same 3 MiB read succeeds there (8 MiB process stack) and fails with
  `Backend_Unavailable` once the environment stack is partly consumed, which
  is exactly the stack-dependence the finding claims.

**Repro:** `tests/repros/src/repro_backend_files_3.adb`. It stores a 1 MiB and
a 3 MiB bucket policy on a files store, reads both back from the environment
task (control: both succeed, so the bytes are on disk and intact), and then
re-executes itself as a child process that performs each read from a task with
the GNAT default `Storage_Size`. The child is wrapped in `/bin/sh` so its
termination status is visible.

**Output** (`cd tests/repros && ./run.sh repro_backend_files_3 180`, exit
status **1**):

```
  -- files root /private/tmp/claude-501/repro-bf3-67416-331341000
  -- documents: 1048576 bytes and 3145728 bytes; documented admission bound is 16 MiB (backends.ads:2792); GNAT default task stack is 2 MiB
  ok: memory (control) CreateBucket
  ok: memory (control) PutBucketPolicy accepts 3 MiB
  -- memory (control) GetBucketPolicy -> SUCCESS length 3145728
  ok: memory (control) round-trips the 3 MiB policy
  ok: files  (subject) CreateBucket small-policy-bucket
  -- files  (subject) PutBucketPolicy(small-policy-bucket, 1048576 bytes) -> SUCCESS
  ok: files  (subject) PutBucketPolicy acknowledges small-policy-bucket
  -- files  (subject) GetBucketPolicy(small-policy-bucket) from the environment task -> SUCCESS length 1048576
  ok: files  (subject) the environment task reads small-policy-bucket back (the bytes are on disk and intact)
  ok: files  (subject) CreateBucket large-policy-bucket
  -- files  (subject) PutBucketPolicy(large-policy-bucket, 3145728 bytes) -> SUCCESS
  ok: files  (subject) PutBucketPolicy acknowledges large-policy-bucket
  -- files  (subject) GetBucketPolicy(large-policy-bucket) from the environment task -> SUCCESS length 3145728
  ok: files  (subject) the environment task reads large-policy-bucket back (the bytes are on disk and intact)
  -- [child] small-policy-bucket GetBucketPolicy from a default-Storage_Size task -> SUCCESS length 1048576
  -- [sh] child for small-policy-bucket terminated with status 0 (128+n means signal n)
/bin/sh: line 1: 79423 Killed: 9               '.../tests/repros/bin/repro_backend_files_3' worker '/private/tmp/claude-501/repro-bf3-67416-331341000' large-policy-bucket 3145728
  -- [sh] child for large-policy-bucket terminated with status 137 (128+n means signal n)
  -- files  (subject) child status for the 1 MiB policy 0
  ok: files  (subject) a default-stack task reads a 1 MiB policy back (child-process control)
  -- files  (subject) child status for the 3 MiB policy 137
  FAILED: files  (subject) a default-stack task reads the acknowledged 3 MiB policy back
  BUG REPRODUCED: 1 failed expectation(s)
```

(The absolute path in the `/bin/sh` diagnostic was shortened to `...` for
width; everything else is verbatim.)

**Description:** `Read_String` sizes a local `String` from the persisted
length, so reading a bucket policy (or CORS, encryption, ownership-controls,
lifecycle, logging or notification document) needs that many contiguous bytes
of the calling task's primary stack, while the writer streams the same
document in 64 KiB chunks and the admission bound is 16 MiB. Any document
larger than the reading task's stack is therefore writable, acknowledged with
200, durable on disk, and unreadable afterwards. Because Flyology's HTTP
worker task declares no `Storage_Size`, every server worker reads with GNAT's
2 MiB default, so the practical ceiling is roughly 2 MiB; the 16 MiB
documented bound also exceeds this host's 8 MiB process stack
(`ulimit -s` = 8176 KiB), so by the same mechanism it is unreachable even from
the environment task — that last step is an inference from the measured stack
sizes, not a separate measurement. The failure is not graceful: the
oversized frame skips past the task's guard page and the process is killed
(SIGKILL, status 137) with no Ada exception, so a single `GetBucketPolicy` for
an already-accepted configuration terminates the server for every client. It
is fully deterministic. Existing coverage does not reach it:
`tests/src/object_storage_test_cases.adb:1524-1579` round-trips 16 MiB only
through replication, which uses the chunked `Read_Unbounded_String`, and the
policy/CORS cases at `:583-657` and `:702-766` use short strings. The fix is
mechanical (route these readers through `Read_Unbounded_String`, as the
metadata/replication/website/named-configuration readers already do) and needs
no new maintainer decision unless the maintainer also wants a smaller
documented bound for these documents.

---

### BACKEND-FILES-4: a failed DeleteObject destroys the object's acknowledged annotations while leaving the object in place

**Verdict:** CONFIRMED for the deterministic, no-crash variant (the
discovery's scenario (a)), which is the strongest one. Scenario (b) — a crash
between the two steps — follows from the same ordering plus the fsync in
`Remove_Tree` and is verified by reading only, because the crash corpus lives
in `tests/src/files_crash_probe.adb` and `tests/scripts/test.sh`, which the
brief forbids me to modify. Scenario (c) (the btrfs-specific PUT-path window)
remains UNVERIFIABLE on this host (APFS).

**Severity:** P0 (discovery said P1). Corrected upward because acknowledged
payload data is destroyed by an operation that reports failure and did not
delete its target, with no request having asked for that deletion — data loss
under the rubric's first clause, not merely a wrong result.

Verified by reading:

- `src/flyology-object_storage-backends-files.adb:8430-8435` (unversioned
  current delete) and `:8419-8424` (exact-version delete) — both call
  `Remove_Annotation_Generation (Item, Bucket, Key, Selected)` and only then
  `Remove_Path (US.To_String (Selected.Path))`.
- `src/flyology-object_storage-backends-files.adb:1034-1046` and `:338-346` —
  `Remove_Annotation_Generation` → `Remove_Tree` → `Validate_Tree_Symlink_Free`,
  `Ada.Directories.Delete_Tree`, `Sync_Directory (Item, Parent)`. The removal
  is made durable before the unlink is even attempted.
- `src/flyology-object_storage-backends-files.adb:8320-8331` — `Remove_Path`
  raises `Data_Error` when the path is not an exact ordinary file, and
  `Ada.Directories.Delete_File` itself can fail.
- `src/flyology-object_storage-backends-files.adb:8517-8541` —
  `Delete_Objects` catches any such exception in `when others`, clears
  `Outcomes` and sets `Result := Backend_Unavailable`, so the caller is told
  the batch failed.
- `src/flyology-object_storage-backends-files.adb:7388-7395` — the PUT path
  has the same shape: the previous sidecar is removed after the rename but
  before the destination directory barrier.
- `docs/qualification/delete-object.md:46-51` documents that a status after
  publication is not proof that the object deletion did not occur. It says
  nothing about destroying a *different* acknowledged payload when the
  deletion demonstrably did not occur.

Refutation attempts that failed:

- Checked whether annotations are re-derivable from the object: they are
  independent payloads with their own size, ETag and checksum
  (`Object_Annotation_Information`, `flyology-object_storage.ads:571-577`).
- Checked whether the reverse order would merely leak: yes — an orphan
  `generation-*` directory is invisible and recoverable, and `Open` already
  sweeps `tmp/`, so a symmetric sweep is the obvious fix shape.
- Checked whether the S3 server can even reach annotations on a files store:
  `src/flyology-object_storage-server-s3_applications.adb:15622`, `:15653`,
  `:15683`, `:15736` dispatch through the `*_If_Supported` wrappers and the
  files `Store` implements `Object_Annotation_Backend`.
- Checked whether an outer retry repairs the state: nothing recreates a
  removed sidecar; a later successful `DeleteObject` removes only the object.

**Repro:** `tests/repros/src/repro_backend_files_4.adb`. It seeds an object
plus one annotation twice. The control key is deleted with no injection (both
disappear, so the harness and the sequence are sound). For the subject key it
makes `buckets/<b>/objects/` mode `0500` — the sidecar removal only needs
`annotations/`, the unlink needs write permission on `objects/` — calls
`DeleteObject`, restores the mode, and then asserts that the surviving object
still has its annotation.

**Output** (`cd tests/repros && ./run.sh repro_backend_files_4`, exit status
**1**):

```
  -- files root /private/tmp/claude-501/repro-bf4-67511-185835000
  ok: CreateBucket
  ok: PutObject control-key
  ok: PutObjectAnnotation control-key/alpha
  ok: control: the annotation is listed before the delete
  -- control: DeleteObject -> SUCCESS
  ok: control: the uninjected delete succeeds
  ok: control: the object is gone after a successful delete
  ok: PutObject doomed-key
  ok: PutObjectAnnotation doomed-key/alpha
  ok: the annotation is listed before the injected delete
  ok: chmod 0500 /private/tmp/claude-501/repro-bf4-67511-185835000/buckets/delete-bucket/objects succeeds
  -- injected: DeleteObject -> BACKEND_UNAVAILABLE
  ok: chmod 0700 /private/tmp/claude-501/repro-bf4-67511-185835000/buckets/delete-bucket/objects succeeds
  ok: the injected delete is reported as failed
  ok: the object survives the failed delete
  -- annotations listed for the surviving object = 0
  FAILED: the surviving object keeps the annotation that no request ever asked to delete
  -- GetObjectAnnotation(doomed-key/alpha) -> SUCCESS presence ANNOTATION_ABSENT
  FAILED: the annotation payload is still readable after the failed delete
  BUG REPRODUCED: 2 failed expectation(s)
```

**Description:** `Delete_One` destroys the object's annotation sidecar,
including an fsync of the sidecar's parent directory, before it issues the
unlink that is the delete's publication point. If the unlink fails — EACCES on
a directory that lost write permission, EPERM after a read-only remount, EIO,
or `Data_Error` because a concurrent external change made the path something
other than an ordinary file — `Delete_Objects` reports `Backend_Unavailable`
(503 `SlowDown` at the S3 boundary), the object is still there and still
readable, and the annotations that the client stored and the server
acknowledged are gone with no request having asked for their deletion, no
recovery path, and no diagnostic distinguishing this from an ordinary
transient failure. The same window exists across a crash: because the sidecar
removal is fsynced before the unlink is issued, a power loss in between leaves
exactly this state on any filesystem, and the deterministic crash matrix in
`tests/scripts/test.sh` plus `tests/src/files_crash_probe.adb` contains no
annotation scenario at all, so it is not gated. The reproduction is fully
deterministic. A fix should be a plain reordering (unlink first, then sweep
the sidecar, with an orphan sweep on `Open` for the crash case); it needs no
new public constant or API, but the maintainer must decide whether the orphan
sweep belongs in `Open`, in `Delete_Bucket`, or both.

---
### BACKEND-FILES-5: multipart operations with a valid upload ID but a different key return `Backend_Unavailable` instead of `Not_Found`

**Verdict:** CONFIRMED for all four entry points (`UploadPart`, `ListParts`,
`CompleteMultipartUpload`, `AbortMultipartUpload`).

**Severity:** P2 (discovery said P2). It needs a client mistake to trigger, so
it stays an edge case, but the consequence is a wrong diagnostic that turns a
permanent error into an indefinitely retried one, and the two backends
disagree.

Verified by reading:

- `src/flyology-object_storage-backends-files.adb:3412-3446` — `Read_Manifest`
  locates the manifest by `Bucket` and `Upload_ID` only
  (`Inspect_Manifest_Path`, `Manifest_Path`), then calls
  `Read_Header (File, Key, Info, Body_At)`.
- `src/flyology-object_storage-backends-files.adb:3070-3087` — `Read_Header`
  raises `Ada.IO_Exceptions.Data_Error` when the stored key differs from the
  expected key.
- `src/flyology-object_storage-backends-files.adb:10829-10837` — the presence
  test before it is `Manifest_Exists (Item, Bucket, Upload_ID)`, which does
  not consider the key; the same shape appears at `:11114-11122` (ListParts),
  `:11611-11618` (Complete) and `:11980-11986` (Abort).
- `src/flyology-object_storage-backends-files.adb:11061-11078` and the
  matching handlers in the other three: `when others => ... Result :=
  Backend_Unavailable`. `Data_Error` is nowhere special-cased.
- `src/flyology-object_storage-backends.ads:2657-2659` — "Upload identifiers
  are backend-generated, opaque, nonempty, and **scoped to the exact bucket and
  key**"; `:2771-2773` — "A missing upload is `Not_Found`".
- `src/flyology-object_storage-backends-memory.adb:332-346` — `Upload_Index`
  matches bucket, key and ID together, so the memory backend reports
  `Not_Found`.
- `src/flyology-object_storage-server-s3_applications.adb:1951-1954` —
  `Backend_Unavailable` → 503 `SlowDown`.

Refutation attempts that failed:

- Looked for a key check before `Read_Manifest` in all four entry points and
  in `Manifest_Exists`: there is none.
- Considered whether the upload ID's derivation from the key
  (`files.adb:10690-10694`) prevents the case: it does not — the ID is opaque
  and the upload directory is named `SHA256 (Upload_ID)`, independent of the
  key, so a manifest for key `alpha` is found under a request for key `beta`.
- Checked existing coverage: `tests/src/multipart_part_conformance.adb`
  never uses a mismatched key and makes no `Not_Found` assertion at all.

**Repro:** `tests/repros/src/repro_backend_files_5.adb`. It runs the identical
sequence on the memory backend (control) and a files store: create an upload
for key `alpha`, upload a part with the correct key (sanity control), then
drive `UploadPart`, `ListParts`, `CompleteMultipartUpload` and
`AbortMultipartUpload` for key `beta` with that upload ID, asserting
`Not_Found` each time.

**Output** (`cd tests/repros && ./run.sh repro_backend_files_5`, exit status
**1**):

```
  -- files root /private/tmp/claude-501/repro-bf5-66816-683503000
  ok: memory (control) CreateBucket succeeds
  ok: memory (control) CreateMultipartUpload succeeds
  -- memory (control) upload id length 64
  -- memory (control) UploadPart(correct key) -> SUCCESS
  ok: memory (control) UploadPart with the correct key succeeds
  -- memory (control) UploadPart(wrong key) -> NOT_FOUND
  ok: memory (control) UploadPart with a mismatched key is Not_Found
  -- memory (control) ListParts(wrong key) -> NOT_FOUND
  ok: memory (control) ListParts with a mismatched key is Not_Found
  -- memory (control) CompleteMultipartUpload(wrong key) -> NOT_FOUND
  ok: memory (control) Complete with a mismatched key is Not_Found
  -- memory (control) AbortMultipartUpload(wrong key) -> NOT_FOUND
  ok: memory (control) Abort with a mismatched key is Not_Found
  ok: files  (subject) CreateBucket succeeds
  ok: files  (subject) CreateMultipartUpload succeeds
  -- files  (subject) upload id length 64
  -- files  (subject) UploadPart(correct key) -> SUCCESS
  ok: files  (subject) UploadPart with the correct key succeeds
  -- files  (subject) UploadPart(wrong key) -> BACKEND_UNAVAILABLE
  FAILED: files  (subject) UploadPart with a mismatched key is Not_Found
  -- files  (subject) ListParts(wrong key) -> BACKEND_UNAVAILABLE
  FAILED: files  (subject) ListParts with a mismatched key is Not_Found
  -- files  (subject) CompleteMultipartUpload(wrong key) -> BACKEND_UNAVAILABLE
  FAILED: files  (subject) Complete with a mismatched key is Not_Found
  -- files  (subject) AbortMultipartUpload(wrong key) -> BACKEND_UNAVAILABLE
  FAILED: files  (subject) Abort with a mismatched key is Not_Found
  BUG REPRODUCED: 4 failed expectation(s)
```

**Description:** The files backend resolves an active multipart upload by
upload ID alone and only discovers the key mismatch when `Read_Header`
validates the manifest's stored key, which it signals with `Data_Error`; every
multipart entry point's blanket `when others` handler turns that into
`Backend_Unavailable`, and the S3 boundary renders it as 503 `SlowDown`. A
client that mistypes or mangles a key on a retry therefore gets a retryable
server-overload response where AWS and the reference memory backend return a
definitive 404 `NoSuchUpload`; aws-cli and boto3 retry 503 with exponential
backoff, so the request loop terminates only when the retry budget is
exhausted, and an `AbortMultipartUpload` sent with the wrong key can never
retire the upload nor tell the client why. The backend contract at
`backends.ads:2657-2659` and `:2771-2773` says upload identifiers are scoped
to the exact bucket and key and that a missing upload is `Not_Found`, so this
is a documented-contract violation as well as a cross-backend divergence. It
is deterministic. No existing test asserts either behaviour. A fix is a key
comparison before `Read_Manifest` (or mapping `Data_Error` from the manifest
key check to `Not_Found`) and needs no new maintainer decision.

---

### BACKEND-FILES-6: deleting the newest generation lets the next PUT reuse the deleted generation's opaque version ID

**Verdict:** CONFIRMED, including the second-order consequence: after the
reuse, `GET key?versionId=<deleted id>` serves the *new* object's bytes.

**Severity:** P2 (discovery said P2). It stays P2 because it needs an exact
delete of the newest generation followed by a republish, but note the
consequence is stronger than "two versions share an ID": a client or replica
holding the old version ID silently reads different bytes under it.

Verified by reading:

- `src/flyology-object_storage-backends-files.adb:1254-1270` —
  `Next_Generation_Publication` scans the retained generations and returns
  `max(publication) + 1`; an empty directory yields 1.
- `src/flyology-object_storage-backends-files.adb:7288-7297` — the opaque
  version ID is `SHA256 (domain, Bucket, Key, Long_Long_Integer'Image
  (Publication))`, a pure function of the publication number. The same
  derivation appears for delete markers at `:8246-8250` and for multipart
  completion at `:11821-11829`.
- `src/flyology-object_storage-backends-files.adb:8419-8424` — an exact
  delete of a non-marker generation calls `Remove_Path`, which unlinks the
  generation file outright, leaving nothing that keeps the counter high.
- `src/flyology-object_storage-backends-memory.adb` — the memory backend uses
  a monotonic `Version_Publication_Order` counter, so its IDs never repeat
  (the control in the repro confirms this).
- Contract `src/flyology-object_storage-backends.ads:50-52` — "@enum
  Exact_Version Select one generated opaque version identifier"; files-backend
  note `files.adb:47-49` — "The value is an opaque S3 identity". S3's
  uniqueness of version IDs per object version is from memory, unverified.

Refutation attempts that failed:

- Checked whether tombstones or delete markers keep the counter high: exact
  deletes remove the file with no residue (`:8419-8424`), and the
  `Null_Tombstone` path at `:8400-8418` applies only to null-version deletes,
  where it is itself removed by `Remove_Path` immediately after
  `Remove_Superseded_Null_Generations`.
- Checked whether the annotation sidecar could collide as a result: PUT mints
  a fresh annotation generation ID per publication (`:7093-7099`), so the
  sidecar identity does not repeat (this is what keeps BACKEND-FILES-1 out of
  the versioned path — except for a completion, which mints none).
- Checked whether the reuse can produce a duplicate file name at publication:
  it cannot, the old file is gone, so the failure is identity reuse rather
  than a local error.

**Repro:** `tests/repros/src/repro_backend_files_6.adb`. Versioning enabled;
`PUT k = "AAAA"` → V1; `Delete_Selected_Object (k, Exact V1)`; `PUT k =
"BBBB"` → V2; assert `V2 /= V1` and that `GET k?versionId=V1` does not serve
`"BBBB"`. The memory backend runs the identical sequence first as the control.

**Output** (`cd tests/repros && ./run.sh repro_backend_files_6`, exit status
**1**):

```
  -- files root /private/tmp/claude-501/repro-bf6-66888-742845000
  ok: memory (control) CreateBucket succeeds
  ok: memory (control) versioning enabled
  ok: memory (control) first PUT succeeds
  -- memory (control) V1 = fda44a6321d0e2d57a2c2c3e611e58b1cb46bb78665b52a0c95fc6eb2d9eff69
  -- memory (control) DELETE versionId=V1 -> SUCCESS
  ok: memory (control) exact delete of V1 succeeds
  ok: memory (control) second PUT succeeds
  -- memory (control) V2 = 64315f7b3a3cb1d53b86836356810b6115bc08ec33fc24d40663d3d25f2702a7
  ok: memory (control) the republished version ID differs from the deleted one
  -- memory (control) GET versionId=V1 -> NOT_FOUND body=""
  ok: memory (control) GET of the deleted version ID does not serve the new bytes
  ok: files  (subject) CreateBucket succeeds
  ok: files  (subject) versioning enabled
  ok: files  (subject) first PUT succeeds
  -- files  (subject) V1 = 0972e6ee85f810eaa3704c8907a13fc770ba5d0db58255e6d1b97eef10ac12c4
  -- files  (subject) DELETE versionId=V1 -> SUCCESS
  ok: files  (subject) exact delete of V1 succeeds
  ok: files  (subject) second PUT succeeds
  -- files  (subject) V2 = 0972e6ee85f810eaa3704c8907a13fc770ba5d0db58255e6d1b97eef10ac12c4
  FAILED: files  (subject) the republished version ID differs from the deleted one
  -- files  (subject) GET versionId=V1 -> SUCCESS body="BBBB"
  FAILED: files  (subject) GET of the deleted version ID does not serve the new bytes
  -- files root retained for inspection: /private/tmp/claude-501/repro-bf6-66888-742845000
  BUG REPRODUCED: 2 failed expectation(s)
```

**Description:** The files backend derives an object's opaque version ID
deterministically from `max(existing publication) + 1`, and an exact delete
removes the generation file outright, so the counter is not monotonic across
deletions. Deleting the newest generation (or every generation above some N)
and republishing mints the deleted generation's exact version ID again, and
`GET key?versionId=<that id>` then returns the new bytes with status 200
instead of 404 — a client, replicator or audit consumer that keyed on
(key, version ID) silently reads different content under an identifier it
believes it has already seen or already deleted. The memory backend uses a
monotonic counter and does not repeat, so the two backends disagree on an
externally visible identity. The effect is deterministic. Existing coverage
only asserts that three consecutive publications differ
(`tests/src/versioned_object_conformance.adb:544-549`); no test deletes the
newest generation and republishes. A fix needs a maintainer decision, because
it changes the on-disk layout or record format: either persist a per-key
monotonic publication high-water mark, or leave a tombstone for exact deletes
the way null deletes already do, or mix an entropy source into the version-ID
digest (which would end the current property that the ID is reproducible from
the generation file name).

---

## Observations not counted as findings

- The `docs/compatibility/s3.md` annotation rows say "server absent" (for
  example the `DeleteObjectAnnotation` row at `:48`), while
  `src/flyology-object_storage-server-s3_applications.adb:3189-3200` routes
  the `?annotation` query and `:15622`, `:15653`, `:15683`, `:15736` dispatch
  all four operations to the backend. Documentation drift; it does not change
  the reachability of BACKEND-FILES-1 or -4, which the code path establishes.
- BACKEND-FILES-1's discovery scenario steps 1-4 (ordinary PUT, annotate,
  then one multipart completion) does **not** expose the annotation through
  the API, because the PUT minted its own generation ID. Only the orphan
  survives there. Two completions in a row are what produce inheritance. The
  repro shows both.
- BACKEND-FILES-3 in the environment task is stack-headroom dependent: with a
  3 MiB local already on the environment stack, the same read returned
  `Backend_Unavailable` rather than succeeding. That is the same defect, not a
  separate one, but it means the failure mode a caller sees (503 versus
  process death) depends on which task issues the read.
