Title: A C0 control byte in an accepted object key makes every listing without encoding-type=url answer 500
Labels: bug
Refs: WIRE-1b, WIRE-4

## Summary

`Valid_Object_Key` accepts every byte except NUL, so a key holding U+0001 is stored and stays individually addressable, but `XML.Escape` raises `XML_Error` for every byte below 32 apart from TAB, LF and CR, and it is the only text escaper the listing serializers use. Serializing a listing page that contains such a key therefore raises before the response is started, and the request handler's catch-all turns that into 500 InternalError. ListObjects v1, ListObjectsV2 and ListObjectVersions for that bucket page fail for every client that does not send `encoding-type=url`, and stay failing until the key is deleted.

## Problem

Commit `5fe6e3e`.

The key contract admits the byte. `src/flyology-object_storage.ads:667-670`:

```ada
   --  Validate an object key at the storage boundary.
   --  @param Value Candidate object key
   --  @return True for a nonempty key of at most 1,024 bytes without NUL
   function Valid_Object_Key (Value : String) return Boolean;
```

`src/flyology-object_storage.adb:479-490` implements exactly that, rejecting only `Character'Val (0)`:

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

Any well-formed `%XX` in the request target becomes the raw byte, so `%01` reaches `Valid_Object_Key` as `0x01` (`src/flyology-object_storage-s3-requests.adb:73-77`):

```ada
            Byte :=
              16 * Hex_Value
                (Character_At (Value, Positive (Input + 1))) +
              Hex_Value (Character_At (Value, Positive (Input + 2)));
            Result (Positive (Output)) := Character'Val (Byte);
```

The XML writer refuses the same byte (`src/flyology-object_storage-s3-xml.adb:228-234`):

```ada
         for Item of Value loop
            if Character'Pos (Item) < 32
              and then Item /= Character'Val (9)
              and then Item /= Character'Val (10)
              and then Item /= Character'Val (13)
            then
               raise XML_Error with "invalid XML character";
```

`Escape_Text` (`src/flyology-object_storage-s3-xml.adb:253-254`) is the only text escaper the listing serializers use (`src/flyology-object_storage-s3-listings.adb:1033-1034`):

```ada
   function Element (Name, Value : String) return String is
     ("<" & Name & ">" & XML.Escape_Text (Value) & "</" & Name & ">");
```

Nothing percent-encodes the key first unless the request asked for it (`src/flyology-object_storage-server-s3_applications.adb:10657-10661`):

```ada
                     function Encoded (Value : String) return String is
                       (if Request.URL_Encoding
                        then Encoding.URI_Encode
                          (Value, Encode_Slash => False)
                        else Value);
```

The same shape recurs at `:10793`, `:10960` and `:11200` for ListObjectVersions, ListMultipartUploads and ListParts, so those listings carry the same exposure.

The listing handler catches only `Listings.Malformed_List_Request` (`src/flyology-object_storage-server-s3_applications.adb:10763-10768`), so `XML_Error` reaches the outer handler (`:18056-18065`):

```ada
      when others =>
         if Apps.Response (X) /= Apps.Not_Started
           or else Apps.Wire_Response_Started (X)
         then
            Apps.Mark_Failed (X);
         else
            Send_Error
              (X, 500, "InternalError",
               "We encountered an internal error", Target_Text);
         end if;
```

The page is serialized before the response is started, so the 500 branch is the one taken.

Authority that such keys are valid input: the pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) documents the `EncodingType` shape as "Encoding type used by Amazon S3 to encode the object keys in the response. Responses are encoded only in UTF-8. An object key can contain any Unicode character. However, the XML 1.0 parser can't parse certain characters, such as characters with an ASCII value from 0 to 10. For characters that aren't supported in XML 1.0, you can add this parameter to request that Amazon S3 encode the keys in the response." In `ListObjectsV2Request` that member is `location: querystring`, `locationName: encoding-type`, and the shape's only required member is `Bucket`, so a listing without it is a well-formed request. What AWS S3 itself emits for such a key when the parameter is absent was not checked against a live server.

Existing tests do not reach this. `tests/src/object_storage_test_cases.adb:3721-3726` asserts that keys are opaque and that empty, NUL and oversized keys are rejected, and `:9223-9238` asserts only that `Escape_Text` must raise for NUL:

```ada
            declare
               Ignored : constant String :=
                 XML.Escape_Text ("bad" & Character'Val (0));
```

