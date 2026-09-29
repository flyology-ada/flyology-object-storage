Title: PutObjectTagging answers MalformedXML for tag failures that the header form and PutBucketTagging answer InvalidTag
Labels: bug
Refs: none

## Summary

`Tagging.Parse` raises `Malformed_Tagging` for a structural XML error, an out-of-repertoire tag key, a duplicate key and an eleventh tag alike, so the object tagging path has no way to say "the XML was fine, the tags were not". The server maps that one exception to 400 `MalformedXML` with a message about the schema. The same tag set sent as `x-amz-tagging` on PutObject, or as a bucket tag set, is answered 400 `InvalidTag` by the same server, and MinIO answers `InvalidTag` for the repertoire and duplicate cases. The package already declares `Invalid_Tag` and never raises it on this path.

## Problem

Commit `5fe6e3e`.

An eleventh `<Tag>` is a structural error to this handler (`src/flyology-object_storage-s3-tagging.adb:60-65`):

```ada
         when 3 =>
            if Local_Name /= "Tag" or else not Item.Seen_Tag_Set
              or else Item.Tags.Length = Maximum_Object_Tags
            then
               raise Malformed_Tagging with "invalid object tag entry";
            end if;
```

and the repertoire and duplicate-key failures are folded into the same exception at the end of the parse (`src/flyology-object_storage-s3-tagging.adb:163-167`):

```ada
      if not Handler.Seen_Tag_Set or else Handler.Depth /= 0
        or else not Valid_S3_Tags (Handler.Tags)
      then
         raise Malformed_Tagging with "invalid object tagging document";
      end if;
```

`Invalid_Tag` is declared for the package (`src/flyology-object_storage-s3-tagging.ads:8-10`):

```ada
   Malformed_Tagging : exception;
   Malformed_Tagging_Query : exception;
   Invalid_Tag : exception;
```

and is never raised on the object XML path.

The server has one arm for the object route (`src/flyology-object_storage-server-s3_applications.adb:15955-15961`):

```ada
                     exception
                        when Tagging.Malformed_Tagging =>
                           Send_Error
                             (X, 400, "MalformedXML",
                              "The XML provided did not validate against " &
                              "the object tagging schema", Target_Text);
                           return;
```

and it stores the parsed set directly at `:15950-15953`, so there is no later re-validation that could emit a different code.

Two other routes answer `InvalidTag` for the same validator failure. `x-amz-tagging` on PutObject (`src/flyology-object_storage-server-s3_applications.adb:15074-15079`):

```ada
                     exception
                        when Tagging.Malformed_Tagging_Query =>
                           Send_Error
                             (X, 400, "InvalidTag",
                              "The PutObject tag set is invalid", Target_Text);
                           return;
```

and CreateMultipartUpload (`src/flyology-object_storage-server-s3_applications.adb:11993-11999`):

```ada
                     exception
                        when Tagging.Malformed_Tagging_Query |
                          Tagging.Invalid_Tag =>
                           Send_Error
                             (X, 400, "InvalidTag",
                              "The multipart tag set is invalid",
                              Target_Text);
```

PutBucketTagging keeps the two apart, so a bad tag there is `InvalidTag` and only a bad document is `MalformedXML` (`src/flyology-object_storage-server-s3_applications.adb:8290-8294`):

```ada
                           when Tagging.Invalid_Tag =>
                              Send_Error
                                (X, 400, "InvalidTag",
                                 "The tag set contains an invalid tag",
                                 Target_Text);
```

The pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) does not settle the code. Printed with python3:

```
--- errors lists ---
 PutObjectTagging   errors=None
 PutBucketTagging   errors=None
 DeleteObjects      errors=None
 InvalidTag shape present: False
```

There is no error shape on any of the three operations and no `InvalidTag` exception shape anywhere in the model, so the authority is the crate's own other two paths plus a real server. MinIO `RELEASE.2025-09-07T16-13-09Z`, from the image pinned at `tests/scripts/test-minio.sh:5`, answers the same three signed `PUT /oracle-b/k?tagging` documents:

```
PutObjectTagging with key a#b                              : 400 <Error><Code>InvalidTag</Code><Message>The TagKey you have provided is invalid</Message>...
PutObjectTagging with a duplicate key                      : 400 <Error><Code>InvalidTag</Code><Message>Cannot provide multiple Tags with the same key</Message>...
PutObjectTagging with eleven tags                          : 400 <Error><Code>BadRequest</Code><Message>Tags cannot be more than 10</Message>...
```

so the repertoire and duplicate cases are settled twice over, and the count case is where the crate and MinIO disagree.

The existing tests do not catch it because none of them asserts a code for an invalid tag on the object XML route. The header path is covered (`tests/src/s3_server_application_corpus.adb:6419-6422`):

```ada
      Require
        (Has (Ten_Tag_Result, "200 OK")
         and then Has (Eleven_Tag_Result, "<Code>InvalidTag</Code>")
         and then Has (Malformed_Tag, "<Code>InvalidTag</Code>")
```

and the PutObjectTagging block covers admission only, asserting the accepted case (`tests/src/s3_server_application_corpus.adb:14403-14406`):

```ada
         Require
           (Has (Response, "200 OK")
            and then Has (Response, "x-amz-version-id: null" & CRLF),
            "PutObjectTagging rejected an unversioned tagging document");
```

No assertion has to be inverted for the two cases MinIO confirms.

## What happens now

