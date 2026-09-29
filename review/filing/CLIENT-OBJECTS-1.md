Title: Get_Whole and Head_Object reject a valid 200 or 206 that omits x-amz-version-id after a versionId selector
Labels: bug
Refs: CLIENT-LOW-1, SERVER-3

## Summary

`Get_Object_Response_Bound` and `Head_Object_Response_Bound` require a successful GetObject or HeadObject response to echo the requested `versionId` byte for byte. A bucket that never had versioning enabled answers `?versionId=null` with a `200` (or `206` for a range) that carries no `x-amz-version-id` header at all, which is what MinIO, RustFS and SeaweedFS return and what the pinned botocore model permits, since `VersionId` is optional on both output shapes. The absent header decodes to the empty string, `"" = "null"` is False, and a complete valid read is destroyed: the synchronous `Get_Whole` raises `Low_Level.Invalid_Response`, the composable whole and range reads clear the destination and return `Corrupt_Or_Invalid_Response`, and `Head_Object` returns `Head_Exchange_Failed`. `versionId=null` is the documented way to name an object in a never-versioned bucket, so every read written that way fails against every stock server.

## Problem

Commit `5fe6e3e`.

Both predicates demand an exact echo (`src/flyology-object_storage-client-objects.adb:121-155`):

```ada
   function Get_Object_Response_Bound
     (Result        : Low_Level.Get_Object_Result;
      Version_ID    : US.Unbounded_String;
      Request_Payer : US.Unbounded_String) return Boolean
   is
      Requested_Version : constant String := US.To_String (Version_ID);
      Requested_Payer : constant String := US.To_String (Request_Payer);
      Returned_Payer : constant String :=
        US.To_String (Result.Request_Charged);
   begin
      return
        (Requested_Version'Length = 0
         or else US.To_String (Result.Version_ID) = Requested_Version)
        and then
          (Returned_Payer /= "requester"
           or else Requested_Payer = "requester");
   end Get_Object_Response_Bound;

   function Head_Object_Response_Bound
     (Result        : Low_Level.Head_Object_Result;
      Version_ID    : US.Unbounded_String;
      Request_Payer : US.Unbounded_String) return Boolean
   is
      Requested_Version : constant String := US.To_String (Version_ID);
      Requested_Payer : constant String := US.To_String (Request_Payer);
      Returned_Payer : constant String :=
        US.To_String (Result.Request_Charged);
   begin
      return
        (Requested_Version'Length = 0
         or else US.To_String (Result.Version_ID) = Requested_Version)
        and then
          (Returned_Payer /= "requester"
           or else Requested_Payer = "requester");
   end Head_Object_Response_Bound;
```

Four call sites are reached from public entry points. The synchronous `Get_Whole` raises after the head has already been decoded (`src/flyology-object_storage-client-objects.adb:951-956`):

```ada
         elsif not Get_Object_Response_Bound
           (Head.Result, US.To_Unbounded_String (Version_ID),
            US.To_Unbounded_String (Request_Payer))
         then
            raise Low_Level.Invalid_Response with
              "GetObject response does not match prepared request";
```

The composable whole read discards the received body (`src/flyology-object_storage-client-objects.adb:2429-2434`):

```ada
                 or else not Get_Object_Response_Bound
                   (Head.Result, Item.Requested_Version_ID,
                    Item.Requested_Request_Payer)
               then
                  Clear_Buffer (Item.Destination.all);
                  Item.Final_Result := Invalid_Read_Result;
```

The composable range read does the same (`src/flyology-object_storage-client-objects.adb:2551-2556`):

```ada
                 or else not Get_Object_Response_Bound
                   (Head.Result, Item.Requested_Version_ID,
                    Item.Requested_Request_Payer)
               then
                  Clear_Buffer (Item.Destination.all);
                  Item.Final_Result := Invalid_Range_Read_Result;
```

and the composable HeadObject reports a corrupt response (`src/flyology-object_storage-client-objects.adb:2963-2971`):

```ada
               if Head.Kind = Low_Level.Object_Found
                 and then not Head_Object_Response_Bound
                   (Head.Result, Item.Requested_Version_ID,
                    Item.Requested_Request_Payer)
               then
                  Item.Final_Result :=
                    (Kind        => Head_Exchange_Failed,
                     Failure     => Corrupt_Or_Invalid_Response,
                     HTTP_Result => HTTP_Client.Response_Invalid,
```

