Title: SQLite Get_Object opens the payload after the catalog gate is released, so a concurrent overwrite answers 503
Labels: bug
Refs: BACKEND-SQLITE-3

## Summary

`Get_Object` in the SQLite backend calls `Catalogs.Find_Selected_Object` without the `Check` hook, so the catalog operation gate is released before the payload file is opened. A concurrent `Put_Object` on the same key unlinks the superseded payload as soon as it leaves the gate, the reader's `SIO.Open` raises `Name_Error`, and the `when others` handler turns that into `Backend_Unavailable`, which the S3 boundary renders as 503 `SlowDown`. A GET of a key that exists before and after the request therefore fails while another client overwrites it. `Head_Object` and `Copy_Object` already pass the hook for exactly this purpose.

## Problem

Commit `5fe6e3e`.

`Get_Object` looks the payload up, releases the gate inside the lookup, and only then opens the file (`sqlite/src/flyology-object_storage-backends-sqlite.adb:2666-2683`):

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

With a null `Check`, that overload unlocks before it returns (`sqlite/src/flyology-object_storage-sqlite-catalogs.adb:5701-5709`):

```ada
      Item.Gate.Acquire;
      Locked := True;
      Find_Selected_Object_Internal
        (Item, Bucket, Key, Selector, Payload, Info, Result);
      if Result = Success and then Check /= null then
         Check.all (US.To_String (Payload), Info);
      end if;
      Item.Gate.Release;
      Locked := False;
```

The catalog contract states what the hook is for (`sqlite/src/flyology-object_storage-sqlite-catalogs.ads:710-712`):

```ada
   --  When present, Check runs after a successful lookup while the catalog
   --  operation gate is still held. It may validate the immutable external
   --  payload before a concurrent publication retires the previous file.
```

and repeats it for this operation (`sqlite/src/flyology-object_storage-sqlite-catalogs.ads:739`):

```ada
   --  @param Check Optional payload validation while the gate is held
```

The two sibling readers use it. `Head_Object` (`sqlite/src/flyology-object_storage-backends-sqlite.adb:2581-2583`):

```ada
      Catalogs.Find_Selected_Object
        (Item.Catalog, Bucket, Key, Selector, Payload, Info, Result,
         Check_Payload'Access);
```

`Copy_Object` (`sqlite/src/flyology-object_storage-backends-sqlite.adb:2448-2451`):

```ada
      Catalogs.Find_Selected_Object
        (Item.Catalog, Source_Bucket, Source_Key, Options.Source_Selector,
         Payload, Source_Info, Source_Tags, Source_Annotations,
         Selected_Source, Result, Open_Source'Access);
```

The replaced payload is unlinked as soon as the writer leaves the gate (`sqlite/src/flyology-object_storage-backends-sqlite.adb:2232-2235`):

```ada
      if US.Length (Previous) > 0 then
         begin
            Delete_Payload_If_Present (Item, US.To_String (Previous));
            Sync_Path (Objects_Path (Item), Directory => True);
```

Any exception outside a sink callback becomes `Backend_Unavailable` (`sqlite/src/flyology-object_storage-backends-sqlite.adb:2736-2745`):

```ada
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         Info := Empty_Info;
         if In_Callback then
            raise;
         else
            Result := Backend_Unavailable;
         end if;
```

and the server renders that as 503 (`src/flyology-object_storage-server-s3_applications.adb:1951-1954`):

```ada
         when Capacity_Exceeded | Backend_Unavailable =>
            Send_Error
              (X, 503, "SlowDown",
               "Please reduce your request rate", Resource);
```

The backend's architecture document states the invariant the code does not keep (`docs/architecture/sqlite-backend.md:20-23`):

```
current-object, retained-generation, or multipart catalog, then flushes both
directories. Superseded and deleted bodies are
intentionally retained until that recovery pass so an already-open reader is
never invalidated by replacement.
```

The code retires superseded bodies at commit time, not at the next recovery pass, and the reader is not already open when replacement happens.

The two multipart readers have the same window. `Copy_Multipart_Part` resolves the source payload with `Catalogs.Find_Object` and no `Check` argument (`sqlite/src/flyology-object_storage-backends-sqlite.adb:4023-4025`):

```ada
      Catalogs.Find_Object
        (Item.Catalog, Source_Bucket, Source_Key,
         Payload, Source_Info, Result);
```

and opens the file afterwards at `sqlite/src/flyology-object_storage-backends-sqlite.adb:4067-4069`. `Complete_Multipart_Upload` reads the part records at `:4175-4176` and then opens each part payload outside the gate at `:4295-4297`. That overload of `Find_Object` is the one whose `Check` hook is documented at `sqlite/src/flyology-object_storage-sqlite-catalogs.ads:710-712`.

The existing SQLite races cover writers against writers only. The conditional race declares two writer workers (`sqlite/tests/src/flyology_object_storage_sqlite_tests.adb:1366-1368`):

```ada
               task type Worker (Delete_Worker : Boolean);

               task body Worker is
```

and the second race is a versioning-against-delete race (`sqlite/tests/src/flyology_object_storage_sqlite_tests.adb:1431-1435`):

```ada
      for Round in 1 .. 16 loop
         declare
            Race_Bucket : constant String :=
              "sqlite-delete-version-" & Ada.Strings.Fixed.Trim
                (Positive'Image (Round), Ada.Strings.Both);
```

No test reads a key while another task overwrites it, so no existing test asserts the wrong behaviour and none has to change.

## What happens now

Spike: the program opens a SQLite store on a fresh root, creates a bucket, seeds one key with a single byte, and then runs two 20 second phases of 32 reader tasks against 2 writer tasks. Every writer publishes the same bytes, so the entity tag never changes and every GET is required to return `Success`. Phase A reads with no conditions; phase B reads with a 14,284 byte matching `If-Match` list, which is the only work `Get_Object` performs between the gate release and `SIO.Open`. A single-task control GET runs first and must succeed.

