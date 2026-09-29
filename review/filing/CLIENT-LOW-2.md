Title: Execute_Get_Object_Attributes rejects the 200 the crate's own server returns for versionId=null
Labels: bug
Refs: CLIENT-LOW-1

## Summary

`Decode_Get_Object_Attributes_Complete_Response` requires a successful GetObjectAttributes response to echo the requested `versionId`. An absent `x-amz-version-id` header decodes to the empty string, so a request that selects `versionId=null` against an object in a bucket that never had versioning enabled turns a valid 200, carrying the requested ETag and object size, into `Invalid_Response`. The pinned botocore model marks the member optional, and no server satisfies the demand: the repository's own in-process S3 application omits the header on this route, so the operation fails against the crate's own server as well as against third-party ones.

## Problem

Commit `5fe6e3e`.

The decoder binds the header and then requires it to equal the retained selector (`src/flyology-object_storage-client-low_level.adb:5371-5372` and `:5383-5397`):

```ada
         Version_ID : constant String :=
           Singleton_Header ("x-amz-version-id");
```

```ada
         if Outcome.Kind = Object_Attributes_Found
           and then
             ((Request_Charged'Length > 0
               and then US.To_String
                 (Prepared.Requested_Get_Attributes_Request_Payer) /=
                   "requester")
              or else
                (US.Length
                   (Prepared.Requested_Get_Attributes_Version_ID) > 0
                 and then Version_ID /= US.To_String
                   (Prepared.Requested_Get_Attributes_Version_ID)))
         then
            raise Invalid_Response with
              "GetObjectAttributes response does not match request";
         end if;
```

An absent header is the empty string, because `Singleton_Header` returns `""` for a header count of zero (`src/flyology-object_storage-client-low_level.adb:5349-5350`):

```ada
         elsif Count = 0 then
            return "";
```

so `"" /= "null"` trips the check. The exception escapes `Execute_Get_Object_Attributes`, which has no other outcome for it (`src/flyology-object_storage-client-low_level.adb:5508-5510`):

```ada
         return Decode_Get_Object_Attributes_Complete_Response
           (Response, Flyology.Bytes.To_Byte_String (Payload), Prepared,
            Limits);
```

The same decoder is reached from the composable `Client.Objects` GetObjectAttributes operation, so both entry points are affected.

The model does not require the header. Reading the pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) with `python3`:

```python
sh = model['shapes']['GetObjectAttributesOutput']
print('GetObjectAttributesOutput required:', sh.get('required'))
v = sh['members']['VersionId']
print(' ', {k: v[k] for k in ('shape', 'location', 'locationName')})
```

```
GetObjectAttributesOutput required: None
  {'shape': 'ObjectVersionId', 'location': 'header', 'locationName': 'x-amz-version-id'}
```

The crate's own specification calls the field optional (`src/flyology-object_storage-client-low_level.ads:2677`):

```ada
   --  @field Version_ID Optional selected-version response header
```

The repository's own server cannot satisfy the demand. Its GetObjectAttributes handler emits the header only when the stored version is nonempty, with no fallback (`src/flyology-object_storage-server-s3_applications.adb:16347-16352`):

```ada
                        HTTP_Last_Modified (Snapshot.Info.Modified));
                     if US.Length (Snapshot.Info.Version) > 0 then
                        Apps.Set_Header
                          (X, "x-amz-version-id",
                           US.To_String (Snapshot.Info.Version));
                     end if;
```

That is the difference from the read routes, where a `null` fallback exists (`src/flyology-object_storage-server-s3_applications.adb:4189-4194` for GetObject and `:16619-16622` for HeadObject) and hides the same client demand, reported as {{ISSUE:CLIENT-LOW-1}}. On this route nothing hides it.

A maintained qualification document states the requirement that no server satisfies, so it is part of the defect rather than a defence of it (`docs/qualification/get-object-attributes.md:41-43`):

```
Unavailable optional attributes are omitted rather than invented. An explicit
nonempty `VersionId` must be echoed exactly; omission observes the generation
current at read time.
```

No test catches this, and no assertion has to be inverted, because no maintained test reaches the branch. `Require_Get_Object_Attributes` in the conformance corpus (`tests/src/s3_implementation_corpus.adb:1675-1861`) never sets `Parameters.Version_ID`, so the real-server run never sends a selector here. The socket corpus does send one, but its fixture echoes it (`tests/src/s3_http_socket_corpus.adb:15918-15919`):

```ada
            Parameters.Version_ID :=
              US.To_Unbounded_String ("socket version");
```

so the absent-header case is unexercised rather than pinned.

## What happens now

Spike: the program below publishes one object into a bucket that never had versioning enabled through the in-repo S3 application, shows with a raw signed request that the server answers `GET /bucket/key?attributes&versionId=null` with a 200 carrying zero `x-amz-version-id` headers, then serves the same application on a loopback listener and drives `Prepare_Get_Object_Attributes` and `Execute_Get_Object_Attributes` against it, once with `Version_ID = "null"` and once with no selector.