An absent header is what makes the comparison fail. The decoders copy the header verbatim and leave the field empty when it is not there (`src/flyology-object_storage-client-low_level.adb:5813` for HeadObject and `:7220` for GetObject, both `Version_ID => H ("x-amz-version-id")`).

The header is optional in the model the repository pins. Reading the pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) with `python3`:

```python
for s in ['GetObjectOutput', 'HeadObjectOutput']:
    sh = model['shapes'][s]
    print(s, 'required:', sh.get('required'))
    v = sh['members']['VersionId']
    print(' ', {k: v[k] for k in ('shape', 'location', 'locationName')})
```

```
GetObjectOutput required: None
  {'shape': 'ObjectVersionId', 'location': 'header', 'locationName': 'x-amz-version-id'}
HeadObjectOutput required: None
  {'shape': 'ObjectVersionId', 'location': 'header', 'locationName': 'x-amz-version-id'}
```

Neither output shape has a `required` list at all, and `VersionId` is an ordinary optional header member on both.

The crate's own low-level specification agrees. `src/flyology-object_storage-client-low_level.ads:1540`, documenting `Head_Object_Result`:

```ada
   --  @field Version_ID Optional selected object-version response value
```

and the public `Get_Whole` prose promises only selection, not an echo (`src/flyology-object_storage-client-objects.ads:3229-3233`):

```ada
   --  Read one complete object and its exact metadata from the same immutable
   --  S3 response. Expected_Entity_Tag binds reconciliation to an opaque ETag;
   --  Version_ID independently selects a provider version when supported.
   --  Maximum bounds retained bytes. A larger or malformed successful body
   --  raises Response_Too_Large or Low_Level.Invalid_Response respectively.
```

A real server omits the header. RustFS 1.0.0-rc.3 from the image pinned at `tests/scripts/test-rustfs.sh:5`, on a bucket that was never version-configured, answered a signed `HEAD /bucket/native-object?versionId=null` carrying `x-amz-request-payer: requester` and `x-amz-checksum-mode: ENABLED` with, verbatim and identically on three consecutive runs apart from `x-request-id`:

```
HTTP/1.1 200 OK
accept-ranges: bytes
content-length: 64
content-type: application/octet-stream
etag: "014842d480b571495a4a0363793f7367"
last-modified: Mon, 07 Sep 2026 01:27:10 GMT
x-request-id: 8c68e1c0-a791-45ec-8778-d9b0729a1312
x-amz-request-id: 8c68e1c0-a791-45ec-8778-d9b0729a1312
date: Mon, 07 Sep 2026 01:27:10 GMT
```

No `x-amz-version-id` and no `x-amz-request-charged`. The same request without the two `x-amz-*` request headers, and the same request without `versionId`, return the same header set, so only the bucket's versioning state decides whether the header appears. Driving the same container through the versioning states gives three shapes for `HEAD ?versionId=null`, none of which is the literal `null`: never configured answers `200` with the header absent, enabled answers `404`, and suspended answers `200` with `x-amz-version-id: 00000000-0000-0000-0000-000000000000`. MinIO `RELEASE.2025-09-07T16-13-09Z` (`tests/scripts/test-minio.sh:5`) and SeaweedFS 4.43 (`tests/scripts/test-seaweedfs.sh:5`) stop the crate's own conformance corpus at that same request, both with the byte-identical line

```
S3 implementation corpus failed: raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE : HeadObject response does not match prepared request
```

so the omission is not RustFS specific.

The one server that does satisfy the demand is the in-repo one, and it satisfies it with a fallback that exists for no other purpose (`src/flyology-object_storage-server-s3_applications.adb:4189-4194`):

```ada
            if US.Length (Info.Version) > 0 then
               Apps.Set_Header
                 (X, "x-amz-version-id", US.To_String (Info.Version));
            elsif Object_Read_Request.Has_Version_ID then
               Apps.Set_Header (X, "x-amz-version-id", "null");
            end if;
```

and unconditionally on the GetObject path (`src/flyology-object_storage-server-s3_applications.adb:16619-16622`):