No test lists a bucket that holds a control-character key, and `tests/src/s3_http_socket_corpus.adb:3129-3134` exercises `encoding-type=url` listings with printable keys only. No test asserts the current 500, so no test has to change.

## What happens now

Spike: it creates a bucket, stores `plain.txt` and then `a%01b`, checks that GET, HEAD and DELETE of the control-byte key all work, and asserts that ListObjectsV2, ListObjects v1 and ListObjectVersions without `encoding-type=url` answer 200 with a page. It also prints, as notes, the `encoding-type=url` listing, both DeleteObjects attempts at removing the key through the request document, and the non-UTF-8 key case that {{ISSUE:WIRE-1b}} covers. Non-printable bytes are printed escaped.

```ada
   Note ("Valid_Object_Key (""a"" & SOH & ""b"") = " &
         Boolean'Image (OS.Valid_Object_Key (Control_Key_Decoded)));
...
   declare
      R : constant String := Run (Signed_Wire
        ("PUT", "/" & Bucket & "/" & Control_Key_Wire,
         "/" & Bucket & "/" & Control_Key_Decoded, Payload => "x"));
   begin
      Check (Status_Code (R) = 200,
             "PutObject of a %01 key is accepted (precondition)");
   end;
...
   declare
      R : constant String :=
        Run (Signed_Request ("GET", "/" & Bucket,
             Query => Q1 ("list-type", "2")));
   begin
      Check (Status_Code (R) = 200,
             "ListObjectsV2 without encoding-type is 200");
      Check (Contains (Body_Of (R), "<Key>"),
             "ListObjectsV2 without encoding-type returns a listing page");
   end;
```

Output, exit status 1:

```
  -- Valid_Object_Key ("a" & SOH & "b") = TRUE
  -- XML.Escape_Text of the same key raised XML_Error
  -- CreateBucket -> status 200
  ok: CreateBucket is 200
  -- PutObject plain.txt -> status 200
  ok: PutObject of an ordinary key is 200
  -- CONTROL ListObjectsV2 with only ordinary keys -> status 200
  ok: CONTROL: listing a bucket of ordinary keys is 200
  ok: CONTROL: the ordinary key appears in the page
  -- PutObject /wire-one-bucket/a%01b -> status 200
  ok: PutObject of a %01 key is accepted (precondition)
  -- CONTROL GetObject of the %01 key -> status 200
  ok: CONTROL: GetObject of the %01 key returns its body
  -- CONTROL HeadObject of the %01 key -> status 200
  ok: CONTROL: HeadObject of the %01 key is 200
  -- ListObjectsV2 (no encoding-type) -> status 500  <Code>InternalError</Code>
  --   body: <?xml version="1.0" encoding="UTF-8"?><Error><Code>InternalError</Code><Message>We encountered an internal error</Message><Resource>/wire-one-bucket?list-type=2</Resource></Error>
  FAILED: ListObjectsV2 without encoding-type is 200
  FAILED: ListObjectsV2 without encoding-type returns a listing page
  -- ListObjects v1 (no encoding-type) -> status 500  <Code>InternalError</Code>
  FAILED: ListObjects v1 without encoding-type is 200
  -- ListObjectVersions (no encoding-type) -> status 500  <Code>InternalError</Code>
  FAILED: ListObjectVersions without encoding-type is 200
  -- ListObjectsV2 with encoding-type=url -> status 200
  --   body: <?xml version="1.0" encoding="UTF-8"?><ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Name>wire-one-bucket</Name><Prefix></Prefix><KeyCount>2</KeyCount><MaxKeys>1000</MaxKeys><IsTruncated>false</IsTruncated><EncodingType>url</EncodingType><Contents><Key>a%01b</Key><LastModified>2026-09-07T05:57:21.000Z</LastModified><ETag>"9dd4e461268c8034f5c8564e155c67a6"</ETag><Size>1</Size><StorageClass>STANDARD</StorageClass></Contents><Contents><Key>plain.txt</Key><LastModified>2026-09-07T05:57:21.000Z</LastModified><ETag>"9dd4e461268c8034f5c8564e155c67a6"</ETag><Size>1</Size><StorageClass>STANDARD</StorageClass></Contents></ListBucketResult>
  -- DeleteObjects with a raw U+0001 in the request XML -> status 400  <Code>MalformedXML</Code>
  --   body: <?xml version="1.0" encoding="UTF-8"?><Error><Code>MalformedXML</Code><Message>The XML provided was not well-formed or did not validate against the published schema</Message><Resource>/wire-one-bucket?delete</Resource></Error>
  -- DeleteObjects with &#1; in the request XML -> status 400  <Code>MalformedXML</Code>
  --   body: <?xml version="1.0" encoding="UTF-8"?><Error><Code>MalformedXML</Code><Message>The XML provided was not well-formed or did not validate against the published schema</Message><Resource>/wire-one-bucket?delete</Resource></Error>
  -- PutObject /wire-one-bucket/h%FF -> status 200
  -- ListObjectsV2 encoding-type=url with the %FF key too -> status 200
  --   body valid UTF-8: TRUE
  -- CONTROL DeleteObject of the %01 key -> status 204
  ok: CONTROL: DELETE of the %01 key succeeds
  -- ListObjectsV2 (no encoding-type) with only the %FF key -> status 200
  --   body valid UTF-8: FALSE
  -- DeleteObject of the %FF key -> status 204
  -- CONTROL ListObjectsV2 after the keys are removed -> status 200
  ok: CONTROL: the listing works again once the keys are gone
BUG REPRODUCED: 4 failed expectation(s)
```

