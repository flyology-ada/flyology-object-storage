Title: ListMultipartUploads pagination silently drops same-key uploads whose upload IDs sort against initiation order
Labels: bug
Refs: none

## Summary

The shared multipart listing builder orders same-key uploads by initiation time, filters them against the `upload-id-marker` by lexical upload ID, and builds the continuation cursor from the last upload it returned. Those three rules are mutually inconsistent whenever the two orders disagree, which is the normal case here because upload IDs are SHA-256 digests with no relation to creation order. A client that pages ListMultipartUploads with the markers the service itself returned loses every same-key upload whose ID sorts at or before the marker, and the truncated flag goes false, so nothing tells the client that uploads are missing.

## Problem

Commit `5fe6e3e`.

The page order for a shared key is initiation time, with the upload ID only as an equal-time tie break (`src/flyology-object_storage-backends-multipart_listing.adb:17-30`):

```ada
   function Before (Left, Right : Candidate) return Boolean is
      Left_Key  : constant String := US.To_String (Left.Key);
      Right_Key : constant String := US.To_String (Right.Key);
   begin
      return Left_Key < Right_Key
        or else
          (Left_Key = Right_Key
           and then
             (Left.Initiated < Right.Initiated
              or else
                (Left.Initiated = Right.Initiated
                 and then US.To_String (Left.Upload_ID) <
                   US.To_String (Right.Upload_ID))));
   end Before;
```

The exclusive marker test is purely lexical on the upload ID and never mentions `Initiated` (`src/flyology-object_storage-backends-multipart_listing.adb:84-91`):

```ada
         if Candidate_Key < After_Key
           or else
             (Candidate_Key = After_Key
              and then
                (After_ID'Length = 0 or else Candidate_ID <= After_ID))
         then
            return;
         end if;
```

The continuation cursor is the key and upload ID of the last returned candidate, so the service produces the marker pair that its own filter then misreads (`src/flyology-object_storage-backends-multipart_listing.adb:141-149`):

```ada
      if Result.Is_Truncated then
         if Returned = 0 then
            Result.Next_After := Item.Options.After;
         else
            Result.Next_After.Key := Item.Candidates (Returned).Key;
            Result.Next_After.Upload_ID :=
              Item.Candidates (Returned).Upload_ID;
         end if;
      end if;
```

The two orders disagree by construction in the memory backend. The upload ID is a SHA-256 digest (`src/flyology-object_storage-backends-memory.adb:2831-2834`):

```ada
         Upload_ID := Ada.Strings.Unbounded.To_Unbounded_String
           (GNAT.SHA256.Digest
              (Bucket & Character'Val (0) & Key & Character'Val (0) &
               Long_Long_Integer'Image (Next_Upload)));
```

and the initiation stamp has whole-second resolution (`src/flyology-object_storage-backends-memory.adb:207-208`):

```ada
   function Current_Unix_Time return Unix_Time is
     (Unix_Time (Long_Long_Integer (Ada.Calendar.Clock - Epoch)));
```

so two uploads more than a second apart get distinct `Initiated` values and the page order is decided by time, while the marker filter still decides by digest.

Nothing above the backend repairs it. The server copies `key-marker` and `upload-id-marker` straight into the backend options (`src/flyology-object_storage-server-s3_applications.adb:11191-11197`):

```ada
                            (Prefix    => Request.Prefix,
                             Delimiter => Request.Delimiter,
                             After     =>
                               (Key       => Request.Key_Marker,
                                Upload_ID => Request.Upload_ID_Marker),
                             Maximum   =>
                               Backends.List_Limit (Request.Max_Uploads));
```

and copies the backend's cursor straight back out (`src/flyology-object_storage-server-s3_applications.adb:11240-11247`):

```ada
                           if Page.Is_Truncated then
                              Response.Next_Key_Marker :=
                                US.To_Unbounded_String
                                  (Encoded
                                     (US.To_String (Page.Next_After.Key)));
                              Response.Next_Upload_ID_Marker :=
                                Page.Next_After.Upload_ID;
                           end if;
```

The two rules are the two AWS rules, and the repository has already written down that they must not be assumed to coincide (`docs/qualification/list-multipart-uploads-preparation.md:39-45`):

```
AWS separately describes response order as ascending key and, for a shared
key, ascending initiation time. Its marker rule permits same-key uploads only
when their upload IDs compare after the supplied upload-ID marker. The later
implementation and oracle must exercise inverse upload-ID/initiation-time data
rather than assume those orders coincide. A service-produced marker pair must
always resume without skipping, repeating, or looping, with a deterministic
upload-ID tie break for equal initiation times.
```

