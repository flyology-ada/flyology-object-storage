Title: Parse_Bucket_Response applies the nonempty publication predicate to a response, so an empty TagSet is rejected
Labels: bug
Refs: none

## Summary

`Parse_Bucket_Document` runs `Tags.Valid_Bucket_Tag_Set` on the way in and on the way out, and that predicate is documented as validating a nonempty bucket tag set. It is a publication rule, applied here to a decoded response. MinIO serves `<Tagging><TagSet></TagSet></Tagging>` with 200 for a bucket whose tag set was stored empty, and the pinned botocore S3 model puts no minimum on `Tagging.TagSet`, so `Decode_Get_Bucket_Tagging_Response` reports `Invalid_Response "malformed GetBucketTagging response"` for a well-formed answer.

## Problem

Commit `5fe6e3e`.

One shared body serves both the request parser and the response decoder, and both run the same set-level predicate (`src/flyology-object_storage-s3-tagging.adb:562-567`):

```ada
      XML.Parse (Document, Handler, Limits);
      if not Handler.Seen_Tag_Set or else Handler.Depth /= 0 then
         raise Malformed_Tagging with "bucket tagging document lacks TagSet";
      elsif not Tags.Valid_Bucket_Tag_Set (Handler.Result) then
         raise Invalid_Tag with "invalid bucket tag set";
      end if;
```

`Parse_Bucket_Response` is one of the two instantiations of that body (`src/flyology-object_storage-s3-tagging.adb:581-586`):

```ada
   function Parse_Bucket_Response
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Tags.Tag_Set is
     (Parse_Bucket_Document
        (Document, Limits, Allow_Empty_Namespace => True));
```

The predicate is documented as a publication rule that requires at least one tag (`src/flyology-object_storage-tags.ads:34-40`):

```ada
   --  Validate a nonempty bucket tag set: at most 50 unique, case-sensitive
   --  keys; UTF-8 scalar values in the AWS L/Z/N or `_.:/=+-@` character
   --  classes; 1..128 key and 0..256 value Unicode characters; and no
   --  user-defined key with the reserved case-insensitive `aws:` prefix.
   --  @param Value Candidate bucket tag set
   --  @return Whether every tag and the complete set satisfy the constraints
   function Valid_Bucket_Tag_Set (Value : Tag_Set) return Boolean;
```

The contract for the response decoder promises namespace tolerance and says nothing about emptiness (`src/flyology-object_storage-s3-tagging.ads:48-54`):

```ada
   --  Parse a bucket-tagging response from S3-compatible implementations.
   --  The official S3 namespace and an absent namespace are accepted;
   --  foreign namespaces and attributes remain invalid.
   function Parse_Bucket_Response
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Tags.Tag_Set;
```

The client catches `Invalid_Tag` and re-raises it as a response-level failure (`src/flyology-object_storage-client-low_level.adb:387-405`):

```ada
      if Status = 200 then
         if Charged'Length > 0 then
            raise Invalid_Response with
              "GetBucketTagging returned invalid request charging metadata";
         end if;
         Result.Value := S3.Tagging.Parse_Bucket_Response (Payload, Limits);
...
   exception
      when S3.Tagging.Malformed_Tagging | S3.Tagging.Invalid_Tag |
           S3.Errors.Malformed_Error =>
         raise Invalid_Response with "malformed GetBucketTagging response";
```

The pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) models an empty set. Printed with python3:

```
--- TagSet shape ---
{"type": "list", "member": {"shape": "Tag", "locationName": "Tag"}}
```

The list has no `min`, so zero members is a modelled value.

MinIO `RELEASE.2025-09-07T16-13-09Z`, from the image pinned at `tests/scripts/test-minio.sh:5`, distinguishes an absent tag set from an empty one and serves the empty one with 200. Four signed requests against the same bucket, in order:

```
DeleteBucketTagging                                        : 204
GetBucketTagging after delete                              : 404 <Error><Code>NoSuchTagSet</Code><Message>The TagSet does not exist</Message>...
PutBucketTagging with an empty TagSet                      : 200
GetBucketTagging after PUT with an empty TagSet            : 200 <Tagging><TagSet></TagSet></Tagging>
```

`NoSuchTagSet` is what MinIO answers only when no tag set was ever stored. Once a client stores an empty one, which MinIO accepts, the empty response is what a reader gets, so the state is reachable and distinct.

Nothing in tree covers it and nothing asserts the wrong behaviour, because Flyology's own writer cannot create the state. `Serialize_Bucket` refuses an empty set with the same predicate (`src/flyology-object_storage-s3-tagging.adb:591-596`):

```ada
   function Serialize_Bucket (Value : Tags.Tag_Set) return String is
      Result : US.Unbounded_String;
   begin
      if not Tags.Valid_Bucket_Tag_Set (Value) then
         raise Invalid_Tag with "invalid bucket tag set";
      end if;
```

so the decoder never sees an empty set in any lane; another client has to create it.