```ada
                     Apps.Set_Header
                       (X, "x-amz-version-id",
                        (if US.Length (Info.Version) > 0
                         then US.To_String (Info.Version) else "null"));
```

That fallback is reported separately as {{ISSUE:SERVER-3}}. It is why the push and pull-request gate, which runs the conformance corpus against the in-repo memory server, stays green while every third-party server is red.

The same predicate exists one layer down, in `Head_Object_Response_Bound` at `src/flyology-object_storage-client-low_level.adb:5641-5658`, reported as {{ISSUE:CLIENT-LOW-1}}. The conformance corpus reaches that layer first, so both layers have to change together for a real-server run to get past this check.

Two maintained qualification documents state the requirement that no stock server satisfies, so they are part of the defect rather than a defence of it. `docs/qualification/get-object.md:11-12`:

```
nonempty `VersionId` must be a valid text-safe selector, and a successful
response must echo it byte-for-byte. An omitted selector observes whichever
```

and `docs/qualification/head-object.md:10-11`:

```
nonempty `VersionId` must be a valid text-safe selector, and a successful
response must echo it byte-for-byte. An omitted selector observes whichever
```

No test catches this, because two tests assert the defective behaviour. `tests/src/s3_http_socket_corpus.adb:9333` requires the whole read to fail when the header is missing:

```ada
               Require_Invalid_Whole_Get ("scoped-get-version-missing");
               Require_Invalid_Whole_Get ("scoped-get-version-mismatch");
               Require_Invalid_Whole_Get ("scoped-get-version-duplicate");
```

where `Require_Invalid_Whole_Get` (definition `tests/src/s3_http_socket_corpus.adb:9308-9331`) insists on `Whole_Get_Exchange_Failed`, `Corrupt_Or_Invalid_Response`, `Response_Invalid` and an empty destination. `tests/src/s3_http_socket_corpus.adb:9741` does the same for the head operation:

```ada
               Require_Invalid_Head ("scoped-head-version-missing");
               Require_Invalid_Head ("scoped-head-version-mismatch");
               Require_Invalid_Head ("scoped-head-version-control");
```

with `Require_Invalid_Head` defined at `tests/src/s3_http_socket_corpus.adb:9711-9739`. The `-mismatch`, `-control` and `-del` cases in both loops, and the `-duplicate` case in the whole-read loop, are correct rejections and must keep failing; only the `-missing` cases assert the wrong contract. The conformance corpus does address an object this way, at `tests/src/s3_implementation_corpus.adb:1147`:

```ada
            Parameters.Version_ID := US.To_Unbounded_String ("null");
            Parameters.Request_Payer := US.To_Unbounded_String ("requester");
```

but the push and pull-request gate runs that corpus only against the in-repo memory server (`.github/workflows/ci.yml:239-271`), and the scripts that drive it against a real server, `tests/scripts/test-minio.sh`, `test-rustfs.sh` and `test-seaweedfs.sh`, are not part of that gate.

## What happens now

Spike: the program below scripts six exchanges on a loopback origin. Three carry the verbatim RustFS never-versioned header set quoted above, with `content-length: 64` and no `x-amz-version-id`; three are identical except for an added `x-amz-version-id: null`. Against each set it calls `Head_Object`, `Get_Whole` (the `Whole_Get_Outcome` overload) and `Get_Whole` (the bounded-destination overload), all with `Version_ID => "null"`, and asserts that the response is complete, that the 64 body octets survive, and that the decoded `Version_ID` is `""` for the absent-header legs and `"null"` for the controls.

