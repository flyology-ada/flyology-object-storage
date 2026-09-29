# Correctness discovery: SQLite backend (BACKEND-SQLITE)

Scope: read in full: `src/flyology-object_storage-backends.ads` (contract),
`sqlite/src/flyology-object_storage-backends-sqlite.ads`,
`sqlite/src/flyology-object_storage-sqlite-catalogs.ads`,
`sqlite/src/flyology-object_storage-sqlite-databases.ads/.adb`,
`sqlite/src/flyology-object_storage-sqlite-c.ads`,
`sqlite/src/flyology_object_storage_sqlite_durability.c`,
`docs/architecture/sqlite-backend.md`, `sqlite/alire.toml`,
`sqlite/tests/src/s3_sqlite_server.adb`,
`tests/src/flyology-object_storage-backends-testing.ad?`,
`docs/qualification/object-annotations-backend-server.md`.
Read by region: `sqlite/src/flyology-object_storage-sqlite-catalogs.adb`
lines 1-1000 (schema DDL, column codecs, tag/metadata/annotation helpers,
gate, `Scalar`), 1742-1880 (`Create_Schema`), 1965-2245 (upgrades V4-V10),
2588-3200 (`Open`, `Close`, buckets, versioning, object lock), 3341-3400
(`Delete_Bucket`), 4327-4430 (point-configuration listing), 4677-5025
(metadata-state CAS), 5454-9179 (object select/publish/delete, lock,
tags, annotations, listing, multipart, payload reference).
`sqlite/src/flyology-object_storage-backends-sqlite.adb` lines 1-320,
2025-2900, 3118-3537, 3601-4430; the bucket-configuration wrappers at
320-2025 were inspected by outline only. Not read line by line: catalog
schema validators 1000-1742 and the bucket tag/PAB/CORS/document wrappers
3397-4327, 4428-4677, 5025-5454. Coverage inspected by outline and `rg`:
`sqlite/tests/src/flyology_object_storage_sqlite_tests.adb`,
`tests/src/object_storage_test_cases.adb`,
`tests/src/s3_server_application_corpus.adb`,
`tests/src/s3_implementation_corpus.adb`,
`tests/scripts/test-flyology-server.sh`. Reference: the shared
`Merge_Bucket_Versioning` contract at `src/flyology-object_storage.ads:349-362`
and body at `src/flyology-object_storage.adb:365-373`; SQLite API semantics
are cited from memory (unverified) where marked; the vendored amalgamation
was not read.

Severity rubric: P0 = memory/aliasing unsafety, security bypass, data loss
or durability violation, hang or deadlock in normal operation, or an
interop-breaking protocol violation a stock client rejects. P1 = wrong result
or unexpected exception on valid input via a reachable path, or a documented
contract violated. P2 = edge-case incorrectness, wrong diagnostics, or
contract drift needing unusual input.

| ID | Title | Severity | Confidence |
|----|-------|----------|------------|
| BACKEND-SQLITE-1 | `Get_Object` (and part assembly) opens the payload after the catalog gate is released, so a concurrent overwrite/delete turns a valid GET into `Backend_Unavailable` | P2 | Medium |
| BACKEND-SQLITE-2 | Annotation copy-lease release decrements `refs` to 0 under `CHECK(refs>0)`, so the first `Copy_Object` of any annotated source raises after publication and leaks the lease | P1 | High |
| BACKEND-SQLITE-3 | `Find_Selected_Object` handler runs lease release before `Gate.Release`; a raise there leaves the catalog gate held forever (permanent hang of every backend call) | P0 | Medium |
| BACKEND-SQLITE-4 | `Delete_Bucket` ignores retained generations; a bucket whose keys all end in delete markers hits the `ON DELETE RESTRICT` foreign key and reports `Backend_Unavailable` (HTTP 503 SlowDown) instead of `Bucket_Not_Empty` | P1 | High |
| BACKEND-SQLITE-5 | Annotation qualification record claims backend/server corpus evidence "across the implementations", but no SQLite test exercises any annotation operation | P2 | High |

---

### BACKEND-SQLITE-1: `Get_Object` opens the payload after the catalog gate is released

**Location:** `sqlite/src/flyology-object_storage-backends-sqlite.adb:2666-2683`
(also `4067-4072` in `Copy_Multipart_Part` and `4295-4301` in
`Complete_Multipart_Upload`)

**Severity:** P2. **Confidence:** Medium.

**Evidence:**