```ada
      Parameters.Version_ID := US.To_Unbounded_String (Selector);
      Parameters.Attributes.Entity_Tag := True;
      Parameters.Attributes.Object_Size := True;
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Get_Object_Attributes
             (Origin, Low_Level.Path_Style, Bucket, Key, Parameters,
              Identity, Server.Region, Server.Timestamp);
         Outcome : constant Low_Level.Get_Object_Attributes_Outcome :=
           Low_Level.Execute_Get_Object_Attributes
             (HTTP, Prepared, Timeout => 10.0);
      begin
...
         Check (Outcome.Kind = Low_Level.Object_Attributes_Found,
                Label & ": a 200 GetObjectAttributes without " &
                  "x-amz-version-id is a modeled success");
...
            Check (Outcome.Result.Attributes.Object_Size.Is_Set
                     and then Outcome.Result.Attributes.Object_Size.Value =
                       Body_Text'Length,
                   Label & ": ObjectSize is" & Body_Text'Length'Image);
```

The raw leg that establishes what the server sends:

```ada
      Raw : constant String := Server.Run
        (Server.Signed_Request
           ("GET", "/" & Bucket & "/" & Key,
            Extra_Headers => "x-amz-object-attributes: ETag,ObjectSize" & CRLF,
            Query => [Server.SigV4.Pair ("attributes", ""),
                      Server.SigV4.Pair ("versionId", "null")]));
...
      Check (Header_Count (Raw, "x-amz-version-id") = 0,
             "setup: that 200 carries no x-amz-version-id");
```

Output, exit status 1:

```
  -- in-process CreateBucket status 200
  ok: setup: CreateBucket is 200
  -- in-process PutObject status 200, x-amz-version-id = ""
  ok: setup: PutObject is 200
  ok: setup: the never-versioned publication returns no version id
  -- raw GET ?attributes&versionId=null -> status 200, x-amz-version-id count 0
  ok: setup: the in-repo server answers the versioned attributes request with 200
  ok: setup: that 200 carries no x-amz-version-id
  -- loopback S3 application on 127.0.0.1:50470
  -- --- explicit versionId=null against a never-versioned bucket ---
  -- versioned: raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE : GetObjectAttributes response does not match request
  FAILED: versioned: a 200 GetObjectAttributes without x-amz-version-id is a modeled success
  -- --- control: no version selector, same object ---
  -- control: Execute_Get_Object_Attributes Kind = OBJECT_ATTRIBUTES_FOUND, status 200
  -- control: ETag = 6b344779a83cd6a352fbfcec796f62f2, ObjectSize set = TRUE, Version_ID = ""
  ok: control: a 200 GetObjectAttributes without x-amz-version-id is a modeled success
  ok: control: the requested ETag attribute reaches the caller
  ok: control: ObjectSize is 16
BUG REPRODUCED: 1 failed expectation(s)
```

The control leg is the same object, the same server and the same decoder with the selector removed, and it returns the ETag and an object size of 16. Adding `versionId=null` to the request is the only difference, and it destroys a response the server produced correctly. No third-party server and no container are involved.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Shapes checked against the pinned botocore S3 model.

## What should happen

A successful GetObjectAttributes that omits `x-amz-version-id` must be accepted, with the decoded `Version_ID` empty, because the pinned botocore model marks `VersionId` optional on `GetObjectAttributesOutput` and `src/flyology-object_storage-client-low_level.ads:2677` calls the field optional. A response that carries the header with a different value is still a mismatch and must still be refused.

## Suggested treatment

Relax the version clause of the check at `src/flyology-object_storage-client-low_level.adb:5390-5393` so that only a present and different value is refused:

```ada
                (US.Length
                   (Prepared.Requested_Get_Attributes_Version_ID) > 0
                 and then Version_ID'Length > 0
                 and then Version_ID /= US.To_String
                   (Prepared.Requested_Get_Attributes_Version_ID))
```

The same relaxation belongs at the other three sites that carry this predicate, reported as {{ISSUE:CLIENT-LOW-1}}, so the four do not diverge. This needs the same maintainer decision recorded there: whether the contract becomes "the response must not contradict the selector" or whether the residual mismatch becomes a typed outcome instead of an exception, which widens the public outcome set and falls under the "Decision authority" and "Ada interface values" sections of `AGENTS.md`.

`docs/qualification/get-object-attributes.md:42` must be reworded either way, because "An explicit nonempty `VersionId` must be echoed exactly" is the requirement being removed. The in-repo server's own asymmetry is worth settling in the same pass: its GetObjectAttributes handler omits the header where its GetObject and HeadObject handlers manufacture `null`.

The regression test belongs in `tests/src/s3_server_application_corpus.adb`, which already drives the in-process S3 application over signed requests, as a client-against-server round trip: publish an object into a never-versioned bucket, then require `Object_Attributes_Found` with `Version_ID = ""` and the requested attributes present from `Execute_Get_Object_Attributes` with `Version_ID = "null"`. A socket-corpus case with a present and different value should stay a rejection. The spike is the test.

## Severity

A GetObjectAttributes request that names a version cannot complete against an object in a bucket that never had versioning enabled, which is the default bucket state, and `versionId=null` is the documented way to address such an object. The caller gets `Invalid_Response` instead of a 200 whose ETag, size, checksums and parts page are all correct, and the exception escapes before any outcome value exists, so the caller cannot classify it. Unlike the sibling defects on the read routes, this one is not masked by the repository's own server: the failure above is against the in-repo S3 application, with no container and no third-party server, so a user of both halves of this crate hits it. It is reachable from `Execute_Get_Object_Attributes` and from the composable `Client.Objects` operation, which calls the same decoder. Deterministic.