Spike: the program below creates `/domain-b6/k` in the in-process memory-backed application and sends three namespaced `PUT /domain-b6/k?tagging` documents with a correct `Content-MD5`, an out-of-repertoire key `a#b`, a duplicate key, and eleven tags, asserting that the `<Code>` is `InvalidTag`. The controls are the same bad key sent as `x-amz-tagging` on PutObject and as a bucket tag set on the same server.

```ada
   function Document (Tags : String) return String is
     ("<Tagging xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
      "<TagSet>" & Tags & "</TagSet></Tagging>");
...
   Object_Case ("outside the AWS repertoire (key a#b)",
                Document (Tag_Element ("a#b", "v")));
   Object_Case ("duplicate key                       ",
                Document (Tag_Element ("dup", "1") &
                          Tag_Element ("dup", "2")));
   Object_Case ("eleven tags                         ",
                Document (Eleven_Tags));
...
   Control ("PutObject x-amz-tagging with key a#b",
            Run (Signed_Request
                   ("PUT", Bucket & "/hdr", "x",
                    "x-amz-tagging: a%23b=v" & CRLF)));
   Control ("PutBucketTagging with key a#b       ",
            Run (Tagging_Put (Bucket, Document (Tag_Element ("a#b", "v")))));
```

Output, exit status 1:

```
  -- === fixtures ===
  ok: CreateBucket /domain-b6 is 200
  ok: PutObject k is 200
  -- 
  -- === the same tag failures on the object XML path ===
  -- PutObjectTagging  outside the AWS repertoire (key a#b)
  --     status=400 code=MalformedXML
  FAILED: PutObjectTagging reports InvalidTag for outside the AWS repertoire (key a#b)
  -- PutObjectTagging  duplicate key                       
  --     status=400 code=MalformedXML
  FAILED: PutObjectTagging reports InvalidTag for duplicate key                       
  -- PutObjectTagging  eleven tags                         
  --     status=400 code=MalformedXML
  FAILED: PutObjectTagging reports InvalidTag for eleven tags                         
  -- 
  -- === controls: the other two paths on the same server ===
  -- control PutObject x-amz-tagging with key a#b
  --     status=400 code=InvalidTag
  ok: control: PutObject x-amz-tagging with key a#b already reports InvalidTag
  -- control PutBucketTagging with key a#b       
  --     status=400 code=InvalidTag
  ok: control: PutBucketTagging with key a#b        already reports InvalidTag
BUG REPRODUCED: 3 failed expectation(s)
```

Every document in the program carries `xmlns`, and the bucket control with the identical body reaches `InvalidTag`, so the namespace rule is not what fires here.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Compared against MinIO `RELEASE.2025-09-07T16-13-09Z` from the pinned image. Shapes checked against the pinned botocore S3 model.

## What should happen

A well-formed `<Tagging>` document whose tags violate the AWS repertoire, or repeat a key, must be answered `InvalidTag`, because that is what the crate's own `x-amz-tagging` and PutBucketTagging routes answer for the same `Valid_S3_Tags` failure and what MinIO answers for the same bytes. `MalformedXML` should stay reserved for a document that really is malformed.

## Suggested treatment

Raise `Tagging.Invalid_Tag`, already declared at `src/flyology-object_storage-s3-tagging.ads:10`, from the tag-validity failures, and give the server one more arm. Concretely, split the condition at `src/flyology-object_storage-s3-tagging.adb:163-167` so that `not Valid_S3_Tags (Handler.Tags)` raises `Invalid_Tag` while the structural conditions keep raising `Malformed_Tagging`, and add `when Tagging.Invalid_Tag => Send_Error (X, 400, "InvalidTag", ...)` beside the existing arm at `src/flyology-object_storage-server-s3_applications.adb:15955-15961`, matching the bucket route at `:8290-8294`. No new public declaration is needed. The `when others` re-raise at `src/flyology-object_storage-s3-tagging.adb:172-173` must be adjusted so `Invalid_Tag` is not swallowed into `Malformed_Tagging`, the way the existing `when Malformed_Tagging => raise;` arm at `:170-171` already does.

The eleventh-tag case needs a maintainer decision, because the three authorities disagree and the answer is an externally visible error code:

- `InvalidTag`, matching the crate's own header path, which already answers `InvalidTag` for an eleventh tag (`tests/src/s3_server_application_corpus.adb:6421`). Consistent inside the crate; differs from MinIO.
- `BadRequest`, matching MinIO `RELEASE.2025-09-07T16-13-09Z`. Consistent with the observed server; differs from the crate's own header path, which would then also have to change or stay inconsistent.
- Leave the count case as `MalformedXML` and change only the repertoire and duplicate cases. Smallest change, but the object route keeps one diagnostic that neither other route nor MinIO gives.

The pinned model names no error shape for `PutObjectTagging`, so it cannot settle this.

The regression test belongs in `tests/src/s3_server_application_corpus.adb`, in the PutObjectTagging block near `:14396-14407`, as three signed `PUT /bucket/key?tagging` requests with a correct `Content-MD5` asserting the chosen `<Code>` for the bad key, the duplicate key and the eleventh tag. `tests/src/s3_implementation_corpus.adb` is where a matching MinIO assertion belongs if the count case is aligned with that server. No existing assertion has to be inverted for the repertoire and duplicate cases. The spike is the test.

## Severity

Wrong diagnostics, not wrong data: the request is correctly refused and nothing is stored, but the caller is told its XML is malformed when the XML is fine and only a tag key is not. A user who hits it will look at their serializer rather than at their tag, and the same tag set sent through `x-amz-tagging` on the same server names the real cause. Any client that sets a tag key containing a character outside the AWS repertoire, repeats a key, or sends an eleventh tag reaches it. The three cases are pure functions of the document, so they fire on every such request. Deterministic.
