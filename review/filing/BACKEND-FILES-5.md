Title: Multipart operations with a valid upload ID but the wrong key answer Backend_Unavailable instead of Not_Found
Labels: bug
Refs: none

## Summary

The files backend locates an active multipart upload by bucket and upload ID alone, and discovers a key mismatch only when `Read_Header` validates the manifest's stored key, which it signals with `Data_Error`. Every multipart entry point's blanket `when others` handler turns that into `Backend_Unavailable`, which the S3 layer renders as 503 SlowDown. `UploadPart`, `ListParts`, `CompleteMultipartUpload` and `AbortMultipartUpload` sent with the wrong key therefore return a retryable server-overload status where the backend contract and the reference memory backend say `Not_Found`, which the same S3 layer renders as 404 NoSuchUpload. A client that mangles a key on a retry spins through its retry budget instead of being told the upload does not exist, and an `AbortMultipartUpload` with the wrong key can neither retire the upload nor say why.

## Problem

Commit `5fe6e3e`.

The contract is explicit on both points. Upload identifiers are scoped to the key (`src/flyology-object_storage-backends.ads:2657-2659`):

```ada
   --  Start one upload. Upload identifiers are backend-generated, opaque,
   --  nonempty, and scoped to the exact bucket and key. Backends that do not
   --  override multipart primitives inherit a Not_Implemented result.
```

and a missing upload has one status (`src/flyology-object_storage-backends.ads:2771-2773`):

```ada
   --  Retire an upload and every staged part atomically with Conditions. A
   --  missing upload is Not_Found; a mismatched initiation time is
   --  Precondition_Failed and leaves the upload and all parts unchanged.
```

`Read_Manifest` looks the upload up without the key and only then checks it (`src/flyology-object_storage-backends-files.adb:3424-3431`):

```ada
   begin
      Inspect_Manifest_Path (Item, Bucket, Upload_ID, Exists);
      if not Exists then
         raise Ada.IO_Exceptions.Name_Error;
      end if;
      Validate_Upload_Contents (Item, Bucket, Upload_ID);
      SIO.Open (File, SIO.In_File, Manifest_Path (Item, Bucket, Upload_ID));
      Read_Header (File, Key, Info, Body_At);
```

`Read_Header` reports the mismatch as a corrupt-data condition (`src/flyology-object_storage-backends-files.adb:3085-3087`):

```ada
      if US.To_String (Key) /= Expected then
         raise Ada.IO_Exceptions.Data_Error;
      end if;
```

The presence test that runs before it does not consider the key. `Put_Multipart_Part` (`src/flyology-object_storage-backends-files.adb:10830-10837`):

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

The same shape appears in `List_Multipart_Parts` (`:11115-11122`), `Complete_Multipart_Upload` (`:11611-11618`) and `Abort_Multipart_Upload` (`:11980-11987`).

`Data_Error` is not special-cased in any of the four handlers. `Put_Multipart_Part` (`src/flyology-object_storage-backends-files.adb:11061-11078`):

```ada
      when others =>
         if Opened then
            SIO.Close (File);
         end if;
         if Locked then
            Item.Publication.Release;
         end if;
         if not Published and then US.Length (Temp) > 0
           and then Ada.Directories.Exists (US.To_String (Temp))
         then
            Ada.Directories.Delete_File (US.To_String (Temp));
         end if;
         Info := Empty_Info;
         if In_Callback then
            raise;
         else
            Result := Backend_Unavailable;
         end if;
```

The upload identifier does not carry the key in a way that would prevent the case. It is a digest, and the upload directory is named by a digest of the identifier alone (`src/flyology-object_storage-backends-files.adb:10690-10694`):

```ada
      Upload_ID := US.To_Unbounded_String
        (GNAT.SHA256.Digest
           (Bucket & Character'Val (0) & Key & Character'Val (0) &
            Long_Long_Integer'Image (Number) &
            Ada.Calendar.Time'Image (Ada.Calendar.Clock)));
```

so a manifest created for key `alpha` is found under a request for key `beta`.

The reference backend matches all three parts of the identity together (`src/flyology-object_storage-backends-memory.adb:331-348`):

```ada
      function Upload_Index
        (Bucket : String; Key : String; Upload_ID : String) return Natural
      is
      begin
         for Index in Uploads'Range loop
            if Uploads (Index).Used
              and then Ada.Strings.Unbounded.To_String
                (Uploads (Index).Bucket) = Bucket
              and then Ada.Strings.Unbounded.To_String
                (Uploads (Index).Key) = Key
              and then Ada.Strings.Unbounded.To_String
                (Uploads (Index).ID) = Upload_ID
            then
               return Index;
            end if;
         end loop;
         return 0;
      end Upload_Index;
```

The two statuses reach the client as very different answers. `Not_Found` becomes a definitive 404 (`src/flyology-object_storage-server-s3_applications.adb:12638-12643`):

```ada
                  if Result = Not_Found then
                     Send_Error
                       (X, 404, "NoSuchUpload",
                        "The specified multipart upload does not exist",
                        Target_Text);
                     return;
```

while `Backend_Unavailable` becomes the retryable one (`src/flyology-object_storage-server-s3_applications.adb:1951-1954`):

```ada
         when Capacity_Exceeded | Backend_Unavailable =>
            Send_Error
              (X, 503, "SlowDown",
               "Please reduce your request rate", Resource);
```

