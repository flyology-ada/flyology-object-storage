Title: Execute_Head_Object rejects a valid 200 that omits x-amz-version-id after a versionId selector
Labels: bug
Refs: CLIENT-OBJECTS-1, SERVER-3

## Summary

`Head_Object_Response_Bound` requires a successful HeadObject response to echo the requested `versionId` byte for byte. An absent `x-amz-version-id` header decodes to the empty string, so `"" = "null"` is False and `Execute_Head_Object` raises `Invalid_Response` on an otherwise complete 200. A bucket that never had versioning enabled is exactly the state that answers `?versionId=null` without the header, and `versionId=null` is the documented way to name an object in such a bucket. This is the check that stops the repository's own conformance corpus against the pinned RustFS, MinIO and SeaweedFS images: the only server the corpus gets past is the in-repo one, which manufactures the header.

## Problem

Commit `5fe6e3e`.

The predicate demands an exact echo (`src/flyology-object_storage-client-low_level.adb:5641-5658`):

```ada
   function Head_Object_Response_Bound
     (Value    : Head_Object_Result;
      Prepared : Prepared_Request) return Boolean
   is
      Requested_Version : constant String := US.To_String
        (Prepared.Requested_Head_Object_Version_ID);
      Requested_Payer : constant String := US.To_String
        (Prepared.Requested_Head_Object_Request_Payer);
      Returned_Payer : constant String := US.To_String
        (Value.Request_Charged);
   begin
      return
        (Requested_Version'Length = 0
         or else US.To_String (Value.Version_ID) = Requested_Version)
        and then
          (Returned_Payer /= "requester"
           or else Requested_Payer = "requester");
   end Head_Object_Response_Bound;
```

The decoded field is the header copied verbatim, which is the empty string when the header is absent (`src/flyology-object_storage-client-low_level.adb:5813`):

```ada
               Version_ID => H ("x-amz-version-id"),
```

`Prepare_Head_Object` retains the caller's selector unconditionally and validates nothing about it (`src/flyology-object_storage-client-low_level.adb:5153-5155`):

```ada
         Result.Requested_Head_Object_Version_ID := Parameters.Version_ID;
         Result.Requested_Head_Object_Request_Payer :=
           Parameters.Request_Payer;
```

and the executor turns a False predicate into an exception, so the decoded metadata never reaches the caller and no `Head_Object_Outcome` value is produced (`src/flyology-object_storage-client-low_level.adb:5880-5886`):

```ada
            if Result.Kind = Object_Found
              and then not Head_Object_Response_Bound
                (Result.Result, Prepared)
            then
               raise Invalid_Response with
                 "HeadObject response does not match prepared request";
            end if;
```

The exception is specified for a response that breaks its modeled contract (`src/flyology-object_storage-client-low_level.ads:300-301`):

```ada
   --  Raised when a received S3 response violates its modeled contract.
   Invalid_Response : exception;
```

An omitted header breaks no modeled contract. Reading the pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) with `python3`:

```python
sh = model['shapes']['HeadObjectOutput']
print('HeadObjectOutput required:', sh.get('required'))
v = sh['members']['VersionId']
print(' ', {k: v[k] for k in ('shape', 'location', 'locationName')})
```

```
HeadObjectOutput required: None
  {'shape': 'ObjectVersionId', 'location': 'header', 'locationName': 'x-amz-version-id'}
```

The crate's own specification calls the field optional too (`src/flyology-object_storage-client-low_level.ads:1540`):

```ada
   --  @field Version_ID Optional selected object-version response value
```

Real servers omit it. RustFS 1.0.0-rc.3, from the image pinned at `tests/scripts/test-rustfs.sh:5`, answered a signed `HEAD /bucket/native-object?versionId=null` carrying `x-amz-request-payer: requester` and `x-amz-checksum-mode: ENABLED`, against a bucket that was never version-configured, with this response, identical on three consecutive runs apart from `x-request-id`:

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

No `x-amz-version-id` and no `x-amz-request-charged`. The same request without the two `x-amz-*` request headers, and the same request without `versionId`, return the same header set, so only the bucket's versioning state decides whether the header appears. The same container driven through the versioning states gives three shapes for `HEAD ?versionId=null`, none of them the literal `null`: never configured answers `200` with the header absent, enabled answers `404`, and suspended answers `200` with `x-amz-version-id: 00000000-0000-0000-0000-000000000000`.

The repository's own conformance corpus sends exactly that request and asserts success (`tests/src/s3_implementation_corpus.adb:1144-1159`):

```ada
         declare
            Parameters : Low_Level.Head_Object_Parameters;
         begin
            Parameters.Version_ID := US.To_Unbounded_String ("null");
            Parameters.Request_Payer := US.To_Unbounded_String ("requester");
            Parameters.Checksum_Mode := True;
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Head_Object
                   (Origin, Low_Level.Path_Style, Bucket, Key, Parameters,
                    Identity, "us-east-1", Timestamp);
               Outcome : constant Low_Level.Head_Object_Outcome :=
                 Low_Level.Execute_Head_Object
                   (HTTP, Prepared, Timeout => 30.0);
            begin
               if Outcome.Kind /= Low_Level.Object_Found
```