`sqlite/src/flyology-object_storage-backends-sqlite.adb:2666-2683`
```ada
      Catalogs.Find_Selected_Object
        (Item.Catalog, Bucket, Key, Selector, Payload, Info, Result);
      if Result /= Success then
         return;
      elsif not Is_Payload_Name (US.To_String (Payload)) then
         raise Ada.IO_Exceptions.Data_Error;
      end if;
      Result := Evaluate_Read_Conditions
        (Conditions, US.To_String (Info.Entity_Tag), Info.Modified);
      if Result /= Success then
         return;
      end if;
      SIO.Open
        (File, SIO.In_File,
         Join (Objects_Path (Item), US.To_String (Payload)));
      if SIO.Size (File) /= SIO.Count (Info.Size) then
         raise Ada.IO_Exceptions.Data_Error;
      end if;
```

No `Check` callback is passed, so the gate is released inside
`Find_Selected_Object` before `SIO.Open`. The sibling operations do use the
hook for exactly this purpose:

`sqlite/src/flyology-object_storage-backends-sqlite.adb:2581-2583` (HEAD)
```ada
      Catalogs.Find_Selected_Object
        (Item.Catalog, Bucket, Key, Selector, Payload, Info, Result,
         Check_Payload'Access);
```
`sqlite/src/flyology-object_storage-backends-sqlite.adb:2448-2451` (COPY)
```ada
      Catalogs.Find_Selected_Object
        (Item.Catalog, Source_Bucket, Source_Key, Options.Source_Selector,
         Payload, Source_Info, Source_Tags, Source_Annotations,
         Selected_Source, Result, Open_Source'Access);
```

The catalog contract documents the hook's purpose:

`sqlite/src/flyology-object_storage-sqlite-catalogs.ads:710-712`
```ada
   --  When present, Check runs after a successful lookup while the catalog
   --  operation gate is still held. It may validate the immutable external
   --  payload before a concurrent publication retires the previous file.
```

The previous payload is unlinked immediately after the replacing commit, not
at the next startup:

`sqlite/src/flyology-object_storage-backends-sqlite.adb:2232-2235`
```ada
      if US.Length (Previous) > 0 then
         begin
            Delete_Payload_If_Present (Item, US.To_String (Previous));
            Sync_Path (Objects_Path (Item), Directory => True);
```
`sqlite/src/flyology-object_storage-backends-sqlite.adb:2824-2827`
```ada
            for Payload of Retired loop
               begin
                  Delete_Payload_If_Unreferenced
                    (Item, US.To_String (Payload));
```

Any exception outside a sink callback becomes `Backend_Unavailable`
(`2736-2745`), which the server maps to HTTP 503 `SlowDown`
(`src/flyology-object_storage-server-s3_applications.adb:1951-1954`).

**Failure scenario:** Bucket `b` is unversioned. Client A issues GET `b/k`;
`Find_Selected_Object` returns payload name `P1` and releases the gate. Client
B's PUT `b/k` commits payload `P2` and, at line 2234, unlinks `P1`. Client A
reaches line 2678: `SIO.Open` raises `Name_Error`; the `when others` handler
sets `Result := Backend_Unavailable`. The client observes 503 for a key that
was readable before and after the request; neither the old nor the new
snapshot is served. The same window exists for a concurrent `Delete_Object`
and for `Complete_Multipart_Upload` reading part files while a concurrent
`Abort_Multipart_Upload` or part replacement unlinks them (the catalog
re-validation at `catalogs.adb:8830-8862` protects content, not the open).

**Reproduction test sketch:** requires a SQLite root. Open a `Store`, create
bucket `b`, PUT `k` once. Task 1 loops `Put_Object (b, k, <1 byte source>)`
200 times. Task 2 loops `Get_Object (b, k, Whole_Range, sink)` 200 times and
records every `Result`. Expected: every GET is `Success` (either generation).
Actual: intermittent `Backend_Unavailable` from GET. Passing a `Check` that
opens the file (as `Head_Object`/`Copy_Object` do) closes the window on
POSIX because an open descriptor survives unlink.

**Existing coverage:** `sqlite/tests/src/flyology_object_storage_sqlite_tests.adb`
runs two-task races at 1365-1425 (conditional Put vs Delete) and 1433-1518
(versioning vs Delete); no test races GET against PUT/DELETE.

