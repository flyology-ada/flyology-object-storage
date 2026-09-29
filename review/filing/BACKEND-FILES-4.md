Title: A failed DeleteObject destroys the object's acknowledged annotations while leaving the object in place
Labels: bug
Refs: BACKEND-FILES-1

## Summary

`Delete_One` removes the object's annotation sidecar, including the directory fsync that makes the removal durable, before it issues the unlink that is the delete's publication point. When the unlink fails, the batch is reported as `Backend_Unavailable`, the object is still present and still readable, and the annotations that the client stored and the server acknowledged are gone. No request asked for their deletion, annotations are independent payloads with their own size, ETag and checksum, so nothing can re-derive them, and the response is indistinguishable from an ordinary transient failure.

## Problem

Commit `5fe6e3e`.

`Delete_One` removes the sidecar first in both branches that unlink a generation. The unversioned current delete (`src/flyology-object_storage-backends-files.adb:8428-8437`):

```ada
            case Configuration.Status is
               when Versioning_Unconfigured =>
                  if Condition_Exists then
                     Outcome.Publication.Kind := Object_Version_Removed;
                     Remove_Annotation_Generation
                       (Item, Bucket, Key, Selected);
                     Remove_Path (US.To_String (Selected.Path));
                  else
                     Outcome.Publication.Kind := No_Version_Removed;
                  end if;
```

and the exact-version delete (`src/flyology-object_storage-backends-files.adb:8419-8425`):

```ada
               else
                  if not Selected.Is_Delete_Marker then
                     Remove_Annotation_Generation
                       (Item, Bucket, Key, Selected);
                  end if;
                  Remove_Path (US.To_String (Selected.Path));
               end if;
```

The first step is durable before the second is attempted. `Remove_Annotation_Generation` (`src/flyology-object_storage-backends-files.adb:1034-1046`):

```ada
   procedure Remove_Annotation_Generation
     (Item     : Store;
      Bucket   : String;
      Key      : String;
      Selected : Selected_Generation)
   is
      Directory : constant String :=
        Annotation_Generation_Directory (Item, Bucket, Key, Selected);
   begin
      if Annotation_Directory_Exists (Item, Bucket, Key, Selected) then
         Remove_Tree (Item, Directory);
      end if;
   end Remove_Annotation_Generation;
```

and `Remove_Tree` (`src/flyology-object_storage-backends-files.adb:338-347`):

```ada
   procedure Remove_Tree (Item : Store; Path : String) is
      Parent : constant String := Ada.Directories.Containing_Directory (Path);
   begin
      if GNAT.OS_Lib.Is_Symbolic_Link (Path) then
         raise Ada.IO_Exceptions.Name_Error;
      end if;
      Validate_Tree_Symlink_Free (Path);
      Ada.Directories.Delete_Tree (Path);
      Sync_Directory (Item, Parent);
   end Remove_Tree;
```

The second step has several ways to fail (`src/flyology-object_storage-backends-files.adb:8320-8332`):

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
            Sync_Directory
              (Item, Ada.Directories.Containing_Directory (Path));
         end Remove_Path;
```

`Delete_File` fails on EACCES against a directory that lost write permission, on EPERM after a read-only remount, and on EIO; `Data_Error` is raised when a concurrent external change made the path something other than an ordinary file. Any of these reaches the batch handler, which discards the outcomes and reports failure (`src/flyology-object_storage-backends-files.adb:8537-8542`):

```ada
      when others =>
         if Locked then
            Item.Publication.Release;
         end if;
         Outcomes.Clear;
         Result := Backend_Unavailable;
```

The S3 boundary renders that as a retryable 503 (`src/flyology-object_storage-server-s3_applications.adb:1951-1954`):

```ada
         when Capacity_Exceeded | Backend_Unavailable =>
            Send_Error
              (X, 503, "SlowDown",
               "Please reduce your request rate", Resource);
```

Nothing can reconstruct what was removed. An annotation is a payload in its own right (`src/flyology-object_storage.ads:571-577`):

```ada
   type Object_Annotation_Information is record
      Size       : Byte_Count;
      Modified   : Unix_Time;
      Entity_Tag : Ada.Strings.Unbounded.Unbounded_String;
      Checksum   : Checksum_Information;
      Version    : Ada.Strings.Unbounded.Unbounded_String;
   end record;
