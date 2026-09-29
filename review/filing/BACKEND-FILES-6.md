Title: Deleting the newest generation lets the next PUT reuse the deleted generation's opaque version ID
Labels: bug
Refs: none

## Summary

The files backend derives an object's opaque version identifier from `max(existing publication) + 1`, scanned from the retained generation files, and an exact delete unlinks the generation file outright, leaving nothing that keeps the counter high. Deleting the newest generation and republishing therefore mints the deleted generation's exact version identifier again. `GET key?versionId=<that identifier>` then serves the new object's bytes with 200 instead of 404, so a client, replicator or audit consumer keyed on (key, version ID) silently reads different content under an identifier it believes it has already seen or already deleted. The memory backend uses a monotonic counter and never repeats, so the two backends disagree on an externally visible identity.

## Problem

Commit `5fe6e3e`.

The publication number comes from a scan of what is still on disk (`src/flyology-object_storage-backends-files.adb:1254-1270`):

```ada
   function Next_Generation_Publication
     (Item : Store; Bucket : String; Key : String) return Long_Long_Integer
   is
      Highest : Long_Long_Integer := 0;

      procedure Consider (Candidate : Generation_Entry) is
      begin
         Highest := Long_Long_Integer'Max
           (Highest, Candidate.Publication);
      end Consider;
   begin
      Scan_Generations (Item, Bucket, Key, Consider'Access);
      if Highest = Long_Long_Integer'Last then
         raise Storage_Error;
      end if;
      return Highest + 1;
   end Next_Generation_Publication;
```

The version identifier is a pure function of that number (`src/flyology-object_storage-backends-files.adb:7290-7296`):

```ada
            Publication := Next_Generation_Publication (Item, Bucket, Key);
            if Kind = Opaque_Object then
               Version_ID := US.To_Unbounded_String
                 (GNAT.SHA256.Digest
                    (Files_Version_ID_Domain & Character'Val (0) &
                     Bucket & Character'Val (0) & Key & Character'Val (0) &
                     Long_Long_Integer'Image (Publication)));
```

The same derivation is repeated for delete markers (`:8244-8250`) and for multipart completion (`:11822-11828`).

An exact delete of a non-marker generation removes the file and leaves no residue (`src/flyology-object_storage-backends-files.adb:8419-8425`):

```ada
               else
                  if not Selected.Is_Delete_Marker then
                     Remove_Annotation_Generation
                       (Item, Bucket, Key, Selected);
                  end if;
                  Remove_Path (US.To_String (Selected.Path));
               end if;
```

`Remove_Path` unlinks the generation file (`:8329`). The one branch that does leave a marker behind applies only to null-version deletes, and it removes its own tombstone immediately (`src/flyology-object_storage-backends-files.adb:8400-8418`):

```ada
               if Request_Entry.Selector.Kind = Null_Version
                 and then not Selected.Legacy
               then
                  declare
                     Publication : Long_Long_Integer;
                     Ignored_ID  : US.Unbounded_String;
                     Tombstone : US.Unbounded_String;
                  begin
                     Publish_Generation
                       (Key, Null_Tombstone, Publication, Ignored_ID);
                     Tombstone := US.To_Unbounded_String
                       (Join
                          (Generation_Directory (Item, Bucket, Key),
                           Generation_File_Name
                             (Publication, Null_Tombstone)));
                     Remove_Superseded_Null_Generations
                       (Item, Bucket, Key, US.To_String (Tombstone));
                     Remove_Path (US.To_String (Tombstone));
                  end;
```

So after deleting every generation numbered above some N, the next publication is numbered N+1 again and its identifier is the identifier of a generation that existed before.

The identifier is a caller-visible identity that the selector treats as naming one generation (`src/flyology-object_storage-backends.ads:49-52`):

```ada
   --  Kind of retained generation selected by a read or metadata operation.
   --  @enum Current_Version Select the newest visible non-delete generation
   --  @enum Null_Version Select the distinguished S3 null generation
   --  @enum Exact_Version Select one generated opaque version identifier
```

and the files backend records that it is meant to be an opaque S3 identity (`src/flyology-object_storage-backends-files.adb:50-52`):

```ada
   Generated_Version_ID_Length : constant Positive := 64;
   --  Flyology files versions use one SHA-256 hexadecimal digest.  The value
   --  is an opaque S3 identity; changing its width would alter persisted paths
```

The reference backend states the intended rule in its own declaration (`src/flyology-object_storage-backends-memory.ads:1844-1846`):