**Refutation attempts:** confirmed `Get_Object` is the only reader of
`Find_Selected_Object` without a `Check` (rg of `'Access)` call sites);
confirmed deletion is not deferred to startup despite
`docs/architecture/sqlite-backend.md:21-23` (see observation O5); on Windows
`Delete_Payload_If_Present` swallows the sharing-violation failure
(`224-233`) so the file survives there, but Windows is not a qualified
target. The window is small (lookup to open), hence Medium confidence and P2
rather than P1; stock clients retry 503.

---

### BACKEND-SQLITE-2: Annotation copy-lease release violates its own `CHECK(refs>0)`

**Location:** `sqlite/src/flyology-object_storage-sqlite-catalogs.adb:2842-2846`,
`866-895`, `844-861`; consumers at
`sqlite/src/flyology-object_storage-backends-sqlite.adb:2378-2393, 2520-2521, 2528, 2536`

**Severity:** P1. **Confidence:** High.

**Evidence:**

`sqlite/src/flyology-object_storage-sqlite-catalogs.adb:2842-2846`
```ada
      DB.Execute
        (Item.Database,
         "CREATE TEMP TABLE annotation_copy_leases(" &
         "payload TEXT PRIMARY KEY,refs INTEGER NOT NULL CHECK(refs>0)) " &
         "WITHOUT ROWID");
```

`sqlite/src/flyology-object_storage-sqlite-catalogs.adb:875-892`
```ada
            DB.Prepare
              (Update, Item.Database,
               "UPDATE annotation_copy_leases SET refs=refs-1 " &
               "WHERE payload=?1 AND refs>0");
            DB.Bind (Update, 1, US.To_String (Annotation.Payload));
            if DB.Step (Update) /= DB.Done
              or else DB.Changes (Item.Database) /= 1
            then
               raise Catalog_Error with "annotation lease was not held";
            end if;
            DB.Prepare
              (Delete, Item.Database,
               "DELETE FROM annotation_copy_leases " &
               "WHERE payload=?1 AND refs=0");
```

Leases start at 1 and are taken on every source selection made by
`Copy_Object`, regardless of `Annotation_Directive`:

`sqlite/src/flyology-object_storage-sqlite-catalogs.adb:847-852`
```ada
               DB.Prepare
                 (Lease, Item.Database,
                  "INSERT INTO annotation_copy_leases(payload,refs) " &
                  "VALUES(?1,1) ON CONFLICT(payload) DO UPDATE " &
                  "SET refs=refs+1");
```
`sqlite/src/flyology-object_storage-sqlite-catalogs.adb:7338-7342`
```ada
      if Result = Success then
         Read_Version_Object_Tags_Internal
           (Item, Bucket, Key, US.To_String (Version_ID), Tags);
         Read_Version_Annotations_Internal
           (Item, Bucket, Key, US.To_String (Version_ID), Annotations);
```

SQLite evaluates every CHECK constraint on each INSERT and UPDATE and treats a
zero result as a constraint violation (from memory, unverified; the vendored
build enables no `SQLITE_OMIT_CHECK`, see
`sqlite/flyology_object_storage_sqlite.gpr:24-35`). A failed step raises:

`sqlite/src/flyology-object_storage-sqlite-databases.adb:398-400`
```ada
      else
         raise SQLite_Error with Error_Message (Item.Resource.Database, Code);
      end if;
```

The backend releases leases on every path, including from inside its own
`when others` handler:

`sqlite/src/flyology-object_storage-backends-sqlite.adb:2378-2384`
```ada
      procedure Release_Annotations is
      begin
         if Annotation_Leases_Held then
            Catalogs.Release_Annotation_Copy_Snapshot
              (Item.Catalog, Source_Annotations);
            Annotation_Leases_Held := False;
```
`sqlite/src/flyology-object_storage-backends-sqlite.adb:2532-2541`
```ada
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         Release_Annotations;
         Info := Empty_Info;
         ...
         Result := Backend_Unavailable;
```

**Failure scenario:** Source `b/src` has one annotation. `Copy_Object
(b/src -> b/dst)`: `Find_Selected_Object` inserts a lease with `refs=1`
(847-856) and returns; `Put_Object_Internal` publishes the destination with
the copied annotation row (`catalogs.adb:6189-6217`); at line 2521
`Release_Annotations` runs `UPDATE ... SET refs=refs-1`, which sets `refs` to
0 and violates `CHECK(refs>0)`; `Step` raises `SQLite_Error`;
`Release_Annotation_Copy_Snapshot` releases the gate and re-raises
(`7373-7378`); `Copy_Object`'s `when others` (2532) calls
`Release_Annotations` again (the flag was never cleared), which raises again
inside the handler, so `SQLite_Error` escapes `Copy_Object`. Through the S3
server this is a 500 `InternalError`
(`src/flyology-object_storage-server-s3_applications.adb:6810-6813`) for a
copy that was committed; a client retry in a versioning-enabled bucket
publishes a second destination generation. The lease row stays at `refs=1`
for the process lifetime, so `Delete_Payload_If_Unreferenced`
(`catalogs.adb:9155-9165`) can never reclaim that annotation payload, and a
second copy of the same source (refs 1->2->1) succeeds, masking the defect.

