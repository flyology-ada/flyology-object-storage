Title: Multipart_Uploads.Validate compares URL-encoded cursors bytewise, so page 2 of an encoded listing is 500
Labels: bug
Refs: none

## Summary

`Multipart_Uploads.Validate` treats `Next_Key_Marker < Key_Marker` as proof that a page's cursor went backwards, but when `encoding-type=url` was requested the server has already percent-encoded both markers, and percent-encoding is not order preserving. `%` sorts below every unreserved byte, so `a9 < a:` raw becomes `a%3A < a9` encoded and the check fires on a page the backend answered correctly. `Validate` runs inside `Serialize_List_Multipart_Uploads`, and the ListMultipartUploads handler catches only `Malformed_List_Request`, so the exception escapes to the generic handler and the caller gets 500 `InternalError`. The same predicate runs in the client decoder, so a conforming non-Flyology server that encodes `NextKeyMarker` makes `Parse_List_Multipart_Uploads` raise `Invalid_Response`.

## Problem

Commit `5fe6e3e`.

The ordering predicate compares the marker strings as they stand (`src/flyology-object_storage-s3-multipart_uploads.adb:655-667`):

```ada
      elsif Value.Is_Truncated
        and then
          (US.To_String (Value.Next_Key_Marker) <
             US.To_String (Value.Key_Marker)
           or else
             (Value.Next_Key_Marker = Value.Key_Marker
              and then
                (US.Length (Value.Next_Upload_ID_Marker) = 0
                 or else Value.Next_Upload_ID_Marker =
                   Value.Upload_ID_Marker)))
      then
         raise Malformed_Upload_Listing with
           "ListMultipartUploads next cursor does not advance";
```

`Validate` runs on both sides of the wire. In the client decoder (`src/flyology-object_storage-s3-multipart_uploads.adb:788`):

```ada
      Validate (Handler.Value);
```

and in the server serializer (`src/flyology-object_storage-s3-multipart_uploads.adb:823-828`):

```ada
   function Serialize_List_Multipart_Uploads
     (Value : List_Multipart_Uploads_Result) return String
   is
      Result : US.Unbounded_String;
   begin
      Validate (Value);
```

The server fills both key markers with encoded text when the request asked for it (`src/flyology-object_storage-server-s3_applications.adb:11200-11204`):

```ada
                        function Encoded (Value : String) return String is
                          (if Request.URL_Encoding
                           then Encoding.URI_Encode
                             (Value, Encode_Slash => False)
                           else Value);
```

`Key_Marker` is built from it (`src/flyology-object_storage-server-s3_applications.adb:11218-11220`):

```ada
                                Key_Marker => US.To_Unbounded_String
                                  (Encoded
                                     (US.To_String (Request.Key_Marker))),
```

and so is `Next_Key_Marker` (`src/flyology-object_storage-server-s3_applications.adb:11240-11246`):

```ada
                           if Page.Is_Truncated then
                              Response.Next_Key_Marker :=
                                US.To_Unbounded_String
                                  (Encoded
                                     (US.To_String (Page.Next_After.Key)));
                              Response.Next_Upload_ID_Marker :=
                                Page.Next_After.Upload_ID;
```

The upload identifier markers stay raw, so only the key markers are affected.

Percent-encoding inverts the order of any pair whose first divergent byte is one the encoder escapes. The unreserved set is `A-Z a-z 0-9 - . _ ~`, plus `/` when `Encode_Slash` is `False` (`src/flyology-object_storage-s3-sigv4_encoding.adb:10-17`):

```ada
   function Unreserved (Value : Character) return Boolean is
     (Value in 'A' .. 'Z'
      or else Value in 'a' .. 'z'
      or else Value in '0' .. '9'
      or else Value = '-'
      or else Value = '.'
      or else Value = '_'
      or else Value = '~');
```