```ada
      --  Every retained generation receives one strictly increasing order.
      --  Exhaustion fails closed rather than reusing a version identity.
      Next_Version : Version_Publication_Order := 0;
```

It never rescans surviving generations: it takes `New_Order := Next_Version + 1` and refuses at the type's last value (`src/flyology-object_storage-backends-memory.adb:1429-1433`).

The existing versioning coverage only asserts that three consecutive publications differ (`tests/src/versioned_object_conformance.adb:543-549`):

```ada
      Require
        (US.Length (V1.Version) > 0
         and then US.Length (V1.Version) <= Maximum_Version_ID_Length
         and then V1.Version /= V2.Version
         and then V2.Version /= V3.Version
         and then V1.Version /= V3.Version,
         "enabled version IDs are not bounded and unique");
```

No test deletes the newest generation and republishes. No existing assertion states the wrong behaviour, so none has to change.

## What happens now

Spike: the program below enables versioning, puts `"AAAA"` under one key and records the returned identifier V1, deletes that exact version, puts `"BBBB"` under the same key and records V2, and then asserts that the identifiers differ and that a read selecting V1 does not return the new bytes. The memory backend runs the identical sequence first as the control.

```ada
      Store.Delete_Selected_Object
        (Bucket, Key,
         (Kind => Backends.Exact_Version, ID => First_ID),
         Backends.No_Delete_Object_Conditions, False, null, Forever,
         Outcome, Result);
...
      Check (US.To_String (Second_ID) /= US.To_String (First_ID),
             Label & " the republished version ID differs from the deleted "
             & "one");
...
         Store.Get_Object
           (Bucket, Key, Storage.Whole_Object, Sink, null, Forever, Info,
            Result,
            Selector =>
              (Kind => Backends.Exact_Version, ID => First_ID));
         Check (US.To_String (Sink.Data) /= "BBBB",
                Label & " GET of the deleted version ID does not serve the "
                & "new bytes");
```

Output, exit status 1:

```
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
BUG REPRODUCED: 2 failed expectation(s)
```

On the files store V2 is character for character V1, and the read that selects the deleted identifier succeeds and returns `"BBBB"`, the bytes of the object published after the delete. The memory backend mints a different identifier and answers `Not_Found` for the deleted one.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire.

## What should happen

An opaque version identifier names one generation for the life of the bucket, so an identifier that was returned for one object's bytes is never returned again for different bytes, and a read selecting a deleted identifier is `Not_Found`. That is what the memory backend guarantees at `src/flyology-object_storage-backends-memory.ads:1844-1846`, and the two backends have to agree on a caller-visible identity.

## Suggested treatment

This needs a maintainer decision, because every option changes the on-disk layout or the record format:

- Persist a per-key monotonic publication high-water mark and derive the next publication from it instead of from the scan at `src/flyology-object_storage-backends-files.adb:1265`. This keeps the identifier reproducible from the publication number and adds one more persisted object per key that has to be written under the publication gate, synced, and recovered when it is missing from an existing root.
- Leave a tombstone for exact deletes the way the null-version path at `:8400-8418` already does, so the scan still sees the high-water mark. This reuses an existing mechanism and no new file kind is needed, but it turns every exact delete into a publication, and the tombstones have to be retained and skipped by listings for as long as the key exists.
- Mix an entropy source or the publication time into the digest at `:7292-7296`, `:8246-8250` and `:11824-11828`. This is the smallest code change and it ends the current property that a generation's identifier is reproducible from its file name, which the file-name derivation and any tooling that relies on it would have to stop assuming.

The regression test belongs with the shared backend conformance helpers in `tests/src/flyology-object_storage-backends-testing.adb`, as a procedure over `Backends.Backend'Class` called from both the memory and the files fixture in `tests/src/object_storage_test_cases.adb`, so that both backends are gated by the same assertion. The nearest existing coverage is the uniqueness assertion in `tests/src/versioned_object_conformance.adb:543-549`, which only compares three consecutive publications and would still pass. The spike is the test: it asserts both the distinct identifier and the second-order effect that the deleted identifier does not read back the new bytes.

## Severity

A client, replicator or audit consumer that keys on (object key, version ID) reads different content under an identifier it has already recorded, and a `GET` for a version it deleted returns 200 with someone else's bytes instead of 404. Nothing in the response marks the identifier as reused. It needs an exact delete of the newest generation, or of every generation above some point, followed by a republish of the same key, which is a normal retention or correction operation rather than an error path but is not the common case. The same sequence on the memory backend behaves correctly, so an application validated against one backend misbehaves on the other. Deterministic. Files backend only.
