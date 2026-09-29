# Correctness discovery: BACKEND-FILES (pure-files backend, durability bridge, secure erase)

Scope: `src/flyology-object_storage-backends-files.ads` (complete);
`src/flyology-object_storage-backends-files.adb` (complete for path helpers
1-1460, record format 1460-2340 and 2340-2875, annotation/generation helpers
2873-3210, tombstone recovery and Open 3206-3575, bucket create/list/delete
3575-3875, bucket tags 3875-3985, generic configuration-document
put/get/delete 4651-4960, metadata state 5163-5312, named-configuration
listing 5671-5850, versioning 6680-6870, Object Lock enablement 6867-6960,
object put/copy/head/attributes/get 7005-8120, delete family 8118-8545,
object-lock update/read 8545-8820, annotations 8930-9813, object tags
9813-10070, listings 10070-10655, multipart 10655-12014; skimmed only:
per-family thin wrappers 4956-6094, bucket policy/control wrappers
6094-6680, PublicAccessBlock 4116-4360, CORS wrappers 4360-4617);
`src/flyology-object_storage-durability.ads/.adb`,
`src/flyology_object_storage_durability.c`,
`src/flyology_object_storage_secure_erase.c` (complete);
`src/flyology-object_storage-backends.ads` (object, delete, listing,
multipart and annotation contracts); `src/flyology-object_storage.adb`
`Valid_Bucket_Name`/`Valid_Object_Key`; memory backend regions used for
comparison (`Upload_Index`, `Multipart_Configuration`, ListObjectVersions
marker handling); S3 adapter error mapping
(`server-s3_applications.adb:1951-1954`) and admission bounds (176-187).
Reference material: `docs/architecture/files-layout.md`,
`docs/qualification/{conditional-put,put-object,delete-object,delete-objects,
bucket-versioning,complete-multipart-upload,abort-multipart-upload,
copy-object,continuous-integration}.md`, `docs/compatibility/s3.md`
(annotation rows), `.github/workflows/ci.yml` (matrix), GNAT 13.2
`s-parame.adb` in the local toolchain (task stack default).
Existing coverage inspected: `tests/scripts/test.sh` (symlink and 140-case
crash matrix), `tests/src/files_crash_probe.adb`,
`tests/src/files_conditional_symlink_probe.adb`, `tests/src/files_open_probe.adb`,
`tests/src/flyology-object_storage-backends-files-testing.ad?`,
`tests/src/flyology-object_storage-durability_testing.ad?`,
`tests/src/object_storage_test_cases.adb` files-store sections (5413-7100,
bucket-configuration bounds 1524-1872 and 5838-5848),
`tests/src/{conditional_put,versioned_object,multipart_part,copy_object}_conformance.adb`,
`tests/generated/s3-operation-tests.sh` (corpus launch list).

Severity rubric: P0 memory/aliasing unsafety, security (traversal, symlink
escape, secret exposure, authz bypass), data loss or durability violation
(acknowledged write not durable or silently corrupted), hang/deadlock, or
interop-breaking protocol violation; P1 wrong result or unexpected exception
on valid input via a reachable path, or a documented contract violated; P2
edge-case incorrectness, wrong diagnostics, or contract drift needing unusual
input.

| ID | Title | Severity | Confidence |
|----|-------|----------|------------|
| BACKEND-FILES-1 | CompleteMultipartUpload in an unversioned bucket inherits the replaced object's annotations (path-derived annotation generation) and orphans PUT-created annotation directories | P1 | High |
| BACKEND-FILES-2 | Valid object keys longer than roughly 400-450 bytes produce paths beyond macOS `PATH_MAX` (1024); PUT/HEAD/GET of such keys fail with `Backend_Unavailable` (HTTP 503) on a CI-qualified platform | P1 | High |
| BACKEND-FILES-3 | Bucket policy/CORS/encryption/ownership/lifecycle/logging/notification readers allocate the whole document on the task stack via `Read_String`; documents accepted up to 16 MiB cannot be read back once they exceed the task stack (2 MiB GNAT default) | P1 | High |
| BACKEND-FILES-4 | Annotation sidecars are removed durably before the object mutation reaches its publication or durability point, so a failed unlink or a crash leaves the surviving generation without its acknowledged annotations | P1 | Medium |
| BACKEND-FILES-5 | Multipart operations with a valid upload ID but a different key return `Backend_Unavailable` (503 SlowDown) instead of `Not_Found` (404 NoSuchUpload); the memory backend returns `Not_Found` | P2 | High |
| BACKEND-FILES-6 | Opaque version IDs are derived from `max(existing publication)+1`, so deleting the newest generation lets the next PUT reuse the deleted generation's version ID | P2 | High |

---

### BACKEND-FILES-1: CompleteMultipartUpload in an unversioned bucket inherits the replaced object's annotations (path-derived annotation generation) and orphans PUT-created annotation directories

**Location:** `src/flyology-object_storage-backends-files.adb:11855`,
`src/flyology-object_storage-backends-files.adb:2873-2900`,
`src/flyology-object_storage-backends-files.adb:7094-7099`,
`src/flyology-object_storage-backends-files.adb:7247-7256`,
`src/flyology-object_storage-backends-files.adb:7389-7392`,
`src/flyology-object_storage-backends-files.adb:9152-9156`

**Severity:** P1. **Confidence:** High.

**Evidence:**