Every one of those bytes is above `%` (16#25#), and every escaped byte is written as `%` followed by two hex digits (`src/flyology-object_storage-s3-sigv4_encoding.adb:36-41`):

```ada
            else
               Result (Used + 1) := '%';
               Result (Used + 2) := Hex (Character'Pos (Item) / 16);
               Result (Used + 3) := Hex (Character'Pos (Item) mod 16);
               Used := Used + 3;
            end if;
```

so no non-ASCII key is needed. The ASCII keys `a9` and `a:` are enough: `a9 < a:` raw, `a%3A < a9` encoded. The same inversion happens for `:` `[` `=` `&` `?` `#`, a space, and any non-ASCII byte.

The handler around the serializer catches only the request-side exception (`src/flyology-object_storage-server-s3_applications.adb:11280-11286`):

```ada
                  exception
                     when Multipart_Uploads.Malformed_List_Request =>
                        Send_Error
                          (X, 400, "InvalidArgument",
                           "The ListMultipartUploads request is invalid",
                           Target_Text);
                  end;
```

so `Malformed_Upload_Listing` reaches the generic tail and the caller sees 500 `InternalError`.

The client decoder maps the same exception to `Invalid_Response` (`src/flyology-object_storage-client-low_level.adb:13422-13426`):

```ada
   exception
      when Occurrence : S3.Multipart_Uploads.Malformed_Upload_Listing =>
         raise Invalid_Response with
           "malformed ListMultipartUploads response: " &
           Ada.Exceptions.Exception_Message (Occurrence);
```

and URL encoding is a supported client parameter, echoed back through the decoder's own expectation function (`src/flyology-object_storage-client-low_level.adb:13477-13484`):

```ada
         Expected_Encoding : constant String :=
           (if Prepared.Requested_URL_Encoding then "url" else "");
         function Expected_Echo
           (Value : US.Unbounded_String) return String is
           (if Prepared.Requested_URL_Encoding
            then Encoding.URI_Encode
              (US.To_String (Value), Encode_Slash => False)
            else US.To_String (Value));
```

so the client is affected symmetrically against any conforming server, Flyology or not.

No existing test produces the combination, and nothing asserts the wrong behaviour. The socket corpus requests URL encoding only to check echo mismatches, with markers it never pages past (`tests/src/s3_http_socket_corpus.adb:12666-12673`):

```ada
            Uploads_Parameters.Delimiter := US.To_Unbounded_String ("/");
            Uploads_Parameters.URL_Encoding := True;
            Uploads_Parameters.Key_Marker := US.To_Unbounded_String ("a+b");
            Uploads_Parameters.Max_Uploads := 7;
            Uploads_Parameters.Prefix :=
              US.To_Unbounded_String ("photos/Jan &");
            Uploads_Parameters.Upload_ID_Marker :=
              US.To_Unbounded_String ("upload+/=");
```

and the codec suite only rejects an unsupported encoding type (`tests/src/object_storage_test_cases.adb:10974-10975`):

```ada
      Must_Reject_Query
        ("uploads&encoding-type=xml", "invalid upload encoding accepted");
```

`rg "does not advance" src` matches only `src/flyology-object_storage-s3-multipart_uploads.adb`, so no sibling listing codec shares the predicate.

## What happens now

Spike: the program below creates multipart uploads for the keys `a9`, `a:` and `az` in the in-process memory-backed application. It first decodes a conforming truncated URL-encoded page through the client decoder, then pages the real server with `encoding-type=url&max-uploads=1` and asserts 200 with the encoded next marker on page 2. The same paging without `encoding-type` is the control.

```ada
   --  Hand-built page that a conforming server (AWS with EncodingType=url)
   --  produces for the same fixtures; the client decoder must accept it.
   Encoded_Page : constant String :=
     "<?xml version=""1.0"" encoding=""UTF-8""?>" &
     "<ListMultipartUploadsResult " &
     "xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
     "<Bucket>domain-b4</Bucket>" &
     "<KeyMarker>a9</KeyMarker>" &
     "<UploadIdMarker>u1</UploadIdMarker>" &
     "<NextKeyMarker>a%3A</NextKeyMarker>" &
     "<NextUploadIdMarker>u2</NextUploadIdMarker>" &
     "<MaxUploads>1</MaxUploads>" &
     "<IsTruncated>true</IsTruncated>" &
     "<EncodingType>url</EncodingType>" &
     "<Upload><Key>a%3A</Key><UploadId>u2</UploadId>" &
     "<Initiated>2026-01-01T00:00:00.000Z</Initiated></Upload>" &
     "</ListMultipartUploadsResult>";
```

Output, exit status 1, with upload identifiers and repeated `<Upload>` bodies trimmed at `...`:

```
  -- === fixtures ===
  ok: CreateBucket /domain-b4 is 200
  -- CreateMultipartUpload key=[a9] status=200 uploadId=4fb6a2da...
  ok: CreateMultipartUpload for key [a9] is 200
  -- CreateMultipartUpload key=[a:] status=200 uploadId=59ac7c6c...
  ok: CreateMultipartUpload for key [a:] is 200
  -- CreateMultipartUpload key=[az] status=200 uploadId=113f3b58...
  ok: CreateMultipartUpload for key [az] is 200
  -- 
  -- === client decoder: a conforming truncated url-encoded page ===
  -- Parse_List_Multipart_Uploads raised Malformed_Upload_Listing: ListMultipartUploads next cursor does not advance
  FAILED: client decodes an encoded truncated page
  -- 
  -- === server: paging with encoding-type=url&max-uploads=1 ===
  -- page 1 status=200
  --     body=<?xml version="1.0" encoding="UTF-8"?><ListMultipartUploadsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Bucket>domain-b4</Bucket><NextKeyMarker>a9</NextKeyMarker><NextUploadIdMarker>4fb6a2da...</NextUploadIdMarker><MaxUploads>1</MaxUploads><IsTruncated>true</IsTruncated><Upload>...<Key>a9</Key>...</Upload><EncodingType>url</EncodingType></ListMultipartUploadsResult>
  ok: page 1 is 200
  ok: page 1 NextKeyMarker is a9
  -- page 2 (key-marker=a9) status=500
  --     body=<?xml version="1.0" encoding="UTF-8"?><Error><Code>InternalError</Code><Message>We encountered an internal error</Message><Resource>/domain-b4?uploads&amp;encoding-type=url&amp;max-uploads=1&amp;key-marker=a9&amp;upload-id-marker=4fb6a2da...</Resource></Error>
  FAILED: page 2 of a url-encoded listing is 200
  FAILED: page 2 reports the encoded next key marker a%3A
  -- 
  -- === control: the same paging without encoding-type ===
  -- plain page 2 status=200
  --     body=<?xml version="1.0" encoding="UTF-8"?><ListMultipartUploadsResult ...><KeyMarker>a9</KeyMarker><NextKeyMarker>a:</NextKeyMarker>...<IsTruncated>true</IsTruncated><Upload>...<Key>a:</Key>...</Upload></ListMultipartUploadsResult>
  ok: control: page 2 without encoding-type is 200
BUG REPRODUCED: 3 failed expectation(s)
```

The control is the same paging over the same three uploads with `encoding-type` dropped, and it returns 200 with `<NextKeyMarker>a:</NextKeyMarker>`, so the fixtures, the backend page and the cursor are all correct and only the encoding turns the answer into a 500.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire.

## What should happen

A truncated `encoding-type=url` page whose next key sorts after the previous marker must be serialized and decoded normally. The cursor-advance rule is a statement about key order, and key order is defined on the decoded keys, which is what both sides hold before the server applies `Encoding.URI_Encode`. Percent-encoding is a transport spelling, and it is not order preserving, so it must not be the input to an ordering comparison. AWS encodes `NextKeyMarker` the same way when `EncodingType=url` is requested, so a conforming server produces this page.

## Suggested treatment

`Validate` must compare decoded markers. The server still holds them before encoding, in `Request.Key_Marker` and `Page.Next_After.Key` at `src/flyology-object_storage-server-s3_applications.adb:11218-11246`, so validating before encoding fixes the server on its own. That is not enough, because `Validate` is shared with the client decoder, which only ever sees the encoded page.

This needs a maintainer decision, because it changes what a shared codec rule means:

- Have `Validate` decode `Key_Marker` and `Next_Key_Marker` when `Encoding_Type` is `"url"` before comparing. This is the only choice that also fixes the client, and it keeps the ordering guarantee for every page. It makes `Validate` depend on a decoder for the encoded form.
- Drop the ordering predicate for pages that carry `Encoding_Type = "url"`. Smaller, but it removes the check exactly where a wrong cursor is hardest to see.
- Validate before encoding on the server and leave the client decoder as it is. This fixes the 500 but leaves the crate unable to read a conforming AWS page.

Independently of the choice, the ListMultipartUploads handler at `src/flyology-object_storage-server-s3_applications.adb:11280-11286` should also catch `Multipart_Uploads.Malformed_Upload_Listing`, so a serializer failure cannot present as `InternalError`.

The regression tests belong in two places. The server half goes in `tests/src/s3_server_application_corpus.adb`, as multipart uploads for `a9` and `a:` paged with `encoding-type=url&max-uploads=1`, asserting 200 and `<NextKeyMarker>a%3A</NextKeyMarker>` on page 2. The client half goes in `tests/src/s3_http_socket_corpus.adb`, beside the existing URL-encoding block at `:12666-12692`, as a scripted truncated page with `<KeyMarker>a9</KeyMarker>` and `<NextKeyMarker>a%3A</NextKeyMarker>` that the decoder must accept. No existing assertion has to be inverted. The spike is the test.

## Severity

A valid, backend-answered ListMultipartUploads request ends as 500 `InternalError`, which reads as a server fault rather than as a cursor rule, and the listing cannot be paged past the first truncation. It needs `encoding-type=url` plus two keys that first differ at a byte the encoder escapes, which includes `:` and a space, so timestamps, URNs and `a:b` namespacing in key names are enough and no non-ASCII key is required. On the client side the same predicate turns a conforming page from any server, AWS included, into `Invalid_Response`. Nothing is lost or corrupted and nothing hangs: the request simply cannot be completed. Deterministic.
