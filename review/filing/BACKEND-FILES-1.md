Title: Multipart completion in an unversioned bucket inherits the replaced object's annotations and orphans a sidecar
Labels: bug
Refs: BACKEND-FILES-4

## Summary

`Complete_Multipart_Upload` publishes its record without an annotation generation identity, so the persisted field is empty and the sidecar identity falls back to the SHA-256 of the object path. In an unversioned bucket every generation of a key lives at the same fixed path, so two completions in a row on one key share one annotation sidecar: annotations acknowledged against the first completed object are served, byte for byte and with their original ETag, as annotations of the second completed object's bytes. Completion also never removes the replaced generation's sidecar, which ordinary `PutObject` does, so a completion that replaces a PUT-created generation leaves a `generation-*` directory that no later request can read or delete. The reference memory backend clears the annotation map on completion, so the two backends disagree on what a newly completed object contains.

## Problem

Commit `5fe6e3e`.

In an unversioned bucket the completion targets the one fixed object path, and it writes the record with no annotation generation identity (`src/flyology-object_storage-backends-files.adb:11810-11811` and `:11852-11855`):

```ada
      if Configuration.Status = Versioning_Unconfigured then
         Target := US.To_Unbounded_String (Object_Path (Item, Bucket, Key));
...
      Validate_New_Temp_Target (Item, US.To_String (Temp));
      SIO.Create (File, SIO.Out_File, US.To_String (Temp));
      Opened := True;
      Write_Header (File, Key, Info, Parts => Completed_Parts);
```

That parameter defaults to the empty string (`src/flyology-object_storage-backends-files.adb:2340-2349`):

```ada
   procedure Write_Header
     (File : in out SIO.File_Type;
      Key  : String;
      Info : Object_Information;
      Tags : Object_Tag_Set := Empty_Object_Tags;
      Parts : Completed_Object_Part_List :=
        Completed_Object_Part_Vectors.Empty_Vector;
      Object_Lock : Persisted_Object_Lock_State := (others => <>);
      Annotation_Generation_ID : String := "";
      Checksum_Value_At : access SIO.Positive_Count := null)
```

and it is written as the record's trailing field (`src/flyology-object_storage-backends-files.adb:2493-2494`):

```ada
      Write_U32 (File, Annotation_Generation_ID'Length);
      Write_String (File, Annotation_Generation_ID);
```

read back into `Info.Version` (`src/flyology-object_storage-backends-files.adb:2811-2827`). An empty field makes the sidecar identity a function of the path (`src/flyology-object_storage-backends-files.adb:2892-2897`):

```ada
      if US.Length (Info.Version) = Generated_Version_ID_Length then
         return US.To_String (Info.Version);
      elsif US.Length (Info.Version) = 0 then
         --  FOSOBJ01 through FOSOBJ06 predate annotation generations.  Their
         --  path-derived identity preserves the established sidecar layout.
         return GNAT.SHA256.Digest (US.To_String (Selected.Path));
```

Every annotation read and write resolves its directory through that value (`src/flyology-object_storage-backends-files.adb:892-899`):

```ada
   function Annotation_Generation_Directory
     (Item     : Store;
      Bucket   : String;
      Key      : String;
      Selected : Selected_Generation) return String
   is
     (Annotation_Generation_Directory_For_ID
        (Item, Bucket, Key, Stored_Annotation_Generation_ID (Selected)));
```

Ordinary `PutObject` does neither of these things. It mints a fresh identity per publication (`src/flyology-object_storage-backends-files.adb:7093-7099`):

```ada
      Item.Temp_Sequence.Next (Number);
      Annotation_Generation_ID := US.To_Unbounded_String
        (GNAT.SHA256.Digest
           ("flyology-files-annotation-generation" & Character'Val (0) &
            Bucket & Character'Val (0) & Key & Character'Val (0) &
            Long_Long_Integer'Image (Number) & Character'Val (0) &
            Ada.Calendar.Time'Image (Ada.Calendar.Clock)));
```

writes it into the header (`:7128-7132`), captures the replaced generation's identity before the rename (`:7247-7249`), and removes that sidecar after it (`src/flyology-object_storage-backends-files.adb:7388-7392`):

```ada
      Published := True;
      if US.Length (Previous_Annotation_ID) > 0 then
         Remove_Annotation_Generation_For_ID
           (Item, Bucket, Key, US.To_String (Previous_Annotation_ID));
      end if;
```

`Complete_Multipart_Upload` (`:11554-11954`) contains no call to either removal helper.

The reference backend publishes the completed object with an empty annotation set (`src/flyology-object_storage-backends-memory.adb:3343-3349`):

