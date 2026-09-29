Title: The first CopyObject of an annotated SQLite object raises SQLite_Error from its own annotation lease CHECK(refs>0)
Labels: bug
Refs: BACKEND-SQLITE-3, BACKEND-SQLITE-5

## Summary

The SQLite catalog keeps a source annotation payload alive across a copy with a temporary lease table declared `refs INTEGER NOT NULL CHECK(refs>0)`, but it releases a lease with `SET refs=refs-1`. A lease taken at 1 therefore violates the constraint on its very first release, `Step` raises `SQLite_Error`, and because the backend clears its "leases held" flag only after that fallible call returns, the exception handler re-enters the release and raises again, so `SQLite_Error` escapes `Copy_Object` entirely. The destination has already been committed at that point, so an S3 client gets 500 `InternalError` for a CopyObject that actually succeeded. Every CopyObject of an annotated source is affected, in both annotation directives, on the first copy of that source in a process.

## Problem

Commit `5fe6e3e`.

The lease table forbids a zero reference count (`sqlite/src/flyology-object_storage-sqlite-catalogs.adb:2842-2846`):

```ada
      DB.Execute
        (Item.Database,
         "CREATE TEMP TABLE annotation_copy_leases(" &
         "payload TEXT PRIMARY KEY,refs INTEGER NOT NULL CHECK(refs>0)) " &
         "WITHOUT ROWID");
```

Leases are taken at 1 (`sqlite/src/flyology-object_storage-sqlite-catalogs.adb:847-856`):

```ada
               DB.Prepare
                 (Lease, Item.Database,
                  "INSERT INTO annotation_copy_leases(payload,refs) " &
                  "VALUES(?1,1) ON CONFLICT(payload) DO UPDATE " &
                  "SET refs=refs+1");
               DB.Bind (Lease, 1, Payload);
               if DB.Step (Lease) /= DB.Done then
                  raise Catalog_Error with
                    "annotation lease returned a row";
               end if;
```

and released by decrementing to zero (`sqlite/src/flyology-object_storage-sqlite-catalogs.adb:875-892`):

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
            DB.Bind (Delete, 1, US.To_String (Annotation.Payload));
            if DB.Step (Delete) /= DB.Done then
               raise Catalog_Error with "annotation lease delete returned row";
            end if;
```

`UPDATE ... SET refs=refs-1` against `CHECK(refs>0)` cannot succeed for a lease at 1, and the `DELETE ... WHERE payload=?1 AND refs=0` that follows is unreachable for the same reason, so the intended reference-count lifecycle cannot complete even once. A failed step raises (`sqlite/src/flyology-object_storage-sqlite-databases.adb:398-400`):

```ada
      else
         raise SQLite_Error with Error_Message (Item.Resource.Database, Code);
      end if;
```

The vendored build suppresses no CHECK constraint (`sqlite/flyology_object_storage_sqlite.gpr:24-35`):

```ada
      for Default_Switches ("C") use
        ("-O2",
         "-fPIC",
         "-DSQLITE_THREADSAFE=1",
         "-DSQLITE_DQS=0",
         "-DSQLITE_DEFAULT_MEMSTATUS=0",
         "-DSQLITE_OMIT_DEPRECATED",
         "-DSQLITE_ENABLE_API_ARMOR",
         "-DSQLITE_ENABLE_COLUMN_METADATA",
         "-DSQLITE_ENABLE_DBSTAT_VTAB",
         "-DSQLITE_ENABLE_RTREE",
         "-DSQLITE_USE_URI=1");
```

and the run below reports the constraint firing with the SQLite message `CHECK constraint failed: refs>0`.

Leases are taken on every successful source selection, before the `Check` callback and irrespective of the copy directive (`sqlite/src/flyology-object_storage-sqlite-catalogs.adb:7338-7345`):

```ada
      if Result = Success then
         Read_Version_Object_Tags_Internal
           (Item, Bucket, Key, US.To_String (Version_ID), Tags);
         Read_Version_Annotations_Internal
           (Item, Bucket, Key, US.To_String (Version_ID), Annotations);
         if Check /= null then
            Check.all (US.To_String (Payload), Info, Tags);
         end if;