`src/flyology-object_storage-backends-files.adb:11811` and `:11855`
(Complete_Multipart_Upload: unversioned target is the fixed object path; the
record is written without an annotation generation ID):

```ada
         Target := US.To_Unbounded_String (Object_Path (Item, Bucket, Key));
...
      Write_Header (File, Key, Info, Parts => Completed_Parts);
```

`src/flyology-object_storage-backends-files.adb:2873-2900` (annotation
generation identity falls back to a hash of the file path when the record
carries no generation ID):

```ada
   function Stored_Annotation_Generation_ID
     (Selected : Selected_Generation) return String
   is
   ...
      if US.Length (Info.Version) = Generated_Version_ID_Length then
         return US.To_String (Info.Version);
      elsif US.Length (Info.Version) = 0 then
         --  FOSOBJ01 through FOSOBJ06 predate annotation generations.  Their
         --  path-derived identity preserves the established sidecar layout.
         return GNAT.SHA256.Digest (US.To_String (Selected.Path));
```

`src/flyology-object_storage-backends-files.adb:7094-7099` and
`:7247-7256`, `:7389-7392` (ordinary PUT mints a fresh generation ID per
publication and removes the previous generation's sidecar directory):

```ada
      Annotation_Generation_ID := US.To_Unbounded_String
        (GNAT.SHA256.Digest
           ("flyology-files-annotation-generation" & Character'Val (0) &
            Bucket & Character'Val (0) & Key & Character'Val (0) &
            Long_Long_Integer'Image (Number) & Character'Val (0) &
            Ada.Calendar.Time'Image (Ada.Calendar.Clock)));
...
            Previous_Annotation_ID := US.To_Unbounded_String
              (Stored_Annotation_Generation_ID (Previous));
...
      if US.Length (Previous_Annotation_ID) > 0 then
         Remove_Annotation_Generation_For_ID
           (Item, Bucket, Key, US.To_String (Previous_Annotation_ID));
      end if;
```

`src/flyology-object_storage-backends-files.adb:9152-9156`
(Put_Object_Annotation resolves the sidecar directory through the same
`Stored_Annotation_Generation_ID`):

```ada
      Ensure_Directory
        (Item, Annotation_Generation_Directory
           (Item, Bucket, Key, Selected));
      Target := US.To_Unbounded_String
        (Annotation_Path (Item, Bucket, Key, Selected, Name));
```

Contract, `src/flyology-object_storage-backends.ads` (Put_Object_Annotation:
"Atomically replace one named annotation on a selected generation"; Copy_Object:
"Copy_Annotations preserves the selected source generation's complete
annotation set; Exclude_Annotations publishes an empty set"). The ordinary PUT
path implements the intent that a newly published generation starts with no
annotations (it passes `Exclude_Annotations` at `:7473` and removes the
previous sidecar); multipart completion neither mints an ID nor removes the
previous sidecar.

**Failure scenario:**
1. Bucket `b` is unversioned. A multipart upload for key `k` is completed
   (record R1 at `objects/<hex(k)>.fos`, header annotation ID empty, so its
   effective ID is `SHA256(path)`).
2. `Put_Object_Annotation (b, k, "a", ...)` writes
   `annotations/<hex(k)>.annotations/generation-<SHA256(path)>/<SHA256("a")>.fos`.
3. A second multipart upload for `k` is completed: R2 replaces R1 by rename
   at the same path (`:11811`, `:11855`), again with an empty annotation ID.
   No sidecar removal occurs (contrast `:7389-7392`).
4. `List_Object_Annotations (b, k)` / `Get_Object_Annotation (b, k, "a")` on
   R2 resolve the directory via `SHA256(path)` and return annotation `a`,
   which belonged to the replaced generation.
5. Orphan variant: R0 created by ordinary PUT (fresh ID A) with annotations;
   a multipart completion replaces it: `generation-A` is never removed and is
   invisible to every later generation (disk leak; `Delete_Bucket` does not
   inspect `annotations/`, so it cannot be cleaned through the API).

**Reproduction test sketch:** files-backend directory only (annotations are
an `Object_Annotation_Backend` capability; the S3 application routes
`PutObjectAnnotation`/`ListObjectAnnotations` to the backend,
`server-s3_applications.adb:6512-6526`). With a `Files.Store` and an
unversioned bucket: `Create_Multipart_Upload`, `Put_Multipart_Part` (1 part),
`Complete_Multipart_Upload` for `k`; `Put_Object_Annotation (k, "a", payload)`
expect Success; repeat initiate/part/complete for `k`;
`List_Object_Annotations (k)` expected: empty page (as after
`Put_Object` replacement, which the same sketch shows returns empty); actual:
one entry `a`. Also assert that after PUT then COMPLETE the directory
`annotations/<hex(k)>.annotations/generation-<A>` still exists.

**Existing coverage:** `tests/src/s3_list_object_annotations_qualification.adb`
and `tests/src/s3_delete_object_annotation_corpus.adb` exercise the S3 layer
against the memory application; `object_storage_test_cases.adb` has no
files-backend annotation + multipart sequence; `files_crash_probe.adb` has no
annotation scenario. None asserts either direction.

**Refutation attempts:** Checked whether `Complete_Multipart_Upload` calls
`Remove_Annotation_Generation*` or passes `Annotation_Generation_ID` (it does
not; only `Put_Object_Internal` at `:7389`, `Delete_One` at `:8421/:8432`, and
`Remove_Superseded_Null_Generations` at `:1423/:1437` remove sidecars).
Checked versioned buckets: enabled/suspended completions publish under a new
generation file name (`:11816-11838`), so the path-derived ID differs and the
suspended path's `Remove_Superseded_Null_Generations` removes the old sidecar;
the defect is limited to `Versioning_Unconfigured`. Checked whether the S3
adapter refuses annotations for the files backend: it dispatches through
`*_If_Supported` and `Store` implements `Object_Annotation_Backend`
(`files.ads:14-16`). Checked whether `Put_Object_Tags`/object-lock rewrites
would reset the ID: they persist `Stored_Annotation_Generation_ID (Selected)`
(`:9875`, `:8615`), i.e. they freeze the path-derived value, which does not
change the outcome.

---

### BACKEND-FILES-2: Valid object keys longer than roughly 400-450 bytes produce paths beyond macOS `PATH_MAX` (1024); PUT/HEAD/GET of such keys fail with `Backend_Unavailable` (HTTP 503) on a CI-qualified platform

**Location:** `src/flyology-object_storage-backends-files.adb:835-860`,
`src/flyology-object_storage-backends-files.adb:217-239`,
`src/flyology-object_storage-backends-files.adb:7404-7457`,
`src/flyology-object_storage.adb:479-489`

**Severity:** P1. **Confidence:** High.

**Evidence:**

`src/flyology-object_storage-backends-files.adb:835-860` (two hex characters
per key byte, one directory component per 50 key bytes):

```ada
   function Encoded_Object_Path
     (Root : String; Key : String; Suffix : String) return String
   is
      Result  : US.Unbounded_String := US.To_Unbounded_String (Root);
      Segment : String (1 .. 100);
      Used    : Natural := 0;
   begin
      for Character_Value of Key loop
         Segment (Used + 1) :=
           Hex (Character'Pos (Character_Value) / 16);
         Segment (Used + 2) :=
           Hex (Character'Pos (Character_Value) mod 16);
         Used := Used + 2;
         if Used = Segment'Length then
            US.Set_Unbounded_String
              (Result, Join (US.To_String (Result), Segment));
            Used := 0;
         end if;
      end loop;
```

`src/flyology-object_storage.adb:479-489` (the storage boundary admits keys
of up to 1,024 bytes; the `.ads` comment at `flyology-object_storage.ads:666-670`
documents "a nonempty key of at most 1,024 bytes without NUL"):

```ada
   function Valid_Object_Key (Value : String) return Boolean is
   begin
      if Value'Length not in 1 .. 1_024 then
         return False;
      end if;
```

`src/flyology-object_storage-backends-files.adb:217-239` (ancestor
directories are created with absolute paths; `Create_Directory` raises on
`ENAMETOOLONG`) and `:7443-7457` (the `when others` handler maps any such
exception to `Backend_Unavailable`):

```ada
         Ensure_Directory (Item, Parent);
         Ada.Directories.Create_Directory (Path);
...
         Info := Empty_Info;
         Identity := (others => <>);
         if In_Callback then
            raise;
         else
            Result := Backend_Unavailable;
         end if;
```

`src/flyology-object_storage-server-s3_applications.adb:1951-1954`:

```ada
         when Capacity_Exceeded | Backend_Unavailable =>
            Send_Error
              (X, 503, "SlowDown",
               "Please reduce your request rate", Resource);
```

`.github/workflows/ci.yml:62-68` (`os: [ubuntu-latest, macos-latest]`) and
`docs/qualification/continuous-integration.md:3-5` ("run the complete root
and SQLite test scripts on Linux and macOS").

External fact: Darwin enforces `PATH_MAX` = 1024 (including the terminator)
on every path-taking syscall and returns `ENAMETOOLONG`; Linux enforces 4096.
A 1,024-byte key encodes to 20 directory components of 100 characters plus a
52-character leaf (2,072 bytes below `objects/`); a retained generation adds
`.versions/` and a 90-character generation file name. With a root such as
`/private/tmp/<x>/root/buckets/<63>/objects/` (~130 bytes), keys beyond
approximately 440 bytes (unversioned) or 390 bytes (versioned) exceed 1023
bytes on macOS. On Linux the same happens only when the root path itself is
longer than about 2,000 bytes.

**Failure scenario:** A stock client (`aws s3 cp` / boto3 `put_object`) sends
`PUT /b/<600-byte key>` to the files-backed server on macOS.
`Put_Object_Internal` stages the body under `tmp/` (short path), acquires the
gate, `Select_Generation` -> `Encoded_Ancestors_Exist` sees `stat` fail
(`Ada.Directories.Exists` returns False on any `stat` error) and reports no
generation, then `Ensure_Directory (Containing_Directory (Target))` reaches a
component whose absolute path exceeds 1023 bytes; `mkdir` fails
`ENAMETOOLONG`, `Create_Directory` raises `Use_Error`, the handler returns
`Backend_Unavailable`, and the server answers 503 SlowDown. Retrying never
succeeds. `HEAD`/`GET` of an existing key at that length (created on Linux and
moved to macOS) fail the same way; `List_Objects` cannot enumerate it either.

**Reproduction test sketch:** files-backend directory on macOS (or Linux with a
root of ~2,000 characters): `Files.Open ("/tmp/r")`, `Create_Bucket ("b")`,
`Put_Object ("b", String'(1 .. 1_024 => 'k'), ...)`. Expected: `Success`
(the key satisfies `Valid_Object_Key`, and the memory backend accepts it).
Actual on macOS: `Backend_Unavailable`. Add the same key through
`tests/src/s3_files_server.adb` and observe HTTP 503 with `SlowDown`.

**Existing coverage:** `object_storage_test_cases.adb:8880-8887` and the
`*_retention_corpus` `Key_Boundary` cases use 1,024-byte keys only for
request parsing/preparation; no test puts a key longer than a few dozen
bytes into a `Files.Store`. The macOS CI lane runs `tests/scripts/test.sh`,
which never exercises long keys on files.

**Refutation attempts:** Looked for a documented key-length limit specific to
the files backend in `files-layout.md`, `docs/compatibility/s3.md`, and the
`.ads` (none; the spec says keys are "opaque bytes encoded as uppercase
hexadecimal and split into bounded path components", which bounds component
length, not total path length). Checked whether `Open` shortens the root
(`Full_Name` makes it absolute, possibly longer). Checked whether any
descriptor-relative (`openat`) access exists (none; every operation uses
absolute paths through `Ada.Directories`/`Stream_IO`). Checked
`Maximum_Object_Path_Depth = 32` (`:113`): it bounds recursion depth, not
byte length, and 1,024-byte keys need only 21 levels.

---

### BACKEND-FILES-3: Bucket policy/CORS/encryption/ownership/lifecycle/logging/notification readers allocate the whole document on the task stack via `Read_String`; documents accepted up to 16 MiB cannot be read back once they exceed the task stack

**Location:** `src/flyology-object_storage-backends-files.adb:1579-1608`,
`src/flyology-object_storage-backends-files.adb:1780-1796`,
`src/flyology-object_storage-backends-files.adb:1809-1825`,
`src/flyology-object_storage-backends-files.adb:1857`, `:1890`, `:1930`,
`:1965`, `:1998`

**Severity:** P1. **Confidence:** High.

**Evidence:**

`src/flyology-object_storage-backends-files.adb:1474-1476` and `:1579-1608`
(the comment recognises the bound; `Read_String` still declares a local
`String` sized by the persisted length):

```ada
   File_String_IO_Chunk_Bytes : constant Positive := 64 * 1_024;
   --  Match the files backend's existing streaming chunk convention while
   --  bounding the stack working set independently of the admitted value.
...
   function Read_String
     (File : in out SIO.File_Type; Length : Natural) return String
   is
      Result : String (1 .. Length);
      Data   : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset
          (File_String_IO_Chunk_Bytes));
```

`src/flyology-object_storage-backends-files.adb:1780-1796` (policy reader;
CORS at `:1809-1825`, encryption `:1857`, ownership `:1890`, lifecycle
`:1930`, logging `:1965`, notification `:1998` are identical in shape):

```ada
   procedure Read_Bucket_Policy
     (File : in out SIO.File_Type; Policy : out US.Unbounded_String)
   is
   ...
      if File_Magic /= Bucket_Policy_Magic
        or else Byte_Count (Length) > Maximum_Bucket_Policy_Bytes
   ...
      Policy := US.To_Unbounded_String (Read_String (File, Length));
```

`src/flyology-object_storage-backends-files.adb:1610-1631` and `:2062-2067`,
`:2104`, `:2137`, `:2180-2181` (metadata state, replication, website and
named configurations already use the chunked `Read_Unbounded_String`).

`src/flyology-object_storage-backends.ads:2792` and
`src/flyology-object_storage-server-s3_applications.adb:176-177`, `:186-187`
(admission bound is 16 MiB for both the backend and the S3 route):

```ada
   Maximum_Bucket_Policy_Bytes : constant Byte_Count := 16 * 1_024 * 1_024;
...
   Maximum_Bucket_CORS_Body : constant Byte_Count :=
     Byte_Count (XML.Default_Limits.Maximum_Document_Bytes);
...
   Maximum_Bucket_Policy_Body : constant Byte_Count :=
     Byte_Count (XML.Default_Limits.Maximum_Document_Bytes);
```

External fact (GNAT 13.2 `adainclude/s-parame.adb:55-62` in the local Alire
toolchain): a task whose `Storage_Size` is unspecified gets
`2 * 1024 * 1024` bytes of primary stack. The environment task uses the
process limit (typically 8 MiB).

**Failure scenario:** `PutBucketPolicy` (or `PutBucketCors`, encryption,
ownership controls, lifecycle, logging, notification) with a 4 MiB canonical
document is admitted (`Valid_Bucket_Policy`, `:199-200` of `backends.adb`),
written in 64 KiB chunks (`Write_String`, `:1478-1504`), synced and renamed:
the server acknowledges 200. The next `GetBucketPolicy` from a server worker
task calls `Read_Bucket_Policy` -> `Read_String (File, 4 MiB)`; the 4 MiB
local overflows a 2 MiB task stack; GNAT raises `Storage_Error` (or the
process dies if the guard page is not honoured on that platform), the
`when others` handler in `Get_Bucket_Policy` returns `Backend_Unavailable`,
and the client receives 503 SlowDown forever for an acknowledged
configuration. A 16 MiB document (the documented limit) also overflows the
8 MiB environment task, so even single-threaded callers cannot read it back.
The same document round-trips through the memory backend.

**Reproduction test sketch:** files-backend directory. Extend
`Exercise_Bucket_Singleton_Configuration_Bounds`
(`tests/src/object_storage_test_cases.adb:1524-1579`, called with a
`Files.Store` at `:5843`) to `Put_Bucket_Policy (Bucket, At_Limit.all)` then
`Get_Bucket_Policy`; expected: `Success` with 16 MiB returned (as the
existing replication case asserts at `:1546-1556`); actual: `Backend_Unavailable`
(or `Storage_Error`). To show the task-stack case, run the same Get from a
task with default `Storage_Size` using a 3 MiB policy.

**Existing coverage:** `object_storage_test_cases.adb:1524-1579` round-trips
16 MiB only through replication (chunked reader) and only rejects over-limit
website/notification documents; `:1785-1872` round-trips 16 MiB named
configurations (chunked reader). Policy/CORS tests (`:583-657`, `:702-766`)
use short strings. No test reads a large policy/CORS/encryption/ownership/
lifecycle/logging/notification record from files.

**Refutation attempts:** Verified that GNAT places a dynamically sized local
`String` on the primary stack (no heap fallback) and that only the returned
copy uses the (heap-backed) secondary stack. Checked whether the S3 adapter
bounds policies to AWS's 20 KB: it uses the 16 MiB XML budget
(`s3_applications.adb:186-187`, `:10158`). Checked for an explicit worker
`Storage_Size` in `src/` and `server/src/` (none found; the HTTP worker task
size lives in the `flyology_http` dependency, not in this worktree, so the
exact threshold is the one uncertainty, not the overflow at 16 MiB).

---

### BACKEND-FILES-4: Annotation sidecars are removed durably before the object mutation reaches its publication or durability point, so a failed unlink or a crash leaves the surviving generation without its acknowledged annotations

**Location:** `src/flyology-object_storage-backends-files.adb:8421-8424`,
`src/flyology-object_storage-backends-files.adb:8432-8435`,
`src/flyology-object_storage-backends-files.adb:7389-7395`,
`src/flyology-object_storage-backends-files.adb:1034-1046`,
`src/flyology-object_storage-backends-files.adb:338-346`

**Severity:** P1. **Confidence:** Medium.

**Evidence:**

`src/flyology-object_storage-backends-files.adb:8430-8435` (Delete_One,
unversioned current delete; the exact-version branch at `:8419-8424` is the
same shape):

```ada
                  if Condition_Exists then
                     Outcome.Publication.Kind := Object_Version_Removed;
                     Remove_Annotation_Generation
                       (Item, Bucket, Key, Selected);
                     Remove_Path (US.To_String (Selected.Path));
```

`src/flyology-object_storage-backends-files.adb:1034-1046` and `:338-346`
(sidecar removal is a durable `Delete_Tree` + parent sync):

```ada
      if Annotation_Directory_Exists (Item, Bucket, Key, Selected) then
         Remove_Tree (Item, Directory);
      end if;
...
      Validate_Tree_Symlink_Free (Path);
      Ada.Directories.Delete_Tree (Path);
      Sync_Directory (Item, Parent);
```

`src/flyology-object_storage-backends-files.adb:8320-8331` (`Remove_Path`
raises `Data_Error` before unlinking when the object path is not an exact
ordinary file, and `Delete_File` itself can fail):

```ada
         procedure Remove_Path (Path : String) is
         begin
            if GNAT.OS_Lib.Is_Symbolic_Link (Path)
              or else not Ada.Directories.Exists (Path)
              or else Ada.Directories.Kind (Path) /=
                Ada.Directories.Ordinary_File
            then
               raise Ada.IO_Exceptions.Data_Error;
            end if;
            Ada.Directories.Delete_File (Path);
```

`src/flyology-object_storage-backends-files.adb:7388-7395` (unversioned
PUT: the previous sidecar is removed after `rename` but before the directory
barrier that makes the rename durable):

```ada
      Published := True;
      if US.Length (Previous_Annotation_ID) > 0 then
         Remove_Annotation_Generation_For_ID
           (Item, Bucket, Key, US.To_String (Previous_Annotation_ID));
      end if;
      Sync_Directory
        (Item, Ada.Directories.Containing_Directory (US.To_String (Target)));
```

Contract: `docs/architecture/files-layout.md:46-47` ("reopens the root and
requires a well-formed old-or-new state") and `:22-25` ("readers can observe
only the old complete record or the new complete record");
`docs/qualification/delete-object.md` ("Pure-files unlink is the publication
point").

**Failure scenario:**
(a) Delete path, no crash needed: object `k` with annotation `a`.
`Delete_Object (b, k)` runs `Remove_Annotation_Generation` (sidecar durably
gone) and then `Remove_Path`; `Delete_File` fails (EIO, EPERM on a read-only
remount, or `Data_Error` from a concurrent external change). The handler
returns `Backend_Unavailable`; the object remains and every later
`Get_Object_Annotation (k, "a")` reports `Annotation_Absent` although no
delete of the annotation was ever acknowledged and the object delete was
reported as failed.
(b) Crash between the two steps yields the same state on any filesystem,
because the sidecar removal is fsynced before the unlink is issued.
(c) PUT path: crash after `:7389-7392` and before `:7393-7394`; on a
filesystem where a directory fsync does not transitively commit an earlier
rename in a different directory (btrfs's per-inode log), the old record
survives without its sidecar.

**Reproduction test sketch:** files-backend directory. Deterministic variant
of (a): after `Put_Object` and `Put_Object_Annotation`, make
`buckets/b/objects/` unwritable (`chmod 0500`) and call `Delete_Object`;
expected: `Backend_Unavailable` with the annotation still listed; actual:
`Backend_Unavailable` and `List_Object_Annotations` returns an empty page.
Crash variant: add a `delete-with-annotation` scenario to
`files_crash_probe.adb` crashing at the sidecar-parent barrier (the first
barrier of the delete) and verify on reopen that either the object and its
annotation both exist or neither does.

**Existing coverage:** `tests/scripts/test.sh` crash matrix (`delete 1`,
`delete-objects 2`, `put 3`) and `files_crash_probe.adb` contain no
annotation scenario (`rg -i annotation` finds nothing there). No fault
injection targets `Delete_File`.

**Refutation attempts:** Checked whether annotations are re-derivable from
the object (no: they are independent payloads with their own ETag/checksum).
Checked whether removing the sidecar after the unlink would leak on crash
instead (it would leave an orphan, which is recoverable and invisible, unlike
silent loss; `Open` already sweeps `tmp/`, so a sweep of orphan
`generation-*` directories would be the symmetric fix). Checked ext4/XFS/APFS
ordering for (c) and found the PUT-path window is filesystem-dependent, which
is why (a)/(b) drive the severity and confidence rather than (c).

---

### BACKEND-FILES-5: Multipart operations with a valid upload ID but a different key return `Backend_Unavailable` (503 SlowDown) instead of `Not_Found` (404 NoSuchUpload); the memory backend returns `Not_Found`

**Location:** `src/flyology-object_storage-backends-files.adb:3412-3448`,
`src/flyology-object_storage-backends-files.adb:3070-3088`,
`src/flyology-object_storage-backends-files.adb:10829-10837`,
`src/flyology-object_storage-backends-files.adb:11122`, `:11618`, `:3459`

**Severity:** P2. **Confidence:** High.

**Evidence:**

`src/flyology-object_storage-backends-files.adb:3423-3435` (the manifest is
located by upload ID alone, then the stored key must equal the request key):

```ada
      Inspect_Manifest_Path (Item, Bucket, Upload_ID, Exists);
      if not Exists then
         raise Ada.IO_Exceptions.Name_Error;
      end if;
      Validate_Upload_Contents (Item, Bucket, Upload_ID);
      SIO.Open (File, SIO.In_File, Manifest_Path (Item, Bucket, Upload_ID));
      Read_Header (File, Key, Info, Body_At);
```

`src/flyology-object_storage-backends-files.adb:3084-3087`:

```ada
      if US.To_String (Key) /= Expected then
         raise Ada.IO_Exceptions.Data_Error;
      end if;
```

`src/flyology-object_storage-backends-files.adb:10830-10837` (Put_Multipart_Part;
List_Multipart_Parts `:11115-11122`, Complete `:11611-11618`, Abort
`:11980-11986` follow the same sequence, and each `when others` handler ends
in `Result := Backend_Unavailable`):

```ada
      if not Manifest_Exists (Item, Bucket, Upload_ID)
      then
         Result := Not_Found;
         Item.Publication.Release;
         Locked := False;
         return;
      end if;
      Read_Manifest (Item, Bucket, Key, Upload_ID, Upload_Options);
```

`src/flyology-object_storage-backends-memory.adb:332-346` and `:2875-2890`
(memory looks the upload up by bucket, key and ID and reports `Not_Found`):

```ada
      function Upload_Index
        (Bucket : String; Key : String; Upload_ID : String) return Natural
      ...
         Index : constant Natural := Upload_Index (Bucket, Key, Upload_ID);
      begin
         Options := Default_Multipart_Options;
         if Index = 0 then
            Result := Not_Found;
```

Contract, `src/flyology-object_storage-backends.ads:2657-2658` ("Upload
identifiers are backend-generated, opaque, nonempty, and scoped to the exact
bucket and key") and `:2771-2773` ("A missing upload is Not_Found");
`server-s3_applications.adb:1951-1954` maps `Backend_Unavailable` to
503 SlowDown.

**Failure scenario:** A client initiates an upload for key `a` and then, by
mistake or during a retry with a mangled key, sends `UploadPart` /
`ListParts` / `CompleteMultipartUpload` / `AbortMultipartUpload` for key `b`
with that upload ID. On files: `Manifest_Exists` is true (ID matches),
`Read_Manifest` raises `Data_Error` on the key mismatch, the handler
returns `Backend_Unavailable`, and the server answers 503 SlowDown, which
stock clients (aws-cli, boto3) treat as retryable and retry with backoff. The
same request on the memory backend or on AWS is a definitive 404
NoSuchUpload. `Abort` with the wrong key never succeeds, so the upload can
only be retired with the right key, but the client cannot learn that from the
response.

**Reproduction test sketch:** `Multipart_Part_Conformance.Exercise` style,
runnable on both backends: `Create_Multipart_Upload (b, "a") -> ID`;
`Put_Multipart_Part (b, "b", ID, 1, src)`; expected `Not_Found` (memory
result); actual on files `Backend_Unavailable`. Same for `List_Multipart_Parts`,
`Complete_Multipart_Upload`, `Abort_Multipart_Upload` with key `"b"`. Over
HTTP through `s3_files_server`: expect 404 NoSuchUpload, observe 503.

**Existing coverage:** `tests/src/multipart_part_conformance.adb` never uses
a mismatched key (no `Not_Found` assertion at all); `object_storage_test_cases.adb`
key-mismatch multipart checks run against the memory application only.

**Refutation attempts:** Looked for a key check before `Read_Manifest` in all
five multipart entry points (none). Considered whether the upload ID
embedding the key (`SHA256 (Bucket & NUL & Key & ...)`, `:10690-10694`)
prevents the case: it does not, the ID is opaque and the directory is named
by `SHA256 (Upload_ID)` regardless of key. Confirmed `Data_Error` is not
special-cased anywhere in the handlers.

---

### BACKEND-FILES-6: Opaque version IDs are derived from `max(existing publication)+1`, so deleting the newest generation lets the next PUT reuse the deleted generation's version ID

**Location:** `src/flyology-object_storage-backends-files.adb:1254-1270`,
`src/flyology-object_storage-backends-files.adb:7290-7297`,
`src/flyology-object_storage-backends-files.adb:8246-8250`,
`src/flyology-object_storage-backends-files.adb:11824-11829`

**Severity:** P2. **Confidence:** High.

**Evidence:**

`src/flyology-object_storage-backends-files.adb:1254-1270`:

```ada
   function Next_Generation_Publication
     (Item : Store; Bucket : String; Key : String) return Long_Long_Integer
   is
      Highest : Long_Long_Integer := 0;
   ...
      Scan_Generations (Item, Bucket, Key, Consider'Access);
      if Highest = Long_Long_Integer'Last then
         raise Storage_Error;
      end if;
      return Highest + 1;
```

`src/flyology-object_storage-backends-files.adb:7290-7297` (the same
derivation appears for delete markers at `:8246-8250` and multipart
completion at `:11824-11829`):

```ada
            Publication := Next_Generation_Publication (Item, Bucket, Key);
            if Kind = Opaque_Object then
               Version_ID := US.To_Unbounded_String
                 (GNAT.SHA256.Digest
                    (Files_Version_ID_Domain & Character'Val (0) &
                     Bucket & Character'Val (0) & Key & Character'Val (0) &
                     Long_Long_Integer'Image (Publication)));
```

Contract: `src/flyology-object_storage-backends.ads:50-52` ("@enum
Exact_Version Select one generated opaque version identifier") and the
files-backend note at `files.adb:47-49` ("Flyology files versions use one
SHA-256 hexadecimal digest. The value is an opaque S3 identity"). S3 version
IDs are unique per object version (AWS S3 User Guide, "Using versioning";
from memory, unverified).

**Failure scenario:** Versioning enabled. `PUT k` (payload A) publishes
`0000000000000000001-O-<H1>.fos` with `x-amz-version-id: H1`, H1 =
SHA256(domain, b, k, " 1"). `DELETE k?versionId=H1` removes the only
generation. `PUT k` (payload B): `Next_Generation_Publication` scans an empty
directory, returns 1, and publishes `...001-O-<H1>.fos` again: the client
receives the same `x-amz-version-id: H1` for different bytes. A replication
or audit consumer keyed on (key, version ID) treats B as already seen, or a
client that cached "H1 was deleted" wrongly believes `GET k?versionId=H1` must
404. The same holds whenever every generation numbered above N is removed
by exact deletes (e.g. delete the newest two, put once).

**Reproduction test sketch:** files-backend directory (memory uses a
monotonic counter, `Objects (Index).Publication`). `Put_Bucket_Versioning
(Enabled)`, `Put_Object (k, "A") -> V1`, `Delete_Selected_Object (k, Exact V1)`,
`Put_Object (k, "B") -> V2`; expected: `V2 /= V1`; actual: `V2 = V1`. Then
`Get_Object (k, Selector => Exact V1)` returns "B".

**Existing coverage:** `tests/src/versioned_object_conformance.adb:544-549`
asserts distinctness of three consecutive publications only ("enabled
version IDs are not bounded and unique"); no test deletes the newest
generation and republishes.

**Refutation attempts:** Checked whether tombstones or delete markers keep
the counter high (exact deletes remove the file outright, `:8419-8424`;
`Remove_Path` leaves nothing behind). Checked whether the annotation sidecar
could collide (no: annotation generation IDs are minted per publication and
stored in the header, `:7094-7099`). Considered whether reuse can produce a
duplicate file name at publication time (no, the old file is gone), so the
consequence is identity reuse rather than a local failure.

---

## Areas reviewed with no findings

- Key path encoding (`Encoded_Object_Path`, `:835-860`): injective, uppercase
  hex only, no `.`/`..`/separator components, no case-folding collisions,
  distinct suffixes for object (`.fos`), generation (`.versions`) and
  annotation (`.annotations`) trees; NUL excluded by `Valid_Object_Key`.
- Path components from untrusted identifiers: upload IDs (`SHA256`),
  annotation names (`SHA256`), named-configuration identifiers (`SHA256`),
  exact version IDs (compared against directory scan, never composed into a
  path), bucket names (`Valid_Bucket_Name` restricts to `[a-z0-9.-]`, 3..63,
  no leading/trailing dot, no `..`).
- Symlink handling: every path is checked symlink-first before kind/exists;
  `Validate_Immediate_Directory` uses raw `readdir` so dangling links are
  detected; TOCTOU against a hostile local process is explicitly out of
  contract (`files-layout.md:80-85`).
- Publication gate discipline: all 55 `Acquire_Publication` sites release on
  every normal and exceptional path (235 `Release` calls inspected by
  pattern); `Acquire_Publication` itself releases on `Validate_Required_Roots`
  failure; the timed entry loop honours deadline and cancellation.
- Publication sequences (temp under `tmp/`, `Validate_New_Temp_Target`,
  `Sync_File`, `rename`, `Sync_Directory` of destination then `tmp/`) for
  object PUT, tags, object-lock rewrite, versioning, Object Lock enablement,
  bucket tags, policy, CORS and every singleton/named configuration
  document, metadata state, bucket create (staged tree) and delete, multipart
  initiate (staged directory with synced manifest), part, completion (assembled
  record synced before rename; upload tree removed after publication), abort.
  Temp files/directories are removed on every failure path inspected.
- Conditional writes: `If-Match`/`If-None-Match` are evaluated under the gate
  against the freshly read header immediately before `rename` in PUT, COPY
  (through `Put_Object_Internal`) and multipart completion; two concurrent
  create-if-absent writers serialize correctly.
- Generation selection (`Select_Generation`): current/null/exact semantics,
  legacy `objects/` file as null version, delete-marker placement (enabled:
  opaque marker; suspended: null marker replacing the null generation),
  tombstone-based exact-null deletion with `Recover_Null_Tombstones` on
  `Open`; `Remove_Superseded_Null_Generations` also removes sidecars.
- ListObjectVersions: bytewise key order, newest-publication-first within a
  key, `IsLatest` for markers, key/version marker resume, common-prefix
  cursor advancement and dedup; ListObjects lists only the current
  non-marker generation per key (prefix/delimiter/cursor logic is the shared
  `Listing` builder, not re-reviewed here).
- Streaming reads: `Get_Object`, `Get_Object_Annotation`, `Copy_Object`
  snapshot creation hold the file descriptor across gate release, so unlink,
  tag rewrite or abort by a concurrent task cannot tear a reader on POSIX.
- Record format (`Write_Header`/`Read_Header_Any_With_Metadata`): bounded
  lengths for every field, exact file-size check against `Body_At + Size`,
  in-place patch offsets (`Body_Size_Position = 29`,
  `Metadata_Position = 37`) verified against the header layout, part
  metadata monotonic and size-summed, checksum/method consistency.
- Durability bridge: `Sync` frees the C string on every path; `F_FULLFSYNC`
  with `fsync` fallback; fault injection cannot leak; `secure_erase` is a
  volatile byte loop.
- Resource handling: every `SIO.File_Type`, `Search_Type` and
  `GNAT.Directory_Operations.Dir_Type` inspected is closed in the matching
  `when others` handler; `Copy_Object` retires its snapshot and annotation
  staging on all paths.

## Observations not counted

- `Complete_Multipart_Upload` (`:11554-11954`) and `Copy_Object` snapshot
  creation (`:7693-7725`) hold the publication gate while copying the whole
  body (up to 5 GiB per copy, up to 5 TiB per completion); every other
  operation on the store blocks for that duration and deadline-bound callers
  fail with `Timeout_Error`. Bounded stall, not a hang; a design/latency
  concern.
- `List_Object_Versions` (`:10604-10610`) and the memory backend
  (`memory.adb:2677-2687`) both return `Invalid_Request` when a supplied
  key-marker/version-id-marker pair no longer exists (e.g. the marked version
  was deleted between pages). Consistent across backends; AWS behaviour not
  verifiable from the model, so recorded rather than counted.
- `docs/architecture/files-layout.md:123-136` still describes the FOSOBJ05
  single-file layout, `Not_Implemented` for enabled-bucket PUT and no
  retained generations, while the code implements FOSOBJ07 with a generation
  history; `docs/qualification/copy-object.md:55` says "the backend cannot
  contain annotations" while `Store` implements `Object_Annotation_Backend`.
  Documentation drift only.
- `files-layout.md:137-139` describes DeleteObjects as "a complete nonmutating
  preflight before the first removal"; the preflight (`:8461-8476`) is
  structural only and each entry's conditions are evaluated inside the
  removal loop, so a later conditioned duplicate observes earlier removals.
  This matches S3 per-entry semantics; the doc wording overstates it.
- `Put_Object_Internal` samples `Info.Modified` before the body is streamed
  (`:7113`), so `Last-Modified` reflects upload start; ordering uses
  publication numbers, so listings stay correct.
- `Open` takes no cross-process lock; two processes opening one root corrupt
  each other's staging assumptions. Documented as unsupported.
- `Has_Objects` (`:3508-3510`) calls `End_Search` in its handler even when
  `Start_Search` never ran; harmless with GNAT's implementation and shadowed
  by the outer `when others`.
- `List_Objects`/`List_Object_Versions` call `Select_Generation` (a directory
  scan) per file, making listings O(files x generations); performance only.
- `Get_Object` reports `Partial => False` for a range request on an empty
  object (`Empty_Object_Range`, `:8042-8050`); range resolution policy lives in
  the core package, outside this area.
- Policy values not counted: `Maximum_Object_Path_Depth = 32`,
  `Maximum_Metadata_Length = 8 KiB`, `Maximum_Checksum_Length = 96`,
  64 KiB streaming buffers, 10 ms gate poll interval, 16 MiB document bounds.
