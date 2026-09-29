Title: Reading a key hidden by a delete marker is a bare 404, and reading the marker's own version is 404 instead of 405
Labels: bug
Refs: none

## Summary

In a versioned bucket the memory backend folds "the selected generation is a delete marker" onto the same `Natural` 0 it uses for "no such generation", so every read of a marker returns `Not_Found` and the server answers a bare 404 `NoSuchKey`. Two behaviours the pinned model states verbatim are lost: a read of a key whose current version is a delete marker does not carry `x-amz-delete-marker: true`, and a read of the marker's own version returns 404 instead of 405 with `Last-Modified`. A versioning-aware client therefore cannot tell "this key was deleted" from "this key never existed", and every key in a versioned bucket enters that state on the next read after any DELETE.

## Problem

Commit `5fe6e3e`.

The selector discards the distinction before any read can see it (`src/flyology-object_storage-backends-memory.adb:318-329`):

```ada
      function Selected_Object_Index
        (Bucket : String; Key : String; Selector : Version_Selector)
         return Natural
      is
         Selected : constant Natural :=
           Selected_Generation_Index (Bucket, Key, Selector);
      begin
         return
           (if Selected /= 0
              and then not Objects (Selected).Is_Delete_Marker
            then Selected else 0);
      end Selected_Object_Index;
```

The GetObject arm forwards the resulting status unchanged (`src/flyology-object_storage-server-s3_applications.adb:17259-17265`):

```ada
                  elsif not Apps.Wire_Response_Started (X) then
                     if Result = Invalid_Range and then Info.Size >= 0 then
                        Apps.Set_Header
                          (X, "Content-Range",
                           "bytes */" & Decimal (Info.Size));
                     end if;
                     Send_Backend_Error (X, Result, False, Target_Text);
```

and so does the HeadObject arm (`:16954-16955`). `Send_Backend_Error` has no marker-aware branch (`:1927-1934`):

```ada
         when Not_Found =>
            Send_Error
              (X, 404,
               (if Is_Bucket then "NoSuchBucket" else "NoSuchKey"),
               (if Is_Bucket
                then "The specified bucket does not exist"
                else "The specified key does not exist"),
               Resource);
```

Nothing in the server can recover the fact, because nothing in the backend contract carries it. The public `Status` type has no marker outcome (`src/flyology-object_storage.ads:39-62`):

```ada
   type Status is
     (Success,
      Not_Found,
      Bucket_Not_Found,
      Tag_Set_Not_Found,
...
      Not_Implemented,
      Backend_Unavailable);
```

`Object_Information` has no marker field either (`src/flyology-object_storage.ads:554-562`):

```ada
   type Object_Information is record
      Size          : Byte_Count := 0;
      Modified      : Unix_Time := 0;
      Entity_Tag    : Ada.Strings.Unbounded.Unbounded_String;
      Content_Type  : Ada.Strings.Unbounded.Unbounded_String;
      Version       : Ada.Strings.Unbounded.Unbounded_String;
      Checksum      : Checksum_Information;
      Metadata      : Object_Metadata;
   end record;
```

so the read contracts have no channel for it (`src/flyology-object_storage-backends.ads:2049-2069`):

```ada
   --  Return one selected immutable metadata snapshot. Conditions are
   --  evaluated against the same snapshot and retained on conditional failure.
...
   procedure Head_Object
     (Item   : in out Backend;
      Bucket : String;
      Key    : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Info   : out Object_Information;
      Result : out Status;
      Conditions : Read_Conditions := Default_Read_Conditions;
      Selector : Version_Selector := Current_Version_Selector) is abstract;
```

`Get_Object_Attributes` (`:2106-2116`) reports through the same `Result : out Status` with no marker channel either, and `Get_Object` reports through the same type. The information does exist in the store: `Listed_Version.Is_Delete_Marker` (`src/flyology-object_storage-backends.ads:98-104`) is populated at `src/flyology-object_storage-backends-memory.adb:2671` and comes back correctly from `List_Object_Versions`, so this is a gap in the read interface rather than a memory-backend slip, and the files and SQLite backends read through the same contract.

The pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) states both behaviours in `shapes.GetObjectOutput.members.DeleteMarker`, which binds `"location": "header"`, `"locationName": "x-amz-delete-marker"`. Its documentation, with HTML stripped:

```
Indicates whether the object retrieved was (true) or was not (false) a Delete
Marker. If false, this response header does not appear in the response. If the
current version of the object is a delete marker, Amazon S3 behaves as if the
object was deleted and includes x-amz-delete-marker: true in the response. If
the specified version in the request is a delete marker, the response returns
a 405 Method Not Allowed error and the Last-Modified: timestamp response
header.
```

`shapes.HeadObjectOutput.members.DeleteMarker` carries the same header binding.

MinIO `RELEASE.2025-09-07T16-13-09Z`, from the image pinned by `tests/scripts/test-minio.sh` (`quay.io/minio/minio@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e`), started by hand as a single container on `127.0.0.1:19000` and driven with the `aws` CLI, answers exactly that way: HEAD of a key whose current generation is a delete marker returns 404 with `x-amz-delete-marker: true` and `x-amz-version-id: <marker>`, and HEAD and GET of the exact marker version return 405.

This is not a documented limitation. `docs/compatibility/s3.md:538-541` documents marker publication and removal with no read-side caveat:

```
Omitted, `null`, and opaque VersionId members map to current, null, and exact
backend selectors. Memory, files, and SQLite publish current delete markers, remove
selected data or markers, echo requested version identities, and return
created/removed marker identities.
```

and the exclusion lists for HeadObject (`docs/compatibility/s3.md:59`) and GetObject (`:858-859`, "GetObject part selection, non-null versions, and encrypted SSE-C objects remain explicit cross-cutting exclusions") do not mention delete-marker reads.

No existing test asserts the right behaviour and none asserts the wrong one over the wire: `tests/src/s3_server_application_corpus.adb:18202-18207` covers only the DeleteObject response headers, and `:17750-17755` only that an exact-version delete carries no marker header. At the backend interface the current behaviour is pinned, `tests/src/versioned_object_conformance.adb:859-861`:

```ada
      Store.Head_Object
        (Bucket, "alpha", null, Ada.Real_Time.Time_Last, Info, Result);
      Require (Result = Not_Found, "suspended marker did not hide current");
```

with the same shape at `:447-450`, so a fix must update those expectations.

## What happens now

Spike: the first program below creates a bucket, enables versioning, writes `k` and a second live key, deletes `k` and captures the marker version id from `x-amz-delete-marker`/`x-amz-version-id`, then asserts the two documented behaviours on GET and HEAD of the current version and of the marker's own version. Controls confirm the DELETE itself reports the marker and a version id, a live key still reads 200, and a key that never existed reads 404 with no marker header.

```ada
      Response : constant String :=
        Run (Signed_Request ("GET", "/marker-bucket/k"));
   begin
      Check (Status_Code (Response) = 404,
             "GET of a current delete marker is 404");
      Check (Header_Value (Response, "x-amz-delete-marker") = "true",
             "GET of a current delete marker carries " &
             "x-amz-delete-marker: true");
...
      Response : constant String :=
        Run (Signed_Request
               ("GET", "/marker-bucket/k",
                Query =>
                  (1 => SigV4.Pair
                     ("versionId", Marker_Version (1 .. Marker_Last)))));
   begin
      Check (Status_Code (Response) = 405,
             "GET of an exact delete-marker version is 405 " &
             "MethodNotAllowed");
```

Output, exit status 1:

```
  ok: fixture: PutBucketVersioning Enabled
  ok: fixture: PutObject /marker-bucket/k
  -- CONTROL DELETE /marker-bucket/k: status 204  x-amz-delete-marker=[true]  x-amz-version-id=[f37f4dffd982f843741984a21d253e64aa73d8a80500283bd999f2928f6f4eed]  Last-Modified=[]
  ok: CONTROL: DELETE reports x-amz-delete-marker: true
  -- GET a key whose current version is a delete marker: status 404  x-amz-delete-marker=[]  x-amz-version-id=[]  Last-Modified=[]
  --    body <?xml version="1.0" encoding="UTF-8"?><Error><Code>NoSuchKey</Code><Message>The specified key does not exist</Message><Resource>/marker-bucket/k</Resource></Error>
  ok: GET of a current delete marker is 404
  FAILED: GET of a current delete marker carries x-amz-delete-marker: true
  -- HEAD a key whose current version is a delete marker: status 404  x-amz-delete-marker=[]  x-amz-version-id=[]  Last-Modified=[]
  ok: HEAD of a current delete marker is 404
  FAILED: HEAD of a current delete marker carries x-amz-delete-marker: true
  -- GET ?versionId=<the marker itself>: status 404  x-amz-delete-marker=[]  x-amz-version-id=[]  Last-Modified=[]
  FAILED: GET of an exact delete-marker version is 405 MethodNotAllowed
  FAILED: GET of an exact delete-marker version carries x-amz-delete-marker: true
  FAILED: GET of an exact delete-marker version carries Last-Modified
  -- HEAD ?versionId=<the marker itself>: status 404  x-amz-delete-marker=[]  x-amz-version-id=[]  Last-Modified=[]
  FAILED: HEAD of an exact delete-marker version is 405 MethodNotAllowed
  FAILED: HEAD of an exact delete-marker version carries x-amz-delete-marker: true
  -- CONTROL GET of a live key: status 200  x-amz-delete-marker=[]  x-amz-version-id=[77d55163c888e8ba05bf5972434e4870281279b1f5546f8145f9158af0f53a58]  Last-Modified=[Mon, 07 Sep 2026 06:11:21 GMT]
  ok: CONTROL: GET of a live key still reads 200
  -- CONTROL GET of a key that never existed: status 404  x-amz-delete-marker=[]  x-amz-version-id=[]  Last-Modified=[]
  ok: CONTROL: GET of an absent key is 404
  ok: CONTROL: GET of an absent key carries no delete-marker header
BUG REPRODUCED: 7 failed expectation(s)
```

The 404 for the marker-hidden key and the 404 for the key that never existed are byte-identical.

A second program shows why the fix cannot be made in the server alone. It drives a private `Backends.Memory.Store` directly, publishes a marker, and asks only that the read surface distinguish the two cases in any observable way at all, on the status, the version, or the timestamp:

```ada
   Store.Head_Object
     (Bucket, "never-existed", null, Deadline, Absent_Info, Absent_Status);
   Store.Head_Object (Bucket, Key, null, Deadline, Marker_Info, Marker_Status);
   Check (Marker_Status /= Absent_Status
            or else US.To_String (Marker_Info.Version) /=
              US.To_String (Absent_Info.Version)
            or else Marker_Info.Modified /= Absent_Info.Modified,
          "current HEAD distinguishes a delete marker from an absent key");
```

Output, exit status 1:

```
  ok: setup: object published
  -- setup: live version 41b6ea08994cc7f6cbd3be48b86d242d2028e178ac6b576a668acdc4fe92a602
  ok: setup: simple delete published a delete marker
  -- setup: marker version 9386a25901aec99598857ac6f2616db093bd4fc09678d8ca98ce1c22bef3b6f3
  -- control: listed version '9386a25901aec99598857ac6f2616db093bd4fc09678d8ca98ce1c22bef3b6f3' is_latest TRUE is_delete_marker TRUE
  ok: control: the listing surface reports the marker generation
  -- head absent key          : NOT_FOUND size 0 modified 0 version ''
  -- head marker-hidden key   : NOT_FOUND size 0 modified 0 version ''
  FAILED: current HEAD distinguishes a delete marker from an absent key
  -- head unknown version id  : NOT_FOUND size 0 modified 0 version ''
  -- head exact marker version: NOT_FOUND size 0 modified 0 version ''
  FAILED: exact HEAD distinguishes a delete marker from an unknown version
  FAILED: exact HEAD of a marker carries the marker's Last-Modified time
  -- head exact live version  : SUCCESS size 7 modified 1788761516 version '41b6ea08994cc7f6cbd3be48b86d242d2028e178ac6b576a668acdc4fe92a602'
  ok: control: exact HEAD of the retained live generation succeeds
  -- attributes exact marker  : NOT_FOUND
  FAILED: GetObjectAttributes on a marker generation is not plain Not_Found
BUG REPRODUCED: 4 failed expectation(s)
```

