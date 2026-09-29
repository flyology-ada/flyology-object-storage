Title: Put_Tags, Get_Tags and Delete_Tags reject every successful tagging response that omits x-amz-version-id
Labels: bug
Refs: CLIENT-LOW-3, CLIENT-LOW-1

## Summary

`Tagging_Version_ID` raises `Low_Level.Invalid_Response` whenever a successful PutObjectTagging, GetObjectTagging or DeleteObjectTagging response carries anything other than exactly one `x-amz-version-id` header. The demand never consults the requested version, so it fires on ordinary tagging calls that mention no version at all, and a bucket that never had versioning enabled has no version to report. The pinned botocore model marks the member optional on all three output shapes, and RustFS answers the repository's own `PUT /bucket/key?tagging` with a `200` that omits it. The result is worse than a failed read: the server applied the tag replacement or deletion, the client reports `Object_Tag_Mutation_Outcome_Unknown` with `Corrupt_Or_Invalid_Response`, and the reconciling read the certainty corpus prescribes for an unknown mutation, a `Get_Tags`, fails identically.

## Problem

Commit `5fe6e3e`.

The multiplicity gate rejects an absent header on any success (`src/flyology-object_storage-client-objects.adb:7177-7211`):

```ada
   function Tagging_Version_ID
     (Response  : HTTP_Client.Response;
      Requested : US.Unbounded_String;
      Success   : Boolean) return String
   is
      Count : constant Natural :=
        HTTP_Client.Header_Count (Response, "x-amz-version-id");
      function Text_Safe (Value : String) return Boolean is
        (for all Item of Value =>
           Character'Pos (Item) >= 16#20#
           and then Character'Pos (Item) /= 16#7F#);
   begin
      if Count > 1 or else (Success and then Count /= 1) then
         raise Low_Level.Invalid_Response with
           "invalid object tagging version header multiplicity";
      elsif Count = 0 then
         return "";
      end if;
      declare
         Value : constant String :=
           HTTP_Client.Header (Response, "x-amz-version-id");
         Expected : constant String := US.To_String (Requested);
      begin
         if Value'Length = 0
           or else not S3.Deletions.Valid_Version_ID (Value)
           or else not Text_Safe (Value)
           or else (Success and then Expected'Length > 0
                    and then Value /= Expected)
         then
            raise Low_Level.Invalid_Response with
              "object tagging response does not match prepared request";
         end if;
         return Value;
      end;
   end Tagging_Version_ID;
```

`Requested` is read only later, at `:7203-7204`, for a present and different value. The presence demand at `:7189` is therefore unconditional: no caller input avoids it. The `Count = 0` branch at `:7192` is reachable only for a rejection.

`Success` is exactly the success status at each of the three call sites. PutObjectTagging (`src/flyology-object_storage-client-objects.adb:7417-7426`):

```ada
            Item.Final_Result := Normalize_Put_Object_Tagging_Response
              (Low_Level.Decode_Put_Object_Tagging_Response
                 (HTTP_Client.Status (Response),
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  Tagging_Version_ID
                    (Response, Item.Requested_Version_ID,
                     HTTP_Client.Status (Response) = 200),
                  HTTP_Client.Header (Response, "x-amz-request-id"),
                  HTTP_Client.Header (Response, "x-amz-id-2")),
               HTTP_Client.Certainty (HTTP_Result));
```

GetObjectTagging (`src/flyology-object_storage-client-objects.adb:7665-7674`):

```ada
            Item.Final_Result := Normalize_Get_Object_Tagging_Response
              (Low_Level.Decode_Get_Object_Tagging_Response
                 (HTTP_Client.Status (Response),
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  Tagging_Version_ID
                    (Response, Item.Requested_Version_ID,
                     HTTP_Client.Status (Response) = 200),
                  HTTP_Client.Header (Response, "x-amz-request-id"),
                  HTTP_Client.Header (Response, "x-amz-id-2")),
               HTTP_Client.Certainty (HTTP_Result));
```

DeleteObjectTagging (`src/flyology-object_storage-client-objects.adb:7956-7965`):

```ada
            Item.Final_Result := Normalize_Delete_Object_Tagging_Response
              (Low_Level.Decode_Delete_Object_Tagging_Response
                 (HTTP_Client.Status (Response),
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  Tagging_Version_ID
                    (Response, Item.Requested_Version_ID,
                     HTTP_Client.Status (Response) = 204),
                  HTTP_Client.Header (Response, "x-amz-request-id"),
                  HTTP_Client.Header (Response, "x-amz-id-2")),
               HTTP_Client.Certainty (HTTP_Result));
```