```ada
   Common_Headers : constant String :=
     "accept-ranges: bytes" & CRLF &
     "content-type: application/octet-stream" & CRLF &
     "etag: ""014842d480b571495a4a0363793f7367""" & CRLF &
     "last-modified: Mon, 07 Sep 2026 01:27:10 GMT" & CRLF &
     "x-request-id: 8c68e1c0-a791-45ec-8778-d9b0729a1312" & CRLF &
     "x-amz-request-id: 8c68e1c0-a791-45ec-8778-d9b0729a1312" & CRLF &
     "date: Mon, 07 Sep 2026 01:27:10 GMT" & CRLF;

   Echoed : constant String := "x-amz-version-id: null" & CRLF;
...
      Parameters.Version_ID := US.To_Unbounded_String ("null");
      declare
         Result : constant Objects.Head_Result := Objects.Head_Object
           (HTTP, Origin, Bucket, Key, Parameters, Identity, Timeout => 10.0);
      begin
...
         Check (Result.Kind = Objects.Head_Response_Available,
                Label & ": HeadObject 200 without x-amz-version-id is a " &
                  "complete response");
...
         Result : constant Objects.Whole_Get_Outcome := Objects.Get_Whole
           (HTTP, Origin, Bucket, Key, 256, Identity,
            Version_ID => "null", Timeout => 10.0);
      begin
...
         Check (Result.Kind = Objects.Whole_Object_Read,
                Label & ": GetObject 200 without x-amz-version-id yields " &
                  "the object bytes");
...
         Result : constant Objects.Whole_Get_Result := Objects.Get_Whole
           (HTTP, Origin, Bucket, Key, Destination, Identity,
            Version_ID => "null", Timeout => 10.0);
      begin
...
         Check (Result.Kind = Objects.Whole_Get_Response_Available,
                Label & ": composable whole GetObject keeps the received " &
                  "bytes");
```

Output, exit status 1:

```
  -- scripted loopback origin on 127.0.0.1:60346
  -- responses carry ETag, Last-Modified, Content-Length and the RustFS request-id headers
  -- --- absent x-amz-version-id (MinIO/RustFS/SeaweedFS/AWS shape) ---
  -- no-header HEAD: Head_Object Kind = HEAD_EXCHANGE_FAILED
  -- no-header HEAD: Failure = CORRUPT_OR_INVALID_RESPONSE, HTTP_Result = RESPONSE_INVALID
  FAILED: no-header HEAD: HeadObject 200 without x-amz-version-id is a complete response
  -- no-header GET: raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE : GetObject response does not match prepared request
  FAILED: no-header GET: GetObject 200 without x-amz-version-id yields the object bytes
  -- no-header GET/dest: Get_Whole (destination) Kind = WHOLE_GET_EXCHANGE_FAILED, Failure = CORRUPT_OR_INVALID_RESPONSE, destination length 0
  -- no-header GET/dest: HTTP_Result = RESPONSE_INVALID, phase RECEIVING_RESPONSE_BODY
  FAILED: no-header GET/dest: composable whole GetObject keeps the received bytes
  -- --- control: server echoes x-amz-version-id: null ---
  -- control HEAD: Head_Object Kind = HEAD_RESPONSE_AVAILABLE
  -- control HEAD: status 200, Version_ID = "null", ETag = "014842d480b571495a4a0363793f7367"
  ok: control HEAD: HeadObject 200 without x-amz-version-id is a complete response
  ok: control HEAD: HeadObject outcome is Object_Found
  ok: control HEAD: decoded Version_ID is "null"
  -- control GET: Get_Whole (outcome) Kind = WHOLE_OBJECT_READ, status 200
  ok: control GET: GetObject 200 without x-amz-version-id yields the object bytes
  -- control GET: body length 64, Version_ID = "null"
  ok: control GET: whole body round-trips
  ok: control GET: decoded Version_ID is "null"
  -- control GET/dest: Get_Whole (destination) Kind = WHOLE_GET_RESPONSE_AVAILABLE, Failure = NO_FAILURE, destination length 64
  ok: control GET/dest: composable whole GetObject keeps the received bytes
  ok: control GET/dest: GetObject head outcome is Object_Opened
  ok: control GET/dest: destination holds all 64 body octets
  ok: control GET/dest: decoded Version_ID is "null"
  -- request 1: HEAD /never-versioned/native-object?versionId=null HTTP/1.1
  -- request 2: GET /never-versioned/native-object?versionId=null HTTP/1.1
  -- request 3: GET /never-versioned/native-object?versionId=null HTTP/1.1
  -- request 4: HEAD /never-versioned/native-object?versionId=null HTTP/1.1
  -- request 5: GET /never-versioned/native-object?versionId=null HTTP/1.1
  -- request 6: GET /never-versioned/native-object?versionId=null HTTP/1.1
  ok: the origin served all six scripted exchanges
BUG REPRODUCED: 3 failed expectation(s)
```