## What happens now

Spike: the program below decodes MinIO's exact bytes through `S3.Tagging.Parse_Bucket_Response` and through `Client.Low_Level.Decode_Get_Bucket_Tagging_Response`. A one-tag body is the control.

```ada
   --  Exactly the bytes MinIO returns (no XML declaration, no namespace).
   Empty_Body : constant String :=
     "<Tagging><TagSet></TagSet></Tagging>";
   One_Tag_Body : constant String :=
     "<Tagging><TagSet><Tag><Key>k</Key><Value>v</Value></Tag>" &
     "</TagSet></Tagging>";
```

Output, exit status 1:

```
  -- === control: a one-tag GetBucketTagging response ===
  -- control: one tag                     body=<Tagging><TagSet><Tag><Key>k</Key><Value>v</Value></Tag></TagSet></Tagging>
  --     S3.Tagging.Parse_Bucket_Response: accepted, tags=1
  --     Client.Low_Level: accepted, kind=BUCKET_TAGS_FOUND
  -- 
  -- === MinIO's empty-TagSet GetBucketTagging response ===
  -- client decodes an empty bucket TagSet body=<Tagging><TagSet></TagSet></Tagging>
  --     S3.Tagging.Parse_Bucket_Response: FLYOLOGY.OBJECT_STORAGE.S3.TAGGING.INVALID_TAG: invalid bucket tag set
  --     Client.Low_Level: FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE: malformed GetBucketTagging response
  FAILED: client decodes an empty bucket TagSet
BUG REPRODUCED: 1 failed expectation(s)
```

The two bodies differ only in whether `<TagSet>` holds a `<Tag>`, and both are namespace-free, so the namespace tolerance the contract promises is working and the emptiness is the sole cause. The exception raised is `Invalid_Tag`, which is the set-level predicate and not a structural error, so the failure is the publication rule rather than the parser.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Compared against MinIO `RELEASE.2025-09-07T16-13-09Z` from the pinned image. Shapes checked against the pinned botocore S3 model.

## What should happen

A GetBucketTagging response carrying an empty `<TagSet>` must decode to an empty tag set, because the pinned botocore S3 model puts no minimum on `Tagging.TagSet`, because `src/flyology-object_storage-s3-tagging.ads:48-50` promises only namespace tolerance for this entry point, and because MinIO serves exactly those bytes with 200 for a bucket whose tag set was stored empty. Publishing an empty set may still be refused.

## Suggested treatment

Split the receive-side check from the publication check, so that `Parse_Bucket_Response` accepts an empty decoded set while `Serialize_Bucket` at `src/flyology-object_storage-s3-tagging.adb:591-596` and `Parse_Bucket` keep the nonempty rule. Concretely, that means the `elsif not Tags.Valid_Bucket_Tag_Set` branch at `src/flyology-object_storage-s3-tagging.adb:565-566` must not fire for an empty set when the document is a response.

This needs a maintainer decision, because it changes what `Tags.Tag_Set` means at the boundary and `Valid_Bucket_Tag_Set` is a visible predicate whose documented meaning is nonemptiness (`src/flyology-object_storage-tags.ads:34-40`):

- Skip the emptiness part of the predicate on the response path only, keeping every per-tag and set-level rule. Smallest change, and it leaves the publication contract untouched. It needs a way to express "empty is allowed here", either a second flag threaded beside `Allow_Empty_Namespace` in `Parse_Bucket_Document` or an explicit `Handler.Result.Is_Empty` short-circuit before the call.
- Redefine `Valid_Bucket_Tag_Set` to accept an empty set and move the nonemptiness requirement to `Serialize_Bucket` and `Parse_Bucket`, which are the two places that publish. This makes the visible predicate mean "every tag is valid and the set is consistent", which is what a decoder wants, and it changes the documented meaning of a public function.
- Leave it and document that GetBucketTagging does not work against a bucket whose tag set was stored empty by another client.

The first two need no new public declaration.

The regression test belongs in `tests/src/s3_http_socket_corpus.adb`, beside the other scripted GetBucketTagging responses, as a decode of `<Tagging><TagSet></TagSet></Tagging>` that must yield an empty tag set with `Bucket_Tags_Found`, keeping the existing one-tag and invalid-tag cases as they are. `tests/src/s3_implementation_corpus.adb` is where the MinIO leg belongs, since reaching the state requires storing an empty tag set first. Nothing in the suite asserts the wrong behaviour, so no test has to be inverted. The spike is the test.

## Severity

A well-formed 200 is reported to the caller as a malformed response, so reading the tags of a bucket whose tag set was stored empty fails outright rather than returning nothing. It needs another client to have deliberately stored an empty set, which Flyology's own writer cannot do, so a deployment that only ever writes tags through this crate will not reach it. The result is a wrong error rather than wrong data, and it is a pure function of the decoded set, so it fires on every read of such a bucket. Deterministic.