The pinned botocore S3 model at botocore commit `36c34f15391da01cd717c73c0fffa747c9889768` states the same two halves. `ListMultipartUploadsRequest.UploadIdMarker`: "Together with key-marker, specifies the multipart upload after which listing should begin. If key-marker is not specified, the upload-id-marker parameter is ignored. Otherwise, any multipart uploads for a key equal to the key-marker might be included in the list only if they have an upload ID lexicographically greater than the specified `upload-id-marker`." `ListMultipartUploadsOutput.NextUploadIdMarker`: "When a list is truncated, this element specifies the value that should be used for the `upload-id-marker` request parameter in a subsequent request." A page bound is not unusual input: `ListMultipartUploadsRequest.MaxUploads` is documented there as "from 1 to 1,000".

The backend contract states the two rules side by side without reconciling them (`src/flyology-object_storage-backends.ads:2711-2715`):

```ada
   --  Return one atomic snapshot of active uploads after the exclusive marker.
   --  Keys use unsigned bytewise lexical order. Uploads with the same key use
   --  initiation-time order and upload ID breaks equal-time ties; marker
   --  filtering independently follows S3's lexical upload-ID rule.
   --  Delimiter-collapsed prefixes count toward Maximum like returned uploads.
```

The existing coverage passes while asserting a weaker property. All five uploads are created in one tight loop (`tests/src/object_storage_test_cases.adb:3318-3328`), so the two same-key uploads share an `Initiated` value and the page order falls through to the upload-ID tie break, which coincides with the marker rule. The marker assertion uses a deliberately chosen smaller and larger ID rather than creation order (`tests/src/object_storage_test_cases.adb:3379-3389`):

```ada
      Options := (others => <>);
      Options.After.Key := US.To_Unbounded_String ("same");
      Options.After.Upload_ID := Smaller_ID;
      Store.List_Multipart_Uploads
        (Bucket, Options, null, Ada.Real_Time.Time_Last, Page, Result);
      Assert
        (Result = Success and then Page.Uploads.Length = 2
         and then US.To_String (Page.Uploads (1).Upload_ID) =
           US.To_String (Larger_ID)
         and then US.To_String (Page.Uploads (2).Key) = "zeta",
         "multipart upload-ID marker filtering");
```

No test creates same-key uploads across a second boundary, so no test asserts the wrong behaviour and none has to change.

## What happens now

Spike: the program below initiates six multipart uploads for one key on a private memory store, one second apart, lists them unbounded as a control, then walks the listing with `Maximum => 1` following the cursor the service returns, asserting each upload comes back exactly once. It then repeats the walk over the in-process S3 application with `?uploads&max-uploads=1&key-marker=...&upload-id-marker=...`.

```ada
      for Index in 1 .. Uploads_Wanted loop
         if Index > 1 then
            Support.Advance_One_Second;
         end if;
         Store.Create_Multipart_Upload
           (Bucket, Key, Backends.Default_Multipart_Options, null, Deadline,
            Created (Index), Result);
...
      --  The walk under test: Maximum = 1, following the returned cursor.
      Options := (others => <>);
      Options.Maximum := 1;
      for Step in 1 .. 3 * Uploads_Wanted loop
         Store.List_Multipart_Uploads
           (Bucket, Options, null, Deadline, Page, Result);
...
         exit when not Page.Is_Truncated;
         Options.After := Page.Next_After;
      end loop;
```

Output, exit status 1, with the six per-upload initiation lines trimmed to the first and last:

