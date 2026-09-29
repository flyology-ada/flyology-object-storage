Title: SQLite Delete_Bucket reports Backend_Unavailable for a bucket whose keys are all delete markers
Labels: bug
Refs: none

## Summary

`Catalogs.Delete_Bucket` decides whether a bucket is empty from the current-object mirror and the multipart table, and never consults `object_versions`. A versioning-enabled bucket whose keys have all been deleted through DeleteObject has no mirror rows, so it passes the emptiness test, and the `DELETE FROM buckets` that follows trips the `ON DELETE RESTRICT` foreign key on the retained generations. The SQLite error is rewrapped as `Backend_Unavailable` and the server answers 503 `SlowDown` instead of the 409 `BucketNotEmpty` that the defined `Bucket_Not_Empty` status exists to produce, so the client retries indefinitely instead of learning that it must remove the versions first. The memory and pure-files backends both return `Bucket_Not_Empty` for the same sequence.

## Problem

Commit `5fe6e3e`.

The emptiness test consults three tables, none of which is `object_versions` (`sqlite/src/flyology-object_storage-sqlite-catalogs.adb:3353-3357`):

```ada
      DB.Prepare
        (Query, Item.Database,
         "SELECT EXISTS(SELECT 1 FROM buckets WHERE name=?1), " &
         "EXISTS(SELECT 1 FROM objects WHERE bucket_name=?1), " &
         "EXISTS(SELECT 1 FROM multipart_uploads WHERE bucket_name=?1)");
```

Only those two results produce the defined status (`sqlite/src/flyology-object_storage-sqlite-catalogs.adb:3368-3374`):

```ada
      elsif DB.Column (Query, 1) /= 0 or else DB.Column (Query, 2) /= 0 then
         DB.Rollback (Item.Database);
         In_Transaction := False;
         Result := Bucket_Not_Empty;
         Item.Gate.Release;
         Locked := False;
         return;
```

and the delete then runs (`sqlite/src/flyology-object_storage-sqlite-catalogs.adb:3376-3380`):

```ada
      DB.Prepare (Delete, Item.Database, "DELETE FROM buckets WHERE name=?1");
      DB.Bind (Delete, 1, Name);
      if DB.Step (Delete) /= DB.Done then
         raise Catalog_Error with "bucket delete returned a row";
      end if;
```

`object_versions` restricts that delete (`sqlite/src/flyology-object_storage-sqlite-catalogs.adb:387`):

```ada
     "FOREIGN KEY(bucket_name) REFERENCES buckets(name) ON DELETE RESTRICT" &
```

A key whose current generation is a delete marker leaves no `objects` row for the emptiness test to find, because publishing a marker removes the mirror row (`sqlite/src/flyology-object_storage-sqlite-catalogs.adb:6271-6279`):

```ada
      DB.Prepare
        (Delete_Object, Item.Database,
         "DELETE FROM objects WHERE bucket_name=?1 AND object_key=?2");
      DB.Bind (Delete_Object, 1, Bucket);
      DB.Bind_Bytes (Delete_Object, 2, Key);
      if DB.Step (Delete_Object) /= DB.Done then
         raise Catalog_Error with
           "current object mirror delete returned a row";
      end if;
```

and returns before it would be reinserted (`sqlite/src/flyology-object_storage-sqlite-catalogs.adb:6317-6319`):

```ada
      if Is_Marker then
         return;
      end if;
```

The backend wrapper turns the resulting exception into an ambiguous status (`sqlite/src/flyology-object_storage-backends-sqlite.adb:400-405`):

```ada
   exception
      when Flyology.Cancellation.Operation_Cancelled
         | Flyology.IO.Timeout_Error =>
         raise;
      when others =>
         Result := Backend_Unavailable;
```

The storage contract that `Backends` operations return defines a status for exactly this state, and a different one for what the backend actually reports (`src/flyology-object_storage.ads:21` and `:38`):

```ada
   --  @enum Bucket_Not_Empty Bucket still contains objects
   --  @enum Backend_Unavailable Backend cannot currently serve the operation
```

The two answers are not interchangeable at the S3 boundary (`src/flyology-object_storage-server-s3_applications.adb:1947-1954`):

```ada
         when Bucket_Not_Empty =>
            Send_Error
              (X, 409, "BucketNotEmpty",
               "The bucket you tried to delete is not empty", Resource);
         when Capacity_Exceeded | Backend_Unavailable =>
            Send_Error
              (X, 503, "SlowDown",
               "Please reduce your request rate", Resource);
```

The other two backends count retained generations. The pure-files backend (`src/flyology-object_storage-backends-files.adb:3846-3852`):

```ada
      elsif Has_Objects (Join (Path, "objects"))
        or else Has_Objects (Join (Path, "multipart"))
        or else
          (Ada.Directories.Exists (Join (Path, "versions"))
           and then Has_Objects (Join (Path, "versions")))
      then
         Result := Bucket_Not_Empty;
```

and the memory backend, whose object table retains markers (`src/flyology-object_storage-backends-memory.adb:585-593`):

```ada
         for Index in 1 .. Highest_Object loop
            if Objects (Index).Used
              and then Ada.Strings.Unbounded.To_String
                (Objects (Index).Bucket) = Name
            then
               Result := Bucket_Not_Empty;
               return;
            end if;
         end loop;
```

The existing SQLite assertion does not cover the marker-only path; it deletes a bucket that still holds a current data object (`sqlite/tests/src/flyology_object_storage_sqlite_tests.adb:7660-7663`):

```ada
      Store.Delete_Bucket
        ("sqlite-bucket", null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Bucket_Not_Empty,
              "SQLite backend deleted a nonempty bucket");
```