The control legs differ from the failing legs by one header and nothing else, so the status, ETag and `Content-Length` checks are not what fires, and with no `x-amz-request-charged` present the payer clause of both predicates is True. The version clause is the sole cause.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Response headers replayed from the pinned RustFS 1.0.0-rc.3 image; shapes checked against the pinned botocore S3 model.

## What should happen

A successful GetObject or HeadObject that omits `x-amz-version-id` must be accepted, because the pinned botocore model marks `VersionId` optional on `GetObjectOutput` and `HeadObjectOutput`, `src/flyology-object_storage-client-low_level.ads:1540` calls the field optional, and MinIO, RustFS and SeaweedFS all omit it for an object in a bucket that never had versioning enabled. A response that carries the header with a different value is still a mismatch and must still be refused.

## Suggested treatment

The smallest fix relaxes both predicates from "the response must echo the requested version" to "the response must not contradict it", rejecting only a present and different value:

```ada
        (Requested_Version'Length = 0
         or else US.Length (Result.Version_ID) = 0
         or else US.To_String (Result.Version_ID) = Requested_Version)
```

applied at `src/flyology-object_storage-client-objects.adb:132-133` and `:150-151`, and identically to the low-level twin reported as {{ISSUE:CLIENT-LOW-1}}. The other socket cases remain rejected: the `-mismatch`, `-control` and `-del` fixtures all serve a present value different from the requested one, and the `-duplicate` fixture is refused by the decoder's singleton-header check (`src/flyology-object_storage-client-low_level.adb:7118-7131`) before the predicate runs. That is the safety property the strict form was reaching for.

That relaxation is not the whole contract question, so this needs a maintainer decision:

- Relaxed predicate only. Accepts the never-versioned shape from all three reference servers. It still rejects the suspended-versioning sentinel `00000000-0000-0000-0000-000000000000` that RustFS returns for `?versionId=null`, so a strict-echo contract remains unsatisfiable across real servers even after the change, and a caller that hits a suspended bucket still gets an exception.
- Relaxed predicate plus a typed outcome for the residual mismatch. Today the mismatch escapes as `Low_Level.Invalid_Response` from the synchronous path before any outcome value exists, so no caller and no oracle mode can classify a per-server deviation. Turning it into a distinct result variant or `Failure_Reason` value widens the public outcome set, which is an interface decision under the "Decision authority" and "Ada interface values" sections of `AGENTS.md`.
- Keep the strict echo and document that these operations do not work against servers that omit the header. This leaves the crate unable to read an object in a never-versioned bucket by `versionId=null` on any stock server.

Whichever is chosen, `docs/qualification/get-object.md:11-12` and `docs/qualification/head-object.md:10-11` must be reworded, because "a successful response must echo it byte-for-byte" is the requirement being removed. The in-repo server's `x-amz-version-id: null` fallback, {{ISSUE:SERVER-3}}, is why the repository's own corpus never observed the absent header, and its own disposition should be decided once the client no longer requires the header.

The regression tests belong in `tests/src/s3_http_socket_corpus.adb`: invert `Require_Invalid_Whole_Get ("scoped-get-version-missing")` at `:9333` and `Require_Invalid_Head ("scoped-head-version-missing")` at `:9741` into success assertions that require `Whole_Get_Response_Available` and `Head_Response_Available` with `Version_ID = ""` and the body intact, leaving the other variants in both loops asserting rejection. `tests/src/s3_implementation_corpus.adb` already fails against real servers at this check, so a fix must make `tests/scripts/test-minio.sh` pass its HeadObject case rather than stop there. The spike is the test.

## Severity

Every whole read, range read and head of an object addressed by `versionId=null` fails against every server that answers the AWS way for a never-versioned bucket, which is the documented way to name such an object. The synchronous `Get_Whole` raises `Low_Level.Invalid_Response` and the composable forms discard a fully received body and report `Corrupt_Or_Invalid_Response`, so a correct response is reported to the caller as a corrupt one. The crate's own conformance corpus fails against the pinned RustFS, MinIO and SeaweedFS images at this class of check, and the only server it passes against is the in-repo one, whose unconditional `x-amz-version-id` fallback supplies the header the client demands. The predicate is a pure function of two strings, so no timing, load or container state is involved. Deterministic.
