Title: A Range field whose unit is not bytes is answered 400 instead of being ignored
Labels: bug
Refs: none

## Summary

`Parse_Range_Header` folds every Range shape it cannot serve into one `Malformed_Range` status, and both server call sites answer 400 InvalidRequest for all of them. That includes a field whose range unit is not `bytes`, which RFC 9110 requires an origin server to ignore, returning the representation normally. A client sending `Range: items=0-1` is refused instead of receiving the object, on GET and on HEAD alike.

## Problem

Commit `5fe6e3e`.

The parser has exactly two outcomes (`src/flyology-object_storage-s3-core.ads:159-178`):

```ada
   --  Result of parsing one range header.
   --  @enum Range_Parsed Header contains one supported byte range
   --  @enum Malformed_Range Header is malformed or unsupported
   type Range_Parse_Status is (Range_Parsed, Malformed_Range);
...
   --  Parse one RFC 9110 byte range. The bytes unit is case-insensitive and
   --  optional whitespace after '=' and at the field end is accepted.
   --  Multiple ranges are rejected because the server does not yet emit
   --  multipart/byteranges responses.
   --  @param Value Candidate Range header value
   --  @return Parsed request or Malformed_Range
   function Parse_Range_Header (Value : String) return Range_Parse_Result;
```

That documents the parser's classification only. The two sites that consume it both turn every non-`Range_Parsed` outcome into a 400. HeadObject (`src/flyology-object_storage-server-s3_applications.adb:16836-16845`):

```ada
                        Parsed_Range : constant S3.Core.Range_Parse_Result :=
                          S3.Core.Parse_Range_Header
                            (Apps.Request_Header (X, "range"));
                     begin
                        if Parsed_Range.Status /= S3.Core.Range_Parsed then
                           Send_Error
                             (X, 400, "InvalidRequest",
                              "The Range header is malformed", Target_Text);
                           return;
                        end if;
```

GetObject (`src/flyology-object_storage-server-s3_applications.adb:17223-17232`) is the same code. Nothing else in `src/` or `docs/` mentions that message.

RFC 9110 section 14.2 states that an origin server MUST ignore a Range header field that contains a range unit it does not understand. The response is then the ordinary 200 with the whole representation. Nothing in the repository documents a deliberate departure: `docs/compatibility/s3.md:736-738` describes the shape of range and part responses,

```
range framing. AWS-style range and part responses are 200 with the selected
`Content-Length` and no GET-only `Content-Range`; the decoder additionally
accepts coherent 206 responses from pinned compatible implementations.
```

and `docs/compatibility/s3.md:906-907` records only that "invalid ranges" are among the shapes the external corpus exercises. Neither states a status code for a Range field the server cannot use. What the S3 service itself answers for a non-`bytes` unit was not checked against a live server.

The existing test pins the parser classification but not the server mapping (`tests/src/object_storage_test_cases.adb:8791-8794`):

```ada
      Assert
        (Core.Parse_Range_Header ("items=0-1").Status =
           Core.Malformed_Range,
         "unknown range unit");
```

A repository-wide search for the string `The Range header is malformed` finds it only at the two server sites above, so no test asserts the 400.

## What happens now

Spike: it stores the ten-byte object `0123456789` and asserts that GET and HEAD with `Range: items=0-1` answer 200 with the whole object. Controls run first: `bytes=0-1` must be 206 with the two bytes, `bytes=100-200` must be 416, and a request with no Range must be 200 with all ten bytes. The other shapes the parser rejects are printed as notes only.

```ada
   Show ("GET", "items=0-1");
   declare
      R : constant String := Fetch ("GET", "items=0-1");
   begin
      Check (Status_Code (R) = 200,
             "GET with an unrecognized range unit is 200");
      Check (Body_Of (R) = Body_Text,
             "GET with an unrecognized range unit returns the whole object");
   end;
   Show ("HEAD", "items=0-1");
   declare
      R : constant String := Fetch ("HEAD", "items=0-1");
   begin
      Check (Status_Code (R) = 200,
             "HEAD with an unrecognized range unit is 200");
   end;
```

Output, exit status 1:

```
  -- CreateBucket 200
  -- PutObject 200
  -- GET Range: [bytes=0-1]  parser=RANGE_PARSED  status=206  Content-Range=[bytes 0-1/10]  Content-Length=[2]  body=2 bytes
  ok: CONTROL: a supported byte range is 206 with the two bytes
  -- GET Range: [bytes=100-200]  parser=RANGE_PARSED  status=416  Content-Range=[bytes */10]  Content-Length=[178]  body=178 bytes
  ok: CONTROL: a valid but unsatisfiable byte range is 416
  ok: CONTROL: a request without Range returns the whole object
  -- GET Range: [items=0-1]  parser=MALFORMED_RANGE  status=400  Content-Range=[]  Content-Length=[171]  body=171 bytes
  FAILED: GET with an unrecognized range unit is 200
  FAILED: GET with an unrecognized range unit returns the whole object
  -- HEAD Range: [items=0-1]  parser=MALFORMED_RANGE  status=400  Content-Range=[]  Content-Length=[171]  body=0 bytes
  FAILED: HEAD with an unrecognized range unit is 200
  -- GET Range: [bytes=0-1, 4-5]  parser=MALFORMED_RANGE  status=400  Content-Range=[]  Content-Length=[171]  body=171 bytes
  -- GET Range: [bytes=0-1,4-5]  parser=MALFORMED_RANGE  status=400  Content-Range=[]  Content-Length=[171]  body=171 bytes
  -- GET Range: [bytes=abc]  parser=MALFORMED_RANGE  status=400  Content-Range=[]  Content-Length=[171]  body=171 bytes
  -- GET Range: [bytes 0-1]  parser=MALFORMED_RANGE  status=400  Content-Range=[]  Content-Length=[171]  body=171 bytes
  -- GET Range: [bytes=]  parser=MALFORMED_RANGE  status=400  Content-Range=[]  Content-Length=[171]  body=171 bytes
  -- GET Range: [bytes=0-1;q=1]  parser=MALFORMED_RANGE  status=400  Content-Range=[]  Content-Length=[171]  body=171 bytes
  -- GET Range: [bytes=5-1]  parser=RANGE_PARSED  status=416  Content-Range=[bytes */10]  Content-Length=[178]  body=178 bytes
BUG REPRODUCED: 3 failed expectation(s)
```

The notes at the end show the reach of the single 400: multi-range with and without a space, `bytes=abc`, `bytes 0-1`, `bytes=` and a parameter suffix are all answered the same way. `curl -r 0-1,4-5` is the realistic stock client that produces the multi-range case. The inverted `bytes=5-1` parses and answers 416 instead, which is a different case and is not part of this report.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire.

## What should happen

A GET or HEAD carrying `Range: items=0-1` should answer 200 with the whole object, because RFC 9110 section 14.2 requires an origin server to ignore a Range header field whose range unit it does not understand. The multi-range and syntactically invalid shapes are a separate question, since the RFC leaves a server free to reject an invalid ranges-specifier.

## Suggested treatment

This needs a maintainer decision, in two parts:

- How the parser reports "ignore this field" separately from "reject this request". Adding a third value to `Range_Parse_Status` at `src/flyology-object_storage-s3-core.ads:162` changes a public enumeration in a SPARK-proved specification and makes every consumer's case coverage change, so under the "Decision authority" and "Ada interface values" sections of `AGENTS.md` the shape of that change is the maintainer's. The alternative that avoids the enumeration change is a separate boolean or predicate that the two server sites consult before they send the 400, leaving `Range_Parse_Status` alone.
- Which of the remaining malformed shapes should be ignored rather than rejected. That should be pinned against a live S3 or the pinned MinIO or RustFS images driven by `tests/scripts/test-minio.sh` and `tests/scripts/test-rustfs.sh`, not decided from the RFC alone, because the RFC permits either treatment for an invalid ranges-specifier and the S3 service's own tolerance was not checked here.

If the enumeration gains a third value, `tests/src/object_storage_test_cases.adb:8791-8794` asserts the current classification of `items=0-1` and must change with it. The parser assertion for multi-range at `:8787-8790` stays correct as long as multi-range remains rejected.

The server regression test belongs in `tests/src/s3_server_application_corpus.adb`: a GET and a HEAD carrying a non-`bytes` unit, asserting the chosen status and body, next to a control that keeps `bytes=0-1` at 206. The spike is that test.

## Severity

A GET or HEAD carrying a Range field the server cannot use is refused with 400 instead of returning the object, on HEAD as well as GET. The clean, diagnosable error limits the damage, and no S3 SDK sends a non-`bytes` unit, so the unrecognized-unit case needs a hand-written or non-SDK client. The same 400 also covers multi-range, which `curl -r 0-1,4-5` produces, but multi-range rejection is a documented parser decision rather than part of this defect. Deterministic; not reproduced against a live server.