Nothing tests either direction. `tests/src/multipart_part_conformance.adb` is 180 lines and contains no occurrence of `Not_Found` and no mismatched-key call. No existing assertion states the wrong behaviour, so none has to change.

## What happens now

Spike: the program below runs one sequence against the memory backend as a control and then against a files store. It creates an upload for key `alpha`, uploads a part with the correct key as a sanity control, and then drives `UploadPart`, `ListParts`, `CompleteMultipartUpload` and `AbortMultipartUpload` for key `beta` with that same upload identifier, asserting `Not_Found` each time.

```ada
         Store.Put_Multipart_Part
           (Bucket, Wrong_Key, US.To_String (Upload_ID), 1, Payload,
            null, Forever, Info, Result);
         Check (Result = Storage.Not_Found,
                Label & " UploadPart with a mismatched key is Not_Found");
...
      Store.Abort_Multipart_Upload
        (Bucket, Wrong_Key, US.To_String (Upload_ID),
         Backends.No_Abort_Multipart_Conditions, null, Forever, Result);
      Check (Result = Storage.Not_Found,
             Label & " Abort with a mismatched key is Not_Found");
```

Output, exit status 1:

```
  ok: memory (control) CreateBucket succeeds
  ok: memory (control) CreateMultipartUpload succeeds
  -- memory (control) upload id length 64
  -- memory (control) UploadPart(correct key) -> SUCCESS
  ok: memory (control) UploadPart with the correct key succeeds
  -- memory (control) UploadPart(wrong key) -> NOT_FOUND
  ok: memory (control) UploadPart with a mismatched key is Not_Found
  -- memory (control) ListParts(wrong key) -> NOT_FOUND
  ok: memory (control) ListParts with a mismatched key is Not_Found
  -- memory (control) CompleteMultipartUpload(wrong key) -> NOT_FOUND
  ok: memory (control) Complete with a mismatched key is Not_Found
  -- memory (control) AbortMultipartUpload(wrong key) -> NOT_FOUND
  ok: memory (control) Abort with a mismatched key is Not_Found
  ok: files  (subject) CreateBucket succeeds
  ok: files  (subject) CreateMultipartUpload succeeds
  -- files  (subject) upload id length 64
  -- files  (subject) UploadPart(correct key) -> SUCCESS
  ok: files  (subject) UploadPart with the correct key succeeds
  -- files  (subject) UploadPart(wrong key) -> BACKEND_UNAVAILABLE
  FAILED: files  (subject) UploadPart with a mismatched key is Not_Found
  -- files  (subject) ListParts(wrong key) -> BACKEND_UNAVAILABLE
  FAILED: files  (subject) ListParts with a mismatched key is Not_Found
  -- files  (subject) CompleteMultipartUpload(wrong key) -> BACKEND_UNAVAILABLE
  FAILED: files  (subject) Complete with a mismatched key is Not_Found
  -- files  (subject) AbortMultipartUpload(wrong key) -> BACKEND_UNAVAILABLE
  FAILED: files  (subject) Abort with a mismatched key is Not_Found
BUG REPRODUCED: 4 failed expectation(s)
```

All four entry points differ from the control, and the correct-key part upload in the same run succeeds, so the upload itself is sound.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire.

## What should happen

A multipart operation whose (bucket, key, upload ID) triple does not name an active upload is `Not_Found`, as `src/flyology-object_storage-backends.ads:2657-2659` and `:2771-2773` require and as the memory backend answers, so the S3 boundary returns 404 NoSuchUpload rather than 503 SlowDown.

## Suggested treatment

Compare the manifest's stored key against the requested key and report the mismatch as absence rather than as a failure. The narrowest change is in `Read_Manifest`: read the header with `Read_Header_Any` instead of `Read_Header` at `src/flyology-object_storage-backends-files.adb:3431`, compare the returned key, and signal a mismatch with the same condition that `Inspect_Manifest_Path` uses for a missing manifest at `:3426-3428`, so it reaches the existing `Not_Found` paths. Alternatively, extend `Manifest_Exists` at `:10830`, `:11115`, `:11611` and `:11980` to take the key and answer False on a mismatch, which keeps the four entry points as they are. Either way `Read_Manifest`'s remaining `Data_Error` cases, the size, entity-tag and checksum checks at `:3433-3438`, must keep reporting a corrupt manifest as a failure rather than as absence. No public constant, variant, parameter or status changes.

The regression test belongs with the shared backend conformance helpers in `tests/src/flyology-object_storage-backends-testing.adb`, as a procedure over `Backends.Backend'Class` called from both the memory and the files fixture in `tests/src/object_storage_test_cases.adb`, so the behaviour is gated for every backend by one assertion; `tests/src/multipart_part_conformance.adb` is the file that covers multipart today and has no mismatched-key case at all. The spike is the test: it asserts `Not_Found` at each of the four entry points and runs the identical sequence against both backends.

## Severity

A client that sends a multipart operation with the wrong key gets 503 SlowDown, which aws-cli and boto3 retry with exponential backoff, so a permanent error is turned into a long retry loop that ends in an unrelated-looking timeout, and an `AbortMultipartUpload` with the wrong key never retires the upload and never explains why, leaving staged parts behind. It needs a client mistake to trigger, such as a mangled key on a retry, so it is an edge case rather than something a correct client meets. It affects all four multipart entry points and reproduces every time. Deterministic. Files backend only.