The versioning race test does reach `Delete_Bucket` on a versioned bucket, but it permanently removes the generation first (`sqlite/tests/src/flyology_object_storage_sqlite_tests.adb:1502-1505`):

```ada
                     Store.Delete_Selected_Object
                       (Race_Bucket, "current", Null_Version_Selector,
                        No_Delete_Object_Conditions, False, null,
                        Ada.Real_Time.Time_Last, Publication, Result);
```

so its cleanup at `:1514-1518` expects `Success`. No existing test asserts the wrong behaviour, and none has to change.

## What happens now

Spike: one class-wide procedure over `Backends.Backend'Class` runs the identical sequence, `Create_Bucket`, `Put_Bucket_Versioning (Versioning_Enabled)`, `Put_Object`, `Delete_Object`, `Head_Object`, `Delete_Bucket`, and asserts `Bucket_Not_Empty` in both cases. It is driven first against a memory store as a control and then against a SQLite store on a fresh root.

```ada
   procedure Exercise
     (Store : in out OSB.Backend'Class; Label : String; Control : Boolean)
   is
   begin
      Store.Create_Bucket (Bucket, null, Never, Result);
      Store.Put_Bucket_Versioning (Bucket, Versioned, null, Never, Result);
         Store.Put_Object
           (Bucket, "k", Source, OSS.Default_Put_Options, null, Never,
            Info, Identity, Result);
      Store.Delete_Object (Bucket, "k", null, Never, Result);
         Store.Head_Object (Bucket, "k", null, Never, Info, Result);
      Store.Delete_Bucket (Bucket, null, Never, Result);
      Check (Result = OSS.Bucket_Not_Empty,
             Label & ": Delete_Bucket reports Bucket_Not_Empty" &
             (if Control then " (control)" else ""));
   end Exercise;
```

Output, exit status 1, with the scratch root path elided:

```
  ok: memory: Create_Bucket succeeds
  ok: memory: Put_Bucket_Versioning Enabled succeeds
  ok: memory: Put_Object succeeds
  -- memory: Delete_Object (publishes a delete marker) SUCCESS
  ok: memory: Delete_Object succeeds
  -- memory: Head_Object after the marker NOT_FOUND
  -- memory: Delete_Bucket BUCKET_NOT_EMPTY
  ok: memory: Delete_Bucket reports Bucket_Not_Empty (control)
  ok: sqlite: Create_Bucket succeeds
  ok: sqlite: Put_Bucket_Versioning Enabled succeeds
  ok: sqlite: Put_Object succeeds
  -- sqlite: Delete_Object (publishes a delete marker) SUCCESS
  ok: sqlite: Delete_Object succeeds
  -- sqlite: Head_Object after the marker NOT_FOUND
  -- sqlite: Delete_Bucket BACKEND_UNAVAILABLE
  FAILED: sqlite: Delete_Bucket reports Bucket_Not_Empty
BUG REPRODUCED: 1 failed expectation(s)
```

The memory control answers `BUCKET_NOT_EMPTY` for the identical call sequence, and SQLite answers `BACKEND_UNAVAILABLE`. `Head_Object` reports `NOT_FOUND` on both, which confirms the key is absent from the current view in both stores and that the difference is in the emptiness test, not in the delete marker.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire.

## What should happen

`Delete_Bucket` on a bucket that still holds retained generations returns `Bucket_Not_Empty`, the status documented as "Bucket still contains objects" (`src/flyology-object_storage.ads:21`), so the S3 boundary answers 409 `BucketNotEmpty`. The memory backend (`src/flyology-object_storage-backends-memory.adb:585-593`) and the pure-files backend (`src/flyology-object_storage-backends-files.adb:3846-3852`) already do this, so the cross-backend expectation is unambiguous.

## Suggested treatment

Add the retained generations to the emptiness query at `sqlite/src/flyology-object_storage-sqlite-catalogs.adb:3353-3357`, for example a fourth `EXISTS(SELECT 1 FROM object_versions WHERE bucket_name=?1)` column, and include it in the test at `:3368`. No interface, status, or documented policy changes, because `Bucket_Not_Empty` already exists and the other two backends already return it here.

The regression test belongs in the shared black-box suite, so every backend is held to the same answer. The class-wide exercisers that already run over `Backends.Backend'Class` live privately inside the body of `tests/src/object_storage_test_cases.adb` and are driven only against the memory and pure-files stores, for example at `:19734` and `:19743`, so the SQLite suite cannot call them. `sqlite/tests/flyology_object_storage_sqlite_tests.gpr:5` already puts `../../tests/src/` on the SQLite suite's source path, so a class-wide bucket-emptiness exerciser placed in the visible `Flyology.Object_Storage.Backends.Testing` package (`tests/src/flyology-object_storage-backends-testing.ads` and `.adb`) can be driven from both suites against all three backends. If that is not wanted, the narrower version belongs in `sqlite/tests/src/flyology_object_storage_sqlite_tests.adb` next to the existing assertion at `:7660-7663`. The spike is the test, unchanged: one class-wide procedure asserting `Bucket_Not_Empty`, run against the memory store as a control and against a SQLite store.

## Severity

Every client that enables versioning, deletes its objects the ordinary way, and then tries to delete the bucket gets 503 `SlowDown`. Stock clients retry a 503 with back-off and then give up, so the caller never learns that it must remove the retained versions and delete markers first. Nothing is deleted and no data is lost, because the delete runs inside a transaction that rolls back, so the defect is the reported status rather than durability. A suspended bucket after DeleteObject reaches the same state. The failure is deterministic. SQLite backend only.