```

`Copy_Object` is the only caller of that overload (`sqlite/src/flyology-object_storage-backends-sqlite.adb:2448-2451`) and it clears its flag only after the fallible release returns (`sqlite/src/flyology-object_storage-backends-sqlite.adb:2378-2393`):

```ada
      procedure Release_Annotations is
      begin
         if Annotation_Leases_Held then
            Catalogs.Release_Annotation_Copy_Snapshot
              (Item.Catalog, Source_Annotations);
            Annotation_Leases_Held := False;
```

so the raise on the success path (`sqlite/src/flyology-object_storage-backends-sqlite.adb:2520-2521`):

```ada
      SIO.Close (File);
      Release_Annotations;
```

leaves `Annotation_Leases_Held` set, and the handler calls the same procedure again (`sqlite/src/flyology-object_storage-backends-sqlite.adb:2532-2540`):

```ada
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         Release_Annotations;
         Info := Empty_Info;
         Source_Identity := (others => <>);
         Destination_Identity := (others => <>);
         Result := Backend_Unavailable;
```

The second call raises inside the handler, so nothing assigns `Result` and `SQLite_Error` propagates out of `Copy_Object`. The S3 application dispatches the copy at `src/flyology-object_storage-server-s3_applications.adb:14555-14560` and its catch-all answers 500 (`src/flyology-object_storage-server-s3_applications.adb:18056-18065`):

```ada
      when others =>
         if Apps.Response (X) /= Apps.Not_Started
           or else Apps.Wire_Response_Started (X)
         then
            Apps.Mark_Failed (X);
         else
            Send_Error
              (X, 500, "InternalError",
               "We encountered an internal error", Target_Text);
         end if;
```

The `Backends` contract states that a copy reports its outcome through `Result` (`src/flyology-object_storage-backends.ads:2010`):

```ada
   --  @param Result Copy result; Backend_Unavailable may be ambiguous
```

There is a second effect. The stranded `refs=1` row keeps the annotation payload referenced for the life of the process, because payload reclamation counts the lease table (`sqlite/src/flyology-object_storage-sqlite-catalogs.adb:9150-9156`):

```ada
      DB.Prepare
        (Query, Item.Database,
         "SELECT EXISTS(SELECT 1 FROM objects WHERE payload=?1), " &
         "EXISTS(SELECT 1 FROM multipart_parts WHERE payload=?1), " &
         "EXISTS(SELECT 1 FROM object_versions WHERE payload=?1), " &
         "EXISTS(SELECT 1 FROM object_annotations WHERE payload=?1), " &
         "EXISTS(SELECT 1 FROM annotation_copy_leases WHERE payload=?1)");
```

No existing test asserts the wrong behaviour, because no SQLite-backed test performs any annotation operation at all; see {{ISSUE:BACKEND-SQLITE-5}}. The annotation copy directives are asserted only against the memory and pure-files stores, by the class-wide exerciser at `tests/src/object_storage_test_cases.adb:19660-19675`, driven at `:19734` and `:19743`. An unannotated copy takes no lease and succeeds, which is why the maintained copy tests pass.

## What happens now

Spike: the program opens a SQLite store on a fresh root, copies an unannotated source as a control, then puts a source, attaches one annotation to it, and copies it, asserting that `Copy_Object` neither raises nor returns a non-success status. It then reads the copied annotation and heads the destination to show that the copy was committed anyway, repeats the subject with `Exclude_Annotations` on a second freshly annotated source, and finally copies the first source a second time.

The subject call:

```ada
      Options : OSB.Copy_Options := OSB.Default_Copy_Options;
      ...
      Options.Annotation_Directive := Directive;
      begin
         Store.Copy_Object
           (Bucket, From, Bucket, To, Options, null, Never,
            Info, Source_Identity, Destination_Identity, Result);
      exception
         when E : others =>
            Raised := True;
      ...
      Check (not Raised, Label & ": Copy_Object does not raise");
      Check (Result = OSS.Success, Label & ": Copy_Object returns Success");
