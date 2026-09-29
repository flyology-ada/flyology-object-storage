Title: A failed lease release in Find_Selected_Object leaks the SQLite catalog gate and the store stops answering
Labels: bug
Refs: BACKEND-SQLITE-1, BACKEND-SQLITE-2

## Summary

The exception handler of the annotation-carrying `Find_Selected_Object` overload runs `Release_Annotation_Copy_Leases_Internal` before `Item.Gate.Release`, and that release is fallible. When it raises, the unlock never runs, `Held` stays `True` for the life of the process, and every later catalog call on the store blocks in the protected entry with no deadline and no cancellation. The store stops answering every operation, on every bucket, permanently: an S3 server on this backend serves no further request and cannot even close the store, and re-opening does not recover it in the same process. The caller-reachable sequence is a CopyObject of a source generation that carries at least one annotation, where the `Open_Source` callback raises because the caller's token was cancelled, because the caller's deadline has passed, or because the source body file is gone.

## Problem

Commit `5fe6e3e`.

The handler puts fallible work before the unlock (`sqlite/src/flyology-object_storage-sqlite-catalogs.adb:7349-7360`):

```ada
   exception
      when others =>
         if Locked then
            Release_Annotation_Copy_Leases_Internal (Item, Annotations);
            Item.Gate.Release;
         end if;
         Payload := US.Null_Unbounded_String;
         Info := Empty_Info;
         Tags := Empty_Object_Tags;
         Annotations.Clear;
         Identity := (others => <>);
         raise;
```

That release raises whenever its update does not change exactly one row, and it raises unconditionally today for a lease at 1 because the table declares `CHECK(refs>0)` (`sqlite/src/flyology-object_storage-sqlite-catalogs.adb:875-884`):

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
```

That constraint defect is reported separately as {{ISSUE:BACKEND-SQLITE-2}}. This defect does not depend on it: any SQLite failure in the release has the same effect, because the handler performs fallible work before the unlock.

The gate has no owner tracking, no timeout, and no controlled unlock (`sqlite/src/flyology-object_storage-sqlite-catalogs.adb:918-928`):

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

Every catalog operation begins with `Item.Gate.Acquire`, including `Delete_Bucket` at `sqlite/src/flyology-object_storage-sqlite-catalogs.adb:3349`, the plain object lookup at `:5701`, this overload at `:7329`, payload reclamation at `:9148`, and `Close` at `:2863`. Once `Held` stays `True` all of them block.

The gate-safe sibling shows the shape the handler should have (`sqlite/src/flyology-object_storage-sqlite-catalogs.adb:7368-7377`):

```ada
      Item.Gate.Acquire;
      Locked := True;
      Release_Annotation_Copy_Leases_Internal (Item, Annotations);
      Item.Gate.Release;
      Locked := False;
   exception
      when others =>
         if Locked then
            Item.Gate.Release;
         end if;
