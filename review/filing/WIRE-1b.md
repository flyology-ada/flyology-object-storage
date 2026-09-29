Title: A non-UTF-8 byte in an object key produces a 200 listing whose body is not the UTF-8 it declares
Labels: bug
Refs: WIRE-1

## Summary

`Valid_Object_Key` places no UTF-8 requirement on a key and `XML.Escape` guards only the C0 range, so a key holding a byte such as `0xFF` is copied verbatim into a listing whose XML declaration says `encoding="UTF-8"`. The server answers 200 and the response passes its own framing checks, but the document is not well formed: every conforming parser, including this crate's own `S3.XML.Parse`, rejects the whole page. The client sees a parse failure with no indication of which key caused it, and the failure repeats on every unencoded listing of that page until the key is deleted.

## Problem

Commit `5fe6e3e`.

The key contract admits the byte (`src/flyology-object_storage.adb:479-490`):

```ada
   function Valid_Object_Key (Value : String) return Boolean is
   begin
      if Value'Length not in 1 .. 1_024 then
         return False;
      end if;
      for Character_Value of Value loop
         if Character_Value = Character'Val (0) then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Object_Key;
```

The escaper guards only bytes below 32, so `0xFF` passes through unchanged (`src/flyology-object_storage-s3-xml.adb:228-248`):

```ada
         for Item of Value loop
            if Character'Pos (Item) < 32
              and then Item /= Character'Val (9)
              and then Item /= Character'Val (10)
              and then Item /= Character'Val (13)
            then
               raise XML_Error with "invalid XML character";
            elsif Item = '&' then
               Append ("&amp;");
            elsif Item = '<' then
               Append ("&lt;");
            elsif Item = '>' then
               Append ("&gt;");
            elsif Attribute and then Item = '"' then
               Append ("&quot;");
            elsif Attribute and then Item = Character'Val (39) then
               Append ("&apos;");
            else
               Append (String'(1 => Item));
            end if;
         end loop;
```

The listing serializer applies nothing else to the key (`src/flyology-object_storage-s3-listings.adb:1033-1034`):

```ada
   function Element (Name, Value : String) return String is
     ("<" & Name & ">" & XML.Escape_Text (Value) & "</" & Name & ">");
```

and the key is only percent-encoded when the request asked for it (`src/flyology-object_storage-server-s3_applications.adb:10657-10661`), which is the same asymmetry as {{ISSUE:WIRE-1}}.

The crate itself requires a reader to refuse such a document. `tests/src/object_storage_test_cases.adb:9219-9221`:

```ada
      Must_Reject
        ("<a>" & Character'Val (16#C0#) & "</a>",
         Message => "invalid UTF-8 was accepted");
```

So the server emits a document its own reader is obliged to reject.

Authority: the pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) documents in the `EncodingType` shape that "Responses are encoded only in UTF-8. An object key can contain any Unicode character." A raw `0xFF` is neither a UTF-8 sequence nor a Unicode character encoded in UTF-8. AWS S3's own handling of such a key was not checked against a live server.

Existing tests do not reach this. Nothing lists a bucket that holds a non-UTF-8 key; `tests/src/s3_http_socket_corpus.adb:3129-3134` covers `encoding-type=url` listings with printable keys only, and `tests/src/object_storage_test_cases.adb:3721-3726` covers only the empty, NUL and oversized key cases at the domain boundary. No test asserts the current 200, so no test has to change.

## What happens now

Spike: it stores `plain.txt`, checks as a control that the all-ASCII listing body is valid UTF-8 and that the crate's own `S3.XML.Parse` accepts it, then stores `h%FF` and asserts the same two properties for the listing that now contains the non-UTF-8 key. Non-printable bytes are printed escaped.

```ada
   declare
      R : constant String := Run (Signed_Wire
        ("PUT", "/" & Bucket & "/" & High_Key_Wire,
         "/" & Bucket & "/" & High_Key_Decoded, "y"));
   begin
      Check (Status_Code (R) = 200,
             "PutObject of a %FF key is accepted (precondition)");
   end;

   declare
      R : constant String := Run (Signed_Request ("GET", "/" & Bucket));
      Parsed : Boolean;
   begin
      Check (Status_Code (R) = 200, "the listing answers 200");
      Check (Valid_UTF8 (Body_Of (R)),
             "the listing body is valid UTF-8 as its declaration claims");
      Try_Parse ("listing with the %FF key", Body_Of (R), Parsed);
      Check (Parsed,
             "the crate's own S3 XML parser accepts the listing it emitted");
   end;
```