The listing control passes, so the store holds the fact and only the read contracts cannot carry it. `Get_Object_Attributes` has the same hole, and every other read in that backend resolves through the same selector function, which has sixteen call sites in `src/flyology-object_storage-backends-memory.adb`.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Compared against MinIO `RELEASE.2025-09-07T16-13-09Z` from the pinned image. Shapes checked against the pinned botocore S3 model.

## What should happen

A read of a key whose current version is a delete marker should still be a 404, but carry `x-amz-delete-marker: true`, and a read that names the marker's own version should answer 405 `MethodNotAllowed` with `Last-Modified`, as the pinned model's `GetObjectOutput.DeleteMarker` documentation states and as the pinned MinIO release does.

## Suggested treatment

The backend must be able to say that the generation it selected is a marker, so this needs a maintainer decision. The choice is a visible addition to `src/flyology-object_storage.ads`, and under the "Ada interface values" and "Decision authority" sections of `AGENTS.md` it is not the implementer's to make:

- Add a `Status` literal, for example `Delete_Marker_Selected`, to the visible enumeration at `src/flyology-object_storage.ads:39-62`, returned with an `Object_Information` that still carries `Modified` and `Version`. Every `case` on `Status` in the crate and in any out-of-tree backend has to gain an arm, which is the wider break, but the outcome stays a single value that `Send_Backend_Error` can map.
- Add an `Is_Delete_Marker` field to `Object_Information` at `:554-562` and keep returning `Not_Found` with a populated snapshot. Existing `case` statements keep compiling, but a caller that ignores the new field sees no change, and the read contracts (`src/flyology-object_storage-backends.ads:2049-2069` for `Head_Object`, `:2106-2116` for `Get_Object_Attributes`) have to state that `Info` is meaningful on that particular `Not_Found`.

Either way the change spans the interface: `Selected_Object_Index` (`src/flyology-object_storage-backends-memory.adb:318-329`) must stop collapsing the two cases, the reads that turn its 0 into `Not_Found` must propagate the new outcome (`Head` at `src/flyology-object_storage-backends-memory.adb:1736-1746`, `Fetch` at `:1562-1565`, and `Attributes` beside them), the files and SQLite backends must implement it identically, the `Head_Object`, `Get_Object` and `Get_Object_Attributes` contracts must document it, and `Send_Backend_Error` (`src/flyology-object_storage-server-s3_applications.adb:1927-1934`) plus the two read arms must emit `x-amz-delete-marker: true` on the current-version 404 and 405 with `Last-Modified` on the exact-version read.

The wire regression test belongs in `tests/src/s3_server_application_corpus.adb`, beside the DeleteObject marker assertions at `:18202-18207`, and the backend-level one in `tests/src/versioned_object_conformance.adb`, whose assertions at `:859-861` and `:447-450` require a marker read to be plain `Not_Found` today and must change with the outcome. Both programs above are the tests.

## Severity

Every key in a versioned bucket enters this state on the next read after any DELETE, so it is not an unusual input: the client that just deleted a key, or any other client, gets a response indistinguishable from "this key never existed". Replication, backup and sync tooling keys on `x-amz-delete-marker` to reproduce deletions, and a tool that walks ListObjectVersions and reads each generation cannot tell that the version it asked for is a marker. No data is lost and no wrong body is returned; the object's earlier generations remain readable by exact version. Deterministic.
