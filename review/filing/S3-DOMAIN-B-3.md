Title: Annotations.Parse_Query binds camelCase query names the model and this crate's own client never send
Labels: bug
Refs: none

## Summary

`Annotations.Parse_Query` matches the query parameters `annotationPrefix`, `maxAnnotationResults` and `continuationToken`, while the pinned botocore S3 model, the generated model descriptor and `Client.Low_Level.Prepare_List_Object_Annotations` all use `annotation-prefix`, `max-annotation-results` and `continuation-token`. Anything the codec does not recognise falls through to `Malformed_Annotation_Request`, which the server answers with 400 `InvalidArgument`. A Flyology client that asks for a prefix, a result limit or the next page is therefore refused by a Flyology server, and only the degenerate "list everything, one page" call works.

## Problem

Commit `5fe6e3e`.

The three list-only members are matched by hand-written camelCase literals, and anything else is rejected (`src/flyology-object_storage-s3-annotations.adb:137-178`):

```ada
                  elsif Name = "annotationPrefix" then
                     if Result.Has_Annotation_Prefix then
                        raise Malformed_Annotation_Request with
                          "duplicate annotation prefix";
                     end if;
                     Result.Has_Annotation_Prefix := True;
                     Result.Annotation_Prefix :=
                       US.To_Unbounded_String (Value);
                  elsif Name = "maxAnnotationResults" then
...
                  elsif Name = "continuationToken" then
...
                  else
                     raise Malformed_Annotation_Request with
                       "unsupported annotation query parameter";
                  end if;
```

The route records that exception and answers 400. The sniff (`src/flyology-object_storage-server-s3_applications.adb:6507-6521`):

```ada
               Annotation_Request := Annotations.Parse_Query
                 (Query_Text, Annotation_Operation);
...
            exception
               when Annotations.Malformed_Annotation_Request =>
                  Annotation_Query_Invalid := True;
```

and the answer (`src/flyology-object_storage-server-s3_applications.adb:7015-7019`):

```ada
      elsif Annotation_Query_Invalid then
         Send_Error
           (X, 400, "InvalidArgument",
            "The object annotation request query is invalid", Target_Text);
         return;
```

The pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) names the querystring members with hyphens. Printed with python3:

```
--- ListObjectAnnotationsRequest querystring members ---
 VersionId              -> 'versionId'
 MaxAnnotationResults   -> 'max-annotation-results'
 AnnotationPrefix       -> 'annotation-prefix'
 ContinuationToken      -> 'continuation-token'
```

The generated descriptor agrees with it (`src/flyology-object_storage-s3-model.adb:45588-45601`):

```ada
         when 393 =>
            case Member is
               when 1 =>
                  return "Bucket";
               when 2 =>
                  return "Key";
               when 3 =>
                  return "versionId";
               when 4 =>
                  return "max-annotation-results";
               when 5 =>
                  return "annotation-prefix";
               when 6 =>
                  return "continuation-token";
```

The crate's own client reads that descriptor. `Prepare_List_Object_Annotations` adds the three members by model name (`src/flyology-object_storage-client-low_level.adb:11609-11621`):

```ada
      if Parameters.Has_Max_Annotation_Results then
         Add ("MaxAnnotationResults", Limit_Image);
      end if;
      if Parameters.Has_Annotation_Prefix then
         Add
           ("AnnotationPrefix",
            US.To_String (Parameters.Annotation_Prefix));
      end if;
      if Parameters.Has_Continuation_Token then
         Add
           ("ContinuationToken",
            US.To_String (Parameters.Continuation_Token));
      end if;
```

and the shared request builder emits each one under its descriptor location name (`src/flyology-object_storage-client-low_level.adb:1217-1222`):

```ada
               if Location = Model.Query_Location then
                  Query_Last := Query_Last + 1;
                  Query (Query_Last) := SigV4.Pair
                    (Model.Member_Location_Name (Input_Shape, Member),
                     US.To_String (Values (Value_Index).Value));
               end if;
```

so the client puts the hyphenated spelling on the wire and the server refuses it. The two singular annotation verbs are correct: `Parse_Query` matches `annotationName` (`src/flyology-object_storage-s3-annotations.adb:119-127`) and `versionId` (`:128-136`), which is what the model gives them, so only these three names are wrong.

