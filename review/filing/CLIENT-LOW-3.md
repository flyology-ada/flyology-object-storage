Title: Execute_Object_Tagging requires exactly one x-amz-version-id on every tagging success, even with no selector
Labels: bug
Refs: CLIENT-OBJECTS-2, CLIENT-LOW-1

## Summary

The nested `Response_Version_ID` inside `Execute_Object_Tagging` raises `Invalid_Response` whenever a successful PutObjectTagging, GetObjectTagging or DeleteObjectTagging response carries anything other than exactly one `x-amz-version-id` header. The demand never consults the request, so it fires on ordinary tagging calls that name no version at all, and a bucket that never had versioning enabled has no version to report. The pinned botocore model marks the member optional on all three output shapes, and the crate's own specification comment says an unrequested version is an observation rather than proof. For PutObjectTagging and DeleteObjectTagging the mutation has already been applied when the exception is raised, and the message says "multiplicity" although the count is zero.

## Problem

Commit `5fe6e3e`.

The gate conflates header multiplicity with header presence (`src/flyology-object_storage-client-low_level.adb:12465-12492`):

```ada
         function Response_Version_ID
           (Response : Flyology.HTTP.Client.Response;
            Success  : Boolean) return String
         is
            Count : constant Natural :=
              Flyology.HTTP.Client.Header_Count
                (Response, "x-amz-version-id");
         begin
            if Count > 1 or else (Success and then Count /= 1) then
               raise Invalid_Response with
                 "invalid object tagging version header multiplicity";
            elsif Count = 0 then
               return "";
            end if;
            declare
               Value : constant String := Flyology.HTTP.Client.Header
                 (Response, "x-amz-version-id");
            begin
               if Value'Length = 0
                 or else not Valid_List_Response_Header_Text (Value)
                 or else not S3.Deletions.Valid_Version_ID (Value)
               then
                  raise Invalid_Response with
                    "invalid object tagging version header value";
               end if;
               return Value;
            end;
         end Response_Version_ID;
```

`Count > 1` is a genuine protocol violation. `Success and then Count /= 1` is not, because `Success` is only "the status matched the modeled response code" (`src/flyology-object_storage-client-low_level.adb:12528-12529`):

```ada
         Version_ID : constant String := Response_Version_ID
           (Response, Status = Model.Response_Code (Expected));
```

so the demand fires on every success of all three operations. The check that actually binds an explicit selector is separate, and it is correct (`src/flyology-object_storage-client-low_level.adb:12533-12539`):

```ada
         if Status = Model.Response_Code (Expected)
           and then Requested_Version_ID'Length > 0
           and then Version_ID /= Requested_Version_ID
         then
            raise Invalid_Response with
              "object tagging response does not match prepared request";
         end if;
```

The model makes the header optional in all three output shapes and fixes the success codes. Reading the pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) with `python3`:

```python
for op in ['PutObjectTagging', 'GetObjectTagging', 'DeleteObjectTagging']:
    o = model['operations'][op]
    out = model['shapes'][o['output']['shape']]
    v = out['members']['VersionId']
    print(op, 'responseCode:', o['http'].get('responseCode', 200))
    print(' ', o['output']['shape'], 'required:', out.get('required'))
    print(' ', {k: v[k] for k in ('shape', 'location', 'locationName')})
```

```
PutObjectTagging responseCode: 200
  PutObjectTaggingOutput required: None
  {'shape': 'ObjectVersionId', 'location': 'header', 'locationName': 'x-amz-version-id'}
GetObjectTagging responseCode: 200
  GetObjectTaggingOutput required: ['TagSet']
  {'shape': 'ObjectVersionId', 'location': 'header', 'locationName': 'x-amz-version-id'}
DeleteObjectTagging responseCode: 204
  DeleteObjectTaggingOutput required: None
  {'shape': 'ObjectVersionId', 'location': 'header', 'locationName': 'x-amz-version-id'}
```

The crate's own specification says the opposite of the code (`src/flyology-object_storage-client-low_level.ads:10540-10542`):

```ada
      --  A successful explicit-version tagging response must echo this exact
      --  selector. Empty means the request selected the current version, so
      --  any returned version remains an observation rather than proof.
```

Empty is exactly the case the gate refuses. The compatibility document does not require the header either; it says only that the tagging clients "validate bounded responses and version IDs" (`docs/compatibility/s3.md:366-372`).

A real server omits it. RustFS 1.0.0-rc.3, from the image pinned at `tests/scripts/test-rustfs.sh:5`, answered the repository's own `PUT /bucket/native-object?tagging` with