```

Output, exit status 1, with the scratch root path elided:

```
  ok: Create_Bucket succeeds
  ok: Put_Object plain-src succeeds
  -- control (no annotation): Copy_Object returned SUCCESS
  ok: control (no annotation): Copy_Object does not raise
  ok: control (no annotation): Copy_Object returns Success
  ok: Put_Object annotated-src succeeds
  -- Put_Object_Annotation on annotated-src SUCCESS size 24
  ok: Put_Object_Annotation on annotated-src succeeds
  -- subject (one annotation): Copy_Object raised FLYOLOGY.OBJECT_STORAGE.SQLITE.DATABASES.SQLITE_ERROR -- CHECK constraint failed: refs>0
  FAILED: subject (one annotation): Copy_Object does not raise
  FAILED: subject (one annotation): Copy_Object returns Success
  -- Get_Object_Annotation on the copy SUCCESS presence ANNOTATION_PRESENT bytes 24
  ok: Get_Object_Annotation on the copy succeeds
  ok: the copied annotation is present on the destination
  ok: the copied annotation payload round-trips
  -- Head_Object on the copy afterwards SUCCESS size 14
  ok: Put_Object excluded-src succeeds
  -- Put_Object_Annotation on excluded-src SUCCESS size 24
  ok: Put_Object_Annotation on excluded-src succeeds
  -- subject (EXCLUDE directive): Copy_Object raised FLYOLOGY.OBJECT_STORAGE.SQLITE.DATABASES.SQLITE_ERROR -- CHECK constraint failed: refs>0
  FAILED: subject (EXCLUDE directive): Copy_Object does not raise
  FAILED: subject (EXCLUDE directive): Copy_Object returns Success
  -- second copy of same source: Copy_Object returned SUCCESS
  ok: second copy of same source: Copy_Object does not raise
  ok: second copy of same source: Copy_Object returns Success
BUG REPRODUCED: 4 failed expectation(s)
```

The exception message is the SQLite text `CHECK constraint failed: refs>0`. The lines after the first failure show the destination was published: its annotation reads back with the source payload and `Head_Object` on the copy succeeds. `Exclude_Annotations` fails identically, because the lease is taken before the directive is consulted. The final copy of the same source succeeds, because the stranded row makes that lease go 1 to 2 to 1; that is what masks the defect after the first copy.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire.

## What should happen

`Copy_Object` of an annotated source returns `Success` and does not raise, reporting its outcome through `Result` as the contract at `src/flyology-object_storage-backends.ads:2010` specifies, and the lease taken for the source annotation payload is released so that payload can be reclaimed later.

## Suggested treatment

Make the release consistent with the table's own constraint, and clear the backend flag before the fallible call so a raise cannot re-enter the handler.

This needs a maintainer decision on the intended lease lifecycle, because the two statements in `Release_Annotation_Copy_Leases_Internal` encode different ones:

- Drop `CHECK(refs>0)` from the TEMP table at `sqlite/src/flyology-object_storage-sqlite-catalogs.adb:2842-2846` and keep the existing decrement plus delete-at-zero. The table then holds transient `refs=0` rows between the two statements.
- Keep the constraint and replace the release with a `DELETE FROM annotation_copy_leases WHERE payload=?1 AND refs=1` and `UPDATE annotation_copy_leases SET refs=refs-1 WHERE payload=?1 AND refs>1` pair, so a row never holds zero. The existing `DB.Changes (Item.Database) /= 1` guard has to cover whichever statement applied.

Independently of that choice, move `Annotation_Leases_Held := False` above the call to `Catalogs.Release_Annotation_Copy_Snapshot` at `sqlite/src/flyology-object_storage-backends-sqlite.adb:2381-2383`, so a failed release cannot be retried from `Copy_Object`'s own handler and the original outcome survives.

The exception path of the same release is the trigger of {{ISSUE:BACKEND-SQLITE-3}}, which wedges the whole store; that one needs its own fix and is not closed by repairing the lease arithmetic.

The regression test belongs in `sqlite/tests/src/flyology_object_storage_sqlite_tests.adb`, which today performs no annotation operation. The spike is the test: put a source, attach one annotation, copy it once with the default directive and once with `Exclude_Annotations`, and assert `Success` with no exception in both cases and on a second copy of the same source. The wider gap it exposes is {{ISSUE:BACKEND-SQLITE-5}}.

## Severity

Every CopyObject of an annotated object fails on the first copy of that source in a process, and the S3 boundary answers 500 `InternalError` for a copy that was committed, so a client that retries against a versioning-enabled bucket publishes a second destination generation. Nothing is lost or corrupted and the retry succeeds. The annotation payload of that source is also never reclaimed while the process lives, because the stranded lease row keeps it referenced. It needs only an annotated source, which is an ordinary use of the annotation operations. The failure is deterministic. SQLite backend only.