**Reproduction test sketch:** SQLite root only. `Create_Bucket (b)`;
`Put_Object (b, src, body)`; `Put_Object_Annotation (b, src, "a", payload)`;
`Copy_Object (b, src, b, dst, Default_Copy_Options, ...)`. Expected:
`Result = Success`, `Destination_Identity` set, `Get_Object_Annotation
(b, dst, "a")` present. Actual: `SQLite_Error` ("CHECK constraint failed")
propagates out of `Copy_Object`; `Head_Object (b, dst)` afterwards is
`Success`. Repeat the same copy: it now returns `Success`.

**Existing coverage:** none on SQLite. `rg -i annotation
sqlite/tests/src/flyology_object_storage_sqlite_tests.adb` matches only
migration `DROP TABLE object_annotations` fixtures (551-963, 1861-1872) and
`Empty_Vector` arguments; there is no `Put_Object_Annotation` call.
Annotation COPY is asserted only on the Memory backend
(`tests/src/object_storage_test_cases.adb:19661-19666`,
`tests/src/s3_server_application_corpus.adb:13637-13667`, both instantiate
`Backends.Memory.Store`). The black-box `tests/src/s3_implementation_corpus.adb`
that `tests/scripts/test-flyology-server.sh sqlite` runs has no annotation
coverage (`rg -i annotation` returns nothing).

**Refutation attempts:** checked for `SQLITE_OMIT_CHECK` or
`ignore_check_constraints` (absent); checked whether leases could always be
above 1 at release (only when two copies of the same source overlap); checked
whether `Copy_Object` skips leases for `Exclude_Annotations` (it does not,
7341 is unconditional); checked whether an unannotated source is affected
(no leases, no failure), which is why the ordinary copy tests pass.

---

### BACKEND-SQLITE-3: Lease release inside `Find_Selected_Object`'s handler can skip `Gate.Release`

**Location:** `sqlite/src/flyology-object_storage-sqlite-catalogs.adb:7349-7361`

**Severity:** P0. **Confidence:** Medium.

**Evidence:**

`sqlite/src/flyology-object_storage-sqlite-catalogs.adb:7349-7361`
```ada
   exception
      when others =>
         if Locked then
            Release_Annotation_Copy_Leases_Internal (Item, Annotations);
            Item.Gate.Release;
         end if;
         Payload := US.Null_Unbounded_String;
         ...
         raise;
   end Find_Selected_Object;
```

`Release_Annotation_Copy_Leases_Internal` raises on any failed step
(`866-895`, and always when a lease drops to 0 per BACKEND-SQLITE-2). The
gate is a protected entry with no timeout and no owner tracking:

`sqlite/src/flyology-object_storage-sqlite-catalogs.adb:918-928`
```ada
   protected body Operation_Gate is
      entry Acquire when not Held is
      begin
         Held := True;
      end Acquire;

      procedure Release is
      begin
         Held := False;
      end Release;
   end Operation_Gate;
```

Every catalog operation begins with `Item.Gate.Acquire` (for example
`6004`, `5701`, `7964`, `8399`), and the only release is the explicit call.
The `Check` callback that runs under the gate raises on cancellation, expired
deadline, or a missing/mis-sized payload:

`sqlite/src/flyology-object_storage-backends-sqlite.adb:2403-2411`
```ada
         Check_Context (Token, Deadline);
         if not Is_Payload_Name (Payload_Name)
           or else not Ada.Directories.Exists (Path)
           or else GNAT.OS_Lib.Is_Symbolic_Link (Path)
           or else Ada.Directories.Kind (Path) /=
             Ada.Directories.Ordinary_File
         then
            raise Ada.IO_Exceptions.Data_Error;
         end if;
```

