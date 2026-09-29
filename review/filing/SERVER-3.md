Title: HeadObject emits x-amz-version-id: null for an object in a never-versioned bucket while GetObject omits it
Labels: bug
Refs: CLIENT-LOW-1, CLIENT-OBJECTS-1

## Summary

HeadObject writes `x-amz-version-id` unconditionally and substitutes the literal `null` when the object has no version, while GetObject writes the header only when a version exists or the request asked for one, and PutObject omits it for unversioned publication. `docs/compatibility/s3.md:446-450` defines three distinct cases and reserves the `null` spelling for a suspended bucket, so HEAD reports an object in a never-versioned bucket with the spelling that means something else. A client doing HEAD then GET on the same key gets two different answers for the same object.

## Problem

Commit `5fe6e3e`.

HeadObject's `Set_Common_Headers` always writes the header (`src/flyology-object_storage-server-s3_applications.adb:16619-16622`):

```ada
                     Apps.Set_Header
                       (X, "x-amz-version-id",
                        (if US.Length (Info.Version) > 0
                         then US.To_String (Info.Version) else "null"));
```

The GetObject responder writes it conditionally (`src/flyology-object_storage-server-s3_applications.adb:4189-4194`):

```ada
            if US.Length (Info.Version) > 0 then
               Apps.Set_Header
                 (X, "x-amz-version-id", US.To_String (Info.Version));
            elsif Object_Read_Request.Has_Version_ID then
               Apps.Set_Header (X, "x-amz-version-id", "null");
            end if;
```

The crate's own rule has three cases, not two (`docs/compatibility/s3.md:446-450`):

```
Successful PutObject returns its version identity from the same backend
publication snapshot as the body and metadata. The server omits the header for
unversioned publication, emits the exact opaque identity for enabled
memory/files/SQLite publication, and emits `x-amz-version-id: null` for
suspended memory/files/SQLite publication.
```

HeadObject conflates the first case with the third. The pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) gives the two reads no licence to differ: `shapes.HeadObjectOutput.members.VersionId` and `shapes.GetObjectOutput.members.VersionId` are the same binding, `{"shape": "ObjectVersionId", "location": "header", "locationName": "x-amz-version-id"}`, with the same documentation "Version ID of the object." What AWS itself emits on a never-versioned bucket was not checked against a live server, and the finding does not rest on it: the disagreement is between the two arms of this server and its own compatibility document.

No existing test asserts either spelling directly, but one exchange depends on the current one.

That consequence is worth stating before anyone changes the header, because it is load-bearing for the in-repository test lanes. The typed client rejects a 200 whose returned version identity does not equal the one the request selected, and it applies that to the `null` selection like any other. `src/flyology-object_storage-client-low_level.adb:5641-5658`:

```ada
   function Head_Object_Response_Bound
     (Value    : Head_Object_Result;
      Prepared : Prepared_Request) return Boolean
   is
      Requested_Version : constant String := US.To_String
        (Prepared.Requested_Head_Object_Version_ID);
...
   begin
      return
        (Requested_Version'Length = 0
         or else US.To_String (Value.Version_ID) = Requested_Version)
```

with the same predicate for GetObject at `src/flyology-object_storage-client-objects.adb:121-137` and for HeadObject at `:139-155`. The implementation corpus makes exactly that request against a never-versioned bucket (`tests/src/s3_implementation_corpus.adb:1144-1157`):

```ada
            Parameters : Low_Level.Head_Object_Parameters;
         begin
            Parameters.Version_ID := US.To_Unbounded_String ("null");
```

Because this server always supplies a version identity on HEAD, and supplies `null` on GET whenever the request named one, that case passes against this server and is red against the pinned third-party reference servers. Those client predicates are reported separately as {{ISSUE:CLIENT-LOW-1}} and {{ISSUE:CLIENT-OBJECTS-1}}.

## What happens now

Spike: the program below writes one object into a never-versioned bucket and one into a versioning-enabled bucket, then compares the `x-amz-version-id` header of GET and HEAD for the same key. Controls confirm PutObject omits the header for unversioned publication, the two reads agree on a real version identity in the versioned bucket, and an explicit `?versionId=null` selection reports `null` on both reads.