The in-tree gate sends the non-model spellings and so pins the defect (`tests/src/s3_server_application_corpus.adb:13550-13553`):

```ada
         First_Query : constant SigV4.Name_Value_Array :=
           (SigV4.Pair ("annotation", ""),
            SigV4.Pair ("maxAnnotationResults", "1"),
            SigV4.Pair ("x-id", "ListObjectAnnotations"));
```

and again for the second page (`tests/src/s3_server_application_corpus.adb:13585-13589`):

```ada
            Next_Query : constant SigV4.Name_Value_Array :=
              (SigV4.Pair ("annotation", ""),
               SigV4.Pair ("continuationToken", Token),
               SigV4.Pair ("maxAnnotationResults", "1"),
               SigV4.Pair ("x-id", "ListObjectAnnotations"));
```

Both must be updated with the fix. The qualification lane sets the three optional members only when environment inputs are present (`tests/src/s3_list_object_annotations_qualification.adb:85-95`):

```ada
      Has_Max_Annotation_Results => Max_Text'Length > 0,
      Annotation_Prefix          =>
        US.To_Unbounded_String (Annotation_Prefix),
      Has_Annotation_Prefix      =>
        Environment.Exists
          ("FLYOLOGY_S3_QUALIFICATION_INPUT_ANNOTATION_PREFIX"),
      Continuation_Token         =>
        US.To_Unbounded_String (Continuation_Token),
      Has_Continuation_Token     =>
        Environment.Exists
          ("FLYOLOGY_S3_QUALIFICATION_INPUT_CONTINUATION_TOKEN"),
```

so the default lane never sends them to a server and never noticed.

## What happens now

Spike: the program below first prints the query location names the compiled model gives the operation, then creates `/domain-b3/obj` with the annotations `alpha` and `beta` in the in-process memory-backed application, and issues signed `GET /domain-b3/obj?annotation&<name>=<value>` requests in both spellings. The camelCase requests are the controls. The `continuation-token` probe uses a real `NextContinuationToken` taken from the preceding page.

```ada
      for Member in 1 .. Model.Member_Count (Shape) loop
         if Model.Location (Shape, Member) = Model.Query_Location then
            Note ("    " & Model.Member_Name (Shape, Member) & " -> """ &
                  Model.Member_Location_Name (Shape, Member) &
                  """ (what Client.Low_Level puts on the wire)");
         end if;
      end loop;
...
   Probe ("control ", "maxAnnotationResults", "1", False);
   Probe ("control ", "annotationPrefix", "al", False);
...
   Probe ("model   ", "max-annotation-results", "1", True);
   Probe ("model   ", "annotation-prefix", "al", True);
```

Output, exit status 1, with the three long response bodies trimmed at `...`:

```
  -- === the pinned model's ListObjectAnnotations query names ===
  ok: control: the model has a ListObjectAnnotations input shape
  --     VersionId -> "versionId" (what Client.Low_Level puts on the wire)
  --     MaxAnnotationResults -> "max-annotation-results" (what Client.Low_Level puts on the wire)
  --     AnnotationPrefix -> "annotation-prefix" (what Client.Low_Level puts on the wire)
  --     ContinuationToken -> "continuation-token" (what Client.Low_Level puts on the wire)
  -- 
  -- === fixtures ===
  ok: CreateBucket /domain-b3 is 200
  ok: PutObject obj is 200
  ok: PutObjectAnnotation alpha is 200
  ok: PutObjectAnnotation beta is 200
  -- 
  -- === control: the codec's camelCase spellings (accepted today) ===
  -- control  GET /domain-b3/obj?annotation&maxAnnotationResults=1
  --     status=200 body=<ListObjectAnnotationsOutput xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Annotations><AnnotationEntry><AnnotationName>alpha</AnnotationName>...<NextContinuationToken>fos1.5073ca3abd4a8ffc65e51385fca7513b2c3a2c5015c9debcaa3ecaf577636496.616c706861</NextContinuationToken></ListObjectAnnotationsOutput>
  -- control  GET /domain-b3/obj?annotation&annotationPrefix=al
  --     status=200 body=<ListObjectAnnotationsOutput ...><AnnotationPrefix>al</AnnotationPrefix><AnnotationCount>1</AnnotationCount></ListObjectAnnotationsOutput>
  -- 
  -- === the model's spellings, as the crate's own client sends ===
  -- model    GET /domain-b3/obj?annotation&max-annotation-results=1
  --     status=400 body=<?xml version="1.0" encoding="UTF-8"?><Error><Code>InvalidArgument</Code><Message>The object annotation request query is invalid</Message><Resource>/domain-b3/obj?annotation&amp;max-annotation-results=1</Resource></Error>
  FAILED: the model's spelling "max-annotation-results" is accepted
  -- model    GET /domain-b3/obj?annotation&annotation-prefix=al
  --     status=400 body=<?xml version="1.0" encoding="UTF-8"?><Error><Code>InvalidArgument</Code><Message>The object annotation request query is invalid</Message><Resource>/domain-b3/obj?annotation&amp;annotation-prefix=al</Resource></Error>
  FAILED: the model's spelling "annotation-prefix" is accepted
  -- 
  -- === pagination with the model's continuation-token ===
  -- first page (camelCase) status=200
  ok: control: the first page returns a continuation token
  -- token=fos1.5073ca3abd4a8ffc65e51385fca7513b2c3a2c5015c9debcaa3ecaf577636496.616c706861
  -- model    GET /domain-b3/obj?annotation&continuation-token=fos1.5073ca3abd4a8ffc65e51385fca7513b2c3a2c5015c9debcaa3ecaf577636496.616c706861
  --     status=400 body=<?xml version="1.0" encoding="UTF-8"?><Error><Code>InvalidArgument</Code><Message>The object annotation request query is invalid</Message><Resource>/domain-b3/obj?annotation&amp;continuation-token=fos1...</Resource></Error>
  FAILED: the model's spelling "continuation-token" is accepted
BUG REPRODUCED: 3 failed expectation(s)
```

The names printed at the top come out of the compiled model through `Model.Member_Location_Name`, which is the same call the client's request builder makes, so descriptor and pinned JSON are not in conflict: the hand-written codec is the only place the camelCase names exist. The token in the last probe is the one the server itself issued on the preceding page, so pagination is impossible in the model's spelling.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Shapes checked against the pinned botocore S3 model.

## What should happen

`Annotations.Parse_Query` must accept `max-annotation-results`, `annotation-prefix` and `continuation-token`, because that is what the pinned botocore S3 model gives those querystring members, what the generated descriptor at `src/flyology-object_storage-s3-model.adb:45596-45601` carries, and what `Client.Low_Level.Prepare_List_Object_Annotations` puts on the wire.

## Suggested treatment

The descriptor is generated from the pinned model and agrees with it, and the "Ada source style" section of `AGENTS.md` forbids hand-editing generated sources, so the hand-written codec is the side that changes. Two shapes, neither of which needs a new public declaration:

- Correct the three literals at `src/flyology-object_storage-s3-annotations.adb:137`, `:145` and `:158` to `annotation-prefix`, `max-annotation-results` and `continuation-token`. Smallest possible change.
- Compare against `Model.Member_Location_Name` for the operation's input shape, the way `src/flyology-object_storage-s3-multipart_uploads.adb:492-504` already reads enumerations out of the model. This costs a little more code and cannot drift again.

Accepting both spellings is a third option, but it makes the non-model names part of the server's contract, so it is a policy choice rather than a fix.

The regression test belongs in `tests/src/s3_server_application_corpus.adb`: change `SigV4.Pair ("maxAnnotationResults", "1")` at `:13552` and `:13588`, and `SigV4.Pair ("continuationToken", Token)` at `:13587`, to the model spellings, so the existing two-page assertion drives the names the crate's own client sends. Those three lines currently assert the wrong behaviour. The spike is the test.

## Severity

This is a self-interop failure: the crate's own client cannot use a prefix, a result limit or pagination against the crate's own server, and every such request is answered 400 `InvalidArgument`. Only the degenerate call that lists everything in one page works, so an object with more annotations than one page holds cannot be enumerated at all through the typed client. `ListObjectAnnotations` is a Flyology extension operation, so no third-party SDK is involved and the blast radius is limited to Flyology clients and to any client generated from the pinned model. The mismatch is a string comparison, so it fires on every request that carries one of the three parameters. Deterministic.