**Failure scenario:** `Copy_Object` of an annotated source. Leases are
inserted at 7341; `Check.all` (7344) runs `Open_Source`, which raises
`Timeout_Error` because the request deadline passed while waiting for the
gate, or `Data_Error` because the source payload is gone (BACKEND-SQLITE-1's
race, or corruption). The handler at 7352 calls
`Release_Annotation_Copy_Leases_Internal`; the UPDATE violates
`CHECK(refs>0)` (BACKEND-SQLITE-2) and raises `SQLite_Error`; line 7353
`Item.Gate.Release` never executes; the original exception is replaced and
propagates to `Copy_Object`, whose `when others` returns
`Backend_Unavailable`. `Held` stays `True` forever. Every subsequent call on
the store (any bucket, any operation, including `Close`) blocks in
`Gate.Acquire` with no deadline, so the S3 server stops answering all
requests on that backend until the process is killed. Independently of
BACKEND-SQLITE-2, any I/O error in the release path has the same effect,
because the handler puts fallible work before the unlock.

**Reproduction test sketch:** SQLite root only. `Create_Bucket (b)`;
`Put_Object (b, src)`; `Put_Object_Annotation (b, src, "a", payload)`; remove
`objects/<payload of src>` from the root directory (simulating the race);
`Copy_Object (b, src, b, dst)` returns `Backend_Unavailable`. Then call
`Head_Bucket (b, null, Clock + 1 s, Result)`: expected `Success` or a raised
`Timeout_Error`; actual: the call never returns (deadline is not consulted
while blocked on the gate). A cancellation-token variant: request the token
from another task after `Copy_Object` starts on a large annotated source.

**Existing coverage:** none. The SQLite suite has no annotation operations
(see BACKEND-SQLITE-2) and no test asserts that the store remains usable
after a failed `Copy_Object`.

**Refutation attempts:** checked whether `Release_Annotation_Copy_Snapshot`
(7363-7379) protects the gate (it does, but it is a different path);
checked whether `Copy_Object` could release the catalog gate (it cannot; the
gate is private to `Catalog`); checked for a `Finalize`/controlled unlock or
a timed entry (none); checked the only other handler with work before
`Gate.Release` (`Open`, 2849-2857, which closes the database and is not
reachable after open). Confidence is Medium only because the trigger needs a
`Check` failure; the mechanism itself is unconditional.

---

### BACKEND-SQLITE-4: `Delete_Bucket` ignores retained generations and surfaces a foreign-key error as `Backend_Unavailable`

**Location:** `sqlite/src/flyology-object_storage-sqlite-catalogs.adb:3353-3380`;
`sqlite/src/flyology-object_storage-backends-sqlite.adb:386-406`

**Severity:** P1. **Confidence:** High.

**Evidence:**

`sqlite/src/flyology-object_storage-sqlite-catalogs.adb:3353-3380`
```ada
      DB.Prepare
        (Query, Item.Database,
         "SELECT EXISTS(SELECT 1 FROM buckets WHERE name=?1), " &
         "EXISTS(SELECT 1 FROM objects WHERE bucket_name=?1), " &
         "EXISTS(SELECT 1 FROM multipart_uploads WHERE bucket_name=?1)");
      ...
      elsif DB.Column (Query, 1) /= 0 or else DB.Column (Query, 2) /= 0 then
         ...
         Result := Bucket_Not_Empty;
         ...
      end if;
      DB.Prepare (Delete, Item.Database, "DELETE FROM buckets WHERE name=?1");
      DB.Bind (Delete, 1, Name);
      if DB.Step (Delete) /= DB.Done then
```

`object_versions` is not consulted, and it restricts bucket deletion:

`sqlite/src/flyology-object_storage-sqlite-catalogs.adb:385-388`
```ada
     "CHECK((is_delete_marker=0 AND payload IS NOT NULL) OR " &
     "(is_delete_marker=1 AND payload IS NULL))," &
     "FOREIGN KEY(bucket_name) REFERENCES buckets(name) ON DELETE RESTRICT" &
     ");" &
```

Foreign keys are verified on at open (`2597-2600`). The current-object mirror
row is removed whenever the newest generation is a delete marker, so a bucket
with only marker-current keys has no `objects` rows:

`sqlite/src/flyology-object_storage-sqlite-catalogs.adb:6271-6279`
```ada
      DB.Prepare
        (Delete_Object, Item.Database,
         "DELETE FROM objects WHERE bucket_name=?1 AND object_key=?2");
      ...
```
`sqlite/src/flyology-object_storage-sqlite-catalogs.adb:6317-6319`
```ada
      if Is_Marker then
         return;
      end if;
```

The backend wrapper turns the resulting `SQLite_Error` into
`Backend_Unavailable`:

`sqlite/src/flyology-object_storage-backends-sqlite.adb:401-405`
```ada
      when Flyology.Cancellation.Operation_Cancelled
         | Flyology.IO.Timeout_Error =>
         raise;
      when others =>
         Result := Backend_Unavailable;
```

and the server maps that to 503:

`src/flyology-object_storage-server-s3_applications.adb:1951-1954`
```ada
         when Capacity_Exceeded | Backend_Unavailable =>
            Send_Error
              (X, 503, "SlowDown",
               "Please reduce your request rate", Resource);
```

The contract provides `Bucket_Not_Empty` for this state
(`src/flyology-object_storage.ads:21,45`: "@enum Bucket_Not_Empty Bucket
still contains objects"), and the pure-files backend counts its `versions`
directory (`src/flyology-object_storage-backends-files.adb:3849-3852`). AWS
DeleteBucket
requires every version and delete marker to be removed first and answers
409 `BucketNotEmpty` otherwise (from memory, unverified; check with
`tests/scripts/test-*.sh` against MinIO/RustFS).

**Failure scenario:** `Put_Bucket_Versioning (b, Enabled)`; `Put_Object
(b, k)`; `Delete_Object (b, k)` publishes a delete marker and
`Refresh_Current_Mirror_Internal` deletes the `objects` row. `Delete_Bucket
(b)`: both EXISTS checks are 0, `DELETE FROM buckets` runs, the two
`object_versions` rows (data + marker) trigger `RESTRICT`, `Step` raises
`SQLite_Error`, `Safe_Rollback` runs, the backend returns
`Backend_Unavailable`, the server answers 503 `SlowDown`. aws-cli/boto3 retry
503 with back-off and then fail with `SlowDown` for a request whose correct
answer is a definitive 409 `BucketNotEmpty`. The same happens for a
suspended bucket after `DeleteObject` (null marker current).

**Reproduction test sketch:** SQLite root. `Create_Bucket (b)`;
`Put_Bucket_Versioning (b, (Status => Versioning_Enabled, others => <>))`;
`Put_Object (b, k, one byte)`; `Delete_Object (b, k)` expecting `Success`;
`Delete_Bucket (b)`. Expected `Bucket_Not_Empty`; actual
`Backend_Unavailable`. Through `s3_sqlite_server`: `aws s3api
delete-bucket --bucket b` expected `BucketNotEmpty` (409), actual `SlowDown`
(503) after retries. The Memory backend can show the intended status for
comparison.

**Existing coverage:** `sqlite/tests/src/flyology_object_storage_sqlite_tests.adb:7660-7663`
asserts `Bucket_Not_Empty` only with a current data object; the versioning
race test permanently deletes the null generation (`1503-1509`) before its
`Delete_Bucket` cleanup (`1515-1518`), so the marker-only path is never
asserted.

**Refutation attempts:** looked for any path that removes `object_versions`
rows when a key's current becomes a marker (none: `Publish_Marker` inserts,
`Refresh_Current_Mirror_Internal` touches only the mirrors); checked that
`Delete_Bucket` runs `BEGIN IMMEDIATE`, so the rollback is clean and no
partial state remains (the defect is the status, not durability); confirmed
`bucket_tags`/documents cascade and do not mask the RESTRICT; confirmed the
Memory backend also reports `Bucket_Not_Empty` from its own object table
(`src/flyology-object_storage-backends-memory.adb:578-600`), so a defined
status, not `Backend_Unavailable`, is the cross-backend expectation.

---

### BACKEND-SQLITE-5: Annotation qualification record claims SQLite corpus evidence that does not exist

**Location:** `docs/qualification/object-annotations-backend-server.md:26-30, 45-48`

**Severity:** P2. **Confidence:** High.

**Evidence:**

`docs/qualification/object-annotations-backend-server.md:26-27`
```
Memory, pure-files, and SQLite implement the same interface. Pure-files keeps
annotation payloads in external files. SQLite schema version 23 records
```
`docs/qualification/object-annotations-backend-server.md:45-48`
```
EXCLUDE publishes none. The maintained backend and server corpora exercise
payload, checksum, version, list, missing, condition, and copy-directive
behavior across the implementations.
```

`sqlite/tests/src/flyology_object_storage_sqlite_tests.adb` contains no
`Put_Object_Annotation`, `Get_Object_Annotation`, `Delete_Object_Annotation`,
or `List_Object_Annotations` call (`rg -i annotation` matches only migration
fixtures and `Empty_Vector` arguments); `tests/src/s3_implementation_corpus.adb`,
the only corpus `tests/scripts/test-flyology-server.sh sqlite` runs against
the SQLite server, has no annotation coverage; the annotation copy tests at
`tests/src/object_storage_test_cases.adb:19661` and
`tests/src/s3_server_application_corpus.adb:13637` instantiate
`Backends.Memory.Store`. The record also lists SQLite among the qualified
implementations while `docs/architecture/sqlite-backend.md` does not mention
annotations at all.