Two long response bodies from the trailing notes are omitted; every status line and assertion line is verbatim. The two `body valid UTF-8` notes belong to {{ISSUE:WIRE-1b}}.

The two DeleteObjects notes show that the bulk delete cannot clean the key up: a request document carrying the byte raw, or as `&#1;`, is rejected 400 MalformedXML by the crate's own reader, which runs XMLAda with `Test_Valid_Chars_Feature` enabled (`src/flyology-object_storage-s3-xml.adb:185`). Only `DELETE /bucket/a%01b` removes it, and until it is removed every unencoded listing of that page answers 500.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Shapes checked against the pinned botocore S3 model.

## What should happen

A listing request that omits `encoding-type` is well formed, so it must not answer 500 InternalError. Either the page is produced with the key represented in a way XML 1.0 admits, or the key is refused at the storage boundary so it can never enter a bucket, or the listing answers a defined 4xx that names the cause. The pinned botocore S3 model documents that an object key can contain any Unicode character and that `encoding-type` is an optional query parameter, so refusing the listing with an unexplained server error is not a defensible reading of the contract.

## Suggested treatment

This needs a maintainer decision, because every candidate is externally visible:

- Narrow `Valid_Object_Key` to reject C0 control bytes. This changes the documented `.ads` contract at `src/flyology-object_storage.ads:667-670` and rejects keys that AWS accepts, so already-stored keys would also need a migration answer.
- Percent-encode bytes the escaper cannot represent in the listing serializers regardless of `EncodingType`. This changes response bytes for a request that did not ask for encoding, and it makes the reported key differ from the stored key unless the response also declares `EncodingType`.
- Map the escaping failure to a defined 4xx, by catching `XML.XML_Error` around the serialization in the listing handlers next to the existing `Listings.Malformed_List_Request` handler at `src/flyology-object_storage-server-s3_applications.adb:10763-10768`, and answering with an error code that names the unrepresentable key. This is the smallest change and leaves the listing unusable, which is what AWS's own guidance about `encoding-type` implies is the client's problem.

Under the "Decision authority" and "Ada interface values" sections of `AGENTS.md` the first two options change published behaviour and belong to the maintainer, not to a fix applied in passing.

The regression test belongs in `tests/src/s3_server_application_corpus.adb`, which already drives the memory backend through the S3 application: store `a%01b`, then assert the chosen outcome for ListObjects v1, ListObjectsV2 and ListObjectVersions without `encoding-type=url`. The spike is that test. No existing test asserts the current 500, so nothing has to be rewritten.

{{ISSUE:WIRE-1b}} and {{ISSUE:WIRE-4}} are the other two consequences of the same escaper asymmetry: a non-UTF-8 key that produces a silently invalid 200 page, and a carriage return that is silently reported as a different key.

## Severity

Every unencoded listing of the affected bucket page answers 500 InternalError, deterministically, until the key is deleted, and DeleteObjects cannot delete it. The key is reachable from any client that percent-encodes a control character into the key, and the failing listing is reachable from any client that omits `encoding-type`. `aws-cli` always sends `encoding-type=url` on listings and therefore never hits this; the clients that do hit it are the ones that leave the parameter out, including the crate's own high-level client, whose `List_Objects_V2_Parameters.URL_Encoding` defaults to `False` (`src/flyology-object_storage-client-low_level.ads:106-119`) and which adds `EncodingType` only when that field is set (`src/flyology-object_storage-client-low_level.adb:1889-1891`). Deterministic; not reproduced against a live server.