```
  ok: backend: bucket created
  ok: backend: upload1 initiated
  -- backend: initiation order1 id dc3e6a657ac580f3a4df5f53a1aa570d861b135eabcd560f2e5936367c9cddd5
  ok: backend: upload6 initiated
  -- backend: initiation order6 id c4dd2ccd99b9625d41552478b4bd692ba625a4db414a4994e09cd6ae36d60da3
  ok: control: unbounded listing succeeds and is complete
  ok: control: unbounded listing returns every active upload
  -- backend: page order1 initiated 1788761467 id dc3e6a657ac580f3a4df5f53a1aa570d861b135eabcd560f2e5936367c9cddd5
  -- backend: page order6 initiated 1788761472 id c4dd2ccd99b9625d41552478b4bd692ba625a4db414a4994e09cd6ae36d60da3
  -- backend: page1 uploads1 truncated TRUE next-key 'k' next-id 'dc3e6a657ac580f3a4df5f53a1aa570d861b135eabcd560f2e5936367c9cddd5'
  -- backend: page2 uploads0 truncated FALSE next-key '' next-id ''
  ok: backend: every page succeeded
  -- backend: walk returned1 of6 uploads
  FAILED: backend: paired-cursor walk returns every active upload
  ok: backend: initiation order1 returned exactly once by the walk
  FAILED: backend: initiation order2 returned exactly once by the walk
  FAILED: backend: initiation order3 returned exactly once by the walk
  FAILED: backend: initiation order4 returned exactly once by the walk
  FAILED: backend: initiation order5 returned exactly once by the walk
  FAILED: backend: initiation order6 returned exactly once by the walk
  ok: control: wire ListMultipartUploads is 200
  -- control: unbounded wire listing reported6 uploads, IsTruncated false
  ok: control: unbounded wire listing returns every upload
  ok: wire: page1 is 200
  -- wire: page1 uploads1 IsTruncated TRUE NextKeyMarker 'k' NextUploadIdMarker '942bb21a5ebfcde5ebd2b01a2554177a62e43461baaccb9ce3061d20b450690e'
  ok: wire: page2 is 200
  -- wire: page2 uploads1 IsTruncated TRUE NextKeyMarker 'k' NextUploadIdMarker 'eea53f36e17e5f3ad8155674dc19707d4c5ceaa7311c335b78da5ea3a80d4579'
  ok: wire: page3 is 200
  -- wire: page3 uploads0 IsTruncated FALSE NextKeyMarker '' NextUploadIdMarker ''
  -- wire: walk returned2 of6 uploads
  FAILED: wire: paired-cursor walk returns every active upload
  ok: wire: initiation order1 returned exactly once by the walk
  FAILED: wire: initiation order2 returned exactly once by the walk
  ok: wire: initiation order3 returned exactly once by the walk
  FAILED: wire: initiation order4 returned exactly once by the walk
  FAILED: wire: initiation order5 returned exactly once by the walk
  FAILED: wire: initiation order6 returned exactly once by the walk
BUG REPRODUCED: 11 failed expectation(s)
```

The unbounded listing returns all six uploads. The paged walk returns 1 of 6 at the backend interface and 2 of 6 over the wire, and in both cases the last page reports the listing as not truncated, so a client is told the walk is complete. Every digest in the run is deterministic, because the upload ID is a digest of the bucket, the key and the store counter.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Shapes checked against the pinned botocore S3 model.

## What should happen

A marker pair the service itself returned must resume the listing without skipping any active upload, which is what `docs/qualification/list-multipart-uploads-preparation.md:43-45` requires and what `NextUploadIdMarker` promises in the pinned botocore S3 model. The page order and the marker filter must therefore use one and the same ordering key.

## Suggested treatment

The fix belongs in `src/flyology-object_storage-backends-multipart_listing.adb`, which the files and SQLite backends share, not in one store. Which of the two S3 rules wins is externally visible ordering policy, so this needs a maintainer decision:

- Make the page order for a shared key lexical upload ID, by dropping `Initiated` from `Before` at `:17-30`. The marker filter at `:84-91` then matches the page order exactly and no cursor can skip. This diverges from the initiation-time response order that `docs/qualification/list-multipart-uploads-preparation.md:39-40` records as AWS's, and the sentence at `src/flyology-object_storage-backends.ads:2712-2714` has to change with it.
- Keep the initiation-time page order and make the marker filter follow it, by resolving `After_ID` to its `Initiated` value and comparing candidates on the same `(Initiated, Upload_ID)` key `Before` uses. This matches AWS's stated response order, but it makes a marker meaningful only while the upload it names still exists, which raises the same unknown-cursor policy question already settled the other way for ListObjectVersions at `src/flyology-object_storage-backends-memory.adb:2687-2690`, where an unknown paired cursor is `Invalid_Request`. That policy answer has to be chosen and documented in the contract at `src/flyology-object_storage-backends.ads:2711-2715`.

The regression test belongs with the existing multipart listing case in `tests/src/object_storage_test_cases.adb:3273-3400`. It must create same-key uploads whose initiation seconds differ, then walk the listing with `Maximum => 1` following the returned cursor and assert every upload is returned exactly once, which is the property the spike asserts. The spike is the test. The assertions at `:3318-3328` and `:3379-3389` do not have to change under either option, because their same-key uploads share an initiation second and the page order there already falls through to the upload-ID tie break.

## Severity

A client that pages ListMultipartUploads with the markers the service returned is silently given an incomplete list and is told the list is complete. Callers who page are exactly the ones that care: multi-writer retry loops, orphan-upload sweepers and lifecycle cleanup, which then leave staged parts charged and uncollected. It needs several uploads on one key whose initiation seconds differ and a `max-uploads` bound reached inside that key, both of which ordinary concurrent writers produce. The same builder serves the memory, files and SQLite backends. Deterministic.