**Failure scenario:** a reader relies on the record to conclude that SQLite
annotation copy is exercised; BACKEND-SQLITE-2 and BACKEND-SQLITE-3 show it
is not.

**Reproduction test sketch:** documentation; add the BACKEND-SQLITE-2 sketch
to the SQLite suite or to the black-box corpus run against
`s3_sqlite_server`.

**Existing coverage:** none for SQLite.

**Refutation attempts:** searched `sqlite/tests/src/` and `tests/src/` for any
SQLite-backed annotation test and for an annotation lane in
`tests/scripts/test-flyology-server.sh`; found none.

---

## Areas reviewed with no findings

- `Databases` binding layer: text and blob binds copy through
  `sqlite3_malloc64` with `SQLITE_TRANSIENT` (`Integer_Address'Last`), all
  integers use `bind_int64`/`column_int64`, object keys, version IDs, tags,
  metadata, entity tags, and documents bind as BLOB, bucket names and payload
  names as TEXT with `COLLATE BINARY`; `column_text`/`column_blob` are read
  before `column_bytes`; every statement is a stack-local controlled object
  finalized on scope exit, so no statement outlives an exception; `Reset`
  clears bindings; `Step` maps every non-ROW/DONE code to `SQLite_Error`.
- `Open`: `trusted_schema=OFF`, `foreign_keys=ON` verified, application id
  and `user_version` checked, empty database created under `BEGIN
  EXCLUSIVE`, nonempty unrecognized database and newer schema refused,
  V1-V22 upgrades each in one exclusive transaction with rollback on failure,
  WAL and `synchronous=FULL` verified after migration, table and column
  validators, `quick_check`; catalog handle closed and gate released on any
  failure. Root lock acquired before catalog open; staging and unreferenced
  objects reclaimed before serving; both directories synced.
- Versioning merge: `CASE WHEN ?2=0 THEN versioning_status ELSE ?2` and the
  MFA twin match `Merge_Bucket_Versioning`'s postcondition exactly because
  `Versioning_Unconfigured` and `MFA_Delete_Unconfigured` are position 0
  (`src/flyology-object_storage.ads:230-240`), the columns are `NOT NULL`
  with `CHECK ... BETWEEN 0 AND 2`, and both parameters bind as integers so
  no NULL can enter the CASE. MFA/Object-Lock admission is read and the row
  published under the same gate.
- PUT publication order matches `docs/architecture/sqlite-backend.md:8-14`:
  exclusive staging create, fsync (`F_FULLFSYNC` then `fsync`), rename,
  objects-directory sync, then one `BEGIN IMMEDIATE` transaction that
  evaluates write conditions against the current mirror, upserts the mirror,
  replaces metadata/tags/parts, publishes the generation per versioning mode,
  copies annotations, and commits with `synchronous=FULL`; a non-success or
  raised catalog result deletes the new payload; the previous payload is
  removed only after commit. Payload names are SHA-256 of
  bucket/key/sequence/pid/clock (not content), so equal bodies never share a
  name and `payload UNIQUE` cannot fire on valid input.
- Delete paths: `Delete_Selected_Object` and `Delete_Objects` run
  `BEGIN IMMEDIATE`, read versioning/MFA once, evaluate `Require_Unversioned`
  and MFA before the first entry, evaluate conditions per entry, publish
  opaque or null markers with publication-order verification, refresh the
  current mirror, and roll back the whole batch on any raise; retired
  payloads are reclaimed only after commit and only when unreferenced.
- Multipart: `Put_Multipart_Part`, `Complete_Multipart_Upload`, and
  `Abort_Multipart_Upload` each run one transaction; completion re-validates
  every selected part's payload/size/modified/ETag/checksum inside the
  transaction (`Conflict` on drift), enforces ascending order, composite
  contiguity, 5 MiB minimum for nonfinal parts, capacity, expected size and
  checksum, and retires the upload and its parts atomically.
- Listing: bucket, part, annotation, and point-configuration pages use keyset
  predicates with `LIMIT Maximum+1`; object and version listings order by
  BLOB `object_key` (bytewise) and `publication_order DESC`; delimiter
  projection and the paired key/version cursor are computed in Ada;
  delete-marker rows are validated to carry no object metadata.