Each is wrapped in `exception when Low_Level.Invalid_Response =>` that produces `Normalize_*_Failure (HTTP_Client.Response_Invalid, ...)`, so the raise becomes an exchange failure rather than an escaping exception on the composable path. Every public tagging entry point funnels through these three, since the `Start_*` procedures at `:7511`, `:7758` and `:8049` are what both the parameter-record overloads and the `Tagging_Outcome` convenience overloads drive.

The header is optional in the model the repository pins. Reading the pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) with `python3`:

```python
for s in ['PutObjectTaggingOutput', 'GetObjectTaggingOutput',
          'DeleteObjectTaggingOutput']:
    sh = model['shapes'][s]
    print(s, 'required:', sh.get('required'))
    v = sh['members']['VersionId']
    print(' ', {k: v[k] for k in ('shape', 'location', 'locationName')})
```

```
PutObjectTaggingOutput required: None
  {'shape': 'ObjectVersionId', 'location': 'header', 'locationName': 'x-amz-version-id'}
GetObjectTaggingOutput required: ['TagSet']
  {'shape': 'ObjectVersionId', 'location': 'header', 'locationName': 'x-amz-version-id'}
DeleteObjectTaggingOutput required: None
  {'shape': 'ObjectVersionId', 'location': 'header', 'locationName': 'x-amz-version-id'}
```

`GetObjectTaggingOutput` requires `TagSet` and not `VersionId`; the other two shapes require nothing. The low-level decoder this value is fed to already accepts an empty version and validates only a nonempty one (`src/flyology-object_storage-client-low_level.adb:12379-12383`):

```ada
      if Version_ID'Length > 0
        and then not S3.Deletions.Valid_Version_ID (Version_ID)
      then
         raise Invalid_Response with
           "object tagging response contains an invalid version id";
```

and its specification calls the parameter optional (`src/flyology-object_storage-client-low_level.ads:6191`):

```ada
   --  @param Version_ID Optional selected object version response header
```

The maintained documents say the same. `docs/architecture/client-objects.md:100-101`:

```
ordered complete set, and `Delete_Tags` clears it explicitly. All three preserve
the optional response version ID and structured S3 errors.
```

and the maintained certainty corpus requires exactly the case the code refuses. `tests/corpora/composable-client/object-tagging-certainty.tsv:3`, `:5` and `:7`, whose `selection` column is `omitted-version`:

```
PutObjectTagging	Response_Complete	Response_Observed	200	none	Object_Tag_Mutation_Completed	No_Failure	no	omitted-version	current-version response proves completion, not target-version identity
GetObjectTagging	Response_Complete	Response_Observed	200	none	not-applicable	No_Failure	no	omitted-version	current-version observation only, with no mutation certainty
DeleteObjectTagging	Response_Complete	Response_Observed	204	none	Object_Tag_Mutation_Completed	No_Failure	no	omitted-version	current-version response proves completion, not target-version identity
```

A `200` or `204` with no S3 code and no requested version must map to `Object_Tag_Mutation_Completed` with `No_Failure` and no reconciliation. The code maps it to `Object_Tag_Mutation_Outcome_Unknown` with `Corrupt_Or_Invalid_Response`.

This was observed against a real server. RustFS 1.0.0-rc.3 from the image pinned at `tests/scripts/test-rustfs.sh:5` answered the crate's own conformance `PUT /bucket/native-object?tagging` on a never-versioned bucket with, verbatim:

```
HTTP/1.1 200 OK
x-request-id: 2e90fdc8-9408-47de-b681-bb06d8dc699e
x-amz-request-id: 2e90fdc8-9408-47de-b681-bb06d8dc699e
content-length: 0
```

and the corpus stopped with `INVALID_RESPONSE : PutObjectTagging response is invalid or exceeds the XML limit`. A conformance run at this commit does not get that far on its own: it stops earlier on the HeadObject version check reported as {{ISSUE:CLIENT-LOW-1}}, so this tagging exchange was observed by supplying the header that earlier response was missing and letting the corpus continue. The corpus call requests no version at all (`tests/src/s3_implementation_corpus.adb:1629-1632`):

```ada
            Outcome : constant Client_Objects.Tagging_Outcome :=
              Client_Objects.Put_Tags
                (HTTP, Origin, Bucket, Key, Wanted, Identity,
                 Timeout => 30.0);
```