and it does not get there. Running that corpus through `tests/scripts/test-rustfs.sh`, `tests/scripts/test-minio.sh` and `tests/scripts/test-seaweedfs.sh` at this commit stops at this HeadObject case on all three pinned images, with the byte-identical line

```
S3 implementation corpus failed: raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE : HeadObject response does not match prepared request
```

so the omission is not RustFS specific. The RustFS run was repeated seven times, on fresh and reused containers, on four different host ports and through a logging proxy, with the same failure at the same exchange every time. The response that check refuses satisfies every assertion the corpus itself makes about it, including the composite checksum values at `tests/src/s3_implementation_corpus.adb:1161-1166`.

The one server that satisfies the demand does so with a fallback that exists for no other purpose (`src/flyology-object_storage-server-s3_applications.adb:4189-4194`):

```ada
            if US.Length (Info.Version) > 0 then
               Apps.Set_Header
                 (X, "x-amz-version-id", US.To_String (Info.Version));
            elsif Object_Read_Request.Has_Version_ID then
               Apps.Set_Header (X, "x-amz-version-id", "null");
            end if;
```

and, in the HeadObject branch that starts at `src/flyology-object_storage-server-s3_applications.adb:16518`, unconditionally (`src/flyology-object_storage-server-s3_applications.adb:16619-16622`):

```ada
                     Apps.Set_Header
                       (X, "x-amz-version-id",
                        (if US.Length (Info.Version) > 0
                         then US.To_String (Info.Version) else "null"));
```

That server behaviour is reported separately as {{ISSUE:SERVER-3}}. It is why the push and pull-request gate stays green: `s3-smoke` runs the corpus against the in-repo memory server (`.github/workflows/ci.yml:240-272`), while the reference servers run only on a schedule (`.github/workflows/ci.yml:283-292`).

The compatibility document describes the opposite direction as correct, so the client demand is not a documented limitation (`docs/compatibility/s3.md:446-450`):

```
Successful PutObject returns its version identity from the same backend
publication snapshot as the body and metadata. The server omits the header for
unversioned publication, emits the exact opaque identity for enabled
memory/files/SQLite publication, and emits `x-amz-version-id: null` for
suspended memory/files/SQLite publication.
```

The only statement of the demand is a private-part comment (`src/flyology-object_storage-client-low_level.ads:10533-10535`):

```ada
      --  Derived HeadObject response binding: an explicit version selector
      --  must be echoed by a successful response, and a charged response is
      --  valid only when the exact request admitted requester pays.
```

No test at this layer catches it, and none has to be inverted here. The check arrived with commit `2703ed6` (2026-08-30) and was qualified only against the in-process socket fake, whose HeadObject version fixtures all emit the header: `tests/src/s3_http_socket_corpus.adb:2761-2790` serves `scoped-head-version-mismatch`, `-control` and `-del`, all with a present value, and the one fixture that omits the header, `scoped-head-version-missing` at `:2753-2760`, is consumed by `Require_Invalid_Head` at `:9741`, which drives the composable `Objects.Head_Object` rather than `Execute_Head_Object`. That composable assertion belongs with the twin predicate reported as {{ISSUE:CLIENT-OBJECTS-1}}, whose `Head_Object_Response_Bound` and `Get_Object_Response_Bound` at `src/flyology-object_storage-client-objects.adb:121-155` have the identical shape. The corpus reaches this layer first, so both layers have to change together.

## What happens now

Spike: the program below scripts two exchanges on a loopback origin. The first replies to `HEAD /never-versioned/native-object?versionId=null` with the verbatim RustFS header set quoted above and no `x-amz-version-id`; the second is identical with `x-amz-version-id: null` added. Both legs drive `Prepare_Head_Object` with the corpus parameters and `Execute_Head_Object`, and assert that the outcome is `Object_Found` and that the ETag reaches the caller.

```ada
      Parameters.Version_ID := US.To_Unbounded_String ("null");
      Parameters.Request_Payer := US.To_Unbounded_String ("requester");
      Parameters.Checksum_Mode := True;
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Head_Object
             (Origin, Low_Level.Path_Style, Bucket, Key, Parameters,
              Identity, "us-east-1", Timestamp);
         Outcome : constant Low_Level.Head_Object_Outcome :=
           Low_Level.Execute_Head_Object (HTTP, Prepared, Timeout => 10.0);
      begin
...
         Check (Outcome.Kind = Low_Level.Object_Found,
                Label & ": a 200 HeadObject without x-amz-version-id is a " &
                  "modeled success");
...
            Check (US.To_String (Outcome.Result.Entity_Tag) =
                     """014842d480b571495a4a0363793f7367""",
                   Label & ": the ETag reaches the caller");
```

Output, exit status 1:

```
  -- scripted loopback origin on 127.0.0.1:50449
  -- --- absent x-amz-version-id (RustFS/MinIO/SeaweedFS/AWS shape) ---
  -- no-header: raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE : HeadObject response does not match prepared request
  FAILED: no-header: a 200 HeadObject without x-amz-version-id is a modeled success
  -- --- control: the origin echoes x-amz-version-id: null ---
  -- control: Execute_Head_Object Kind = OBJECT_FOUND, status 200
  -- control: ETag = "014842d480b571495a4a0363793f7367", Content-Length = 64, Version_ID = "null"
  ok: control: a 200 HeadObject without x-amz-version-id is a modeled success
  ok: control: decoded Version_ID is "null"
  ok: control: the ETag reaches the caller
  -- request 1: HEAD /never-versioned/native-object?versionId=null HTTP/1.1
  -- request 2: HEAD /never-versioned/native-object?versionId=null HTTP/1.1
  ok: the origin served both scripted exchanges
BUG REPRODUCED: 1 failed expectation(s)
```

The two legs differ by one header and nothing else, so status, ETag and `Content-Length` are not what fires, and with no `x-amz-request-charged` in either response the payer clause of the predicate is True in both. The version clause is the sole cause.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Response headers replayed from the pinned RustFS 1.0.0-rc.3 image; shapes checked against the pinned botocore S3 model.

## What should happen

A successful HeadObject that omits `x-amz-version-id` must be accepted, with the decoded `Version_ID` empty, because the pinned botocore model marks `VersionId` optional on `HeadObjectOutput`, `src/flyology-object_storage-client-low_level.ads:1540` calls the field optional, and RustFS, MinIO and SeaweedFS all omit it for an object in a bucket that never had versioning enabled. A response that carries the header with a different value is still a mismatch and must still be refused.

## Suggested treatment

Relax the predicate from "the response must echo the requested version" to "the response must not contradict it", so that only a present and different value is refused:

```ada
        (Requested_Version'Length = 0
         or else US.Length (Value.Version_ID) = 0
         or else US.To_String (Value.Version_ID) = Requested_Version)
```

Apply the same change at every site that carries this predicate, so the layers cannot disagree: `Head_Object_Response_Bound` here at `src/flyology-object_storage-client-low_level.adb:5652-5654`, the GetObjectAttributes check at `src/flyology-object_storage-client-low_level.adb:5383-5397`, the tagging gate at `src/flyology-object_storage-client-low_level.adb:12473-12475`, and the two predicates one layer up, `Get_Object_Response_Bound` at `src/flyology-object_storage-client-objects.adb:131-133` and `Head_Object_Response_Bound` at `src/flyology-object_storage-client-objects.adb:149-151`. The last two are reported as {{ISSUE:CLIENT-OBJECTS-1}} and must change in the same commit, because the conformance corpus reaches this layer first and the composable layer immediately after.

This needs a maintainer decision on what the contract becomes, because the relaxation does not settle the residual mismatch:

- Relaxed predicate only. It accepts the never-versioned shape from all three reference servers. It still refuses the versioning-suspended sentinel `00000000-0000-0000-0000-000000000000` that RustFS returns for `?versionId=null`, which is a present and different value, so a strict-echo contract remains unsatisfiable across real servers even after the change and such a caller still gets an exception.
- Relaxed predicate plus a typed outcome for the residual mismatch. Today the mismatch escapes as `Invalid_Response` before any `Head_Object_Outcome` exists, so no caller can classify a per-server deviation and no oracle mode in the conformance corpus can express one. Turning it into a distinct outcome variant widens the public outcome set, which is an interface decision under the "Decision authority" and "Ada interface values" sections of `AGENTS.md`.
- Keep the strict echo and document that a version-selected HeadObject does not work against servers that omit the header. That leaves the crate unable to head an object in a never-versioned bucket by `versionId=null` on any stock server.

The in-repo server's `x-amz-version-id: null` fallback, {{ISSUE:SERVER-3}}, should be dispositioned once the client stops requiring the header, since it is what hides the defect from the in-tree gate.

The regression test belongs in `tests/src/s3_http_socket_corpus.adb`, beside the existing low-level HeadObject cases: serve a 200 with ETag, `Content-Length`, `Last-Modified` and no `x-amz-version-id` to a `versionId=null` request, and require `Object_Found` with `Version_ID = ""` from `Execute_Head_Object`, leaving `scoped-head-version-mismatch`, `-control` and `-del` asserting rejection. `tests/src/s3_implementation_corpus.adb:1144-1172` already fails against all three reference servers and passes once the predicate is fixed, so a fix must make `tests/scripts/test-rustfs.sh` get past this exchange rather than stop at it. The spike is the test.

## Severity

A version-selected HeadObject cannot complete against any conforming S3 server on the default bucket state. The caller gets `Invalid_Response` instead of a complete 200 whose ETag, size, checksum and metadata are all present and correct, and because the failure escapes as an exception rather than as an outcome variant, the caller cannot classify it or degrade gracefully. `versionId=null` is the documented way to address an object in a bucket where versioning was never enabled, so this is what an ordinary version-aware caller writes. The repository's own conformance corpus fails here against the pinned RustFS, MinIO and SeaweedFS images, seven of seven RustFS runs with the same message at the same exchange, and the only server it passes against is the in-repo one, whose fallback supplies the header the client demands. The predicate is a pure function of two strings, so no timing, load or container state is involved. Deterministic.