- Object Lock, legal hold and retention: bucket must be versioning-enabled
  for Put, retention may only be extended in the same mode, permanent
  deletion checks legal hold and unexpired retention inside the delete
  transaction.
- Bucket metadata state CAS (`Create`/`Replace`/`Delete_Bucket_Metadata_State`)
  compare the complete expected snapshot inside a transaction under the gate.
- Unix durability C: `flock(LOCK_EX|LOCK_NB)` on a persistent inode with
  `O_CLOEXEC`, `F_FULLFSYNC` fallback to `fsync`, errors reported through the
  return code and mapped to `Device_Error` in Ada.

## Observations not counted

- O1 `backends-sqlite.adb:2885-2889`: `Delete_Objects` runs
  `Delete_Payload_If_Unreferenced` after commit without the per-payload
  `begin ... when others => null` used by `Delete_Selected_Object`
  (2824-2831); a cleanup raise after a successful commit returns
  `Backend_Unavailable` with `Outcomes` cleared. Within the contract's
  "not a no-deletion certainty signal" wording; low probability.
- O2 `catalogs.adb:8776-9029`: `Complete_Multipart_Upload` does not collect
  annotation payloads of the generations it replaces (`Replace_All` /
  `Replace_Null`), unlike `Put_Object` (6056-6090); their files are orphaned
  until the next startup reconciliation. Disk leak, no data loss.
- O3 `catalogs.adb:7981-7988, 8122-8218`: `List_Objects` scans every object
  of the bucket per page and `List_Object_Versions` appends every
  prefix-matching generation of the bucket into an Ada vector before
  projecting the page, all while holding the gate; per-request memory and
  latency grow with bucket size. Scalability, not correctness.
- O4 `catalogs.adb:8221-8237`: a `Version_ID_Marker` that no longer exists
  (deleted between pages) yields `Invalid_Request`; the Memory backend does
  the same (`backends-memory.adb:2677-2691`), so this is a cross-backend
  design choice outside this area.
- O5 `docs/architecture/sqlite-backend.md:21-23` says superseded bodies are
  "retained until that recovery pass"; the code unlinks them immediately
  after commit (`backends-sqlite.adb:2234, 2826, 2887, 3841, 4351-4355`).
  Open readers survive on POSIX; the sentence is documentation drift and the
  root cause of the window in BACKEND-SQLITE-1.
- O6 `flyology_object_storage_sqlite_durability.c:35-50`: the Windows
  `sync_path` opens with `GENERIC_READ` only; `FlushFileBuffers` requires
  `GENERIC_WRITE` (from memory, unverified), so every PUT would fail there.
  The architecture document limits qualification to Linux and macOS.
- O7 `backends-sqlite.adb:2220-2229, 2279-2282`: if `COMMIT` itself raises
  after SQLite has durably written the WAL commit frame (fsync failure
  ambiguity), the backend deletes the new payload while the catalog may
  reference it after recovery. The contract already calls
  `Backend_Unavailable` ambiguous; theoretical and unverifiable here.
- O8 `backends-sqlite.adb:2209-2212`: `Rename_File` would silently replace an
  existing `objects/<name>.blob`; the name derivation makes a collision
  practically impossible, and a `Create_New_File` on the destination would
  make it impossible.
- O9 `catalogs.adb:918-928`: `Gate.Acquire` is an unconditional entry; a
  caller's `Deadline`/`Token` is not honoured while waiting for the gate, and
  long listings hold it. Latency, not a hang, absent BACKEND-SQLITE-3.
- O10 `databases.ads:14`: `Busy_Timeout_Millis := 5_000` and the 64 KiB
  stream buffers are policy values; with the root lock there is no second
  writer, so busy handling is only exercised by external tools.
- O11 `backends-sqlite.adb:312-313`: `Open` rewraps every failure as
  "could not open SQLite backend", discarding the catalog's specific message
  (unsupported schema, integrity failure, WAL unavailable). Diagnostics only.
- O12 `backends-sqlite.adb:2224-2229`: a `Delete_File` raise inside the
  `Result /= Success` branch re-enters the `Published` cleanup in the handler
  and would escape `Put_Object`; requires an external actor removing the
  just-renamed file.
- O13 `catalogs.adb:2923`: bucket listing prefix uses `substr(name,1,
  length(?2))` on TEXT (character semantics); correct for the ASCII bucket
  names `Valid_Bucket_Name` admits.