```

The only caller of the leaking overload is `Copy_Object` (`sqlite/src/flyology-object_storage-backends-sqlite.adb:2448-2451`):

```ada
      Catalogs.Find_Selected_Object
        (Item.Catalog, Source_Bucket, Source_Key, Options.Source_Selector,
         Payload, Source_Info, Source_Tags, Source_Annotations,
         Selected_Source, Result, Open_Source'Access);
```

and the hook it passes raises on three ordinary conditions (`sqlite/src/flyology-object_storage-backends-sqlite.adb:2402-2411`):

```ada
      begin
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

`Check_Context` raises on a cancelled token or an expired deadline (`sqlite/src/flyology-object_storage-backends-sqlite.adb:169-176`):

```ada
      if Token /= null and then Token.Requested then
         raise Flyology.Cancellation.Operation_Cancelled;
      end if;
      if Deadline /= Ada.Real_Time.Time_Last
        and then Ada.Real_Time.Clock >= Deadline
      then
         raise Flyology.IO.Timeout_Error;
      end if;
```

Both are plain arguments of the public copy profile (`src/flyology-object_storage-backends.ads:2018-2019`):

```ada
      Token              : access Flyology.Cancellation.Token;
      Deadline           : Ada.Real_Time.Time;
```

and the S3 application passes the request's own cancellation and deadline on every CopyObject (`src/flyology-object_storage-server-s3_applications.adb:14555-14560`):

```ada
                  Store.Copy_Object
                    (Requests.Bucket_Name (Source_Target, Source_Parsed),
                     Requests.Object_Key (Source_Target, Source_Parsed),
                     Bucket, Key, Copy_Options_Value,
                     Apps.Cancellation (X), Apps.Deadline (X), Info,
                     Source_Identity, Destination_Identity, Result);
```

so an ordinary S3 CopyObject whose client aborts, or whose request deadline expires, reaches the handler. The missing source body file is the third route, and one way to produce it is the payload race reported as {{ISSUE:BACKEND-SQLITE-1}}.

`Get_Object` and `Head_Object` cannot reach this handler. They use the overload at `sqlite/src/flyology-object_storage-sqlite-catalogs.adb:5701-5715`, which takes no leases and whose handler releases the gate unconditionally, so a cancelled or timed-out GET of an annotated object is not enough.

An amplifier belongs with the fix. `Gate.Acquire` is an unconditional protected entry, so a caller waiting for it does not consult its own `Token` or `Deadline`, and long operations hold the gate meanwhile. `List_Objects` acquires it at `sqlite/src/flyology-object_storage-sqlite-catalogs.adb:7964` and then scans every object of the bucket under it (`sqlite/src/flyology-object_storage-sqlite-catalogs.adb:7981-7989`):

```ada
      DB.Prepare
        (Query, Item.Database,
         "SELECT object_key,size,modified,entity_tag,content_type," &
         "checksum_algorithm,checksum_method,checksum_value," &
         "(SELECT count(*) FROM object_parts WHERE bucket_name=objects." &
         "bucket_name AND object_key=objects.object_key) " &
         "FROM objects WHERE bucket_name=?1 ORDER BY object_key");
      DB.Bind (Query, 1, Bucket);
      while DB.Step (Query) = DB.Row loop
```

On its own that is latency. Together with this handler it is what makes the timed-out CopyObject trigger easy to reach, because a copy request can spend its whole deadline queued behind such an operation and then find the deadline already expired when `Open_Source` runs under the gate.

No existing test covers this. The SQLite suite performs no annotation operation at all, so no test can reach the lease-taking overload, and no test asserts that the store remains usable after a failed `Copy_Object`. No existing test asserts the wrong behaviour.

## What happens now

Spike: two programs, both of which put a source, annotate it, confirm `Head_Bucket` answers, provoke a `Copy_Object` failure, and then probe `Head_Bucket` from a second task with a bounded 5 second wait. The probe timing out is the observation: the gate was never released. Both programs exit through `GNAT.OS_Lib.OS_Exit (1)` on the timeout rather than hanging with a blocked task.

The first program establishes the mechanism deterministically. It removes the source body file so `Open_Source` raises `Data_Error` under the gate:

```ada
      Ada.Directories.Delete_File (Body_Payload);
      ...
      Store.Copy_Object
        (Bucket, "src", Bucket, "dst", OSB.Default_Copy_Options, null, Never,
         Info, Source_Identity, Destination_Identity, Result);
      ...
      select
         Completion.Wait (Probe);
      or
         delay 5.0;
```

Output, exit status 1, with the scratch root path elided:

```
  ok: Create_Bucket succeeds
  ok: Put_Object src succeeds
  ok: exactly one payload file before annotating
  ok: Put_Object_Annotation succeeds
  -- control Head_Bucket SUCCESS
  ok: control Head_Bucket succeeds
  -- removed the source body payload <root>/objects/0c2b44addcdd34f164dc191cac24a2acb5ff851120baf4c8910613092031af8d.blob
  -- Copy_Object with a missing source body returned BACKEND_UNAVAILABLE
  -- probing the store from a second task (bounded 5 s wait)
  -- probe Head_Bucket did not return within 5 s: the catalog operation gate was never released
  FAILED: the store still serves Head_Bucket after a failed Copy_Object
BUG REPRODUCED: 1 failed expectation(s)
```

This shows the mechanism: a `Check` callback that raises under the gate leaves the store wedged, and the control `Head_Bucket` immediately before proves the store was answering.

The second program shows the same outcome with no filesystem interference and nothing but a caller-supplied deadline through the public backend interface. The source carries 200 annotations, which only widens the interval between the entry check and the `Open_Source` callback, and the deadline is scanned upward in 3 microsecond steps. Attempts that are too short raise `Timeout_Error` at the entry check, take no leases and are harmless, so the scan is safe:

```ada
   for Step in 1 .. 400 loop
      declare
         Budget : constant Integer := Step * 3;
         Deadline : constant Ada.Real_Time.Time :=
           Ada.Real_Time.Clock + Ada.Real_Time.Microseconds (Budget);
      begin
         Store.Copy_Object
           (Bucket, "src", Bucket, "dst", OSB.Default_Copy_Options, null,
            Deadline, Info, Source_Identity, Destination_Identity, Result);
         Engaged := True;
      exception
         when Flyology.IO.Timeout_Error =>
            Entry_Timeouts := Entry_Timeouts + 1;
```

Output, exit status 1, with the scratch root path elided:

```
  ok: Create_Bucket succeeds
  ok: Put_Object src succeeds
  -- attached 200 annotations to src
  -- control Head_Bucket SUCCESS
  ok: control Head_Bucket succeeds
  -- CopyObject with a 6 us deadline returned BACKEND_UNAVAILABLE (the deadline expired inside the gate-held window)
  -- attempts rejected at the entry check: 1
  -- probing the store from a second task (bounded 5 s wait)
  -- probe Head_Bucket did not return within 5 s: the catalog operation gate was never released
  FAILED: the store still serves Head_Bucket after a CopyObject whose deadline expired
BUG REPRODUCED: 1 failed expectation(s)
```

This shows the trigger is caller-reachable: one CopyObject with a 6 microsecond deadline, after a single attempt rejected at the entry check, and the store never answers again. It also shows a secondary effect visible in both runs. The timed-out `Copy_Object` reports `Backend_Unavailable` rather than propagating `Timeout_Error`, because the SQLite exception from the lease release replaced the original one before `Copy_Object`'s `when Operation_Cancelled | Timeout_Error => raise` handler could see it.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire.

## What should happen

A `Copy_Object` that fails for any reason leaves the store usable: the catalog operation gate is released on every path out of `Find_Selected_Object`, exactly as the sibling `Release_Annotation_Copy_Snapshot` at `sqlite/src/flyology-object_storage-sqlite-catalogs.adb:7368-7377` and the non-leasing overload at `:5701-5715` already do. The caller then sees the outcome the `Backends` contract defines, `Result` or the propagated `Operation_Cancelled` or `Timeout_Error` (`src/flyology-object_storage-backends.ads:2010`).

## Suggested treatment

Make the unlock unconditional in the handler at `sqlite/src/flyology-object_storage-sqlite-catalogs.adb:7349-7360`: release the gate first and perform the lease release afterwards, or hold the lock in a controlled object whose `Finalize` releases it, so no fallible work can precede the unlock. Guard the lease release so that its own failure cannot displace the exception that is being propagated. The separate lease repair in {{ISSUE:BACKEND-SQLITE-2}} is still needed; it removes today's guaranteed failure but not the structural one.

This needs a maintainer decision on two points that change documented behaviour rather than fixing an internal ordering:

- Whether `Gate.Acquire` should honour the caller's `Token` and `Deadline` while waiting. It is currently `entry Acquire when not Held` with no timeout (`sqlite/src/flyology-object_storage-sqlite-catalogs.adb:918-928`), so a queued request waits without bound and its deadline can expire inside the gate-held window, which is what makes the timed-out-copy trigger easy to reach under load. Honouring them would make a queued request fail with `Timeout_Error` or `Operation_Cancelled` where it currently waits, which is an externally visible change of outcome for every catalog operation. Leaving it as is keeps the current latency behaviour and relies on the handler fix alone.
- Whether a `Copy_Object` whose deadline expires inside the gate-held window should propagate `Timeout_Error` instead of returning `Backend_Unavailable`. Both runs above show `Backend_Unavailable`, because the replacement exception reaches `Copy_Object`'s handler instead of the original. Preserving the original exception changes the outcome a caller observes for a timed-out copy.

The regression test belongs in `sqlite/tests/src/flyology_object_storage_sqlite_tests.adb`, because the gate and the lease table are specific to this backend. The spike is the test, in the first program's deterministic form: annotate a source, make the source body unavailable so the copy's payload check raises under the gate, call `Copy_Object`, then assert from a second task with a bounded wait that `Head_Bucket` still answers. A test written this way must keep the bounded wait, because a failing run otherwise blocks the suite instead of reporting.

## Severity

The store stops answering every operation, on every bucket, for the life of the process, and it cannot be closed or recovered in that process because `Close` also acquires the gate. An S3 server on this backend serves no further request after one CopyObject of an annotated object that is cancelled, that times out, or whose source body is unavailable, and cancellation and deadline are ordinary arguments a server passes on every request. Both routes are demonstrated end to end through the public backend interface, and both programs reproduce the wedge on every run. The mechanism is deterministic; the exact deadline value at which the second program lands is timing dependent, so it scans rather than using a fixed one. SQLite backend only.