```ada
      Got  : constant String := Run (Signed_Request ("GET", "/plain-bucket/k"));
      Head : constant String := Run (Signed_Request ("HEAD", "/plain-bucket/k"));
      G    : constant String := Header_Value (Got, "x-amz-version-id");
      H    : constant String := Header_Value (Head, "x-amz-version-id");
   begin
      Check (G = H,
             "GET and HEAD report the same x-amz-version-id for the same " &
             "unversioned object");
      Check (Header_Count (Head, "x-amz-version-id") = 0,
             "HEAD of an object in a never-versioned bucket omits " &
             "x-amz-version-id, as GetObject already does");
```

Output, exit status 1:

```
  ok: fixture: CreateBucket /plain-bucket (never versioned)
  ok: fixture: PutObject /plain-bucket/k
  -- PutObject on the never-versioned bucket: x-amz-version-id header count 0 value []
  ok: CONTROL: PutObject omits x-amz-version-id for unversioned publication, as docs/compatibility/s3.md:446-450 states
  ok: fixture: PutBucketVersioning Enabled
  ok: fixture: PutObject /versioned-bucket/k
  -- never-versioned bucket: GET status 200 x-amz-version-id=[] (header count 0)
  -- never-versioned bucket: HEAD status 200 x-amz-version-id=[null] (header count 1)
  ok: CONTROL: both reads of the unversioned object are 200
  FAILED: GET and HEAD report the same x-amz-version-id for the same unversioned object
  FAILED: HEAD of an object in a never-versioned bucket omits x-amz-version-id, as GetObject already does
  -- CONTROL versioned bucket: GET x-amz-version-id=[45dda79046d651db6ab22b5ae137da89aebed4224cb052ff10a9d76ab6530b12]  HEAD x-amz-version-id=[45dda79046d651db6ab22b5ae137da89aebed4224cb052ff10a9d76ab6530b12]
  ok: CONTROL: in a versioned bucket GET and HEAD agree on a real version id
  -- CONTROL explicit ?versionId=null: GET x-amz-version-id=[null]  HEAD x-amz-version-id=[null]
  ok: CONTROL: an explicit versionId=null selection reports null on both reads
BUG REPRODUCED: 2 failed expectation(s)
```

The `null` value does round-trip: a client that feeds HEAD's answer back as `?versionId=null` still gets 200 from both reads, which is why no client behaviour was observed to change.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Shapes checked against the pinned botocore S3 model. Not compared against a third-party server.

## What should happen

HeadObject and GetObject should report the same `x-amz-version-id` for the same object, and the header should be omitted for an object published without versioning, which is the case `docs/compatibility/s3.md:446-450` distinguishes from suspended publication and which PutObject and GetObject already implement.

## Suggested treatment

Make the HEAD arm match the GET arm: replace the unconditional `Set_Header` at `src/flyology-object_storage-server-s3_applications.adb:16619-16622` with the conditional form at `:4189-4194`, so the header is written when the object has a version and written as `null` only when the request asked for a version. No public value, type or parameter changes.

Sequencing matters more than the edit. The typed client predicates quoted above require a returned version identity whenever a version was selected, and this server's unconditional header is what keeps the in-repository corpus green against it; the corpus fails against third-party servers at the same exchange. The narrow fix above preserves the `null` answer for an explicit `?versionId=null` request, so it leaves the lanes green, but any change that also dropped the header in that case would turn them red until {{ISSUE:CLIENT-LOW-1}} and {{ISSUE:CLIENT-OBJECTS-1}} are fixed. Those two should land first, so that a later decision about the explicit-`null` case is not blocked by the client.

The regression test belongs in `tests/src/s3_server_application_corpus.adb`, beside the other HeadObject header assertions: one case asserting that HEAD of an object in a never-versioned bucket carries no `x-amz-version-id`, and one asserting that HEAD and GET of the same key agree. The spike is the test; no existing assertion has to change.

## Severity

The two reads of one object disagree, and HEAD uses the spelling this crate documents for a suspended bucket to describe a bucket that was never versioned, so a client that keys on the header sees a bucket state that does not exist. No client behaviour was observed to change: the value round-trips as `?versionId=null` and both reads still answer 200. It affects every HEAD of every object in a never-versioned bucket, which is the default bucket state. Deterministic.