```

A later successful `DeleteObject` removes only the object, and no path recreates a removed sidecar.

The delete qualification record covers the opposite direction only (`docs/qualification/delete-object.md:46-51`):

```
Pure-files unlink is the publication point. A later directory-sync failure can
return `Backend_Unavailable` after the name is already gone, so a single caller
must reconcile the exact key/generation. A batch may expose a deleted prefix
after a later failure or cancellation. The deterministic barrier and
cancellation lanes gate both cases; no status or exception after publication is
documented as proof that deletion did not occur.
```

It documents that a failure status is not proof the object deletion did not occur. It says nothing about destroying a different acknowledged payload in the case where the deletion demonstrably did not occur.

The same ordering leaves the same window across a crash, because the sidecar removal is fsynced through `Sync_Directory` at `:346` before the unlink at `:8424` and `:8434` is issued: a power loss between the two steps leaves the object present without its annotations on any filesystem. That variant is established by reading the code above only. The crash corpus does not gate it: `tests/src/files_crash_probe.adb` contains no annotation step at all (its `delete` scenario at `:399-408` seeds an object and deletes it with a condition), and the matrix in `tests/scripts/test.sh` runs `run_crash_cases delete 1` (`:136`) and `run_crash_cases delete-objects 2` (`:137`) over that annotation-free scenario. There is also a narrower window on the PUT path, where the previous sidecar is removed at `src/flyology-object_storage-backends-files.adb:7389-7392` before the destination directory barrier at `:7393-7394`; whether a crash there can lose the sidecar while keeping the old record depends on filesystem-specific ordering and could not be established on APFS, so no claim is made about it.

No fault injection targets `Delete_File` anywhere in the suite, so the reported-failure case below is not covered either.

## What happens now

Spike: the program below seeds an object plus one annotation twice on a files store. The control key is deleted with no injection, so the sequence and the harness are shown sound. For the subject key it makes `buckets/<bucket>/objects/` mode `0500`, which leaves the sidecar removal (under `annotations/`) able to succeed while the unlink (needing write permission on `objects/`) fails, calls `DeleteObject`, restores the mode, and then asserts that the surviving object still has the annotation.

```ada
   Chmod ("0500", Objects_Directory);
   Subject.Delete_Object (Bucket, "doomed-key", null, Forever, Result);
   Note ("injected: DeleteObject -> " & Result'Image);
   Chmod ("0700", Objects_Directory);

   Check (Result /= Storage.Success,
          "the injected delete is reported as failed");
   Check (Object_Present ("doomed-key"),
          "the object survives the failed delete");
   Check (Annotation_Count ("doomed-key") = 1,
          "the surviving object keeps the annotation that no request ever "
          & "asked to delete");
```

Output, exit status 1:

```
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
  ok: chmod 0500 /private/tmp/.../buckets/delete-bucket/objects succeeds
  -- injected: DeleteObject -> BACKEND_UNAVAILABLE
  ok: chmod 0700 /private/tmp/.../buckets/delete-bucket/objects succeeds
  ok: the injected delete is reported as failed
  ok: the object survives the failed delete
  -- annotations listed for the surviving object = 0
  FAILED: the surviving object keeps the annotation that no request ever asked to delete
  -- GetObjectAnnotation(doomed-key/alpha) -> SUCCESS presence ANNOTATION_ABSENT
  FAILED: the annotation payload is still readable after the failed delete
BUG REPRODUCED: 2 failed expectation(s)
```

The delete reported `Backend_Unavailable`, the object is still readable, and the annotation is gone: the listing returns an empty page and `GetObjectAnnotation` reports `Annotation_Absent` for a name that was acknowledged and never deleted. The control key deleted cleanly in the same run, so the injection is what makes the difference.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire.

## What should happen

A delete that does not remove its target must leave the target's annotations intact. The publication point is the unlink (`docs/qualification/delete-object.md:46`), so nothing that a failure can still cancel may be destroyed before it, and a status of `Backend_Unavailable` with the object still in place must mean the store is unchanged.

## Suggested treatment

Reorder the two steps in both branches, so the unlink at `src/flyology-object_storage-backends-files.adb:8424` and `:8434` runs first and `Remove_Annotation_Generation` follows it. The sidecar identity is read from the record, so it has to be captured before the unlink, exactly as the PUT path already captures `Previous_Annotation_ID` at `:7247-7249` and applies it after the rename at `:7389-7392`; `Remove_Annotation_Generation_For_ID` (`:1048`) is the form that takes the captured identity. After the reorder the failure mode inverts from silent loss to a recoverable orphan directory, which is the same residue that {{ISSUE:BACKEND-FILES-1}} leaves behind on multipart completion.

Where the orphan sweep that collects those directories belongs is a maintainer decision:

- In `Open`, beside the existing `tmp/` sweep and `Recover_Null_Tombstones` at `src/flyology-object_storage-backends-files.adb:3553-3566`, so a crash is repaired at the next start. This adds work proportional to the annotation tree to every open.
- In `Delete_Bucket`, which today removes the whole bucket tree at `src/flyology-object_storage-backends-files.adb:3854-3855` and checks emptiness only for `objects/`, `multipart/` and `versions/` (`:3846-3850`). This reclaims the space eventually but leaves the orphan in place for the life of the bucket.
- In both.

No public constant, variant, parameter or status changes under any of these.

The crash variant belongs in the deterministic crash corpus: add a `delete-with-annotation` scenario to `tests/src/files_crash_probe.adb` beside the existing `delete` scenario at `:399-408`, seeding an annotation in `Prepare` and asserting on reopen that the object and its annotation are either both present or both gone, and register it in the matrix in `tests/scripts/test.sh` beside `run_crash_cases delete 1` at `:136`. The reported-failure variant is what the spike covers, and it fits the same probe as an injected-permission case, since it needs a `chmod` between the two steps that an in-process suite case cannot express cleanly. No existing assertion in either file is wrong, so none has to change.

## Severity

A `DeleteObject` that fails and does not delete anything destroys a different payload that the client stored and the server acknowledged, with no request having asked for it, no way to reconstruct it and no diagnostic that separates this from ordinary backpressure: the client sees 503 SlowDown and retries. It needs the unlink to fail, which happens on a permission or mount change, on an I/O error, or when something outside the store changed the path, and the same state follows from a power loss between the two steps on any filesystem. The reported-failure variant reproduces every time under the injection above. Deterministic. Files backend only.