The in-repo server always supplies the header, which is why the memory-server gate cannot observe any of this (`src/flyology-object_storage-server-s3_applications.adb:15846-15854`):

```ada
                  procedure Set_Version_Header is
                  begin
                     Apps.Set_Header
                       (X, "x-amz-version-id",
                        (if not Identity.Has_Version_ID
                           or else Identity.Is_Null_Version
                         then "null"
                         else US.To_String (Identity.Version_ID)));
                  end Set_Version_Header;
```

The same predicate exists one layer down, in `Response_Version_ID` inside `Execute_Object_Tagging` at `src/flyology-object_storage-client-low_level.adb:12465-12475`, reported as {{ISSUE:CLIENT-LOW-3}}. The conformance corpus reaches this layer rather than that one, because it calls `Put_Tags`, but both raise on the same input and both need the same change.

No test catches it, because one asserts the defective behaviour. `tests/src/s3_http_socket_corpus.adb:15091-15254` defines `Require_Invalid_Version`, which demands a rejection for every listed invalid kind:

```ada
               procedure Require_Invalid_Version
                 (Kind : Tagging_Operation_Kind;
                  Invalid : Invalid_Version_Kind)
               is
                  Key : constant String :=
                    "tag-" & Name (Kind) & "-" & Suffix (Invalid);
...
                  if not Rejected then
                     raise Program_Error with
                       Name (Kind) & " object tagging accepted " &
                       Suffix (Invalid) & " version response";
                  end if;
               end Require_Invalid_Version;
```

and it is invoked for every operation and every invalid kind, `Missing` included (`tests/src/s3_http_socket_corpus.adb:15256-15260`):

```ada
               for Kind in Tagging_Operation_Kind loop
                  for Invalid in Invalid_Version_Kind loop
                     Require_Invalid_Version (Kind, Invalid);
                  end loop;
               end loop;
```

The `Duplicate`, `Mismatch`, `Control` and `Delete_Control` variants are correct rejections. Only the `Missing` variant asserts the wrong contract. The success cases in the same corpus all serve the header, so no test serves a success without it and expects success.

## What happens now

Spike: the program below scripts eight exchanges on a loopback origin. Four carry the RustFS tagging reply shape quoted above, with the request identifiers, a content length and no `x-amz-version-id`, using `200` for Put, `200` plus a one-tag `<Tagging>` document for Get and `204` for Delete; four are identical except for an added `x-amz-version-id: null`. Against each set it calls `Put_Tags`, `Get_Tags`, `Delete_Tags` and the `Tagging_Outcome` convenience `Put_Tags`. Every `Parameters.Version_ID` is left empty, so no leg requests a version. It asserts a complete response, `Object_Tag_Mutation_Completed` for the two mutations, the served tag set for Get, and a decoded `Version_ID` of `""` on the absent-header legs and `"null"` on the controls.

```ada
   Request_IDs : constant String :=
     "x-request-id: 2e90fdc8-9408-47de-b681-bb06d8dc699e" & CRLF &
     "x-amz-request-id: 2e90fdc8-9408-47de-b681-bb06d8dc699e" & CRLF;

   Echoed : constant String := "x-amz-version-id: null" & CRLF;
...
      Result : constant Objects.Put_Object_Tagging_Result := Objects.Put_Tags
        (HTTP, Origin, Bucket, Key, Wanted, Parameters, Identity,
         Timeout => 10.0);
...
      Check (Result.Kind = Objects.Put_Object_Tagging_Response_Available,
             Label & ": PutObjectTagging 200 without x-amz-version-id is a " &
               "complete response");
      Check (Result.Disposition = Objects.Object_Tag_Mutation_Completed,
             Label & ": the applied tag replacement is reported as " &
               "completed");
...
      Result : constant Objects.Get_Object_Tagging_Result := Objects.Get_Tags
        (HTTP, Origin, Bucket, Key, Parameters, Identity, Timeout => 10.0);
...
      Check (Result.Kind = Objects.Get_Object_Tagging_Response_Available,
             Label & ": GetObjectTagging 200 without x-amz-version-id is a " &
               "complete response");
...
      Result : constant Objects.Delete_Object_Tagging_Result :=
        Objects.Delete_Tags
          (HTTP, Origin, Bucket, Key, Parameters, Identity, Timeout => 10.0);
...
      Check (Result.Kind = Objects.Delete_Object_Tagging_Response_Available,
             Label & ": DeleteObjectTagging 204 without x-amz-version-id " &
               "is a complete response");
      Check (Result.Disposition = Objects.Object_Tag_Mutation_Completed,
             Label & ": the applied tag deletion is reported as completed");
...
         Result : constant Objects.Tagging_Outcome := Objects.Put_Tags
           (HTTP, Origin, Bucket, Key, Wanted, Identity, Timeout => 10.0);
      begin
...
         Check (Result.Kind = Objects.Tags_Replaced,
                Label & ": the convenience overload reports Tags_Replaced");
```