```ada
            --  Finish every allocating metadata operation before consuming
            --  the staged upload or publishing its assembled payload.
            Next_Version := New_Order;
            Objects (Object_At).Annotations.Clear;
            Objects (Object_At).Bucket := Stored_Bucket;
            Objects (Object_At).Key := Stored_Key;
            Objects (Object_At).Info := Completed_Info;
```

The backends are required to agree. `docs/qualification/object-annotations-backend-server.md:26` states:

```
Memory, pure-files, and SQLite implement the same interface. Pure-files keeps
```

and the annotation contract binds each annotation to one generation (`src/flyology-object_storage-backends.ads:2288-2291`):

```ada
   --  Atomically replace one named annotation on a selected generation. The
   --  payload is consumed before publication; checksum and parent-object
   --  predicates are evaluated over the same selected generation. The
   --  returned ETag is an unquoted lowercase MD5 digest.
```

Versioned buckets are not affected: an enabled or suspended completion publishes under a generation file name that carries the publication number and, for an enabled bucket, sets `Info.Version` to the minted wire identifier (`src/flyology-object_storage-backends-files.adb:11812-11843`), so the identity differs per publication. The defect is confined to `Versioning_Unconfigured`.

The orphan cannot be reclaimed through the API while the bucket exists. `Delete_Bucket` tests emptiness for `objects/`, `multipart/` and `versions/` only and then removes the whole bucket tree (`src/flyology-object_storage-backends-files.adb:3846-3855`):

```ada
      elsif Has_Objects (Join (Path, "objects"))
        or else Has_Objects (Join (Path, "multipart"))
        or else
          (Ada.Directories.Exists (Join (Path, "versions"))
           and then Has_Objects (Join (Path, "versions")))
      then
         Result := Bucket_Not_Empty;
      else
         Validate_Tree_Symlink_Free (Path);
         Ada.Directories.Delete_Tree (Path);
```

so the only way to reclaim an orphan `generation-*` directory is to empty and delete the bucket.

The annotation operations are reachable over HTTP against a files store: the S3 application dispatches all four through the `*_If_Supported` wrappers (`src/flyology-object_storage-server-s3_applications.adb:15622`, `:15653`, `:15683`, `:15736`) and `Files.Store` is declared with `Object_Annotation_Backend` (`src/flyology-object_storage-backends-files.ads:14-16`).

No test covers the combination. The shared annotation exercise runs on both backends (`tests/src/object_storage_test_cases.adb:19734` and `:19743` call `Exercise_Object_Annotations`, declared at `:19555`) and contains no multipart step. `tests/src/multipart_part_conformance.adb` contains no annotation step. No existing assertion is wrong, so none has to change.

## What happens now

Spike: the program below runs two scenarios against the memory backend as a control and then against a files store on a fresh root, both on an unversioned bucket. Scenario A is `PutObject`, `PutObjectAnnotation`, then a one-part `CompleteMultipartUpload` on the same key. Scenario B is `CompleteMultipartUpload`, `PutObjectAnnotation`, then `CompleteMultipartUpload` again. After each it asserts an empty annotation page and `Annotation_Absent`, and it finally counts the `generation-*` directories left on disk under each key's annotation subtree.

```ada
      Annotate (Store, "put-then-complete", "alpha", Label);
      Complete_One_Part_Upload
        (Store, "put-then-complete", "mp-body-1", Label);
      Check (Annotation_Count (Store, "put-then-complete", Label) = 0,
             Label & " A: the completed object starts with no annotations");
...
      Complete_One_Part_Upload (Store, "complete-twice", "mp-body-2", Label);
      Annotate (Store, "complete-twice", "beta", Label);
      Complete_One_Part_Upload (Store, "complete-twice", "mp-body-3", Label);
      Check (Annotation_Count (Store, "complete-twice", Label) = 0,
             Label & " B: the second completed object starts with no "
             & "annotations");
```

Output, exit status 1, with repeated `ok:` lines from the memory control and from the harness steps trimmed:

```
  ok: memory (control) A: the completed object starts with no annotations
  ok: memory (control) A: GetObjectAnnotation reports the annotation absent
  -- memory (control) B: annotations after the second COMPLETE = 0
  ok: memory (control) B: the second completed object starts with no annotations
  ok: memory (control) B: GetObjectAnnotation reports the annotation absent
  ok: files  (subject) CreateBucket succeeds
  ok: files  (subject) PutObject succeeds
  ok: files  (subject) PutObjectAnnotation put-then-complete/alpha
  ok: files  (subject) the annotation is visible before replacement
  ok: files  (subject) CompleteMultipartUpload put-then-complete
  -- files  (subject) A: annotations after COMPLETE replaced a PUT = 0
  ok: files  (subject) A: the completed object starts with no annotations
  ok: files  (subject) A: GetObjectAnnotation reports the annotation absent
  ok: files  (subject) CompleteMultipartUpload complete-twice
  ok: files  (subject) PutObjectAnnotation complete-twice/beta
  ok: files  (subject) the annotation is visible before the second completion
  ok: files  (subject) CompleteMultipartUpload complete-twice
  -- files  (subject) B: annotations after the second COMPLETE = 1
  FAILED: files  (subject) B: the second completed object starts with no annotations
  FAILED: files  (subject) B: GetObjectAnnotation reports the annotation absent
  -- files A: sidecar generation- directories left under /private/tmp/.../buckets/anno-bucket/annotations/7075742D7468656E2D636F6D706C657465.annotations = 1
  FAILED: files  (subject) A: the PUT generation's sidecar directory is removed by the completion that replaced it (no orphan)
  -- files B: sidecar generation- directories left under /private/tmp/.../buckets/anno-bucket/annotations/636F6D706C6574652D7477696365.annotations = 1
  FAILED: files  (subject) B: the replaced completion's sidecar directory is removed by the second completion
BUG REPRODUCED: 4 failed expectation(s)
```

Read the two scenarios separately. In A the annotation correctly disappears from the API after the completion, because the PUT had minted its own identity and the completed record resolves a different one; what A leaves behind is the orphan directory, one per key, which the count line reports and no request can reach. In B, where the replaced generation was itself produced by a completion, both records resolve the same path-derived identity and the annotation written against the first completed object is returned for the second: the listing has one entry and `GetObjectAnnotation` reports it present. The memory backend answers 0 in both scenarios.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire.

## What should happen

A newly published object generation starts with no annotations, and publishing it releases the replaced generation's annotation storage. That is what the reference backend does (`src/flyology-object_storage-backends-memory.adb:3346`), what the files PUT path does (`src/flyology-object_storage-backends-files.adb:7093-7099` and `:7388-7392`), and what `docs/qualification/object-annotations-backend-server.md:26` requires of the three backends together.

## Suggested treatment

Give `Complete_Multipart_Upload` the same two steps that `Put_Object_Internal` already has: mint an annotation generation identity before `Write_Header` and pass it at `src/flyology-object_storage-backends-files.adb:11855`, and capture the replaced generation's identity under the gate before the rename so that `Remove_Annotation_Generation_For_ID` (`:1048`) can run after it, as at `:7388-7392`. This is confined to the unversioned branch, since the versioned branch already sets `Info.Version` at `:11842`. A crash between the rename and the removal then leaves an orphan directory instead of a shared identity, which is the same residue that the reordering asked for in {{ISSUE:BACKEND-FILES-4}} produces, so one orphan sweep serves both.

The second half of the fix is a maintainer decision, because it changes the meaning of records already on disk:

- Keep the path-derived fallback at `src/flyology-object_storage-backends-files.adb:2894-2897` for every record with an empty field. Records written by current code stop taking it, but any FOSOBJ01 through FOSOBJ06 record and any record written by an earlier build of the current format keeps the shared identity, so an unversioned key that already has two completed generations stays affected until it is republished.
- Retire the fallback for the current record version and treat an empty field as no annotation storage. This makes the behaviour uniform immediately and changes the on-disk contract for the older record versions the comment at `:2895-2896` names.

The regression test belongs with the shared backend conformance helpers in `tests/src/flyology-object_storage-backends-testing.adb`, as a procedure over `Backends.Backend'Class` called from both the memory and the files fixture in `tests/src/object_storage_test_cases.adb`, so that both backends are gated by one assertion. The nearest existing coverage is `Exercise_Object_Annotations` (`tests/src/object_storage_test_cases.adb:19555`), which is already run against both backends at `:19734` and `:19743` and has no multipart step. The spike is the test: the second scenario asserts the inheritance and the count of leftover `generation-*` directories asserts the orphan.

## Severity

A client that uses object annotations together with multipart uploads on an unversioned bucket reads one object's annotations as another object's, with the original ETag and payload, after an ordinary sequence of two completions on the same key. Nothing in the response marks the annotations as stale, and the same sequence on the memory backend returns none, so an application that trusts either backend gets different answers from the two. It needs no concurrency, no unusual configuration and no error path. The orphan half wastes space that no request can reclaim until the bucket is deleted, which is a smaller effect than the inheritance. Deterministic. Files backend only.
