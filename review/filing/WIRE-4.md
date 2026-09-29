Title: A key containing a carriage return is reported as a different key by listings without encoding-type=url
Labels: bug
Refs: WIRE-1

## Summary

`XML.Escape` lets TAB, LF and CR through unescaped, and the listing serializers apply nothing else to a key, so a key stored as the three bytes `a`, `0x0D`, `b` is written into the `<Key>` element with the carriage return literal. XML 1.0 requires a parser to report a literal carriage return in character data as a line feed, so a conforming client reads the key back as `a`, `0x0A`, `b`. The server answers 200, the document is well formed, nothing reports an error, and the client is handed a key that does not exist.

## Problem

Commit `5fe6e3e`.

The escaper exempts carriage return from the C0 rejection and writes it verbatim (`src/flyology-object_storage-s3-xml.adb:228-248`):

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

No numeric character reference is produced, and `Element` applies only `Escape_Text` (`src/flyology-object_storage-s3-listings.adb:1033-1034`):

```ada
   function Element (Name, Value : String) return String is
     ("<" & Name & ">" & XML.Escape_Text (Value) & "</" & Name & ">");
```

The key is only percent-encoded when the request asked for it (`src/flyology-object_storage-server-s3_applications.adb:10657-10661`):

```ada
                     function Encoded (Value : String) return String is
                       (if Request.URL_Encoding
                        then Encoding.URI_Encode
                          (Value, Encode_Slash => False)
                        else Value);
```

The same shape recurs at `:10793`, `:10960` and `:11200`, so ListObjectVersions, ListMultipartUploads and ListParts behave the same way.

Carriage return is a valid key byte (`src/flyology-object_storage.adb:479-490` rejects only NUL), and `%0D` decodes to it (`src/flyology-object_storage-s3-requests.adb:73-77`), so the key is reachable from any client that percent-encodes a key containing a carriage return, which is what botocore does.

The XML 1.0 specification requires a parser to translate a literal carriage return in character data into a line feed before the character data is reported to the application, so the byte written cannot survive the round trip. The spike below confirms that empirically through the crate's own `S3.XML.Parse`, so the claim does not rest on the specification text alone.

Existing tests do not reach this. Nothing lists a bucket that holds a key containing a carriage return; `tests/src/s3_http_socket_corpus.adb:3129-3134` covers `encoding-type=url` listings with printable keys only, and `tests/src/object_storage_test_cases.adb:3721-3726` covers only the empty, NUL and oversized cases at the key boundary. No test asserts the current behaviour, so nothing has to change.

## What happens now

Spike: it stores `a%0Db`, confirms the object is addressable with GET, then parses the unencoded v1 listing with the crate's own `S3.XML.Parse` and asserts that the key read back equals the key that was stored. As a control it asserts that the `encoding-type=url` listing reports `a%0Db`, so the failure is isolated to the unencoded path. Non-printable bytes are printed escaped, so `a\rb` is `a`, `0x0D`, `b` and `a\nb` is `a`, `0x0A`, `b`.

```ada
   CR : constant Character := Character'Val (13);
   Key_Decoded : constant String := "a" & CR & "b";
   Key_Wire    : constant String := "a%0Db";
...
   declare
      R : constant String := Run (Signed_Request ("GET", "/" & Bucket));
      Wire_Keys : constant String := Parsed_Keys (Body_Of (R));
   begin
      Check (Status_Code (R) = 200, "the listing answers 200");
      Check (Wire_Keys = Key_Decoded,
             "the key a conforming XML parser reads back is the stored key");
   end;
```

Output, exit status 1:

```
  -- CreateBucket 200
  -- PutObject /wire-four-bucket/a%0Db -> 200
  ok: PutObject of a %0D key is accepted (precondition)
  ok: CONTROL: GetObject of the %0D key returns its body
  -- ListObjects (no encoding-type) -> 200
  --   wire bytes of the page: <?xml version="1.0" encoding="UTF-8"?><ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Name>wire-four-bucket</Name><Prefix></Prefix><Marker></Marker><MaxKeys>1000</MaxKeys><IsTruncated>false</IsTruncated><Contents><Key>a\rb</Key><LastModified>2026-09-07T05:57:56.000Z</LastModified><ETag>"9dd4e461268c8034f5c8564e155c67a6"</ETag><Size>1</Size><StorageClass>STANDARD</StorageClass><Owner><ID>repro-principal</ID></Owner></Contents></ListBucketResult>
  --   stored key:            [a\rb]
  --   key read back by S3.XML.Parse: [a\nb]
  ok: the listing answers 200
  FAILED: the key a conforming XML parser reads back is the stored key
  -- CONTROL encoding-type=url -> 200  key read back [a%0Db]
  ok: CONTROL: encoding-type=url reports the key percent-encoded
  -- DeleteObject of the %0D key -> 204
BUG REPRODUCED: 1 failed expectation(s)
```

The wire bytes carry `0x0D` inside the `<Key>` element, and the parser reports `0x0A`. A client that then issues GET, HEAD or DELETE for `a%0Ab` gets 404, because no such object exists. The same substitution applies to a `NextMarker` derived from such a key, so a paginating client can send back a marker the server never produced and skip or repeat entries.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire.

## What should happen

The key a listing reports must be the key that was stored. The characters XML end-of-line normalization alters must therefore be written as numeric character references rather than literally, so that a conforming parser hands the client back the exact bytes.

## Suggested treatment

The narrow fix is in the escaper's text path used by the listing serializers: emit `&#13;` for carriage return, and, because normalization and attribute-value normalization also touch them, `&#9;` for TAB and `&#10;` for line feed. That leaves the document well formed and round-trip exact, and it needs no change to `Valid_Object_Key` or any published contract.

This needs a maintainer decision on scope: whether the new escaping applies to every `Escape_Text` caller, which changes response bytes across all S3 XML responses the crate emits, or only to key-bearing elements in the listing serializers such as `Element` at `src/flyology-object_storage-s3-listings.adb:1033-1034`. The narrower option keeps the change confined to keys, at the cost of leaving the same round-trip hazard in every other text element.

The regression test belongs in `tests/src/s3_server_application_corpus.adb`: store `a%0Db`, request an unencoded listing, parse it with `S3.XML.Parse`, and assert the key read back equals the stored key, with the `encoding-type=url` listing as a control. The spike is that test.

{{ISSUE:WIRE-1}} is the other consequence of the same escaper decision at `src/flyology-object_storage-s3-xml.adb:228-234`, where the bytes that are refused rather than passed through turn an unencoded listing into a 500.

## Severity

The client is silently handed the wrong key. Nothing reports an error: the status is 200, the document is well formed, and the substituted key looks ordinary, so the failure only surfaces later as a 404 on a key the listing just reported, or as skipped or repeated entries when a corrupted marker is sent back. It is reachable from a stock SDK, since botocore percent-encodes a key containing a carriage return as `%0D`, and it affects ListObjects v1, ListObjectsV2 and ListObjectVersions whenever `encoding-type=url` is absent. There is no data loss: the object stays stored under its real key and stays reachable by anyone who knows it. Deterministic.