Output, exit status 1:

```
  -- scripted loopback origin on 127.0.0.1:60488
  -- no leg requests a version: every Parameters.Version_ID is empty
  -- no-header PUT: Put_Tags Kind = PUT_OBJECT_TAGGING_EXCHANGE_FAILED, Disposition = OBJECT_TAG_MUTATION_OUTCOME_UNKNOWN, Failure = CORRUPT_OR_INVALID_RESPONSE
  -- no-header PUT: HTTP_Result = RESPONSE_INVALID, phase RECEIVING_RESPONSE_BODY
  FAILED: no-header PUT: PutObjectTagging 200 without x-amz-version-id is a complete response
  FAILED: no-header PUT: the applied tag replacement is reported as completed
  -- no-header GET: Get_Tags Kind = GET_OBJECT_TAGGING_EXCHANGE_FAILED, Failure = CORRUPT_OR_INVALID_RESPONSE
  -- no-header GET: HTTP_Result = RESPONSE_INVALID, phase RECEIVING_RESPONSE_BODY
  FAILED: no-header GET: GetObjectTagging 200 without x-amz-version-id is a complete response
  -- no-header DELETE: Delete_Tags Kind = DELETE_OBJECT_TAGGING_EXCHANGE_FAILED, Disposition = OBJECT_TAG_MUTATION_OUTCOME_UNKNOWN, Failure = CORRUPT_OR_INVALID_RESPONSE
  -- no-header DELETE: HTTP_Result = RESPONSE_INVALID
  FAILED: no-header DELETE: DeleteObjectTagging 204 without x-amz-version-id is a complete response
  FAILED: no-header DELETE: the applied tag deletion is reported as completed
  -- no-header PUT/convenience: raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE : PutObjectTagging response is invalid or exceeds the XML limit
  FAILED: no-header PUT/convenience: the convenience overload reports Tags_Replaced
  -- --- control: server echoes x-amz-version-id: null ---
  -- control PUT: Put_Tags Kind = PUT_OBJECT_TAGGING_RESPONSE_AVAILABLE, Disposition = OBJECT_TAG_MUTATION_COMPLETED, Failure = NO_FAILURE
  -- control PUT: status 200, Version_ID = "null"
  ok: control PUT: PutObjectTagging 200 without x-amz-version-id is a complete response
  ok: control PUT: the applied tag replacement is reported as completed
  ok: control PUT: outcome is Tags_Put
  ok: control PUT: decoded Version_ID is "null"
  -- control GET: Get_Tags Kind = GET_OBJECT_TAGGING_RESPONSE_AVAILABLE, Failure = NO_FAILURE
  -- control GET: status 200, tags 1, Version_ID = "null"
  ok: control GET: GetObjectTagging 200 without x-amz-version-id is a complete response
  ok: control GET: outcome is Tags_Gotten
  ok: control GET: the served tag set is returned
  ok: control GET: decoded Version_ID is "null"
  -- control DELETE: Delete_Tags Kind = DELETE_OBJECT_TAGGING_RESPONSE_AVAILABLE, Disposition = OBJECT_TAG_MUTATION_COMPLETED, Failure = NO_FAILURE
  -- control DELETE: status 204, Version_ID = "null"
  ok: control DELETE: DeleteObjectTagging 204 without x-amz-version-id is a complete response
  ok: control DELETE: the applied tag deletion is reported as completed
  ok: control DELETE: decoded Version_ID is "null"
  -- control PUT/convenience: Put_Tags (Tagging_Outcome) Kind = TAGS_REPLACED, status 200
  ok: control PUT/convenience: the convenience overload reports Tags_Replaced
  -- request 1: PUT /never-versioned/native-object?tagging HTTP/1.1
  -- request 2: GET /never-versioned/native-object?tagging HTTP/1.1
  -- request 3: DELETE /never-versioned/native-object?tagging HTTP/1.1
  -- request 4: PUT /never-versioned/native-object?tagging HTTP/1.1
  -- request 5: PUT /never-versioned/native-object?tagging HTTP/1.1
  -- request 6: GET /never-versioned/native-object?tagging HTTP/1.1
  -- request 7: DELETE /never-versioned/native-object?tagging HTTP/1.1
  -- request 8: PUT /never-versioned/native-object?tagging HTTP/1.1
  ok: the origin served all eight scripted exchanges
BUG REPRODUCED: 6 failed expectation(s)
```