The reader and writer loops:

```ada
   task body Reader is
      Conditions : constant OSB.Read_Conditions := Read_Template;
   begin
      while Ada.Real_Time.Clock < Stop_Time loop
            Store.Get_Object
              (Bucket, Key, OSS.Whole_Object, Sink, null, Never,
               Info, Result, Conditions);
            Tally.Record_Get (Result);
      end loop;

   task body Writer is
   begin
      while Ada.Real_Time.Clock < Stop_Time loop
            Store.Put_Object
              (Bucket, Key, Source, OSS.Default_Put_Options, null, Never,
               Info, Identity, Result);
            Tally.Record_Put (Result);
      end loop;
```

Output, exit status 1, with the scratch root path elided:

```
  ok: Create_Bucket succeeds
  ok: Put_Object seeds the key
  -- entity tag 9dd4e461268c8034f5c8564e155c67a6 (constant: every writer publishes the same bytes)
  -- control Get_Object SUCCESS bytes 1
  ok: control Get_Object succeeds
  ok: control Get_Object round-trips the body
  -- phase A (plain reads) GET total 361969: SUCCESS=355387 BACKEND_UNAVAILABLE=6582
  -- phase A (plain reads) PUT total 2082: SUCCESS=2082
  ok: phase A (plain reads): the writers made progress
  ok: phase A (plain reads): tally is consistent
  FAILED: phase A (plain reads): no concurrent Get_Object reports Backend_Unavailable for a key that always exists
  ok: phase A (plain reads): no concurrent Get_Object reports Not_Found for a key that always exists
  -- phase B If-Match list length 14284 (matching, evaluated after the gate release)
  -- phase B (long matching If-Match) GET total 334399: SUCCESS=326960 BACKEND_UNAVAILABLE=7439
  -- phase B (long matching If-Match) PUT total 1430: SUCCESS=1430
  ok: phase B (long matching If-Match): the writers made progress
  ok: phase B (long matching If-Match): tally is consistent
  FAILED: phase B (long matching If-Match): no concurrent Get_Object reports Backend_Unavailable for a key that always exists
  ok: phase B (long matching If-Match): no concurrent Get_Object reports Not_Found for a key that always exists
BUG REPRODUCED: 2 failed expectation(s)
```

Phase A failed 6,582 of 361,969 reads, 1.8 %, against 2,082 successful overwrites, about three failed reads per overwrite. Phase B failed 7,439 of 334,399 reads, 2.2 %, against 1,430 overwrites. Widening the unprotected window with the long `If-Match` list did not change the rate materially, so the dominant factor is reader scheduling rather than the amount of work in the window. Zero `Not_Found` was recorded in either phase, so the catalog lookup always succeeded and only the file open failed. All writes returned `Success`, so the key exists for the whole run.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire.

## What should happen

A GET of a key that exists before and after the request returns `Success` and serves either generation. The catalog contract provides the `Check` hook so a reader can bind the payload file before a concurrent publication retires it (`sqlite/src/flyology-object_storage-sqlite-catalogs.ads:710-712`), and `docs/architecture/sqlite-backend.md:20-23` states that an already-open reader is never invalidated by replacement.

## Suggested treatment

Give `Get_Object` a `Check` hook that performs the `SIO.Open` while the gate is still held, in the shape `Head_Object` uses at `sqlite/src/flyology-object_storage-backends-sqlite.adb:2581-2583` and `Copy_Object` at `:2448-2451`; an open POSIX descriptor survives unlink, so the remaining work outside the gate is unaffected. Apply the same change to `Copy_Multipart_Part`, whose `Catalogs.Find_Object` call at `sqlite/src/flyology-object_storage-backends-sqlite.adb:4023-4025` accepts the same hook, and to the part opens in `Complete_Multipart_Upload` at `:4295-4297`. No public interface changes.

This needs a maintainer decision: the code and `docs/architecture/sqlite-backend.md:20-23` disagree about payload retirement, and closing the window does not by itself resolve that.

- Keep the immediate unlink after commit, close the window with the `Check` hook, and rewrite the sentence at `docs/architecture/sqlite-backend.md:20-23` to say that superseded bodies are unlinked at commit and that readers bind the file under the gate. Disk use is unchanged; the document stops promising retention.
- Adopt the documented behaviour and defer unlinking of superseded and deleted bodies to the startup recovery pass. Readers are then safe without a hook, but a busy store holds every superseded body until the next restart, which changes the disk footprint of an overwrite-heavy workload.

The gate is also what a raising `Check` hook interacts with, so any hook added here should be read together with {{ISSUE:BACKEND-SQLITE-3}}: on that path a raise inside the hook currently leaks the gate.

The regression test belongs in `sqlite/tests/src/flyology_object_storage_sqlite_tests.adb`, next to the two existing races at `:1365` and `:1431`, because the mechanism is specific to this backend's external payload files and catalog gate. The spike is the test: a bounded reader-against-writer race on one key whose bytes never change, asserting that no GET reports `Backend_Unavailable` or `Not_Found`.

## Severity

Every S3 client that reads a key while another client overwrites it can get 503 `SlowDown` for an object that exists throughout, and multipart copy and completion have the same window on part payloads. Nothing is lost and no request is served with wrong bytes, because the payload names are immutable and the size check at `sqlite/src/flyology-object_storage-backends-sqlite.adb:2681-2683` rejects a mismatched file, and 503 is retriable. It needs concurrency on one key, so it is not deterministic per request, but at 32 readers against 2 writers it produced about three failed reads per overwrite and is statistically certain under ordinary server load. SQLite backend only.