Output, exit status 1:

```
  -- CreateBucket status 200
  ok: CreateBucket is 200
  ok: PutObject of an ordinary key is 200
  -- CONTROL ListObjects status 200
  ok: CONTROL: an ordinary listing body is valid UTF-8
  -- CONTROL listing: parsed, keys [plain.txt]
  ok: CONTROL: the crate parses its own ordinary listing
  -- PutObject /wire-one-b-bucket/h%FF status 200
  ok: PutObject of a %FF key is accepted (precondition)
  -- ListObjects (no encoding-type) status 200
  --   body: <?xml version="1.0" encoding="UTF-8"?><ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Name>wire-one-b-bucket</Name><Prefix></Prefix><Marker></Marker><MaxKeys>1000</MaxKeys><IsTruncated>false</IsTruncated><Contents><Key>h\xff</Key><LastModified>2026-09-07T05:57:35.000Z</LastModified><ETag>"415290769594460e2e485922904f345d"</ETag><Size>1</Size><StorageClass>STANDARD</StorageClass><Owner><ID>repro-principal</ID></Owner></Contents><Contents><Key>plain.txt</Key><LastModified>2026-09-07T05:57:35.000Z</LastModified><ETag>"9dd4e461268c8034f5c8564e155c67a6"</ETag><Size>1</Size><StorageClass>STANDARD</StorageClass><Owner><ID>repro-principal</ID></Owner></Contents></ListBucketResult>
  ok: the listing answers 200
  FAILED: the listing body is valid UTF-8 as its declaration claims
  -- listing with the %FF key: S3.XML.Parse raised XML_Error
  FAILED: the crate's own S3 XML parser accepts the listing it emitted
  -- DeleteObject of the %FF key status 204
BUG REPRODUCED: 2 failed expectation(s)
```

`h\xff` in the printed body is the two bytes `h` and `0xFF`. The control listing above it shows the receiver is not the problem: the same parser accepts the all-ASCII page from the same server.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Shapes checked against the pinned botocore S3 model.

## What should happen

A response whose XML declaration says `encoding="UTF-8"` must be UTF-8. Either the key never enters storage, or the listing represents it in a way that keeps the document well formed, or the listing fails with a defined status that names the cause. The pinned botocore S3 model states that responses are encoded only in UTF-8 and that keys are Unicode characters, and `tests/src/object_storage_test_cases.adb:9219-9221` already requires the crate's own reader to reject a document with an invalid UTF-8 byte.

## Suggested treatment

This needs a maintainer decision, and it is the same decision as {{ISSUE:WIRE-1}}:

- Add a UTF-8 requirement to `Valid_Object_Key`. That is a change to the documented `.ads` contract at `src/flyology-object_storage.ads:667-670` and needs an answer for keys already stored, so under the "Ada interface values" section of `AGENTS.md` it is not a change to make in passing.
- Escape or percent-encode bytes the response encoding cannot carry in the listing serializers regardless of `EncodingType`, which changes response bytes for a request that did not ask for encoding.
- Answer a defined error for a page that holds an unrepresentable key, which leaves the bucket page unlistable but at least diagnosable.

Whichever is chosen, the same choice should cover the C0 case in {{ISSUE:WIRE-1}}, since both come from the single escaper at `src/flyology-object_storage-s3-xml.adb:228-248`.

The regression test belongs in `tests/src/s3_server_application_corpus.adb`: store a key containing `0xFF`, request an unencoded listing, and assert the chosen outcome, including that the emitted body parses with the crate's own `S3.XML.Parse`. The spike is that test.

## Severity

The server reports success and hands back a document that no conforming parser will accept, so the client loses the whole page rather than one entry, and gets no indication which key is at fault. The key cannot be created by botocore or any SDK that encodes keys from Unicode strings, since those cannot emit a lone `0xFF`; it takes a hand-built signed request, which makes the trigger unusual even though the consequence is worse than a server error. Deterministic; not reproduced against a live server.