Each control leg differs from its failing leg by that one header and nothing else, so status, body and tag decoding are not what fires. Note the convenience leg: the `Tagging_Outcome` overload does not soften the result, it re-raises `Low_Level.Invalid_Response` at the caller.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Response headers replayed from the pinned RustFS 1.0.0-rc.3 image; shapes checked against the pinned botocore S3 model.

## What should happen

A successful tagging response that carries no `x-amz-version-id` must be accepted, with the decoded version empty. The pinned botocore model marks `VersionId` optional on `PutObjectTaggingOutput`, `GetObjectTaggingOutput` and `DeleteObjectTaggingOutput`, `docs/architecture/client-objects.md:100-101` calls it "the optional response version ID", and rows `:3`, `:5` and `:7` of `tests/corpora/composable-client/object-tagging-certainty.tsv` require a `200` or `204` with no S3 code and no requested version to be `Object_Tag_Mutation_Completed` with `No_Failure`. A duplicated header remains an invalid response, and a present value different from an explicitly requested one remains a mismatch.

## Suggested treatment

The smallest fix drops the presence half of the multiplicity gate at `src/flyology-object_storage-client-objects.adb:7189`, so that only a duplicate is rejected:

```ada
      if Count > 1 then
```

The `Count = 0` branch immediately below already returns `""`, and the low-level decoder already accepts an empty version at `src/flyology-object_storage-client-low_level.adb:12379-12383`, so nothing further downstream needs to change. Apply the same change to the low-level twin reported as {{ISSUE:CLIENT-LOW-3}}.

How an absent header is then reported needs a maintainer decision:

- Report it as `Version_ID = ""`, matching the low-level decoder and the existing "optional" wording in `src/flyology-object_storage-client-low_level.ads:6191`. No public type changes. A caller cannot distinguish "the server reported no version" from "the field was not populated", which is the situation the crate is already in for reads.
- Add an explicit "no version reported" discriminant or flag to the three tagging result records. This distinguishes the two states, and it is a public API change that widens the result types, so it falls under the "Decision authority" and "Ada interface values" sections of `AGENTS.md`.

Either way `docs/qualification/object-tagging.md:72-74` ("successful responses preserve the selected `x-amz-version-id` from that same exchange") should be reconciled with `docs/architecture/client-objects.md:100-101`, because the tests currently read the qualification sentence as "the header must be present".

The regression test belongs in `tests/src/s3_http_socket_corpus.adb`: invert the `Missing` variant driven by `Require_Invalid_Version` from `:15256-15260` into a success assertion, requiring `Put_Object_Tagging_Response_Available` with `Object_Tag_Mutation_Completed` and `No_Failure`, the served tag set for the get, and `Version_ID = ""` on all three, while `Duplicate`, `Mismatch`, `Control` and `Delete_Control` keep asserting rejection. `tests/src/s3_implementation_corpus.adb` already fails against real servers on this path, so a fix must let `tests/scripts/test-minio.sh` get past its HeadObject case and then through `Require_Object_Tagging`. The spike is the test.

## Severity

Object tagging is unusable through this API against any server that omits the header for an object in a never-versioned bucket. That was observed directly on RustFS. MinIO and SeaweedFS omit the same header for the same bucket state on the read path, so they are expected to hit this too; that was not confirmed, because their conformance run stops earlier. The demand is unconditional, so no caller input avoids it: an ordinary `Put_Tags` with no version selector is enough. The damage is not confined to a lost read, because the server has already applied the replacement or the deletion when the client reports `Object_Tag_Mutation_Outcome_Unknown`, which is the disposition the certainty corpus marks `reconcile = yes`. The reconciling read is `Get_Tags`, and it fails the same way, so the caller can neither complete nor reconcile through this API. The `Tagging_Outcome` convenience overloads raise `Low_Level.Invalid_Response` instead. The predicate is a header count, so nothing about timing or load is involved. Deterministic.