```
HTTP/1.1 200 OK
x-request-id: 2e90fdc8-9408-47de-b681-bb06d8dc699e
x-amz-request-id: 2e90fdc8-9408-47de-b681-bb06d8dc699e
content-length: 0
```

and nothing else. The identical predicate one layer up, `Tagging_Version_ID` at `src/flyology-object_storage-client-objects.adb:7177-7211`, is what raised on that response, since the conformance corpus reaches tagging through `Client.Objects.Put_Tags`; it is reported as {{ISSUE:CLIENT-OBJECTS-2}} and the two are one defect at two layers.

The in-repo server is why CI never sees it. Its tagging branch always sets the header, defaulting to the literal `null` (`src/flyology-object_storage-server-s3_applications.adb:15846-15854`):

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

An existing test asserts the defective behaviour and must be inverted with the fix. `Require_Invalid_Version` (`tests/src/s3_http_socket_corpus.adb:15091-15253`) leaves the selector empty for every kind except `Mismatch` (`:15095-15099`):

```ada
                  Key : constant String :=
                    "tag-" & Name (Kind) & "-" & Suffix (Invalid);
                  Selected : constant String :=
                    (if Invalid = Mismatch
                     then "expected-" & Name (Kind) else "");
```

so the `Missing` case pins exactly the no-selector case. It records a pass only when the synchronous call raises (`:15166-15167`):

```ada
                        when Low_Level.Invalid_Response =>
                           Rejected := True;
```

and fails the corpus otherwise (`:15249-15253`):

```ada
                  if not Rejected then
                     raise Program_Error with
                       Name (Kind) & " object tagging accepted " &
                       Suffix (Invalid) & " version response";
                  end if;
```

It is driven for every operation and every kind, `Missing` included (`tests/src/s3_http_socket_corpus.adb:15256-15260`). The fixtures it consumes are the never-versioned shapes: `tag-put-missing` answers 200 with no version header (`:4331-4334`), `tag-get-missing` answers 200 with a `<Tagging>` body (`:4360-4362`), and `tag-delete-missing` answers 204 (`:4385-4388`). That assertion contradicts `Require_Object_Tagging` in the conformance corpus (`tests/src/s3_implementation_corpus.adb:1617-1673`), which expects the same shapes from real servers to succeed.

## What happens now

Spike: the program below scripts six exchanges on a loopback origin. Three answer `PUT`, `GET` and `DELETE` on `/never-versioned/native-object?tagging` with the RustFS shapes quoted above and no `x-amz-version-id`; three are identical with `x-amz-version-id: opaque-version-1` added. None of the six prepared requests carries a `versionId` selector.

```ada
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Put_Object_Tagging
             (Origin, Low_Level.Path_Style, Bucket, Key, Tags, Parameters,
              Identity, "us-east-1", Timestamp);
         Outcome : constant Low_Level.Object_Tagging_Outcome :=
           Low_Level.Execute_Put_Object_Tagging (HTTP, Prepared, 10.0);
      begin
         Report (Label, Outcome, Low_Level.Tags_Put, Expect_Version);
...
      Check (Outcome.Kind = Wanted,
             Label & ": a successful tagging response without " &
               "x-amz-version-id is " &
               Low_Level.Object_Tagging_Outcome_Kind'Image (Wanted));
...
            Check (Outcome.Result.Tags.Length = 1
                     and then US.To_String (Outcome.Result.Tags.Items (1).Key)
                       = "project",
                   Label & ": the decoded tag set reaches the caller");
```

Output, exit status 1:

```
  -- scripted loopback origin on 127.0.0.1:50501
  -- no request carries a versionId selector; the model marks VersionId optional in all three tagging output shapes
  -- --- no x-amz-version-id (RustFS/MinIO/SeaweedFS/AWS shape) ---
  -- no-header PUT: raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE : invalid object tagging version header multiplicity
  FAILED: no-header PUT: a successful tagging response without x-amz-version-id is TAGS_PUT
  -- no-header GET: raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE : invalid object tagging version header multiplicity
  FAILED: no-header GET: a successful tagging response without x-amz-version-id is TAGS_GOTTEN
  -- no-header DELETE: raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE : invalid object tagging version header multiplicity
  FAILED: no-header DELETE: a successful tagging response without x-amz-version-id is TAGS_DELETED
  -- --- control: the origin echoes x-amz-version-id ---
  -- control PUT: Kind = TAGS_PUT, status 200
  ok: control PUT: a successful tagging response without x-amz-version-id is TAGS_PUT
  -- control PUT: Version_ID = "opaque-version-1", tags 0
  ok: control PUT: decoded Version_ID is "opaque-version-1"
  -- control GET: Kind = TAGS_GOTTEN, status 200
  ok: control GET: a successful tagging response without x-amz-version-id is TAGS_GOTTEN
  -- control GET: Version_ID = "opaque-version-1", tags 1
  ok: control GET: decoded Version_ID is "opaque-version-1"
  ok: control GET: the decoded tag set reaches the caller
  -- control DELETE: Kind = TAGS_DELETED, status 204
  ok: control DELETE: a successful tagging response without x-amz-version-id is TAGS_DELETED
  -- control DELETE: Version_ID = "opaque-version-1", tags 0
  ok: control DELETE: decoded Version_ID is "opaque-version-1"
  -- request 1: PUT /never-versioned/native-object?tagging HTTP/1.1
  -- request 2: GET /never-versioned/native-object?tagging HTTP/1.1
  -- request 3: DELETE /never-versioned/native-object?tagging HTTP/1.1
  -- request 4: PUT /never-versioned/native-object?tagging HTTP/1.1
  -- request 5: GET /never-versioned/native-object?tagging HTTP/1.1
  -- request 6: DELETE /never-versioned/native-object?tagging HTTP/1.1
  ok: the origin served all six scripted exchanges
BUG REPRODUCED: 3 failed expectation(s)
```

All six requests are byte-identical between the failing and the control legs; the responses differ only by the added header. The control GET shows that the tag set decodes correctly once the header is present, so the body handling is not what fires.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Response shapes replayed from the pinned RustFS 1.0.0-rc.3 image; shapes checked against the pinned botocore S3 model.

## What should happen

A successful tagging response that carries no `x-amz-version-id` must be accepted, with the decoded `Version_ID` empty, because the pinned botocore model marks `VersionId` optional on `PutObjectTaggingOutput`, `GetObjectTaggingOutput` and `DeleteObjectTaggingOutput`, and `src/flyology-object_storage-client-low_level.ads:10540-10542` says an unrequested version is an observation rather than proof. Two or more such headers remain an invalid response, and a value different from an explicitly requested selector remains a mismatch, which the separate check at `:12533-12539` already catches.

## Suggested treatment

Split the two rules at `src/flyology-object_storage-client-low_level.adb:12473`: keep `Count > 1` as `Invalid_Response`, and drop the `Success and then Count /= 1` clause so that a zero count returns the empty string on the existing `elsif Count = 0` path. Nothing else in the subprogram has to change, and the message stops claiming a multiplicity that did not occur. The identical gate one layer up at `src/flyology-object_storage-client-objects.adb:7189`, reported as {{ISSUE:CLIENT-OBJECTS-2}}, must change in the same commit, and the same relaxation is due at the two version-echo predicates reported as {{ISSUE:CLIENT-LOW-1}}.

This needs a maintainer decision on how an absent version is represented, because the two states are otherwise indistinguishable to a caller:

- Leave `Version_ID` a plain `Unbounded_String` that is empty when the server omitted the header. This is the shape `Head_Object_Result` and `Get_Object_Attributes_Result` already use, and it adds no public entity. A caller cannot then tell "no version reported" from "version reported as the empty string", which no server sends.
- Give the tagging result an explicit optional, so the two states are distinct. That widens the public result types and falls under the "Decision authority" and "Ada interface values" sections of `AGENTS.md`.

The regression test belongs in `tests/src/s3_http_socket_corpus.adb`: invert the `Missing` variant driven by `Require_Invalid_Version` at `:15256-15260` into a success assertion, requiring `Tags_Put`, `Tags_Gotten` and `Tags_Deleted` with `Version_ID = ""` and the served tag set on the get, while `Duplicate`, `Mismatch`, `Control` and `Delete_Control` keep asserting rejection. `tests/src/s3_implementation_corpus.adb:1617-1673` already expects those shapes to succeed against real servers, so the two files stop contradicting each other. The spike is the test.

## Severity

Every PutObjectTagging, GetObjectTagging and DeleteObjectTagging against an object in a bucket that never had versioning enabled fails, and no caller input avoids it, because the demand does not consult the request. That makes it the broadest of this family: the plain `Put_Tags`, `Get_Tags` and `Delete_Tags` paths are affected on the default bucket state of every stock server. For the two mutations the server has already applied the change when the exception is raised, so the caller is left unable to distinguish an applied mutation from a corrupt response, and the diagnostic it does get names a header multiplicity that is zero. The in-repo server hides it by always sending the header, so the in-tree gate is green while real servers are not. Deterministic.
